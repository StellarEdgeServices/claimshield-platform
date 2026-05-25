/**
 * OtterQuote Edge Function: create-docusign-envelope
 * Creates DocuSign envelopes for the contract signing flow.
 *
 * SIGNING ORDER (IC 24-5-11-11 compliance):
 *   1. Once a homeowner selects a contractor, the contract is distributed to both parties
 *   2. Contractor signs FIRST (after homeowner selection)
 *   3. Homeowner signs SECOND
 *
 * Supported document_type values:
 *   - "contractor_sign"          — Creates envelope with contractor as sole signer (Step A)
 *   - "homeowner_sign"           — Adds homeowner to existing envelope as next signer (Step C)
 *   - "contract" (DEPRECATED)    — Legacy flow, kept for backward compatibility
 *   - "color_confirmation"       — Color confirmation signing
 *   - "project_confirmation"     — Project confirmation signing
 *
 * IC 24-5-11 Compliance Addendum:
 *   Every contract envelope includes a programmatically generated addendum PDF as the
 *   LAST document. This addendum contains:
 *   - Verbatim Statement of Right to Cancel (IC 24-5-11-10.6)
 *   - Notice of Cancellation form (10-point boldface equivalent)
 *   - Homeowner acknowledgment that OtterQuote is not a party
 *
 * Environment variables:
 *   DOCUSIGN_INTEGRATION_KEY
 *   DOCUSIGN_USER_ID
 *   DOCUSIGN_API_ACCOUNT_ID (fallback: DOCUSIGN_ACCOUNT_ID)
 *   DOCUSIGN_RSA_PRIVATE_KEY (base64 encoded PKCS8 DER)
 *   DOCUSIGN_BASE_URI (REST API base, e.g. https://demo.docusign.net for sandbox)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.104.0";
import { getTemplateFromStorage, fetchTemplateFromUrl, getPcTemplateFromStorage, selectPcTemplateSlot, base64EncodeBinary, generateComplianceAddendumPdf, generateRetailScopeOfWorkPdf } from "./../_shared/pdf-helpers.ts";

const FUNCTION_NAME = "create-docusign-envelope";

// CORS tightened Apr 15, 2026 (Session 195): sensitive function (contract
// envelope creation + DocuSign signing URL generation) — origin allowlisted
// instead of wildcard. Matches the Session 181 pattern applied to send-sms,
// send-adjuster-email, create-payment-intent, create-setup-intent,
// admin-contractor-action, and switch-contractor.
const ALLOWED_ORIGINS = [
  "https://otterquote.com",
  "https://app.otterquote.com",
  "https://app-staging.otterquote.com",
  "https://jade-alpaca-b82b5e.netlify.app",
  "https://staging--jade-alpaca-b82b5e.netlify.app",
];

function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

// ========== TOKEN CACHE ==========
interface CachedToken {
  accessToken: string;
  accountId: string;
  baseUri: string;
  expiresAt: number;
}

let cachedToken: CachedToken | null = null;

// ========== JWT GENERATION & BASE64URL UTILITIES ==========
function base64urlEncode(data: string | Uint8Array): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const binary = String.fromCharCode(...bytes);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlDecode(str: string): Uint8Array {
  const padded = str + "=".repeat((4 - (str.length % 4)) % 4);
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  return new Uint8Array(binary.split("").map((c) => c.charCodeAt(0)));
}

async function importRsaPrivateKey(pemBase64: string): Promise<CryptoKey> {
  // The secret may be stored as:
  //   (a) a raw base64-encoded DER key (no PEM headers), or
  //   (b) a full PEM string with -----BEGIN/END PRIVATE KEY----- headers
  //       (possibly as a single line with no real newlines, or with \n newlines).
  // Strategy: use a regex to extract the base64 body between PEM delimiters.
  // If no PEM delimiters exist, treat the whole value as raw base64 DER.
  let b64 = pemBase64.trim();
  if (b64.includes("-----BEGIN")) {
    // Regex captures everything between the header and footer, regardless of
    // whether newlines are real \n or whether the whole thing is on one line.
    const match = b64.match(/-----BEGIN[^-]+-----([A-Za-z0-9+/=\s]+)-----END[^-]+-----/);
    if (match) {
      b64 = match[1];
    } else {
      // Fallback: strip any -----...------ blocks and take what's left.
      b64 = b64.replace(/-----[^-]+-----/g, "");
    }
  }
  // Strip all remaining whitespace (newlines, spaces, carriage returns).
  b64 = b64.replace(/\s+/g, "");

  const pemBinary = atob(b64);
  let pemBytes = new Uint8Array(pemBinary.split("").map((c) => c.charCodeAt(0)));

  // Detect PKCS#1 format: RSAPrivateKey starts with SEQUENCE (0x30), then after the
  // 2-4 byte length field comes INTEGER (0x02) for the version field.
  // PKCS#8 PrivateKeyInfo instead has SEQUENCE → INTEGER 0 → SEQUENCE (AlgorithmIdentifier).
  // We detect PKCS#1 by checking that byte[4] == 0x02 (the outer SEQUENCE uses a 2-byte
  // length encoding 0x82 nn nn for typical 1024-4096 bit keys, so the payload starts at byte 4).
  // PKCS#8 PrivateKeyInfo ::= SEQUENCE { version INTEGER, privateKeyAlgorithm AlgorithmIdentifier, privateKey OCTET STRING }
  const isPkcs1 = pemBytes[0] === 0x30 && pemBytes[4] === 0x02;
  if (isPkcs1) {
    // Helper: encode a DER length
    function derLen(n: number): number[] {
      if (n < 0x80) return [n];
      if (n < 0x100) return [0x81, n];
      return [0x82, (n >> 8) & 0xff, n & 0xff];
    }
    function derTLV(tag: number, valueBytes: Uint8Array): Uint8Array {
      const lenBytes = derLen(valueBytes.length);
      const out = new Uint8Array(1 + lenBytes.length + valueBytes.length);
      out[0] = tag;
      out.set(lenBytes, 1);
      out.set(valueBytes, 1 + lenBytes.length);
      return out;
    }
    function concatBytes(...arrays: Uint8Array[]): Uint8Array {
      const total = arrays.reduce((s, a) => s + a.length, 0);
      const out = new Uint8Array(total);
      let off = 0;
      for (const a of arrays) { out.set(a, off); off += a.length; }
      return out;
    }

    // version INTEGER ::= 0
    const version = new Uint8Array([0x02, 0x01, 0x00]);

    // AlgorithmIdentifier SEQUENCE { OID rsaEncryption, NULL }
    const algorithmIdentifier = new Uint8Array([
      0x30, 0x0d,
      0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
      0x05, 0x00,
    ]);

    // privateKey OCTET STRING containing the PKCS#1 DER
    const privateKeyOctet = derTLV(0x04, pemBytes);

    // Outer SEQUENCE
    const inner = concatBytes(version, algorithmIdentifier, privateKeyOctet);
    pemBytes = derTLV(0x30, inner);
  }

  return await crypto.subtle.importKey(
    "pkcs8",
    pemBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

async function createJwtAssertion(
  integrationKey: string,
  userId: string,
  baseUrl: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 3600; // 1 hour

  // Determine audience based on baseUrl (sandbox vs production)
  const aud = baseUrl.includes("demo") || baseUrl.includes("account-d")
    ? "account-d.docusign.com"
    : "account.docusign.com";

  const payload = {
    iss: integrationKey,
    sub: userId,
    aud,
    iat: now,
    exp,
    scope: "signature impersonation",
  };

  const header = { alg: "RS256", typ: "JWT" };
  const headerEncoded = base64urlEncode(JSON.stringify(header));
  const payloadEncoded = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerEncoded}.${payloadEncoded}`;

  const rsaPrivateKeyB64 = Deno.env.get("DOCUSIGN_RSA_PRIVATE_KEY");
  if (!rsaPrivateKeyB64) {
    throw new Error(
      "DOCUSIGN_RSA_PRIVATE_KEY not configured. Please set this environment variable with a base64-encoded RSA private key in PEM format."
    );
  }

  const cryptoKey = await importRsaPrivateKey(rsaPrivateKeyB64);
  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );
  const signatureEncoded = base64urlEncode(new Uint8Array(signatureBuffer));

  return `${signingInput}.${signatureEncoded}`;
}

// ========== TOKEN MANAGEMENT ==========
async function getAccessToken(baseUrl: string): Promise<CachedToken> {
  const now = Date.now();

  // Return cached token if valid (with 5-minute buffer)
  if (cachedToken && cachedToken.expiresAt > now + 300000) {
    console.log("Using cached DocuSign access token");
    return cachedToken;
  }

  console.log("Fetching new DocuSign access token via JWT grant flow");

  const integrationKey = Deno.env.get("DOCUSIGN_INTEGRATION_KEY");
  const userId = Deno.env.get("DOCUSIGN_USER_ID");

  if (!integrationKey || !userId) {
    throw new Error(
      "DocuSign JWT auth not configured. Set DOCUSIGN_INTEGRATION_KEY and DOCUSIGN_USER_ID."
    );
  }

  const jwtAssertion = await createJwtAssertion(integrationKey, userId, baseUrl);

  // Determine OAuth endpoint based on baseUrl
  const oauthHost = baseUrl.includes("demo") || baseUrl.includes("account-d")
    ? "https://account-d.docusign.com"
    : "https://account.docusign.com";

  const tokenResponse = await fetch(`${oauthHost}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwtAssertion}`,
  });

  if (!tokenResponse.ok) {
    const errorData = await tokenResponse.text();
    console.error("DocuSign token request failed:", errorData);
    throw new Error(`DocuSign token request failed: ${tokenResponse.status} ${errorData}`);
  }

  const tokenData = await tokenResponse.json();
  const accessToken = tokenData.access_token;

  if (!accessToken) {
    throw new Error("No access_token in DocuSign response");
  }

  // Fetch account info from /oauth/userinfo to get the correct account ID and base URI.
  console.log("Fetching DocuSign account info via /oauth/userinfo");
  const userInfoResponse = await fetch(`${oauthHost}/oauth/userinfo`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!userInfoResponse.ok) {
    const errText = await userInfoResponse.text();
    throw new Error(`DocuSign userinfo request failed: ${userInfoResponse.status} ${errText}`);
  }

  const userInfo = await userInfoResponse.json();
  const account = userInfo.accounts?.find((a: any) => a.is_default) || userInfo.accounts?.[0];

  if (!account?.account_id) {
    throw new Error(`Could not determine DocuSign account ID from userinfo: ${JSON.stringify(userInfo)}`);
  }

  // base_uri from userinfo is the REST API base (e.g. https://demo.docusign.net)
  const resolvedBaseUri = account.base_uri || baseUrl;
  console.log(`DocuSign account ID: ${account.account_id}, base_uri: ${resolvedBaseUri}`);

  // Cache token (valid for 1 hour, cache with 5-minute buffer)
  cachedToken = {
    accessToken,
    accountId: account.account_id,
    baseUri: resolvedBaseUri,
    expiresAt: now + 3600000 - 300000,
  };

  return cachedToken;
}


// ========== TAB BUILDERS ==========
interface TextTab {
  anchorString: string;
  anchorUnits: string;
  anchorXOffset: string;
  anchorYOffset: string;
  value: string;
  locked: string;
  font: string;
  fontSize: string;
  documentId: string;
}

interface SignHereTab {
  anchorString: string;
  anchorUnits: string;
  anchorXOffset: string;
  anchorYOffset: string;
  documentId: string;
}

interface DateSignedTab {
  anchorString: string;
  anchorUnits: string;
  anchorXOffset: string;
  anchorYOffset: string;
  documentId: string;
}

interface TextTabFields {
  [key: string]: string;
}

function buildTextTabs(
  fields: TextTabFields,
  documentId: string,
  documentType: string
): TextTab[] {
  // Mapping of field names to anchor strings found in contractor PDFs
  const fieldAnchors: { [key: string]: string } = {
    // Homeowner / property fields
    customer_name: "Name",
    customer_address: "Address:",
    customer_city_zip: "City/Zip:",
    customer_phone: "Phone",
    customer_email: "Email:",
    // Insurance fields
    insurance_company: "Insurance Co",
    claim_number: "Claim #",
    deductible: "DEDUCTIBLE:",
    // Contract / job fields
    contract_date: "Date:",
    job_description: "Description:",
    material_type: "Material:",
    contract_price: "Contract Price:",
    warranty_years: "Warranty:",
    estimated_start: "Start Date:",
    decking_per_sheet: "Decking/Sheet:",
    full_redeck_price: "Full Redeck:",
    // Contractor fields
    contractor_name: "Contractor:",
    contractor_phone: "Contractor Phone:",
    contractor_email: "Contractor Email:",
    contractor_address: "Contractor Address:",
    contractor_license: "License #:",
    // Color / project confirmation fields
    shingle_manufacturer: "Single Manufacture",
    shingle_type: "Shingle Type:",
    shingle_color: "Shingle Color:",
    drip_edge_color: "Drip Edge Color:",
    vents: "Vents",
    satellite: "Satellite",
    skylights: "Skylights",
    // Project confirmation extended fields
    num_structures: "Structures:",
    structure_names: "Structure Names:",
    valley_type: "Valley Type:",
    gutter_guards: "Gutter Guards:",
    bad_decking: "Bad Decking:",
    work_not_done: "Work Not Done:",
    non_recoverable: "Non-Recoverable Dep:",
    project_notes: "Project Notes:",
  };

  const tabs: TextTab[] = [];

  for (const [fieldName, fieldValue] of Object.entries(fields)) {
    const anchor = fieldAnchors[fieldName];
    if (!anchor) {
      // Skip unmapped fields
      continue;
    }

    tabs.push({
      anchorString: anchor,
      anchorUnits: "pixels",
      anchorXOffset: "150",
      anchorYOffset: "-5",
      value: String(fieldValue),
      locked: "true",
      font: "helvetica",
      fontSize: "size10",
      documentId,
    });
  }

  return tabs;
}

function buildSignerTabs(documentId: string, signerType: "homeowner" | "contractor") {
  const signAnchor = signerType === "homeowner" ? "Customer" : "Contractor";
  const dateAnchor = `${signAnchor}_Date`;

  return {
    signHereTabs: [
      {
        anchorString: `/${signAnchor}/`,
        anchorUnits: "pixels",
        anchorXOffset: "0",
        anchorYOffset: "0",
        documentId,
      } as SignHereTab,
    ],
    dateSignedTabs: [
      {
        anchorString: `/${dateAnchor}/`,
        anchorUnits: "pixels",
        anchorXOffset: "0",
        anchorYOffset: "0",
        documentId,
      } as DateSignedTab,
    ],
  };
}

// ========== ADDENDUM SIGNER TABS ==========
// These are positioned on the compliance addendum for the homeowner's
// acknowledgment signature and optional cancellation notice signature.
function buildAddendumTabs(documentId: string) {
  return {
    // D-123: signHere tab replaces prior checkboxTab for otterquote_acknowledgment.
    // checkboxTab with required: "true" is unreliable in DocuSign embedded signing —
    // the "Finish" button can fire before required-checkbox validation triggers.
    // signHere is the only tab type DocuSign reliably enforces before completion.
    // Approved: Dustin Stohler, 2026-05-25, task 86e1frafj.
    signHereTabs: [
      // Optional sign on the Notice of Cancellation (homeowner only)
      {
        anchorString: "I HEREBY CANCEL THIS TRANSACTION",
        anchorUnits: "pixels",
        anchorXOffset: "0",
        anchorYOffset: "20",
        tabLabel: "cancellation_acknowledgment_signature",
        optional: "true",
        documentId,
      },
      // D-123 platform disclosure acknowledgment — homeowner signs to confirm
      // OtterQuote is not a party to the homeowner-contractor agreement.
      {
        anchorString: "PLATFORM DISCLOSURE",
        anchorUnits: "pixels",
        anchorXOffset: "0",
        anchorYOffset: "180",
        tabLabel: "otterquote_acknowledgment",
        documentId,
      },
    ],
  };
}

// ========== DOCUMENT LABEL HELPERS ==========
function getDocumentLabel(documentType: string): string {
  switch (documentType) {
    case "contract":
    case "contractor_sign":
    case "homeowner_sign":
      return "Repair Contract";
    case "color_confirmation": return "Color Confirmation";
    case "project_confirmation": return "Project Confirmation";
    default: return "Document";
  }
}

// ========== AUTO-POPULATE FIELDS FROM DB ==========
async function autoPopulateFields(
  supabase: any,
  claimId: string,
  contractorId: string,
  signerName: string,
  signerEmail: string,
  documentType: string
): Promise<{ fields: TextTabFields; claimData: any; contractorData: any; bidData: any }> {
  const { data: claimData } = await supabase
    .from("claims")
    .select("*")
    .eq("id", claimId)
    .single();

  const { data: contractorData } = await supabase
    .from("contractors")
    .select("*")
    .eq("id", contractorId)
    .single();

  const { data: bidData } = await supabase
    .from("quotes")
    .select("*")
    .eq("claim_id", claimId)
    .eq("contractor_id", contractorId)
    .single();

  const fields: TextTabFields = {};

  if (claimData) {
    // Homeowner info
    fields.customer_name = signerName || "";
    fields.customer_address = claimData.property_address || claimData.address_line1 || "";
    fields.customer_city_zip = `${claimData.address_city || ""}, ${claimData.address_state || ""} ${claimData.address_zip || ""}`.trim();
    fields.customer_phone = claimData.phone || "";
    fields.customer_email = signerEmail || "";
    // Insurance info
    fields.insurance_company = claimData.insurance_carrier || "";
    fields.claim_number = claimData.claim_number || "";
    fields.deductible = claimData.deductible_amount ? `$${Number(claimData.deductible_amount).toLocaleString()}` : "";
    // Job info
    fields.contract_date = new Date().toLocaleDateString("en-US");
    fields.job_description = claimData.damage_type ? `Roof ${claimData.damage_type}` : "Roof Replacement";
    fields.material_type = claimData.material_product || bidData?.brand || "";
  }

  if (bidData) {
    fields.contract_price = bidData.amount ? `$${Number(bidData.amount).toLocaleString()}` : "";
    fields.warranty_years = bidData.warranty_years ? `${bidData.warranty_years} years` : "";
    fields.estimated_start = bidData.estimated_start_date || "";
    fields.decking_per_sheet = bidData.decking_price_per_sheet ? `$${bidData.decking_price_per_sheet}` : "";
    fields.full_redeck_price = bidData.full_redeck_price ? `$${Number(bidData.full_redeck_price).toLocaleString()}` : "";
  }

  if (contractorData) {
    fields.contractor_name = contractorData.company_name || "";
    fields.contractor_phone = contractorData.phone || "";
    fields.contractor_email = contractorData.email || "";
    fields.contractor_address = contractorData.address_line1
      ? `${contractorData.address_line1}, ${contractorData.address_city || ""}, ${contractorData.address_state || ""} ${contractorData.address_zip || ""}`
      : "";
    fields.contractor_license = "";

    // Get contractor license info
    const { data: licenseData } = await supabase
      .from("contractor_licenses")
      .select("license_number, municipality")
      .eq("contractor_id", contractorData.id)
      .limit(1);
    if (licenseData && licenseData.length > 0) {
      fields.contractor_license = `${licenseData[0].license_number} (${licenseData[0].municipality})`;
    }
  }

  // Project Confirmation: merge scope/material fields from project_confirmation JSONB
  if (documentType === "project_confirmation" && claimData?.project_confirmation) {
    const pc = claimData.project_confirmation;
    Object.assign(fields, {
      shingle_manufacturer: pc.shingleManufacturer || "",
      shingle_type: pc.shingleType || "",
      shingle_color: pc.shingleColor || "",
      drip_edge_color: pc.dripEdgeColor || "",
      skylights: pc.skylightsAction ? `${pc.skylightsAction} (${pc.skylightCount || 0})` : "",
      satellite: pc.satelliteDish || "",
      valley_type: pc.valleyType || "",
      gutter_guards: pc.gutterGuards || "",
      num_structures: pc.numStructures || "",
      structure_names: pc.structureNames || "",
      bad_decking: pc.badDeckingExpected || "",
      work_not_done: pc.workNotBeingDone || "",
      non_recoverable: pc.nonRecoverableDepreciation != null ? `$${Number(pc.nonRecoverableDepreciation).toLocaleString()}` : "",
      project_notes: pc.homeownerNotes || "",
    });
  }

  return { fields, claimData, contractorData, bidData };
}

// ========== HANDLER: CONTRACTOR SIGN (new — Step A) ==========
async function handleContractorSign(
  supabase: any,
  requestBody: any,
  tokenInfo: CachedToken,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const { claim_id, contractor_id, signer, fields: providedFields, return_url, quote_id } = requestBody;

  // Auto-populate fields if not provided
  let autoFields = providedFields || {};
  let claimData: any = null;
  let contractorData: any = null;
  let bidData: any = null;

  if (!providedFields || Object.keys(providedFields).length === 0) {
    const result = await autoPopulateFields(supabase, claim_id, contractor_id, signer.name, signer.email, "contractor_sign");
    autoFields = result.fields;
    claimData = result.claimData;
    contractorData = result.contractorData;
    bidData = result.bidData;
  } else {
    const { data: c } = await supabase.from("contractors").select("*").eq("id", contractor_id).single();
    contractorData = c;
    const { data: cl } = await supabase.from("claims").select("*").eq("id", claim_id).single();
    claimData = cl;
    // Fetch bid data for SOW generation — needed even when caller provides their own fields
    const { data: bd } = await supabase
      .from("quotes")
      .select("*")
      .eq("claim_id", claim_id)
      .eq("contractor_id", contractor_id)
      .maybeSingle();
    bidData = bd;
  }

  // Fetch contractor's contract template from storage
  // Determine trade + funding type to select the right template
  const trades = claimData?.selected_trades || [];
  const trade = trades.length ? trades[0].toLowerCase() : "roofing";
  let fundingType = "insurance";
  if (claimData?.funding_type) {
    fundingType = claimData.funding_type.toLowerCase();
  } else if (claimData?.job_type === "retail" || claimData?.job_type === "cash") {
    fundingType = "retail";
  }

  // Look up template from contractor's contract_templates JSONB
  const templates = contractorData?.contract_templates || [];
  let matchingTemplate = templates.find((t: any) =>
    t.trade && t.trade.toLowerCase() === trade &&
    t.funding_type && t.funding_type.toLowerCase() === fundingType
  );
  if (!matchingTemplate) {
    matchingTemplate = templates.find((t: any) => t.trade && t.trade.toLowerCase() === trade);
  }
  if (!matchingTemplate && contractorData?.contract_pdf_url) {
    matchingTemplate = { file_url: contractorData.contract_pdf_url };
  }

  let templateBase64: string;
  if (matchingTemplate?.file_url && matchingTemplate.file_url.includes("contractor-templates")) {
    // Extract storage path from URL and download
    const pathMatch = matchingTemplate.file_url.match(/contractor-templates\/(.+)$/);
    if (pathMatch) {
      const storagePath = decodeURIComponent(pathMatch[1]);
      const { data: blob, error } = await supabase.storage.from("contractor-templates").download(storagePath);
      if (error) throw new Error(`Template download error: ${error.message}`);
      const ab = await blob.arrayBuffer();
      templateBase64 = base64EncodeBinary(new Uint8Array(ab));
    } else {
      templateBase64 = await fetchTemplateFromUrl(matchingTemplate.file_url);
    }
  } else if (matchingTemplate?.file_url) {
    templateBase64 = await fetchTemplateFromUrl(matchingTemplate.file_url);
  } else {
    // Fallback: try standard path convention
    templateBase64 = await getTemplateFromStorage(supabase, contractor_id, "contract");
  }

  // Generate IC 24-5-11 compliance addendum
  const contractDate = new Date().toLocaleDateString("en-US");
  const contractorName = contractorData?.company_name || signer.name || "Contractor";
  const homeownerName = autoFields.customer_name || "Homeowner";
  const addendumBase64 = generateComplianceAddendumPdf(contractorName, homeownerName, contractDate);

  // For retail (non-insurance) jobs: generate a Scope of Work PDF and attach it as
  // document 2. The IC 24-5-11 compliance addendum shifts to document 3.
  // For insurance jobs the loss sheet serves as the scope reference — no SOW generated.
  const isRetail = fundingType !== "insurance";
  let scopeOfWorkBase64: string | null = null;
  if (isRetail) {
    try {
      const measurements = await fetchHoverMeasurements(supabase, claim_id);
      scopeOfWorkBase64 = generateRetailScopeOfWorkPdf({
        homeownerName,
        contractorName,
        propertyAddress: claimData?.property_address || autoFields.customer_address || "",
        claimId: claim_id,
        trades: claimData?.selected_trades || [trade],
        contractPrice: bidData?.amount ?? bidData?.total_price ?? null,
        estimatedStartDate: bidData?.estimated_start_date ?? null,
        valueAdds: bidData?.value_adds ?? null,
        bidBrand: bidData?.brand ?? null,
        deckingPricePerSheet: bidData?.decking_price_per_sheet ?? null,
        fullRedeckPrice: bidData?.full_redeck_price ?? null,
        messageToHomeowner: bidData?.message_to_homeowner ?? bidData?.contractor_message ?? null,
        homeownerNotes: claimData?.homeowner_notes ?? null,
        projectConfirmation: claimData?.project_confirmation ?? null,
        measurements,
        contractDate,
      });
      console.log(`Retail Scope of Work PDF generated for claim ${claim_id}`);
    } catch (sowErr) {
      // Non-fatal: proceed without SOW if generation fails for any reason
      console.error("Retail SOW PDF generation failed (non-fatal, continuing without SOW):", sowErr);
      scopeOfWorkBase64 = null;
    }
  }

  const { accessToken, accountId, baseUri } = tokenInfo;

  // Document IDs:
  //   Insurance:  doc 1 = contractor agreement, doc 2 = IC 24-5-11 addendum
  //   Retail:     doc 1 = contractor agreement, doc 2 = Scope of Work, doc 3 = IC 24-5-11 addendum
  const documentId = "1";
  const sowDocId    = "2"; // retail only
  const addendumDocId = isRetail && scopeOfWorkBase64 ? "3" : "2";
  const textTabs = buildTextTabs(autoFields, documentId, "contractor_sign");
  const contractorTabs = buildSignerTabs(documentId, "contractor");

  // Resolve homeowner email for placeholder recipient (from profiles table)
  let homeownerEmail = "homeowner@placeholder.otterquote.com";
  let homeownerFullName = homeownerName;
  if (claimData?.user_id) {
    const { data: profileData } = await supabase
      .from("profiles")
      .select("email, full_name")
      .eq("id", claimData.user_id)
      .single();
    if (profileData) {
      homeownerEmail = profileData.email || homeownerEmail;
      homeownerFullName = profileData.full_name || homeownerFullName;
    }
  }

  const docLabel = getDocumentLabel("contractor_sign");

  const envelopeDefinition: any = {
    emailSubject: `${docLabel} — Otter Quotes (Job #${claim_id.slice(0, 8).toUpperCase()})`,
    documents: [
      {
        documentBase64: templateBase64,
        name: docLabel,
        fileExtension: "pdf",
        documentId,
      },
      // Scope of Work — retail jobs only (doc 2). Shifts addendum to doc 3.
      ...(scopeOfWorkBase64 ? [{
        documentBase64: scopeOfWorkBase64,
        name: "Scope of Work",
        fileExtension: "pdf",
        documentId: sowDocId,
      }] : []),
      {
        documentBase64: addendumBase64,
        name: "IC 24-5-11 Compliance Addendum",
        fileExtension: "pdf",
        documentId: addendumDocId,
      },
    ],
    recipients: {
      signers: [
        {
          email: signer.email,
          name: signer.name,
          recipientId: "1",
          routingOrder: "1",
          clientUserId: "contractor_1",
          tabs: {
            textTabs,
            ...contractorTabs,
          },
        },
        // Homeowner is signer 2 — not yet active (will use createRecipient later)
        // Placeholder with routingOrder 2 so DocuSign knows the signing order
        {
          email: homeownerEmail,
          name: homeownerFullName,
          recipientId: "2",
          routingOrder: "2",
          clientUserId: "homeowner_1",
          tabs: {
            ...buildSignerTabs(documentId, "homeowner"),
            ...buildAddendumTabs(addendumDocId),
          },
        },
      ],
    },
    status: "sent", // "sent" starts the signing workflow
  };

  console.log("Creating DocuSign envelope (contractor_sign)");
  const envelopeResponse = await fetch(
    `${baseUri}/restapi/v2.1/accounts/${accountId}/envelopes`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(envelopeDefinition),
    }
  );

  if (!envelopeResponse.ok) {
    const errorData = await envelopeResponse.text();
    console.error("DocuSign envelope creation failed:", errorData);
    throw new Error(`Failed to create envelope: ${envelopeResponse.status} ${errorData}`);
  }

  const envelopeData = await envelopeResponse.json();
  const envelopeId = envelopeData.envelopeId;
  if (!envelopeId) throw new Error("No envelopeId returned from DocuSign");

  console.log(`Envelope created (contractor_sign): ${envelopeId}`);

  // Generate embedded signing URL for contractor
  const defaultReturnUrl = return_url || `https://otterquote.com/contractor-bid-form.html?claim_id=${claim_id}&signed=contractor`;
  const recipientViewResponse = await fetch(
    `${baseUri}/restapi/v2.1/accounts/${accountId}/envelopes/${envelopeId}/views/recipient`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        returnUrl: defaultReturnUrl,
        authenticationMethod: "none",
        email: signer.email,
        userName: signer.name,
        clientUserId: "contractor_1",
      }),
    }
  );

  if (!recipientViewResponse.ok) {
    const errorData = await recipientViewResponse.text();
    throw new Error(`Failed to generate contractor signing URL: ${recipientViewResponse.status} ${errorData}`);
  }

  const recipientViewData = await recipientViewResponse.json();
  const signingUrl = recipientViewData.url;
  if (!signingUrl) throw new Error("No URL returned from DocuSign recipient view endpoint");

  // Store envelope ID on the quote record
  const quoteUpdateFilter = quote_id
    ? supabase.from("quotes").update({ docusign_envelope_id: envelopeId }).eq("id", quote_id)
    : supabase.from("quotes").update({ docusign_envelope_id: envelopeId })
        .eq("claim_id", claim_id)
        .eq("contractor_id", contractor_id);

  const { error: quoteUpdateError } = await quoteUpdateFilter;
  if (quoteUpdateError) {
    console.error("Failed to update quote with envelope ID:", quoteUpdateError);
  }

  // Also update claim with the latest envelope
  await supabase.from("claims").update({
    contract_sent_at: new Date().toISOString(),
    docusign_envelope_id: envelopeId,
  }).eq("id", claim_id);

  return new Response(
    JSON.stringify({
      success: true,
      envelope_id: envelopeId,
      signing_url: signingUrl,
      status: "sent",
      document_type: "contractor_sign",
      signer_email: signer.email,
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ========== HANDLER: HOMEOWNER SIGN (new — Step C) ==========
async function handleHomeownerSign(
  supabase: any,
  requestBody: any,
  tokenInfo: CachedToken,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const { claim_id, contractor_id, signer, return_url, quote_id } = requestBody;

  // Look up existing envelope from the quote
  let envelopeId: string | null = null;

  if (quote_id) {
    const { data: quoteData } = await supabase
      .from("quotes")
      .select("docusign_envelope_id, contractor_signed_at")
      .eq("id", quote_id)
      .single();
    envelopeId = quoteData?.docusign_envelope_id;
  }

  if (!envelopeId) {
    // Fallback: look up by claim_id + contractor_id
    const { data: quoteData } = await supabase
      .from("quotes")
      .select("docusign_envelope_id, contractor_signed_at")
      .eq("claim_id", claim_id)
      .eq("contractor_id", contractor_id)
      .not("docusign_envelope_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    envelopeId = quoteData?.docusign_envelope_id;
  }

  if (!envelopeId) {
    throw new Error("No existing DocuSign envelope found for this quote. The contractor must sign first.");
  }

  const { accessToken, accountId, baseUri } = tokenInfo;

  // Generate embedded signing URL for the homeowner (recipient 2, already in the envelope)
  const defaultReturnUrl = return_url || `https://otterquote.com/contract-signing.html?claim_id=${claim_id}&signed=true`;

  console.log(`Generating homeowner signing URL for envelope ${envelopeId}`);

  const recipientViewResponse = await fetch(
    `${baseUri}/restapi/v2.1/accounts/${accountId}/envelopes/${envelopeId}/views/recipient`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        returnUrl: defaultReturnUrl,
        authenticationMethod: "none",
        email: signer.email,
        userName: signer.name,
        clientUserId: "homeowner_1",
      }),
    }
  );

  if (!recipientViewResponse.ok) {
    const errorData = await recipientViewResponse.text();
    console.error("Homeowner signing URL generation failed:", errorData);
    throw new Error(`Failed to generate homeowner signing URL: ${recipientViewResponse.status} ${errorData}`);
  }

  const recipientViewData = await recipientViewResponse.json();
  const signingUrl = recipientViewData.url;
  if (!signingUrl) throw new Error("No URL returned from DocuSign recipient view endpoint");

  console.log("Homeowner signing URL generated successfully");

  return new Response(
    JSON.stringify({
      success: true,
      envelope_id: envelopeId,
      signing_url: signingUrl,
      status: "sent",
      document_type: "homeowner_sign",
      signer_email: signer.email,
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ========== HANDLER: LEGACY CONTRACT / COLOR / PROJECT CONFIRMATION ==========
async function handleLegacyFlow(
  supabase: any,
  requestBody: any,
  tokenInfo: CachedToken,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const {
    claim_id,
    document_type,
    contractor_id,
    signer,
    fields: providedFields,
    return_url,
  } = requestBody;

  // Auto-populate fields if not provided
  let autoFields = providedFields || {};
  let claimData: any = null;
  let contractorData: any = null;

  if (!providedFields || Object.keys(providedFields).length === 0) {
    const result = await autoPopulateFields(supabase, claim_id, contractor_id, signer.name, signer.email, document_type);
    autoFields = result.fields;
    claimData = result.claimData;
    contractorData = result.contractorData;
  } else {
    if (document_type === "project_confirmation") {
      const { data: fetchedClaim } = await supabase
        .from("claims")
        .select("project_confirmation, property_address, selected_trades, funding_type, job_type")
        .eq("id", claim_id)
        .single();
      claimData = fetchedClaim;

      const { data: fetchedContractor } = await supabase
        .from("contractors")
        .select("color_confirmation_template, company_name, email")
        .eq("id", contractor_id)
        .single();
      contractorData = fetchedContractor;
    }
  }

  // Fetch template PDF
  let templateBase64: string;

  if (document_type === "project_confirmation") {
    // Ensure contractor data with JSONB PC template column is loaded
    const templateContractor = contractorData || await (async () => {
      const { data } = await supabase
        .from("contractors")
        .select("color_confirmation_template, company_name")
        .eq("id", contractor_id)
        .single();
      return data;
    })();

    // Resolve trade + funding type from claim data
    const trade: string = (
      claimData?.selected_trades?.[0] ||
      (autoFields?.trade_type as string | undefined)
    )?.toLowerCase() || "roofing";

    const rawFunding: string = (
      claimData?.funding_type ||
      claimData?.job_type ||
      (autoFields?.funding_type as string | undefined) ||
      ""
    ).toLowerCase();
    // Normalize: anything containing "insurance" → "insurance", else "retail"
    const fundingType: string = rawFunding.includes("insurance") ? "insurance" : "retail";

    // Select the best-matching PC template slot
    const slot = selectPcTemplateSlot(
      templateContractor?.color_confirmation_template,
      trade,
      fundingType
    );

    if (!slot) {
      // No PC template available — log a warning and omit the PC document.
      // The envelope still generates (non-fatal per D-161 spec).
      console.warn(
        `[D-161] No project confirmation template found for contractor ${contractor_id} ` +
        `(trade=${trade}, fundingType=${fundingType}). Omitting PC document from envelope.`
      );
      throw new Error(
        "No project confirmation template on file for this trade and funding type. " +
        "The contractor must upload a Project Confirmation Template in their profile before this document can be created."
      );
    }

    templateBase64 = await getPcTemplateFromStorage(supabase, slot.file_url);
  } else {
    templateBase64 = await getTemplateFromStorage(supabase, contractor_id, document_type);
  }

  const { accessToken, accountId, baseUri } = tokenInfo;

  // Build envelope definition
  const documentId = "1";
  const textTabs = buildTextTabs(autoFields, documentId, document_type);
  const homeownerTabs = buildSignerTabs(documentId, "homeowner");
  const contractorTabs = buildSignerTabs(documentId, "contractor");

  let contractorEmail = autoFields.contractor_email || "contractor@example.com";
  let contractorName = autoFields.contractor_name || "Contractor";

  const docLabel = getDocumentLabel(document_type);

  // For contract type, also generate the compliance addendum
  const documents: any[] = [
    {
      documentBase64: templateBase64,
      name: docLabel,
      fileExtension: "pdf",
      documentId,
    },
  ];

  if (document_type === "contract") {
    const contractDate = new Date().toLocaleDateString("en-US");
    const addendumBase64 = generateComplianceAddendumPdf(
      contractorName,
      autoFields.customer_name || signer.name || "Homeowner",
      contractDate
    );
    documents.push({
      documentBase64: addendumBase64,
      name: "IC 24-5-11 Compliance Addendum",
      fileExtension: "pdf",
      documentId: "2",
    });
  }

  const envelopeDefinition = {
    emailSubject: `${docLabel} — Otter Quotes (Job #${claim_id.slice(0, 8).toUpperCase()})`,
    documents,
    recipients: {
      signers: [
        {
          email: signer.email,
          name: signer.name,
          recipientId: "1",
          routingOrder: "1",
          clientUserId: "homeowner_1",
          tabs: {
            textTabs,
            ...homeownerTabs,
            ...(document_type === "contract" ? buildAddendumTabs("2") : {}),
          },
        },
        {
          email: contractorEmail,
          name: contractorName,
          recipientId: "2",
          routingOrder: "2",
          clientUserId: "contractor_1",
          tabs: {
            ...contractorTabs,
          },
        },
      ],
    },
    status: "sent",
  };

  console.log(`Creating DocuSign envelope (legacy: ${document_type})`);
  const envelopeResponse = await fetch(
    `${baseUri}/restapi/v2.1/accounts/${accountId}/envelopes`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(envelopeDefinition),
    }
  );

  if (!envelopeResponse.ok) {
    const errorData = await envelopeResponse.text();
    console.error("DocuSign envelope creation failed:", errorData);
    throw new Error(`Failed to create envelope: ${envelopeResponse.status} ${errorData}`);
  }

  const envelopeData = await envelopeResponse.json();
  const envelopeId = envelopeData.envelopeId;
  if (!envelopeId) throw new Error("No envelopeId returned from DocuSign");

  console.log(`Envelope created (${document_type}): ${envelopeId}`);

  // Generate embedded signing URL
  const defaultReturnUrl = document_type === "project_confirmation"
    ? `https://otterquote.com/project-confirmation.html?claim_id=${claim_id}&signed=true`
    : "https://otterquote.com/contract-signing.html?signed=true";
  const signingReturnUrl = return_url || defaultReturnUrl;

  const recipientViewResponse = await fetch(
    `${baseUri}/restapi/v2.1/accounts/${accountId}/envelopes/${envelopeId}/views/recipient`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        returnUrl: signingReturnUrl,
        authenticationMethod: "none",
        email: signer.email,
        userName: signer.name,
        clientUserId: "homeowner_1",
      }),
    }
  );

  if (!recipientViewResponse.ok) {
    const errorData = await recipientViewResponse.text();
    throw new Error(`Failed to generate signing URL: ${recipientViewResponse.status} ${errorData}`);
  }

  const recipientViewData = await recipientViewResponse.json();
  const signingUrl = recipientViewData.url;
  if (!signingUrl) throw new Error("No URL returned from DocuSign recipient view endpoint");

  // Update claim in Supabase
  const updateData: any = {
    contract_sent_at: new Date().toISOString(),
  };

  if (document_type === "contract") {
    updateData.docusign_envelope_id = envelopeId;
  } else if (document_type === "color_confirmation") {
    updateData.color_confirmation_envelope_id = envelopeId;
  } else if (document_type === "project_confirmation") {
    updateData.project_confirmation_envelope_id = envelopeId;
  }

  const { error: updateError } = await supabase
    .from("claims")
    .update(updateData)
    .eq("id", claim_id);

  if (updateError) {
    console.error("Failed to update claim:", updateError);
  }

  return new Response(
    JSON.stringify({
      success: true,
      envelope_id: envelopeId,
      signing_url: signingUrl,
      status: "sent",
      document_type,
      signer_email: signer.email,
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ========== MAIN HANDLER ==========
serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const requestBody = await req.json();
    const {
      claim_id,
      document_type,
      contractor_id,
      signer,
    } = requestBody;

    // ========== INPUT VALIDATION ==========
    if (!claim_id || !document_type || !contractor_id || !signer?.email || !signer?.name) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields",
          required: ["claim_id", "document_type", "contractor_id", "signer.email", "signer.name"],
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const validDocTypes = ["contract", "contractor_sign", "homeowner_sign", "color_confirmation", "project_confirmation"];
    if (!validDocTypes.includes(document_type)) {
      return new Response(
        JSON.stringify({
          error: `document_type must be one of: ${validDocTypes.join(", ")}`,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========== RATE LIMIT CHECK ==========
    // Skip rate limit for homeowner_sign (no new envelope created)
    if (document_type !== "homeowner_sign") {
      const { data: rateLimitResult, error: rlError } = await supabase.rpc("check_rate_limit", {
        p_function_name: FUNCTION_NAME,
        p_caller_id: claim_id || null,
      });

      if (rlError) {
        console.error("Rate limit check failed:", rlError);
        return new Response(
          JSON.stringify({
            error: "Rate limit check failed. Refusing to create envelope for safety.",
            detail: rlError.message,
          }),
          { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!rateLimitResult?.allowed) {
        console.warn(`RATE LIMITED [${FUNCTION_NAME}]: ${rateLimitResult?.reason}`);
        return new Response(
          JSON.stringify({
            error: "Rate limit exceeded",
            reason: rateLimitResult?.reason,
            counts: rateLimitResult?.counts,
          }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ========== DOCUSIGN CONFIG ==========
    const REST_API_BASE = Deno.env.get("DOCUSIGN_BASE_URI") || Deno.env.get("DOCUSIGN_BASE_URL") || "https://demo.docusign.net";

    const INTEGRATION_KEY = Deno.env.get("DOCUSIGN_INTEGRATION_KEY");
    if (!INTEGRATION_KEY) {
      throw new Error("DocuSign credentials not configured. Set DOCUSIGN_INTEGRATION_KEY.");
    }

    // ========== GET ACCESS TOKEN + ACCOUNT INFO ==========
    console.log("Acquiring DocuSign access token");
    const tokenInfo = await getAccessToken(REST_API_BASE);

    // ========== ROUTE BY DOCUMENT TYPE ==========
    switch (document_type) {
      case "contractor_sign":
        return await handleContractorSign(supabase, requestBody, tokenInfo, corsHeaders);

      case "homeowner_sign":
        return await handleHomeownerSign(supabase, requestBody, tokenInfo, corsHeaders);

      case "contract":
      case "color_confirmation":
      case "project_confirmation":
        return await handleLegacyFlow(supabase, requestBody, tokenInfo, corsHeaders);

      default:
        throw new Error(`Unhandled document type: ${document_type}`);
    }

  } catch (error) {
    console.error("create-docusign-envelope error:", error);

    const message =
      e
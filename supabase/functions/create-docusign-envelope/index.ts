/**
 * OtterQuote Edge Function: create-docusign-envelope
 * Creates a DocuSign envelope for contract signing with JWT Grant auth flow.
 * Auto-populates contractor templates with claim data using anchor-based tabs.
 * Rate-limited via Supabase check_rate_limit() RPC.
 * Supports document types: "contract", "color_confirmation", "project_confirmation"
 *
 * Environment variables:
 *   DOCUSIGN_INTEGRATION_KEY
 *   DOCUSIGN_USER_ID
 *   DOCUSIGN_API_ACCOUNT_ID (fallback: DOCUSIGN_ACCOUNT_ID)
 *   DOCUSIGN_RSA_PRIVATE_KEY (base64 encoded PKCS8 DER)
 *   DOCUSIGN_BASE_URI (REST API base, e.g. https://demo.docusign.net for sandbox)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_NAME = "create-docusign-envelope";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
  const pemBinary = atob(pemBase64);
  const pemBytes = new Uint8Array(pemBinary.split("").map((c) => c.charCodeAt(0)));
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
  // This avoids relying on a hardcoded DOCUSIGN_API_ACCOUNT_ID secret which may be wrong.
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

// ========== PDF RETRIEVAL ==========
async function getTemplateFromStorage(
  supabase: any,
  contractorId: string,
  documentType: string
): Promise<string> {
  const bucketName = "contractor-templates";
  const filePath = `${contractorId}/${documentType}.pdf`;

  try {
    const { data, error } = await supabase.storage
      .from(bucketName)
      .download(filePath);

    if (error) {
      throw new Error(`Storage error: ${error.message}`);
    }

    if (!data) {
      throw new Error("No data returned from storage");
    }

    // Convert blob to base64
    const arrayBuffer = await data.arrayBuffer();
    const base64 = base64EncodeBinary(new Uint8Array(arrayBuffer));
    return base64;
  } catch (err) {
    throw new Error(
      `Failed to retrieve template PDF (${bucketName}/${filePath}): ${err.message}`
    );
  }
}

/**
 * Fetch a PDF template from a public Supabase Storage URL.
 * Used for project_confirmation templates whose paths include timestamps
 * (e.g. {contractorId}/project_confirmation_template_{timestamp}.pdf).
 */
async function fetchTemplateFromUrl(url: string): Promise<string> {
  console.log(`Fetching template PDF from URL: ${url}`);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch template from URL (${response.status} ${response.statusText}): ${url}`
    );
  }
  const arrayBuffer = await response.arrayBuffer();
  return base64EncodeBinary(new Uint8Array(arrayBuffer));
}

function base64EncodeBinary(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
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

// ========== DOCUMENT LABEL HELPERS ==========
function getDocumentLabel(documentType: string): string {
  switch (documentType) {
    case "contract": return "Repair Contract";
    case "color_confirmation": return "Color Confirmation";
    case "project_confirmation": return "Project Confirmation";
    default: return "Document";
  }
}

// ========== MAIN HANDLER ==========
serve(async (req) => {
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
      fields,
      return_url,  // Optional: override the returnUrl after signing
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

    if (!["contract", "color_confirmation", "project_confirmation"].includes(document_type)) {
      return new Response(
        JSON.stringify({
          error: 'document_type must be "contract", "color_confirmation", or "project_confirmation"',
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========== RATE LIMIT CHECK ==========
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
    // ========== END RATE LIMIT CHECK ==========

    // ========== DOCUSIGN CONFIG ==========
    const INTEGRATION_KEY = Deno.env.get("DOCUSIGN_INTEGRATION_KEY");
    // BASE_URI from Supabase secret determines sandbox vs production OAuth routing.
    // Account ID is resolved dynamically via /oauth/userinfo — do not rely on DOCUSIGN_API_ACCOUNT_ID.
    const REST_API_BASE = Deno.env.get("DOCUSIGN_BASE_URI") || Deno.env.get("DOCUSIGN_BASE_URL") || "https://demo.docusign.net";

    if (!INTEGRATION_KEY) {
      throw new Error(
        "DocuSign credentials not configured. Set DOCUSIGN_INTEGRATION_KEY."
      );
    }

    // ========== LOAD CLAIM + CONTRACTOR DATA ==========
    // If fields not provided, auto-populate from claim and contractor records
    let autoFields = fields || {};
    let claimData: any = null;
    let contractorData: any = null;

    if (!fields || Object.keys(fields).length === 0) {
      const { data: fetchedClaim } = await supabase
        .from("claims")
        .select("*")
        .eq("id", claim_id)
        .single();

      const { data: fetchedContractor } = await supabase
        .from("contractors")
        .select("*")
        .eq("id", contractor_id)
        .single();

      const { data: bidData } = await supabase
        .from("quotes")
        .select("*")
        .eq("claim_id", claim_id)
        .eq("contractor_id", contractor_id)
        .single();

      claimData = fetchedClaim;
      contractorData = fetchedContractor;

      if (claimData && signer) {
        autoFields = {
          // Homeowner info
          customer_name: signer.name,
          customer_address: claimData.property_address || claimData.address_line1 || "",
          customer_city_zip: `${claimData.address_city || ""}, ${claimData.address_state || ""} ${claimData.address_zip || ""}`.trim(),
          customer_phone: claimData.phone || "",
          customer_email: signer.email,
          // Insurance info
          insurance_company: claimData.insurance_carrier || "",
          claim_number: claimData.claim_number || "",
          deductible: claimData.deductible_amount ? `$${Number(claimData.deductible_amount).toLocaleString()}` : "",
          // Job info
          contract_date: new Date().toLocaleDateString("en-US"),
          job_description: claimData.damage_type ? `Roof ${claimData.damage_type}` : "Roof Replacement",
          material_type: claimData.material_product || bidData?.brand || "",
          // Bid info
          contract_price: bidData?.amount ? `$${Number(bidData.amount).toLocaleString()}` : "",
          warranty_years: bidData?.warranty_years ? `${bidData.warranty_years} years` : "",
          estimated_start: bidData?.estimated_start_date || "",
          decking_per_sheet: bidData?.decking_price_per_sheet ? `$${bidData.decking_price_per_sheet}` : "",
          full_redeck_price: bidData?.full_redeck_price ? `$${Number(bidData.full_redeck_price).toLocaleString()}` : "",
          // Contractor info
          contractor_name: contractorData?.company_name || "",
          contractor_phone: contractorData?.phone || "",
          contractor_email: contractorData?.email || "",
          contractor_address: contractorData?.address_line1 ? `${contractorData.address_line1}, ${contractorData.address_city || ""}, ${contractorData.address_state || ""} ${contractorData.address_zip || ""}` : "",
          contractor_license: "",
        };

        // Get contractor license info
        if (contractorData) {
          const { data: licenseData } = await supabase
            .from("contractor_licenses")
            .select("license_number, municipality")
            .eq("contractor_id", contractorData.id)
            .limit(1);
          if (licenseData && licenseData.length > 0) {
            autoFields.contractor_license = `${licenseData[0].license_number} (${licenseData[0].municipality})`;
          }
        }
      }

      // ── Project Confirmation: merge scope/material fields from project_confirmation JSONB ──
      if (document_type === "project_confirmation" && claimData?.project_confirmation) {
        const pc = claimData.project_confirmation;
        Object.assign(autoFields, {
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
    } else {
      // fields were provided by caller — we still may need claim/contractor data
      // for project_confirmation template retrieval (handled below)
      if (document_type === "project_confirmation") {
        const { data: fetchedClaim } = await supabase
          .from("claims")
          .select("project_confirmation, property_address")
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

    // ========== FETCH TEMPLATE PDF ==========
    let templateBase64: string;

    if (document_type === "project_confirmation") {
      // project_confirmation uses the contractor's color_confirmation_template URL
      // (uploaded via contractor-profile.html, stored in contractors.color_confirmation_template)
      const templateContractor = contractorData || await (async () => {
        const { data } = await supabase
          .from("contractors")
          .select("color_confirmation_template, company_name")
          .eq("id", contractor_id)
          .single();
        return data;
      })();

      const templateUrl = templateContractor?.color_confirmation_template;
      if (!templateUrl) {
        throw new Error(
          "No project confirmation template on file. The contractor must upload a Project Confirmation Template in their profile before this document can be created."
        );
      }
      console.log(`Fetching project confirmation template for contractor ${contractor_id}`);
      templateBase64 = await fetchTemplateFromUrl(templateUrl);
    } else {
      console.log(`Fetching template: ${contractor_id}/${document_type}.pdf`);
      templateBase64 = await getTemplateFromStorage(supabase, contractor_id, document_type);
    }

    // ========== GET ACCESS TOKEN + ACCOUNT INFO ==========
    console.log("Acquiring DocuSign access token");
    const tokenInfo = await getAccessToken(REST_API_BASE);
    const accessToken = tokenInfo.accessToken;
    const ACCOUNT_ID = tokenInfo.accountId;
    const RESOLVED_BASE_URI = tokenInfo.baseUri;

    // ========== BUILD ENVELOPE DEFINITION ==========
    const documentId = "1";
    const textTabs = buildTextTabs(autoFields, documentId, document_type);

    // Homeowner (recipient 1)
    const homeownerTabs = buildSignerTabs(documentId, "homeowner");

    // Contractor (recipient 2)
    const contractorTabs = buildSignerTabs(documentId, "contractor");

    // Look up contractor info for recipient 2
    let contractorEmail = "contractor@example.com";
    let contractorName = "Contractor";
    if (autoFields.contractor_email) {
      contractorEmail = autoFields.contractor_email;
    }
    if (autoFields.contractor_name) {
      contractorName = autoFields.contractor_name;
    }

    const docLabel = getDocumentLabel(document_type);

    const envelopeDefinition = {
      emailSubject: `${docLabel} — OtterQuote (Claim ${claim_id.slice(0, 8)})`,
      documents: [
        {
          documentBase64: templateBase64,
          name: docLabel,
          fileExtension: "pdf",
          documentId,
        },
      ],
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

    // ========== CREATE ENVELOPE ==========
    console.log("Creating DocuSign envelope");
    const envelopeResponse = await fetch(
      `${RESOLVED_BASE_URI}/restapi/v2.1/accounts/${ACCOUNT_ID}/envelopes`,
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
      throw new Error(
        `Failed to create envelope: ${envelopeResponse.status} ${errorData}`
      );
    }

    const envelopeData = await envelopeResponse.json();
    const envelopeId = envelopeData.envelopeId;

    if (!envelopeId) {
      throw new Error("No envelopeId returned from DocuSign");
    }

    console.log(`Envelope created: ${envelopeId}`);

    // ========== GENERATE EMBEDDED SIGNING URL ==========
    console.log("Generating embedded signing URL for homeowner");

    // Default returnUrl by document type; caller can override with return_url param
    const defaultReturnUrl = document_type === "project_confirmation"
      ? `https://otterquote.com/project-confirmation.html?claim_id=${claim_id}&signed=true`
      : "https://otterquote.com/contract-signing.html?signed=true";
    const signingReturnUrl = return_url || defaultReturnUrl;

    const recipientViewResponse = await fetch(
      `${RESOLVED_BASE_URI}/restapi/v2.1/accounts/${ACCOUNT_ID}/envelopes/${envelopeId}/views/recipient`,
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
      console.error("Embedded signing URL generation failed:", errorData);
      throw new Error(
        `Failed to generate signing URL: ${recipientViewResponse.status} ${errorData}`
      );
    }

    const recipientViewData = await recipientViewResponse.json();
    const signingUrl = recipientViewData.url;

    if (!signingUrl) {
      throw new Error("No URL returned from DocuSign recipient view endpoint");
    }

    console.log("Signing URL generated successfully");

    // ========== UPDATE CLAIM IN SUPABASE ==========
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
      // Non-fatal: log but don't fail the request — envelope was created successfully
      console.error("Failed to update claim:", updateError);
    }

    // ========== SUCCESS RESPONSE ==========
    return new Response(
      JSON.stringify({
        success: true,
        envelope_id: envelopeId,
        signing_url: signingUrl,
        status: "sent",
        document_type,
        signer_email: signer.email,
        rate_limit_counts: rateLimitResult?.counts,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("create-docusign-envelope error:", error);

    const message =
      error instanceof Error
        ? error.message
        : "An unexpected error occurred";

    return new Response(
      JSON.stringify({
        error: message,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

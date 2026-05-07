/**
 * OtterQuote Edge Function: create-hubspot-contact
 *
 * Creates or updates a HubSpot contact for homeowners (D-189) or contractors (D-210/D-218).
 *
 * Homeowner mode (default):
 *   Called fire-and-forget from get-started.html page 1.
 *   Auth: no JWT required — called pre-auth
 *
 * Contractor mode (D-210 / D-218):
 *   Called from contractor-pre-approval.html after page 2 submission.
 *   Updates existing contractor contact with wc_path, license_path, license_count, license_summary.
 *   license_path, license_count, license_summary are computed server-side from contractor_licenses rows.
 *   Auth: requires JWT (contractor is signed in)
 *
 * Environment variables:
 *   HUBSPOT_PRIVATE_APP_TOKEN  — pat-na2-... private app token (scopes: contacts r/w)
 *   SUPABASE_URL               — auto-provided by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY  — auto-provided by Supabase
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const HUBSPOT_API = "https://api.hubapi.com";

const ALLOWED_ORIGINS = [
  "https://otterquote.com",
  "https://app.otterquote.com",
  "https://app-staging.otterquote.com",
  "https://jade-alpaca-b82b5e.netlify.app",
  "https://staging--jade-alpaca-b82b5e.netlify.app",
];

function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function jsonResponse(
  body: unknown,
  status: number,
  cors: Record<string, string>
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Supabase REST helpers (service-role, no RLS bypass needed — EF has full access)
// ---------------------------------------------------------------------------

interface ContractorRow {
  id: string;
  no_license_required: boolean | null;
}

interface LicenseRow {
  municipality: string;
  jurisdiction_level: string;
}

async function fetchContractorByEmail(
  supabaseUrl: string,
  serviceKey: string,
  email: string
): Promise<ContractorRow | null> {
  const url = `${supabaseUrl}/rest/v1/contractors?email=eq.${encodeURIComponent(email)}&select=id,no_license_required&limit=1`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
    },
  });
  if (!res.ok) {
    const t = await res.text().catch(() => "?");
    console.error(`create-hubspot-contact: contractors lookup failed ${res.status}: ${t}`);
    return null;
  }
  const rows: ContractorRow[] = await res.json();
  return rows.length > 0 ? rows[0] : null;
}

async function fetchLicenses(
  supabaseUrl: string,
  serviceKey: string,
  contractorId: string
): Promise<LicenseRow[]> {
  const url = `${supabaseUrl}/rest/v1/contractor_licenses?contractor_id=eq.${encodeURIComponent(contractorId)}&select=municipality,jurisdiction_level&order=created_at.asc`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
    },
  });
  if (!res.ok) {
    const t = await res.text().catch(() => "?");
    console.error(`create-hubspot-contact: contractor_licenses lookup failed ${res.status}: ${t}`);
    return [];
  }
  return res.json();
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  const cors = buildCorsHeaders(req);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405, cors);
  }

  // Parse body
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid json" }, 400, cors);
  }

  // Health check shortcut (used by platform-health-check pinger)
  if (body.health_check === true) {
    return jsonResponse({ status: "ok" }, 200, cors);
  }

  const token = Deno.env.get("HUBSPOT_PRIVATE_APP_TOKEN");
  if (!token) {
    console.error("create-hubspot-contact: HUBSPOT_PRIVATE_APP_TOKEN not set");
    return jsonResponse({ success: false, reason: "token_not_configured" }, 200, cors);
  }

  const authHeaders = {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
  };

  // -------------------------------------------------------------------------
  // Contractor mode (D-210 / D-218): update existing contact with insurance +
  // license data. license_path, license_count, license_summary are computed
  // server-side from contractor_licenses rows.
  // -------------------------------------------------------------------------
  if (body.mode === "contractor") {
    const email = body.email as string | undefined;
    const wc_path = body.wc_path as string | undefined;

    if (!email) {
      return jsonResponse({ error: "email required for contractor mode" }, 400, cors);
    }

    if (!wc_path) {
      return jsonResponse({ error: "wc_path required for contractor mode" }, 400, cors);
    }

    // --- Fetch license data from Supabase ---
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    let licenseCount = 0;
    let licenseSummary = "";
    let licensePathComputed = "not_provided";

    if (supabaseUrl && serviceKey) {
      try {
        const contractor = await fetchContractorByEmail(supabaseUrl, serviceKey, email);
        if (contractor) {
          const licenses = await fetchLicenses(supabaseUrl, serviceKey, contractor.id);
          licenseCount = licenses.length;
          licenseSummary = licenses.map((l) => l.municipality).filter(Boolean).join(", ");
          // has_license if any contractor_licenses rows exist; not_provided otherwise
          licensePathComputed = licenseCount > 0 ? "has_license" : "not_provided";
          console.log(
            `create-hubspot-contact (contractor): ${email} → license_count=${licenseCount}, license_path=${licensePathComputed}`
          );
        } else {
          console.warn(`create-hubspot-contact (contractor): no contractor row found for ${email} — using not_provided`);
        }
      } catch (err) {
        // Non-fatal: proceed with defaults (license_count=0, not_provided)
        console.error("create-hubspot-contact (contractor): supabase license lookup exception", err);
      }
    } else {
      console.warn("create-hubspot-contact (contractor): SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — skipping license lookup");
    }

    // --- Find HubSpot contact ---
    try {
      const searchRes = await fetch(`${HUBSPOT_API}/crm/v3/objects/contacts/search`, {
        method: "POST",
        headers: authHeaders,
        body: JSON.stringify({
          filterGroups: [{
            filters: [{ propertyName: "email", operator: "EQ", value: email }],
          }],
          properties: ["email"],
          limit: 1,
        }),
      });

      if (!searchRes.ok) {
        const errText = await searchRes.text().catch(() => "(unreadable)");
        console.error(`create-hubspot-contact (contractor): search failed ${searchRes.status}:`, errText);
        return jsonResponse({ success: false, status: searchRes.status, mode: "contractor" }, 200, cors);
      }

      const searchData = await searchRes.json();
      if (!searchData.results || searchData.results.length === 0) {
        console.warn(`create-hubspot-contact (contractor): contact not found for ${email}`);
        return jsonResponse({ success: false, reason: "contact_not_found", mode: "contractor" }, 200, cors);
      }

      const contactId = searchData.results[0].id;

      // --- Update HubSpot contact ---
      const updateRes = await fetch(
        `${HUBSPOT_API}/crm/v3/objects/contacts/${contactId}`,
        {
          method: "PATCH",
          headers: authHeaders,
          body: JSON.stringify({
            properties: {
              wc_path,
              license_path: licensePathComputed,
              license_count: String(licenseCount),
              license_summary: licenseSummary,
            },
          }),
        }
      );

      if (updateRes.ok) {
        console.log(
          `create-hubspot-contact (contractor): updated contact ${contactId} for ${email} — wc_path=${wc_path}, license_path=${licensePathComputed}, license_count=${licenseCount}`
        );
        return jsonResponse({
          success: true,
          id: contactId,
          action: "updated",
          mode: "contractor",
          license_count: licenseCount,
          license_path: licensePathComputed,
        }, 200, cors);
      } else {
        const errText = await updateRes.text().catch(() => "(unreadable)");
        console.error(`create-hubspot-contact (contractor): update failed ${updateRes.status}:`, errText);
        return jsonResponse({ success: false, status: updateRes.status, mode: "contractor" }, 200, cors);
      }
    } catch (err) {
      console.error("create-hubspot-contact (contractor): exception", err);
      return jsonResponse({ success: false, error: String(err), mode: "contractor" }, 200, cors);
    }
  }

  // -------------------------------------------------------------------------
  // Homeowner mode (D-189): original logic
  // -------------------------------------------------------------------------
  const { email, firstname, lastname, phone, address } = body as Record<string, string>;

  if (!email) {
    return jsonResponse({ error: "email required" }, 400, cors);
  }

  const properties: Record<string, string> = { email };
  if (firstname) properties.firstname = firstname;
  if (lastname)  properties.lastname  = lastname;
  if (phone)     properties.phone     = phone;
  if (address)   properties.address   = address;
  // Source tracking
  properties.hs_lead_status        = "NEW";
  properties.lead_source_detail    = "OtterQuote Get Started Form";

  // Step 1: Attempt to create contact
  const createRes = await fetch(`${HUBSPOT_API}/crm/v3/objects/contacts`, {
    method: "POST",
    headers: authHeaders,
    body: JSON.stringify({ properties }),
  });

  if (createRes.ok) {
    const data = await createRes.json();
    console.log(`create-hubspot-contact: created contact ${data.id} for ${email}`);
    return jsonResponse({ success: true, id: data.id, action: "created" }, 200, cors);
  }

  // Step 2: Handle 409 CONTACT_EXISTS — find and update
  if (createRes.status === 409) {
    try {
      const searchRes = await fetch(`${HUBSPOT_API}/crm/v3/objects/contacts/search`, {
        method: "POST",
        headers: authHeaders,
        body: JSON.stringify({
          filterGroups: [{
            filters: [{ propertyName: "email", operator: "EQ", value: email }],
          }],
          properties: ["email"],
          limit: 1,
        }),
      });

      if (searchRes.ok) {
        const searchData = await searchRes.json();
        if (searchData.results?.length > 0) {
          const contactId = searchData.results[0].id;
          const updateRes = await fetch(
            `${HUBSPOT_API}/crm/v3/objects/contacts/${contactId}`,
            {
              method: "PATCH",
              headers: authHeaders,
              body: JSON.stringify({ properties }),
            }
          );
          if (updateRes.ok) {
            console.log(`create-hubspot-contact: updated existing contact ${contactId} for ${email}`);
            return jsonResponse({ success: true, id: contactId, action: "updated" }, 200, cors);
          }
        }
      }
    } catch (err) {
      console.error("create-hubspot-contact: update-on-conflict failed", err);
    }
    // Duplicate suppressed — not an error
    return jsonResponse({ success: true, action: "duplicate_suppressed" }, 200, cors);
  }

  // Step 3: Other HubSpot API errors — log but return 200 (non-fatal to caller)
  const errText = await createRes.text().catch(() => "(unreadable)");
  console.error(`create-hubspot-contact: HubSpot API error ${createRes.status}:`, errText);
  return jsonResponse({ success: false, status: createRes.status }, 200, cors);
});

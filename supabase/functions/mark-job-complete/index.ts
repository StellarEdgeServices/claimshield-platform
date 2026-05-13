/**
 * OtterQuote Edge Function: mark-job-complete
 *
 * LAUNCH-BLOCKER — ClickUp 86e0yvj7b
 * W2-P1 — May 1, 2026
 *
 * Allows a contractor to mark one of their won jobs as complete.
 * Sets claims.completion_date, writes an activity_log entry, and
 * sends a homeowner notification email via Mailgun (D-228).
 *
 * Authorization:
 *   - Caller must have a valid Supabase JWT (contractor)
 *   - Contractor must own a quote on the claim with status 'selected' or 'awarded'
 *
 * Idempotent:
 *   - If completion_date is already set, returns the existing timestamp
 *     with already_complete: true — no second write, no duplicate activity log row
 *
 * Input:  POST { claim_id: string }
 * Output: { completion_date: string, already_complete: boolean }
 *
 * Error codes:
 *   400 — missing or invalid claim_id
 *   401 — missing or invalid JWT
 *   403 — contractor has no 'selected'/'awarded' quote on this claim
 *   404 — claim not found
 *   409 — claim is not in a completable state (not contract_signed or awarded)
 *   500 — internal error
 *
 * Downstream listeners (NOT wired in this build — placeholder only):
 *   job_completed → process-hover-rebate, warranty-upload prompt, Lodge home-profile
 *
 * Environment variables:
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, MAILGUN_API_KEY
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_NAME = "mark-job-complete";

// States in which a contractor is allowed to mark a job complete.
// Other states (bidding, draft, submitted) mean no contractor has been
// selected yet — completing makes no sense.
const COMPLETABLE_STATES = ["contract_signed", "awarded"];

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
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

function jsonResponse(
  data: unknown,
  status: number,
  corsHeaders: Record<string, string>
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// =============================================================================
// HOMEOWNER NOTIFICATION (D-228)
// Non-fatal — failure is logged but does not roll back completion_date.
// =============================================================================

async function sendHomeownerNotification(
  supabase: ReturnType<typeof createClient>,
  claimId: string,
  homeownerId: string,
  address: string,
  contractorName: string,
  completionDate: string,
  mailgunApiKey: string | undefined
): Promise<void> {
  if (!mailgunApiKey) {
    console.warn(`[${FUNCTION_NAME}] MAILGUN_API_KEY not set — skipping homeowner notification for claim ${claimId}`);
    return;
  }

  // ── Look up homeowner email: profiles first, fall back to auth.admin ──────
  let homeownerEmail: string | null = null;
  let homeownerName = "Homeowner";

  const { data: profile } = await supabase
    .from("profiles")
    .select("email, full_name")
    .eq("id", homeownerId)
    .maybeSingle();

  if (profile?.email) {
    homeownerEmail = profile.email;
    homeownerName = profile.full_name || "Homeowner";
  } else {
    const { data: authUser } = await supabase.auth.admin.getUserById(homeownerId);
    homeownerEmail = authUser?.user?.email || null;
    homeownerName = authUser?.user?.user_metadata?.full_name || "Homeowner";
  }

  if (!homeownerEmail) {
    console.warn(`[${FUNCTION_NAME}] Could not resolve homeowner email for user ${homeownerId} on claim ${claimId} — skipping notification`);
    return;
  }

  const formattedDate = new Date(completionDate).toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  const subject = `Your contractor has marked your job complete — ${address}`;

  const textBody = [
    `Hi ${homeownerName},`,
    "",
    `${contractorName} has marked the job at ${address} as complete as of ${formattedDate}.`,
    "",
    "If the work is finished to your satisfaction, no action is needed. If you have any concerns or believe the job is not yet complete, please log in to your Otter Quotes account and reach out through your project dashboard.",
    "",
    "Log in to review: https://app.otterquote.com",
    "",
    "Thank you for using Otter Quotes.",
    "— The Otter Quotes Team",
  ].join("\n");

  const htmlBody = `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:2rem;color:#1F2937;">
  <div style="text-align:center;margin-bottom:2rem;">
    <img src="https://otterquote.com/images/otter-logo.png" alt="Otter Quotes" style="height:48px;" onerror="this.style.display='none'">
  </div>
  <h2 style="color:#0D1B2E;margin-bottom:1rem;">Job Marked Complete</h2>
  <p>Hi ${homeownerName},</p>
  <p><strong>${contractorName}</strong> has marked the job at <strong>${address}</strong> as complete as of <strong>${formattedDate}</strong>.</p>
  <p>If the work is finished to your satisfaction, no action is needed. If you have any concerns or believe the job is not yet complete, please log in to your Otter Quotes account and reach out through your project dashboard.</p>
  <div style="text-align:center;margin:2rem 0;">
    <a href="https://app.otterquote.com" style="background:#E07B00;color:#fff;padding:0.75rem 1.5rem;border-radius:0.5rem;text-decoration:none;font-weight:600;">Review Your Project</a>
  </div>
  <p style="color:#6B7280;font-size:0.875rem;">Thank you for using Otter Quotes.</p>
  <hr style="border:none;border-top:1px solid #E2E8F0;margin:1.5rem 0;">
  <p style="color:#9CA3AF;font-size:0.75rem;text-align:center;">Otter Quotes · Indianapolis, IN · <a href="https://otterquote.com" style="color:#9CA3AF;">otterquote.com</a></p>
</body>
</html>`;

  const mailgunFormData = new FormData();
  mailgunFormData.append("from", "Otter Quotes <noreply@mail.otterquote.com>");
  mailgunFormData.append("to", homeownerEmail);
  mailgunFormData.append("subject", subject);
  mailgunFormData.append("text", textBody);
  mailgunFormData.append("html", htmlBody);

  try {
    const mailgunResponse = await fetch(
      "https://api.mailgun.net/v3/mail.otterquote.com/messages",
      {
        method: "POST",
        headers: { Authorization: `Basic ${btoa(`api:${mailgunApiKey}`)}` },
        body: mailgunFormData,
      }
    );

    if (mailgunResponse.ok) {
      console.log(`[${FUNCTION_NAME}] Homeowner notification sent to ${homeownerEmail} for claim ${claimId}`);
    } else {
      const errText = await mailgunResponse.text().catch(() => "(unreadable)");
      console.error(`[${FUNCTION_NAME}] Mailgun returned ${mailgunResponse.status} for claim ${claimId}: ${errText}`);
    }
  } catch (mailgunErr) {
    console.error(`[${FUNCTION_NAME}] Mailgun fetch threw (non-fatal) for claim ${claimId}:`, mailgunErr);
  }
}

// =============================================================================
// MAIN HANDLER
// =============================================================================

serve(async (req: Request) => {
  const corsHeaders = buildCorsHeaders(req);

  // ── CORS preflight ──────────────────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405, corsHeaders);
  }

  const supabaseUrl    = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnon   = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const mailgunApiKey  = Deno.env.get("MAILGUN_API_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error(`[${FUNCTION_NAME}] Missing required environment variables`);
    return jsonResponse({ ok: false, error: "Server configuration error" }, 500, corsHeaders);
  }

  // ── Authenticate caller ────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ ok: false, error: "Missing authorization token" }, 401, corsHeaders);
  }

  // User-scoped client — used only to verify the JWT
  const userClient = createClient(supabaseUrl, supabaseAnon || serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ ok: false, error: "Invalid or expired token" }, 401, corsHeaders);
  }

  const authUserId = userData.user.id;

  // Service role client for all DB writes
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    // ── Rate limiting ──────────────────────────────────────────────────────────
    const { data: rlOk, error: rlError } = await supabase.rpc("check_rate_limit", {
      p_function_name: FUNCTION_NAME,
      p_user_id: authUserId,
    });
    if (rlError) {
      console.warn(`[${FUNCTION_NAME}] Rate limit RPC error (non-fatal):`, rlError.message);
    } else if (!rlOk) {
      return jsonResponse({ ok: false, error: "Rate limit exceeded — please try again shortly" }, 429, corsHeaders);
    }

    // ── Parse body ─────────────────────────────────────────────────────────────
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch (_) {
      return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400, corsHeaders);
    }

    const claimId = (body.claim_id as string || "").trim();
    if (!claimId) {
      return jsonResponse({ ok: false, error: "claim_id is required" }, 400, corsHeaders);
    }

    // ── Resolve contractor record ──────────────────────────────────────────────
    const { data: contractor, error: contractorError } = await supabase
      .from("cont
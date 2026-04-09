// ============================================================
// Supabase Edge Function: notify-feature-request
//
// Triggered by a Database Webhook on INSERT to feature_requests.
// Sends an email to Dustin via Resend whenever a contractor
// submits a feature request.
//
// Required secret (set via Supabase Dashboard or CLI):
//   RESEND_API_KEY = your Resend API key
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const NOTIFY_TO      = "dustinstohler1@gmail.com";
const NOTIFY_FROM    = "OtterQuote <notifications@otterquote.com>";

serve(async (req: Request) => {
  try {
    // Supabase Database Webhook sends the row as { type, table, record, old_record }
    const payload = await req.json();
    const record = payload.record ?? payload; // graceful fallback

    const contractorName  = record.contractor_name  ?? "Unknown Contractor";
    const contractorEmail = record.contractor_email ?? "Unknown Email";
    const requestText     = record.request_text     ?? "(no text)";
    const createdAt       = record.created_at
      ? new Date(record.created_at).toLocaleString("en-US", { timeZone: "America/Chicago" })
      : new Date().toLocaleString("en-US", { timeZone: "America/Chicago" });

    // ── Plain-text body ──────────────────────────────────────
    const textBody = [
      "New feature request submitted on OtterQuote.",
      "",
      `Contractor : ${contractorName}`,
      `Email      : ${contractorEmail}`,
      `Submitted  : ${createdAt} (CT)`,
      "",
      "─────────────────────────────────",
      requestText,
      "─────────────────────────────────",
      "",
      "View all requests in your Supabase dashboard:",
      "https://app.supabase.com → Table Editor → feature_requests",
    ].join("\n");

    // ── HTML body ────────────────────────────────────────────
    const htmlBody = `
      <div style="font-family:sans-serif; max-width:600px; margin:0 auto; color:#0B1929;">
        <div style="background:#0B1929; padding:20px 24px; border-radius:8px 8px 0 0;">
          <h2 style="color:#F59E0B; margin:0; font-size:1.1rem;">🦦 New OtterQuote Feature Request</h2>
        </div>
        <div style="background:#F8FAFC; padding:24px; border:1px solid #E2E8F0; border-top:none; border-radius:0 0 8px 8px;">
          <table style="width:100%; border-collapse:collapse; font-size:0.9rem; margin-bottom:20px;">
            <tr>
              <td style="padding:6px 0; color:#64748B; width:110px;">Contractor</td>
              <td style="padding:6px 0; font-weight:600;">${escapeHtml(contractorName)}</td>
            </tr>
            <tr>
              <td style="padding:6px 0; color:#64748B;">Email</td>
              <td style="padding:6px 0;"><a href="mailto:${escapeHtml(contractorEmail)}" style="color:#0369A1;">${escapeHtml(contractorEmail)}</a></td>
            </tr>
            <tr>
              <td style="padding:6px 0; color:#64748B;">Submitted</td>
              <td style="padding:6px 0;">${escapeHtml(createdAt)} CT</td>
            </tr>
          </table>
          <div style="background:white; border:1px solid #CBD5E1; border-radius:6px; padding:16px; font-size:0.95rem; line-height:1.6; white-space:pre-wrap;">${escapeHtml(requestText)}</div>
          <p style="margin-top:20px; font-size:0.8rem; color:#94A3B8;">
            View all requests in your
            <a href="https://app.supabase.com" style="color:#0369A1;">Supabase dashboard</a>
            → Table Editor → feature_requests
          </p>
        </div>
      </div>
    `;

    // ── Send via Resend ──────────────────────────────────────
    if (!RESEND_API_KEY) {
      throw new Error("RESEND_API_KEY secret is not set. Add it in Supabase Dashboard → Settings → Edge Functions → Secrets.");
    }

    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from:    NOTIFY_FROM,
        to:      [NOTIFY_TO],
        subject: `Feature Request — ${contractorName}`,
        text:    textBody,
        html:    htmlBody,
      }),
    });

    if (!resendRes.ok) {
      const errText = await resendRes.text();
      throw new Error(`Resend API error ${resendRes.status}: ${errText}`);
    }

    const resendData = await resendRes.json();
    console.log("Email sent:", resendData.id);

    return new Response(
      JSON.stringify({ success: true, email_id: resendData.id }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("notify-feature-request error:", err);
    return new Response(
      JSON.stringify({ success: false, error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

// ── Utility ─────────────────────────────────────────────────
function escapeHtml(str: string): string {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

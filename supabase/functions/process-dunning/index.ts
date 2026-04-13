/**
 * OtterQuote Edge Function: process-dunning
 * Handles the dunning sequence for failed contractor payments.
 *
 * Two modes:
 *   1. TRIGGER mode (POST with body): Called immediately on payment failure
 *      to create a payment_failures record and send the first notification.
 *   2. CRON mode (POST without body / GET): Scans for active dunning records
 *      that need reminders or escalation, and processes them.
 *
 * Environment variables:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   STRIPE_SECRET_KEY
 *   MAILGUN_API_KEY
 *   MAILGUN_DOMAIN (e.g. mail.otterquote.com)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_API_BASE = "https://api.stripe.com/v1";
const ADMIN_EMAIL = "dustinstohler1@gmail.com";
const PLATFORM_URL = "https://otterquote.com";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Email helper via Mailgun ──
async function sendEmail(
  to: string,
  subject: string,
  html: string,
  from?: string
) {
  const mailgunKey = Deno.env.get("MAILGUN_API_KEY");
  const mailgunDomain = Deno.env.get("MAILGUN_DOMAIN") || "mail.otterquote.com";

  if (!mailgunKey) {
    console.error("MAILGUN_API_KEY not set — cannot send email");
    return false;
  }

  const formData = new URLSearchParams();
  formData.append("from", from || `OtterQuote <noreply@${mailgunDomain}>`);
  formData.append("to", to);
  formData.append("subject", subject);
  formData.append("html", html);

  try {
    const resp = await fetch(
      `https://api.mailgun.net/v3/${mailgunDomain}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`api:${mailgunKey}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: formData.toString(),
      }
    );

    if (!resp.ok) {
      const errText = await resp.text();
      console.error(`Mailgun error (${resp.status}):`, errText);
      return false;
    }
    return true;
  } catch (err) {
    console.error("Mailgun send error:", err);
    return false;
  }
}

// ── Get next business day at 10 AM ET ──
function getNextBusinessDay10AM(): Date {
  const now = new Date();
  // Convert to Eastern Time approximation (UTC-4 EDT / UTC-5 EST)
  // Using UTC-4 as a safe approximation for storm season (EDT)
  const etOffset = -4;
  const etNow = new Date(now.getTime() + etOffset * 60 * 60 * 1000);

  let target = new Date(etNow);
  target.setDate(target.getDate() + 1);
  // Skip weekends
  while (target.getDay() === 0 || target.getDay() === 6) {
    target.setDate(target.getDate() + 1);
  }
  // Set to 10:00 AM ET
  target.setHours(10, 0, 0, 0);

  // Convert back to UTC
  return new Date(target.getTime() - etOffset * 60 * 60 * 1000);
}

// ── Check if it's quiet hours (9 PM - 7 AM ET) ──
function isQuietHours(): boolean {
  const now = new Date();
  const etOffset = -4;
  const etHour =
    (now.getUTCHours() + etOffset + 24) % 24;
  return etHour >= 21 || etHour < 7;
}

// ── Get next allowed reminder time (respects quiet hours) ──
function getNextReminderTime(): Date {
  const twoHours = new Date(Date.now() + 2 * 60 * 60 * 1000);

  if (isQuietHours()) {
    // Set to 7 AM ET next day
    const etOffset = -4;
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setUTCHours(7 - etOffset, 0, 0, 0);
    return tomorrow;
  }

  // Check if 2 hours from now would be in quiet hours
  const etOffset = -4;
  const futureEtHour =
    (twoHours.getUTCHours() + etOffset + 24) % 24;
  if (futureEtHour >= 21 || futureEtHour < 7) {
    // Set to 7 AM ET next day
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setUTCHours(7 - etOffset, 0, 0, 0);
    return tomorrow;
  }

  return twoHours;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    let body: any = null;
    try {
      const text = await req.text();
      if (text) body = JSON.parse(text);
    } catch {
      // No body or invalid JSON — cron mode
    }

    // ════════════════════════════════════════════════
    // MODE 1: TRIGGER — Payment just failed
    // ════════════════════════════════════════════════
    if (body && body.quote_id && body.contractor_id) {
      console.log("TRIGGER mode: Creating dunning record for quote", body.quote_id);

      const {
        quote_id,
        contractor_id,
        claim_id,
        homeowner_id,
        amount_cents,
        stripe_error,
      } = body;

      // Create payment_failures record
      const { data: failureRecord, error: insertError } = await supabase
        .from("payment_failures")
        .insert({
          quote_id,
          contractor_id,
          claim_id,
          homeowner_id,
          amount_cents,
          stripe_error: stripe_error || "Payment declined",
          dunning_status: "active",
          next_reminder_at: getNextReminderTime().toISOString(),
          reminder_count: 1, // First notification sent now
        })
        .select()
        .single();

      if (insertError) {
        throw new Error(`Failed to create payment_failures record: ${insertError.message}`);
      }

      // Update quote payment status
      await supabase
        .from("quotes")
        .update({ payment_status: "dunning" })
        .eq("id", quote_id);

      // Look up contractor info for the email
      const { data: contractor } = await supabase
        .from("contractors")
        .select("company_name, email, notification_emails, user_id")
        .eq("id", contractor_id)
        .single();

      // Look up claim info for context
      const { data: claim } = await supabase
        .from("claims")
        .select("property_address")
        .eq("id", claim_id)
        .single();

      // Get contractor email
      let contractorEmail = contractor?.email;
      if (!contractorEmail && contractor?.notification_emails?.length) {
        contractorEmail = contractor.notification_emails[0];
      }
      if (!contractorEmail && contractor?.user_id) {
        const { data: profile } = await supabase
          .from("profiles")
          .select("email")
          .eq("id", contractor.user_id)
          .single();
        contractorEmail = profile?.email;
      }

      const companyName = contractor?.company_name || "Contractor";
      const projectDesc = claim?.property_address
        ? `Project at ${claim.property_address}`
        : `Quote ${quote_id.substring(0, 8)}`;
      const feeFormatted = `$${(amount_cents / 100).toFixed(2)}`;
      const escalationTime = getNextBusinessDay10AM();
      const escalationStr = escalationTime.toLocaleString("en-US", {
        weekday: "long",
        month: "long",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
        timeZone: "America/Indiana/Indianapolis",
      });

      // Send immediate email to contractor
      if (contractorEmail) {
        await sendEmail(
          contractorEmail,
          `Action Required: Payment Failed for ${projectDesc}`,
          `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background: #0B1929; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
              <img src="${PLATFORM_URL}/img/otter-logo.svg" alt="OtterQuote" style="width: 40px; height: 40px;">
              <h1 style="color: #F59E0B; font-size: 18px; margin: 10px 0 0;">Payment Failed</h1>
            </div>
            <div style="background: #ffffff; padding: 24px; border: 1px solid #e5e7eb; border-radius: 0 0 8px 8px;">
              <p>Hi ${companyName},</p>
              <p>We attempted to charge your payment method <strong>${feeFormatted}</strong> for the platform fee on <strong>${projectDesc}</strong>, but the payment was <strong style="color: #DC2626;">declined</strong>.</p>
              <div style="background: #FEF2F2; border: 1px solid #FECACA; border-radius: 8px; padding: 16px; margin: 16px 0;">
                <p style="color: #991B1B; font-weight: 600; margin: 0 0 8px;">What happens next:</p>
                <ul style="color: #7F1D1D; margin: 0; padding-left: 20px;">
                  <li>Update your card at <a href="${PLATFORM_URL}/contractor-settings.html" style="color: #0369A1;">${PLATFORM_URL}/contractor-settings.html</a></li>
                  <li>If not resolved by <strong>${escalationStr}</strong>, the homeowner will be advised to select another contractor</li>
                </ul>
              </div>
              <a href="${PLATFORM_URL}/contractor-settings.html" style="display: inline-block; background: #F59E0B; color: #0B1929; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600; margin-top: 8px;">Update Payment Method</a>
              <p style="color: #6B7280; font-size: 13px; margin-top: 20px;">Questions? Contact us at support@otterquote.com</p>
            </div>
          </div>
          `
        );
      }

      // Create in-app notification for contractor
      if (contractor?.user_id) {
        await supabase.from("notifications").insert({
          user_id: contractor.user_id,
          notification_type: "payment_failed",
          channel: "dashboard",
          title: "Payment Failed",
          message: `Your payment of ${feeFormatted} for ${projectDesc} was declined. Please update your payment method.`,
          metadata: {
            quote_id,
            claim_id,
            failure_id: failureRecord.id,
            amount_cents,
          },
        });
      }

      console.log(
        "Dunning initiated: failure_id=",
        failureRecord.id,
        "contractor=",
        contractor_id,
        "amount=",
        feeFormatted
      );

      return new Response(
        JSON.stringify({
          success: true,
          failure_id: failureRecord.id,
          next_reminder_at: failureRecord.next_reminder_at,
          escalation_at: escalationTime.toISOString(),
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ════════════════════════════════════════════════
    // MODE 2: CRON — Process active dunning records
    // ════════════════════════════════════════════════
    console.log("CRON mode: Scanning active dunning records...");

    const now = new Date();
    const escalationDeadline = now.toISOString();

    // Fetch all active dunning records where next_reminder_at has passed
    const { data: activeFailures, error: fetchError } = await supabase
      .from("payment_failures")
      .select(`
        *,
        contractors:contractor_id (
          id, company_name, email, notification_emails, user_id,
          stripe_customer_id, stripe_payment_method_id
        ),
        claims:claim_id (
          id, property_address, status
        )
      `)
      .eq("dunning_status", "active")
      .lte("next_reminder_at", escalationDeadline)
      .order("next_reminder_at", { ascending: true });

    if (fetchError) {
      throw new Error(`Failed to fetch active dunning records: ${fetchError.message}`);
    }

    if (!activeFailures || activeFailures.length === 0) {
      console.log("No active dunning records to process.");
      return new Response(
        JSON.stringify({ processed: 0, message: "No active dunning records." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Processing ${activeFailures.length} active dunning records...`);

    let processed = 0;
    let escalated = 0;

    for (const failure of activeFailures) {
      const contractor = failure.contractors as any;
      const claim = failure.claims as any;
      const feeFormatted = `$${(failure.amount_cents / 100).toFixed(2)}`;
      const projectDesc = claim?.property_address
        ? `Project at ${claim.property_address}`
        : `Quote ${failure.quote_id?.substring(0, 8) || "unknown"}`;

      // Check if we've passed the 10 AM next business day escalation deadline
      const createdAt = new Date(failure.created_at);
      const escalationTime = getNextBusinessDay10AMFrom(createdAt);

      if (now >= escalationTime) {
        // ── ESCALATE: Past deadline ──
        console.log(
          "ESCALATING failure",
          failure.id,
          "— past 10AM deadline"
        );

        // Update dunning status
        await supabase
          .from("payment_failures")
          .update({
            dunning_status: "escalated",
            next_reminder_at: null,
          })
          .eq("id", failure.id);

        // Update quote payment status
        if (failure.quote_id) {
          await supabase
            .from("quotes")
            .update({ payment_status: "failed", status: "submitted" })
            .eq("id", failure.quote_id);
        }

        // Reset claim status so homeowner can select another contractor
        if (failure.claim_id) {
          await supabase
            .from("claims")
            .update({
              status: "bidding",
              selected_contractor_id: null,
              selected_bid_amount: null,
            })
            .eq("id", failure.claim_id);

          // Un-decline other quotes
          await supabase
            .from("quotes")
            .update({ status: "submitted" })
            .eq("claim_id", failure.claim_id)
            .eq("status", "declined");
        }

        // Email homeowner
        if (failure.homeowner_id) {
          const { data: hwProfile } = await supabase
            .from("profiles")
            .select("email, full_name")
            .eq("id", failure.homeowner_id)
            .single();

          if (hwProfile?.email) {
            await sendEmail(
              hwProfile.email,
              `Action Needed: Please Select Another Contractor — OtterQuote`,
              `
              <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                <div style="background: #0B1929; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
                  <img src="${PLATFORM_URL}/img/otter-logo.svg" alt="OtterQuote" style="width: 40px; height: 40px;">
                  <h1 style="color: #14B8A6; font-size: 18px; margin: 10px 0 0;">Update on Your Project</h1>
                </div>
                <div style="background: #ffffff; padding: 24px; border: 1px solid #e5e7eb; border-radius: 0 0 8px 8px;">
                  <p>Hi ${hwProfile.full_name || "there"},</p>
                  <p>We're sorry — there was a processing issue with your selected contractor for <strong>${projectDesc}</strong>. We recommend selecting another contractor from your bids.</p>
                  <a href="${PLATFORM_URL}/bids.html?claim_id=${failure.claim_id}" style="display: inline-block; background: #14B8A6; color: #ffffff; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600; margin-top: 12px;">View Your Bids</a>
                  <p style="color: #6B7280; font-size: 13px; margin-top: 20px;">Questions? Contact us at support@otterquote.com</p>
                </div>
              </div>
              `
            );
          }
        }

        // Email contractor that they lost the project
        let contractorEmail = contractor?.email;
        if (!contractorEmail && contractor?.notification_emails?.length) {
          contractorEmail = contractor.notification_emails[0];
        }
        if (contractorEmail) {
          await sendEmail(
            contractorEmail,
            `Payment Not Resolved — ${projectDesc}`,
            `
            <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
              <div style="background: #0B1929; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
                <img src="${PLATFORM_URL}/img/otter-logo.svg" alt="OtterQuote" style="width: 40px; height: 40px;">
                <h1 style="color: #EF4444; font-size: 18px; margin: 10px 0 0;">Payment Not Resolved</h1>
              </div>
              <div style="background: #ffffff; padding: 24px; border: 1px solid #e5e7eb; border-radius: 0 0 8px 8px;">
                <p>Hi ${contractor?.company_name || "there"},</p>
                <p>Your payment of <strong>${feeFormatted}</strong> for <strong>${projectDesc}</strong> was not resolved within the required timeframe.</p>
                <p>The homeowner has been advised to select another contractor.</p>
                <p>Please update your payment method at <a href="${PLATFORM_URL}/contractor-settings.html">${PLATFORM_URL}/contractor-settings.html</a> to avoid this on future projects.</p>
                <p style="color: #6B7280; font-size: 13px; margin-top: 20px;">Questions? Contact us at support@otterquote.com</p>
              </div>
            </div>
            `
          );
        }

        // Notify Dustin (admin)
        await sendEmail(
          ADMIN_EMAIL,
          `Payment Escalation: ${contractor?.company_name || "Unknown"} — ${projectDesc}`,
          `
          <div style="font-family: monospace; padding: 20px;">
            <h2>Payment Escalation Alert</h2>
            <p><strong>Contractor:</strong> ${contractor?.company_name || "Unknown"} (${failure.contractor_id})</p>
            <p><strong>Project:</strong> ${projectDesc}</p>
            <p><strong>Amount:</strong> ${feeFormatted}</p>
            <p><strong>Quote ID:</strong> ${failure.quote_id}</p>
            <p><strong>Claim ID:</strong> ${failure.claim_id}</p>
            <p><strong>Stripe Error:</strong> ${failure.stripe_error || "N/A"}</p>
            <p><strong>Reminders Sent:</strong> ${failure.reminder_count}</p>
            <p><strong>Homeowner notified.</strong> Claim status reset to bidding.</p>
          </div>
          `
        );

        escalated++;
        processed++;
        continue;
      }

      // ── REMINDER: Not yet at escalation deadline ──
      console.log(
        "Sending reminder #",
        failure.reminder_count + 1,
        "for failure",
        failure.id
      );

      // Determine urgency level
      const hoursRemaining = Math.max(
        0,
        (escalationTime.getTime() - now.getTime()) / (1000 * 60 * 60)
      );
      const urgencyLevel =
        hoursRemaining < 4 ? "FINAL WARNING" :
        hoursRemaining < 8 ? "URGENT" :
        "REMINDER";

      // Email contractor with escalating urgency
      let contractorEmail2 = contractor?.email;
      if (!contractorEmail2 && contractor?.notification_emails?.length) {
        contractorEmail2 = contractor.notification_emails[0];
      }
      if (contractorEmail2) {
        await sendEmail(
          contractorEmail2,
          `${urgencyLevel}: Payment Still Pending for ${projectDesc}`,
          `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background: ${urgencyLevel === "FINAL WARNING" ? "#7F1D1D" : "#0B1929"}; padding: 20px; border-radius: 8px 8px 0 0; text-align: center;">
              <h1 style="color: ${urgencyLevel === "FINAL WARNING" ? "#FCA5A5" : "#F59E0B"}; font-size: 18px; margin: 0;">${urgencyLevel}: Payment Required</h1>
            </div>
            <div style="background: #ffffff; padding: 24px; border: 1px solid #e5e7eb; border-radius: 0 0 8px 8px;">
              <p>Hi ${contractor?.company_name || "there"},</p>
              <p>Your payment of <strong>${feeFormatted}</strong> for <strong>${projectDesc}</strong> is still pending.</p>
              ${hoursRemaining < 4 ? `<p style="color: #DC2626; font-weight: 600;">This is your final warning. The homeowner will be advised to choose another contractor if payment is not resolved within ${Math.ceil(hoursRemaining)} hours.</p>` : ""}
              <a href="${PLATFORM_URL}/contractor-settings.html" style="display: inline-block; background: #F59E0B; color: #0B1929; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600; margin-top: 12px;">Update Payment Method Now</a>
              <p style="color: #6B7280; font-size: 13px; margin-top: 20px;">Questions? Contact us at support@otterquote.com</p>
            </div>
          </div>
          `
        );
      }

      // Update reminder tracking
      await supabase
        .from("payment_failures")
        .update({
          reminder_count: failure.reminder_count + 1,
          next_reminder_at: getNextReminderTime().toISOString(),
        })
        .eq("id", failure.id);

      // SMS hook (ready for when TCR is approved)
      // TODO: When TCR campaign is active, add SMS reminders here
      // if (contractor?.notification_phones?.length) {
      //   await sendSMS(contractor.notification_phones[0], message);
      // }

      processed++;
    }

    console.log(
      `Dunning cron complete: ${processed} processed, ${escalated} escalated.`
    );

    return new Response(
      JSON.stringify({
        processed,
        escalated,
        total_active: activeFailures.length,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("process-dunning error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Helper: get escalation deadline relative to a specific date
function getNextBusinessDay10AMFrom(fromDate: Date): Date {
  const etOffset = -4;
  const etFrom = new Date(fromDate.getTime() + etOffset * 60 * 60 * 1000);

  let target = new Date(etFrom);
  target.setDate(target.getDate() + 1);
  while (target.getDay() === 0 || target.getDay() === 6) {
    target.setDate(target.getDate() + 1);
  }
  target.setHours(10, 0, 0, 0);

  return new Date(target.getTime() - etOffset * 60 * 60 * 1000);
}

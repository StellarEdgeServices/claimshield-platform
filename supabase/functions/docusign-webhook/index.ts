/**
 * OtterQuote Edge Function: docusign-webhook
 * Receives DocuSign Connect webhook notifications when envelope status changes.
 * Updates claims table on signing completion, decline, or void.
 *
 * Environment variables:
 *   DOCUSIGN_CONNECT_HMAC_KEY — shared secret for HMAC-SHA256 signature verification
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — auto-provided by Supabase
 *
 * DocuSign Connect sends JSON payloads to this endpoint. The webhook URL is:
 *   https://yeszghaspzwwstvsrioa.supabase.co/functions/v1/docusign-webhook
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-docusign-signature-1",
};

// ========== HMAC VERIFICATION ==========
async function verifyHmacSignature(
  payload: string,
  signatureHeader: string | null,
  hmacKey: string
): Promise<boolean> {
  if (!signatureHeader || !hmacKey) {
    console.warn("Missing signature header or HMAC key — skipping verification");
    // In development/sandbox, allow unsigned requests
    // In production, return false to reject unsigned requests
    return !hmacKey; // Allow if no key configured, reject if key exists but no signature
  }

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(hmacKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signatureBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payload)
  );

  const computedSignature = btoa(
    String.fromCharCode(...new Uint8Array(signatureBuffer))
  );

  return computedSignature === signatureHeader;
}

// ========== MAIN HANDLER ==========
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only accept POST
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    // Read raw body for HMAC verification
    const rawBody = await req.text();

    // Verify HMAC signature if configured
    const hmacKey = Deno.env.get("DOCUSIGN_CONNECT_HMAC_KEY") || "";
    const signatureHeader = req.headers.get("x-docusign-signature-1");

    if (hmacKey) {
      const isValid = await verifyHmacSignature(rawBody, signatureHeader, hmacKey);
      if (!isValid) {
        console.error("HMAC signature verification failed");
        return new Response(
          JSON.stringify({ error: "Invalid signature" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      console.log("HMAC signature verified");
    }

    // Parse the payload
    const payload = JSON.parse(rawBody);

    // DocuSign Connect sends envelope status in different formats depending on config.
    // JSON format: { event, apiVersion, uri, retryCount, configurationId, generatedDateTime,
    //               data: { envelopeId, envelopeSummary: { status, emailSubject, ... } } }
    // or sometimes: { envelopeId, status, ... } directly

    let envelopeId: string | null = null;
    let status: string | null = null;
    let recipientEmail: string | null = null;
    let completedDateTime: string | null = null;
    let declinedDateTime: string | null = null;
    let voidedDateTime: string | null = null;
    let event: string | null = null;

    // Handle the Connect JSON payload format
    if (payload.data?.envelopeSummary) {
      const summary = payload.data.envelopeSummary;
      envelopeId = payload.data.envelopeId || summary.envelopeId;
      status = summary.status;
      completedDateTime = summary.completedDateTime;
      declinedDateTime = summary.declinedDateTime;
      voidedDateTime = summary.voidedDateTime;
      event = payload.event;

      // Try to get the first signer's email
      const signers = summary.recipients?.signers;
      if (signers && signers.length > 0) {
        recipientEmail = signers[0].email;
      }
    } else if (payload.envelopeId) {
      // Simpler format
      envelopeId = payload.envelopeId;
      status = payload.status;
      completedDateTime = payload.completedDateTime;
      declinedDateTime = payload.declinedDateTime;
      voidedDateTime = payload.voidedDateTime;
      event = payload.event;
    } else {
      console.warn("Unrecognized payload format:", JSON.stringify(payload).slice(0, 500));
      return new Response(
        JSON.stringify({ received: true, warning: "Unrecognized payload format" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!envelopeId) {
      console.warn("No envelopeId in payload");
      return new Response(
        JSON.stringify({ received: true, warning: "No envelopeId" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Webhook received: envelope=${envelopeId}, status=${status}, event=${event}`);

    // ========== FIND THE CLAIM ==========
    // Look up claim by docusign_envelope_id or color_confirmation_envelope_id
    const { data: claim, error: claimError } = await supabase
      .from("claims")
      .select("id, status, docusign_envelope_id, color_confirmation_envelope_id, contract_signed_at")
      .or(`docusign_envelope_id.eq.${envelopeId},color_confirmation_envelope_id.eq.${envelopeId}`)
      .limit(1)
      .single();

    if (claimError || !claim) {
      console.warn(`No claim found for envelope ${envelopeId}:`, claimError?.message);
      // Return 200 anyway — DocuSign will retry on non-2xx
      return new Response(
        JSON.stringify({ received: true, warning: "No matching claim found" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const isContract = claim.docusign_envelope_id === envelopeId;
    const isColorConfirmation = claim.color_confirmation_envelope_id === envelopeId;

    console.log(`Matched claim ${claim.id} (${isContract ? "contract" : "color_confirmation"})`);

    // ========== UPDATE CLAIM BASED ON STATUS ==========
    const updateData: Record<string, any> = {};

    if (status === "completed") {
      // Envelope fully signed by all parties
      if (isContract) {
        // Only update if not already marked signed (idempotency)
        if (!claim.contract_signed_at) {
          updateData.contract_signed_at = completedDateTime || new Date().toISOString();
          updateData.contract_signed_by = recipientEmail || null;
          updateData.status = "contract_signed";
        }
      } else if (isColorConfirmation) {
        updateData.color_confirmed_at = completedDateTime || new Date().toISOString();
      }
    } else if (status === "declined") {
      // A signer declined
      if (isContract) {
        updateData.contract_declined_at = declinedDateTime || new Date().toISOString();
        // Don't change claim status — homeowner may re-sign or choose another contractor
      }
    } else if (status === "voided") {
      // Envelope was voided (cancelled)
      if (isContract) {
        updateData.contract_voided_at = voidedDateTime || new Date().toISOString();
      }
    } else if (status === "sent" || status === "delivered") {
      // Informational — envelope was sent or viewed. No claim update needed.
      console.log(`Informational status: ${status} for envelope ${envelopeId}`);
    }

    // Apply updates if any
    if (Object.keys(updateData).length > 0) {
      const { error: updateError } = await supabase
        .from("claims")
        .update(updateData)
        .eq("id", claim.id);

      if (updateError) {
        console.error(`Failed to update claim ${claim.id}:`, updateError);
        // Still return 200 to avoid DocuSign retries
      } else {
        console.log(`Updated claim ${claim.id}:`, JSON.stringify(updateData));
      }

      // ── Notify contractor on signing completion ──
      if (status === "completed" && isContract) {
        try {
          // Fire-and-forget notification to contractor
          const notifyResponse = await fetch(`${supabaseUrl}/functions/v1/notify-contractors`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${supabaseKey}`,
            },
            body: JSON.stringify({
              claim_id: claim.id,
              event_type: "contract_signed",
              message: "A homeowner has signed your contract! Contact them within 48 hours.",
            }),
          });
          console.log(`Contractor notification sent: ${notifyResponse.status}`);
        } catch (notifyErr) {
          // Non-critical — don't fail the webhook
          console.error("Failed to notify contractor:", notifyErr);
        }
      }
    }

    // ========== LOG THE EVENT ==========
    try {
      await supabase.from("notifications").insert({
        claim_id: claim.id,
        channel: "webhook",
        notification_type: `docusign_${status}`,
        recipient: recipientEmail || "unknown",
        message_preview: `Envelope ${envelopeId} status: ${status}`,
      });
    } catch (logErr) {
      // Non-critical
      console.error("Failed to log webhook event:", logErr);
    }

    // ========== SUCCESS ==========
    return new Response(
      JSON.stringify({
        received: true,
        envelope_id: envelopeId,
        status,
        claim_id: claim.id,
        updated: Object.keys(updateData).length > 0,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("docusign-webhook error:", error);

    // Always return 200 to prevent DocuSign from retrying on parse errors
    return new Response(
      JSON.stringify({
        received: true,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

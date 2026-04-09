/**
 * OtterQuote Edge Function: create-payment-intent
 * Creates a Stripe PaymentIntent for three use cases:
 *   - Hover measurement purchases (~$49)
 *   - Deductible escrow
 *   - Contractor platform fees
 * Rate-limited via Supabase check_rate_limit() RPC.
 *
 * Environment variables:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   STRIPE_SECRET_KEY
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_NAME = "create-payment-intent";
const STRIPE_API_BASE = "https://api.stripe.com/v1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const {
      amount,
      currency,
      description,
      metadata,
      contractor_id,
      off_session,
    } = await req.json();

    // Validate required fields
    if (
      !amount ||
      typeof amount !== "number" ||
      amount <= 0 ||
      !Number.isInteger(amount)
    ) {
      return new Response(
        JSON.stringify({
          error: "Invalid amount. Must be a positive integer (in cents).",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!currency || typeof currency !== "string") {
      return new Response(
        JSON.stringify({
          error: "Invalid currency. Must be a string (e.g., 'usd').",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!metadata || !metadata.claim_id || !metadata.type) {
      return new Response(
        JSON.stringify({
          error:
            "Missing required metadata fields: claim_id and type (hover_measurement, deductible_escrow, or platform_fee).",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const validTypes = ["hover_measurement", "deductible_escrow", "platform_fee"];
    if (!validTypes.includes(metadata.type)) {
      return new Response(
        JSON.stringify({
          error: `Invalid metadata.type. Must be one of: ${validTypes.join(", ")}`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // For platform_fee type, contractor_id and off_session are required
    if (metadata.type === "platform_fee" && off_session) {
      if (!contractor_id) {
        return new Response(
          JSON.stringify({
            error:
              "Missing contractor_id for off-session platform fee charge.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    // ========== RATE LIMIT CHECK ==========
    const { data: rateLimitResult, error: rlError } = await supabase.rpc(
      "check_rate_limit",
      {
        p_function_name: FUNCTION_NAME,
        p_caller_id: metadata.claim_id || null,
      }
    );

    if (rlError) {
      console.error("Rate limit check failed:", rlError);
      return new Response(
        JSON.stringify({
          error:
            "Rate limit check failed. Refusing to create payment intent for safety.",
          detail: rlError.message,
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!rateLimitResult?.allowed) {
      console.warn(
        `RATE LIMITED [${FUNCTION_NAME}]: ${rateLimitResult?.reason}`
      );
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          reason: rateLimitResult?.reason,
          counts: rateLimitResult?.counts,
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ========== GET STRIPE SECRET KEY ==========
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");

    if (!stripeSecretKey) {
      throw new Error(
        "Stripe secret key not configured. Set STRIPE_SECRET_KEY environment variable."
      );
    }

    // ========== HANDLE OFF-SESSION CHARGING (Contractor Platform Fees) ==========
    let paymentIntentData;

    if (metadata.type === "platform_fee" && off_session && contractor_id) {
      // Look up contractor's saved payment method
      const { data: contractorData, error: contractorError } = await supabase
        .from("contractors")
        .select("stripe_payment_method_id, stripe_customer_id")
        .eq("id", contractor_id)
        .single();

      if (contractorError || !contractorData) {
        throw new Error(
          `Failed to look up contractor payment method: ${
            contractorError?.message || "contractor not found"
          }`
        );
      }

      if (
        !contractorData.stripe_payment_method_id ||
        !contractorData.stripe_customer_id
      ) {
        throw new Error(
          "Contractor does not have a payment method on file. Charge cannot proceed."
        );
      }

      console.log(
        "Creating off-session PaymentIntent for contractor",
        contractor_id,
        "amount:",
        amount,
        currency
      );

      // Build URL-encoded form data for off-session charge
      const offSessionFormData = new URLSearchParams();
      offSessionFormData.append("amount", String(amount));
      offSessionFormData.append("currency", currency);
      offSessionFormData.append("customer", contractorData.stripe_customer_id);
      offSessionFormData.append(
        "payment_method",
        contractorData.stripe_payment_method_id
      );
      offSessionFormData.append("off_session", "true");
      offSessionFormData.append("confirm", "true"); // Automatically confirm the payment
      offSessionFormData.append("description", description || "");
      offSessionFormData.append("metadata[claim_id]", metadata.claim_id);
      offSessionFormData.append("metadata[type]", metadata.type);
      offSessionFormData.append("metadata[contractor_id]", contractor_id);

      const basicAuth = btoa(`${stripeSecretKey}:`);

      const offSessionResponse = await fetch(
        `${STRIPE_API_BASE}/payment_intents`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${basicAuth}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: offSessionFormData.toString(),
        }
      );

      if (!offSessionResponse.ok) {
        const errorData = await offSessionResponse.text();
        console.error(
          "Stripe off-session PaymentIntent failed:",
          offSessionResponse.status,
          errorData
        );
        throw new Error(
          `Stripe off-session charge failed (HTTP ${offSessionResponse.status}): ${errorData}`
        );
      }

      paymentIntentData = await offSessionResponse.json();

      // Check payment intent status
      if (paymentIntentData.status === "requires_action") {
        throw new Error(
          "Payment requires additional authentication. Please update your payment method."
        );
      }

      if (paymentIntentData.status === "requires_payment_method") {
        throw new Error(
          "Payment method failed. Please update your payment method and try again."
        );
      }

      console.log(
        "Off-session PaymentIntent status:",
        paymentIntentData.status,
        "ID:",
        paymentIntentData.id
      );
    } else {
      // ========== CREATE PAYMENT INTENT (Standard flow for homeowner/measurement fees) ==========
      const basicAuth = btoa(`${stripeSecretKey}:`);

      // Build URL-encoded form data
      const formData = new URLSearchParams();
      formData.append("amount", String(amount));
      formData.append("currency", currency);
      formData.append("description", description || "");
      formData.append("metadata[claim_id]", metadata.claim_id);
      formData.append("metadata[type]", metadata.type);
      formData.append("automatic_payment_methods[enabled]", "true");

      console.log(
        "Creating Stripe PaymentIntent for",
        metadata.type,
        "claim:",
        metadata.claim_id,
        "amount:",
        amount,
        currency
      );

      const paymentIntentResponse = await fetch(
        `${STRIPE_API_BASE}/payment_intents`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${basicAuth}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: formData.toString(),
        }
      );

      if (!paymentIntentResponse.ok) {
        const errorData = await paymentIntentResponse.text();
        console.error(
          "Stripe PaymentIntent creation failed:",
          paymentIntentResponse.status,
          errorData
        );
        throw new Error(
          `Stripe API error (HTTP ${paymentIntentResponse.status}): ${errorData}`
        );
      }

      paymentIntentData = await paymentIntentResponse.json();
    }
    /*
     * paymentIntentData shape:
     * {
     *   id: "pi_xxx",
     *   client_secret: "pi_xxx_secret_xxx",
     *   amount: 4900,
     *   currency: "usd",
     *   status: "requires_payment_method",
     *   metadata: { claim_id: "...", type: "..." },
     *   ...
     * }
     */

    console.log(
      "Stripe PaymentIntent created/confirmed. ID:",
      paymentIntentData.id,
      "Status:",
      paymentIntentData.status
    );

    // For off-session charges, success status is 'succeeded' or 'processing'
    // For standard intents awaiting client action, status is 'requires_payment_method'
    const successStatuses = ["succeeded", "processing"];
    const isSuccessful = successStatuses.includes(paymentIntentData.status);

    return new Response(
      JSON.stringify({
        client_secret: paymentIntentData.client_secret || null,
        payment_intent_id: paymentIntentData.id,
        status: paymentIntentData.status,
        succeeded: isSuccessful,
        amount: paymentIntentData.amount,
        currency: paymentIntentData.currency,
        rate_limit_counts: rateLimitResult?.counts,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("create-payment-intent error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

/**
 * OtterQuote Edge Function: create-setup-intent
 * Creates a Stripe SetupIntent for securely saving a contractor's payment method.
 * If the contractor doesn't have a Stripe Customer yet, creates one first.
 *
 * Environment variables:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   STRIPE_SECRET_KEY
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    const { contractor_id } = await req.json();

    if (!contractor_id) {
      return new Response(
        JSON.stringify({ error: "Missing contractor_id" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Look up contractor record
    const { data: contractor, error: contractorError } = await supabase
      .from("contractors")
      .select(
        "id, stripe_customer_id, company_name, contact_name, email, user_id"
      )
      .eq("id", contractor_id)
      .single();

    if (contractorError || !contractor) {
      return new Response(
        JSON.stringify({
          error: `Contractor not found: ${contractorError?.message || "no record"}`,
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecretKey) {
      throw new Error("Stripe secret key not configured.");
    }

    const basicAuth = btoa(`${stripeSecretKey}:`);

    // ── Step 1: Ensure Stripe Customer exists ──
    let customerId = contractor.stripe_customer_id;

    if (!customerId) {
      // Look up contractor's email from profiles table if not on contractor record
      let email = contractor.email;
      if (!email && contractor.user_id) {
        const { data: profile } = await supabase
          .from("profiles")
          .select("email")
          .eq("id", contractor.user_id)
          .single();
        email = profile?.email;
      }

      // Create Stripe Customer
      const customerFormData = new URLSearchParams();
      customerFormData.append(
        "name",
        contractor.company_name || contractor.contact_name || "Contractor"
      );
      if (email) customerFormData.append("email", email);
      customerFormData.append("metadata[contractor_id]", contractor_id);
      customerFormData.append("metadata[platform]", "otterquote");

      console.log("Creating Stripe Customer for contractor:", contractor_id);

      const customerResponse = await fetch(`${STRIPE_API_BASE}/customers`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${basicAuth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: customerFormData.toString(),
      });

      if (!customerResponse.ok) {
        const errorData = await customerResponse.text();
        throw new Error(
          `Failed to create Stripe Customer (HTTP ${customerResponse.status}): ${errorData}`
        );
      }

      const customerData = await customerResponse.json();
      customerId = customerData.id;

      // Save customer ID to contractor record
      const { error: updateError } = await supabase
        .from("contractors")
        .update({ stripe_customer_id: customerId })
        .eq("id", contractor_id);

      if (updateError) {
        console.error("Failed to save stripe_customer_id:", updateError);
        // Non-fatal — continue with SetupIntent creation
      }

      console.log("Stripe Customer created:", customerId);
    }

    // ── Step 2: Create SetupIntent ──
    const setupFormData = new URLSearchParams();
    setupFormData.append("customer", customerId);
    setupFormData.append("payment_method_types[]", "card");
    setupFormData.append("metadata[contractor_id]", contractor_id);
    setupFormData.append("metadata[platform]", "otterquote");
    setupFormData.append("usage", "off_session");

    console.log(
      "Creating SetupIntent for customer:",
      customerId,
      "contractor:",
      contractor_id
    );

    const setupResponse = await fetch(`${STRIPE_API_BASE}/setup_intents`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: setupFormData.toString(),
    });

    if (!setupResponse.ok) {
      const errorData = await setupResponse.text();
      throw new Error(
        `Failed to create SetupIntent (HTTP ${setupResponse.status}): ${errorData}`
      );
    }

    const setupData = await setupResponse.json();

    console.log("SetupIntent created:", setupData.id, "Status:", setupData.status);

    return new Response(
      JSON.stringify({
        client_secret: setupData.client_secret,
        setup_intent_id: setupData.id,
        customer_id: customerId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("create-setup-intent error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

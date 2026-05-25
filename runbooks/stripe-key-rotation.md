# Runbook: Stripe Key Rotation

**Type:** Credential rotation procedure  
**Applies to:** All environments (live + test keys)  
**Last updated:** 2026-05-14 — Created per Postmortem A4 (docusign-keypair-rotation-20260514)

---

## When to Run This

- Stripe dashboard detects unauthorized API key usage
- Routine security rotation (recommended: every 90 days)
- Pre-launch rotation before first real transaction
- Any team member with access to the key departs
- Security audit or compliance requirement

---

## Env Vars Covered

| Supabase Secret Name | Description | Edge Functions |
|---|---|---|
| `STRIPE_SECRET_KEY` | Live secret key (`sk_live_...`) | create-payment-intent, create-setup-intent, process-dunning |
| `STRIPE_SECRET_KEY_TEST` | Test secret key (`sk_test_...`) — fallback in non-live mode | create-payment-intent, create-setup-intent, process-dunning |
| `STRIPE_WEBHOOK_SIGNING_SECRET` | Webhook endpoint signing secret (`whsec_...`) | stripe-webhook (if deployed) |

> **Note (2026-05-14):** The `stripe-webhook` Edge Function is not currently present in the repo. `STRIPE_WEBHOOK_SIGNING_SECRET` should still be rotated if the secret exists in Supabase, as the EF may be re-deployed. See also: task 86e1d1ht4 (CLICKUP_API_KEY undocumented stripe-webhook dependency).

---

## Tier A Steps (autonomous — before touching Supabase)

- Step 1: Log into Stripe Dashboard → Developers → API keys and note the current key name/ID for rollback reference
- Step 2: Verify current Stripe connectivity — check Stripe Dashboard → Events for recent successful API calls
- Step 3: Check Sentry for baseline Stripe error rate (should be 0) — if errors are already present, diagnose before rotating

## Tier B Steps (execute + notify Dustin)

- Step 1: Generate new key (see procedure below), update Supabase secrets, redeploy EFs
- Step 2: Run smoke test — if it fails, initiate rollback immediately and notify

## Tier C Steps (escalate)

- Step 1: If payment intents are failing in production and rollback does not resolve within 5 minutes, escalate to Stripe support with the API key ID and error logs from Sentry

---

## Full Rotation Procedure

### 1. Generate new key in Stripe Dashboard

1. Go to **Stripe Dashboard → Developers → API keys**
2. Click **+ Create secret key** (recommended) or **Roll** existing key
3. Name it: `otterquote-main-YYYY-MM-DD`
4. Copy the value immediately — Stripe shows it only once

For webhook signing secret rotation:
1. Go to **Stripe Dashboard → Developers → Webhooks**
2. Select the OtterQuote endpoint
3. Click **Roll signing secret**
4. Copy the new `whsec_...` value

### 2. Update Supabase secrets

Go to **Supabase Dashboard → Project Settings → Edge Functions → Secrets** and update:

| Secret Name | Value |
|---|---|
| `STRIPE_SECRET_KEY` | New live key (`sk_live_...`) |
| `STRIPE_SECRET_KEY_TEST` | New test key (`sk_test_...`) — update if rotating test keys |
| `STRIPE_WEBHOOK_SIGNING_SECRET` | New webhook signing secret (`whsec_...`) — if set |

Click **Save** after each update.

### 3. Redeploy all affected Edge Functions

Supabase Edge Functions cache secrets at cold-start. After updating secrets, redeploy:

```bash
supabase functions deploy create-payment-intent --project-ref <project-ref>
supabase functions deploy create-setup-intent --project-ref <project-ref>
supabase functions deploy process-dunning --project-ref <project-ref>
# If stripe-webhook EF is deployed:
supabase functions deploy stripe-webhook --project-ref <project-ref>
```

Or use the Supabase MCP `deploy_edge_function` tool for each function.

### 4. Smoke test — verify payment intent creation

After redeploying, verify the new key works end-to-end:

**Option A — Direct EF test (staging):**
```bash
curl -X POST https://<project-ref>.supabase.co/functions/v1/create-payment-intent \
  -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"amount": 100, "test_mode": true}'
```
Expected: `{"clientSecret": "pi_..."}` — a 500 or Stripe auth error means the secret was not saved or the EF was not redeployed.

**Option B — Staging site walkthrough:**  
Go to staging → initiate a test bid acceptance → confirm the payment intent appears in Stripe Dashboard → Payments.

### 5. Revoke old key (only after smoke test passes)

1. Return to **Stripe Dashboard → Developers → API keys**
2. Click **Roll** or **Delete** on the previous key
3. Confirm it no longer appears as active

---

## Coordinated Rotation Notes

- **`CLICKUP_API_KEY`:** If rotating during a Stripe audit, also check whether `CLICKUP_API_KEY` is set in Supabase secrets for `stripe-webhook`. This undocumented dependency (task 86e1d1ht4) means a ClickUp API key rotation can silently break stripe-webhook side-effects. Rotate via ClickUp → Settings → Integrations → API if needed.
- **`process-dunning` timing:** This EF runs on a schedule. Avoid rotating mid-dunning-cycle (typically late evening). Rotate during business hours and verify dunning emails are queuing correctly post-rotation.
- **Live vs. test keys:** Rotating `STRIPE_SECRET_KEY` (live) is production-impacting. Always smoke-test with `STRIPE_SECRET_KEY_TEST` first if possible.

---

## Resolution Criteria

- New Stripe key is active and listed in Stripe Dashboard
- Supabase secrets updated for all three vars (if applicable)
- All affected EFs redeployed
- Smoke test: `create-payment-intent` returns `{"clientSecret": "pi_..."}` without error
- Old key revoked in Stripe Dashboard
- No Stripe auth errors in Sentry for 5 minutes post-rotation

## Auto-resolve eligible: no

Manual verification required — Stripe auth failures are not always immediately surfaced in Sentry. Human sign-off on smoke test is mandatory.

---

## Rollback

If rotation causes payment failures:

1. Re-add the old key value to Supabase as `STRIPE_SECRET_KEY` (save it before rotation starts — see Step 1 note above)
2. Redeploy all affected EFs with the restored secret
3. Verify smoke test passes with old key
4. Do **not** revoke the old key until the root cause is diagnosed

> Stripe allows multiple active keys simultaneously — you can transition without downtime by activating the new key before revoking the old one.

---

## See Also

- `runbooks/payment-error.md` — when created, add a reference to this runbook in the Stripe auth failure section
- `SUPABASE-SECRETS-SETUP.md` — canonical Supabase secret names for Stripe
- Postmortem: docusign-keypair-rotation-20260514 — source of this runbook gap
- Task 86e1d1ht4 — CLICKUP_API_KEY undocumented stripe-webhook dependency
- Task 86e1d1hfy — parent task for this runbook

# Runbook: Mailgun Key Rotation

**Type:** Credential rotation procedure  
**Applies to:** All environments  
**Last updated:** 2026-05-14 — Created per Postmortem A4 (docusign-keypair-rotation-20260514)

---

## When to Run This

- Mailgun API key is suspected to be compromised
- Routine security rotation (recommended: every 90 days)
- Any team member with access to the key departs
- Mailgun account access is transferred or audited

---

## Env Vars Covered

| Supabase Secret Name | Description | Edge Functions |
|---|---|---|
| `MAILGUN_API_KEY` | Mailgun API key (`key-...`) | send-adjuster-email, process-dunning |
| `MAILGUN_DOMAIN` | Sending domain | send-adjuster-email, process-dunning |

> **Note on `MAILGUN_DOMAIN`:** This value is a domain name, not a secret, but it is stored as a Supabase secret for consistency. It typically does not need rotation unless the sending domain changes. Current value from Supabase: `sandboxd2b099fad357409b845e5f4c5e8bd74e.mailgun.org`. The `process-dunning` EF falls back to `mail.otterquote.com` if this secret is absent.

---

## Tier A Steps (autonomous)

- Step 1: Check Mailgun Dashboard → Logs for recent delivery failures — if failures are already present, diagnose before rotating
- Step 2: Verify both EFs (`send-adjuster-email`, `process-dunning`) are currently healthy in Sentry

## Tier B Steps (execute + notify Dustin)

- Step 1: Generate new API key in Mailgun, update Supabase secret, redeploy affected EFs
- Step 2: Run smoke test (send test email via EF); notify Dustin of result

## Tier C Steps (escalate)

- Step 1: If outbound email is failing in production and rollback does not restore delivery within 10 minutes, contact Mailgun support with the domain name and error details

---

## Full Rotation Procedure

### 1. Dunning-cycle timing check ⚠️

**Before starting:** Confirm that `process-dunning` is not mid-cycle.

`process-dunning` runs on a schedule and sends payment reminder emails. Rotating `MAILGUN_API_KEY` during an active dunning run will cause those emails to fail silently — the EF will log an error but no retry is wired.

- Check the Supabase Edge Function logs for recent `process-dunning` invocations
- If a dunning run completed within the last 30 minutes, proceed
- If a dunning run appears to be in progress, wait for it to complete before rotating

### 2. Generate new API key in Mailgun

1. Go to **Mailgun Dashboard → API Keys** (or Settings → API Keys)
2. Click **Add new key**
3. Label it: `otterquote-main-YYYY-MM-DD`
4. Copy the key value — it is shown only once

### 3. Update Supabase secrets

Go to **Supabase Dashboard → Project Settings → Edge Functions → Secrets** and update:

| Secret Name | Value |
|---|---|
| `MAILGUN_API_KEY` | New Mailgun API key (`key-...`) |
| `MAILGUN_DOMAIN` | Only update if changing the sending domain; otherwise leave unchanged |

Click **Save**.

### 4. Redeploy affected Edge Functions

```bash
supabase functions deploy send-adjuster-email --project-ref <project-ref>
supabase functions deploy process-dunning --project-ref <project-ref>
```

Or use the Supabase MCP `deploy_edge_function` tool for each.

### 5. Smoke test — send a test email via the EF

Invoke `send-adjuster-email` with a test payload to verify the new key is working:

```bash
curl -X POST https://<project-ref>.supabase.co/functions/v1/send-adjuster-email \
  -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "dustinstohler1@gmail.com",
    "subject": "Mailgun rotation smoke test",
    "body": "This is a post-rotation test email. If you received this, the Mailgun key rotation succeeded."
  }'
```

Expected: `{"success": true}` and an email delivered to the test address within 60 seconds.

If the EF returns a 500 or Mailgun auth error, the secret was not saved correctly or the EF was not redeployed — initiate rollback (see below).

### 6. Revoke old key (only after smoke test passes)

1. Return to **Mailgun Dashboard → API Keys**
2. Delete or revoke the previous key
3. Confirm it no longer appears as active

---

## Coordinated Rotation Notes

- **`process-dunning` timing:** See Step 1. Do not rotate mid-dunning-cycle. Dunning emails, adjuster notifications, and bid confirmation emails all route through Mailgun — a failed rotation drops these silently.
- **`MAILGUN_DOMAIN` changes:** If the sending domain changes (e.g., moving from sandbox to `mail.otterquote.com`), also update the `From:` address expectations in any email templates and verify DNS records (SPF, DKIM, DMARC) are configured for the new domain before rotating.
- **Sandbox vs. production domain:** The current Supabase secret uses a Mailgun sandbox domain. If/when migrating to `mail.otterquote.com`, treat that as a domain change rotation — DNS verification must complete before deploying.

---

## Resolution Criteria

- New Mailgun API key is active and listed in Mailgun Dashboard
- Supabase `MAILGUN_API_KEY` secret updated
- Both `send-adjuster-email` and `process-dunning` EFs redeployed
- Smoke test: test email delivered successfully
- Old API key revoked in Mailgun Dashboard
- No Mailgun delivery errors in EF logs for 5 minutes post-rotation

## Auto-resolve eligible: no

Manual verification required — Mailgun delivery failures are not always surfaced in Sentry immediately. Human sign-off on smoke test and email receipt is mandatory.

---

## Rollback

If rotation causes email delivery failures:

1. Re-add the old API key value to Supabase as `MAILGUN_API_KEY` (save it before rotation — see Step 2 note)
2. Redeploy both affected EFs
3. Verify smoke test passes (test email delivered)
4. Do **not** delete the old key from Mailgun until the root cause is diagnosed

> Mailgun allows multiple active API keys — you can hold the old key active during transition for zero-downtime rotation.

---

## See Also

- `SUPABASE-SECRETS-SETUP.md` — canonical Supabase secret names for Mailgun
- Postmortem: docusign-keypair-rotation-20260514 — source of this runbook gap
- Task 86e1d1hk4 — parent task for this runbook
- `runbooks/stripe-key-rotation.md` — parallel rotation runbook (same postmortem)

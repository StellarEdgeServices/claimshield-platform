# Runbook: Twilio Credential Rotation

**Type:** Credential rotation procedure  
**Applies to:** All environments  
**Last updated:** 2026-05-14 — Created per Postmortem A4 (docusign-keypair-rotation-20260514)

---

## When to Run This

- Twilio credentials are suspected to be compromised
- Routine security rotation (recommended: every 90 days)
- Any team member with access to the credentials departs
- Twilio account access is transferred or audited

---

## Env Vars Covered

| Supabase Secret Name | Description | Edge Functions |
|---|---|---|
| `TWILIO_ACCOUNT_SID` | Twilio account SID (`AC...`) | send-sms, process-dunning |
| `TWILIO_AUTH_TOKEN` | Twilio auth token | send-sms, process-dunning |
| `TWILIO_MESSAGING_SERVICE_SID` | Messaging Service SID (`MG...`) | send-sms, process-dunning |
| `TWILIO_PHONE_NUMBER` | Sending phone number (`+1...`) | send-sms |

> **Important:** `TWILIO_ACCOUNT_SID` and `TWILIO_PHONE_NUMBER` typically do not change during a credential rotation — only `TWILIO_AUTH_TOKEN` and potentially `TWILIO_MESSAGING_SERVICE_SID` change. However, all four must be verified in Supabase secrets to ensure consistency. A partial rotation (rotating `TWILIO_AUTH_TOKEN` alone) is sufficient in most cases.

---

## Tier A Steps (autonomous)

- Step 1: Check Twilio Console → Monitor → Logs for recent SMS delivery errors — if errors are present, diagnose before rotating
- Step 2: Check Sentry for `send-sms` and `process-dunning` error rates at current baseline

## Tier B Steps (execute + notify Dustin)

- Step 1: Rotate `TWILIO_AUTH_TOKEN` in Twilio Console, update Supabase secret, redeploy both EFs atomically
- Step 2: Run smoke test (trigger test SMS via `send-sms` EF); notify Dustin of result

## Tier C Steps (escalate)

- Step 1: If SMS delivery fails in production and rollback does not restore within 10 minutes, contact Twilio Support with Account SID and error details from logs

---

## Full Rotation Procedure

### 1. Partial vs. full rotation decision

| What changed | What to rotate |
|---|---|
| Suspected `AUTH_TOKEN` leak | `TWILIO_AUTH_TOKEN` only |
| Full account compromise | All four vars |
| Messaging Service replaced | `TWILIO_MESSAGING_SERVICE_SID` only |
| Phone number changed | `TWILIO_PHONE_NUMBER` only |

In most cases, only `TWILIO_AUTH_TOKEN` needs rotation.

### 2. Rotate credentials in Twilio Console

**For `TWILIO_AUTH_TOKEN`:**
1. Go to **Twilio Console → Account → General Settings**
2. Click **Rotate Auth Token** (or use the secondary auth token promote workflow)
3. Twilio provides a secondary token — promote it to primary, then copy the new primary token

**For `TWILIO_MESSAGING_SERVICE_SID`:**
1. Go to **Twilio Console → Messaging → Services**
2. Note the new Messaging Service SID if a new service was created

**For `TWILIO_PHONE_NUMBER`:**
1. Go to **Twilio Console → Phone Numbers → Active Numbers**
2. Note the new number in E.164 format (`+18448753412`)

### 3. ⚠️ Atomic update requirement

Both `send-sms` and `process-dunning` must be redeployed **together** after updating secrets. A partial redeploy where one EF has the new token and one has the old creates an authentication split — `process-dunning` uses Mailgun as its primary channel and Twilio as a fallback, so its failure mode is less severe, but `send-sms` failures are immediate and user-facing.

### 4. Update Supabase secrets

Go to **Supabase Dashboard → Project Settings → Edge Functions → Secrets** and update as needed:

| Secret Name | Action |
|---|---|
| `TWILIO_AUTH_TOKEN` | Replace with new token |
| `TWILIO_ACCOUNT_SID` | Update only if account changed |
| `TWILIO_MESSAGING_SERVICE_SID` | Update only if Messaging Service changed |
| `TWILIO_PHONE_NUMBER` | Update only if number changed |

Click **Save**.

### 5. Redeploy both Edge Functions atomically

Deploy both EFs in the same operation to prevent the auth-split failure mode:

```bash
supabase functions deploy send-sms --project-ref <project-ref>
supabase functions deploy process-dunning --project-ref <project-ref>
```

Or use the Supabase MCP `deploy_edge_function` tool for each.

### 6. Smoke test — trigger a test SMS via send-sms EF

```bash
curl -X POST https://<project-ref>.supabase.co/functions/v1/send-sms \
  -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "+1<your-test-number>",
    "body": "OtterQuote Twilio rotation smoke test — YYYY-MM-DD"
  }'
```

Expected: `{"success": true}` and SMS delivered within 60 seconds. A 401 from Twilio means the auth token was not saved correctly or the EF was not redeployed.

Check Twilio Console → Monitor → Logs to confirm the message was sent and delivered.

---

## Coordinated Rotation Notes

- **`process-dunning` fallback:** `process-dunning` uses Mailgun as its primary email channel and Twilio SMS as a fallback for failed email delivery. If SMS fails during a dunning cycle, payment reminders revert to email-only — this is degraded but not broken. Rotating during off-peak hours reduces risk.
- **Auth token promote workflow:** Twilio offers a two-token promote pattern (primary/secondary) that allows zero-downtime rotation. Use this if rotating during business hours with active SMS traffic.
- **`TWILIO_ACCOUNT_SID` is stable:** Account SIDs do not change unless the Twilio account itself is replaced. Do not rotate this unless explicitly required.

---

## Resolution Criteria

- Twilio Console shows the new auth token as active
- Supabase secrets updated for all rotated vars
- Both `send-sms` and `process-dunning` EFs redeployed
- Smoke test: test SMS delivered successfully
- Twilio Console → Monitor → Logs shows the test message as delivered (not just sent)
- No Twilio 401 errors in Sentry for 5 minutes post-rotation

## Auto-resolve eligible: no

Manual verification required — SMS delivery failures surface in Twilio logs but may not immediately appear in Sentry. Human sign-off on smoke test receipt is mandatory.

---

## Rollback

If rotation causes SMS delivery failures:

1. Re-enter the old `TWILIO_AUTH_TOKEN` in Supabase secrets (save it before rotation — see Step 2 above)
2. Redeploy both `send-sms` and `process-dunning`
3. Verify smoke test SMS is delivered
4. Do **not** revoke the old token in Twilio until root cause is diagnosed

> Twilio's two-token promote workflow keeps the old token valid until explicitly revoked — use this to maintain a rollback path during rotation.

---

## See Also

- `SUPABASE-SECRETS-SETUP.md` — canonical Supabase secret names for Twilio
- Postmortem: docusign-keypair-rotation-20260514 — source of this runbook gap
- Task 86e1d1hpm — parent task for this runbook
- `runbooks/stripe-key-rotation.md` — parallel rotation runbook (same postmortem)
- `runbooks/mailgun-key-rotation.md` — Mailgun rotation; coordinates with process-dunning

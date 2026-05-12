# Runbooks

On-call runbooks for OtterQuote. Each file maps to an alert type that the `on-call-bot` skill uses for automated triage.

## Naming Convention

```
runbooks/
├── auth-failure.md           — login or OAuth errors
├── onboarding-broken.md      — contractor onboarding flow errors
├── payment-error.md          — Stripe connect / charge errors
├── contracts-broken.md       — DocuSign envelope failures
├── edge-function-error.md    — Supabase Edge Function failures
├── site-down.md              — HTML/JS load failures
└── database-error.md         — Supabase query / RLS errors
```

## Runbook Format

Each runbook must follow this structure for `on-call-bot` to parse it correctly:

```markdown
# Runbook: {alert-name}

## When This Fires
{What condition triggers this alert}

## Tier A Steps (autonomous)
- Step 1: {action Claude executes immediately}

## Tier B Steps (execute + notify)
- Step 1: {action Claude executes, then notifies Dustin}

## Tier C Steps (escalate)
- Step 1: {what to escalate and to whom}

## Resolution Criteria
{How to verify the alert is resolved}

## Auto-resolve eligible: yes/no
{If yes, conditions under which to mark resolved}
```

## Coverage Policy

`on-call-bot` refuses to triage an alert without a corresponding runbook in this directory. If an alert fires and no runbook exists, `on-call-bot` creates a stub runbook and stops — forcing coverage before the next incident.

**Target:** Every alert that has fired in production gets a runbook within 24 hours of first occurrence.

## Related

- `Skills Output/on-call-bot-SKILL.md` — the skill that reads these runbooks
- `Scripts/ci-file-integrity.py` — integrity checks (does not apply to runbooks/)
- CTO-Operating-System.md §2 (On-call), §6 (Observability)

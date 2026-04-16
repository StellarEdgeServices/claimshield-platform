-- ============================================================================
-- OtterQuote Commission Reversal Trigger Migration
-- ============================================================================
-- Created: 2026-04-16
-- Version: v42
-- Depends on: v7-referral-system.sql, v36-recruit-system.sql,
--             v37-switch-contractor.sql, v40-commission-trigger.sql
--
-- Purpose:
--   Closes the residual half of Gap A flagged after Session 182. The v40
--   forward-write trigger sets $200 referrer + $50 recruiter on
--   payment_status='succeeded'. The switch-contractor Edge Function
--   (Session 168) sets payment_status='refunded' when a homeowner switches
--   contractors, but nothing walks the ledger back — so a refund leaves the
--   referrer dashboard overstating amounts owed. This migration introduces
--   the first and only automatic writer that ZEROES referrals.commission_amount
--   / recruit_commission_amount and decrements referral_agents.recruit_earnings.
--
-- Scope — what this trigger does NOT do (policy, per Dustin):
--   * It does NOT move money. `commission_paid_at` / `recruit_paid_at` are
--     the manual-control flags on actual payout, and this trigger never
--     touches them.
--   * It does NOT reverse commissions that were already paid out. If
--     `commission_paid_at IS NOT NULL` when a refund fires, the function
--     emits a RAISE LOG warning and no-ops so Dustin can decide whether to
--     claw back manually. Reversing a paid commission silently would move
--     the dashboard out of sync with cash that already left the account.
--
-- Semantics note — pairing with v40:
--   v40 writes the ledger entry on the transition INTO 'succeeded' for jobs
--   >= $10K. v42 reverses it on the transition INTO 'refunded'. The two
--   triggers are symmetric: same journal, opposite signs, same idempotency
--   contract. Double-reversal is a no-op (commission_amount already 0).
--   A refund on a quote that never had a referral is a no-op (no referral
--   row found). A refund on a quote whose job value was under the $10K
--   commission floor is a no-op for the same reason — v40 never wrote the
--   entry, so commission_amount is 0 and the idempotency guard fires.
--
-- Decision implemented: D-145 (new — see otterquote-reference.md)
-- ClickUp: (no existing task — log-only per session-archive)
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: FUNCTION — reverse_referral_commission()
-- ============================================================================
-- Fires inside the quote-refund transaction. Locates the referral row for
-- the refunded quote's claim, verifies the commission has NOT been paid out,
-- and reverses the ledger entries written by v40's apply_referral_commission.
--
-- SECURITY DEFINER so the function can update referrals / referral_agents
-- under the caller's JWT context (the switch-contractor Edge Function runs
-- with the homeowner's bearer token, which the referrals RLS policies would
-- otherwise block from updating someone else's referral row).
-- search_path is pinned to prevent search_path-based privilege escalation.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reverse_referral_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_referral      public.referrals%ROWTYPE;
  v_referrer      public.referral_agents%ROWTYPE;
  v_recruit_amt   DECIMAL(10,2);
BEGIN
  -- 1. Locate the referral via the quote's claim_id. A claim may have at
  --    most one referral attached (see v7 schema), so LIMIT 1 is defensive
  --    rather than necessary. If no referral exists for this claim, there
  --    is nothing to reverse — no-op.
  --
  --    FOR UPDATE locks the row against concurrent writers: the v40 forward
  --    trigger on a sibling quote's UPDATE can race with this reversal if a
  --    homeowner rapidly switches contractors (contract signed -> refunded
  --    -> re-signed). The lock forces serialization.
  SELECT * INTO v_referral
    FROM public.referrals
    WHERE claim_id = NEW.claim_id
    ORDER BY created_at ASC
    LIMIT 1
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- 2. Idempotency: if no commission was ever written (or a prior reversal
  --    already zeroed it), do not re-apply. Matches v40's symmetric guard.
  IF COALESCE(v_referral.commission_amount, 0) = 0 THEN
    RETURN NEW;
  END IF;

  -- 3. Safety rail: never silently reverse a commission that has already
  --    been paid out. The dashboard would lie about what was owed, and the
  --    real money has already left the account. RAISE LOG so the condition
  --    is visible in Supabase logs and Dustin can decide whether to
  --    manually claw back. Return NEW to leave the ledger intact.
  IF v_referral.commission_paid_at IS NOT NULL THEN
    RAISE LOG 'reverse_referral_commission: SKIPPING reversal — commission already paid. quote_id=% claim_id=% referral_id=% commission_amount=% commission_paid_at=% — FLAGGED FOR MANUAL REVIEW',
      NEW.id, NEW.claim_id, v_referral.id,
      v_referral.commission_amount, v_referral.commission_paid_at;
    RETURN NEW;
  END IF;

  -- 4. Capture the recruiter amount BEFORE the UPDATE zeroes it — we need
  --    the value to decrement the running recruit_earnings counter on the
  --    recruiter's referral_agents row. Default to 0 so arithmetic on NULL
  --    never produces NULL.
  v_recruit_amt := COALESCE(v_referral.recruit_commission_amount, 0);

  -- 5. If a recruiter tier was accrued, walk it back on the recruiter's
  --    running total. We load the referrer to get recruited_by_id — the
  --    recruiter's referral_agents row — then decrement by exactly the
  --    amount that was credited on the forward path (v40 writes $50;
  --    this decrements whatever was written, not a hardcoded $50, so the
  --    reversal stays correct if the amount ever changes). GREATEST(..., 0)
  --    guards against a NULL or negative running total turning into an
  --    implausible negative balance.
  IF v_recruit_amt > 0 THEN
    SELECT * INTO v_referrer
      FROM public.referral_agents
      WHERE id = v_referral.referral_agent_id;

    IF FOUND AND v_referrer.recruited_by_id IS NOT NULL THEN
      UPDATE public.referral_agents
         SET recruit_earnings = GREATEST(COALESCE(recruit_earnings, 0) - v_recruit_amt, 0)
       WHERE id = v_referrer.recruited_by_id;
    END IF;
  END IF;

  -- 6. Zero the referral ledger and step the status back from 'job_completed'
  --    to 'contract_signed' (the pre-completion state per the v7 enum:
  --    clicked -> registered -> claim_submitted -> bid_received ->
  --    contract_signed -> job_completed -> commission_paid). Guard the
  --    status reset with a CASE so we never walk back from a state that
  --    wasn't 'job_completed' in the first place — e.g., if a row was
  --    manually reconciled to some other state, leave it alone.
  UPDATE public.referrals
     SET commission_amount         = 0,
         recruit_commission_amount = 0,
         job_value                 = NULL,
         status                    = CASE
                                        WHEN status = 'job_completed'
                                          THEN 'contract_signed'
                                        ELSE status
                                      END
   WHERE id = v_referral.id;

  RETURN NEW;

EXCEPTION
  -- Never allow a reversal-side failure to roll back the refund itself.
  -- Refund integrity is primary; ledger accrual is best-effort and can be
  -- reconciled manually. Emit a Postgres LOG entry so the failure is
  -- visible in Supabase logs. Mirrors v40's exception handler exactly.
  WHEN OTHERS THEN
    RAISE LOG 'reverse_referral_commission failed for quote_id=% claim_id=% sqlstate=% sqlerrm=%',
      NEW.id, NEW.claim_id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.reverse_referral_commission() IS
'Trigger function attached to quotes AFTER UPDATE OF payment_status. On the transition NEW.payment_status=''refunded'', zeroes referrals.commission_amount and recruit_commission_amount, decrements referral_agents.recruit_earnings by the amount previously credited to the recruiter, and steps the referral status back from ''job_completed'' to ''contract_signed''. Does NOT touch commission_paid_at / recruit_paid_at — actual payouts remain manually controlled. Skips (with RAISE LOG) if commission_paid_at IS NOT NULL so already-paid commissions are flagged for manual clawback rather than silently reversed. Idempotent via commission_amount = 0 guard. SECURITY DEFINER; all reversal-side errors are swallowed and logged to protect refund integrity.';

-- ============================================================================
-- SECTION 2: TRIGGER — after_quote_refunded
-- ============================================================================
-- Fires exactly once per quote on the payment_status transition to
-- 'refunded'. The WHEN clause is the full gate:
--   * NEW.payment_status = 'refunded'   — only on the refunded state
--   * OLD IS DISTINCT FROM 'refunded'   — only on the transition INTO refunded,
--                                         never on a same-state update
--
-- Note: there is deliberately no $10K job-value guard here (unlike v40's
-- after_quote_paid trigger). A refund on a sub-$10K job will find
-- commission_amount = 0 and no-op via the function's idempotency guard,
-- so the WHEN clause does not need to repeat that filter. Keeping the
-- WHEN tight also means the trigger is not evaluated for routine
-- payment_status changes that do not transition into 'refunded'.
--
-- AFTER UPDATE OF payment_status restricts the trigger to updates that
-- actually touch payment_status — unrelated quote mutations never fire it.
-- ============================================================================
DROP TRIGGER IF EXISTS after_quote_refunded ON public.quotes;

CREATE TRIGGER after_quote_refunded
  AFTER UPDATE OF payment_status ON public.quotes
  FOR EACH ROW
  WHEN (
    NEW.payment_status = 'refunded'
    AND OLD.payment_status IS DISTINCT FROM 'refunded'
  )
  EXECUTE FUNCTION public.reverse_referral_commission();

COMMENT ON TRIGGER after_quote_refunded ON public.quotes IS
'Fires once per quote when payment_status transitions to refunded. Entry point for D-145 commission reversal. See reverse_referral_commission().';

-- ============================================================================
-- SECTION 3: INDEX — referrals.claim_id
-- ============================================================================
-- v7 indexed referral_agent_id and status but not claim_id. The v42 reversal
-- function does WHERE claim_id = NEW.claim_id on every refund, and the v40
-- trigger (which uses claims.referral_id -> referrals.id) does not exercise
-- this path so the missing index has been latent. Adding it now keeps the
-- reversal trigger from seq-scanning the referrals table on every refund.
-- IF NOT EXISTS makes re-apply safe.
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_referrals_claim_id
  ON public.referrals(claim_id);

COMMIT;

-- ============================================================================
-- SECTION 3: VERIFICATION QUERIES
-- ============================================================================
-- 3a. Confirm the function exists and is SECURITY DEFINER.
SELECT
  n.nspname               AS schema,
  p.proname               AS function_name,
  p.prosecdef             AS is_security_definer,
  pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'reverse_referral_commission';

-- 3b. Confirm the trigger exists and is attached to quotes.
SELECT
  tgname              AS trigger_name,
  tgrelid::regclass   AS table_name,
  tgenabled           AS enabled,
  pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE tgname = 'after_quote_refunded';

-- ============================================================================
-- End of Migration v42 — Commission Reversal Trigger
-- ============================================================================

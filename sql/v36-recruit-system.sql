-- ============================================================================
-- OtterQuote Recruit System Migration
-- ============================================================================
-- Created: 2026-04-15
-- Version: v36
-- NOTE: v35 is occupied by v35-admin-verification.sql
--
-- Purpose: Add two-tier commission system — referral partners can now recruit
--          other partners. When a recruited partner's referral completes a job
--          over $10K, the recruiter earns $50 and the referrer earns $200
--          (was $250 flat). One level deep only — no cascading.
--          Forward-only attribution — no retroactive credit.
--
-- Decisions implemented: D-139 through D-143
--
-- Modifications to existing tables:
--   - referral_agents: recruit_code, recruited_by_id, recruited_at,
--                      recruit_earnings, referred_by_note
--   - referrals:       recruit_commission_amount, recruit_paid_at
--
-- Functions:
--   - generate_recruit_code(): Generates 'r-' + 6-char alphanumeric codes
--   - referral_agents_generate_recruit_code(): Trigger function, auto-assigns
--
-- Triggers:
--   - referral_agents_generate_recruit_code: BEFORE INSERT on referral_agents
--
-- Indexes:
--   - idx_referral_agents_recruited_by  on referral_agents(recruited_by_id)
--   - idx_referral_agents_recruit_code  on referral_agents(recruit_code)
--
-- RLS:
--   - Existing "Agents can manage own profile" policy (v7) already covers
--     new columns via FOR ALL / user_id = auth.uid(). No new policy needed.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: NEW COLUMNS — referral_agents
-- ============================================================================

-- recruit_code: Used in otterquote.com/recruit/[code] links.
-- Prefixed with 'r-' (e.g., 'r-AB3X9K') so recruit codes are visually
-- distinguishable from referral codes (e.g., 'JOHNDOE1') at a glance.
ALTER TABLE public.referral_agents
  ADD COLUMN IF NOT EXISTS recruit_code TEXT UNIQUE;

COMMENT ON COLUMN public.referral_agents.recruit_code IS
'8-character unique recruit link code (format: r-XXXXXX) used in otterquote.com/recruit/[code] URLs. Auto-generated on INSERT by the referral_agents_generate_recruit_code trigger. Visually distinct from unique_code referral codes.';

-- recruited_by_id: FK to the referral_agents row that recruited this partner.
-- NULL = organic or direct signup. ON DELETE SET NULL preserves the recruited
-- partner's record if the recruiter is ever removed.
ALTER TABLE public.referral_agents
  ADD COLUMN IF NOT EXISTS recruited_by_id UUID
    REFERENCES public.referral_agents(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.referral_agents.recruited_by_id IS
'FK to referral_agents(id) — identifies who recruited this partner via a recruit link. NULL = organic or direct signup. ON DELETE SET NULL ensures removing a recruiter does not cascade to their recruited partners.';

-- recruited_at: Timestamp when the recruit relationship was established.
-- NULL if the partner joined organically (no recruit link used).
ALTER TABLE public.referral_agents
  ADD COLUMN IF NOT EXISTS recruited_at TIMESTAMPTZ;

COMMENT ON COLUMN public.referral_agents.recruited_at IS
'Timestamp when this partner completed signup via a recruit link, establishing the recruiter relationship. NULL if the partner signed up organically (recruited_by_id will also be NULL).';

-- recruit_earnings: Running total of $50 recruiter-tier payouts earned.
-- This is separate from total_commission_earned, which tracks referral
-- commissions only ($200 per qualified job).
ALTER TABLE public.referral_agents
  ADD COLUMN IF NOT EXISTS recruit_earnings DECIMAL(10,2) DEFAULT 0;

COMMENT ON COLUMN public.referral_agents.recruit_earnings IS
'Running total of recruiter-tier earnings — $50 per qualifying job completion by a recruited partner (job_value > $10,000). Separate from total_commission_earned, which tracks the referring partner''s $200 payout.';

-- referred_by_note: Free-text "Who told you about us?" field captured at
-- signup for manual attribution when no recruit link was used.
-- Informational only — does not affect commission logic.
ALTER TABLE public.referral_agents
  ADD COLUMN IF NOT EXISTS referred_by_note TEXT;

COMMENT ON COLUMN public.referral_agents.referred_by_note IS
'Free-text "Who told you about us?" answer captured at partner signup. Used for manual attribution when no recruit link was present. Stored for reference only — does not trigger recruit earnings logic.';

-- ============================================================================
-- SECTION 2: NEW COLUMNS — referrals
-- ============================================================================

-- recruit_commission_amount: The $50 recruiter payout for this specific referral.
-- Populated at job completion when (1) the referring partner has a non-NULL
-- recruited_by_id and (2) job_value > $10,000. Otherwise stays at 0.
ALTER TABLE public.referrals
  ADD COLUMN IF NOT EXISTS recruit_commission_amount DECIMAL(10,2) DEFAULT 0;

COMMENT ON COLUMN public.referrals.recruit_commission_amount IS
'Recruiter-tier commission ($50) attributed to this referral. Non-zero only when the referring partner was recruited (recruited_by_id IS NOT NULL) and job_value > $10,000. Paid to the recruiter, not the referrer.';

-- recruit_paid_at: When the recruiter was paid their $50 for this referral.
-- NULL until payment is confirmed.
ALTER TABLE public.referrals
  ADD COLUMN IF NOT EXISTS recruit_paid_at TIMESTAMPTZ;

COMMENT ON COLUMN public.referrals.recruit_paid_at IS
'Timestamp confirming payment of the $50 recruiter commission for this referral. NULL until the recruiter payout is processed and confirmed.';

-- ============================================================================
-- SECTION 3: FUNCTION — generate_recruit_code()
-- ============================================================================
-- Generates an 8-character recruit code: 'r-' prefix + 6 random uppercase
-- alphanumeric characters (A–Z, 0–9). Example output: 'r-AB3X9K'.
--
-- The 'r-' prefix ensures recruit codes cannot collide with referral codes
-- (which are 8 random alphanumeric chars with no prefix), and makes the
-- code's purpose immediately clear in logs, URLs, and support tickets.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.generate_recruit_code()
RETURNS TEXT AS $$
DECLARE
  code TEXT;
  chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  i INT := 0;
BEGIN
  code := 'r-';
  WHILE i < 6 LOOP
    code := code || substr(chars, (random() * length(chars))::INT + 1, 1);
    i := i + 1;
  END LOOP;
  RETURN code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.generate_recruit_code() IS
'Generates an 8-character recruit code with "r-" prefix followed by 6 random uppercase alphanumeric characters (A-Z, 0-9). Example: r-AB3X9K. Mirrors generate_referral_code() but targets the recruit_code column and uses a distinct prefix for visual differentiation.';

-- ============================================================================
-- SECTION 4: TRIGGER FUNCTION — referral_agents_generate_recruit_code()
-- ============================================================================
-- Auto-populates recruit_code on INSERT if not explicitly provided.
-- Uses a collision-safe loop — keeps generating until a unique code is found.
-- Mirrors the existing referral_agents_generate_code() trigger function.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.referral_agents_generate_recruit_code()
RETURNS TRIGGER AS $$
DECLARE
  code TEXT;
BEGIN
  IF NEW.recruit_code IS NULL THEN
    -- Keep generating until we get a unique code
    LOOP
      code := public.generate_recruit_code();
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.referral_agents WHERE recruit_code = code
      );
    END LOOP;
    NEW.recruit_code := code;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.referral_agents_generate_recruit_code() IS
'BEFORE INSERT trigger function that auto-generates a unique recruit_code for new referral_agents rows. Uses a collision-safe loop identical in structure to referral_agents_generate_code(), but targets the recruit_code column and calls generate_recruit_code().';

-- ============================================================================
-- SECTION 5: TRIGGER — referral_agents_generate_recruit_code
-- ============================================================================
DROP TRIGGER IF EXISTS referral_agents_generate_recruit_code
  ON public.referral_agents;

CREATE TRIGGER referral_agents_generate_recruit_code
  BEFORE INSERT ON public.referral_agents
  FOR EACH ROW
  EXECUTE FUNCTION public.referral_agents_generate_recruit_code();

-- ============================================================================
-- SECTION 6: BACKFILL — assign recruit_codes to existing rows
-- ============================================================================
-- Existing referral_agents rows will have recruit_code = NULL after the column
-- is added (ADD COLUMN with no DEFAULT). This block assigns a unique
-- recruit_code to each existing row using the same collision-safe logic as
-- the trigger. Forward-only: does not set recruited_by_id or recruited_at
-- for existing partners (no retroactive attribution per D-143).
-- ============================================================================
DO $$
DECLARE
  agent RECORD;
  code  TEXT;
BEGIN
  FOR agent IN
    SELECT id FROM public.referral_agents WHERE recruit_code IS NULL
    ORDER BY created_at ASC
  LOOP
    LOOP
      code := public.generate_recruit_code();
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.referral_agents WHERE recruit_code = code
      );
    END LOOP;

    UPDATE public.referral_agents
      SET recruit_code = code
      WHERE id = agent.id;
  END LOOP;
END;
$$;

-- ============================================================================
-- SECTION 7: INDEXES
-- ============================================================================

-- Supports lookups of all partners recruited by a given recruiter
-- (e.g., "show me everyone I've recruited" on the recruiter dashboard).
CREATE INDEX IF NOT EXISTS idx_referral_agents_recruited_by
  ON public.referral_agents(recruited_by_id);

-- Supports fast lookup when a partner signs up via an otterquote.com/recruit/[code] URL.
CREATE INDEX IF NOT EXISTS idx_referral_agents_recruit_code
  ON public.referral_agents(recruit_code);

-- ============================================================================
-- SECTION 8: RLS — recruit_code visibility
-- ============================================================================
-- The existing "Agents can manage own profile" policy from v7-referral-system.sql
-- is defined as FOR ALL with USING (user_id = auth.uid()), which already covers
-- SELECT on all columns — including the new recruit_code, recruited_by_id,
-- recruited_at, recruit_earnings, and referred_by_note columns.
--
-- No additional RLS policy is required. Authenticated partners can retrieve
-- their own recruit_code (to display their recruit link on the dashboard) via:
--
--   SELECT recruit_code FROM referral_agents WHERE user_id = auth.uid();
--
-- This is satisfied by the existing policy without modification.
-- ============================================================================

COMMIT;

-- ============================================================================
-- SECTION 9: VERIFICATION QUERY
-- ============================================================================
-- Run after applying migration to confirm all 7 new columns exist.
-- Expected result: 7 rows — 5 for referral_agents, 2 for referrals.
-- ============================================================================
SELECT
  table_name,
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   IN ('referral_agents', 'referrals')
  AND column_name  IN (
    'recruit_code',
    'recruited_by_id',
    'recruited_at',
    'recruit_earnings',
    'referred_by_note',
    'recruit_commission_amount',
    'recruit_paid_at'
  )
ORDER BY table_name, column_name;

-- ============================================================================
-- End of Migration v36 — Recruit System
-- ============================================================================

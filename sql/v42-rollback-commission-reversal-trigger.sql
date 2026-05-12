-- Rollback for v42-commission-reversal-trigger.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_referrals_claim_id;

-- Drop trigger created by this migration
DROP TRIGGER IF EXISTS after_quote_refunded ON quotes;

-- Drop function created by this migration
DROP FUNCTION IF EXISTS reverse_referral_commission() CASCADE;

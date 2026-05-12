-- Rollback for v40-commission-trigger.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop trigger created by this migration
DROP TRIGGER IF EXISTS after_quote_paid ON quotes;

-- Drop function created by this migration
DROP FUNCTION IF EXISTS apply_referral_commission() CASCADE;

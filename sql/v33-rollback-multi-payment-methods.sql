-- Rollback for v33-multi-payment-methods.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS contractor_payment_methods CASCADE;

-- Drop columns added by this migration
ALTER TABLE quotes DROP COLUMN IF EXISTS payment_method_id CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS payment_method_type CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS card_fee_cents CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_cpm_stripe_pm_id;
DROP INDEX IF EXISTS idx_cpm_contractor_id;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE contractor_payment_methods DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM contractor_payment_methods;  -- REVIEW BEFORE RUNNING

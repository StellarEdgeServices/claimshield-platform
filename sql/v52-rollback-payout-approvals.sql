-- Rollback for v52-payout-approvals.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS payout_approvals CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_payout_approvals_reminder;
DROP INDEX IF EXISTS idx_payout_approvals_created_at;
DROP INDEX IF EXISTS idx_payout_approvals_auto_approve_at;
DROP INDEX IF EXISTS idx_payout_approvals_referral_id;
DROP INDEX IF EXISTS idx_payout_approvals_partner_id;
DROP INDEX IF EXISTS idx_payout_approvals_status;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS apply_referral_commission() CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE payout_approvals DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM payout_approvals;  -- REVIEW BEFORE RUNNING
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

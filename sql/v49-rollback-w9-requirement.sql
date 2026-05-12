-- Rollback for v49-w9-requirement.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE referral_agents DROP COLUMN IF EXISTS w9_file_url CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS w9_submitted_at CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS w9_verified_at CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS payments_blocked CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS w9_notification_sent_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_referral_agents_payments_blocked;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS apply_referral_commission() CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

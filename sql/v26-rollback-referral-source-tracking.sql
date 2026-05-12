-- Rollback for v26-referral-source-tracking.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS referral_source CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS referral_agent_id CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_referral_agent_id;
DROP INDEX IF EXISTS idx_claims_referral_source;

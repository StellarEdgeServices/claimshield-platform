-- Rollback for v7-referral-system.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS referrals CASCADE;
DROP TABLE IF EXISTS referral_agents CASCADE;

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS referral_code CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_referral_code;
DROP INDEX IF EXISTS idx_referrals_status;
DROP INDEX IF EXISTS idx_referrals_referral_agent_id;
DROP INDEX IF EXISTS idx_referral_agents_agent_type;
DROP INDEX IF EXISTS idx_referral_agents_email;
DROP INDEX IF EXISTS idx_referral_agents_unique_code;

-- Drop triggers created by this migration

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS referral_agents_generate_code() CASCADE;
DROP FUNCTION IF EXISTS update_referral_stats() CASCADE;
DROP FUNCTION IF EXISTS generate_referral_code() CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE referral_agents DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE referrals DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

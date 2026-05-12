-- Rollback for v36-recruit-system.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE referral_agents DROP COLUMN IF EXISTS recruit_code CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS recruited_by_id CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS recruited_at CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS recruit_earnings CASCADE;
ALTER TABLE referral_agents DROP COLUMN IF EXISTS referred_by_note CASCADE;
ALTER TABLE referrals DROP COLUMN IF EXISTS recruit_commission_amount CASCADE;
ALTER TABLE referrals DROP COLUMN IF EXISTS recruit_paid_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_referral_agents_recruit_code;
DROP INDEX IF EXISTS idx_referral_agents_recruited_by;

-- Drop triggers created by this migration
DROP TRIGGER IF EXISTS referral_agents_generate_recruit_code ON referral_agents;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS referral_agents_generate_recruit_code() CASCADE;
DROP FUNCTION IF EXISTS generate_recruit_code() CASCADE;

-- Rollback for v15-carrier-adjuster-kb.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS adjusters CASCADE;
DROP TABLE IF EXISTS carrier_profiles CASCADE;

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_name CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_email CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_phone CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS carrier_id CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_carrier_profiles_name;
DROP INDEX IF EXISTS idx_adjusters_carrier;
DROP INDEX IF EXISTS idx_adjusters_name;
DROP INDEX IF EXISTS idx_adjusters_email;
DROP INDEX IF EXISTS idx_claims_carrier;
DROP INDEX IF EXISTS idx_claims_adjuster;

-- Drop triggers created by this migration

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS upsert_adjuster_from_claim(text, text, text, uuid) CASCADE;

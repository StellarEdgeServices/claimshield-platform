-- Rollback for v4-dashboard-fixes.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS estimate_filename CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS measurements_filename CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS date_of_loss CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS damage_type CASCADE;

-- Drop triggers created by this migration
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM profiles;  -- REVIEW BEFORE RUNNING

-- Rollback for v3-role-auth-migration.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE profiles DROP COLUMN IF EXISTS role CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_profiles_role;

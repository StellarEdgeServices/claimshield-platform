-- Rollback for v9-policy-type.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS policy_type CASCADE;

-- Rollback for v51-cpa-version.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS cpa_version CASCADE;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS record_cpa_ip(uuid) CASCADE;

-- Rollback for v25-two-document-flow.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS project_confirmation CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS color_confirmation_template CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_project_confirmation;

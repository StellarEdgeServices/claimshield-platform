-- Rollback for v28-contractor-onboarding-hardening.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS agreement_accepted_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS agreement_version CASCADE;

-- Drop constraints added by this migration
ALTER TABLE contractors DROP CONSTRAINT IF EXISTS contractors_status_check;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_contractors_status;
DROP INDEX IF EXISTS idx_contractors_agreement_accepted_at;

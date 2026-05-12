-- Rollback for v53-switch-reason-survey.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS switch_reason_survey CASCADE;

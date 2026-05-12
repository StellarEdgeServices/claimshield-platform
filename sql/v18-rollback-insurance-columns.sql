-- Rollback for v18-insurance-columns.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS has_workers_comp CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS has_general_liability CASCADE;

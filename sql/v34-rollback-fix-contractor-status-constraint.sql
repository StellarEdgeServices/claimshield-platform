-- Rollback for v34-fix-contractor-status-constraint.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop constraints added by this migration
ALTER TABLE contractors DROP CONSTRAINT IF EXISTS contractors_status_check;

-- Rollback for v55-hover-material-list.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE hover_orders DROP COLUMN IF EXISTS material_list CASCADE;

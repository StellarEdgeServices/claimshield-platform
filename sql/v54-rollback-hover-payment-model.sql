-- Rollback for v54-hover-payment-model.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE hover_orders DROP COLUMN IF EXISTS homeowner_charge_amount CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_hover_orders_rebate_due;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM platform_settings;  -- REVIEW BEFORE RUNNING

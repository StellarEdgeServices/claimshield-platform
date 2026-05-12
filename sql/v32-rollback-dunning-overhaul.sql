-- Rollback for v32-dunning-overhaul.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS timezone CASCADE;
ALTER TABLE payment_failures DROP COLUMN IF EXISTS contractor_timezone CASCADE;
ALTER TABLE payment_failures DROP COLUMN IF EXISTS warning_at CASCADE;
ALTER TABLE payment_failures DROP COLUMN IF EXISTS homeowner_notify_at CASCADE;

-- Drop constraints added by this migration
ALTER TABLE payment_failures DROP CONSTRAINT IF EXISTS payment_failures_dunning_status_check;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_payment_failures_warning_sent;
DROP INDEX IF EXISTS idx_payment_failures_active;

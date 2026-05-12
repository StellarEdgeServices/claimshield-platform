-- Rollback for v37-switch-contractor.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS contractor_switched_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS contractor_switch_count CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS cancelled_at CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS cancellation_reason CASCADE;

-- Drop constraints added by this migration
ALTER TABLE quotes DROP CONSTRAINT IF EXISTS quotes_payment_status_check;

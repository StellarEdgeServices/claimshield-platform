-- Rollback for v31-payment-dunning.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS payment_failures CASCADE;

-- Drop columns added by this migration
ALTER TABLE quotes DROP COLUMN IF EXISTS payment_intent_id CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS payment_status CASCADE;

-- Drop constraints added by this migration
ALTER TABLE quotes DROP CONSTRAINT IF EXISTS quotes_payment_status_check;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_quotes_payment_intent;
DROP INDEX IF EXISTS idx_payment_failures_contractor;
DROP INDEX IF EXISTS idx_payment_failures_active;

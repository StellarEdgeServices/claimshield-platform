-- Rollback for v29-rate-limit-alerts.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE rate_limit_config DROP COLUMN IF EXISTS alert_sent_month CASCADE;

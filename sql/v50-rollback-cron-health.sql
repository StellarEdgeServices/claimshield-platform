-- Rollback for v50-cron-health.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop table created by this migration (CASCADE removes indexes, policies)
DROP TABLE IF EXISTS cron_health CASCADE;

-- Drop function created by this migration
DROP FUNCTION IF EXISTS record_cron_health(text, text, text) CASCADE;

-- Unschedule pg_cron jobs created by this migration
-- (None in this migration -- pg_cron entries added separately)

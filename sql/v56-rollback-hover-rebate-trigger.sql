-- Rollback for v56-hover-rebate-trigger.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS notify_hover_rebate() CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

-- Unschedule pg_cron jobs created by this migration
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'process-hover-rebate-scan'; -- safe: no-op if job absent

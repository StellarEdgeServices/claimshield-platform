-- Rollback for v44-siding-bid-release.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS siding_bid_released_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_siding_pending_release;

-- Unschedule pg_cron jobs created by this migration
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'check-siding-design-completion'; -- safe: no-op if job absent

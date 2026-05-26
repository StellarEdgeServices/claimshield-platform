-- v81 rollback: remove process-auto-bids pg_cron schedule
-- Does NOT remove the Edge Function itself — undeploy separately via CLI if needed
-- Does NOT reverse any auto-bids already submitted (quotes are immutable once submitted)

SELECT cron.unschedule('process-auto-bids');

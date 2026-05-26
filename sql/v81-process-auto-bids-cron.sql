-- v81: D-093 process-auto-bids pg_cron schedule
-- Runs every 5 minutes; invokes process-auto-bids Edge Function via net.http_post
-- Auth: passes SUPABASE_SERVICE_ROLE_KEY as Bearer token (accepted by EF auth check)
-- Companion rollback: sql/v81r-process-auto-bids-cron-rollback.sql
--
-- DEPLOY NOTE: Replace [SUPABASE_SERVICE_ROLE_KEY] below with the actual
-- service role key value before running. Pattern matches v50a (process-coi-reminders).
-- cron.schedule() is upsert-safe: updates if named job already exists.

SELECT cron.schedule(
  'process-auto-bids',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://yeszghaspzwwstvsrioa.supabase.co/functions/v1/process-auto-bids',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer [SUPABASE_SERVICE_ROLE_KEY]'
      ),
      body    := '{}'::jsonb
    ) AS request_id;
  $$
);

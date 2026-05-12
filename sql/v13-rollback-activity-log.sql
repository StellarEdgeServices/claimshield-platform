-- Rollback for v13-activity-log.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS activity_log CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_activity_log_user_created;
DROP INDEX IF EXISTS idx_activity_log_created_at;
DROP INDEX IF EXISTS idx_activity_log_user_id;

-- Drop triggers created by this migration
DROP TRIGGER IF EXISTS trg_log_bid_accepted ON quotes;
DROP TRIGGER IF EXISTS trg_log_bid_submitted ON quotes;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS log_bid_accepted() CASCADE;
DROP FUNCTION IF EXISTS log_bid_submitted() CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE activity_log DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM activity_log;  -- REVIEW BEFORE RUNNING

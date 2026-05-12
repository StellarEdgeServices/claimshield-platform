-- Rollback for v52-platform-monitoring.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS platform_alerts_log CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_platform_alerts_function;
DROP INDEX IF EXISTS idx_platform_alerts_unacked;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS acknowledge_alert(uuid) CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE platform_alerts_log DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

-- Rollback for v3-rate-limits.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS rate_limit_config CASCADE;
DROP TABLE IF EXISTS rate_limits CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_rate_limits_function_caller;
DROP INDEX IF EXISTS idx_rate_limits_created_at;
DROP INDEX IF EXISTS idx_rate_limit_config_function;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS cleanup_old_rate_limits() CASCADE;
DROP FUNCTION IF EXISTS check_rate_limit(text, uuid) CASCADE;

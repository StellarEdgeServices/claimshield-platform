-- Rollback for v6-hover-tokens.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS hover_tokens CASCADE;

-- Drop columns added by this migration
ALTER TABLE hover_orders DROP COLUMN IF EXISTS capture_request_id CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_hover_orders_hover_job_id;
DROP INDEX IF EXISTS idx_hover_orders_capture_request_id;

-- Drop triggers created by this migration

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS update_hover_tokens_updated_at() CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE hover_tokens DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

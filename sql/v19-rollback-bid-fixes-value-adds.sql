-- Rollback for v19-bid-fixes-value-adds.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE quotes DROP COLUMN IF EXISTS value_adds CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS auto_bid_value_adds CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_contractors_auto_bid_value_adds;
DROP INDEX IF EXISTS idx_quotes_value_adds;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS log_bid_submitted() CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM activity_log;  -- REVIEW BEFORE RUNNING

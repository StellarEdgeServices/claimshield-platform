-- Rollback for v17-loss-sheet-parser.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS parsed_line_items CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_parsed_line_items;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

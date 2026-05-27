-- =============================================================================
-- v82: Drop 4 orphaned Phase 2 scaffolding tables
-- =============================================================================
-- Verified 2026-05-26 (ARCHITECT tasks 86e1fwddx + 86e1fwdh2):
--   documents:           0 rows, 0 JS/TS/HTML references
--   job_assignments:     0 rows, 0 JS/TS/HTML references
--   inspection_bookings: 0 rows, 0 JS/TS/HTML references
--   claim_trade_items:   0 rows, 0 JS/TS/HTML references
--
-- CTO ruling 2026-05-26: All four are Phase 2 scaffolding with no active
-- feature dependency. Safe to drop in a single migration.
--
-- Rollback: sql/v82r-drop-orphaned-tables-rollback.sql
-- ClickUp:  86e1jkar2
-- Note:     v83 (public_directory_optin) was applied before this migration
--           was executed. Supabase orders by timestamp, not name.
-- =============================================================================

DROP TABLE IF EXISTS claim_trade_items;
DROP TABLE IF EXISTS documents;
DROP TABLE IF EXISTS inspection_bookings;
DROP TABLE IF EXISTS job_assignments;
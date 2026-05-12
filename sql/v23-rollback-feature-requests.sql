-- Rollback for v23-feature-requests.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS feature_requests CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE feature_requests DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

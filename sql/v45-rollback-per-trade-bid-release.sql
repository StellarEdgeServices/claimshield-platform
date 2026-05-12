-- Rollback for v45-per-trade-bid-release.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS roofing_bid_released_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claims_windows_pending_release;
DROP INDEX IF EXISTS idx_claims_gutters_pending_release;
DROP INDEX IF EXISTS idx_claims_roofing_pending_release;

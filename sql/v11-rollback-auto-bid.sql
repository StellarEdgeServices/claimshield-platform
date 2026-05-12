-- Rollback for v11-auto-bid.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS auto_bid_enabled CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS auto_bid_settings CASCADE;

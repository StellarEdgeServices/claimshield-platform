-- Rollback for v48-bid-expiration.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE quotes DROP COLUMN IF EXISTS expires_at CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS auto_renew CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS renewed_from_quote_id CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS expired_at CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS bid_status CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS default_auto_renew CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS bid_window_expires_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS bid_window_notified_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_quotes_claim_id_bid_status;
DROP INDEX IF EXISTS idx_quotes_renewed_from;
DROP INDEX IF EXISTS idx_claims_bid_window_expires_at;
DROP INDEX IF EXISTS idx_quotes_expiry_active;

-- Drop triggers created by this migration
DROP TRIGGER IF EXISTS trg_enforce_bid_window_expiry ON quotes;
DROP TRIGGER IF EXISTS trg_set_bid_window_on_first_bid ON quotes;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS enforce_bid_window_expiry() CASCADE;
DROP FUNCTION IF EXISTS set_bid_window_on_first_bid() CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

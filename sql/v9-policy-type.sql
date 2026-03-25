-- =============================================================================
-- OtterQuote v9 Migration: Insurance Policy Type (RCV/ACV)
-- Adds policy_type column to claims table to track whether homeowner has
-- Replacement Cost Value or Actual Cash Value coverage.
-- Run via: Supabase SQL Editor or CLI
-- =============================================================================

-- Policy type: RCV, ACV, or unknown (homeowner selected "I don't know")
ALTER TABLE claims ADD COLUMN IF NOT EXISTS policy_type text
  CHECK (policy_type IN ('rcv', 'acv', 'idk'));

-- Add comment for documentation
COMMENT ON COLUMN claims.policy_type IS 'Insurance policy type: rcv (replacement cost value), acv (actual cash value), idk (homeowner unsure). NULL for cash/retail jobs.';

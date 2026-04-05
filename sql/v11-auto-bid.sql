-- v11: Auto-Bid Settings for Insurance Roofing
-- Run in Supabase SQL Editor
-- Session 41, April 5, 2026

-- Add auto-bid columns to contractors table
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS auto_bid_enabled BOOLEAN DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS auto_bid_settings JSONB DEFAULT '{"funding_type": "insurance", "scope": "full_replacement", "trade": "roofing", "pricing": "rcv"}'::jsonb;

-- Remove color_selection_enabled (no longer a contractor toggle — colors are homeowner-driven)
-- Keeping the column for now in case existing data needs migration, but it's no longer used by the UI.
-- ALTER TABLE contractors DROP COLUMN IF EXISTS color_selection_enabled;

COMMENT ON COLUMN contractors.auto_bid_enabled IS 'When true, OtterQuote automatically bids on matching opportunities for this contractor';
COMMENT ON COLUMN contractors.auto_bid_settings IS 'JSON config: {funding_type, scope, trade, pricing}. Currently only insurance/full_replacement/roofing/rcv supported.';

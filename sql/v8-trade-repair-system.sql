-- =============================================================================
-- OtterQuote v8 Migration: Trade Selection, Repair Flow & Inspection Bookings
-- Decisions: D-097 (trade selector), D-098 (funding requirements), D-099 (bundled bids),
--            D-100 (repair flow), D-101 (inspection scheduling), D-102 (repair monetization)
-- Run via: Supabase SQL Editor or CLI
-- =============================================================================

-- ============================================================================
-- SECTION 1: ALTER TABLE claims - Add trade selection and repair fields
-- ============================================================================

-- Funding type: indicates whether claim is insurance-backed or cash/retail
ALTER TABLE claims ADD COLUMN IF NOT EXISTS funding_type text
  CHECK (funding_type IN ('insurance', 'cash'));

-- Array of selected trade types (roofing, siding, gutters, windows, etc.)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS trades text[] DEFAULT '{}';

-- ============================================================================
-- SECTION 2: Repair-specific tracking (for roofing, siding, and other repairs)
-- ============================================================================

-- Type of repair issue detected or reported
ALTER TABLE claims ADD COLUMN IF NOT EXISTS repair_type text
  CHECK (repair_type IN ('leak', 'blown_off', 'other'));

-- Detailed description of the repair issue
ALTER TABLE claims ADD COLUMN IF NOT EXISTS repair_description text;

-- Approximate number of missing/damaged shingles (for roofing repairs)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS repair_shingle_count integer;

-- Age of roof/siding in years (helps assess scope of work)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS roof_age_years integer;

-- ============================================================================
-- SECTION 3: Material identification tracking
-- ============================================================================

-- How material was identified (from paperwork, leftover samples, AI photo analysis, etc.)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS material_id_method text
  CHECK (material_id_method IN ('paperwork', 'leftover', 'ai_photo', 'itel', 'inspection'));

-- Status of material identification process
ALTER TABLE claims ADD COLUMN IF NOT EXISTS material_id_status text
  CHECK (material_id_status IN ('pending', 'identified', 'submitted', 'completed'))
  DEFAULT 'pending';

-- Reference to ITEL (integrated testing/lab) order for material matching
ALTER TABLE claims ADD COLUMN IF NOT EXISTS itel_order_id text;

-- Status of ITEL order (pending, completed)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS itel_status text
  CHECK (itel_status IN ('pending', 'completed'));

-- AI confidence score for AI-based material identification (0-100 scale)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS ai_id_confidence numeric(5,2);

-- ============================================================================
-- SECTION 4: Multi-trade intent tracking
-- ============================================================================

-- JSON array storing trade-specific intents for claims spanning multiple trades
-- Example: [{"trade": "roofing", "intent": "replace"}, {"trade": "gutters", "intent": "repair"}]
-- Allows different intents per trade in bundled claims
ALTER TABLE claims ADD COLUMN IF NOT EXISTS trade_intents jsonb DEFAULT '[]';

-- ============================================================================
-- SECTION 5: ALTER TABLE quotes - Add trade type and bundled bid support
-- ============================================================================

-- Trade type covered by this quote (roofing, siding, gutters, windows)
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS trade_type text
  CHECK (trade_type IN ('roofing', 'siding', 'gutters', 'windows'));

-- Flag indicating if this bid covers multiple trades bundled together
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS is_bundled_bid boolean DEFAULT false;

-- Array of trades included in a bundled bid
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS bundled_trades text[] DEFAULT '{}';

-- JSON breakdown of pricing per trade for bundled bids
-- Example: {"roofing": 12000, "gutters": 2000, "siding": 8500}
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS per_trade_breakdown jsonb;

-- ============================================================================
-- SECTION 6: CREATE TABLE inspection_bookings
-- ============================================================================
-- Manages inspection scheduling, confirmation, and fee tracking
-- Supports inspection guarantees and contractor penalties

CREATE TABLE IF NOT EXISTS inspection_bookings (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,

  -- Foreign keys
  claim_id uuid NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
  contractor_id uuid REFERENCES contractors(id),
  homeowner_id uuid NOT NULL REFERENCES auth.users(id),

  -- Scheduling information
  scheduled_date date NOT NULL,
  scheduled_time text NOT NULL, -- e.g., 'morning', 'afternoon', '10:00', '2:30pm'

  -- Booking status lifecycle
  status text DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'confirmed', 'completed', 'no_show', 'cancelled')),

  -- Inspection type and fee tracking
  inspection_type text
    CHECK (inspection_type IN ('free', 'credited', 'flat')),
  inspection_fee numeric(10,2) DEFAULT 0,

  -- Guarantee and penalty tracking for no-shows
  homeowner_guarantee_paid boolean DEFAULT false,
  contractor_penalty_charged boolean DEFAULT false,

  -- Additional notes
  notes text,

  -- Timestamps
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ============================================================================
-- SECTION 7: CREATE INDEXES for inspection_bookings
-- ============================================================================
-- Improves query performance for common lookups

CREATE INDEX IF NOT EXISTS idx_inspection_bookings_claim
  ON inspection_bookings(claim_id);

CREATE INDEX IF NOT EXISTS idx_inspection_bookings_contractor
  ON inspection_bookings(contractor_id);

CREATE INDEX IF NOT EXISTS idx_inspection_bookings_date
  ON inspection_bookings(scheduled_date);

-- ============================================================================
-- SECTION 8: ROW LEVEL SECURITY (RLS) for inspection_bookings
-- ============================================================================

-- Enable RLS to enforce data access control at row level
ALTER TABLE inspection_bookings ENABLE ROW LEVEL SECURITY;

-- Policy: Homeowners can only view their own inspection bookings
CREATE POLICY "Homeowners can view own bookings" ON inspection_bookings
  FOR SELECT
  USING (auth.uid() = homeowner_id);

-- Policy: Homeowners can create new bookings
CREATE POLICY "Homeowners can create bookings" ON inspection_bookings
  FOR INSERT
  WITH CHECK (auth.uid() = homeowner_id);

-- Policy: Contractors can view bookings assigned to them
CREATE POLICY "Contractors can view assigned bookings" ON inspection_bookings
  FOR SELECT
  USING (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- Policy: Contractors can update status of bookings assigned to them
CREATE POLICY "Contractors can update assigned bookings" ON inspection_bookings
  FOR UPDATE
  USING (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- This migration adds comprehensive trade selection, repair flow tracking,
-- material identification workflows, and inspection booking management.
-- All new columns use IF NOT EXISTS and IF NOT EXISTS on tables for safety.
-- =============================================================================

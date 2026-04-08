-- ============================================================
-- OtterQuote v14 Migration — Contractor Address & Profile Columns
-- Adds columns referenced in auth.js contractor join flow
-- that were never added via migration.
-- ============================================================
-- Run in Supabase SQL Editor (or already run via Management API)
-- Date: April 6, 2026
-- ============================================================

-- These columns are used by auth.js lines 207-213 during contractor signup
-- and by contractor-join.html during the onboarding form submission.
-- They were referenced in code but never existed in the database,
-- causing silent insert failures (PostgREST ignores unknown columns).

ALTER TABLE contractors ADD COLUMN IF NOT EXISTS address_line1 TEXT;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS address_city TEXT;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS address_state TEXT DEFAULT 'IN';
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS address_zip TEXT;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS website_url TEXT;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS num_employees TEXT;

-- years_in_business was already referenced in auth.js but may or may not
-- exist depending on the original CREATE TABLE. Adding IF NOT EXISTS to be safe.
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS years_in_business INTEGER;

-- ============================================================
-- DONE. Added 7 columns to contractors table.
-- These were already being sent by the frontend but silently
-- dropped by PostgREST because the columns didn't exist.
-- ============================================================

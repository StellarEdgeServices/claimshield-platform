-- ──────────────────────────────────────────────────────────────────────────────
-- v18 — Insurance columns + auth.js contractor signup fixes
-- Applied: April 8, 2026 (Session 74 — E2E test)
-- Method: Applied directly via Supabase Management API (not supabase CLI)
-- ──────────────────────────────────────────────────────────────────────────────

-- Add insurance flag columns to contractors table
-- These were missing and caused contractor-about.html to error on page load
-- (Supabase returned error code 42703 "column does not exist", causing the entire
--  Promise.all data load to fail and leaving contractor = null → "Contractor Not Found")

ALTER TABLE contractors ADD COLUMN IF NOT EXISTS has_workers_comp BOOLEAN DEFAULT false;
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS has_general_liability BOOLEAN DEFAULT false;

-- ──────────────────────────────────────────────────────────────────────────────
-- NOTES ON RELATED auth.js FIXES (also applied in Session 74)
-- ──────────────────────────────────────────────────────────────────────────────
-- 1. contractor_licenses.contractor_id fix:
--    auth.js was inserting contractor licenses with contractor_id = user.id (auth UUID),
--    but contractor_licenses.contractor_id REFERENCES contractors(id) (the table PK,
--    a different UUID). Fixed to use the newly inserted contractor record's id.
--
-- 2. Missing signup fields:
--    auth.js contractor INSERT was missing: service_counties, trades (stored as
--    trade_types in localStorage), preferred_brands (stored as shingle_brands in
--    localStorage), has_workers_comp, has_general_liability.
--    All are now saved to the contractor record on first login after signup.
--
-- 3. Auth.requireAuth() role enforcement:
--    requireAuth('contractor') was not enforcing the role — it only checked if
--    the user was authenticated. Fixed to redirect homeowners away from contractor
--    pages and vice versa.
-- ──────────────────────────────────────────────────────────────────────────────

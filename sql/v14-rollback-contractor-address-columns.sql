-- Rollback for v14-contractor-address-columns.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS address_line1 CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS address_city CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS address_state CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS address_zip CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS website_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS num_employees CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS years_in_business CASCADE;

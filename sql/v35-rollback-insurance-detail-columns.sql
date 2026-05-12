-- Rollback for v35-insurance-detail-columns.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS gl_carrier CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS gl_policy_number CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS gl_coverage_amount CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS gl_expiration_date CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS wc_carrier CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS wc_policy_number CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS wc_coverage_amount CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS wc_expiration_date CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS gallery_photo_urls CASCADE;
ALTER TABLE contractor_licenses DROP COLUMN IF EXISTS expiration_date CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:

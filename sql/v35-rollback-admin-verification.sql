-- Rollback for v35-admin-verification.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS admin_notes CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS license_verified CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS license_verified_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS insurance_verified CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS insurance_verified_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS insurance_verification_sent_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS insurance_verification_email CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS approved_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS rejected_at CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS rejection_reason CASCADE;

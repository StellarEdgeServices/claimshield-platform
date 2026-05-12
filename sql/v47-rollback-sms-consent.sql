-- Rollback for v47-sms-consent.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE profiles DROP COLUMN IF EXISTS sms_consent_ts CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS sms_consent_ts CASCADE;

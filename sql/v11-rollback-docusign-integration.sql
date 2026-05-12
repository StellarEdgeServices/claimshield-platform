-- Rollback for v11-docusign-integration.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS contract_pdf_url CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS docusign_envelope_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS color_confirmation_envelope_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS contract_sent_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS contract_signed_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS contract_signed_by CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS selected_contractor_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS selected_bid_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_collected CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_collected_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS homeowner_name CASCADE;

-- Drop constraints added by this migration
ALTER TABLE claims DROP CONSTRAINT IF EXISTS claims_selected_contractor_id_fkey;

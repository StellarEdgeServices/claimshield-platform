-- ============================================================
-- OtterQuote v11 Migration — DocuSign Integration
-- Adds contract template storage, DocuSign envelope tracking,
-- and signing-related columns.
-- ============================================================
-- Run in Supabase SQL Editor
-- Date: April 5, 2026
-- ============================================================

-- 1. Add contract_pdf_url to contractors (stores the uploaded contract template URL)
ALTER TABLE contractors ADD COLUMN IF NOT EXISTS contract_pdf_url TEXT;

-- 2. Add DocuSign / signing columns to claims (IF NOT EXISTS for safety)
ALTER TABLE claims ADD COLUMN IF NOT EXISTS docusign_envelope_id TEXT;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS color_confirmation_envelope_id TEXT;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS contract_sent_at TIMESTAMPTZ;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS contract_signed_at TIMESTAMPTZ;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS contract_signed_by TEXT;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS selected_contractor_id UUID;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS selected_bid_amount NUMERIC;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS deductible_collected BOOLEAN DEFAULT false;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS deductible_collected_at TIMESTAMPTZ;
ALTER TABLE claims ADD COLUMN IF NOT EXISTS homeowner_name TEXT;

-- 3. Add FK constraint for selected_contractor_id if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'claims_selected_contractor_id_fkey'
        AND table_name = 'claims'
    ) THEN
        ALTER TABLE claims ADD CONSTRAINT claims_selected_contractor_id_fkey
            FOREIGN KEY (selected_contractor_id) REFERENCES contractors(id);
    END IF;
END
$$;

-- ============================================================
-- NOTE: Storage bucket "contractor-templates" must be created
-- manually in Supabase Dashboard → Storage → New Bucket:
--   Name: contractor-templates
--   Public: OFF
--   File size limit: 10MB
--   Allowed MIME types: application/pdf
--
-- Then add RLS policies via Dashboard:
--   - Contractors can upload to their own folder (INSERT)
--   - Contractors can read their own folder (SELECT)
--   - Service role has full access (ALL)
-- ============================================================

-- ============================================================
-- DONE. Changes:
-- Modified: contractors (1 new column: contract_pdf_url)
-- Modified: claims (10 new columns for DocuSign and signing)
-- Manual step: Create contractor-templates storage bucket
-- ============================================================

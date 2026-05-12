-- Rollback for v5-session14-job-types.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS claim_trade_items CASCADE;
DROP TABLE IF EXISTS contractor_licenses CASCADE;

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS job_type CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS rcv_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS acv_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS roof_squares CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS repair_squares CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS existing_shingle_brand CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS existing_shingle_product CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS existing_shingle_color CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS urgency CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS urgency_deadline CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS urgency_reason CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS homeowner_notes CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS decking_price_per_sheet CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS full_redeck_price CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS supplement_acknowledged CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS no_license_required CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_claim_trade_items_claim_id;
DROP INDEX IF EXISTS idx_contractor_licenses_contractor_id;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE contractor_licenses DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE claim_trade_items DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

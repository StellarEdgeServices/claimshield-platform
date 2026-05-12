-- Rollback for v46-coi-attestation.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS coi_file_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS ic_24511_attestation CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_contractors_attestation_accepted;
DROP INDEX IF EXISTS idx_contractors_coi_expires;

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS record_attestation_ip(uuid) CASCADE;
DROP FUNCTION IF EXISTS contractor_can_bid(uuid) CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE quotes DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

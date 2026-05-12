-- Rollback for v21-fix-rls-recursion.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS get_contractor_quote_claim_ids(uuid) CASCADE;

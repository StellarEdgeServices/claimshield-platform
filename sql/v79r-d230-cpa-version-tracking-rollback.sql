-- =============================================================================
-- v79r — D-230 ROLLBACK: CPA version tracking
-- =============================================================================
-- Reverses v79-d230-cpa-version-tracking.sql
-- Run this only if the forward migration needs to be undone.
-- =============================================================================

BEGIN;

-- Drop cpa_versions table and all its policies / indexes (CASCADE handles them)
DROP TABLE IF EXISTS public.cpa_versions CASCADE;

-- Drop the performance index on contractors
DROP INDEX IF EXISTS public.idx_contractors_needs_reattestation;

-- Remove needs_cpa_reattestation column from contractors
ALTER TABLE public.contractors
  DROP COLUMN IF EXISTS needs_cpa_reattestation;

-- Revert cpa_version to nullable (pre-v79 state)
ALTER TABLE public.contractors
  ALTER COLUMN cpa_version DROP NOT NULL;

-- Note: the normalised cpa_version values ('v1-2026-04' replacing '1.0') are
-- left as-is — reverting string values is not necessary and safer to leave.

COMMIT;

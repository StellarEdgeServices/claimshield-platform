-- =============================================================================
-- v79 — D-230: CPA version tracking
-- =============================================================================
-- Adds `needs_cpa_reattestation` flag to contractors, normalises cpa_version,
-- and creates the `cpa_versions` admin table so Dustin can publish CPA updates
-- via admin-cpa.html without a code deploy.
--
-- Tier 3 — requires Dustin approval before production deploy.
-- Companion rollback: sql/v79r-d230-cpa-version-tracking-rollback.sql
-- ClickUp: https://app.clickup.com/t/86e1bdnu7
-- =============================================================================

BEGIN;

-- ── 1. Normalise cpa_version — one contractor has '1.0', standardise to label format ──
UPDATE public.contractors
SET    cpa_version = 'v1-2026-04'
WHERE  cpa_version = '1.0'
   OR  cpa_version IS NULL;

-- ── 2. Make cpa_version NOT NULL with default ─────────────────────────────────
ALTER TABLE public.contractors
  ALTER COLUMN cpa_version SET NOT NULL,
  ALTER COLUMN cpa_version SET DEFAULT 'v1-2026-04';

-- ── 3. Add needs_cpa_reattestation flag ───────────────────────────────────────
-- Defaults to false so all existing contractors are unaffected until admin
-- explicitly publishes a new CPA version via admin-cpa.html.
ALTER TABLE public.contractors
  ADD COLUMN IF NOT EXISTS needs_cpa_reattestation BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 4. Create cpa_versions admin table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cpa_versions (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  version_label   TEXT        NOT NULL UNIQUE,
  effective_date  DATE        NOT NULL,
  change_summary  TEXT        NOT NULL,
  is_current      BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 5. Enforce exactly one current version at the DB level ────────────────────
-- Partial unique index: only one row may have is_current = true.
CREATE UNIQUE INDEX IF NOT EXISTS cpa_versions_single_current
  ON public.cpa_versions (is_current)
  WHERE is_current = TRUE;

-- ── 6. Row Level Security ─────────────────────────────────────────────────────
ALTER TABLE public.cpa_versions ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read (dashboard version-check query)
CREATE POLICY "cpa_versions_read_authenticated"
  ON public.cpa_versions
  FOR SELECT
  TO authenticated
  USING (true);

-- Admin (Dustin) can insert and update (publish new versions)
CREATE POLICY "cpa_versions_admin_insert"
  ON public.cpa_versions
  FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() ->> 'email') = 'dustinstohler1@gmail.com');

CREATE POLICY "cpa_versions_admin_update"
  ON public.cpa_versions
  FOR UPDATE
  TO authenticated
  USING  ((auth.jwt() ->> 'email') = 'dustinstohler1@gmail.com')
  WITH CHECK ((auth.jwt() ->> 'email') = 'dustinstohler1@gmail.com');

-- ── 7. Seed initial version ────────────────────────────────────────────────────
INSERT INTO public.cpa_versions (version_label, effective_date, change_summary, is_current)
VALUES ('v1-2026-04', '2026-04-01', 'Initial Contractor Partner Agreement', TRUE)
ON CONFLICT (version_label) DO NOTHING;

-- ── 8. Performance indexes ─────────────────────────────────────────────────────
-- Fast lookup of current version
CREATE INDEX IF NOT EXISTS idx_cpa_versions_current
  ON public.cpa_versions (is_current)
  WHERE is_current = TRUE;

-- Fast lookup of contractors who need re-attestation (admin view + bulk flag queries)
CREATE INDEX IF NOT EXISTS idx_contractors_needs_reattestation
  ON public.contractors (needs_cpa_reattestation)
  WHERE needs_cpa_reattestation = TRUE;

COMMIT;

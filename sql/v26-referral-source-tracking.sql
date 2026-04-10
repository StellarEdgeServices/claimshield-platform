-- ============================================================================
-- OtterQuote SQL Migration v26 — Referral Source Tracking
-- ============================================================================
-- Applied: 2026-04-10
-- ClickUp: 86e0v8cce
-- Purpose: Add referral channel attribution to claims so marketing ROI can be
--          measured from day one. Two new columns:
--
--   referral_source TEXT
--     - Free-text channel label written from the ?ref= URL query param
--     - Examples: 'inspector', 're-agent', 'direct', 'facebook', etc.
--     - Written at claim INSERT in trade-selector.html
--
--   referral_agent_id UUID REFERENCES referral_agents(id)
--     - If a ?partner_id= param is present in the URL, the frontend looks up
--       the matching referral_agents record and populates this column
--     - Enables per-agent commission reporting and ROI attribution
--
-- No existing columns are modified. Both columns are nullable — claims without
-- a referral source simply have NULL values (organic / direct traffic).
-- ============================================================================

-- Add referral_source column for channel attribution
ALTER TABLE public.claims
  ADD COLUMN IF NOT EXISTS referral_source TEXT;

-- Add referral_agent_id for per-agent attribution (links to referral_agents)
ALTER TABLE public.claims
  ADD COLUMN IF NOT EXISTS referral_agent_id UUID
    REFERENCES public.referral_agents(id) ON DELETE SET NULL;

-- Index for analytics queries (filter/group by referral source)
CREATE INDEX IF NOT EXISTS idx_claims_referral_source
  ON public.claims(referral_source);

-- Index for per-agent reporting
CREATE INDEX IF NOT EXISTS idx_claims_referral_agent_id
  ON public.claims(referral_agent_id);

-- Column documentation
COMMENT ON COLUMN public.claims.referral_source IS
'Marketing channel that brought in this homeowner, captured from ?ref= URL param at intake. Examples: inspector, re-agent, direct, facebook, nextdoor.';

COMMENT ON COLUMN public.claims.referral_agent_id IS
'FK to referral_agents. Populated when ?partner_id= is present in the intake URL and matches an active referral_agents record.';

-- ============================================================================
-- End of Migration v26
-- ============================================================================

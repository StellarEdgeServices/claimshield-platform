-- v80: D-231 — Post-completion homeowner home profile prompt (Lodge data moat)
-- Creates: home_profiles table + claims.profile_prompt_sent_at column
-- Adds:    RLS policies, updated_at trigger, rate_limit_config entry, pg_cron schedule (see below)
-- Applied: [DATE — fill in at apply time]
-- Rollback: v80-rollback-d231-home-profiles.sql

-- ─── 1. home_profiles table ──────────────────────────────────────────────────
--
-- One row per homeowner (UNIQUE on homeowner_user_id).
-- Required fields: year_built, square_footage, stories, future_projects
-- Optional fields: roof_last_replaced, siding_material, hvac_age_years, notes
-- stories uses TEXT (not smallint) because the UI option set includes '1.5' and '3+'

CREATE TABLE IF NOT EXISTS public.home_profiles (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  homeowner_user_id   UUID          NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

  -- Required fields (set on initial submission)
  year_built          INTEGER       NOT NULL CHECK (year_built BETWEEN 1800 AND 2100),
  square_footage      INTEGER       NOT NULL CHECK (square_footage > 0),
  stories             TEXT          NOT NULL CHECK (stories IN ('1', '1.5', '2', '3+')),
  future_projects     TEXT[]        NOT NULL DEFAULT '{}',

  -- Optional fields (expandable section in form)
  roof_last_replaced  INTEGER       NULL CHECK (roof_last_replaced BETWEEN 1800 AND 2100),
  siding_material     TEXT          NULL,
  hvac_age_years      SMALLINT      NULL CHECK (hvac_age_years >= 0),
  notes               TEXT          NULL,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT home_profiles_homeowner_user_id_unique UNIQUE (homeowner_user_id)
);

COMMENT ON TABLE public.home_profiles IS
  'D-231: One-row-per-homeowner home property profile. Feeds The Lodge data moat (D-205). '
  'Populated via post-completion prompt (email + in-app card). '
  'future_projects values: Roofing | Siding | Gutters | Windows | HVAC | Other.';

-- ─── 2. updated_at auto-update trigger ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.home_profiles_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS home_profiles_updated_at ON public.home_profiles;
CREATE TRIGGER home_profiles_updated_at
  BEFORE UPDATE ON public.home_profiles
  FOR EACH ROW EXECUTE FUNCTION public.home_profiles_set_updated_at();

-- ─── 3. Indexes ───────────────────────────────────────────────────────────────

-- Primary lookup: homeowner fetching their own profile
CREATE INDEX IF NOT EXISTS home_profiles_homeowner_user_id_idx
  ON public.home_profiles (homeowner_user_id);

-- Lodge data moat: querying homeowners interested in specific future projects
CREATE INDEX IF NOT EXISTS home_profiles_future_projects_gin_idx
  ON public.home_profiles USING GIN (future_projects);

-- ─── 4. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.home_profiles ENABLE ROW LEVEL SECURITY;

-- Homeowners read their own profile
DROP POLICY IF EXISTS "Homeowners can view own home profile" ON public.home_profiles;
CREATE POLICY "Homeowners can view own home profile"
  ON public.home_profiles FOR SELECT
  USING (homeowner_user_id = auth.uid());

-- Homeowners create their own profile (INSERT — enforced by UNIQUE constraint too)
DROP POLICY IF EXISTS "Homeowners can create own home profile" ON public.home_profiles;
CREATE POLICY "Homeowners can create own home profile"
  ON public.home_profiles FOR INSERT
  WITH CHECK (homeowner_user_id = auth.uid());

-- Homeowners update their own profile
DROP POLICY IF EXISTS "Homeowners can update own home profile" ON public.home_profiles;
CREATE POLICY "Homeowners can update own home profile"
  ON public.home_profiles FOR UPDATE
  USING (homeowner_user_id = auth.uid());

-- Service role (Edge Functions) has unrestricted access via service_role key bypass

-- ─── 5. claims.profile_prompt_sent_at column ─────────────────────────────────
--
-- Idempotency gate for send-home-profile-prompt EF.
-- NULL = not yet sent; NOT NULL = email sent at this timestamp.
-- Also stamped when homeowner already has a home_profiles row (prevents re-scans).

ALTER TABLE public.claims
  ADD COLUMN IF NOT EXISTS profile_prompt_sent_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.claims.profile_prompt_sent_at IS
  'D-231: Timestamp when the home profile prompt email was sent (or skipped because '
  'homeowner already had a home_profiles row). NULL = not yet sent. '
  'Idempotency gate for send-home-profile-prompt EF.';

-- Index: cron scan query — "completion_date IS NOT NULL AND profile_prompt_sent_at IS NULL"
CREATE INDEX IF NOT EXISTS claims_profile_prompt_pending_idx
  ON public.claims (completion_date)
  WHERE profile_prompt_sent_at IS NULL AND completion_date IS NOT NULL;

-- ─── 6. rate_limit_config entry ──────────────────────────────────────────────

INSERT INTO public.rate_limit_config (
  function_name,
  max_per_hour,
  max_per_day,
  max_per_month,
  enabled,
  monthly_cost_estimate,
  monthly_budget_cap,
  notes
)
VALUES (
  'send-home-profile-prompt',
  100,    -- batch up to 100 emails/hr (50 claims × 2 retry slots)
  500,    -- daily ceiling well above realistic job volume
  5000,   -- monthly ceiling
  true,
  0.50,
  10.00,
  'D-231: Hourly cron — sends Mailgun email 24h post job-completion to homeowners '
  'without a home_profiles row. Also called non-blocking by mark-job-complete.'
)
ON CONFLICT (function_name) DO NOTHING;

-- ─── 7. pg_cron schedule ─────────────────────────────────────────────────────
--
-- ⚠️  REQUIRES MANUAL APPLICATION — do NOT commit the service-role key.
-- Apply in Supabase SQL editor (with pg_net and pg_cron extensions enabled):
--
-- SELECT cron.schedule(
--   'home-profile-prompt-hourly',
--   '0 * * * *',   -- top of every hour
--   $$
--   SELECT net.http_post(
--     url    := 'https://yeszghaspzwwstvsrioa.supabase.co/functions/v1/send-home-profile-prompt',
--     body   := '{}',
--     headers := jsonb_build_object(
--       'Content-Type',  'application/json',
--       'X-Cron-Secret', '<CRON_SECRET_VALUE>'
--     )
--   );
--   $$
-- );
--
-- Set CRON_SECRET env var on the EF to match the value used above.
-- Verify with: SELECT * FROM cron.job WHERE jobname = 'home-profile-prompt-hourly';

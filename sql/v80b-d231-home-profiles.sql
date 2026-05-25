-- v80b-d231-home-profiles.sql
-- D-231: Post-completion homeowner home profile prompt
--   - home_profiles table
--   - claims.profile_prompt_sent_at idempotency column
--
-- Applied to production: 2026-05-13
-- Backfilled to repo:    2026-05-14 (migration was missing from sql/)
-- Idempotent: uses IF NOT EXISTS / IF NOT EXISTS guards throughout.
--
-- Companion rollback: v80br-d231-home-profiles-rollback.sql

-- ============================================================
-- 1. home_profiles table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.home_profiles (
  id                   UUID         NOT NULL DEFAULT gen_random_uuid(),
  homeowner_user_id    UUID         NOT NULL,
  year_built           INTEGER      NOT NULL,
  square_footage       INTEGER      NOT NULL,
  stories              TEXT         NOT NULL,
  future_projects      TEXT[]       NOT NULL DEFAULT '{}',
  roof_last_replaced   INTEGER,
  siding_material      TEXT,
  hvac_age_years       SMALLINT,
  notes                TEXT,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT home_profiles_pkey
    PRIMARY KEY (id),
  CONSTRAINT home_profiles_homeowner_user_id_unique
    UNIQUE (homeowner_user_id),
  CONSTRAINT home_profiles_homeowner_user_id_fkey
    FOREIGN KEY (homeowner_user_id) REFERENCES public.profiles(id)
);

-- Lookup index (also covers UNIQUE constraint btree above, but explicit idx for clarity)
CREATE INDEX IF NOT EXISTS home_profiles_homeowner_user_id_idx
  ON public.home_profiles USING btree (homeowner_user_id);

-- GIN index for future_projects array queries
CREATE INDEX IF NOT EXISTS home_profiles_future_projects_gin_idx
  ON public.home_profiles USING gin (future_projects);

-- ============================================================
-- 2. Row-Level Security
-- ============================================================
ALTER TABLE public.home_profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'home_profiles'
      AND policyname = 'Homeowners can view own home profile'
  ) THEN
    EXECUTE '
      CREATE POLICY "Homeowners can view own home profile"
        ON public.home_profiles
        FOR SELECT
        USING (homeowner_user_id = auth.uid())
    ';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'home_profiles'
      AND policyname = 'Homeowners can create own home profile'
  ) THEN
    EXECUTE '
      CREATE POLICY "Homeowners can create own home profile"
        ON public.home_profiles
        FOR INSERT
        WITH CHECK (homeowner_user_id = auth.uid())
    ';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'home_profiles'
      AND policyname = 'Homeowners can update own home profile'
  ) THEN
    EXECUTE '
      CREATE POLICY "Homeowners can update own home profile"
        ON public.home_profiles
        FOR UPDATE
        USING (homeowner_user_id = auth.uid())
    ';
  END IF;
END $$;

-- ============================================================
-- 3. claims.profile_prompt_sent_at — idempotency gate column
-- ============================================================
ALTER TABLE public.claims
  ADD COLUMN IF NOT EXISTS profile_prompt_sent_at TIMESTAMPTZ;

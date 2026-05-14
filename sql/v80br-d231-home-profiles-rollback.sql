-- v80br-d231-home-profiles-rollback.sql
-- Rollback for: v80b-d231-home-profiles.sql
-- D-231: home_profiles table + claims.profile_prompt_sent_at
--
-- ⚠️  DESTRUCTIVE — drops home_profiles CASCADE.
--     Only execute if all home_profiles data can be safely discarded
--     (i.e., no homeowners have submitted profiles yet, or data has
--     been exported/archived separately).
--
-- RLS policies and indexes are dropped automatically via CASCADE.

-- ============================================================
-- 1. Remove idempotency gate column from claims
-- ============================================================
ALTER TABLE public.claims
  DROP COLUMN IF EXISTS profile_prompt_sent_at;

-- ============================================================
-- 2. Drop home_profiles table (CASCADE removes indexes + policies)
-- ============================================================
DROP TABLE IF EXISTS public.home_profiles CASCADE;

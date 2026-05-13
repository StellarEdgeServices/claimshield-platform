-- v80 ROLLBACK: D-231 — Post-completion homeowner home profile prompt
-- Reverses v80-d231-home-profiles.sql
-- Apply ONLY if v80 forward migration needs to be undone.
-- ⚠️  Data loss: drops home_profiles table (all profile data lost) and
--     removes claims.profile_prompt_sent_at column (timestamps lost).
-- Run ONLY in coordination with Dustin per D-220.

-- ─── 1. Remove pg_cron job (if scheduled) ────────────────────────────────────
-- Run manually in Supabase SQL editor:
-- SELECT cron.unschedule('home-profile-prompt-hourly');

-- ─── 2. Remove rate_limit_config entry ───────────────────────────────────────
DELETE FROM public.rate_limit_config
  WHERE function_name = 'send-home-profile-prompt';

-- ─── 3. Drop claims.profile_prompt_sent_at ───────────────────────────────────
DROP INDEX IF EXISTS public.claims_profile_prompt_pending_idx;

ALTER TABLE public.claims
  DROP COLUMN IF EXISTS profile_prompt_sent_at;

-- ─── 4. Drop home_profiles table (CASCADE drops dependent RLS, indexes, trigger) ──
DROP TABLE IF EXISTS public.home_profiles CASCADE;

-- ─── 5. Drop trigger function ────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.home_profiles_set_updated_at() CASCADE;

-- ─── 6. Verify ───────────────────────────────────────────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'claims' AND column_name = 'profile_prompt_sent_at';
-- -- Should return 0 rows.
--
-- SELECT tablename FROM pg_tables WHERE tablename = 'home_profiles';
-- -- Should return 0 rows.

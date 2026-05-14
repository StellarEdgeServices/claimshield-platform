-- v80r — rollback v80 check_rate_limit alias overload
-- Drops the (uuid, text) overload only. Canonical (text, uuid) signature untouched.
-- Sentinel: v80r-check-rate-limit-uuid-text-overload-rollback.

DROP FUNCTION IF EXISTS public.check_rate_limit(uuid, text);


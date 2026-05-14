-- v80 — Codify check_rate_limit(p_caller_id uuid, p_function_name text) overload
-- Surfaced by pfw-1778709516 (May 13, 2026). Live in production DB but never persisted.
-- This pins the alias overload into versioned migrations. Sentinel: v80-check-rate-limit-uuid-text-overload.
--
-- Applied to production via Supabase MCP apply_migration on 2026-05-14.
-- Companion rollback: v80r-check-rate-limit-uuid-text-overload-rollback.sql.

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_caller_id uuid,
  p_function_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Alias for the canonical (p_function_name text, p_user_id uuid) signature.
  -- EFs that pass (uuid, text) positional args resolve to this overload and
  -- delegate to the canonical implementation via named parameters.
  RETURN public.check_rate_limit(
    p_function_name => p_function_name,
    p_user_id       => p_caller_id
  );
END;
$function$;


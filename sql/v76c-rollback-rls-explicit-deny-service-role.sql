-- v76c-rollback-rls-explicit-deny-service-role.sql
-- Rollback for v76c-rls-explicit-deny-service-role
--
-- Drops the explicit RESTRICTIVE deny-all policies from the three
-- service-role-only tables. The existing permissive service-role policies
-- remain intact; only the deny gates for anon/authenticated are removed.
--
-- WARNING: After rollback, anon/authenticated roles are no longer
-- explicitly blocked from these tables. Re-apply v76c immediately
-- if this rollback was executed in error.

DROP POLICY IF EXISTS hover_tokens_deny_all        ON public.hover_tokens;
DROP POLICY IF EXISTS imported_hover_jobs_deny_all  ON public.imported_hover_jobs;
DROP POLICY IF EXISTS support_tickets_deny_all      ON public.support_tickets;

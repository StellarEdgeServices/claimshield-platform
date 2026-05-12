-- Rollback: rls_explicit_deny_service_role_only_tables
-- Drops the RESTRICTIVE deny-all policies from service-role-only tables,
-- restoring their pre-migration RLS state.
-- Companion forward: v76c-rls-explicit-deny-service-role.sql

DROP POLICY IF EXISTS hover_tokens_deny_all ON public.hover_tokens;
DROP POLICY IF EXISTS imported_hover_jobs_deny_all ON public.imported_hover_jobs;
DROP POLICY IF EXISTS support_tickets_deny_all ON public.support_tickets;

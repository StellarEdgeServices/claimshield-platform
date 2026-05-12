-- v76c-rls-explicit-deny-service-role.sql
-- Supabase Security Advisor remediation (May 6, 2026)
-- Adds RESTRICTIVE deny-all RLS policies for tables that should only be
-- accessible by the service role. Without an explicit deny, anon/authenticated
-- roles could access these tables if a permissive policy is ever added by mistake.
--
-- Applied to production DB via Supabase MCP: 2026-05-06T23:45:50Z
-- Migration name in schema_migrations: rls_explicit_deny_service_role_only_tables
-- Companion rollback: sql/v76c-rollback-rls-explicit-deny-service-role.sql

-- hover_tokens: stores Hover OAuth tokens — service role only
CREATE POLICY hover_tokens_deny_all
  ON public.hover_tokens
  AS RESTRICTIVE
  FOR ALL
  TO anon, authenticated
  USING (false);

-- imported_hover_jobs: internal Hover import staging table — service role only
CREATE POLICY imported_hover_jobs_deny_all
  ON public.imported_hover_jobs
  AS RESTRICTIVE
  FOR ALL
  TO anon, authenticated
  USING (false);

-- support_tickets: internal admin/EF table — service role only
CREATE POLICY support_tickets_deny_all
  ON public.support_tickets
  AS RESTRICTIVE
  FOR ALL
  TO anon, authenticated
  USING (false);

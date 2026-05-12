-- Migration: rls_explicit_deny_service_role_only_tables
-- Applied to production DB via Supabase MCP: 2026-05-06T23:45:50Z
-- Adds RESTRICTIVE deny-all RLS policies on service-role-only tables so
-- anon/authenticated roles are explicitly blocked (Supabase security advisor finding).
-- Companion rollback: v76c-rollback-rls-explicit-deny-service-role.sql

CREATE POLICY hover_tokens_deny_all ON public.hover_tokens
  AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false);

CREATE POLICY imported_hover_jobs_deny_all ON public.imported_hover_jobs
  AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false);

CREATE POLICY support_tickets_deny_all ON public.support_tickets
  AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false);

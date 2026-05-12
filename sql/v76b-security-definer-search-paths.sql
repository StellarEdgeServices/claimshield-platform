-- Migration: fix_security_definer_search_paths
-- Applied to production DB via Supabase MCP: 2026-05-06T23:41:06Z
-- Pins search_path='public' on all SECURITY DEFINER functions to prevent
-- search_path injection attacks (Supabase security advisor finding).
-- Companion rollback: v76b-rollback-security-definer-search-paths.sql

ALTER FUNCTION public.acknowledge_alert(p_id uuid) SET search_path = 'public';
ALTER FUNCTION public.bid_can_submit(p_contractor_id uuid, p_trade text, p_funding_type text) SET search_path = 'public';
ALTER FUNCTION public.contractor_can_bid(p_contractor_id uuid) SET search_path = 'public';
ALTER FUNCTION public.contractor_has_required_docs(p_contractor_id uuid) SET search_path = 'public';
ALTER FUNCTION public.enforce_bid_can_submit() SET search_path = 'public';
ALTER FUNCTION public.get_contractor_last_logins() SET search_path = 'public';
ALTER FUNCTION public.get_contractor_quote_claim_ids(p_user_id uuid) SET search_path = 'public';
ALTER FUNCTION public.record_attestation_ip(p_contractor_id uuid) SET search_path = 'public';
ALTER FUNCTION public.record_cpa_ip(p_contractor_id uuid) SET search_path = 'public';
ALTER FUNCTION public.record_cron_health(p_job_name text, p_status text, p_error text) SET search_path = 'public';
ALTER FUNCTION public.sync_contractor_cert_status() SET search_path = 'public';

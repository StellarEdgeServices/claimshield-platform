-- Rollback: fix_security_definer_search_paths
-- Removes pinned search_path from SECURITY DEFINER functions,
-- restoring mutable search_path state (pre-migration condition).
-- Companion forward: v76b-security-definer-search-paths.sql

ALTER FUNCTION public.acknowledge_alert(p_id uuid) RESET search_path;
ALTER FUNCTION public.bid_can_submit(p_contractor_id uuid, p_trade text, p_funding_type text) RESET search_path;
ALTER FUNCTION public.contractor_can_bid(p_contractor_id uuid) RESET search_path;
ALTER FUNCTION public.contractor_has_required_docs(p_contractor_id uuid) RESET search_path;
ALTER FUNCTION public.enforce_bid_can_submit() RESET search_path;
ALTER FUNCTION public.get_contractor_last_logins() RESET search_path;
ALTER FUNCTION public.get_contractor_quote_claim_ids(p_user_id uuid) RESET search_path;
ALTER FUNCTION public.record_attestation_ip(p_contractor_id uuid) RESET search_path;
ALTER FUNCTION public.record_cpa_ip(p_contractor_id uuid) RESET search_path;
ALTER FUNCTION public.record_cron_health(p_job_name text, p_status text, p_error text) RESET search_path;
ALTER FUNCTION public.sync_contractor_cert_status() RESET search_path;

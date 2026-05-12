-- v76b-rollback-security-definer-search-paths.sql
-- Rollback for v76b-security-definer-search-paths
--
-- Removes the pinned search_path from each SECURITY DEFINER function,
-- restoring mutable search_path state.
--
-- WARNING: This re-exposes the search_path injection vector that v76b
-- was written to close. Only apply if rolling back the security fix
-- deliberately (e.g., debugging a regression caused by the pin).
--
-- Execute all statements; each is independent.

ALTER FUNCTION public.acknowledge_alert(p_id uuid)                                           RESET search_path;
ALTER FUNCTION public.bid_can_submit(p_contractor_id uuid, p_trade text, p_funding_type text) RESET search_path;
ALTER FUNCTION public.contractor_can_bid(p_contractor_id uuid)                               RESET search_path;
ALTER FUNCTION public.contractor_has_required_docs(p_contractor_id uuid)                     RESET search_path;
ALTER FUNCTION public.enforce_bid_can_submit()                                               RESET search_path;
ALTER FUNCTION public.get_contractor_last_logins()                                           RESET search_path;
ALTER FUNCTION public.get_contractor_quote_claim_ids(p_user_id uuid)                         RESET search_path;
ALTER FUNCTION public.record_attestation_ip(p_contractor_id uuid)                            RESET search_path;
ALTER FUNCTION public.record_cpa_ip(p_contractor_id uuid)                                    RESET search_path;
ALTER FUNCTION public.record_cron_health(p_job_name text, p_status text, p_error text)       RESET search_path;
ALTER FUNCTION public.sync_contractor_cert_status()                                          RESET search_path;

-- FORWARD MIGRATION: D-199 bid-time validation gate (SQL v65)
-- Applied: Session 463, Apr 30, 2026 (commit 4d7dcc2)
-- Recovered: 2026-05-20 — file was never committed; reconstructed from pg_proc + pg_trigger
-- Companion rollback: sql/v65-rollback-d199-bid-can-submit.sql
-- THIS MIGRATION HAS ALREADY BEEN APPLIED TO PRODUCTION. DO NOT RE-RUN.

-- 1. Predicate function: determines whether a contractor can submit a bid
--    for a given trade + funding type by checking contractor_templates status.
CREATE OR REPLACE FUNCTION public.bid_can_submit(p_contractor_id uuid, p_trade text, p_funding_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_reason text;
  v_can_submit boolean := false;
BEGIN
  -- Input validation
  IF p_contractor_id IS NULL THEN
    RETURN jsonb_build_object('can_submit', false, 'reason', 'contractor_id required', 'status', NULL);
  END IF;
  IF p_trade IS NULL OR length(trim(p_trade)) = 0 THEN
    RETURN jsonb_build_object('can_submit', false, 'reason', 'trade required', 'status', NULL);
  END IF;
  IF p_funding_type IS NULL OR length(trim(p_funding_type)) = 0 THEN
    RETURN jsonb_build_object('can_submit', false, 'reason', 'funding_type required', 'status', NULL);
  END IF;

  -- Look up the contractor_templates row for this slot (case-insensitive)
  SELECT status INTO v_status
  FROM public.contractor_templates
  WHERE contractor_id = p_contractor_id
    AND lower(trade) = lower(p_trade)
    AND lower(funding_type) = lower(p_funding_type)
  LIMIT 1;

  IF v_status IS NULL THEN
    RETURN jsonb_build_object(
      'can_submit', false,
      'reason', 'Your contract template for ' || initcap(p_trade) || ' / ' || initcap(p_funding_type) || ' has not been uploaded yet. Upload and validate it on your profile before bidding.',
      'status', 'not_found'
    );
  END IF;

  -- Status mapping (matches js/contract-template-validation.js status set)
  CASE v_status
    WHEN 'auto_validated', 'manual_validated', 'admin_validated' THEN
      v_can_submit := true;
      v_reason := NULL;
    WHEN 'pending_validation' THEN
      v_reason := 'Your contract template for ' || initcap(p_trade) || ' / ' || initcap(p_funding_type) || ' is still being validated. Refresh in a moment or check your profile.';
    WHEN 'manual_mapping_pending' THEN
      v_reason := 'Your contract template for ' || initcap(p_trade) || ' / ' || initcap(p_funding_type) || ' needs your action — please complete the manual anchor mapping on your profile.';
    WHEN 'submitted_for_admin_review' THEN
      v_reason := 'Your contract template for ' || initcap(p_trade) || ' / ' || initcap(p_funding_type) || ' is in admin review. You will be notified once approved.';
    WHEN 'rejected' THEN
      v_reason := 'Your contract template for ' || initcap(p_trade) || ' / ' || initcap(p_funding_type) || ' was rejected. Please re-upload a corrected template on your profile.';
    ELSE
      v_reason := 'Template status (' || v_status || ') does not permit bidding. Contact support if you believe this is an error.';
  END CASE;

  RETURN jsonb_build_object(
    'can_submit', v_can_submit,
    'reason', v_reason,
    'status', v_status
  );
END;
$function$;

-- 2. Trigger function: enforces bid_can_submit() on every INSERT into quotes.
--    Skips enforcement for auto-bids (validated by their own pipeline).
CREATE OR REPLACE FUNCTION public.enforce_bid_can_submit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trade text;
  v_funding_type text;
  v_job_type text;
  v_funding_col text;
  v_result jsonb;
BEGIN
  -- Skip enforcement for auto-bids (validated by their own pipeline)
  IF NEW.is_auto_bid IS TRUE THEN
    RETURN NEW;
  END IF;

  -- Resolve trade from the row
  v_trade := lower(coalesce(NEW.trade_type, 'roofing'));

  -- Resolve funding_type from the linked claim
  -- claims may have funding_type column OR may infer from job_type ('insurance_*' -> insurance, 'retail'/'cash' -> retail)
  SELECT
    lower(coalesce(c.funding_type, '')) AS funding_col,
    lower(coalesce(c.job_type, '')) AS job_type_col
  INTO v_funding_col, v_job_type
  FROM public.claims c
  WHERE c.id = NEW.claim_id
  LIMIT 1;

  IF v_funding_col IS NOT NULL AND length(v_funding_col) > 0 THEN
    v_funding_type := v_funding_col;
  ELSIF v_job_type LIKE 'insurance%' THEN
    v_funding_type := 'insurance';
  ELSIF v_job_type IN ('retail', 'cash') THEN
    v_funding_type := 'retail';
  ELSE
    -- Default conservatively to retail (D-202 fallback path)
    v_funding_type := 'retail';
  END IF;

  -- Normalize: contractor_templates uses 'insurance' / 'retail'
  IF v_funding_type LIKE 'insurance%' THEN v_funding_type := 'insurance'; END IF;
  IF v_funding_type IN ('cash', 'out_of_pocket') THEN v_funding_type := 'retail'; END IF;

  -- Run the predicate
  v_result := public.bid_can_submit(NEW.contractor_id, v_trade, v_funding_type);

  IF (v_result->>'can_submit')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'D-199 bid gate: %', coalesce(v_result->>'reason', 'Template not validated')
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$function$;

-- 3. Trigger: fires BEFORE INSERT on quotes, enforcing bid gate for every new bid.
CREATE TRIGGER quotes_enforce_bid_can_submit
  BEFORE INSERT ON public.quotes
  FOR EACH ROW
  EXECUTE FUNCTION enforce_bid_can_submit();

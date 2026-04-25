-- v57 ROLLBACK: Restore global check_rate_limit() and remove per-user index
--
-- Run this if v57 needs to be reverted.
-- Restores the original function body (global COUNT queries, p_caller_id parameter).
-- Drops the covering index added by v57.

-- Step 1: Remove per-user covering index
DROP INDEX IF EXISTS idx_rate_limits_fn_caller_time;

-- Step 2: Restore original check_rate_limit() with global counts
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_function_name TEXT,
  p_caller_id     UUID DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  config        rate_limit_config%ROWTYPE;
  hourly_count  int;
  daily_count   int;
  monthly_count int;
  monthly_spend numeric;
  result        jsonb;
BEGIN
  -- Get config for this function
  SELECT * INTO config FROM rate_limit_config WHERE function_name = p_function_name;

  -- If no config exists, deny by default (fail closed)
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'No rate limit config found for function: ' || p_function_name || '. Denying by default.'
    );
  END IF;

  -- Check master kill switch
  IF NOT config.enabled THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_caller_id, true, '{"reason": "function_disabled"}'::jsonb);

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'Function ' || p_function_name || ' is disabled via kill switch.'
    );
  END IF;

  -- Count recent calls globally (non-blocked only)
  SELECT COUNT(*) INTO hourly_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND called_at > now() - interval '1 hour'
    AND NOT blocked;

  SELECT COUNT(*) INTO daily_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND called_at > now() - interval '1 day'
    AND NOT blocked;

  SELECT COUNT(*) INTO monthly_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND called_at > now() - interval '1 month'
    AND NOT blocked;

  -- Check limits
  IF hourly_count >= config.max_per_hour THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_caller_id, true,
      jsonb_build_object('reason', 'hourly_limit', 'count', hourly_count, 'limit', config.max_per_hour));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Hourly limit reached: %s/%s calls in the last hour.', hourly_count, config.max_per_hour),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  IF daily_count >= config.max_per_day THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_caller_id, true,
      jsonb_build_object('reason', 'daily_limit', 'count', daily_count, 'limit', config.max_per_day));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Daily limit reached: %s/%s calls today.', daily_count, config.max_per_day),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  IF monthly_count >= config.max_per_month THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_caller_id, true,
      jsonb_build_object('reason', 'monthly_limit', 'count', monthly_count, 'limit', config.max_per_month));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Monthly limit reached: %s/%s calls this month.', monthly_count, config.max_per_month),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  -- Check estimated monthly budget
  IF config.monthly_budget_cap > 0 THEN
    monthly_spend := monthly_count * config.monthly_cost_estimate;
    IF monthly_spend >= config.monthly_budget_cap THEN
      INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
      VALUES (p_function_name, p_caller_id, true,
        jsonb_build_object('reason', 'budget_cap', 'spend', monthly_spend, 'cap', config.monthly_budget_cap));

      RETURN jsonb_build_object(
        'allowed', false,
        'reason', format('Monthly budget cap reached: $%s/$%s estimated spend.', monthly_spend, config.monthly_budget_cap),
        'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count),
        'estimated_spend', monthly_spend
      );
    END IF;
  END IF;

  -- All checks passed — log the call and allow it
  INSERT INTO rate_limits (function_name, caller_id, blocked)
  VALUES (p_function_name, p_caller_id, false);

  RETURN jsonb_build_object(
    'allowed', true,
    'counts', jsonb_build_object('hour', hourly_count + 1, 'day', daily_count + 1, 'month', monthly_count + 1),
    'estimated_spend', (monthly_count + 1) * config.monthly_cost_estimate
  );
END;
$$;

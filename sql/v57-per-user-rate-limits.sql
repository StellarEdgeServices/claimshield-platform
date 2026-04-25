-- v57: Per-user rate limits for check_rate_limit()
--
-- Problem: check_rate_limit() counts calls globally across all users.
--   One user exhausting their limit blocks all other users from the same function.
--   The p_caller_id parameter was stored in rate_limits but never used in COUNT queries.
--
-- Fix: Count per (function_name, user_id) pair.
--   NULL p_user_id callers share a single anonymous bucket (cron jobs, server triggers).
--   Budget cap check remains global — it is a total-spend ceiling, not per-user.
--
-- Parameter renamed: p_caller_id → p_user_id
-- New index: idx_rate_limits_fn_caller_time covers (function_name, caller_id, called_at)
--
-- Companion rollback: sql/v57-per-user-rate-limits-rollback.sql
-- ClickUp: 86e117tmv

-- Step 1: Covering index for efficient per-user queries
-- Existing idx_rate_limits_function_time covers (function_name, called_at) only;
-- per-user filter would be a post-scan heap filter without this index.
CREATE INDEX IF NOT EXISTS idx_rate_limits_fn_caller_time
  ON rate_limits(function_name, caller_id, called_at DESC);

-- Step 2: Replace check_rate_limit() with per-user variant
-- DROP required — PostgreSQL disallows renaming parameters via REPLACE
DROP FUNCTION IF EXISTS check_rate_limit(text, uuid);

CREATE FUNCTION check_rate_limit(
  p_function_name TEXT,
  p_user_id       UUID DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  config               rate_limit_config%ROWTYPE;
  hourly_count         int;
  daily_count          int;
  monthly_count        int;
  global_monthly_count int;  -- used only for budget cap (always global)
  monthly_spend        numeric;
BEGIN
  -- Get config for this function
  SELECT * INTO config FROM rate_limit_config WHERE function_name = p_function_name;

  -- No config found → fail closed
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'No rate limit config found for function: ' || p_function_name || '. Denying by default.'
    );
  END IF;

  -- Kill switch
  IF NOT config.enabled THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_user_id, true, '{"reason": "function_disabled"}'::jsonb);

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'Function ' || p_function_name || ' is disabled via kill switch.'
    );
  END IF;

  -- Per-user counts (non-blocked only)
  -- When p_user_id IS NULL, counts the shared anonymous bucket (caller_id IS NULL rows)
  SELECT COUNT(*) INTO hourly_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND (
      (p_user_id IS NOT NULL AND caller_id = p_user_id) OR
      (p_user_id IS NULL     AND caller_id IS NULL)
    )
    AND called_at > now() - interval '1 hour'
    AND NOT blocked;

  SELECT COUNT(*) INTO daily_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND (
      (p_user_id IS NOT NULL AND caller_id = p_user_id) OR
      (p_user_id IS NULL     AND caller_id IS NULL)
    )
    AND called_at > now() - interval '1 day'
    AND NOT blocked;

  SELECT COUNT(*) INTO monthly_count
  FROM rate_limits
  WHERE function_name = p_function_name
    AND (
      (p_user_id IS NOT NULL AND caller_id = p_user_id) OR
      (p_user_id IS NULL     AND caller_id IS NULL)
    )
    AND called_at > now() - interval '1 month'
    AND NOT blocked;

  -- Enforce per-user hourly limit
  IF hourly_count >= config.max_per_hour THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_user_id, true,
      jsonb_build_object('reason', 'hourly_limit', 'count', hourly_count, 'limit', config.max_per_hour));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Hourly limit reached: %s/%s calls in the last hour.', hourly_count, config.max_per_hour),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  -- Enforce per-user daily limit
  IF daily_count >= config.max_per_day THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_user_id, true,
      jsonb_build_object('reason', 'daily_limit', 'count', daily_count, 'limit', config.max_per_day));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Daily limit reached: %s/%s calls today.', daily_count, config.max_per_day),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  -- Enforce per-user monthly limit
  IF monthly_count >= config.max_per_month THEN
    INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
    VALUES (p_function_name, p_user_id, true,
      jsonb_build_object('reason', 'monthly_limit', 'count', monthly_count, 'limit', config.max_per_month));

    RETURN jsonb_build_object(
      'allowed', false,
      'reason', format('Monthly limit reached: %s/%s calls this month.', monthly_count, config.max_per_month),
      'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count)
    );
  END IF;

  -- Global budget cap (total spend across ALL users — cost safety ceiling)
  IF config.monthly_budget_cap > 0 THEN
    SELECT COUNT(*) INTO global_monthly_count
    FROM rate_limits
    WHERE function_name = p_function_name
      AND called_at > now() - interval '1 month'
      AND NOT blocked;

    monthly_spend := global_monthly_count * config.monthly_cost_estimate;
    IF monthly_spend >= config.monthly_budget_cap THEN
      INSERT INTO rate_limits (function_name, caller_id, blocked, metadata)
      VALUES (p_function_name, p_user_id, true,
        jsonb_build_object('reason', 'budget_cap', 'spend', monthly_spend, 'cap', config.monthly_budget_cap));

      RETURN jsonb_build_object(
        'allowed', false,
        'reason', format('Monthly budget cap reached: $%s/$%s estimated spend.', monthly_spend, config.monthly_budget_cap),
        'counts', jsonb_build_object('hour', hourly_count, 'day', daily_count, 'month', monthly_count),
        'estimated_spend', monthly_spend
      );
    END IF;
  END IF;

  -- All checks passed — log the allowed call and return
  INSERT INTO rate_limits (function_name, caller_id, blocked)
  VALUES (p_function_name, p_user_id, false);

  RETURN jsonb_build_object(
    'allowed', true,
    'counts', jsonb_build_object('hour', hourly_count + 1, 'day', daily_count + 1, 'month', monthly_count + 1),
    'estimated_spend', (monthly_count + 1) * config.monthly_cost_estimate
  );
END;
$$;

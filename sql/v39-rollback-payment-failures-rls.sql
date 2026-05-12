-- Rollback for v39-payment-failures-rls.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- This migration only adds RLS and policies to payment_failures.
-- CAUTION: disabling RLS exposes all rows to authenticated users.

-- Drop policies added by this migration
DROP POLICY IF EXISTS contractor_select_own_payment_failures ON payment_failures;
DROP POLICY IF EXISTS contractor_update_own_payment_failures ON payment_failures;
DROP POLICY IF EXISTS admin_select_payment_failures ON payment_failures;
DROP POLICY IF EXISTS admin_update_payment_failures ON payment_failures;

-- Disable RLS (uncomment only if fully intentional)
-- ALTER TABLE payment_failures DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

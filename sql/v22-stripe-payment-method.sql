/**
 * v22 — Stripe Payment Method Storage (Session 93, Apr 9, 2026)
 * Adds columns to contractors table for storing Stripe customer and payment method IDs.
 * These are used for off-session charging when homeowners select a contractor.
 *
 * Changes:
 *   - Add stripe_customer_id TEXT to contractors table
 *   - Add stripe_payment_method_id TEXT to contractors table
 *   - Add stripe_payment_method_last4 TEXT (last 4 digits of card)
 *   - Add stripe_payment_method_brand TEXT (card brand: visa, mastercard, amex, etc.)
 */

-- Add Stripe payment method columns to contractors table
ALTER TABLE contractors
ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
ADD COLUMN IF NOT EXISTS stripe_payment_method_id TEXT,
ADD COLUMN IF NOT EXISTS stripe_payment_method_last4 TEXT,
ADD COLUMN IF NOT EXISTS stripe_payment_method_brand TEXT;

-- Add comment documenting the columns
COMMENT ON COLUMN contractors.stripe_customer_id IS 'Stripe customer ID for this contractor (cus_xxx)';
COMMENT ON COLUMN contractors.stripe_payment_method_id IS 'Stripe payment method ID for off-session charging (pm_xxx)';
COMMENT ON COLUMN contractors.stripe_payment_method_last4 IS 'Last 4 digits of the card for display';
COMMENT ON COLUMN contractors.stripe_payment_method_brand IS 'Card brand (visa, mastercard, amex, diners, discover, jcb, unionpay)';

-- ══════════════════════════════════════════════════════════════
-- v33: Multi-Payment Methods for Contractors
-- Adds contractor_payment_methods table, migrates existing data,
-- adds payment_method_id tracking to quotes table.
-- ══════════════════════════════════════════════════════════════

-- 1. Create contractor_payment_methods table
CREATE TABLE IF NOT EXISTS contractor_payment_methods (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contractor_id           UUID NOT NULL REFERENCES contractors(id) ON DELETE CASCADE,
  stripe_payment_method_id TEXT NOT NULL,
  payment_type            TEXT NOT NULL CHECK (payment_type IN ('card', 'us_bank_account')),
  last_four               TEXT,
  brand                   TEXT,          -- for cards: visa, mastercard, amex, discover, etc.
  bank_name               TEXT,          -- for ACH: bank name from Stripe
  is_default              BOOLEAN NOT NULL DEFAULT false,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cpm_contractor_id ON contractor_payment_methods(contractor_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cpm_stripe_pm_id ON contractor_payment_methods(stripe_payment_method_id);

-- 2. Migrate existing payment method data from contractors table
-- Only migrates rows that have a stripe_payment_method_id set
INSERT INTO contractor_payment_methods (
  contractor_id,
  stripe_payment_method_id,
  payment_type,
  last_four,
  brand,
  is_default,
  created_at
)
SELECT
  id,
  stripe_payment_method_id,
  'card',
  stripe_payment_method_last4,
  stripe_payment_method_brand,
  true,       -- existing method becomes the default
  COALESCE(updated_at, now())
FROM contractors
WHERE stripe_payment_method_id IS NOT NULL
  AND stripe_payment_method_id != ''
ON CONFLICT (stripe_payment_method_id) DO NOTHING;

-- 3. Add payment_method_used column to quotes table
-- Tracks which specific payment method was charged for each quote
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_method_id UUID REFERENCES contractor_payment_methods(id);
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_method_type TEXT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS card_fee_cents INTEGER;

-- 4. RLS policies for contractor_payment_methods
ALTER TABLE contractor_payment_methods ENABLE ROW LEVEL SECURITY;

-- Contractors can read their own payment methods
CREATE POLICY "Contractors can view own payment methods"
  ON contractor_payment_methods FOR SELECT
  USING (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- Contractors can insert their own payment methods
CREATE POLICY "Contractors can insert own payment methods"
  ON contractor_payment_methods FOR INSERT
  WITH CHECK (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- Contractors can update their own payment methods (set default, etc.)
CREATE POLICY "Contractors can update own payment methods"
  ON contractor_payment_methods FOR UPDATE
  USING (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- Contractors can delete their own payment methods
CREATE POLICY "Contractors can delete own payment methods"
  ON contractor_payment_methods FOR DELETE
  USING (
    contractor_id IN (
      SELECT id FROM contractors WHERE user_id = auth.uid()
    )
  );

-- Service role bypass (Edge Functions use service role key)
CREATE POLICY "Service role full access to payment methods"
  ON contractor_payment_methods FOR ALL
  USING (auth.role() = 'service_role');

-- Done. stripe_customer_id stays on contractors table (one customer, many methods).
-- Old columns (stripe_payment_method_id, stripe_payment_method_last4, stripe_payment_method_brand)
-- are NOT dropped — they remain for backward compatibility during transition.

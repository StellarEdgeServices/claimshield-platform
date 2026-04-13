-- v31: Payment Collection & Dunning System
-- Adds payment tracking to quotes table and creates payment_failures table
-- for the dunning sequence when contractor payments fail.

-- 1. Add payment tracking columns to quotes
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_intent_id TEXT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_status TEXT;

-- Add check constraint for payment_status
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'quotes_payment_status_check'
  ) THEN
    ALTER TABLE quotes ADD CONSTRAINT quotes_payment_status_check
      CHECK (payment_status IN ('succeeded', 'failed', 'pending', 'dunning'));
  END IF;
END $$;

-- 2. Create payment_failures table for dunning tracking
CREATE TABLE IF NOT EXISTS payment_failures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id UUID REFERENCES quotes(id),
  contractor_id UUID REFERENCES contractors(id),
  claim_id UUID REFERENCES claims(id),
  homeowner_id UUID,
  amount_cents INTEGER NOT NULL,
  stripe_error TEXT,
  dunning_status TEXT DEFAULT 'active'
    CHECK (dunning_status IN ('active', 'resolved', 'escalated', 'expired')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  next_reminder_at TIMESTAMPTZ,
  reminder_count INTEGER DEFAULT 0
);

-- Indexes for dunning queries
CREATE INDEX IF NOT EXISTS idx_payment_failures_active
  ON payment_failures(dunning_status, next_reminder_at)
  WHERE dunning_status = 'active';

CREATE INDEX IF NOT EXISTS idx_payment_failures_contractor
  ON payment_failures(contractor_id, dunning_status);

CREATE INDEX IF NOT EXISTS idx_quotes_payment_intent
  ON quotes(payment_intent_id)
  WHERE payment_intent_id IS NOT NULL;

-- Comments
COMMENT ON TABLE payment_failures IS 'Tracks failed contractor platform fee payments and dunning sequence state';
COMMENT ON COLUMN payment_failures.dunning_status IS 'active=reminders sending, resolved=paid, escalated=homeowner notified, expired=abandoned';
COMMENT ON COLUMN payment_failures.next_reminder_at IS 'When the next dunning reminder should be sent (every 2 hours, paused 9PM-7AM)';
COMMENT ON COLUMN payment_failures.reminder_count IS 'Number of dunning reminders sent so far';
COMMENT ON COLUMN quotes.payment_intent_id IS 'Stripe PaymentIntent ID for the platform fee charge';
COMMENT ON COLUMN quotes.payment_status IS 'Payment status: succeeded, failed, pending, dunning';

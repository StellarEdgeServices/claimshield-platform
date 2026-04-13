-- v30: Contract Signing Flow Overhaul + IC 24-5-11 Compliance
-- Adds columns to quotes table for contractor-first signing flow.
-- Contractor signs at bid submission; homeowner signs after selection.

-- 1. Add DocuSign envelope tracking to quotes
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS docusign_envelope_id TEXT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS contractor_signed_at TIMESTAMPTZ;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS homeowner_signed_at TIMESTAMPTZ;

-- 2. Auto-bid flag (auto-bid contractors can't sign at submission time)
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS is_auto_bid BOOLEAN DEFAULT FALSE;

-- 3. Index for envelope lookups
CREATE INDEX IF NOT EXISTS idx_quotes_docusign_envelope_id ON quotes(docusign_envelope_id) WHERE docusign_envelope_id IS NOT NULL;

-- 4. Index for finding unsigned auto-bids that need contractor signature
CREATE INDEX IF NOT EXISTS idx_quotes_auto_bid_unsigned ON quotes(contractor_id, is_auto_bid) WHERE is_auto_bid = TRUE AND contractor_signed_at IS NULL;

COMMENT ON COLUMN quotes.docusign_envelope_id IS 'DocuSign envelope ID created when contractor signs the contract at bid time';
COMMENT ON COLUMN quotes.contractor_signed_at IS 'Timestamp when contractor signed the contract (must be before homeowner per IC 24-5-11-11)';
COMMENT ON COLUMN quotes.homeowner_signed_at IS 'Timestamp when homeowner signed the contract';
COMMENT ON COLUMN quotes.is_auto_bid IS 'Whether this bid was auto-generated. Auto-bids require contractor to sign after homeowner selects them.';

-- Rollback for v30-contract-signing-flow.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE quotes DROP COLUMN IF EXISTS docusign_envelope_id CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS contractor_signed_at CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS homeowner_signed_at CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS is_auto_bid CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_quotes_auto_bid_unsigned;
DROP INDEX IF EXISTS idx_quotes_docusign_envelope_id;

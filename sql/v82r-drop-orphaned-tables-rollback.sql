-- =============================================================================
-- v82r: ROLLBACK for v82 — Recreate 4 orphaned tables
-- =============================================================================
-- Only apply this if v82 needs to be reverted.
-- Schema reconstructed from live DB inspection on 2026-05-27.
-- RLS was enabled on all 4 tables but no active policies were in use.
-- =============================================================================

-- claim_trade_items
CREATE TABLE IF NOT EXISTS claim_trade_items (
  id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id             UUID         REFERENCES claims(id),
  trade                TEXT         NOT NULL,
  scope                TEXT,
  estimated_amount     NUMERIC,
  depreciation_amount  NUMERIC,
  sides_affected       TEXT,
  homeowner_decision   TEXT,
  notes                TEXT,
  created_at           TIMESTAMPTZ  DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_claim_trade_items_claim_id ON claim_trade_items USING btree (claim_id);
ALTER TABLE claim_trade_items ENABLE ROW LEVEL SECURITY;

-- documents
CREATE TABLE IF NOT EXISTS documents (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id      UUID         REFERENCES claims(id),
  user_id       UUID         REFERENCES auth.users(id),
  file_name     TEXT         NOT NULL,
  file_type     TEXT         NOT NULL,
  file_size     BIGINT       NOT NULL,
  storage_path  TEXT         NOT NULL,
  doc_category  TEXT         DEFAULT 'other',
  created_at    TIMESTAMPTZ  DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_claim_id ON documents USING btree (claim_id);
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- inspection_bookings
CREATE TABLE IF NOT EXISTS inspection_bookings (
  id                         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id                   UUID         NOT NULL REFERENCES claims(id),
  contractor_id              UUID         REFERENCES contractors(id),
  homeowner_id               UUID         NOT NULL REFERENCES auth.users(id),
  scheduled_date             DATE         NOT NULL,
  scheduled_time             TEXT         NOT NULL,
  status                     TEXT         DEFAULT 'scheduled',
  inspection_type            TEXT,
  inspection_fee             NUMERIC      DEFAULT 0,
  homeowner_guarantee_paid   BOOLEAN      DEFAULT false,
  contractor_penalty_charged BOOLEAN      DEFAULT false,
  notes                      TEXT,
  created_at                 TIMESTAMPTZ  DEFAULT now(),
  updated_at                 TIMESTAMPTZ  DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inspection_bookings_claim ON inspection_bookings USING btree (claim_id);
CREATE INDEX IF NOT EXISTS idx_inspection_bookings_contractor ON inspection_bookings USING btree (contractor_id);
CREATE INDEX IF NOT EXISTS idx_inspection_bookings_date ON inspection_bookings USING btree (scheduled_date);
ALTER TABLE inspection_bookings ENABLE ROW LEVEL SECURITY;

-- job_assignments
CREATE TABLE IF NOT EXISTS job_assignments (
  id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id            UUID         NOT NULL UNIQUE REFERENCES claims(id),
  quote_id            UUID         NOT NULL REFERENCES quotes(id),
  contractor_id       UUID         NOT NULL REFERENCES contractors(id),
  homeowner_id        UUID         NOT NULL REFERENCES auth.users(id),
  quoted_price        NUMERIC      NOT NULL,
  fee_percentage      NUMERIC      NOT NULL,
  fee_amount          NUMERIC      NOT NULL,
  fee_status          TEXT         DEFAULT 'pending',
  stripe_charge_id    TEXT,
  contract_signed     BOOLEAN      DEFAULT false,
  contract_signed_at  TIMESTAMPTZ,
  status              TEXT         DEFAULT 'pending_contract',
  created_at          TIMESTAMPTZ  DEFAULT now(),
  updated_at          TIMESTAMPTZ  DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_job_assignments_claim_id ON job_assignments USING btree (claim_id);
CREATE INDEX IF NOT EXISTS idx_job_assignments_contractor_id ON job_assignments USING btree (contractor_id);
CREATE INDEX IF NOT EXISTS idx_job_assignments_quote_id ON job_assignments USING btree (quote_id);
ALTER TABLE job_assignments ENABLE ROW LEVEL SECURITY;
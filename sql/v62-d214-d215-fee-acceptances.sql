-- v62: fee_acceptances + platform_fee_config (D-214/D-215) — idempotent backfill
-- Schema changes were applied directly to the DB; this file makes them reproducible.
-- Safe to re-run: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS.

-- ============================================================
-- 1. fee_acceptances table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.fee_acceptances (
    id                  uuid        NOT NULL DEFAULT gen_random_uuid(),
    contractor_id       uuid        NOT NULL,
    claim_id            uuid        NOT NULL,
    bid_id              uuid        NOT NULL,
    fee_pct             numeric     NOT NULL,
    fee_basis           text        NOT NULL,
    fee_amount          numeric     NOT NULL,
    fee_text_displayed  text        NOT NULL,
    accepted_at         timestamptz NOT NULL DEFAULT now(),
    ip_address          inet,
    user_agent          text,
    invoice_url         text,
    rescinded_at        timestamptz,
    rescission_reason   text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fee_acceptances_pkey PRIMARY KEY (id),
    CONSTRAINT fee_acceptances_contractor_id_fkey
        FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),
    CONSTRAINT fee_acceptances_claim_id_fkey
        FOREIGN KEY (claim_id) REFERENCES public.claims(id),
    CONSTRAINT fee_acceptances_bid_id_fkey
        FOREIGN KEY (bid_id) REFERENCES public.quotes(id)
);

-- ============================================================
-- 2. platform_fee_config table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.platform_fee_config (
    id              uuid    NOT NULL DEFAULT gen_random_uuid(),
    state           text,
    trade           text,
    fee_pct         numeric NOT NULL,
    fee_basis       text    NOT NULL,
    effective_date  date    NOT NULL DEFAULT CURRENT_DATE,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT platform_fee_config_pkey PRIMARY KEY (id)
);

-- ============================================================
-- 3. quotes columns added in v62
-- ============================================================
ALTER TABLE public.quotes
    ADD COLUMN IF NOT EXISTS platform_fee_pct   numeric,
    ADD COLUMN IF NOT EXISTS platform_fee_basis  text,
    ADD COLUMN IF NOT EXISTS fee_accepted_at     timestamptz;

-- ============================================================
-- 4. Indexes on fee_acceptances
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_fee_acceptances_contractor
    ON public.fee_acceptances USING btree (contractor_id);

CREATE INDEX IF NOT EXISTS idx_fee_acceptances_bid
    ON public.fee_acceptances USING btree (bid_id);

CREATE INDEX IF NOT EXISTS idx_fee_acceptances_claim
    ON public.fee_acceptances USING btree (claim_id);

-- ============================================================
-- 5. Row Level Security
-- ============================================================
ALTER TABLE public.fee_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_fee_config ENABLE ROW LEVEL SECURITY;

-- fee_acceptances policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'fee_acceptances'
      AND policyname = 'Admin can read all fee acceptances'
  ) THEN
    CREATE POLICY "Admin can read all fee acceptances"
      ON public.fee_acceptances FOR SELECT
      USING ((auth.jwt() ->> 'email'::text) = 'dustinstohler1@gmail.com'::text);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'fee_acceptances'
      AND policyname = 'Admin can update fee acceptances'
  ) THEN
    CREATE POLICY "Admin can update fee acceptances"
      ON public.fee_acceptances FOR UPDATE
      USING ((auth.jwt() ->> 'email'::text) = 'dustinstohler1@gmail.com'::text);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'fee_acceptances'
      AND policyname = 'Contractors can insert own fee acceptances'
  ) THEN
    CREATE POLICY "Contractors can insert own fee acceptances"
      ON public.fee_acceptances FOR INSERT
      WITH CHECK (
        contractor_id IN (
          SELECT contractors.id FROM contractors
          WHERE contractors.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'fee_acceptances'
      AND policyname = 'Contractors can read own fee acceptances'
  ) THEN
    CREATE POLICY "Contractors can read own fee acceptances"
      ON public.fee_acceptances FOR SELECT
      USING (
        contractor_id IN (
          SELECT contractors.id FROM contractors
          WHERE contractors.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- platform_fee_config policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'platform_fee_config'
      AND policyname = 'Admin can manage fee config'
  ) THEN
    CREATE POLICY "Admin can manage fee config"
      ON public.platform_fee_config FOR ALL
      USING ((auth.jwt() ->> 'email'::text) = 'dustinstohler1@gmail.com'::text)
      WITH CHECK ((auth.jwt() ->> 'email'::text) = 'dustinstohler1@gmail.com'::text);
  END IF;
END $$;

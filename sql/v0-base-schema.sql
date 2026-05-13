-- =============================================================================
-- v0-base-schema.sql  —  OtterQuote Base Schema (pre-migration-tracking)
-- =============================================================================
-- PURPOSE
--   Branch replay fails at v53 with "relation 'claims' does not exist" because
--   all core tables were created manually before Supabase migration tracking
--   was set up (migrations start at v53 / 20260423…).
--
--   This file recreates every pre-v53 table so that a fresh branch starts with
--   the full table set in place before any tracked migration runs.
--
-- IDEMPOTENCY
--   Every statement uses CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS
--   / ADD CONSTRAINT IF NOT EXISTS so the file is a complete no-op on production
--   (or any branch that already has these tables).
--
-- SCOPE
--   Only tables that predate migration tracking are defined here.
--   Tables created by tracked migrations are intentionally EXCLUDED:
--     rate_limits, rate_limit_config (v57)
--     cron_health (v60)
--     support_tickets (v60)
--     fee_acceptances, platform_fee_config (v62)
--     warranty_options (v62b)
--     contractor_templates (v63)
--     contractor_cert_verifications (v66)
--     warranty_manifest_drift (v69)
--     messages (v74)
--     contractor_licenses (v77)
--     cpa_versions (v79)
--   Views (admin_contractor_last_logins, cert_verification_quality,
--          cert_verification_quality_by_manufacturer, contribution_summary,
--          org_summary, referral_network, state_summary) are also excluded —
--   they are created by their respective migrations after base tables exist.
--
-- TRACKED MIGRATION COMPATIBILITY
--   All tracked migrations (v53+) use ADD COLUMN IF NOT EXISTS / CREATE TABLE
--   to make their changes. A branch that applies v0 first will see those later
--   migrations as no-ops for any column already present here. Safe on both ends.
--
-- DEPLOY PATH
--   D-221 (commit_via_api.py + GitHub Actions) per D-182.
--   This file requires Tier 3 SQL approval (D-182 / D-220) before apply.
--   DO NOT apply without explicit Dustin approval.
--   Companion rollback: v0-base-schema-rollback.sql  (DROP TABLE IF EXISTS
--   in reverse dependency order — to be created before any apply on a branch).
--
-- FILE SORT ORDER
--   Named v0-base-schema.sql — sorts before any 20260423… timestamp migration.
--   Apply via Supabase CLI:
--     supabase db push --db-url <branch-url>
--   Or rename to  00000000000000_v0_base_schema.sql  for automatic replay pickup.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. profiles
--    Central user-profile table. id mirrors auth.users(id).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID        NOT NULL,
  full_name       TEXT,
  email           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  phone           TEXT,
  address_street  TEXT,
  address_city    TEXT,
  address_state   TEXT        DEFAULT 'IN'::text,
  address_zip     TEXT,
  referral_source TEXT,
  referring_agent_name  TEXT,
  referring_agent_email TEXT,
  role            TEXT        NOT NULL DEFAULT 'homeowner'::text,
  sms_consent_ts  TIMESTAMPTZ,
  is_test         BOOLEAN     NOT NULL DEFAULT false,
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 2. leads
--    Top-of-funnel email captures (landing page).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.leads (
  id         UUID        NOT NULL DEFAULT gen_random_uuid(),
  email      TEXT        NOT NULL,
  name       TEXT,
  zip        TEXT,
  source     TEXT        DEFAULT 'landing_page'::text,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT leads_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 3. members
--    Legacy membership / waitlist table (Stellar Edge Services era).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.members (
  id            UUID        NOT NULL DEFAULT gen_random_uuid(),
  first_name    TEXT        NOT NULL,
  last_name     TEXT        NOT NULL,
  email         TEXT        NOT NULL,
  email_domain  TEXT,
  organization  TEXT,
  title         TEXT,
  phone         TEXT,
  state         TEXT        NOT NULL,
  referred_by   TEXT        NOT NULL,
  contributions TEXT[]      DEFAULT '{}'::text[],
  top_concern   TEXT,
  registered_at TIMESTAMPTZ DEFAULT now(),
  status        TEXT        DEFAULT 'active'::text,
  notes         TEXT,
  verified      BOOLEAN     DEFAULT false,
  updated_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT members_pkey     PRIMARY KEY (id),
  CONSTRAINT members_email_key UNIQUE (email)
);

-- ---------------------------------------------------------------------------
-- 4. material_catalog
--    Reference catalog for roofing / siding / other materials.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.material_catalog (
  id            UUID        NOT NULL DEFAULT gen_random_uuid(),
  category      TEXT        NOT NULL,
  subcategory   TEXT        NOT NULL,
  manufacturer  TEXT,
  product_name  TEXT,
  impact_class  TEXT,
  description   TEXT,
  price_tier    TEXT,
  image_url     TEXT,
  visualizer_url TEXT,
  active        BOOLEAN     DEFAULT true,
  sort_order    INT         DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT material_catalog_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 5. carrier_profiles
--    Insurance carrier knowledge-base.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.carrier_profiles (
  id                    UUID        NOT NULL DEFAULT gen_random_uuid(),
  carrier_name          TEXT        NOT NULL,
  claims_portal_url     TEXT,
  claims_email          TEXT,
  claims_phone          TEXT,
  typical_estimate_days INT,
  process_notes         TEXT,
  special_instructions  TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  active                BOOLEAN     NOT NULL DEFAULT true,
  CONSTRAINT carrier_profiles_pkey           PRIMARY KEY (id),
  CONSTRAINT carrier_profiles_carrier_name_key UNIQUE (carrier_name)
);

-- ---------------------------------------------------------------------------
-- 6. adjusters
--    Adjuster knowledge-base (linked to carrier_profiles).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.adjusters (
  id              UUID        NOT NULL DEFAULT gen_random_uuid(),
  adjuster_name   TEXT        NOT NULL,
  adjuster_email  TEXT,
  adjuster_phone  TEXT,
  carrier_id      UUID,
  region          TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT adjusters_pkey PRIMARY KEY (id),
  CONSTRAINT adjusters_adjuster_name_adjuster_email_carrier_id_key
    UNIQUE (adjuster_name, adjuster_email, carrier_id)
);

-- ---------------------------------------------------------------------------
-- 7. contractors
--    Contractor accounts. Extensive profile + compliance columns.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contractors (
  id                              UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id                         UUID,
  company_name                    TEXT        NOT NULL,
  contact_name                    TEXT        NOT NULL,
  email                           TEXT        NOT NULL,
  phone                           TEXT,
  license_number                  TEXT,
  specialties                     TEXT[],
  rating                          NUMERIC,
  review_count                    INT         DEFAULT 0,
  verified                        BOOLEAN     DEFAULT false,
  has_payment_method              BOOLEAN     DEFAULT false,
  stripe_customer_id              TEXT,
  created_at                      TIMESTAMPTZ DEFAULT now(),
  updated_at                      TIMESTAMPTZ DEFAULT now(),
  no_license_required             BOOLEAN     DEFAULT false,
  about_us                        TEXT,
  why_choose_us                   TEXT,
  owner_photo_url                 TEXT,
  preferred_brands                TEXT[],
  trades                          TEXT[],
  service_counties                TEXT[],
  service_area_description        TEXT,
  google_reviews_url              TEXT,
  bbb_url                         TEXT,
  angi_url                        TEXT,
  yelp_url                        TEXT,
  color_selection_enabled         BOOLEAN     DEFAULT true,
  notification_emails             TEXT[],
  notification_phones             TEXT[],
  notification_preferences        JSONB       DEFAULT '{"bid_accepted":true,"reminder_48h":true,"color_complete":true,"contract_signed":true,"new_opportunity":true,"deductible_collected":true}'::jsonb,
  status                          TEXT        DEFAULT 'pending_approval'::text,
  contract_pdf_url                TEXT,
  auto_bid_enabled                BOOLEAN     DEFAULT false,
  auto_bid_settings               JSONB       DEFAULT '{"scope":"full_replacement","trade":"roofing","pricing":"rcv","funding_type":"insurance"}'::jsonb,
  contract_templates              JSONB       DEFAULT '[]'::jsonb,
  address_line1                   TEXT,
  address_city                    TEXT,
  address_state                   TEXT        DEFAULT 'IN'::text,
  address_zip                     TEXT,
  website_url                     TEXT,
  num_employees                   TEXT,
  years_in_business               INT,
  repairs_accepted                BOOLEAN     NOT NULL DEFAULT false,
  guarantee_accepted              BOOLEAN     NOT NULL DEFAULT false,
  has_workers_comp                BOOLEAN     DEFAULT false,
  has_general_liability           BOOLEAN     DEFAULT false,
  auto_bid_value_adds             JSONB,
  stripe_payment_method_id        TEXT,
  stripe_payment_method_last4     TEXT,
  stripe_payment_method_brand     TEXT,
  color_confirmation_template     JSONB,
  agreement_accepted_at           TIMESTAMPTZ,
  agreement_version               TEXT,
  timezone                        TEXT        DEFAULT 'America/New_York'::text,
  gl_carrier                      TEXT,
  gl_policy_number                TEXT,
  gl_coverage_amount              TEXT,
  gl_expiration_date              DATE,
  wc_carrier                      TEXT,
  wc_policy_number                TEXT,
  wc_coverage_amount              TEXT,
  wc_expiration_date              DATE,
  gallery_photo_urls              TEXT[]      DEFAULT '{}'::text[],
  admin_notes                     TEXT,
  license_verified                BOOLEAN     DEFAULT false,
  license_verified_at             TIMESTAMPTZ,
  insurance_verified              BOOLEAN     DEFAULT false,
  insurance_verified_at           TIMESTAMPTZ,
  insurance_verification_sent_at  TIMESTAMPTZ,
  insurance_verification_email    TEXT,
  approved_at                     TIMESTAMPTZ,
  rejected_at                     TIMESTAMPTZ,
  rejection_reason                TEXT,
  pc_template_migration_pending   BOOLEAN     DEFAULT false,
  coi_file_url                    TEXT,
  coi_expires_at                  DATE,
  coi_insurer                     TEXT,
  coi_policy_number               TEXT,
  coi_uploaded_at                 TIMESTAMPTZ,
  coi_reminder_30_sent_at         TIMESTAMPTZ,
  coi_reminder_14_sent_at         TIMESTAMPTZ,
  coi_reminder_7_sent_at          TIMESTAMPTZ,
  coi_expired_notified_at         TIMESTAMPTZ,
  ic_24511_attestation            JSONB       DEFAULT '{}'::jsonb,
  attestation_accepted_at         TIMESTAMPTZ,
  attestation_signer_name         TEXT,
  attestation_signer_title        TEXT,
  attestation_text_version        TEXT,
  sms_consent_ts                  TIMESTAMPTZ,
  default_auto_renew              BOOLEAN     DEFAULT false,
  cpa_version                     TEXT        NOT NULL DEFAULT 'v1-2026-04'::text,
  cpa_accepted_at                 TIMESTAMPTZ,
  -- Columns added by tracked migrations (v58, v59, v63, v63b, v72, v75, v79)
  -- Safe to include here because all tracked migrations use ADD COLUMN IF NOT EXISTS
  onboarding_step                 INT         NOT NULL DEFAULT 1,
  partial_completion_email_sent_at TIMESTAMPTZ,
  template_review_role            TEXT,
  cert_status                     JSONB,
  intro_video_path                TEXT,
  wc_cert_file_ref                TEXT,
  wc_cert_expiry                  DATE,
  wc_cert_uploaded_at             TIMESTAMPTZ,
  license_path                    TEXT,
  license_document_url            TEXT,
  license_attestation_signed_at   TIMESTAMPTZ,
  legacy_pre_approval             BOOLEAN     NOT NULL DEFAULT false,
  wc_cert_reminder_30_sent_at     TIMESTAMPTZ,
  needs_cpa_reattestation         BOOLEAN     NOT NULL DEFAULT false,
  CONSTRAINT contractors_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 8. referral_agents
--    RE agents, inspectors, and customer referrers.
--    Defined before claims because claims.referral_agent_id references it.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referral_agents (
  id                       UUID        NOT NULL DEFAULT gen_random_uuid(),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  agent_type               TEXT        NOT NULL,
  first_name               TEXT        NOT NULL,
  last_name                TEXT        NOT NULL,
  email                    TEXT        NOT NULL,
  phone                    TEXT,
  company                  TEXT,
  photo_url                TEXT,
  bio                      TEXT,
  website                  TEXT,
  service_area             TEXT,
  unique_code              TEXT        NOT NULL,
  status                   TEXT        NOT NULL DEFAULT 'active'::text,
  onboarded_at             TIMESTAMPTZ,
  total_referrals          INT         DEFAULT 0,
  total_commission_earned  NUMERIC     DEFAULT 0,
  total_commission_paid    NUMERIC     DEFAULT 0,
  user_id                  UUID,
  metadata                 JSONB       DEFAULT '{}'::jsonb,
  recruit_code             TEXT,
  recruited_by_id          UUID,
  recruited_at             TIMESTAMPTZ,
  recruit_earnings         NUMERIC     DEFAULT 0,
  referred_by_note         TEXT,
  w9_file_url              TEXT,
  w9_submitted_at          TIMESTAMPTZ,
  w9_verified_at           TIMESTAMPTZ,
  payments_blocked         BOOLEAN     NOT NULL DEFAULT true,
  w9_notification_sent_at  TIMESTAMPTZ,
  CONSTRAINT referral_agents_pkey             PRIMARY KEY (id),
  CONSTRAINT referral_agents_email_key        UNIQUE (email),
  CONSTRAINT referral_agents_unique_code_key  UNIQUE (unique_code),
  CONSTRAINT referral_agents_recruit_code_key UNIQUE (recruit_code)
);

-- ---------------------------------------------------------------------------
-- 9. claims
--    Core claim record — hub of the entire homeowner pipeline.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.claims (
  id                               UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id                          UUID        NOT NULL,
  claim_number                     TEXT,
  status                           TEXT        DEFAULT 'documents_needed'::text,
  created_at                       TIMESTAMPTZ DEFAULT now(),
  updated_at                       TIMESTAMPTZ DEFAULT now(),
  carrier_id                       UUID,
  adjuster_id                      UUID,
  adjuster_name                    TEXT,
  adjuster_email                   TEXT,
  adjuster_phone                   TEXT,
  ingest_email                     TEXT,
  material_category                TEXT,
  shingle_type                     TEXT,
  impact_class                     TEXT,
  designer_product                 TEXT,
  designer_manufacturer            TEXT,
  metal_type                       TEXT,
  metal_material                   TEXT,
  color_brand                      TEXT,
  color_name                       TEXT,
  color_selected_at                TIMESTAMPTZ,
  color_addendum_signed            BOOLEAN     DEFAULT false,
  hover_order_id                   TEXT,
  hover_status                     TEXT,
  hover_paid                       BOOLEAN     DEFAULT false,
  hover_rebated                    BOOLEAN     DEFAULT false,
  has_estimate                     BOOLEAN     DEFAULT false,
  has_measurements                 BOOLEAN     DEFAULT false,
  has_material_selection           BOOLEAN     DEFAULT false,
  ready_for_bids                   BOOLEAN     DEFAULT false,
  bids_submitted_at                TIMESTAMPTZ,
  selected_contractor_id           UUID,
  contract_signed_at               TIMESTAMPTZ,
  docusign_envelope_id             TEXT,
  deductible_amount                NUMERIC,
  deductible_collected             BOOLEAN     DEFAULT false,
  deductible_stripe_id             TEXT,
  platform_fee_charged             BOOLEAN     DEFAULT false,
  platform_fee_amount              NUMERIC,
  platform_fee_stripe_id           TEXT,
  estimate_filename                TEXT,
  measurements_filename            TEXT,
  date_of_loss                     DATE,
  damage_type                      TEXT        DEFAULT 'roof'::text,
  job_type                         TEXT,
  rcv_amount                       NUMERIC,
  acv_amount                       NUMERIC,
  roof_squares                     NUMERIC,
  repair_squares                   NUMERIC,
  existing_shingle_brand           TEXT,
  existing_shingle_product         TEXT,
  existing_shingle_color           TEXT,
  urgency                          TEXT        DEFAULT 'flexible'::text,
  urgency_deadline                 DATE,
  urgency_reason                   TEXT,
  homeowner_notes                  TEXT,
  referral_code                    TEXT,
  referral_id                      UUID,
  policy_type                      TEXT,
  funding_type                     TEXT,
  trades                           TEXT[]      DEFAULT '{}'::text[],
  repair_type                      TEXT,
  repair_description               TEXT,
  repair_shingle_count             INT,
  roof_age_years                   INT,
  material_id_method               TEXT,
  material_id_status               TEXT        DEFAULT 'pending'::text,
  itel_order_id                    TEXT,
  itel_status                      TEXT,
  ai_id_confidence                 NUMERIC,
  trade_intents                    JSONB       DEFAULT '[]'::jsonb,
  color_confirmation_envelope_id   TEXT,
  contract_sent_at                 TIMESTAMPTZ,
  contract_signed_by               TEXT,
  selected_bid_amount              NUMERIC,
  deductible_collected_at          TIMESTAMPTZ,
  homeowner_name                   TEXT,
  contract_declined_at             TIMESTAMPTZ,
  contract_voided_at               TIMESTAMPTZ,
  color_confirmed_at               TIMESTAMPTZ,
  property_address                 TEXT,
  ingest_email_address             TEXT,
  parsed_line_items                JSONB,
  contractor_scope_summary         TEXT,
  loss_sheet_parsed_at             TIMESTAMPTZ,
  project_confirmation             JSONB,
  project_confirmation_envelope_id TEXT,
  referral_source                  TEXT,
  referral_agent_id                UUID,
  contractor_switched_at           TIMESTAMPTZ,
  contractor_switch_count          INT         NOT NULL DEFAULT 0,
  siding_bid_released_at           TIMESTAMPTZ,
  roofing_bid_released_at          TIMESTAMPTZ,
  gutters_bid_released_at          TIMESTAMPTZ,
  windows_bid_released_at          TIMESTAMPTZ,
  bid_window_expires_at            TIMESTAMPTZ,
  bid_window_notified_at           TIMESTAMPTZ,
  property_state                   TEXT,
  -- Columns added by tracked migrations (v53: switch_reason_survey; v68: completion_date)
  -- Safe to include: all tracked migrations use ADD COLUMN IF NOT EXISTS
  switch_reason_survey             JSONB,
  completion_date                  TIMESTAMPTZ,
  video_url                        TEXT,
  CONSTRAINT claims_pkey                     PRIMARY KEY (id),
  CONSTRAINT claims_ingest_email_key         UNIQUE (ingest_email),
  CONSTRAINT claims_ingest_email_address_key UNIQUE (ingest_email_address)
);

-- ---------------------------------------------------------------------------
-- 10. hover_orders
--     One Hover measurement order per claim.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hover_orders (
  id                                   UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id                             UUID        NOT NULL,
  user_id                              UUID        NOT NULL,
  hover_job_id                         TEXT,
  status                               TEXT        DEFAULT 'pending'::text,
  hover_link                           TEXT,
  amount_charged                       NUMERIC,
  stripe_payment_id                    TEXT,
  rebated                              BOOLEAN     DEFAULT false,
  rebate_stripe_id                     TEXT,
  report_url                           TEXT,
  created_at                           TIMESTAMPTZ DEFAULT now(),
  updated_at                           TIMESTAMPTZ DEFAULT now(),
  capture_request_id                   INT,
  capture_request_identifier           TEXT,
  capture_link                         TEXT,
  deliverable_type_id                  INT         DEFAULT 2,
  model_id                             INT,
  capturing_user_email                 TEXT,
  capturing_user_phone                 TEXT,
  measurements_json                    JSONB,
  resend_count                         INT         NOT NULL DEFAULT 0,
  last_resend_at                       TIMESTAMPTZ,
  -- Columns added by tracked migrations (v55: material_list; v54: D-181 payment model)
  material_list                        JSONB,
  homeowner_charge_amount              INT,
  homeowner_stripe_payment_intent_id   TEXT,
  rebate_due                           BOOLEAN     DEFAULT false,
  rebate_paid_at                       TIMESTAMPTZ,
  CONSTRAINT hover_orders_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 11. hover_tokens
--     OAuth token storage for Hover API. Single-row pattern.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hover_tokens (
  id            UUID        NOT NULL DEFAULT gen_random_uuid(),
  access_token  TEXT        NOT NULL,
  refresh_token TEXT        NOT NULL,
  token_type    TEXT        DEFAULT 'Bearer'::text,
  expires_at    TIMESTAMPTZ NOT NULL,
  scope         TEXT        DEFAULT 'all'::text,
  owner_id      INT,
  owner_type    TEXT,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  account_label TEXT        DEFAULT 'otterquote'::text,
  CONSTRAINT hover_tokens_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 12. documents
--     Files uploaded by homeowners (estimate PDFs, loss sheets, etc.).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.documents (
  id            UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id      UUID        NOT NULL,
  user_id       UUID        NOT NULL,
  file_name     TEXT        NOT NULL,
  file_type     TEXT        NOT NULL,
  file_size     BIGINT      NOT NULL,
  storage_path  TEXT        NOT NULL,
  doc_category  TEXT        DEFAULT 'other'::text,
  created_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT documents_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 13. quotes
--     Contractor bids on claims. Becomes the platform fee record on signing.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.quotes (
  id                         UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id                   UUID        NOT NULL,
  contractor_id              UUID        NOT NULL,
  total_price                NUMERIC     NOT NULL,
  estimated_days             INT,
  timeline_note              TEXT,
  scope_summary              TEXT,
  notes                      TEXT,
  fee_percentage             NUMERIC     NOT NULL,
  fee_amount                 NUMERIC     NOT NULL,
  fee_agreed                 BOOLEAN     DEFAULT false,
  fee_agreed_at              TIMESTAMPTZ,
  status                     TEXT        DEFAULT 'submitted'::text,
  created_at                 TIMESTAMPTZ DEFAULT now(),
  updated_at                 TIMESTAMPTZ DEFAULT now(),
  decking_price_per_sheet    NUMERIC,
  full_redeck_price          NUMERIC,
  supplement_acknowledged    BOOLEAN     DEFAULT false,
  trade_type                 TEXT,
  is_bundled_bid             BOOLEAN     DEFAULT false,
  bundled_trades             TEXT[]      DEFAULT '{}'::text[],
  per_trade_breakdown        JSONB,
  value_adds                 JSONB,
  payment_intent_id          TEXT,
  payment_status             TEXT,
  docusign_envelope_id       TEXT,
  contractor_signed_at       TIMESTAMPTZ,
  homeowner_signed_at        TIMESTAMPTZ,
  is_auto_bid                BOOLEAN     DEFAULT false,
  payment_method_id          UUID,
  payment_method_type        TEXT,
  card_fee_cents             INT,
  cancelled_at               TIMESTAMPTZ,
  cancellation_reason        TEXT,
  expires_at                 TIMESTAMPTZ,
  auto_renew                 BOOLEAN     DEFAULT false,
  renewed_from_quote_id      UUID,
  expired_at                 TIMESTAMPTZ,
  bid_status                 TEXT        NOT NULL DEFAULT 'active'::text,
  -- Columns added by tracked migrations (v64: warranty/material; v70: warranty doc; v62: fee fields)
  warranty_option_id         UUID,
  warranty_snapshot          TEXT,
  material_selection         JSONB,
  workmanship_warranty_years INT,
  warranty_document_url      TEXT,
  warranty_uploaded_at       TIMESTAMPTZ,
  platform_fee_pct           NUMERIC,
  platform_fee_basis         TEXT,
  fee_accepted_at            TIMESTAMPTZ,
  CONSTRAINT quotes_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 14. notifications
--     Audit log of all emails and SMS sent through the platform.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id                UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id           UUID,
  claim_id          UUID,
  channel           TEXT        NOT NULL,
  notification_type TEXT        NOT NULL,
  recipient         TEXT        NOT NULL,
  message_preview   TEXT,
  sent_at           TIMESTAMPTZ DEFAULT now(),
  delivered         BOOLEAN,
  twilio_sid        TEXT,
  mailgun_id        TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  read_at           TIMESTAMPTZ,
  CONSTRAINT notifications_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 15. activity_log
--     Append-only audit trail for all significant platform events.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activity_log (
  id          UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL,
  event_type  TEXT        NOT NULL,
  title       TEXT        NOT NULL,
  metadata    JSONB       DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT activity_log_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 16. platform_settings
--     Key-value store for runtime-configurable platform parameters.
--     key is the primary key (text). Values are JSONB.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_settings (
  key        TEXT        NOT NULL,
  value      JSONB       NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT platform_settings_pkey PRIMARY KEY (key)
);

-- ---------------------------------------------------------------------------
-- 17. platform_alerts_log
--     Internal alert/notification log for operational monitoring.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_alerts_log (
  id              UUID        NOT NULL DEFAULT gen_random_uuid(),
  alert_type      TEXT        NOT NULL,
  function_name   TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  sent_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  acknowledged_at TIMESTAMPTZ,
  CONSTRAINT platform_alerts_log_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 18. adjuster_email_requests
--     Tracks outbound adjuster contact emails for loss-sheet ingest.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.adjuster_email_requests (
  id                UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id          UUID        NOT NULL,
  adjuster_id       UUID,
  to_email          TEXT        NOT NULL,
  to_name           TEXT,
  request_type      TEXT        NOT NULL,
  ingest_email      TEXT        NOT NULL,
  sent_at           TIMESTAMPTZ DEFAULT now(),
  response_received BOOLEAN     DEFAULT false,
  response_at       TIMESTAMPTZ,
  followup_sent     BOOLEAN     DEFAULT false,
  followup_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT adjuster_email_requests_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 19. contractor_certifications
--     Manufacturer certifications (legacy — pre-D-204 structure).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contractor_certifications (
  id                   UUID        NOT NULL DEFAULT gen_random_uuid(),
  contractor_id        UUID        NOT NULL,
  certification_name   TEXT        NOT NULL,
  issuing_organization TEXT,
  certification_number TEXT,
  expiration_date      DATE,
  verified             BOOLEAN     DEFAULT false,
  created_at           TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT contractor_certifications_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 20. contractor_payment_methods
--     Stripe payment methods saved per contractor.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contractor_payment_methods (
  id                        UUID        NOT NULL DEFAULT gen_random_uuid(),
  contractor_id             UUID        NOT NULL,
  stripe_payment_method_id  TEXT        NOT NULL,
  payment_type              TEXT        NOT NULL,
  last_four                 TEXT,
  brand                     TEXT,
  bank_name                 TEXT,
  is_default                BOOLEAN     NOT NULL DEFAULT false,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT contractor_payment_methods_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 21. claim_trade_items
--     Per-trade line items parsed from the insurance estimate.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.claim_trade_items (
  id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id            UUID,
  trade               TEXT        NOT NULL,
  scope               TEXT,
  estimated_amount    NUMERIC,
  depreciation_amount NUMERIC,
  sides_affected      TEXT,
  homeowner_decision  TEXT,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT claim_trade_items_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 22. inspection_bookings
--     Pre-bid inspection scheduling (legacy flow — rarely used).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inspection_bookings (
  id                          UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id                    UUID        NOT NULL,
  contractor_id               UUID,
  homeowner_id                UUID        NOT NULL,
  scheduled_date              DATE        NOT NULL,
  scheduled_time              TEXT        NOT NULL,
  status                      TEXT        DEFAULT 'scheduled'::text,
  inspection_type             TEXT,
  inspection_fee              NUMERIC     DEFAULT 0,
  homeowner_guarantee_paid    BOOLEAN     DEFAULT false,
  contractor_penalty_charged  BOOLEAN     DEFAULT false,
  notes                       TEXT,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT inspection_bookings_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 23. job_assignments
--     Snapshot record created when a homeowner selects a contractor.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_assignments (
  id                 UUID        NOT NULL DEFAULT gen_random_uuid(),
  claim_id           UUID        NOT NULL,
  quote_id           UUID        NOT NULL,
  contractor_id      UUID        NOT NULL,
  homeowner_id       UUID        NOT NULL,
  quoted_price       NUMERIC     NOT NULL,
  fee_percentage     NUMERIC     NOT NULL,
  fee_amount         NUMERIC     NOT NULL,
  fee_status         TEXT        DEFAULT 'pending'::text,
  stripe_charge_id   TEXT,
  contract_signed    BOOLEAN     DEFAULT false,
  contract_signed_at TIMESTAMPTZ,
  status             TEXT        DEFAULT 'pending_contract'::text,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT job_assignments_pkey      PRIMARY KEY (id),
  CONSTRAINT job_assignments_claim_id_key UNIQUE (claim_id)
);

-- ---------------------------------------------------------------------------
-- 24. payment_failures
--     Dunning queue for failed contractor platform-fee payments.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_failures (
  id                    UUID        NOT NULL DEFAULT gen_random_uuid(),
  quote_id              UUID,
  contractor_id         UUID,
  claim_id              UUID,
  homeowner_id          UUID,
  amount_cents          INT         NOT NULL,
  stripe_error          TEXT,
  dunning_status        TEXT        DEFAULT 'active'::text,
  created_at            TIMESTAMPTZ DEFAULT now(),
  resolved_at           TIMESTAMPTZ,
  next_reminder_at      TIMESTAMPTZ,
  reminder_count        INT         DEFAULT 0,
  contractor_timezone   TEXT        DEFAULT 'America/New_York'::text,
  warning_at            TIMESTAMPTZ,
  homeowner_notify_at   TIMESTAMPTZ,
  CONSTRAINT payment_failures_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 25. feature_requests
--     Contractor-submitted feature request inbox.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feature_requests (
  id               UUID        NOT NULL DEFAULT gen_random_uuid(),
  contractor_id    UUID,
  contractor_name  TEXT,
  contractor_email TEXT,
  request_text     TEXT        NOT NULL,
  created_at       TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT feature_requests_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 26. imported_hover_jobs
--     Hover jobs imported from legacy Stohler Roofing account for outreach.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.imported_hover_jobs (
  id                UUID        NOT NULL DEFAULT gen_random_uuid(),
  hover_job_id      INT         NOT NULL,
  hover_job_name    TEXT,
  full_address      TEXT,
  address_line1     TEXT,
  city              TEXT,
  state             TEXT,
  zip               TEXT,
  contact_name      TEXT,
  contact_email     TEXT,
  contact_phone     TEXT,
  hover_status      TEXT,
  hover_created_at  TIMESTAMPTZ,
  hover_completed_at TIMESTAMPTZ,
  raw_metadata      JSONB,
  outreach_status   TEXT        NOT NULL DEFAULT 'pending'::text,
  outreach_notes    TEXT,
  imported_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT imported_hover_jobs_pkey           PRIMARY KEY (id),
  CONSTRAINT imported_hover_jobs_hover_job_id_key UNIQUE (hover_job_id)
);

-- ---------------------------------------------------------------------------
-- 27. expansion_waitlist
--     Homeowners who opted in for notification when their state goes live.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expansion_waitlist (
  id          UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id     UUID,
  claim_id    UUID,
  state       TEXT        NOT NULL,
  opted_in    BOOLEAN     DEFAULT false,
  opted_in_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT expansion_waitlist_pkey             PRIMARY KEY (id),
  CONSTRAINT expansion_waitlist_user_state_unique UNIQUE (user_id, state)
);

-- ---------------------------------------------------------------------------
-- 28. referrals
--     Individual referral events (click-through → claim → commission).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  id                       UUID        NOT NULL DEFAULT gen_random_uuid(),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  referral_agent_id        UUID        NOT NULL,
  claim_id                 UUID,
  homeowner_name           TEXT,
  homeowner_email          TEXT,
  homeowner_phone          TEXT,
  status                   TEXT        NOT NULL DEFAULT 'clicked'::text,
  job_value                NUMERIC,
  commission_amount        NUMERIC,
  commission_paid_at       TIMESTAMPTZ,
  landing_page             TEXT,
  utm_source               TEXT,
  utm_medium               TEXT,
  utm_campaign             TEXT,
  metadata                 JSONB       DEFAULT '{}'::jsonb,
  recruit_commission_amount NUMERIC    DEFAULT 0,
  recruit_paid_at          TIMESTAMPTZ,
  CONSTRAINT referrals_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 29. payout_approvals
--     Manual approval queue for referral/recruit commission payouts.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payout_approvals (
  id                   UUID        NOT NULL DEFAULT gen_random_uuid(),
  referral_id          UUID,
  payout_type          TEXT        NOT NULL,
  partner_id           UUID,
  partner_name         TEXT,
  amount               NUMERIC     NOT NULL,
  trigger_event        TEXT,
  status               TEXT        NOT NULL DEFAULT 'pending_approval'::text,
  rejection_reason     TEXT,
  auto_approve_at      TIMESTAMPTZ,
  approved_at          TIMESTAMPTZ,
  rejected_at          TIMESTAMPTZ,
  approved_by          TEXT,
  reminder_sent_at     TIMESTAMPTZ,
  notification_sent_at TIMESTAMPTZ,
  created_at           TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT payout_approvals_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- 30. disputes
--     Stripe dispute records (D-228). Stub table created pre-tracking.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.disputes (
  id                         UUID        NOT NULL DEFAULT gen_random_uuid(),
  stripe_dispute_id          TEXT        NOT NULL,
  stripe_charge_id           TEXT,
  stripe_payment_intent_id   TEXT,
  claim_id                   UUID,
  quote_id                   UUID,
  contractor_id              UUID,
  amount                     INT         NOT NULL,
  currency                   TEXT        NOT NULL DEFAULT 'usd'::text,
  reason                     TEXT,
  status                     TEXT        NOT NULL,
  livemode                   BOOLEAN     NOT NULL DEFAULT false,
  routing                    TEXT        NOT NULL,
  evidence_submitted_at      TIMESTAMPTZ,
  evidence_payload           JSONB,
  auto_submit_result         JSONB,
  auto_submit_error          TEXT,
  contractor_mark_complete_at   TIMESTAMPTZ,
  homeowner_acknowledgment_at   TIMESTAMPTZ,
  stub_notes                 TEXT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT disputes_pkey                  PRIMARY KEY (id),
  CONSTRAINT disputes_stripe_dispute_id_key UNIQUE (stripe_dispute_id)
);

-- ---------------------------------------------------------------------------
-- 31. admin_dispute_queue
--     Admin-facing queue for manual dispute resolution (D-228 >$500 routing).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_dispute_queue (
  id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
  dispute_id          UUID        NOT NULL,
  stripe_dispute_id   TEXT        NOT NULL,
  amount              INT         NOT NULL,
  reason              TEXT,
  claim_id            UUID,
  contractor_id       UUID,
  stripe_dispute_url  TEXT,
  clickup_task_id     TEXT,
  clickup_task_url    TEXT,
  status              TEXT        NOT NULL DEFAULT 'open'::text,
  resolved_at         TIMESTAMPTZ,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT admin_dispute_queue_pkey PRIMARY KEY (id)
);

-- =============================================================================
-- INDEXES
-- =============================================================================
-- Only indexes on tables defined in this file.
-- Indexes created by tracked migrations are excluded (they use IF NOT EXISTS
-- and will apply cleanly after this file runs on a fresh branch).

-- claims
CREATE INDEX IF NOT EXISTS idx_claims_user_id        ON public.claims (user_id);
CREATE INDEX IF NOT EXISTS idx_claims_status         ON public.claims (status);
CREATE INDEX IF NOT EXISTS idx_claims_selected_contractor_id
  ON public.claims (selected_contractor_id);

-- quotes
CREATE INDEX IF NOT EXISTS idx_quotes_claim_id       ON public.quotes (claim_id);
CREATE INDEX IF NOT EXISTS idx_quotes_contractor_id  ON public.quotes (contractor_id);
CREATE INDEX IF NOT EXISTS idx_quotes_status         ON public.quotes (status);

-- documents
CREATE INDEX IF NOT EXISTS idx_documents_claim_id    ON public.documents (claim_id);

-- hover_orders
CREATE INDEX IF NOT EXISTS idx_hover_orders_claim_id ON public.hover_orders (claim_id);
CREATE INDEX IF NOT EXISTS idx_hover_orders_rebate_due
  ON public.hover_orders (rebate_due)
  WHERE rebate_due = true AND rebate_paid_at IS NULL;

-- activity_log
CREATE INDEX IF NOT EXISTS idx_activity_log_user_id  ON public.activity_log (user_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON public.activity_log (created_at DESC);

-- notifications
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_claim_id ON public.notifications (claim_id);

-- payment_failures
CREATE INDEX IF NOT EXISTS idx_payment_failures_contractor_id
  ON public.payment_failures (contractor_id);
CREATE INDEX IF NOT EXISTS idx_payment_failures_dunning_status
  ON public.payment_failures (dunning_status);

-- referrals
CREATE INDEX IF NOT EXISTS idx_referrals_referral_agent_id
  ON public.referrals (referral_agent_id);
CREATE INDEX IF NOT EXISTS idx_referrals_claim_id    ON public.referrals (claim_id);

-- disputes
CREATE INDEX IF NOT EXISTS idx_disputes_claim_id     ON public.disputes (claim_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status       ON public.disputes (status);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE public.profiles IS
  'Central user profile table. id mirrors auth.users(id). Homeowner and admin rows live here; contractor rows are joined via contractors.user_id.';

COMMENT ON TABLE public.claims IS
  'Core claim/project record. Hub of the homeowner pipeline. Status column drives the 8-stage dashboard (D-013).';

COMMENT ON TABLE public.contractors IS
  'Contractor company accounts. Onboarding, compliance, billing, and notification settings all live here.';

COMMENT ON TABLE public.quotes IS
  'Contractor bids on claims. Becomes the authoritative fee record on DocuSign contract signing.';

COMMENT ON TABLE public.hover_orders IS
  'Hover measurement orders. One per claim. D-181 payment columns track homeowner charge and rebate state.';

COMMENT ON TABLE public.platform_settings IS
  'Runtime-configurable key/value settings. All server-side prices and feature flags read from here.';

COMMENT ON TABLE public.disputes IS
  'D-228: Stripe dispute records. Stub created pre-migration-tracking. charge.dispute.created webhook handler populates this table.';

COMMENT ON TABLE public.admin_dispute_queue IS
  'D-228: Admin queue for manual dispute review (>$500 or non-delivery allegations).';

COMMIT;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Run after apply on a branch to confirm all 31 tables are present:
--
-- SELECT table_name
--   FROM information_schema.tables
--  WHERE table_schema = 'public'
--    AND table_type = 'BASE TABLE'
--    AND table_name IN (
--      'profiles','leads','members','material_catalog','carrier_profiles',
--      'adjusters','contractors','referral_agents','claims','hover_orders',
--      'hover_tokens','documents','quotes','notifications','activity_log',
--      'platform_settings','platform_alerts_log','adjuster_email_requests',
--      'contractor_certifications','contractor_payment_methods',
--      'claim_trade_items','inspection_bookings','job_assignments',
--      'payment_failures','feature_requests','imported_hover_jobs',
--      'expansion_waitlist','referrals','payout_approvals',
--      'disputes','admin_dispute_queue'
--    )
--  ORDER BY table_name;
-- Expected: 31 rows.

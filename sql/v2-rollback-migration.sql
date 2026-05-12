-- Rollback for v2-migration.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS hover_orders CASCADE;
DROP TABLE IF EXISTS material_catalog CASCADE;
DROP TABLE IF EXISTS adjuster_email_requests CASCADE;
DROP TABLE IF EXISTS adjusters CASCADE;
DROP TABLE IF EXISTS carrier_profiles CASCADE;

-- Drop columns added by this migration
ALTER TABLE profiles DROP COLUMN IF EXISTS phone CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS address_street CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS address_city CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS address_state CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS address_zip CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS referral_source CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS referring_agent_name CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS referring_agent_email CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS carrier_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_name CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_email CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS adjuster_phone CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS ingest_email CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS material_category CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS shingle_type CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS impact_class CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS designer_product CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS designer_manufacturer CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS metal_type CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS metal_material CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS color_brand CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS color_name CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS color_selected_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS color_addendum_signed CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS hover_order_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS hover_status CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS hover_paid CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS hover_rebated CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS has_estimate CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS has_measurements CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS has_material_selection CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS ready_for_bids CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS bids_submitted_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS selected_contractor_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS contract_signed_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS docusign_envelope_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_collected CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS deductible_stripe_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS platform_fee_charged CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS platform_fee_amount CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS platform_fee_stripe_id CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_notif_user;
DROP INDEX IF EXISTS idx_notif_claim;
DROP INDEX IF EXISTS idx_hover_claim;
DROP INDEX IF EXISTS idx_aer_ingest;
DROP INDEX IF EXISTS idx_aer_claim;
DROP INDEX IF EXISTS idx_adjusters_name;
DROP INDEX IF EXISTS idx_adjusters_carrier;

-- Drop triggers created by this migration

-- Drop functions created by this migration
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE carrier_profiles DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE adjusters DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE adjuster_email_requests DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE material_catalog DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE hover_orders DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM carrier_profiles;  -- REVIEW BEFORE RUNNING
-- DELETE FROM material_catalog;  -- REVIEW BEFORE RUNNING

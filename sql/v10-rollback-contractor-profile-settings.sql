-- Rollback for v10-contractor-profile-settings.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS contractor_certifications CASCADE;

-- Drop columns added by this migration
ALTER TABLE contractors DROP COLUMN IF EXISTS about_us CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS why_choose_us CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS owner_photo_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS preferred_brands CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS trades CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS service_counties CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS service_area_description CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS google_reviews_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS bbb_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS angi_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS yelp_url CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS color_selection_enabled CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS notification_emails CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS notification_phones CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS notification_preferences CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS status CASCADE;
ALTER TABLE contractors DROP COLUMN IF EXISTS updated_at CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS ready_for_bids CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS bids_submitted_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_notifications_claim_id;
DROP INDEX IF EXISTS idx_notifications_user_id;
DROP INDEX IF EXISTS idx_contractor_certs_contractor_id;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE contractor_certifications DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE
-- ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

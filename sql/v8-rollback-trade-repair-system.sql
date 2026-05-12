-- Rollback for v8-trade-repair-system.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS inspection_bookings CASCADE;

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS funding_type CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS trades CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS repair_type CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS repair_description CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS repair_shingle_count CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS roof_age_years CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS material_id_method CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS material_id_status CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS itel_order_id CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS itel_status CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS ai_id_confidence CASCADE;
ALTER TABLE claims DROP COLUMN IF EXISTS trade_intents CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS trade_type CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS is_bundled_bid CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS bundled_trades CASCADE;
ALTER TABLE quotes DROP COLUMN IF EXISTS per_trade_breakdown CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_inspection_bookings_date;
DROP INDEX IF EXISTS idx_inspection_bookings_contractor;
DROP INDEX IF EXISTS idx_inspection_bookings_claim;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE inspection_bookings DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

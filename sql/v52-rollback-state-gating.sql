-- Rollback for v52-state-gating.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS expansion_waitlist CASCADE;

-- Drop columns added by this migration
ALTER TABLE claims DROP COLUMN IF EXISTS property_state CASCADE;

-- Drop constraints added by this migration
-- (expansion_waitlist dropped above; constraint gone with it)

-- Drop indexes created by this migration
DROP INDEX IF EXISTS claims_property_state_idx;
DROP INDEX IF EXISTS expansion_waitlist_user_id_idx;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE expansion_waitlist DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

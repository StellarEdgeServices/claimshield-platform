-- Rollback for v27-bid-change-notifications.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE notifications DROP COLUMN IF EXISTS read_at CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_notifications_type;
DROP INDEX IF EXISTS idx_notifications_read_at;

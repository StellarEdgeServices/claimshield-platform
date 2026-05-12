-- Rollback for v24-hover-import.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop tables created by this migration (reverse order)
DROP TABLE IF EXISTS imported_hover_jobs CASCADE;

-- Drop columns added by this migration
ALTER TABLE hover_tokens DROP COLUMN IF EXISTS account_label CASCADE;

-- Drop indexes created by this migration
DROP INDEX IF EXISTS idx_imported_hover_jobs_raw_metadata;
DROP INDEX IF EXISTS idx_imported_hover_jobs_outreach_status;
DROP INDEX IF EXISTS idx_imported_hover_jobs_contact_email;
DROP INDEX IF EXISTS idx_imported_hover_jobs_hover_job_id;

-- Disable RLS enabled by this migration (CAUTION: may expose rows)
-- ALTER TABLE imported_hover_jobs DISABLE ROW LEVEL SECURITY;  -- UNCOMMENT WITH CARE

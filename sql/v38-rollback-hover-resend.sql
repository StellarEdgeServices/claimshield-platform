-- Rollback for v38-hover-resend.sql
-- Generated 2026-05-12 | Tier 3 deploy required (D-182)
-- Run ONLY after confirming the forward migration is what you're rolling back.

-- Drop columns added by this migration
ALTER TABLE hover_orders DROP COLUMN IF EXISTS resend_count CASCADE;

-- Seed data inserted by this migration
-- Review carefully before running DELETE — this removes ALL rows from these tables:
-- DELETE FROM rate_limit_config;  -- REVIEW BEFORE RUNNING

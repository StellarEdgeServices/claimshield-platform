-- =============================================================================
-- v0-base-schema-rollback.sql  —  OtterQuote Base Schema Rollback
-- =============================================================================
-- PURPOSE
--   Companion rollback for v0-base-schema.sql.
--   Drops all 31 pre-v53 tables in reverse dependency order.
--
-- SAFETY
--   Every statement uses DROP TABLE IF EXISTS — safe to run on a branch
--   where some tables were never created (partial apply scenarios).
--
-- ⚠️  DO NOT RUN ON PRODUCTION.
--   This will destroy all homeowner, contractor, claims, and quote data.
--   This file is intended for branch-level rollback ONLY.
--
-- DEPENDENCY ORDER (reverse of v0-base-schema.sql)
--   Tables that have FK dependents must drop after their dependents.
--   admin_dispute_queue → disputes (disputes referenced by admin_dispute_queue)
--   payout_approvals → referrals → referral_agents
--   expansion_waitlist, imported_hover_jobs, feature_requests → no dependents
--   payment_failures, job_assignments → quotes, claims
--   inspection_bookings, claim_trade_items → claims
--   contractor_payment_methods, contractor_certifications → contractors
--   adjuster_email_requests → claims, adjusters
--   activity_log, notifications → no FK deps (user_id is soft)
--   quotes → claims, contractors
--   documents, hover_orders → claims
--   claims → profiles, carriers, contractors, referral_agents
--   hover_tokens → standalone
--   adjusters → carrier_profiles
--   contractors → standalone
--   referral_agents → standalone
--   carrier_profiles, material_catalog, members, leads, profiles → standalone
-- =============================================================================

BEGIN;

-- Leaf tables first (no other tables reference them as FK targets)
DROP TABLE IF EXISTS public.admin_dispute_queue     CASCADE;
DROP TABLE IF EXISTS public.disputes                CASCADE;
DROP TABLE IF EXISTS public.payout_approvals        CASCADE;
DROP TABLE IF EXISTS public.referrals               CASCADE;
DROP TABLE IF EXISTS public.expansion_waitlist      CASCADE;
DROP TABLE IF EXISTS public.imported_hover_jobs     CASCADE;
DROP TABLE IF EXISTS public.feature_requests        CASCADE;
DROP TABLE IF EXISTS public.payment_failures        CASCADE;
DROP TABLE IF EXISTS public.job_assignments         CASCADE;
DROP TABLE IF EXISTS public.inspection_bookings     CASCADE;
DROP TABLE IF EXISTS public.claim_trade_items       CASCADE;
DROP TABLE IF EXISTS public.contractor_payment_methods CASCADE;
DROP TABLE IF EXISTS public.contractor_certifications CASCADE;
DROP TABLE IF EXISTS public.adjuster_email_requests CASCADE;
DROP TABLE IF EXISTS public.platform_alerts_log     CASCADE;
DROP TABLE IF EXISTS public.platform_settings       CASCADE;
DROP TABLE IF EXISTS public.activity_log            CASCADE;
DROP TABLE IF EXISTS public.notifications           CASCADE;
DROP TABLE IF EXISTS public.quotes                  CASCADE;
DROP TABLE IF EXISTS public.documents               CASCADE;
DROP TABLE IF EXISTS public.hover_orders            CASCADE;
DROP TABLE IF EXISTS public.hover_tokens            CASCADE;
DROP TABLE IF EXISTS public.claims                  CASCADE;
DROP TABLE IF EXISTS public.referral_agents         CASCADE;
DROP TABLE IF EXISTS public.contractors             CASCADE;
DROP TABLE IF EXISTS public.adjusters               CASCADE;
DROP TABLE IF EXISTS public.carrier_profiles        CASCADE;
DROP TABLE IF EXISTS public.material_catalog        CASCADE;
DROP TABLE IF EXISTS public.members                 CASCADE;
DROP TABLE IF EXISTS public.leads                   CASCADE;
DROP TABLE IF EXISTS public.profiles                CASCADE;

COMMIT;

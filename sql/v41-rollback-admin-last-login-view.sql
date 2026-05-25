-- Rollback: v41-rollback-admin-last-login-view.sql
-- Reverts: v41-admin-last-login-view.sql
-- Author: Wingman F-22 (automated)
-- Date: 2026-05-18
-- WARNING: Only run this if the forward migration needs to be undone in production.
--
-- Reverts: DROP the admin_contractor_last_logins view created in v41.
-- All associated GRANTs and REVOKEs are automatically removed when the view is dropped.
--
-- Safe to re-run: DROP VIEW IF EXISTS is idempotent.

DROP VIEW IF EXISTS public.admin_contractor_last_logins;

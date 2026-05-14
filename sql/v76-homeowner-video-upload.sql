-- v76: Homeowner video upload — video_url column on claims + Storage RLS
-- Feature task: 86e0v8c28
-- Applied via Supabase MCP on 2026-05-06 (commit e1ad3e7 added JS/HTML only).
-- This file recovers the DDL for D-182 / D-220 compliance.
-- Storage path convention: {user_id}/videos/{filename}
-- Bucket: claim-documents (private, created v-pre, predates this migration)
--
-- Companion rollback: v76-rollback-homeowner-video-upload.sql

-- 1. Add video_url column to claims table
ALTER TABLE claims
  ADD COLUMN IF NOT EXISTS video_url TEXT;

COMMENT ON COLUMN claims.video_url IS
  'Optional path within claim-documents storage bucket for the homeowner walkthrough video '
  '(MP4/MOV/WebM, max 250 MB, max 60 s). Null when no video uploaded. '
  'Read via signed URL (private bucket). Added v76 2026-05-06.';

-- 2. RLS policies on storage.objects for claim-documents homeowner video access.
--    Idempotent: DROP IF EXISTS before each CREATE.

-- Service role: full access to claim-documents (Edge Function signed URL generation)
DROP POLICY IF EXISTS "Service role full access claim docs" ON storage.objects;
CREATE POLICY "Service role full access claim docs"
  ON storage.objects FOR ALL
  USING (bucket_id = 'claim-documents' AND auth.role() = 'service_role');

-- Homeowners: upload their own videos (INSERT)
DROP POLICY IF EXISTS "homeowner_upload_own_video" ON storage.objects;
CREATE POLICY "homeowner_upload_own_video"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'claim-documents'
    AND (auth.uid())::text = (storage.foldername(name))[1]
    AND name LIKE 'videos/%'
  );

-- Homeowners: read their own videos (SELECT)
DROP POLICY IF EXISTS "homeowner_read_own_video" ON storage.objects;
CREATE POLICY "homeowner_read_own_video"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'claim-documents'
    AND (auth.uid())::text = (storage.foldername(name))[1]
    AND name LIKE 'videos/%'
  );

-- Homeowners: update their own videos (UPDATE — allows replace/overwrite)
DROP POLICY IF EXISTS "homeowner_update_own_video" ON storage.objects;
CREATE POLICY "homeowner_update_own_video"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'claim-documents'
    AND (auth.uid())::text = (storage.foldername(name))[1]
    AND name LIKE 'videos/%'
  );

-- Homeowners: delete their own videos (DELETE)
DROP POLICY IF EXISTS "homeowner_delete_own_video" ON storage.objects;
CREATE POLICY "homeowner_delete_own_video"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'claim-documents'
    AND (auth.uid())::text = (storage.foldername(name))[1]
    AND name LIKE 'videos/%'
  );

-- Rollback for v76-homeowner-video-upload.sql
-- Removes homeowner video RLS policies from claim-documents and drops claims.video_url.
--
-- ⚠️  Storage objects in claim-documents/videos/ are NOT deleted by this rollback —
--     any uploaded homeowner videos must be purged separately if needed.
--
-- Before running: redeploy get-started.html and dashboard.html with video upload
--     section removed so new uploads cannot occur during the rollback window.

-- Drop homeowner video RLS policies
DROP POLICY IF EXISTS "homeowner_upload_own_video"          ON storage.objects;
DROP POLICY IF EXISTS "homeowner_read_own_video"             ON storage.objects;
DROP POLICY IF EXISTS "homeowner_update_own_video"           ON storage.objects;
DROP POLICY IF EXISTS "homeowner_delete_own_video"           ON storage.objects;
DROP POLICY IF EXISTS "Service role full access claim docs"  ON storage.objects;

-- Drop video_url column from claims
-- ⚠️  This destroys any stored video_url values — confirm no active video data before rolling back.
ALTER TABLE claims
  DROP COLUMN IF EXISTS video_url;

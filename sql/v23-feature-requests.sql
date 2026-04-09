-- ============================================================
-- Feature Requests Table
-- Run this in Supabase SQL Editor (Database > SQL Editor)
-- ============================================================

create table if not exists feature_requests (
  id           uuid        default gen_random_uuid() primary key,
  contractor_id uuid        references contractors(id) on delete set null,
  contractor_name text,
  contractor_email text,
  request_text text        not null,
  created_at   timestamptz default now()
);

-- Row-Level Security: contractors can insert their own requests; no public read
alter table feature_requests enable row level security;

create policy "Contractors can submit feature requests"
  on feature_requests for insert
  to authenticated
  with check (true);

-- Only service_role (your backend/admin) can read all requests
-- (No SELECT policy = authenticated users can't read the table at all)

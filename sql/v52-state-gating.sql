-- v52-state-gating.sql
-- D-178: Homeowner state gating + expansion waitlist
-- Note: claims.status is unconstrained TEXT — no constraint modification needed.

-- 1. Add property_state to claims table
ALTER TABLE claims ADD COLUMN IF NOT EXISTS property_state TEXT;

-- 2. Create expansion_waitlist table
CREATE TABLE IF NOT EXISTS expansion_waitlist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  claim_id UUID REFERENCES claims(id),
  state TEXT NOT NULL,
  opted_in BOOLEAN DEFAULT false,
  opted_in_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Enable RLS on expansion_waitlist
ALTER TABLE expansion_waitlist ENABLE ROW LEVEL SECURITY;

-- 4. RLS policies
CREATE POLICY "Users read own waitlist entry" ON expansion_waitlist
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users insert own waitlist entry" ON expansion_waitlist
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own waitlist entry" ON expansion_waitlist
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Admin all" ON expansion_waitlist
  FOR ALL USING (auth.jwt() ->> 'email' = 'dustinstohler1@gmail.com');

-- 5. Unique constraint to support upsert by (user_id, state) and prevent duplicates
ALTER TABLE expansion_waitlist ADD CONSTRAINT expansion_waitlist_user_state_unique UNIQUE (user_id, state);

-- 6. Index for fast user_id lookups
CREATE INDEX IF NOT EXISTS expansion_waitlist_user_id_idx ON expansion_waitlist(user_id);
CREATE INDEX IF NOT EXISTS claims_property_state_idx ON claims(property_state);

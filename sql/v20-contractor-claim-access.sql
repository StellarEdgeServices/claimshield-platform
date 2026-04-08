-- v20: Contractor claim access for post-bid-submission visibility
--
-- Problem: Contractors can only see claims with status IN ('active','bidding','pending')
-- via the existing "Contractors can view biddable claims" policy.
-- Once a claim advances to 'contract_signed' (or other post-bidding statuses),
-- that policy blocks the contractor, so nested claim joins on the quotes table
-- return null — making their submitted bid row show "Unknown" location.
--
-- Fix: Add a separate SELECT policy that lets a contractor read any claim
-- for which they have submitted a quote. This is narrow and safe — a contractor
-- can only see claims they are already associated with via their own quotes row.
--
-- Applied: Session 79, April 8, 2026.

-- ── Policy: Contractors can read claims for their own quotes ──
-- A contractor's auth.uid() must match contractors.user_id, and their
-- contractor record's PK must appear in quotes.contractor_id for the target claim.
CREATE POLICY "Contractors can view claims for their quotes"
  ON claims
  FOR SELECT
  USING (
    id IN (
      SELECT q.claim_id
      FROM quotes q
      JOIN contractors c ON c.id = q.contractor_id
      WHERE c.user_id = auth.uid()
    )
  );

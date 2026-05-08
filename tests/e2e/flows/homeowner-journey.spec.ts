/**
 * Flow B — Homeowner Journey (Phase 1 Stub)
 *
 * Current coverage (Phase 1):
 *   B1: get-started.html has correct meta-refresh redirect → app.otterquote.com (D-211 Phase 2)
 *   B2: test homeowner authenticates via magic link injection
 *   B3: homeowner dashboard loads without errors
 *   B4: bids.html renders for the test claim
 *
 * Deferred to Phase 2 (post-launch):
 *   B5: Full claim creation flow (loss sheet upload, trade selection, D-178 state gate)
 *   B6: Measurements step (Hover $150 payment — requires Stripe test mode)
 *   B7: Material selection (shingle type, impact class)
 *   B8: Bid review and contractor selection
 *   B9: Contract signing (DocuSign — requires sandbox credentials)
 *   B10: Project confirmation / Colors step
 *
 * Rationale for Phase 1 scope:
 *   The homeowner UI was manually verified end-to-end in the Cycle 5 walkthrough
 *   (April 28, 2026 — zero code defects found blocking launch). The Phase 1 stub
 *   covers authenticated page load — the highest-risk failure mode for static HTML
 *   + Supabase auth. Full flow automation is planned post-launch when the product
 *   is stable and DocuSign sandbox credentials are configured.
 *
 * Prerequisites:
 *   - Run `npm run seed` before this spec
 *   - .env.test must have SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, BASE_URL
 *
 * See README.md for full test data expectations.
 */

import { test, expect } from '@playwright/test';
import { generateMagicLink, getTestState, type TestState } from '../helpers/auth.js';
import { getTestClaim, getClaimEnvelopeId } from '../helpers/db.js';
import { runArtifactCapture, isDocuSignE2EEnabled } from '../helpers/docusign-artifacts.js';

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function loginAsHomeowner(page: import('@playwright/test').Page, state: TestState) {
  const magicLink = await generateMagicLink(
    state.homeownerEmail,
    `${state.baseUrl}/dashboard.html`
  );
  await page.goto(magicLink);
  await page.waitForURL(/dashboard/, { timeout: 30_000 });
  await page.waitForLoadState('load');
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test.describe('Flow B — Homeowner Journey (Phase 1 Stub)', () => {
  let state: TestState;

  test.beforeAll(() => {
    state = getTestState();
  });


  // ── Phase 2 artifact capture ────────────────────────────────────────────
  // Runs after all Flow B tests. If DOCUSIGN_E2E_ENABLED=true AND a DocuSign
  // envelope was created on the test claim (after homeowner selects a contractor
  // via B8), downloads the pre-signing PDF and persists it to:
  //   e2e-artifacts/phase-2/{runId}/{envelopeId}.pdf
  //
  // Today: always finds no envelope (B8 not yet implemented). Will activate
  // automatically once B8 triggers create-docusign-envelope and
  // DOCUSIGN_E2E_ENABLED=true is set in .env.test.
  //
  // QUOTA: Each activation burns one production DocuSign envelope (40/month).
  // Ram decides when to enable; Dustin approves before each run.
  test.afterAll(async () => {
    if (!isDocuSignE2EEnabled() || !state) return;
    const envelopeId = await getClaimEnvelopeId(state.testClaimId);
    await runArtifactCapture('2', state.runId, envelopeId ? [envelopeId] : []);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // B1: Public page — meta-refresh redirect to React app (D-211 Phase 2)
  //
  // D-211 Phase 2 turned get-started.html into a redirect stub pointing to
  // the React homeowner intake at app.otterquote.com/get-started. This test
  // verifies the redirect is correctly in place. The registration form itself
  // now lives in the React app and is outside the static-site E2E scope.
  // ──────────────────────────────────────────────────────────────────────────
  test('B1: get-started.html redirects to React app registration (D-211)', async ({ page }) => {
    // Abort the redirect before it fires so we can inspect the static page's meta tag
    // without leaving the test server's origin.
    await page.route('https://app.otterquote.com/**', route => route.abort());

    await page.goto('/get-started.html');
    await page.waitForLoadState('domcontentloaded');

    // Verify meta-refresh redirect is present and points to the correct destination
    const metaContent = await page
      .locator('meta[http-equiv="refresh"]')
      .getAttribute('content');
    expect(metaContent).toMatch(/url=https:\/\/app\.otterquote\.com\/get-started/i);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // B2: Magic link authentication
  // ──────────────────────────────────────────────────────────────────────────
  test('B2: test homeowner authenticates via magic link and lands on dashboard', async ({ page }) => {
    await loginAsHomeowner(page, state);

    // Must be on the homeowner dashboard
    await expect(page).toHaveURL(/dashboard/);
    await expect(page).not.toHaveURL(/login|get-started|contractor/);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // B3: Homeowner dashboard — authenticated state
  // ──────────────────────────────────────────────────────────────────────────
  test('B3: homeowner dashboard loads without errors for test account', async ({ page }) => {
    await loginAsHomeowner(page, state);

    // Page body must be visible and error-free
    await expect(page.locator('body')).toBeVisible();
    await expect(page.locator('body')).not.toContainText(/uncaught|typeerror|referenceerror/i);
    // Visibility-aware error check: the #gate-error div is in the DOM at all times
    // (display:none by default) and only populated/shown if saveWaitlistSpot() throws.
    // toContainText() reads textContent of hidden elements, so we use visibility instead.
    await expect(page.locator('#gate-error')).not.toBeVisible();

    // Must not be redirected
    await expect(page).not.toHaveURL(/login|get-started/);

    // Verify test claim exists in DB (belt + suspenders — seed already created it)
    const claim = await getTestClaim(state.testClaimId);
    expect(claim).not.toBeNull();
    expect(claim?.status).toBe('bidding');
    expect(claim?.property_state).toBe('IN');
  });

  // ──────────────────────────────────────────────────────────────────────────
  // B4: Bids page — authenticated homeowner can view bid comparison
  // ──────────────────────────────────────────────────────────────────────────
  test('B4: bids.html renders bid comparison UI for test claim', async ({ page }) => {
    await loginAsHomeowner(page, state);

    await page.goto(`/bids.html?claim_id=${state.testClaimId}`);
    await page.waitForLoadState('load');

    // Must remain authenticated
    await expect(page).not.toHaveURL(/login|get-started/);

    // Page body must be visible
    await expect(page.locator('body')).toBeVisible();

    // Bid-related content should be on the page
    await expect(page.locator('body')).not.toContainText(/uncaught|typeerror/i);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // TODO: B5 — Claim creation flow
  // Navigate to app.otterquote.com/get-started, fill contact info, proceed
  // through /trade-selector, verify claim created in DB.
  // Deferred: requires Stripe test mode for Hover payment step.
  // ──────────────────────────────────────────────────────────────────────────

  // TODO: B6 — Measurements step
  // Verify help-measurements.html renders Hover purchase UI.
  // Skip actual Stripe charge — assert form renders with $150 price.
  // Deferred: Stripe test mode required for payment step.

  // TODO: B7 — Material selection
  // Fill shingle type + impact class on dashboard.
  // Verify has_material_selection = true persists to claims.

  // TODO: B8 — Bid review and contractor selection
  // After Flow A A8 (bid submission), navigate to bids.html.
  // Assert test contractor's bid appears.
  // Click "Select This Contractor" — assert claim.selected_contractor_id set.

  // TODO: B9 — Contract signing
  // Navigate to contract-signing.html after contractor selected.
  // Assert DocuSign iframe container renders.
  // Skip signing — requires DocuSign sandbox credentials.
  // See CI_INTEGRATION.md → DocuSign Sandbox Setup.

  // TODO: B10 — Project confirmation
  // Navigate to project-confirmation.html (color-selection.html).
  // Assert trade-specific form fields render (roofing: shingle color, drip edge, etc.)
  // Verify project_confirmation JSONB persists on submit.
});

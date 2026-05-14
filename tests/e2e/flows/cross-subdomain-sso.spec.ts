/**
 * Flow E — Cross-Subdomain SSO (D-212 regression test)
 * ClickUp 86e1bpk7b — May 12, 2026
 *
 * Verifies that a session established on otterquote.com persists when the user
 * navigates to app.otterquote.com. Locks in the D-212 token-only cookie pattern
 * (sb-otterquote-at + sb-otterquote-rt at Domain=.otterquote.com) and prevents
 * the silent-drop regression in which the full session JSON exceeded Chrome's
 * 4096-byte per-cookie limit.
 *
 * Coverage:
 *   E1: After magic-link auth on otterquote.com, the canonical cookies are set,
 *       carry Domain=.otterquote.com, and each is well under 2048 URL-encoded
 *       bytes. Size guard fails loudly if we ever drift back toward 4096.
 *   E2: Navigating to app.otterquote.com immediately surfaces an authenticated
 *       session — no redirect to a login route.
 *   E3: The user.id seen on app.otterquote.com after cross-subdomain navigation
 *       matches the user.id authenticated on otterquote.com.
 *
 * Environments:
 *   Runs against BASE_URL when it is a *.otterquote.com domain (prod or staging).
 *   Skips on Netlify preview URLs (no shared app subdomain available).
 *
 * Prerequisites:
 *   - npm run seed must have written the homeowner test account
 *   - .env.test (or GitHub secrets) provides SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
 *     BASE_URL
 */

import { test, expect } from '@playwright/test';
import { generateMagicLink, getTestState, type TestState } from '../helpers/auth.js';

/**
 * Derive the app.otterquote.com URL from the marketing BASE_URL.
 * Returns null when the env is not on the otterquote.com root domain
 * (e.g. Netlify previews) — tests skip in that case.
 */
function appBaseUrl(marketingBaseUrl: string): string | null {
  try {
    const u = new URL(marketingBaseUrl);
    const host = u.hostname;
    if (host === 'otterquote.com') {
      return `${u.protocol}//app.otterquote.com`;
    }
    if (host === 'staging.otterquote.com') {
      return `${u.protocol}//app-staging.otterquote.com`;
    }
    if (host.endsWith('.otterquote.com')) {
      // Unknown subdomain pattern on otterquote.com — best-effort: prefix with "app-".
      return `${u.protocol}//app-${host}`;
    }
    return null;
  } catch {
    return null;
  }
}

test.describe('Flow E — Cross-Subdomain SSO (D-212)', () => {
  let state: TestState;
  let marketingUrl: string;
  let appUrl: string | null;

  test.beforeAll(() => {
    state = getTestState();
    marketingUrl = state.baseUrl;
    appUrl = appBaseUrl(marketingUrl);
  });

  test('E1: canonical cookies set under 2048 bytes after magic-link auth on otterquote.com', async ({ page }) => {
    test.skip(!appUrl, 'app subdomain not available in this environment (likely a Netlify preview)');

    const magicLink = await generateMagicLink(
      state.homeownerEmail,
      `${marketingUrl}/dashboard.html`
    );
    await page.goto(magicLink);
    await page.waitForURL(/dashboard/, { timeout: 30_000 });
    await page.waitForLoadState('networkidle');

    const cookies = await page.context().cookies();
    const at = cookies.find((c) => c.name === 'sb-otterquote-at');
    const rt = cookies.find((c) => c.name === 'sb-otterquote-rt');

    expect(at, 'sb-otterquote-at cookie must be set after auth').toBeTruthy();
    expect(rt, 'sb-otterquote-rt cookie must be set after auth').toBeTruthy();

    // Cross-subdomain requires the leading dot.
    expect(at!.domain).toMatch(/^\.?otterquote\.com$/);
    expect(rt!.domain).toMatch(/^\.?otterquote\.com$/);

    // Size guard — surface drift back toward the 4096-byte limit immediately.
    const atSize = encodeURIComponent(at!.value).length;
    const rtSize = encodeURIComponent(rt!.value).length;
    expect(atSize, `sb-otterquote-at URL-encoded size must be < 2048 (got ${atSize})`).toBeLessThan(2048);
    expect(rtSize, `sb-otterquote-rt URL-encoded size must be < 2048 (got ${rtSize})`).toBeLessThan(2048);
  });

  test('E2: session persists from otterquote.com to app.otterquote.com', async ({ page }) => {
    test.skip(!appUrl, 'app subdomain not available in this environment');

    const magicLink = await generateMagicLink(
      state.homeownerEmail,
      `${marketingUrl}/dashboard.html`
    );
    await page.goto(magicLink);
    await page.waitForURL(/dashboard/, { timeout: 30_000 });
    await page.waitForLoadState('networkidle');

    // Cross to the app surface — cookies carry the session.
    await page.goto(`${appUrl}/`);
    await page.waitForLoadState('networkidle');

    const url = page.url();
    expect(
      url,
      `App surface must not redirect to login when session cookie exists. Got: ${url}`
    ).not.toMatch(/\/(login|get-started|sign-?in)/i);
  });

  test('E3: user.id matches across subdomains', async ({ page }) => {
    test.skip(!appUrl, 'app subdomain not available in this environment');

    const magicLink = await generateMagicLink(
      state.homeownerEmail,
      `${marketingUrl}/dashboard.html`
    );
    await page.goto(magicLink);
    await page.waitForURL(/dashboard/, { timeout: 30_000 });

    // Capture user.id on the marketing surface via the static-stack sb client.
    const marketingUserId = await page.evaluate(async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const sb = (window as any).sb;
      if (!sb) return null;
      const { data } = await sb.auth.getUser();
      return data?.user?.id || null;
    });
    expect(marketingUserId, 'Marketing surface must surface a Supabase user').toBeTruthy();
    expect(marketingUserId).toBe(state.homeownerUserId);

    await page.goto(`${appUrl}/`);
    await page.waitForLoadState('networkidle');

    // The React app's Supabase client is module-scoped; read the user.id from
    // the access-token cookie's JWT sub claim. This avoids depending on a
    // production global that may not exist in optimised builds.
    const appUserId = await page.evaluate(() => {
      const cookie = document.cookie
        .split('; ')
        .find((c) => c.startsWith('sb-otterquote-at='));
      if (!cookie) return null;
      try {
        const token = decodeURIComponent(cookie.split('=')[1]);
        const parts = token.split('.');
        if (parts.length !== 3) return null;
        const payload = JSON.parse(atob(parts[1]));
        return payload.sub || null;
      } catch {
        return null;
      }
    });

    expect(appUserId, 'App surface must see a user via the shared cookie').toBeTruthy();
    expect(appUserId).toBe(marketingUserId);
  });
});

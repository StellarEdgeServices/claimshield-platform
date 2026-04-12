/**
 * OtterQuote — Navigation Component
 * Renders consistent header/footer across all pages.
 * Primary detection: URL-based (contractor in pathname).
 * Secondary correction: role-based (Auth.getRole) for pages where URL and role
 * may disagree — most notably contractor-about.html, which is a homeowner page
 * whose URL contains "contractor".
 */

const Nav = {
  /** Detect if current page is a contractor page */
  _isContractorPage() {
    const path = window.location.pathname;
    return path.includes('contractor');
  },

  /** Render the site header */
  renderHeader(options = {}) {
    const { active = '', showAuth = true } = options;
    const nav = document.getElementById('site-header');
    if (!nav) return;

    const isContractor = this._isContractorPage();

    const links = isContractor ? [
      { href: '/contractor-dashboard.html',      label: 'Home',         id: 'home' },
      { href: '/contractor-how-it-works.html',   label: 'How It Works', id: 'how-it-works' },
      { href: '/contractor-faq.html',            label: 'FAQ',          id: 'faq' },
    ] : [
      { href: '/index.html',        label: 'Home',         id: 'home' },
      { href: '/how-it-works.html',  label: 'How It Works', id: 'how-it-works' },
      { href: '/faq.html',           label: 'FAQ',          id: 'faq' },
    ];

    nav.innerHTML = `
      <div class="nav-inner container">
        <a href="${isContractor ? '/contractor-dashboard.html' : '/index.html'}" class="nav-logo">
          <img src="/img/otter-logo.svg" alt="OtterQuote" class="nav-logo-icon" style="width:32px;height:32px;">
          <span class="nav-logo-text">${CONFIG.SITE_NAME}</span>
        </a>
        <div class="nav-links" id="nav-links">
          ${links.map(l => `
            <a href="${l.href}" class="nav-link ${active === l.id ? 'active' : ''}">${l.label}</a>
          `).join('')}
          ${showAuth ? '<div class="nav-mobile-auth" id="nav-mobile-auth-slot"></div>' : ''}
        </div>
        <div class="nav-actions" id="nav-actions">
          ${showAuth ? '<div id="nav-auth-slot"></div>' : ''}
        </div>
        <button class="nav-hamburger" id="nav-hamburger" aria-label="Menu">
          <span></span><span></span><span></span>
        </button>
      </div>
    `;

    // Mobile hamburger toggle
    const hamburger = document.getElementById('nav-hamburger');
    const navLinks = document.getElementById('nav-links');
    if (hamburger && navLinks) {
      hamburger.addEventListener('click', () => {
        hamburger.classList.toggle('open');
        navLinks.classList.toggle('open');
      });
    }

    // Auth state
    if (showAuth) {
      this._renderAuthSlot();
    }
  },

  /**
   * Patch nav links and logo href when the authenticated role does not match
   * the URL-based contractor detection. This handles pages like
   * contractor-about.html (homeowner page whose URL contains "contractor").
   * Only fires when showAuth=true (i.e., pages that render the auth slot).
   */
  _updateNavLinksForRole(role) {
    if (!role) return;
    const isContractorByUrl  = this._isContractorPage();
    const isContractorByRole = (role === 'contractor');
    if (isContractorByUrl === isContractorByRole) return; // nothing to fix

    const links = isContractorByRole ? [
      { href: '/contractor-dashboard.html',    label: 'Home' },
      { href: '/contractor-how-it-works.html', label: 'How It Works' },
      { href: '/contractor-faq.html',          label: 'FAQ' },
    ] : [
      { href: '/index.html',       label: 'Home' },
      { href: '/how-it-works.html', label: 'How It Works' },
      { href: '/faq.html',          label: 'FAQ' },
    ];

    // Update the three main nav-link anchors (exclude mobile-auth injected links)
    const container = document.getElementById('nav-links');
    if (container) {
      const anchors = container.querySelectorAll(
        'a.nav-link:not(.nav-mobile-cta):not(.nav-mobile-cta-secondary)'
      );
      anchors.forEach((a, i) => {
        if (links[i]) { a.href = links[i].href; a.textContent = links[i].label; }
      });
    }

    // Update logo href
    const logo = document.querySelector('.nav-logo');
    if (logo) {
      logo.href = isContractorByRole ? '/contractor-dashboard.html' : '/index.html';
    }
  },

  async _renderAuthSlot() {
    const slot = document.getElementById('nav-auth-slot');
    const mobileSlot = document.getElementById('nav-mobile-auth-slot');
    if (!slot && !mobileSlot) return;

    const user = await Auth.getUser();
    let desktopHTML, mobileHTML;

    if (user) {
      // Determine which dashboard to link to based on role
      const role = await Auth.getRole();

      // Correct nav links if URL detection disagrees with actual role
      // (e.g. homeowner on contractor-about.html, or contractor on a homeowner page)
      this._updateNavLinksForRole(role);

      const dashboardUrl = role === 'contractor'
        ? '/contractor-dashboard.html'
        : '/dashboard.html';
      const dashboardLabel = role === 'contractor'
        ? 'Contractor Portal'
        : 'My Dashboard';
      desktopHTML = `
        <a href="${dashboardUrl}" class="btn btn-sm btn-primary">${dashboardLabel}</a>
        <button class="btn btn-sm btn-ghost" onclick="Auth.signOut()">Sign Out</button>
      `;
      mobileHTML = `
        <a href="${dashboardUrl}" class="nav-link nav-mobile-cta">${dashboardLabel}</a>
        <a href="#" class="nav-link nav-mobile-cta-secondary" onclick="Auth.signOut(); return false;">Sign Out</a>
      `;
    } else {
      desktopHTML = `
        <a href="/get-started.html" class="btn btn-sm btn-primary">Get Started</a>
        <a href="/contractor-login.html" class="btn btn-sm btn-ghost">Contractor Login</a>
      `;
      mobileHTML = `
        <a href="/get-started.html" class="nav-link nav-mobile-cta">Get Started</a>
        <a href="/contractor-login.html" class="nav-link nav-mobile-cta-secondary">Contractor Login</a>
      `;
    }

    if (slot) slot.innerHTML = desktopHTML;
    if (mobileSlot) mobileSlot.innerHTML = mobileHTML;
  },

  /** Render the site footer */
  renderFooter() {
    const footer = document.getElementById('site-footer');
    if (!footer) return;

    const isContractor = this._isContractorPage();

    footer.innerHTML = `
      <div class="footer-inner container">
        <div class="footer-grid">
          <div class="footer-col">
            <div class="footer-logo">
              <img src="/img/otter-logo.svg" alt="OtterQuote" class="nav-logo-icon" style="width:32px;height:32px;">
              <span class="nav-logo-text">${CONFIG.SITE_NAME}</span>
            </div>
            <p class="footer-tagline">${isContractor
              ? 'Your sales team — without the truck, the manager, or the advance.'
              : 'Helping homeowners get the best deal on roofing and exterior projects.'
            }</p>
          </div>
          <div class="footer-col">
            <h4 class="footer-heading">${isContractor ? 'Contractor Portal' : 'Platform'}</h4>
            ${isContractor ? `
              <a href="/contractor-how-it-works.html">How It Works</a>
              <a href="/contractor-faq.html">FAQ</a>
              <a href="/contractor-opportunities.html">Browse Opportunities</a>
            ` : `
              <a href="/how-it-works.html">How It Works</a>
              <a href="/faq.html">FAQ</a>
              <a href="/get-started.html">Get Started</a>
            `}
          </div>
          <div class="footer-col">
            <h4 class="footer-heading">${isContractor ? 'Your Account' : 'Contractors'}</h4>
            ${isContractor ? `
              <a href="/contractor-dashboard.html">Dashboard</a>
              <a href="/contractor-profile.html">Company Profile</a>
              <a href="/contractor-agreement.html">Partner Agreement</a>
            ` : `
              <a href="/contractor-login.html">Contractor Login</a>
              <a href="/contractor-join.html">Join Our Network</a>
              <a href="/contractor-agreement.html">Partner Agreement</a>
            `}
          </div>
          ${!isContractor ? `
          <div class="footer-col">
            <h4 class="footer-heading">Partners</h4>
            <a href="/partner-re.html">Real Estate Agents</a>
            <a href="/partner-insurance.html">Insurance Agents</a>
            <a href="/partner-dashboard.html">Partner Dashboard</a>
            <a href="/refer-a-friend.html">Refer a Friend</a>
          </div>
          ` : ''}
          <div class="footer-col">
            <h4 class="footer-heading">Legal</h4>
            <a href="/terms.html">Terms of Service</a>
            <a href="/privacy.html">Privacy Policy</a>
          </div>
        </div>
        <div class="footer-bottom">
          <p>&copy; ${new Date().getFullYear()} ${CONFIG.SITE_NAME}. All rights reserved.</p>
        </div>
      </div>
    `;
  }
};

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  // Look for data attributes on header/footer elements
  const header = document.getElementById('site-header');
  if (header) {
    Nav.renderHeader({
      active: header.dataset.active || '',
      showAuth: header.dataset.auth !== 'false'
    });
  }

  const footer = document.getElementById('site-footer');
  if (footer) {
    Nav.renderFooter();
  }
});

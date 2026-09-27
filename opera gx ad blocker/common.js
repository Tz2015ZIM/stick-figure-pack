// Shared by the background worker, content.js and the sidebar panel (not page-guard.js,
// which runs in the page's world). Loaded as a classic script, it exposes one global: PB.
globalThis.PB = (() => {
  const DEFAULTS = {
    enabled: true,
    popups: true,
    signIn: true,
    overlays: false,
    dialogs: true,
    notifications: true,
    leave: false,
    notices: true,
    stickman: true,
    stickmanAds: true,
  };

  const KINDS = {
    popup: 'Pop-up tab',
    link: 'Invisible ad link',
    overlay: 'Covering pop-up',
    dialog: 'Alert box',
    notification: 'Notification request',
    ad: 'Ad',
  };

  // Log-in windows that must keep working as pop-ups. Anything else that looks like an
  // OAuth/SSO endpoint (by host prefix or path) is let through too.
  const SIGN_IN_HOSTS = ['accounts.google.com', 'appleid.apple.com', 'paypal.com', 'checkout.stripe.com'];
  const SIGN_IN_HOST_PREFIX = /^(auth|login|accounts?|sso|id|signin|oauth)\./i;
  const SIGN_IN_PATH = /(^|[/._-])(oauth2?|openid|auth|authorize|login|signin|sign-in|sso)([/._-]|$)/i;

  const matchesDomain = (host, domain) => host === domain || host.endsWith('.' + domain);

  function hostOf(url) {
    try {
      const u = new URL(url);
      return /^https?:$/.test(u.protocol) ? u.hostname.replace(/^www\./, '') : '';
    } catch {
      return '';
    }
  }

  function isAllowed(host, allowlist) {
    return !!host && allowlist.some(domain => matchesDomain(host, domain));
  }

  function isSignInUrl(url) {
    let u;
    try {
      u = new URL(url);
    } catch {
      return false;
    }
    if (!/^https?:$/.test(u.protocol)) return false;
    return SIGN_IN_HOSTS.some(domain => matchesDomain(u.hostname, domain))
      || SIGN_IN_HOST_PREFIX.test(u.hostname)
      || SIGN_IN_PATH.test(u.pathname);
  }

  // --- DOM helpers (content scripts only) ---

  function frameNamed(doc, name) {
    for (const frame of doc.querySelectorAll('iframe, frame')) {
      if (frame.name === name) return true;
    }
    return false;
  }

  // What following this link would do. page-guard.js builds the same shape for its checks.
  function linkInfo(link, event) {
    if (!(link instanceof HTMLAnchorElement || link instanceof HTMLAreaElement)) return null;
    const doc = link.ownerDocument;
    return {
      href: link.href,
      target: link.target || doc.querySelector('base[target]')?.target || '',
      download: link.hasAttribute('download'),
      forced: !!event && (event.ctrlKey || event.metaKey || event.shiftKey || event.button === 1),
    };
  }

  // Would this link (or window.open call) open a new tab or window?
  function opensNewTab({ href, target, download, forced }, doc) {
    if (!href || /^javascript:/i.test(href) || download) return false;
    if (forced) return true;
    const keyword = target.toLowerCase();
    if (!keyword || keyword === '_self' || keyword === '_parent' || keyword === '_top') return false;
    return keyword === '_blank' || !frameNamed(doc, target);
  }

  return { DEFAULTS, KINDS, hostOf, isAllowed, isSignInUrl, linkInfo, opensNewTab };
})();

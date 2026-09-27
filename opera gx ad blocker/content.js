// Isolated-world half of the blocker. Answers page-guard.js's "block this?" questions from
// the settings, reports what it blocks to the background worker, tells the background which
// new tabs the user really asked for, and runs the on-page tools: overlay remover, zapper,
// notices, and the stickman who runs in and smashes ads and pop-ups.
(() => {
  const CHECK_EVENT = 'gxpb:check';
  const isTop = window === window.top;
  const site = topSite();

  let settings = { ...PB.DEFAULTS };
  let active = false; // stays off until the settings have loaded
  const on = key => active && !!settings[key];

  function topSite() {
    if (isTop) return PB.hostOf(location.href);
    const origins = location.ancestorOrigins;
    return origins && origins.length ? PB.hostOf(origins[origins.length - 1]) : '';
  }

  function send(message) {
    try {
      chrome.runtime.sendMessage(message).catch(() => {});
    } catch {} // the extension was reloaded and this copy is orphaned
  }

  async function load() {
    let data;
    try {
      data = await chrome.storage.local.get(['settings', 'allowlist']);
    } catch {
      return;
    }
    settings = { ...PB.DEFAULTS, ...data.settings };
    active = settings.enabled && !PB.isAllowed(site, data.allowlist || []);
    if (isTop) {
      overlays.setAuto(on('overlays'));
      ads.setAuto(on('stickman') && settings.stickmanAds);
      if (!on('stickman')) stickman.callOff();
    }
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && (changes.settings || changes.allowlist)) load();
  });

  // Repeats (e.g. an alert() loop) are logged once every few seconds.
  const recent = new Map();
  function blocked(kind, detail) {
    const key = kind + detail;
    const now = Date.now();
    if (now - (recent.get(key) || 0) < 3000) return;
    recent.set(key, now);
    send({ type: 'blocked', kind, detail: String(detail).slice(0, 500) });
  }

  // The link the user last really clicked. Pages often cancel a link click and call
  // window.open(link.href) themselves; that's the user's choice, not a pop-up.
  let lastClick = { href: '', time: 0 };

  // When the user last clicked or pressed a key in this frame. Tracked here rather than
  // read from navigator.userActivation, which browsers also grant on some navigations.
  let lastInput = 0;
  for (const type of ['pointerdown', 'keydown']) {
    window.addEventListener(type, e => {
      if (e.isTrusted) lastInput = Date.now();
    }, true);
  }

  function decide(check) {
    switch (check.kind) {
      case 'popup': {
        const info = check.info;
        if (!on('popups') || typeof info?.href !== 'string' || typeof info.target !== 'string') return false;
        if (!PB.opensNewTab(info, document)) return false;
        if (settings.signIn && PB.isSignInUrl(info.href)) return false;
        if (info.href === lastClick.href && Date.now() - lastClick.time < 1000) return false;
        blocked('popup', info.href);
        return true;
      }
      case 'dialog':
        // Dialogs right after a click or key press are the user's doing; anything else is spam.
        if (!on('dialogs') || Date.now() - lastInput < 5000) return false;
        blocked('dialog', check.detail);
        return true;
      case 'leave':
        return on('leave');
      case 'notification':
        if (!on('notifications')) return false;
        blocked('notification', location.origin);
        return true;
    }
    return false;
  }

  window.addEventListener(CHECK_EVENT, e => {
    let check;
    try {
      check = JSON.parse(e.detail);
    } catch {
      return;
    }
    if (check && decide(check)) e.preventDefault();
  });

  // --- what the user really clicked ---

  const elementIn = (event, selector) => event.composedPath().find(n => n instanceof Element && n.matches(selector));

  // A see-through link stretched over the page is the classic "every click opens an ad" trick.
  function isInvisibleLink(link) {
    const r = link.getBoundingClientRect();
    if (r.width * r.height < innerWidth * innerHeight * 0.5) return false;
    if (link.innerText.trim() || link.querySelector('img, video, picture, canvas, svg, iframe')) return false;
    return getComputedStyle(link).backgroundImage === 'none';
  }

  function onUserClick(e) {
    if (!e.isTrusted) return;
    const link = elementIn(e, 'a[href], area[href]');
    const info = PB.linkInfo(link, e);
    if (e.type !== 'contextmenu') lastClick = { href: info ? info.href : '', time: Date.now() };
    if (!on('popups')) return;
    if (info) {
      if (e.type !== 'contextmenu' && PB.opensNewTab(info, document) && isInvisibleLink(link)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        link.style.setProperty('pointer-events', 'none', 'important'); // let the next click through
        blocked('link', info.href);
        return;
      }
      send({ type: 'intent', url: info.href, ttl: e.type === 'contextmenu' ? 30000 : 3000 });
      return;
    }
    if (e.type === 'contextmenu') {
      // Browser menu items such as "Search the web for…" open tabs from this page too.
      send({ type: 'intent', url: '*', ttl: 30000 });
      return;
    }
    const button = elementIn(e, 'button, input[type=submit], input[type=image]');
    if (button && button.form) {
      const action = button.hasAttribute('formaction') ? button.formAction : button.form.action;
      send({ type: 'intent', url: action, ttl: 3000 });
    }
  }
  for (const type of ['click', 'auxclick', 'contextmenu']) window.addEventListener(type, onUserClick, true);

  const describe = el => el.tagName.toLowerCase()
    + (el.id ? '#' + el.id : '')
    + (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '');

  const parentOf = n => n.parentElement || (n.getRootNode() instanceof ShadowRoot ? n.getRootNode().host : null);

  // Too big to be an ad: a whole section of the page.
  const isSection = el => {
    const r = el.getBoundingClientRect();
    return r.width * r.height > innerWidth * innerHeight * 0.6;
  };

  // --- on-page notices (top frame only) ---

  const notices = (() => {
    const CSS = `
      .stack { display: flex; flex-direction: column; align-items: flex-end; gap: 8px;
        font: 13px/1.35 "Segoe UI", system-ui, sans-serif; }
      .card { display: flex; align-items: center; gap: 10px; width: 330px; box-sizing: border-box;
        padding: 10px 8px 10px 12px; color: #f3f1f7; background: #17141f;
        border: 1px solid #2d2839; border-left: 3px solid #fa1e4e; border-radius: 10px;
        box-shadow: 0 10px 30px rgba(0, 0, 0, .4); animation: in .18s ease-out; }
      .icon { flex: none; width: 18px; height: 18px; color: #fa1e4e; }
      .text { flex: 1; min-width: 0; }
      .title { font-weight: 600; }
      .sub { color: #a39fb0; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      button { flex: none; font: inherit; font-size: 12px; font-weight: 600; color: #f3f1f7; cursor: pointer;
        background: #262130; border: 1px solid #36304a; border-radius: 6px; padding: 4px 8px; }
      button:hover { background: #fa1e4e; border-color: #fa1e4e; }
      button.close { background: none; border: 0; color: #a39fb0; font-size: 16px; line-height: 1; padding: 4px 6px; }
      button.close:hover { color: #f3f1f7; background: none; }
      @keyframes in { from { opacity: 0; transform: translateY(8px); } }`;
    let host = null;
    let stack = null;
    const cards = new Map();

    // Built node by node rather than with innerHTML, which Trusted Types pages may refuse.
    function shieldIcon() {
      const NS = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(NS, 'svg');
      svg.setAttribute('class', 'icon');
      svg.setAttribute('viewBox', '0 0 24 24');
      for (const [k, v] of Object.entries({ fill: 'none', stroke: 'currentColor', 'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) {
        svg.setAttribute(k, v);
      }
      for (const d of ['M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z', 'M9.5 9.5l5 5M14.5 9.5l-5 5']) {
        const path = document.createElementNS(NS, 'path');
        path.setAttribute('d', d);
        svg.append(path);
      }
      return svg;
    }

    function mount() {
      if (host && host.isConnected) return;
      host = document.createElement('gxpb-notices');
      host.style.cssText = 'all: initial; position: fixed; right: 16px; bottom: 16px; z-index: 2147483647;';
      const root = host.attachShadow({ mode: 'closed' });
      const style = document.createElement('style');
      style.textContent = CSS;
      stack = el('div', 'stack');
      root.append(style, stack);
      document.documentElement.append(host);
    }

    function el(tag, className, text) {
      const node = document.createElement(tag);
      if (className) node.className = className;
      if (text) node.textContent = text;
      return node;
    }

    // show({ key, title, sub, actions: [{ label, run }], sticky })
    function show({ key, title, sub, actions = [], sticky = false }) {
      if (!document.documentElement) return;
      mount();
      let card = cards.get(key);
      if (!card) {
        const node = el('div', 'card');
        card = { node, timer: 0 };
        cards.set(key, card);
        node.addEventListener('mouseenter', () => clearTimeout(card.timer));
        node.addEventListener('mouseleave', () => arm(key, card));
        stack.append(node);
      }
      card.sticky = sticky;
      const text = el('div', 'text');
      text.append(el('div', 'title', title));
      if (sub) text.append(el('div', 'sub', sub));
      const buttons = actions.map(({ label, run }) => {
        const button = el('button', '', label);
        button.addEventListener('click', e => {
          if (e.isTrusted) run();
        });
        return button;
      });
      const close = el('button', 'close', '×');
      close.title = 'Dismiss';
      close.addEventListener('click', e => e.isTrusted && hide(key));
      card.node.replaceChildren(shieldIcon(), text, ...buttons, close);
      arm(key, card);
    }

    function arm(key, card) {
      clearTimeout(card.timer);
      if (!card.sticky) card.timer = setTimeout(() => hide(key), 6000);
    }

    function hide(key) {
      const card = cards.get(key);
      if (!card) return;
      clearTimeout(card.timer);
      card.node.remove();
      cards.delete(key);
    }

    const owns = event => !!host && event.composedPath().includes(host);

    return { show, hide, owns };
  })();

  // Background asks us to show a notice after it records something as blocked.
  const counts = {};
  function showBlockedNotice({ kind, detail }) {
    counts[kind] = (counts[kind] || 0) + 1;
    const n = counts[kind];
    const many = n > 1 ? ` (${n})` : '';
    const url = /^https?:/i.test(detail) ? detail : '';
    const allowSite = { label: 'Allow site', run: () => {
      send({ type: 'allowSite' });
      notices.show({ key: kind, title: `Allowed on ${site}`, sub: 'Blockers are off for this site now.' });
    } };
    const open = url && { label: 'Open', run: () => {
      send({ type: 'openBlocked', url });
      notices.hide(kind);
    } };
    const copy = {
      popup: ['Blocked a pop-up' + many, url || detail, [open, allowSite]],
      link: ['Blocked an invisible ad link' + many, 'Click again to reach the page.', [allowSite]],
      overlay: ['Hid a covering pop-up' + many, detail, [{ label: 'Undo', run: () => {
        overlays.undo();
        notices.hide(kind);
      } }]],
      dialog: ['Blocked an alert box' + many, detail, [allowSite]],
      notification: ['Blocked a notification request' + many, site, [allowSite]],
    }[kind];
    if (!copy) return;
    const [title, sub, actions] = copy;
    notices.show({ key: kind, title, sub, actions: actions.filter(Boolean) });
  }

  // --- covering pop-ups (top frame only) ---

  const overlays = (() => {
    let auto = false;
    let observer = null;
    let timer = 0;
    const userOwned = new WeakSet(); // opened right after a click, so the user wanted them
    const hidden = [];

    function coverage(el) {
      const r = el.getBoundingClientRect();
      const w = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
      const h = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
      return (w * h) / (innerWidth * innerHeight || 1);
    }

    function outermostFixed(el) {
      let found = null;
      for (let n = el; n && n !== document.body && n !== document.documentElement; n = parentOf(n)) {
        if (getComputedStyle(n).position === 'fixed') found = n;
      }
      return found;
    }

    function fixedLayersAtCenter() {
      const layers = [];
      for (const el of document.elementsFromPoint(innerWidth / 2, innerHeight / 2)) {
        const layer = outermostFixed(el);
        if (layer && !layers.includes(layer) && !(host() && layer === host())) layers.push(layer);
      }
      return layers;
    }
    const host = () => document.querySelector('gxpb-notices');

    function isSeeThrough(el) {
      const s = getComputedStyle(el);
      if (s.backdropFilter && s.backdropFilter !== 'none') return true;
      const m = s.backgroundColor.match(/rgba?\(([^)]+)\)/);
      const parts = m ? m[1].split(/[\s,/]+/).filter(Boolean) : [];
      const alpha = (parts.length > 3 ? parseFloat(parts[3]) : 1) * parseFloat(s.opacity);
      return alpha > 0.04 && alpha < 0.97;
    }

    // A full-screen layer with a dimmed or blurred backdrop, on itself or a full-size child.
    function looksLikeModal(el) {
      if (coverage(el) < 0.85) return false;
      return isSeeThrough(el) || [...el.children].some(c => coverage(c) >= 0.85 && isSeeThrough(c));
    }

    const zIndex = el => parseInt(getComputedStyle(el).zIndex, 10) || 0;

    function hide(el) {
      try {
        if (el instanceof HTMLDialogElement && el.open) el.close();
        else if (el.matches(':popover-open')) el.hidePopover();
      } catch {}
      el.style.setProperty('display', 'none', 'important');
      if (!hidden.includes(el)) hidden.push(el);
    }

    function unlockScroll() {
      for (const el of [document.documentElement, document.body]) {
        if (!el) continue;
        const s = getComputedStyle(el);
        if (s.overflow.includes('hidden') || s.overflowY === 'hidden') el.style.setProperty('overflow', 'auto', 'important');
        if (el === document.body && s.position === 'fixed') el.style.setProperty('position', 'static', 'important');
      }
      for (const child of document.body ? document.body.children : []) {
        if (getComputedStyle(child).filter.includes('blur')) child.style.setProperty('filter', 'none', 'important');
      }
    }

    function removeModal(modal) {
      hide(modal);
      // The dialog box itself is often a separate fixed layer sitting on top of the backdrop.
      const minZ = zIndex(modal);
      for (const layer of fixedLayersAtCenter()) {
        if (!userOwned.has(layer) && coverage(layer) < 0.85 && zIndex(layer) >= minZ) hide(layer);
      }
      unlockScroll();
      blocked('overlay', describe(modal));
    }

    // What the stickman should hit: the dialog box in the middle, not the whole backdrop.
    function boxIn(modal) {
      const skip = n => n === document.body || n === document.documentElement;
      for (const el of document.elementsFromPoint(innerWidth / 2, innerHeight / 2)) {
        if (el === modal || skip(el)) break;
        const c = coverage(el);
        if (c <= 0.02 || c >= 0.6) continue;
        let box = el;
        for (let up = parentOf(box); up && up !== modal && !skip(up) && coverage(up) < 0.6; up = parentOf(up)) box = up;
        return box;
      }
      return modal;
    }

    const claimed = new WeakSet(); // the stickman is already on his way to these

    // Send him at a pop-up: he hits box, and when it breaks the whole layer goes.
    function smash({ layer, box, modal }) {
      if (claimed.has(layer)) return;
      claimed.add(layer);
      stickman.attack(box, {
        destroyed: modal ? () => {
          hide(box);
          removeModal(layer);
        } : () => {
          hide(layer);
          blocked('overlay', describe(layer));
        },
        abandoned: () => claimed.delete(layer),
        priority: true,
      });
    }

    const sendStickmanAt = modal => smash({ layer: modal, box: boxIn(modal), modal: true });

    // Right-click "Destroy ad" inside a pop-up: the layer to clear and the box he should hit.
    function popupAt(el) {
      const layer = outermostFixed(el);
      if (!layer) return null;
      if (looksLikeModal(layer)) {
        // the dialog box that was clicked, or the one in the middle for a click on the backdrop
        let box = el === layer ? null : el;
        for (let up = box && parentOf(box); up && up !== layer && coverage(up) < 0.6; up = parentOf(up)) box = up;
        return { layer, box: box && coverage(box) < 0.6 ? box : boxIn(layer), modal: true };
      }
      if (coverage(layer) >= 0.6) return null; // the page's own fixed layout, not a pop-up
      // The dialog box may be its own layer, over a separate dimmed backdrop.
      const layers = fixedLayersAtCenter();
      const backdrop = layers.includes(layer) && layers.slice(layers.indexOf(layer) + 1).find(looksLikeModal);
      return backdrop ? { layer: backdrop, box: layer, modal: true } : { layer, box: layer, modal: false };
    }

    function scan() {
      timer = 0;
      if (!auto || document.fullscreenElement || !document.body) return;
      const layers = fixedLayersAtCenter().filter(l => !userOwned.has(l) && l.style.display !== 'none');
      if (Date.now() - lastInput < 1500) {
        layers.forEach(l => userOwned.add(l));
        return;
      }
      const modal = layers.find(looksLikeModal);
      if (!modal || claimed.has(modal)) return;
      if (on('stickman')) sendStickmanAt(modal);
      else removeModal(modal);
    }

    // "Send stickman": go after a covering pop-up right now, even with auto-hiding off.
    function huntNow() {
      if (!document.body) return 0;
      const modal = fixedLayersAtCenter().find(l => l.style.display !== 'none' && looksLikeModal(l));
      if (!modal || claimed.has(modal)) return 0;
      sendStickmanAt(modal);
      return 1;
    }

    function schedule() {
      if (!timer) timer = setTimeout(scan, 400);
    }

    function setAuto(enabled) {
      auto = enabled;
      if (auto && !observer) {
        observer = new MutationObserver(schedule);
        observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'open'] });
        schedule();
      } else if (!auto && observer) {
        observer.disconnect();
        observer = null;
      }
    }

    // The panel's "Remove overlay" button: peel off the top layer at the centre of the page,
    // plus any big backdrop underneath it.
    function removeNow() {
      const layers = fixedLayersAtCenter().filter(l => l.style.display !== 'none');
      const removed = layers.filter((layer, i) => i === 0 || coverage(layer) >= 0.5);
      removed.forEach(hide);
      if (removed.length) unlockScroll();
      return removed.length;
    }

    function undo() {
      for (const el of hidden.splice(0)) {
        el.style.removeProperty('display');
        userOwned.add(el);
      }
    }

    return { setAuto, removeNow, undo, huntNow, popupAt, smash };
  })();

  // --- the stickman: runs in and smashes ads and pop-ups (top frame only) ---

  const stickman = (() => {
    let host = null;
    let fighter = null;

    function ensure() {
      if (!fighter) {
        host = document.createElement('gxpb-stickman');
        host.style.cssText = 'all: initial; position: fixed; inset: 0; z-index: 2147483646; pointer-events: none;';
        const canvas = document.createElement('canvas');
        canvas.style.cssText = 'display: block; width: 100%; height: 100%;';
        host.attachShadow({ mode: 'closed' }).append(canvas);
        fighter = new Stickman.Fighter(canvas, { scale: 1.3, onGone: () => host.remove() });
      }
      if (!host.isConnected) document.documentElement.append(host);
      return fighter;
    }

    const SHAKE = [{ translate: '0 0' }, { translate: '-7px 3px' }, { translate: '6px -3px' }, { translate: '-3px 1px' }, { translate: '0 0' }];

    // A real element on the page: it shakes on every hit and shrinks away on the last, then
    // destroyed() runs. With vanish off (a video he skips rather than removes) the last hit
    // just shakes it harder.
    function attack(el, { destroyed, abandoned, priority = false, vanish = true }) {
      if (document.fullscreenElement) { // he can't be seen over it, so no show
        destroyed();
        return;
      }
      ensure().add({
        rect() {
          if (!el.isConnected) return null;
          const r = el.getBoundingClientRect();
          const inView = r.width > 4 && r.height > 4 && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
          return inView ? r : null;
        },
        hit() {
          el.animate(SHAKE, { duration: 180 });
        },
        destroy() {
          if (!vanish) {
            el.animate(SHAKE, { duration: 180, iterations: 2 });
            destroyed();
            return;
          }
          el.animate([{ opacity: 1, scale: '1' }, { opacity: 0, scale: '0.4' }], { duration: 200, easing: 'ease-in' })
            .finished.then(destroyed, destroyed);
        },
        abandon: abandoned,
      }, { priority });
    }

    // Pop-up tabs, alert boxes and the like are stopped before they show, so he gets a
    // pretend window to smash instead.
    const GHOSTS = {
      popup: detail => [PB.hostOf(detail) || 'Pop-up', 'POP-UP AD'],
      link: () => ['Invisible ad link', 'AD LINK'],
      dialog: () => ['alert()', 'ALERT!'],
      notification: () => [site || 'Notifications', 'NOTIFY ME?'],
    };

    function ghost(kind, detail) {
      if (!GHOSTS[kind] || document.fullscreenElement) return;
      const f = ensure();
      if (f.targets.filter(t => t.draw).length >= 4) return; // a pop-up storm; he has enough to do
      const w = Math.min(200, innerWidth * 0.45);
      const h = w * 0.6;
      const [title, body] = GHOSTS[kind](detail);
      f.add(Stickman.ghost({
        x: Math.max(10, innerWidth * (0.35 + Math.random() * 0.35) - w / 2),
        y: innerHeight * (0.12 + Math.random() * 0.25),
        w, h, title, body,
      }));
    }

    // "Send stickman" in the menu: hunt the ads and covering pop-ups on this page now.
    function send() {
      const found = ads.hunt() + overlays.huntNow();
      if (!found) ensure().visit();
      return found;
    }

    // Stickman switched off: drop what he was after and let him walk off.
    function callOff() {
      if (!fighter) return;
      fighter.setEnabled(false);
      fighter.setEnabled(true);
    }

    // Nothing for him to hit: he walks on, has a look, waves and leaves.
    const visit = () => ensure().visit();

    return { attack, ghost, send, callOff, visit };
  })();

  // --- ads for the stickman to hunt (top frame only) ---

  const ads = (() => {
    const SELECTOR = [
      'ins.adsbygoogle', '[id^="google_ads_iframe"]', 'div[id^="div-gpt-ad"]', '[data-google-query-id]',
      'iframe[src*="doubleclick.net"]', 'iframe[src*="googlesyndication.com"]', 'iframe[src*="amazon-adsystem.com"]',
      'iframe[src*="adnxs.com"]', 'iframe[id*="taboola"]', '[id^="taboola-"]', '.OUTBRAIN', '.trc_related_container',
      '[id^="ad-slot"]', '[class*="ad-slot"]', '[class*="adslot"]', '.adsbox', '.ad-banner', '.advert', '.advertisement',
      '[aria-label="Advertisement"]', '[aria-label="advertisement"]', '[aria-label="Ads"]',
      '[data-ad-slot]', '[data-adunit]', '[data-ad-unit]',
    ].join(', ');
    const claimed = new WeakSet();
    let auto = false;
    let timer = 0;
    let observer = null;

    function looksLikeAd(el) {
      if (claimed.has(el)) return false;
      const r = el.getBoundingClientRect();
      if (r.width < 40 || r.height < 20) return false;
      if (r.width * r.height > innerWidth * innerHeight * 0.6) return false; // a page section, not an ad
      return r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
    }

    // Words ad slots carry in their id or class, as a whole word: "ad", "top-ad", "ads_box"...
    const AD_WORD = /(^|[\s_-])(ads?|adverts?|advertisement|advertising|sponsor|sponsored|promoted)([\s_-]|$)/i;

    function smash(el, priority = false) {
      if (claimed.has(el)) return;
      claimed.add(el);
      stickman.attack(el, {
        destroyed: () => {
          el.style.setProperty('display', 'none', 'important');
          blocked('ad', el instanceof HTMLIFrameElement && /^https?:/.test(el.src) ? el.src : describe(el));
        },
        abandoned: () => claimed.delete(el),
        priority,
      });
    }

    // Send him after every ad in view. Returns how many.
    function hunt() {
      if (document.fullscreenElement) return 0;
      const found = [...document.querySelectorAll(SELECTOR)].filter(looksLikeAd);
      let count = 0;
      for (const el of found) {
        if (found.some(other => other !== el && other.contains(el))) continue; // take the whole slot
        count++;
        smash(el);
      }
      return count;
    }

    // Right-click "Destroy ad": the outermost ad slot around what was clicked, if it has one.
    function slotAt(el) {
      let slot = null;
      for (let n = el; n && n !== document.body && n !== document.documentElement && !isSection(n); n = parentOf(n)) {
        if (n.matches(SELECTOR) || AD_WORD.test(`${n.id} ${typeof n.className === 'string' ? n.className : ''}`)) slot = n;
      }
      return slot;
    }

    function schedule() {
      if (!timer) {
        timer = setTimeout(() => {
          timer = 0;
          if (auto) hunt();
        }, 700);
      }
    }

    function setAuto(enabled) {
      if (enabled === auto) return;
      auto = enabled;
      if (auto) {
        document.addEventListener('scroll', schedule, { passive: true, capture: true });
        addEventListener('resize', schedule);
        observer = new MutationObserver(schedule);
        observer.observe(document.documentElement, { childList: true, subtree: true });
        schedule();
      } else {
        document.removeEventListener('scroll', schedule, { capture: true });
        removeEventListener('resize', schedule);
        observer.disconnect();
        observer = null;
      }
    }

    return { hunt, setAuto, slotAt, smash };
  })();

  // --- "Destroy ad" in the right-click menu ---
  //
  // Every frame notes where the menu was opened; the top frame, where the stickman lives,
  // picks what to send him at. A video isn't removed: once he's knocked it, it skips to the
  // end, so a video ad counts as finished and the player moves on.

  const destroyer = (() => {
    let menu = { el: null, x: 0, y: 0 };
    addEventListener('contextmenu', e => {
      if (e.isTrusted) menu = { el: e.composedPath()[0], x: e.clientX, y: e.clientY };
    }, true);

    // The video the menu was opened on: under the right-click, or else the one playing src.
    function videoAt(src) {
      const { el, x, y } = menu;
      if (el instanceof HTMLVideoElement) return el;
      const videos = [...document.querySelectorAll('video')];
      if (el) { // player controls and overlays usually sit on top of it
        const under = document.elementsFromPoint(x, y).find(n => n instanceof HTMLVideoElement) || videos.find(v => {
          const r = v.getBoundingClientRect();
          return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
        });
        if (under) return under;
      }
      return (src && videos.find(v => v.currentSrc === src || v.src === src)) || null;
    }

    function skip(video) {
      const { duration, seekable } = video;
      const end = Number.isFinite(duration) ? duration : seekable.length ? seekable.end(seekable.length - 1) : NaN; // live: jump to now
      if (!Number.isFinite(end)) return;
      video.loop = false; // or it would just start over
      video.currentTime = end;
      blocked('ad', /^https?:/.test(video.currentSrc) ? video.currentSrc : describe(video));
    }

    // No ad markings to go by: take what was clicked plus the wrappers hugging it (link,
    // picture, box around a frame) up to where the next one is clearly bigger.
    function wrapperOf(el) {
      let box = el;
      for (let up = parentOf(box); up && up !== document.body && up !== document.documentElement && !isSection(up); up = parentOf(up)) {
        const r = box.getBoundingClientRect();
        const u = up.getBoundingClientRect();
        if (r.width >= 40 && r.height >= 20 && u.width * u.height > r.width * r.height * 1.5) break;
        box = up;
      }
      return box;
    }

    function framesIn(root) {
      const found = [];
      for (const el of root.querySelectorAll('*')) {
        if (el instanceof HTMLIFrameElement || el instanceof HTMLFrameElement) found.push(el);
        if (el.shadowRoot) found.push(...framesIn(el.shadowRoot));
      }
      return found;
    }

    // Which <iframe> on this page a child frame is: only the frame itself can tell, so the
    // background asks it to post the token up here, and the sender gives it away.
    const pointing = new Map(); // token -> resolve
    addEventListener('message', e => {
      const resolve = pointing.get(e.data?.gxpbPointOut);
      if (!resolve) return;
      pointing.delete(e.data.gxpbPointOut);
      resolve(framesIn(document).find(f => f.contentWindow === e.source) || null);
    });

    function frameElement(token, url) {
      return new Promise(resolve => {
        pointing.set(token, resolve);
        setTimeout(() => { // no answer (nothing of ours running in there): go by its address
          if (pointing.delete(token)) resolve(framesIn(document).find(f => url && f.src === url) || null);
        }, 1000);
      });
    }

    const pointOut = token => window.parent.postMessage({ gxpbPointOut: token }, '*');

    // Top frame. frameId: the child frame the menu was opened in, or 0 for this page.
    // video: { frameId, src } when it was opened on a video (frameId is then its own frame).
    async function destroy({ frameId, frameUrl, video, token }) {
      const el = frameId ? await frameElement(token, frameUrl) : menu.el;
      const player = video && (frameId ? el : videoAt(video.src));
      if (player) {
        stickman.attack(player, {
          destroyed: frameId ? () => send({ type: 'skipVideo', frameId: video.frameId, src: video.src }) : () => skip(player),
          priority: true,
          vanish: false,
        });
        return;
      }
      if (!(el instanceof Element) || !el.isConnected || el.closest('gxpb-notices, gxpb-stickman, gxpb-zap')) {
        stickman.visit();
        return;
      }
      const popup = overlays.popupAt(el);
      if (popup) {
        overlays.smash(popup);
        return;
      }
      const box = ads.slotAt(el) || wrapperOf(el);
      if (box === document.body || box === document.documentElement || isSection(box)) stickman.visit(); // nothing ad-sized there
      else ads.smash(box, true);
    }

    function skipVideo(src) {
      const video = videoAt(src);
      if (video) skip(video);
    }

    return { destroy, skipVideo, pointOut };
  })();

  // --- zapper: click anything on the page to remove it (top frame only) ---

  const zapper = (() => {
    let active = false;
    let box = null;
    let current = null;

    const pick = (x, y) => {
      const el = document.elementFromPoint(x, y);
      return el && el !== document.documentElement && el !== document.body && el !== box ? el : null;
    };

    function onMove(e) {
      current = notices.owns(e) ? null : pick(e.clientX, e.clientY);
      if (!current) {
        box.style.display = 'none';
        return;
      }
      const r = current.getBoundingClientRect();
      Object.assign(box.style, { display: 'block', left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });
    }

    function swallow(e) {
      if (!e.isTrusted || notices.owns(e)) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      if (e.type === 'click' && current) {
        current.style.setProperty('display', 'none', 'important');
        current = null;
        box.style.display = 'none';
      }
    }

    function onKey(e) {
      if (e.key === 'Escape') {
        e.preventDefault();
        stop();
      }
    }

    const EVENTS = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click', 'auxclick'];

    function start() {
      active = true;
      box = document.createElement('gxpb-zap');
      box.style.cssText = 'all: initial; position: fixed; display: none; z-index: 2147483646; pointer-events: none; box-sizing: border-box;'
        + 'border: 2px solid #fa1e4e; background: rgba(250, 30, 78, .15); border-radius: 3px;';
      document.documentElement.append(box);
      addEventListener('mousemove', onMove, true);
      addEventListener('keydown', onKey, true);
      EVENTS.forEach(type => addEventListener(type, swallow, true));
      notices.show({ key: 'zap', title: 'Zap mode', sub: 'Click anything to remove it. Esc to stop.', sticky: true, actions: [{ label: 'Stop', run: stop }] });
      send({ type: 'zapState', on: true });
    }

    function stop() {
      if (!active) return;
      active = false;
      box.remove();
      removeEventListener('mousemove', onMove, true);
      removeEventListener('keydown', onKey, true);
      EVENTS.forEach(type => removeEventListener(type, swallow, true));
      notices.hide('zap');
      send({ type: 'zapState', on: false });
    }

    return {
      toggle() {
        active ? stop() : start();
        return active;
      },
      get active() {
        return active;
      },
    };
  })();

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    // "Destroy ad" in a frame: these go to that frame, not the top one.
    if (message?.type === 'skipVideo') {
      destroyer.skipVideo(message.src);
      return;
    }
    if (message?.type === 'pointOut') {
      destroyer.pointOut(message.token);
      return;
    }
    if (!isTop) return;
    switch (message?.type) {
      case 'ping':
        sendResponse({ ok: true, zapping: zapper.active });
        break;
      case 'blockedHere':
        if (settings.notices) showBlockedNotice(message);
        if (on('stickman')) stickman.ghost(message.kind, message.detail);
        break;
      case 'sendStickman':
        sendResponse({ found: stickman.send() });
        break;
      case 'removeOverlay':
        sendResponse({ removed: overlays.removeNow() });
        break;
      case 'zap':
        sendResponse({ zapping: zapper.toggle() });
        break;
      case 'destroyAd':
        destroyer.destroy(message);
        sendResponse({}); // the background waits for this before asking the frame to point itself out
        break;
    }
  });

  load();
})();

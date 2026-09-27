// Runs inside the page itself (MAIN world) at document_start, so it can wrap window.open,
// alert() and friends before the page's own scripts grab references to them.
// It holds no settings and makes no decisions: for each attempt it asks content.js, which
// answers by cancelling the question event (dispatchEvent is synchronous across worlds).
// Pages can tamper with anything in here, so this is only the first line of defence; the
// background worker still closes any pop-up tab that slips past it.
//
// Self-contained on purpose: Chrome injects a given file only once per frame, so this
// world can't share common.js with content.js.
(() => {
  const CHECK_EVENT = 'gxpb:check';
  const realDispatch = EventTarget.prototype.dispatchEvent;
  const stringify = JSON.stringify;

  // True if content.js says to block it (it also logs it).
  const shouldBlock = detail =>
    !realDispatch.call(window, new CustomEvent(CHECK_EVENT, { detail: stringify(detail), cancelable: true }));

  function absolute(url) {
    if (url === undefined || url === null || url === '') return 'about:blank';
    try {
      return new URL(String(url), document.baseURI).href;
    } catch {
      return String(url);
    }
  }

  // Same shape as PB.linkInfo in common.js.
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

  // --- window.open ---

  const guarded = new WeakSet();
  function guardWindow(win) {
    try {
      if (!win || guarded.has(win)) return;
      guarded.add(win);
      const realOpen = win.open; // throws for cross-origin windows, which is fine
      win.open = function open(url, target) {
        const info = {
          href: absolute(url),
          target: target === undefined || target === null || target === '' ? '_blank' : String(target),
        };
        if (shouldBlock({ kind: 'popup', info })) return null;
        return realOpen.apply(this, arguments);
      };
    } catch {}
  }
  guardWindow(window);

  // Ad scripts dodge a wrapped window.open by borrowing a fresh one from a new iframe.
  function hookFrameGetter(proto, prop, toWindow) {
    const desc = Object.getOwnPropertyDescriptor(proto, prop);
    if (!desc || !desc.get) return;
    const get = desc.get;
    Object.defineProperty(proto, prop, {
      ...desc,
      get() {
        const value = get.call(this);
        if (value) guardWindow(toWindow(value));
        return value;
      },
    });
  }
  for (const proto of [HTMLIFrameElement.prototype, HTMLFrameElement.prototype]) {
    hookFrameGetter(proto, 'contentWindow', w => w);
    hookFrameGetter(proto, 'contentDocument', d => d.defaultView);
  }

  // --- script-made clicks on links (often on links never added to the page) ---

  const realClick = HTMLElement.prototype.click;
  HTMLElement.prototype.click = function click() {
    const info = linkInfo(this, null);
    if (info && shouldBlock({ kind: 'popup', info })) return;
    return realClick.call(this);
  };

  EventTarget.prototype.dispatchEvent = function dispatchEvent(event) {
    if (event && event.type === 'click' && !event.isTrusted && this instanceof Element) {
      const info = linkInfo(this.closest('a[href], area[href]'), event);
      if (info && shouldBlock({ kind: 'popup', info })) return false;
    }
    return realDispatch.call(this, event);
  };

  // --- alert / confirm / prompt ---

  const blockedResult = { alert: undefined, confirm: false, prompt: null };
  for (const name of Object.keys(blockedResult)) {
    const real = window[name];
    window[name] = function (message) {
      let text = '';
      try {
        text = String(message ?? '').slice(0, 80);
      } catch {}
      if (shouldBlock({ kind: 'dialog', detail: `${name}(${stringify(text)})` })) return blockedResult[name];
      return real.apply(this, arguments);
    };
  }

  // --- "Leave site?" ---

  // Registered before any page script, so stopping propagation here keeps every page
  // beforeunload handler (including window.onbeforeunload) from asking.
  window.addEventListener('beforeunload', e => {
    if (shouldBlock({ kind: 'leave' })) e.stopImmediatePropagation();
  }, true);

  // --- notification permission prompts ---

  if (window.Notification) {
    const realRequest = Notification.requestPermission;
    Notification.requestPermission = function requestPermission(callback) {
      if (Notification.permission === 'default' && shouldBlock({ kind: 'notification' })) {
        if (typeof callback === 'function') setTimeout(callback, 0, 'default');
        return Promise.resolve('default');
      }
      return realRequest.apply(this, arguments);
    };
  }

  if (window.PushManager) {
    const realSubscribe = PushManager.prototype.subscribe;
    PushManager.prototype.subscribe = function subscribe() {
      if (window.Notification && Notification.permission === 'default' && shouldBlock({ kind: 'notification' })) {
        return Promise.reject(new DOMException('Registration failed - permission denied', 'NotAllowedError'));
      }
      return realSubscribe.apply(this, arguments);
    };
  }
})();

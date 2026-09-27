// The sidebar menu. Reads and writes chrome.storage directly; the content scripts and
// background worker pick up changes through storage.onChanged.

const $ = id => document.getElementById(id);

let settings = { ...PB.DEFAULTS };
let allowlist = [];
let total = 0;
let log = [];
let tabCounts = {};

let tab = null;        // the active tab in this window
let reachable = false; // our content script answered in that tab
let locked = false;    // a website Opera won't let extensions touch (e.g. its add-ons store)
let zapping = false;

if (new URLSearchParams(location.search).has('popup')) document.body.classList.add('popup');

const KIND_ICONS = {
  popup: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/><path d="M12 12v5M9.5 14.5h5"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  overlay: '<rect x="3" y="3" width="18" height="18" rx="2"/><rect x="7" y="8" width="10" height="8" rx="1.5"/>',
  dialog: '<path d="M4 5h16v11H9l-5 4z"/><path d="M12 8v3.5M12 13.8v.2"/>',
  notification: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  ad: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M6.5 15l2-6 2 6M7.2 13.2h2.6M13.5 9v6h1.3a3 3 0 0 0 0-6z"/>',
};

function icon(inner) {
  const span = document.createElement('span');
  span.className = 'row-icon';
  span.innerHTML = `<svg viewBox="0 0 24 24">${inner}</svg>`; // our own constant markup
  return span;
}

function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  Object.assign(el, props);
  el.append(...children.filter(c => c !== null && c !== undefined && c !== false));
  return el;
}

function ago(time) {
  const s = Math.round((Date.now() - time) / 1000);
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m ago`;
  const hours = Math.round(m / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function shortUrl(url) {
  try {
    const u = new URL(url);
    return u.hostname.replace(/^www\./, '') + (u.pathname === '/' ? '' : u.pathname) + u.search;
  } catch {
    return url;
  }
}

const saveSettings = patch => chrome.storage.local.set({ settings: { ...settings, ...patch } });
const saveAllowlist = list => chrome.storage.local.set({ allowlist: list });

// --- rendering ---

function renderHeader() {
  $('enabled').checked = settings.enabled;
  document.body.classList.toggle('off', !settings.enabled);
  $('total').textContent = total ? `${total.toLocaleString()} blocked in total` : 'Nothing blocked yet';
}

function renderToggles() {
  for (const input of document.querySelectorAll('input[data-key]')) {
    input.checked = !!settings[input.dataset.key];
  }
  $('sign-in-row').classList.toggle('disabled', !settings.popups);
  document.body.classList.toggle('no-stickman', !settings.stickman);
  fighter.setEnabled(settings.enabled && settings.stickman);
}

function renderSite() {
  const host = tab ? PB.hostOf(tab.url) : '';
  const dot = $('site-dot');
  const hint = $('site-hint');
  hint.hidden = true;
  hint.replaceChildren();

  // Opera keeps extensions off its own pages (start page, GX Corner, settings...), so
  // there's nowhere for him to go there.
  $('send-stickman').disabled = !reachable;
  $('stick-note').textContent = reachable || !tab ? ''
    : !host ? "He can't go onto Opera's own pages, like the start page or GX Corner. Open a website first."
    : locked ? "Opera doesn't let extensions onto this page, so he can't go here."
    : 'Reload this page to let him in.';

  if (!host) {
    $('site-host').textContent = 'No website open';
    $('site-status').textContent = 'Browser pages are left alone.';
    dot.className = 'dot';
    $('site-count').hidden = true;
    $('site-actions').hidden = true;
    return;
  }

  const allowed = PB.isAllowed(host, allowlist);
  const count = tabCounts[tab.id] || 0;
  $('site-host').textContent = host;
  $('site-actions').hidden = false;
  $('site-count').hidden = !count;
  $('site-count').querySelector('b').textContent = count;

  if (!settings.enabled) {
    dot.className = 'dot';
    $('site-status').textContent = 'Paused: every blocker is off';
  } else if (allowed) {
    dot.className = 'dot warn';
    $('site-status').textContent = 'Allowed: blockers are off on this site';
  } else {
    dot.className = 'dot ok';
    $('site-status').textContent = 'Protected';
  }

  const allowBtn = $('allow-site');
  allowBtn.textContent = allowed ? 'Block pop-ups on this site again' : 'Allow pop-ups on this site';
  allowBtn.className = allowed ? 'btn wide primary' : 'btn wide';

  $('remove-overlay').disabled = !reachable;
  $('zap').disabled = !reachable;
  $('zap').classList.toggle('active', zapping);
  $('zap-label').textContent = zapping ? 'Stop zapping' : 'Zap element';

  if (locked) {
    hint.hidden = false;
    hint.append("Opera doesn't let extensions run on this page, so the blockers can't work here.");
  } else if (!reachable) {
    hint.hidden = false;
    hint.append('This page was open before the blocker started. ',
      h('button', { className: 'link-btn', textContent: 'Reload it', onclick: () => chrome.tabs.reload(tab.id).catch(() => {}) }),
      ' to turn on every blocker.');
  }
}

function renderLog() {
  const box = $('log');
  $('clear-log').hidden = !log.length;
  if (!log.length) {
    box.replaceChildren(h('p', { className: 'empty', textContent: 'Nothing blocked yet. Browse around; blocked things show up here.' }));
    return;
  }
  box.replaceChildren(...log.slice(0, 30).map(entry => {
    const isUrl = /^https?:/i.test(entry.detail);
    const main = isUrl ? shortUrl(entry.detail) : entry.detail || PB.KINDS[entry.kind];
    const meta = [PB.KINDS[entry.kind], entry.site && `on ${entry.site}`, ago(entry.time)].filter(Boolean).join(' · ');
    const open = isUrl && (entry.kind === 'popup' || entry.kind === 'link')
      ? h('button', { className: 'btn small', textContent: 'Open', title: 'Open this pop-up in a new tab', onclick: () => chrome.tabs.create({ url: entry.detail }) })
      : null;
    return h('div', { className: 'log-item', title: entry.detail },
      icon(KIND_ICONS[entry.kind] || KIND_ICONS.popup),
      h('div', { className: 'log-text' },
        h('div', { className: 'log-main', textContent: main }),
        h('div', { className: 'log-meta', textContent: meta })),
      open);
  }));
}

function renderAllowed() {
  const box = $('allowed');
  if (!allowlist.length) {
    box.replaceChildren(h('p', { className: 'empty', textContent: 'No sites allowed. Use the button above to let a site open pop-ups.' }));
    return;
  }
  box.replaceChildren(...allowlist.map(host => {
    const remove = h('button', { title: `Block pop-ups on ${host} again`, onclick: () => saveAllowlist(allowlist.filter(d => d !== host)) });
    remove.innerHTML = '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>';
    return h('span', { className: 'chip' }, h('span', { textContent: host }), remove);
  }));
}

function render() {
  renderHeader();
  renderToggles();
  renderSite();
  renderLog();
  renderAllowed();
}

// --- data ---

async function loadData() {
  const local = await chrome.storage.local.get(['settings', 'allowlist', 'total']);
  const session = await chrome.storage.session.get(['log', 'tabCounts']);
  settings = { ...PB.DEFAULTS, ...local.settings };
  allowlist = local.allowlist || [];
  total = local.total || 0;
  log = session.log || [];
  seen = new Set(log.map(entry => entry.id));
  tabCounts = session.tabCounts || {};
}

async function loadTab() {
  let [active] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!active) [active] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  tab = active || null;
  reachable = false;
  locked = false;
  zapping = false;
  if (tab && PB.hostOf(tab.url)) {
    try {
      const pong = await chrome.tabs.sendMessage(tab.id, { type: 'ping' }, { frameId: 0 });
      reachable = !!pong;
      zapping = !!pong?.zapping;
    } catch {}
    if (!reachable) {
      // No answer: either the page predates the blocker (a reload fixes it) or Opera
      // refuses extensions there. A do-nothing script tells the two apart.
      try {
        await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: () => {} });
      } catch {
        locked = true;
      }
    }
  }
  renderSite();
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local') {
    if (changes.settings) settings = { ...PB.DEFAULTS, ...changes.settings.newValue };
    if (changes.allowlist) allowlist = changes.allowlist.newValue || [];
    if (changes.total) total = changes.total.newValue || 0;
  } else if (area === 'session') {
    if (changes.log) {
      log = changes.log.newValue || [];
      smashNew();
    }
    if (changes.tabCounts) tabCounts = changes.tabCounts.newValue || {};
  }
  render();
});

chrome.tabs.onActivated.addListener(loadTab);
chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (tabId === tab?.id && (info.url || info.status === 'complete')) loadTab();
});
chrome.windows.onFocusChanged.addListener(loadTab);

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type === 'zapState' && sender.tab?.id === tab?.id) {
    zapping = message.on;
    renderSite();
  }
});

// --- controls ---

$('enabled').addEventListener('change', e => saveSettings({ enabled: e.target.checked }));

for (const input of document.querySelectorAll('input[data-key]')) {
  input.addEventListener('change', () => saveSettings({ [input.dataset.key]: input.checked }));
}

$('allow-site').addEventListener('click', () => {
  const host = PB.hostOf(tab?.url);
  if (!host) return;
  saveAllowlist(PB.isAllowed(host, allowlist)
    ? allowlist.filter(d => !PB.isAllowed(host, [d]))
    : [...allowlist, host]);
});

let statusTimer = 0;
function toolStatus(text) {
  $('tool-status').textContent = text;
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => ($('tool-status').textContent = ''), 5000);
}

$('remove-overlay').addEventListener('click', async () => {
  try {
    const { removed } = await chrome.tabs.sendMessage(tab.id, { type: 'removeOverlay' }, { frameId: 0 });
    toolStatus(removed
      ? `Removed ${removed} layer${removed > 1 ? 's' : ''}. Click again for more, or reload the page to undo.`
      : 'Nothing is covering the middle of the page.');
  } catch {
    toolStatus("Couldn't reach this page. Try reloading it.");
  }
});

$('zap').addEventListener('click', async () => {
  try {
    ({ zapping } = await chrome.tabs.sendMessage(tab.id, { type: 'zap' }, { frameId: 0 }));
    renderSite();
    toolStatus(zapping ? 'Click anything on the page to remove it. Press Esc to stop.' : '');
  } catch {
    toolStatus("Couldn't reach this page. Try reloading it.");
  }
});

$('clear-log').addEventListener('click', () => chrome.storage.session.set({ log: [] }));

// --- the stickman's stage ---

// He lives here and smashes a little stand-in for everything that gets blocked.
const fighter = new Stickman.Fighter($('stage'), { scale: 0.8, stay: true, floor: 5 });
fighter.start();
let seen = new Set();

const GHOST_TEXT = { popup: 'POP-UP', link: 'AD LINK', overlay: 'COVER', dialog: 'ALERT!', notification: 'NOTIFY?', ad: 'AD' };

function spawnGhost(title, body) {
  if (fighter.targets.length >= 4) return;
  const w = 84;
  const h = 50;
  const width = $('stage').clientWidth;
  fighter.add(Stickman.ghost({
    x: 8 + Math.random() * Math.max(0, width - w - 16),
    y: 8 + Math.random() * 84,
    w, h, title, body,
  }));
}

function smashNew() {
  const fresh = log.filter(entry => !seen.has(entry.id));
  fresh.forEach(entry => seen.add(entry.id));
  for (const entry of fresh.slice(0, 3)) {
    const title = /^https?:/i.test(entry.detail) ? shortUrl(entry.detail) : entry.site || PB.KINDS[entry.kind];
    spawnGhost(title, GHOST_TEXT[entry.kind] || 'POP-UP');
  }
}

$('stage').addEventListener('click', () => spawnGhost('practice.test', 'POP-UP'));

$('send-stickman').addEventListener('click', async () => {
  const status = text => {
    $('stick-status').textContent = text;
    setTimeout(() => ($('stick-status').textContent = ''), 5000);
  };
  try {
    const { found } = await chrome.tabs.sendMessage(tab.id, { type: 'sendStickman' }, { frameId: 0 });
    status(found
      ? `He's on it: ${found} thing${found > 1 ? 's' : ''} to smash.`
      : 'Nothing to smash on this page. He came to say hi.');
  } catch {
    status("Couldn't reach this page. Try reloading it.");
  }
});

setInterval(renderLog, 30000); // keep "2m ago" fresh

loadData().then(render).then(loadTab);

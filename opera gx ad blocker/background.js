importScripts('common.js');

// Settings and the allow-list live in storage.local (the panel edits them). The blocked
// log and per-tab counters live in storage.session, so they reset when Opera restarts.
let settings = { ...PB.DEFAULTS };
let allowlist = [];
let total = 0;
let log = [];
let tabCounts = {};

const ready = (async () => {
  const local = await chrome.storage.local.get(['settings', 'allowlist', 'total']);
  const session = await chrome.storage.session.get(['log', 'tabCounts']);
  settings = { ...PB.DEFAULTS, ...local.settings };
  allowlist = local.allowlist || [];
  total = local.total || 0;
  log = session.log || [];
  tabCounts = session.tabCounts || {};
})();

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local') return;
  if (changes.settings) settings = { ...PB.DEFAULTS, ...changes.settings.newValue };
  if (changes.allowlist) allowlist = changes.allowlist.newValue || [];
});

let persistTimer = 0;
function persist() {
  clearTimeout(persistTimer);
  persistTimer = setTimeout(() => {
    chrome.storage.local.set({ total });
    chrome.storage.session.set({ log, tabCounts });
  }, 200);
}

const sidebar = globalThis.opr?.sidebarAction;
chrome.action.setBadgeBackgroundColor({ color: '#fa1e4e' });
try {
  sidebar?.setBadgeBackgroundColor?.({ color: [250, 30, 78, 255] });
} catch {}

function updateBadge(tabId) {
  const n = tabCounts[tabId] || 0;
  const text = n ? (n > 99 ? '99+' : String(n)) : '';
  chrome.action.setBadgeText({ tabId, text }).catch(() => {});
  try {
    sidebar?.setBadgeText?.({ tabId, text });
  } catch {}
}

async function recordBlocked(tabId, kind, detail, pageUrl) {
  await ready;
  total++;
  tabCounts[tabId] = (tabCounts[tabId] || 0) + 1;
  log.unshift({ id: crypto.randomUUID(), kind, detail, site: PB.hostOf(pageUrl), time: Date.now() });
  log.length = Math.min(log.length, 50);
  updateBadge(tabId);
  persist();
  // The page shows a notice and/or sends the stickman after it, depending on the settings.
  chrome.tabs.sendMessage(tabId, { type: 'blockedHere', kind, detail }, { frameId: 0 }).catch(() => {});
}

chrome.webNavigation.onCommitted.addListener(async ({ tabId, frameId }) => {
  if (frameId !== 0) return;
  await ready;
  if (tabCounts[tabId]) {
    delete tabCounts[tabId];
    persist();
  }
  updateBadge(tabId);
});

chrome.tabs.onRemoved.addListener(async tabId => {
  intents.delete(tabId);
  await ready;
  if (tabCounts[tabId]) {
    delete tabCounts[tabId];
    persist();
  }
});

// --- new tabs the user asked for ---

// content.js reports every real link click (and right-click, for "Open in new tab").
// A new tab whose URL matches one of these is the user's; anything else is a pop-up.
const intents = new Map();

function normalize(url) {
  try {
    const u = new URL(url);
    u.hash = '';
    return u.href;
  } catch {
    return String(url);
  }
}

function addIntent(tabId, url, ttl) {
  const now = Date.now();
  const list = (intents.get(tabId) || []).filter(i => i.until > now);
  list.push({ url: url === '*' ? '*' : normalize(url), until: now + Math.min(Number(ttl) || 3000, 30000) });
  intents.set(tabId, list.slice(-20));
}

function takeIntent(tabId, url) {
  const now = Date.now();
  const list = intents.get(tabId) || [];
  const target = normalize(url);
  const exact = list.find(i => i.until > now && i.url === target);
  if (exact) return true;
  const any = list.find(i => i.until > now && i.url === '*');
  if (any) list.splice(list.indexOf(any), 1); // a right-click covers one tab
  return !!any;
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Safety net behind page-guard.js: closes pop-up tabs opened by tricks it can't see.
chrome.webNavigation.onCreatedNavigationTarget.addListener(async details => {
  await ready;
  if (!settings.enabled || !settings.popups) return;
  let source;
  try {
    source = await chrome.tabs.get(details.sourceTabId);
  } catch {
    return;
  }
  const site = PB.hostOf(source.url);
  if (!site || PB.isAllowed(site, allowlist)) return;
  if (settings.signIn && PB.isSignInUrl(details.url)) return;

  // Without our content script in the page (e.g. store pages extensions can't touch)
  // we'd never hear about the user's clicks, so leave those tabs alone.
  try {
    const pong = await chrome.tabs.sendMessage(details.sourceTabId, { type: 'ping' }, { frameId: 0 });
    if (!pong) return;
  } catch {
    return;
  }

  // The click report and this event race each other; give the click a moment to land.
  for (const wait of [0, 150, 350]) {
    if (wait) await sleep(wait);
    if (takeIntent(details.sourceTabId, details.url)) return;
  }

  let url = details.url;
  try {
    const tab = await chrome.tabs.get(details.tabId);
    url = tab.pendingUrl || tab.url || url;
  } catch {
    return; // already closed
  }
  if (settings.signIn && PB.isSignInUrl(url)) return;
  chrome.tabs.remove(details.tabId).catch(() => {});
  recordBlocked(details.sourceTabId, 'popup', url, source.url);
});

// --- messages from content.js ---

chrome.runtime.onMessage.addListener((message, sender) => {
  const tab = sender.tab;
  if (!tab || tab.id === undefined) return;
  switch (message?.type) {
    case 'blocked':
      if (Object.hasOwn(PB.KINDS, message.kind)) {
        recordBlocked(tab.id, message.kind, String(message.detail ?? '').slice(0, 500), tab.url);
      }
      break;
    case 'intent':
      addIntent(tab.id, message.url, message.ttl);
      break;
    case 'openBlocked':
      if (/^https?:/i.test(message.url)) {
        chrome.tabs.create({ url: message.url, index: tab.index + 1, openerTabId: tab.id, windowId: tab.windowId });
      }
      break;
    case 'allowSite': {
      const host = PB.hostOf(tab.url);
      if (host && !PB.isAllowed(host, allowlist)) {
        allowlist = [...allowlist, host];
        chrome.storage.local.set({ allowlist });
      }
      break;
    }
    case 'skipVideo': // the stickman hit the frame a right-clicked video plays in
      if (Number.isInteger(message.frameId)) {
        chrome.tabs.sendMessage(tab.id, { type: 'skipVideo', src: message.src }, { frameId: message.frameId }).catch(() => {});
      }
      break;
  }
});

// --- "Destroy ad" in the right-click menu ---

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: 'destroyAd',
      title: 'Destroy ad',
      contexts: ['page', 'frame', 'link', 'image', 'video', 'selection'],
    });
  });
});

// The stickman lives in the top frame, so for an ad inside a frame (or a frame in a frame)
// he goes after the <iframe> the top page holds.
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== 'destroyAd' || !(tab?.id >= 0)) return;
  let frameId = info.frameId || 0;
  let frameUrl = '';
  if (frameId) {
    try {
      const frames = new Map((await chrome.webNavigation.getAllFrames({ tabId: tab.id })).map(f => [f.frameId, f]));
      while (frames.get(frameId)?.parentFrameId > 0) frameId = frames.get(frameId).parentFrameId;
      frameUrl = frames.get(frameId)?.url || '';
    } catch {}
  }
  const video = info.mediaType === 'video' ? { frameId: info.frameId || 0, src: info.srcUrl || '' } : null;
  const token = crypto.randomUUID();
  await chrome.tabs.sendMessage(tab.id, { type: 'destroyAd', frameId, frameUrl, video, token }, { frameId: 0 }).catch(() => {});
  // Only the frame itself can show the top page which <iframe> it is; it answers the token.
  if (frameId) chrome.tabs.sendMessage(tab.id, { type: 'pointOut', token }, { frameId }).catch(() => {});
});

// Tabs that were already open when the extension was installed or updated don't have
// the content scripts yet; add them so blocking works without a reload.
chrome.runtime.onInstalled.addListener(async () => {
  const tabs = await chrome.tabs.query({ url: ['http://*/*', 'https://*/*'] });
  for (const tab of tabs) {
    const target = { tabId: tab.id, allFrames: true };
    try {
      if (await chrome.tabs.sendMessage(tab.id, { type: 'ping' }, { frameId: 0 })) continue; // loaded after install
    } catch {}
    try {
      await chrome.scripting.executeScript({ target, files: ['page-guard.js'], world: 'MAIN', injectImmediately: true });
      await chrome.scripting.executeScript({ target, files: ['common.js', 'stickman.js', 'content.js'], injectImmediately: true });
    } catch {} // discarded tabs and pages extensions may not touch
  }
});

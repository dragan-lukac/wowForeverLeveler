// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- MASTER DATA: built from data/guide.json by scripts/build_guide.py ---
const GUIDE = window.GUIDE;
const zoneLabel = name => `${name} (${GUIDE.zones[name].levels})`;

// The bank character is planned like the others but has no professions and no leveling route.
const PLAN_CHARACTERS = [...GUIDE.characters, ...(GUIDE.bank ? [{ ...GUIDE.bank, bank: true }] : [])];
const CHAR_DATA_BLUEPRINT = Object.fromEntries(PLAN_CHARACTERS.map(c => [c.id, c]));

// A realm with no characters yet: every planned character shows as a grey "to create" card.
const blueprintRealm = title => ({
  title,
  subtitle: "Planned characters in play order. 'Open' ones are decided after we play on live.",
  status: "Launch Plan",
  planned: true,
  chars: []
});

// Characters planned in guide.json that this realm does not have yet, Start ones first.
function plannedChars(realm) {
  if (!realm.planned) return [];
  const have = new Set(realm.chars.map(c => c.key));
  // Play order (guide.json `order`), then the open ones, the bank last.
  const order = c => c.bank ? 99 : c.order || 50;
  return PLAN_CHARACTERS
    .filter(c => !have.has(c.id))
    .sort((a, b) => order(a) - order(b))
    .map(c => ({ key: c.id, name: c.name || c.class, level: 'New', planned: true }));
}

const REALM_ROSTERS = {
  'forever-pvp-eu': blueprintRealm("[EU] WoW Forever - PvP (Launch Plan)"),
  'forever-pve-eu': blueprintRealm("[EU] WoW Forever - Normal (Launch Plan)")
};

// Page sections: showView shows one and hides the others. Each full page also has a show...View()
// function that re-renders it; switchRealm uses PAGE_VIEWS to keep an open page open.
// Top tabs and their pages. A tab with several pages shows a small page menu (subnav).
const TABS = {
  launch: { pages: ['launchView'] },
  characters: { pages: ['characterGridView', 'characterDetailView'] },
  professions: { pages: ['trainersView', 'recipesView', 'campingView', 'favorView'],
                 names: { trainersView: '🧭 Trainers', recipesView: '📚 Recipes', campingView: '🏕 Camping', favorView: '🪙 Merchant\'s Favor' } },
  ah: { pages: ['auctionView', 'methodsView', 'mountView'],
        names: { auctionView: '📈 Buy & Sell', methodsView: '💡 Money methods', mountView: '🐺 Mount gold' } }
};
const VIEWS = Object.values(TABS).flatMap(t => t.pages);
const PAGE_VIEWS = { auctionView: () => showAuctionView(), recipesView: () => showRecipesView(), campingView: () => showCampingView(),
                     trainersView: () => showTrainersView(), launchView: () => showLaunchView(), favorView: () => showFavorView(),
                     methodsView: () => showMethodsView(), mountView: () => showMountView() };

function showView(id) {
  VIEWS.forEach(v => document.getElementById(v).classList.toggle('hidden', v !== id));
  const tab = Object.keys(TABS).find(t => TABS[t].pages.includes(id));
  Object.keys(TABS).forEach(t => {
    const btn = document.getElementById(`top-${t}`);
    if (btn) btn.className = `topTab ${t === tab ? 'topTab-on' : ''}`;
  });
  const sub = document.getElementById('subnav');
  const names = TABS[tab].names;
  sub.classList.toggle('hidden', !names);
  if (names) {
    sub.innerHTML = Object.entries(names).map(([page, label]) =>
      `<button onclick="PAGE_VIEWS['${page}']()" class="subTab ${page === id ? 'subTab-on' : ''}">${label}</button>`).join('');
  }
  document.getElementById('top-launch').classList.toggle('hidden', launchAllDone() && tab !== 'launch');
}

// A top tab opens its first page.
function openTab(tab) {
  if (tab === 'characters') return backToOverview();
  PAGE_VIEWS[TABS[tab].pages[0]]();
}

let currentRealmKey = null;
let currentGroupFilter = 'all';
let activeCharacter = null;
let activeCategory = 'leveling';

const FONT_KEY = 'wow_font_size_pct';

function applyFontSize(pct) {
  document.documentElement.style.fontSize = `${pct}%`;
}

function changeFontSize(delta) {
  const current = parseInt(document.documentElement.style.fontSize, 10) || 150;
  const next = Math.min(250, Math.max(90, current + delta));
  applyFontSize(next);
  try { localStorage.setItem(FONT_KEY, String(next)); } catch (e) {}
}

try {
  const saved = parseInt(localStorage.getItem(FONT_KEY), 10);
  if (saved) applyFontSize(saved);
} catch (e) {}

function init() {
  const synced = window.SYNCED_ROSTERS || {};
  const sel = document.getElementById('realmSelect');
  Object.entries(synced).reverse().forEach(([slug, realm]) => {
    // Addon realms (Forever beta or live) also show the planned characters not created yet.
    REALM_ROSTERS[slug] = { ...realm, planned: !!realm.client };
    const opt = document.createElement('option');
    opt.value = slug;
    opt.textContent = realm.title;
    sel.insertBefore(opt, sel.options[0] || null);
  });
  sel.selectedIndex = 0;
  try {
    const saved = sessionStorage.getItem('wow_realm_after_sync');
    sessionStorage.removeItem('wow_realm_after_sync');
    if (saved && REALM_ROSTERS[saved]) sel.value = saved;
  } catch (e) {}
  switchRealm();
}

async function runSync(withBnet) {
  const buttons = [document.getElementById('syncGameBtn'), document.getElementById('syncBnetBtn')];
  const status = document.getElementById('statusText');
  buttons.forEach(b => b.disabled = true);
  status.textContent = withBnet ? 'Log in to Battle.net in the new tab…' : 'Syncing… (waits up to 1 min for the game to save)';
  try {
    const resp = await fetch(`/api/sync${withBnet ? '?bnet=1' : ''}`, {
      method: 'POST',
      headers: { 'X-Requested-With': 'dashboard' }
    });
    const result = await resp.json().catch(() => ({ ok: false, log: `HTTP ${resp.status}` }));
    if (!result.ok) throw new Error(result.log);
    try { sessionStorage.setItem('wow_realm_after_sync', currentRealmKey); } catch (e) {}
    location.reload();
  } catch (err) {
    status.textContent = 'Sync failed';
    alert(`Sync failed.\n\n${err.message}\n\nIs the dashboard started with WFL Dashboard or make serve?`);
    buttons.forEach(b => b.disabled = false);
  }
}

// Auto sync (scripts/server.py watches the save file): when new game data arrives, reload by itself while the
// tab is in the background, or show a small button while you look at it, so the view does not jump.
(function watchSync() {
  let first = null;
  const check = async () => {
    try {
      const r = await fetch('data/.last_sync.json', { cache: 'no-store' });
      if (!r.ok) return;
      const t = (await r.json()).saveFileMtime;
      if (first === null) { first = t; return; }
      if (t === first) return;
      if (document.hidden) return location.reload();
      if (document.getElementById('newDataButton')) return;
      const b = document.createElement('button');
      b.id = 'newDataButton';
      b.textContent = '⟳ New game data: refresh';
      b.className = 'fixed bottom-4 right-4 z-50 px-4 py-2 rounded-lg bg-amber-500 text-slate-900 font-semibold shadow-lg';
      b.onclick = () => location.reload();
      document.body.appendChild(b);
    } catch (e) { /* server not reachable: try again later */ }
  };
  if (typeof window !== 'undefined' && window.fetch && typeof document !== 'undefined' && document.addEventListener) {
    check();
    setInterval(check, 10000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
  }
})();

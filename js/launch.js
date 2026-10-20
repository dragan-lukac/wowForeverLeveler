// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Launch checklist: steps from guide.json, ticked by hand or automatically from synced data ---
const LAUNCH_KEY = 'wow_launch_checklist';
const LAUNCH_DATE = new Date(2026, 10, 4); // November 4, 2026

function showLaunchView() {
  activeCharacter = null;
  showView('launchView');
  renderLaunchView();
}

function loadLaunchTicks() {
  try { return JSON.parse(localStorage.getItem(LAUNCH_KEY) || '{}'); } catch (e) { return {}; }
}

function toggleLaunchItem(id, done) {
  const ticks = loadLaunchTicks();
  ticks[id] = done;
  try { localStorage.setItem(LAUNCH_KEY, JSON.stringify(ticks)); } catch (e) {}
  renderLaunchView();
}

// True when every step is ticked or done by itself: then the Launch tab hides.
function launchAllDone() {
  const ticks = loadLaunchTicks();
  const items = (GUIDE.launchChecklist || []).flatMap(s => s.items);
  return items.length > 0 && items.every(item => launchAutoDone(item) || !!ticks[item.id]);
}

// Live realms are addon realms from any client except the beta.
function liveRealms() {
  return Object.values(REALM_ROSTERS).filter(r => r.client && r.client !== 'classic_beta');
}

// True when synced data already shows the step is done: a live realm, or live characters of the given classes.
function launchAutoDone(item) {
  if (!item.auto) return false;
  // Beta tests: { quests: [ids] } is done when one beta character has completed all of them.
  if (item.auto.quests) {
    const beta = Object.values(REALM_ROSTERS).filter(r => r.client === 'classic_beta').flatMap(r => r.chars);
    return beta.some(c => item.auto.quests.every(id => (c.completedQuests || []).includes(id)));
  }
  const live = liveRealms();
  if (item.auto === 'liveRealm') return live.length > 0;
  // A class id, or a list of class ids that must all exist on a live realm.
  return [].concat(item.auto).every(key => live.some(r => r.chars.some(c => c.key === key)));
}

function renderLaunchView() {
  const ticks = loadLaunchTicks();
  const sections = GUIDE.launchChecklist || [];
  const items = sections.flatMap(s => s.items);
  const isDone = item => launchAutoDone(item) || !!ticks[item.id];
  const done = items.filter(isDone).length;
  const days = Math.ceil((LAUNCH_DATE - new Date()) / 86400000);
  const countdown = days > 0 ? `${days} day${days === 1 ? '' : 's'} to launch` : days === 0 ? 'Launch day!' : 'WoW Forever is live';

  // The planned characters as a list (item.characters): class icon, name, race and class, in play order.
  // A character that already exists on a live realm gets a tick.
  const liveKeys = new Set(liveRealms().flatMap(r => r.chars.map(c => c.key)));
  const charList = () => `<div class="grid sm:grid-cols-2 gap-2 mt-2">${[...PLAN_CHARACTERS]
    .sort((a, b) => (a.bank ? 99 : a.order || 50) - (b.bank ? 99 : b.order || 50))
    .map(c => `<div class="flex items-center gap-3 rounded-lg bg-slate-900/80 border border-slate-800 px-3 py-2">
        ${classIcon({ class: c.class, bank: c.bank }, 'w-9 h-9 text-lg')}
        <div class="min-w-0">
          <div class="text-base font-semibold text-slate-100">${c.name} ${c.lastName || ''}${liveKeys.has(c.id) ? ' <span class="text-emerald-400">✓</span>' : ''}</div>
          <div class="text-sm text-slate-400">${c.race} ${c.class}${c.bank ? ', female · bank' : c.order ? ` · #${c.order}` : ''}</div>
        </div></div>`).join('')}</div>`;

  const row = item => {
    const auto = launchAutoDone(item);
    const checked = isDone(item);
    return `
      <label class="flex items-start gap-3 py-2 border-t border-slate-800/80 ${auto ? '' : 'cursor-pointer'}">
        <input type="checkbox" ${checked ? 'checked' : ''} ${auto ? 'disabled' : ''} onchange="toggleLaunchItem('${item.id}', this.checked)"
               class="mt-1 rounded bg-slate-800 border-slate-700 text-amber-500 focus:ring-0">
        <span class="text-base leading-relaxed ${checked ? 'line-through text-slate-500' : 'text-slate-100'}">${item.text}
          ${auto ? '<span class="text-xs text-emerald-400 no-underline"> (done: seen in synced data)</span>' : ''}
          ${item.characters ? charList() : ''}</span>
      </label>`;
  };

  document.getElementById('launchView').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="text-sm text-amber-300 font-semibold">${countdown}</div>
    </div>
    <h2 class="text-xl font-bold text-slate-100">🚀 Launch checklist</h2>
    <div class="flex items-center gap-3">
      <div class="flex-1 bg-slate-800 h-2 rounded-full overflow-hidden">
        <div class="bg-amber-400 h-full rounded-full" style="width: ${items.length ? Math.round(done / items.length * 100) : 0}%"></div>
      </div>
      <span class="text-sm text-slate-300">${done} / ${items.length} done</span>
    </div>
    ${sections.map(s => `
      <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800">
        <div class="text-sm font-semibold uppercase tracking-wider text-amber-400 mb-1">${s.title}</div>
        ${s.items.map(row).join('')}
      </div>`).join('')}
    ${addonListCard()}
  `;
}

// The addon list from guide.json `addons`, with ✓ for folders installed in any game client (synced).
function addonListCard() {
  const plan = GUIDE.addons;
  if (!plan) return '';
  const installed = new Set(Object.values(window.ADDON_FOLDERS || {}).flat());
  const group = (title, list, mark) => list && list.length ? `
    <div class="mt-3 text-sm font-semibold text-slate-300">${title}</div>
    ${list.map(a => `
      <div class="flex items-start gap-3 py-1.5 border-t border-slate-800/80">
        <span class="w-5 shrink-0">${mark(installed.has(a.folder))}</span>
        <span class="text-base leading-relaxed text-slate-100"><b>${a.name}</b>: <span class="text-slate-300">${a.why}</span></span>
      </div>`).join('')}` : '';
  return `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800">
      <div class="text-sm font-semibold uppercase tracking-wider text-amber-400 mb-1">🧩 Addons to install</div>
      <p class="text-xs text-slate-500">${plan.note} ✓ = installed now (after a Sync).</p>
      ${group('Needed', plan.needed, have => have ? '<span class="text-emerald-400">✓</span>' : '<span class="text-rose-400">✗</span>')}
      ${group('Data only: keep the folder, you can turn it off in game', plan.dataOnly, have => have ? '<span class="text-emerald-400">✓</span>' : '<span class="text-rose-400">✗</span>')}
      ${group('Optional', plan.optional, have => have ? '<span class="text-emerald-400">✓</span>' : '')}
      ${group('Later: for easy leveling with more gold', plan.later, have => have ? '<span class="text-emerald-400">✓</span>' : '')}
      ${group('To try', plan.toTry, have => have ? '<span class="text-emerald-400">✓</span>' : '')}
      ${group('Not needed: you can delete these folders', plan.notNeeded, have => have ? '<span class="text-amber-400">🗑</span>' : '')}
    </div>`;
}

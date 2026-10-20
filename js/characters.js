// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// Character grid, character detail view and the leveling tab.

function switchRealm() {
  const sel = document.getElementById('realmSelect');
  currentRealmKey = sel.value;
  const realmData = REALM_ROSTERS[currentRealmKey] || REALM_ROSTERS['forever-pvp-eu'];

  document.getElementById('realmTitle').innerHTML = `
    <span>${realmData.title}</span>
    <span class="text-xs font-normal px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700" id="charCountBadge">${realmData.chars.length} Characters${plannedChars(realmData).length ? ` · ${plannedChars(realmData).length} to create` : ''}</span>
  `;
  document.getElementById('realmSubtitle').textContent = realmData.subtitle;
  document.getElementById('statusText').textContent = realmData.status;

  const openPage = Object.keys(PAGE_VIEWS).find(id => !document.getElementById(id).classList.contains('hidden'));
  backToOverview();
  if (openPage) PAGE_VIEWS[openPage]();
}

function filterGroup(group) {
  currentGroupFilter = group;
  ['all', 'g1', 'g2', 'g3'].forEach(g => {
    const btn = document.getElementById(`tab-${g}`);
    if (g === group) {
      btn.className = "px-3 py-1 rounded bg-amber-500/20 text-amber-300 font-medium";
    } else {
      btn.className = "px-3 py-1 rounded text-slate-400 hover:text-slate-200";
    }
  });
  renderCharacterGrid();
}

// Zone boxes ticked or unticked by hand. The old key saved every untick as false, which would now hide
// the automatic progress, so only its ticks are carried over.
const ZONE_TICKS_KEY = 'wow_zone_ticks';
function loadZoneTicks() {
  const saved = localStorage.getItem(ZONE_TICKS_KEY);
  if (saved) return JSON.parse(saved);
  const old = JSON.parse(localStorage.getItem('wow_forever_progress') || '{}');
  const ticks = Object.fromEntries(Object.entries(old).filter(([, done]) => done === true));
  localStorage.setItem(ZONE_TICKS_KEY, JSON.stringify(ticks));
  return ticks;
}

// The level to plan with: the addon level, or a higher level typed on the dashboard.
function effectiveLevel(name, addonLevel) {
  const saved = JSON.parse(localStorage.getItem('wow_custom_levels') || '{}');
  const levels = [saved[name], addonLevel].map(l => parseInt(l, 10)).filter(l => !isNaN(l));
  return levels.length ? String(Math.max(...levels)) : addonLevel;
}

// 'done', 'current' or 'upcoming' for each zone. A zone is done once the level reaches its top level or
// the character turned in quests in a later route zone; a box ticked or unticked by hand wins over that. The first zone not done is the current one.
function zoneProgress(name, level, zones, completedMap, questZones = {}) {
  const lvl = parseInt(level, 10);
  // The route zone with the newest quest turn-in: every zone before it is done (the character moved on).
  const times = zones.map(z => questZones[z] || 0);
  const newest = Math.max(...times) > 0 ? times.indexOf(Math.max(...times)) : -1;
  const done = zones.map((z, i) => {
    const manual = completedMap[`${name}_${zoneLabel(z)}`];
    if (manual !== undefined) return manual;
    if (i < newest) return true;
    const top = parseInt(String(GUIDE.zones[z].levels).split('-').pop(), 10);
    return !isNaN(lvl) && !isNaN(top) && lvl >= top;
  });
  const current = done.indexOf(false);
  return done.map((d, i) => d ? 'done' : i === current ? 'current' : 'upcoming');
}

function renderCharacterGrid() {
  if (typeof renderAccountCards === 'function') renderAccountCards();
  const container = document.getElementById('characterCardsContainer');
  const realmData = REALM_ROSTERS[currentRealmKey];
  const completedMap = loadZoneTicks();

  let filteredChars = [...realmData.chars, ...plannedChars(realmData)].filter(c => {
    const meta = CHAR_DATA_BLUEPRINT[c.key];
    if (currentGroupFilter === 'all') return true;
    return meta.group === currentGroupFilter;
  });

  if (filteredChars.length === 0) {
    container.innerHTML = `<div class="col-span-3 py-12 text-center text-slate-500 text-xs">No characters found for this filter on ${realmData.title}.</div>`;
    return;
  }

  container.innerHTML = filteredChars.map(c => {
    const meta = metaFor(c);
    if (c.planned) return plannedCard(c, meta);
    const displayLvl = effectiveLevel(c.name, c.level);
    const doneZones = zoneProgress(c.name, displayLvl, meta.zones, completedMap, c.questZones).filter(s => s === 'done').length;
    const totalZones = meta.zones.length;
    const pct = Math.round((doneZones / totalZones) * 100);

    return `
      <div onclick="selectCharacter('${c.key}', '${c.name}', '${displayLvl}')" 
           class="hover-card cursor-pointer bg-slate-900/60 rounded-xl p-5 border border-slate-800 transition duration-200 flex flex-col justify-between group">
        
        <div>
          <div class="flex items-start justify-between mb-3">
            <div class="flex items-center gap-3">
              ${classIcon(meta)}
              <div>
              <div class="flex items-center space-x-2">
                <h3 class="text-base font-bold text-slate-100 group-hover:text-amber-400 transition">${c.name}${c.lastName && !c.name.includes(' ') ? ` <span class="font-normal text-slate-300">${c.lastName}</span>` : ''}</h3>
                <span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 font-semibold uppercase tracking-wider">${meta.class}</span>
              </div>
              <div class="text-xs text-slate-400 mt-0.5">${meta.race} • <span class="text-amber-400 font-medium">${meta.profText}</span></div>
              </div>
            </div>
            
            <span class="text-xs font-bold px-2 py-1 rounded bg-slate-800/80 border border-${meta.class.toLowerCase()} color-${meta.class.toLowerCase()}">
              Lvl ${displayLvl}
            </span>
          </div>

          ${cardSteps(c, meta, displayLvl)}
        </div>

        <div class="mt-4 pt-3 border-t border-slate-800/60 flex items-center justify-between text-[0.75rem] text-slate-400">
          <div class="flex items-center space-x-2">
            <span>Zones: ${doneZones}/${totalZones}</span>
            <div class="w-16 bg-slate-800 h-1.5 rounded-full overflow-hidden">
              <div class="bg-amber-400 h-full rounded-full" style="width: ${pct}%"></div>
            </div>
          </div>
          <span class="text-amber-400 font-medium group-hover:translate-x-1 transition-transform">Details →</span>
        </div>

      </div>
    `;
  }).join('');
}

// The next two route steps, one line each.
function cardSteps(c, meta, level) {
  return `<div class="mt-3 space-y-1">${nextSteps(c, meta, level).map(s =>
    `<div class="text-sm text-slate-200 leading-snug">${ROUTE_ICONS[s.type] || '•'} ${s.short || s.text}</div>`).join('')}</div>`;
}

// A class symbol in a round badge with the class colour (the game's icon site blocks images on this page).
const CLASS_ICONS = { Hunter: '🏹', Warlock: '👿', Paladin: '🛡️', Priest: '✨', Shaman: '⚡', Warrior: '⚔️',
                      Mage: '❄️', Rogue: '🗡️', Druid: '🐻' };
function classIcon(meta, size = 'w-10 h-10 text-xl') {
  const cls = meta.class.toLowerCase();
  return `<div class="${size} shrink-0 rounded-full bg-slate-800/80 border-2 border-${cls} flex items-center justify-center" title="${meta.class}">${meta.bank ? '💰' : CLASS_ICONS[meta.class] || '⚔️'}</div>`;
}

// A grey card for a character that is planned but not created in game yet: who, professions, play order
// (guide.json `order`; none = still open). Quest and route tips live in the addons.
function plannedCard(c, meta) {
  const plan = CHAR_DATA_BLUEPRINT[c.key];
  return `
      <div onclick="selectCharacter('${c.key}', '${c.name}', '1')"
           class="cursor-pointer rounded-xl p-5 border-2 border-dashed border-slate-700 bg-slate-950/40 opacity-60 hover:opacity-90 transition flex flex-col justify-between">
        <div>
          <div class="flex items-start justify-between mb-2">
            <div class="flex items-center gap-3">
              ${classIcon(meta)}
              <div>
              <div class="flex items-center space-x-2">
                <h3 class="text-base font-bold text-slate-300">${c.name} <span class="${plan.lastName ? '' : 'text-slate-500 italic font-normal'}">${plan.lastName || 'last name?'}</span></h3>
                <span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-slate-800 text-slate-500 font-semibold uppercase tracking-wider">${meta.class}</span>
              </div>
              <div class="text-xs text-slate-500 mt-0.5">${meta.race} • ${meta.profText}</div>
              </div>
            </div>
            <span class="text-xs font-bold px-2 py-1 rounded ${plan.order ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40' : 'bg-slate-800 text-slate-400'}">
              ${plan.bank ? 'Bank' : plan.order ? '#' + plan.order : 'Open'}
            </span>
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-slate-800/60 text-[0.75rem] text-slate-500 flex justify-between">
          <span>Not created yet</span><span>Plan →</span>
        </div>
      </div>
    `;
}

function selectCharacter(key, name, level) {
  const c = REALM_ROSTERS[currentRealmKey].chars.find(ch => ch.name === name) || { key, name };
  activeCharacter = { key, name, level, meta: metaFor(c) };
  activeProfTab = null;
  showView('characterDetailView');

  renderCharacterHero();
  renderActiveLevelingCategory();
  renderActiveProfessionsCategory();
  renderCharMoney();
  switchCategory('leveling');
}

function backToOverview() {
  activeCharacter = null;
  showView('characterGridView');
  renderCharacterGrid();
}

function renderCharacterHero() {
  const { name, level, meta } = activeCharacter;
  const hero = document.getElementById('characterHero');
  hero.className = `p-6 rounded-2xl bg-gradient-to-r from-slate-900 to-slate-950 border border-${meta.class.toLowerCase()} shadow-xl flex flex-col md:flex-row md:items-center justify-between gap-6`;

  hero.innerHTML = `
    <div class="flex items-center space-x-4">
      ${classIcon(meta, 'w-14 h-14 text-3xl')}
      <div>
        <div class="flex items-center space-x-3">
          <h2 class="text-2xl font-bold color-${meta.class.toLowerCase()}">${name}</h2>
          <span class="text-xs px-2 py-0.5 rounded bg-slate-800 border border-slate-700 text-slate-300">${meta.race} ${meta.class}</span>
          <span class="text-xs px-2 py-0.5 rounded bg-amber-500/10 border border-amber-500/30 text-amber-400 font-semibold uppercase tracking-wider">${meta.group.toUpperCase()}</span>
        </div>
        <div class="text-xs text-slate-400 mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
          <span>Professions: <span class="text-amber-300 font-semibold">${meta.profText}</span></span>
          ${meta.profSource === 'game'
            ? `<span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-emerald-950/40 text-emerald-400 border border-emerald-500/20" title="Read from the in-game addon">from game</span>`
            : `<span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700" title="From the plan in data/guide.json">plan</span>`}
          <span>• Role: <span class="text-slate-200">${meta.roleTitle}</span></span>
        </div>
        ${meta.profSource === 'plan' && !meta.bank ? `
          <div class="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
            <span class="text-slate-500">Change plan for every ${meta.class}:</span>
            <select id="planRace" class="bg-slate-900 border border-slate-700 rounded px-1.5 py-0.5 text-amber-300">
              ${Object.entries(GUIDE.races || {}).filter(([, r]) => r.classes.includes(meta.class))
                .map(([race]) => `<option value="${race}" ${race === meta.race ? 'selected' : ''}>${race}</option>`).join('')}
            </select>
            ${[0, 1].map(i => `
              <select id="planProf${i + 1}" class="bg-slate-900 border border-slate-700 rounded px-1.5 py-0.5 text-amber-300">
                ${Object.entries(PROFS).filter(([, p]) => p.type === 'gather' || p.type === 'craft')
                  .map(([code, p]) => `<option value="${code}" ${meta.profs[i] === code ? 'selected' : ''}>${p.name}</option>`).join('')}
              </select>`).join('')}
            <button onclick="savePlanProfs()" class="px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 hover:bg-amber-500/30 font-semibold">Save</button>
          </div>` : ''}
      </div>
    </div>

    <div class="flex items-center space-x-3">
      <div class="text-right">
        <div class="text-[0.75rem] text-slate-400 uppercase tracking-wider font-semibold">Current Level</div>
        <div class="text-xl font-bold text-slate-100 flex items-center justify-end space-x-1 cursor-pointer hover:text-amber-400" onclick="editCharLevel()">
          <span>${level}</span>
          <span class="text-xs text-amber-400 ml-1">✎</span>
        </div>
      </div>
    </div>
  `;
}

function editCharLevel() {
  const current = activeCharacter.level === 'Beta' ? '1' : activeCharacter.level;
  const next = prompt(`Update current level for ${activeCharacter.name}:`, current);
  if (next !== null && next.trim() !== '') {
    const saved = JSON.parse(localStorage.getItem('wow_custom_levels') || '{}');
    saved[activeCharacter.name] = next.trim();
    localStorage.setItem('wow_custom_levels', JSON.stringify(saved));
    activeCharacter.level = next.trim();
    renderCharacterHero();
    renderCharacterGrid();
    renderActiveLevelingCategory();
  }
}

const CATEGORIES = { leveling: 'categoryLeveling', professions: 'categoryProfessions', money: 'categoryMoney' };

function switchCategory(cat) {
  activeCategory = cat;
  Object.entries(CATEGORIES).forEach(([key, sectionId]) => {
    const active = key === cat;
    document.getElementById(`catTab-${key}`).className = active
      ? "pb-3 border-b-2 border-amber-500 text-amber-400 flex items-center space-x-2"
      : "pb-3 border-b-2 border-transparent text-slate-400 hover:text-slate-200 flex items-center space-x-2";
    document.getElementById(sectionId).classList.toggle('hidden', !active);
  });
}

function renderActiveLevelingCategory() {
  if (!activeCharacter) return;
  const { name, level, meta } = activeCharacter;
  // The synced character (finished quests, rested XP), or just the name for a planned one.
  const synced = (REALM_ROSTERS[currentRealmKey].chars || []).find(ch => ch.name === name);
  renderRoute(document.getElementById('zonesTimelineContainer'), synced || { name }, meta, level);
}

function toggleZoneDone(idx, checked) {
  const key = `${activeCharacter.name}_${zoneLabel(activeCharacter.meta.zones[idx])}`;
  const completedMap = loadZoneTicks();
  completedMap[key] = checked;
  localStorage.setItem(ZONE_TICKS_KEY, JSON.stringify(completedMap));
  renderActiveLevelingCategory();
}

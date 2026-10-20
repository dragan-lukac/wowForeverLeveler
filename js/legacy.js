// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Rested XP and Legacy points: two cards above the character grid, from guide.json `legacy` and the
// synced characters. Both are estimates; the tips are suggestions, not rules. ---

// Rested XP now: the value saved at the last logout plus what built up since (5% of a level per
// 8 hours in an inn or city, 4 times slower outside), up to 1.5 levels; Well Rested adds 4% per rank.
function restedNow(c, now = Date.now() / 1000) {
  const L = GUIDE.legacy;
  if (!L || c.restedXp == null || !c.maxXp) return null;
  const boost = 1 + (L.wellRestedRanks || 0) * L.rested.perRank;
  const hours = Math.max(0, (now - (c.updatedT || now)) / 3600);
  const perHour = c.maxXp * L.rested.perEightHours / 8 * (c.resting ? 1 : L.rested.outsideInn) * boost;
  const cap = c.maxXp * L.rested.cap * boost;
  const xp = Math.min(cap, c.restedXp + perHour * hours);
  return { levels: xp / c.maxXp, capLevels: cap / c.maxXp, daysToFull: xp >= cap ? 0 : (cap - xp) / perHour / 24 };
}

function restedCard(chars) {
  const L = GUIDE.legacy;
  const rows = chars.map(c => ({ c, r: restedNow(c) })).filter(x => x.r).sort((a, b) => b.r.levels - a.r.levels);
  const list = rows.length ? rows.map(({ c, r }) => `
      <div class="flex items-center gap-3 py-1.5 border-t border-slate-800/80">
        <span class="w-40 shrink-0 text-slate-100">${c.name} <span class="text-slate-500">${c.level}</span></span>
        <div class="flex-1 bg-slate-800 h-2 rounded-full overflow-hidden"><div class="bg-sky-400 h-full" style="width: ${Math.round(r.levels / r.capLevels * 100)}%"></div></div>
        <span class="w-56 shrink-0 text-sm text-slate-300">${r.levels.toFixed(1)} levels${r.daysToFull ? ` · full in ${Math.ceil(r.daysToFull)} days` : ' · full'}${c.resting ? '' : ' · <span class="text-amber-400">not in an inn</span>'}</span>
      </div>`).join('') : '<p class="text-sm text-slate-400">No rested XP data yet: needs addon 3.4.0, /reload and Sync.</p>';
  return `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
      <div class="text-sm font-semibold uppercase tracking-wider text-sky-300">😴 Rested XP</div>
      ${list}
      <details class="text-sm text-slate-300"><summary class="cursor-pointer text-slate-400">How to use rested XP (tips, not rules)</summary>
        <ul class="list-disc pl-5 pt-2 space-y-1">${L.rested.tips.map(t => `<li>${t}</li>`).join('')}</ul></details>
    </div>`;
}

// Legacy points sync can see: the first character of each class at 25/45/60 and each crafting
// profession at 150/225/300 (gathering professions do not count).
function legacyProgress(chars) {
  const L = GUIDE.legacy;
  const levels = L.objectives.find(o => o.kind === 'level').values;
  const profGoal = L.objectives.find(o => o.kind === 'profession');
  const skills = profGoal.values;
  const counts = new Set(profGoal.only || Object.keys(PROFS));
  const byClass = {}, byProf = {};
  chars.forEach(c => {
    const cls = String((CHAR_DATA_BLUEPRINT[c.key] || {}).class || c.key);
    byClass[cls] = Math.max(byClass[cls] || 0, parseInt(c.level, 10) || 0);
    (c.professions || []).forEach(p => {
      const code = CODE_BY_NAME[p.name];
      if (code && counts.has(code)) byProf[p.name] = Math.max(byProf[p.name] || 0, p.rank || 0);
    });
  });
  let points = 0;
  const next = [];
  Object.entries(byClass).forEach(([cls, lvl]) => {
    points += levels.filter(v => lvl >= v).length;
    const goal = levels.find(v => lvl < v);
    if (goal) next.push({ text: `${cls} to level ${goal}`, left: goal - lvl, unit: 'levels', weight: (goal - lvl) * 30 });
  });
  Object.entries(byProf).forEach(([prof, rank]) => {
    points += skills.filter(v => rank >= v).length;
    const goal = skills.find(v => rank < v);
    if (goal) next.push({ text: `${prof} to ${goal}`, left: goal - rank, unit: 'skill points', weight: goal - rank });
  });
  // Rough effort: one character level counts like 30 skill points.
  next.sort((a, b) => a.weight - b.weight);
  return { points, next: next.slice(0, 3) };
}

function legacyCard(chars) {
  const L = GUIDE.legacy;
  const { points, next } = legacyProgress(chars);
  return `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
      <div class="text-sm font-semibold uppercase tracking-wider text-amber-400">⭐ Legacy points</div>
      <p class="text-base text-slate-100">About <b>${points}</b> point${points === 1 ? '' : 's'} from what sync can see.</p>
      ${next.length ? `<div class="text-sm text-slate-300">Next easiest: ${next.map(n => `<b>${n.text}</b> (${n.left} ${n.unit} left)`).join(' · ')}</div>` : ''}
      <details class="text-sm text-slate-300"><summary class="cursor-pointer text-slate-400">Where to spend them</summary>
        <ul class="list-disc pl-5 pt-2 space-y-1">${L.perks.map(p => `<li><b>${p.name}</b>${p.ranks ? ` (${p.ranks} ranks)` : ''}: ${p.text} Best for: ${p.best}.</li>`).join('')}</ul>
        <p class="pt-2 text-xs text-slate-500">${L.perksNote || ''}</p>
        ${L.spelunker ? `<div class="pt-2"><b>Dungeon points</b> (${L.spelunker.note})${Object.entries(L.spelunker.tiers).map(([t, list]) => `<div class="pt-1"><span class="text-amber-300">${t}:</span> ${list.join(', ')}</div>`).join('')}</div>` : ''}
        <p class="pt-2 text-xs text-slate-500">Counts: ${L.objectives.map(o => o.text).join('; ')}. ${L.rewards || ''} ${L.note} Set your Well Rested rank in guide.json (legacy.wellRestedRanks): now ${L.wellRestedRanks}.</p>
      </details>
    </div>`;
}

function renderAccountCards() {
  const box = document.getElementById('accountCards');
  if (!box) return;
  const realm = REALM_ROSTERS[currentRealmKey];
  if (!GUIDE.legacy || !realm || !realm.chars.length) { box.innerHTML = ''; return; }
  box.innerHTML = restedCard(realm.chars) + legacyCard(realm.chars);
}

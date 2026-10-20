// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Recipes view: every recipe we know about, per profession ---
let recipesProf = null;
let recipesQuery = '';

function recipeRows(code, chars, book) {
  const profName = PROFS[code].name;
  const trainer = trainerBook(profName) || {};
  const vendors = vendorBook(profName);
  const guide = PROFS[code].recipes || {};
  const knownBy = {}, gameReagents = {};
  chars.forEach(c => {
    const scan = (c.recipes || {})[profName];
    Object.entries((scan && scan.recipes) || {}).forEach(([name, r]) => {
      (knownBy[name] = knownBy[name] || []).push(c.name);
      if (r.reagents && r.reagents.length) gameReagents[name] = r.reagents.map(g => [g.name, g.count]);
    });
  });
  const names = new Set([...Object.keys(trainer), ...Object.keys(vendors), ...Object.keys(guide), ...Object.keys(knownBy)]);
  return [...names].map(name => {
    const reagents = gameReagents[name] || Object.entries(guide[name] || {});
    let cost = 0;
    for (const [n, q] of reagents) {
      const p = unitCost(book, code, n);
      if (p == null) { cost = null; break; }
      cost += p * q;
    }
    const t = trainer[name];
    return {
      name, skill: t ? t.skill : (vendors[name] && vendors[name].skill != null ? vendors[name].skill : guideSkillFor(code, name)),
      level: t && t.level, trainerCost: t && t.cost, soldBy: vendors[name] ? vendorText(vendors[name]) : null,
      reagents, fromGame: !!gameReagents[name], cost: reagents.length ? cost : null,
      value: latestPrice(book, name), knownBy: knownBy[name] || [], atTrainer: !!t
    };
  }).sort((a, b) => (a.skill ?? 999) - (b.skill ?? 999) || a.name.localeCompare(b.name));
}

function showRecipesView() {
  activeCharacter = null;
  showView('recipesView');
  renderRecipesView();
}

function setRecipesProf(code) { recipesProf = code; renderRecipesView(); }

function setRecipesQuery(value) {
  recipesQuery = value;
  renderRecipesView();
  const box = document.getElementById('recipesSearch');
  box.focus();
  box.setSelectionRange(value.length, value.length);
}

function renderRecipesView() {
  const realm = REALM_ROSTERS[currentRealmKey];
  const book = priceBook(realm);
  const crafting = Object.keys(PROFS).filter(isCrafting);
  if (!crafting.includes(recipesProf)) recipesProf = crafting[0];
  const rows = recipeRows(recipesProf, realm.chars, book)
    .filter(r => !recipesQuery || r.name.toLowerCase().includes(recipesQuery.toLowerCase()));
  const trainerCount = Object.keys(trainerBook(PROFS[recipesProf].name) || {}).length;

  document.getElementById('recipesView').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-3">
      <input id="recipesSearch" value="${recipesQuery.replace(/"/g, '&quot;')}" oninput="setRecipesQuery(this.value)" placeholder="Search recipes…"
             class="bg-slate-900 border border-slate-700 rounded-lg px-3 py-1.5 text-sm text-slate-200 w-64 max-w-full">
    </div>
    <h2 class="text-xl font-bold text-slate-100">📚 Recipes</h2>
    <div class="flex flex-wrap gap-2">
      ${crafting.map(code => `
        <button onclick="setRecipesProf('${code}')" class="px-4 py-2 rounded-lg text-sm font-semibold border ${code === recipesProf
          ? 'bg-amber-500/20 text-amber-200 border-amber-500/50'
          : 'bg-slate-900/60 text-slate-300 border-slate-800 hover:text-slate-100'}">${PROFS[code].name}</button>`).join('')}
    </div>
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
      <div class="text-sm text-slate-400">${rows.length} recipes · ${trainerCount ? `${trainerCount} from your trainer visits` : 'no trainer visit yet: visit a ' + PROFS[recipesProf].name + ' trainer to add all its recipes'}</div>
      ${rows.length ? `
      <table class="w-full text-sm">
        <thead><tr class="text-slate-400 text-left">
          <th class="font-medium pb-1">Recipe</th><th class="font-medium pb-1 text-right">Skill</th>
          <th class="font-medium pb-1 text-right">Trainer cost</th><th class="font-medium pb-1">Materials</th>
          <th class="font-medium pb-1 text-right">Materials cost</th><th class="font-medium pb-1 text-right">Sells for</th>
          <th class="font-medium pb-1">Known by</th>
        </tr></thead>
        <tbody>${rows.map(r => `
          <tr class="border-t border-slate-800/80 align-top">
            <td class="py-1.5 text-slate-200">${r.name}${r.soldBy ? `<div class="text-xs text-sky-300">vendor: ${r.soldBy}</div>` : r.atTrainer || !trainerCount ? '' : '<div class="text-xs text-slate-500">not seen at a trainer or vendor</div>'}</td>
            <td class="py-1.5 text-right">${r.skill ?? '—'}${r.level ? `<div class="text-xs text-slate-500">level ${r.level}</div>` : ''}</td>
            <td class="py-1.5 text-right text-slate-400">${r.trainerCost ? formatCopper(r.trainerCost) : '—'}</td>
            <td class="py-1.5 text-slate-300">${r.reagents.length ? r.reagents.map(([n, q]) => `${q}× ${n}`).join(', ') : '<span class="text-slate-500">unknown</span>'}
              ${r.reagents.length && !r.fromGame ? '<div class="text-xs text-slate-500">from the guide</div>' : ''}</td>
            <td class="py-1.5 text-right">${formatCopper(r.cost)}</td>
            <td class="py-1.5 text-right">${formatCopper(r.value)}</td>
            <td class="py-1.5 ${r.knownBy.length ? 'text-emerald-300' : 'text-slate-500'}">${r.knownBy.join(', ') || 'nobody'}</td>
          </tr>`).join('')}</tbody>
      </table>` : '<p class="text-sm text-slate-400">No recipes match.</p>'}
    </div>
    <p class="text-xs text-slate-500">Materials come from your game when a character knows the recipe, otherwise from the guide. Costs use the cheapest way to get each material from your auction scans.</p>
  `;
}

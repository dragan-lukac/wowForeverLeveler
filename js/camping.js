// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Camping view: what your characters can build at a camp ---
function showCampingView() {
  activeCharacter = null;
  showView('campingView');
  renderCampingView();
}

// For one profession: who can build now, who has it but needs more skill, who only has it planned.
function campMakers(code, skillNeeded, metas) {
  const now = [], later = [], planned = [];
  metas.forEach(({ c, meta }) => {
    const has = meta.profs.includes(code) || (meta.secondary || []).includes(code);
    if (!has) return;
    const rank = meta.profRanks[code];
    if (rank == null) planned.push(c.name);
    else if (rank >= skillNeeded) now.push(`${c.name} (${rank})`);
    else later.push(`${c.name} (${rank})`);
  });
  return { now, later, planned };
}

function makersText({ now, later, planned }) {
  return [
    now.length && `<span class="text-emerald-300">can make now: ${now.join(', ')}</span>`,
    later.length && `<span class="text-amber-300">needs more skill: ${later.join(', ')}</span>`,
    planned.length && `<span class="text-slate-400">planned: ${planned.join(', ')}</span>`
  ].filter(Boolean).join('<br>') || '<span class="text-slate-500">nobody</span>';
}

function renderCampingView() {
  const camping = GUIDE.camping;
  const realm = REALM_ROSTERS[currentRealmKey];
  const metas = realm.chars.map(c => ({ c, meta: metaFor(c) }));
  const card = (title, body) => `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
      <div class="text-xs font-semibold uppercase tracking-wider text-amber-400">${title}</div>${body}
    </div>`;

  document.getElementById('campingView').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="text-sm text-slate-400">${realm.title}</div>
    </div>
    <h2 class="text-xl font-bold text-slate-100">🏕 Camping</h2>

    ${card('How camps work', `<ul class="space-y-1">${camping.rules.map(r => `<li class="text-sm text-slate-200 leading-relaxed">• ${r}</li>`).join('')}</ul>`)}

    ${card('Campfire kits (Cooking)', `
      <table class="w-full text-sm">
        <thead><tr class="text-slate-400 text-left"><th class="font-medium pb-1">Kit</th><th class="font-medium pb-1 text-right">Cooking skill</th><th class="font-medium pb-1 text-right">Camp objects</th><th class="font-medium pb-1">Your characters</th></tr></thead>
        <tbody>${camping.campfires.map(k => `
          <tr class="border-t border-slate-800/80 align-top">
            <td class="py-1.5 text-slate-200">${k.name}</td>
            <td class="py-1.5 text-right">${k.skill}</td>
            <td class="py-1.5 text-right">${k.slots}</td>
            <td class="py-1.5 text-sm">${makersText(campMakers('cook', k.skill, metas))}</td>
          </tr>`).join('')}</tbody>
      </table>`)}

    ${card('Camp objects', `
      <table class="w-full text-sm">
        <thead><tr class="text-slate-400 text-left"><th class="font-medium pb-1">Object</th><th class="font-medium pb-1">Buff</th><th class="font-medium pb-1">Your characters</th></tr></thead>
        <tbody>${camping.objects.map(o => `
          <tr class="border-t border-slate-800/80 align-top">
            <td class="py-1.5 text-slate-200"><b>${o.name}</b><div class="text-xs text-slate-400">${PROFS[o.prof].name} ${o.skill} · ${o.mats || ''}</div>${(o.tiers || []).map(t => `<div class="text-xs text-slate-500">${t.skill}: ${t.name} (${t.mats}; blueprint: ${t.blueprint})</div>`).join('')}</td>
            <td class="py-1.5 text-slate-200">${o.buff}${o.noStack ? `<div class="text-xs text-slate-500">does not stack with ${o.noStack}</div>` : ''}</td>
            <td class="py-1.5 text-sm">${makersText(campMakers(o.prof, o.skill, metas))}</td>
          </tr>`).join('')}</tbody>
      </table>`)}
    <p class="text-xs text-slate-500">${camping.note}</p>
  `;
}

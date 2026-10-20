// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Pages under the Auction House and Professions tabs: money methods, mount gold, Merchant's Favor ---
const pageCard = (title, body, accent = 'border-slate-800') => `
  <div class="p-5 rounded-xl bg-slate-900/60 border ${accent} space-y-2">
    <div class="text-sm font-semibold uppercase tracking-wider text-amber-400">${title}</div>${body}
  </div>`;

// Every character on this realm, real and planned, with its plan data.
function realmMetas() {
  const realm = REALM_ROSTERS[currentRealmKey];
  return [...realm.chars, ...plannedChars(realm)].map(c => ({ c, meta: metaFor(c) }));
}

const fullName = meta => [meta.name, meta.lastName].filter(Boolean).join(' ');

function showMethodsView() {
  activeCharacter = null;
  showView('methodsView');
  const book = priceBook(REALM_ROSTERS[currentRealmKey]);
  const metas = realmMetas();
  document.getElementById('methodsView').innerHTML = (MONEY.methods || []).map(m => {
    const who = metas.filter(({ meta }) => m.needs.every(p => meta.profs.includes(p))).map(({ c }) => c.name);
    return `${methodCard(m, book)}
      <p class="text-sm text-slate-400 -mt-2 px-1">Who: ${who.join(', ') || 'nobody with ' + m.needs.map(p => PROFS[p].name).join(' + ')}</p>`;
  }).join('');
}

function showMountView() {
  activeCharacter = null;
  showView('mountView');
  const realm = REALM_ROSTERS[currentRealmKey];
  const goal = MONEY.mountGoal;
  const target = goal.gold * 10000;
  const rows = realm.chars.filter(c => !CHAR_DATA_BLUEPRINT[c.key]?.bank).map(c => {
    const pct = c.money != null ? Math.min(100, Math.round(c.money / target * 100)) : 0;
    return `
      <div class="py-2 border-t border-slate-800/80">
        <div class="flex justify-between text-base"><span class="text-slate-100">${c.name} · ${c.level}</span>
          <span class="text-slate-300">${c.money != null ? `${formatCopper(c.money)} · need ${formatCopper(Math.max(0, target - c.money))}` : 'no gold data'}</span></div>
        <div class="w-full bg-slate-800 h-2 rounded-full overflow-hidden mt-1"><div class="bg-amber-400 h-full" style="width:${pct}%"></div></div>
      </div>`;
  });
  const phase = p => `
    <details class="rounded-lg border border-slate-800 p-3">
      <summary class="cursor-pointer text-base font-semibold text-slate-200">${p.name} <span class="font-normal text-slate-400">(${p.when})</span></summary>
      <ul class="mt-2 space-y-1">${p.do.map(t => `<li class="text-sm text-slate-200">✓ ${t}</li>`).join('')}
        ${p.avoid.map(t => `<li class="text-sm text-rose-300">✗ ${t}</li>`).join('')}</ul>
    </details>`;
  document.getElementById('mountView').innerHTML = `
    ${pageCard(`Mount: level ${goal.level}, ${goal.gold} gold${goal.training ? ` (riding ${goal.training} + mount ${goal.mount})` : ''}`, rows.join('') || '<p class="text-sm text-slate-400">No characters with gold data yet.</p>')}
    ${pageCard('Money plan by level', MONEY.phases.map(phase).join(''))}`;
}

function showFavorView() {
  activeCharacter = null;
  showView('favorView');
  const f = GUIDE.merchantsFavor;
  const metas = realmMetas();
  const byId = Object.fromEntries(metas.map(({ c, meta }) => [meta.id, c.name]));
  const crafters = code => metas.filter(({ meta }) => meta.profs.includes(code)).map(({ c }) => c.name);
  const table = code => `
    <table class="w-full text-base"><tbody>${f.sets[code].map(s => `
      <tr class="border-t border-slate-800/80 ${s.for.length ? '' : 'opacity-50'}">
        <td class="py-1.5 pr-3 text-slate-100">${s.set}</td>
        <td class="py-1.5 pr-3 text-slate-400 text-sm">${s.stat}</td>
        <td class="py-1.5 text-slate-200">${s.for.map(id => byId[id]).filter(Boolean).join(', ') || '—'}</td>
      </tr>`).join('')}</tbody></table>`;
  document.getElementById('favorView').innerHTML = `
    ${pageCard("Get Merchant's Favor", `<ol class="list-decimal pl-5 space-y-1">${f.how.map(t => `<li class="text-base text-slate-200">${t}</li>`).join('')}</ol>
      <p class="text-xs text-slate-500">${f.note}</p>`)}
    ${Object.keys(f.sets).map(code => pageCard(`${PROFS[code].name} sets · crafted by ${crafters(code).join(', ') || 'nobody yet'}`, table(code))).join('')}`;
}

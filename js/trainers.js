// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Trainers view: the Classic list of city trainers, updated with where the addon really saw them ---
let trainersMineOnly = true;

function showTrainersView() {
  activeCharacter = null;
  showView('trainersView');
  renderTrainersView();
}

function toggleTrainersMine() {
  trainersMineOnly = !trainersMineOnly;
  renderTrainersView();
}

// Profession names of this realm's real characters (or of the plan while none exist yet).
// Cooking, First Aid and Fishing are for everyone.
function realmProfessionNames(realm) {
  const codes = new Set(['cook', 'aid', 'fish']);
  (realm.chars.length ? realm.chars : plannedChars(realm)).forEach(c => {
    const meta = metaFor(c);
    [...meta.profs, ...(meta.secondary || [])].forEach(p => codes.add(p));
  });
  return new Set([...codes].map(code => PROFS[code].name));
}

function seenDate(t) {
  return new Date(t * 1000).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

function placeText(npc) {
  const coords = npc.x != null ? `${npc.x.toFixed(1)}, ${npc.y.toFixed(1)}` : '';
  return [npc.subzone, coords].filter(Boolean).join(' · ');
}

// One row per trainer or vendor. `seen` is what the addon saved; without it the row shows the plan.
function trainerRow(profession, name, where, seen, highlight) {
  const status = seen
    ? `<span class="text-emerald-300">✓ ${placeText(seen) || seen.zone}</span>${seen.seen ? `<span class="text-slate-500"> · seen ${seenDate(seen.seen)}</span>` : ''}`
    : `<span class="text-amber-300">Not visited</span><span class="text-slate-500"> · Classic: ${where}</span>`;
  return `
    <tr class="border-t border-slate-800/80 align-top ${highlight ? '' : 'opacity-50'}">
      <td class="py-1.5 pr-3 text-slate-200 whitespace-nowrap">${profession}</td>
      <td class="py-1.5 pr-3 text-slate-100">${name}</td>
      <td class="py-1.5 text-sm">${status}</td>
    </tr>`;
}

// Recipe vendors from the vendor scans (vendors.js) and the NPC map (npcs.js), keyed by vendor name.
function recipeVendors(client, seen) {
  const out = {};
  Object.values((window.VENDORS || {})[client] || {}).forEach(entry => {
    (entry.vendors || []).forEach(v => {
      const name = v.vendor;
      const o = out[name] || (out[name] = { zone: v.zone, subzone: v.subzone, profs: new Set(), recipes: 0 });
      o.profs.add(entry.profession);
      o.recipes += 1;
    });
  });
  Object.entries(seen).filter(([, n]) => n.kind === 'vendor').forEach(([name, n]) => {
    const o = out[name] || (out[name] = { profs: new Set(), recipes: 0 });
    Object.assign(o, { zone: n.zone, subzone: n.subzone, seen: n });
    (n.profession || '').split(', ').filter(Boolean).forEach(p => o.profs.add(p));
  });
  // "Recipes" is only a fallback name for vendors whose profession was not known yet.
  Object.values(out).forEach(o => { if (o.profs.size > 1) o.profs.delete('Recipes'); });
  return out;
}

function renderTrainersView() {
  const realm = REALM_ROSTERS[currentRealmKey];
  const plan = GUIDE.npcs || { list: [] };
  const seen = (window.NPCS || {})[realm.client] || {};
  const mine = realmProfessionNames(realm);
  const show = profession => !trainersMineOnly || mine.has(profession);

  // Trainers the addon saw, by zone and profession, to match the Classic list.
  const seenTrainer = {};
  Object.entries(seen).filter(([, n]) => n.kind === 'trainer' && n.profession)
    .forEach(([name, n]) => { seenTrainer[`${n.zone}|${n.profession}`] = { name, ...n }; });

  const zones = {};
  const zoneRows = zone => zones[zone] || (zones[zone] = []);
  const matched = new Set();
  plan.list.forEach(t => {
    if (!show(t.profession)) return;
    const s = seen[t.name] || seenTrainer[`${t.city}|${t.profession}`];
    if (s) matched.add(s.name || t.name);
    const name = s && s.name && s.name !== t.name ? `${s.name} <span class="text-slate-500">(Classic: ${t.name})</span>` : t.name;
    zoneRows(t.city).push(trainerRow(t.profession, name, t.where, s, mine.has(t.profession)));
  });
  Object.entries(seen).filter(([name, n]) => n.kind === 'trainer' && !matched.has(name) && show(n.profession))
    .forEach(([name, n]) => zoneRows(n.zone).push(trainerRow(n.profession || 'Trainer', `${name} <span class="text-sky-300">new</span>`, '', n, true)));
  Object.entries(seen).filter(([, n]) => n.kind === 'class trainer')
    .forEach(([name, n]) => zoneRows(n.zone).push(trainerRow(`${n.profession} trainer`, name, '', n, true)));

  const vendors = Object.entries(recipeVendors(realm.client, seen))
    .filter(([, v]) => !trainersMineOnly || [...v.profs].some(p => mine.has(p)));

  const card = (title, body) => `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
      <div class="text-sm font-semibold uppercase tracking-wider text-amber-400">${title}</div>${body}
    </div>`;
  const table = rows => `<table class="w-full text-sm"><tbody>${rows.join('')}</tbody></table>`;
  const seenCount = Object.keys(seen).length;

  document.getElementById('trainersView').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="text-sm text-slate-400">${realm.title}</div>
    </div>
    <h2 class="text-xl font-bold text-slate-100">🧭 Trainers & Vendors</h2>
    <p class="text-sm text-slate-300 leading-relaxed">${plan.note}</p>
    <div class="flex flex-wrap items-center gap-3 text-sm">
      <button onclick="toggleTrainersMine()" class="px-3 py-1 rounded-lg border ${trainersMineOnly ? 'bg-amber-500/20 text-amber-300 border-amber-500/40' : 'bg-slate-900 text-slate-400 border-slate-700'}">
        ${trainersMineOnly ? '✓ Only my professions' : 'All professions'}</button>
      <span class="text-slate-400">${realm.client ? `${seenCount} trainers and vendors saved by the addon on this game client.` : 'Launch plan: no game data yet. The list fills when you play.'}</span>
    </div>
    ${Object.entries(zones).map(([zone, rows]) => card(zone, table(rows))).join('')}
    ${card('Recipe vendors', vendors.length ? table(vendors.map(([name, v]) => trainerRow(
      [...v.profs].join(', '), `${name}${v.recipes ? ` <span class="text-slate-500">(${v.recipes} recipes)</span>` : ''}`, '',
      v.seen || { zone: v.zone, subzone: [v.zone, v.subzone].filter(Boolean).join(', ') }, true))) :
      '<div class="text-sm text-slate-400">None yet. Open a vendor that sells recipes and the addon saves it.</div>')}
  `;
}

// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Professions & supply chain (mirrors supply_lines() in scripts/build_guide.py) ---
const PROFS = GUIDE.professions;
const CODE_BY_NAME = Object.fromEntries(Object.entries(PROFS).map(([code, p]) => [p.name, code]));
const charLabel = c => `${c.race} ${c.class}`;

function roleTitle(codes) {
  if (!codes.length) return 'Bank';
  const kinds = new Set(codes.map(p => PROFS[p].type));
  if (kinds.size === 2) return 'Gatherer & Crafter';
  return kinds.has('gather') ? 'Gatherer' : 'Crafter';
}

// `roster` is the plan with this character's real professions swapped in.
function partners(ch, match, roster) {
  const others = roster.filter(c => c.id !== ch.id && match(c));
  const sameGroup = others.filter(c => c.group === ch.group);
  return sameGroup.length ? sameGroup : others;
}

function recipients(gatherer, code, roster) {
  return partners(gatherer, c => PROFS[code].usedBy.some(u => c.profs.includes(u)), roster);
}

function craftRecipients(maker, craft, roster) {
  return partners(maker, c => (craft.to || []).some(p => c.profs.includes(p)) || (craft.toClasses || []).includes(c.class), roster);
}

function supplyLines(ch) {
  if (ch.bank) return [];
  const roster = GUIDE.characters.map(c => c.id === ch.id ? ch : c);
  const others = roster.filter(c => c.id !== ch.id);
  const lines = [];
  Object.entries(PROFS).forEach(([code, prof]) => {
    if (prof.type !== 'gather') return;
    if (ch.profs.includes(code)) {
      const to = recipients(ch, code, roster);
      if (to.length) lines.push(`Send ${prof.gives} to ${to.map(charLabel).join(', ')}.`);
    }
    const src = others.filter(c => c.profs.includes(code) && recipients(c, code, roster).some(r => r.id === ch.id));
    if (src.length) lines.push(`Get ${prof.gives} from ${src.map(charLabel).join(', ')}.`);
  });

  ch.profs.forEach(code => (PROFS[code].crafts || []).forEach(craft => {
    if (craft.to === 'all') return lines.push(`Make ${craft.item} for everyone.`);
    const to = craftRecipients(ch, craft, roster);
    if (to.length) lines.push(`Send ${craft.item} to ${to.map(charLabel).join(', ')}.`);
  }));
  const received = {};
  others.forEach(c => c.profs.forEach(code =>
    (PROFS[code].crafts || []).forEach(craft => {
      if (craft.to !== 'all' && craftRecipients(c, craft, roster).some(r => r.id === ch.id)) {
        (received[craft.item] = received[craft.item] || []).push(charLabel(c));
      }
    })));
  Object.entries(received).forEach(([item, makers]) => lines.push(`Get ${item} from ${makers.join(', ')}.`));
  return lines;
}

// Professions that make items: the crafting ones plus Cooking and First Aid.
const isCrafting = code => PROFS[code].type === 'craft' || code === 'cook' || code === 'aid';
const campObject = code => ((GUIDE.camping || {}).objects || []).find(o => o.prof === code);

const pairTips = codes => (GUIDE.synergies || []).filter(s => s.profs.every(p => codes.includes(p)));

// Route choices (guide.json routeChoices): where two ways cover the same levels, the chosen option's
// zones replace every zone of the other options. Chosen by hand (saved per character), else the option
// where the character last turned in a quest, else the plan stays as it is.
const ROUTE_CHOICE_KEY = 'wow_route_choice';
function loadRouteChoices() {
  try { return JSON.parse(localStorage.getItem(ROUTE_CHOICE_KEY) || '{}'); } catch (e) { return {}; }
}

function applyRouteChoices(meta, c) {
  const saved = loadRouteChoices();
  const quests = c.questZones || {};
  meta.choices = [];
  (GUIDE.routeChoices || []).forEach(choice => {
    const all = choice.options.flatMap(o => o.zones);
    const at = meta.zones.findIndex(z => all.includes(z));
    if (at < 0) return;
    const last = o => Math.max(0, ...o.zones.map(z => quests[z] || 0));
    const byQuests = choice.options.reduce((best, o, i) => (last(o) > (best < 0 ? 0 : last(choice.options[best])) ? i : best), -1);
    const chosen = saved[`${c.name}|${choice.id}`] ?? (byQuests >= 0 ? byQuests : null);
    if (chosen != null) {
      const rest = meta.zones.filter(z => !all.includes(z));
      rest.splice(at, 0, ...choice.options[chosen].zones);
      meta.zones = rest;
    }
    meta.choices.push({ ...choice, chosen, at: meta.zones[at] });
  });
}

function metaFor(c) {
  const meta = { ...CHAR_DATA_BLUEPRINT[c.key] };
  if (c.race) meta.race = c.race;
  // A real character of another race than planned starts in its own race's zone.
  const raceInfo = (GUIDE.races || {})[meta.race];
  if (raceInfo && meta.zones[0] !== raceInfo.start) meta.zones = [raceInfo.start, ...meta.zones.slice(1)];
  meta.planZones = meta.zones;
  applyRouteChoices(meta, c);
  const known = (c.professions || []).filter(p => CODE_BY_NAME[p.name]);
  const isSecondary = p => PROFS[CODE_BY_NAME[p.name]].type === 'secondary';
  const real = known.filter(p => !isSecondary(p));
  meta.secondary = known.filter(isSecondary).map(p => CODE_BY_NAME[p.name]);
  meta.profSource = real.length ? 'game' : 'plan';
  // Real professions win; while a slot is still empty the plan fills it (Mining learned, Skinning still planned).
  if (real.length) {
    const have = real.map(p => CODE_BY_NAME[p.name]);
    meta.profs = [...have, ...meta.profs.filter(p => !have.includes(p))].slice(0, Math.max(2, have.length));
  }
  const ranks = Object.fromEntries(known.map(p => [CODE_BY_NAME[p.name], p.rank]));
  meta.profRanks = ranks;
  meta.profMaxRanks = Object.fromEntries(known.map(p => [CODE_BY_NAME[p.name], p.maxRank]));
  meta.recipes = c.recipes || {};
  meta.profText = meta.bank ? 'bank, auction house, mail' : meta.profs.map(p => ranks[p] != null ? `${p} ${ranks[p]}` : p).join(' / ');
  meta.roleTitle = roleTitle(meta.profs);
  meta.supply = supplyLines(meta);
  return meta;
}

async function savePlanProfs() {
  const a = document.getElementById('planProf1').value;
  const b = document.getElementById('planProf2').value;
  const raceBox = document.getElementById('planRace');
  if (a === b) return alert('Pick two different professions.');
  try {
    const resp = await fetch('/api/plan', {
      method: 'POST',
      headers: { 'X-Requested-With': 'dashboard', 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: activeCharacter.key, profs: [a, b], race: raceBox ? raceBox.value : undefined })
    });
    const result = await resp.json().catch(() => ({ ok: false, log: `HTTP ${resp.status}` }));
    if (!result.ok) throw new Error(result.log);
    try { sessionStorage.setItem('wow_realm_after_sync', currentRealmKey); } catch (e) {}
    location.reload();
  } catch (err) {
    alert(`Could not save.\n\n${err.message}\n\nIs the dashboard started with Start Dashboard or make serve?`);
  }
}

function renderActiveProfessionsCategory() {
  if (!activeCharacter) return;
  const container = document.getElementById('professionsDetailContainer');
  const meta = activeCharacter.meta;
  const roster = GUIDE.characters.map(c => c.id === meta.id ? meta : c);
  const tailors = roster.filter(c => c.profs.includes('tail')).map(charLabel);
  const enchanters = roster.filter(c => c.profs.includes('ench')).map(charLabel);

  // Secondary professions: the learned ones, plus the plan's (every character levels all three).
  const secondary = [...new Set([...(meta.secondary || []), ...(meta.bank ? [] : ((GUIDE.secondaryPlan || {}).all || []))])];
  const tabs = [...(meta.bank ? [] : [{ key: 'plan', label: '🧭 Secondary & camp' }]), ...[...meta.profs, ...secondary].map(code => ({
    key: code,
    label: `${PROFS[code].name}${meta.profRanks[code] != null ? ` ${meta.profRanks[code]}` : ''}`
  })), { key: 'supply', label: 'Supply & pairs' }];
  if (!tabs.some(t => t.key === activeProfTab)) activeProfTab = tabs[0].key;

  const supplyPanel = `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
      <div class="text-xs font-semibold uppercase tracking-wider text-amber-400">Supply Role: ${meta.roleTitle}</div>
      ${(meta.supply.length ? meta.supply : ['No supply partners yet.']).map(l => `<p class="text-sm text-slate-200 leading-relaxed">${l}</p>`).join('')}
      <p class="text-xs text-slate-500 leading-relaxed">Everyone: send cloth to ${tailors.join(', ') || 'nobody yet'} and green items to ${enchanters.join(', ') || 'nobody yet'}.</p>
    </div>
    ${pairTips(meta.profs).map(s => `
      <div class="p-4 rounded-xl bg-emerald-950/20 border border-emerald-500/30">
        <div class="text-xs font-semibold uppercase tracking-wider text-emerald-400">Profession pair: ${s.profs.map(p => PROFS[p].name).join(' + ')}</div>
        <p class="text-sm text-slate-200 leading-relaxed mt-1">${s.tip}</p>
      </div>`).join('')}`;

  container.innerHTML = `
    <div class="flex flex-wrap gap-2">
      ${tabs.map(t => `
        <button onclick="setProfTab('${t.key}')" class="px-4 py-2 rounded-lg text-sm font-semibold border ${t.key === activeProfTab
          ? 'bg-amber-500/20 text-amber-200 border-amber-500/50'
          : 'bg-slate-900/60 text-slate-300 border-slate-800 hover:text-slate-100'}">${t.label}</button>`).join('')}
    </div>
    ${activeProfTab === 'supply' ? supplyPanel
      : activeProfTab === 'plan' ? secondaryPanel(meta)
      : renderProfession(activeProfTab, meta.profRanks[activeProfTab], meta.recipes[PROFS[activeProfTab].name])}
  `;
}

let activeProfTab = null;

// The skill step (milestone entry) a rank falls in, and the ones after it.
function rangeEntries(code) {
  return (PROFS[code].milestones || []).flatMap(m => (m.levelWith || []).map(e => ({ ...e, r: stepRange(e.range) })));
}

// Cooking ingredients you gather (not the spices, water and milk you buy) for a list of recipes.
const BOUGHT = ['Mild Spices', 'Hot Spices', 'Soothing Spices', 'Refreshing Spring Water', 'Ice Cold Milk', 'Shiny Red Apple'];
function gathered(code, recipes) {
  return [...new Set(recipes.flatMap(r => Object.keys((PROFS[code].recipes || {})[r] || {})).filter(n => !BOUGHT.includes(n)))];
}

// One card per secondary profession and one for camping: learn where, do what now, keep or vendor what,
// train next where. Ranks come from the game; a profession not learned yet counts as 0.
function secondaryPanel(meta) {
  const plan = GUIDE.secondaryPlan || {};
  const start = (plan.startTrainers || {})[meta.zones[0]] || {};
  const ranks = meta.profRanks || {};
  const max = meta.profMaxRanks || {};
  const line = (label, text) => text ? `<p class="text-base text-slate-200 leading-relaxed"><span class="text-amber-300 font-semibold">${label}:</span> ${text}</p>` : '';
  const nextTraining = code => {
    const t = (PROFS[code].training || []).find(x => !(max[code] >= x.cap));
    return t ? `${t.name} at skill ${t.skill}${t.level ? ` and level ${t.level}` : ''}: ${t.where}.` : null;
  };
  const card = (code, body) => {
    const rank = ranks[code];
    return `<div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-1.5">
      <div class="text-lg font-bold text-slate-100">${PROFS[code] ? PROFS[code].name : code} <span class="text-sm font-normal text-slate-400">${rank != null ? `${rank}/${max[code] || '?'}` : 'not learned'}</span></div>
      ${body}</div>`;
  };
  const learn = code => ranks[code] == null && start[code] ? line('Learn', `${start[code]} (about 1s).`) : '';

  // First Aid: the bandage to make, the cloth to keep.
  const aidRank = Math.max(ranks.aid || 0, 1); // skill steps start at 1
  const aidKeep = Object.entries(PROFS.aid.keepCloth || {}).filter(([, k]) => aidRank < k.until).slice(0, 2).map(([n, k]) => `${k.count} ${n}`);
  const aid = card('aid', learn('aid')
    + line('Now', (profStepText('aid', aidRank) || '').replace('. Buy ', '. You need ') || null)
    + line('Keep', aidKeep.length ? `${aidKeep.join(', ')} (the rest goes to the tailor).` : null)
    + line('Next', nextTraining('aid')));

  // Cooking: any recipe of the current step; keep the ingredients of this and the next step, vendor older ones.
  const cookRank = ranks.cook || 0;
  const steps = rangeEntries('cook');
  const now = steps.find(e => cookRank >= e.r[0] && cookRank < e.r[1]) || steps[0];
  const nextStep = steps[steps.indexOf(now) + 1];
  const keep = gathered('cook', [...now.recipes, ...(nextStep ? nextStep.recipes : [])]);
  const old = gathered('cook', steps.filter(e => e.r[1] <= cookRank).flatMap(e => e.recipes)).filter(n => !keep.includes(n));
  const recipeText = now.recipes.map(r => `${r} (${Object.entries(PROFS.cook.recipes[r] || {}).map(([n, q]) => `${q > 1 ? `${q} ` : ''}${n}`).join(' + ')})`).join(', ');
  const cook = card('cook', learn('cook')
    + line('Now', `cook about ${now.r[1] - Math.max(cookRank, now.r[0])} of any: ${recipeText}.`)
    + line('Keep', `${keep.join(', ')}.`)
    + line('Vendor', old.length ? `${old.join(', ')} (no skill-ups any more).` : null)
    + line('Next', nextTraining('cook')));

  // Fishing: where to fish at this skill; the fish go to Cooking.
  const fishRank = Math.max(ranks.fish || 0, 1);
  const fishStep = (PROFS.fish.milestones || []).find(m => { const r = stepRange(m.rank); return r && fishRank >= r[0] && fishRank < r[1]; });
  const fish = card('fish', learn('fish')
    + (ranks.fish == null && start.gear ? line('Buy', `${start.gear}.`) : '')
    + line('Now', fishStep ? fishStep.desc : null)
    + line('Keep', 'every raw fish your Cooking step above lists; sell or vendor the rest.')
    + line('Next', nextTraining('fish')));

  // Camping: the picked object, its skill, what to carry.
  const pick = ((GUIDE.camping || {}).picks || {})[meta.id];
  const obj = pick && GUIDE.camping.objects.find(o => o.prof === pick);
  const camp = obj ? `<div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-1.5">
      <div class="text-lg font-bold text-slate-100">🏕 Camp: ${obj.name} <span class="text-sm font-normal text-slate-400">${obj.buff}</span></div>
      ${line('Needs', `${PROFS[pick].name} ${obj.skill}${ranks[pick] != null ? ` (now ${ranks[pick]})` : ' (not learned)'} and Cooking 20 for the kits${ranks.cook != null ? ` (now ${ranks.cook})` : ''}.`)}
      ${line('Carry', `5 Basic Campfire Kits (Cooking 20: 1 Simple Wood each), ${obj.mats.replace(/\d+/g, n => n * 5)}. That is 5 hours of buff.`)}
      ${line('Every hour', `put down the campfire, then the ${obj.name}, then sit for 1 minute.`)}
      ${obj.noStack ? line('Note', `it does not stack with ${obj.noStack}.`) : ''}
    </div>` : '';
  return `<div class="space-y-3">${camp}${aid}${cook}${fish}
    <p class="text-xs text-slate-500">${plan.supplies || ''} ${plan.note || ''}</p></div>`;
}

function setProfTab(key) {
  activeProfTab = key;
  renderActiveProfessionsCategory();
}

function stepRange(rankText) {
  const m = rankText.match(/(\d+)\s*-\s*(\d+)/);
  return m ? [Number(m[1]), Number(m[2])] : null;
}

// Crafts per skill point by recipe colour. Yellow and green are rough averages.
const CRAFTS_PER_POINT = { optimal: 1, medium: 1.5, easy: 3 };
const COLOR_NAME = { optimal: 'orange', medium: 'yellow', easy: 'green', trivial: 'grey' };

// Breaks craftable reagents (bolts, cured hides) down into what you gather or buy.
function rawMaterials(code, needs, out = {}) {
  Object.entries(needs).forEach(([name, qty]) => {
    const sub = (PROFS[code].recipes || {})[name];
    if (sub && qty > 0) rawMaterials(code, Object.fromEntries(Object.entries(sub).map(([n, c]) => [n, c * qty])), out);
    else if (qty > 0) out[name] = (out[name] || 0) + qty;
  });
  return out;
}

function renderCurrentStep(entry, skill, scan, code) {
  const profName = PROFS[code].name;
  const to = stepRange(entry.range)[1];
  const known = scan && scan.recipes ? entry.recipes.find(r => scan.recipes[r]) : null;
  const recipeName = known || entry.recipes[0];
  const gameRecipe = known ? scan.recipes[known] : null;
  const guideRecipe = (PROFS[code].recipes || {})[recipeName] || {};
  const box = inner => `<div class="mt-1.5 ml-3 p-3 rounded-lg bg-amber-500/10 border border-amber-500/40 text-sm text-slate-200 space-y-1.5">${inner}</div>`;

  if (gameRecipe && gameRecipe.difficulty === 'trivial') {
    return box(`<b>${recipeName}</b> is grey: it gives no more skill. Move to the next recipe.`);
  }

  const difficulty = gameRecipe ? gameRecipe.difficulty : 'optimal';
  const perPoint = CRAFTS_PER_POINT[difficulty] || 1;
  const crafts = Math.ceil((to - skill) * perPoint);
  const reagents = gameRecipe
    ? gameRecipe.reagents.map(r => ({ name: r.name, count: r.count, have: r.have }))
    : Object.entries(guideRecipe).map(([name, count]) => ({ name, count, have: null }));
  if (!reagents.length) return box(`Make about <b>${crafts}× ${recipeName}</b> to go from ${skill} to ${to}.`);

  const showBags = reagents.some(r => r.have != null);
  const missingNeeds = {};
  const rows = reagents.map(r => {
    const need = r.count * crafts;
    const missing = showBags ? Math.max(0, need - r.have) : need;
    missingNeeds[r.name] = missing;
    return `<tr>
      <td class="pr-4">${r.name}</td>
      <td class="pr-4 text-right font-semibold">${need}</td>
      ${showBags ? `<td class="pr-4 text-right">${r.have}</td>
      <td class="text-right ${missing ? 'text-rose-300 font-semibold' : 'text-emerald-300'}">${missing || '✓'}</td>` : ''}
    </tr>`;
  }).join('');

  const raw = rawMaterials(code, missingNeeds);
  const rawChanged = Object.keys(raw).sort().join() !== Object.keys(missingNeeds).filter(n => missingNeeds[n] > 0).sort().join();
  const colour = COLOR_NAME[difficulty] || difficulty;
  const source = gameRecipe
    ? `From your game (bags as of ${new Date(scan.scanned * 1000).toLocaleString()}).`
    : `Amounts from the guide, assuming the recipe is orange.${scan && !known ? ` You have not learned ${recipeName} yet.` : ''}`;

  return box(`
    <div>Make about <b>${crafts}× ${recipeName}</b> to go from ${skill} to ${to}.${gameRecipe ? ` <span class="text-slate-400">Recipe is ${colour} now${perPoint > 1 ? ', so not every craft gives a point' : ''}.</span>` : ''}</div>
    <table>
      <thead><tr class="text-slate-400"><th class="pr-4 text-left font-medium">Material</th><th class="pr-4 text-right font-medium">Need</th>${showBags ? '<th class="pr-4 text-right font-medium">In bags</th><th class="text-right font-medium">Missing</th>' : ''}</tr></thead>
      <tbody>${rows}</tbody>
    </table>
    ${rawChanged && Object.keys(raw).length ? `<div><span class="font-semibold text-amber-300">${showBags ? 'Still to collect' : 'Total to collect'}:</span> ${Object.entries(raw).map(([n, q]) => `${Math.ceil(q - 1e-9)} ${n}`).join(', ')}</div>` : ''}
    <div class="text-slate-500 text-xs">${source}</div>`);
}

function renderLevelWith(entries, skill, scan, code) {
  if (!entries || !entries.length) return '';
  return `
    <div class="mt-2">
      <div class="text-xs font-semibold text-amber-400">Level with</div>
      <ul class="mt-1 space-y-0.5">${entries.map(e => {
        const [from, to] = stepRange(e.range);
        const current = skill != null && skill >= from && skill < to;
        const text = `${e.range}: ${e.recipes.join(' or ')}.${e.note ? ' ' + e.note : ''}`;
        return `<li class="text-sm leading-relaxed ${current ? 'text-amber-200 font-semibold' : skill != null && skill >= to ? 'text-slate-500 line-through' : 'text-slate-300'}">
          ${current ? '▶' : '•'} ${text}
        </li>`;
      }).join('')}</ul>
    </div>`;
}

// Ranks the character's learned recipes that still give skill by gold per skill point,
// using the latest auction prices. Uses only real game data, so it follows WoW Forever's own recipes.
function bestRecipes(scan, book) {
  const latest = name => { const h = book[name]; return h && h.length ? h[h.length - 1].min : null; };
  const cut = GUIDE.money.signals.ahCut;
  return Object.entries(scan.recipes || {})
    .filter(([, r]) => CRAFTS_PER_POINT[r.difficulty])
    .map(([name, r]) => {
      const perPoint = CRAFTS_PER_POINT[r.difficulty];
      const unpriced = r.reagents.filter(g => latest(g.name) == null).map(g => g.name);
      const costPerCraft = unpriced.length ? null : r.reagents.reduce((sum, g) => sum + latest(g.name) * g.count, 0);
      const resale = latest(name);
      const netPerCraft = costPerCraft == null ? null : costPerCraft - (resale != null ? resale * (1 - cut) : 0);
      const canMake = r.reagents.length ? Math.min(...r.reagents.map(g => Math.floor((g.have || 0) / g.count))) : 0;
      return { name, difficulty: r.difficulty, perPoint, costPerPoint: netPerCraft == null ? null : netPerCraft * perPoint, resale, unpriced, canMake };
    })
    .sort((a, b) => (a.costPerPoint == null) - (b.costPerPoint == null)
      || (a.costPerPoint ?? 0) - (b.costPerPoint ?? 0)
      || a.perPoint - b.perPoint);
}

function renderBestRecipes(scan) {
  if (!scan || !scan.recipes) return '';
  const picks = bestRecipes(scan, priceBook(REALM_ROSTERS[currentRealmKey])).slice(0, 3);
  if (!picks.length) {
    return `<div class="p-3 rounded-lg bg-rose-950/20 border border-rose-500/30 text-sm text-slate-200">None of your learned recipes gives skill any more. Learn new recipes from your trainer.</div>`;
  }
  const colorClass = { optimal: 'text-orange-300', medium: 'text-yellow-300', easy: 'text-emerald-300' };
  return `
    <div class="p-4 rounded-lg bg-amber-500/10 border border-amber-500/40 space-y-2">
      <div class="text-sm font-semibold text-amber-300">Best recipes to level with now (from your game and auction prices)</div>
      <table class="w-full text-sm">
        <thead><tr class="text-slate-400 text-left">
          <th class="font-medium pb-1">Recipe</th><th class="font-medium pb-1">Color</th>
          <th class="font-medium pb-1 text-right">Cost per skill point</th><th class="font-medium pb-1 text-right">You can make now</th>
        </tr></thead>
        <tbody>${picks.map((p, i) => `
          <tr class="border-t border-slate-800/80">
            <td class="py-1.5 ${i === 0 ? 'font-semibold text-amber-200' : 'text-slate-200'}">${i === 0 ? '★ ' : ''}${p.name}</td>
            <td class="py-1.5 ${colorClass[p.difficulty]}">${COLOR_NAME[p.difficulty]}</td>
            <td class="py-1.5 text-right">${p.costPerPoint == null ? `<span class="text-slate-500">no price: ${p.unpriced.join(', ')}</span>` : p.costPerPoint <= 0 ? '<span class="text-emerald-300">free (resale pays for it)</span>' : formatCopper(p.costPerPoint)}</td>
            <td class="py-1.5 text-right">${p.canMake}</td>
          </tr>`).join('')}</tbody>
      </table>
      <div class="text-xs text-slate-500">Cost per point = material prices × crafts per point (orange 1, yellow ~1.5, green ~3), minus the resale value of the item after the ${Math.round(GUIDE.money.signals.ahCut * 100)}% cut when it sells. Beta prices are not real market prices.</div>
    </div>`;
}

// Trainer recipes (from the addon's trainer scan) split into "learn now" and "coming next".
function renderTrainerHints(profName, skill, scan) {
  const trainer = trainerBook(profName);
  const vendors = vendorBook(profName);
  if (!trainer && !Object.keys(vendors).length) {
    return `<div class="text-xs text-slate-500">Visit a ${profName} trainer once to see what you can learn next.</div>`;
  }
  const known = (scan && scan.recipes) || {};
  const fromTrainer = Object.entries(trainer || {}).map(([name, t]) => ({ name, ...t }));
  const fromVendor = Object.entries(vendors)
    .filter(([name, v]) => !(trainer || {})[name] && v.skill != null)
    .map(([name, v]) => ({ name, skill: v.skill, cost: v.vendors[0] && v.vendors[0].price, vendor: vendorText(v) }));
  const all = [...fromTrainer, ...fromVendor].filter(r => !known[r.name]);
  // Rank upgrades (Journeyman, Expert, ...) raise the skill cap, so they always come first.
  const isRank = r => /^(Apprentice|Journeyman|Expert|Artisan|Master) /.test(r.name);
  const now = all.filter(r => r.skill <= skill).sort((a, b) => isRank(b) - isRank(a) || b.skill - a.skill);
  const NOW_LIMIT = 8;
  const next = all.filter(r => r.skill > skill).sort((a, b) => a.skill - b.skill).slice(0, 5);
  const item = r => `<li class="text-sm text-slate-200">• ${r.name} <span class="text-slate-400">(skill ${r.skill}${r.level ? `, level ${r.level}` : ''}${r.cost ? `, ${formatCopper(r.cost)}` : ''})</span>${r.vendor ? `<div class="text-xs text-sky-300 ml-3">vendor: ${r.vendor}</div>` : ''}</li>`;
  const nowCost = now.reduce((sum, r) => sum + (r.cost || 0), 0);
  return `
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3 pt-1">
      <div>
        <div class="text-sm font-semibold text-emerald-300">Learn now at the trainer${now.length ? ` · ${formatCopper(nowCost)} total` : ''}</div>
        ${now.length ? `<ul class="mt-1 space-y-0.5">${now.slice(0, NOW_LIMIT).map(r => isRank(r)
          ? `<li class="text-sm font-bold text-amber-200">★ ${r.name} <span class="font-normal text-slate-400">(needed to go past your skill cap${r.level ? `, level ${r.level}` : ''}${r.cost ? `, ${formatCopper(r.cost)}` : ''})</span></li>`
          : item(r)).join('')}</ul>
          ${now.length > NOW_LIMIT ? `<div class="text-xs text-slate-500 mt-1">+${now.length - NOW_LIMIT} more: see the 📚 Recipes page.</div>` : ''}`
          : '<div class="text-sm text-slate-400 mt-1">Nothing new to learn.</div>'}
      </div>
      <div>
        <div class="text-sm font-semibold text-sky-300">Coming next</div>
        ${next.length ? `<ul class="mt-1 space-y-0.5">${next.map(item).join('')}</ul>` : '<div class="text-sm text-slate-400 mt-1">No more recipes at this trainer.</div>'}
      </div>
    </div>`;
}

function renderProfession(code, skill, scan) {
  const prof = PROFS[code];
  const checkedTag = prof.checked
    ? `<span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-emerald-950/40 text-emerald-400 border border-emerald-500/20">✓ ${prof.checked.client} ${prof.checked.date}</span>`
    : `<span class="text-[0.7rem] px-1.5 py-0.5 rounded bg-amber-950/40 text-amber-400 border border-amber-500/20" title="Skill numbers are approximate until checked in game">Not checked</span>`;
  const list = (label, items, color) => items && items.length ? `
    <div class="mt-2">
      <div class="text-xs font-semibold ${color}">${label}</div>
      <ul class="mt-1 space-y-0.5">${items.map(t => `<li class="text-sm text-slate-200 leading-relaxed">• ${t}</li>`).join('')}</ul>
    </div>` : '';

  const currentTier = prof.milestones.find(m => {
    const r = stepRange(m.rank);
    return skill != null && r && skill >= r[0] && skill < r[1];
  });
  const currentLine = currentTier && (currentTier.levelWith || []).find(e => {
    const [from, to] = stepRange(e.range);
    return skill >= from && skill < to;
  });
  const nowCard = skill == null ? '' : `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-amber-500/50 space-y-2">
      <div class="text-xs font-semibold uppercase tracking-wider text-amber-400">Now: ${prof.name} ${skill}${currentTier ? ` · ${currentTier.rank}` : ''}</div>
      ${currentLine
        ? `<div class="text-base font-semibold text-amber-100">▶ ${currentLine.range}: ${currentLine.recipes.join(' or ')}.${currentLine.note ? ` <span class="font-normal text-slate-300">${currentLine.note}</span>` : ''}</div>
           ${renderCurrentStep(currentLine, skill, scan, code)}`
        : `<div class="text-sm text-slate-300">${skill >= 300 ? 'Maxed out. Well done.' : 'No guide step for this skill yet. Use the best recipes below.'}</div>`}
      ${renderTrainerHints(prof.name, skill, scan)}
    </div>`;

  return `
    <div class="space-y-4">
      <div class="flex flex-wrap items-center gap-2">
        <div class="text-xs font-semibold uppercase tracking-wider text-slate-400">${prof.name}</div>
        ${prof.milestones.some(m => m.levelWith) ? checkedTag : ''}
      </div>
      ${campObject(code) ? `<div class="text-sm text-slate-300">🏕 Camp object: <b class="text-amber-200">${campObject(code).name}</b> at skill ${campObject(code).skill} · ${campObject(code).buff}${campObject(code).noStack ? ` <span class="text-slate-500">(does not stack with ${campObject(code).noStack})</span>` : ''}</div>` : ''}
      ${nowCard}
      ${renderBestRecipes(scan)}
      ${prof.tips ? `
        <details class="rounded-xl bg-slate-900/60 border border-slate-800">
          <summary class="cursor-pointer p-4 text-sm font-semibold text-slate-300">Tips for ${prof.name}</summary>
          <ul class="px-4 pb-4 space-y-0.5">${prof.tips.map(t => `<li class="text-sm text-slate-300 leading-relaxed">• ${t}</li>`).join('')}</ul>
        </details>` : ''}
      ${prof.newRecipes ? `
        <details class="rounded-xl bg-slate-900/60 border border-slate-800">
          <summary class="cursor-pointer p-4 text-sm font-semibold text-slate-300">New in Forever (${prof.newRecipes.length} recipes)</summary>
          <ul class="px-4 pb-4 space-y-0.5">${prof.newRecipes.map(r => `<li class="text-sm text-slate-300 leading-relaxed">• <b>${r.name}</b>: ${r.mats} → ${r.effect}</li>`).join('')}</ul>
        </details>` : ''}
      ${prof.milestones.map((m, i) => {
        const here = m === currentTier;
        return `
          <details class="rounded-xl bg-slate-900/60 border ${here ? 'border-amber-500/60' : 'border-slate-800'}" ${here || (skill == null && i === 0) ? 'open' : ''}>
            <summary class="cursor-pointer p-4 flex flex-wrap items-center gap-2">
              <span class="text-sm font-bold text-slate-200">Tier ${i + 1}: ${m.rank}</span>
              ${here ? '<span class="text-[0.7rem] px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40 font-semibold">You are here</span>' : ''}
              ${skill != null && stepRange(m.rank) && skill >= stepRange(m.rank)[1] ? '<span class="text-[0.7rem] px-2 py-0.5 rounded bg-emerald-950/40 text-emerald-400 border border-emerald-500/20">done</span>' : ''}
            </summary>
            <div class="px-4 pb-4">
              <div class="text-sm text-slate-400 leading-relaxed">${m.desc}</div>
              ${renderLevelWith(m.levelWith, skill, scan, code)}
              ${list('Worth learning', m.learn, 'text-emerald-400')}
              ${list('Skip', m.skip, 'text-rose-400')}
              ${m.greens ? `<div class="mt-2 text-sm text-slate-400"><span class="font-semibold text-emerald-300">Green items</span> (disenchant, or mail to your enchanter): ${m.greens.join(', ')}</div>` : ''}
              ${m.mats ? `<div class="mt-2 text-sm text-slate-400"><span class="font-semibold text-slate-300">Materials:</span> ${m.mats}</div>` : ''}
            </div>
          </details>`;
      }).join('')}
    </div>`;
}

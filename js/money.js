// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Money & Market tab ---
const MONEY = GUIDE.money;

function formatCopper(copper) {
  if (copper == null) return '—';
  const c = Math.round(copper);
  const g = Math.floor(c / 10000), s = Math.floor((c % 10000) / 100), cu = c % 100;
  // Zero parts after the first are left out: 2s, 1g 5c, 0c.
  return [g && `${g}g`, s && `${s}s`, (cu || (!g && !s)) && `${cu}c`].filter(Boolean).join(' ');
}

// Prices and trainer lists are keyed by game client, so beta and live data never mix.
// A realm without a client (the launch blueprints) has no prices.
function priceBook(realm) {
  const all = window.PRICES || {};
  if (!realm || !realm.client || !realm.realmName) return {};
  const prefix = `${realm.client}|${realm.realmName}-`;
  const scope = Object.keys(all).find(k => k.startsWith(prefix));
  return scope ? all[scope] : {};
}

// Vendor recipes for this profession on the current realm's client: recipe -> { skill, vendors: [...] }.
function vendorBook(profName) {
  const realm = REALM_ROSTERS[currentRealmKey];
  const byClient = (window.VENDORS || {})[realm && realm.client] || {};
  return Object.fromEntries(Object.entries(byClient).filter(([, v]) => v.profession === profName));
}

const vendorText = v => v.vendors.map(x =>
  `${x.vendor} (${[x.subzone, x.zone].filter(Boolean).join(', ')})${x.price ? ' · ' + formatCopper(x.price) : ''}${x.limited != null ? ' · limited stock' : ''}`).join('; ');

function trainerBook(profName) {
  const realm = REALM_ROSTERS[currentRealmKey];
  const byClient = (window.TRAINERS || {})[realm && realm.client] || {};
  return byClient[profName] || null;
}

function medianOf(values) {
  const v = [...values].sort((a, b) => a - b);
  if (!v.length) return null;
  const mid = Math.floor(v.length / 2);
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

// Signal: newest lowest price vs. the median of earlier snapshots in the window.
function marketSignal(history) {
  const s = MONEY.signals;
  if (!history || !history.length) return null;
  const latest = history[history.length - 1];
  const since = latest.t - s.windowDays * 86400;
  const earlier = history.slice(0, -1).filter(h => h.t >= since).map(h => h.min);
  const median = medianOf(earlier);
  if (earlier.length + 1 < s.minSnapshots || !median) return { now: latest.min, median, signal: 'wait', scans: earlier.length + 1 };
  const ratio = latest.min / median;
  const signal = ratio >= s.sellAbove ? 'sell' : ratio <= s.buyBelow ? 'buy' : 'normal';
  return { now: latest.min, median, signal, ratio, scans: earlier.length + 1 };
}

const SIGNAL_STYLE = {
  sell: ['Sell', 'bg-emerald-950/40 text-emerald-300 border-emerald-500/30'],
  buy: ['Buy / hold', 'bg-sky-950/40 text-sky-300 border-sky-500/30'],
  normal: ['Normal', 'bg-slate-800 text-slate-300 border-slate-700'],
  wait: ['Need more scans', 'bg-slate-900 text-slate-500 border-slate-800']
};

// Chance of each result. With your own results (calc.observed: result id -> times seen), each result
// counts once extra, so a result you have not seen yet keeps a small chance. Without, calc.yields chances.
function yieldOdds(calc) {
  const obs = calc.observed;
  if (!obs) return Object.fromEntries(calc.yields.map(y => [y.id || y.item, y.chance]));
  const total = calc.yields.reduce((t, y) => t + (obs[y.id] || 0) + 1, 0);
  return Object.fromEntries(calc.yields.map(y => [y.id, ((obs[y.id] || 0) + 1) / total]));
}

// Live numbers for a money method (guide.json money.methods[].calc) from the newest lowest prices.
// Returns cost of one craft, expected sale value after disenchanting (after the auction cut), profit,
// materials without a price, materials above their price limit, and whether essence beats the wand.
function methodNumbers(calc, book) {
  // Vendor goods (calc.vendorPrices) use the vendor price; everything else the newest lowest auction price.
  const price = name => {
    if (calc.vendorPrices && calc.vendorPrices[name] != null) return calc.vendorPrices[name];
    const h = book[name];
    return h && h.length ? h[h.length - 1].min : null;
  };
  const missing = [];
  const sum = (entries, f) => entries.reduce((total, e) => {
    const p = price(e.item);
    if (p == null) { missing.push(e.item); return total; }
    return total + f(e, p);
  }, 0);
  const materials = Object.entries(calc.materials).map(([item, count]) => ({ item, count }));
  const cost = sum(materials, (e, p) => e.count * p);
  const odds = yieldOdds(calc);
  const value = sum(calc.yields, (e, p) => odds[e.id || e.item] * e.count * p) * (1 - MONEY.signals.ahCut);
  const tooHigh = Object.entries(calc.maxPrice || {})
    .filter(([item, max]) => price(item) != null && price(item) > max)
    .map(([item, max]) => ({ item, price: price(item), max }));
  if (calc.maxCost && cost > calc.maxCost && !missing.length) tooHigh.push({ item: `One ${calc.craft}`, price: cost, max: calc.maxCost });
  let wand = null;
  if (calc.wand) {
    const essence = price('Lesser Magic Essence');
    const extra = Object.entries(calc.wand.materials).filter(([item]) => item !== 'Lesser Magic Essence')
      .reduce((t, [item, n]) => t + n * (price(item) || 0), 0);
    if (essence != null) {
      const essenceSale = essence * (1 - MONEY.signals.ahCut);
      const wandGain = calc.wand.vendor - extra;
      wand = { essenceSale, wandGain, better: essenceSale >= wandGain ? 'essence' : 'wand' };
    }
  }
  const uniqueMissing = [...new Set(missing)];
  const samples = calc.observed ? Object.values(calc.observed).reduce((a, b) => a + b, 0) : 0;
  return { cost, value, profit: value - cost, missing: uniqueMissing, tooHigh, wand, complete: !uniqueMissing.length, samples };
}

function methodCard(m, book) {
  const n = methodNumbers(m.calc, book);
  const profitColor = n.profit > 0 ? 'text-emerald-300' : 'text-rose-300';
  const numbers = n.complete ? `
      <table class="w-full text-base">
        <tr><td class="py-1 text-slate-300">Materials for 1 ${m.calc.craft}</td><td class="py-1 text-right text-slate-100">${formatCopper(n.cost)}</td></tr>
        <tr><td class="py-1 text-slate-300">Expected sale after disenchanting (after the 5% auction cut)${n.samples ? `, from your ${n.samples} disenchants` : ''}</td><td class="py-1 text-right text-slate-100">${formatCopper(n.value)}</td></tr>
        <tr class="border-t border-slate-700"><td class="py-1 font-semibold text-slate-200">Profit per ${m.calc.craft}</td><td class="py-1 text-right font-bold ${profitColor}">${n.profit < 0 ? '−' : ''}${formatCopper(Math.abs(n.profit))}</td></tr>
      </table>`
    : `<p class="text-sm text-slate-400">No prices yet for: ${n.missing.join(', ')}. Scan the auction house to see the numbers.</p>`;
  const warnings = n.tooHigh.map(t => `<li class="text-sm text-amber-300">⚠ ${t.item} costs ${formatCopper(t.price)} now: the limit is ${formatCopper(t.max)}. Wait, or use your own materials.</li>`);
  const wand = n.wand ? `<li class="text-sm text-slate-200">Lesser Magic Essence: ${n.wand.better === 'essence'
      ? `<b>sell it</b> on the auction house (${formatCopper(n.wand.essenceSale)}) instead of a wand for the vendor (${formatCopper(n.wand.wandGain)}).`
      : `<b>make a wand</b> for the vendor (${formatCopper(n.wand.wandGain)}): it pays more than selling the essence (${formatCopper(n.wand.essenceSale)}).`}</li>` : '';
  return `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-amber-500/40 space-y-3">
      <div class="text-sm font-semibold uppercase tracking-wider text-amber-400">💡 ${m.name}</div>
      ${numbers}
      <ul class="space-y-1">${warnings.join('')}${wand}</ul>
      <details>
        <summary class="cursor-pointer text-sm font-semibold text-slate-300">Steps</summary>
        <ol class="mt-2 space-y-1 list-decimal pl-5">${m.steps.map(t => `<li class="text-sm text-slate-200 leading-relaxed">${t}</li>`).join('')}</ol>
      </details>
      <p class="text-xs text-slate-500">${m.calc.note} ${m.source}</p>
    </div>`;
}

function currentPhase(level) {
  const lvl = parseInt(level, 10);
  if (!lvl || lvl < 25) return 0;
  return lvl < MONEY.mountGoal.level ? 1 : 2;
}

function relevantItems(meta) {
  const items = new Set(MONEY.watch.cloth);
  meta.profs.forEach(code => {
    (MONEY.watch[code] || []).forEach(i => items.add(i));
    Object.entries(PROFS[code].recipes || {}).forEach(([recipe, reagents]) => {
      items.add(recipe);
      Object.keys(reagents).forEach(r => items.add(r));
    });
  });
  return [...items];
}

function renderMoneyCategory(c) {
  const meta = activeCharacter.meta;
  const container = document.getElementById('categoryMoney');
  const realm = REALM_ROSTERS[currentRealmKey];
  const book = priceBook(realm);
  const goal = MONEY.mountGoal;
  const goldCopper = goal.gold * 10000;
  const money = c.money;
  const pct = money != null ? Math.min(100, Math.round(money / goldCopper * 100)) : 0;
  const phaseIdx = currentPhase(c.level);

  const phaseCard = (phase, i) => `
    <details class="rounded-xl bg-slate-900/60 border ${i === phaseIdx ? 'border-amber-500/50' : 'border-slate-800'}" ${i === phaseIdx ? 'open' : ''}>
      <summary class="cursor-pointer p-4 text-sm font-semibold ${i === phaseIdx ? 'text-amber-300' : 'text-slate-300'}">
        ${phase.name} <span class="font-normal text-slate-400">(${phase.when})</span>${i === phaseIdx ? ' · <span class="text-amber-400">you are here</span>' : ''}
      </summary>
      <div class="px-4 pb-4 space-y-2">
        <p class="text-sm text-slate-200">${phase.goal}</p>
        <div class="text-sm font-semibold text-emerald-400">Do</div>
        <ul class="space-y-0.5">${phase.do.map(t => `<li class="text-sm text-slate-200 leading-relaxed">• ${t}</li>`).join('')}</ul>
        <div class="text-sm font-semibold text-rose-400">Avoid</div>
        <ul class="space-y-0.5">${phase.avoid.map(t => `<li class="text-sm text-slate-200 leading-relaxed">• ${t}</li>`).join('')}</ul>
      </div>
    </details>`;

  const items = relevantItems(meta);
  const priced = items.map(name => ({ name, sig: marketSignal(book[name]) })).filter(r => r.sig);
  const order = { sell: 0, buy: 1, normal: 2, wait: 3 };
  priced.sort((a, b) => order[a.sig.signal] - order[b.sig.signal] || a.name.localeCompare(b.name));
  const realmGolds = realm.chars.map(ch => ch.money).filter(m => m != null);
  const realmGold = realmGolds.length ? realmGolds.reduce((a, b) => a + b, 0) : null;
  const ideas = craftOpportunities([c], book);

  container.innerHTML = `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-2">
      <div class="text-xs font-semibold uppercase tracking-wider text-amber-400">Mount goal: level ${goal.level}, ${goal.gold} gold</div>
      <div class="text-sm text-slate-200">${money != null ? `You have <b>${formatCopper(money)}</b> on ${activeCharacter.name}. ${pct >= 100 ? 'Goal reached: buy the mount at level ' + goal.level + '.' : `Still needed: <b>${formatCopper(goldCopper - money)}</b>.`}` : 'No gold data for this character yet.'}</div>
      <div class="w-full bg-slate-800 h-2.5 rounded-full overflow-hidden"><div class="bg-amber-400 h-full rounded-full" style="width:${pct}%"></div></div>
      <div class="text-xs text-slate-500">${goal.note}</div>
    </div>

    ${(MONEY.methods || []).filter(m => m.needs.every(p => meta.profs.includes(p))).map(m => methodCard(m, book)).join('')}

    ${MONEY.phases.map(phaseCard).join('')}

    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
      <div class="text-xs font-semibold uppercase tracking-wider text-slate-400">Market: items for ${meta.profText}</div>
      ${priced.length ? `
        <table class="w-full text-sm">
          <thead><tr class="text-slate-400 text-left"><th class="font-medium pb-1">Item</th><th class="font-medium pb-1 text-right">Price now</th><th class="font-medium pb-1 text-right">7-day median</th><th class="font-medium pb-1 text-right">Signal</th></tr></thead>
          <tbody>${priced.map(({ name, sig }) => `
            <tr class="border-t border-slate-800/80">
              <td class="py-1.5 text-slate-200">${name}</td>
              <td class="py-1.5 text-right text-slate-200">${formatCopper(sig.now)}</td>
              <td class="py-1.5 text-right text-slate-400">${formatCopper(sig.median)}</td>
              <td class="py-1.5 text-right"><span class="text-xs px-2 py-0.5 rounded border ${SIGNAL_STYLE[sig.signal][1]}">${SIGNAL_STYLE[sig.signal][0]}</span></td>
            </tr>`).join('')}</tbody>
        </table>` : `<p class="text-sm text-slate-300">No prices yet for these items.</p>`}
      <p class="text-xs text-slate-500">${priced.length} of ${items.length} items have prices. ${MONEY.signals.note} Prices come from Auctionator: run its full scan at the auction house, then /reload and Sync.</p>
    </div>

    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
      <div class="text-xs font-semibold uppercase tracking-wider text-slate-400">Crafts that make a profit for ${activeCharacter.name}</div>
      ${ideas.length ? CRAFT_GROUPS.map(g => {
        const rows = ideas.filter(o => craftGroup(o.cost, realmGold) === g.key);
        return rows.length ? `
          <details class="rounded-lg border ${g.border}" ${g.open ? 'open' : ''}>
            <summary class="cursor-pointer p-3 text-sm font-semibold ${g.color}">${g.title} <span class="font-normal text-slate-400">· ${rows.length}</span></summary>
            <div class="px-3 pb-3">${craftTable(rows)}</div>
          </details>` : '';
      }).join('') : '<p class="text-sm text-slate-400">No profitable crafts with the current prices.</p>'}
      <p class="text-xs text-slate-500">Same numbers as the 🏦 Auction House page, for this character only. Groups compare one craft's materials with your gold on this realm (${formatCopper(realmGold)}).</p>
    </div>
  `;
}

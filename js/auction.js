// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Auction House view (whole account) ---
const latestPrice = (book, name) => { const h = book[name]; return h && h.length ? h[h.length - 1].min : null; };

// Guesses how fast an item sells from drops in the listed amount between scans.
// New listings hide some sales, so this underestimates; it needs several scans spread over time.
function salesSpeed(history) {
  const s = MONEY.signals;
  if (!history || history.length < 3) return { label: 'unknown', perDay: null };
  const since = history[history.length - 1].t - s.windowDays * 86400;
  const recent = history.filter(h => h.t >= since);
  const days = (recent[recent.length - 1].t - recent[0].t) / 86400;
  if (recent.length < 3 || days < 0.25) return { label: 'unknown', perDay: null };
  let dropped = 0;
  for (let i = 1; i < recent.length; i++) dropped += Math.max(0, (recent[i - 1].qty || 0) - (recent[i].qty || 0));
  const perDay = dropped / days;
  const avgListed = recent.reduce((sum, h) => sum + (h.qty || 0), 0) / recent.length || 1;
  const ratio = perDay / avgListed;
  return { label: ratio >= 0.3 ? 'fast' : ratio >= 0.08 ? 'medium' : 'slow', perDay };
}

const SPEED_STYLE = {
  fast: ['sells fast', 'text-emerald-300'], medium: ['sells ok', 'text-slate-300'],
  slow: ['⚠ sells slowly', 'text-rose-300'], unknown: ['speed unknown (needs more scans)', 'text-slate-500']
};

// Cheapest price of one unit of material: buy it ready-made, or buy its raw materials and make it.
function unitCost(book, code, name) {
  const direct = latestPrice(book, name);
  const sub = (PROFS[code].recipes || {})[name];
  let made = null;
  if (sub) {
    made = 0;
    for (const [n, q] of Object.entries(sub)) {
      const p = unitCost(book, code, n);
      if (p == null) { made = null; break; }
      made += p * q;
    }
  }
  if (direct == null) return made;
  return made == null ? direct : Math.min(direct, made);
}

function guideSkillFor(code, recipe) {
  const trained = (trainerBook(PROFS[code].name) || {})[recipe];
  if (trained) return trained.skill;
  for (const m of PROFS[code].milestones) {
    for (const e of m.levelWith || []) {
      if (e.recipes.includes(recipe)) return stepRange(e.range)[0];
    }
  }
  return null;
}

function craftOpportunities(chars, book) {
  const cut = MONEY.signals.ahCut;
  const best = {};
  chars.forEach(c => {
    const meta = metaFor(c);
    [...meta.profs, ...(meta.secondary || [])].forEach(code => {
      if (!isCrafting(code)) return;
      const scan = meta.recipes[PROFS[code].name];
      const known = (scan && scan.recipes) || {};
      const names = new Set([...Object.keys(known), ...Object.keys(PROFS[code].recipes || {})]);
      names.forEach(name => {
        const value = latestPrice(book, name);
        if (value == null) return;
        const game = known[name];
        const reagents = game
          ? game.reagents.map(r => [r.name, r.count])
          : Object.entries((PROFS[code].recipes || {})[name] || {});
        if (!reagents.length) return;
        let cost = 0, missingPrice = null;
        for (const [n, q] of reagents) {
          const p = unitCost(book, code, n);
          if (p == null) { missingPrice = n; break; }
          cost += p * q;
        }
        if (missingPrice) return;
        const profit = value * (1 - cut) - cost;
        if (profit <= 0) return;
        const skill = meta.profRanks[code];
        const needSkill = game ? null : guideSkillFor(code, name);
        const entry = {
          name, profName: PROFS[code].name, crafter: c.name, known: !!game,
          needSkill: needSkill != null && (skill == null || skill < needSkill) ? needSkill : null,
          value, cost, profit, margin: profit / cost, speed: salesSpeed(book[name])
        };
        const prev = best[name];
        if (!prev || (entry.known && !prev.known) || (entry.known === prev.known && entry.profit > prev.profit)) best[name] = entry;
      });
    });
  });
  const speedRank = { fast: 0, medium: 1, unknown: 2, slow: 3 };
  // Known recipes first (no trainer cost or wait), then faster sellers, then bigger profit.
  return Object.values(best).sort((a, b) => (b.known - a.known)
    || speedRank[a.speed.label] - speedRank[b.speed.label] || b.profit - a.profit);
}

const CRAFT_GROUPS = [
  { key: 'safe', title: '1. Safe: you can afford it easily', hint: 'materials cost up to half your gold', color: 'text-emerald-300', border: 'border-emerald-500/40', open: true },
  { key: 'risky', title: '2. Riskier: expensive for you', hint: 'materials cost more than half your gold', color: 'text-amber-300', border: 'border-amber-500/30', open: false },
  { key: 'cannot', title: '3. Cannot afford yet', hint: 'materials cost more than your gold', color: 'text-rose-300', border: 'border-rose-500/30', open: false }
];

function craftGroup(cost, gold) {
  if (gold == null || cost <= gold * 0.5) return 'safe';
  return cost <= gold ? 'risky' : 'cannot';
}

function craftTable(rows) {
  return `
    <table class="w-full text-sm">
      <thead><tr class="text-slate-400 text-left">
        <th class="font-medium pb-1">Item</th><th class="font-medium pb-1">Who crafts</th>
        <th class="font-medium pb-1 text-right">Materials</th><th class="font-medium pb-1 text-right">Sells for</th>
        <th class="font-medium pb-1 text-right">Profit each</th><th class="font-medium pb-1 text-right">Speed</th>
      </tr></thead>
      <tbody>${rows.map(o => `
        <tr class="border-t border-slate-800/80 align-top">
          <td class="py-1.5 text-slate-200">${o.name}
            ${o.known ? '' : `<div class="text-xs text-amber-300">learn first${o.needSkill ? ` (needs ${o.profName} ${o.needSkill})` : ''}</div>`}</td>
          <td class="py-1.5 text-slate-300">${o.crafter} <span class="text-slate-500">(${o.profName})</span></td>
          <td class="py-1.5 text-right text-slate-400">${formatCopper(o.cost)}</td>
          <td class="py-1.5 text-right">${formatCopper(o.value)}</td>
          <td class="py-1.5 text-right font-semibold text-emerald-300">+${formatCopper(o.profit)} <span class="text-xs text-slate-500">(${Math.round(o.margin * 100)}%)</span></td>
          <td class="py-1.5 text-right ${SPEED_STYLE[o.speed.label][1]}">${SPEED_STYLE[o.speed.label][0]}</td>
        </tr>`).join('')}</tbody>
    </table>`;
}

function showAuctionView() {
  activeCharacter = null;
  showView('auctionView');
  renderAuctionView();
}

function renderAuctionView() {
  const realm = REALM_ROSTERS[currentRealmKey];
  const book = priceBook(realm);
  const chars = realm.chars;
  const golds = chars.map(c => c.money).filter(m => m != null);
  const gold = golds.length ? golds.reduce((a, b) => a + b, 0) : null;
  const scanTimes = Object.values(book).flat().map(h => h.t);
  const lastScan = scanTimes.length ? new Date(Math.max(...scanTimes) * 1000).toLocaleString() : null;

  const crafts = craftOpportunities(chars, book);
  const signals = Object.keys(book).map(name => ({ name, sig: marketSignal(book[name]), speed: salesSpeed(book[name]) }))
    .filter(r => r.sig && (r.sig.signal === 'buy' || r.sig.signal === 'sell'));
  const buys = signals.filter(r => r.sig.signal === 'buy').sort((a, b) => a.sig.ratio - b.sig.ratio);
  const sells = signals.filter(r => r.sig.signal === 'sell').sort((a, b) => b.sig.ratio - a.sig.ratio);

  const card = (title, body) => `
    <div class="p-5 rounded-xl bg-slate-900/60 border border-slate-800 space-y-3">
      <div class="text-xs font-semibold uppercase tracking-wider text-amber-400">${title}</div>${body}
    </div>`;
  const signalTable = (rows, emptyText) => rows.length ? `
    <table class="w-full text-sm">
      <thead><tr class="text-slate-400 text-left"><th class="font-medium pb-1">Item</th><th class="font-medium pb-1 text-right">Now</th><th class="font-medium pb-1 text-right">Usual</th><th class="font-medium pb-1 text-right">Difference</th><th class="font-medium pb-1 text-right">Speed</th></tr></thead>
      <tbody>${rows.map(r => `
        <tr class="border-t border-slate-800/80">
          <td class="py-1.5 text-slate-200">${r.name}</td>
          <td class="py-1.5 text-right">${formatCopper(r.sig.now)}</td>
          <td class="py-1.5 text-right text-slate-400">${formatCopper(r.sig.median)}</td>
          <td class="py-1.5 text-right ${r.sig.ratio >= 1 ? 'text-emerald-300' : 'text-sky-300'}">${r.sig.ratio >= 1 ? '+' : ''}${Math.round((r.sig.ratio - 1) * 100)}%</td>
          <td class="py-1.5 text-right ${SPEED_STYLE[r.speed.label][1]}">${SPEED_STYLE[r.speed.label][0]}</td>
        </tr>`).join('')}</tbody>
    </table>` : `<p class="text-sm text-slate-400">${emptyText}</p>`;

  document.getElementById('auctionView').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="text-sm text-slate-400">${realm.title} · ${Object.keys(book).length} items priced · last scan: ${lastScan || 'none yet'} · your gold: <b class="text-slate-200">${formatCopper(gold)}</b></div>
    </div>
    <h2 class="text-xl font-bold text-slate-100">🏦 Auction House</h2>

    ${gold == null ? `<p class="text-sm text-amber-300">Your gold is not known yet, so every craft is listed as safe. Log in and out once, then Sync.</p>` : ''}
    ${CRAFT_GROUPS.map(g => {
      const rows = crafts.filter(o => craftGroup(o.cost, gold) === g.key).slice(0, 15);
      return `
        <details class="rounded-xl bg-slate-900/60 border ${g.border}" ${g.open ? 'open' : ''}>
          <summary class="cursor-pointer p-5 flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span class="text-sm font-semibold ${g.color}">${g.title}</span>
            <span class="text-sm text-slate-400">${g.hint} · ${rows.length} idea${rows.length === 1 ? '' : 's'}</span>
          </summary>
          <div class="px-5 pb-5 space-y-2">${rows.length ? craftTable(rows) : '<p class="text-sm text-slate-400">Nothing in this group with the current prices.</p>'}</div>
        </details>`;
    }).join('')}
    <p class="text-xs text-slate-500">Profit = sale price after the ${Math.round(MONEY.signals.ahCut * 100)}% auction house cut, minus today's material prices, for one craft. Groups compare the material cost of one craft with your gold on this realm (${formatCopper(gold)}). Items that sell fast are listed first. Speed is a guess from how much the listed amount drops between your scans.</p>

    ${card('Buy now: cheaper than usual', signalTable(buys, 'Nothing is clearly cheap right now. Signals need at least 3 scans of an item.'))}
    ${card('Sell now: more expensive than usual', signalTable(sells, 'Nothing is clearly expensive right now. Signals need at least 3 scans of an item.'))}
    <p class="text-xs text-slate-500">"Usual" is your own median price of the last ${MONEY.signals.windowDays} days. Beta prices are for testing only.</p>
  `;
}

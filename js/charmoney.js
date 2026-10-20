// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Money per character: what to sell, vendor or keep, from your own auction and vendor prices ---

// Cloth drops by mob level: the cloth a zone's humanoids drop.
const CLOTH_BY_LEVEL = [
  { name: 'Linen Cloth', from: 1, to: 17 }, { name: 'Wool Cloth', from: 13, to: 28 },
  { name: 'Silk Cloth', from: 24, to: 42 }, { name: 'Mageweave Cloth', from: 38, to: 52 },
  { name: 'Runecloth', from: 48, to: 60 }
];
// Words in a zone's gathering tip that name ore and leather.
const ORE_WORDS = { copper: 'Copper Ore', tin: 'Tin Ore', silver: 'Silver Ore', iron: 'Iron Ore', gold: 'Gold Ore',
                    mithril: 'Mithril Ore', truesilver: 'Truesilver Ore', thorium: 'Thorium Ore' };
const LEATHER_WORDS = { light: ['Ruined Leather Scraps', 'Light Leather'], medium: ['Medium Leather'], heavy: ['Heavy Leather'],
                        thick: ['Thick Leather'], rugged: ['Rugged Leather'] };

function vendorPrice(realm, name) {
  const byClient = (window.SELL_PRICES || {})[realm && realm.client] || {};
  return byClient[name] != null ? byClient[name] : null;
}

// Items a character gets in a zone: gathered by its professions, plus the zone's cloth.
function zoneItems(zoneName, meta) {
  const zone = GUIDE.zones[zoneName];
  const tips = zone.gather || {};
  const items = [];
  const add = (name, code) => { if (!items.some(i => i.name === name)) items.push({ name, code }); };
  meta.profs.forEach(code => {
    const tip = (tips[code] || '').toLowerCase();
    if (!tip) return;
    if (code === 'herb') (MONEY.watch.herb || []).filter(h => tip.includes(h.toLowerCase())).forEach(h => add(h, code));
    if (code === 'mine') Object.entries(ORE_WORDS).filter(([w]) => new RegExp(`\\b${w}\\b`).test(tip)).forEach(([, o]) => add(o, code));
    if (code === 'skin') Object.entries(LEATHER_WORDS).filter(([w]) => tip.includes(w)).forEach(([, ls]) => ls.forEach(l => add(l, code)));
  });
  const [lo, hi] = String(zone.levels).split('-').map(Number);
  CLOTH_BY_LEVEL.filter(c2 => lo <= c2.to && hi >= c2.from).forEach(c2 => add(c2.name, 'cloth'));
  return items;
}

// Who uses an item this character gets: crafters of the gathering profession, tailors for cloth.
// Only crafters that exist on this realm and have really learned the crafting profession count;
// until then the item is money.
function keepFor(meta, code, realm) {
  const roster = GUIDE.characters.map(c => (c.id === meta.id ? meta : c));
  const crafts = code === 'cloth' ? ['tail'] : PROFS[code] ? PROFS[code].usedBy : [];
  const users = partners(meta, c => crafts.some(p => c.profs.includes(p)), roster);
  const real = ((realm && realm.chars) || []);
  return users.map(u => real.find(ch => ch.key === u.id && crafts.some(p =>
      (ch.professions || []).some(x => x.name === PROFS[p].name))))
    .filter(Boolean).map(ch => ch.name);
}

// The character's own crafting profession that uses this item, or null.
const ITEM_USERS = { cloth: ['tail'], skin: ['leath'], herb: ['alch'], mine: ['bsmith', 'eng'] };
function ownUse(meta, code) {
  const own = (ITEM_USERS[code] || []).find(p => meta.profs.includes(p));
  return own ? PROFS[own].name : null;
}

// Cloth the character's own First Aid needs (guide.json professions.aid.keepCloth): 'now' while the skill is
// in that cloth's range, 'later' before it, null after. Without First Aid data the skill counts as 0.
function firstAidNeed(meta, name) {
  const need = ((PROFS.aid || {}).keepCloth || {})[name];
  const rank = (meta.profRanks || {}).aid || 0;
  if (!need || rank >= need.until) return null;
  return { count: need.count, when: Math.max(rank, 1) >= (need.from || 0) ? 'now' : 'later', from: need.from };
}

// Vendor price and stack size: the addon's vendor scan of this realm's client first (SHOP_PRICES),
// else the guide's Classic values. Loot items use the guide's Classic stack sizes per kind.
function shopItem(realm, name) {
  const seen = ((window.SHOP_PRICES || {})[realm && realm.client] || {})[name];
  const guide = (GUIDE.shopping.items || {})[name] || {};
  if (seen) return { price: seen.price / Math.max(seen.per || 1, 1), stack: seen.stack || guide.stack || 20, game: true };
  return guide.price != null ? { price: guide.price, stack: guide.stack || 20, game: false } : null;
}

function lootStack(item) {
  return (GUIDE.shopping.lootStacks || {})[item.code] || 20;
}

// Mail costs 30c per item: a stack is worth mailing when it is worth 3x that to the receiver.
// Worth = AH price per unit (else 3x the vendor price) x a full stack. Null when nothing is known.
function stackWorth(item, realm, book) {
  const ah = latestPrice(book, item.name);
  const vendor = vendorPrice(realm, item.name);
  const unit = ah != null ? ah : vendor != null ? vendor * 3 : null;
  return unit == null ? null : unit * lootStack(item);
}

// One decision per item, from evidence: keep (own craft or First Aid now), bank (First Aid later),
// mail (a crafter needs it and a stack pays the stamp), sell at the auction house, vendor it,
// or hold it while the price is below its usual level.
function itemDecision(item, meta, realm, book) {
  const aid = item.code === 'cloth' && !ownUse(meta, item.code) ? firstAidNeed(meta, item.name) : null;
  if (aid && aid.when === 'now') return { action: 'keep', aid: aid.count, text: `Keep ${aid.count} for First Aid` };
  if (aid) return { action: 'bank', text: `Bank ${aid.count} for First Aid ${aid.from}+` };
  const own = ownUse(meta, item.code);
  if (own) return { action: 'keep', text: `Keep for your ${own}` };
  const users = keepFor(meta, item.code, realm);
  const ah = latestPrice(book, item.name);
  const vendor = vendorPrice(realm, item.name);
  const sig = marketSignal(book[item.name]);
  if (users.length && !users.includes(meta.name)) {
    const worth = stackWorth(item, realm, book);
    const stamp = GUIDE.shopping.postage * GUIDE.shopping.mailWorth;
    if (worth == null) return { action: 'mail', text: `Mail full stacks to ${users.join(' or ')}` };
    if (worth >= stamp) return { action: 'mail', text: `Mail to ${users.join(' or ')}` };
  }
  if (ah == null) return vendor != null ? { action: 'vendor', text: `Vendor (${formatCopper(vendor)})` } : { action: 'unknown', text: 'No price yet: scan the auction house' };
  // Vendor or AH is judged on the usual price of the last days, so one stray cheap listing
  // (Light Leather once showed 9c against 1s 40c) does not turn an AH item into vendor trash.
  const usual = sig && sig.median ? Math.max(ah, sig.median) : ah;
  const net = usual * (1 - MONEY.signals.ahCut);
  if (vendor != null && net < vendor * 1.5) return { action: 'vendor', text: `Vendor (${formatCopper(vendor)}); AH pays only ${formatCopper(net)}` };
  if (sig && sig.signal === 'buy') return { action: 'hold', text: `Keep for now: ${formatCopper(ah)} is below the usual ${formatCopper(sig.median)}` };
  const qty = (book[item.name] || []).slice(-1)[0].qty;
  return { action: 'ah', text: `Sell on AH at ${formatCopper(Math.max(1, ah - 1))} each (${qty} on sale)` };
}

const DECISION_STYLE = { keep: 'text-sky-300', mail: 'text-sky-300', bank: 'text-violet-300', ah: 'text-emerald-300', vendor: 'text-slate-300', hold: 'text-amber-300', unknown: 'text-slate-500' };

// Short text for the route: one money line per zone, grouped by action.
// "Sell: Bruiseweed 3s 89c · Mail to Vestac: Wool Cloth · First Aid: keep 150 Linen Cloth · Bank: Wool Cloth (First Aid 80+)".
function zoneMoneyLine(zoneName, meta, realm, book) {
  const items = zoneItems(zoneName, meta);
  if (!items.length) return null;
  const groups = {};
  const add = (label, text) => (groups[label] = groups[label] || []).push(text);
  items.forEach(item => {
    const d = itemDecision(item, meta, realm, book);
    const price = latestPrice(book, item.name);
    if (d.aid) return add('First Aid: keep', `${d.aid} ${item.name}`);
    if (d.action === 'bank') return add('Bank', `${item.name} (${d.text.replace(/^Bank \d+ for /, '')})`);
    if (d.action === 'keep' || d.action === 'mail') return add(d.text, item.name);
    add({ ah: 'Sell', vendor: 'Vendor', hold: 'Hold', unknown: 'Sell' }[d.action], price != null && d.action === 'ah' ? `${item.name} ${formatCopper(price)}` : item.name);
  });
  return Object.entries(groups).map(([label, names]) => `${label}: ${names.join(', ')}`).join(' · ');
}

// --- Shopping, banks, fishing and what to carry (guide.json shopping, zones.<zone>.fishing) ---

const usesMana = meta => !(GUIDE.shopping.noMana || []).includes(meta.class);

// The water a mana user buys at this level.
function waterFor(level) {
  return [...(GUIDE.shopping.water || [])].reverse().find(w => level >= w.from);
}

// "5 Simple Wood, 2 Shiny Bauble · about 2s 15c · 2 bag slots" from [[name, qty], ...].
function shopText(list, realm) {
  let cost = 0, slots = 0, guess = false;
  const names = list.map(([name, qty]) => {
    const it = shopItem(realm, name);
    if (it) { cost += it.price * qty; slots += Math.ceil(qty / it.stack); guess = guess || !it.game; } else slots += 1;
    return `${qty} ${name}`;
  });
  return `${names.join(', ')} · about ${formatCopper(cost)}${guess ? ' (Classic prices)' : ''} · ${slots} bag slot${slots === 1 ? '' : 's'}`;
}

// What to buy in a zone's town before questing there. The first zone buys only the fishing pole and a
// bauble (money goes to skills first; the start steps buy the gathering tools). From the second zone:
// wood for 3 campfires, bait for the zone's fishing range, and 5 water for mana users.
function zoneShopping(zoneName, idx, meta) {
  const list = [];
  const ranks = meta.profRanks || {};
  const level = zoneEntryLevel(zoneName);
  const fish = GUIDE.zones[zoneName].fishing;
  if (idx === 0) {
    if (ranks.fish == null) list.push(['Fishing Pole', 1]);
    if (fish && !(ranks.fish >= fish.to)) list.push(['Shiny Bauble', 2]);
    return list;
  }
  const pick = ((GUIDE.camping || {}).picks || {})[meta.id];
  if (pick) list.push(['Simple Wood', 3]); // 3 Basic Campfire Kits; camp object materials are not carried
  if (fish && !(ranks.fish >= fish.to)) {
    const bait = fish.to <= 75 ? 'Shiny Bauble' : fish.to <= 205 ? 'Nightcrawlers' : 'Bright Baubles';
    list.push([bait, fish.to <= 75 ? 2 : 5]);
  }
  if (usesMana(meta)) { const w = waterFor(level); if (w) list.push([w.item, 5]); }
  return list;
}

function zoneShopLine(zoneName, idx, meta, realm) {
  const list = zoneShopping(zoneName, idx, meta);
  if (!list.length) return null;
  const town = (GUIDE.zones[zoneName].hubs || [])[0] || 'town';
  return `Buy in ${town}: ${shopText(list, realm)}.`;
}

// "Fish here up to 150 (any water; Nightcrawlers if fish get away)" while the skill is below the zone's top.
function zoneFishLine(zoneName, meta) {
  const fish = GUIDE.zones[zoneName].fishing;
  const rank = (meta.profRanks || {}).fish;
  if (!fish || rank >= fish.to) return null;
  return `Fishing ${fish.from}-${fish.to} here: ${fish.where}.${rank != null && rank < fish.from ? ` You are ${rank}: fish in an easier zone first.` : ''}`;
}

// Bank stop in the zone's town (guide.json shopping.banks): drop what waits for later, take out what is needed now.
function zoneBankLine(zoneName, meta, realm, book) {
  const town = (GUIDE.shopping.banks || {})[zoneName];
  if (!town) return null;
  const drop = zoneItems(zoneName, meta).filter(i => itemDecision(i, meta, realm, book).action === 'bank').map(i => i.name);
  const rank = (meta.profRanks || {}).aid || 0;
  const take = Object.entries((PROFS.aid || {}).keepCloth || {})
    .filter(([, k]) => rank >= (k.from || 0) && rank < k.until && k.from > 1).map(([n]) => n);
  const parts = [drop.length && `drop ${drop.join(', ')}`, take.length && `take out ${take.join(', ')} (First Aid ${rank} now)`].filter(Boolean);
  return `${town} bank: ${parts.length ? parts.join('; ') : 'drop what you do not need until later (it is free; mail costs 30c per item)'}.`;
}

// The short kit every character carries (user, 2026-10-16: keep bags free): tools, a few campfires for cooking,
// food, water, bandages, one stack of healing potions, bait. Camp object materials (vials, fish) stay in the bank.
function carryList(meta, realm) {
  // RestedXP deletes the Hearthstone at level 1 for bag space; an innkeeper gives a new one free when you bind.
  const list = [['Hearthstone (free again from the first innkeeper)', 1, 1]];
  if (meta.profs.includes('mine')) list.push(['Mining Pick', 1, 1]);
  if (meta.profs.includes('skin')) list.push(['Skinning Knife', 1, 1]);
  list.push(['Fishing Pole', 1, 1], ['Basic Campfire Kit', 3, 1], ['Food (Well Fed, your own cooking)', 10, 1]);
  if (usesMana(meta)) list.push(['Water (your level)', 10, 1]);
  list.push(['Bandages (your best)', 10, 1], ['Healing Potions (your best), 1 stack', 1, 1], ['Fishing bait', 5, 1]);
  return list;
}

// Money methods and crafts as buy/make/sell steps with numbers. Only ones with a real, positive profit.
function methodPlan(m, book, count = 10) {
  const n = methodNumbers(m.calc, book);
  if (!n.complete || n.profit <= 0) return null;
  const mats = Object.entries(m.calc.materials).map(([name, q]) => `${q * count} ${name}`).join(', ');
  const tested = n.samples ? `tested: ${n.samples} disenchants` : 'not tested yet';
  return `Buy ${mats}. Make ${count} ${m.calc.craft} and disenchant them. Profit about ${formatCopper(n.profit * count)} (${tested}).`;
}

function craftPlan(o, book) {
  const count = 3;
  return `Make ${count} ${o.name} (materials ${formatCopper(o.cost * count)}), sell at ${formatCopper(Math.max(1, o.value - 1))} each: profit about ${formatCopper(o.profit * count)}.`;
}

function renderCharMoney() {
  if (!activeCharacter) return;
  const container = document.getElementById('categoryMoney');
  const { name, level, meta } = activeCharacter;
  const realm = REALM_ROSTERS[currentRealmKey];
  const book = priceBook(realm);
  const c = realm.chars.find(ch => ch.name === name) || { key: activeCharacter.key, name };
  if (meta.bank) {
    container.innerHTML = pageCard('Bank', '<p class="text-base text-slate-200">Post what the others mail you. Use 🏦 Auction House › Buy & Sell for prices.</p>');
    return;
  }
  const progress = zoneProgress(name, level, meta.zones, loadZoneTicks(), c.questZones);
  const zoneName = meta.zones[Math.max(0, progress.indexOf('current'))] || meta.zones[0];
  const items = zoneItems(zoneName, meta);
  const rows = items.map(item => {
    const d = itemDecision(item, meta, realm, book);
    return `<tr class="border-t border-slate-800/80"><td class="py-1.5 pr-3 text-slate-100">${item.name}</td><td class="py-1.5 ${DECISION_STYLE[d.action]}">${d.text}</td></tr>`;
  });
  const methods = (MONEY.methods || []).filter(m => m.needs.every(p => meta.profs.includes(p)))
    .map(m => ({ m, plan: methodPlan(m, book) }));
  const crafts = craftOpportunities([c], book).filter(o => o.known).slice(0, 3);
  const goal = MONEY.mountGoal;
  const money = c.money;

  container.innerHTML = `
    ${pageCard(`Items in ${zoneName}`, rows.length ? `<table class="w-full text-base"><tbody>${rows.join('')}</tbody></table>` : '<p class="text-base text-slate-400">Nothing to sell from your professions here.</p>')}
    ${methods.length ? pageCard('Money methods', methods.map(({ m, plan }) => `
      <div class="py-1.5 border-t border-slate-800/80"><div class="text-base font-semibold text-slate-100">${m.name}</div>
      <div class="text-base ${plan ? 'text-emerald-300' : 'text-slate-400'}">${plan || 'No profit with today\'s prices: wait.'}</div></div>`).join('')) : ''}
    ${crafts.length ? pageCard('Crafts with profit now', crafts.map(o => `<div class="py-1.5 border-t border-slate-800/80 text-base text-slate-200">${craftPlan(o, book)}</div>`).join('')) : ''}
    ${pageCard(`Mount: ${goal.gold} gold at level ${goal.level}`, `<p class="text-base text-slate-200">${money != null ? `${formatCopper(money)} now · need ${formatCopper(Math.max(0, goal.gold * 10000 - money))}` : 'No gold data yet.'}</p>`)}`;
}

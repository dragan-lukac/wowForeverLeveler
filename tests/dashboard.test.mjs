// Tests for the dashboard's money and supply logic. Run with: make test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ROOT = new URL('..', import.meta.url);
const read = path => readFileSync(new URL(path, ROOT), 'utf-8');

// Load the dashboard scripts into a sandbox the way the browser does: plain scripts sharing globals.
function loadDashboard() {
  const sandbox = { console };
  sandbox.window = sandbox;
  // The built guide (data/guide.json + the team from personal/ or personal.example/, `make guide`).
  sandbox.GUIDE = JSON.parse(read('data/guide.js').split('window.GUIDE = ')[1].trim().replace(/;$/, ''));
  // A small in-memory localStorage, like the browser's.
  const store = {};
  sandbox.localStorage = { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); } };
  vm.createContext(sandbox);
  for (const name of ['app', 'professions', 'characters', 'money', 'auction', 'recipes', 'camping', 'trainers', 'launch', 'route', 'ahpages', 'charmoney']) {
    vm.runInContext(read(`js/${name}.js`), sandbox, { filename: `js/${name}.js` });
  }
  return sandbox;
}

const d = loadDashboard();
// Values from the sandbox have its own prototypes; compare plain copies.
const plain = v => JSON.parse(JSON.stringify(v));
const DAY = 86400;
const history = (mins, qtys = mins.map(() => 100), t0 = 1_800_000_000, step = DAY / 4) =>
  mins.map((min, i) => ({ t: t0 + i * step, min, med: min, qty: qtys[i] }));

test('medianOf handles odd and even lists', () => {
  assert.equal(d.medianOf([3, 1, 2]), 2);
  assert.equal(d.medianOf([1, 2, 3, 4]), 2.5);
  assert.equal(d.medianOf([]), null);
});

test('marketSignal: sell above 1.2x median, buy below 0.8x, wait with too few scans', () => {
  assert.equal(d.marketSignal(history([100, 100, 100, 130])).signal, 'sell');
  assert.equal(d.marketSignal(history([100, 100, 100, 70])).signal, 'buy');
  assert.equal(d.marketSignal(history([100, 100, 100, 105])).signal, 'normal');
  assert.equal(d.marketSignal(history([100, 130])).signal, 'wait');
  assert.equal(d.marketSignal([]), null);
});

test('marketSignal ignores snapshots older than the 7-day window', () => {
  const old = history([10, 10, 10], undefined, 1_800_000_000 - 30 * DAY);
  const recent = history([100, 100, 100, 100]);
  assert.equal(d.marketSignal([...old, ...recent]).median, 100);
});

test('salesSpeed: falling listed amount is fast, flat is slow, few scans unknown', () => {
  assert.equal(d.salesSpeed(history([1, 1, 1, 1], [900, 600, 300, 100])).label, 'fast');
  assert.equal(d.salesSpeed(history([1, 1, 1, 1], [400, 400, 400, 400])).label, 'slow');
  assert.equal(d.salesSpeed(history([1, 1], [400, 100])).label, 'unknown');
});

test('craftGroup splits by share of gold', () => {
  assert.equal(d.craftGroup(1000, null), 'safe');
  assert.equal(d.craftGroup(400, 1000), 'safe');
  assert.equal(d.craftGroup(700, 1000), 'risky');
  assert.equal(d.craftGroup(1200, 1000), 'cannot');
});

test('unitCost takes the cheaper of buying ready-made or crafting from raw materials', () => {
  const book = { 'Linen Cloth': history([75]), 'Bolt of Linen Cloth': history([189]) };
  assert.equal(d.unitCost(book, 'tail', 'Bolt of Linen Cloth'), 150);
  assert.equal(d.unitCost({ 'Bolt of Linen Cloth': history([189]) }, 'tail', 'Bolt of Linen Cloth'), 189);
  assert.equal(d.unitCost({}, 'tail', 'Bolt of Linen Cloth'), null);
});

test('rawMaterials breaks intermediates down, including fractional Motes of Magic', () => {
  assert.deepEqual(plain(d.rawMaterials('tail', { 'Bolt of Linen Cloth': 3, 'Coarse Thread': 3 })), { 'Linen Cloth': 6, 'Coarse Thread': 3 });
  const motes = d.rawMaterials('ench', { 'Mote of Magic': 18 });
  assert.ok(Math.abs(motes['Strange Dust'] - 6) < 0.01);
});

test('bestRecipes ranks by gold per skill point and skips grey recipes', () => {
  const scan = { recipes: {
    'Cheap Orange': { difficulty: 'optimal', reagents: [{ name: 'Wool Cloth', count: 3, have: 3 }] },
    'Pricey Green': { difficulty: 'easy', reagents: [{ name: 'Wool Cloth', count: 3, have: 0 }] },
    'Grey': { difficulty: 'trivial', reagents: [{ name: 'Wool Cloth', count: 1, have: 0 }] },
    'Unpriced': { difficulty: 'optimal', reagents: [{ name: 'Mystery Thread', count: 1, have: 0 }] },
  } };
  const picks = d.bestRecipes(scan, { 'Wool Cloth': history([10]) });
  assert.deepEqual(plain(picks.map(p => p.name)), ['Cheap Orange', 'Pricey Green', 'Unpriced']);
  assert.equal(picks[0].costPerPoint, 30);
  assert.equal(picks[1].costPerPoint, 90);
  assert.equal(picks[0].canMake, 1);
});

test('stepRange reads skill ranges from labels', () => {
  assert.deepEqual(plain(d.stepRange('Apprentice (1-75)')), [1, 75]);
  assert.deepEqual(plain(d.stepRange('20-70')), [20, 70]);
  assert.equal(d.stepRange('no range'), null);
});

test('supply chain in the dashboard matches guide.md for every character', () => {
  const md = read('guide.md').split('\n');
  for (const c of d.GUIDE.characters) {
    const line = md.find(l => l.includes(`**${c.race} ${c.class}** (`));
    const lines = d.supplyLines(c);
    if (!lines.length) continue;
    assert.ok(line, `no supply line in guide.md for ${c.race} ${c.class}`);
    assert.ok(line.endsWith(lines.join(' ')), `mismatch for ${c.race} ${c.class}:\n md: ${line}\n js: ${lines.join(' ')}`);
  }
});

test('every guide recipe step has materials', () => {
  for (const [code, prof] of Object.entries(d.GUIDE.professions)) {
    for (const m of prof.milestones) {
      for (const e of m.levelWith || []) {
        for (const r of e.recipes) assert.ok((prof.recipes || {})[r], `${code}: no materials for ${r}`);
      }
    }
  }
});

test('zoneProgress: zones below the level are done, the next one is current, ticks win', () => {
  const zones = ['Tirisfal Glades', 'Silverpine Forest', 'The Barrens', 'Hillsbrad Foothills'];
  assert.deepEqual(plain(d.zoneProgress('A', '19', zones, {})), ['done', 'current', 'upcoming', 'upcoming']);
  assert.deepEqual(plain(d.zoneProgress('A', '20', zones, {})), ['done', 'done', 'current', 'upcoming']);
  const manual = { 'A_Silverpine Forest (10-20)': true, 'A_Tirisfal Glades (1-10)': false };
  assert.deepEqual(plain(d.zoneProgress('A', '15', zones, manual)), ['current', 'done', 'upcoming', 'upcoming']);
  assert.deepEqual(plain(d.zoneProgress('A', 'Beta', zones, {})), ['current', 'upcoming', 'upcoming', 'upcoming']);
});

test('plannedChars: grey cards only for planned characters the realm lacks, Start first', () => {
  const realm = { planned: true, chars: [{ key: 'hunter' }] };
  const keys = plain(d.plannedChars(realm)).map(c => c.key);
  assert.equal(keys.length, 9); // 8 other classes and the bank character
  assert.ok(!keys.includes('hunter'));
  assert.deepEqual(keys.slice(0, 2), ['warlock', 'paladin']);
  assert.equal(keys[keys.length - 1], 'bank');
  assert.deepEqual(plain(d.plannedChars({ chars: [] })), []);
});

test('launchAutoDone: a class is done once a live (non-beta) realm has it', () => {
  const rosters = vm.runInContext('REALM_ROSTERS', d); // a const, so not on the sandbox object
  const saved = { ...rosters };
  rosters.beta = { client: 'classic_beta', chars: [{ key: 'hunter' }] };
  assert.equal(d.launchAutoDone({ auto: 'hunter' }), false);
  rosters.live = { client: 'classic', chars: [{ key: 'hunter' }] };
  assert.equal(d.launchAutoDone({ auto: 'hunter' }), true);
  assert.equal(d.launchAutoDone({ auto: 'liveRealm' }), true);
  assert.equal(d.launchAutoDone({ id: 'manual' }), false);
  delete rosters.beta; delete rosters.live;
  assert.deepEqual(Object.keys(rosters), Object.keys(saved));
});

test('launchAutoDone: a list of classes is done only when every class is live', () => {
  const rosters = vm.runInContext('REALM_ROSTERS', d);
  rosters.live = { client: 'classic', chars: [{ key: 'hunter' }, { key: 'warlock' }] };
  assert.equal(d.launchAutoDone({ auto: ['hunter', 'warlock'] }), true);
  assert.equal(d.launchAutoDone({ auto: ['hunter', 'warlock', 'paladin'] }), false);
  delete rosters.live;
});

test('methodNumbers: cost, expected value after the cut, limits and essence vs wand', () => {
  const at = min => [{ t: 1, min, med: min, qty: 1 }];
  const book = { 'Linen Cloth': at(80), 'Coarse Thread': at(20), 'Strange Dust': at(250),
                 'Lesser Magic Essence': at(720), 'Simple Wood': at(80) };
  const calc = { ...d.GUIDE.money.methods[0].calc, observed: undefined };
  const n = plain(d.methodNumbers(calc, book));
  assert.equal(n.cost, 4 * 80 + 20);
  // 0.25 * (250 + 500 + 720 + 1440) = 727.5, minus 5% = 691.125
  assert.ok(Math.abs(n.value - 691.125) < 1e-9);
  assert.ok(n.profit > 0);
  assert.deepEqual(n.tooHigh.map(t => t.item), ['Linen Cloth']);
  assert.equal(n.wand.better, 'essence'); // 684 on the AH vs 500 - 80 from the vendor
  assert.equal(d.methodNumbers(calc, {}).complete, false);
});

test('yieldOdds: own results count once extra, so unseen results keep a small chance', () => {
  const calc = { yields: [{ id: 'a' }, { id: 'b' }], observed: { a: 8, b: 0 } };
  assert.deepEqual(plain(d.yieldOdds(calc)), { a: 0.9, b: 0.1 });
});

test('methodNumbers: vendor prices for vendor goods and a warning above the cost limit', () => {
  const at = min => [{ t: 1, min, med: min, qty: 1 }];
  const calc = d.GUIDE.money.methods.find(m => m.id === 'copperMaceShuffle').calc;
  const book = { 'Copper Bar': at(140), 'Light Leather': at(146), 'Weak Flux': at(999), 'Greater Magic Essence': at(2150) };
  const n = plain(d.methodNumbers(calc, book));
  assert.equal(n.cost, 12 * 140 + 2 * 146 + 2 * 100); // Weak Flux at the vendor price, not 999
  assert.ok(n.tooHigh.some(t => t.item === 'One Heavy Copper Mace'));
});

test('buildRoute: zones in order, the current step is the first open one, extras by level', () => {
  const meta = d.metaFor({ key: 'hunter', name: 'Lovac', level: '12', professions: [
    { name: 'Skinning', rank: 64, maxRank: 75 }, { name: 'Herbalism', rank: 40, maxRank: 75 }] });
  const route = plain(d.buildRoute({ name: 'Lovac' }, meta, '12'));
  const zones = route.filter(s => s.type === 'zone').map(s => s.text.split(' (')[0]);
  assert.deepEqual(zones.slice(0, 3), ['Mulgore', 'The Barrens', 'Stonetalon Mountains']);
  const current = route.find(s => s.current);
  assert.ok(current && !current.done);
  assert.ok(route.filter(s => s.current).length === 1);
  const journeyman = route.find(s => s.text.startsWith('Train Journeyman'));
  assert.equal(journeyman.done, false); // max rank 75 < 150, even though level 12 >= 10
  // Due by skill: Skinning 64 >= 50 is ready, Herbalism 40 is not.
  assert.ok(journeyman.now && journeyman.text === 'Train Journeyman Skinning (64/75) now.');
  // Gatherers get no "what to gather at this skill" line: the zone lines say it.
  assert.ok(!route.some(s => s.now && s.text.startsWith('Skinning 64/75')));
  const expert = route.find(s => s.text.startsWith('Train Expert'));
  assert.ok(expert.wait && !expert.now && expert.text === 'Train Expert Skinning + Herbalism at skill 125.');
});

test('route choices: the last quest zone picks the way, a hand choice wins, earlier zones tick', () => {
  const c = { key: 'hunter', name: 'Lovac', level: '25',
              questZones: { 'The Barrens': 100, 'Stonetalon Mountains': 200, 'Hillsbrad Foothills': 300 } };
  const meta = d.metaFor(c);
  assert.deepEqual(plain(meta.zones).slice(0, 4), ['Mulgore', 'The Barrens', 'Hillsbrad Foothills', 'Thousand Needles']);
  assert.deepEqual(plain(d.zoneProgress('Lovac', '25', meta.zones, {}, c.questZones)).slice(0, 4),
                   ['done', 'done', 'current', 'upcoming']);
  d.localStorage.setItem('wow_route_choice', JSON.stringify({ 'Lovac|20-30': 0 }));
  assert.deepEqual(plain(d.metaFor(c).zones).slice(2, 5), ['Stonetalon Mountains', 'Ashenvale', 'Thousand Needles']);
  d.localStorage.setItem('wow_route_choice', '{}');
});

test('zoneItems: herbs by name, leather and ore by word, cloth by zone level', () => {
  const meta = d.metaFor({ key: 'hunter' }); // plan: Skinning + Herbalism
  const names = plain(d.zoneItems('Mulgore', meta)).map(i => i.name);
  assert.ok(names.includes('Peacebloom'));
  assert.ok(names.includes('Light Leather'));
  assert.ok(names.includes('Linen Cloth'));
  assert.ok(!names.includes('Silk Cloth'));
});

test('itemDecision: vendor when the AH pays little, hold below the median, keep only for real crafters', () => {
  const at = mins => mins.map((min, i) => ({ t: 1_800_000_000 + i * 3600, min, med: min, qty: 50 }));
  const meta = d.metaFor({ key: 'hunter' });
  const item = { name: 'Light Leather', code: 'skin' };
  const realm = { client: 'x', chars: [] };
  d.SELL_PRICES = { x: { 'Light Leather': 100 } };
  assert.equal(d.itemDecision(item, meta, realm, { 'Light Leather': at([120]) }).action, 'vendor');
  assert.equal(d.itemDecision(item, meta, realm, { 'Light Leather': at([500, 500, 500, 300]) }).action, 'hold');
  assert.equal(d.itemDecision(item, meta, realm, { 'Light Leather': at([400]) }).action, 'ah');
  const planned = { client: 'x', chars: [{ key: 'shaman', name: 'Postarka', professions: [] }] };
  assert.equal(d.itemDecision(item, meta, planned, { 'Light Leather': at([400]) }).action, 'ah'); // no Leatherworking yet
  const withCrafter = { client: 'x', chars: [{ key: 'shaman', name: 'Postarka', professions: [{ name: 'Leatherworking', rank: 1 }] }] };
  const kept = d.itemDecision(item, meta, withCrafter, { 'Light Leather': at([400]) });
  assert.equal(kept.action, 'mail'); // 400 x 10 per stack pays the 30c stamp 3 times over
  assert.match(kept.text, /Postarka/); // the real character's name, not the plan's
  // A stack worth less than 3 stamps (90c) is not mailed: 5c x 10 = 50c, so it goes to the vendor.
  assert.equal(d.itemDecision(item, meta, withCrafter, { 'Light Leather': at([5]) }).action, 'vendor');
  // No price at all: mail full stacks only.
  assert.match(d.itemDecision({ name: 'Medium Leather', code: 'skin' }, meta, withCrafter, {}).text, /full stacks/);
  // First Aid cloth: the current range is kept, a later range is banked.
  const fresh = d.metaFor({ key: 'hunter' });
  assert.equal(d.itemDecision({ name: 'Linen Cloth', code: 'cloth' }, fresh, realm, {}).action, 'keep');
  assert.equal(d.itemDecision({ name: 'Wool Cloth', code: 'cloth' }, fresh, realm, {}).action, 'bank');
  const tailor = d.metaFor({ key: 'warlock' }); // plan: Tailoring + Enchanting
  assert.equal(d.itemDecision({ name: 'Linen Cloth', code: 'cloth' }, tailor, realm, {}).text, 'Keep for your Tailoring');
  delete d.SELL_PRICES;
});

test('buildRoute: gear steps come from the character plan and sit at their level', () => {
  const meta = d.metaFor({ key: 'warlock' });
  const route = plain(d.buildRoute({ name: 'Vestac' }, meta, '1'));
  const gear = route.filter(s => s.type === 'gear');
  assert.ok(gear.length > 0);
  assert.ok(gear.some(s => s.text.includes('Lesser Magic Wand')));
  assert.ok(gear.every(s => s.checked === false));
});

test('RestedXP mode: below the limit only professions, money, bank, gear and zones stay', () => {
  const meta = d.metaFor({ key: 'hunter', name: 'Lovac' });
  const until = d.GUIDE.restedXp.until;
  const low = s => (s.level != null ? s.level < until : false);
  const route = plain(d.buildRoute({ name: 'Lovac' }, meta, '12'));
  assert.ok(!route.some(s => low(s) && ['tip', 'must', 'skip', 'class', 'travel', 'dungeon', 'choice'].includes(s.type)));
  assert.ok(route.some(s => low(s) && s.type === 'prof'));
  assert.ok(route.some(s => s.type === 'dungeon' && s.level >= until)); // dungeons above the limit stay
  d.localStorage.setItem('wow_rxp_mode', 'off');
  const all = plain(d.buildRoute({ name: 'Lovac' }, meta, '12'));
  assert.ok(all.length > route.length); // without the mode, the low zones' steps come back
  // Quest steps never show: the addons guide the quests in game.
  assert.ok(!all.some(s => ['tip', 'must', 'skip', 'quest', 'pickup'].includes(s.type)));
  assert.ok(!all.some(s => s.type === 'dungeon' && s.details));
  d.localStorage.setItem('wow_rxp_mode', 'on');
});

test('no beta data on live: prices, class trainer costs and bag vendors stay with their game client', () => {
  const live = { client: 'forever_live', realmName: 'Live Realm', chars: [] };
  assert.deepEqual(plain(d.priceBook(live)), {});
  const meta = d.metaFor({ key: 'hunter', name: 'Lovac' });
  assert.deepEqual(plain(d.classTrainingSteps(meta, live)), []);
  const bag = d.bagVendorStep(meta, live);
  assert.ok(!bag || bag.text === d.GUIDE.bagVendorFallback.text);
});

test('shopping: zone list with cost and bag slots, carry list for the camp pick', () => {
  const meta = d.metaFor({ key: 'paladin', name: 'Pala' });
  const realm = { client: 'x', chars: [] };
  const line = d.zoneShopLine('Tirisfal Glades', 0, meta, realm);
  assert.match(line, /^Buy in Deathknell: 1 Fishing Pole, 2 Shiny Bauble ·/); // money goes to skills first
  assert.match(d.zoneShopLine('Silverpine Forest', 1, meta, realm), /^Buy in The Sepulcher: 3 Simple Wood, 5 Nightcrawlers, 5 Ice Cold Milk/);
  assert.match(line, /about \d/);
  assert.match(line, /bag slots/);
  const carry = plain(d.carryList(meta, realm)).map(x => x[0]);
  assert.ok(!carry.includes('Empty Vial') && carry.includes('Basic Campfire Kit')); // short kit: no camp materials
  assert.ok(carry.includes('Healing Potions (your best), 1 stack'));
  assert.ok(carry.includes('Water (your level)')); // a Paladin uses mana
  assert.match(d.zoneFishLine('Tirisfal Glades', meta), /^Fishing 1-75 here: Brightwater Lake/);
});

test('zone quests: one line per hub in level order, other givers last, done counts', () => {
  d.ZONE_QUESTS = { zones: { 'Hillsbrad Foothills': [
    { id: 1, level: 22, name: 'A', hub: 'Tarren Mill', status: 'same' },
    { id: 2, level: 24, name: 'B', hub: 'Tarren Mill', status: 'new' },
    { id: 3, level: 21, name: 'C', hub: 'Undercity', status: 'same' },
    { id: 4, level: 60, name: 'D', hub: 'Tarren Mill', status: 'same' }] } }; // far above the zone: left out
  const lines = plain(d.zoneQuestLines('Hillsbrad Foothills', { completedQuests: [1] }));
  assert.equal(lines[0].text, 'Tarren Mill (22-24): 2 quests, 1 done · new in Forever: B.');
  assert.match(lines[1].text, /^Other \(items, posters, givers in other zones\) \(21\): 1 quest\.$/);
  delete d.ZONE_QUESTS;
});

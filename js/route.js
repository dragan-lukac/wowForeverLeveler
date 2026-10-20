// Part of the WoW Forever dashboard (index.html). Plain script: shares globals with the other js/ files.
// --- Route: one list per character in level order: zones, must-do and skipped quests, profession,
// gear and money steps. Everything comes from guide.json and the character's synced data. ---

// Classic training tiers: the level and skill you need, and the new skill cap.
const PROF_TIERS = [
  { name: 'Journeyman', level: 10, skill: 50, cap: 150 },
  { name: 'Expert', level: 20, skill: 125, cap: 225 },
  { name: 'Artisan', level: 35, skill: 200, cap: 300 }
];

const ROUTE_ICONS = { zone: '🗺', choice: '🔀', camp: '🏕', shop: '🛒', fish: '🎣', quest: '📜', pickup: '🏰', must: '⭐', tip: '💡', class: '❗', skip: '✂', dungeon: '🏰', prof: '⚒', gear: '🗡', money: '💰', travel: '➜', bank: '🏦' };

function zoneEntryLevel(zoneName) {
  return parseInt(String(GUIDE.zones[zoneName].levels).split('-')[0], 10) || 1;
}

// Adds the skill each herb, ore or leather needs in brackets (guide.json professions.<code>.nodes),
// for example "Earthroot (15)". A number above the character's skill shows in amber.
function withSkillNeeded(code, text, rank) {
  const nodes = PROFS[code].nodes;
  if (!nodes || !text) return text;
  const names = Object.keys(nodes).sort((a, b) => b.length - a.length);
  const escape = n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`\\b(${names.map(escape).join('|')})\\b(?! \\()`, 'gi');
  return text.replace(re, match => {
    const key = names.find(n => n.toLowerCase() === match.toLowerCase());
    const node = nodes[key];
    const skill = typeof node === 'object' ? node.skill : node;
    const low = parseInt(String(skill), 10);
    const label = typeof node === 'object' ? `beasts ${node.beasts}, skill ${node.skill}` : `${skill}`;
    const short = rank != null && low > rank;
    return `${match} <span class="${short ? 'text-amber-400' : 'text-slate-400'}">(${label})</span>`;
  });
}

// What to do at this skill: the recipe for the current range with how many to make and the raw
// materials (about 1 craft per point), or the gathering tip. Null when the guide has no step.
function profStepText(code, rank) {
  const milestone = (PROFS[code].milestones || []).find(m => {
    const r = stepRange(String(m.rank));
    return r && rank >= r[0] && rank < r[1];
  });
  if (!milestone) return null;
  const entry = (milestone.levelWith || []).find(e => {
    const r = stepRange(e.range);
    return r && rank >= r[0] && rank < r[1];
  });
  if (!entry) return milestone.desc;
  const recipe = entry.recipes[0];
  const count = stepRange(entry.range)[1] - rank;
  const reagents = (PROFS[code].recipes || {})[recipe];
  const mats = reagents ? rawMaterials(code, Object.fromEntries(Object.entries(reagents).map(([n, q]) => [n, q * count]))) : null;
  const matText = mats ? ` Buy ${Object.entries(mats).map(([n, q]) => `${q} ${n}`).join(', ')}.` : '';
  return `make about ${count} ${recipe} (to ${stepRange(entry.range)[1]}).${matText}`;
}

// Dungeon quests from the Forever Loot / DFL Dungeon Journal addons (data/dungeons.js), per game client.
function dungeonList(realm) {
  const all = window.DUNGEONS || {};
  const book = all[realm && realm.client] || Object.values(all)[0];
  return book ? book.list : [];
}

const coords = p => p && p.x != null ? ` ${p.x}, ${p.y}` : '';

// The Legacy dungeon challenge a dungeon counts for (guide.json legacy.spelunker), or null.
const SPELUNKER_ALIASES = { 'Sunken Temple': "Temple of Atal'Hakkar" };
function spelunkerTier(name) {
  const tiers = ((GUIDE.legacy || {}).spelunker || {}).tiers || {};
  const wanted = SPELUNKER_ALIASES[name] || name;
  return Object.keys(tiers).find(t => tiers[t].some(entry => entry.includes(wanted))) || null;
}

// One step per dungeon at its lowest level; opening it lists the Horde quests to pick up before
// going in, with giver and place. Quests the character has finished are left out; all done = step done.
// The plan for one dungeon: when all its quests can be taken and from which cities, a run level per
// role (rule of thumb from the level range), until when the quests give full XP, and the total XP.
function dungeonPlan(d, quests, meta) {
  const [low, high] = String(d.levels).split('-').map(n => parseInt(n, 10));
  if (!quests.length || !low) return { runShort: '', html: '' };
  const span = (high || low) - low;
  const at = f => Math.round(low + span * f);
  const dps = at(0.3), healer = [at(0.35), at(0.45)], tank = [at(0.5), at(0.6)];
  const from = Math.max(...quests.map(q => q.minLevel || 1));
  // Quests far above the dungeon (a level 60 quest listed under Wailing Caverns) do not count here.
  const fitting = quests.filter(q => (q.level || low) <= (high || low) + 5);
  const fullXp = Math.max(...(fitting.length ? fitting : quests).map(q => q.level || low)) + 5;
  const xp = quests.reduce((t, q) => t + ((q.reward && q.reward.xp) || 0), 0);
  const cities = {};
  quests.forEach(q => { const z = q.start && q.start.zone; if (z && z !== d.name) cities[z] = (cities[z] || 0) + 1; });
  const travel = ((GUIDE.dungeons || {}).cityTravel || {});
  const far = Object.keys(cities).filter(z => travel[z] && !meta.zones.includes(z) && !(meta.zones[0] === 'Mulgore' && z === 'Thunder Bluff')
    && !(meta.zones[0] === 'Durotar' && z === 'Orgrimmar') && !(meta.zones[0] === 'Tirisfal Glades' && z === 'Undercity'));
  const fmtRange = r => r[0] === r[1] ? `${r[0]}` : `${r[0]}-${r[1]}`;
  const html = `<div class="text-sm py-1 text-amber-200">Plan: collect the quests from level ${from}`
    + (Object.keys(cities).length ? ` (${Object.entries(cities).map(([z, n]) => `${z} ${n}`).join(', ')})` : '')
    + `. Run at about ${dps}-${tank[1]}: DPS ${dps}, healer ${fmtRange(healer)}, tank ${fmtRange(tank)}. ${fullXp >= 60 ? 'Full quest XP up to level 60.' : `Full quest XP until level ${fullXp}.`}`
    + (xp ? ` About ${xp.toLocaleString('en')} quest XP.` : '')
    + (far.length ? `<br>New city on the way: ${far.map(z => travel[z]).join(' ')}` : '')
    + `</div>`;
  return { runShort: ` Run at ${dps}-${tank[1]}.`, html };
}

function dungeonSteps(c, realm, lvl, meta = { zones: [] }) {
  const done = new Set((c && c.completedQuests) || []);
  const known = !!(c && c.completedQuests && c.completedQuests.length);
  const skip = new Set((GUIDE.dungeons || {}).hordeSkip || []);
  // Guide dungeons the addons have no quests for yet, with a Horde text (Excavation Site).
  const inAddons = new Set(dungeonList(realm).map(d => d.name));
  const fromGuide = ((GUIDE.dungeons || {}).list || []).filter(d => d.horde && !inAddons.has(d.name)).map(d => {
    const [low, high] = String(d.levels).split('-').map(n => parseInt(n, 10));
    return { level: low || 1, type: 'dungeon', zone: ((GUIDE.dungeons || {}).zoneOf || {})[d.name],
             done: lvl > (high || low), text: d.horde.text, short: d.horde.text.split('.')[0] + '.', checked: d.horde.checked };
  });
  return fromGuide.concat(dungeonList(realm).filter(d => d.kind === 'dungeon' && d.quests.length && !skip.has(d.name)).map(d => {
    const open = d.quests.filter(q => !done.has(q.id));
    // Chain steps often share one name: show each name once, with the giver of the step that has one.
    const byName = new Map();
    open.forEach(q => {
      const seen = byName.get(q.name);
      if (!seen) byName.set(q.name, { ...q, steps: 1 });
      else byName.set(q.name, { ...(seen.start ? seen : q), steps: seen.steps + 1 });
    });
    const groups = [...byName.values()];
    const line = q => {
      const giver = q.start ? [q.start.name, q.start.zone ? q.start.zone + coords(q.start) : ''].filter(Boolean).join(', ') : 'giver unknown';
      const steps = q.steps > 1 ? ` · ${q.steps} steps` : '';
      const chain = (q.chainFirst && q.chainFirst.name !== q.name ? ` · starts with ${q.chainFirst.name}` : '') + steps;
      const extra = ((GUIDE.dungeons || {}).questNotes || {})[q.name];
      return `<div class="text-sm py-0.5"><b>${q.name}</b> [${q.level}, from ${q.minLevel}]: ${giver}${chain}${extra ? ` <span class="text-amber-300">${extra}</span>` : ''}</div>`;
    };
    const [low, high] = String(d.levels).split('-').map(n => parseInt(n, 10));
    const tier = spelunkerTier(d.name);
    const plan = dungeonPlan(d, open, meta);
    // One line: no quest list (the addons show the dungeon quests in game).
    const head = `${d.name} (${d.levels}):${plan.runShort}${tier ? ' ⭐ Legacy.' : ''}`;
    return {
      level: low || 1, type: 'dungeon', zone: ((GUIDE.dungeons || {}).zoneOf || {})[d.name],
      // Outlevelled dungeons are done too, so old quests do not pile up as "due now".
      done: (known && open.length === 0) || lvl > (high || low),
      text: head, short: head
    };
  }));
}

// Class training up to level 20 (later skills matter less for money), from the class trainer the
// addon read (data/trainers.js CLASS_TRAINERS): one step per level with the skills and their cost.
const CLASS_TRAINING_MAX_LEVEL = 20;

function classTrainingSteps(meta, realm) {
  const all = window.CLASS_TRAINERS || {};
  // Only this realm's own game client: beta costs never show on live characters.
  const book = all[realm && realm.client] || {};
  const skills = book[String(meta.class || '').toUpperCase()];
  if (!skills) return [];
  const byLevel = {};
  Object.entries(skills).forEach(([name, s]) => {
    if (s.level > 1 && s.level <= CLASS_TRAINING_MAX_LEVEL && s.cost > 0) (byLevel[s.level] = byLevel[s.level] || []).push({ name, ...s });
  });
  return Object.entries(byLevel).map(([level, list]) => ({
    level: Number(level), type: 'class',
    text: `Class trainer (${formatCopper(list.reduce((t, x) => t + x.cost, 0))}): ${list.map(x => x.name).join(', ')}.`
  }));
}

// Where to buy a bag if none dropped: a bag vendor the addon saw in this character's first zones
// (data/npcs.js BAG_VENDORS), else the guide's fallback text. Levels 6+ (the money goes to skills first).
function bagVendorStep(meta, realm) {
  const all = window.BAG_VENDORS || {};
  // Only this realm's own game client: beta prices never show on live characters (the guide text does).
  const book = all[realm && realm.client] || {};
  const zones = meta.zones.slice(0, 2);
  const offers = [];
  Object.entries(book).forEach(([vendor, v]) => {
    if (!zones.includes(v.zone)) return;
    Object.entries(v.bags || {}).forEach(([bag, b]) => offers.push({ vendor, v, bag, ...b }));
  });
  offers.sort((a, b) => (a.price / (a.slots || 1)) - (b.price / (b.slots || 1)));
  const o = offers[0];
  if (o) {
    const where = [o.v.subzone, o.v.zone].filter(Boolean).join(', ') + (o.v.x != null ? ` (${o.v.x}, ${o.v.y})` : '');
    return { level: 6, type: 'money', text: `No bag dropped yet? ${o.vendor} in ${where} sells ${o.bag}${o.slots ? ` (${o.slots} slots)` : ''} for about ${formatCopper(o.price)} (the price drops with reputation).` };
  }
  const fb = GUIDE.bagVendorFallback;
  return fb ? { level: 6, type: 'money', text: fb.text, checked: fb.checked } : null;
}

// Steps that are not tied to a zone, each with the level it belongs to.
// One line: which weapon skills the class can learn, grouped by Horde weapon master (home city first).
// Wands are not trained; a skill two masters teach is listed only at the first city.
function weaponSkillsText(meta) {
  const W = GUIDE.weaponSkills;
  const mine = W && (W.classes[meta.class] || []).filter(s => s !== 'Wands');
  if (!mine || !mine.length) return null;
  const home = W.home[meta.race];
  const cities = Object.keys(W.trainers).sort((a, b) => (b === home) - (a === home));
  const left = new Set(mine);
  const parts = cities.map(city => {
    const t = W.trainers[city];
    const here = t.skills.filter(s => left.delete(s)).map(s => (s === 'Polearms' ? 'Polearms (level 20, 1g)' : s));
    return here.length ? `${city} (${t.npc} ${t.where.replace(/^[^,]*, /, '')}): ${here.join(', ')}` : null;
  }).filter(Boolean);
  return `Weapon skills (10s): ${parts.join(' · ')}.`;
}

// "Two ways for levels 20-30: Kalimdor (...) or Eastern Kingdoms (...)": each a button, the chosen one bold.
function choiceText(ch) {
  const opts = ch.options.map((o, i) => {
    const label = `${o.name}: ${o.zones.join(' + ')} (${o.note})`;
    return `<button onclick="event.stopPropagation(); setRouteChoice('${ch.id}', ${i})" class="inline text-left underline decoration-dotted ${ch.chosen === i ? 'font-semibold text-amber-300' : 'hover:text-amber-300'}">${label}</button>`;
  });
  return `Two ways for levels ${ch.levels}: ${opts.join(' or ')}`;
}

function setRouteChoice(id, idx) {
  const saved = loadRouteChoices();
  saved[`${activeCharacter.name}|${id}`] = idx;
  try { localStorage.setItem(ROUTE_CHOICE_KEY, JSON.stringify(saved)); } catch (e) {}
  activeCharacter.meta = metaFor(REALM_ROSTERS[currentRealmKey].chars.find(ch => ch.name === activeCharacter.name) || { key: activeCharacter.key, name: activeCharacter.name });
  renderActiveLevelingCategory();
}

// Secondary professions (guide.json secondaryPlan: every character levels all three): learn them in the
// first town, train First Aid by skill, what to make now, and the camp line (camping.picks).
function secondarySteps(meta, level) {
  const plan = GUIDE.secondaryPlan;
  if (!plan || meta.bank) return [];
  const steps = [];
  const ranks = meta.profRanks || {};
  const missing = plan.all.filter(p => ranks[p] == null);
  // Trainers of the starting zone (secondaryPlan.startTrainers): Bloodhoof Village, Razor Hill or Brill, Fishing at a lake.
  const where = (plan.startTrainers || {})[meta.zones[0]] || {};
  const list = (missing.length ? missing : plan.all).map(p => `${PROFS[p].name}${where[p] ? ` (${where[p]})` : ''}`);
  steps.push({ level: 1, type: 'prof', start: true, done: !missing.length,
               text: `Learn ${list.join(', ')}: about 1s each.` });
  // Training by skill for each learned secondary profession (guide.json professions.<code>.training).
  // What to make or where to fish is on the Professions tab card (secondaryCard).
  plan.all.filter(p => ranks[p] != null).forEach(p => {
    const max = (meta.profMaxRanks || {})[p];
    (PROFS[p].training || []).forEach(t => steps.push({
      level: t.level || 10, type: 'prof', done: max >= t.cap, wait: ranks[p] < t.skill,
      text: ranks[p] < t.skill ? `Train ${t.name} ${PROFS[p].name} at skill ${t.skill}: ${t.where}.`
        : `Train ${t.name} ${PROFS[p].name} (${ranks[p]}/${max}) now: ${t.where}.` }));
  });
  const pick = ((GUIDE.camping || {}).picks || {})[meta.id];
  const obj = pick && GUIDE.camping.objects.find(o => o.prof === pick);
  if (obj) {
    const rank = ranks[pick];
    const ready = rank != null && rank >= obj.skill && (ranks.cook || 0) >= 20;
    // Pinned on top once the skills are there; until then it waits at level 10.
    steps.push({ type: 'camp', ...(ready ? { group: null, now: true, level } : { level: 10, done: false, wait: true }),
                 text: `Camp every hour: Basic Campfire Kit, then ${obj.name} (${obj.buff}). Carry 5 kits (1 Simple Wood each), ${obj.mats.replace(/\d+/g, n => n * 5)}.${ready ? '' : ` Needs ${PROFS[pick].name} ${obj.skill}${rank != null ? ` (now ${rank})` : ''} and Cooking 20.`}` });
  }
  return steps;
}

// Quest hubs of a zone (data/zone_quests.js, levels 20+): one line per hub in level order, with how many of
// its quests are done and the new Forever ones by name. Quests without a known hub go into one last line.
function zoneQuestLines(zoneName, c) {
  const top = parseInt(String(GUIDE.zones[zoneName].levels).split('-').pop(), 10);
  const list = (((window.ZONE_QUESTS || {}).zones || {})[zoneName] || []).filter(q => !(q.level > top + 5));
  if (!list.length) return [];
  const own = GUIDE.zones[zoneName].hubCoords || {};
  const other = 'Other (items, posters, givers in other zones)';
  const done = new Set((c && c.completedQuests) || []);
  const hubs = new Map();
  // A hub in another zone can be named (zones.<zone>.hubAliases: the Bulwark is in Tirisfal, its quests in WPL).
  const alias = GUIDE.zones[zoneName].hubAliases || {};
  list.forEach(q => { const h = own[q.hub] ? q.hub : alias[q.hub] || other; if (!hubs.has(h)) hubs.set(h, []); hubs.get(h).push(q); });
  const order = [...hubs.entries()].sort(([a, x], [b, y]) => ((a === other) - (b === other))
    || Math.min(...x.map(q => q.level)) - Math.min(...y.map(q => q.level)));
  return order.map(([hub, qs]) => {
    const lv = qs.map(q => q.level);
    const range = Math.min(...lv) === Math.max(...lv) ? `${lv[0]}` : `${Math.min(...lv)}-${Math.max(...lv)}`;
    const finished = qs.filter(q => done.has(q.id)).length;
    const fresh = [...new Set(qs.filter(q => q.status === 'new').map(q => q.name))];
    return { type: 'quest', level: Math.min(...lv), done: finished === qs.length,
             text: `${hub} (${range}): ${qs.length} quest${qs.length === 1 ? '' : 's'}${finished ? `, ${finished} done` : ''}${fresh.length ? ` · new in Forever: ${fresh.slice(0, 4).join(', ')}${fresh.length > 4 ? ` +${fresh.length - 4}` : ''}` : ''}.` };
  });
}

// Dungeon quests whose giver stands in this zone: take them while you are here (Forever Loot / DFL data).
function zonePickupLines(zoneName, c, realm, lvl) {
  const done = new Set((c && c.completedQuests) || []);
  const skip = new Set((GUIDE.dungeons || {}).hordeSkip || []);
  return dungeonList(realm).filter(d => d.kind === 'dungeon' && !skip.has(d.name)).map(d => {
    const high = parseInt(String(d.levels).split('-').pop(), 10);
    const here = [...new Map(d.quests.filter(q => q.start && q.start.zone === zoneName && !done.has(q.id)).map(q => [q.name, q])).values()];
    if (!here.length || lvl > high) return null;
    return { type: 'pickup', level: Math.min(...here.map(q => q.minLevel || q.level)),
             text: `Take for ${d.name}: ${here.map(q => `${q.name} (${q.start.name}${coords(q.start)})`).join(', ')}.` };
  }).filter(Boolean);
}

function extraSteps(meta, level) {
  const steps = [];
  const ranks = meta.profRanks || {};
  const maxRanks = meta.profMaxRanks || {};
  const primary = meta.profs.filter(p => PROFS[p].type !== 'secondary');
  const weapons = weaponSkillsText(meta);
  if (weapons) steps.push({ level: 10, type: 'gear', checked: GUIDE.weaponSkills.checked, text: weapons });
  if (primary.length) {
    // Level 1 setup, in this order before the first zone (start: true): the free profession quest,
    // the trainers, the gathering bag. Gathering trainers stand in the starting camps (Camp Narache:
    // 10c each, seen in the beta); crafting trainers are in the cities.
    const gather = primary.filter(p => PROFS[p].type === 'gather');
    const craft = primary.filter(p => PROFS[p].type !== 'gather');
    const has = list => list.length > 0 && list.every(p => ranks[p] != null);
    if (gather.length) {
      // Crafters skip it: a free gathering profession would take a slot they need.
      // Order tested with a beta hunter: free quest profession, then the paid one with its tool at
      // 20c, then the gathering bags at 50c.
      // Once one gathering profession is learned, that one was the paid one and the book is for the other.
      const learned = gather.filter(p => ranks[p] != null);
      // Mining + Skinning (user's choice): train Skinning at once (a Junior trainer in the starting camp, so skins
      // from the first kill), Mining from the book quest.
      const paid = learned.length === 1 ? learned[0] : gather.find(p => p === 'skin') || gather.find(p => p === 'mine') || gather[0];
      const free = gather.find(p => p !== paid);
      const tool = { skin: ' and buy a Skinning Knife (about 10c)', mine: ' and buy a Mining Pick' }[paid] || '';
      // Each starting zone has a quest (guide.json zones.<zone>.professionQuest) whose reward is a book
      // that teaches one gathering profession: take the book for the one you do not train.
      const pq = (GUIDE.zones[meta.zones[0]] || {}).professionQuest;
      if (free && pq) {
        steps.push({ level: pq.level, type: 'prof', start: pq.level <= 1, checked: pq.checked,
                     done: ranks[free] != null,
                     text: `Quest ${pq.quest} (level ${pq.level}): choose the book ${GUIDE.professionBooks[free]}. It teaches ${PROFS[free].name} for free.` });
      }
      steps.push({ level: 1, type: 'prof', start: true, done: ranks[paid] != null,
                   text: `As soon as you have 20c: learn ${PROFS[paid].name} at the trainer in your starting camp (10c)${tool}.` });
      // Only one reagent bag slot: the bag for the profession that fills bags fastest goes there.
      const bags = ['mine', 'skin', 'herb'].filter(p => gather.includes(p));
      if (bags.length) {
        // Tested on the beta hunter: herbs take only 1-2 slots in the starting zone, so one bag is enough.
        const knife = bags[0] === 'skin' ? ' It also holds your Skinning Knife and the scraps, so they leave your backpack.' : '';
        const second = bags[1] === 'herb' ? ' Skip the Herbalism bag: herbs take only 1-2 slots at the start.'
          : bags[1] ? ` A ${PROFS[bags[1]].name} bag (25c) can go in a normal bag slot if those fill your backpack.` : '';
        steps.push({ level: 1, type: 'money', start: true,
                     text: `As soon as you have 25c: buy a ${PROFS[bags[0]].name} bag (4 slots) for the reagent bag slot.${knife}${second}` });
      }
    }
    steps.push({ level: 1, type: 'money', start: true,
                 text: 'Sell grey items at every vendor. Keep materials and quest items.' });
    // Silver is scarce at the start: skills and professions first, bag materials later.
    steps.push({ level: 1, type: 'money', start: true,
                 text: `Levels 1-6: buy no bag materials. Money goes to skills first, then your professions.${meta.profs.some(p => ['skin', 'mine', 'herb'].includes(p)) ? ' One exception: the 25c gathering bag, buy it as soon as you can (4 slots for 25c).' : ''}` });
    steps.push({ level: 10, type: 'money',
                 text: 'After your level 10 skills: if you still need bags, mail the bank character Linen Cloth (free from mobs, 6 per bag) and 30c per Linen Bag. Add 1s 30c once, for her very first bag (recipe and Tailoring). You decide how many.' });
    // Starting camps have no mailbox (guide.json zones.<zone>.firstMailbox): until then the bags are
    // the only storage, and class skills come first.
    const mailbox = (GUIDE.zones[meta.zones[0]] || {}).firstMailbox;
    if (mailbox) {
      steps.push({ level: 1, type: 'money', start: true, checked: mailbox.checked,
                   text: meta.profs.includes('skin')
                     ? `No mailbox in your starting camp: the first one is in ${mailbox.town}. Until then, if money for skills or bag space runs short, sell greys first, then only as many Ruined Leather Scraps (7c each) as you need. Mail the rest to the bank character from ${mailbox.town}.`
                     : `No mailbox in your starting camp: the first one is in ${mailbox.town}. Mail materials to the bank character from there.` });
    }
    if (craft.length) {
      steps.push({ level: 5, type: 'prof', done: has(craft),
                   text: `Learn ${craft.map(p => PROFS[p].name).join(' + ')} at a profession trainer in the city (🧭 Trainers). No level needed: learn them when you first reach the city.` });
    }
    // Each tier names only the professions that still need it. With skill data a tier is due once the
    // skill reaches the tier's need (it waits otherwise); without it, it goes by level.
    const known = primary.every(p => maxRanks[p] != null);
    PROF_TIERS.forEach(t => {
      const todo = known ? primary.filter(p => maxRanks[p] < t.cap) : primary;
      const ready = todo.filter(p => ranks[p] >= t.skill);
      const now = (known ? ready : todo).map(p => `${PROFS[p].name}${ranks[p] != null ? ` (${ranks[p]}/${maxRanks[p]})` : ''}`);
      steps.push({
        level: t.level, type: 'prof', done: known ? todo.length === 0 : undefined, wait: known && !ready.length,
        text: known && !ready.length
          ? `Train ${t.name} ${todo.map(p => PROFS[p].name).join(' + ')} at skill ${t.skill}.`
          : `Train ${t.name} ${now.join(' + ')} now.`
      });
    });
    // What to make at the current skill (crafting only: the zone lines say what to gather).
    primary.filter(p => ranks[p] != null && PROFS[p].type !== 'gather' && !(maxRanks[p] && ranks[p] >= maxRanks[p])).forEach(p => {
      const text = profStepText(p, ranks[p]);
      if (text) steps.push({ level, type: 'prof', now: true, text: `${PROFS[p].name} ${ranks[p]}/${maxRanks[p] || '?'}: ${text}` });
    });
  }
  steps.push(...secondarySteps(meta, level));
  // Notes for this character only (guide.json characters[].routeNotes), e.g. the Paladin's Bandarion Keep.
  // RestedXP does not know them, so they stay in RestedXP mode.
  (meta.routeNotes || []).forEach(n => steps.push({ ...n, keep: true }));
  (MONEY.methods || []).filter(m => m.needs.every(p => meta.profs.includes(p)))
    .forEach(m => steps.push({ level: m.level || 1, type: 'money', text: `${m.name} (🏦 Auction House › Money methods).` }));
  if (String(meta.class).toLowerCase() === 'hunter') {
    // Hunters start with their ammo holder: Tauren a gun and an ammo pouch, Orcs and Trolls a bow and a quiver.
    const gun = ['Tauren', 'Dwarf'].includes(meta.race);
    steps.push({ level: 1, type: 'gear', start: true,
                 text: `Ammo: you start with ${gun ? 'a gun and an ammo pouch' : 'a bow and a quiver'}, so do not buy one. Buy ${gun ? 'bullets' : 'arrows'} at every vendor and keep 2+ stacks.` });
  }
  // Must-do steps for every character at a level (guide.json globalMustDo), e.g. the level 30 bag.
  (GUIDE.globalMustDo || []).forEach(m => steps.push({ level: m.level, type: 'must', text: m.text, checked: m.checked }));
  const chain = (GUIDE.legacy || {}).questChain;
  if (chain) steps.push({ level: chain.level, type: 'must', text: chain.text, checked: chain.checked });
  // Warlocks and Paladins learn a class mount from their trainer instead of buying one.
  const classMount = ['warlock', 'paladin'].includes(String(meta.class).toLowerCase());
  steps.push({ level: MONEY.mountGoal.level, type: 'money', text: classMount
    ? `Learn your class mount from your class trainer at level ${MONEY.mountGoal.level}. Save gold for the training (cost not known yet).`
    : MONEY.mountGoal.training
      ? `Level ${MONEY.mountGoal.level}: learn Apprentice Riding (${MONEY.mountGoal.training} gold) and buy a mount (${MONEY.mountGoal.mount} gold): ${MONEY.mountGoal.gold} gold in total.`
      : `Buy your mount: ${MONEY.mountGoal.gold} gold at level ${MONEY.mountGoal.level}.` });
  // Weapon steps; ones that are not an upgrade over a sure weapon are marked hidden in guide.json.
  ((GUIDE.gear || {})[meta.id] || []).filter(g => !g.hidden)
    .forEach(g => steps.push({ level: g.level, type: 'gear', text: g.text, checked: g.checked }));
  return steps;
}

// The full route: zone blocks in route order, with the other steps placed after the last zone
// that starts at or below their level. Each step gets done / current flags.
// Quest steps the dashboard no longer shows (user, 2026-10-16): Polestar and our addon guide the quests in game.
const QUEST_STEPS = new Set(['tip', 'must', 'skip', 'quest', 'pickup']);

function buildRoute(c, meta, level) {
  if (meta.bank) {
    return (meta.steps || []).map((s, i) => ({ ...s, type: 'bank', current: i === 0 }));
  }
  const lvl = parseInt(level, 10) || 1;
  const realm = REALM_ROSTERS[currentRealmKey];
  const book = priceBook(realm);
  const completedMap = loadZoneTicks();
  const progress = zoneProgress(c.name, level, meta.zones, completedMap, (c && c.questZones) || {});
  const mustStart = [];
  const zoneBlocks = meta.zones.map((zoneName, idx) => {
    const info = GUIDE.zones[zoneName];
    const note = (meta.zoneNotes || {})[zoneName] || {};
    const done = progress[idx] === 'done';
    const block = [{ level: zoneEntryLevel(zoneName), type: 'zone', zoneIdx: idx, group: idx, done,
                     text: `${zoneLabel(zoneName)}: ${(info.hubs || []).join(', ') || 'quests'}.` }];
    if (note.class) block.push({ type: 'class', done, text: note.class });
    // Optional quests worth knowing (guide.json zones.<zone>.optional): one line each, inside the zone.
    // With an id the quest ticks itself when done and its name links to ClassicDB.
    (info.optional || []).forEach(o => {
      const name = o.id ? `<a href="https://classicdb.ch/?quest=${o.id}" target="_blank" class="underline decoration-dotted hover:text-amber-300">${o.quest}</a>` : o.quest;
      block.push({ type: 'tip', checked: o.checked, level: o.level,
                   done: o.id ? ((c && c.completedQuests) || []).includes(o.id) || done : done,
                   text: o.id ? o.text.replace(o.quest, name) : o.text });
    });
    // Must-do quests (guide.json zones.<zone>.mustDo): in the first zone they open the route.
    (info.mustDo || []).forEach(m => {
      const step = { type: 'must', checked: m.checked, level: m.level,
                     done: m.id ? ((c && c.completedQuests) || []).includes(m.id) : (done || undefined),
                     text: `Do ${m.quest}: it gives ${m.reward}.${m.note ? ' ' + m.note : ''}` };
      if (idx === 0) mustStart.push({ ...step, level: m.level || 1, start: true });
      else block.push(step);
    });
    // All elite quests of the zone on one line; each name links to its ClassicDB page.
    const skips = info.skips || [];
    if (skips.length) {
      const link = s => s.id ? `<a href="https://classicdb.ch/?quest=${s.id}" target="_blank" class="underline decoration-dotted hover:text-amber-300">${s.quest}</a>` : s.quest;
      // One entry per quest name: "The Crown of Will [39-43]".
      const byName = Object.values(skips.reduce((acc, s) => ((acc[s.quest] = acc[s.quest] || []).push(s), acc), {}));
      const levels = list => [...new Set(list.map(s => s.level).filter(Boolean))].sort((a, b) => a - b);
      const shown = byName.slice(0, 8).map(list => { const l = levels(list); return `${link(list[0])}${l.length ? ` [${l.length > 1 ? `${l[0]}-${l[l.length - 1]}` : l[0]}]` : ''}`; });
      const more = byName.length > 8 ? `, and ${byName.length - 8} more` : '';
      block.push({ type: 'skip', done, text: `Skip (elite): ${shown.join(', ')}${more}.` });
    }
    meta.profs.filter(p => PROFS[p].type === 'gather' && (info.gather || {})[p])
      .forEach(p => block.push({ type: 'prof', done, text: `${PROFS[p].name}: ${p === 'skin' ? info.gather[p] : withSkillNeeded(p, info.gather[p], (meta.profRanks || {})[p])}` }));
    zoneQuestLines(zoneName, c).forEach(q => block.push({ ...q, done: q.done || done }));
    zonePickupLines(zoneName, c, realm, lvl).forEach(q => block.push({ ...q, done }));
    const shop = zoneShopLine(zoneName, idx, meta, realm);
    if (shop) block.push({ type: 'shop', done, text: shop });
    const money = zoneMoneyLine(zoneName, meta, realm, book);
    if (money) block.push({ type: 'money', done, text: money });
    const bank = zoneBankLine(zoneName, meta, realm, book);
    if (bank) block.push({ type: 'bank', done, text: bank });
    const fishing = zoneFishLine(zoneName, meta);
    if (fishing) block.push({ type: 'fish', done, text: fishing });
    (meta.choices || []).filter(ch => ch.at === zoneName).forEach(ch => block.push({ type: 'choice', done, text: choiceText(ch) }));
    const nextZone = meta.zones[idx + 1];
    // The plan's travel note only fits when the next zone is still the planned one.
    const planNext = (meta.planZones || meta.zones)[(meta.planZones || meta.zones).indexOf(zoneName) + 1];
    const next = (planNext === nextZone && note.next) || (nextZone ? `Go to ${zoneLabel(nextZone)}.` : null);
    if (next) block.push({ type: 'travel', done, text: next });
    return block;
  });

  // A dungeon goes inside its own zone, before the travel line, when the route has that zone and the
  // dungeon's first level is inside the zone's level range; otherwise it is placed by level.
  const zoneRange = z => String(GUIDE.zones[z].levels).split('-').map(n => parseInt(n, 10));
  const fits = d => meta.zones.includes(d.zone) && (([lo, hi]) => d.level >= lo && d.level <= (hi || lo))(zoneRange(d.zone));
  const dungeons = dungeonSteps(c, realm, lvl, meta);
  dungeons.filter(fits).forEach(d => {
    const block = zoneBlocks[meta.zones.indexOf(d.zone)];
    const at = block[block.length - 1].type === 'travel' ? block.length - 1 : block.length;
    block.splice(at, 0, d);
  });

  // Steps whose level has passed but that are not done yet (for example training) are due now.
  // Level 1 setup steps come first, outside the zones. Without data they count as done after level 5.
  const allExtras = extraSteps(meta, lvl);
  // Order: professions, must-do quests (free bags first), then buying and selling.
  const startOrder = { prof: 0, must: 1, money: 2, gear: 3 };
  const startSteps = [...allExtras.filter(s => s.start), ...mustStart]
    .map((s, i) => ({ ...s, i, group: null, done: s.done != null ? s.done : lvl > 5 }))
    .sort((a, b) => (startOrder[a.type] ?? 9) - (startOrder[b.type] ?? 9) || a.i - b.i);
  const bagStep = bagVendorStep(meta, realm);
  const extras = [...allExtras.filter(s => !s.start), ...(bagStep ? [bagStep] : []), ...classTrainingSteps(meta, realm), ...dungeons.filter(d => !fits(d))]
    // Dungeons are optional: they stay in their zone instead of moving up as "due now".
    .map(s => (s.done === false && !s.wait && s.level <= lvl && s.type !== 'dungeon' ? { ...s, now: true } : s))
    .sort((a, b) => a.level - b.level);
  const route = [...startSteps];
  // Every step belongs to the zone it falls in (group = zone index), so the route can fold by zone.
  zoneBlocks.forEach((block, idx) => {
    route.push(...block.map(s => ({ ...s, group: idx })));
    const nextEntry = idx + 1 < zoneBlocks.length ? zoneBlocks[idx + 1][0].level : Infinity;
    while (extras.length && extras[0].level < nextEntry) {
      const s = extras.shift();
      route.push({ ...s, group: idx, done: s.done != null ? s.done : (!s.now && s.level < lvl) });
    }
  });
  route.push(...extras.map(s => ({ ...s, group: zoneBlocks.length - 1, done: s.done != null ? s.done : s.level < lvl })));

  // "Now" steps belong right before the first step that is not done.
  // They stand on their own at the top of the open steps, outside any zone.
  const nowSteps = route.filter(s => s.now).map(s => ({ ...s, group: null }));
  const rest = route.filter(s => !s.now);
  const firstOpen = rest.findIndex(s => !s.done);
  const at = firstOpen < 0 ? rest.length : firstOpen;
  const ordered = restedXpFilter([...rest.slice(0, at), ...nowSteps, ...rest.slice(at)], meta).filter(s => !QUEST_STEPS.has(s.type));
  const current = ordered.findIndex(s => !s.done);
  return ordered.map((s, i) => ({ ...s, current: i === current }));
}

// The next few open steps, for the character cards.
function nextSteps(c, meta, level, count = 2) {
  return buildRoute(c, meta, level).filter(s => !s.done).slice(0, count);
}

function routeLine(s) {
  const lvl = s.level != null ? `<span class="text-slate-500 w-8 shrink-0 text-right">${s.level}</span>` : '<span class="w-8 shrink-0"></span>';
  const unchecked = s.checked === false ? ' <span class="text-xs text-amber-400">(not checked)</span>' : '';
  const box = s.type === 'zone' && s.zoneIdx != null
    ? `<input type="checkbox" ${s.done ? 'checked' : ''} onclick="event.stopPropagation()" onchange="toggleZoneDone(${s.zoneIdx}, this.checked)" class="mt-1 rounded bg-slate-800 border-slate-700 text-amber-500 focus:ring-0">`
    : '<span class="w-4 shrink-0"></span>';
  const arrow = s.fold ? '<span class="route-arrow text-slate-500 shrink-0">▸</span>' : '';
  const row = `
    <div class="flex items-start gap-2 py-1.5 px-2 rounded ${s.current ? 'bg-amber-500/10 border border-amber-500/40' : ''}">
      ${box}${lvl}
      <span class="shrink-0">${ROUTE_ICONS[s.type] || '•'}</span>
      <span class="text-base leading-relaxed ${s.done ? 'text-slate-500 line-through' : s.type === 'zone' ? 'text-slate-100 font-semibold' : 'text-slate-200'}">${s.text}${unchecked}</span>
      ${arrow}
    </div>`;
  if (!s.details) return row;
  // A dungeon folds: one line, and its quests when opened.
  return `<details class="route-fold"><summary class="list-none cursor-pointer">${row.replace('</div>', '<span class="route-arrow text-slate-500 shrink-0">▸</span></div>')}</summary>
    <div class="pl-20 pr-2 pb-2 text-slate-300">${s.details}</div></details>`;
}

// Folds the steps by zone: the zone is one line, its steps (and dungeons) open below it.
// The zone you are in (and the one with the current step) starts open. Steps outside any zone stay on their own.
function routeBlocks(steps, route) {
  const blocks = [];
  steps.forEach(s => {
    const last = blocks[blocks.length - 1];
    if (s.group == null) return blocks.push({ steps: [s] });
    if (last && last.group === s.group) return s.type === 'zone' ? (last.header = s) : last.steps.push(s);
    const header = s.type === 'zone' ? s : route.find(r => r.type === 'zone' && r.group === s.group);
    blocks.push({ group: s.group, header, steps: s.type === 'zone' ? [] : [s] });
  });
  const here = blocks.find(b => b.header && !b.header.done);
  return blocks.map(b => {
    if (!b.header) return b.steps.map(routeLine).join('');
    if (!b.steps.length) return `<div class="mt-2">${routeLine(b.header)}</div>`;
    const open = b === here || b.header.current || b.steps.some(x => x.current);
    // Two parts per zone: tips for the whole zone, then the steps with a level, lowest first.
    const general = b.steps.filter(x => x.level == null);
    const byLevel = b.steps.filter(x => x.level != null).sort((x, y) => x.level - y.level);
    // Each part folds on its own (open by default), with how many steps it holds.
    const part = (title, list) => list.length
      ? `<details class="route-fold" open><summary class="list-none cursor-pointer text-xs font-semibold uppercase tracking-wider text-slate-500 pt-2 pl-2">
           <span class="route-arrow">▸</span> ${title} (${list.length})</summary>${list.map(routeLine).join('')}</details>` : '';
    return `<details class="route-fold mt-2" ${open ? 'open' : ''}>
      <summary class="list-none cursor-pointer">${routeLine({ ...b.header, fold: true })}</summary>
      <div class="pl-4">${part('General', general)}${part('By level', byLevel)}</div></details>`;
  }).join('');
}

// The character's macros from the beta (guide.json macros.<class id> plus macros.all), ready to copy on live.
function macroCard(meta) {
  const M = GUIDE.macros || {};
  const list = [...(M[meta.id] || []), ...(meta.bank ? [] : (M.all || []))];
  if (!list.length) return '';
  const esc = t => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  return `<details class="rounded-xl bg-slate-900/60 border border-slate-800 mb-2"><summary class="cursor-pointer p-3 text-base font-semibold text-slate-200">⌨ Macros (${list.length})</summary>
    <div class="px-4 pb-3 space-y-2">${list.map(m => `<div><div class="text-base text-slate-200"><b>${m.name}</b>: ${m.what}</div>
      <pre class="mt-1 p-2 rounded bg-slate-950 text-sm text-emerald-200 whitespace-pre-wrap select-all">${esc(m.body)}</pre></div>`).join('')}
    <p class="text-xs text-slate-500">${M.note || ''}</p></div></details>`;
}

let showDoneRoute = false;

// RestedXP mode (guide.json restedXp.until): the RestedXP addon shows the quest steps up to that level,
// so the route keeps only professions, money, bags and gear there. On by default; saved per browser.
const RXP_KEY = 'wow_rxp_mode';
const RXP_KEEP = ['zone', 'prof', 'money', 'bank', 'gear', 'camp', 'shop', 'fish'];
function restedXpMode() {
  try { return localStorage.getItem(RXP_KEY) !== 'off'; } catch (e) { return true; }
}

function setRestedXpMode(on) {
  try { localStorage.setItem(RXP_KEY, on ? 'on' : 'off'); } catch (e) {}
  renderActiveLevelingCategory();
}

// A step goes when its level is below the limit; a step without a level goes when its whole zone is.
function restedXpFilter(route, meta) {
  const until = (GUIDE.restedXp || {}).until;
  if (!until || !restedXpMode()) return route;
  const zoneTop = g => parseInt(String((GUIDE.zones[meta.zones[g]] || {}).levels || '').split('-').pop(), 10);
  return route.filter(s => RXP_KEEP.includes(s.type) || s.keep
    || (s.level != null ? s.level >= until : !(s.group != null && zoneTop(s.group) <= until)));
}

function toggleDoneRoute() {
  showDoneRoute = !showDoneRoute;
  renderActiveLevelingCategory();
}

function renderRoute(container, c, meta, level) {
  const route = buildRoute(c, meta, level);
  const until = (GUIDE.restedXp || {}).until;
  const done = route.filter(s => s.done);
  const open = route.filter(s => !s.done);
  const carry = meta.bank ? [] : carryList(meta, REALM_ROSTERS[currentRealmKey]);
  const carrySlots = carry.reduce((t, [, , slots]) => t + slots, 0);
  container.innerHTML = `
    ${carry.length ? `<details class="rounded-xl bg-slate-900/60 border border-slate-800 mb-2"><summary class="cursor-pointer p-3 text-base font-semibold text-slate-200">🎒 Always carry: about ${carrySlots} bag slots</summary>
      <p class="px-4 pb-3 text-base text-slate-300 leading-relaxed">${carry.map(([name, qty, slots]) => `${qty > 1 ? `${qty} ` : ''}${name} (${slots})`).join(' · ')}</p></details>` : ''}
    ${macroCard(meta)}
    ${until ? `<label class="flex items-center gap-2 text-sm text-slate-400 cursor-pointer pb-1"><input type="checkbox" ${restedXpMode() ? 'checked' : ''} onchange="setRestedXpMode(this.checked)" class="rounded bg-slate-800 border-slate-700 text-amber-500 focus:ring-0"> RestedXP guides my quests until level ${until}: show only professions, money and gear there</label>` : ''}
    ${done.length ? `<button onclick="toggleDoneRoute()" class="text-sm text-slate-400 hover:text-amber-300">✓ ${done.length} steps done · ${showDoneRoute ? 'hide' : 'show'}</button>` : ''}
    ${showDoneRoute ? routeBlocks(done, route) : ''}
    ${routeBlocks(open, route)}
    <p class="text-xs text-slate-500 pt-2">${Object.entries(ROUTE_ICONS).filter(([k]) => !QUEST_STEPS.has(k)).map(([k, v]) => `${v} ${{ zone: 'zone', choice: 'two ways', camp: 'camp', shop: 'buy', fish: 'fishing', quest: 'quest hub', pickup: 'dungeon quest to take', must: 'must-do quest', tip: 'optional', class: 'class tip', skip: 'skip', dungeon: 'dungeon', prof: 'profession', gear: 'gear', money: 'money', travel: 'travel', bank: 'bank' }[k]}`).join(' · ')}</p>`;
}

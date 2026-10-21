# Project Status & Handoff

**Read this first.** Any AI agent picking up this project starts here, and adds an entry to the
Session Log at the end of its session. Architecture rules live in `AGENTS.md` and `GEMINI.md`;
user-facing instructions live in `README.md`.

Last updated: 2026-10-16

---

## 0. Start here (handoff 2026-10-16)

**Money first (user, 2026-10-19):** professions are not only about leveling fast with few materials; they must
make money. More materials is fine if the crafts sell. The first month on live: every character is poor, so focus
on making money (craft to sell, flip on the AH with Banka) without flooding the market; big costs later (mount
100g, training). Profession paths count sales with a market limit (forever_profs.py SALE_WEIGHT 1, MARKET_CAP 10
per item, strict prices, sale at most 2x material cost).

**Direction (user, 2026-10-15/16):** quests in game come from the **Polestar** addon (free, GPL-3.0, Horde 1-60
guides, profession guides; user tests it on Sveti). Our addon is the **high-level planner for the whole team**:
next dungeon chain with its quests, profession steps and materials, character rotation by rested XP, Legacy
points, and a **bank character** (Banka) that receives everyone's materials and trades on the AH. The browser
dashboard stays but gets no new work ("game first"). **Restated 2026-10-17:** the addon does not replace quest addons; it
gathers information from other addons and our data for **professions and dungeons** and gives **high-level
guidance per character**, flexible, informative, with **no unnecessary information**. Our older full-quest version is tag `own-3.31.0` (since 2026-10-20 only in `personal/backups/history-backup.bundle`: `git clone personal/backups/history-backup.bundle /tmp/old -b history-backup`) and still
lives on as the Quests window addon.

**Three addons (`make addon` installs every folder under addon/):**
| Folder | Version | What |
|---|---|---|
| `addon/WoWForeverLeveler/` | 3.38.4 | **Core.** Data collection (WoWForeverLeveler.lua: character state, quests + journey log, recipes, trainers, vendors, prices, rested XP), saved variables (unchanged names, so beta data stays), Plan.lua (generated), fonts (Noto Sans, OFL), and **all shared window code** in UI.lua exported as global `WFL` (window, rows, check boxes = TomTom arrow + Blizzard quest tracking, minimap icon + menu, item tooltip "WFL:" lines, bag/bank counting, dungeon helpers). Without a window addon: no window, data still recorded. |
| `addon/WoWForeverLeveler_Planner/` | 2.5.0 | **The window the user uses.** Planner.lua registers tabs via `WFL.RegisterTabs`. Leveling characters: **Next \| Dungeons \| Professions \| Team**; bank character: **Next \| Market \| Team** (tabs hide via `tab.visible`). |
| `addon/WoWForeverLeveler_Quests/` | 1.0.1 | The old quest window (Now / Route / Materials, Do next, zone routes). Registers nothing when the Planner is loaded or enabled (both gave 7 tabs). |

**Planner, what each tab does** (design = `mockups.html`, http://localhost:8765/mockups.html: one window with a
"logged in as" switch over real data for Lovac 25, Vestac 18, Sveti 4 and Banka, plus a "How it fits together"
panel; refresh its data with `make guide` and `python3 scripts/mockup_state.py`):
- **Next:** per area the step **Now** and the one **After**, updating live. Dungeons (DungeonActions: per quest
  chain its first open quest, hand in / finish / take, starts in your zone first, then "Run X", or "Reach level N"),
  main professions (Plan.lua `craftSteps`, capped at the trainer rank; gatherers: gather / train at cap), Team
  (keep playing or switch to the most rested; bank characters never suggested), Legacy (level 25/45/60, crafting
  150/225/300). Bank Next: Market (best sell / buy / craft), Mail (live via HasNewMail), Team.
- **Dungeons:** next 3 stops with open quests you can still run (dungeon chains such as "Dungeon chain 1" = RFC >
  RoL > WC as one stop); each dungeon: entrance with arrow, then quests grouped by chain start ("then ..." for the
  next quests, dungeon quests marked) with NPC, zone and spot. No zone quests (Polestar does those).
- **Professions:** now/after per profession + the current skill bracket's materials as have / need bars.
- **Team:** rotation (planned names only, Plan.lua `teamNames`) + team materials for every crafter's current step.
- **Market (bank only):** Sell now (stock above crafters' needs, AH x0.95 >= 1.5x vendor), Buy cheap (needed and
  <= 80% of usual), Craft to sell (product vs materials at AH prices), Hold (< 70% of usual). Prices: Auctionator
  in-game API by item ID, else Plan.lua `prices` (last + usual = median of Sync scans). Beta data is thin (13
  scans): tips are hints until live has 1-2 weeks of daily scans.
- **Item lines:** hover = the game's item tooltip + ours; Shift- or Ctrl-click puts the name into the focused box,
  else the AH search box, else chat.
- **Bank character:** Plan.lua `bank` (guide.json bank name: Banka) or the minimap
  menu switch "This character is the bank" (WoWForeverLevelerUI.bankChars[name-realm]; the user set Postarka for a test).
- **Stock ("have"):** each character counts its bags + bank for team materials (Plan.lua matNeed) into
  WoWForeverLevelerUI.have[name-realm] 2 s after BAG_UPDATE_DELAYED / MAIL_CLOSED / BANKFRAME_CLOSED and at login.
  **Fixed in 3.34.2:** the Forever client has only C_Item.GetItemCount (before that nothing was counted).

**Data pipeline for the Planner (Sync runs it; by hand: `make routes` = build_routes + build_guide):**
- `scripts/questie_db.py` decodes the **QuestieDB addon's Forever database** (TOC metadata CBOR): quests, NPC/object
  spawns, items. `scripts/build_routes.py` -> `data/routes.js`: zone routes (Quests window), `_givers`,
  `_classes`, `_chains` / `_chainPaths` (every quest before a dungeon quest, e.g. Forgotten Pools > Stagnant Oasis
  > Altered Beings > Hamuul Runetotem > Nara Wildmane > Leaders of the Fang), `_entrances` (QuestieDB
  support/Forever/Zones/dungeons.lua base table).
- `scripts/build_guide.py` `addon_plan()` -> Plan.lua (+ `data/addon_plan.js` for the browser): pickups with
  `chain` and class masks, runs with `entrance`, dungeonChains (guide.json), craftSteps, matPlan (raw materials
  per profession and bracket, one craft per point +15%, Classic recipes, not checked), matNeed, prices,
  bank, teamNames, routeChoices.
- **Forever profession paths (2026-10-16, replaces the Polestar counts):** `scripts/forever_profs.py` (by hand,
  fetches 45 pages; `--cached` rebuilds from data/forever_pages/, not in git) reads forevervsclassic.com
  /professions/<prof>?rank=<apprentice|journeyman|expert|artisan|300> into `data/forever_recipes.json` (every
  recipe: learn, colours, source, reagents, makes, status), applies the game's trainer scans (learn skill only,
  colours stay: checked against the save file's recipe difficulty), and builds `data/forever_profs.json`: per
  profession a point-by-point cheapest path 1-300 (cost = materials at auction price or tier value, crafted
  reagents priced by their materials, / skill-up chance; vendor/quest recipes x2, drops x5; cooldowns, "Not yet
  confirmed" and reagents named "Item #" left out; a reagent made by the same profession only from its skill)
  and the raw materials per bracket. build_guide uses it for matPlan (`src: "Forever"`) and craftSteps (also
  First Aid and Cooking paths in the file, not wired yet). Steps from vendor/quest/drop recipes carry `source`.
  Planner/mockups count crafts left from the step count. Weak spots: 250-300 leans on vendor/drop recipes (some
  may be Alliance-only or event items: no faction on the list page); Tailoring 150-225 uses Long Silken Cloak
  (1576 Silk Cloth).

**Confirmed 2026-10-15 17:18 (save file):** stock counting works (Lovac: Linen 31, Wool 10, Light/Medium
Leather 3); no "UI error" lines in the log.

**Not seen in game yet (ask the user for a screenshot: Cmd+Shift+3 saves to ~/Desktop; scale with
`sips -Z 1800` into the scratchpad and Read it):** Market with real stock,
Shift/Ctrl-click insert into the AH search box (Blizzard AH vs Auctionator box name may need adjusting), the
4-tab layout after the Quests fix, the bank switch's tabs.

**Open / next ideas:** buffs list (potions, elixirs, food the team can make, useful for the class; data from
Polestar_Codex recipes), book
quest (HandyNotes Books: 10/20/30 Tomes), The Riverglades (no quest data anywhere until launch 2026-11-04: then update QuestieDB, run
`python3 scripts/zone_quests.py` and `make routes`), group 3 professions double Alchemy/Engineering/Blacksmithing.

**After an addon change:** syntax check (lupa: `load()`; luaparser also works), `tests/addon_fakegame.py` and
`tests/addon_fakegame.py planner` (needs the lupa venv, see its docstring; look for "panel error" / "UI error";
the planner run also shows the bank view), `make test`, bump the `.toc` version(s), `make addon`, tell the user to
`/reload` (new files or new addons need a full game restart). Drawing errors land in WoWForeverLevelerLog as
"UI error ...". Keep addon text ASCII/Latin-1.

**User style:** ELI5 output style (short sentences, simple words, max 2 options with a recommendation). Commit only
when the user says "commit". Read the save file and addon log yourself. Prefer the user's own game data over
web/AI answers. Likes mockups in the browser first, then the in-game build.

---

## 1. What this project is

A leveling, profession and money system for 9 Horde characters plus a bank character in
**World of Warcraft: Forever** (Blizzard's "Classic+"). Beta 2026-09-17 to 2026-10-21, name reservation
2026-10-27 to 11-03 (3 names), launch **2026-11-04**, raids open 2026-12-09.

- **Player's plan:** PvP ruleset, EU. Create all 9 characters + the bank on launch day; play Group 1
  ("Play first") first. First gold goal: level 40 mount (100 gold until Blizzard announces the price).
- **Names** (WoW Forever needs first + last name; only the full name must be free in the region):

  | Group | Class | Name | Plan professions |
  |---|---|---|---|
  | 1 (Play first, reserve these 3) | Tauren Hunter | Kaspin Lovac (was Lovac Kasapin, name rules, 2026-10-16) | Skinning + Herbalism |
  | 1 | Orc Warlock | Vestac Zla | Tailoring + Enchanting |
  | 1 | Undead Paladin | Pally Rifle (was Pala Rifle, 2026-10-16) | Mining + Skinning |
  | 2 | Undead Priest | Nemrtvi Svestenik | Skinning + Mining |
  | 2 | Troll Shaman | Sveti Munja | Alchemy + Leatherworking (4th in rotation, 2026-10-14) |
  | 2 | Orc Warrior | Konan Unistitelj (was Konan Ratnik, 2026-10-16) | Mining + Blacksmithing (5th, fixed 2026-10-16) |
  | 3 | Undead Mage | More Vatre | Skinning + Herbalism |
  | 3 | Undead Rogue | Ubica Propalitet | Mining + Engineering (6th, fixed 2026-10-16) |
  | 3 | Skyborne Druid (was Tauren, 2026-10-15) | Travar Vracevgajski (was Travar Baum, 2026-10-16) | Alchemy + Engineering |
  | bank | Tauren Warrior (female) | Banka Posta | none; stays in Thunder Bluff |

  No spare first names (removed 2026-10-16): if a name is taken, the user picks a new one.
  **Fixed (user, 2026-10-16):** the first 6 in this order: Lovac, Vestac, Pala, Sveti, Konan, Ubica. They cover
  all 6 crafting professions (18 Legacy points, once per account); the ore crafters mine their own ore (Pala's
  is extra). **Open until the user has played on live:** Nemrtvi, More, Travar (their profs in guide.json are
  placeholders).

- **Parts:**
  - `data/guide.json` - the single source of truth (see section 2). `make guide` builds `guide.md`,
    `data/guide.js`, `addon/.../TrackedItems.lua` and `addon/.../NPCList.lua` from it.
  - `index.html` + `js/` - the local dashboard, http://localhost:8765/. Started by the Dock app
    `Launchers/WFL Dashboard.app` (click = start + open or focus the Chrome tab; Quit = stop the server).
  - `addon/WoWForeverLeveler/` - in-game addon, now **3.21.0** (section 0). `make addon` installs it into every
    local WoW client folder. New files in the `.toc` need a full game restart, not `/reload`.
  - `scripts/` - sync pipeline and dashboard server (`server.py`, port 8765; port 8000 is the Battle.net
    OAuth callback). `personal/history.sqlite` keeps full history (daily backups in `personal/backups/`, not in git).
  - `tests/` - `make test` (Node dashboard tests + Python script tests). `make launch-check` checks the setup.

## 2. Data flow and where things live

```
WoW client (addon) --SavedVariables on logout or /reload--> scripts/build_roster.py
    --> personal/history.sqlite (+ daily backup)
    --> data/roster.js, prices.js (+ SELL_PRICES), trainers.js, vendors.js, npcs.js
Auctionator.lua (same SavedVariables folder) --scripts/auctionator.py--> price_snapshots, one row per
    item per day (Auctionator keeps one lowest price and amount per day; names via our addon's item IDs)
Interface/AddOns/ForeverLoot + DFLDungeonJournal data files --scripts/dungeon_addons.py--> data/dungeons.js
    (Horde dungeon quests: giver + coordinates, level, chain start, rewards; not in git, rebuilt every sync)
data/guide.json (+ zone_quests.js, npcs.js, dungeons.js) --scripts/build_guide.py--> guide.md, data/guide.js,
    TrackedItems.lua, NPCList.lua, Plan.lua (the in-game window's data)
scripts/zone_quests.py (by hand) --> data/zone_quests.js: Forever Horde quests per route zone (forevervsclassic.com)
    with givers and hubs (classicdb.ch)
scripts/trainers_db.py (by hand) --> guide.json trainerDB: Horde profession trainers with map positions (ClassicDB)
scripts/server.py also watches the save file and syncs by itself (auto sync, section 4)
Dashboard "Sync" --> server.py /api/sync: waits up to 60 s for a new save file, then runs
    build_guide, build_roster, quest_report
```

Every key carries the **game client** (`classic_beta|...`) so beta and live data never mix. Checked 2026-10-12:
the dashboard reads prices, vendor prices, class trainer costs and bag vendors only for the realm's own client
(no fallback to beta). Beta prices are not valid for live: ignore them after launch. Real
characters match the plan by **first name** (`plan_ids()` in build_roster.py), else by class.

**`data/guide.json` keys:** `characters` (plan: zones, zoneNotes, profs, name/lastName, order, start),
`bank`, `zones` (levels, hubs, do, gather, skips), `professions` (milestones, levelWith, recipes, usedBy),
`money` (mountGoal, signals, phases, watch lists, `methods`), `gear` (per character id), `npcs` (Classic
city trainer list), `merchantsFavor`, `launchChecklist`, `camping`, `races`, `dungeons`, `synergies`.

**Dashboard files (`js/`, plain scripts sharing globals, loaded in this order):** app (tabs, `showView`,
plan characters), professions (`metaFor`, supply chains, profession tab), characters (cards, character
page, zone progress), money (prices, market signals, `methodNumbers`), auction (Buy & Sell page, craft
ideas), recipes, camping, trainers, launch, route (`buildRoute`: the level-ordered route), ahpages (Money
methods, Mount gold, Merchant's Favor pages), charmoney (per-character Money tab: keep / mail / vendor /
hold / sell), legacy (Rested XP and Legacy point cards above the character grid).

## 3. Important facts learned (do not relearn these)

- **Forever profession guides compared (2026-10-19):** every guide found is computed from the same beta client
  data (Wowhead Forever / datamine, builds 1.60.1.70291-70450), none is player-tested, and no reviews or Reddit
  threads exist yet. They disagree a lot: crafts 1-300 per profession endgametools.com 419-625 (Tailoring 474),
  ours 395-583 (Tailoring 411); classicwowforever.com Tailoring 1-150 uses 792 Silk + 830 Mageweave (bolts as
  skill-ups), ours 406 Linen + 648 Wool + 128 Silk. All assume the Classic skill-up curve (not measured in
  Forever). Claims: 209 of 234 Classic recipes changed, most grey ~35 points sooner; colours above 225 likely to
  move before launch; one guide says bolts/stones/leather conversions give no skill. Our data: Bolt of Silk,
  Bolt of Runecloth, Medium/Heavy Leather have grey = learn (no range). Many "Same" recipes look like that too
  (Simple Black Dress): it means the site has no Forever range. forever_profs.py (2026-10-19): no range +
  conversion (Bolt of ..., Light/Medium/Heavy/Thick/Rugged Leather) = no skill-ups; other no-range recipes keep
  +5/+15. Holiday patterns are left out. Recording skill-ups in game: skipped (user asked; the addon already
  saves each known recipe's colour, which is the useful part). Sources: classicwowforever.com/professions/<prof>/leveling, endgametools.com/en/wow-forever/
  leveling, forevervsclassic.com/professions.

- **The TomTom arrow follows Polestar quests** because Polestar's "Mirror to TomTom" (Guide > Arrow & routes >
  Other waypoints, nav.tomtom) is on by default. Our addon sets the arrow only on a selection. Fix: the user turns
  that Polestar option off (Polestar keeps its own arrow).
- **Rested XP of other characters** = the last value saved while playing (GetXPExhaustion, IsResting) + 5% of
  a level per 8 h (a quarter outside an inn or city). **At PLAYER_LOGOUT the Forever client reports 0 and "not
  resting"** (all beta characters on 2026-10-19 were saved that way); since core 3.36.3 the logout keeps the
  previous values, and PLAYER_UPDATE_RESTING / UPDATE_EXHAUSTION save them while playing. Log out in an inn or a city, and log each character in once
  so the save has it. The character you play uses the live value.
- **Lua test environment:** `/tmp/wfl-lua` disappears when macOS cleans /tmp; lupa 2.8 is broken (no
  LuaRuntime). Rebuild: `python3 -m venv /tmp/wfl-lua && /tmp/wfl-lua/bin/pip install "lupa==2.4"`.

- **Character creation is throttled (beta, 2026-10-16):** after 9 new characters in about 6 minutes the game said
  "creation is throttled"; Banka could not be made. Wait time unknown (try again later). Launch day: create the
  ones to play first and the names that matter most first, Banka last.

- **Mount at level 40 (user, 2026-10-16, from a web answer, not seen in game):** Apprentice Riding 80 gold +
  mount 20 gold = 100 gold. In guide.json `money.mountGoal` (training, mount, gold); route and Mount gold page
  show the split. Class mounts (Paladin, Warlock): cost still unknown.

- **Legacy crafting points are once per account (web check 2026-10-16, Icy Veins, Mobalytics, classicwowforever):**
  each of the 6 crafting professions pays 1 point at 150, 225 and 300 the first time any character reaches it
  (18 in total). A second character with the same profession earns no Legacy points. Gathering, Cooking,
  Fishing and First Aid pay nothing. So duplicate crafters (2x Alchemy, 2x Blacksmithing, 3x Engineering in the
  roster) only make sense for their goods, not for Legacy. Profession plan for groups 2-3 stays open until the
  user has played on live (ore is the bottleneck: 5 ore crafters, 2 miners; 4 skinners for 1 Leatherworker).

- **Forever professions differ from Classic (2026-10-16):** healing potions moved from Alchemy to **First Aid**
  (Minor, Lesser, Healing Potion from the trainer; Greater and up from drops). Own trainer scan: First Aid
  Minor Healing Potion at skill 1, Lesser 55, Healing 110; forevervsclassic.com says 55 / 85 / 135 (Wowhead data,
  12 Oct): not settled, trust the game scan. Forever Alchemy starts with Elixir of Minor Defense / Minor Strength.
  **Polestar's profession guides use Classic recipes** (its Alchemy starts with Minor Healing Potion), so
  data/polestar_profs.json is wrong where Forever changed recipes. Polestar_Codex has no recipe data.
  **Best source:** forevervsclassic.com/professions/<prof> (robots.txt allows): every recipe with skill colors
  (orange/yellow/green/grey), source (Trainer/Drop/Vendor/Quest), reagents (title="Item xN"), status
  (New/Changed/Same/Not yet confirmed). 9 professions incl. First Aid and Cooking.

- The WoW Forever client has **only modern APIs**: C_TradeSkillUI, C_AuctionHouse, C_Item. The Classic ones
  (GetTradeSkillLine, QueryAuctionItems, global GetItemInfo) are missing. An unknown event name throws and
  aborts the addon file, so events are registered defensively.
- `SetTrainerServiceTypeFilter` wants **true/false** on this client (Classic wants 1/0).
- `GetMoney()` returns 0 during logout, so gold is not saved at logout. `UnitLevel` can report 1 at logout,
  and PLAYER_LEVEL_UP fires before UnitLevel changes: the addon keeps the highest level (3.4.1).
- The beta client's interface number is **16001** (2026-10-08): the addon's `## Interface` must list it, or
  the game shows "incompatible". `make launch-check` now warns when the other addons share a number ours lacks.
- `IsTradeskillTrainer` does not exist on the Forever client; `GetTrainerServiceInfo`'s 2nd value is the
  status ("available"), not the rank. `UnitName`'s 2nd value is the last name.
- The game writes the save file a few seconds after `/reload`; a Sync clicked too early reads the old
  file. The server now waits for a new file (`wait_for_save`).
- Full auction download (`C_AuctionHouse.ReplicateItems`) works: ~64,000-82,000 listings in ~15 s,
  once per 15 minutes.
- Blizzard API: Classic profile API has **no professions**; Classic auction API lists houses but returns 404
  for prices. WoW Forever namespaces returned 403 on 2026-09-28 - `make launch-check` retests them.
- Forever changes: Healing Potions moved to First Aid; food gives Well Fed +5% XP; Tauren Cultivation grows
  a bonus herb node; Linen Bag needs Tailoring 5; many recipes turn grey ~25 points earlier than Classic;
  Enchanting uses Mote of Magic (1 Strange Dust -> 3 Motes); dungeon mob XP is lower but first-run dungeon
  quest XP is higher; every race learns one gathering profession from a starting-zone quest; Sen'jin
  Village has an Enchanting trainer; Merchant's Favor currency (Booty Bay crates) buys spec gear recipes.
- **Free gathering profession:** each starting zone has a quest whose reward is a book that teaches one gathering
  profession (Mining for Dummies / Wild Harvest / Pelt Collecting for Beginners): Tirisfal Marla's Last Wish
  (level 3, seen by the user), Mulgore A Humble Task (level 1), Durotar Galgar's Cactus Apple Surprise (level 1)
  (forevervsclassic.com). Rule (user, 2026-10-12): train Skinning at once at the Junior trainer (skins from the first kill), take the
  Mining book (Pala on the beta did it the other way round).
- **Junior trainers** stand in the starting zones (mobalytics). Deathknell has Junior Mining (Walter Mason) and
  Herbalism (Florence Nightshade) (addon scan); No First Aid/Cooking/Fishing trainer in Deathknell (user, 2026-10-12):
  they are in Brill and at Brightwater Lake. AI chat answers about this were wrong twice: trust the game data.
  Beta scan: Journeyman Cooking needs skill 50 and no level; Journeyman Fishing needs level 10.
- **Forever vendor prices are far below Classic** (addon 3.7.0 scan, Deathknell): Mining Pick and Skinning Knife
  10c (Classic 81-82c), gathering bags 25c, Refreshing Spring Water and bread 5c each (sold in 5s). Water and
  bread stack to 20. forevervsclassic.com has Forever quest data per zone (levels, new/changed quests, rewards)
  and works in the browser pane; Wowhead does not (region block).
- Pala's first new Forever quests (likely the Paladin story): A Difficult Path, Rediscovering the Light (level 2),
  Continue Your Training, A Light in the Darkness, Coming to Terms (level 4), all in Deathknell.
- Undead Paladins start in Deathknell like other Undead (user, beta 2026-10-12). RestedXP's first step deletes
  the Hearthstone for bag space; the first innkeeper gives a new one free when you bind.
- Beta trainer scan (2026-10-11): Apprentice Fishing costs 90c (not free); the Basic Campfire Kit is a Cooking
  trainer recipe at skill 20 for 1s (web guides said it comes with Cooking at 1). Secondary trainers stand in
  Bloodhoof Village / Razor Hill / Brill, Fishing at a lake, not in the first camp.
- Beta bug (video): mail with many full stacks can get lost. Send a few stacks per mail.
- Disenchanting matches the Classic odds: armor gives mostly dust (user's test: 10 Brown Linen Pants ->
  12 Strange Dust + 1 Lesser Magic Essence), weapons mostly essence.
- **Sources:** Wowhead is blocked in the user's region. **classicdb.ch works in the browser pane** (not
  with WebFetch): quest lists per zone (`/?quests=1.17`), items per weapon type (`/?items=2.<subclass>`),
  Listview data in the page scripts; quest `type:1` = Elite, `81` = dungeon. Warcraft Wiki mixes retail and
  Classic data. Many "WoW Forever gold" sites are gold-seller pages with made-up numbers.
- YouTube transcripts: read them in the browser pane by hooking the player's timedtext request, or by
  playing at 2x with captions on (see the 2026-09-30 session).
- **Other addons (2026-10-01):** "Forever Dungeon Journal" (CurseForge, shown by Venruki) lists every
  dungeon's bosses, loot and quests, marks which quests you have and pins quest givers on the map. The user
  can just use it. Auctionator works on the Forever client (Gillee uses it) and shows craft cost vs. sale
  price in game. Auctioneer is not shown working on Forever.
- **Video claims, not checked (2026-10-01, Gillee, Loru, Ceedsy):** Lesser Magic Wand 11.3 DPS and Greater
  Magic Wand 17.5 DPS in Forever (Classic: 5.7 / ~11); Enchanting 1-10 with ~10 Novice's Practice Wands;
  gathering skill capped at 75 in starting zones; Mining +% health, Skinning more damage to beasts and
  dragonkin, Herbalism small resistances, Tailors get more cloth from humanoids; Blacksmith "repair all"
  cooldown (8 h, rank 2: 4 h) and belt buckle; Enchanters enchant own rings/neck/off-hand, make relics,
  maybe enchant scrolls; Alchemists get longer elixirs/flasks; Leatherworking is the weakest. Arcane Salvager
  (Enchanting camp object, needs Enchanting ~225) gives a second disenchant roll ~10-20% of the time.
- The user's addon log is in the save file (`WoWForeverLevelerLog`). Read it yourself after the user runs
  `/reload`; the user cannot easily copy chat text.

## 4. Done

- **Dashboard layout:** top tabs 🚀 Launch (hides once every step is done) / 👥 Characters /
  ⚒ Professions (Trainers, Recipes, Camping, Merchant's Favor) / 🏦 Auction House (Buy & Sell, Money
  methods, Mount gold).
- **Characters:** real characters plus grey "to create" cards for planned ones (Play first / Play later /
  Bank). Each card shows the next 2 route steps. Character page tabs: 🧭 Route, ⚒ Professions, 💰 Money.
- **Route** (`js/route.js`): one list in level order: zone + hubs, class quest notes, elite skips (ClassicDB
  links), gathering tips, a 💰 sell/keep/mail line per zone, training tiers (tick themselves from the skill
  cap), the current skill step with materials ("make about 15 Bolt of Woolen Cloth, buy 45 Wool Cloth"),
  money methods, the mount, and 🗡 weapon/wand upgrades. Overdue steps move to the top. Zone progress
  follows the level (a hand tick wins).
- **Money:** per-character Money tab (keep for own craft / mail to a real crafter / vendor / hold below the
  usual price / sell on AH, from own prices and vendor prices), money methods with live profit (Brown Linen
  Pants shuffle with observed disenchant odds; Heavy Copper Mace with vendor prices and a 20s cost limit),
  crafts with profit now, mount gold per character, money phases.
- **Professions:** Trainers page (Classic city trainer list merged with trainers and recipe vendors the addon
  saw, with map positions; "only my professions" counts real characters' professions), Recipes, Camping,
  Merchant's Favor (how to get it, which set each crafter makes for whom).
- **Launch checklist:** countdown, steps before launch / launch day / first week; group-creation steps tick
  themselves from live realm data. 🧩 Addon list (guide.json `addons`: needed / optional / not needed) with ✓
  from the synced addon folders; `make launch-check` warns about missing needed addons. The user does not run
  launch-check: they say "launch check" and Claude runs it.
- **Addon 3.0.0:** character state, quests, recipes, trainer and vendor scans (once a day), trainer/vendor
  positions, "Trainers to visit" window (`/wfl todo`, opens itself in a city), saved log. Its own auction
  scan is gone: **auction prices come from Auctionator** (see section 2). The addon saves item name -> ID
  and vendor sell prices for every item Auctionator has seen, plus Auctionator's realm key.
- **Route folds by zone:** each zone is one line; opening it shows its steps. The zone you are in starts open.
  Due-now steps stay on top, outside the zones.
- **Skill needed in brackets:** guide.json `professions.<herb|mine|skin>.nodes` (Classic values, not checked);
  `withSkillNeeded()` in js/route.js adds "(15)" after each herb/ore name and "(beasts 20-30, skill 100-150)"
  after each leather in the gathering lines; amber when above the character's skill.
- **Dungeon plan line (2026-10-09):** each dungeon line says "Run at about A-B" and its fold starts with a plan:
  collect the quests from level X (cities with counts), run levels DPS / healer / tank (rule of thumb: 30% /
  35-45% / 50-60% of the level range; RFC 13-18 gives 15 / 15 / 16, Classic bosses are 16), full quest XP
  until the highest fitting quest level + 5, total quest XP (DFL rewards), and how to reach cities off the
  route (guide.json `dungeons.cityTravel`, e.g. the Undercity zeppelin). The user wants far-city quests kept:
  they open new cities and flight paths.
- **Route review (2026-10-08):** zone folds split into General / By level (each foldable, sorted by level).
  Weapon steps that are not an upgrade over a sure weapon are `hidden` in guide.json (casters: wands only);
  one Forever DPS per weapon; crafted lines name the crafter ("ask Vestac (Enchanting 10)"); Practice Wand and
  Brown Linen Pants at level 5; Warlock/Paladin learn a class mount; no "needs a group" under level 10.
  Dungeons never become "due now"; a capped profession says "train the next rank first".
  Money: vendor-or-AH uses the usual 7-day price (one 9c Light Leather listing had flipped it to vendor);
  auctionator.py takes a past day's highest low price. Questie + QuestieDB are needed addons.
- **Weapons (2026-10-08):** guide.json `gear` merges our Classic quest rewards with the Forever weapon paths
  from classicwowforever.com/weapons (per class + race: dungeon drops "if you are lucky", vendor and crafted
  weapons, Forever DPS; 122 added, 20 DPS values updated; source `classicwowforever.com`, not checked).
  The hunter list keeps ranged only; level 1 starting weapons are left out. Raw list: re-read the site per
  class with race horde/<race> (the race in the link only applies after the page loads).
- **Weapon skills (2026-10-10):** guide.json `weaponSkills` (Forever class table from Warcraft Tavern; Horde
  masters Sayoc / Ansekhwa / Archibald match ClassicDB and Blizzard Watch). Forever changes: Hunters no maces
  or thrown, Rogues get 1H axes, Druids get polearms. Each route has one level 10 🗡 line (home city first);
  guide.md has the tables under Leveling Tips. Not checked in game.
- **Route choices + zone ticks (2026-10-12):** guide.json `routeChoices` (now 20-30: Kalimdor = Stonetalon +
  Ashenvale, or Eastern Kingdoms = Hillsbrad). `applyRouteChoices` in js/professions.js swaps the zones: hand
  choice (🔀 line in the zone, localStorage `wow_route_choice`) > the option with the newest quest turn-in >
  the plan. build_roster saves `questZones` (zone -> last turn-in time from the addon quest log); a route zone
  is done once a later route zone has the newest turn-in. Travel notes fall back to "Go to X" when the next
  zone changed.
- **Own route after level 20 (option B, 2026-10-12):** `scripts/zone_quests.py` (run by hand, a few minutes)
  reads the Forever Horde quest list per zone from forevervsclassic.com (guide.json `zones.<zone>.fvc`) and
  each quest's giver position from ClassicDB, and groups quests by hub (`zones.<zone>.hubCoords`, Classic map
  coordinates, radius 9; `hubAliases` for the Bulwark) -> data/zone_quests.js. Each zone shows 📜 one line per
  hub in level order ("Tarren Mill (22-34): 22 quests, 3 done · new in Forever: ..."), and 🏰 "Take for
  <dungeon>: quest (giver x, y)" for dungeon quests whose giver stands in that zone. The Riverglades has no
  quests on the site yet. New Forever quests have no ClassicDB giver: they count under "Other".
- **Target button + arrows (addon 3.10.0):** a secure button (off by default, `/wflp target` shows it; shift-drag to move) and a
  character macro "WFL Target" with /targetexact lines for the monsters of unfinished "slain" objectives in the
  quest log; updated out of combat only (waits for PLAYER_REGEN_ENABLED). Panel rows with ➜ are clickable:
  TomTom arrow (optional addon) to trainers the addon saw (WoWForeverLevelerNPCs) and to the zone's quest hubs
  (Plan.lua zones.<zone>.hubs from data/zone_quests.js); without TomTom it prints the coordinates.
- **Panel sections (addon 3.12.0):** one title line per topic with a short summary and a ➜ button (TomTom arrow);
  click the title to open details (Train and Quest hubs start open; state in WoWForeverLevelerUI.open). Cooking
  (➜ trainer; details: 3 recipes, spice vendor ➜ from the shop-price scan), First Aid (➜ trainer; bandage, cloth
  to keep), Fishing (➜ the zone's fishing spot, `zones.<zone>.fishing.at` = the zone's fishing trainer; bait
  vendor ➜), Gathering (red/green per node vs your skill, plus the next zone of the planned route), Camp, Quest
  hubs (➜ each hub). Plan.lua now has classes[].zones (route) and zones[].nodes (node -> skill needed).
- **Trainer list (2026-10-12):** `scripts/trainers_db.py` (run by hand) writes guide.json `trainerDB`: 110
  Horde-friendly profession trainers from ClassicDB (by title, incl. "Journeyman Blacksmith" etc.) with uiMapID
  and position. Plan.lua carries game-seen trainers first, then these. The panel points to the nearest trainer
  on your map (player position), else one on your continent.
- **Auto sync (2026-10-12):** scripts/server.py watches the save file (every 5 s) and rebuilds the dashboard data
  by itself once a new file has settled 2 s (`watch_save_file`, same scripts as the Sync button). The page polls
  data/.last_sync.json every 10 s: it reloads itself in a background tab, else shows "⟳ New game data: refresh".
  In game: right-click the minimap icon -> menu with icons: Sync (a secure button running /reload: this client
  blocks ReloadUI() from addon code, "Interface action failed"), Panel, Target button, Coordinates with on/off
  (addon 3.11.1; add more entries to MENU in UI.lua).
- **Item tooltip (3.20.0):** every item tooltip gets one "WFL:" line: Keep (a planned recipe of your profession,
  current step or within 50 points), Bank (own use later), Mail to <crafter> (planned recipe of a teammate's
  profession, full stacks), Sell on AH (Auctionator API price x0.95 >= 1.5x vendor and >= 5c), Vendor (price).
  Plan.lua `reagents` (item -> planned recipes with skill range, raw materials included) and `crafters`.
  Example: Small Spider Leg -> Vendor (only the Alliance Kaldorei Spider Kabob uses it).
- **One window, two tabs (3.19.0, user's choice):** the two windows overlapped, so it is one window "WoW Forever
  Leveler" (frame WoWForeverLevelerPanel, settings in WoWForeverLevelerUI, active tab in .tab) with tab buttons
  Professions | Leveling; the search box only on Professions; each tab keeps its open topics (.open / .open_lv).
  One minimap icon (click: show/hide; right-click menu: Sync and the two macros (3.19.1: tab entries removed, the window has tabs)). /wflp toggles,
  /wfll opens the Leveling tab.
- **Leveling = quest list (3.18.0):** the user only wants the quests to do, in order. WFL Leveling now lists the
  current zone's Horde quests (Plan.lua zones[].quests from data/zone_quests.js, now for every route zone incl.
  the starting zones: MIN_LEVEL 0, fvc + hubCoords for Tirisfal/Durotar/Mulgore) in level order, grouped by hub
  (first hub with open quests starts open, "Other" last), done quests hidden (IsQuestFlaggedCompleted), "in log"
  / "from level N" tags, check box on the giver (arrow + WFL Prof macro). The 3.17 topics (zone, hubs, dungeons,
  class, targets) are gone from the window (code kept in git history). Background: the QuestBG parchment texture
  again (the user's preferred look), on the frame above the inset (keeps the Sync fix).
- **Two windows (3.17.0):** one builder (`MakeWindow` in UI.lua) makes WFL Professions (book icon, `/wflp`,
  settings in WoWForeverLevelerUI) and WFL Leveling (map icon, `/wfll`, settings in WoWForeverLevelerUI.lv), each
  with its own minimap button, place, size, font and open topics; the menu toggles both. Leveling shows: Zone (its
  levels vs yours, "you outlevel it: move on", next route zone, travel note, class tip), Quest hubs (moved from
  Professions), Dungeons (run levels from the 30-60% rule; dungeon quests whose giver stands here, with check box:
  Plan.lua `pickups`/`runs` from data/dungeons.js), Class (routeNotes within -2/+5 levels), Quest targets.
- **WFL Professions look (3.15.0, user's choices):** Blizzard-style window (BasicFrameTemplateWithInset, plain
  frame as fallback) titled "WFL Professions"; a game icon per topic; no progress numbers (the user sees those in
  the Blizzard profession window): every title line is a warning or instruction ("cook to 50: ...", "make Heavy
  Linen Bandage to 75", "fish here up to 75", red "Learn First Aid", red camp needs).
  3.15.1: the game font has no ▸ ▾ ○ ● ← ➜ glyphs (they showed as rectangles): UI.lua is plain ASCII now and the
  selection is the game's UICheckButtonTemplate check box. Keep addon text ASCII/Latin-1.
  3.15.2 gold lines between topics and title bands; the dark-brown background was too dark. 3.16.0 (user: "use the
  colors from the quest dialog"): background = a fixed light parchment color on its own frame above the template's
  dark Inset child frame (3.16.5: before, it flipped dark/light after each /reload depending on draw order), text colors read from QuestFont / QuestTitleFont,
  dark red/green warnings, no text shadow. Not seen in game yet.
- **Selection + profession macro (3.14.0):** the ➜ button became a dot (○ / green ●). Selecting a row sets the
  TomTom arrow (arrow only) and points the character macro "WFL Prof" at that NPC (/targetexact); selecting it
  again clears both. One selection at a time, kept in WoWForeverLevelerUI.selected (arrow restored after reload).
  Menu: Sync, Panel, Profession macro, Quest macro (each macro entry puts it on the cursor). Two panels idea:
  this one is professions; quest guidance for other characters comes later.
- **RestedXP clash (3.12.2):** editing "WFL Target" on every quest-log update fired UPDATE_MACROS, and RestedXP
  rebuilds its own targeting macro on that event. Now the macro is edited only when its text changes, and it pauses
  while RestedXP (folder RXPGuides) is loaded and the character is below level 20.
- **TomTom (2026-10-12):** it only draws an arrow to points on your own continent, so the panel offers ➜ only for
  trainers on this map or continent (an Orgrimmar trainer gave an invisible arrow in Tirisfal). Its coordinate
  block is switched off at every login (the user never wants it; no toggle). 3.13.0: a ➜ click sets an arrow
  only (no world map or minimap pins, which piled up), one at a time; the same ➜ again removes it; coordinates
  also go to chat. Rows react on mouse press with a click sound; the ➜ button is the full row height. Junior
  trainers: profession read from the NPC title when the service list does not name it. Plan.lua also carries
  every trainer seen so far (data/npcs.js, all clients) plus guide.json `npcFixes` (Margaret Weaver = Skinning),
  so arrows work at once. Run build_roster before make guide to refresh that list.
- **In-game panel (addon 3.9.0, UI.lua):** movable, resizable window with font -/+ buttons, a minimap button
  (click: show/hide, drag: move) and `/wflp`. It shows what to do now from live skills, level and zone: Train
  (unlearned professions with the starting-zone trainer, ranks due now), Cook (current step's recipes and
  ingredients, Well Fed), First Aid (bandage + cloth to keep), Gather here, Fish here, Camp (needs, carry).
  The search box filters guide lines (recipes with materials, zone gathering, fishing, camp objects).
  Data: `make guide` writes addon/WoWForeverLeveler/Plan.lua (`addon_plan()` in build_guide.py). Settings in
  WoWForeverLevelerUI. Tested with a fake game in a scratch Lua runtime (lupa); needs a real in-game test.
- **Journey log (addon 3.8.0):** WoWForeverLevelerQuestLog[char].journey records zone changes, level-ups and
  quest accepts (time, level, zone; max 1000); done quests also keep acceptLevel/acceptTime. Sync writes a
  "Journey" list per character into data/quest_report.md (zones in visit order, levels, quests taken).
  Pala's 10 checks are a Launch tab section (`launchChecklist` id `pala-checks`).
- **Shopping, mail, bank, fishing (2026-10-12, addon 3.7.0):** each zone gets 🛒 "Buy in <town>: items · cost ·
  bag slots" (first zone: only pole + bauble; later: 5 Simple Wood, camp mats, bait for the zone's fishing range,
  5 water for mana users), 🏦 bank line (guide.json `shopping.banks`; Ratchet from the user), 🎣 "Fishing A-B here"
  (`zones.<zone>.fishing`). Top of the route: 🎒 "Always carry" with bag slots. Mail rule (user): a stack is mailed
  only if worth 3x the 30c stamp (AH price, else 3x vendor; no price = full stacks only); First Aid cloth for a
  later range is banked. Addon 3.7.0 saves every vendor item's price, amount and max stack at each visit
  (`WoWForeverLevelerShopPrices` -> data/npcs.js SHOP_PRICES); until then Classic ClassicDB prices (marked).
  Pala: Mining + Skinning, Retribution, Fish Bowl, dungeons on; `routeNotes` (Bandarion Keep at 10, low-level
  tank/heal test, class mount quest A Trusty Steed) stay in RestedXP mode.
- **Secondary professions + camping (2026-10-12):** user's choice: every character levels First Aid, Cooking
  and Fishing to 300 (guide.json `secondaryPlan`; the three tabs always show). Camping objects now have
  materials and tier 2/3 (name, mats, blueprint drop) from wow-professions.com. Solo = one camp object per hour;
  picks per character in `camping.picks` (Fish Bowl for most, Camp Chair for the paladin, Camp Tent for the
  shaman); the route pins a 🏕 line with what to carry. First Aid: bandage route (wow-professions.com), training
  steps by skill (Expert book: Balai Lok'Wein, Dustwallow; Artisan: Triage quest, Hammerfall), a "make now" line,
  17 new Forever recipes (`aid.newRecipes`, mobalytics), and cloth kept for First Aid (`aid.keepCloth`: e.g.
  150 Wool until skill 150) shown as "First Aid: keep ... (rest to Vestac)" in the money line.
  Cooking and Fishing now too (training, steps, cook recipes with ingredients, Horde starting-zone trainers in
  `secondaryPlan.startTrainers`). Character page › Professions › "🧭 Secondary & camp" (first tab,
  `secondaryPanel` in js/professions.js): per character camp (needs / carry / every hour) and per secondary
  profession Learn / Now / Keep / Vendor / Next. The route only keeps the training steps (by skill) and the
  🏕 line. RestedXP free guide ends at level 20 (`restedXp.until`). Beta test list cut to 3 (Legacy panel, Skywatcher bag, dungeon run levels).
- **RestedXP mode (2026-10-12):** the user follows the RestedXP addon for quests until level 30
  (guide.json `restedXp.until`). A switch at the top of the route (on by default, localStorage `wow_rxp_mode`)
  keeps only zone, prof, money, bank and gear steps below that level (`restedXpFilter` in js/route.js); the
  character cards use it too. We do not copy RestedXP's routes (their product).
- **Less text (2026-10-12):** gathering lines are names only (herbs/ore with the skill needed, skinning
  without); no "what to gather at this skill" line; training steps are due by skill ("Train Journeyman
  Skinning (75/75) now", else "at skill 125", not due by level); shorter dungeon, trainer, skip (one entry per
  quest name), optional quest (no level in text: the left column has it) and gear lines; prices drop zero
  parts (2s, not 2s 0c). Lovac's route text went from about 17,900 to 13,400 characters.
- **Dedicated Study (Legacy perk):** in the Legacy card's perk list and as a Phase 3 money tip: characters with
  all 5 professions at 300 make 2-3 elemental essences a day (Studen Albatroz video, not checked).
- **NPC reads happen once (addon 3.6.0):** WoWForeverLevelerScanTimes[key] = { build, level, seen }; trainers,
  vendors (recipes, bags, map spot) are read again only after a game patch (new build), class trainers also
  after a level-up. PLAYER_MONEY only updates gold (no full save). No per-frame code in the addon.
- **Bag vendors:** addon 3.5.0 saves vendors that sell bags (WoWForeverLevelerBagVendors: place, bags with slots
  from the tooltip and price) -> data/npcs.js BAG_VENDORS. The route's level 6 step names the cheapest bag per
  slot in the character's first two zones, else guide.json `bagVendorFallback` (5s 6-slot bag, probably Small
  Brown Pouch; Brill / Sen'jin / Crossroads, not checked).
- **Early money order (user's rule):** levels 1-6 no bag materials (skills > professions), except the 25c
  gathering bag: buy it as soon as possible. Linen Bags to sell only if 6 linen + 30c is well under the 5s a
  vendor charges for a 6-slot bag (beta: linen 99c = about 6s 24c per bag, a loss at 4s);
  after the level 10 skills, mail Banka linen (6 per bag) + 30c per Linen Bag (+1s 30c once for her recipe and
  Tailoring); the user decides how many from bags already found. Tailor tip: craft only what sells now (bags
  while the auction house is empty) or what Enchanting uses (gear to disenchant).
- **Mining (Dave The Gamer video, not checked):** milestone notes: loot each node fully (several hits, max 1
  skill point), keep Pyrite/Bauxite/Pitchblende, beta caps Mining at 225. Camp: Rock Garden (140), Molten
  Foundry (300). Mining gives no Legacy points.
- **Bag quests (04AM bag video, not checked):** ⭐ Tirisfal "Sticks and Bones" (Brill, Collecting Basket),
  ⭐ Durotar "Carry Your Weight" (8 Canvas Scraps, Handmade Leather Bag), ⭐ The Barrens "Deviate Hides" (Nalpak
  above the Wailing Caverns entrance, 10-slot Deviate Hide Pack; also marked in the WC quest list through
  `dungeons.questNotes`), 💡 Durotar Makrura Snapclaws drop small pouches. Spidersilk Pouch quest needs only
  level 23 (the user kept the step at 30).
- **Optional quests (💡, guide.json `zones.<zone>.optional`):** one line inside the zone, not a must-do.
  2026-10-09: 37 more from ClassicDB (1-4 per zone, Classic data, not checked): Horde quests with a blue or
  green reward or high XP for their level. With `id` + `level` they sit under "By level", link to ClassicDB
  and tick themselves from completed quests. Picked from all Horde quests of each route zone (scraped with
  curl: `?quests=<cat>.<zone>` pages and `?item=<id>` pages for reward quality; curl works for classicdb.ch).
  Desolace: Highway Robbery chain (Desolace -> Booty Bay -> Thandol Span; ring/gloves/helm, dungeon-quest XP;
  Kaghoegaming video, not checked).
- **Skywatcher Plateau (new Forever hub, far NW Mulgore, levels 27-30):** guide.json `globalMustDo` puts a ⭐
  level 30 step on every route: free bag quest, take the 12-slot Spidersilk Pouch (user's choice). Excavation
  Site is back for the Horde (`dungeons.list[].horde` text; its chain goes through Thunder Bluff and ends at
  Skywatcher Plateau); the addons have no quests for it yet. The Deadmines stays skipped. From a Scunnered
  video, not checked: confirm the bag quest's name and ID in game.
- **Rested XP + Legacy (js/legacy.js, guide.json `legacy`):** addon 3.4.0 saves `restedXp` and `resting` at
  each save; the 😴 card estimates rested XP now (5% of a level per 8 h in an inn, 1/4 outside, cap 1.5
  levels, +4% per Well Rested rank in `legacy.wellRestedRanks`) and sorts characters by it. ⭐ card counts
  Legacy points sync can see (first character of each class at 25/45/60, each CRAFTING profession at
  150/225/300; gathering does not count) and the next easiest. From two videos (MMO Unlocked, RedCloud showing
  the beta panel), not checked. The user wants rested XP as tips, not a fixed rotation. Perk order chosen by
  the user: Well Rested first, then Talented (Talented needs Well Rested 5/5). Dungeon lines carry
  "⭐ Legacy: Novice/Experienced/Master Spelunker" (`legacy.spelunker`, wowforevertalent.com list); the
  Lord Valthalak chain (An Earnest Proposition ... Saving the Best for Last) is a level 60 ⭐ step.
  IGN wiki Legacy guide (2026-09-30) confirms the class, crafting (no gathering) and Spelunker lists; adds
  reward items (15/25/40/55), PvP / explore / raid challenges, and the Reinforce and Master Chef perks.
- **Route start (level 1, before the first zone):** free profession quest at the camp leader, the paid
  gathering profession + tool at 20c, gathering bags at 50c (one reagent slot; the Skinning bag holds the knife
  and scraps), ⭐ must-do quests (guide.json `zones.<zone>.mustDo`, e.g. Mulgore: Grace of An'she and Mu'sha =
  free 6-slot bag, from the user's beta hunter; add `id` once known so it ticks itself), hunter quiver.
- **Dungeon quests in the route (🏰):** one line per dungeon inside the zone it is in (`dungeons.zoneOf` in
  guide.json) when its first level is inside that zone's level range; else placed by level; opening it lists the Horde quests to pick up first (giver, zone,
  coordinates; no rewards, to keep it short), from the Forever Loot + DFL Dungeon Journal addons. Done quests
  drop out (addon 3.1.0 saves every completed quest ID). `dungeons.hordeSkip` in guide.json leaves out
  Alliance-land dungeons.
- **Data:** quest skips = the 146 Elite quests of the route zones (ClassicDB, with ids). Gear = quest-reward
  weapon/wand paths per character (route zones, Horde cities, dungeon quests, +15% DPS rule) plus
  enchanter wands and blacksmith weapons.

## 5. Built but not yet confirmed in game

- **Confirmed in game:** Auctionator prices (2026-10-01), addon 3.1.0 completed quest IDs, 3.3.x last name
  (UnitName's 2nd value) and GUID keys, 3.2.1+ class trainer scan (hunter levels 1-6 saved).
- **Confirmed in game (2026-10-12/13):** addon 3.7-3.20: shop prices + stacks, journey log, minimap icon on the
  modern minimap edge, TomTom arrows (after the continent fix and the shipped trainer list), WFL Target macro
  content, Esc closes, the window itself (user: "looks much better", "already useful").
- **Not yet seen in game:** 3.19 tabs, 3.20 item tooltip line, 3.21 bandage money line / level 60 note / AH timing,
  the QuestBG parchment staying light after Sync (3.16.5 layer fix), quest list on the Leveling tab, the
  Junior-trainer title detection (TrainerTitleProfession), the RestedXP pause of WFL Target.
- Class trainer costs for the other 8 classes: open each class trainer once.
- Everything from videos or web sites is marked "not checked" (bag quests, Skywatcher Plateau, Highway
  Robbery, Mining notes, Legacy rules, weapon paths, dungeon run levels). Confirm or correct while playing.
- Linen Bag: at what Tailoring skill it turns grey (no skill-ups).
- Classic data still "not checked": zone cards, class tips, elite skips, city trainers, skills 225-300.

## 6. Plan / open to-do list

**Try on live (money ideas from the beta):**
- **Video "WoW Forever Fresh Server Guide: How to Get Ahead on Day One" (World of Wyland, 2026-10-16, read
  2026-10-19), not checked:** first weeks = sell raw materials (Linen Cloth, Ruined Leather Scraps, Light Leather,
  herbs, ore) while demand is high and supply low; buy them back cheap weeks later to level crafts (he made 7g
  before level 12 on the beta; later alts could not). Learn Skinning at once (10c + knife from the trainer) and
  skin every corpse, also others' kills; sell Ruined Leather Scraps (a stack a bit over 1s at the vendor); a
  second gathering profession builds skill for later crafting. Farm humanoids (copper, linen, bag drops); no
  First Aid with early Linen (sell it). Quest rewards: take the one worth most at the vendor (weapons aside).
  AH: look at the stack count, not the lowest price (a few very cheap listings are bait); list only for about 2x
  the vendor price after the deposit, else vendor it; many green items near vendor price -> vendor them. No PvP
  pressure until about level 30.
- **Lesser Magic Wand** (Enchanting 10-75, orange): the user keeps the Strange Dust path and makes a few wands to
  sell only with spare Lesser Magic Essence (2026-10-19). Beta AH: 2-4s each, small market.
- **Elixir of Minor Force** (Alchemy, learn 10, 1 Silverleaf + 1 Empty Vial, about 4c in vials): the user sold
  some on the beta (2026-10-19). Auctionator lowest: 40-65c early October, 1s 88c on 10-16, 5s 48c at the last
  scan (Classic Beta PvP 2, 946 listed). Recipe source not known yet (forevervsclassic: "Not yet confirmed").
  Sveti or Travar (Alchemy) with Lovac/More herbs; check the price after the first days on live.

**Beta restart (user, 2026-10-16):** the user deletes all beta characters and starts fresh in launch order
(Lovac, Vestac, Pala, Sveti, Konan, Ubica) plus Banka, for gathering, levels and a launch rehearsal. Backup
first: `personal/backups/beta-WTF-before-reset-2026-10-16/` (whole beta WTF folder + history.sqlite; not in git).
**To do after the deletion:** clean the old characters out of the save file (WoWForeverLevelerDB, ...UI.have,
...UI.bankChars Postarka, recipes) and the dashboard, so the Team tab and cards show no ghosts (match by GUID:
new characters get new GUIDs). Account data (trainers, vendors, prices, item IDs) stays.

**Next test session (user, 2026-10-16, when the servers are up):**
1. **Addon load test:** only the Needed addons (Polestar x5, Auctionator, Questie + QuestieDB) + our core and
   Planner. Forever Loot, DFL and RestedXP turned off. Question: too much on screen, or just right?
2. **Sveti test (Troll Shaman, level 4):** play with our Planner and note what to improve. Save file 2026-10-15:
   Sveti has **Herbalism 4 + Skinning 13** (the plan says Alchemy + Leatherworking), so the Professions tab
   shows gathering lines only. **User's choice: Sveti switches to Alchemy + Leatherworking** (unlearn both, train
   Alchemy at Miao'zan, Durotar 55.4, 74.0 (Sen'jin Village) or Yelmak, Orgrimmar 56.8, 33.0; Leatherworking at
   Karolek, Orgrimmar 62.8, 44.2) to test the crafting part (Polestar counts, materials, Make N lines).
3. **Try 4 addons** with their first setup: SkillUp Forever, HandyNotes + Books, Layer Swap, OPie
   (guide.json `addons.toTry`).
After the session: read the save file and log, ask for screenshots, fix what the user found.

**For the user (beta ends 2026-10-21):** fully restart the game for addon 3.10.0 (new files and saved table), visit
vendors (prices + stacks), start Pala Rifle (Undead Paladin) with RestedXP, Sync after the first session: read the
start zone, which gathering profession the Undead start quest gives, and paladin trainer costs.
 the ordered list is the first section of the 🚀 Launch tab
(guide.json `launchChecklist`, section with `beta: true`). Quest tests tick themselves (`auto: {quests: [...]}`
in js/launch.js: done when one beta character completed all of them). Lovac was level 23 in Hillsbrad on
2026-10-11. Confirmed from the save file: addon 3.6.1 works (rested XP saved), Deviate Hides = quest 1486, the
6-slot Small Brown Pouch costs about 5s (4s 50c in Thunder Bluff: vendor prices drop with reputation, so
scanned prices are per character, not fixed). Forever-only quests seen: 91899,
98248 (Barrens), 95883-95885 (Silverpine).

**Launch (the 🚀 Launch tab has the full list):**
5. Rotate the Battle.net client secret (shown in an early chat); put it in `.env`.
6. Reserve Lovac Kasapin, Vestac Zla, Pala Rifle (2026-10-27 to 11-03).
7. Launch day: start the live client once, `make addon`, install the needed addons (Auctionator, Forever Loot,
   Questie + QuestieDB), restart, create all characters, Banka runs to Thunder Bluff for bags, Sync.
   Then set the real mount price (`money.mountGoal.gold`) and say "launch check".

**Next (user's priority, 2026-10-13):** (gold tips from Gillee's video are built: First Aid bandage profit line,
level 60 "quests give gold" note, "best Tue/Thu evening" on the AH tooltip line)
- **Quest guidance in WFL Leveling.** Today the tab only lists the zone's quests by hub with a check box/arrow.
  It needs real guidance: what to take where, the order to do them in (objectives grouped by area), when to hand
  in, which to skip, and the trip to the next hub/zone. Build it from our own data: the addon's journey log
  (real order of accepts/turn-ins from Pala and Lovac), zone_quests (levels, givers, hubs), skips, dungeon pickups.
- **Item tooltip decisions: BUILT in 3.20.0** (see section 4). Originally proposed as: one line on every item tooltip: Keep (planned recipe at
  the current/next skill step), Bank (own use later), Mail to <crafter> (team need, stack worth 3x the 30c stamp),
  Sell on AH (AH net >= 1.5x vendor), Vendor. Data: guide recipes (only planned ones count: far or Alliance-only
  recipes like Kaldorei Spider Kabob mean "sell"), live skills, roster professions, Auctionator's in-game price
  API and the item's vendor price.

**Code ideas (not started):**
8. Boss/mob levels per dungeon (no source yet) to replace the run-level rule of thumb.
9. Must-do quests: 💡 lines added for Classic rewards (2026-10-09). Still open: Forever-only quests and real
   Forever quest XP, from the user's tests.
10. More money methods only with evidence, each with a live calculator in `money.methods`.

## 7. How the user likes to work

- **Game first (2026-10-12):** the user now uses the in-game panel, not the browser dashboard. Keep the dashboard
  code (it may be used again later), but build new features in the addon (UI.lua + Plan.lua from `make guide`).
  Open idea: money decisions (sell/vendor/hold/mail) in game, from Auctionator's prices.

- Explain in very simple English (short sentences, one idea per sentence, active voice). Give at most 2
  options and a recommendation when a decision is needed.
- **Commit only when the user says "commit"** (or "save everything"). Scan for secrets before committing;
  `.env` is ignored.
- Show concrete answers (exact numbers, materials, quest names) instead of "open X to see it".
- Dashboard: minimal and readable, big text, one-line steps with numbers, no long explanations.
- Evidence first: prefer the user's own data and trusted databases; mark Classic data "not checked".
- Test changes: `make test`, and the dashboard in the browser pane. Lua cannot run here: syntax-check the
  addon (luaparser) and let the user test in game.

---

## 8. Session routine

### A play session (the user)
1. Click **WFL Dashboard** in the Dock.
2. Play. After training a profession: open its window once and visit the trainer once. At the auction
   house: run Auctionator's full scan (once per 15 minutes).
3. When done: `/reload` or log out, then click **⟳ Sync** (it waits for the game to save).

### A work session with an AI agent
1. Tell the agent: "Read STATUS.md and continue."
2. The agent starts with `git log --oneline -10`, `make test` and, if game data matters, `make launch-check`.
   To see what happened in game, it reads the addon log and data from the save file
   (`/Applications/World of Warcraft/_*_/WTF/Account/*/SavedVariables/WoWForeverLeveler.lua`).
3. Typical update requests while leveling:
   - "This zone card / step is correct or wrong" -> edit `data/guide.json`, set `checked`, `make guide`.
   - "The addon shows an error" -> read the log in the save file, fix, bump the `.toc` version, `make addon`.
   - "Prices look odd" -> check `personal/history.sqlite` and the Auction House tab.
   - "New money method" -> add it to `money.methods` with a `calc`, test with `methodNumbers`.
4. At the end: add a Session Log entry below (date, what changed, what is open), and commit when asked.

### After a game patch
Recheck profession guides and zone cards (reset `checked` where things changed), run `make launch-check`,
and update section 3 if Blizzard changed an API.

---

## 9. Session Log

Newest first. One short entry per session.

- **2026-10-21** (Claude, addons): Edit Mode Tweaks supports Forever (1.60.1); `settings_transfer.py` also copies
  its per-character file (guessed name SavedVariables/EditModeTweaks.lua, check after install). Forever Loot and DFL
  Dungeon Journal are not needed in game: Sync (build_roster.py) now keeps the last data/dungeons.js data for a
  client whose addon folders are gone (data/dungeons.js is git-ignored, so it lives only on this Mac).
  Planner 2.5.1: every dungeon is listed on its own too, not only inside its chain (Stratholme, Scholomance).
  Planner 2.5.2: a chain section is short: Order, Pick up (first open step of each quest, grouped by zone,
  clickable), Run (dungeons with entrance). Full quest lists stay in each dungeon's own section.
  Core 3.38.6: the mouse wheel scrolls about 3 lines (3 x (font + 4) px), not half a window.
  Planner 2.5.3: Dungeons tab in two groups, each in level order: "Dungeon chains", then "Dungeons".
  Planner 2.5.4: chain section = Run (in this order, entrances), then Pick up N quests; no Order line or note.
  Planner 2.5.5 + core 3.38.7: dungeon headers read "lvl: 15 - (run: 15-16)" (green when due), joined with
  no-break spaces so a narrow window moves it under the name whole. Rows take `stripe` (light band on every
  second quest) and `gap` (space above, before zone headings and each quest group).
  Planner 2.5.6: a chain shows only "Run in this order" (gold) and its numbered dungeons with run levels and
  entrances; the quests to pick up are only in each dungeon's own section.
  Planner 2.5.7: a dungeon's section = Entrance (zone, click for arrow), then its quests under zone headings
  (one city at a time): quest name and giver only, the next open step of each chain; grey = not yet your
  level. No coordinates, level numbers or "dungeon" tags. Fake-game test now opens Ragefire Chasm and WC.
  Level check (2026-10-21): every dungeon's quests open before its run levels (RFC quests 9, run 15-16), so
  the start level is the run start. Core 3.38.8: allFrom ignores quests above the run's end (Shrewd Negotiations
  24 for Ruins of Lordaeron 17-18). Planner 2.5.8: headers show one range "lvl: 17-18"; the Next tab's dungeon
  steps name the zone only, no coordinates.
  Planner 2.6.0: a dungeon quest in your log shows its task text under it (Forever Loot objective, pickups
  `obj` in Plan.lua; 263 of 300 quests have one). No arrow inside dungeons: the game gives addons no player
  position there.
  Planner 2.6.1: "Inside the dungeon" heading per dungeon: quests started inside (person, object, looted item;
  135 of 265 dungeon quests had no outside giver and were hidden). Lunar Festival Elders and Darkmoon card quests
  left out; other classes' quests hidden (QuestieDB class mask). Built in build_guide.py as runs[].inside.
  Chain levels: you run the dungeons back to back; their XP carries you to the next (Ceedsy, chain 1).
  Planner 2.6.2: inside quests show "after <quest>" (Forever Loot chainFirst) and always their task text.
  New scripts/dungeon_givers.py (run by hand, then make guide) writes data/dungeon_givers.json from QuestieDB:
  each dungeon quest's real giver. 16 givers marked inside stand outside (Nalpak and Ebru above the Wailing
  Caverns entrance) and now show under their zone with an arrow; 35 quests start from a dropped item ("drops
  from Mutanus the Devourer"); 9 quests not in Forever's QuestieDB or Alliance-only are left out. QuestieDB
  startedBy is a dict {3: [...]} when only items start it. Planner 2.6.3.
  Automatic since then: scripts/refresh_data.py reruns dungeon_givers.py and vendor_items.py (about 3 s) on every
  Sync (server.py SYNC_SCRIPTS, before build_guide.py) and every `make guide`. Without QuestieDB it keeps the last
  files. Nothing to run by hand after a QuestieDB or Forever Loot update.
  Alliance check: all 144 dungeon pickups and their chain steps are Horde-takeable (QuestieDB races, Forever
  race bits: Horde 0x2000000B2, Alliance 0x10000004D; giver NPC factions). Only 3 Alliance-only quests exist in
  the data and none has a map spot, so none shows. User confirmed: no Alliance quests, they only sounded like it.
- **2026-10-21** (Claude, settings): New `scripts/settings_transfer.py` (apply / export / import). Edit Mode
  layouts and key bindings are account-wide; each character only stores its layout number. `apply --from
  Kaspin-Lovac` set the 9 other team characters to Kasapin's layout ("Main", renamed from "Lovac"; since the import test it is the only layout, number 3), extra bars, Cooldown
  Manager on, window positions, chat, click bindings, addon list. Backup: personal/backups/wtf-beta-20261021-1249.tar.gz.
  `export` saved it for live in personal/settings-backup/2026-10-21 (plus addon settings and 133 graphics lines).
  Launch day: start live once, log in each character once, close the game, `python3 scripts/settings_transfer.py import`.
  Checked in game (user): every character loads "Main". The script now keeps the game's line endings, and
  `export` also saves each class's Cooldown Manager spells and character macros (`import` puts them on the
  character of the same class in personal/team.json). Re-run `export` after in-game changes, with the game closed.
- **2026-10-20** (Claude, arrow): Core 3.38.5. No arrow at login: the last selection is forgotten and old WFL
  waypoints that TomTom saved are removed; the arrow shows only after you select something. The selected
  target also gets a TomTom pin on the world map and minimap. Trainers-to-visit window (`/wfl todo`): click a
  trainer line for the arrow and pin, click again to clear. Vendor search prints only the closest vendor.
  Fact: Polestar has its own arrow (nav.arrow) and "Mirror to TomTom" (nav.tomtom), both on by default; those
  are the quest arrows at login. Turn them off in Polestar options, Arrow & routes.
- **2026-10-20** (Claude): Core 3.38.4: the vendor click also takes Alt (Option) and Command (IsMetaKeyDown), not
  only Ctrl: the user's Mac has Control and Command swapped. Clicking a material line in our window works (user).
  **Confirmed in game (user): Option + click in the profession window finds the vendors.**

- **2026-10-20** (Claude): Core 3.38.3: Ctrl + click in the profession window did nothing (user): the Forever
  client has the modern profession window (C_TradeSkillUI; log "Classic recipes: no"), whose reagent buttons do
  not call HandleModifiedItemClick. Now the GLOBAL_MOUSE_DOWN event: Ctrl held (not Shift) + an item in the
  GameTooltip (not wearable) -> FindVendor, once per 0.3 s. Fallback to the HandleModifiedItemClick hook when the
  event is missing; the log says which ("vendor click: ..."). Not seen in game.

- **2026-10-20** (Claude): Core 3.38.2. **Forever trainers from QuestieDB**: vendor_items.py also writes Horde-
  friendly profession trainers (111, by title: "Journeyman Enchanter", "Junior Herbalism Trainer", ...), and
  build_guide adds them after our own scans and before ClassicDB. The user's "Enchanting trainer in Sen'jin?" =
  **Pa'zula, Journeyman Enchanter**, new in Forever, Durotar 56.7, 73.7 (guide texts named now). Vendor search on
  **Ctrl + click (left or right) on a material** (the user wants it in the profession window, whose reagent buttons
  take only the left button); wearable items keep the dressing room. Not seen in game.

- **2026-10-20** (Claude): Core 3.38.1: vendor search also on **Ctrl + right-click** on any item (hooksecurefunc
  HandleModifiedItemClick + GetMouseButtonClicked; Ctrl + left-click stays the dressing room); the Alt+V default is
  gone (the user's Alt+V is nameplates; the binding stays, without a key). Minimap and addon-list icon now
  INV_Misc_Spyglass_02 (the book INV_Misc_Book_09 is Forever Loot's). Guide comparison: in the journey logs
  Polestar characters took 1-2 quests 3+ levels above them (lvl 1-12), old Pala on RestedXP 5 (avg +0.4).

- **2026-10-20** (Claude): **Vendor search** (user: "where do I buy Coarse Thread in Razor Hill"). New
  `scripts/vendor_items.py` -> `data/vendor_items.json` (run by hand after a QuestieDB update, then make guide):
  QuestieDB item field 14 = vendors, Horde-friendly NPCs (friendlyToFaction H/AH) with spawns via areaIdToUiMapId,
  for every recipe reagent, profession kit item and shopping item (98 items, 299 vendors; Coarse Thread 67, in
  Razor Hill: Flakk, Durotar 53.0, 42.0). Plan.lua `vendors` (id as string -> {n, sub, at}) and `vendorItems`.
  Core 3.38.0 UI.lua FindVendor(item): nearest 3 (world yards via C_Map.GetWorldPosFromMapPos, else your zone,
  then your continent) in chat, arrow + selection to the nearest. Ways in: **Bindings.xml** "Find the nearest
  vendor of the hovered item" (WFL_FindVendorHovered, GameTooltip/ItemRefTooltip:GetItem; default Alt+V set once
  when free, Settings().vendorKeyDone), a **click on a material line** (item without its own place), and
  **/wfl buy <item>** (exact, else first name containing the text). New file: full game restart needed. User will
  try both and decide what to keep.

- **2026-10-20** (Claude): Dashboard characters page: cards first, Rested XP and Legacy boxes below them;
  each card shows a rested bar ("0.5 levels rested · not in an inn"; not for the bank); cards in plan order by
  default (#1-#6, open ones, the bank last), a sort menu "Plan order / Level / Rested XP" (kept in the browser,
  wow_char_sort; the bank always last). Vendor search design proposed (QuestieDB item field 14 = vendors, e.g.
  122 for Coarse Thread with faction and spawns): Professions Buy line with the nearest vendor, tooltip line,
  `/wfl buy <item>`; waiting for the user's go.

- **2026-10-20** (Claude): Fresh history pushed to the public remote https://github.com/dragan-lukac/wowForeverLeveler
  (main = one clean commit). The old 117 commits and the tag own-3.31.0 are packed in
  `personal/backups/history-backup.bundle` (checked: opens, complete); the local branch and tag are deleted.

- **2026-10-20** (Claude): **Personal data split** (user: make it universal before a remote repo). New
  `personal/` (git-ignored): team.json (names, last names, races, groups, start, order, professions per character
  id; bank name/race/class), account_characters.json, local_characters.json, roster.js, mockup_state.js,
  quest_report.md, history.sqlite, backups/. `personal.example/team.json` = example team (class names). New
  `scripts/team.py`: load_guide() = data/guide.json (general guide, no personal fields) + team (race sets the
  first route zone); save_character() for the dashboard picker (server.py). build_guide, build_roster,
  build_routes, quest_report, launch_check, mockup_state, tests read through it. Built files with names are
  git-ignored: data/guide.js, data/addon_plan.js, addon/WoWForeverLeveler/Plan.lua, guide.md (`make test` and
  `make addon` run `make guide` first). Guide texts no longer name characters ("ask your blacksmith", "the bank
  character"). Launchers (WFL Dashboard.app, Sync Characters.app, sources in Launchers/*.applescript) and
  .claude/launch.json find the project folder themselves. History check: no secrets in any of the 116 commits
  (.env never committed); old commits hold account ids and Classic Era character names, so a fresh history is
  planned for the remote.

- **2026-10-19** (Claude): Our own recipe scans now correct the site data (user: "Novice's Practice Wand, vendor
  mats"). forever_profs.py reads WoWForeverLevelerRecipes from every local save (recipe, skill at scan time,
  colour): a known recipe is learned by that skill (no source + known by 10 = comes with the profession, from 1),
  confirmed, counts like a trainer recipe; its colour moves the site colours to match. Vendor goods cost their real
  vendor price from our vendor scans (WoWForeverLevelerShopPrices: Copper Rod 1s 24c was valued 10c as "Copper").
  Weapons now get a disenchant value (item kind "Weapons"), except Enchanting's own crafts (loop; user keeps the
  dust path). Enchanting now: 1-11 Novice's Practice Wand (Mote of Magic 10c + Simple Wood 38c), 11-25 Enchant
  Bracer - Inferior Stamina (Mote of Magic), then the Strange Dust enchants. Core 3.37.2 (Plan.lua).

- **2026-10-19** (Claude): Where to learn each recipe (user: "Linen Reagent Bag, I don't have it; apply to all").
  New `scripts/recipe_sources.py` -> `data/recipe_sources.json`: every vendor/quest recipe (866) looked up on
  ClassicDB (pattern item -> Horde-friendly vendors with zone, map spot, price, limited stock; quest rewards):
  255 for the Horde, 54 Alliance only, 557 not on ClassicDB (new in Forever). forever_profs.py: drop recipes only
  where no trainer/vendor/quest recipe gives points; Alliance-only recipes left out. build_guide craftSteps
  `learn` = trainer cost (trainers.js) or pattern + vendors (our scans first, then ClassicDB) + quests. Planner
  2.5.0: a "Learn" row before Make when this character does not know the recipe (WoWForeverLevelerRecipes, saved
  when the profession window opens): "Pattern: Linen Reagent Bag 1s 35c from Mahu" + arrow, "quest X (level N)",
  or "vendor, where not known yet"; trainer recipes only when the window shows them missing. Core 3.37.1 exports
  WFL.VendorPoint. Path steps: 120 trainer, 65 vendor known, 6 quest known, 17 new Forever patterns without a
  known vendor (they fill in when our vendor scans see them on live: Sync + make guide). Run order after data
  changes: forever_profs.py (--cached) -> recipe_sources.py -> forever_profs.py --cached -> make guide.

- **2026-10-19** (Claude): Planner 2.4.0. **Dungeons** (user: no route filter, list all, I decide): every dungeon
  with open quests in level order (all stops, only the first open), folded line "quests from 24, run at 24-31",
  each dungeon "Level 13-18, run at 15-16" + entrance; the route filter from 2.3.5 is gone. **Market states**
  (user: flexible, depends on the AH): Plan.lua prices now carry n (scans), qty (last listed) and qtyUsual
  (build_guide); MarketState(item) compares the price now (Auctionator in game) with its usual price and the
  amount listed with its usual amount: hot (+25% price or half as many listed) -> Sell now (all of it, "buy N back
  later"), flooded (-25% or twice as many) -> Buy cheap what crafters need / Hold extras, normal -> sell extras
  at >= 1.5x vendor; below 2 scans = normal. "few listed: check the price" when under 5 are listed. Crafters'
  profession rows get a Market line: "Linen Cloth is hot (...): sell it, craft later" / "is cheap: buy it for
  this step". Core 3.37.0 (Plan.lua). Needs daily Auctionator scans + Sync to be useful.

- **2026-10-19** (Claude): Planner 2.3.5: dungeons in a zone of the 20-30 route option you did not pick are left
  out (WoWForeverLevelerUI.routeChoice; Plan.lua runs zone), so with "Eastern Kingdoms" Blackfathom Deeps
  (Ashenvale) is gone and Dungeon chain 3 moves up. Fake game: `8 planner ek`. Video tips noted (Try on live).

- **2026-10-19** (Claude): Disenchant value in the profession paths (user). forever_profs.py reads each green-or-
  better crafted item's page once (forevervsclassic.com/items/<id>, cached in data/forever_pages/items/, 1331
  items: Forever quality, item level, Armor/Weapon) and values disenchanting with the Classic table (green by item
  level: armor 75% dust / 20% essence / 5% shard, weapon essence 75%; levels <=15 no shard; blue = 1 shard; not
  checked in Forever) at our auction prices. A craft is worth its AH price for the first MARKET_CAP=10, then its
  disenchant value (unlimited; feeds Vestac's Enchanting), the higher one from the start. Many items turned green
  in Forever (Green Linen Bracers: Common -> Uncommon). Planner 2.3.4 Make row: "sells 1g, sell at most 10, then
  disenchant (4s 85c)". Core 3.36.8 (Plan.lua craftSteps de).

- **2026-10-19** (Claude): Profession paths now aim at money (user). forever_profs.py: net cost = materials minus
  the item's auction price (5% cut) for at most MARKET_CAP=10 crafts of a recipe; strict sale price (seen in 2+
  scans, lower quarter of the lowest prices; Plan.lua uses it as craftSteps `sell`); sale at most 2x material
  cost; score = net / chance when it costs, net x chance when it pays. Crafts per profession stay about the same
  (389-499); Tailoring now goes through shirts, robes and reagent bags; Enchanting keeps the Strange Dust path
  (user's choice). Planner 2.3.3 Make row: "· sells 1g, sell at most 10". Core 3.36.7 (Plan.lua). Beta prices are
  high and thin: rerun `python3 scripts/forever_profs.py --cached` + `make guide` after a week of live scans.

- **2026-10-19** (Claude): User asked: wands instead of 10 Runed Copper Rods? forever_profs.py can now count the
  made item's auction price as paid back (SALE_WEIGHT); tested at 1.0 and 0.5: every path got 10-20% more crafts
  (sellable green recipes win), Enchanting at 1.0 made 94 Greater Magic Wands 70-140. Left **off** (0): fewer
  materials for the gatherers, thin beta prices. Enchanting facts: Runed Copper Rod is the only recipe below 10 in
  our data (16 crafts, ~20s in Copper Rods); Lesser Magic Wand is orange 10-75 (1 Simple Wood + 1 Lesser Magic
  Essence, sold 2-4s on the beta AH). Vestac knew Novice's Practice Wand and Dust to Motes (both "Not yet
  confirmed" on the site, learn 10): our own recipe scans could mark such recipes confirmed (not built).

- **2026-10-19** (Claude): Material bars count what is **still needed** (user: crafting lowered "have" but not
  "need"). forever_profs.py adds `raw` per step (raw materials, vendor goods left out) -> Plan.lua craftSteps
  raw; Planner 2.3.2 StillNeeded(prof, rank, bracket) sums the steps from the current skill to the bracket end
  (a started step counts for the part left) for the Professions tab ("Materials still needed to 150") and Team
  materials. Core 3.36.6 (Plan.lua).

- **2026-10-19** (Claude): Core 3.36.5: background messages go only to WoWForeverLevelerLog, not chat (Log(text,
  true)): "N Auctionator items named" (user saw "1 ... named" at every login: two item IDs share a name, now only
  a new name counts), "saved N new trainer recipes", "class trainer: N new skills", "saved N recipes sold by",
  "saved bag vendor". Errors and /wfl output still print.

- **2026-10-19** (Claude): Profession paths fixed: conversion steps with no range removed (Bolt of Runecloth,
  Medium/Heavy/Thick Leather), holiday recipes left out; totals now Alchemy 416, Blacksmithing 572, Enchanting
  397, Engineering 487, Leatherworking 438, Tailoring 411 crafts. Dungeon chains 2-7 added to guide.json
  (SFK > Excavation Site > Dalaran; RFK > Gnomeregan > SM; RFD > Uldaman > ZF; Maraudon > Sunken Temple;
  BRD > BRS; Scholomance, Stratholme, Dire Maul), from our levels and quest givers, not checked. Core 3.36.4.

- **2026-10-19** (Claude): Rested XP was wrong (user): every save had rested 0 and resting false because the logout
  values are empty on the Forever client. Core 3.36.3 keeps the previous rested/resting at logout and saves on
  PLAYER_UPDATE_RESTING and UPDATE_EXHAUSTION. Planner 2.3.1: the bank (Banka, bankChars) is never in the team
  rotation, also while you play her ("Switch to <most rested>"). Old saves fix themselves after each character
  logs in once and goes to an inn. Elixir of Minor Force noted under "Try on live".

- **2026-10-19** (Claude): Planner 2.3.0 "less novel" pass (user feedback on Pally): professions as labelled rows
  (Learn / Make / Then / Gather / Next / Train / Buy, each on its own line, trainer or vendor under it; Planner.lua
  Rows); Skinning shows only Train (rank, cost, skill/level needed, where) and Buy; no "(N to go)"; Train rows
  "Journeyman (5s) at skill 50" or "...: now" (then first). Team materials: one short line. Legacy: Next tab shows
  this character's next point ("Level 25: first Paladin there", "Craft Enchanting 150", "N of 48"); Team tab lists
  all points (9 classes x 25/45/60 and 6 crafts x 150/225/300, reached ones green, from WoWForeverLevelerDB +
  live skills; the 3 Spelunker tiers with their dungeons from Plan.lua `spelunker`). Dungeons: chain "Order" line +
  note one sentence per line; repeated chain step names shown once ("Hidden Enemies ... 3 steps  dungeon"); "Level
  13: collect the Dungeon chain 1 quests". Core 3.36.2 (Plan.lua). Only one dungeon chain is known (Ceedsy video);
  Excavation Site shows because it is a Novice Spelunker dungeon (24-29). Not seen in game.

- **2026-10-17** (Claude): Profession costs (user). Plan.lua `profCosts` (trainer scans: Apprentice 10c, Journeyman
  ~5s, Expert ~50s, Artisan ~5g for gathering; crafts only partly scanned) and `profKit` (guide.json
  professions.<code>.kit: tools, bag, alt; prices from shopping.items, now Forever beta prices: Mining Pick 10c,
  Skinning Knife 10c, Herb Pouch 25c, Skinning Satchel 25c, Blacksmith Hammer 18c, Copper Rod 1s 24c). Planner
  2.2.1: "Learn Mining (10c)", "Train Journeyman Skinning (5s)", and a "Buy: Mining Pick 10c (vendor)" line while
  this character lacks a tool or bag (core 3.36.1 WFL.OwnCount counts bags, bank and the 4 bag slots;
  WFL.ShopPrice = own vendor scan first). No Mining bag known yet.

- **2026-10-17** (Claude): Profession help for low levels (user: no info on where to learn, what to gather, the
  skill for Briarthorn). Planner 2.2.0 ProfessionActions: planned professions not learned (Plan.lua classes.profs)
  -> "Learn X" + nearest trainer (WFL.TrainerPoint, now exported) with arrow; gatherers -> "Gather here: <nodes
  your skill can pick in this zone> (skill)" (zones.<zone>.nodes, else gatherNodes) and "Next: Tin at 65 (54 to
  go), Silver at 75" + the next rank ("Journeyman Mining at skill 50"); Skinning by beast level (Classic rule:
  up to 10 any, 11-20 (L-10)x10, 21+ Lx5; "Skin beasts up to level 16"); when a rank can be trained or the skill
  is capped -> "Train Journeyman X" + trainer, then the craft/gather step. Core 3.36.0: Plan.lua gatherNodes (herb
  and ore skills, Classic, not checked), item tooltip "WFL: Herbalism 70 to gather (you: 45)" (red when short).
  Fake game: `planner crafter` shows the Learn lines. Not seen in game.

- **2026-10-16** (Claude): The new beta characters are on realm **"Classic Beta PvP 2"** (realm id 4613; the old
  one was 4619). The save file gets each character when it logs in (23:11: only Kaspin 5). `make roster` shows
  it on the dashboard as "Classic Beta PvP 2 (WoW Forever Beta)".

- **2026-10-16** (Claude): The user re-created the 9 characters on beta (Classic Beta PvP, ~21:42-21:48); the
  game's name rules forced 4 changes, now in guide.json: **Kaspin Lovac** (hunter), **Pally Rifle** (paladin),
  Konan **Unistitelj**, Travar **Vracevgajski** (also the reserve step and the BS supply tip). Banka not created
  yet: "creation is throttled" after 9 characters. Core 3.35.5 (Plan.lua teamNames), installed. New characters appear in the save file after logout + Sync.

- **2026-10-16** (Claude): Old beta PvP characters removed from the save file and the dashboard (see section 6,
  "Beta restart"). History database kept (personal/backups/history-2026-10-16.sqlite made by make roster).

- **2026-10-16** (Claude): Backup of the beta WTF folder + history.sqlite before the user's character reset
  (personal/backups/beta-WTF-before-reset-2026-10-16/, checked with diff). Ghost cleanup still to do. 21:35 check:
  the game was still running; WTF character-list-order.txt showed only Vestac (GUID 00D0CA3F, level 18) left on
  Classic Beta PvP (realm 136) and no new characters yet. Clean up only with the game closed (it overwrites the
  save file on logout). 21:37: user says all PvP characters are deleted; the list file (rewritten 21:36) still
  had GUID 00D0CA3F on realm 136; the game was still running. Plan: with the game closed, remove every
  "Classic Beta PvP" character (all are old).
  **Done 21:39 (game closed):** 24 old PvP character blocks removed from WoWForeverLeveler.lua (DB 9, QuestLog 6,
  Recipes 4, UI.have 4, UI.bankChars Postarka); account data unchanged (counts checked with lupa); the 21:34
  file is in the backup folder (SavedVariables-2134/). `make roster`: the beta realm has no characters now (the
  new ones were not in the save file yet: they appear after log in + Sync). The dashboard falls back to
  Ashbringer (old Classic Era characters from the Battle.net sync, unrelated to Forever).

- **2026-10-16** (Claude): Mount price from the user: riding 80 + mount 20 = 100 gold (money.mountGoal, route
  line, Mount gold page, checklist step "check it in game"). Launch "create all 10" step as an icon list.

- **2026-10-16** (Claude): Launch checklist cut to 8 steps (user: too long): before launch (reserve Lovac Kasapin,
  Vestac Zla, Pala Rifle; pre-download + "launch check"; new client secret), launch day (create all 10
  characters right away for the names, auto-ticks when all exist on live; make addon + Needed addons; log in
  each + Sync), first week (daily Auctionator scan; mount price). Beta test sections removed. Carry list keeps
  10 bandages (user).
  The "create all 10" step shows the characters as a 2-column list with class icons, race, class and play
  order (checklist item `characters: true`, js/launch.js charList; ✓ when the character exists on live).

- **2026-10-16** (Claude): Dashboard character route without quests (user: the addons guide quests): js/route.js
  QUEST_STEPS (tip, must, skip, quest, pickup) are filtered out of buildRoute; dungeons are one line (name,
  levels, run at, Legacy) with no quest list. Zones keep profession, buy, money, bank, fishing, travel, class
  tip lines. Test updated.

- **2026-10-16** (Claude): "Always carry" kit made short (user: too many bag slots, vials not needed): Hearthstone,
  gathering tools, Fishing Pole, 3 Basic Campfire Kits, 10 food, 10 water (mana users), 1 stack of healing
  potions, 10 bandages (user: keep them), 5 bait. No camp object materials (vials, fish) any more; zone shopping buys
  3 Simple Wood instead of 5 wood + 5 vials (js/charmoney.js carryList, zoneShopping; test updated).

- **2026-10-16** (Claude): Other first names removed (user: "quite bad"): guide.json `altNames` gone from all
  characters and the bank, the card line, and the launch checklist texts ("If a full name is taken, pick a new
  first name"; Travar is Skyborne there now). Plan.lua teamNames = the 10 planned names. Core 3.35.4, installed.

- **2026-10-16** (Claude): Launch-plan cards on the dashboard are minimal (user: the addons hold the quest and
  route tips): name, race, class, professions, play order badge (#1-#6 from new guide.json `order`; "Open" for
  7-9; Bank), other first names. No route steps on planned cards (js/characters.js plannedCard); planned cards
  sort by `order` (js/app.js plannedChars). Created characters' cards still show their next 2 steps.
  Class icons: a class symbol (emoji) in a round badge with the class colour on every card and the character
  page (js/characters.js classIcon; bank = 💰). Wowhead's icon images (wow.zamimg.com) do not load here (403).

- **2026-10-16** (Claude): Professions rethought with the user: Legacy crafting points are once per account
  (web check), ore was the bottleneck (5 ore crafters, 2 miners). Fixed: Konan **Mining + Blacksmithing**, Ubica
  **Mining + Engineering** (guide.json profs, zone tips, weapon tips "ask Konan (Blacksmithing)", "ask Ubica or
  Travar (Engineering)"). Characters 7-9 open. Core 3.35.3 (Plan.lua), installed; dashboard checked.

- **2026-10-16** (Claude): **Own Forever profession data** (user: Minor Healing Potion is First Aid now; Polestar
  uses Classic recipes). New scripts/forever_profs.py -> data/forever_recipes.json + data/forever_profs.json;
  scripts/polestar_profs.py and data/polestar_profs.json removed. Core 3.35.2 (Plan.lua). Alchemy now starts
  "Make 19 Elixir of Minor Defense to 20"; Tailoring 1-150: 406 Linen, 648 Wool, 128 Silk. make test OK, fake
  game OK, installed. Not seen in game. Open: guide.json professions (recipes, milestones, greens) are still
  Classic data (tooltips, dashboard); First Aid / Cooking paths not wired; faction of vendor recipes.

- **2026-10-16** (Claude): guide.json `addons` regrouped (user): Needed = Polestar (5 folders), Auctionator,
  Questie + QuestieDB; **Data only** = Forever Loot, DFL (Sync's dungeon_addons.py reads their files; can be off
  in game); Optional = TomTom; **Later** = Spoken addons + Spoken Zones (place history, was ZoneLore); **To try** =
  SkillUp Forever, HandyNotes + Books, Layer Swap, OPie (user's pick; EasyMarksForever dropped, RestedXP moved
  to Not needed: Polestar does the same).
  Launch tab shows the new groups (js/launch.js).

- **2026-10-16** (Claude): Stock counting confirmed from the save file (Lovac: Linen 31, Wool 10). **Polestar
  merge:** new `scripts/polestar_profs.py` -> `data/polestar_profs.json`; build_guide uses it for matPlan
  (`src: "Polestar"`) and craftSteps; Planner 2.1.1 / mockups use the step's craft count (CraftsLeft); core
  3.35.1 (Plan.lua only). `tests/addon_fakegame.py planner crafter` = Tailoring 60 + Enchanting 120 (shows
  "Make 26 Linen Belt to 75", 88 / 408 Linen). make test OK, installed. Not seen in game. Uncommitted.

- **2026-10-16** (Claude, session summary): Polestar review and plan (tag own-3.31.0); split into core + Quests +
  Planner; dungeon chains with full quest paths and entrances; craft steps, material totals, team totals; bank
  character with Market tab (Auctionator prices); Planner 2.x built from mockups.html (Next / Dungeons /
  Professions / Team, bank: Next / Market / Team); fixes from in-game screenshots (tabs, menu, counting). Section 0
  rewritten as the handoff. Open: in-game checks listed in section 0, buffs list, Polestar merge.
- **2026-10-16** (Claude): core 3.35.0 / Planner 2.1.0: item lines (materials, market) carry line.item: hover shows
  the game's item tooltip (GameTooltip:SetHyperlink via WoWForeverLevelerItemIDs) plus our lines; Shift- or
  Ctrl-click inserts the name into the focused edit box (AH / Auctionator search, mail), else the open AH search
  box (AuctionHouseFrame.SearchBar.SearchBox), else the chat line as a link. Told the user how much to trust the
  market tips: Sell = turn extras into gold, Buy cheap = save vs usual, Craft to sell = real profit (5% cut in, no
  deposit, no undercut risk); beta data is thin (13 scans), improves with daily live scans.
- **2026-10-16** (Claude): core 3.34.2 / Planner 2.0.2: **bag/bank counting never worked** (WoWForeverLevelerUI.have
  empty): the Forever client has only C_Item.GetItemCount, the code checked the missing global and returned. Now
  C_Item first, errors to the log ("UI error count"), and a redraw after each count. Redraw also on
  MAIL_INBOX_UPDATE, UPDATE_PENDING_MAIL, AUCTION_HOUSE_CLOSED; count on MAIL_CLOSED. Bank characters (plan name,
  spares, menu switch; the user switched Postarka on for a test) are left out of the rotation. Bank Next "Mail"
  is live (HasNewMail: "new mail is waiting" / "nothing new").
- **2026-10-16** (Claude): core 3.34.1 / Planner 2.0.1 after the user's menu screenshot: menu 230 px wide (the
  bank switch was cut off); the Planner removes the "Profession macro" and "Quest macro" menu entries (Polestar /
  RestedXP target quest monsters, the arrow leads to NPCs; macros on bars keep working; the Quests window keeps
  them); Team lists only planned names (Plan.lua teamNames = names + altNames + bank; Postarka, a test character,
  left out) plus the character logged in.
- **2026-10-16** (Claude): Quests 1.0.1: steps aside (registers no tabs) when the Planner is loaded or enabled;
  the user's screenshot showed 7 tabs with both on. Planner and Polestar seen together in game (Sveti, Durotar).
- **2026-10-16** (Claude): **Planner 2.0.0 built in game** from the mockup (user's choice A for the bank: name
  in the plan + menu switch). Who is the bank: WoWForeverLevelerUI.bankChars[name-realm] (minimap menu "This
  character is the bank") else the plan's bank name/altNames (Plan.lua bank). Tabs can hide themselves
  (tab.visible; core TabShown/CurrentTab/layoutTabs, WFL.Relayout): leveling = Next, Dungeons, Professions,
  Team; bank = Next, Market, Team. Next: Dungeons (DungeonActions: per chain the first open quest, starts in
  your zone first, then "Run X", "Reach level N"), main professions now/after (craftSteps, capped at the trainer
  rank), Team (keep playing / switch to most rested), Legacy. Dungeons: 3 stops, entrance arrows, chains
  (ChainGroups from Plan.lua pickups[].chain). Professions: now/after + current bracket materials (have = all
  characters). Team: rotation + team materials for every crafter's current step. Market: Auctionator in-game
  price by item ID (WoWForeverLevelerItemIDs) else Plan.lua prices.last; usual = Plan.lua prices.usual (median
  of Sync scans, build_guide); vendor from item info; sell / buy cheap / craft to sell / hold. Core exports
  WFL.menu, AuctionPrice, MaterialHave, ItemIcon, QuestObjectives, Complete, Refresh, Relayout. Not seen in game.
- **2026-10-16** (Claude): mockups.html = everything together: ONE window as in game with "logged in as"
  buttons (Lovac, Vestac, Sveti, Banka); tabs change by character (leveling: Next, Dungeons, Professions, Team;
  Banka: Next, Market, Team; open folds and tab kept per character), plus a "How it fits together" panel (tabs
  by character, what each tab is for, where the data comes from, a day with the team). Next step after the
  user's OK: build it in game (Planner addon: port view(), stops/chainGroups/actions, market; bag+bank counts
  per character already saved in WoWForeverLevelerUI.have; prices from Auctionator's in-game API + history).
- **2026-10-16** (Claude): mockup: 4th window **Banka** (bank character; user: everyone mails her almost
  everything; she sells, buys, trades) with tabs Next / Market / Team. Market uses the real Auctionator prices
  (data/prices.js: 2338 items, 13 beta scans 2026-09-28..10-07): Sell now (team stock above the crafters' current
  needs, AH x0.95 >= 1.5x vendor and >= 5c, by total value), Buy cheap (what crafters still need at <= 80% of the
  usual = median of earlier scans), Craft to sell (steps up to each crafter's skill: product AH price x0.95 minus
  materials at AH prices), Hold (price < 70% of usual). Next on Banka: Market now/after + best craft, Mail
  (collect, send crafters their step's materials), Team. Stock = sample (low-level items only) until each
  character counts its bags in game; "last scan N days ago: scan again" warning.
- **2026-10-16** (Claude): mockups.html rebuilt with only the new Planner design (user: tabs Dungeons,
  Professions, Team plus a first tab **Next** = now + one step after for each area, updating as steps are done):
  three windows with real data (scripts/mockup_state.py picks the highest, a middle and the lowest level
  character of the plan: Lovac 25, Vestac 18, Sveti 4; mockup_state.js = {chars, team}; stale "accepted" quests
  dropped). Next: Dungeons (first action of the next stop: take/finish/hand in per chain, starts in your zone
  first, then "Run X"; "Reach level N" when too low), Professions (craft step now + after, capped at the trainer
  rank; gatherers: gather / train at cap), Team (keep playing or switch to the most rested, then the next),
  Legacy. Dungeons tab: next 3 stops with entrance and quest chains. Professions tab: now/after + materials of
  the current bracket. Team tab: rotation + team materials for every crafter's current step (to Banka, "sell N").
  Waiting for the user's verdict, then build it as the Planner addon (Lua port of these functions).
- **2026-10-16** (Claude): Frostadamus addon video read (OPie, Node on minimap, RestedXP, HandyNotes + Books
  (library quest: 10/20/30 Tomes = blue rewards), EasyMarksForever, SkillUp Forever (best craft per skill point +
  AH cost), Layer Swap); suggested to the user, not added to guide.json `addons` yet. User: "less data": no zone
  quests, only dungeons with clear where/arrow; short crafting lines; team material totals on the bank character
  (Banka gathers mats and trades on the AH). Built mockup **E · one page (simple)** in mockups.html (button "view
  as Banka"): Next (dungeon chain, Legacy, rested switch), the dungeon chain with each dungeon's entrance and its
  quests grouped by chain start (start "!", then each next quest, dungeon quests marked, NPC + zone + spot),
  Team, Professions (one line per profession: "Make N <recipe> to X, then train"; Plan.lua `craftSteps` from
  levelWith), on Banka: Team crafting (every crafter's line) + Team materials (all characters' have / team need,
  "sell N" for extras; have = sample). Waiting for the user's verdict, then build E as the Planner addon.
- **2026-10-15** (Claude, cut off by usage limit): data for dungeon quest chains built: build_routes `_chainPaths`
  -> Plan.lua pickups[].chain = every quest before a dungeon quest, first first (e.g. Forgotten Pools > Stagnant
  Oasis > Altered Beings > Hamuul Runetotem > Nara Wildmane > Leaders of the Fang), with giver and spot. Planner
  Team keeps one save per name (newest). mockup_state.py writes the team. OPEN: (1) show the chains in
  DungeonLines (one block per chain start, the next quests under it, dungeon quests marked, done ones hidden);
  (2) mockup "E: one page, no tabs" in mockups.html with blocks Next / Team / Professions / Buffs (user chose
  mockup first, then build); (3) buffs from potions/elixirs/food (Polestar_Codex recipes). Uncommitted.
- **2026-10-15** (Claude): 3.33.1: an opened dungeon shows "Entrance: <zone> x, y, run at A-B" with an arrow
  (QuestieDB support/Forever/Zones/dungeons.lua base table -> routes.js _entrances -> Plan.lua runs[].entrance;
  17 of our dungeons), then chain starts and quests with "NPC, zone x, y" under the name (live objectives when in
  the log), sorted by zone so each city is one trip.
- **2026-10-15** (Claude): 3.33.0: split into core + Quests + Planner (see section 0). Planner Plan tab: the core
  Plan lines, Dungeons (next 3 stops with open quests you can still run, chains as one stop with their dungeons
  and chain starts), Team (every character of the realm, most rested first, level, rested %, inn or outside,
  professions on hover; green when worth switching to), Camp buffs (camp objects some character can build now,
  later ones with the skill gap). Professions tab: the profession topics + materials. Next: buffs from potions,
  elixirs, food (team's skills, useful for the class) from Polestar_Codex recipe data.
- **2026-10-15** (Claude): 3.32.1: Travar (Druid) is now **Skyborne** (user's choice): route starts on Zephras Isle
  (Skyborne start, levels 1-12; Polestar: next The Barrens via the skyboat to Orgrimmar), build_routes knows
  Zephras Isle (map 2521): 119 quests built; the race filter may still let Alliance-only Skyborne quests in (not
  checked). Skyborne classes in guide.json races (Warrior, Hunter, Rogue, Druid, Shaman) not checked in game.
- **2026-10-15** (Claude): 3.32.0: "Plan" section at the top of the Now tab (open by default): Next (a dungeon
  chain/dungeon whose quests open within 3 levels, else "Move on to <next zone>" one level before the zone's
  top), Legacy (next character level 25/45/60 and each crafting profession's next 150/225/300), Rested (yours and
  the account's best other character from WoWForeverLevelerDB: saved restedXp/maxXp + 5% of a level per 8 h
  resting, a quarter outside, cap 1.5; green "switch to X" when yours is gone and theirs >= 30%). The user starts
  Sveti (Troll Shaman, Alchemy + Leatherworking) in Durotar to test Polestar.
- **2026-10-15** (Claude): Polestar checked (addons Polestar, Polestar_Guides, _QuestDB, _ItemDB, _Codex; GPL-3.0,
  github.com/fitzforge/polestar; data from pfQuest (MIT) and Forever quest XP sites). 158 guides: Horde leveling
  1-60 (28 guides + starting zones, ~1000 quests, 187 Forever-new, steps with NPC, spot, kill/collect spots,
  flight paths, hearth, notes), professions 1-300 (all 12, craft counts, collect counts, cost per bracket; counts
  far above our material_plan, e.g. Tailoring 1482 Wool, Leatherworking 1666 Light Leather), reputation,
  exploration, mounts, pets, Legacy challenges. No Riverglades. Read with lupa: Polestar.RegisterGuide stub +
  Polestar_Guides/Guides.lua. User's plan: our version saved as tag `own-3.31.0`; the user tests Polestar on a
  new character; if good, fork it and merge: Polestar = quest details, ours = high-level plan (zone, dungeon
  chain, Legacy points, profession targets, rotation with rested XP, team names/professions/supply chain).
  The journey recorder records the Polestar test character, so the two can be compared.
- **2026-10-14** (Claude): 3.31.0 = mockup "D as in game" (user: "make it look like the browser"): flat window
  (dark fill, 1-px gold edges, title bar, flat buttons A- A+ "+ all" x, flat tabs, parchment color list, no
  Blizzard frame art), shipped fonts addon/WoWForeverLeveler/Fonts/NotoSans-Regular.ttf + NotoSans-Bold.ttf (Noto
  Project, SIL OFL, OFL.txt next to them; game font fallback), rows with a bold title FontString + regular text
  (inline when it fits, topic summaries right-aligned, objectives below). `make addon` now copies folders
  (cp -R). New files: needs a full game restart. Not seen in game yet.
- **2026-10-14** (Claude): 3.30.3: dungeons count as due only up to their run levels + 2 (Wailing Caverns showed
  "Dungeon now" for Lovac at 25); the addon applies guide.json routeChoices (Plan.lua routeChoices, being in a
  zone of an option picks it, kept in WoWForeverLevelerUI.routeChoice): Lovac in Hillsbrad gets Hillsbrad in his
  Route tab instead of Stonetalon.
- **2026-10-14** (Claude): 3.30.1-3.30.2 after the user's in-game screenshots (Cmd+Shift+3 -> Desktop, read and
  scaled with sips): window drawing errors now go to WoWForeverLevelerLog ("UI error ..."); tab buttons share the
  width for any number of tabs (Route and Materials overlapped); Do next shows one line per quest (take, then
  objectives while in the log, hand in only when ReadyForTurnIn: IsComplete said true for talk-to and dungeon
  quests); check box at the top right of multi-line rows.
- **2026-10-14** (Claude): 3.30.0 = mockup version D built (user's pick). Tabs **Now | Route | Materials**
  (/wfll opens Route). Now: Do next with Blizzard quest icons (gossip AvailableQuestIcon "!" = take,
  ActiveQuestIcon "?" = hand in, desaturated "?" = in your log with live objectives from GetQuestObjectives,
  spyglass = not taken yet), NPC grey after the name, spot/zone on hover (row tooltips), then the profession
  topics. Route: all route zones and dungeons (no wrapper fold), dungeon quest lines with icons, Skipped here.
  Materials: per profession and bracket one row per raw material with a StatusBar "have / need" (gold when
  enough); have = bags + bank of every character (WoWForeverLevelerUI.have[name-realm], counted 2 s after
  BAG_UPDATE_DELAYED / BANKFRAME_CLOSED and at login; each character counts itself once logged in).
  Not seen in game yet: icons, desaturation, bar look, GetItemCount with bank.
- **2026-10-14** (Claude): UI rework started (user: "jumbled, unclear"). User's picks: 3 tabs (Now / Route /
  Materials), step icons (! do ?), materials table with have/need (needs bag+bank counts per character in the
  addon), one line per thing with details on hover, compare versions as HTML mockups first. Window stays
  resizable with font buttons; columns/size and a dark look decided later; parchment for now.
  `mockups.html` (http://localhost:8765/mockups.html) draws versions A (3 tabs, icons), B (2 tabs, icons),
  C (3 tabs, quest-tracker style) from data/addon_plan.js (make guide writes it) and data/mockup_state.js
  (`python3 scripts/mockup_state.py Pala`). Next: user picks, then build the winner in UI.lua; after that the
  dashboard (characters to create, what each learns, synced from the game) gets the same treatment.
- **2026-10-14** (Claude): 3.29.0, after Ceedsy's "Alt Army Blueprint" (video + Google Doc, not checked):
  user starts with 3 characters (Lovac, Pala gather; Vestac Tailoring + Enchanting) and adds more later; 4th =
  Sveti, now Alchemy + Leatherworking (Mana Well, Camp Tent raises rested XP; herbs/leather from Lovac and Pala).
  Group 3 still doubles Alchemy/Engineering/Blacksmithing: revisit. Legacy order kept: Well Rested first (Ceedsy:
  Working Overtime). New: build_guide material_plan (raw materials per crafting profession 1-150/150-225/225-300,
  one craft per point +15%, leathers count as gathered, bars expanded to ore, vendor items apart; Blacksmithing
  data ends at 225) -> Plan.lua matPlan/matNeed; Professions tab "Save for crafting"; item tooltip second WFL
  line "Team needs about N (Tailoring 840, ...)". Dungeon chain block (guide.json dungeonChains: RFC > RoL > WC)
  as one stop under All route zones; every dungeon shows "Start chain: X - NPC (leads to Y)" from QuestieDB
  prerequisites (The Forgotten Pools -> Leaders of the Fang, Raptor Horns -> Smart Drinks).
- **2026-10-14** (Claude): 3.28.1 (user: "no pin, reuse Blizzard quest tracking"): a check box on a quest that is
  in your log also selects it in the game (C_SuperTrack.SetSuperTrackedQuestID + C_QuestLog.SetSelectedQuest: the
  highlighted quest marker on the map). "Take" steps get only the TomTom arrow. Clearing clears only a quest we
  selected. No user waypoint pins (3.28.0 tried that; removed). Result logged once ("quest tracking: ...").
- **2026-10-14** (Claude): 3.27.0: no zone title row on the Leveling tab (the zone showed twice); "Do next" names
  the zone and level; zones under All route zones start closed.
- **2026-10-14** (Claude): 3.26.0 (user's choice A): hub lists removed from the Leveling tab. It is now: zone
  title, Do next, Skipped here, All route zones (your zone open by default, marked "you are here").
- **2026-10-14** (Claude): 3.25.0: every title row has the game's plus/minus button texture (open or closed at a
  glance); header button "+ all" / "- all" opens or closes every topic of the tab (3 rounds when opening, for
  nested topics).
- **2026-10-14** (Claude): 3.24.0: dungeons are stops in "All route zones", placed after the last route zone
  starting at or below the level where all its quests can be taken (or its run level). Each shows quest count,
  "take all from level N", run levels; open = one check box per quest giver; "All quests taken: run it". A green
  "Dungeon now" line under Do next when one is due. Other classes' dungeon quests hidden (QuestieDB masks).
  The Riverglades shows 0 quests: the zone is above the beta level cap (content opens at launch, 2026-11-04).
  Checked 2026-10-14: QuestieDB has 186 NPCs there but 0 quests, forevervsclassic.com lists 0, RestedXP files
  have nothing, web guides only describe it (35-45, Rog'mar = Horde town, Boulder Rock ogres, Krol'dok
  Stronghold 40-45). After launch: update QuestieDB, run `python3 scripts/zone_quests.py` and `make routes`.
- **2026-10-14** (Claude): 3.23.2: a recorded route now ends with Do / Hand-in steps for quests the recorder
  took but did not finish (Do steps nearest first, then hand-ins in town, city, next zone). RestedXP save shows
  Pala at level 13 on "06-12 Tirisfal Glades" step 161; its Forever guide text is not in local files (not read).
- **2026-10-14** (Claude): Addon 3.23.0: route rules learned from Pala's RestedXP recording (delivery quests,
  profession quests, item starters), all route zones in the Leveling tab, high quests hidden, Undercity givers.
- **2026-10-13** (Claude): Quest routes. Addon 3.22.0 records accept/done/turnin with map spots and shows "Do
  next" on the Leveling tab with right-click skip. New scripts/questie_db.py (QuestieDB Forever data) and
  scripts/build_routes.py (recorded + built routes, hassle skips), `make routes`, Sync runs it. Open: in-game
  test on another character; check built routes 20+ while playing.

- **2026-10-09 to 10-13** (Claude): Big session, now game first. Dashboard work first (optional ClassicDB quests,
  weapon skills, route choices, RestedXP mode, secondary professions + camping, shopping/mail/bank/fishing lines,
  own quest hubs after 20, beta-vs-live data fix), then the addon became the main tool: addon 3.7 -> 3.21 (shop
  prices, journey log, in-game window with tabs Professions/Leveling, minimap icon + menu with secure Sync,
  TomTom arrows + check-box selection + WFL Prof macro, WFL Target quest macro (RestedXP-safe), item tooltip
  advice, trainer DB with nearest trainer, quest list per zone, Blizzard/parchment look). Pala Rife (Undead
  Paladin, beta) played to level 10: Deathknell start, Marla's Last Wish book = free Skinning, Forever vendor
  prices far below Classic. Gillee gold video: First Aid bandage profit, level 60 quest gold, AH timing.
  Open: quest guidance in the Leveling tab (next), in-game checks of the window, item tooltip in game.

- **2026-10-09 to 10-12** (Claude): 💡 optional quests from ClassicDB; Legacy data checked against IGN (the
  user's 16 points are Blizzard's beta grant); weapon skills per class and trainer; ordered beta tests (cut to
  3); zones tick from quest turn-ins; 20-30 route choice (Kalimdor / Hillsbrad); shorter route text; RestedXP
  mode (quests hidden below level 20); camp objects with materials and per-character picks; First Aid,
  Cooking and Fishing for every character with a "🧭 Secondary & camp" card. Open: Cooking/Fishing meat and fish
  sale prices (no Auctionator data yet), confirm camp picks and First Aid steps in game.

- **2026-10-09** (Claude): 37 💡 optional quests (green/blue rewards, high XP) added to 19 route zones from
  ClassicDB; optional lines with an id tick themselves and link to ClassicDB. The test hunter already did 3 of
  them (they show as done). Legacy data checked against the IGN wiki (matches; rewards, PvP/explore/raid
  challenges and 2 perks added). The user's 16 Legacy points are Blizzard's beta grant (Air Rifle reward quest
  96339 on 2026-10-09), not earned. Weapon skills line + guide.md tables. Open: confirm in game; Forever quest
  XP may differ from Classic.

- **2026-10-01 to 10-09** (Claude): Long session. Auction prices now come from Auctionator (our scan removed);
  dungeon quests from Forever Loot + DFL; route folds by zone (General / By level), dungeon plan lines (run
  levels, collect-from level, full-XP level, quest XP, city travel), ⭐ must-do and 💡 optional quests, level 1
  start steps from the user's beta hunter test (free profession quest, 20c skinning, 25c gathering bag, no
  bag materials before level 6, mailbox), bag plan with Banka (Tailoring for bags, 30c per bag after the level
  10 skills), skill needed per herb/ore/leather, Rested XP and Legacy cards (Well Rested then Talented),
  Forever weapon paths for all 9 classes (downgrades hidden, crafter named), addon 3.0 -> 3.6.1 (Auctionator
  link, completed quests, class trainer + rank costs, GUID keys + last name, rested XP, bag vendors, NPCs read
  once per patch, Interface 16001), launch tab addon list (Questie needed, Spoken optional). Many YouTube
  videos read via the browser pane (captions: hook XHR, toggle CC, skip ads by ref). Open: sections 5-6.

- **2026-10-01** (Claude): Read 4 videos (professions, day-1 gold, Dungeon Journal addon, bank alt with
  Arcane Salvager). No plan change; claims noted in section 3. Advice: keep our auction scan, use Auctionator
  and Forever Dungeon Journal in game. YouTube captions: hook XHR, then toggle the CC button; a running ad
  blocks them (click the Skip button by ref). Then switched auction prices to Auctionator (user's choice):
  addon 3.0.0 drops its own scan and saves item IDs, vendor prices and Auctionator's realm key;
  `scripts/auctionator.py` decodes Auctionator's CBOR database (confirmed working). Dungeon quests from the
  user's Forever Loot and DFL Dungeon Journal addons now appear in the route; addon 3.1.0 saves completed
  quest IDs. Open: confirm 3.1.0 in game.

- **2026-09-30** (Claude): New layout with top tabs; character page = Route / Professions / Money; bank
  character Banka Posta; characters match the plan by first name. Per-character Money tab and addon 2.5.0
  vendor prices. Quest skips replaced by ClassicDB Elite quests (the old list had retail-only names).
  Weapon/wand upgrade paths per character from ClassicDB quest rewards. README and this file rewritten as
  a full handoff. Open: section 6.
- **2026-09-29** (Claude): Sync waits for the save file. Planned characters as grey cards; names chosen
  (see section 1). Trainers page + addon trainer/vendor positions (2.3.x) and the "Trainers to visit"
  window (2.4.0), confirmed in game. Launch checklist. Money methods from two beta videos (Brown Linen
  Pants, Heavy Copper Mace); user's beta test: bags at 15s sold, pants a small loss at 88c linen.
- **2026-09-28** (Claude, session 2): Zone cards for all characters, automatic zone progress, addon 2.2.0
  auction panel (minutes box, Full download), `/wfl dump` confirmed, one Dock app for the dashboard.
- **2026-09-28** (Claude): Built most of the system: addon 1.1 -> 2.1.1 (modern APIs, recipes, trainers,
  vendors, auction scan), dashboard pages, SQLite history with backups, Forever beta guides, new zones and
  dungeons, race-based start zones, tests and launch check.

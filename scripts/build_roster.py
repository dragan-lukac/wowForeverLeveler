#!/usr/bin/env python3
"""
Builds personal/roster.js for the dashboard from two sources:
  1. personal/account_characters.json (Battle.net sync, see sync_characters.py)
  2. WoWForeverLevelerDB SavedVariables written by the in-game addon (any local WoW flavor)
index.html loads roster.js with a <script> tag, so the dashboard works from file:// without a server.
"""

import os
import re
import glob
import json
import time

import history_db
import auctionator
import dungeon_addons

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, 'data')
PERSONAL_DIR = os.path.join(ROOT, 'personal')  # your characters: personal, not in git
BNET_SOURCE = os.path.join(PERSONAL_DIR, 'account_characters.json')
OUTPUT = os.path.join(PERSONAL_DIR, 'roster.js')
PRICES_OUTPUT = os.path.join(DATA_DIR, 'prices.js')
TRAINERS_OUTPUT = os.path.join(DATA_DIR, 'trainers.js')
VENDORS_OUTPUT = os.path.join(DATA_DIR, 'vendors.js')
NPCS_OUTPUT = os.path.join(DATA_DIR, 'npcs.js')
DUNGEONS_OUTPUT = os.path.join(DATA_DIR, 'dungeons.js')

WOW_ROOTS = [
    "/Applications/World of Warcraft",
    os.path.expanduser("~/Applications/World of Warcraft"),
]

KNOWN_CLASSES = {"hunter", "warlock", "paladin", "priest", "shaman", "warrior", "mage", "rogue", "druid"}
CLIENT_LABELS = {"classic_beta": "WoW Forever Beta", "classic": "Classic", "classic_era": "Classic Era", "retail": "Retail"}
RACE_NAMES = {"Scourge": "Undead", "Orc": "Orc", "Tauren": "Tauren", "Troll": "Troll", "Undead": "Undead"}


def slugify(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')


# --- Minimal Lua table parser for SavedVariables files ---

LUA_TOKEN = re.compile(r'''
    \s+ | --\[\[.*?\]\] | --[^\n]* |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?) |
    (?P<word>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<sym>[{}\[\]=,;])
''', re.VERBOSE | re.DOTALL)
LUA_LITERALS = {'true': True, 'false': False, 'nil': None}


def lua_tokens(text):
    pos = 0
    while pos < len(text):
        m = LUA_TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"Unexpected Lua at offset {pos}: {text[pos:pos + 20]!r}")
        pos = m.end()
        if m.group('str') is not None:
            yield ('val', json.loads(m.group('str')))
        elif m.group('num') is not None:
            n = m.group('num')
            yield ('val', float(n) if any(c in n for c in '.eE') else int(n))
        elif m.group('word') is not None:
            w = m.group('word')
            yield ('val', LUA_LITERALS[w]) if w in LUA_LITERALS else ('name', w)
        elif m.group('sym') is not None:
            yield ('sym', m.group('sym'))


def parse_saved_variables(text):
    tokens = list(lua_tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, tok = tokens[i]
        if kind == 'sym' and tok == '{':
            return table()
        i += 1
        return tok

    def table():
        nonlocal i
        i += 1
        result, auto_index = {}, 1
        while not (tokens[i] == ('sym', '}')):
            if tokens[i] == ('sym', '['):
                i += 1
                key = value()
                i += 2  # ']' '='
                result[key] = value()
            elif tokens[i][0] == 'name' and tokens[i + 1] == ('sym', '='):
                key = tokens[i][1]
                i += 2
                result[key] = value()
            else:
                result[auto_index] = value()
                auto_index += 1
            if tokens[i][0] == 'sym' and tokens[i][1] in ',;':
                i += 1
        i += 1
        # Arrays (keys 1..n) become lists; tables keyed by IDs ([209] = ...) stay dicts.
        if result and sorted(result) == list(range(1, len(result) + 1)):
            return [result[k] for k in sorted(result)]
        return result

    variables = {}
    while i < len(tokens):
        name = tokens[i][1]
        i += 2  # name '='
        variables[name] = value()
    return variables


# --- Sources ---

def load_bnet(realms):
    if not os.path.exists(BNET_SOURCE):
        return
    with open(BNET_SOURCE, 'r', encoding='utf-8') as f:
        namespaces = json.load(f)
    for ns, payload in namespaces.items():
        for account in payload.get("wow_accounts", []):
            for c in account.get("characters", []):
                if c.get("faction", {}).get("type") != "HORDE":
                    continue
                key = c.get("playable_class", {}).get("name", "").lower()
                if key not in KNOWN_CLASSES:
                    continue
                realm = c.get("realm", {})
                entry = realms.setdefault(realm.get("slug", "unknown"), {
                    "title": f"{realm.get('name', 'Unknown')} (Battle.net Sync)",
                    "subtitle": f"Characters synced via official Battle.net OAuth API ({ns}).",
                    "status": "Battle.net Synced",
                    "chars": []
                })
                entry["chars"].append({
                    "key": key,
                    "name": c.get("name"),
                    "level": str(c.get("level", "?")),
                    "race": c.get("playable_race", {}).get("name"),
                    "active": True
                })


def plan_ids():
    """First name -> plan id from data/guide.json, so two characters of one class stay apart."""
    try:
        from team import load_guide
        g = load_guide()
    except (OSError, ValueError):
        return {}
    chars = g.get('characters', []) + ([g['bank']] if g.get('bank') else [])
    return {c['name']: c['id'] for c in chars if c.get('name')}


def load_addon(realms, prices, trainers, vendors, npcs=None, sell_prices=None, daily_prices=None, class_trainers=None,
               bag_vendors=None, shop_prices=None):
    by_name = plan_ids()
    pattern = "WTF/Account/*/SavedVariables/WoWForeverLeveler.lua"
    for root in WOW_ROOTS:
        for path in glob.glob(os.path.join(root, "_*_", pattern)):
            flavor = path[len(root) + 1:].split(os.sep)[0].strip('_')
            with open(path, 'r', encoding='utf-8') as f:
                sv = parse_saved_variables(f.read())
            db = sv.get("WoWForeverLevelerDB") or {}
            all_recipes = sv.get("WoWForeverLevelerRecipes") or {}
            quest_logs = sv.get("WoWForeverLevelerQuestLog") or {}
            # Every key carries the game client (beta, live, ...) so data from different
            # clients never mixes, even when realm names match.
            for scope, items in (sv.get("WoWForeverLevelerPrices") or {}).items():
                prices.setdefault(f"{flavor}|{scope}", {}).update(items)
            for prof, recipes in (sv.get("WoWForeverLevelerTrainer") or {}).items():
                trainers.setdefault(flavor, {}).setdefault(prof, {}).update(recipes)
            vendors.setdefault(flavor, {}).update(sv.get("WoWForeverLevelerVendors") or {})
            if class_trainers is not None:
                for cls, skills in (sv.get("WoWForeverLevelerClassTrainer") or {}).items():
                    # Addon 3.3.1 and older saved "Track Beasts (available)": drop the status word.
                    clean = {re.sub(r' \((available|unavailable|used)\)$', '', k): v for k, v in skills.items()}
                    class_trainers.setdefault(flavor, {}).setdefault(cls, {}).update(clean)
            if npcs is not None:
                npcs.setdefault(flavor, {}).update(sv.get("WoWForeverLevelerNPCs") or {})
            if bag_vendors is not None:
                bag_vendors.setdefault(flavor, {}).update(sv.get("WoWForeverLevelerBagVendors") or {})
            if shop_prices is not None:
                # Cheapest price per item across accounts (prices drop with reputation).
                book = shop_prices.setdefault(flavor, {})
                for item, p in (sv.get("WoWForeverLevelerShopPrices") or {}).items():
                    unit = lambda x: x.get("price", 0) / max(x.get("per") or 1, 1)
                    if item not in book or unit(p) < unit(book[item]):
                        book[item] = p
            if sell_prices is not None:
                sell_prices.setdefault(flavor, {}).update(sv.get("WoWForeverLevelerSellPrices") or {})
            # Auction prices come from Auctionator's save file next to ours, named by our addon's item IDs.
            auctionator_path = os.path.join(os.path.dirname(path), "Auctionator.lua")
            if daily_prices is not None and os.path.exists(auctionator_path):
                with open(auctionator_path, 'rb') as f:
                    found = auctionator.prices(f.read(), sv.get("WoWForeverLevelerItemIDs") or {},
                                               sv.get("WoWForeverLevelerAuctionRealms") or {}, flavor)
                for scope, items in found.items():
                    daily_prices.setdefault(scope, {}).update(items)
            # Addon 3.3.0 keys characters by realm-name-GUID; an older realm-name record of the same
            # character is left out once a new one exists (two characters can share a first name).
            new_style = {(c.get("realm"), c.get("name")) for c in db.values() if c.get("guid")}
            for char_key, c in db.items():
                if not c.get("guid") and (c.get("realm"), c.get("name")) in new_style:
                    continue
                key = by_name.get(c.get("name")) or str(c.get("class", "")).lower()
                if key not in KNOWN_CLASSES and key != "bank":
                    continue
                realm_name = c.get("realm", "Unknown")
                entry = realms.setdefault(slugify(f"{flavor}-{realm_name}"), {
                    "title": f"{realm_name} ({CLIENT_LABELS.get(flavor, flavor)})",
                    "realmName": realm_name,
                    "client": flavor,
                    "subtitle": f"Characters recorded by the WoWForeverLeveler addon ({flavor} client). Updates when you log out.",
                    "status": "Addon Synced",
                    "chars": []
                })
                if any(ch.get("charKey") == f"{flavor}|{char_key}" for ch in entry["chars"]):
                    continue
                profs = c.get("professions") or []
                entry["chars"].append({
                    "key": key,
                    "name": c.get("name"),
                    "lastName": c.get("lastName"),
                    "level": str(c.get("level", "?")),
                    "race": RACE_NAMES.get(c.get("race"), c.get("race")),
                    "professions": [{"name": p.get("name"), "rank": p.get("rank"), "maxRank": p.get("maxRank")} for p in profs],
                    "updated": time.strftime("%Y-%m-%d %H:%M", time.localtime(c.get("lastUpdated", 0))),
                    "charKey": f"{flavor}|{char_key}",
                    "updatedT": c.get("lastUpdated"),
                    "recipes": all_recipes.get(char_key, {}),
                    "money": c.get("money"),
                    "xp": c.get("xp"), "maxXp": c.get("maxXp"),
                    "restedXp": c.get("restedXp"), "resting": c.get("resting"),
                    # Quest IDs done: the full list from the game, plus quests the addon saw turned in.
                    "completedQuests": sorted(set(c.get("completedQuests") or []) |
                                              {q.get("id") for q in (quest_logs.get(char_key) or {}).get("done") or [] if q.get("id")}),
                    "questZones": quest_zones((quest_logs.get(char_key) or {}).get("done") or []),
                    "active": True
                })


def quest_zones(done):
    """Zone -> time of the last quest turned in there. The dashboard ticks a route zone once the
    character turns in quests in a later zone."""
    zones = {}
    for q in done:
        zone, t = q.get("turnInZone") or q.get("acceptZone"), q.get("time") or 0
        if zone and t > zones.get(zone, 0):
            zones[zone] = t
    return zones


def addon_folders():
    out = {}
    for root in WOW_ROOTS:
        for addons_dir in glob.glob(os.path.join(root, "_*_", "Interface", "AddOns")):
            flavor = addons_dir[len(root) + 1:].split(os.sep)[0].strip('_')
            out[flavor] = sorted(n for n in os.listdir(addons_dir) if not n.startswith('.'))
    return out


def unique_names(realms):
    """The dashboard finds characters by name: two characters with one first name get their last
    name added ("Lovac Kasapin"), or a number when the last name is unknown."""
    for entry in realms.values():
        chars = entry.get("chars", [])
        for first in {ch["name"] for ch in chars if sum(c["name"] == ch["name"] for c in chars) > 1}:
            for n, ch in enumerate([c for c in chars if c["name"] == first], start=1):
                ch["name"] = f"{first} {ch['lastName']}" if ch.get("lastName") else f"{first} ({n})"


def build():
    realms, prices, trainers, vendors, npcs, sell_prices, daily_prices, class_trainers, bag_vendors = {}, {}, {}, {}, {}, {}, {}, {}, {}
    shop_prices = {}
    load_addon(realms, prices, trainers, vendors, npcs, sell_prices, daily_prices, class_trainers, bag_vendors, shop_prices)
    unique_names(realms)

    # Keep everything in the SQLite history, then export from it: the history outlives
    # the addon's 60-snapshot limit per item.
    saved = history_db.backup()
    if saved:
        print(f"[+] Database backup: {saved}")
    conn = history_db.connect()
    characters = [{
        'char_key': ch['charKey'], 'updated_t': ch.get('updatedT'), 'level': ch.get('level'),
        'money': ch.get('money'), 'professions': ch.get('professions'), 'recipes': ch.get('recipes'),
    } for entry in realms.values() for ch in entry['chars'] if ch.get('charKey')]
    added = history_db.ingest(conn, prices, trainers, characters, vendors)
    added += history_db.replace_daily_prices(conn, daily_prices)
    prices = history_db.export_prices(conn, days=30)
    trainers = history_db.export_trainers(conn)
    vendors = history_db.export_vendors(conn)
    print(f"[+] History database: {added} new price records; totals {history_db.stats(conn)}")
    conn.close()
    load_bnet(realms)

    with open(PRICES_OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py from Auctionator's auction house prices. Do not edit by hand.\n")
        f.write("window.PRICES = ")
        json.dump(prices, f, ensure_ascii=False)
        f.write(";\n")
        f.write("// What a vendor pays for one item, per game client.\n")
        f.write("window.SELL_PRICES = ")
        json.dump(sell_prices, f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Prices: {sum(len(items) for items in prices.values())} items in {len(prices)} auction house(s), "
          f"{sum(len(v) for v in sell_prices.values())} vendor prices")

    with open(TRAINERS_OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py from the addon's trainer scans. Do not edit by hand.\n")
        f.write("window.TRAINERS = ")
        json.dump(trainers, f, ensure_ascii=False)
        f.write(";\n")
        f.write("// Class trainer skills per client and class (UnitClass file name): level and cost.\n")
        f.write("window.CLASS_TRAINERS = ")
        json.dump(class_trainers, f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Trainers: {sum(len(r) for profs in trainers.values() for r in profs.values())} recipes from {len(trainers)} client(s)")

    with open(VENDORS_OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py from the addon's vendor scans. Do not edit by hand.\n")
        f.write("window.VENDORS = ")
        json.dump(vendors, f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Vendors: {sum(len(r) for r in vendors.values())} vendor recipes")

    with open(NPCS_OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py: trainers and recipe vendors the addon saw, per client. Do not edit by hand.\n")
        f.write("window.NPCS = ")
        json.dump(npcs, f, ensure_ascii=False)
        f.write(";\n")
        f.write("// Vendors that sell bags (addon 3.5.0+): zone, place, bags with slots and price.\n")
        f.write("window.BAG_VENDORS = ")
        json.dump(bag_vendors, f, ensure_ascii=False)
        f.write(";\n")
        f.write("// Vendor prices per item (addon 3.7.0+): cheapest price, amount per purchase, max stack, vendor.\n")
        f.write("window.SHOP_PRICES = ")
        json.dump(shop_prices, f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Trainers and vendors on the map: {sum(len(n) for n in npcs.values())}")

    # Dungeon quests come from the dungeon addons' own data files, read fresh on every sync. A client whose
    # addon folders are gone keeps its last data, so the two addons can be removed from the game.
    dungeons = {}
    if os.path.exists(DUNGEONS_OUTPUT):
        with open(DUNGEONS_OUTPUT, encoding='utf-8') as f:
            text = f.read()
        if 'window.DUNGEONS = ' in text:
            dungeons = json.loads(text.split('window.DUNGEONS = ', 1)[1].rstrip().rstrip(';'))
    for root in WOW_ROOTS:
        for addons_dir in glob.glob(os.path.join(root, "_*_", "Interface", "AddOns")):
            flavor = addons_dir[len(root) + 1:].split(os.sep)[0].strip('_')
            found = dungeon_addons.read(addons_dir)
            if found:
                dungeons[flavor] = found
    with open(DUNGEONS_OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py from the Forever Loot and DFL Dungeon Journal addons. Do not edit by hand.\n")
        f.write("window.DUNGEONS = ")
        json.dump(dungeons, f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Dungeon quests: {sum(len(dg['quests']) for d in dungeons.values() for dg in d['list'])} from {len(dungeons)} client(s)")

    for entry in realms.values():
        entry["chars"].sort(key=lambda ch: -int(ch["level"]) if ch["level"].isdigit() else 0)

    os.makedirs(PERSONAL_DIR, exist_ok=True)
    with open(OUTPUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_roster.py. Do not edit by hand.\n")
        f.write("window.SYNCED_ROSTERS = ")
        json.dump(realms, f, indent=2, ensure_ascii=False)
        f.write(";\n")
        f.write("// Addon folders installed per game client, for the addon list on the Launch tab.\n")
        f.write("window.ADDON_FOLDERS = ")
        json.dump(addon_folders(), f, ensure_ascii=False)
        f.write(";\n")

    for slug, entry in realms.items():
        print(f"[+] {slug}: {len(entry['chars'])} characters ({', '.join(ch['name'] for ch in entry['chars'])})")
    print(f"[+] Roster written to: {OUTPUT}")


if __name__ == "__main__":
    build()

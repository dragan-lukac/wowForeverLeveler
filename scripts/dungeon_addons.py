"""
Reads dungeon quests from two dungeon addons the user installed, straight from their data files in
Interface/AddOns (nothing is copied into this repository):
  - Forever Loot (ForeverLoot/Quests.lua, Data.lua): every dungeon with its level range and quests,
    quest givers with map coordinates, quest chains (Wowhead Forever data).
  - DFL Dungeon Journal (DFLDungeonJournal/QuestRewards.lua): reward item names, XP and money.
Only quests the Horde can take are kept.
"""

import os

HORDE_SIDES = {2, 3}  # Forever Loot: 1 = Alliance, 2 = Horde, 3 = both
PLACE_TYPES = {1: 'npc', 2: 'object', 3: 'item'}


def read_lua_tables(path, prefix=''):
    """Parses a data file of `Name = {...}` lines. prefix: text before the first table to drop,
    for files that start with `local _,J=...` and assign `J.Name = {...}`."""
    from build_roster import parse_saved_variables  # build_roster imports this module
    with open(path, encoding='utf-8') as f:
        text = f.read()
    if prefix:
        text = text[text.index(prefix):]
        text = text[len('J.'):table_end(text) + 1]  # code follows the table in these files
    return parse_saved_variables(text)


def table_end(text):
    """Index of the brace that closes the first table in text; skips braces inside strings."""
    depth, i, quote = 0, text.index('{'), None
    while True:
        c = text[i]
        if quote:
            if c == '\\':
                i += 1
            elif c == quote:
                quote = None
        elif c in '"\'':
            quote = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1


def place(places, zones, index):
    p = places[index - 1] if index and 0 < index <= len(places) else None
    if not p:
        return None
    zone_index = p[2] if len(p) > 2 else None
    return {'type': PLACE_TYPES.get(p[0], 'npc'), 'name': p[1],
            'zone': zones[zone_index - 1] if zone_index and 0 < zone_index <= len(zones) else None,
            'x': p[3] if len(p) > 3 else None, 'y': p[4] if len(p) > 4 else None}


def rewards_from(dfl):
    """DFL quest ID -> {items: [names], xp, money}."""
    out = {}
    for qid, r in (dfl or {}).items():
        items = [i.get('name') for i in (r.get('choice') or []) + (r.get('fixed') or []) if i.get('name')]
        out[int(qid)] = {'items': items, 'xp': r.get('xp'), 'money': r.get('money')}
    return out


def read(addons_dir):
    """-> {'source', 'date', 'list': [dungeon]} or None when Forever Loot is not installed."""
    loot_dir = os.path.join(addons_dir, 'ForeverLoot')
    if not os.path.exists(os.path.join(loot_dir, 'Quests.lua')):
        return None
    q = read_lua_tables(os.path.join(loot_dir, 'Quests.lua'))
    d = read_lua_tables(os.path.join(loot_dir, 'Data.lua'))
    zones, places = q.get('ForeverLoot_QuestZones') or [], q.get('ForeverLoot_QuestPlaces') or []
    db, by_zone, chains = q.get('ForeverLoot_QuestDB') or {}, q.get('ForeverLoot_Quests') or {}, q.get('ForeverLoot_QuestChains') or []

    rewards = {}
    dfl_path = os.path.join(addons_dir, 'DFLDungeonJournal', 'QuestRewards.lua')
    if os.path.exists(dfl_path):
        rewards = rewards_from(read_lua_tables(dfl_path, 'J.QuestRewards').get('QuestRewards'))

    dungeons = []
    for inst in d.get('ForeverLoot_Data') or []:
        quests = []
        for qid in by_zone.get(inst.get('zone')) or []:
            row = db.get(qid)
            if not row or row[3] not in HORDE_SIDES:
                continue
            chain_index = row[7] if len(row) > 7 else 0
            chain = chains[chain_index - 1] if chain_index and chain_index <= len(chains) else []
            first = chain[0] if chain and chain[0] != qid else None
            quests.append({
                'id': qid, 'name': row[0], 'level': row[1], 'minLevel': row[2],
                'start': place(places, zones, row[4]), 'end': place(places, zones, row[5]),
                'objective': row[6] if len(row) > 6 else None,
                'chainFirst': {'id': first, 'name': db[first][0]} if first in db else None,
                'reward': rewards.get(qid),
            })
        quests.sort(key=lambda x: (x['minLevel'] or 0, x['level'] or 0))
        dungeons.append({'name': inst.get('name'), 'kind': inst.get('kind'), 'levels': inst.get('levels'),
                         'new': bool(inst.get('new')), 'quests': quests})
    return {'source': 'Forever Loot' + (' + DFL Dungeon Journal' if rewards else ''),
            'date': d.get('ForeverLoot_DataDate'), 'list': dungeons}

#!/usr/bin/env python3
"""
Writes data/rares.json: for each rare in guide.json `rares.list` (the rare spawns worth hunting, user 2026-10-26),
its level, elite or not, one spawn on an outdoor map, and the items QuestieDB says it drops, from the QuestieDB
addon's Forever database. The Next tab shows "Kill Swiftmane for Signet of the Zebra" with an arrow to that spawn.

A rare is found by name; when QuestieDB lacks the name, by the item it drops (the Alliance Outrunners).

Runs by itself on every Sync and `make guide` (scripts/refresh_data.py).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402
from build_routes import area_maps, by_area  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, 'data', 'guide.json')
OUT = os.path.join(ROOT, 'data', 'rares.json')
RANK = {1: 'elite', 2: 'rare elite', 4: 'rare'}


def lst(v):
    if isinstance(v, dict):
        return [v[k] for k in sorted(v)]
    return v or []


def main():
    toc = questie_db.toc_path()
    db = questie_db.load(toc)
    maps = area_maps(toc)
    npcs, items = db['npcs'], db['items']
    with open(GUIDE, encoding='utf-8') as f:
        wanted = json.load(f).get('rares', {}).get('list', [])
    by_name = {}
    for nid, n in npcs.items():
        if n.get('name'):
            by_name.setdefault(n['name'], int(nid))
    drops = {}  # npc id -> item names it drops
    item_by_name = {}
    for it in items.values():
        if not it.get('name'):
            continue
        for nid in lst(it.get('npcDrops')):
            drops.setdefault(int(nid), []).append(it['name'])
            item_by_name.setdefault(it['name'], int(nid))
    out = {}
    for r in wanted:
        nid = by_name.get(r['npc']) or item_by_name.get(r['item'])
        n = npcs.get(nid) or npcs.get(str(nid)) if nid else None
        if not n:
            print(f"  not in QuestieDB: {r['npc']}")
            continue
        spot = None
        for area, coords in by_area(n.get('spawns')).items():
            m = maps.get(int(area))
            c = (coords or [None])[0]
            if m and c and c[0] is not None and c[0] >= 0:
                spot = (m, round(c[0], 1), round(c[1], 1))
                break
        out[r['npc']] = {'id': nid, 'name': n.get('name'), 'lo': n.get('minLevel'), 'hi': n.get('maxLevel') or n.get('minLevel'),
                         'rank': RANK.get(n.get('rank'), ''), 'drops': sorted(drops.get(nid, []))}
        if spot:
            out[r['npc']].update({'m': spot[0], 'x': spot[1], 'y': spot[2]})
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print(f'{len(out)} of {len(wanted)} rares found')


if __name__ == '__main__':
    main()

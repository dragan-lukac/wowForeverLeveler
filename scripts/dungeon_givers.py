#!/usr/bin/env python3
"""
Writes data/dungeon_givers.json: for every dungeon quest in data/dungeons.js, where its giver really is, from the
QuestieDB addon's Forever database (quest startedBy -> NPC / object spawns, or the item that starts it and what
drops that item).

Forever Loot gives no map spot for many givers, and those looked like "inside the dungeon" although some stand
outside (Nalpak and Ebru in the cave above the Wailing Caverns entrance). Here a giver counts as outside when one
of its spawns is on an outdoor zone map; the window then shows the zone and an arrow. Otherwise it is inside.

Runs by itself on every Sync and `make guide` (scripts/refresh_data.py).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402
from build_routes import area_maps, by_area, horde_ok  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUNGEONS = os.path.join(ROOT, 'data', 'dungeons.js')
OUT = os.path.join(ROOT, 'data', 'dungeon_givers.json')


def outdoor(m):
    """Classic outdoor zone and city maps are 1411-1458 in the Forever client; 1414 and 1415 are the continents."""
    return m is not None and 1411 <= m <= 1460 and m not in (1414, 1415)  # not the continent maps


def spots(entity, maps):
    """[(uiMap, x, y)] for each area the NPC or object spawns in, first spawn per area."""
    out = []
    for area, coords in by_area((entity or {}).get('spawns')).items():
        m = maps.get(int(area))
        c = (coords or [None])[0]
        if c and c[0] is not None and c[0] >= 0:
            out.append((m, round(c[0], 1), round(c[1], 1)))
        elif m:
            out.append((m, None, None))
    return out


def first(v):
    """startedBy parts come back as lists (or dicts keyed 1..n from CBOR)."""
    if isinstance(v, dict):
        v = [v[k] for k in sorted(v)]
    return v or []


def main():
    db = questie_db.load()
    maps = area_maps(questie_db.toc_path())
    Q, N, O, I = db['quests'], db['npcs'], db.get('objects', {}), db.get('items', {})
    get = lambda t, k: t.get(k) or t.get(str(k)) or {}  # noqa: E731
    with open(DUNGEONS, encoding='utf-8') as f:
        book = json.loads(f.read().split('window.DUNGEONS = ', 1)[1].rstrip().rstrip(';'))
    book = book.get('classic_beta') or next(iter(book.values()))
    out, moved = {}, []
    for d in book['list']:
        for q in d['quests']:
            qd = get(Q, q['id'])
            if not qd or not horde_ok(qd):
                # Not in Forever's quest database (an Alliance version, or gone), or Alliance only: leave it out.
                out[str(q['id'])] = {'skip': True}
                continue
            sb = qd.get('startedBy') or []
            if isinstance(sb, dict):  # keyed by part (1 NPCs, 2 objects, 3 items) when some parts are empty
                sb = [sb.get(i) or sb.get(str(i)) or [] for i in (1, 2, 3)]
            npcs, objs, items = (first(sb[i]) if len(sb) > i else [] for i in range(3))
            hit = None
            for kind, ids, table in (('npc', npcs, N), ('object', objs, O)):
                for gid in ids:
                    e = get(table, gid)
                    sp = spots(e, maps)
                    out_sp = [s for s in sp if outdoor(s[0]) and s[1] is not None]
                    cand = {'kind': kind, 'name': e.get('name') or '', 'inside': not out_sp}
                    if out_sp:
                        cand.update(m=out_sp[0][0], x=out_sp[0][1], y=out_sp[0][2])
                    if not hit or (hit['inside'] and not cand['inside']):
                        hit = cand
            if not hit and items:
                it = get(I, items[0])
                drops = [get(N, n).get('name') for n in first(it.get('npcDrops'))[:2]]
                drops += [get(O, o).get('name') for o in first(it.get('objectDrops'))[:1]]
                hit = {'kind': 'item', 'name': it.get('name') or '', 'inside': True, 'drop': ', '.join(x for x in drops if x)}
            if hit:
                out[str(q['id'])] = hit
                st = q.get('start') or {}
                if st.get('x') is None and not hit['inside']:
                    moved.append(f"{d['name']}: {q['name']} ({hit['name']}, map {hit['m']} {hit['x']}, {hit['y']})")
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    skip = sum(1 for v in out.values() if v.get('skip'))
    print(f'{len(out) - skip} quest givers, {skip} quests left out; {len(moved)} were "inside" but stand outside:')
    for line in moved:
        print('  ' + line)


if __name__ == '__main__':
    main()

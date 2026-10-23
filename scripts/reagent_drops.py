#!/usr/bin/env python3
"""
Writes data/reagent_drops.json: where the Cooking and First Aid materials come from, from the QuestieDB addon's
Forever database. For a meat (Chunk of Boar Meat): the monsters that drop it, with their levels and one spawn on an
outdoor map, so the window can say "Kill Stonetusk Boar for 10 Chunk of Boar Meat, Elwynn Forest" with an arrow
instead of "Buy". A fish ("Raw ..." with no monster dropping it) is marked fish.

QuestieDB has no drop chances, so the window picks the monster nearest the player's level.

Runs by itself on every Sync and `make guide` (scripts/refresh_data.py).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402
from build_routes import area_maps, by_area  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECIPES = os.path.join(ROOT, 'data', 'forever_recipes.json')
OUT = os.path.join(ROOT, 'data', 'reagent_drops.json')
PROFESSIONS = ('Cooking', 'First Aid')
MAX_MOBS = 40


def outdoor(m):
    """Outdoor zone and city maps of Kalimdor and the Eastern Kingdoms; 1414 and 1415 are the continents."""
    return m is not None and 1411 <= m <= 1460 and m not in (1414, 1415)


def lst(v):
    if isinstance(v, dict):
        return [v[k] for k in sorted(v)]
    return v or []


def main():
    toc = questie_db.toc_path()
    db = questie_db.load(toc)
    maps = area_maps(toc)
    items, npcs = db['items'], db['npcs']
    get = lambda t, k: t.get(k) or t.get(str(k)) or {}  # noqa: E731
    by_name = {}
    for it in items.values():
        if it.get('name'):
            by_name.setdefault(it['name'], []).append(it)
    with open(RECIPES, encoding='utf-8') as f:
        recipes = json.load(f)['professions']
    reagents = set()
    for prof in PROFESSIONS:
        for r in recipes.get(prof, {}).values():
            reagents.update(r.get('reagents', {}))
    out = {}
    for name in sorted(reagents):
        mobs, seen = [], set()
        for it in by_name.get(name, []):
            for nid in lst(it.get('npcDrops')):
                n = get(npcs, nid)
                # Town people (friendly to one side) and NPCs without a level left out; wild animals are "AH" here.
                if not n or n.get('friendlyToFaction') in ('A', 'H') or not n.get('minLevel') or n.get('name') in seen:
                    continue
                spot = None
                for area, coords in by_area(n.get('spawns')).items():
                    m = maps.get(int(area))
                    c = (coords or [None])[0]
                    if outdoor(m) and c and c[0] is not None and c[0] >= 0:
                        spot = (m, round(c[0], 1), round(c[1], 1))
                        break
                if not spot:
                    continue
                seen.add(n['name'])
                mobs.append({'n': n['name'], 'lo': n['minLevel'], 'hi': n.get('maxLevel') or n['minLevel'],
                             'm': spot[0], 'x': spot[1], 'y': spot[2]})
        mobs.sort(key=lambda x: (x['lo'], x['n']))
        if mobs:
            out[name] = {'mobs': mobs[:MAX_MOBS]}
        elif name.startswith('Raw ') or 'Fish' in name or name in ('Darkclaw Lobster', 'Deviate Fish'):
            out[name] = {'fish': True}
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print(f"{sum(1 for v in out.values() if v.get('mobs'))} materials dropped by monsters, "
          f"{sum(1 for v in out.values() if v.get('fish'))} fish")


if __name__ == '__main__':
    main()

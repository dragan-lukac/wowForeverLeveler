#!/usr/bin/env python3
"""
Writes data/vendor_items.json: for every material a crafter can buy (reagents of all profession recipes, the
profession tools and bags, the guide's shopping items) the Horde-friendly vendors that sell it, with their map
spots. Source: the QuestieDB addon's Forever database (item field 14 = vendors; NPC spawns and faction), read
with scripts/questie_db.py. build_guide.py puts it into Plan.lua `vendors` / `vendorItems` for the in-game vendor
search (Ctrl + click a material, click a material line in the window, the WFL key, or /wfl buy <item>).

It also writes the Horde-friendly profession trainers of QuestieDB (`trainers`), so trainers that are new in Forever
(Pa'zula, Journeyman Enchanter in Sen'jin Village; the Junior gathering trainers) get an arrow too: ClassicDB
(scripts/trainers_db.py) does not know them.

Runs by itself on every Sync and `make guide` (scripts/refresh_data.py).
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402
from build_routes import area_maps, by_area  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'vendor_items.json')
RECIPES = os.path.join(ROOT, 'data', 'forever_recipes.json')
GUIDE = os.path.join(ROOT, 'data', 'guide.json')


def wanted_items():
    """Item names a crafter may want to buy: every recipe reagent, profession kit items, shopping items."""
    names = set()
    with open(RECIPES, encoding='utf-8') as f:
        for recipes in json.load(f)['professions'].values():
            for r in recipes.values():
                names.update(r.get('reagents', {}))
    with open(GUIDE, encoding='utf-8') as f:
        guide = json.load(f)
    for p in guide['professions'].values():
        kit = p.get('kit') or {}
        names.update(kit.get('tools', []))
        if kit.get('bag'):
            names.add(kit['bag'])
    names.update((guide.get('shopping') or {}).get('items', {}))
    # Cooking and First Aid recipes sold by vendors, and the fishing pole (the "From your bags" and Fishing rows).
    with open(RECIPES, encoding='utf-8') as f:
        prof = json.load(f)['professions']
    for p in ('Cooking', 'First Aid'):
        for rname, r in prof.get(p, {}).items():
            if 'Vendor' in (r.get('source') or ''):
                names.add('Recipe: ' + rname)
    names.add('Fishing Pole')
    return names


# A trainer's title -> its profession ("Journeyman Enchanter", "Junior Herbalism Trainer", "Expert Alchemist").
TITLES = [(r'Alchem', 'Alchemy'), (r'Blacksmith', 'Blacksmithing'), (r'Enchant', 'Enchanting'), (r'Engineer', 'Engineering'),
          (r'Leatherwork', 'Leatherworking'), (r'Tailor', 'Tailoring'), (r'Herbalis', 'Herbalism'), (r'Mining|Miner', 'Mining'),
          (r'Skinn', 'Skinning'), (r'Cook|Chef', 'Cooking'), (r'First Aid|Physician|Surgeon', 'First Aid'), (r'Fish', 'Fishing')]


def trainer_profession(sub):
    if not re.search(r'Trainer|^(Apprentice|Journeyman|Expert|Artisan|Master) ', sub or ''):
        return None
    if re.search(r'Supplies|Riding|Weapon|Pet|Portal', sub):
        return None
    return next((prof for pat, prof in TITLES if re.search(pat, sub)), None)


def main():
    questie_db.ITEM_FIELDS[14] = 'vendors'
    db = questie_db.load()
    maps = area_maps(questie_db.toc_path())
    items, npcs = db['items'], db['npcs']
    by_name = {}
    for iid, it in items.items():
        if it.get('name') and it.get('vendors'):
            by_name.setdefault(it['name'], []).extend(it['vendors'])
    vendors, out = {}, {}
    for name in sorted(wanted_items()):
        ids = []
        for npc_id in by_name.get(name, []):
            npc = npcs.get(npc_id) or npcs.get(str(npc_id)) or {}
            if npc.get('friendlyToFaction') not in ('H', 'AH'):
                continue  # Alliance or hostile
            spots = []
            for area, coords in by_area(npc.get('spawns')).items():
                m = maps.get(int(area))
                for c in (coords or [])[:1]:
                    if m and c and c[0] is not None and c[0] >= 0:
                        spots.append([m, round(c[0], 1), round(c[1], 1)])
            if not spots:
                continue
            key = str(npc_id)
            vendors[key] = {'n': npc.get('name'), 'sub': npc.get('subName') or '', 'at': spots[:2]}
            ids.append(int(npc_id))
        if ids:
            out[name] = sorted(set(ids))
    trainers = []
    for npc_id, npc in npcs.items():
        prof = trainer_profession(npc.get('subName'))
        if not prof or npc.get('friendlyToFaction') not in ('H', 'AH'):
            continue
        for area, coords in by_area(npc.get('spawns')).items():
            m = maps.get(int(area))
            c = (coords or [None])[0]
            if m and c and c[0] is not None and c[0] >= 0:
                trainers.append({'name': npc.get('name'), 'profession': prof, 'mapID': m, 'x': round(c[0], 2), 'y': round(c[1], 2)})
                break
    trainers.sort(key=lambda t: (t['profession'], t['name']))
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump({'source': 'QuestieDB (Forever), Horde-friendly vendors and profession trainers', 'vendors': vendors,
                   'items': out, 'trainers': trainers},
                  f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print(f'{len(out)} items with Horde vendors, {len(vendors)} vendors; e.g. Coarse Thread: {len(out.get("Coarse Thread", []))}; '
          f'{len(trainers)} profession trainers')


if __name__ == '__main__':
    main()

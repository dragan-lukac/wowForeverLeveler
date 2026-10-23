#!/usr/bin/env python3
"""
Writes data/dungeon_levels.json: the real monster levels inside each dungeon, from the QuestieDB addon's Forever
database (each NPC's zone and level). Per dungeon: how many monsters, the level most of them have (median) and the
top level (the last boss). build_guide.py turns that into the run range "most monsters to last boss", in place of
the old rule of thumb (30% to 60% of the dungeon's level range).

The dungeons new in Forever (Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran) have NPCs without
levels in QuestieDB yet (2026-10-22): they keep the rule of thumb until QuestieDB fills them in.

Runs by itself on every Sync and `make guide` (scripts/refresh_data.py).
"""

import json
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questie_db  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'dungeon_levels.json')


def dungeon_areas(toc):
    """{ area id: dungeon name } from QuestieDB's Forever dungeon list (support/Forever/Zones/dungeons.lua)."""
    path = os.path.join(os.path.dirname(toc), 'support', 'Forever', 'Zones', 'dungeons.lua')
    with open(path, encoding='utf-8') as f:
        return {int(a): n for a, n in re.findall(r'^\s*\[(\d+)\] = \{"([^"]+)"', f.read(), re.M)}


def main():
    toc = questie_db.toc_path()
    db = questie_db.load(toc)
    areas = dungeon_areas(toc)
    by_area = {}
    for n in db['npcs'].values():
        # Hostile monsters with a level (friendly NPCs and the ones without data left out).
        if n.get('zoneID') in areas and (n.get('minLevel') or 0) > 0 and n.get('friendlyToFaction') is None:
            by_area.setdefault(n['zoneID'], []).append(n)
    # Some dungeons have several zone numbers (Dire Maul's wings): their monsters count together.
    by_name = {}
    for area, mobs in by_area.items():
        by_name.setdefault(areas[area], []).extend(mobs)
    out = {}
    for name, mobs in sorted(by_name.items()):
        levels = sorted(n['minLevel'] for n in mobs)
        top = max(n.get('maxLevel') or n['minLevel'] for n in mobs)
        out[name] = {'monsters': len(mobs), 'most': int(statistics.median(levels)), 'top': top}
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print(f'{len(out)} dungeons and raids with monster levels')


if __name__ == '__main__':
    main()

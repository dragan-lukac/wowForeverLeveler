#!/usr/bin/env python3
"""
Writes guide.json `trainerDB`: every Horde-friendly profession trainer from ClassicDB (Classic data) with its
zone and map position, so the in-game panel can point to the nearest one before the addon has seen it.
Junior trainers that are new in Forever are not in ClassicDB: the addon's own trainer scans add those.

Run it by hand (a minute or two): python3 scripts/trainers_db.py && make guide
"""

import json
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, 'data', 'guide.json')
CDB = 'https://classicdb.ch'
PROFESSIONS = ['Alchemy', 'Blacksmithing', 'Enchanting', 'Engineering', 'Herbalism', 'Leatherworking', 'Mining',
               'Skinning', 'Tailoring', 'Cooking', 'First Aid', 'Fishing']
# ClassicDB zone (area) id -> the game's map id (uiMapID, what TomTom and C_Map use).
UI_MAP = {85: 1420, 14: 1411, 215: 1412, 17: 1413, 1637: 1454, 1638: 1456, 1497: 1458, 130: 1421, 267: 1424,
          331: 1440, 406: 1442, 405: 1443, 400: 1441, 45: 1417, 33: 1434, 440: 1446, 357: 1444, 47: 1425,
          15: 1445, 8: 1435, 3: 1418, 36: 1416, 28: 1422, 139: 1423, 361: 1448, 490: 1449, 618: 1452,
          1377: 1451, 16: 1447, 148: 1439, 11: 1437, 51: 1427, 46: 1428, 38: 1432, 44: 1433, 10: 1431,
          40: 1436, 12: 1429, 1: 1426, 141: 1438, 4: 1419, 41: 1430, 493: 1450}


def get(url):
    return subprocess.run(['curl', '-s', '-m', '40', '-A', 'Mozilla/5.0', url], capture_output=True, text=True).stdout


# Crafting trainers are titled by rank and role ("Journeyman Blacksmith", "Expert Enchanter").
NOUNS = {'Alchemy': 'Alchemist', 'Blacksmithing': 'Blacksmith', 'Enchanting': 'Enchanter', 'Engineering': 'Engineer',
         'Leatherworking': 'Leatherworker', 'Tailoring': 'Tailor'}
RANKS = ('', 'Journeyman ', 'Expert ', 'Artisan ', 'Master ')


def search(prof):
    """[(name, npc id)] of Horde-friendly trainers of a profession, by their title."""
    titles = {f'{prof} Trainer'} | {f'{r}{NOUNS[prof]}' for r in RANKS if prof in NOUNS}
    queries = [f'{prof} Trainer'] + ([NOUNS[prof]] if prof in NOUNS else [])
    out = {}
    for q in queries:
        html = get(f"{CDB}/?search={q.replace(' ', '+')}")
        rows = re.findall(r"\{name:'((?:[^'\\]|\\.)*)',tag:'([^']*)'.*?react:\[(-?\d),(-?\d)\].*?id:(\d+)\}", html)
        for n, tag, a, h, i in rows:
            if tag in titles and int(h) >= 0:
                out[int(i)] = n.replace("\\'", "'")
    return [(n, i) for i, n in out.items()]


def place(npc):
    html = get(f'{CDB}/?npc={npc}')
    z = re.search(r"zone: '(\d+)'", html)
    c = re.search(r'coords:\[\s*\[([\d.]+),([\d.]+)', html)
    return (int(z.group(1)) if z else None, float(c.group(1)) if c else None, float(c.group(2)) if c else None)


def build():
    found = []
    for prof in PROFESSIONS:
        npcs = search(prof)
        with ThreadPoolExecutor(8) as pool:
            places = list(pool.map(lambda n: place(n[1]), npcs))
        for (name, _), (zone, x, y) in zip(npcs, places):
            if zone in UI_MAP and x is not None:
                found.append({'name': name, 'profession': prof, 'mapID': UI_MAP[zone], 'x': x, 'y': y})
        print(f"[+] {prof}: {sum(1 for f in found if f['profession'] == prof)} Horde trainers")
    with open(GUIDE, encoding='utf-8') as f:
        guide = json.load(f)
    guide['trainerDB'] = {'source': 'classicdb.ch (Classic data, not checked on Forever)', 'list': found}
    with open(GUIDE, 'w', encoding='utf-8') as f:
        f.write(json.dumps(guide, indent=2, ensure_ascii=False) + '\n')
    print(f"[+] guide.json trainerDB: {len(found)} trainers")


if __name__ == '__main__':
    build()

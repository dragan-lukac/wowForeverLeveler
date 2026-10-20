#!/usr/bin/env python3
"""
Builds data/zone_quests.js (window.ZONE_QUESTS): the Horde quests of each route zone, grouped by quest hub.

Sources (read with curl, both work outside the browser):
- forevervsclassic.com: the Forever quest list per zone (level, required level, faction, new/changed/removed).
- classicdb.ch: who starts each quest and where that NPC stands (zone and map position).
Quests whose giver stands within HUB_RADIUS of a hub in guide.json zones.<zone>.hubCoords belong to that hub;
the rest are "elsewhere". New Forever quests have no ClassicDB page, so their hub is not known.

Run it by hand (it takes a few minutes): python3 scripts/zone_quests.py
"""

import json
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, 'data', 'guide.json')
OUT = os.path.join(ROOT, 'data', 'zone_quests.js')
FVC = 'https://www.forevervsclassic.com'
CDB = 'https://classicdb.ch'
HUB_RADIUS = 9  # map units: a giver this close to a hub's centre belongs to that hub
MIN_LEVEL = 0  # every route zone (the Leveling window lists quests from level 1)


def get(url):
    return subprocess.run(['curl', '-s', '-m', '40', '-A', 'Mozilla/5.0', url], capture_output=True, text=True).stdout


def forever_list(group, zone):
    """[{id, level, req, name, side, status}] for one zone, all pages."""
    out, page = [], 1
    while True:
        html = get(f'{FVC}/quests?group={group}&zone={zone}&side=2&page={page}')
        rows = re.findall(r'href="/quests/(\d+)".*?font-bold text-quest"[^>]*>(\d+)</span>.*?font-semibold"[^>]*>([^<]+)</div>'
                          r'<div class="truncate text-\[13px\] text-dim"><span[^>]*>(Horde|Alliance|Both)</span>.*?req (\d+).*?'
                          r'(Same|Changed|New|Removed|Not yet confirmed)</span>', html, re.S)
        for qid, level, name, side, req, status in rows:
            out.append({'id': int(qid), 'level': int(level), 'req': int(req), 'name': name.replace('&#x27;', "'").replace('&amp;', '&'),
                        'side': side, 'status': status.lower()})
        if f'page={page + 1}' not in html or not rows:
            return out
        page += 1


def giver(qid):
    """(npc name, npc id) that starts the quest on ClassicDB, or (None, None)."""
    m = re.search(r'Start: <a href="\?npc=(\d+)"\s*>([^<]+)</a>', get(f'{CDB}/?quest={qid}'))
    return (m.group(2), int(m.group(1))) if m else (None, None)


def npc_place(npc):
    """(zone id, x, y) of an NPC on ClassicDB, or (None, None, None)."""
    html = get(f'{CDB}/?npc={npc}')
    z = re.search(r"zone: '(\d+)'", html)
    c = re.search(r'coords:\[\s*\[([\d.]+),([\d.]+)', html)
    return (int(z.group(1)) if z else None, float(c.group(1)) if c else None, float(c.group(2)) if c else None)


def zone_names():
    """Zone id -> name, from the site's zone menus (cities included), for givers in another zone."""
    names = {}
    for group in (0, 1):
        for zid, name in re.findall(r'<option value="(\d+)">([^<]+)', get(f'{FVC}/quests?group={group}')):
            names[int(zid)] = name.replace('&#x27;', "'")
    return names


def build():
    with open(GUIDE, encoding='utf-8') as f:
        guide = json.load(f)
    names = zone_names()
    zones = {name: z for name, z in guide['zones'].items()
             if z.get('fvc') and str(z.get('levels', '')).split('-')[-1].isdigit()
             and int(str(z['levels']).split('-')[-1]) > MIN_LEVEL}
    result = {}
    for name, z in zones.items():
        quests = [q for q in forever_list(*z['fvc']) if q['side'] != 'Alliance' and q['status'] != 'removed']
        skips = {s.get('id') for s in z.get('skips', [])}
        quests = [q for q in quests if q['id'] not in skips]
        with ThreadPoolExecutor(8) as pool:
            givers = list(pool.map(lambda q: giver(q['id']) if q['status'] != 'new' else (None, None), quests))
        npcs = {g[1] for g in givers if g[1]}
        with ThreadPoolExecutor(8) as pool:
            places = dict(zip(npcs, pool.map(npc_place, npcs)))
        hubs = z.get('hubCoords', {})
        for q, (npc, npc_id) in zip(quests, givers):
            q['giver'] = npc
            zid, x, y = places.get(npc_id, (None, None, None))
            near = [(h, ((x - hx) ** 2 + (y - hy) ** 2) ** 0.5) for h, (hx, hy) in hubs.items()] if x is not None else []
            near = [n for n in near if n[1] <= HUB_RADIUS]
            q['hub'] = min(near, key=lambda n: n[1])[0] if near else None
            # A giver in another zone or a city (e.g. Western Plaguelands quests from the Bulwark in Tirisfal).
            if zid and zid != z['fvc'][1] and zid in names:
                q['hub'] = names[zid]
            if x is not None and zid == z['fvc'][1]:
                q['at'] = [round(x, 1), round(y, 1)]
        result[name] = sorted(quests, key=lambda q: (q['level'], q['name']))
        print(f"[+] {name}: {len(quests)} quests, {sum(1 for q in quests if q['hub'])} placed in a hub")
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/zone_quests.py (forevervsclassic.com + classicdb.ch). Do not edit by hand.\n")
        f.write("window.ZONE_QUESTS = ")
        json.dump({'source': 'forevervsclassic.com (Forever quest list) + classicdb.ch (givers)', 'zones': result},
                  f, ensure_ascii=False)
        f.write(";\n")
    print(f"[+] Written: {OUT}")


if __name__ == '__main__':
    build()

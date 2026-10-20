#!/usr/bin/env python3
"""
Writes data/recipe_sources.json: where each vendor or quest recipe (data/forever_recipes.json) is learned. For every such recipe it looks up its pattern on ClassicDB (Classic data, not
checked in Forever): the Horde-friendly vendors that sell it (zone, map spot, price, limited stock) and the quests
that give it. New Forever patterns are not on ClassicDB; for those build_guide.py uses our own vendor scans
(data/vendors.js), which also win when both have the recipe.

A recipe found on ClassicDB with only Alliance vendors and quests gets "horde": false; forever_profs.py leaves those
out of the paths. Run it by hand (a few minutes), then forever_profs.py again and make guide:
    python3 scripts/recipe_sources.py && python3 scripts/forever_profs.py --cached && make guide
"""

import json
import os
import re
import subprocess
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

from trainers_db import CDB, UI_MAP, place

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECIPES = os.path.join(ROOT, 'data', 'forever_recipes.json')
OUT = os.path.join(ROOT, 'data', 'recipe_sources.json')
# The pattern item of a recipe is named "<prefix> <recipe>".
PREFIX = {'Tailoring': 'Pattern', 'Leatherworking': 'Pattern', 'Blacksmithing': 'Plans', 'Engineering': 'Schematic',
          'Alchemy': 'Recipe', 'Enchanting': 'Formula', 'Cooking': 'Recipe', 'First Aid': 'Manual'}


def get(url):
    return subprocess.run(['curl', '-s', '-L', '-m', '40', '-A', 'Mozilla/5.0', url], capture_output=True, text=True).stdout


def listviews(html):
    """{listview id: data text} of a ClassicDB page."""
    return {m.group(1): m.group(2) for m in re.finditer(r"new Listview\(\{template:'\w+',id:'([a-z-]+)'.*?data:(\[.*?\])\}\);", html, re.S)}


def lookup(prof, recipe):
    """{'item', 'vendors': [{name, mapID, x, y, cost, limited}], 'quests': [{name, id, level}]} or None."""
    names = [f'{PREFIX.get(prof, "Pattern")}: {recipe}'] + ([f'Pattern: {recipe}'] if PREFIX.get(prof) != 'Pattern' else [])
    views = None
    for item_name in names:
        page = get(f'{CDB}/?search={urllib.parse.quote_plus(item_name)}')
        if '- Item - ' in page[:2000]:
            views = listviews(page)  # an exact name opens the item page at once
            break
        found = re.search(r"\{name:'\d" + re.escape(item_name.replace("'", "\\'")) + r"'[^}]*?id:(\d+)\}", page)
        if found:
            views = listviews(get(f'{CDB}/?item={found.group(1)}'))
            break
    if views is None:
        return None
    out = {'item': item_name, 'vendors': [], 'quests': [], 'horde': False}
    for m in re.finditer(r"\{name:'((?:[^'\\]|\\.)*)'[^}]*?react:\[(-?\d),(-?\d)\][^}]*?stock:(-?\d+)[^}]*?cost:\[(\d+)[^}]*?id:(\d+)\}",
                         views.get('sold-by', '')):
        name, _, horde, stock, cost, npc = m.groups()
        if int(horde) < 0:
            continue  # hostile to the Horde
        out['horde'] = True
        zone, x, y = place(int(npc))
        out['vendors'].append({'name': name.replace("\\'", "'"), 'mapID': UI_MAP.get(zone), 'x': x, 'y': y,
                               'cost': int(cost), 'limited': int(stock) > 0})
    # A quest reward ('reward-of'): {id:'1487',name:'Deviate Eradication',level:'21',reqlevel:15,side:'3',...}
    # side 1 = Alliance only.
    for m in re.finditer(r"\{id:'(\d+)',name:'((?:[^'\\]|\\.)*)',level:'(\d+)',reqlevel:(\d+),side:'(\d)'", views.get('reward-of', '')):
        qid, qname, level, req, side = m.groups()
        if side != '1':
            out['horde'] = True
            out['quests'].append({'name': qname.replace("\\'", "'"), 'id': int(qid), 'level': int(level), 'from': int(req)})
    return out


def main():
    with open(RECIPES, encoding='utf-8') as f:
        recipes = json.load(f)['professions']
    todo = sorted({(prof, name) for prof, rs in recipes.items() for name, r in rs.items()
                   if prof in PREFIX and ('Vendor' in r['source'] or 'Quest' in r['source']) and 'Trainer' not in r['source']})
    with ThreadPoolExecutor(4) as pool:  # 4 at a time: polite to the site
        found = list(pool.map(lambda t: lookup(*t), todo))
    out = {}
    for (prof, recipe), info in zip(todo, found):
        if info:
            out[recipe] = info
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump({'source': 'classicdb.ch (Classic data, not checked in Forever)', 'recipes': out}, f, indent=1,
                  sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print(f"{len(todo)} recipes looked up: {sum(1 for i in out.values() if i['horde'])} for the Horde, "
          f"{sum(1 for i in out.values() if not i['horde'])} Alliance only, {len(todo) - len(out)} not on ClassicDB (new in Forever)")


if __name__ == '__main__':
    main()

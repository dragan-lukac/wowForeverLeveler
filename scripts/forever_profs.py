#!/usr/bin/env python3
"""
Builds our own WoW Forever profession data:

1. data/forever_recipes.json: every recipe of every profession from forevervsclassic.com/professions/<prof>
   (Wowhead Forever data; robots.txt allows it): learn skill, skill-up colours (orange, yellow, green, grey),
   source (Trainer, Vendor, Drop, Quest), reagents, how many one craft makes, Forever status. Corrected with the
   user's own trainer scans (data/trainers.js, GetTrainerServiceSkillReq in game): the game's learn skill wins,
   the colours stay (checked 2026-10-16 against the save file's recipe difficulty: Lovac First Aid 80 saw Minor
   Healing Potion green and Lesser Healing Potion orange; only unmoved colours give that).
2. data/forever_profs.json: a 1-300 leveling path per crafting profession, picked point by point for the lowest
   material cost per expected skill-up (less what the made item sells for on the auction house), and the
   materials per skill bracket. Recipes in order of preference:
   trainer or known from the start (no source), then vendor or quest (cost x2), then drops (cost x5); such steps
   carry `source`. Cooldown crafts (transmutes, Mooncloth, Salt Shaker) are left out. "Not yet confirmed" recipes are left out unless the game scan saw them.
   build_guide.py uses it for Plan.lua matPlan and craftSteps.

Skill-up chance (Classic rule): orange 100%, from yellow on (grey - skill) / (grey - yellow), grey 0. Colours with
no range (grey at the learn skill, missing data): conversions (bolts, leather) give no points, others get +5/+15.

Run it by hand (fetches 45 pages: 9 professions x 5 ranks): python3 scripts/forever_profs.py
Use --cached to rebuild from the saved pages in data/forever_pages/ (not in git). Green-or-better crafted items
are read from forevervsclassic.com/items/<id> once (data/forever_pages/items/) for their disenchant value.
"""

import html
import json
import math
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = 'https://www.forevervsclassic.com/professions/'
PAGES = os.path.join(ROOT, 'data', 'forever_pages')
RECIPES_OUT = os.path.join(ROOT, 'data', 'forever_recipes.json')
PROFS_OUT = os.path.join(ROOT, 'data', 'forever_profs.json')
SLUGS = {'Alchemy': 'alchemy', 'Blacksmithing': 'blacksmithing', 'Cooking': 'cooking', 'Enchanting': 'enchanting',
         'Engineering': 'engineering', 'First Aid': 'first-aid', 'Leatherworking': 'leatherworking',
         'Mining': 'mining', 'Tailoring': 'tailoring'}
ROW = 'grid grid-cols-[auto_1fr_auto]'
CRAFTS = ('Alchemy', 'Blacksmithing', 'Enchanting', 'Engineering', 'Leatherworking', 'Tailoring')
ALL = {}  # every recipe of every profession by name (filled in main)
# Professions should make money, not only level cheaply (user, 2026-10-19): what the made item sells for on the
# auction house (5% cut) counts as paid back, so a path may use more materials when the crafts sell. A market takes
# only so many of one item: the sale counts for at most MARKET_CAP crafts of each recipe, then the craft counts as
# not sold. Prices: our Auctionator scans (beta: thin, update with Sync and rerun on live).
SALE_WEIGHT = 1.0
MARKET_CAP = 10  # launch month: few players have money, so the market for one item is small
SALE = {}  # strict sale price per item (load_prices)
SHOP = {}  # vendor price per item from our vendor scans (own_recipe_scans): vendor goods cost exactly this
# recipe -> True / False: the Horde can get it (scripts/recipe_sources.py, ClassicDB); missing = not known
try:
    with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data', 'recipe_sources.json'), encoding='utf-8') as _f:
        HORDE = {k: v.get('horde') for k, v in json.load(_f).get('recipes', {}).items()}
except (OSError, ValueError):
    HORDE = {}
RANKS = ('apprentice', 'journeyman', 'expert', 'artisan', '300')  # one page per rank (the plain page shows one)


def fetch(prof, rank, cached):
    path = os.path.join(PAGES, f'{SLUGS[prof]}-{rank}.html')
    if not cached:
        os.makedirs(PAGES, exist_ok=True)
        url = f'{SITE}{SLUGS[prof]}?rank={rank}'
        text = subprocess.run(['curl', '-s', '-m', '60', '-A', 'Mozilla/5.0', url], capture_output=True, text=True).stdout
        if 'Forever vs Classic' not in text:
            sys.exit(f'{prof}: could not read {url}')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    with open(path, encoding='utf-8') as f:
        return f.read()


def num(s):
    s = s.strip()
    return int(s) if s.isdigit() else None


QUALITY = {'Poor': 0, 'Common': 1, 'Uncommon': 2, 'Rare': 3, 'Epic': 4, 'Legendary': 5}


def item_info(item_id, cached):
    """(Forever quality, item level, 'Armor'/'Weapon'/other) from forevervsclassic.com/items/<id>, cached on disk."""
    folder = os.path.join(PAGES, 'items')
    path = os.path.join(folder, f'{item_id}.html')
    if not os.path.exists(path):
        if cached:
            return None
        os.makedirs(folder, exist_ok=True)
        text = subprocess.run(['curl', '-s', '-m', '40', '-A', 'Mozilla/5.0', f'https://www.forevervsclassic.com/items/{item_id}'],
                              capture_output=True, text=True).stdout
        if 'Item level' not in text and 'Item Level' not in text:
            return None
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    with open(path, encoding='utf-8') as f:
        text = html.unescape(re.sub(r'<[^>]+>', ' ', re.sub(r'<script.*?</script>', '', f.read(), flags=re.S)))
    text = re.sub(r'\s+', ' ', text)
    q = re.search(r'(Poor|Common|Uncommon|Rare|Epic|Legendary)(?: → (Poor|Common|Uncommon|Rare|Epic|Legendary))? · Item level (\d+)', text)
    kind = re.search(r'Items / (\w+)', text)
    if not q:
        return None
    return QUALITY[q.group(2) or q.group(1)], int(q.group(3)), kind.group(1) if kind else ''


def add_item_info(recipes, cached):
    """Quality, item level and kind for every green-or-better crafted item (for its disenchant value)."""
    from concurrent.futures import ThreadPoolExecutor
    todo = {}
    for prof in CRAFTS:
        for r in recipes.get(prof, {}).values():
            if r.get('item') and (r.get('quality') or 0) >= 2:
                todo[r['item']] = None
    with ThreadPoolExecutor(4) as pool:  # 4 at a time: polite to the site
        for item_id, info in zip(todo, pool.map(lambda i: item_info(i, cached), list(todo))):
            todo[item_id] = info
    n = 0
    for prof in CRAFTS:
        for r in recipes.get(prof, {}).values():
            info = todo.get(r.get('item'))
            if info:
                r['quality'], r['ilvl'], r['kind'] = info
                n += 1
    return n


# Disenchanting (Classic table, not checked in Forever): green items by item level -> (dust, essence, shard,
# dust count, essence count); armor gives dust 75% / essence 20% / shard 5%, a weapon essence 75% / dust 20%.
# Blue items give one shard. Levels up to 15: no shard (80/20).
DE_GREEN = [(15, 'Strange Dust', 'Lesser Magic Essence', None, 1.5, 1.5),
            (20, 'Strange Dust', 'Greater Magic Essence', 'Small Glimmering Shard', 2.5, 1.5),
            (25, 'Strange Dust', 'Lesser Astral Essence', 'Small Glimmering Shard', 5, 1.5),
            (30, 'Soul Dust', 'Greater Astral Essence', 'Large Glimmering Shard', 1.5, 1.5),
            (35, 'Soul Dust', 'Lesser Mystic Essence', 'Small Glowing Shard', 3.5, 1.5),
            (40, 'Vision Dust', 'Greater Mystic Essence', 'Large Glowing Shard', 1.5, 1.5),
            (45, 'Vision Dust', 'Lesser Nether Essence', 'Small Radiant Shard', 3.5, 1.5),
            (50, 'Dream Dust', 'Greater Nether Essence', 'Large Radiant Shard', 1.5, 1.5),
            (55, 'Dream Dust', 'Lesser Eternal Essence', 'Small Brilliant Shard', 3.5, 1.5),
            (60, 'Illusion Dust', 'Greater Eternal Essence', 'Large Brilliant Shard', 1.5, 1.5),
            (99, 'Illusion Dust', 'Greater Eternal Essence', 'Large Brilliant Shard', 3.5, 2.5)]
DE_BLUE = [(25, 'Small Glimmering Shard'), (30, 'Large Glimmering Shard'), (35, 'Small Glowing Shard'),
           (40, 'Large Glowing Shard'), (45, 'Small Radiant Shard'), (50, 'Large Radiant Shard'),
           (55, 'Small Brilliant Shard'), (99, 'Large Brilliant Shard')]


def de_value(r, prices):
    """Expected auction value (copper) of disenchanting one made item, 0 when it cannot be or a price is missing."""
    q, lvl = r.get('quality') or 0, r.get('ilvl') or 0
    if q == 2 and r.get('kind') in ('Armor', 'Weapon', 'Weapons') and lvl >= 5:
        _, dust, ess, shard, nd, ne = next(x for x in DE_GREEN if lvl <= x[0])
        weapon = r.get('kind') in ('Weapon', 'Weapons')
        pd, pe, ps = (0.2, 0.75, 0.05) if weapon else (0.75, 0.2, 0.05)
        if not shard:
            pd, pe, ps = (0.2, 0.8, 0) if weapon else (0.8, 0.2, 0)
        return 0.95 * (pd * nd * prices.get(dust, 0) + pe * ne * prices.get(ess, 0) + (ps * prices.get(shard, 0) if shard else 0))
    if q == 3 and r.get('kind') in ('Armor', 'Weapon', 'Weapons'):
        return 0.95 * prices.get(next(x[1] for x in DE_BLUE if lvl <= x[0]), 0)
    return 0


def has_range(c):
    """True when the colours give points over more than one skill (grey above orange/yellow)."""
    c = c + [None] * (4 - len(c))
    low = c[1] if c[1] is not None else c[0]
    return c[3] is not None and low is not None and c[3] > low


def parse(prof, page):
    """{recipe name: {...}} from one profession page."""
    out = {}
    slug = SLUGS[prof]
    for row in page.split(ROW)[1:]:
        m = re.search(r'href="/professions/' + slug + r'/(\d+)">([^<]+)</a>', row)
        if not m:
            continue
        rid, name = int(m.group(1)), html.unescape(m.group(2))
        item = re.match(r'[^>]*>\s*<a data-wowhead="item=(\d+)', row)
        makes = re.match(r'.*?</a>', row, re.S)
        badge = re.search(r'text-shadow[^"]*">(\d+)</span>', makes.group(0)) if makes else None
        reagents = {}
        for title in re.findall(r'title="([^"]+ ×\d+[^"]*)"', row):
            if 'no longer needed' in title:
                continue
            t = re.match(r'(.+?) ×(\d+)', html.unescape(title))
            reagents[t.group(1)] = int(t.group(2))
        src = re.search(r'md:block">([A-Z][A-Za-z, ]+)</div>', row)
        learn = re.search(r'\(<b class="font-semibold text-white">(\d+)</b>\)', row)
        # The first colour line is Forever's; a second one ("was") is Classic's. Forever lines without a range
        # (grey at the learn skill, e.g. Runecloth Belt 255 - 255 255) are missing data: take Classic's.
        lines = [[num(x) for x in re.findall(r'w-\[3ch\][^>]*>([^<]*)<', ln)] for ln in re.findall(r'font-mono[^>]*>(.*?)</div>', row, re.S)]
        colors = lines[0] if lines else []
        if len(lines) > 1 and not has_range(colors) and has_range(lines[1]):
            colors = lines[1]
        status = re.search(r'label inline-flex[^>]*>(?:<span[^>]*></span>)?([^<]+)<', row)
        quality = re.search(r'font-semibold hover:underline" style="color:var\(--q(\d)\)', row)
        out[name] = {'id': rid, 'item': int(item.group(1)) if item else None, 'makes': int(badge.group(1)) if badge else 1,
                     'learn': int(learn.group(1)) if learn else None, 'colors': colors,
                     'source': src.group(1).strip() if src else '', 'reagents': reagents,
                     'quality': int(quality.group(1)) if quality else None,
                     'status': html.unescape(status.group(1)).replace('✚', '').replace('—', '').replace('?', '').strip() if status else ''}
    return out


def trainer_scans():
    """{prof: {recipe: learn skill}} from the user's trainer scans (all game clients)."""
    path = os.path.join(ROOT, 'data', 'trainers.js')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as f:
        data = json.loads(f.read().split('window.TRAINERS = ', 1)[1].split(';\n', 1)[0])
    out = {}
    for client in data.values():
        for prof, recipes in client.items():
            for name, r in recipes.items():
                if r.get('skill') is not None:
                    out.setdefault(prof, {})[name] = r['skill']
    return out


DIFFICULTY = {'optimal': 0, 'medium': 1, 'easy': 2, 'trivial': 3}  # orange, yellow, green, grey


def own_recipe_scans():
    """[(prof, recipe, skill, difficulty, reagents)] from our addon's recipe scans in every local game client
    (WoWForeverLevelerRecipes: the profession window, saved with the character's skill at that time)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from build_roster import WOW_ROOTS, parse_saved_variables
    import glob
    out = []
    for root in WOW_ROOTS:
        for path in glob.glob(os.path.join(root, '_*_', 'WTF/Account/*/SavedVariables/WoWForeverLeveler.lua')):
            with open(path, encoding='utf-8') as f:
                sv = parse_saved_variables(f.read())
            for item, p in (sv.get('WoWForeverLevelerShopPrices') or {}).items():
                if isinstance(p, dict) and p.get('price'):
                    SHOP[item] = min(SHOP.get(item, 10 ** 9), p['price'] / (p.get('per') or 1))
            for profs in (sv.get('WoWForeverLevelerRecipes') or {}).values():
                for prof, e in (profs or {}).items():
                    rank = e.get('rank') if isinstance(e, dict) else None
                    for name, r in ((e or {}).get('recipes') or {}).items():
                        reag = {x.get('name'): x.get('count') for x in (r.get('reagents') or {}).values() if isinstance(x, dict)} \
                            if isinstance(r.get('reagents'), dict) else {}
                        out.append((prof, name, rank, r.get('difficulty'), reag))
    return out


def correct_from_game(recipes, scans):
    """The game wins over the site (Novice's Practice Wand: site learn 10 "Not yet confirmed", Vestac knows it
    orange at Enchanting 3): a known recipe is learned by that skill and confirmed; its colour at that skill moves
    the site's colours just enough to match (orange: yellow above it; grey: grey at or below it)."""
    notes = []
    for prof, name, rank, diff, reag in scans:
        r = recipes.get(prof, {}).get(name)
        if not r or rank is None:
            continue
        r['scanned'] = True
        # No source and known by skill 10: it comes with the profession (Apprentice), so from skill 1.
        learned = 1 if not r['source'] and rank <= 10 else rank
        if r['learn'] is None or r['learn'] > learned:
            notes.append(f'{prof}: {name} learn {r["learn"]} -> {learned} (known in game)')
            r['learn'] = learned
        c = (r['colors'] + [None] * 4)[:4]
        d = DIFFICULTY.get(diff)
        if d is None or not has_range(c):
            continue
        yellow, green, grey = c[1] or c[0], c[2], c[3]
        if d == 0 and yellow is not None and yellow <= rank:
            shift = rank + 1 - yellow
            c = [x + shift if x is not None else None for x in c]
        elif d == 3 and grey is not None and grey > rank:
            shift = rank - grey
            c = [x + shift if x is not None else None for x in c]
        r['colors'] = c
    return notes


def correct(recipes, scans):
    """Apply the game's learn skill (the colours stay) and mark the recipe as taught by a trainer."""
    notes = []
    for prof, scanned in scans.items():
        rs = recipes.get(prof)
        if rs is None:
            continue
        for name, skill in scanned.items():
            r = rs.get(name)
            if not r:
                continue
            if 'Trainer' not in r['source']:
                r['source'] = (r['source'] + ', Trainer').strip(', ')
            r['scanned'] = True
            if r['learn'] is not None and skill != r['learn'] and skill > 0:
                notes.append(f'{prof}: {name} learn {r["learn"]} -> {skill} (game scan)')
                r['learn'] = skill
    return notes


# --- Leveling path ----------------------------------------------------------------------------------------------
# Bars from ore (Mining). Bronze makes 2 from 1 Copper + 1 Tin, so half of each per bar.
SMELT = {'Copper Bar': {'Copper Ore': 1}, 'Tin Bar': {'Tin Ore': 1}, 'Silver Bar': {'Silver Ore': 1},
         'Bronze Bar': {'Copper Bar': 0.5, 'Tin Bar': 0.5}, 'Iron Bar': {'Iron Ore': 1}, 'Gold Bar': {'Gold Ore': 1},
         'Steel Bar': {'Iron Bar': 1, 'Coal': 1}, 'Mithril Bar': {'Mithril Ore': 1},
         'Truesilver Bar': {'Truesilver Ore': 1}, 'Thorium Bar': {'Thorium Ore': 1}}
VENDOR = re.compile(r'(Thread|Dye|Vial|Flux|Salt|Spice|Mote of Magic|Copper Rod|Silver Rod|Golden Rod|Truesilver Rod|'
                    r'Arcanite Rod|Leaded Vial|Crystal Vial|Imbued Vial|Coal|Oil|Bleach|Spices)$')
GATHERED = re.compile(r'^(Light|Medium|Heavy|Thick|Rugged) Leather$|^(Linen|Wool|Silk|Mageweave) Cloth$|^Runecloth$')
# A rough value per raw material (copper) when there is no auction price: higher tiers cost more.
TIER = [(r'Linen|Copper|Light Leather|Peacebloom|Silverleaf|Strange Dust|Rough Stone|Ruined Leather|Earthroot|Mageroyal', 10),
        (r'Wool|Tin|Medium Leather|Briarthorn|Bruiseweed|Coarse Stone|Soul Dust|Swiftthistle|Stranglekelp', 25),
        (r'Silk|Iron|Heavy Leather|Kingsblood|Liferoot|Wild Steelbloom|Heavy Stone|Vision Dust|Fadeleaf|Goldthorn|Khadgar', 60),
        (r'Mageweave|Mithril|Thick Leather|Sungrass|Firebloom|Purple Lotus|Dream Dust|Solid Stone|Arthas', 120),
        (r'Runecloth|Thorium|Rugged Leather|Dense Stone|Illusion Dust|Golden Sansam|Dreamfoil|Mountain Silversage', 200)]


def load_prices():
    path = os.path.join(ROOT, 'data', 'prices.js')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as f:
        allp = json.loads(f.read().split('window.PRICES = ', 1)[1].split(';\n', 1)[0])
    out, seen = {}, {}
    for scope in allp.values():
        for item, hist in scope.items():
            mins = sorted(e['min'] for e in hist if e.get('min'))
            if mins:
                out[item] = mins[len(mins) // 2]
            seen.setdefault(item, []).extend(mins)
    # Sale prices are stricter: seen in at least 2 scans, the lower quarter of all lowest prices (one odd
    # listing at a silly price does not count).
    SALE.clear()
    for item, mins in seen.items():
        if len(mins) >= 2:
            SALE[item] = sorted(mins)[len(mins) // 4]
    return out


def make_raw(all_recipes):
    """raw(item, qty, out, vendor): break an item down to gathered materials (out) and vendor goods (vendor)."""
    made = {}
    for prof in ('Tailoring', 'Leatherworking', 'Blacksmithing', 'Engineering', 'Alchemy', 'Enchanting'):
        for name, r in all_recipes.get(prof, {}).items():
            # Only cheap intermediates (bolts, kits, powders, tubes): an item that is itself a leveling craft stays as is.
            if r['reagents'] and re.search(r'^Bolt of|Blasting Powder|Copper Tube|Bronze Tube|Copper Bolts|Bronze Framework|'
                                           r'Iron Strut|Gyrochronatom|Whirring Bronze Gizmo|Mithril Tube|Thorium Widget|'
                                           r'Heavy Leather$|Cured .* Hide|Sharpening Stone|Grinding Stone|Runed .* Rod|'
                                           r'Mithril Casing|Unstable Trigger|Thorium Tube|Mithril Filigree', name):
                made[name] = (r['reagents'], r['makes'] or 1)

    def raw(item, qty, out, vendor):
        if VENDOR.search(item):
            vendor[item] = vendor.get(item, 0) + qty
        elif item in made and not GATHERED.search(item):
            reag, makes = made[item]
            for m, q in reag.items():
                raw(m, qty * q / makes, out, vendor)
        elif item in SMELT:
            for m, q in SMELT[item].items():
                raw(m, qty * q, out, vendor)
        else:
            out[item] = out.get(item, 0) + qty
    return raw


# Rare reagents: only where nothing else gives points.
RARE = re.compile(r'Ruby|Emerald|Sapphire|Pearl|Diamond|Aquamarine|Citrine|Jade|Malachite|Tigerseye|Shadowgem|'
                  r'Heart of|Essence of|Living Essence|Breath of|Globe of|Core of|Ichor|Dragonscale|Core Leather|'
                  r'Fiery Core|Lava Core|Felcloth|Mooncloth|Enchanted|Shard|Nether Essence|Power Core|Transformer|'
                  r'Ironweb|Guardian Stone|Elemental|Shadow Silk|Spider Silk|Ogre Tannin|Chimera|Frostsaber|Big One|'
                  r'Wildvine|Black Lotus|Worn Dragonscale|Turtle Scale|Dark Iron|Arcanite')


def value(item, prices, crafted=None, seen=()):
    """Copper per item: vendor price (our scans) for vendor goods, auction price, else a crafted item's materials,
    else a rough tier value."""
    if item in SHOP and (VENDOR.search(item) or item not in prices):
        return SHOP[item]
    if item in prices:
        return prices[item]
    if RARE.search(item):
        return 3000
    if crafted and item in crafted and item not in seen and not GATHERED.search(item):
        reag, makes = crafted[item]
        return sum(value(m, prices, crafted, seen + (item,)) * q for m, q in reag.items()) / makes
    for pat, v in TIER:
        if re.search(pat, item):
            return v
    return 1000  # unknown: assume it is hard to get


CONVERSION = re.compile(r'^Bolt of |^(Light|Medium|Heavy|Thick|Rugged) Leather$')


def chance(r, skill):
    """Skill-up chance at this skill (0 when grey or not learned yet)."""
    c = r['colors'] + [None] * (4 - len(r['colors']))
    learn, yellow, green, grey = r['learn'] or 0, c[1], c[2], c[3]
    if not has_range(c):
        # Grey at the learn skill: the site has no Forever range. Conversions (bolts, leather from leather) give
        # no points in Forever (guides, 2026-10); other recipes keep a short range (yellow +5, grey +15), as most
        # "Same" recipes had one in Classic.
        if CONVERSION.search(r.get('name', '')):
            return 0.0
        yellow, grey = learn + 5, learn + 15
    if skill < learn or grey is None or skill >= grey:
        return 0.0
    if yellow is None or skill < yellow:
        return 1.0
    return max(0.0, (grey - skill) / (grey - yellow))


def path(prof, recipes, raw, prices):
    """Point-by-point cheapest trainer recipe 1-300: steps [{from, to, recipe, count, mats}], brackets, vendor."""
    def tier(r):
        src = r['source']
        if 'Trainer' in src or (not src and ((r['learn'] or 0) <= 1 or r.get('scanned'))):
            return 0  # trainer, known from the start, or a recipe our characters know
        return 1 if ('Vendor' in src or 'Quest' in src) else 2
    crafted = {r2['name']: (r2['reagents'], r2['makes'] or 1) for r2 in ALL.values() if r2['reagents']}
    cands = []
    for name, r in recipes.items():
        if not r['reagents'] or r['learn'] is None:
            continue
        r = dict(r, name=name)
        if any(m.startswith('Item #') for m in r['reagents']):
            continue  # the site does not know a reagent: data not ready
        if r['status'] == 'Not yet confirmed' and not r.get('scanned'):
            continue
        # A vendor or quest recipe that only the Alliance can get (data/recipe_sources.json from ClassicDB).
        if 'Trainer' not in r['source'] and HORDE.get(name) is False:
            continue
        if re.search(r'^(Apprentice|Journeyman|Expert|Artisan) |Trainer$|Camp|Tent|Study|Laboratory', name):
            continue
        # Cooldowns (one a day or so): never a leveling recipe ...
        # ... and holiday patterns (only during an event).
        if re.search(r'^Transmute|^Mooncloth$|^Salt Shaker$| Recipe$|Festival|Winter Veil|Hallow|Lunar|Lovely|Noggenfogger', name):
            continue
        mats, vend = {}, {}
        for m, q in r['reagents'].items():
            raw(m, q, mats, vend)
        cost = sum(value(m, prices, crafted) * q for m, q in mats.items()) + sum(value(m, prices, crafted) * q for m, q in vend.items())
        sale = SALE_WEIGHT * 0.95 * SALE[name] * (r.get('makes') or 1) if r.get('item') and name in SALE else 0
        # Green or better armor and weapons can be disenchanted (Vestac): the materials' value, unlimited (the
        # dust and essences also feed the team's Enchanting). A sale counts as at most twice the material cost.
        # An enchanter disenchanting their own crafts is a loop (and the user keeps the Strange Dust path): no
        # disenchant value for Enchanting's crafts.
        de = SALE_WEIGHT * de_value(r, prices) * (r.get('makes') or 1) if prof != 'Enchanting' else 0
        r['sale'], r['de'] = min(max(sale, de), 2 * cost), min(de, 2 * cost)
        # A reagent this profession makes (Rugged Armor Kit for Mystic Rugged Armor Kit): usable from its skill on.
        needs = max([recipes[m]['learn'] or 0 for m in r['reagents'] if m in recipes and m != name] + [r['learn']])
        cands.append((name, r, cost, tier(r), needs))
    steps, skill, used = [], 1, {}
    while skill < 300:
        best = None
        # Drop recipes (random monster drops: you may never find one) only where no trainer, vendor or quest
        # recipe gives points.
        usable = [c for c in cands if c[3] < 2 and skill >= c[4] and chance(c[1], skill) > 0] or cands
        for name, r, cost, t, needs in usable:
            p = chance(r, skill) if skill >= needs else 0
            if p > 0:
                # Net cost of one craft: materials less the sale while the market still takes this item. Below 0
                # is a profit; per skill point that is net / chance (a lower chance means more crafts to sell).
                net = cost - (r['sale'] if used.get(name, 0) < MARKET_CAP else r['de'])
                # Cost per point when it costs; profit per craft times the chance when it pays (a slow recipe does
                # not win just because it needs more crafts).
                score = net / p if net > 0 else net * p
                # A recipe to buy costs a little extra, one to find a lot (weighed against the materials).
                score = score * (1, 2, 5)[t] if score > 0 else score / (1, 2, 5)[t]
                if best is None or score < best[0]:
                    best = (score, name, r, p)
        if not best:
            # No trainer recipe gives points here: a gap the path cannot cross (see the notes).
            steps.append({'from': skill, 'to': skill, 'recipe': '', 'count': 0, 'gap': True})
            skill += 1
            continue
        _, name, r, p = best
        used[name] = used.get(name, 0) + 1 / p
        if steps and steps[-1]['recipe'] == name:
            steps[-1]['to'] = skill + 1
            steps[-1]['crafts'] += 1 / p
        else:
            steps.append({'from': skill, 'to': skill + 1, 'recipe': name, 'crafts': 1 / p})
        skill += 1
    out_steps = []
    for st in steps:
        if st.get('gap'):
            if out_steps and out_steps[-1].get('gap'):
                out_steps[-1]['to'] = st['to'] + 1
            else:
                out_steps.append({'from': st['from'], 'to': st['to'] + 1, 'recipe': '', 'count': 0, 'mats': {}, 'gap': True})
            continue
        n = max(1, math.ceil(st['crafts']))
        r = recipes[st['recipe']]
        step = {'from': st['from'], 'to': st['to'], 'recipe': st['recipe'], 'count': n,
                'mats': {m: q * n for m, q in r['reagents'].items()}}
        # The same materials as gathered raw materials (bolts as cloth, bars as ore), vendor goods left out: the
        # Planner counts what is still needed from the current skill (have / still need).
        raw_mats, _vendor = {}, {}
        for m, q in step['mats'].items():
            raw(m, q, raw_mats, _vendor)
        step['raw'] = {k: math.ceil(v) for k, v in sorted(raw_mats.items(), key=lambda kv: -kv[1])}
        if r['source'] and 'Trainer' not in r['source']:
            step['source'] = r['source']
        if r.get('item') and st['recipe'] in SALE:
            step['sell'] = SALE[st['recipe']]  # auction price of one made item (copper, our scans, strict)
        de = de_value(r, prices)
        if de > 0:
            step['de'] = round(de)  # what disenchanting one is worth (copper, Classic table, our prices)
        out_steps.append(step)
    brackets = [{'from': 1, 'to': 150, 'mats': {}}, {'from': 150, 'to': 225, 'mats': {}}, {'from': 225, 'to': 300, 'mats': {}}]
    vendor = {}
    for st in out_steps:
        b = brackets[0 if st['from'] < 150 else 1 if st['from'] < 225 else 2]
        for m, q in st['mats'].items():
            raw(m, q, b['mats'], vendor)
    for b in brackets:
        b['mats'] = {k: math.ceil(v) for k, v in sorted(b['mats'].items(), key=lambda kv: -kv[1])}
    return {'steps': out_steps, 'brackets': [b for b in brackets if b['mats']],
            'vendor': {k: math.ceil(v) for k, v in sorted(vendor.items())}}


def main():
    cached = '--cached' in sys.argv
    recipes = {}
    for prof in SLUGS:
        recipes[prof] = {}
        for rank in RANKS:
            recipes[prof].update(parse(prof, fetch(prof, rank, cached)))
    notes = correct(recipes, trainer_scans())
    notes += correct_from_game(recipes, own_recipe_scans())
    print('item levels read:', add_item_info(recipes, False))  # missing item pages are fetched once
    with open(RECIPES_OUT, 'w', encoding='utf-8') as f:
        json.dump({'source': SITE + ' (Wowhead Forever data) + own trainer scans', 'notes': notes, 'professions': recipes},
                  f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write('\n')
    print('\n'.join(notes))
    for prof, rs in recipes.items():
        print(f'{prof}: {len(rs)} recipes, {sum(1 for r in rs.values() if "Trainer" in r["source"])} from trainers')
    raw, prices = make_raw(recipes), load_prices()
    # Every recipe by the item it makes (its name), for the value of crafted reagents.
    for prof, rs in recipes.items():
        for name, r in rs.items():
            ALL.setdefault(name, dict(r, name=name))
    out = {'source': 'scripts/forever_profs.py from data/forever_recipes.json', 'professions': {}}
    for prof in ('Alchemy', 'Blacksmithing', 'Enchanting', 'Engineering', 'Leatherworking', 'Tailoring', 'First Aid', 'Cooking'):
        p = path(prof, recipes[prof], raw, prices)
        out['professions'][prof] = p
        gaps = [f"{s['from']}-{s['to']}" for s in p['steps'] if s.get('gap')]
        print(f"\n== {prof}" + (f"  GAPS: {', '.join(gaps)}" if gaps else ''))
        for s in p['steps']:
            if not s.get('gap'):
                print(f"  {s['from']:3}-{s['to']:3} {s['count']:4} {s['recipe']}" + (f" ({s['source']})" if s.get('source') else '') + f"  [{', '.join(f'{q} {m}' for m, q in s['mats'].items())}]")
        for b in p['brackets']:
            print(f"  {b['from']}-{b['to']}: " + ', '.join(f'{n} {i}' for i, n in list(b['mats'].items())[:6]))
    with open(PROFS_OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, ensure_ascii=False)  # keep the order: steps by skill, materials biggest first
        f.write('\n')
    print('wrote', RECIPES_OUT, 'and', PROFS_OUT)


if __name__ == '__main__':
    main()

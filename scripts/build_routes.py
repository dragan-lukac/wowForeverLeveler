#!/usr/bin/env python3
"""
Quest routes per zone for the in-game Leveling tab -> data/routes.js (then `make guide` puts them in Plan.lua).

Two kinds:
  recorded - the real order a character played (addon journey log: accept / done / turnin with map spots;
             older characters only have accept and hand-in times, then the spots come from QuestieDB).
  built    - our own order from the QuestieDB addon's Forever database (local addon file, no web):
             a walk that picks the nearest next step (take quest, do objectives, hand in) and takes every
             step at a hub at once. Quest XP (QuestieDB xpDB + kills) moves an estimated level, which
             unlocks quests; grey quests are not taken; elite quests (guide.json skips) and quests whose
             objectives are not in the zone (dungeons) are left out.
A recorded route wins over the built one for its zone.

Step: {k: "a" take | "d" do | "t" hand in, id, n quest, m map, x, y, npc, l estimated level, r required
level, c class mask (only class quests), o short objective (do steps)}.
Run: python3 scripts/build_routes.py  (needs the QuestieDB addon; the save file for recorded routes)
"""

import glob
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import questie_db  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, 'data', 'guide.json')
OUT = os.path.join(ROOT, 'data', 'routes.js')

ZONE_MAP = {'Tirisfal Glades': 1420, 'Durotar': 1411, 'Mulgore': 1412, 'The Barrens': 1413, 'Orgrimmar': 1454,
            'Thunder Bluff': 1456, 'Undercity': 1458, 'Silverpine Forest': 1421, 'Hillsbrad Foothills': 1424,
            'Ashenvale': 1440, 'Stonetalon Mountains': 1442, 'Desolace': 1443, 'Thousand Needles': 1441,
            'Arathi Highlands': 1417, 'Stranglethorn Vale': 1434, 'Tanaris': 1446, 'Feralas': 1444,
            'The Hinterlands': 1425, 'Dustwallow Marsh': 1445, 'Swamp of Sorrows': 1435, 'Badlands': 1418,
            'Alterac Mountains': 1416, 'Western Plaguelands': 1422, 'Eastern Plaguelands': 1423, 'Felwood': 1448,
            "Un'Goro Crater": 1449, 'Winterspring': 1452, 'Silithus': 1451, 'Azshara': 1447, 'Wetlands': 1437,
            'Searing Gorge': 1427, 'Burning Steppes': 1428, 'Blasted Lands': 1419, 'The Riverglades': 2548,
            'Zephras Isle': 2521}
MAP_ZONE = {v: k for k, v in ZONE_MAP.items()}

HORDE_RACES = 2 | 16 | 32 | 128  # Orc, Undead, Tauren, Troll
KILL_FACTOR = 1.6  # quest XP is about 60% of leveling; the kills on the way give the rest
HUB_RADIUS = 4.0  # map units: steps this close count as "here"

# Classic XP to the next level, levels 1-59 (Forever may differ; only used to estimate the level).
LEVEL_XP = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
            17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
            50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
            117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900,
            195000, 202300, 209800]


def area_maps(toc):
    """QuestieDB areaId -> uiMapID (zones and their subzones)."""
    path = os.path.join(os.path.dirname(toc), 'support', 'Forever', 'Zones', 'areaIdToUiMapId.lua')
    with open(path, encoding='utf-8') as f:
        return {int(a): int(m) for a, m in re.findall(r'\[(\d+)\] = (\d+),', f.read())}


def quest_xp(toc):
    path = os.path.join(os.path.dirname(toc), 'support', 'Forever', 'QuestXP', 'xpDB-classic.lua')
    with open(path, encoding='utf-8') as f:
        return {int(q): int(xp) for q, _, xp in re.findall(r'\[(\d+)\] = \{(\d+), (\d+)\}', f.read())}


def grey_level(level):
    """Quests at or below this level give (almost) no XP."""
    if level <= 5:
        return 0
    if level <= 39:
        return level - level // 10 - 5
    return level - level // 5 - 1


def by_area(spawns):
    """Spawn tables keyed by area ID; a table with keys 1..n comes back from CBOR as a list."""
    if isinstance(spawns, list):
        return {i + 1: v for i, v in enumerate(spawns) if v}
    return spawns or {}


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


class World:
    def __init__(self, db, amap):
        self.db, self.amap = db, amap

    def spawns(self, kind, eid, mapid):
        e = self.db[kind].get(eid) or {}
        pts = []
        for area, lst in by_area(e.get('spawns')).items():
            if self.amap.get(int(area)) == mapid:
                pts += [(p[0], p[1]) for p in lst if isinstance(p, list) and len(p) >= 2 and p[0] >= 0]
        return pts

    def any_spawn_map(self, kind, eid):
        e = self.db[kind].get(eid) or {}
        for area, lst in by_area(e.get('spawns')).items():
            if lst and self.amap.get(int(area)):
                return self.amap[int(area)], (lst[0][0], lst[0][1])
        return None, None

    def givers(self, field, mapid):
        """[(name, point)] of quest starters/finishers (npcs, objects) in this map."""
        out = []
        groups = field or []
        if isinstance(groups, dict):
            groups = [groups.get(i) or groups.get(str(i)) for i in (1, 2, 3)]
        for kind, ids in zip(('npcs', 'objects'), groups[:2]):
            for eid in ids or []:
                pts = self.spawns(kind, eid, mapid)
                if pts:
                    out.append(((self.db[kind].get(eid) or {}).get('name', ''), pts[0]))
        # Quests started by an item: where that item drops.
        for iid in (groups[2] if len(groups) > 2 else None) or []:
            item = self.db['items'].get(iid) or {}
            pts = [p for n in item.get('npcDrops') or [] for p in self.spawns('npcs', n, mapid)]
            pts += [p for o in item.get('objectDrops') or [] for p in self.spawns('objects', o, mapid)]
            if pts:
                out.append(('item: ' + item.get('name', ''), densest(pts)))
        return out

    def giver_anywhere(self, field):
        groups = field or []
        if isinstance(groups, dict):
            groups = [groups.get(1) or groups.get('1'), groups.get(2) or groups.get('2')]
        for kind, ids in zip(('npcs', 'objects'), groups[:2]):
            for eid in ids or []:
                m, p = self.any_spawn_map(kind, eid)
                if m:
                    return (self.db[kind].get(eid) or {}).get('name', ''), m, p
        return None, None, None

    def objective_points(self, q, mapid):
        """Spawn points of everything the quest needs (monsters, objects, item droppers), in this map.
        Returns (points, has_objectives)."""
        obj = q.get('objectives') or {}
        if isinstance(obj, list):
            obj = {i + 1: g for i, g in enumerate(obj)}
        obj = {int(k): v for k, v in obj.items()}
        pts, has = [], False
        for e in obj.get(1) or []:
            has = True
            pts += self.spawns('npcs', e[0], mapid)
        for e in obj.get(2) or []:
            has = True
            pts += self.spawns('objects', e[0], mapid)
        for e in obj.get(3) or []:
            has = True
            item = self.db['items'].get(e[0]) or {}
            for n in item.get('npcDrops') or []:
                pts += self.spawns('npcs', n, mapid)
            for o in item.get('objectDrops') or []:
                pts += self.spawns('objects', o, mapid)
        for e in obj.get(5) or []:
            has = True
            for n in (e[0] if isinstance(e[0], list) else [e[0]]):
                pts += self.spawns('npcs', n, mapid)
        trig = q.get('triggerEnd')
        if trig and len(trig) > 1 and trig[1]:
            has = True
            for area, lst in by_area(trig[1]).items():
                if self.amap.get(int(area)) == mapid:
                    pts += [(p[0], p[1]) for p in lst]
        return pts, has


def densest(pts, radius=8.0):
    """The spawn point with the most other spawns near it (where to go for the objectives)."""
    if not pts:
        return None
    sample = pts if len(pts) <= 400 else pts[::len(pts) // 400 + 1]
    best = max(sample, key=lambda p: sum(1 for o in sample if dist(p, o) <= radius))
    return (round(best[0], 1), round(best[1], 1))


def short_objective(q):
    text = (q.get('objectivesText') or [''])[0] or ''
    text = re.split(r',? (?:and )?(?:then )?(?:return|report|bring|go back)\b', text, 1, flags=re.I)[0]
    text = text.strip().rstrip('.,')
    return text if len(text) <= 70 else text[:67].rsplit(' ', 1)[0] + '...'


SKILLS = {171: 'Alchemy', 164: 'Blacksmithing', 333: 'Enchanting', 202: 'Engineering', 182: 'Herbalism',
          165: 'Leatherworking', 186: 'Mining', 393: 'Skinning', 197: 'Tailoring', 185: 'Cooking',
          129: 'First Aid', 356: 'Fishing'}


def quest_profession(q):
    """The profession a quest is for ("Camping 101: Mining", or a required skill), else None."""
    m = re.match(r'Camping 101: (.+)$', q.get('name') or '')
    if m:
        return m.group(1)
    skill = q.get('requiredSkill')
    if isinstance(skill, list) and skill and skill[0] in SKILLS:
        return SKILLS[skill[0]]
    return None


def horde_ok(q):
    races = q.get('requiredRaces') or 0
    return races == 0 or bool(races & HORDE_RACES) or races & 0xFF == 0


# Hassle rules: quests that cost much time for their XP are left out of built routes (and recorded ones).
HASSLE_TEXT = re.compile(r'\b(escort|protect|accompany|defend|survive|wait for|guard)\b', re.I)
FAR = 18.0  # map units (about a fifth of the zone) from every other quest of the zone


def hassle_skips(quests):
    """{quest id: reason} for quests far from all others (a long walk for one quest), unless another quest of
    the zone needs it first."""
    needed = set()
    for v in quests.values():
        q = v['q']
        needed |= set(q.get('preQuestSingle') or []) | set(q.get('preQuestGroup') or [])
    out = {}
    for qid, v in quests.items():
        if not v['do'] or qid in needed:
            continue
        others = [p for oid, o in quests.items() if oid != qid
                  for p in (o['start'][1], o['do'], o['end'][1] if o['end'][2] == v['end'][2] else None) if p]
        near = min((dist(v['do'], p) for p in others), default=0)
        if near > FAR:
            out[qid] = f'far from other quests ({round(near)} map units)'
    return out


FOLLOW_UPS = {}  # quests some other quest needs first (their chain goes on)


def build_zone(world, zone, levels, skips, xpdb, start_level=None, skipped=None, next_zones=()):
    mapid = ZONE_MAP[zone]
    db = world.db
    follow_ups = FOLLOW_UPS.get(id(db))
    if follow_ups is None:
        follow_ups = FOLLOW_UPS[id(db)] = {p for q in db['quests'].values()
                                           for p in (q.get('preQuestSingle') or []) + (q.get('preQuestGroup') or [])}
    lo, hi = levels
    quests = {}
    skipped = {} if skipped is None else skipped
    for qid, q in db['quests'].items():
        if qid in skips or not horde_ok(q) or (q.get('specialFlags') or 0) & 1:
            continue
        if (q.get('questLevel') or 0) < 0 or (q.get('questLevel') or 0) > hi + 3:
            continue
        starts = world.givers(q.get('startedBy'), mapid)
        if not starts:
            continue
        pts, has = world.objective_points(q, mapid)
        if has and not pts:
            continue  # objectives in a dungeon or another zone
        ends = world.givers(q.get('finishedBy'), mapid)
        if ends:
            end = (ends[0][0], ends[0][1], mapid)
        else:
            name, m, p = world.giver_anywhere(q.get('finishedBy'))
            if not m:
                continue
            end = (name, p, m)
        # RestedXP-style (learned from Pala's play): a quest that only sends you to another zone (a letter to
        # Undercity) is a trip for little XP. It stays when it is a class quest or a breadcrumb, when its chain
        # goes on (Pala took The Prodigal Lich), or when it goes to the next zone of a route.
        leads_on = q.get('nextQuestInChain') or q.get('childQuests') or qid in follow_ups
        if (end[2] != mapid and not has and not q.get('requiredClasses') and not q.get('breadcrumbForQuestId')
                and not leads_on and MAP_ZONE.get(end[2]) not in next_zones):
            skipped[qid] = {'n': q.get('name', ''), 'why': 'only sends you to ' + MAP_ZONE.get(end[2], 'another zone')}
            continue
        text = ' '.join(q.get('objectivesText') or [])
        if HASSLE_TEXT.search(text) and not q.get('requiredClasses'):
            skipped[qid] = {'n': q.get('name', ''), 'why': 'escort or event: slow, can fail'}
            continue
        quests[qid] = {'q': q, 'start': starts[0], 'do': densest(pts), 'end': end}
    for qid, why in hassle_skips(quests).items():
        skipped[qid] = {'n': quests[qid]['q'].get('name', ''), 'why': why}
        del quests[qid]
    pre_single = {qid: set(v['q'].get('preQuestSingle') or []) for qid, v in quests.items()}
    pre_group = {qid: set(v['q'].get('preQuestGroup') or []) for qid, v in quests.items()}

    level = start_level or lo
    xp = 0
    pos = None
    taken, did, turned = set(), set(), set()
    blocked = set()  # exclusive quests ruled out by a taken one
    steps = []

    def available(qid):
        v = quests[qid]
        q = v['q']
        if qid in taken or qid in blocked:
            return False
        if (q.get('requiredLevel') or 1) > level or (q.get('questLevel') or 1) <= grey_level(level):
            return False
        if pre_single[qid] and pre_single[qid] <= set(skipped):
            return False
        if pre_single[qid] and not (pre_single[qid] & turned):
            # Prerequisites outside this zone's list count as done (earlier zone or a city).
            if pre_single[qid] & set(quests):
                return False
        if pre_group[qid] and not (pre_group[qid] & set(quests)) <= turned:
            return False
        return True

    def gain(qid):
        nonlocal level, xp
        xp += xpdb.get(qid, 0) * KILL_FACTOR
        while level < 60 and xp >= LEVEL_XP[level - 1]:
            xp -= LEVEL_XP[level - 1]
            level += 1

    while True:
        actions = []
        for qid in quests:
            if available(qid):
                actions.append(('a', qid, quests[qid]['start'][1], mapid))
        for qid in taken - did:
            if quests[qid]['do']:
                actions.append(('d', qid, quests[qid]['do'], mapid))
            else:
                did.add(qid)
        for qid in did - turned:
            name, p, m = quests[qid]['end']
            if m == mapid:
                actions.append(('t', qid, p, m))
        if not actions:
            # Only quests above the estimated level are left: a "level up first" step, then go on.
            later = [quests[qid]['q'].get('requiredLevel') or 1 for qid in quests
                     if qid not in taken and qid not in blocked and (quests[qid]['q'].get('requiredLevel') or 1) > level]
            nxt = min(later, default=99)
            if nxt > hi:
                break
            level, xp = nxt, 0
            steps.append({'k': 'w', 'l': level, 'n': f'Level {level}'})
            continue
        here = pos or actions[0][2]
        # At a hub: hand in first, then take; else the nearest step.
        near = [a for a in actions if a[0] != 'd' and dist(a[2], here) <= HUB_RADIUS]
        if near:
            act = min(near, key=lambda a: (a[0] != 't', dist(a[2], here)))
        else:
            act = min(actions, key=lambda a: dist(a[2], here))
        k, qid, p, m = act
        v = quests[qid]
        q = v['q']
        step = {'k': k, 'id': qid, 'n': q.get('name', ''), 'm': m, 'x': p[0], 'y': p[1], 'l': level}
        if k == 'a':
            taken.add(qid)
            blocked |= set(q.get('exclusiveTo') or [])
            step['npc'] = v['start'][0]
            step['r'] = q.get('requiredLevel') or 1
            prof = quest_profession(q)
            if prof:
                step['p'] = prof
            if q.get('requiredClasses'):
                step['c'] = q['requiredClasses']
        elif k == 'd':
            did.add(qid)
            step['o'] = short_objective(q)
        else:
            turned.add(qid)
            step['npc'] = v['end'][0]
            gain(qid)
        steps.append(step)
        pos = p
    # Hand-ins in another zone (letters to the next zone, city quests): at the end, as a reminder.
    for qid in sorted(did - turned):
        name, p, m = quests[qid]['end']
        steps.append({'k': 't', 'id': qid, 'n': quests[qid]['q'].get('name', ''), 'm': m, 'x': p[0], 'y': p[1],
                      'npc': name, 'l': level, 'z': MAP_ZONE.get(m, '')})
    return steps


# --- Recorded routes -----------------------------------------------------------------------------------------

def recorded_routes(world):
    """Per character: the journey (accept/done/turnin with spots) or, for older data, the accept and hand-in
    times of the done list. Grouped by zone, in play order."""
    from quest_report import load_saved_variables
    logs = load_saved_variables().get('WoWForeverLevelerQuestLog') or {}
    out = {}
    for key, log in logs.items():
        char = key.split('-')[1] if '-' in key else key
        events = []
        seen = set()
        for e in log.get('journey') or []:
            if e.get('k') in ('accept', 'done', 'turnin') and e.get('id'):
                events.append(dict(e))
                seen.add((e['k'], e['id']))
        for d in log.get('done') or []:
            if d.get('acceptTime') and ('accept', d['id']) not in seen:
                events.append({'k': 'accept', 'id': d['id'], 'title': d.get('title'), 't': d['acceptTime'],
                               'level': d.get('acceptLevel'), 'zone': d.get('acceptZone')})
            if ('turnin', d['id']) not in seen:
                events.append({'k': 'turnin', 'id': d['id'], 'title': d.get('title'), 't': d.get('time', 0),
                               'level': d.get('level'), 'zone': d.get('turnInZone')})
        events.sort(key=lambda e: (e.get('t') or 0, {'turnin': 0, 'accept': 1, 'done': 2}[e['k']]))
        # A quest complete the moment it was taken (a delivery, or the item was already in the bags) has no Do.
        took_at = {e['id']: e.get('t') or 0 for e in events if e['k'] == 'accept'}
        events = [e for e in events if not (e['k'] == 'done' and abs((e.get('t') or 0) - took_at.get(e['id'], -99)) <= 2)]
        # Quest turned in without a "done" record: its "do" step goes before the run of hand-ins it belongs to.
        done_ids = {e['id'] for e in events if e['k'] == 'done'}
        accepted = {e['id'] for e in events if e['k'] == 'accept'}
        withdo = []
        run = []

        def flush():
            for t in run:
                q = world.db['quests'].get(t['id']) or {}
                if t['id'] not in done_ids and t['id'] in accepted and q.get('objectives'):
                    withdo.append({'k': 'done', 'id': t['id'], 'title': t.get('title'), 'level': t.get('level'),
                                   'zone': t.get('zone'), 'guess': True})
            withdo.extend(run)
            run.clear()
        for e in events:
            if e['k'] == 'turnin':
                run.append(e)
            else:
                flush()
                withdo.append(e)
        flush()
        steps_by_zone = {}
        for e in withdo:
            zone = e.get('zone')
            mapid = ZONE_MAP.get(zone)
            q = world.db['quests'].get(e['id']) or {}
            k = {'accept': 'a', 'done': 'd', 'turnin': 't'}[e['k']]
            step = {'k': k, 'id': e['id'], 'n': e.get('title') or q.get('name', ''), 'l': e.get('level') or 1}
            if e.get('m') and e.get('x') is not None:
                step.update(m=e['m'], x=e['x'], y=e['y'])
            elif mapid:
                p = None
                if k == 'a':
                    g = world.givers(q.get('startedBy'), mapid)
                    p = g[0][1] if g else None
                    if g:
                        step['npc'] = g[0][0]
                elif k == 't':
                    g = world.givers(q.get('finishedBy'), mapid)
                    p = g[0][1] if g else None
                    if g:
                        step['npc'] = g[0][0]
                else:
                    p = densest(world.objective_points(q, mapid)[0])
                if p:
                    step.update(m=mapid, x=round(p[0], 1), y=round(p[1], 1))
            if e.get('npc'):
                step['npc'] = e['npc']
            if k == 'd':
                step['o'] = short_objective(q)
            if k == 'a':
                step['r'] = q.get('requiredLevel') or 1
                if quest_profession(q):
                    step['p'] = quest_profession(q)
                if q.get('requiredClasses'):
                    step['c'] = q['requiredClasses']
            if zone:
                steps_by_zone.setdefault(zone, []).append(step)
        for zone, steps in steps_by_zone.items():
            if sum(1 for s in steps if s['k'] == 'a') >= 5:
                out.setdefault(zone, []).append({'by': char, 'steps': steps})
    return out


def finish_steps(world, zone, steps):
    """Do / hand-in steps for quests a recording took but never handed in (the player stopped there)."""
    mapid = ZONE_MAP.get(zone)
    has = {(st['k'], st['id']) for st in steps if st.get('id')}
    todo = []
    for st in steps:
        if st['k'] != 'a' or ('t', st['id']) in has:
            continue
        q = world.db['quests'].get(st['id']) or {}
        if ('d', st['id']) not in has:
            p = densest(world.objective_points(q, mapid)[0]) if mapid else None
            if p:
                todo.append({'k': 'd', 'id': st['id'], 'n': st['n'], 'm': mapid, 'x': p[0], 'y': p[1],
                             'l': st['l'], 'o': short_objective(q)})
        g = world.givers(q.get('finishedBy'), mapid) if mapid else []
        if g:
            todo.append({'k': 't', 'id': st['id'], 'n': st['n'], 'm': mapid, 'x': round(g[0][1][0], 1),
                         'y': round(g[0][1][1], 1), 'npc': g[0][0], 'l': st['l']})
        else:
            name, m, p = world.giver_anywhere(q.get('finishedBy'))
            if m:
                todo.append({'k': 't', 'id': st['id'], 'n': st['n'], 'm': m, 'x': round(p[0], 1), 'y': round(p[1], 1),
                             'npc': name, 'l': st['l'], 'z': MAP_ZONE.get(m, ''), 'away': True})
    # All the Do steps first (nearest first from the last recorded spot), then the hand-ins in one trip (they
    # sit together in the town), other-zone hand-ins last.
    last = next(((st['x'], st['y']) for st in reversed(steps) if st.get('x') is not None), (50, 50))
    out = []
    for kind in ('d', 't'):
        left = [t for t in todo if t['k'] == kind and not t.get('away')]
        while left:
            nxt = min(left, key=lambda t: dist((t['x'], t['y']), last))
            out.append(nxt)
            left.remove(nxt)
            last = (nxt['x'], nxt['y'])
    # Away hand-ins: the city first (one visit), then the next zone.
    cities = ('Undercity', 'Orgrimmar', 'Thunder Bluff')
    for t in sorted((t for t in todo if t.get('away')), key=lambda t: (t['z'] not in cities, t['z'])):
        t.pop('away')
        out.append(t)
    return out


def build():
    toc = questie_db.toc_path()
    if not toc:
        # Without the QuestieDB folder (Questie uninstalled with it): keep the last data/routes.js and let the sync
        # go on. Reinstall QuestieDB to refresh the routes.
        print('[routes] QuestieDB addon not found (QuestieDB_Forever.toc): data/routes.js kept as it is')
        return None
    db = questie_db.load(toc)
    world = World(db, area_maps(toc))
    xpdb = quest_xp(toc)
    from team import load_guide
    g = load_guide()
    route_zones = []
    for c in g['characters']:
        for z in c['zones']:
            if z not in route_zones:
                route_zones.append(z)
    # Skips you chose: guide.json routeSkips {id: reason} and the in-game "skip" clicks (save file).
    manual = {int(k): v for k, v in (g.get('routeSkips') or {}).items()}
    try:
        from quest_report import load_saved_variables
        from build_roster import WOW_ROOTS, parse_saved_variables  # noqa: F401
        for path in glob.glob('/Applications/World of Warcraft/_*_/WTF/Account/*/SavedVariables/WoWForeverLeveler.lua'):
            with open(path, encoding='utf-8') as f:
                ui = parse_saved_variables(f.read()).get('WoWForeverLevelerUI') or {}
            for k in (ui.get('skip') or {}):
                manual.setdefault(int(k), 'you skipped it in game')
    except Exception as e:
        print('No in-game skips:', e)
    routes = {}
    for zone in route_zones:
        z = g['zones'].get(zone, {})
        lv = re.findall(r'\d+', str(z.get('levels', '')))
        if zone not in ZONE_MAP or len(lv) < 2:
            continue
        skips = {s['id'] for s in z.get('skips', []) if s.get('id')} | set(manual)
        skipped = {}
        nxt = {c['zones'][i + 1] for c in g['characters'] for i, cz in enumerate(c['zones'][:-1]) if cz == zone}
        steps = build_zone(world, zone, (int(lv[0]), int(lv[1])), skips, xpdb, skipped=skipped, next_zones=nxt)
        for qid in skips:
            q = db['quests'].get(qid)
            if q and qid in manual and world.givers(q.get('startedBy'), ZONE_MAP[zone]):
                skipped[qid] = {'n': q.get('name', ''), 'why': manual[qid]}
        if steps:
            routes[zone] = {'kind': 'built', 'steps': steps, 'skipped': skipped}
    try:
        recorded = recorded_routes(world)
    except Exception as e:  # no save file yet
        print('No recorded routes:', e)
        recorded = {}
    # A recording keeps the real order, minus the quests the built route skips for hassle.
    for zone, recs in recorded.items():
        best = max(recs, key=lambda r: len(r['steps']))
        drop = set((routes.get(zone) or {}).get('skipped', {})) | set(manual)
        built_takes = [st['id'] for st in (routes.get(zone) or {}).get('steps', []) if st['k'] == 'a'
                       and st.get('r', 1) <= max(x['l'] for x in best['steps']) and not st.get('c') and not st.get('p')]
        # Quests the recording took but did not finish: their Do and Hand-in steps, nearest first.
        best['steps'] += finish_steps(world, zone, best['steps'])
        # After the recording ends, the built route goes on with the quests the recording did not reach.
        rec_ids = {st['id'] for st in best['steps']}
        top = max(x['l'] for x in best['steps'])
        late = {st['id'] for st in (routes.get(zone) or {}).get('steps', []) if st['k'] == 'a' and st['l'] >= top}
        tail = [st for st in (routes.get(zone) or {}).get('steps', [])
                if st.get('id') in late and st['id'] not in rec_ids]
        routes[zone] = {'kind': 'recorded', 'by': best['by'], 'built_takes': built_takes,
                        'steps': [st for st in best['steps'] if st['id'] not in drop] + tail,
                        'skipped': (routes.get(zone) or {}).get('skipped', {})}
    # How close the built route is to a recorded one (Pala follows RestedXP): quests both take, and the rest.
    for zone, r in routes.items():
        if r['kind'] == 'recorded' and r.get('built_takes'):
            rec = {st['id'] for st in r['steps'] if st['k'] == 'a'}
            built = set(r.pop('built_takes'))
            print(f"{zone}: built vs recorded: {len(rec & built)} same, {len(built - rec)} only built, {len(rec - built)} only recorded")
        r.pop('built_takes', None)
    # Giver spots for every quest of the zone lists (data/zone_quests.js lacks many, e.g. Undercity givers).
    givers = {}
    zq_path = os.path.join(ROOT, 'data', 'zone_quests.js')
    if os.path.exists(zq_path):
        with open(zq_path, encoding='utf-8') as f:
            zq = json.loads(f.read().split('window.ZONE_QUESTS = ', 1)[1].rstrip().rstrip(';'))['zones']
        for quests in zq.values():
            for q in quests:
                name, m, p = world.giver_anywhere((db['quests'].get(q['id']) or {}).get('startedBy'))
                if m:
                    givers[q['id']] = [m, round(p[0], 1), round(p[1], 1), name]
    routes['_givers'] = givers
    # Where each dungeon quest's chain starts (QuestieDB prerequisites): Leaders of the Fang starts with The
    # Forgotten Pools in the Crossroads. {quest id: [start id, start name, giver, map, x, y, required level]}.
    chains, chain_paths = {}, {}
    dpath = os.path.join(ROOT, 'data', 'dungeons.js')
    if os.path.exists(dpath):
        with open(dpath, encoding='utf-8') as f:
            books = json.loads(f.read().split('window.DUNGEONS = ', 1)[1].rstrip().rstrip(';'))
        Q = db['quests']

        def head(qid, seen):
            q = Q.get(qid) or {}
            pre = [x for x in (q.get('preQuestSingle') or []) + (q.get('preQuestGroup') or [])
                   if x in Q and horde_ok(Q[x]) and x not in seen]
            if not pre:
                return qid
            seen.add(qid)
            return head(pre[0], seen)
        def path(qid):
            """The chain before a quest, first quest first (one prerequisite per step)."""
            out, seen = [], {qid}
            q = Q.get(qid) or {}
            while True:
                pre = [x for x in (q.get('preQuestSingle') or []) + (q.get('preQuestGroup') or [])
                       if x in Q and horde_ok(Q[x]) and x not in seen]
                if not pre:
                    break
                seen.add(pre[0])
                out.insert(0, pre[0])
                q = Q[pre[0]]
            return out
        for book in books.values():
            for d in book.get('list', []):
                for q in d.get('quests', []):
                    steps = []
                    for sid in path(q['id']):
                        name, m, p = world.giver_anywhere(Q[sid].get('startedBy'))
                        steps.append([sid, Q[sid].get('name', ''), name or '', m or 0,
                                      round(p[0], 1) if p else 0, round(p[1], 1) if p else 0, Q[sid].get('requiredLevel') or 1])
                    if steps:
                        chain_paths[q['id']] = steps
                    h = head(q['id'], set())
                    if h != q['id']:
                        name, m, p = world.giver_anywhere(Q[h].get('startedBy'))
                        if m:
                            chains[q['id']] = [h, Q[h].get('name', ''), name, m, round(p[0], 1), round(p[1], 1),
                                               Q[h].get('requiredLevel') or 1]
    routes['_chains'] = chains
    # The whole chain before each dungeon quest: {quest id: [[id, name, giver, map, x, y, required level], ...]}.
    routes['_chainPaths'] = chain_paths
    # Dungeon entrances (QuestieDB support/Forever/Zones/dungeons.lua, the base table: Forever keeps the Classic
    # spots; the Cata block below it does not apply): {dungeon name: [map, x, y]}.
    entrances = {}
    dpath2 = os.path.join(os.path.dirname(toc), 'support', 'Forever', 'Zones', 'dungeons.lua')
    if os.path.exists(dpath2):
        with open(dpath2, encoding='utf-8') as f:
            text = f.read().split('if Expansions.Current', 1)[0]
        amap = world.amap
        for name, area, x, y in re.findall(r'\[\d+\] = \{"([^"]+)",[^\n]*?\{\{(\d+), ([\d.]+), ?([\d.]+)\}', text):
            m = amap.get(int(area))
            if m and name not in entrances:
                entrances[name] = [m, float(x), float(y)]
    routes['_entrances'] = entrances
    # Class quests (bit mask per quest), so the window can hide other classes' dungeon quests.
    routes['_classes'] = {qid: q['requiredClasses'] for qid, q in db['quests'].items() if q.get('requiredClasses')}
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('// Generated by scripts/build_routes.py (QuestieDB Forever data + recorded journeys). Do not edit by hand.\n')
        f.write('window.ROUTES = ' + json.dumps(routes, separators=(',', ':')) + ';\n')
    for zone, r in routes.items():
        if zone.startswith('_'):
            continue
        n = sum(1 for s in r['steps'] if s['k'] == 'a')
        last = r['steps'][-1]['l'] if r['steps'] else '-'
        print(f"{zone}: {r['kind']}{' by ' + r['by'] if r.get('by') else ''}, {n} quests, {len(r['steps'])} steps, "
              f"ends at level ~{last}, skipped {len(r.get('skipped', {}))}")


if __name__ == '__main__':
    build()

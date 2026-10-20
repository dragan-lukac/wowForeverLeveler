#!/usr/bin/env python3
"""
Builds guide.md and data/guide.js from data/guide.json (the single source of truth).
index.html loads data/guide.js with a <script> tag, so the dashboard works from file:// too.
The supply chain is derived from each character's `profs`; index.html mirrors this logic in supplyLines().
"""

import os
import json
from team import load_guide
import math
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'data', 'guide.json')
GUIDE_MD = os.path.join(ROOT, 'guide.md')
GUIDE_JS = os.path.join(ROOT, 'data', 'guide.js')
TRACKED_LUA = os.path.join(ROOT, 'addon', 'WoWForeverLeveler', 'TrackedItems.lua')
NPC_LUA = os.path.join(ROOT, 'addon', 'WoWForeverLeveler', 'NPCList.lua')
PLAN_LUA = os.path.join(ROOT, 'addon', 'WoWForeverLeveler', 'Plan.lua')


def dash(levels):
    return levels.replace('-', '–')


def zone_label(name, zones):
    return f"{name} ({dash(zones[name]['levels'])})"


def char_label(c):
    return f"{c['race']} {c['class']}"


def next_step(char, idx, zones):
    note = char.get('zoneNotes', {}).get(char['zones'][idx], {})
    if note.get('next'):
        return note['next']
    if idx + 1 < len(char['zones']):
        return f"Go to {zone_label(char['zones'][idx + 1], zones)}."
    return None


def checked_text(zone):
    c = zone.get('checked')
    return f"checked on {c['client']}, {c['date']}" if c else "not checked in game yet"


def role_title(profs, professions):
    kinds = {professions[p]['type'] for p in profs}
    return {frozenset({'gather'}): "Gatherer", frozenset({'craft'}): "Crafter"}.get(frozenset(kinds), "Gatherer & Crafter")


def partners(char, chars, match):
    """Characters matching `match`, same group first; falls back to the whole roster."""
    others = [c for c in chars if c is not char and match(c)]
    same_group = [c for c in others if c['group'] == char['group']]
    return same_group or others


def recipients(gatherer, code, chars, professions):
    used_by = professions[code]['usedBy']
    return partners(gatherer, chars, lambda c: any(u in c['profs'] for u in used_by))


def supply_lines(char, chars, professions):
    lines = []
    for code, prof in professions.items():
        if prof['type'] != 'gather':
            continue
        if code in char['profs']:
            to = recipients(char, code, chars, professions)
            if to:
                lines.append(f"Send {prof['gives']} to {', '.join(char_label(c) for c in to)}.")
        src = [c for c in chars if c is not char and code in c['profs'] and char in recipients(c, code, chars, professions)]
        if src:
            lines.append(f"Get {prof['gives']} from {', '.join(char_label(c) for c in src)}.")

    for code in char['profs']:
        for craft in professions[code].get('crafts', []):
            if craft.get('to') == 'all':
                lines.append(f"Make {craft['item']} for everyone.")
            else:
                to = craft_recipients(char, craft, chars)
                if to:
                    lines.append(f"Send {craft['item']} to {', '.join(char_label(c) for c in to)}.")
    received = {}
    for c in chars:
        if c is char:
            continue
        for code in c['profs']:
            for craft in professions[code].get('crafts', []):
                if craft.get('to') != 'all' and char in craft_recipients(c, craft, chars):
                    received.setdefault(craft['item'], []).append(char_label(c))
    lines += [f"Get {item} from {', '.join(makers)}." for item, makers in received.items()]
    return lines


def craft_recipients(maker, craft, chars):
    return partners(maker, chars, lambda c: any(p in c['profs'] for p in craft.get('to', []))
                    or c['class'] in craft.get('toClasses', []))


def level_line(entry):
    text = f"{entry['range']}: {' or '.join(entry['recipes'])}."
    return f"{text} {entry['note']}" if entry.get('note') else text


def pair_tips(profs, synergies):
    return [s for s in synergies if all(p in profs for p in s['profs'])]


def build_markdown(g):
    zones, chars, profs = g['zones'], g['characters'], g['professions']
    tailors = [char_label(c) for c in chars if 'tail' in c['profs']]
    enchanters = [char_label(c) for c in chars if 'ench' in c['profs']]
    out = [
        "<!-- Generated from data/guide.json by scripts/build_guide.py. Edit the JSON, then run: make guide -->",
        f"# {g['title']}", "", g['intro'], "", "---", "",
        "## 1. Roster & Profession Architecture", "",
        "The 9 Horde characters are divided into 3 groups. Gatherers send raw materials to the crafters who use them, inside their own group first. Change a character's `profs` in `data/guide.json` and this whole section updates.", "",
        "### Master Roster Table", "",
        "| Group | Class | Race | Professions | Role |",
        "| :---: | :--- | :--- | :--- | :--- |",
    ]
    for gid, group in g['groups'].items():
        members = [c for c in chars if c['group'] == gid]
        out.append(
            f"| **{group['name']}** | {'<br>'.join(c['class'] for c in members)} | "
            f"{'<br>'.join(c['race'] for c in members)} | {'<br>'.join(' / '.join(c['profs']) for c in members)} | "
            f"{'<br>'.join(role_title(c['profs'], profs) for c in members)} |"
        )

    out += ["", "### Profession Abbreviation Key"]
    out += [f"- `{code}`: {p['name']}" for code, p in profs.items()]

    out += ["", "### Supply Chains"]
    for gid, group in g['groups'].items():
        out.append(f"- **{group['name']}:**")
        for c in [c for c in chars if c['group'] == gid]:
            lines = supply_lines(c, chars, profs)
            if lines:
                out.append(f"  - **{char_label(c)}** (`{' / '.join(c['profs'])}`): {' '.join(lines)}")
    if tailors or enchanters:
        out.append(f"- **Everyone:** send cloth to {', '.join(tailors) or 'nobody yet'} and green items to {', '.join(enchanters) or 'nobody yet'}.")

    out += ["", "### Profession Pairs"]
    for s in g.get('synergies', []):
        who = [char_label(c) for c in chars if all(p in c['profs'] for p in s['profs'])]
        out.append(f"- **{' + '.join(s['profs'])}:** {s['tip']} _Planned on: {', '.join(who) or 'nobody'}._")

    out += ["", "### Profession Skill Steps"]
    for code, p in profs.items():
        out.append(f"- **{p['name']}** (`{code}`): " + " ".join(f"_{m['rank']}:_ {m['desc']}" for m in p['milestones']))

    out += ["", "---", "", "## 2. Zone Leveling Routes (1–60)", "",
            "| Character | Zones & Level Brackets |", "| :--- | :--- |"]
    for c in chars:
        labels = [zone_label(z, zones) for z in c['zones']]
        rows = [labels[0]] + [', '.join(labels[i:i + 2]) for i in range(1, len(labels), 2)]
        out.append(f"| **{char_label(c)}** | {'<br>'.join(rows)} |")

    dungeons = g.get('dungeons')
    if dungeons:
        faction = {'horde': 'Horde', 'alliance': 'Alliance side', 'both': 'Both factions'}
        out += ["", "### New WoW Forever Dungeons", "", f"_{dungeons['note']}_", "",
                "| Dungeon | Levels | Where | Who | Note |", "| :--- | :--- | :--- | :--- | :--- |"]
        out += [f"| {d['name']} | {dash(d['levels'])} | {d['where']} | {faction[d['faction']]} | {d['note']} |" for d in dungeons['list']]
    if g.get('levelingTips'):
        out += ["", "### Leveling Tips", ""]
        out += [f"- {tip}" for tip in g['levelingTips']]
    weapons = g.get('weaponSkills')
    if weapons:
        out += ["", "### Weapon Skills (Horde)", "", f"_{weapons['note']}_", "",
                "| Weapon master | Teaches |", "| :--- | :--- |"]
        out += [f"| {city}: {t['npc']}<br>{t['where']} | {', '.join(t['skills'])} |" for city, t in weapons['trainers'].items()]
        out += ["", "| Class | Can use |", "| :--- | :--- |"]
        out += [f"| {cls} | {', '.join(skills)} |" for cls, skills in weapons['classes'].items()]

    out += ["", "---", "", "## 3. Zone Cards", "",
            "Short notes per zone. They say where to go, not every quest. Use Questie in game for exact quest spots.", ""]
    for c in chars:
        if not c.get('zoneNotes'):
            continue
        out += [f"### {char_label(c)} (`{' / '.join(c['profs'])}`)", ""]
        for idx, z in enumerate(c['zones']):
            zone, note = zones[z], c['zoneNotes'].get(z, {})
            if not zone.get('hubs'):
                continue
            out.append(f"#### {zone_label(z, zones)} · _{checked_text(zone)}_")
            out.append(f"- **Hubs:** {', '.join(zone['hubs'])}")
            out += [f"- **Do:** {line}" for line in zone.get('do', [])]
            if note.get('class'):
                out.append(f"- **{c['class']}:** {note['class']}")
            for p in c['profs']:
                tip = zone.get('gather', {}).get(p)
                if tip:
                    out.append(f"- **{profs[p]['name']}:** {tip}")
            nxt = next_step(c, idx, zones)
            if nxt:
                out.append(f"- **Next:** {nxt}")
            out.append("")

    new_zones = [(n, z) for n, z in zones.items() if z.get('new')]
    if new_zones:
        out += ["### New WoW Forever zones", ""]
        for n, z in new_zones:
            levels = 'levels not announced' if z['levels'] == '?' else dash(z['levels'])
            out.append(f"- **{n}** ({levels}): " + " ".join(z.get('do', [])))
        out.append("")

    out += ["---", "", "## 4. Quests to Explicitly Skip Per Zone", "",
            "Avoid these quests while leveling solo or duo. They have been benchmarked as high-death risks, escort bottlenecks, abysmal drop-rates, or poor XP-per-hour time traps."]
    current_bracket = None
    for name, zone in zones.items():
        if not zone.get('skips'):
            continue
        if zone['bracket'] != current_bracket:
            current_bracket = zone['bracket']
            out += ["", f"### {current_bracket}"]
        out.append(f"- **{name}:**")
        out += [f"  - *{s['quest']}*" + (f" [{s['level']}]" if s.get('level') else '') + f" – {s['reason']}"
                + (f" ([ClassicDB](https://classicdb.ch/?quest={s['id']}))" if s.get('id') else '') for s in zone['skips']]

    money = g.get('money')
    if money:
        goal = money['mountGoal']
        out += ["", "---", "", "## 5. Money Plan", "",
                f"First goal: the level {goal['level']} mount, about **{goal['gold']} gold**. {goal['note']}", "",
                f"Market signals on the dashboard: _Sell_ when the price is {money['signals']['sellAbove']}× your 7-day median or more, "
                f"_Buy_ when it is {money['signals']['buyBelow']}× or less. {money['signals']['note']} "
                "Collect prices with Auctionator: run its full scan at the auction house, then `/reload` and Sync."]
        for phase in money['phases']:
            out += ["", f"### {phase['name']} ({phase['when']})", "", phase['goal'], "", "**Do:**"]
            out += [f"- {line}" for line in phase['do']]
            out += ["", "**Avoid:**"]
            out += [f"- {line}" for line in phase['avoid']]

    camping = g.get('camping')
    if camping:
        out += ["", "---", "", "## 6. Camping", "", f"_{camping['note']}_", ""]
        out += [f"- {rule}" for rule in camping['rules']]
        out += ["", "| Campfire kit (Cooking) | Skill | Camp objects |", "| :--- | ---: | ---: |"]
        out += [f"| {k['name']} | {k['skill']} | {k['slots']} |" for k in camping['campfires']]
        out += ["", "| Profession | Object (skill) | Materials | Buff | Does not stack with | Higher tiers |", "| :--- | :--- | :--- | :--- | :--- | :--- |"]
        for o in camping['objects']:
            higher = '<br>'.join(f"{t['skill']}: {t['name']} ({t['mats']})" for t in o.get('tiers', [])) or '—'
            out.append(f"| {profs[o['prof']]['name']} | {o['name']} ({o['skill']}) | {o.get('mats', '—')} | {o['buff']} | "
                       f"{o.get('noStack', '—')} | {higher} |")

    detailed = {code: p for code, p in profs.items() if any(m.get('levelWith') for m in p['milestones'])}
    if detailed:
        out += ["", "---", "", "## 7. Profession Guides", "",
                "How to level each profession, what to learn and what to skip. Skill numbers are approximate: check them in game."]
        for code, p in detailed.items():
            out += ["", f"### {p['name']} (`{code}`) · _{checked_text(p)}_"]
            out += [f"- {tip}" for tip in p.get('tips', [])]
            if p.get('newRecipes'):
                out += ["", "| New in Forever | Materials | Effect |", "| :--- | :--- | :--- |"]
                out += [f"| {r['name']} | {r['mats']} | {r['effect']} |" for r in p['newRecipes']]
            for m in p['milestones']:
                out += ["", f"#### {m['rank']}"]
                if m.get('levelWith'):
                    out.append("- **Level with:**")
                    out += [f"  - {level_line(e)}" for e in m['levelWith']]
                for key, label in (('learn', 'Worth learning'), ('skip', 'Skip')):
                    if m.get(key):
                        out.append(f"- **{label}:**")
                        out += [f"  - {line}" for line in m[key]]
                if m.get('greens'):
                    out.append(f"- **Green items (disenchant, or mail to your enchanter):** {', '.join(m['greens'])}")
                if m.get('mats'):
                    out.append(f"- **Materials:** {m['mats']}")

    return "\n".join(out) + "\n"


def validate(g):
    errors = []
    missing = {z for c in g['characters'] for z in c['zones']} - set(g['zones'])
    if missing:
        errors.append(f"zones used by characters but missing from 'zones': {sorted(missing)}")
    races = g.get('races', {})
    for c in g['characters']:
        race = races.get(c['race'])
        if races and (not race or c['class'] not in race['classes']):
            errors.append(f"{c['id']}: a {c['race']} cannot be a {c['class']}")
        elif races and c['zones'][0] != race['start']:
            errors.append(f"{c['id']}: route must start in {race['start']} for a {c['race']}, starts in {c['zones'][0]}")
        bad = [p for p in c['profs'] if g['professions'].get(p, {}).get('type') not in ('gather', 'craft')]
        if bad or len(c['profs']) != 2 or len(set(c['profs'])) != 2:
            errors.append(f"{c['id']} needs 2 different primary professions, has {c['profs']}")
    if errors:
        raise SystemExit("[!] " + "\n[!] ".join(errors))


def build():
    guide = load_guide()  # data/guide.json + personal/team.json (scripts/team.py)
    validate(guide)

    with open(GUIDE_MD, 'w', encoding='utf-8') as f:
        f.write(build_markdown(guide))
    with open(GUIDE_JS, 'w', encoding='utf-8') as f:
        f.write("// Generated from data/guide.json by scripts/build_guide.py. Do not edit by hand.\n")
        f.write("window.GUIDE = ")
        json.dump(guide, f, indent=2, ensure_ascii=False)
        f.write(";\n")

    tracked = tracked_items(guide)
    with open(TRACKED_LUA, 'w', encoding='utf-8') as f:
        f.write("-- Generated from data/guide.json by scripts/build_guide.py. Do not edit by hand.\n")
        f.write("WoWForeverLevelerTracked = {\n")
        f.writelines(f"    [{json.dumps(name, ensure_ascii=False)}] = true,\n" for name in tracked)
        f.write("}\n")

    npcs = guide.get('npcs', {}).get('list', [])
    with open(NPC_LUA, 'w', encoding='utf-8') as f:
        f.write("-- Generated from data/guide.json by scripts/build_guide.py. Do not edit by hand.\n")
        f.write("-- Trainers to visit per city; the addon reminds you when you enter the city.\n")
        f.write("WoWForeverLevelerNPCPlan = {\n")
        for city in sorted({n['city'] for n in npcs}):
            f.write(f"    [{json.dumps(city)}] = {{\n")
            for n in (n for n in npcs if n['city'] == city):
                f.write(f"        {{ name = {json.dumps(n['name'], ensure_ascii=False)}, profession = {json.dumps(n['profession'])}, where = {json.dumps(n['where'], ensure_ascii=False)} }},\n")
            f.write("    },\n")
        f.write("}\n")

    print(f"[+] {GUIDE_MD}")
    print(f"[+] {GUIDE_JS}")
    print(f"[+] {TRACKED_LUA} ({len(tracked)} items)")
    print(f"[+] {NPC_LUA} ({len(npcs)} trainers)")
    plan = addon_plan(guide)
    with open(PLAN_LUA, 'w', encoding='utf-8') as f:
        f.write("-- Generated from data/guide.json by scripts/build_guide.py. Do not edit by hand.\n")
        f.write("-- The in-game panel (UI.lua) picks the lines that fit the character's live skills, level and zone.\n")
        f.write("WoWForeverLevelerPlan = " + to_lua(plan) + "\n")
    print(f"[+] {PLAN_LUA}")
    # The same data for the browser (mockups.html draws the addon window from it).
    with open(os.path.join(ROOT, 'data', 'addon_plan.js'), 'w', encoding='utf-8') as f:
        f.write("// Generated by scripts/build_guide.py: the addon's Plan.lua data. Do not edit by hand.\n")
        f.write("window.ADDON_PLAN = " + json.dumps(plan, separators=(',', ':'), ensure_ascii=False) + ";\n")


LUA_WORDS = {'and', 'do', 'end', 'for', 'if', 'in', 'nil', 'not', 'or'}


def to_lua(value, indent=0):
    """Python data -> Lua table source (strings, numbers, lists, dicts)."""
    pad = '    ' * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return '{}'
        # Flat records with short keys (route steps) go on one line: the file stays small.
        if all(isinstance(v, (str, int, float)) and re.fullmatch(r'[a-z]{1,3}', str(k)) and str(k) not in LUA_WORDS
               for k, v in value.items()):
            return '{ ' + ', '.join(f"{k} = {to_lua(v)}" for k, v in value.items()) + ' }'
        items = [f"{pad}[{json.dumps(str(k), ensure_ascii=False)}] = {to_lua(v, indent + 1)}," for k, v in value.items()]
        return '{\n' + '\n'.join(items) + '\n' + '    ' * indent + '}'
    if isinstance(value, list):
        if not value:
            return '{}'
        return '{\n' + '\n'.join(f"{pad}{to_lua(v, indent + 1)}," for v in value) + '\n' + '    ' * indent + '}'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if value is None:
        return 'nil'
    return json.dumps(str(value), ensure_ascii=False)


GATHER_TIERS = [{'name': 'Journeyman', 'skill': 50, 'cap': 150, 'level': 10, 'where': ''},
                {'name': 'Expert', 'skill': 125, 'cap': 225, 'level': 20, 'where': ''},
                {'name': 'Artisan', 'skill': 200, 'cap': 300, 'level': 35, 'where': ''}]


def with_skill(text, nodes):
    """'Mageroyal, Briarthorn.' -> 'Mageroyal (50), Briarthorn (70).' for herbs and ore."""
    for name in sorted(nodes, key=len, reverse=True):
        skill = nodes[name] if not isinstance(nodes[name], dict) else nodes[name].get('skill')
        text = re.sub(rf'\b({re.escape(name)})\b(?! \()', rf'\1 ({skill})', text, flags=re.I)
    return text


def addon_plan(g):
    """What the in-game panel needs: per class the professions and camp pick, per profession the training
    and skill steps, per zone what to gather and fish, and search lines."""
    profs = g['professions']
    name = {code: p['name'] for code, p in profs.items()}
    picks = g.get('camping', {}).get('picks', {})
    classes = {c['class'].upper(): {'profs': [name[p] for p in c['profs']], 'zones': c['zones'],
                                   'camp': name.get(picks.get(c['id']), '')} for c in g['characters']}
    steps = {}
    for code in ('cook', 'aid'):
        p = profs[code]
        steps[p['name']] = [{'from': int(e['range'].split('-')[0]), 'to': int(e['range'].split('-')[1]),
                             'recipes': [{'name': r, 'mats': ', '.join(f"{q} {m}" if q > 1 else m for m, q in p['recipes'].get(r, {}).items())}
                                         for r in e['recipes']]}
                            for m in p['milestones'] for e in m.get('levelWith', [])]
    fish_steps = []
    for m in profs['fish']['milestones']:
        lo, hi = re.search(r'(\d+)-(\d+)', m['rank']).groups()
        fish_steps.append({'from': int(lo), 'to': int(hi), 'text': m['desc']})
    training = {name[c]: profs[c].get('training') or GATHER_TIERS for c in profs if profs[c].get('type') != 'secondary' or profs[c].get('training')}
    zones = {}
    for zname, z in g['zones'].items():
        gather = {}
        for code, text in (z.get('gather') or {}).items():
            gather[name[code]] = with_skill(text, profs[code].get('nodes', {})) if code in ('herb', 'mine') else text
        # Per gathering profession the nodes of this zone with the skill each needs (lowest skill of a range).
        nodes = {}
        for code, text in (z.get('gather') or {}).items():
            found = []
            for node, need in profs[code].get('nodes', {}).items():
                skill = need.get('skill') if isinstance(need, dict) else need
                if re.search(rf'\b{re.escape(node)}\b', text, re.I):
                    found.append({'name': node, 'skill': int(str(skill).split('-')[0])})
            if found:
                nodes[name[code]] = sorted(found, key=lambda n: n['skill'])
        entry = {'levels': str(z.get('levels', '')), 'gather': gather, 'nodes': nodes}
        if z.get('fishing'):
            entry['fishing'] = z['fishing']
        zones[zname] = entry
    camp = {name[o['prof']]: {'name': o['name'], 'buff': o['buff'], 'skill': o['skill'], 'mats': o.get('mats', ''),
                              'carry': re.sub(r'\d+', lambda m: str(int(m.group()) * 5), o.get('mats', ''))}
            for o in g.get('camping', {}).get('objects', [])}
    start = {z: {name[c]: who for c, who in t.items() if c in name}
             for z, t in g.get('secondaryPlan', {}).get('startTrainers', {}).items()}
    keep = [{'item': n, 'from': k.get('from', 1), 'to': k['until'], 'count': k['count']} for n, k in profs['aid'].get('keepCloth', {}).items()]
    search = []
    for code, p in profs.items():
        for r, mats in p.get('recipes', {}).items():
            search.append(f"{r} ({p['name']}): {', '.join(f'{q} {m}' for m, q in mats.items())}")
        for r in p.get('newRecipes', []):
            search.append(f"{r['name']} ({p['name']}, new): {r['mats']} -> {r['effect']}")
    for zname, z in zones.items():
        for prof, text in z['gather'].items():
            search.append(f"{zname} ({z['levels']}) {prof}: {text}")
        if z.get('fishing'):
            f = z['fishing']
            search.append(f"{zname} Fishing {f['from']}-{f['to']}: {f['where']}")
    for prof, o in camp.items():
        search.append(f"Camp: {o['name']} ({prof} {o['skill']}): {o['buff']} - {o['mats']}")
    # Quest hubs per zone (data/zone_quests.js from scripts/zone_quests.py): name, map position, levels, count.
    zq_path = os.path.join(ROOT, 'data', 'zone_quests.js')
    if os.path.exists(zq_path):
        with open(zq_path, encoding='utf-8') as f:
            zq = json.loads(f.read().split('window.ZONE_QUESTS = ', 1)[1].rstrip().rstrip(';'))['zones']
        for zname, quests in zq.items():
            z = g['zones'].get(zname, {})
            top = int(str(z.get('levels', '0')).split('-')[-1] or 0)
            hubs = []
            for hub, (x, y) in z.get('hubCoords', {}).items():
                qs = [q for q in quests if q.get('hub') == hub and q['level'] <= top + 5]
                if qs:
                    hubs.append({'name': hub, 'x': x, 'y': y, 'from': min(q['level'] for q in qs),
                                 'to': max(q['level'] for q in qs), 'count': len(qs)})
            if hubs and zname in zones:
                zones[zname]['hubs'] = sorted(hubs, key=lambda h: h['from'])
            # Every Horde quest of the zone in level order, for the Leveling window (giver position when known).
            if zname in zones:
                zones[zname]['quests'] = [
                    {k: v for k, v in {'id': q['id'], 'l': q['level'], 'r': q['req'], 'n': q['name'], 'g': q.get('giver') or '',
                                       'hub': q.get('hub') or '', 'x': (q.get('at') or [None, None])[0],
                                       'y': (q.get('at') or [None, None])[1], 'new': q['status'] == 'new'}.items() if v is not None}
                    for q in sorted(quests, key=lambda q: (q['level'], q['req'], q['name']))]
    # Quest routes per zone (data/routes.js from scripts/build_routes.py): recorded or built step lists for the
    # Leveling tab's "Do next" list. Steps: k = a take / d do / t hand in / w level up first.
    rpath = os.path.join(ROOT, 'data', 'routes.js')
    class_mask, chain_start, entrances, chain_paths = {}, {}, {}, {}
    if os.path.exists(rpath):
        with open(rpath, encoding='utf-8') as f:
            rts = json.loads(f.read().split('window.ROUTES = ', 1)[1].rstrip().rstrip(';'))
        givers = rts.pop('_givers', {})
        class_mask.update(rts.pop('_classes', {}))
        chain_start.update(rts.pop('_chains', {}))
        entrances.update(rts.pop('_entrances', {}))
        chain_paths.update(rts.pop('_chainPaths', {}))
        # Giver spots from QuestieDB where zone_quests.js has none (Undercity givers), with their own map.
        for z in zones.values():
            for q in z.get('quests', []):
                gv = givers.get(str(q['id']))
                if gv:
                    q['m'] = gv[0]
                    if q.get('x') is None or not q.get('g'):
                        q['x'], q['y'] = gv[1], gv[2]
                        q['g'] = q.get('g') or gv[3]
        for zname, r in rts.items():
            if zname in zones:
                zones[zname]['route'] = {'kind': r['kind'], 'by': r.get('by', ''), 'steps': r['steps'],
                                         'skipped': [{'id': int(k), 'n': v['n'], 'why': v['why']} for k, v in r.get('skipped', {}).items()]}
    # Profession trainers the addon has seen (data/npcs.js, every client) with their map position, so the
    # panel can point to one at once; guide.json npcFixes names the profession where the game did not.
    trainers = []
    npc_path = os.path.join(ROOT, 'data', 'npcs.js')
    if os.path.exists(npc_path):
        with open(npc_path, encoding='utf-8') as f:
            text = f.read()
        npcs = json.loads(text.split('window.NPCS = ', 1)[1].split(';\n', 1)[0])
        fixes = g.get('npcFixes', {})
        seen = set()
        for client in npcs.values():
            for npc, n in client.items():
                prof = n.get('profession') or fixes.get(npc, {}).get('profession')
                if n.get('kind') == 'trainer' and prof and n.get('mapID') and n.get('x') is not None and npc not in seen:
                    seen.add(npc)
                    trainers.append({'name': npc, 'profession': prof, 'mapID': n['mapID'], 'x': n['x'], 'y': n['y']})
        names = {t['name'] for t in trainers}
    else:
        names = set()
    # Then every Horde trainer from ClassicDB (guide.json trainerDB, scripts/trainers_db.py) not seen in game yet.
    for t in g.get('trainerDB', {}).get('list', []):
        if t['name'] not in names:
            names.add(t['name'])
            trainers.append(dict(t))
    # Leveling window: dungeon quests per giver zone (with map positions) and when to run each dungeon,
    # from the Forever Loot / DFL addon data (data/dungeons.js).
    zone_map = {'Tirisfal Glades': 1420, 'Durotar': 1411, 'Mulgore': 1412, 'The Barrens': 1413, 'Orgrimmar': 1454,
                'Thunder Bluff': 1456, 'Undercity': 1458, 'Silverpine Forest': 1421, 'Hillsbrad Foothills': 1424,
                'Ashenvale': 1440, 'Stonetalon Mountains': 1442, 'Desolace': 1443, 'Thousand Needles': 1441,
                'Arathi Highlands': 1417, 'Stranglethorn Vale': 1434, 'Tanaris': 1446, 'Feralas': 1444,
                'The Hinterlands': 1425, 'Dustwallow Marsh': 1445, 'Swamp of Sorrows': 1435, 'Badlands': 1418,
                'Alterac Mountains': 1416, 'Western Plaguelands': 1422, 'Eastern Plaguelands': 1423, 'Felwood': 1448,
                "Un'Goro Crater": 1449, 'Winterspring': 1452, 'Silithus': 1451, 'Azshara': 1447, 'Wetlands': 1437,
                'Searing Gorge': 1427, 'Burning Steppes': 1428, 'Blasted Lands': 1419}
    pickups, runs = {}, []
    dpath = os.path.join(ROOT, 'data', 'dungeons.js')
    if os.path.exists(dpath):
        with open(dpath, encoding='utf-8') as f:
            books = json.loads(f.read().split('window.DUNGEONS = ', 1)[1].rstrip().rstrip(';'))
        book = books.get('classic_beta') or next(iter(books.values()), {})
        dg = g.get('dungeons', {})
        skip = set(dg.get('hordeSkip', []))
        for d in book.get('list', []):
            if d.get('kind') != 'dungeon' or d['name'] in skip:
                continue
            lo, hi = (int(x) for x in str(d['levels']).split('-')) if '-' in str(d['levels']) else (0, 0)
            if lo:
                runs.append({'name': d['name'], 'from': lo, 'to': hi, 'zone': dg.get('zoneOf', {}).get(d['name'], ''),
                             'runFrom': lo + round(0.3 * (hi - lo)), 'runTo': lo + round(0.6 * (hi - lo))})
            seen = set()
            for q in d.get('quests', []):
                st = q.get('start') or {}
                if st.get('zone') in zone_map and st.get('x') is not None and q['name'] not in seen:
                    seen.add(q['name'])
                    pickups.setdefault(st['zone'], []).append({
                        'dungeon': d['name'], 'quest': q['name'], 'id': q['id'], 'npc': st.get('name', ''),
                        'mapID': zone_map[st['zone']], 'x': st['x'], 'y': st['y'], 'from': q.get('minLevel') or q.get('level', 1)})
    # Dungeon entrances (QuestieDB) on each run, for an arrow to the door.
    for r in runs:
        e = entrances.get(r['name'])
        if e:
            r['entrance'] = {'m': e[0], 'x': e[1], 'y': e[2]}
    # Class quests among the dungeon quests (QuestieDB masks via routes.js): the window hides other classes'.
    for lst in pickups.values():
        for pk in lst:
            if class_mask.get(str(pk['id'])):
                pk['c'] = class_mask[str(pk['id'])]
            cp = chain_paths.get(str(pk['id']))
            if cp:
                pk['chain'] = [{'id': c[0], 'n': c[1], 'npc': c[2], 'm': c[3], 'x': c[4], 'y': c[5], 'r': c[6]} for c in cp]
            st = chain_start.get(str(pk['id']))
            if st:
                pk['start'] = {'id': st[0], 'n': st[1], 'npc': st[2], 'm': st[3], 'x': st[4], 'y': st[5], 'r': st[6]}
    for c in g['characters']:
        k = c['class'].upper()
        classes[k]['notes'] = [{'level': n['level'], 'text': n['text']} for n in c.get('routeNotes', [])]
        classes[k]['travel'] = {z: n['next'] for z, n in (c.get('zoneNotes') or {}).items() if n.get('next')}
        classes[k]['classTips'] = {z: n['class'] for z, n in (c.get('zoneNotes') or {}).items() if n.get('class')}
    # Tooltip decisions: every item a PLANNED recipe uses (directly or as a raw material), with the profession and
    # the skill range of that step; and which characters have which profession (for "mail to").
    reagents = {}
    for code, p in profs.items():
        recipes = p.get('recipes', {})

        def raw(mats, out):
            for m, q in mats.items():
                out.add(m)
                if m in recipes:
                    raw(recipes[m], out)
        for m in p.get('milestones', []):
            for e in m.get('levelWith', []):
                lo, hi = (int(x) for x in e['range'].split('-'))
                for r in e['recipes']:
                    items = set()
                    raw(recipes.get(r, {}), items)
                    for item in items:
                        lst = reagents.setdefault(item, [])
                        hit = next((x for x in lst if x['prof'] == p['name'] and x['recipe'] == r), None)
                        if hit:
                            hit['from'], hit['to'] = min(hit['from'], lo), max(hit['to'], hi)
                        else:
                            lst.append({'prof': p['name'], 'recipe': r, 'from': lo, 'to': hi})
    crafters = {}
    for c in g['characters']:
        for code in c['profs']:
            crafters.setdefault(name[code], []).append(c.get('name') or c['class'])
    # Materials to level every crafting profession of the roster (material_plan), and per raw material the
    # roster total, for the "Save for crafting" topic and the tooltip.
    mat_plan = material_plan(g)
    roster_crafts = sorted({name[c] for ch in g['characters'] for c in ch['profs'] if profs[c].get('type') == 'craft'})
    mat_need = {}
    for prof in roster_crafts:
        for b in mat_plan.get(prof, {}).get('brackets', []):
            for item, n in b['mats'].items():
                e = mat_need.setdefault(item, {'total': 0, 'by': {}})
                e['total'] += n
                e['by'][prof] = e['by'].get(prof, 0) + n
    mat_need = {k: {'total': v['total'], 'by': ', '.join(f"{p} {n}" for p, n in sorted(v['by'].items(), key=lambda kv: -kv[1]))}
                for k, v in mat_need.items()}
    # The crafting steps per profession: our Forever path (data/forever_profs.json, scripts/forever_profs.py) when
    # it has the profession, else the guide's (levelWith): from, to, recipe, crafts (one per point +15%), materials.
    craft_steps = {}
    forever = forever_profs()
    for code, p in profs.items():
        if p.get('type') != 'craft':
            continue
        if p['name'] in forever:
            craft_steps[p['name']] = [{'from': st['from'], 'to': st['to'], 'recipe': st['recipe'], 'count': st['count'],
                                       'mats': ', '.join(f"{n} {mat}" for mat, n in st['mats'].items()),
                                       'raw': st.get('raw', {}), 'sell': st.get('sell'), 'de': st.get('de'),
                                       # Where the recipe is learned: trainer cost, or the pattern with its vendors
                                       # (our scans first, then ClassicDB with map spots) and the quests giving it.
                                       'learn': learn_info(st)}
                                      for st in forever[p['name']]['steps'] if st['recipe']]
            continue
        lst = []
        for m in p.get('milestones', []):
            for e in m.get('levelWith', []):
                lo, hi = (int(x) for x in e['range'].split('-'))
                r = e['recipes'][0]
                n = max(1, math.ceil((hi - lo) * CRAFT_EXTRA)) if hi - lo > 1 else 1
                lst.append({'from': lo, 'to': hi, 'recipe': r, 'count': n,
                            'mats': ', '.join(f"{q * n} {mat}" for mat, q in p.get('recipes', {}).get(r, {}).items())})
        craft_steps[p['name']] = lst
    # Auction prices for Banka's Market tab (data/prices.js from Auctionator, the scope with the newest scan):
    # per team material and craftable item the usual price (median of the scans) and the newest one, copper.
    prices = {}
    ppath = os.path.join(ROOT, 'data', 'prices.js')
    if os.path.exists(ppath):
        with open(ppath, encoding='utf-8') as f:
            text = f.read()
        allp = json.loads(text.split('window.PRICES = ', 1)[1].split(';\n', 1)[0])
        if allp:
            scope = max(allp, key=lambda k: max((e['t'] for h in allp[k].values() for e in h), default=0))
            wanted = set(mat_need) | {st['recipe'] for lst in craft_steps.values() for st in lst}
            for item in wanted:
                hist = allp[scope].get(item)
                if hist:
                    mins = sorted(e['min'] for e in hist)
                    # How many are listed: the last scan and the usual (median) amount, for the market state
                    # (hot / normal / flooded) in the Planner; n = scans seen (the usual means little below 3).
                    qtys = sorted(e['qty'] for e in hist if e.get('qty') is not None)
                    prices[item] = {'usual': mins[len(mins) // 2], 'last': hist[-1]['min'], 't': hist[-1]['t'], 'n': len(hist),
                                    'qty': hist[-1].get('qty'), 'qtyUsual': qtys[len(qtys) // 2] if qtys else None}
    bank = g.get('bank') or {}
    return {'reagents': reagents, 'crafters': crafters, 'craftSteps': craft_steps, 'prices': prices,
            'bank': {'name': bank.get('name', ''), 'alt': bank.get('altNames', [])},
            # Every planned name (first names and spares, the bank too): the Planner's Team leaves test characters out.
            'teamNames': sorted({n for c in g['characters'] + ([bank] if bank else []) for n in [c.get('name')] + (c.get('altNames') or []) if n}),
            'matPlan': {p: mat_plan[p] for p in roster_crafts if p in mat_plan}, 'matNeed': mat_need,
            # Skill needed per herb and ore (Classic numbers, not checked in Forever): the Planner's "next unlock"
            # and the item tooltip. Skinning goes by beast level instead (see Planner.lua SkinLevel).
            # What a profession costs: training per rank (our trainer scans, data/trainers.js, newest per rank) and
            # the tools and bag to buy (guide.json professions.<code>.kit) with a fallback price (shopping.items;
            # in game the addon's own vendor scan wins).
            # Legacy "Spelunker" points: the dungeons of each tier (guide.json legacy.spelunker, not checked).
            'spelunker': [{'name': t, 'dungeons': d} for t, d in ((g.get('legacy') or {}).get('spelunker') or {}).get('tiers', {}).items()],
            'profCosts': prof_costs(),
            'profKit': {profs[c]['name']: {**profs[c]['kit'], 'prices': {i: (g['shopping']['items'].get(i) or {}).get('price')
                        for i in profs[c]['kit'].get('tools', []) + ([profs[c]['kit']['bag']] if profs[c]['kit'].get('bag') else [])}}
                        for c in profs if profs[c].get('kit')},
            'gatherNodes': {profs[c]['name']: {k: v for k, v in profs[c].get('nodes', {}).items() if isinstance(v, int)}
                            for c in ('herb', 'mine')},
            'pickups': pickups, 'runs': sorted(runs, key=lambda r: r['from']),
            'routeChoices': [{'id': c['id'], 'options': [{'name': o['name'], 'zones': o['zones']} for o in c['options']]}
                             for c in g.get('routeChoices', [])],
            'dungeonChains': [{'name': c['name'], 'dungeons': c['dungeons'], 'note': c.get('note', '')}
                              for c in g.get('dungeonChains', [])],
            'trainers': sorted(trainers, key=lambda t: t['name']),
            'classes': classes, 'steps': steps, 'fish': fish_steps, 'training': training, 'zones': zones,
            'camp': camp, 'startTrainers': start, 'aidKeep': keep, 'search': sorted(search)}


# Bars come from ore (Mining smelting); Bronze and Steel mix two. Used only for the material totals.
SMELT = {'Copper Bar': {'Copper Ore': 1}, 'Tin Bar': {'Tin Ore': 1}, 'Silver Bar': {'Silver Ore': 1},
         'Bronze Bar': {'Copper Bar': 0.5, 'Tin Bar': 0.5}, 'Iron Bar': {'Iron Ore': 1}, 'Gold Bar': {'Gold Ore': 1},
         'Steel Bar': {'Iron Bar': 1, 'Coal': 1}, 'Mithril Bar': {'Mithril Ore': 1},
         'Truesilver Bar': {'Truesilver Ore': 1}, 'Thorium Bar': {'Thorium Ore': 1}}
# Bought from a vendor: listed apart, never "save".
VENDOR = re.compile(r'(Thread|Dye|Vial|Flux|Salt|Spice|Mote of Magic|Copper Rod|Silver Rod|Golden Rod|Truesilver Rod|Arcanite Rod)$')
# Skinned, not made: Leatherworking can turn scraps or lower leather into these, but you collect them.
GATHERED = re.compile(r'^(Light|Medium|Heavy|Thick|Rugged) Leather$')
CRAFT_EXTRA = 1.15  # crafts per skill point: a few crafts give no point (yellow), Forever greys some early


_SOURCES = None


def learn_info(st):
    """How to learn a step's recipe: {'trainer': cost} or {'source', 'item', 'vendors': [{n, zone, m, x, y, cost,
    limited}], 'quests': [{n, id, level, from}]}."""
    global _SOURCES
    if _SOURCES is None:
        path = os.path.join(ROOT, 'data', 'recipe_sources.json')
        _SOURCES = json.load(open(path, encoding='utf-8')).get('recipes', {}) if os.path.exists(path) else {}
    recipe = st['recipe']
    if not st.get('source'):
        return {'trainer': trainer_costs().get(recipe)}
    out = {'source': st['source'], 'vendors': [], 'quests': []}
    ours = recipe_vendors().get(recipe)
    cdb = _SOURCES.get(recipe) or {}
    out['item'] = (ours or {}).get('item') or cdb.get('item') or ''
    for v in (ours or {}).get('vendors', []):
        out['vendors'].append({'n': v[0], 'zone': v[1] + (f' ({v[2]})' if v[2] else ''), 'cost': v[3]})
    seen = {v['n'] for v in out['vendors']}
    for v in cdb.get('vendors', []):
        if v['name'] not in seen:
            out['vendors'].append({'n': v['name'], 'm': v.get('mapID'), 'x': v.get('x'), 'y': v.get('y'),
                                   'cost': v.get('cost'), 'limited': v.get('limited')})
    out['quests'] = [{'n': q['name'], 'id': q['id'], 'level': q.get('level'), 'from': q.get('from')} for q in cdb.get('quests', [])]
    return out


_TRAINER_COSTS = None


def trainer_costs():
    """{recipe: copper} from our trainer scans (data/trainers.js, every client)."""
    global _TRAINER_COSTS
    if _TRAINER_COSTS is None:
        _TRAINER_COSTS = {}
        path = os.path.join(ROOT, 'data', 'trainers.js')
        if os.path.exists(path):
            data = json.loads(open(path, encoding='utf-8').read().split('window.TRAINERS = ', 1)[1].split(';\n', 1)[0])
            for client in data.values():
                for recipes in client.values():
                    for name, r in recipes.items():
                        if r.get('cost') is not None:
                            _TRAINER_COSTS[name] = r['cost']
    return _TRAINER_COSTS


def recipe_vendors():
    """{recipe: {'item': pattern name, 'vendors': [[name, zone, subzone, price], ...]}} from our vendor scans."""
    path = os.path.join(ROOT, 'data', 'vendors.js')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as f:
        data = json.loads(f.read().split('window.VENDORS = ', 1)[1].split(';\n', 1)[0])
    out = {}
    for client in data.values():
        for recipe, v in client.items():
            e = out.setdefault(recipe, {'item': v.get('item', ''), 'vendors': []})
            for x in v.get('vendors', []):
                row = [x.get('vendor'), x.get('zone', ''), x.get('subzone', ''), x.get('price') or 0]
                if row[0] and row not in e['vendors']:
                    e['vendors'].append(row)
    return out


def prof_costs():
    """{prof: {"Apprentice": copper, "Journeyman": ...}} from the trainer scans (data/trainers.js, every client)."""
    path = os.path.join(ROOT, 'data', 'trainers.js')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as f:
        data = json.loads(f.read().split('window.TRAINERS = ', 1)[1].split(';\n', 1)[0])
    out, seen = {}, {}
    for client in data.values():
        for prof, recipes in client.items():
            for name, r in recipes.items():
                m = re.match(r'(Apprentice|Journeyman|Expert|Artisan) ', name)
                if m and r.get('cost') is not None and r.get('seen', 0) >= seen.get((prof, m.group(1)), -1):
                    seen[(prof, m.group(1))] = r.get('seen', 0)
                    out.setdefault(prof, {})[m.group(1)] = r['cost']
    return out


def forever_profs():
    """{prof name: {steps, brackets, vendor}} from data/forever_profs.json (scripts/forever_profs.py), or {}."""
    path = os.path.join(ROOT, 'data', 'forever_profs.json')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as f:
        return json.load(f).get('professions', {})


def material_plan(g):
    """Raw materials to level each crafting profession 1-300, split by skill bracket: our Forever path
    (forever_profs) when it has the profession, else the guide's levelWith steps (one craft per point +15%).
    {prof name: {'brackets': [{'from', 'to', 'mats': {item: n}}], 'vendor': {item: n}, 'src'}}."""
    profs = g['professions']
    recipes = {}
    for p in profs.values():
        recipes.update(p.get('recipes', {}))

    def raw(item, qty, out, vendor):
        if VENDOR.search(item):
            vendor[item] = vendor.get(item, 0) + qty
        elif item in recipes and not GATHERED.search(item):
            # A recipe can make more than one (Bolt of Linen Cloth makes 1; bombs 1): take 1.
            for m, q in recipes[item].items():
                raw(m, qty * q, out, vendor)
        elif item in SMELT:
            for m, q in SMELT[item].items():
                raw(m, qty * q, out, vendor)
        else:
            out[item] = out.get(item, 0) + qty
    plan = {}
    forever = forever_profs()
    for code, p in profs.items():
        if p.get('type') != 'craft':
            continue
        fp = forever.get(p['name'])
        if fp:
            # Already raw materials (bars as ore, bolts as cloth) and vendor goods apart.
            plan[p['name']] = {'brackets': fp['brackets'], 'top': max((st['to'] for st in fp['steps']), default=300),
                               'vendor': fp['vendor'], 'src': 'Forever'}
            continue
        brackets = [{'from': 1, 'to': 150, 'mats': {}}, {'from': 150, 'to': 225, 'mats': {}}, {'from': 225, 'to': 300, 'mats': {}}]
        vendor = {}
        top = 0
        for m in p.get('milestones', []):
            for e in m.get('levelWith', []):
                lo, hi = (int(x) for x in e['range'].split('-'))
                top = max(top, hi)
                crafts = max(1, math.ceil((hi - lo) * CRAFT_EXTRA)) if hi - lo > 1 else 1
                r = e['recipes'][0]
                b = next(b for b in brackets if lo < b['to'] or b is brackets[-1])
                for mat, q in recipes.get(r, {}).items():
                    raw(mat, crafts * q, b['mats'], vendor)
        for b in brackets:
            b['mats'] = {k: math.ceil(v) for k, v in sorted(b['mats'].items(), key=lambda kv: -kv[1])}
        plan[p['name']] = {'brackets': [b for b in brackets if b['mats']], 'top': top,
                           'vendor': {k: math.ceil(v) for k, v in sorted(vendor.items())}}
    return plan


def tracked_items(g):
    """Every item the Money tab can price: watch lists, guide recipes and their reagents."""
    names = {n for items in g.get('money', {}).get('watch', {}).values() for n in items}
    for m in g.get('money', {}).get('methods', []):
        calc = m.get('calc', {})
        names.update(calc.get('materials', {}))
        names.update(y['item'] for y in calc.get('yields', []))
        if calc.get('craft'):
            names.add(calc['craft'])
        if calc.get('wand'):
            names.add(calc['wand']['name'])
            names.update(calc['wand']['materials'])
    for p in g['professions'].values():
        for recipe, reagents in p.get('recipes', {}).items():
            names.add(recipe)
            names.update(reagents)
    return sorted(names)


if __name__ == "__main__":
    build()

"""
The personal team on top of data/guide.json.

data/guide.json holds the general guide (zone routes, class tips, professions, dungeons). Who plays what is personal
and lives in personal/team.json (git-ignored): per character id its name, last name, race, group, play order,
start flag and professions, and the bank character's name, race and class. Without personal/team.json the example
team in personal.example/team.json is used, so a fresh copy of the project works at once.

Every script that needs the characters reads the guide with load_guide(); the dashboard's profession picker
saves to personal/team.json with save_character().
"""

import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, 'data', 'guide.json')
PERSONAL = os.path.join(ROOT, 'personal')
TEAM = os.path.join(PERSONAL, 'team.json')
EXAMPLE = os.path.join(ROOT, 'personal.example', 'team.json')
CHAR_FIELDS = ('name', 'lastName', 'race', 'group', 'start', 'order', 'profs')
BANK_FIELDS = ('name', 'lastName', 'race', 'class')


def team_path():
    return TEAM if os.path.exists(TEAM) else EXAMPLE


def load_team():
    with open(team_path(), encoding='utf-8') as f:
        return json.load(f)


def load_guide():
    """data/guide.json with the team's personal fields filled in."""
    with open(GUIDE, encoding='utf-8') as f:
        guide = json.load(f)
    team = load_team()
    for c in guide.get('characters', []):
        c.update({k: v for k, v in (team.get('characters') or {}).get(c['id'], {}).items() if k in CHAR_FIELDS})
        c.setdefault('name', c['class'])
        # The route's first zone is the race's start zone.
        start = (guide.get('races') or {}).get(c.get('race'), {}).get('start')
        if start and c.get('zones'):
            c['zones'][0] = start
    if guide.get('bank') is not None:
        guide['bank'].update({k: v for k, v in (team.get('bank') or {}).items() if k in BANK_FIELDS})
    return guide


def save_character(char_id, **fields):
    """Change a character's personal fields in personal/team.json (made from the example the first time)."""
    if not os.path.exists(TEAM):
        os.makedirs(PERSONAL, exist_ok=True)
        shutil.copyfile(EXAMPLE, TEAM)
    with open(TEAM, encoding='utf-8') as f:
        team = json.load(f)
    team.setdefault('characters', {}).setdefault(char_id, {}).update({k: v for k, v in fields.items() if k in CHAR_FIELDS})
    with open(TEAM, 'w', encoding='utf-8') as f:
        f.write(json.dumps(team, indent=2, ensure_ascii=False) + '\n')

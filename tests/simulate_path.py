"""
Plays Kaspin (Tauren Hunter, Skinning + Herbalism) through levels 1-20 in the fake game of addon_fakegame.py and
prints every Planner tab (Next, Dungeons, Professions, Team) at each stage, plus the alerts that popped up on the
way. Auction prices are mock data, so the Market rows show how much text they add. Needs lupa (see
addon_fakegame.py). Run after `make guide`:

    /tmp/wfl-lua/bin/python tests/simulate_path.py > personal/kaspin_1-20.txt
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import tests.addon_fakegame as af  # noqa: E402

lupa = af.lupa

# Mock auction prices (copper): usual = median of the scans, last = the newest scan.
PRICES = {
    'Light Leather': (60, 75, 40, 25), 'Ruined Leather Scraps': (8, 6, 120, 200),
    'Peacebloom': (25, 40, 30, 15), 'Silverleaf': (20, 18, 60, 70), 'Earthroot': (30, 30, 25, 25),
    'Mageroyal': (45, 60, 20, 12), 'Briarthorn': (55, 50, 30, 35), 'Bruiseweed': (70, 95, 10, 6),
    'Linen Cloth': (12, 10, 300, 400), 'Medium Leather': (90, 85, 30, 30),
}

# (title, level, zone, mapID, money in copper, skills {name: (rank, max)}, items in the bags {name: count})
STAGES = [
    ('Level 1, just logged in', 1, 'Mulgore', 1412, 0, {}, {}),
    ('Level 2, 20c in the bags', 2, 'Mulgore', 1412, 20, {}, {'Ruined Leather Scraps': 0}),
    ('Level 3, Skinning learned, 25c, book read', 3, 'Mulgore', 1412, 25,
     {'Skinning': (12, 75), 'Herbalism': (1, 75)}, {'Skinning Knife': 1, 'Ruined Leather Scraps': 9}),
    ('Level 6, Bloodhoof Village, 1s 10c', 6, 'Mulgore', 1412, 110,
     {'Skinning': (38, 75), 'Herbalism': (30, 75)}, {'Skinning Knife': 1, "Apprentice's Skinning Satchel": 1, "Apprentice's Herb Pouch": 1,
                                                    'Light Leather': 8, 'Peacebloom': 12, 'Silverleaf': 9}),
    ('Level 10, The Barrens, Cooking and Fishing learned, 4s', 10, 'The Barrens', 1413, 400,
     {'Skinning': (62, 75), 'Herbalism': (58, 75), 'Cooking': (22, 75), 'Fishing': (18, 75)},
     {'Skinning Knife': 1, "Apprentice's Skinning Satchel": 1, "Apprentice's Herb Pouch": 1, 'Fishing Pole': 1, 'Light Leather': 14,
      'Peacebloom': 6, 'Earthroot': 7, 'Mageroyal': 4}),
    ('Level 13, Skinning 75 and Herbalism 75 (cap), 12s', 13, 'The Barrens', 1413, 1200,
     {'Skinning': (75, 75), 'Herbalism': (75, 75), 'Cooking': (45, 75), 'Fishing': (40, 75)},
     {'Skinning Knife': 1, "Apprentice's Skinning Satchel": 1, "Apprentice's Herb Pouch": 1, 'Fishing Pole': 1, 'Light Leather': 20,
      'Briarthorn': 6, 'Mageroyal': 8}),
    ('Level 16, Journeyman trained, 30s', 16, 'The Barrens', 1413, 3000,
     {'Skinning': (105, 150), 'Herbalism': (98, 150), 'Cooking': (55, 150), 'Fishing': (52, 75)},
     {'Skinning Knife': 1, "Apprentice's Skinning Satchel": 1, "Apprentice's Herb Pouch": 1, 'Fishing Pole': 1, 'Medium Leather': 10,
      'Briarthorn': 12, 'Bruiseweed': 5}),
    ('Level 20, 80s', 20, 'The Barrens', 1413, 8000,
     {'Skinning': (130, 150), 'Herbalism': (125, 150), 'Cooking': (75, 150), 'Fishing': (75, 150)},
     {'Skinning Knife': 1, "Apprentice's Skinning Satchel": 1, "Apprentice's Herb Pouch": 1, 'Fishing Pole': 1, 'Medium Leather': 18,
      'Bruiseweed': 9, 'Wild Steelbloom': 4}),
]

SETUP = r'''
UnitName = function() return "Kaspin", "Lovac" end
UnitClass = function() return "Hunter", "HUNTER", 3 end
UnitRace = function() return "Tauren", "Tauren" end
GetRealmName = function() return "Sim" end
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
C_QuestLog.IsOnQuest = function() return false end
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
local names = { [1412] = "Mulgore", [1413] = "The Barrens", [1456] = "Thunder Bluff", [1454] = "Orgrimmar", [1411] = "Durotar",
                [1420] = "Tirisfal Glades", [1458] = "Undercity", [1421] = "Silverpine Forest", [1414] = "Kalimdor", [1415] = "Eastern Kingdoms" }
local parent = { [1412] = 1414, [1413] = 1414, [1456] = 1414, [1454] = 1414, [1411] = 1414, [1420] = 1415, [1458] = 1415, [1421] = 1415 }
C_Map.GetMapInfo = function(m) if not names[m] then return nil end
  return { mapID = m, name = names[m], mapType = parent[m] and 3 or 2, parentMapID = parent[m] } end
C_Map.GetBestMapForUnit = function() return MAPID end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return POSX / 100, POSY / 100 end } end
GetRealZoneText = function() return ZONE end
GetMoney = function() return MONEY end
BAGS = {}
C_Item = C_Item or {}
C_Item.GetItemCount = function(it) return BAGS[it] or 0 end
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(CHAT, m) end }
UIErrorsFrame = { AddMessage = function(self, m) table.insert(CHAT, "[top] " .. m) end }
WoWForeverLevelerDB = {
  ["Sim-Kaspin"] = { name = "Kaspin", level = 1, class = "HUNTER", lastUpdated = os.time() },
  ["Sim-Vestac"] = { name = "Vestac", level = 1, class = "WARLOCK", lastUpdated = os.time() - 3600 },
  ["Sim-Nemrtvi"] = { name = "Nemrtvi", level = 1, class = "PRIEST", lastUpdated = os.time() - 7200 } }
'''


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().LEVEL = 1
    lua.execute(af.FAKE_GAME)
    lua.execute('ZONE, MAPID, MONEY, POSX, POSY = "Mulgore", 1412, 0, 44.5, 76.7')
    lua.execute(SETUP)
    for f in [os.path.join(af.ADDON, 'Plan.lua'), os.path.join(af.ADDON, 'UI.lua'),
              os.path.join(af.ADDON + '_Planner', 'Alert.lua'), os.path.join(af.ADDON + '_Planner', 'Planner.lua')]:
        with open(f, encoding='utf-8') as fh:
            lua.execute(fh.read())
    g = lua.globals()
    # Mock auction prices into the plan (the Market rows and the Professions tab read them).
    rows = ', '.join(f'["{k}"] = {{ usual = {u}, last = {l}, t = os.time(), n = 5, qty = {q}, qtyUsual = {qu} }}'
                     for k, (u, l, q, qu) in PRICES.items())
    lua.execute(f'WoWForeverLevelerPlan.prices = {{ {rows} }}')
    events = [f for f in g.FRAMES.values() if f.scripts['OnEvent']]

    def fire(ev, arg=None):
        for f in events:
            try:
                f.scripts['OnEvent'](f, ev, arg)
            except Exception as e:  # one frame's error must not hide the others
                print('  [error in', ev, ']', e)

    fire('PLAYER_LOGIN')
    fire('PLAYER_ENTERING_WORLD')
    for title, level, zone, mapid, money, skills, bags in STAGES:
        skill_rows = ', '.join(f'{{ "{n}", {r}, {m} }}' for n, (r, m) in skills.items())
        bag_rows = ', '.join(f'["{n}"] = {c}' for n, c in bags.items())
        # Where you stand: Camp Narache to level 5, Bloodhoof Village at 6, the Crossroads from 10.
        posx, posy = (44.5, 76.7) if level < 6 else (47.0, 58.0) if level < 10 else (52.0, 30.0)
        lua.execute(f'POSX, POSY = {posx}, {posy}; LEVEL = {level}; ZONE = "{zone}"; MAPID = {mapid}; MONEY = {money}; SKILLS = {{ {skill_rows} }}; '
                    f'BAGS = {{ {bag_rows} }}; CHAT = {{}}; WoWForeverLevelerDB["Sim-Kaspin"].level = {level}')
        # The events a real game sends on the way to this stage: the alerts react to them.
        fire('PLAYER_LEVEL_UP', level)
        fire('PLAYER_MONEY')
        fire('SKILL_LINES_CHANGED')
        fire('BAG_UPDATE_DELAYED')
        print('\n' + '=' * 70 + f'\n{title}\n' + '=' * 70)
        alerts = [af.plain(m) for m in g.CHAT.values() if 'WFL:' in m and 'WFL: character level' not in m]
        if alerts:
            print('\n>>> POP-UP ALERTS on the way here:')
            for m in alerts:
                print('  ' + m.replace('WFL: ', ''))
        for key, label in (('next', 'NEXT TAB'), ('dg', 'DUNGEONS TAB'), ('prof2', 'PROFESSIONS TAB'), ('team', 'TEAM TAB')):
            lua.execute(f'TEXTS = {{}}; WoWForeverLevelerUI.tab = "{key}"')
            events[0].scripts['OnEvent'](None, 'SKILL_LINES_CHANGED')
            print(f'\n--- {label}')
            skip = ('Now', 'Route', 'Materials', '+', '-', 'A-', 'A+', 'Next', 'Dungeons', 'Professions', 'Team', 'Market')
            texts = [af.plain(t) for t in g.TEXTS.values()]
            # The window title and the tab buttons come first; the tab's lines follow them.
            print('\n'.join(t for i, t in enumerate(texts) if t and not (t in skip and i < 8)))


if __name__ == '__main__':
    main()

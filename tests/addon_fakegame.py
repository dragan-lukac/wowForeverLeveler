#!/usr/bin/env python3
"""
Runs the in-game window code (addon Plan.lua + UI.lua) against a fake game and prints what the window shows:
the Now, Route and Materials tabs, the minimap menu and a few item tooltip lines.

Lua cannot run in the real game from here, so this is the quick check after every UI.lua change. It needs the
`lupa` package (a Lua runtime for Python), which is not installed system-wide:

    python3 -m venv /tmp/wfl-lua && /tmp/wfl-lua/bin/pip install "lupa==2.4"   (lupa 2.8 broke: no LuaRuntime)
    /tmp/wfl-lua/bin/python tests/addon_fakegame.py            (the Quests window)
    /tmp/wfl-lua/bin/python tests/addon_fakegame.py planner    (the Planner window)
    /tmp/wfl-lua/bin/python tests/addon_fakegame.py planner crafter    (Tailoring 60, Enchanting 120 instead)
    /tmp/wfl-lua/bin/python tests/addon_fakegame.py 8 planner ek       (level 8, route choice Eastern Kingdoms)

Look for "panel error" lines (a Lua error) and check the printed rows. The fake game: a level 10 Undead Paladin
in Tirisfal Glades near Brill with Mining 11, Skinning 61, Cooking 12, First Aid 45, Fishing 5, two kill quests,
a few known trainers and vendors, and Auctionator prices for a few items.
"""

import os
import re
import sys

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed: see the docstring at the top of this file.")

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'addon', 'WoWForeverLeveler')
LEVEL = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 10
PLANNER = 'planner' in sys.argv  # load the Planner window addon instead of the Quests one
CRAFTER = 'crafter' in sys.argv  # crafting professions instead of the gathering ones
EK = "ek" in sys.argv  # the 20-30 route choice "Eastern Kingdoms"

FAKE_GAME = r'''
date = date or (os and os.date) or function() return '' end

TEXTS, ATTR, MACROS = {}, {}, {}
local function fake()
  local f = { scripts = {} }
  return setmetatable(f, { __index = function(t, k)
    if k == "TitleText" or k == "CloseButton" or k == "Inset" then return nil end
    if k == "SetScript" or k == "HookScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "SetText" then return function(self, s) table.insert(TEXTS, s) end end
    if k == "SetAttribute" then return function(self, a, v) ATTR[a] = v end end
    if k == "GetText" then return function() return "" end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetStringHeight" or k == "GetStringWidth" then return function() return 300 end end
    if k == "GetFrameLevel" then return function() return 3 end end
    if k == "GetVerticalScroll" then return function() return 0 end end
    if k == "IsShown" then return function() return true end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return fake() end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
    return function(self) return self end
  end })
end
FRAMES = {}
function CreateFrame() local f = fake(); table.insert(FRAMES, f); return f end
UIParent, Minimap = fake(), fake()
GameTooltip = setmetatable({}, { __index = function(t, k)
  if k == "HookScript" then return function(self, n, fn) rawset(self, "hook", fn) end end
  return function() end end })
STANDARD_TEXT_FONT = "x"; SlashCmdList = {}; UISpecialFrames = {}
function UnitLevel() return LEVEL end
function GetRealZoneText() return "Tirisfal Glades" end
function UnitClass() return "Paladin", "PALADIN", 2 end
function GetXPExhaustion() return 0 end
function UnitXPMax() return 7600 end
time = time or os.time
WoWForeverLevelerDB = { ["Realm-Lovac-1"] = { name = "Lovac", level = 25, maxXp = 34000, restedXp = 9000, resting = true, lastUpdated = os.time() - 86400 },
                        ["Realm-Vestac-2"] = { name = "Vestac", level = 18, maxXp = 19400, restedXp = 0, resting = false, lastUpdated = os.time() - 3600 } }
function UnitName() return "Pala" end
SKILLS = { { "Mining", 11, 75 }, { "Skinning", 61, 75 }, { "Cooking", 12, 75 }, { "First Aid", 45, 75 }, { "Fishing", 5, 75 } }
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i) local s = SKILLS[i]; return s[1], false, nil, s[2], nil, nil, s[3] end
function InCombatLockdown() return false end
C_Timer = { After = function(t, fn) fn() end }
C_Map = { GetBestMapForUnit = function() return 1420 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.61, 0.52 end } end,
  GetMapInfo = function(m) local t = { [1420] = { mapID = 1420, mapType = 3, parentMapID = 1415 }, [1415] = { mapID = 1415, mapType = 2 },
    [1454] = { mapID = 1454, mapType = 3, parentMapID = 1414 }, [1414] = { mapID = 1414, mapType = 2 } }; return t[m] end }
C_QuestLog = { GetNumQuestLogEntries = function() return 2 end,
  GetInfo = function(i) return i == 1 and { isHeader = true } or { questID = 3901 } end,
  GetQuestObjectives = function() return { { text = "2/10 Rattlecage Skeleton slain", type = "monster", finished = false },
                                           { text = "Scavenged Goods: 1/6", type = "item", finished = false } } end,
  IsQuestFlaggedCompleted = function(id) return id == 363 or id == 364 or id == 376 end, IsOnQuest = function(id) return id == 3901 end,
  IsComplete = function(id) return false end }
function GetMacroIndexByName(n) return MACROS[n] and 1 or 0 end
function CreateMacro(n, i, body) MACROS[n] = body end
function EditMacro(i, n, ic, body) MACROS[n] = body end
WoWForeverLevelerNPCs = { ["Abigail Shiel"] = { kind = "vendor", profession = "Cooking", mapID = 1420, x = 61, y = 52.4 } }
WoWForeverLevelerShopPrices = { ["Mild Spices"] = { vendor = "Abigail Shiel", price = 10, per = 5 },
                                ["Shiny Bauble"] = { vendor = "Abigail Shiel", price = 50, per = 1 } }
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemName = function(c, n) return ({ ["Heavy Linen Bandage"] = 60, ["Linen Cloth"] = 10 })[n] end,
  GetAuctionPriceByItemLink = function() return nil end } } }
SELL = { ["Small Spider Leg"] = 2, ["Stringy Wolf Meat"] = 3, ["Wool Cloth"] = 33, ["Silk Cloth"] = 38 }
function GetItemInfo(link) return link, nil, nil, nil, nil, nil, nil, nil, nil, nil, SELL[link] end
function tooltipLine(name)
  local out
  local tip = { GetItem = function() return name, name end, AddLine = function(self, s) out = out and (out .. " / " .. s) or s end, Show = function() end }
  rawget(GameTooltip, "hook")(tip)
  return out
end
'''


def plain(t):
    return re.sub(r'\|c\w{8}|\|r', '', t)


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().LEVEL = LEVEL
    lua.execute(FAKE_GAME)
    if CRAFTER:
        lua.execute('SKILLS = { { "Tailoring", 60, 75 }, { "Enchanting", 120, 150 }, { "Cooking", 12, 75 } }')
    if EK:
        lua.execute('WoWForeverLevelerUI = WoWForeverLevelerUI or {}; WoWForeverLevelerUI.routeChoice = { ["20-30"] = "Eastern Kingdoms" }')
    files = [os.path.join(ADDON, 'Plan.lua'), os.path.join(ADDON, 'UI.lua'),
             os.path.join(ADDON + ('_Planner' if PLANNER else '_Quests'), 'Planner.lua' if PLANNER else 'Quests.lua')]
    if PLANNER:
        files.insert(2, os.path.join(ADDON + '_Planner', 'Alert.lua'))
    for f in files:
        with open(f, encoding='utf-8') as fh:
            lua.execute(fh.read())
    g = lua.globals()
    events = [f for f in g.FRAMES.values() if f.scripts['OnEvent']]
    login = [e for e in events]
    for e in login:
        e.scripts['OnEvent'](None, 'PLAYER_LOGIN')
    def show(title, setup):
        lua.execute('TEXTS = {}; ' + setup)
        events[0].scripts['OnEvent'](None, 'SKILL_LINES_CHANGED')
        print(f'\n=== {title}')
        print('\n'.join(plain(t) for t in g.TEXTS.values() if t not in ('Now', 'Route', 'Materials', '+', '-', 'A-', 'A+')))
    if PLANNER:
        show('Next tab', 'WoWForeverLevelerUI.tab = "next"')
        show('Dungeons tab', 'WoWForeverLevelerUI.tab = "dg"')
        show('Dungeons tab (Ragefire Chasm open)', 'WoWForeverLevelerUI.tab = "dg"; '
             'WoWForeverLevelerUI.open_dg = { ["d:Ragefire Chasm"] = true, ["d:Wailing Caverns"] = true }; '
             'local onQuest = C_QuestLog.IsOnQuest; C_QuestLog.IsOnQuest = function(id) return id == 5761 or onQuest(id) end')
        show('Dungeons tab (chains folded)', 'WoWForeverLevelerUI.tab = "dg"; WoWForeverLevelerUI.open_dg = { ["g:chains"] = false }')
        # A link from Next: the Dungeons tab with "Shadowfang Keep" open (WFL.OpenTab).
        show('Link: WFL.OpenTab("dg", "d:Shadowfang Keep", "Arugal Must Die")', 'WoWForeverLevelerUI.open_dg = {}; WFL.OpenTab("dg", "d:Shadowfang Keep", "Arugal Must Die")')
        show('Professions tab', 'WoWForeverLevelerUI.tab = "prof2"; WoWForeverLevelerUI.have = { ["Alt-Realm"] = { ["Linen Cloth"] = 88 } }')
        if CRAFTER:
            # SkillUp Forever installed: its API steps and reagents replace our craft steps for Tailoring.
            show('Professions tab (SkillUp Forever)', 'C_Item = C_Item or {}; C_Item.GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [2320] = "Coarse Thread" })[id] end; '
                 'NAVIGATED = nil; SkillUpForever = { API = { version = 1, '
                 'Professions = function() return { { name = "Tailoring", skillLineID = 197, rank = 60, maxRank = 75, steps = { '
                 '{ kind = "buy", text = "Buy 10 Coarse Thread", detail = "Krugosh, Razor Hill \\194\\183 50c", nav = true }, '
                 '{ kind = "craft", text = "Craft 10 Heavy Linen Gloves", detail = "60 to 70", nav = false }, '
                 '{ kind = "train", text = "Train Journeyman Tailoring", detail = "Snang, Orgrimmar \\194\\183 5s", nav = true } }, '
                 'recipes = { { name = "Heavy Linen Gloves", count = 10, fromRank = 60, toRank = 70, learned = true }, '
                 '{ name = "Reinforced Linen Cape", count = 5, fromRank = 70, toRank = 75, learned = false, trainAt = 60 } }, '
                 'reagents = { { itemID = 2589, need = 200, have = 40 }, { itemID = 2320, need = 10, have = 0 } } } } end, '
                 'Navigate = function(line, i) NAVIGATED = i; return true end, OpenRecipes = function() return true end } }; '
                 'WoWForeverLevelerUI.tab = "prof2"')
        # A cook without Fishing, boar meat in the bags; SkillUp says "Buy 10 Chunk of Boar Meat".
        show('Professions tab (cook, no Fishing, boar meat in bags)',
             'SKILLS = { { "Cooking", 12, 75 }, { "First Aid", 45, 75 } }; '
             'C_Item = C_Item or {}; C_Item.GetItemNameByID = function(id) return ({ [769] = "Chunk of Boar Meat" })[id] end; '
             'C_Item.GetItemCount = function(it) return (it == "Chunk of Boar Meat" or it == 769) and 6 or (it == "Small Egg" and 3) or 0 end; '
             'SkillUpForever = { API = { version = 1, Professions = function() return { { name = "Cooking", skillLineID = 185, rank = 12, maxRank = 75, steps = { '
             '{ kind = "buy", text = "Buy 10 Chunk of Boar Meat", itemID = 769, count = 10, nav = true } }, recipes = {}, reagents = {} } } end, '
             'Navigate = function() return true end, OpenRecipes = function() return true end } }; '
             'WoWForeverLevelerUI.tab = "prof2"')
        lua.execute('SkillUpForever = nil; C_Item.GetItemCount = nil; '
                    'SKILLS = { { "Mining", 11, 75 }, { "Skinning", 61, 75 }, { "Cooking", 12, 75 }, { "First Aid", 45, 75 }, { "Fishing", 5, 75 } }')
        show('Team tab', 'WoWForeverLevelerUI.tab = "team"')
        # The bank character: Next shows market and mail, the Market tab replaces Dungeons and Professions.
        show('Bank: Next tab', 'UnitName = function() return "Banka" end; WoWForeverLevelerUI.tab = "next"')
        show('Bank: Market tab', 'WoWForeverLevelerUI.tab = "market"; WoWForeverLevelerUI.have = { ["Alt-Realm"] = { ["Linen Cloth"] = 400, ["Copper Ore"] = 60 } }')
        # A dungeon leveler at level 22, between dungeon chains 1 and 2: the Next tab says to quest.
        show('Next tab (dungeon leveler, level 22)', 'UnitName = function() return "Konan" end; WoWForeverLevelerPlan.dungeonLevelers = { Konan = "Protection" }; '
             'local lvl = UnitLevel; UnitLevel = function() return 22 end; WoWForeverLevelerUI.tab = "next"')
        lua.execute('UnitLevel = function() return LEVEL end')
        # Plan alerts: Kaspin at level 1 with no professions. The first check only marks; 20c then says "learn
        # Skinning", 25c with Skinning says "buy a Skinning Satchel", level 6 with 90c says "learn Cooking and Fishing".
        print('\n=== Plan alerts (Kaspin)')
        lua.execute('CHAT = {}; DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(CHAT, m) end }; '
                    'UnitName = function() return "Kaspin" end; SKILLS = {}; MONEY = 0; GetMoney = function() return MONEY end; '
                    'local function fire(ev, a) for _, f in pairs(FRAMES) do local h = f.scripts and f.scripts.OnEvent; if h then pcall(h, f, ev, a) end end end; '
                    'fire("PLAYER_ENTERING_WORLD"); MONEY = 20; fire("PLAYER_MONEY"); fire("PLAYER_MONEY"); '
                    'SKILLS = { { "Skinning", 1, 75 } }; MONEY = 25; fire("PLAYER_MONEY"); '
                    'MONEY = 100; UnitLevel = function() return 6 end; fire("PLAYER_LEVEL_UP", 6); UnitLevel = function() return LEVEL end; '
                    'SKILLS = { { "Mining", 11, 75 }, { "Skinning", 61, 75 }, { "Cooking", 12, 75 }, { "First Aid", 45, 75 }, { "Fishing", 5, 75 } }')
        for m in g.CHAT.values():
            print(plain(m))
        print('\n=== Level-up reminder (level 9 opens the Ragefire Chasm quests)')
        lua.execute('CHAT = {}; DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(CHAT, m) end }; '
                    'UIErrorsFrame = { AddMessage = function(self, m) table.insert(CHAT, "[top] " .. m) end }; '
                    'local lvl = UnitLevel; UnitLevel = function() return 9 end; '
                    'for _, f in pairs(FRAMES) do local h = f.scripts and f.scripts.OnEvent; if h then pcall(h, f, "PLAYER_LEVEL_UP", 9) end end; '
                    'UnitLevel = lvl')
        for m in g.CHAT.values():
            print(plain(m))
        return
    show('Now tab', 'WoWForeverLevelerUI.tab = "now"; WoWForeverLevelerUI.open_now = { cook = true, aid = true, fish = true, gather = true, camp = true }')
    show('Route tab (Dungeon chain 1 and Wailing Caverns open)', 'WoWForeverLevelerUI.tab = "route"; WoWForeverLevelerUI.open_route = { ["chain:Dungeon chain 1"] = true, ["dg:Wailing Caverns"] = true }')
    show('Materials tab (Tailoring open)', 'WoWForeverLevelerUI.tab = "mat"; WoWForeverLevelerUI.have = { ["Alt-Realm"] = { ["Linen Cloth"] = 88, ["Wool Cloth"] = 900 } }; WoWForeverLevelerUI.open_mat = { ["mat:Tailoring"] = true }')
    # Hillsbrad scenario: the 20-30 route choice swaps Stonetalon + Ashenvale for Hillsbrad.
    show('Route tab in Hillsbrad (route choice)', 'GetRealZoneText = function() return "Hillsbrad Foothills" end; WoWForeverLevelerUI.tab = "route"; WoWForeverLevelerUI.open_route = {}')
    print('\n=== Macros')
    for name, body in g.MACROS.items():
        print(f'{name}: {body!r}')
    print('\n=== Vendor search (/wfl buy coarse thread, then a material line click)')
    lua.execute('WFL.FindVendorByName("coarse thread"); WFL.FindVendor("Empty Vial"); WFL.FindVendorByName("no such thing")')
    print('\n=== Item tooltip lines')
    for item in ('Small Spider Leg', 'Stringy Wolf Meat', 'Wool Cloth', 'Silk Cloth', 'Briarthorn', 'Copper Ore', 'Tin Ore'):
        print(f'{item}: {plain(lua.eval(f"tooltipLine({item!r})") or "nothing")}')


if __name__ == '__main__':
    main()

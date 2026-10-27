-- WoW Forever Leveler - Planner (2.0.0): the overview window for the team, built from mockups.html.
-- Quests come from another guide (Polestar); this window says what is next on a bigger scale.
--   Leveling characters: Next | Dungeons | Professions | Team
--   The bank character:   Next | Market | Team
-- Next is always first: for each area the step now and the one after; it moves on as steps get done.
-- Which character is the bank: its name in the plan (guide.json bank name), or the minimap menu
-- switch "This character is the bank" (kept per character in WoWForeverLevelerUI.bankChars).
-- Shared code lives in the core addon (WoWForeverLeveler/UI.lua, table WFL).

local PLAN = WoWForeverLevelerPlan or {}
local C = WFL.colors
local CRAFTS = { Tailoring = true, Enchanting = true, Leatherworking = true, Alchemy = true, Blacksmithing = true, Engineering = true }
local GATHER = { Herbalism = "herbs", Mining = "ore", Skinning = "skins" }
local GREEN_C, GREY_C = { 0.12, 0.48, 0.12 }, { 0.43, 0.35, 0.24 }

-- --- Who is logged in ---------------------------------------------------------------------------------------------
local function MyKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

local function IsBank()
    local s = WFL.Settings()
    local v = s.bankChars and s.bankChars[MyKey()]
    if v ~= nil then return v end
    local name, b = UnitName("player"), PLAN.bank or {}
    if name and name == b.name then return true end
    for _, a in ipairs(b.alt or {}) do if a == name then return true end end
    return false
end
local function NotBank() return not IsBank() end

-- The Planner's menu: Sync and the bank switch. The macro entries belong to the quest window (Polestar and
-- RestedXP target quest monsters themselves; the arrow leads to NPCs); macros already on a bar keep working.
for i = #WFL.menu, 1, -1 do
    if WFL.menu[i].text == "Profession macro" or WFL.menu[i].text == "Quest macro" then table.remove(WFL.menu, i) end
end

table.insert(WFL.menu, { text = "This character is the bank", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    tip = "The bank character gets the Market tab instead of Dungeons and Professions.",
    state = IsBank,
    run = function()
        local s = WFL.Settings()
        s.bankChars = s.bankChars or {}
        s.bankChars[MyKey()] = not IsBank()
        WFL.Relayout()
    end })

-- --- Small helpers ------------------------------------------------------------------------------------------------
-- Where something is: the zone or city only, never coordinates (click the line for the arrow).
local function Pos(m, x, y)
    local zone = (m and m > 0) and WFL.MapName(m) or ""
    return zone ~= "" and zone or "place not known"
end
local function Money(c) return WFL.CopperText(math.floor((c or 0) + 0.5)) end

-- "Now" and "After" lines; the Now line can carry an arrow (point) and a "where" line under it.
-- Links between tabs (user, 2026-10-22: no extra link lines): the rows added since `from` that have no arrow or
-- action of their own open another tab with one card expanded (WFL.OpenTab).
-- match: what to highlight in the opened card (WFL.OpenTab), a text or a function(line) -> text (true: the card
-- itself); a line's own l.match wins. A row without a match does not link.
local function LinkRows(lines, from, key, section, match)
    for i = from + 1, #lines do
        local l = lines[i]
        if not l.point and not l.click and not l.section then
            -- Only a row with something to show in the other tab links (user, 2026-10-22: no links to nothing).
            local m = l.match or (type(match) == "function" and match(l)) or (type(match) == "string" and match) or nil
            if m == true then l.click = function() WFL.OpenTab(key, section) end
            elseif m then l.click = function() WFL.OpenTab(key, section, m) end end
        end
    end
end

local function Pair(lines, now, after, point, where, icon)
    -- What to do now and what comes after, told apart by look, not by words (user, 2026-10-22): now = full colour,
    -- bold, icon in colour, the place in grey under it; after = one quiet grey line with a faded icon.
    table.insert(lines, { icon = icon or "Interface\\Icons\\INV_Misc_Note_01", title = now, inline = false, titleColor = GREEN_C,
                          text = (where and where ~= "") and (C.GREY .. where .. "|r") or nil, point = point })
    if after and after ~= "" then
        table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", desat = true, title = after, inline = true,
                              titleColor = GREY_C })
    end
end

-- Labelled rows, one per line: { label, text, point, where }. The first label is green, the others grey; a
-- "where" (trainer, vendor) goes on its own grey line under its row.
-- --- Icons for profession and step rows (all tabs) ----------------------------------------------------------------
local PROF_ICON = {
    Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
    Engineering = "Trade_Engineering", Herbalism = "Spell_Nature_NatureTouchGrow", Leatherworking = "INV_Misc_ArmorKit_17",
    Mining = "Trade_Mining", Skinning = "INV_Misc_Pelt_Wolf_01", Tailoring = "Trade_Tailoring",
    Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Fishing = "Trade_Fishing",
}
-- A class's round icon ("HUNTER" -> ClassIcon_Hunter).
local function ClassIcon(classFile)
    local c = (classFile or ""):lower():gsub("^%l", string.upper)
    return c ~= "" and ("Interface\\Icons\\ClassIcon_" .. c) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function ProfIcon(prof) return "Interface\\Icons\\" .. (PROF_ICON[prof] or "INV_Misc_QuestionMark") end
local STEP_ICON = {
    Learn = "INV_Misc_Book_11", Train = "INV_Misc_Book_11", Buy = "INV_Misc_Coin_01", Gather = "INV_Misc_Bag_10",
    Next = "INV_Misc_Note_01", Level = "Spell_Holy_BlessingOfStrength", Temporary = "INV_Misc_Note_02",
    Market = "INV_Misc_Coin_02",
}
-- Rows about buying are blue, about selling red (the same colours as the Market tab's headers).
-- Buy and sell show by text colour only (user, 2026-10-22: no coloured boxes inside cards, like the Team tab).
local SELL_C, BUY_C, TEMP_C = { 0.70, 0.16, 0.10 }, { 0.12, 0.33, 0.60 }, { 0.55, 0.35, 0.00 }
-- "Hot": a small flame and a burning red word (user, 2026-10-22: hot was green).
local FLAME = "|TInterface\\Icons\\Spell_Fire_Fire:14:14|t"
local HOT = FLAME .. " |cffe0301ehot|r"
-- "Linen Cloth is hot (66c, usual 19c, 11400 listed): sell it, craft later" -> "Linen Cloth high: sell now".
-- The grey line under a row: its kind, the place, extras; the kind is left out when the bold line already starts
-- with it ("Learn Mining" over "Learn · ...").
local function Detail(r, ...)
    local parts = {}
    if not (r.text or ""):find("^" .. (r.label or "")) then table.insert(parts, r.label) end
    for _, x in ipairs({ ... }) do if x and x ~= "" then table.insert(parts, x) end end
    return table.concat(parts, " \194\183 ")
end
local function MarketShort(text)
    local item, state = (text or ""):match("^(.-) is (%a+)")
    if state == "hot" then return FLAME .. " " .. item .. " price high: sell now" end
    if state == "cheap" then return item .. " cheap: buy now" end
    return text
end
local function MarketNote(text)
    if (text or ""):find("is hot") or (text or ""):find("[Ss]ell") then return "hot" end
    if (text or ""):find("is cheap") then return "cold" end
end
local function RankName(max)
    return (max or 0) <= 0 and "not learned" or max <= 75 and "Apprentice" or max <= 150 and "Journeyman"
        or max <= 225 and "Expert" or "Artisan"
end
local SKILL_GREEN = { 0.25, 0.6, 0.2 }

local function Rows(lines, rows, prof)
    for _, r in ipairs(rows) do
        if r.text and r.text ~= "" then
            -- One block per row, like the Team tab (user, 2026-10-22): icon, the text in bold, one grey line under it
            -- with the kind of row and the place. Buy rows and market rows show by text colour (blue buy, red sell).
            local icon = r.icon or (STEP_ICON[r.label] and ("Interface\\Icons\\" .. STEP_ICON[r.label]))
                         or ((prof or (r.text:match("^(%a+)"))) and PROF_ICON[prof or r.text:match("^(%a+)")] and ProfIcon(prof or r.text:match("^(%a+)")))
            local kind = r.label == "Market" and (MarketNote(r.text) or "cold") or r.label == "Buy" and "cold" or r.label == "Temporary" and "temp" or nil
            local color = kind == "hot" and SELL_C or kind == "cold" and BUY_C or kind == "temp" and TEMP_C or { 0.35, 0.18, 0 }
            local detail = Detail(r, r.where, r.extra)
            table.insert(lines, { icon = icon, title = r.label == "Market" and MarketShort(r.text) or r.text, inline = false, titleColor = color,
                                  text = C.GREY .. detail .. "|r", point = r.point, click = r.click, match = r.match })
        end
    end
end

-- The team: every character of this realm the addon has seen (one save per name, the newest), most rested first.
local function Team()
    local realm = GetRealmName and GetRealmName()
    local me = UnitName("player")
    -- Only characters of the plan (test characters stay out); the one logged in always counts.
    local planned = {}
    for _, n in ipairs(PLAN.teamNames or {}) do planned[n] = true end
    local usePlan = next(planned) ~= nil
    local newest = {}
    for _, c in pairs(WoWForeverLevelerDB or {}) do
        if type(c) == "table" and c.name and (not realm or c.realm == realm) and (not usePlan or planned[c.name] or c.name == me) then
            local b = newest[c.name]
            if not b or (c.lastUpdated or 0) > (b.lastUpdated or 0) then newest[c.name] = c end
        end
    end
    -- The bank never levels: she is not part of the rotation (plan name, spare names or the menu switch).
    local bankNames, s = {}, WFL.Settings()
    local b = PLAN.bank or {}
    if b.name then bankNames[b.name] = true end
    for _, a in ipairs(b.alt or {}) do bankNames[a] = true end
    for key, on in pairs(s.bankChars or {}) do if on then bankNames[(key:match("^(.-)%-") or key)] = true end end
    -- The bank never levels: she is left out even while you play her.
    local team = {}
    for _, c in pairs(newest) do
        if not bankNames[c.name] then
        local rested = c.name == me and ((GetXPExhaustion and GetXPExhaustion() or 0) / math.max(1, UnitXPMax("player") or 1)) or WFL.RestedLevels(c)
        table.insert(team, { c = c, rested = rested, me = c.name == me, bank = bankNames[c.name] })
        end
    end
    table.sort(team, function(a, b) return a.rested > b.rested end)
    return team
end

local function Pct(r) return math.floor(r * 100 + 0.5) .. "%" end

-- --- Dungeons -----------------------------------------------------------------------------------------------------
-- Stops: dungeons with open quests you can still run, the nearest first. A dungeon chain is one more stop; its
-- dungeons are listed on their own as well.
local function Stops(level)
    local inChain = {}
    for _, ch in ipairs(PLAN.dungeonChains or {}) do
        for i, dn in ipairs(ch.dungeons) do inChain[dn] = { ch = ch, i = i } end
    end
    -- Every dungeon with open quests, whatever the route (user, 2026-10-19: list all, I decide where to go).
    local list, chainStop = {}, {}
    for _, d in ipairs(WFL.DungeonEntries(level)) do
        local open = false
        for _, q in ipairs(d.quests) do if not WFL.QuestDone(q.id) then open = true end end
        if open and level <= (d.run.runTo or d.run.to or 60) + 2 then
            local c = inChain[d.name]
            if c then
                local e = chainStop[c.ch.name]
                if not e then
                    e = { name = c.ch.name, chain = c.ch, slots = {}, at = d.allFrom }
                    chainStop[c.ch.name] = e
                    table.insert(list, e)
                end
                e.slots[c.i] = d
                e.at = math.min(e.at, d.allFrom)
            end
            -- Every dungeon also on its own (user, 2026-10-21: Stratholme and Scholomance were only in a chain).
            table.insert(list, { name = d.name, slots = { d }, at = d.allFrom })
        end
    end
    for _, s in ipairs(list) do
        s.members = {}
        for i = 1, 10 do if s.slots[i] then table.insert(s.members, s.slots[i]) end end
    end
    -- Level order; at the same level a chain comes before its own dungeons.
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if (a.chain ~= nil) ~= (b.chain ~= nil) then return a.chain ~= nil end
        return a.name < b.name
    end)
    return list
end

-- A dungeon's quests grouped by chain start: the start, then each next quest; dungeon quests marked.
local function ChainGroups(d)
    local groups, order = {}, {}
    for _, pk in ipairs(d.quests) do
        local seq = {}
        for _, c in ipairs(pk.chain or {}) do table.insert(seq, { id = c.id, n = c.n, npc = c.npc, m = c.m, x = c.x, y = c.y, r = c.r }) end
        table.insert(seq, { id = pk.id, n = pk.quest, npc = pk.npc, m = pk.mapID, x = pk.x, y = pk.y, r = pk.from, dungeon = true, o = pk.obj })
        local k = seq[1].id
        if not groups[k] then groups[k] = {}; table.insert(order, k) end
        table.insert(groups[k], seq)
    end
    local out = {}
    for _, k in ipairs(order) do
        local seqs = groups[k]
        table.sort(seqs, function(a, b) return #a > #b end)
        local ids, byId = {}, {}
        for _, seq in ipairs(seqs) do
            for _, q in ipairs(seq) do
                if not byId[q.id] then byId[q.id] = q; table.insert(ids, q.id)
                elseif q.dungeon then byId[q.id].dungeon = true; byId[q.id].o = q.o end
            end
        end
        -- Steps of one chain often share a name (Hidden Enemies three times): show the first open step once, with
        -- how many steps it has and whether the chain ends in a dungeon quest.
        local g = {}
        for _, id in ipairs(ids) do
            local q = byId[id]
            if not WFL.QuestDone(id) then
                local last = g[#g]
                if last and last.n == q.n then
                    last.steps = (last.steps or 1) + 1
                    last.dungeon = last.dungeon or q.dungeon
                else
                    table.insert(g, q)
                end
            end
        end
        if #g > 0 then table.insert(out, g) end
    end
    return out
end

-- The zone or city of a map spot, no coordinates (click the line for the arrow).
local function Zone(m) return (m and m > 0) and WFL.MapName(m) or "place not known" end

local function QPoint(q) return q.m and q.m > 0 and { mapID = q.m, x = q.x, y = q.y, title = q.npc ~= "" and q.npc or q.n, npc = q.npc ~= "" and q.npc or nil, questID = q.id } or nil end

-- The dungeon steps in order: per chain its first open quest (hand in, finish, take; starts in your zone first),
-- then "run it" once all its quests are in the log.
local function DungeonActions(level, zone)
    local st = Stops(level)[1]
    if not st then return {}, nil end
    local acts = {}
    if level < st.at - 2 then
        table.insert(acts, { text = "Character level " .. (st.at - 2) .. ": collect the " .. st.name .. " quests" })
    end
    for _, d in ipairs(st.members) do
        local groups = ChainGroups(d)
        table.sort(groups, function(a, b)
            local ha, hb = WFL.MapName(a[1].m) == zone and 0 or 1, WFL.MapName(b[1].m) == zone and 0 or 1
            return ha < hb
        end)
        for _, g in ipairs(groups) do
            local q = g[1]
            if WFL.InLog(q.id) and WFL.Complete(q.id) then
                table.insert(acts, { quest = q.n, text = "Hand in " .. q.n .. " to " .. q.npc, where = Zone(q.m), point = QPoint(q) })
            elseif WFL.InLog(q.id) then
                table.insert(acts, { quest = q.n, text = "Finish " .. q.n, where = "then " .. q.npc .. ", " .. Zone(q.m), point = QPoint(q) })
            elseif (q.r or 1) <= level then
                table.insert(acts, { quest = q.n, text = "Take " .. q.n .. " from " .. q.npc, where = Zone(q.m), point = QPoint(q) })
            end
        end
        local allIn, any = true, false
        for _, q in ipairs(d.quests) do
            if not WFL.QuestDone(q.id) then any = true; if not WFL.InLog(q.id) then allIn = false end end
        end
        if any and allIn then
            local e = d.run.entrance
            table.insert(acts, { text = "Run " .. d.name .. " until its quests are done", where = e and ("entrance " .. Zone(e.m)) or nil,
                                 point = e and { mapID = e.m, x = e.x, y = e.y, title = d.name .. " entrance" } or nil })
        end
    end
    return acts, st
end

-- The market state of an item (hot / normal / flooded), defined with the Market below; professions use it too.
local MarketState

-- --- Professions --------------------------------------------------------------------------------------------------
-- Crafts left in a step from skill `from` to `goal`: the step's count (Polestar's real counts, with the crafts that
-- give no point) for the part of the step still to do.
local function CraftsLeft(st, from, goal)
    local span = math.max(1, st.to - st.from)
    return math.max(1, math.ceil((st.count or span * 1.15) * (goal - from) / span))
end

-- The next rank to train (Plan.lua training) and the nearest trainer.
local function NextRank(prof, s)
    for _, t in ipairs((PLAN.training or {})[prof] or {}) do if s.max < t.cap then return t end end
end
local function TrainerWhere(prof, skipJunior)
    local p = WFL.TrainerPoint and WFL.TrainerPoint(prof, skipJunior)
    return p, p and (p.npc .. ", " .. Pos(p.mapID, p.x, p.y)) or "no trainer known on this continent yet"
end
-- What a rank costs at the trainer (Plan.lua profCosts, from the trainer scans): " (5s)", or "" when not known.
local function RankCost(prof, rank)
    local c = ((PLAN.profCosts or {})[prof] or {})[rank]
    return c and (" (" .. Money(c) .. ")") or ""
end

-- The tools and bag of a profession that this character has not got yet (Plan.lua profKit): the Buy row text
-- with prices (own vendor scan, else the plan's price) and the vendor of the first one (arrow), or nil.
local function KitToBuy(prof)
    local kit = (PLAN.profKit or {})[prof]
    if not kit then return nil end
    local items = {}
    for _, i in ipairs(kit.tools or {}) do table.insert(items, i) end
    if kit.bag then table.insert(items, kit.bag) end
    local parts, point = {}, nil
    for _, item in ipairs(items) do
        -- An item you already turned into something else counts too (Copper Rod -> Runed Copper Rod).
        local have = (WFL.OwnCount(item) or 0) > 0
        for _, alt in ipairs((kit.alt or {})[item] or {}) do have = have or (WFL.OwnCount(alt) or 0) > 0 end
        if not have then
            local price, vendor = WFL.ShopPrice(item, (kit.prices or {})[item])
            table.insert(parts, item .. (price and (" " .. Money(price)) or "") .. (vendor and (" (" .. vendor .. ")") or ""))
            point = point or WFL.ItemVendorPoint(item)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", "), point
end

-- "Journeyman (4s 50c): now" (true) when skill and level allow it, else "Journeyman (4s 50c) at skill 50, level 10".
local function TrainText(prof, s, level)
    local t = NextRank(prof, s)
    if not t then return nil, false end
    if s.rank >= t.skill and level >= (t.level or 0) then return t.name .. RankCost(prof, t.name) .. ": now", true end
    local need = {}
    if s.rank < t.skill then table.insert(need, "skill " .. t.skill) end
    if level < (t.level or 0) then table.insert(need, "character level " .. t.level) end
    return t.name .. RankCost(prof, t.name) .. " at " .. table.concat(need, " and "), false
end

-- What your skill can gather: in this zone (Plan.lua zones.<zone>.nodes), else anywhere (gatherNodes); best first.
local function GatherNow(prof, rank, zone)
    if prof == "Skinning" then return nil end
    local ok, here = {}, (((PLAN.zones or {})[zone] or {}).nodes or {})[prof]
    for _, n in ipairs(here or {}) do if n.skill <= rank then table.insert(ok, n) end end
    if #ok == 0 then
        for name, skill in pairs((PLAN.gatherNodes or {})[prof] or {}) do if skill <= rank then table.insert(ok, { name = name, skill = skill }) end end
    end
    if #ok == 0 then return nil end
    table.sort(ok, function(a, b) return a.skill > b.skill or (a.skill == b.skill and a.name < b.name) end)
    local t = {}
    for i = 1, math.min(3, #ok) do t[i] = ok[i].name .. " (" .. ok[i].skill .. ")" end
    return table.concat(t, ", ")
end

-- The next herbs or ores your skill unlocks: "Briarthorn at 70, Stranglekelp at 85" (Skinning: none).
local function NextUnlock(prof, rank)
    if prof == "Skinning" then return nil end
    local list = {}
    for name, skill in pairs((PLAN.gatherNodes or {})[prof] or {}) do if skill > rank then table.insert(list, { name = name, skill = skill }) end end
    table.sort(list, function(a, b) return a.skill < b.skill or (a.skill == b.skill and a.name < b.name) end)
    if not list[1] then return nil end
    local t = { list[1].name .. " at " .. list[1].skill }
    if list[2] then table.insert(t, list[2].name .. " at " .. list[2].skill) end
    return table.concat(t, ", ")
end

-- Whether this character knows a recipe (WoWForeverLevelerRecipes, saved when its profession window opens):
-- true / false, or nil when that window was never opened.
local function Knows(prof, recipe)
    local key = (GetRealmName and GetRealmName() or "") .. "-" .. (UnitName("player") or "")
    for k, profs in pairs(WoWForeverLevelerRecipes or {}) do
        if (k == key or k:sub(1, #key + 1) == key .. "-") and profs[prof] and profs[prof].recipes then
            return profs[prof].recipes[recipe] ~= nil
        end
    end
    return nil
end

-- Where to learn a step's recipe when this character does not know it (Plan.lua craftSteps learn): the trainer
-- with its cost, the pattern's vendor (our scans or ClassicDB, an arrow when the spot is known, limited stock
-- noted), the quest that gives it, or "where not known yet" for new Forever patterns.
local function LearnRow(prof, st)
    local l = st.learn
    local known = Knows(prof, st.recipe)
    if not l or known == true then return nil end
    if not l.source then
        if known ~= false then return nil end -- profession window never opened: trainer recipes come with the rank
        local p, w = TrainerWhere(prof)
        return { label = "Learn", text = st.recipe .. " at the trainer" .. (l.trainer and (" (" .. Money(l.trainer) .. ")") or ""), point = p, where = w }
    end
    local item = (l.item and l.item ~= "") and l.item or st.recipe
    local best, bestPoint
    for _, v in ipairs(l.vendors or {}) do
        local pt = WFL.VendorPoint(v.n, item)
        if not pt and v.m and v.x then pt = { mapID = v.m, x = v.x, y = v.y, title = v.n .. " (" .. item .. ")", npc = v.n } end
        if not best or (pt and not bestPoint) then best, bestPoint = v, pt end
    end
    if best then
        return { label = "Learn", text = item .. ((best.cost or 0) > 0 and (" " .. Money(best.cost)) or "") .. " from " .. best.n .. (best.limited and ", limited stock" or ""),
                 point = bestPoint, where = best.zone or (bestPoint and Pos(bestPoint.mapID, bestPoint.x, bestPoint.y)) }
    end
    local q = l.quests and l.quests[1]
    if q then return { label = "Learn", text = "Recipe: " .. item, where = "quest " .. q.n .. (q.level and (", quest level " .. q.level) or "") } end
    return { label = "Learn", text = "Recipe: " .. item, where = (l.source or "source") .. " \194\183 place not known" }
end

-- Per profession labelled rows (Rows): planned professions not learned yet (Learn, Buy, Then), crafts (Make, Then),
-- herbs and ore (Gather, Next), every profession its next rank with the trainer (Train) and missing tools (Buy).
-- SkillUp Forever (when installed): its public API (SkillUpForever.API, version 1) gives each learned crafting
-- profession's next steps, best recipes and reagents from its own live route (bags, bank, Auctionator prices, the
-- game's skill tables). We draw them here; clicks use its arrow or open the profession window.
local SU_LABEL = { craft = "Craft", buy = "Buy", gather = "Gather", train = "Train" }
local function SkillUp()
    local api = SkillUpForever and SkillUpForever.API
    if not (api and api.version == 1 and api.Professions) then return nil end
    local ok, list = pcall(api.Professions)
    if not ok or type(list) ~= "table" then return nil end
    local by = {}
    for _, e in ipairs(list) do if e.name then by[e.name] = e end end
    return by, api
end

-- Runs fn without SkillUp Forever's and TomTom's chat lines ("route set to ...", "Added a waypoint"): the arrow is
-- enough (user, 2026-10-22).
local function Quietly(fn, ...)
    local frame = DEFAULT_CHAT_FRAME
    local add = frame and frame.AddMessage
    if add then
        frame.AddMessage = function(self, msg, ...)
            if type(msg) == "string" and (msg:find("SkillUp") or msg:find("TomTom")) then return end
            return add(self, msg, ...)
        end
    end
    local ok, a, b = pcall(fn, ...)
    if add then frame.AddMessage = add end
    return ok and a, b
end

-- A material that monsters drop (Plan.lua reagentDrops, QuestieDB): the monster to kill, nearest your level, one
-- on your map first. Returns a row ("Kill Mottled Boar for 10 Chunk of Boar Meat") or a fishing row, or nil.
local function DropRow(item, count)
    local d = item and (PLAN.reagentDrops or {})[item]
    if not d then return nil end
    if d.fish then
        return { label = "Fish", text = "Fish for " .. (count or "") .. " " .. item, icon = "Interface\\Icons\\Trade_Fishing" }
    end
    local level = UnitLevel("player") or 1
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local best, bestScore
    for _, m in ipairs(d.mobs or {}) do
        -- Distance from your level (0 inside the monster's range), and a little bonus when it is on your map.
        local gap = (level < m.lo and (m.lo - level)) or (level > m.hi and (level - m.hi)) or 0
        local score = gap * 2 + (m.m == here and 0 or 3)
        if not bestScore or score < bestScore then best, bestScore = m, score end
    end
    if not best then return nil end
    return { label = "Kill", text = "Kill " .. best.n .. " for " .. (count or "") .. " " .. item,
             where = ((WFL.MapName(best.m) or "") ~= "" and (WFL.MapName(best.m) .. " \194\183 ") or "") .. "monster level " .. best.lo .. (best.hi ~= best.lo and ("-" .. best.hi) or ""),
             point = { mapID = best.m, x = best.x, y = best.y, title = best.n .. " (" .. item .. ")" },
             icon = WFL.ItemIcon(item) }
end

local function SkillUpRows(entry, api)
    local rows = {}
    local open = function() Quietly(api.OpenRecipes, entry.skillLineID) end
    -- What to craft first (user, 2026-10-22: Sveti saw only buy steps). SkillUp's API gives at most 3 steps and lists
    -- a buy step for each missing material first, which can push the craft out; its route recipes always say what to
    -- craft. The next two that still give points.
    local rank, shown = entry.rank or 0, 0
    for _, rc in ipairs(entry.recipes or {}) do
        if shown < 2 and (rc.toRank or 0) > rank then
            shown = shown + 1
            local icon = rc.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(rc.itemID)
            table.insert(rows, { label = "Craft", text = (rc.count or "?") .. " " .. (rc.name or "?") .. " \226\134\146 " .. rc.toRank,
                                 where = (rc.learned == false) and ("learn it first" .. (rc.trainAt and (" (skill " .. rc.trainAt .. ")") or "")) or nil,
                                 icon = icon, click = open })
        end
    end
    -- Then up to two of its other steps (buy, gather, train); its craft steps are covered above.
    local others = 0
    for i, st in ipairs(entry.steps or {}) do
        local drop = st.kind == "buy" and st.itemID and C_Item and C_Item.GetItemNameByID
                     and DropRow(C_Item.GetItemNameByID(st.itemID), st.count)
        if drop and others < 2 then
            -- "Buy 10 Chunk of Boar Meat" -> "Kill Mottled Boar for 10 Chunk of Boar Meat" (user, 2026-10-22).
            others = others + 1
            table.insert(rows, drop)
        elseif st.kind ~= "craft" and others < 2 then
            others = others + 1
            local click
            if st.nav then click = function() WFL.ClearArrows(); Quietly(api.Navigate, entry.skillLineID, i) end end
            -- "Krugosh, Razor Hill · 50c": the place under the step, the cost on the right.
            local where, cost = (st.detail or ""):match("^(.-)%s*\194\183%s*(.+)$")
            local icon = st.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(st.itemID)
            table.insert(rows, { label = SU_LABEL[st.kind] or "Next", text = st.text, where = where or st.detail, cost = cost,
                                 click = click, icon = icon })
        end
    end
    return rows
end

local function ProfessionActions()
    local acts, skills = {}, WFL.Skills()
    local level = UnitLevel("player") or 1
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local _, classFile = UnitClass("player")
    local planned = (((PLAN.classes or {})[classFile or ""]) or {}).profs or {}
    -- Temporary professions: a gathering (or any main) profession learned that is not in the plan, kept until the
    -- character reaches the trainer of a planned one it has no slot for (user, 2026-10-21). Paired in order:
    -- the first temporary one gives way to the first planned one not learned yet.
    local inPlan, temps, missing = {}, {}, {}
    for _, p in ipairs(planned) do inPlan[p] = true; if not skills[p] then table.insert(missing, p) end end
    for p in pairs(skills) do if (CRAFTS[p] or GATHER[p]) and not inPlan[p] then table.insert(temps, p) end end
    table.sort(temps)
    local replaces, freeSlots = {}, 2
    for p in pairs(skills) do if CRAFTS[p] or GATHER[p] then freeSlots = freeSlots - 1 end end
    for i, p in ipairs(temps) do replaces[p] = missing[i] end
    for _, prof in ipairs(planned) do
        if not skills[prof] then
            local point, where = TrainerWhere(prof)
            local drop
            if freeSlots <= 0 then
                for t, m in pairs(replaces) do if m == prof then drop = t end end
            end
            local buy, buyPoint = KitToBuy(prof)
            local st = ((PLAN.craftSteps or {})[prof] or {})[1]
            -- Your plan takes it from the start zone's free book (user, 2026-10-24): say so, not "Learn (10c)".
            local learnText = "Learn " .. prof .. RankCost(prof, "Apprentice")
            for _, ps in ipairs((PLAN.paths or {})[UnitName("player")] or {}) do
                if ps.alert and ps.alert.has == prof and (ps.text or ""):find("book") then
                    learnText = "Free " .. prof .. " book: quest " .. ((ps.text or ""):match("^(.-):") or "")
                    point, where = nil, ps.where
                end
            end
            table.insert(acts, { prof = prof, s = { rank = 0, max = 0 }, learn = true, craft = CRAFTS[prof], gather = GATHER[prof] and true, rows = {
                { label = "Learn", text = learnText, point = point,
                  where = drop and ("Drop " .. drop .. " first \194\183 " .. (where or "")) or where },
                { label = "Buy", text = buy, point = buyPoint },
                { label = "Gather", text = GatherNow(prof, 1, zone) },
                { label = "Make", text = st and (CraftsLeft(st, st.from, st.to) .. " " .. st.recipe .. " to " .. st.to) },
            } })
        end
    end
    local su, api = SkillUp()
    for prof, s in pairs(skills) do
        local buy, buyPoint = KitToBuy(prof)
        local train = TrainText(prof, s, level)
        -- The next rank of a learned profession is Journeyman or higher: not at a Junior trainer.
        local tPoint, tWhere = TrainerWhere(prof, true)
        local trainRow = train and { label = "Train", text = train, point = tPoint, where = tWhere }
        local rows = {}
        local steps = (PLAN.craftSteps or {})[prof]
        local sue = su and su[prof]
        if sue then
            -- SkillUp's next steps replace our Make / Then / Train / Buy; our market note stays under them.
            rows = SkillUpRows(sue, api)
            if #rows == 0 then rows = { { label = "Level", text = "nothing to do now (SkillUp Forever)" } } end
            local st = steps and steps[1]
            for item in pairs((st and st.raw) or {}) do
                local state, why = MarketState(item)
                if state == "hot" then table.insert(rows, { label = "Market", text = item .. " is hot (" .. why .. "): sell it, craft later" }) break end
                if state == "flooded" then table.insert(rows, { label = "Market", text = item .. " is cheap (" .. why .. "): buy it for this step" }) break end
            end
            table.insert(acts, { prof = prof, s = s, craft = true, gather = GATHER[prof] and true, mats = true, su = sue, rows = rows })
        elseif steps then
            local i = 1
            for j, x in ipairs(steps) do if s.rank < x.to then i = j break end i = j end
            local st, nx = steps[i], steps[i + 1]
            local goal = math.min(st.to, s.max)
            -- A craft that sells (Plan.lua craftSteps sell: our auction scans): its price, and sell only a few
            -- (the launch market is small: forever_profs.py MARKET_CAP).
            -- Green or better armor and weapons: what disenchanting one is worth (the enchanter gets the materials).
            local de = st.de and st.de > 0 and ("disenchant " .. Money(st.de)) or nil
            -- No generic "sell at most 10" (user, 2026-10-22); a warning only when the item's market is small
            -- (usually fewer than 5 listed in our scans).
            local pr = (PLAN.prices or {})[st.recipe]
            local small = pr and pr.qtyUsual and pr.qtyUsual < 5 and "small market: sell a few" or nil
            local sells = st.sell and ("Sells " .. Money(st.sell) .. (small and (", " .. small) or "") .. (de and (" \194\183 " .. de) or "")) or de
            if s.rank < goal then
                local learn = LearnRow(prof, st)
                if learn then table.insert(rows, learn) end
                table.insert(rows, { label = "Make", text = CraftsLeft(st, math.max(s.rank, st.from), goal) .. " " .. st.recipe .. " \226\134\146 " .. goal, extra = sells })
            end
            if nx and nx.from < s.max then
                local g2 = math.min(nx.to, s.max)
                table.insert(rows, { label = "Then", text = CraftsLeft(nx, nx.from, g2) .. " " .. nx.recipe .. " \226\134\146 " .. g2 })
            end
            -- The market for this step's materials: hot = sell them now and craft later, cheap = buy them now.
            for item in pairs(st.raw or {}) do
                local state, why = MarketState(item)
                if state == "hot" then table.insert(rows, { label = "Market", text = item .. " is hot (" .. why .. "): sell it, craft later" }) break end
                if state == "flooded" then table.insert(rows, { label = "Market", text = item .. " is cheap (" .. why .. "): buy it for this step" }) break end
            end
        elseif GATHER[prof] then
            table.insert(rows, { label = "Gather", text = GatherNow(prof, s.rank, zone) })
            table.insert(rows, { label = "Next", text = NextUnlock(prof, s.rank) })
        end
        if not sue then
            -- Training comes first when it can be done now or the skill is capped.
            if trainRow then
                if s.rank >= s.max or train:find(": now$") then table.insert(rows, 1, trainRow) else table.insert(rows, trainRow) end
            end
            table.insert(rows, { label = "Buy", text = buy, point = buyPoint })
            if not rows[1] or not rows[1].text then table.insert(rows, 1, { label = "Level", text = "while you play" }) end
            table.insert(acts, { prof = prof, s = s, craft = steps and true, gather = GATHER[prof] and true, mats = steps and true, rows = rows })
        end
    end
    -- The temporary row on top: gather now, mail what you gather, drop it at the planned profession's trainer.
    for _, a in ipairs(acts) do
        if not a.learn and not inPlan[a.prof] and (CRAFTS[a.prof] or GATHER[a.prof]) then
            local goal = replaces[a.prof]
            local _, where = TrainerWhere(goal or "")
            table.insert(a.rows, 1, { label = "Temporary", text = goal and ("Drop for " .. goal .. " \194\183 " .. (where:match(", (.+)$") or where))
                                                               or "not in your plan; keep it while it pays" })
            a.temp = true
        end
    end
    table.sort(acts, function(a, b) return (a.craft and 0 or a.gather and 1 or 2) .. a.prof < (b.craft and 0 or b.gather and 1 or 2) .. b.prof end)
    return acts
end

local function Bracket(prof, rank)
    local mp = (PLAN.matPlan or {})[prof]
    if not mp then return nil end
    for _, b in ipairs(mp.brackets or {}) do if rank < b.to then return b end end
    return mp.brackets and mp.brackets[#mp.brackets]
end

-- Raw materials still needed from this skill to the end of the bracket: the path steps (Plan.lua craftSteps raw)
-- from here on, a step already started counted for the part left. Crafting lowers "have" and this "need" together.
-- Without step data: the whole bracket (b.mats).
local function StillNeeded(prof, rank, b)
    local steps = (PLAN.craftSteps or {})[prof]
    if not (steps and steps[1] and steps[1].raw) then return b.mats end
    local out = {}
    for _, st in ipairs(steps) do
        local from, to = math.max(st.from, rank, b.from), math.min(st.to, b.to)
        if to > from then
            local part = (to - from) / math.max(1, st.to - st.from)
            for item, n in pairs(st.raw or {}) do out[item] = (out[item] or 0) + n * part end
        end
    end
    for item, n in pairs(out) do out[item] = math.ceil(n) end
    return out
end

local function MatLine(item, have, need, tip)
    -- One block like the other rows: the material in bold, who holds it in grey under it ("Banka 40 · You 12 ·
    -- Pala 3"), the have / need bar on the right.
    local where = {}
    for i, w in ipairs(WFL.MaterialWhere and WFL.MaterialWhere(item) or {}) do
        if i <= 4 then table.insert(where, w.name .. " " .. w.n) end
    end
    local extra = have > need and (C.GREEN .. "sell " .. (have - need) .. "|r") or nil
    local holders = #where > 0 and (C.GREY .. table.concat(where, " \194\183 ") .. "|r") or nil
    return { icon = WFL.ItemIcon(item), title = item, inline = false, titleColor = { 0.35, 0.18, 0 },
             text = (holders and extra) and (holders .. "  " .. extra) or holders or extra,
             bar = { have = have, need = need }, tip = tip, item = item }
end

-- What the crafters of the team need for their current skill step: { item = { n, by = {...} } }.
local function TeamNeed()
    local need = {}
    for _, t in ipairs(Team()) do
        for _, p in ipairs(t.c.professions or {}) do
            if CRAFTS[p.name] then
                local b = Bracket(p.name, p.rank or 0)
                if b then
                    for item, n in pairs(StillNeeded(p.name, p.rank or 0, b)) do
                        need[item] = need[item] or { n = 0, by = {} }
                        need[item].n = need[item].n + n
                        table.insert(need[item].by, t.c.name .. " " .. p.name .. " " .. b.from .. "-" .. b.to)
                    end
                end
            end
        end
    end
    return need
end

-- --- Market (bank) ------------------------------------------------------------------------------------------------
-- Prices: Auctionator's current price in game when it has one, else the newest scan from Sync; the usual price
-- is the middle of the scans (Plan.lua prices). Vendor price from the item info.
local function PriceNow(item)
    local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[item]
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if id and api and api.GetAuctionPriceByItemID then
        local ok, p = pcall(api.GetAuctionPriceByItemID, "WoWForeverLeveler", id)
        if ok and p and p > 0 then return p end
    end
    local p = (PLAN.prices or {})[item]
    return p and p.last
end
local function PriceUsual(item) local p = (PLAN.prices or {})[item]; return p and p.usual or PriceNow(item) end
local function VendorPrice(item)
    local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[item]
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (id and info and select(11, info(id))) or 0
end

-- Market state from the item's own history (Plan.lua prices: usual price and usual amount listed from the Sync
-- scans; now = Auctionator in game): no fixed prices, so it follows the market at launch and later.
--   hot:     price 25% above usual or half as many listed -> sell raw materials now, craft later
--   flooded: price 25% below usual or twice as many listed -> buy what the crafters need, hold extras
--   normal:  follow the plan. Below 2 scans every item counts as normal.
MarketState = function(item)
    local p, now = (PLAN.prices or {})[item], PriceNow(item)
    if not (p and now and p.usual and p.usual > 0 and (p.n or 0) >= 2) then return "normal", nil, now end
    local ratio = now / p.usual
    local why = Money(now) .. ", usual " .. Money(p.usual) .. (p.qty and (", " .. p.qty .. " listed") or "")
    -- By price only (user, 2026-10-22: too many hot items): the number listed jumps around during the day, so it no
    -- longer makes an item hot or flooded on its own.
    if ratio >= 1.3 then return "hot", why, now end
    if ratio <= 0.75 then return "flooded", why, now end
    return "normal", why, now
end
-- Few listed (under 5): a cheap price there may be bait, do not copy it.
local function FewListed(item) local p = (PLAN.prices or {})[item]; return p and p.qty and p.qty < 5 end

local function Market()
    local need, items = TeamNeed(), {}
    for item in pairs(PLAN.matNeed or {}) do items[item] = true end
    local sell, buy, hold = {}, {}, {}
    for item in pairs(items) do
        local have, n = WFL.MaterialHave(item), need[item] and need[item].n or 0
        local state, why, now = MarketState(item)
        local vend = VendorPrice(item)
        if now and have > 0 then
            if state == "hot" then
                -- Hot: sell all of it, also what the crafters need; buy it back when the market cools.
                table.insert(sell, { item = item, extra = have, now = now, value = have * now * 0.95, why = why, needed = n, state = state })
            elseif have > n then
                local extra = have - n
                if state == "flooded" then table.insert(hold, { item = item, extra = extra, now = now, why = why })
                elseif now * 0.95 >= math.max(1.5 * vend, 5) then table.insert(sell, { item = item, extra = extra, now = now, value = extra * now * 0.95, why = why, state = state }) end
            end
        end
        if now and n > have and state == "flooded" then
            table.insert(buy, { item = item, short = n - have, now = now, why = why, cost = (n - have) * now })
        end
    end
    -- Crafts the team can make now: the plan's leveling recipes up to each crafter's skill, product vs materials.
    local crafts, seen = {}, {}
    for _, t in ipairs(Team()) do
        for _, p in ipairs(t.c.professions or {}) do
            for _, st in ipairs((PLAN.craftSteps or {})[p.name] or {}) do
                if st.from <= (p.rank or 0) and not seen[st.recipe] then
                    seen[st.recipe] = true
                    local sellAt = PriceNow(st.recipe)
                    if sellAt then
                        local cost, known = 0, true
                        for part in (st.mats .. ", "):gmatch("(.-), ") do
                            local q, mat = part:match("^(%d+) (.+)$")
                            if q then
                                local pr = PriceNow(mat)
                                if pr then cost = cost + tonumber(q) / st.count * pr else known = false end
                            end
                        end
                        if known and sellAt * 0.95 > cost then
                            table.insert(crafts, { recipe = st.recipe, who = t.c.name, prof = p.name, sellAt = sellAt, cost = cost, profit = sellAt * 0.95 - cost })
                        end
                    end
                end
            end
        end
    end
    table.sort(sell, function(a, b) return (a.state == "hot" and 0 or 1) < (b.state == "hot" and 0 or 1) or ((a.state == "hot") == (b.state == "hot") and a.value > b.value) end)
    table.sort(buy, function(a, b) return a.cost > b.cost end)
    table.sort(crafts, function(a, b) return a.profit > b.profit end)
    return { sell = sell, buy = buy, hold = hold, crafts = crafts }
end

-- --- Tabs ---------------------------------------------------------------------------------------------------------
local function Section(lines, id, open, title, summary, icon, default, tint)
    local isOpen = open[id]
    if isOpen == nil then isOpen = default ~= false end
    table.insert(lines, { section = id, icon = icon, open = isOpen, title = title, inline = true, text = C.GREY .. (summary or "") .. "|r", tint = tint })
    return isOpen
end

-- Cards on every tab (style A, user 2026-10-22): each section header becomes a card header (medium brown, yellow
-- title, cream summary) and the lines under it go inside the card. A line with group = true (a title over several
-- cards, such as "Dungeon chains") stays outside. Lines that already have a card (the Professions tab) are kept.
local HEAD_TEXT = "|cffeadfb8"
local HEAD_TITLE = { 1, 0.82, 0 }
local function HeadText(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", HEAD_TEXT) end
-- Every second header is light (no dark fill): dark brown title, grey-brown summary.
local ALT_TITLE = { 0.35, 0.18, 0 }
local function AltText(t) return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", "|cff6e5a3c") end
-- Every second row inside a card gets a stripe (user, 2026-10-22). A row is a line with a title or an icon; the
-- lines under it (its place, its task text) keep its stripe. Notes and headers keep their own look.
local function Stripe(lines)
    local k, on = 0, false
    for _, l in ipairs(lines) do
        if l.card == "head" or l.group or not l.card then
            k, on = 0, false
        elseif l.title or l.icon then
            k = k + 1
            on = k % 2 == 0
            if l.stripe == nil then l.stripe = on end
        elseif l.stripe == nil then
            l.stripe = on
        end
    end
    return lines
end

local function Cardify(lines)
    local last
    local function close()
        if not last then return end
        local l = lines[last]
        l.cardEnd = true
        if l.card == "body" then l.card = "foot" end
        last = nil
    end
    local n = 0
    for i, l in ipairs(lines) do
        if l.card then
            -- built as a card already: leave it
        elseif l.group then
            close()
            n = 0
        elseif l.section then
            close()
            n = n + 1
            l.card, l.alt = "head", n % 2 == 0 and not l.tint
            l.titleColor, l.text = l.alt and ALT_TITLE or HEAD_TITLE, l.alt and AltText(l.text) or HeadText(l.text)
            if l.icon then l.big = true end
            last = i
        elseif l.group then
            close()
            n = 0
        elseif last then
            l.card = "body"
            last = i
        end
    end
    close()
    return Stripe(lines)
end

-- The team member a line names ("Switch to Vestac: ..."), for a link to that row of the Team tab.
local function TeamName(l)
    local title = l.title or ""
    for _, t in ipairs(Team()) do
        if t.c.name and title:find(t.c.name, 1, true) then return t.c.name end
    end
end

local function TeamPair(lines)
    local team, mine, others = Team(), nil, {}
    for _, t in ipairs(team) do if t.me then mine = t elseif not t.bank then table.insert(others, t) end end
    if mine and not IsBank() and mine.rested > 0.05 then
        Pair(lines, "Keep playing " .. mine.c.name .. ": " .. Pct(mine.rested) .. " rested left", others[1] and ("Then " .. others[1].c.name .. " (" .. Pct(others[1].rested) .. ")"))
    elseif others[1] then
        Pair(lines, "Switch to " .. others[1].c.name .. ": " .. Pct(others[1].rested) .. " rested", others[2] and ("Then " .. others[2].c.name .. " (" .. Pct(others[2].rested) .. ")"))
    else
        Pair(lines, "No rested XP on anyone yet", nil)
    end
    return #team
end

-- Legacy points on this account and realm (WoWForeverLevelerDB): the highest level per class (25, 45, 60: one
-- point each for the first of each class) and the best rank per crafting profession (150, 225, 300).
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function ClassName(file)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file or ""]
    return n or ((file or "?"):sub(1, 1) .. (file or "?"):sub(2):lower())
end
local function LegacyStatus()
    local realm = GetRealmName and GetRealmName()
    local levels, crafts = {}, {}
    for _, c in pairs(WoWForeverLevelerDB or {}) do
        if type(c) == "table" and (not realm or c.realm == realm) then
            if c.class then levels[c.class] = math.max(levels[c.class] or 0, c.level or 0) end
            for _, p in ipairs(c.professions or {}) do
                if CRAFTS[p.name] then crafts[p.name] = math.max(crafts[p.name] or 0, p.rank or 0) end
            end
        end
    end
    local _, me = UnitClass("player")
    if me then levels[me] = math.max(levels[me] or 0, UnitLevel("player") or 0) end
    for prof, s in pairs(WFL.Skills()) do if CRAFTS[prof] then crafts[prof] = math.max(crafts[prof] or 0, s.rank) end end
    local got = 0
    for _, cl in ipairs(CLASS_ORDER) do for _, l in ipairs({ 25, 45, 60 }) do if (levels[cl] or 0) >= l then got = got + 1 end end end
    for prof in pairs(CRAFTS) do for _, c in ipairs({ 150, 225, 300 }) do if (crafts[prof] or 0) >= c then got = got + 1 end end end
    return { levels = levels, crafts = crafts, got = got, total = 27 + 18 + #(PLAN.spelunker or {}) }
end

-- "25 · 45 · 60" with the reached ones green.
local function Marks(have, steps)
    local t = {}
    for _, x in ipairs(steps) do table.insert(t, ((have or 0) >= x and C.GREEN or C.GREY) .. x .. "|r") end
    return table.concat(t, C.GREY .. " · |r")
end

local function LegacyLines(lines)
    local st = LegacyStatus()
    table.insert(lines, { plain = true, gap = 4, text = C.GOLD .. "Character levels|r" .. C.GREY .. "  first of each class|r" })
    for _, cl in ipairs(CLASS_ORDER) do
        table.insert(lines, { icon = ClassIcon(cl), title = ClassName(cl), inline = true, titleColor = GREY_C, text = Marks(st.levels[cl], { 25, 45, 60 }) })
    end
    table.insert(lines, { plain = true, gap = 4, text = C.GOLD .. "Crafting|r" })
    local names = {}
    for prof in pairs(CRAFTS) do table.insert(names, prof) end
    table.sort(names)
    for _, prof in ipairs(names) do
        table.insert(lines, { icon = ProfIcon(prof), title = prof, inline = true, titleColor = GREY_C, text = Marks(st.crafts[prof], { 150, 225, 300 }) })
    end
    if PLAN.spelunker and PLAN.spelunker[1] then
        table.insert(lines, { plain = true, gap = 4, text = C.GOLD .. "Dungeons|r" .. C.GREY .. "  one clear per tier|r" })
        for _, t in ipairs(PLAN.spelunker) do
            table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_Key_14", title = t.name, inline = false, titleColor = GREY_C, text = C.GREY .. table.concat(t.dungeons, ", ") .. "|r" })
        end
    end
    table.insert(lines, { text = C.GREY .. "More in the game's Legacy panel (Y).|r" })
end

-- This character's own plan (personal/team.json "path", user 2026-10-24): the steps for your level, then the next
-- one in grey. A step with "to" lasts from..to; one without lasts until the next such step.
local function PathRows(level)
    local path = (PLAN.paths or {})[UnitName("player")]
    if not path then return nil end
    local rows, nextStep = {}, nil
    local skills = WFL.Skills() or {}
    for i, st in ipairs(path) do
        -- Done: the profession it teaches is learned, or the item it buys is in your bags (user, 2026-10-24).
        local a = st.alert or {}
        local done = (a.lacks and skills[a.lacks]) or (a.noItem and (WFL.OwnCount(a.noItem) or 0) > 0)
        local active
        if st.to then
            active = level >= st.from and level <= st.to
        else
            active = level >= st.from
            for j = i + 1, #path do
                if not path[j].to and path[j].from > st.from and path[j].from <= level then active = false break end
            end
        end
        if done then
            -- nothing: a done step is not shown
        elseif active then
            table.insert(rows, { icon = "Interface\\Icons\\INV_Misc_Note_01", title = st.text, inline = false,
                                 text = st.where and (C.GREY .. st.where .. "|r") or nil })
        elseif st.from > level and (not nextStep or st.from < nextStep.from) then
            nextStep = st
        end
    end
    if nextStep then
        table.insert(rows, { icon = "Interface\\Icons\\INV_Misc_Note_01", desat = true, title = nextStep.text, inline = false, titleColor = GREY_C,
                             text = C.GREY .. "character level " .. nextStep.from .. (nextStep.where and (" \194\183 " .. nextStep.where) or "") .. "|r" })
    end
    return rows
end

-- Rares worth hunting for this character (Plan.lua rares, user 2026-10-26): from 2 character levels below the rare,
-- until the item is in your bags or worn. Sorted by level; at most 3.
local function RareOwned(item)
    if (WFL.OwnCount(item) or 0) > 0 then return true end
    local eq = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
    local ok, yes = pcall(eq or function() end, item)
    return ok and yes and true or false
end
local function MyRares(level)
    local me, out = UnitName("player"), {}
    for _, r in ipairs(PLAN.rares or {}) do
        if (r["for"] or {})[me] and level >= (r.lo or 1) - 2 and not RareOwned(r.item) then table.insert(out, r) end
    end
    return out
end
local function RareWhere(r)
    return (r.m and (WFL.MapName(r.m) .. " \194\183 ") or "") .. "rare, monster level " .. (r.lo or "?")
           .. (r.stats ~= "" and (" \194\183 " .. r.stats) or "") .. (r.group and " \194\183 group needed" or "")
end

local function NextLeveling(open)
    local lines, level, zone = {}, UnitLevel("player") or 1, GetRealZoneText() or ""
    local path = PathRows(level)
    if path and Section(lines, "n-plan", open, "Your plan", (PLAN.dungeonLevelers or {})[UnitName("player")] or "", "Interface\\Icons\\INV_Misc_Note_01") then
        for _, r in ipairs(path) do table.insert(lines, r) end
    end
    local rares = MyRares(level)
    if #rares > 0 and Section(lines, "n-rare", open, "Rares", #rares .. " for you", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01") then
        for i, r in ipairs(rares) do
            if i > 3 then break end
            table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", title = "Kill " .. r.npc .. " for " .. r.item,
                                  inline = false, text = C.GREY .. RareWhere(r) .. "|r",
                                  point = r.m and { mapID = r.m, x = r.x, y = r.y, title = r.npc .. " (" .. r.item .. ")" } or nil })
        end
    end
    local acts, st = DungeonActions(level, zone)
    if Section(lines, "n-d", open, "Dungeons", st and st.name or "nothing for your level", "Interface\\Icons\\INV_Misc_Key_14") then
        -- A dungeon leveler (Konan, Nemrtvi) between two dungeon chains: quest here (user, 2026-10-24).
        if (PLAN.dungeonLevelers or {})[UnitName("player")] then
            for _, gap in ipairs(PLAN.dungeonGaps or {}) do
                if level >= gap.from and level < gap.to then
                    table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Quest gap: character level " .. gap.from .. "-" .. gap.to,
                                          inline = false, titleColor = { 0.85, 0.45, 0 }, text = C.GREY .. gap.text .. "|r" })
                end
            end
        end
        if acts[1] then
            local t = acts[1].text
            local icon = t:find("^Take") and WFL.icons.take or (t:find("^Hand in") or t:find("^Finish")) and WFL.icons.turnin or "Interface\\Icons\\INV_Misc_Key_03"
            local from = #lines
            Pair(lines, t, acts[2] and (acts[2].text .. ((acts[2].where and acts[2].where ~= "") and (" (" .. acts[2].where .. ")") or "")), acts[1].point, acts[1].where, icon)
            LinkRows(lines, from, "dg", "d:" .. st.name, acts[2] and acts[2].quest)
        else
            table.insert(lines, { text = C.GREY .. "No dungeon quests open for character level " .. level .. ".|r" })
        end
    end
    -- Only the main professions here (crafting and gathering); Cooking, First Aid and Fishing are on the Professions tab.
    local pa = {}
    for _, a in ipairs(ProfessionActions()) do if a.craft or a.gather then table.insert(pa, a) end end
    local names = {}
    for _, a in ipairs(pa) do table.insert(names, a.prof .. " " .. (a.learn and "(learn)" or a.s.rank)) end
    if Section(lines, "n-p", open, "Professions", #names == 0 and "none yet" or "", "Interface\\Icons\\Trade_BlackSmithing") then
        if #pa == 0 then table.insert(lines, { text = C.GREY .. "No professions learned yet.|r" }) end
        -- Per profession only the first thing to do (user, 2026-10-22: Next repeated the whole Professions tab);
        -- click the profession for its card in the Professions tab.
        for _, a in ipairs(pa) do
            local open = function() WFL.OpenTab("prof2", "p:" .. a.prof) end
            table.insert(lines, { icon = ProfIcon(a.prof), title = a.prof, inline = true, titleColor = { 0.35, 0.18, 0 },
                                  text = a.learn and (C.GREY .. "not learned|r") or "", click = open,
                                  bar = (not a.learn) and { have = a.s.rank, need = a.s.max, color = SKILL_GREEN } or nil })
            local firstRow, tempRow
            for _, r in ipairs(a.rows) do
                if r.label == "Temporary" then tempRow = tempRow or r
                elseif r.label ~= "Market" and r.text and r.text ~= "" then firstRow = firstRow or r end
            end
            local pick = {}
            if tempRow then table.insert(pick, tempRow) end
            if firstRow then table.insert(pick, firstRow) end
            Rows(lines, pick, a.prof)
        end
    end
    if Section(lines, "n-t", open, "Team", "", "Interface\\Icons\\INV_Misc_GroupLooking") then
        local from = #lines
        TeamPair(lines)
        LinkRows(lines, from, "team", "t-l", TeamName)
    end
    -- Legacy: this character's next point (level, then crafting), only when nobody on the account has it yet.
    local st, rows = LegacyStatus(), {}
    local _, classFile = UnitClass("player")
    for _, l in ipairs({ 25, 45, 60 }) do
        if (st.levels[classFile or ""] or 0) < l then table.insert(rows, { label = "Level", text = "Character level " .. l .. ": first " .. ClassName(classFile) .. " there", match = ClassName(classFile) }) break end
    end
    for prof in pairs(WFL.Skills()) do
        if CRAFTS[prof] then
            for _, c in ipairs({ 150, 225, 300 }) do
                if (st.crafts[prof] or 0) < c then table.insert(rows, { label = "Craft", text = prof .. " " .. c, match = prof }) break end
            end
        end
    end
    if Section(lines, "n-l", open, "Legacy points", st.got .. " of " .. st.total, "Interface\\Icons\\INV_Misc_Book_08") then
        local from = #lines
        if rows[1] then Rows(lines, rows) else table.insert(lines, { text = C.GREY .. "Nothing left for this character.|r" }) end
        LinkRows(lines, from, "team", "t-g")
    end
    return lines
end

local function NextBank(open)
    local lines, mk = {}, Market()
    if Section(lines, "b-m", open, "Market", "scan the AH with Auctionator first", "Interface\\Icons\\INV_Misc_Coin_02") then
        local s0, s1, b0, c0 = mk.sell[1], mk.sell[2], mk.buy[1], mk.crafts[1]
        Pair(lines, s0 and ("Sell " .. s0.extra .. " " .. s0.item .. " at " .. Money(s0.now) .. (s0.state == "hot" and ("  " .. HOT) or "")) or "Nothing to sell now",
             b0 and ("Buy " .. b0.short .. " " .. b0.item .. " (" .. b0.why .. ")")
             or (s1 and ("Sell " .. s1.extra .. " " .. s1.item .. " (" .. Money(s1.value) .. ")")))
        -- Click the sell or buy line: the Market tab at that list (links, 2026-10-22).
        local n = #lines
        for i = n - 2, n do
            local l = lines[i]
            if l and l.title and not l.section then
                local key = l.title:find("^Buy") and "m-b" or "m-s"
                local item = (b0 and l.title:find(b0.item, 1, true) and b0.item) or (s0 and l.title:find(s0.item, 1, true) and s0.item)
                             or (s1 and l.title:find(s1.item, 1, true) and s1.item) or nil
                if item then l.click = function() WFL.OpenTab("market", key, item) end end
                l.titleColor = key == "m-b" and BUY_C or SELL_C
            end
        end
        if c0 then
            table.insert(lines, { icon = WFL.ItemIcon(c0.recipe), title = c0.recipe, inline = false, titleColor = GREEN_C,
                                  text = C.GREY .. "Craft to sell \194\183 " .. c0.who .. " \194\183 +" .. Money(c0.profit) .. " each|r",
                                  click = function() WFL.OpenTab("market", "m-c", c0.recipe) end })
        end

    end
    -- Mail: only when new mail is waiting (user, 2026-10-22: "No new mail" added nothing).
    if HasNewMail and HasNewMail() and Section(lines, "b-mail", open, "Mail", "", "Interface\\Icons\\INV_Letter_15") then
        table.insert(lines, { icon = "Interface\\Icons\\INV_Letter_15", title = "Collect the new mail", inline = false, titleColor = GREEN_C })
    end
    if Section(lines, "n-t", open, "Team", "", "Interface\\Icons\\INV_Misc_GroupLooking") then
        local from = #lines
        TeamPair(lines)
        LinkRows(lines, from, "team", "t-l", TeamName)
    end
    return lines
end

local function NextTabLines(open)
    open = open or {}
    if IsBank() then return NextBank(open) end
    return NextLeveling(open)
end

local function DungeonTabLines(open)
    open = open or {}
    local lines, level = {}, UnitLevel("player") or 1
    -- Only what you can run in the next 10 character levels (user, 2026-10-24: 20 dungeons up to level 62 at
    -- level 1 was too much); a grey line says how many come later.
    local stops, later = {}, 0
    for _, st in ipairs(Stops(level)) do
        local lo = 99
        for _, m in ipairs(st.members) do lo = math.min(lo, m.run.runFrom or st.at or 99) end
        if math.max(lo, st.at or 0) <= level + 10 then table.insert(stops, st) else later = later + 1 end
    end
    if #stops == 0 then return { { text = C.GREY .. "No dungeon quests open for character level " .. level .. ".|r" } } end
    -- Two groups, each in level order: the chains (what to pick up for a run of dungeons), then every dungeon.
    local ordered, first = {}, {}
    for _, want in ipairs({ true, false }) do
        for _, st in ipairs(stops) do
            if (st.chain ~= nil) == want then
                if not first[want] then first[want] = st end
                table.insert(ordered, st)
            end
        end
    end
    -- The two banners fold like cards: closed, the chains or dungeons under them are hidden (user, 2026-10-22).
    local gOpen = {}
    for _, want in ipairs({ true, false }) do
        local o = open[want and "g:chains" or "g:dungeons"]
        if o == nil then o = true end
        gOpen[want] = o
    end
    for si = 1, #ordered do
        local s = ordered[si]
        if first[true] == s then table.insert(lines, { plain = true, group = true, section = "g:chains", open = gOpen[true], text = "|cffffd100Dungeon chains|r" }) end
        if first[false] == s then table.insert(lines, { plain = true, group = true, section = "g:dungeons", open = gOpen[false], text = "|cffffd100Dungeons|r" }) end
        if gOpen[s.chain ~= nil] then
        local due = level >= s.at
        -- Folded line: when the quests open and the run levels of its dungeons.
        local lo, hi = 99, 0
        for _, m in ipairs(s.members) do lo = math.min(lo, m.run.runFrom or 99); hi = math.max(hi, m.run.runTo or 0) end
        -- "lvl: 15-16": when to run it, with all its quests in hand (green when you are there).
        -- Joined with no-break spaces, so a narrow window moves it under the name whole instead of splitting it.
        local range = hi > 0 and (math.max(s.at, lo) .. "-" .. hi) or tostring(s.at)
        local summary = ((due and C.GREEN or "") .. "character level " .. range .. (due and "|r" or "")):gsub(" ", "\194\160")
        if Section(lines, "d:" .. s.name, open, s.name, summary, "Interface\\Icons\\INV_Misc_Key_14", si == 1) then
            if s.chain then
                -- A chain: only the dungeons in run order, with entrances. Where to pick up the quests is in each
                -- dungeon's own section (user, 2026-10-21: a chain's full quest list is too long, levels differ).
                table.insert(lines, { plain = true, text = C.GOLD .. "Run in this order|r" })
                for i, d in ipairs(s.members) do
                    local e = d.run.entrance
                    table.insert(lines, { num = i, icon = "Interface\\Icons\\INV_Misc_Key_03", title = d.name, inline = false,
                                          text = C.GREY .. "character level " .. d.run.runFrom .. "-" .. d.run.runTo .. " \194\183 " .. (e and Zone(e.m) or (d.run.zone or "?")) .. "|r",
                                          point = e and { mapID = e.m, x = e.x, y = e.y, title = d.name .. " entrance" } or nil, stripe = i % 2 == 0 })
                end
            else
            for _, d in ipairs(s.members) do
                local e = d.run.entrance
                table.insert(lines, { title = "Entrance", inline = true, titleColor = GREY_C,
                                      text = C.WHITE .. (e and WFL.MapName(e.m) or (d.run.zone or "?")) .. "|r",
                                      point = e and { mapID = e.m, x = e.x, y = e.y, title = d.name .. " entrance" } or nil })
                -- The quests by zone: what to pick up in one city at once. Per quest chain only its next open step;
                -- the name and who gives it (click for the arrow). Grey: you cannot take it yet.
                local list = {}
                for _, g in ipairs(ChainGroups(d)) do
                    local q = g[1]
                    table.insert(list, { q = q, zone = (q.m and q.m > 0) and WFL.MapName(q.m) or "" })
                end
                table.sort(list, function(x, y)
                    if x.zone ~= y.zone then
                        if x.zone == "" or y.zone == "" then return y.zone == "" end
                        return x.zone < y.zone
                    end
                    return (x.q.r or 1) < (y.q.r or 1)
                end)
                local zone, n = nil, 0
                for _, x in ipairs(list) do
                    local q = x.q
                    if x.zone ~= zone then
                        zone, n = x.zone, 0
                        table.insert(lines, { plain = true, gap = 4, icon = "Interface\\Icons\\INV_Misc_Map_01", text = C.GOLD .. (zone ~= "" and zone or "Other") .. "|r" })
                    end
                    n = n + 1
                    local icon, desat, state = WFL.icons.take, false, ""
                    if WFL.InLog(q.id) then
                        icon, desat = WFL.icons.turnin, not WFL.Complete(q.id)
                        state = WFL.Complete(q.id) and (C.GREEN .. "  hand in|r") or (C.GREY .. "  in your log|r")
                    end
                    local later = not WFL.InLog(q.id) and (q.r or 1) > level
                    table.insert(lines, { icon = icon, desat = desat or later, title = q.n, inline = true, titleColor = later and GREY_C or nil,
                                          text = C.GREY .. (q.npc ~= "" and q.npc or "?") .. "|r" .. state,
                                          point = QPoint(q), skipId = q.id, stripe = n % 2 == 0 })
                    -- What to do in the dungeon, once the quest is in your log (no arrow works inside a dungeon).
                    if q.o and WFL.InLog(q.id) and not WFL.Complete(q.id) then
                        table.insert(lines, { text = C.GREY .. q.o .. "|r", stripe = n % 2 == 0 })
                    end
                end
                -- Quests you pick up inside the dungeon (a person, an object or a looted item there): no arrow.
                local ins = {}
                for _, q in ipairs(d.run.inside or {}) do
                    if WFL.ClassFits(q.c) and not WFL.QuestDone(q.id) then table.insert(ins, q) end
                end
                table.sort(ins, function(x, y) return (x.from or 1) < (y.from or 1) end)
                if #ins > 0 then
                    table.insert(lines, { plain = true, gap = 4, text = C.GOLD .. "Inside the dungeon|r" })
                end
                for k, q in ipairs(ins) do
                    local icon, desat, state = WFL.icons.take, false, ""
                    if WFL.InLog(q.id) then
                        icon, desat = WFL.icons.turnin, not WFL.Complete(q.id)
                        state = WFL.Complete(q.id) and (C.GREEN .. "  hand in|r") or (C.GREY .. "  in your log|r")
                    end
                    local later = not WFL.InLog(q.id) and (q.from or 1) > level
                    table.insert(lines, { icon = icon, desat = desat or later, title = q.quest, inline = true, titleColor = later and GREY_C or nil,
                                          text = C.GREY .. (q.kind == "item" and (q.npc ~= "" and q.npc or "an item") .. (q.drop and (", drops from " .. q.drop) or "")
                                                 or (q.npc ~= "" and q.npc or "giver not known"))
                                                 .. (q.after and (", after " .. q.after) or "") .. "|r" .. state, skipId = q.id, stripe = k % 2 == 0 })
                    -- No arrow inside a dungeon, so the task is always shown here (until it is ready to hand in).
                    if q.obj and not WFL.Complete(q.id) then
                        table.insert(lines, { text = C.GREY .. q.obj .. "|r", stripe = k % 2 == 0 })
                    end
                end
            end
            end
        end
    end
        end
    if later > 0 then
        table.insert(lines, { plain = true, gap = 4, text = C.GREY .. later .. " more for later character levels.|r" })
    end
    return lines
end

-- --- Professions tab: one card per profession (redesign 2026-10-22, style A) -----------------------------------
-- Header: profession icon, name, rank, skill bar, a tag (SkillUp / Temporary). Inside: numbered steps with an icon,
-- the place under them and the cost on the right; market and "temporary" notes as coloured boxes; the materials
-- still needed as bars (all characters' bags and banks).

-- Cooking / First Aid: recipes for the materials in your bags that you do not know yet and that still give skill,
-- with where to learn them: the trainer, a recipe vendor, or the source (quest, drop). Up to four (user, 2026-10-22:
-- "I have boar meat, where do I get a recipe to cook it?").
local function BagRecipeRows(prof, rank)
    local rows, seen = {}, {}
    -- Materials this character sends to someone else (personal/team.json "reserved": items, or "Herbalism" for every
    -- herb): no recipe for them (user, 2026-10-24: Peace Tea wanted Kaspin's Peacebloom, which goes to Konan).
    local reserved = {}
    for _, r in ipairs((PLAN.reserved or {})[UnitName("player")] or {}) do
        reserved[r] = true
        for herb in pairs(((PLAN.gatherNodes or {})[r]) or {}) do reserved[herb] = true end
    end
    local list = (PLAN.cookRecipes or {})[prof] or {}
    local names = {}
    for name in pairs(list) do table.insert(names, name) end
    table.sort(names, function(x, y) return (list[x].learn or 0) < (list[y].learn or 0) end)
    for _, name in ipairs(names) do
        local r = list[name]
        if #rows >= 4 then break end
        -- No source: a starter recipe that comes with the profession (Roasted Boar Meat), nothing to fetch.
        local useful = (r.src or "") ~= "" and (not r.grey or rank < r.grey) and (r.learn or 0) <= rank + 50
                       and Knows(prof, name) ~= true
        if useful then
            for mat in pairs(r.r or {}) do
                local have = (not reserved[mat]) and WFL.OwnCount and WFL.OwnCount(mat) or 0
                if (have or 0) > 0 and not seen[name] then
                    seen[name] = true
                    local point, where
                    local src = r.src or ""
                    if src:find("Trainer") then
                        point, where = TrainerWhere(prof)
                        where = "Trainer \194\183 " .. (where or "")
                    elseif src:find("Vendor") and WFL.NearestVendor then
                        local p, w = WFL.NearestVendor("Recipe: " .. name)
                        point, where = p, "Vendor \194\183 " .. (w or "place not known")
                    else
                        where = src
                    end
                    table.insert(rows, { label = "Recipe", text = "Recipe: " .. name, icon = "Interface\\Icons\\INV_Scroll_03",
                                         where = "for your " .. mat .. " (" .. have .. ") \194\183 " .. where
                                                 .. ((r.learn or 0) > rank and (" \194\183 skill " .. r.learn) or ""),
                                         point = point })
                    break
                end
            end
        end
    end
    return rows
end

local function ProfessionTabLines(open)
    open = open or {}
    local lines = {}
    local pa = ProfessionActions()
    if #pa == 0 then return { { text = C.GREY .. "No professions learned yet.|r" } } end
    -- Crafts this character can sell at a profit now (the bank's "Craft to sell" list, user 2026-10-22).
    local me = UnitName("player")
    local okMk, mk = pcall(Market)
    local profit = {}
    for _, c in ipairs(okMk and mk.crafts or {}) do
        if c.who == me then
            profit[c.prof] = profit[c.prof] or {}
            if #profit[c.prof] < 2 then table.insert(profit[c.prof], c) end
        end
    end
    -- Fishing for everyone (user, 2026-10-22): a card to learn it, with a pole, when it is not learned.
    if not WFL.Skills()["Fishing"] then
        local tPoint, tWhere = TrainerWhere("Fishing")
        local pPoint, pWhere
        if WFL.NearestVendor then pPoint, pWhere = WFL.NearestVendor("Fishing Pole") end
        table.insert(pa, { prof = "Fishing", s = { rank = 0, max = 0 }, learn = true, rows = {
            { label = "Learn", text = "Learn Fishing", point = tPoint, where = tWhere },
            { label = "Buy", text = "Fishing Pole", point = pPoint, where = pWhere },
            { label = "Next", text = "Fish while you level, cook the fish for Cooking skill", icon = "Interface\\Icons\\INV_Misc_Food_15" },
        } })
    end
    for ci, a in ipairs(pa) do
        if (a.prof == "Cooking" or a.prof == "First Aid") and not a.learn then
            for _, r in ipairs(BagRecipeRows(a.prof, a.s.rank or 0)) do table.insert(a.rows, r) end
        end
        for _, c in ipairs(profit[a.prof] or {}) do
            local dup = false
            for _, r in ipairs(a.rows) do if r.label == "Profit" and r.text:find(c.recipe, 1, true) then dup = true end end
            if not dup then
                table.insert(a.rows, { label = "Profit", text = "Craft " .. c.recipe .. " to sell", where = "+" .. Money(c.profit) .. " each",
                                       icon = WFL.ItemIcon(c.recipe) })
            end
        end
        local id = "p:" .. a.prof
        local isOpen = open[id]
        if isOpen == nil then isOpen = true end
        local tag = a.temp and "|cffffd27aTemporary|r" or a.su and "|cffb6e39aSkillUp|r" or nil
        local alt = ci % 2 == 0
        local head = { section = id, open = isOpen, card = "head", alt = alt, big = true, icon = ProfIcon(a.prof),
                       title = a.prof, titleColor = alt and ALT_TITLE or { 1, 0.82, 0 }, inline = true,
                       text = (alt and AltText(RankName(a.s.max)) or HeadText(RankName(a.s.max))) .. (tag and ("  " .. (alt and AltText(tag) or tag)) or ""),
                       bar = (not a.learn) and { have = a.s.rank, need = a.s.max, color = SKILL_GREEN } or nil }
        table.insert(lines, head)
        local first = #lines
        if isOpen then
            local n = 0
            for _, r in ipairs(a.rows) do
                if r.text and r.text ~= "" then
                    -- One block per row, like the Team tab: icon, bold text, one grey line under it (what kind of
                    -- step, where, the cost). Market and "temporary" rows by text colour, no boxes.
                    local kind = r.label == "Temporary" and "temp" or r.label == "Market" and (MarketNote(r.text) or "cold") or nil
                    local icon = r.icon or (STEP_ICON[r.label] and ("Interface\\Icons\\" .. STEP_ICON[r.label])) or ProfIcon(a.prof)
                    local detail = Detail(r, r.where, r.cost, r.extra)
                    if kind then
                        table.insert(lines, { card = "body", icon = icon, title = kind ~= "temp" and MarketShort(r.text) or r.text, inline = false,
                                              titleColor = kind == "hot" and SELL_C or kind == "cold" and BUY_C or TEMP_C,
                                              text = C.GREY .. (kind == "temp" and "Temporary" or kind == "hot" and "Sell" or "Buy") .. "|r",
                                              point = r.point, click = r.click })
                    else
                        table.insert(lines, { card = "body", icon = icon, title = r.text, inline = false,
                                              titleColor = r.label == "Buy" and BUY_C or r.label == "Profit" and GREEN_C or { 0.35, 0.18, 0 },
                                              text = C.GREY .. detail .. "|r", point = r.point, click = r.click })
                    end
                end
            end
            -- Materials still needed: SkillUp's route reagents, else our step's.
            local mats = {}
            if a.su then
                for _, r in ipairs(a.su.reagents or {}) do
                    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID)
                    if name then
                        local have = math.max(r.have or 0, WFL.MaterialHave(name) or 0)
                        if have < (r.need or 0) then table.insert(mats, { item = name, have = have, n = r.need, why = a.prof .. ", SkillUp route" }) end
                    end
                end
            else
                local b = a.craft and not a.learn and Bracket(a.prof, a.s.rank)
                if b then
                    for item, n in pairs(StillNeeded(a.prof, a.s.rank, b)) do
                        if n > 0 then table.insert(mats, { item = item, have = WFL.MaterialHave(item), n = n, why = a.prof .. " " .. a.s.rank .. " to " .. b.to }) end
                    end
                    table.sort(mats, function(x, y) return x.n > y.n end)
                end
            end
            if #mats > 0 then
                table.insert(lines, { card = "body", plain = true, text = C.GREY .. "Materials (all characters)|r" })
                for _, m in ipairs(mats) do
                    local l = MatLine(m.item, m.have, m.n, { m.item, m.why, "Have = all characters' bags and banks" })
                    l.card = "body"
                    table.insert(lines, l)
                end
            end
        end
        lines[#lines].cardEnd = true
        if #lines > first then lines[#lines].card = "foot" end
    end
    return Stripe(lines)
end

local function TeamTabLines(open)
    open = open or {}
    local lines, team = {}, Team()
    if Section(lines, "t-l", open, "Rotation", "", "Interface\\Icons\\INV_Misc_GroupLooking") then
        for _, t in ipairs(team) do
            local c, profs = t.c, {}
            for _, p in ipairs(c.professions or {}) do table.insert(profs, p.name .. " " .. (p.rank or 0)) end
            table.insert(lines, { icon = ClassIcon(c.class), title = c.name .. (t.me and " (you)" or ""), inline = false,
                                  text = C.GREY .. "character level " .. (c.level or "?") .. ", rested " .. Pct(t.rested) .. ", " .. (t.me and "playing" or (c.resting and "in an inn" or "outside"))
                                         .. (#profs > 0 and ("\n" .. table.concat(profs, ", ")) or "") .. "|r",
                                  titleColor = (not t.me and t.rested >= 0.3) and GREEN_C or nil })
        end
    end
    local need, rows = TeamNeed(), {}
    for item, v in pairs(need) do table.insert(rows, { item = item, n = v.n, by = v.by }) end
    table.sort(rows, function(a, b) return a.n > b.n end)
    if Section(lines, "t-m", open, "Team materials", "", "Interface\\Icons\\INV_Misc_Bag_10") then
        if #rows == 0 then table.insert(lines, { text = C.GREY .. "No crafter has learned a profession yet.|r" }) end
        for _, r in ipairs(rows) do table.insert(lines, MatLine(r.item, WFL.MaterialHave(r.item), r.n, { r.item, "For: " .. table.concat(r.by, ", ") })) end
    end
    local ls = LegacyStatus()
    -- Folded by default (user, 2026-10-24: about 40 lines that rarely change); the summary keeps the count.
    if Section(lines, "t-g", open, "Legacy points", ls.got .. " of " .. ls.total, "Interface\\Icons\\INV_Misc_Book_08", false) then
        LegacyLines(lines)
    end
    return lines
end

local function MarketTabLines(open)
    open = open or {}
    local lines, mk = {}, Market()
    local total = 0
    for _, x in ipairs(mk.sell) do total = total + x.value end
    if Section(lines, "m-s", open, "Sell now", (#mk.sell > 0 and (#mk.sell .. " \194\183 about " .. Money(total)) or "none"), "Interface\\Icons\\INV_Misc_Coin_02", nil, "sell") then
        if #mk.sell == 0 then table.insert(lines, { text = C.GREY .. "Nothing to sell now.|r" }) end
        for i = 1, math.min(10, #mk.sell) do
            local x = mk.sell[i]
            local note = x.state == "hot" and HOT or "" -- (no "buy N back later": user, 2026-10-22)
            table.insert(lines, { titleColor = SELL_C, icon = WFL.ItemIcon(x.item), item = x.item, title = x.extra .. " " .. x.item, inline = true,
                                  text = C.GREY .. "at " .. Money(x.now) .. "|r  " .. note .. (FewListed(x.item) and (C.GREY .. "  few listed: check the price|r") or ""),
                                  tip = { x.item, x.why or ("AH now " .. Money(x.now)), "Vendor " .. Money(VendorPrice(x.item)) } })
        end
    end
    if Section(lines, "m-b", open, "Buy cheap", (#mk.buy > 0 and tostring(#mk.buy) or "none"), "Interface\\Icons\\INV_Misc_Bag_10", nil, "buy") then
        if #mk.buy == 0 then table.insert(lines, { text = C.GREY .. "Nothing cheap now.|r" }) end
        for i = 1, math.min(8, #mk.buy) do
            local x = mk.buy[i]
            table.insert(lines, { titleColor = BUY_C, icon = WFL.ItemIcon(x.item), item = x.item, title = x.short .. " " .. x.item, inline = true,
                                  text = C.GREY .. "at " .. Money(x.now) .. " = " .. Money(x.cost) .. "|r", tip = { x.item, x.why } })
        end
    end
    if Section(lines, "m-c", open, "Craft to sell", (#mk.crafts > 0 and tostring(#mk.crafts) or "none"), "Interface\\Icons\\Trade_BlackSmithing", nil, "craft") then
        if #mk.crafts == 0 then table.insert(lines, { text = C.GREY .. "No profitable craft now.|r" }) end
        for i = 1, math.min(6, #mk.crafts) do
            local x = mk.crafts[i]
            table.insert(lines, { titleColor = GREEN_C, icon = WFL.ItemIcon(x.recipe), item = x.recipe, title = x.recipe, inline = true, text = C.GREY .. x.who .. ": +" .. Money(x.profit) .. " each" .. (((PLAN.prices or {})[x.recipe] or {}).qtyUsual and ((PLAN.prices or {})[x.recipe].qtyUsual < 5) and ", small market: sell a few" or "") .. "|r",
                                  tip = { x.recipe, "Sells at " .. Money(x.sellAt), "Materials " .. Money(x.cost) .. " at AH prices" } })
        end
    end
    if #mk.hold > 0 and Section(lines, "m-h", open, "Hold", #mk.hold .. " flooded now, sell later", "Interface\\Icons\\INV_Misc_Note_01", false, "hold") then
        for _, x in ipairs(mk.hold) do
            table.insert(lines, { icon = WFL.ItemIcon(x.item), item = x.item, title = x.extra .. " " .. x.item, inline = true, text = C.GREY .. x.why .. "|r" })
        end
    end
    return lines
end

WFL.title = "WoW Forever Planner"
WFL.RegisterTabs({
    { key = "next", label = "Next", lines = function(open) return Cardify(NextTabLines(open)) end },
    { key = "dg", label = "Dungeons", lines = function(open) return Cardify(DungeonTabLines(open)) end, visible = NotBank },
    { key = "prof2", label = "Professions", lines = ProfessionTabLines, visible = NotBank },
    { key = "market", label = "Market", lines = function(open) return Cardify(MarketTabLines(open)) end, visible = IsBank },
    { key = "team", label = "Team", lines = function(open) return Cardify(TeamTabLines(open)) end },
})

-- Alerts (user, 2026-10-24/26): a big alert (Alert.lua: WFL_Alert, also a chat line) for each thing on the Next
-- tab whose condition is met, once per character:
--   * a step of "Your plan": its "alert" (personal/team.json: money, lacks / has a profession, noItem, skill
--     {profession, rank}) or, without one, reaching its character level;
--   * a new profession rank you can train (skill, character level and the money when the cost is known);
--   * new herbs or ores your Herbalism / Mining skill can gather (Plan.lua gatherNodes);
--   * a rare worth hunting for you (Plan.lua rares);
--   * a dungeon chain whose quests are due ("Collect the Dungeon chain 1 quests");
--   * on a level-up, the dungeon quests that open at the new character level.
-- The first check on a character only marks what is already due, so nothing floods at login.
-- /wflp alerts turns them off and on; /wflp alert shows a test.
local function QueueAlert(st) WFL_Alert(st.text, st.where, st.icon) end

local function AlertDue(st, level, money, skills)
    if level < (st.from or 1) then return false end
    local a = st.alert
    if not a then return not st.to and (st.from or 1) > 1 end
    if a.money and money < a.money then return false end
    if a.lacks and skills[a.lacks] then return false end
    if a.has and not skills[a.has] then return false end
    if a.noItem and (WFL.OwnCount(a.noItem) or 0) > 0 then return false end
    if a.skill then
        local s = skills[a.skill[1]]
        if not s or (s.rank or 0) < a.skill[2] then return false end
    end
    return true
end

-- The dungeon quests that open exactly at this character level, grouped by dungeon: "5 new dungeon quests", text.
local function NewDungeonQuests(level)
    local byDungeon, order, count = {}, {}, 0
    for _, d in ipairs(WFL.DungeonEntries(level)) do
        for _, q in ipairs(d.quests or {}) do
            if (q.from or 1) == level and not WFL.QuestDone(q.id) then
                if not byDungeon[d.name] then byDungeon[d.name] = {}; table.insert(order, d.name) end
                table.insert(byDungeon[d.name], q.quest)
                count = count + 1
            end
        end
    end
    return count, order
end

local function CheckAlerts(newLevel)
    local s = WFL.Settings()
    local path = (PLAN.paths or {})[UnitName("player")] or {}
    if s.alertsOff then return end
    s.alertsDone = s.alertsDone or {}
    local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
    local first = s.alertsDone[key] == nil
    local done = s.alertsDone[key] or {}
    s.alertsDone[key] = done
    local function Once(id, alert)
        if done[id] then return end
        done[id] = true
        if not first then QueueAlert(alert) end
    end
    -- PLAYER_LEVEL_UP comes before UnitLevel changes: take the event's level.
    local level = math.max(tonumber(newLevel) or 0, UnitLevel("player") or 1)
    local money = (GetMoney and GetMoney()) or 0
    local skills = WFL.Skills() or {}
    for _, st in ipairs(path) do
        if not done[st.text] and AlertDue(st, level, money, skills) then Once(st.text, st) end
    end
    for prof, sk in pairs(skills) do
        -- A new rank to train.
        local t = NextRank(prof, sk)
        if t and sk.rank >= t.skill and level >= (t.level or 0) then
            local cost = ((PLAN.profCosts or {})[prof] or {})[t.name]
            if not cost or money >= cost then
                local p = WFL.TrainerPoint and WFL.TrainerPoint(prof, true)
                Once("rank:" .. prof .. ":" .. t.name, { text = "Train " .. t.name .. " " .. prof .. RankCost(prof, t.name) .. ".",
                     where = p and (p.npc .. ", " .. WFL.MapName(p.mapID)) or nil, icon = ProfIcon(prof) })
            end
        end
        -- New herbs or ores: one alert per skill step ("You can now gather Mageroyal and Swiftthistle").
        local nodes = (PLAN.gatherNodes or {})[prof]
        if nodes then
            local bySkill = {}
            for node, need in pairs(nodes) do
                if need > 1 and sk.rank >= need then bySkill[need] = bySkill[need] or {}; table.insert(bySkill[need], node) end
            end
            for need, list in pairs(bySkill) do
                table.sort(list)
                Once("gather:" .. prof .. ":" .. need, { text = "You can now gather " .. table.concat(list, " and ") .. ".",
                     where = prof .. " skill " .. need, icon = ProfIcon(prof) })
            end
        end
    end
    -- A rare worth hunting for you (from 2 character levels below it, until you own the item).
    for _, r in ipairs(MyRares(level)) do
        Once("rare:" .. r.npc .. ":" .. r.item, { text = "Rare: kill " .. r.npc .. " for " .. r.item .. ".", where = RareWhere(r),
             icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" })
    end
    -- A dungeon chain whose quests are due (the Next tab's "Character level 11: collect ..." line).
    for _, st in ipairs(Stops(level)) do
        if st.chain and level >= st.at - 2 then
            local names = {}
            for _, m in ipairs(st.members) do table.insert(names, m.name) end
            Once("chain:" .. st.name, { text = "Collect the " .. st.name .. " quests: " .. table.concat(names, ", ") .. ".",
                 where = "Dungeons tab", icon = "Interface\\Icons\\INV_Misc_Key_14" })
        end
    end
    -- New dungeon quests at this character level (was a small yellow line, user 2026-10-26: big alerts only).
    if newLevel then
        local count, order = NewDungeonQuests(level)
        if count > 0 then
            Once("quests:" .. level, { text = count .. " new dungeon quest" .. (count > 1 and "s" or "") .. ": " .. table.concat(order, ", ") .. ".",
                 where = "Dungeons tab", icon = "Interface\\Icons\\INV_Misc_Key_14" })
        end
    end
end

local alerts = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
    pcall(alerts.RegisterEvent, alerts, ev)
end
alerts:SetScript("OnEvent", function(_, event, arg1)
    local run = function()
        local ok, err = pcall(CheckAlerts, event == "PLAYER_LEVEL_UP" and arg1 or nil)
        if not ok and WoWForeverLevelerLog then
            table.insert(WoWForeverLevelerLog, date("%Y-%m-%d %H:%M:%S") .. "  Planner error alerts: " .. tostring(err))
        end
    end
    -- At login the skills and bags are not ready at once.
    if event == "PLAYER_ENTERING_WORLD" and C_Timer then C_Timer.After(5, run) else run() end
end)

-- For /wflp alert and /wflp alerts (UI.lua).
function WFL_TestAlert()
    WFL_Alert("When you have 20c: learn Skinning (10c) and buy a Skinning Knife (10c).", "Test alert")
end
function WFL_ToggleAlerts()
    local s = WFL.Settings()
    s.alertsOff = not s.alertsOff
    print("|cffffd100WoW Forever Planner:|r alerts " .. (s.alertsOff and "off" or "on"))
end

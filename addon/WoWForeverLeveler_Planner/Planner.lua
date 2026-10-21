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
local function Pair(lines, now, after, point, where)
    table.insert(lines, { title = "Now", inline = true, text = C.WHITE .. now .. "|r", titleColor = GREEN_C, point = point })
    if where and where ~= "" then table.insert(lines, { text = C.GREY .. where .. "|r" }) end
    if after and after ~= "" then table.insert(lines, { title = "After", inline = true, text = C.GREY .. after .. "|r", titleColor = GREY_C }) end
end

-- Labelled rows, one per line: { label, text, point, where }. The first label is green, the others grey; a
-- "where" (trainer, vendor) goes on its own grey line under its row.
local function Rows(lines, rows)
    for i, r in ipairs(rows) do
        if r.text and r.text ~= "" then
            table.insert(lines, { title = r.label, inline = true, text = (i == 1 and C.WHITE or C.GREY) .. r.text .. "|r",
                                  titleColor = i == 1 and GREEN_C or GREY_C, point = r.point, click = r.click })
            if r.where and r.where ~= "" then table.insert(lines, { text = C.GREY .. r.where .. "|r", point = r.point, click = r.click }) end
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
        table.insert(acts, { text = "Level " .. (st.at - 2) .. ": collect the " .. st.name .. " quests" })
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
                table.insert(acts, { text = "Hand in " .. q.n .. " to " .. q.npc, where = Zone(q.m), point = QPoint(q) })
            elseif WFL.InLog(q.id) then
                table.insert(acts, { text = "Finish " .. q.n, where = "then " .. q.npc .. ", " .. Zone(q.m), point = QPoint(q) })
            elseif (q.r or 1) <= level then
                table.insert(acts, { text = "Take " .. q.n .. " from " .. q.npc, where = Zone(q.m), point = QPoint(q) })
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
local function TrainerWhere(prof)
    local p = WFL.TrainerPoint and WFL.TrainerPoint(prof)
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
    if level < (t.level or 0) then table.insert(need, "level " .. t.level) end
    return t.name .. RankCost(prof, t.name) .. " at " .. table.concat(need, ", "), false
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
    if q then return { label = "Learn", text = item .. ": quest " .. q.n .. (q.level and (" (level " .. q.level .. ")") or "") } end
    return { label = "Learn", text = item .. ": " .. string.lower(l.source or "") .. ", where not known yet" }
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

local function SkillUpRows(entry, api)
    local rows = {}
    for i, st in ipairs(entry.steps or {}) do
        local click
        if st.nav then
            click = function() WFL.ClearArrows(); api.Navigate(entry.skillLineID, i) end
        elseif st.kind == "craft" then
            click = function() api.OpenRecipes(entry.skillLineID) end
        end
        table.insert(rows, { label = SU_LABEL[st.kind] or "Next", text = st.text, where = st.detail, click = click })
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
            table.insert(acts, { prof = prof, s = { rank = 0, max = 0 }, learn = true, craft = CRAFTS[prof], gather = GATHER[prof] and true, rows = {
                { label = "Learn", text = prof .. RankCost(prof, "Apprentice") .. (drop and (", after you drop " .. drop) or ""), point = point, where = where },
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
        local tPoint, tWhere = TrainerWhere(prof)
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
            local de = st.de and st.de > 0 and ("disenchant (" .. Money(st.de) .. ")") or nil
            local sells = st.sell and (" · sells " .. Money(st.sell) .. ", sell at most 10" .. (de and (", then " .. de) or ""))
                          or (de and (" · " .. de) or "")
            if s.rank < goal then
                local learn = LearnRow(prof, st)
                if learn then table.insert(rows, learn) end
                table.insert(rows, { label = "Make", text = CraftsLeft(st, math.max(s.rank, st.from), goal) .. " " .. st.recipe .. " to " .. goal .. sells })
            end
            if nx and nx.from < s.max then
                local g2 = math.min(nx.to, s.max)
                table.insert(rows, { label = "Then", text = CraftsLeft(nx, nx.from, g2) .. " " .. nx.recipe .. " to " .. g2 })
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
            table.insert(a.rows, 1, { label = "Temporary", text = goal and ("drop it when you reach the " .. goal .. " trainer (" .. where .. "); mail what you gathered first")
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
    return { icon = WFL.ItemIcon(item), text = C.WHITE .. item .. "|r" .. (have > need and (" " .. C.GREEN .. "sell " .. (have - need) .. "|r") or ""),
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
    local q = (p.qty and p.qtyUsual and p.qtyUsual > 0) and (p.qty / p.qtyUsual) or 1
    local why = Money(now) .. ", usual " .. Money(p.usual) .. (p.qty and (", " .. p.qty .. " listed") or "")
    if ratio >= 1.25 or q <= 0.5 then return "hot", why, now end
    if ratio <= 0.75 or q >= 2 then return "flooded", why, now end
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
local function Section(lines, id, open, title, summary, icon, default)
    local isOpen = open[id]
    if isOpen == nil then isOpen = default ~= false end
    table.insert(lines, { section = id, icon = icon, open = isOpen, title = title, inline = true, text = C.GREY .. (summary or "") .. "|r" })
    return isOpen
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
    table.insert(lines, { plain = true, text = C.GOLD .. "Levels|r" .. C.GREY .. "  first of each class, 1 point each|r" })
    for _, cl in ipairs(CLASS_ORDER) do
        table.insert(lines, { title = ClassName(cl), inline = true, titleColor = GREY_C, text = Marks(st.levels[cl], { 25, 45, 60 }) })
    end
    table.insert(lines, { plain = true, text = C.GOLD .. "Crafting|r" .. C.GREY .. "  any character, 1 point each|r" })
    local names = {}
    for prof in pairs(CRAFTS) do table.insert(names, prof) end
    table.sort(names)
    for _, prof in ipairs(names) do
        table.insert(lines, { title = prof, inline = true, titleColor = GREY_C, text = Marks(st.crafts[prof], { 150, 225, 300 }) })
    end
    if PLAN.spelunker and PLAN.spelunker[1] then
        table.insert(lines, { plain = true, text = C.GOLD .. "Dungeons|r" .. C.GREY .. "  clear each dungeon of a tier once, 1 point per tier|r" })
        for _, t in ipairs(PLAN.spelunker) do
            table.insert(lines, { title = t.name, inline = false, titleColor = GREY_C, text = C.GREY .. table.concat(t.dungeons, ", ") .. "|r" })
        end
    end
    table.insert(lines, { text = C.GREY .. "Quests, exploring, PvP and raids: see the game's Legacy panel (Y).|r" })
end

local function NextLeveling(open)
    local lines, level, zone = {}, UnitLevel("player") or 1, GetRealZoneText() or ""
    local acts, st = DungeonActions(level, zone)
    if Section(lines, "n-d", open, "Dungeons", st and st.name or "nothing for your level", "Interface\\Icons\\INV_Misc_Key_14") then
        if acts[1] then
            Pair(lines, acts[1].text, acts[2] and (acts[2].text .. (acts[2].where and (" (" .. acts[2].where .. ")") or "")), acts[1].point, acts[1].where)
        else
            table.insert(lines, { text = C.GREY .. "No dungeon quests open for level " .. level .. ".|r" })
        end
    end
    -- Only the main professions here (crafting and gathering); Cooking, First Aid and Fishing are on the Professions tab.
    local pa = {}
    for _, a in ipairs(ProfessionActions()) do if a.craft or a.gather then table.insert(pa, a) end end
    local names = {}
    for _, a in ipairs(pa) do table.insert(names, a.prof .. " " .. (a.learn and "(learn)" or a.s.rank)) end
    if Section(lines, "n-p", open, "Professions", #names > 0 and table.concat(names, ", ") or "none yet", "Interface\\Icons\\Trade_BlackSmithing") then
        if #pa == 0 then table.insert(lines, { text = C.GREY .. "No professions learned yet.|r" }) end
        for _, a in ipairs(pa) do
            table.insert(lines, { plain = true, text = C.GOLD .. a.prof .. " " .. (a.learn and "not learned" or (a.s.rank .. "/" .. a.s.max)) .. "|r" })
            Rows(lines, a.rows)
        end
    end
    if Section(lines, "n-t", open, "Team", "", "Interface\\Icons\\INV_Misc_GroupLooking") then TeamPair(lines) end
    -- Legacy: this character's next point (level, then crafting), only when nobody on the account has it yet.
    local st, rows = LegacyStatus(), {}
    local _, classFile = UnitClass("player")
    for _, l in ipairs({ 25, 45, 60 }) do
        if (st.levels[classFile or ""] or 0) < l then table.insert(rows, { label = "Level", text = l .. ": first " .. ClassName(classFile) .. " there" }) break end
    end
    for prof in pairs(WFL.Skills()) do
        if CRAFTS[prof] then
            for _, c in ipairs({ 150, 225, 300 }) do
                if (st.crafts[prof] or 0) < c then table.insert(rows, { label = "Craft", text = prof .. " " .. c }) break end
            end
        end
    end
    if Section(lines, "n-l", open, "Legacy points", st.got .. " of " .. st.total .. " (Team tab)", "Interface\\Icons\\INV_Misc_Book_08") then
        if rows[1] then Rows(lines, rows) else table.insert(lines, { text = C.GREY .. "Nothing left for this character.|r" }) end
    end
    return lines
end

local function NextBank(open)
    local lines, mk = {}, Market()
    if Section(lines, "b-m", open, "Market", "scan the AH with Auctionator first", "Interface\\Icons\\INV_Misc_Coin_02") then
        local s0, s1, b0, c0 = mk.sell[1], mk.sell[2], mk.buy[1], mk.crafts[1]
        Pair(lines, s0 and ("Sell " .. s0.extra .. " " .. s0.item .. " at " .. Money(s0.now) .. (s0.state == "hot" and " (hot)" or "")) or "Nothing to sell now",
             b0 and ("Buy " .. b0.short .. " " .. b0.item .. " (" .. b0.why .. ")")
             or (s1 and ("Sell " .. s1.extra .. " " .. s1.item .. " (" .. Money(s1.value) .. ")")))
        if c0 then table.insert(lines, { title = "Craft", inline = true, titleColor = GREY_C, text = C.GREY .. c0.who .. ": " .. c0.recipe .. " +" .. Money(c0.profit) .. " each|r" }) end
    end
    if Section(lines, "b-mail", open, "Mail", "", "Interface\\Icons\\INV_Letter_15") then
        local crafters = {}
        for _, t in ipairs(Team()) do
            for _, p in ipairs(t.c.professions or {}) do if CRAFTS[p.name] then table.insert(crafters, t.c.name) break end end
        end
        local newMail = HasNewMail and HasNewMail()
        Pair(lines, newMail and "Collect the mail: new mail is waiting" or "Mailbox checked: nothing new",
             #crafters > 0 and ("Send each crafter their step's materials: " .. table.concat(crafters, ", ")) or nil)
    end
    if Section(lines, "n-t", open, "Team", "", "Interface\\Icons\\INV_Misc_GroupLooking") then TeamPair(lines) end
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
    local stops = Stops(level)
    if #stops == 0 then return { { text = C.GREY .. "No dungeon quests open for level " .. level .. ".|r" } } end
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
    for si = 1, #ordered do
        local s = ordered[si]
        if first[true] == s then table.insert(lines, { plain = true, text = C.GOLD .. "Dungeon chains|r" .. C.GREY .. "  dungeons to run one after another|r" }) end
        if first[false] == s then table.insert(lines, { plain = true, text = C.GOLD .. "Dungeons|r" .. C.GREY .. "  each on its own, all its quests|r" }) end
        local due = level >= s.at
        -- Folded line: when the quests open and the run levels of its dungeons.
        local lo, hi = 99, 0
        for _, m in ipairs(s.members) do lo = math.min(lo, m.run.runFrom or 99); hi = math.max(hi, m.run.runTo or 0) end
        -- "lvl: 15-16": when to run it, with all its quests in hand (green when you are there).
        -- Joined with no-break spaces, so a narrow window moves it under the name whole instead of splitting it.
        local range = hi > 0 and (math.max(s.at, lo) .. "-" .. hi) or tostring(s.at)
        local summary = ((due and C.GREEN or "") .. "lvl: " .. range .. (due and "|r" or "")):gsub(" ", "\194\160")
        if Section(lines, "d:" .. s.name, open, s.name, summary, "Interface\\Icons\\INV_Misc_Key_14", si == 1) then
            if s.chain then
                -- A chain: only the dungeons in run order, with entrances. Where to pick up the quests is in each
                -- dungeon's own section (user, 2026-10-21: a chain's full quest list is too long, levels differ).
                table.insert(lines, { plain = true, text = C.GOLD .. "Run in this order|r" })
                for i, d in ipairs(s.members) do
                    local e = d.run.entrance
                    table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_Key_03", title = i .. ". " .. d.name, inline = false,
                                          text = C.GREY .. "lvl: " .. d.run.runFrom .. "-" .. d.run.runTo .. ", entrance " .. (e and Zone(e.m) or (d.run.zone or "?")) .. "|r",
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
                        table.insert(lines, { plain = true, gap = 4, text = C.GOLD .. (zone ~= "" and zone or "Other") .. "|r" })
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
    return lines
end

local function ProfessionTabLines(open)
    open = open or {}
    local lines = {}
    local pa = ProfessionActions()
    if #pa == 0 then return { { text = C.GREY .. "No professions learned yet.|r" } } end
    for _, a in ipairs(pa) do
        if Section(lines, "p:" .. a.prof, open, a.prof .. " " .. (a.learn and "not learned" or (a.s.rank .. "/" .. a.s.max)), "", nil) then
            Rows(lines, a.rows)
            local b = a.craft and not a.learn and not a.su and Bracket(a.prof, a.s.rank)
            if a.su and #(a.su.reagents or {}) > 0 then
                -- SkillUp's route reagents; have = all characters' bags and banks (mail them over).
                table.insert(lines, { plain = true, text = C.GREY .. "Materials still needed (SkillUp Forever route)|r" })
                for _, r in ipairs(a.su.reagents) do
                    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID)
                    if name then
                        local have = math.max(r.have or 0, WFL.MaterialHave(name) or 0)
                        if have < (r.need or 0) then
                            table.insert(lines, MatLine(name, have, r.need, { name, a.prof .. ", SkillUp route", "Have = all characters' bags and banks" }))
                        end
                    end
                end
            end
            if b then
                table.insert(lines, { plain = true, text = C.GREY .. "Materials still needed to " .. b.to .. "|r" })
                local items = {}
                for item, n in pairs(StillNeeded(a.prof, a.s.rank, b)) do if n > 0 then table.insert(items, { item = item, n = n }) end end
                table.sort(items, function(x, y) return x.n > y.n end)
                for _, x in ipairs(items) do
                    table.insert(lines, MatLine(x.item, WFL.MaterialHave(x.item), x.n, { x.item, a.prof .. " " .. a.s.rank .. " to " .. b.to, "Have = all characters' bags and banks" }))
                end
            end
        end
    end
    return lines
end

local function TeamTabLines(open)
    open = open or {}
    local lines, team = {}, Team()
    if Section(lines, "t-l", open, "Rotation", "most rested first", "Interface\\Icons\\INV_Misc_GroupLooking") then
        for _, t in ipairs(team) do
            local c, profs = t.c, {}
            for _, p in ipairs(c.professions or {}) do table.insert(profs, p.name .. " " .. (p.rank or 0)) end
            table.insert(lines, { title = c.name .. (t.me and " (you)" or ""), inline = false,
                                  text = C.GREY .. "level " .. (c.level or "?") .. ", rested " .. Pct(t.rested) .. ", " .. (t.me and "playing" or (c.resting and "in an inn" or "outside"))
                                         .. (#profs > 0 and ("\n" .. table.concat(profs, ", ")) or "") .. "|r",
                                  titleColor = (not t.me and t.rested >= 0.3) and GREEN_C or nil })
        end
    end
    local need, rows = TeamNeed(), {}
    for item, v in pairs(need) do table.insert(rows, { item = item, n = v.n, by = v.by }) end
    table.sort(rows, function(a, b) return a.n > b.n end)
    if Section(lines, "t-m", open, "Team materials", "what the crafters need now", "Interface\\Icons\\INV_Misc_Bag_10") then
        table.insert(lines, { text = C.GREY .. "Mail these to the bank. Bar: have / need.|r" })
        if #rows == 0 then table.insert(lines, { text = C.GREY .. "No crafter has learned a profession yet.|r" }) end
        for _, r in ipairs(rows) do table.insert(lines, MatLine(r.item, WFL.MaterialHave(r.item), r.n, { r.item, "For: " .. table.concat(r.by, ", ") })) end
    end
    local ls = LegacyStatus()
    if Section(lines, "t-g", open, "Legacy points", ls.got .. " of " .. ls.total .. " from levels and crafting", "Interface\\Icons\\INV_Misc_Book_08") then
        LegacyLines(lines)
    end
    return lines
end

local function MarketTabLines(open)
    open = open or {}
    local lines, mk = {}, Market()
    table.insert(lines, { text = C.GREY .. "Each item against its own usual price and amount listed (Sync scans).|r" })
    local total = 0
    for _, x in ipairs(mk.sell) do total = total + x.value end
    if Section(lines, "m-s", open, "Sell now", #mk.sell .. " items, about " .. Money(total), "Interface\\Icons\\INV_Misc_Coin_02") then
        if #mk.sell == 0 then table.insert(lines, { text = C.GREY .. "Nothing to sell now.|r" }) end
        for i = 1, math.min(10, #mk.sell) do
            local x = mk.sell[i]
            local note = x.state == "hot" and (C.GREEN .. "hot|r" .. C.GREY .. (x.needed and x.needed > 0 and (", buy " .. x.needed .. " back later") or "") .. "|r") or ""
            table.insert(lines, { icon = WFL.ItemIcon(x.item), item = x.item, title = x.extra .. " " .. x.item, inline = true,
                                  text = C.GREY .. "at " .. Money(x.now) .. "|r  " .. note .. (FewListed(x.item) and (C.GREY .. "  few listed: check the price|r") or ""),
                                  tip = { x.item, x.why or ("AH now " .. Money(x.now)), "Vendor " .. Money(VendorPrice(x.item)) } })
        end
    end
    if Section(lines, "m-b", open, "Buy cheap", #mk.buy .. " the crafters need", "Interface\\Icons\\INV_Misc_Bag_10") then
        if #mk.buy == 0 then table.insert(lines, { text = C.GREY .. "Nothing the crafters need is cheap now.|r" }) end
        for i = 1, math.min(8, #mk.buy) do
            local x = mk.buy[i]
            table.insert(lines, { icon = WFL.ItemIcon(x.item), item = x.item, title = x.short .. " " .. x.item, inline = true,
                                  text = C.GREY .. "at " .. Money(x.now) .. " = " .. Money(x.cost) .. "|r", tip = { x.item, x.why } })
        end
    end
    if Section(lines, "m-c", open, "Craft to sell", #mk.crafts .. " with profit now", "Interface\\Icons\\Trade_BlackSmithing") then
        if #mk.crafts == 0 then table.insert(lines, { text = C.GREY .. "No craft of the team sells above its materials now.|r" }) end
        for i = 1, math.min(6, #mk.crafts) do
            local x = mk.crafts[i]
            table.insert(lines, { icon = WFL.ItemIcon(x.recipe), item = x.recipe, title = x.recipe, inline = true, text = C.GREY .. x.who .. ": +" .. Money(x.profit) .. " each, sell at most 10|r",
                                  tip = { x.recipe, "Sells at " .. Money(x.sellAt), "Materials " .. Money(x.cost) .. " at AH prices" } })
        end
    end
    if #mk.hold > 0 and Section(lines, "m-h", open, "Hold", #mk.hold .. " flooded now, sell later", "Interface\\Icons\\INV_Misc_Note_01", false) then
        for _, x in ipairs(mk.hold) do
            table.insert(lines, { icon = WFL.ItemIcon(x.item), item = x.item, title = x.extra .. " " .. x.item, inline = true, text = C.GREY .. x.why .. "|r" })
        end
    end
    return lines
end

WFL.title = "WoW Forever Planner"
WFL.RegisterTabs({
    { key = "next", label = "Next", lines = NextTabLines },
    { key = "dg", label = "Dungeons", lines = DungeonTabLines, visible = NotBank },
    { key = "prof2", label = "Professions", lines = ProfessionTabLines, visible = NotBank },
    { key = "market", label = "Market", lines = MarketTabLines, visible = IsBank },
    { key = "team", label = "Team", lines = TeamTabLines },
})

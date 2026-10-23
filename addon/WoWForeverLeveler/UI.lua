-- WoW Forever Leveler: the in-game panel. A small, movable, resizable window with what this character should
-- do now (train, cook, first aid, gather, fish, camp), from its live skills, level and zone and the guide data
-- in Plan.lua. A minimap button shows and hides it; /wflp does too. The search box finds recipes, materials and
-- zones in the guide data. Settings: WoWForeverLevelerUI = { shown, point, x, y, w, h, angle, font }.

local PLAN = WoWForeverLevelerPlan or {}
local Refresh -- the window's redraw, defined further down
local FindVendor -- the vendor search, defined further down (a click on a material line uses it)
local SECONDARY = { "First Aid", "Cooking", "Fishing" }
-- Quest-dialog theme: the quest window's parchment with its own text colors, read from the game's quest fonts
-- (QuestFont for text, QuestTitleFont for titles); fixed parchment colors if a font object is missing.
-- GOLD = topic titles, WHITE = normal text (names kept from the first, dark theme).
local function FontHex(fontName, fallback)
    local f = _G[fontName]
    if f and f.GetTextColor then
        local r, g, b = f:GetTextColor()
        if r then return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
    end
    return fallback
end
local GOLD = FontHex("QuestTitleFont", "|cff5a2d00")
local WHITE = FontHex("QuestFont", "|cff2b1d0e")
local GREY, GREEN = "|cff6e5a3c", "|cff1e7a1e"

local function Settings()
    WoWForeverLevelerUI = WoWForeverLevelerUI or { shown = true, w = 340, h = 300, angle = 200, font = 13 }
    return WoWForeverLevelerUI
end

-- Profession name -> { rank, max } for every profession the character knows (primary and secondary).
local function Skills()
    local out = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not isHeader then out[name] = { rank = rank or 0, max = maxRank or 0 } end
        end
    end
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            if idx then
                local name, _, rank, maxRank = GetProfessionInfo(idx)
                if name then out[name] = { rank = rank or 0, max = maxRank or 0 } end
            end
        end
    end
    return out
end

-- Auctionator's last price for an item name (copper), or nil without a scan / without Auctionator.
local function PriceByName(name)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemName) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemName, "WoWForeverLeveler", name)
    return ok and price or nil
end

local function CopperText(c)
    c = math.floor((c or 0) + 0.5)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then table.insert(out, g .. "g") end
    if sv > 0 then table.insert(out, sv .. "s") end
    if cu > 0 or #out == 0 then table.insert(out, cu .. "c") end
    return table.concat(out, " ")
end

local function StepFor(list, rank)
    for _, s in ipairs(list or {}) do
        if rank >= s.from and rank < s.to then return s end
    end
    if rank < 1 and list and list[1] then return list[1] end
end

-- The continent a map belongs to (TomTom only draws an arrow to points on your own continent).
local function Continent(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local info = mapID and C_Map.GetMapInfo(mapID)
    for _ = 1, 10 do
        if not info then return nil end
        if info.mapType == 2 then return info.mapID end -- Enum.UIMapType.Continent
        info = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
    end
end

-- The nearest trainer for this profession: what this client saw (WoWForeverLevelerNPCs), then the guide's list
-- (Plan.lua: every client plus ClassicDB). On your map the closest one wins; else one on your continent.
-- Trainers on another continent are left out: TomTom draws no arrow there.
local function TrainerPoint(prof)
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local continent = Continent(here)
    local px, py
    if here and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(here, "player")
        if pos then px, py = pos:GetXY(); px, py = px * 100, py * 100 end
    end
    local list = {}
    for name, n in pairs(WoWForeverLevelerNPCs or {}) do list[name] = n end
    for _, t in ipairs(PLAN.trainers or {}) do
        local n = list[t.name]
        if not n or not n.profession then list[t.name] = { kind = "trainer", profession = t.profession, mapID = t.mapID, x = t.x, y = t.y } end
    end
    local best, bestDist, other
    for name, n in pairs(list) do
        if n.kind == "trainer" and n.profession == prof and n.mapID and n.x then
            local point = { mapID = n.mapID, x = n.x, y = n.y, title = name .. " (" .. prof .. ")", npc = name }
            if n.mapID == here then
                local d = px and ((n.x - px) ^ 2 + (n.y - py) ^ 2) or 0
                if not bestDist or d < bestDist then best, bestDist = point, d end
            elseif continent and Continent(n.mapID) == continent then
                other = other or point
            end
        end
    end
    return best or other
end

-- A named trainer's map spot. The name may carry a note ("Pa'zula (Journeyman Enchanter, new in Forever)").
-- Unknown name: the nearest trainer of that profession.
local function NamedTrainerPoint(name, prof)
    local short = name and (name:match("^(.-)%s*%(") or name)
    local n = (WoWForeverLevelerNPCs or {})[short]
    if not (n and n.mapID and n.x) then
        for _, t in ipairs(PLAN.trainers or {}) do
            if t.name == short and t.mapID then n = t break end
        end
    end
    if n and n.mapID and n.x then return { mapID = n.mapID, x = n.x, y = n.y, title = short .. " (" .. prof .. ")", npc = short } end
    return TrainerPoint(prof)
end

-- Where a vendor stands: our recipe-vendor and bag-vendor scans (WoWForeverLevelerNPCs, ...BagVendors).
local function VendorPoint(vendor, what)
    if not vendor then return nil end
    local n = (WoWForeverLevelerNPCs or {})[vendor] or (WoWForeverLevelerBagVendors or {})[vendor]
    if not (n and n.mapID and n.x) then return nil end
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if Continent(n.mapID) ~= Continent(here) then return nil end
    return { mapID = n.mapID, x = n.x, y = n.y, title = vendor .. (what and (" (" .. what .. ")") or ""), npc = vendor }
end

-- The vendor where the addon saw an item for the lowest price (WoWForeverLevelerShopPrices).
local function ItemVendorPoint(item)
    local p = (WoWForeverLevelerShopPrices or {})[item]
    return p and VendorPoint(p.vendor, item)
end

-- How many of an item this character has in bags and bank (C_Item.GetItemCount; nil when the client cannot say).
local function OwnCount(item)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return nil end
    local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[item]
    local ok, n = pcall(count, id or item, true)
    n = ok and n or nil
    -- A bag in a bag slot is not counted as an item: look at the four bag slots too.
    local bagName = (C_Container and C_Container.GetBagName) or GetBagName
    if bagName then
        for bag = 1, 4 do
            local okB, b = pcall(bagName, bag)
            if okB and b == item then n = (n or 0) + 1 end
        end
    end
    return n
end

-- A vendor item's price (copper) and vendor: this client's vendor scan (WoWForeverLevelerShopPrices) first, else
-- the plan's fallback price (Plan.lua profKit prices).
local function ShopPrice(item, fallback)
    local p = (WoWForeverLevelerShopPrices or {})[item]
    if p and p.price then return math.floor(p.price / (p.per or 1) + 0.5), p.vendor end
    return fallback, nil
end

-- Sections: { id, title, summary, point, open, lines = { { text, point } } }. A section shows one line with its
-- summary and a check box; clicking the title opens or closes its details. Train and Quest hubs start open.
local DEFAULT_OPEN = { zone = true, train = true, hubs = true, lvzone = true, dung = true, class = true }
local GREEN_, RED_ = "|cff1e7a1e", "|cffb01818"

local function Sections()
    local out = {}
    local level = UnitLevel("player") or 1
    local zone = GetRealZoneText() or ""
    local _, classFile = UnitClass("player")
    local plan = (PLAN.classes or {})[classFile or ""] or { profs = {}, camp = "", zones = {} }
    local skills = Skills()
    local z = (PLAN.zones or {})[zone]
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local function rankText(p) local s = skills[p]; return s and (s.rank .. "/" .. s.max) or "not learned" end

    -- Train: professions not learned yet, and ranks due now.
    local train = {}
    local profs = {}
    for _, p in ipairs(plan.profs or {}) do table.insert(profs, p) end
    for _, p in ipairs(SECONDARY) do table.insert(profs, p) end
    for _, p in ipairs(profs) do
        local s = skills[p]
        if not s then
            table.insert(train, { text = RED_ .. "Learn " .. p .. "|r", point = TrainerPoint(p) })
        else
            for _, t in ipairs((PLAN.training or {})[p] or {}) do
                if s.max < t.cap then
                    if s.rank >= t.skill and level >= (t.level or 0) then
                        table.insert(train, { text = t.name .. " " .. p,
                                              point = (t.where ~= "" and t.where:find("book")) and nil or TrainerPoint(p) })
                    end
                    break
                end
            end
        end
    end
    if #train > 0 then table.insert(out, { id = "train", title = "Train", icon = "Interface\\Icons\\INV_Misc_Book_11", summary = "", lines = train }) end

    -- Cooking: summary with the target skill; details: three recipes and where to buy spices.
    local cook = skills["Cooking"]
    if cook then
        local st = StepFor((PLAN.steps or {})["Cooking"], cook.rank)
        local lines = {}
        for i, r in ipairs(st and st.recipes or {}) do if i <= 3 then table.insert(lines, { text = r.name .. " from " .. r.mats }) end end
        local spice = ItemVendorPoint("Mild Spices")
        if spice then table.insert(lines, { text = "Spices and vials: " .. spice.title:gsub(" %(.*", ""), point = spice }) end
        local names = {}
        for i, r in ipairs(st and st.recipes or {}) do if i <= 2 then table.insert(names, r.name) end end
        table.insert(out, { id = "cook", title = "Cooking", icon = "Interface\\Icons\\INV_Misc_Food_15",
                            summary = st and ("cook to " .. st.to .. ": " .. table.concat(names, ", ")) or "",
                            point = TrainerPoint("Cooking"), lines = lines })
    end

    -- First Aid: the bandage now and the cloth to keep.
    local aid = skills["First Aid"]
    if aid then
        local st = StepFor((PLAN.steps or {})["First Aid"], aid.rank)
        local lines = {}
        if st and st.recipes[1] then table.insert(lines, { text = st.recipes[1].name .. " from " .. st.recipes[1].mats }) end
        for _, k in ipairs(PLAN.aidKeep or {}) do
            if aid.rank >= k.from - 1 and aid.rank < k.to then table.insert(lines, { text = "Keep " .. k.count .. " " .. k.item }) break end
        end
        -- Money (Gillee's tip): a bandage you can make that sells for more than its cloth, after the 5% AH cut.
        local best, profit
        for _, step in ipairs((PLAN.steps or {})["First Aid"] or {}) do
            if step.from <= aid.rank then
                for _, r in ipairs(step.recipes) do
                    local qty, cloth = r.mats:match("^(%d*)%s*(.-Cloth)$")
                    if cloth then
                        local sell, cost = PriceByName(r.name), PriceByName(cloth)
                        if sell and cost then
                            local p = sell * 0.95 - (tonumber(qty) or 1) * cost
                            if p > 0 and (not profit or p > profit) then best, profit = r.name, p end
                        end
                    end
                end
            end
        end
        if best then table.insert(lines, { text = GREEN_ .. "Money: make " .. best .. " to sell, +" .. CopperText(profit) .. " each|r" }) end
        table.insert(out, { id = "aid", title = "First Aid", icon = "Interface\\Icons\\INV_Misc_Bandage_15",
                            summary = (st and st.recipes[1]) and ("make " .. st.recipes[1].name .. " to " .. st.to) or "",
                            point = TrainerPoint("First Aid"), lines = lines })
    end

    -- Fishing: where to fish in this zone, with the spot; details: bait and the pole/bait vendor.
    local fish, f = skills["Fishing"], z and z.fishing
    if fish and f and fish.rank < f.to then
        local spot = (f.at and mapID) and { mapID = mapID, x = f.at[1], y = f.at[2], title = "Fishing spot" } or nil
        local lines = { { text = f.where } }
        local gear = ItemVendorPoint(f.to <= 75 and "Shiny Bauble" or "Nightcrawlers")
        if gear then table.insert(lines, { text = "Pole and bait: " .. gear.title:gsub(" %(.*", ""), point = gear }) end
        table.insert(out, { id = "fish", title = "Fishing", icon = "Interface\\Icons\\Trade_Fishing",
                            summary = "fish here up to " .. f.to, point = spot, lines = lines })
    end

    -- Gathering: what needs more skill here, and in the next zone of your route.
    local function check(zname)
        local zz = (PLAN.zones or {})[zname]
        local res = {}
        for _, p in ipairs(plan.profs or {}) do
            local s = skills[p]
            for _, n in ipairs(((zz or {}).nodes or {})[p] or {}) do
                local ok = s and s.rank >= n.skill
                table.insert(res, { prof = p, name = n.name, skill = n.skill, ok = ok })
            end
        end
        return res
    end
    local here = check(zone)
    if #here > 0 then
        local short, lines = {}, {}
        local byProf = {}
        for _, n in ipairs(here) do
            if not n.ok then table.insert(short, n.name .. " " .. n.skill) end
            byProf[n.prof] = (byProf[n.prof] and (byProf[n.prof] .. ", ") or "") .. (n.ok and GREEN_ or RED_) .. n.name .. " " .. n.skill .. "|r"
        end
        for _, p in ipairs(plan.profs or {}) do
            if byProf[p] then table.insert(lines, { text = p .. ": " .. byProf[p] }) end
        end
        -- The next zone of the planned route.
        for i, rz in ipairs(plan.zones or {}) do
            if rz == zone and plan.zones[i + 1] then
                local nxt = check(plan.zones[i + 1])
                local need = {}
                for _, n in ipairs(nxt) do if not n.ok then table.insert(need, n.name .. " " .. n.skill) end end
                table.insert(lines, { text = "Next zone, " .. plan.zones[i + 1] .. ": " .. (#need > 0 and table.concat(need, ", ") or "all OK") })
                break
            end
        end
        table.insert(out, { id = "gather", title = "Gathering", icon = "Interface\\Icons\\Trade_Herbalism",
                            summary = #short > 0 and (RED_ .. table.concat(short, ", ") .. "|r") or (GREEN_ .. "all OK here|r"), lines = lines })
    end

    -- Camp: the planned object, its skills and what to carry.
    local camp = (PLAN.camp or {})[plan.camp or ""]
    if camp then
        local have = skills[plan.camp]
        local ready = have and have.rank >= camp.skill and ((skills["Cooking"] or {}).rank or 0) >= 20
        table.insert(out, { id = "camp", title = "Camp", icon = "Interface\\Icons\\Spell_Fire_Fire",
                            summary = camp.name .. (ready and "" or (RED_ .. ": needs " .. plan.camp .. " " .. camp.skill .. ", Cooking 20|r")),
                            lines = { { text = camp.buff }, { text = "Carry: 5 Basic Campfire Kits, " .. (camp.carry or camp.mats) } } })
    end


    -- Save for crafting: raw materials to level every crafting profession of the roster (Plan.lua matPlan, one
    -- craft per skill point +15%, Classic recipes, not checked). One line per profession and skill bracket.
    local saveLines = {}
    local names = {}
    for prof in pairs(PLAN.matPlan or {}) do table.insert(names, prof) end
    table.sort(names)
    for _, prof in ipairs(names) do
        local mp = PLAN.matPlan[prof]
        for _, b in ipairs(mp.brackets or {}) do
            local parts = {}
            for item, n in pairs(b.mats) do table.insert(parts, { item = item, n = n }) end
            table.sort(parts, function(a, c) return a.n > c.n end)
            local txt = {}
            for i, x in ipairs(parts) do if i <= 6 then table.insert(txt, x.n .. " " .. x.item) end end
            table.insert(saveLines, { text = GOLD .. prof .. " " .. b.from .. "-" .. b.to .. ":|r " .. table.concat(txt, ", ") })
        end
    end
    if #saveLines > 0 then
        table.insert(out, { id = "save", title = "Save for crafting", icon = "Interface\\Icons\\INV_Misc_Bag_10",
                            summary = "materials to level the team's crafts", lines = saveLines })
    end
    return out
end

-- The rows to draw: a title line per section (click: open/close), then its lines when open.
local function NowLines(open, flat)
    open = open or {}
    if flat then
        local lines = {}
        for _, sec in ipairs(Sections()) do
            if sec.id ~= "save" then
                local isOpen = open[sec.id]
                if isOpen == nil then isOpen = DEFAULT_OPEN[sec.id] or false end
                table.insert(lines, { section = sec.id, point = sec.point, icon = sec.icon, open = isOpen, inline = true,
                                      title = sec.title, text = (sec.summary or "") ~= "" and (GREY .. sec.summary .. "|r") or "" })
                if isOpen then
                    for _, l in ipairs(sec.lines or {}) do table.insert(lines, { text = WHITE .. l.text .. "|r", point = l.point }) end
                end
            end
        end
        return lines
    end
    -- The zone is a title too: folding it hides every topic (room for more zones later).
    local zoneOpen = open.zone
    if zoneOpen == nil then zoneOpen = DEFAULT_OPEN.zone end
    local lines = { { section = "zone", icon = "Interface\\Icons\\INV_Misc_Map02", open = zoneOpen,
                      text = GOLD .. (GetRealZoneText() or "") .. "|r  " .. WHITE .. "level " .. (UnitLevel("player") or 1) .. "|r" } }
    if not zoneOpen then return lines end
    for _, sec in ipairs(Sections()) do
        local isOpen = open[sec.id]
        if isOpen == nil then isOpen = DEFAULT_OPEN[sec.id] or false end
        table.insert(lines, { section = sec.id, point = sec.point, icon = sec.icon, open = isOpen,
                              text = GOLD .. sec.title .. "|r" .. ((sec.summary or "") ~= "" and ("  " .. WHITE .. sec.summary .. "|r") or "") })
        if isOpen then
            for _, l in ipairs(sec.lines or {}) do table.insert(lines, { text = WHITE .. l.text .. "|r", point = l.point }) end
        end
    end
    return lines
end

-- Search lines from the guide data that contain the text (case does not matter).
local function SearchLines(text)
    local lines, needle = {}, text:lower()
    for _, l in ipairs(PLAN.search or {}) do
        if l:lower():find(needle, 1, true) then
            table.insert(lines, { text = WHITE .. l .. "|r" })
            if #lines >= 60 then table.insert(lines, { text = GREY .. "... more: type more letters|r" }) break end
        end
    end
    if #lines == 0 then lines[1] = { text = GREY .. "Nothing found for \"" .. text .. "\"|r" } end
    return lines
end

-- Selection: one profession target at a time. Selecting sets a TomTom arrow with a pin on the world map and the
-- minimap, and points the "WFL Prof" macro at the NPC; selecting it again clears both. Kept in
-- WoWForeverLevelerUI.selected until logout or reload: nothing is selected at login.
local PROF_MACRO = "WFL Prof"
local arrowUid
local pendingProf

local function PointKey(p) return p and (p.mapID .. ":" .. p.x .. ":" .. p.y) end

-- Blizzard's quest tracking: selecting a quest that is in your log also selects it in the game (the highlighted
-- quest marker on the world map and minimap, the same as clicking the quest there). Only quests in the log have
-- Blizzard markers, so a "Take" step gets the TomTom arrow only. Clearing the selection clears the tracked
-- quest. Each result goes to the addon log once (silent in chat), so we learn what the Forever client supports.
local trackLogged = {}
local function TrackLog(key, text)
    if trackLogged[key] then return end
    trackLogged[key] = true
    WoWForeverLevelerLog = WoWForeverLevelerLog or {}
    table.insert(WoWForeverLevelerLog, date("%Y-%m-%d %H:%M:%S") .. "  quest tracking: " .. text)
end

local trackedByUs
local function TrackQuest(point)
    local setTracked = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
    if not setTracked then TrackLog("api", "C_SuperTrack.SetSuperTrackedQuestID missing on this client") return end
    local id = point and point.questID
    if id and C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
        local ok, err = pcall(setTracked, id)
        if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
        trackedByUs = ok and id or nil
        TrackLog(ok and "ok" or "fail", ok and "works" or ("failed: " .. tostring(err)))
    elseif trackedByUs then
        -- Only clear a quest we selected, never one you picked on the map yourself.
        if C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() == trackedByUs then pcall(setTracked, 0) end
        trackedByUs = nil
    end
end

-- Waypoints from us (older versions saved them) and from SkillUp Forever (its steps open in our window and TomTom
-- keeps them by default): removed at login, and before another arrow is set, so only one arrow is ever on.
local ARROW_SOURCES = { ["WoW Forever Leveler"] = true, ["SkillUp Forever"] = true }
local function ClearOldWaypoints()
    if not (TomTom and TomTom.waypoints and TomTom.RemoveWaypoint) then return end
    local old = {}
    for _, list in pairs(TomTom.waypoints) do
        for _, uid in pairs(list) do
            if type(uid) == "table" and ARROW_SOURCES[uid.from] then table.insert(old, uid) end
        end
    end
    for _, uid in ipairs(old) do pcall(TomTom.RemoveWaypoint, TomTom, uid) end
end

local function SetArrow(point)
    pcall(TrackQuest, point)
    if not (TomTom and TomTom.AddWaypoint) then return end
    if arrowUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, arrowUid) end
    arrowUid = nil
    pcall(ClearOldWaypoints) -- a SkillUp Forever arrow goes too: one arrow at a time
    if point then
        arrowUid = TomTom:AddWaypoint(point.mapID, point.x / 100, point.y / 100, { title = point.title,
            from = "WoW Forever Leveler", world = true, minimap = true, crazy = true, persistent = false, cleardistance = 8,
            silent = true }) -- no "Added a waypoint" chat line
    end
end

-- The profession macro: /targetexact the selected NPC, written only when the text changes, out of combat.
local function UpdateProfMacro()
    if InCombatLockdown and InCombatLockdown() then pendingProf = true return end
    pendingProf = false
    if not (GetMacroIndexByName and CreateMacro and EditMacro) then return end
    local sel = Settings().selected
    local text = "#showtooltip\n" .. ((sel and sel.npc) and ("/targetexact " .. sel.npc) or "/run print('WoW Forever Leveler: nothing selected')")
    local idx = GetMacroIndexByName(PROF_MACRO)
    if idx == 0 then pcall(CreateMacro, PROF_MACRO, "INV_MISC_GROUPLOOKING", text, true)
    elseif not GetMacroBody or GetMacroBody(idx) ~= text then pcall(EditMacro, idx, PROF_MACRO, nil, text) end
end

local function Select(point)
    if not point then return end
    if Refresh then C_Timer.After(0, function() pcall(Refresh) end) end
    local s = Settings()
    if s.selected and s.selected.key == PointKey(point) then
        s.selected = nil
        SetArrow(nil)
    else
        s.selected = { key = PointKey(point), mapID = point.mapID, x = point.x, y = point.y, title = point.title, npc = point.npc, questID = point.questID }
        SetArrow(point)
    end
    UpdateProfMacro()
end

-- --- The windows ---------------------------------------------------------------------------------------------
-- One builder makes both windows (WFL Professions, WFL Leveling): same look, rows, check boxes and Esc. Each keeps
-- its own place, size, font and open topics: Professions in WoWForeverLevelerUI itself (as before), Leveling in
-- WoWForeverLevelerUI.lv.

local windows = {}

-- " 56.7, 73.7" and "(56.7, 73.7)" out of a text; the comma before them too.
local function NoCoords(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("%s*%(%-?%d+%.?%d*, %-?%d+%.?%d*%)", "")
    text = text:gsub(",?%s+%-?%d+%.%d+, %-?%d+%.%d+", "")
    return text
end
WFL_NoCoords = NoCoords

local function WinSettings(win)
    local s = Settings()
    if win.key == "main" or win.key == "prof" then return s end
    s[win.key] = s[win.key] or { shown = true, w = 320, h = 280, angle = 230, font = 13 }
    return s[win.key]
end

-- Tabs: one window, "Professions" and "Leveling". The active tab is WoWForeverLevelerUI.tab; each tab keeps
-- its own open topics (Professions in .open as before, Leveling in .open_lv).
-- A tab can hide itself for some characters (tab.visible = function() ... end; the bank sees other tabs).
local function TabShown(t) return not t.visible or t.visible() end

local function CurrentTab(win)
    local ws = WinSettings(win)
    for _, t in ipairs(win.tabs) do if t.key == ws.tab and TabShown(t) then return t end end
    for _, t in ipairs(win.tabs) do if TabShown(t) then return t end end
    return win.tabs[1]
end

local function OpenMap(win)
    local ws, tab = WinSettings(win), CurrentTab(win)
    local key = tab.key == "prof" and "open" or ("open_" .. tab.key)
    ws[key] = ws[key] or {}
    return ws[key]
end

-- --- Look (3.31.0, mockup "D as in game") -------------------------------------------------------------------------
-- Two fonts shipped with the addon (Noto Sans, SIL Open Font License, Fonts/OFL.txt); the game font if a file is
-- missing (new files need a full game restart). Flat colors, a 1-pixel edge, flat buttons.
local FONT = "Interface\\AddOns\\WoWForeverLeveler\\Fonts\\NotoSans-Regular.ttf"
local FONT_BOLD = "Interface\\AddOns\\WoWForeverLeveler\\Fonts\\NotoSans-Bold.ttf"
local COLORS = {
    frame = { 0.10, 0.08, 0.055 }, bar = { 0.17, 0.125, 0.085 }, gold = { 0.54, 0.415, 0.17 }, black = { 0, 0, 0 },
    paper = { 0.937, 0.89, 0.773 }, button = { 0.23, 0.17, 0.11 }, red = { 0.35, 0.08, 0.06 },
    section = { 0.353, 0.176, 0 }, quest = { 0.24, 0.12, 0 },
}

local function SetFontSafe(fs, path, size, flags)
    local ok = fs.SetFont and fs:SetFont(path, size, flags or "")
    if not ok and fs.SetFont then fs:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end

local function Fill(frame, layer, c, a)
    local t = frame:CreateTexture(nil, layer)
    t:SetAllPoints()
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- A 1-pixel edge around a frame.
local function Edge(frame, c)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                            { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- A flat button: dark fill, gold edge, gold bold label; red fill for close. setActive(true) = parchment (tabs).
local function FlatButton(parent, label, w, h, red)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local fill = Fill(b, "BACKGROUND", red and COLORS.red or COLORS.button)
    Edge(b, COLORS.gold)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.5, 0.15)
    b.label = b:CreateFontString(nil, "OVERLAY")
    SetFontSafe(b.label, FONT_BOLD, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.label:SetTextColor(1, 0.82, 0)
    b.setActive = function(on)
        local c = on and COLORS.paper or (red and COLORS.red or COLORS.button)
        fill:SetColorTexture(c[1], c[2], c[3], 1)
        if on then b.label:SetTextColor(COLORS.section[1], COLORS.section[2], COLORS.section[3])
        else b.label:SetTextColor(0.79, 0.7, 0.48) end
    end
    return b
end

-- Card look of a row (see MakeRow): dark header or light body, gold edges (top on the header, bottom on the last
-- line), and a coloured note box inside.
local NOTE_COLORS = {
    hot = { 0.96, 0.82, 0.78, 0.64, 0.15, 0.10 },   -- sell now: price high
    cold = { 0.83, 0.89, 0.95, 0.12, 0.36, 0.56 },  -- buy now: price low
    temp = { 0.95, 0.87, 0.66, 0.48, 0.30, 0.00 },  -- a temporary profession
    good = { 0.85, 0.93, 0.78, 0.17, 0.42, 0.12 },  -- something ready
}
-- Header colours by meaning (line.tint): the same everywhere a list is about selling, buying or crafting.
local TINTS = {
    sell = { 0.55, 0.20, 0.13 },  -- red: sell now
    buy = { 0.17, 0.33, 0.52 },   -- blue: buy now
    craft = { 0.24, 0.43, 0.17 }, -- green: craft to sell
    hold = { 0.40, 0.37, 0.33 },  -- grey: keep for later
}
local function CardLook(r, card, note, pad, last, alt, group, tint)
    if group then
        -- A title over several cards (line.group): a dark band across the window with a gold line under it.
        r.cardBg:SetColorTexture(0.20, 0.13, 0.06, 1)
        r.cardBg:Show()
        r.cardEdges.L:Hide(); r.cardEdges.R:Hide(); r.cardEdges.T:Hide()
        r.cardEdges.B:Show()
    elseif card then
        -- Header: a warm medium brown (the first dark one, 0.23/0.17/0.11, was too dark: user, 2026-10-22); every
        -- second header (line.alt) a lighter caramel, so a long list of closed cards reads in stripes.
        if card == "head" and tint and TINTS[tint] then
            local t = TINTS[tint]
            r.cardBg:SetColorTexture(t[1], t[2], t[3], 1)
        elseif card == "head" then
            -- Every second header (alt) has no dark fill at all: the card's light paper, gold edge, dark text
            -- (user, 2026-10-22: more contrast than a paler brown).
            -- Tuned 2026-10-22: the light one a little darker than the card's paper, the dark one a little lighter.
            if alt then r.cardBg:SetColorTexture(0.80, 0.70, 0.51, 1) else r.cardBg:SetColorTexture(0.56, 0.40, 0.19, 1) end
        else r.cardBg:SetColorTexture(0.965, 0.93, 0.84, 1) end
        r.cardBg:Show()
        r.cardEdges.L:Show(); r.cardEdges.R:Show()
        r.cardEdges.T:SetShown(card == "head")
        r.cardEdges.B:SetShown(card == "foot" or card == "head" or last)
    else
        r.cardBg:Hide()
        for _, t in pairs(r.cardEdges) do t:Hide() end
    end
    local c = note and NOTE_COLORS[note]
    if c then
        r.noteBg:ClearAllPoints()
        r.noteBg:SetPoint("TOPLEFT", pad, -1)
        r.noteBg:SetPoint("BOTTOMRIGHT", -pad, 1)
        r.noteBg:SetColorTexture(c[1], c[2], c[3], 1)
        r.noteEdge:ClearAllPoints()
        r.noteEdge:SetPoint("TOPLEFT", r.noteBg, "TOPLEFT")
        r.noteEdge:SetPoint("BOTTOMLEFT", r.noteBg, "BOTTOMLEFT")
        r.noteEdge:SetWidth(3)
        r.noteEdge:SetColorTexture(c[4], c[5], c[6], 1)
        r.noteBg:Show(); r.noteEdge:Show()
    else
        r.noteBg:Hide(); r.noteEdge:Hide()
    end
end

local function RefreshWindow(win)
    if not win.panel or not win.panel:IsShown() then return end
    local ws = WinSettings(win)
    local tab = CurrentTab(win)
    local text = (tab.search and win.search) and win.search:GetText() or ""
    local lines = (#text >= 2) and SearchLines(text) or tab.lines(OpenMap(win))
    local font = ws.font or 13
    local width = win.scroll:GetWidth() - 4
    local y = 0
    local curSection, flashDone, flashHead
    for i, line in ipairs(lines) do
        local r = win.row(i)
        -- No coordinates anywhere (user, 2026-10-21): the zone name and the arrow are enough. Data texts can carry
        -- them ("Durotar 56.7, 73.7"), so they are taken out here, for every line.
        if line.text then line.text = NoCoords(line.text) end
        if line.title then line.title = NoCoords(line.title) end
        r.point, r.section, r.open, r.skipId, r.tip, r.item = line.point, line.section, line.open, line.skipId, line.tip, line.item
        r.click = line.click
        local card = line.card
        local pad = (card or line.group) and 7 or 0 -- lines in a card keep away from its edges
        CardLook(r, card, line.note, pad, line.cardEnd, line.alt, line.group, line.tint)
        SetFontSafe(r.text, line.group and FONT_BOLD or FONT, line.group and (font + 3) or font)
        -- Title rows: the topic icon and the instruction; detail rows are indented.
        local indent = pad
        if line.section then
            r.fold:SetTexture(line.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            r.fold:SetSize(font + 2, font + 2)
            r.fold:ClearAllPoints()
            r.fold:SetPoint("TOPLEFT", pad, (card == "head" or line.group) and -6 or -2)
            r.fold:Show()
            indent = pad + font + 6
        else
            r.fold:Hide()
        end
        -- A step number in front of the icon.
        if line.num then
            local sz = font + 4
            r.numBg:ClearAllPoints()
            r.numBg:SetPoint("TOPLEFT", indent, card == "head" and -5 or -1)
            r.numBg:SetSize(sz, sz)
            r.numBg:Show()
            SetFontSafe(r.num, FONT_BOLD, math.max(9, font - 2))
            r.num:SetText(tostring(line.num))
            r.num:Show()
            indent = indent + sz + 5
        else
            r.numBg:Hide(); r.num:Hide()
        end
        if line.icon then
            r.icon:ClearAllPoints()
            r.icon:SetPoint("TOPLEFT", indent, card == "head" and -4 or -1)
            r.icon:SetTexture(line.icon)
            if r.icon.SetDesaturated then r.icon:SetDesaturated(line.desat and true or false) end
            local isz = line.big and (font + 14) or (font + 5)
            r.icon:SetSize(isz, isz)
            r.icon:Show()
            indent = indent + isz + 5
        else
            r.icon:Hide()
            if not line.section and not line.plain then indent = indent + font + 10 end
        end
        -- A material row: the name on the left half, a bar with "have / need" inside it on the right half.
        local barW = line.bar and math.floor((width - indent - pad) * 0.5) or 0
        -- The value on the right, before the arrow box.
        local rightW = 0
        if line.right and line.right ~= "" then
            SetFontSafe(r.right, FONT, math.max(9, font - 1))
            r.right:SetText(line.right)
            r.right:SetWidth(0)
            rightW = r.right:GetStringWidth() + 2
            r.right:SetWidth(rightW)
            r.right:ClearAllPoints()
            r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(pad + ((line.point or line.click) and 26 or 2) + (line.bar and (barW + 6) or 0)), card == "head" and -6 or -2)
            r.right:SetTextColor(0.24, 0.16, 0.08)
            r.right:Show()
        else
            r.right:Hide()
        end
        local avail = width - indent - pad - (line.point and 26 or 0) - (line.bar and (barW + 6) or 0) - (rightW > 0 and rightW + 6 or 0)
        local textH
        r.text:ClearAllPoints()
        r.text:SetJustifyH("LEFT")
        if line.title then
            -- Bold title (quest or topic name) and regular text: on the same line when it fits (topic summaries
            -- to the right edge), else under the title (objectives, long NPC names).
            SetFontSafe(r.title, FONT_BOLD, font)
            local c = line.titleColor or (line.section and COLORS.section or COLORS.quest)
            r.title:SetTextColor(c[1], c[2], c[3])
            r.title:ClearAllPoints()
            r.title:SetPoint("TOPLEFT", indent, card == "head" and -5 or -2)
            r.title:SetWidth(0)
            r.title:SetText(line.title)
            local tw = r.title:GetStringWidth()
            if tw > avail then r.title:SetWidth(avail); tw = avail end
            r.title:Show()
            local th = r.title:GetStringHeight()
            textH = th
            local rest = line.text or ""
            r.text:SetWidth(0)
            r.text:SetText(rest)
            if rest ~= "" then
                local nw = r.text:GetStringWidth()
                local oneLine = line.inline and not rest:find("\n")
                if oneLine and tw + 8 + nw <= avail then
                    if line.section then
                        r.text:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(pad + (line.point and 28 or 4)), card == "head" and -5 or -2)
                        r.text:SetJustifyH("RIGHT")
                    else
                        r.text:SetPoint("TOPLEFT", indent + tw + 6, -2)
                    end
                    r.text:SetWidth(nw + 2)
                else
                    r.text:SetPoint("TOPLEFT", indent, (card == "head" and -6 or -3) - th)
                    r.text:SetWidth(avail)
                    textH = th + 1 + r.text:GetStringHeight()
                end
            end
        else
            r.title:Hide()
            r.text:SetPoint("TOPLEFT", indent, line.group and -7 or -2)
            r.text:SetWidth(avail)
            r.text:SetText(line.text)
            textH = r.text:GetStringHeight()
        end
        if line.bar then
            local bar = r.makeBar()
            bar:ClearAllPoints()
            bar:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(2 + pad), card == "head" and -5 or -1)
            bar:SetSize(barW, font + 5)
            bar:SetMinMaxValues(0, math.max(1, line.bar.need))
            bar:SetValue(math.min(line.bar.have, line.bar.need))
            if line.bar.color then bar:SetStatusBarColor(line.bar.color[1], line.bar.color[2], line.bar.color[3])
            elseif line.bar.have >= line.bar.need then bar:SetStatusBarColor(0.85, 0.65, 0.15) else bar:SetStatusBarColor(0.25, 0.6, 0.2) end
            SetFontSafe(bar.label, FONT_BOLD, math.max(9, font - 1), "OUTLINE")
            bar.label:SetTextColor(1, 1, 1)
            bar.label:SetText(line.bar.label or (line.bar.have .. " / " .. line.bar.need))
            bar:Show()
        elseif r.matBar then
            r.matBar:Hide()
        end
        if line.point then
            r.arrow:ClearAllPoints()
            r.arrow:SetPoint("TOPRIGHT", -pad, (card == "head" and -2 or 2))
            local sel = Settings().selected
            r.arrow:SetChecked(sel and sel.key == PointKey(line.point) or false)
            r.arrow:Show()
        else
            r.arrow:Hide()
        end
        local h = math.max(textH, font + (line.bar and 5 or 0), line.big and (font + 14) or 0, line.num and (font + 4) or 0)
                  + (line.section and 8 or 4) + (card == "head" and 6 or 0) + (card == "foot" and 4 or 0) + (line.note and 4 or 0)
                  + (line.group and 10 or 0)
        r:SetSize(width, h)
        if line.section and not card and not line.group then r.band:Show() else r.band:Hide() end
        if line.stripe and not line.section then
            -- Inside a card the paper is lighter, so the stripe is darker there.
            if card then r.stripe:SetColorTexture(0.55, 0.35, 0.1, 0.13) else r.stripe:SetColorTexture(0.55, 0.35, 0.1, 0.06) end
            r.stripe:Show()
        else
            r.stripe:Hide()
        end
        if line.section and i > 2 and not card and not line.group then r.sep:Show() else r.sep:Hide() end
        r:ClearAllPoints()
        if line.section and i > 2 and not card and not line.group then y = y + 4 end
        if line.group and i > 1 then y = y + 10 end -- room above a group title
        if line.gap then y = y + line.gap end
        r:SetPoint("TOPLEFT", win.child, "TOPLEFT", 2, -y)
        -- The row a link pointed at: inside the linked card, the first line whose text holds flash.match, else the
        -- card's header. It glows and is what the window scrolls to.
        if line.section then curSection = line.section end
        local f = win.flash
        local hit = false
        if f and not flashDone and curSection == f.section then
            if not f.match then
                hit = line.section == f.section
            else
                local hay = ((line.title or "") .. " " .. (line.text or "")):lower()
                hit = hay:find(f.match:lower(), 1, true) ~= nil and not line.section
            end
        end
        if hit then flashDone = true end
        if f and line.section == f.section then flashHead = r end
        r.glowing = hit
        r.setGlow(hit)
        if hit and win.scrollTo then win.scrollY = math.max(0, y - 20) end
        if win.scrollTo and line.section == win.scrollTo and not win.scrollY then win.scrollY = y end
        r:Show()
        y = y + h + (line.cardEnd and 8 or 0) -- a gap after each card
    end
    for i = #lines + 1, #win.rows do win.rows[i]:Hide() end
    -- The clicked thing was not found in the card: its header glows instead.
    if win.flash and not flashDone and flashHead then flashHead.glowing = true; flashHead.setGlow(true) end
    win.child:SetHeight(y + 8)
    -- WFL.OpenTab asked for a card: scroll it to the top once the new height is known.
    if win.scrollTo then
        local target = win.scrollY or 0
        win.scrollTo, win.scrollY = nil, nil
        if C_Timer then C_Timer.After(0, function()
            local range = tonumber(win.scroll:GetVerticalScrollRange()) or target
            win.scroll:SetVerticalScroll(math.min(target, range))
        end) end
    end
    -- What the open/close-all button works on, and its label.
    win.sections = {}
    local anyClosed = false
    for _, line in ipairs(lines) do
        if line.section then
            table.insert(win.sections, line.section)
            if not line.open then anyClosed = true end
        end
    end
    if win.allButton then win.allButton:SetText(anyClosed and "+ all" or "- all") end
end

-- Drawing errors go to the addon log (once per message), so they can be read from the save file after /reload.
local loggedErrors = {}
local function LogError(where, err)
    local msg = where .. ": " .. tostring(err)
    if loggedErrors[msg] then return end
    loggedErrors[msg] = true
    WoWForeverLevelerLog = WoWForeverLevelerLog or {}
    table.insert(WoWForeverLevelerLog, date("%Y-%m-%d %H:%M:%S") .. "  UI error " .. msg)
end

Refresh = function()
    for _, w in pairs(windows) do
        local ok, err = pcall(RefreshWindow, w)
        if not ok then LogError("window", err) end
    end
end

-- Item links and "put this item where I am typing": the focused box (AH search, Auctionator, mail), else the
-- open auction house's search box, else the chat line (as a link).
local function ItemLink(name)
    local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[name]
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link = id and info and select(2, info(id))
    return link
end

local function InsertItem(name)
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.Insert then focus:Insert(name) return end
    local ah = AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar
    local box = ah and (ah.SearchBox or ah.SearchBar)
    if box and box.SetText then
        box:SetText(name)
        if box.SetFocus then box:SetFocus() end
        return
    end
    local link = ItemLink(name) or name
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

local function MakeRow(win, i)
    if win.rows[i] then return win.rows[i] end
    local b = CreateFrame("Button", nil, win.child)
    -- A thin line above each topic and a soft band behind its title line.
    b.sep = b:CreateTexture(nil, "BACKGROUND")
    b.sep:SetPoint("TOPLEFT", 0, 0)
    b.sep:SetPoint("TOPRIGHT", 0, 0)
    b.sep:SetHeight(1)
    b.sep:SetColorTexture(0.45, 0.28, 0.08, 0.55)
    b.band = b:CreateTexture(nil, "BACKGROUND")
    b.band:SetAllPoints()
    b.band:SetColorTexture(0.55, 0.35, 0.1, 0.12)
    -- Every second entry of a long list (line.stripe): a lighter band, easier to read than a wall of text.
    b.stripe = b:CreateTexture(nil, "BACKGROUND")
    b.stripe:SetAllPoints()
    b.stripe:SetColorTexture(0.55, 0.35, 0.1, 0.06)
    -- Plus / minus in front of every title row: open or closed at a glance.
    -- Cards (line.card = "head" / "body" / "foot"): a box with a dark header and gold edges around a group of
    -- lines, and coloured notes inside (line.note = "hot" sell now, "cold" buy now, "temp" temporary). 3.40.0.
    b.cardBg = b:CreateTexture(nil, "BACKGROUND", nil, -6)
    b.cardBg:SetAllPoints()
    b.cardEdges = {}
    for _, side in ipairs({ "L", "R", "T", "B" }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.54, 0.42, 0.17, 1)
        b.cardEdges[side] = t
    end
    b.cardEdges.L:SetPoint("TOPLEFT"); b.cardEdges.L:SetPoint("BOTTOMLEFT"); b.cardEdges.L:SetWidth(1)
    b.cardEdges.R:SetPoint("TOPRIGHT"); b.cardEdges.R:SetPoint("BOTTOMRIGHT"); b.cardEdges.R:SetWidth(1)
    b.cardEdges.T:SetPoint("TOPLEFT"); b.cardEdges.T:SetPoint("TOPRIGHT"); b.cardEdges.T:SetHeight(1)
    b.cardEdges.B:SetPoint("BOTTOMLEFT"); b.cardEdges.B:SetPoint("BOTTOMRIGHT"); b.cardEdges.B:SetHeight(1)
    -- The glow on the row a link pointed at (win.flash): a rounded gold frame that pulses, until the mouse goes over
    -- it. Built the first time it is needed.
    -- The light on the row a link pointed at (win.flash): additive gold light (it adds to what is behind it, like the
    -- game's proc glow on action buttons): a halo fading outward from the four edges, a thin bright edge line and a
    -- faint wash over the row. It flashes in fading waves (strong, weaker, weaker), then stays as a steady glow until
    -- the mouse goes over the row (user, 2026-10-22). Built the first time it is needed; a redraw does not restart it.
    local halo, veil, active
    -- Spotlight: for about two seconds everything else in the window dims, then the dimming fades away and the glow
    -- stays (user, 2026-10-22). Four large dark areas around the row; the scroll frame clips them to the window.
    local function BuildVeil()
        local v = CreateFrame("Frame", nil, b)
        v:SetAllPoints()
        v:SetFrameLevel(b:GetFrameLevel() + 3) -- under the light, over the other rows
        if v.EnableMouse then v:EnableMouse(false) end
        local FAR = 3000
        local function Dark()
            local t = v:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(0, 0, 0, 0.55)
            return t
        end
        local up = Dark(); up:SetPoint("BOTTOMLEFT", v, "TOPLEFT", -FAR, 0); up:SetPoint("BOTTOMRIGHT", v, "TOPRIGHT", FAR, 0); up:SetHeight(FAR)
        local down = Dark(); down:SetPoint("TOPLEFT", v, "BOTTOMLEFT", -FAR, 0); down:SetPoint("TOPRIGHT", v, "BOTTOMRIGHT", FAR, 0); down:SetHeight(FAR)
        local left = Dark(); left:SetPoint("TOPRIGHT", v, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", v, "BOTTOMLEFT", 0, 0); left:SetWidth(FAR)
        local right = Dark(); right:SetPoint("TOPLEFT", v, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMLEFT", v, "BOTTOMRIGHT", 0, 0); right:SetWidth(FAR)
        pcall(function()
            local ag = v:CreateAnimationGroup()
            local hold = ag:CreateAnimation("Alpha")
            hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.8); hold:SetOrder(1)
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.8); fade:SetOrder(2)
            if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
            ag:SetScript("OnFinished", function() v:Hide() end)
            v.fade = ag
        end)
        return v
    end
    local GOLD_LIGHT = { 1, 0.78, 0.25 }
    local WHITE_LIGHT = { 1, 0.96, 0.78 }
    local function Gradient(t, orientation, a1, a2, c)
        c = c or GOLD_LIGHT
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        if CreateColor and t.SetGradient then
            pcall(t.SetGradient, t, orientation, CreateColor(c[1], c[2], c[3], a1), CreateColor(c[1], c[2], c[3], a2))
        elseif t.SetGradientAlpha then
            pcall(t.SetGradientAlpha, t, orientation, c[1], c[2], c[3], a1, c[1], c[2], c[3], a2)
        else
            t:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2)
        end
        if t.SetBlendMode then t:SetBlendMode("ADD") end
    end
    local function BuildHalo()
        local f = CreateFrame("Frame", nil, b)
        f:SetAllPoints()
        f:SetFrameLevel(b:GetFrameLevel() + 4)
        if f.EnableMouse then f:EnableMouse(false) end
        local W = 16 -- how far the light reaches out of the row
        -- A dark frame around the row under the light, so the gold shows on the light paper (user, 2026-10-22).
        -- Inside the row the paper and the text stay as they are.
        for _, d in ipairs({ { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", true },
                              { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", false }, { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", false } }) do
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(0.16, 0.09, 0.03, 0.88)
            if d[5] then
                t:SetPoint(d[1], f, d[2], -W, 0); t:SetPoint(d[3], f, d[4], W, 0); t:SetHeight(W)
            else
                t:SetPoint(d[1], f, d[2], 0, 0); t:SetPoint(d[3], f, d[4], 0, 0); t:SetWidth(W)
            end
        end
        local top = f:CreateTexture(nil, "OVERLAY")
        top:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0); top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0); top:SetHeight(W)
        Gradient(top, "VERTICAL", 0.9, 0)       -- bright at the row, fading upward
        local bottom = f:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0); bottom:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(W)
        Gradient(bottom, "VERTICAL", 0, 0.9)    -- bright at the row, fading downward
        local left = f:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0); left:SetWidth(W)
        Gradient(left, "HORIZONTAL", 0, 0.9)
        local right = f:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0); right:SetWidth(W)
        Gradient(right, "HORIZONTAL", 0.9, 0)
        -- A near-white core close to the row, over the gold: two layers of light add up, so the edge burns brighter.
        local C = 6
        local t2 = f:CreateTexture(nil, "OVERLAY", nil, 2)
        t2:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0); t2:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0); t2:SetHeight(C)
        Gradient(t2, "VERTICAL", 1, 0, WHITE_LIGHT)
        local b2 = f:CreateTexture(nil, "OVERLAY", nil, 2)
        b2:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0); b2:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0); b2:SetHeight(C)
        Gradient(b2, "VERTICAL", 0, 1, WHITE_LIGHT)
        local l2 = f:CreateTexture(nil, "OVERLAY", nil, 2)
        l2:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0); l2:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0); l2:SetWidth(C)
        Gradient(l2, "HORIZONTAL", 0, 1, WHITE_LIGHT)
        local r2 = f:CreateTexture(nil, "OVERLAY", nil, 2)
        r2:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0); r2:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0); r2:SetWidth(C)
        Gradient(r2, "HORIZONTAL", 1, 0, WHITE_LIGHT)
        -- The thin bright edge and the faint wash.
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
            local t = f:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.97, 0.8, 1)
            if t.SetBlendMode then t:SetBlendMode("ADD") end
            t:SetPoint(e[1]); t:SetPoint(e[2])
            if e[3] then t:SetHeight(2) else t:SetWidth(2) end
        end
        local wash = f:CreateTexture(nil, "OVERLAY")
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.8, 0.3, 0.14)
        if wash.SetBlendMode then wash:SetBlendMode("ADD") end
        pcall(function()
            local ag = f:CreateAnimationGroup()
            -- Waves: full, a dip, weaker, a dip, weaker, then settle on a steady glow.
            local steps = { { 1, 0.25, 0.4 }, { 0.25, 0.9, 0.3 }, { 0.9, 0.3, 0.45 }, { 0.3, 0.75, 0.3 }, { 0.75, 0.5, 0.6 } }
            for i, st in ipairs(steps) do
                local an = ag:CreateAnimation("Alpha")
                an:SetFromAlpha(st[1]); an:SetToAlpha(st[2]); an:SetDuration(st[3]); an:SetOrder(i)
            end
            if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
            f.waves = ag
            -- Then a slow pulse that keeps going, like the glow on a new spell in the spellbook.
            local pulse = f:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local p = pulse:CreateAnimation("Alpha")
            p:SetFromAlpha(0.5); p:SetToAlpha(0.95); p:SetDuration(1.1)
            if p.SetSmoothing then p:SetSmoothing("IN_OUT") end
            f.pulse = pulse
            ag:SetScript("OnFinished", function() if f:IsShown() then pulse:Play() end end)
        end)
        return f
    end
    b.setGlow = function(on)
        if not on then
            active = false
            if halo then
                if halo.pulse then halo.pulse:Stop() end
                halo:Hide()
            end
            if veil then
                if veil.fade then veil.fade:Stop() end
                veil:Hide()
            end
            return
        end
        if active then return end
        active = true
        halo = halo or BuildHalo()
        veil = veil or BuildVeil()
        veil:Show()
        veil:SetAlpha(1)
        if veil.fade then veil.fade:Stop(); veil.fade:Play() else C_Timer.After(2, function() veil:Hide() end) end
        halo:Show()
        halo:SetAlpha(1)
        if halo.pulse then halo.pulse:Stop() end
        if halo.waves then halo.waves:Stop(); halo.waves:Play() else halo:SetAlpha(0.6) end
    end
    b.noteBg = b:CreateTexture(nil, "BACKGROUND", nil, -4)
    b.noteEdge = b:CreateTexture(nil, "BORDER")
    -- The number of a step: a small dark square with a gold digit.
    b.numBg = b:CreateTexture(nil, "ARTWORK")
    b.numBg:SetColorTexture(0.23, 0.17, 0.11, 1)
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.num:SetPoint("CENTER", b.numBg, "CENTER", 0, 0)
    b.num:SetTextColor(1, 0.82, 0)
    -- A value on the right (a cost, a level).
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.right:SetShadowOffset(0, 0)
    b.right:SetJustifyH("RIGHT")
    b.fold = b:CreateTexture(nil, "ARTWORK")
    b.fold:SetPoint("TOPLEFT", 0, -2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 0, -1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetShadowOffset(0, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetJustifyV("TOP")
    if b.title.SetWordWrap then b.title:SetWordWrap(true) end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetShadowOffset(0, 0) -- no shadow: dark text on parchment
    b.text:SetPoint("TOPLEFT")
    b.text:SetJustifyH("LEFT")
    b.text:SetJustifyV("TOP")
    if b.text.SetWordWrap then b.text:SetWordWrap(true) end
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    -- A progress bar for material rows, made the first time a row needs one.
    b.matBar = false
    b.makeBar = function()
        if b.matBar then return b.matBar end
        local bar = CreateFrame("StatusBar", nil, b)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.25, 0.15, 0.05, 0.25)
        bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.label:SetPoint("CENTER")
        b.matBar = bar
        return bar
    end
    -- Details on hover (NPC, spot, what a material is for), like the game's own tooltips.
    b:SetScript("OnEnter", function(self)
        if self.glowing then win.flash = nil; self.glowing = false; self.setGlow(false) end
        if not self.tip and not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- An item line shows the game's own item tooltip, then our lines under it.
        local link = self.item and ItemLink(self.item)
        if link and GameTooltip.SetHyperlink then
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            for i, l in ipairs(self.tip or {}) do if i > 1 and l ~= "" then GameTooltip:AddLine(l, 0.6, 0.8, 1, true) end end
            GameTooltip:AddLine("Shift- or Ctrl-click: put the name in the search box or chat", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
            return
        end
        for i, l in ipairs(self.tip or {}) do
            if l ~= "" then if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- React on press, with a click sound.
    b:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    -- A title row opens or closes its topic; any other row with a place selects it. Right-click on a quest
    -- step skips that quest (or takes a skipped one back).
    b:SetScript("OnClick", function(self, button)
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115) end
        -- Shift- or Ctrl-click on an item line: the name goes where you would type it (3.35.0).
        if self.item and button ~= "RightButton" and ((IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())) then
            InsertItem(self.item)
            return
        end
        if button == "RightButton" then
            if self.skipId then
                local s = Settings()
                s.skip = s.skip or {}
                s.skip[self.skipId] = (not s.skip[self.skipId]) or nil
                RefreshWindow(win)
            end
            return
        end
        -- A row with its own action (a SkillUp Forever step: its arrow, or the profession window).
        if self.click then
            pcall(self.click)
            return
        end
        -- A material line (an item without its own place): find the nearest vendor that sells it.
        if self.item and not self.point and not self.section then
            FindVendor(self.item, true) -- quiet: the arrow is enough, no chat line (user, 2026-10-22)
            return
        end
        if self.section then
            local open = OpenMap(win)
            -- The row knows how it is drawn now (default-open hubs included), so one click always flips it.
            local isOpen = self.open
            if isOpen == nil then isOpen = open[self.section] end
            if isOpen == nil then isOpen = DEFAULT_OPEN[self.section] or false end
            open[self.section] = not isOpen
            RefreshWindow(win)
        else
            Select(self.point)
        end
    end)
    -- The game's check box: checked = selected (arrow and WFL Prof macro).
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, b, "UICheckButtonTemplate")
    b.arrow = ok and cb or CreateFrame("CheckButton", nil, b)
    b.arrow:SetSize(22, 22)
    b.arrow:SetPoint("TOPRIGHT", 0, 2)
    b.arrow:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115) end
        Select(b.point)
    end)
    b.arrow:SetScript("OnEnter", function(self)
        if not b.point then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sel = Settings().selected
        local on = sel and sel.key == PointKey(b.point)
        GameTooltip:AddLine((on and "Clear: " or "Select: ") .. b.point.title)
        GameTooltip:AddLine("Arrow and the WFL Prof macro point here.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b.arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.rows[i] = b
    return b
end

-- cfg: { key, frame (global name), title, lines = function(open) -> rows, search = true/false }
local function MakeWindow(cfg)
    local win = { key = cfg.key, tabs = cfg.tabs, rows = {} }
    win.row = function(i) return MakeRow(win, i) end
    windows[cfg.key] = win
    local ws = WinSettings(win)
    -- Flat window (3.31.0, mockup "D as in game"): dark frame with a thin gold edge, a title bar, flat tabs and
    -- buttons, a plain parchment list. No Blizzard frame art.
    local panel = CreateFrame("Frame", cfg.frame, UIParent)
    win.panel = panel
    panel:SetSize(ws.w or 360, ws.h or 480)
    panel:SetPoint(ws.point or "CENTER", UIParent, ws.point or "CENTER", ws.x or -300, ws.y or 0)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    Fill(panel, "BACKGROUND", COLORS.frame)
    Edge(panel, COLORS.black)
    local function savePlace()
        local point, _, _, x, y = panel:GetPoint()
        ws.point, ws.x, ws.y = point, x, y
        ws.w, ws.h = panel:GetWidth(), panel:GetHeight()
    end
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then panel:SetResizeBounds(240, 160, 900, 1000)
    elseif panel.SetMinResize then panel:SetMinResize(240, 160) end
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); savePlace() end)

    -- Title bar: the name on the left, buttons on the right.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetHeight(22)
    Fill(bar, "BACKGROUND", COLORS.bar)
    Edge(bar, COLORS.gold)
    local title = bar:CreateFontString(nil, "OVERLAY")
    SetFontSafe(title, FONT_BOLD, 12)
    title:SetTextColor(1, 0.82, 0)
    title:SetPoint("LEFT", 8, 0)
    title:SetText(cfg.title)

    local close = FlatButton(bar, "x", 18, 16, true)
    close:SetPoint("RIGHT", -3, 0)
    close:SetScript("OnClick", function() panel:Hide() end)
    local function fontButton(label, delta, anchor)
        local b = FlatButton(bar, label, 22, 16)
        b:SetPoint("RIGHT", anchor, "LEFT", -3, 0)
        b:SetScript("OnClick", function()
            ws.font = math.max(9, math.min(24, (ws.font or 13) + delta))
            RefreshWindow(win)
        end)
        return b
    end
    local plus = fontButton("A+", 1, close)
    local minus = fontButton("A-", -1, plus)
    -- Open or close every topic of this tab. Opening goes a few rounds: an opened topic can hold more topics.
    win.allButton = FlatButton(bar, "+ all", 40, 16)
    win.allButton:SetPoint("RIGHT", minus, "LEFT", -3, 0)
    win.allButton:SetScript("OnClick", function()
        local open = OpenMap(win)
        local opening = win.allButton.label:GetText() == "+ all"
        for _ = 1, (opening and 3 or 1) do
            for _, id in ipairs(win.sections or {}) do open[id] = opening end
            RefreshWindow(win)
        end
    end)
    win.allButton.GetText = function(self) return self.label:GetText() end
    win.allButton.SetText = function(self, t) self.label:SetText(t) end

    -- Flat tabs under the title bar, equal shares of the width; the active one has the parchment color.
    win.tabButtons, win.tabOrder = {}, {}
    for i, t in ipairs(cfg.tabs) do
        local b = FlatButton(panel, t.label, 80, 20)
        b:SetScript("OnClick", function() win.showTab(t.key) end)
        win.tabButtons[t.key] = b
        win.tabOrder[i] = b
    end
    local function layoutTabs()
        local shown = {}
        for i, b in ipairs(win.tabOrder) do
            if TabShown(cfg.tabs[i]) then table.insert(shown, b); b:Show() else b:Hide() end
        end
        local n = math.max(1, #shown)
        local w = ((panel:GetWidth() or 300) - 12 - (n - 1) * 4) / n
        for i, b in ipairs(shown) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", 6 + (i - 1) * (w + 4), -27)
            b:SetWidth(w)
        end
    end
    win.layoutTabs = layoutTabs
    layoutTabs()
    panel:HookScript("OnSizeChanged", layoutTabs)

    -- The parchment under the tabs: search box (Now tab) and the list sit on it.
    local paper = CreateFrame("Frame", nil, panel)
    paper:SetPoint("TOPLEFT", 2, -47)
    paper:SetPoint("BOTTOMRIGHT", -2, 2)
    Fill(paper, "BACKGROUND", COLORS.paper)
    Edge(paper, COLORS.gold)
    local search = CreateFrame("EditBox", nil, paper, "InputBoxTemplate")
    win.search = search
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", 12, -5)
    search:SetPoint("TOPRIGHT", -8, -5)
    search:SetAutoFocus(false)
    SetFontSafe(search, FONT, 12)
    search:SetScript("OnTextChanged", function() RefreshWindow(win) end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local hint = search:CreateFontString(nil, "OVERLAY")
    SetFontSafe(hint, FONT, 11)
    hint:SetPoint("LEFT", 4, 0)
    hint:SetText("Search: item, recipe, zone")
    hint:SetTextColor(0.7, 0.7, 0.7)
    search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    local scroll = CreateFrame("ScrollFrame", nil, paper, "UIPanelScrollFrameTemplate")
    win.scroll = scroll
    local child = CreateFrame("Frame", nil, scroll)
    win.child = child
    child:SetSize(300, 100)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function() child:SetWidth(scroll:GetWidth()); RefreshWindow(win) end)
    -- The mouse wheel moves about 3 lines, not half a window (the template's step).
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local step = 3 * ((ws.font or 13) + 4)
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * step)))
    end)

    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() panel:StopMovingOrSizing(); savePlace(); RefreshWindow(win) end)
    grip:SetFrameLevel(scroll:GetFrameLevel() + 5)

    -- Switch tabs: the active tab in parchment colors, the search box only where the tab has one.
    win.showTab = function(key)
        ws.tab = key
        local tab = CurrentTab(win)
        for k, b in pairs(win.tabButtons) do b.setActive(k == tab.key) end
        search:SetShown(tab.search and true or false)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 6, tab.search and -28 or -4)
        scroll:SetPoint("BOTTOMRIGHT", -26, 6)
        scroll:SetVerticalScroll(0)
        RefreshWindow(win)
    end
    win.showTab(ws.tab or cfg.tabs[1].key)

    panel:SetScript("OnShow", function() ws.shown = true; RefreshWindow(win) end)
    panel:HookScript("OnHide", function() ws.shown = false end)
    -- Esc closes it, like the game's own windows.
    if UISpecialFrames then table.insert(UISpecialFrames, cfg.frame) end
    if ws.shown == false then panel:Hide() else panel:Show() end
    return win
end

local function ToggleWindow()
    local win = windows.main
    if not win then return end
    if win.panel:IsShown() then win.panel:Hide() else win.panel:Show() end
end

-- Open the window on a tab (or close it when that tab is already showing).
local function ShowTab(key)
    local win = windows.main
    if not win then return end
    if win.panel:IsShown() and WinSettings(win).tab == key then return win.panel:Hide() end
    win.panel:Show()
    win.showTab(key)
end

local function Toggle() ToggleWindow() end

-- --- Target button and macro: the monsters your open quests still need ------------------------------------------
-- A secure click button and a character macro "WFL Target" with /targetexact lines. The game only allows
-- changing them out of combat, so an update during combat waits until the fight ends.

local MACRO_NAME = "WFL Target"
local targetButton, pending

-- Monster names from unfinished "slain" objectives of the quests in the log.
local function QuestTargets()
    local names, seen = {}, {}
    local function addObjective(text, kind, finished)
        if finished or not text then return end
        -- Classic: "Scarlet Missionary slain: 2/10"; Forever: "2/10 Scarlet Missionary slain".
        local name = text:gsub("^%s*%d+%s*/%s*%d+%s+", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
        local slain = name:match("^(.-) slain")
        name = slain or (kind == "monster" and name) or nil
        if name and name ~= "" and not seen[name] then seen[name] = true; table.insert(names, name) end
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do addObjective(o.text, o.type, o.finished) end
            end
        end
    elseif GetNumQuestLogEntries and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for i = 1, GetNumQuestLogEntries() do
            for j = 1, GetNumQuestLeaderBoards(i) or 0 do addObjective(GetQuestLogLeaderBoard(j, i)) end
        end
    end
    return names
end

local function UpdateTargets()
    if InCombatLockdown and InCombatLockdown() then pending = true return end
    pending = false
    local names = QuestTargets()
    local body = ""
    for i, n in ipairs(names) do
        local line = "/targetexact " .. n .. "\n"
        if #body + #line > 250 then break end
        body = body .. line
    end
    if targetButton then
        targetButton:SetAttribute("type", "macro")
        targetButton:SetAttribute("macrotext", body)
        targetButton.label:SetText(#names > 0 and ("Target: " .. table.concat(names, ", ")) or "No quest targets")
        targetButton:SetWidth(math.min(320, targetButton.label:GetStringWidth() + 20))
        -- The button is off by default (the macro does the job); /wflp target shows it.
        if #names > 0 and Settings().targetShown == true then targetButton:Show() else targetButton:Hide() end
    end
    -- The macro, for an action bar key: created once per character, then edited only when its text changes.
    -- Every edit fires UPDATE_MACROS, and RestedXP rebuilds its own targeting macro on that event, so needless
    -- edits made the two addons trigger each other. While RestedXP guides (it is loaded and you are below level
    -- 20, its free part), its targeting is enough and ours pauses.
    local rxpGuides = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RXPGuides")) or (IsAddOnLoaded and IsAddOnLoaded("RXPGuides"))
    if rxpGuides and (UnitLevel("player") or 1) < 20 then return end
    if GetMacroIndexByName and CreateMacro and EditMacro then
        local text = "#showtooltip\n" .. (body ~= "" and body or "/run print('WoW Forever Leveler: no quest targets')")
        local idx = GetMacroIndexByName(MACRO_NAME)
        if idx == 0 then
            pcall(CreateMacro, MACRO_NAME, "INV_MISC_QUESTIONMARK", text, true)
        elseif not GetMacroBody or GetMacroBody(idx) ~= text then
            pcall(EditMacro, idx, MACRO_NAME, nil, text)
        end
    end
end

local function BuildTargetButton()
    local s = Settings()
    targetButton = CreateFrame("Button", "WoWForeverLevelerTargetButton", UIParent, "SecureActionButtonTemplate")
    targetButton:SetSize(160, 24)
    targetButton:SetPoint(s.tPoint or "TOP", UIParent, s.tPoint or "TOP", s.tx or 0, s.ty or -120)
    targetButton:RegisterForClicks("AnyUp", "AnyDown")
    local bg = targetButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    targetButton.label = targetButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetButton.label:SetPoint("CENTER")
    -- Shift-drag moves it (out of combat).
    targetButton:SetMovable(true)
    targetButton:RegisterForDrag("LeftButton")
    targetButton:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end end)
    targetButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        s.tPoint, s.tx, s.ty = point, x, y
    end)
    targetButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Click: target the nearest quest monster.")
        GameTooltip:AddLine("Shift-drag: move. Also in your macros as \"" .. MACRO_NAME .. "\".", 1, 1, 1)
        GameTooltip:Show()
    end)
    targetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    targetButton:Hide()
end

-- --- WFL Leveling: zone, quest hubs, dungeon quests, class notes, quest targets --------------------------------

local function QuestDone(id)
    return id and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
end

-- --- Do next: the zone's quest route (Plan.lua zones[].route from scripts/build_routes.py) ----------------------
-- A route is a list of steps: a = take, d = do the objectives, t = hand in, w = level up first. It is recorded
-- (the real order another character played) or built (our own nearest-step walk over the QuestieDB data). The
-- list follows your quest log: steps already done drop out, quests you passed by without taking them are
-- dropped too (missed), and quests in your log always show their next step. Right-click a quest line to skip
-- that quest on every character (WoWForeverLevelerUI.skip; the next build_routes run leaves it out).

local NEXT_MAX = 8
local DungeonEntries, DungeonLines -- defined with the route zones further down

local function InLog(id) return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) end
-- Ready to hand in. ReadyForTurnIn when the client has it: IsComplete also says true for some quests that are not
-- done (talk-to and dungeon quests showed as "hand in" in game, 3.30.0).
local function Complete(id)
    if not C_QuestLog then return false end
    if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(id) and true or false end
    return C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false
end

local function ClassFits(mask)
    if not mask or mask == 0 then return true end
    local _, _, classID = UnitClass("player")
    if not classID then return true end
    return math.floor(mask / 2 ^ (classID - 1)) % 2 == 1
end

-- Is this step already behind you?
local function StepDone(st, level)
    if st.k == "w" then return level >= st.l end
    if QuestDone(st.id) then return true end
    if st.k == "a" then return InLog(st.id) end
    if st.k == "d" then return InLog(st.id) and Complete(st.id) end
    return false
end

-- Version D (user's pick from mockups.html, 3.30.0): Blizzard's quest icons and colors. Yellow "!" = take, grey
-- "?" = in your log, not done yet (with the live objectives under the name), yellow "?" = hand in, spyglass = a
-- quest you have not taken yet (what you will do). The NPC is grey after the name; spot and zone on hover.
local ICON_TAKE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_DO = "Interface\\Icons\\INV_Misc_Spyglass_02"

local function QuestObjectives(id)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if o.text and o.text ~= "" then table.insert(out, (o.finished and GREEN_ or WHITE) .. o.text .. "|r") end
        end
    end
    return out
end

local MAP_NAMES = { [1420] = "Tirisfal Glades", [1458] = "Undercity", [1421] = "Silverpine Forest", [1413] = "The Barrens",
                    [1454] = "Orgrimmar", [1456] = "Thunder Bluff", [1411] = "Durotar", [1412] = "Mulgore" }
local function MapName(mapID)
    if MAP_NAMES[mapID] then return MAP_NAMES[mapID] end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or ""
end

local function StepLine(st)
    local point = (st.x and st.m) and { mapID = st.m, x = st.x, y = st.y, title = st.npc or st.n, npc = st.npc, questID = st.id } or nil
    local npc = st.npc and (GREY .. "- " .. st.npc .. ((st.z and st.z ~= "") and (" (" .. st.z .. ")") or "") .. "|r") or ""
    local tip = { st.n }
    if st.npc then table.insert(tip, "NPC: " .. st.npc) end
    if point then table.insert(tip, MapName(st.m)) end
    table.insert(tip, "Right-click: skip this quest (all characters)")
    local line = { point = point, skipId = st.id, tip = tip, title = st.n, inline = true }
    if st.k == "a" then
        line.icon, line.text = ICON_TAKE, npc
    elseif st.k == "t" then
        line.icon, line.text = ICON_TURNIN, npc
    elseif InLog(st.id) then
        local objs = QuestObjectives(st.id)
        if #objs == 0 and st.o and st.o ~= "" then objs = { WHITE .. st.o .. "|r" } end
        line.icon, line.desat = ICON_TURNIN, true
        line.text, line.inline = table.concat(objs, "\n"), false
    else
        line.icon = ICON_DO
        line.text, line.inline = (st.o and st.o ~= "") and (WHITE .. st.o .. "|r") or "", false
    end
    return line
end

local ClassZones -- defined with the route zones below
local function NextZone(zone)
    local c = ClassZones(zone)
    for i, z in ipairs(c and c.zones or {}) do
        if z == zone then return c.zones[i + 1] end
    end
end

local function RouteLines(z, zone, level, open)
    local r = z and z.route
    if not (r and r.steps and #r.steps > 0) then return {} end
    local skip = Settings().skip or {}
    local steps = {}
    local skills = Skills()
    for _, st in ipairs(r.steps) do
        if st.k == "w" or (not skip[st.id] and ClassFits(st.c) and (not st.p or skills[st.p])) then table.insert(steps, st) end
    end
    -- The last step you have done; takes before it that you did not do were passed by (missed).
    local last = 0
    for i, st in ipairs(steps) do
        if st.k ~= "w" and StepDone(st, level) then last = i end
    end
    local pendingTake = {}
    for i = last + 1, #steps do
        if steps[i].k == "a" and not StepDone(steps[i], level) then pendingTake[steps[i].id] = true end
    end
    local out, shown = {}, {}
    -- Catch-up first: quests in your log whose next step lies behind you.
    for i = 1, last do
        local st = steps[i]
        if st.k ~= "a" and st.k ~= "w" and InLog(st.id) and (st.k ~= "t" or Complete(st.id)) and not StepDone(st, level) and not shown[st.id .. st.k] then
            shown[st.id .. st.k] = true
            table.insert(out, StepLine(st))
        end
    end
    local wait
    for i = last + 1, #steps do
        if #out >= NEXT_MAX then break end
        local st = steps[i]
        if st.k == "w" then
            if level < st.l then wait = st.l break end
        elseif not StepDone(st, level) and not shown[st.id .. st.k] then
            -- One line per quest: take it, then its objectives while in your log, then hand in once it is done.
            local relevant = st.k == "a" or (st.k == "d" and InLog(st.id)) or (st.k == "t" and InLog(st.id) and Complete(st.id))
            if relevant then
                shown[st.id .. st.k] = true
                if st.k == "a" and (st.r or 1) > level then wait = st.r break end
                table.insert(out, StepLine(st))
            end
        end
    end
    if wait then
        table.insert(out, { plain = true, text = GREY .. "Next quests here from level " .. wait .. ": grind or do another zone first.|r" })
    elseif #out == 0 then
        local nxt = NextZone(zone)
        table.insert(out, { plain = true, text = GREEN_ .. "Zone route done." .. (nxt and (" Next: " .. nxt .. ".") or "") .. "|r" })
    end
    -- Quests ready to hand in that the route does not list (other zones, city quests).
    local onRoute = {}
    for _, st in ipairs(r.steps) do onRoute[st.id or 0] = true end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and not onRoute[info.questID] and Complete(info.questID) then
                table.insert(out, { icon = ICON_TURNIN, title = info.title or "", inline = true, text = GREY .. "- not on this route|r" })
            end
        end
    end
    local isOpen = open.next
    if isOpen == nil then isOpen = true end
    local source = r.kind == "recorded" and ("recorded by " .. (r.by or "?")) or "built"
    local lines = { { section = "next", icon = "Interface\\Icons\\INV_Misc_Map_01", open = isOpen,
                      title = "Do next", inline = true, text = GREY .. zone .. ", level " .. level .. "|r",
                      tip = { "Do next", "Route: " .. source } } }
    if not isOpen then return lines end
    for _, l in ipairs(out) do table.insert(lines, l) end
    return lines
end

-- Quests the zone's route leaves out (with the reason) and the ones you skipped (right-click: take it back).
local function SkippedLines(z, open)
    local r = z and z.route
    if not r then return {} end
    local skip = Settings().skip or {}
    local out = {}
    for _, q in ipairs(r.skipped or {}) do
        if not QuestDone(q.id) then table.insert(out, { text = GREY .. q.n .. ": " .. q.why .. "|r" }) end
    end
    local seen = {}
    for _, st in ipairs(r.steps) do
        if st.id and skip[st.id] and not seen[st.id] then
            seen[st.id] = true
            table.insert(out, { text = GREY .. st.n .. ": you skipped it|r", skipId = st.id, tip = { st.n, "Right-click: take it back" } })
        end
    end
    if #out == 0 then return {} end
    local lines = { { section = "skipped", icon = "Interface\\Icons\\Ability_Rogue_Sprint", open = open.skipped or false,
                      title = "Skipped here", inline = true, text = GREY .. #out .. " quests|r" } }
    if open.skipped then for _, l in ipairs(out) do table.insert(lines, l) end end
    return lines
end

-- --- Dungeons as stops between the zones -------------------------------------------------------------------------
-- Plan.lua runs (level range, run levels) and pickups (dungeon quests with giver spots, from the Forever Loot /
-- DFL addon data). Per dungeon: the level where you can take all its quests, and one check box per quest giver.
-- Take them all, run the dungeon until the quests are done, then go back to the zones.

DungeonEntries = function(level)
    local byName = {}
    for _, lst in pairs(PLAN.pickups or {}) do
        for _, pk in ipairs(lst) do
            if ClassFits(pk.c) then
                byName[pk.dungeon] = byName[pk.dungeon] or {}
                table.insert(byName[pk.dungeon], pk)
            end
        end
    end
    local out = {}
    for _, r in ipairs(PLAN.runs or {}) do
        local quests = byName[r.name] or {}
        table.sort(quests, function(a, b) return (a.from or 1) < (b.from or 1) end)
        -- When you have all its quests: every quest opens before the run levels (2026-10-21 check), so this is the
        -- run start; a quest above the run's end (Shrewd Negotiations, 24, for a 17-18 run) is for later and does
        -- not move it.
        local all = r.runFrom or r.from
        for _, q in ipairs(quests) do
            if (q.from or 1) <= (r.runTo or r.to or 60) then all = math.max(all, q.from or 1) end
        end
        table.insert(out, { name = r.name, run = r, quests = quests, allFrom = all, at = math.max(all, r.runFrom or r.from) })
    end
    return out
end

DungeonLines = function(d, level, open)
    local id = "dg:" .. d.name
    local todo, taken = {}, 0
    for _, q in ipairs(d.quests) do
        if not QuestDone(q.id) then
            table.insert(todo, q)
            if InLog(q.id) then taken = taken + 1 end
        end
    end
    local r = d.run
    local state
    if #d.quests > 0 and #todo == 0 then state = GREY .. "all quests done|r"
    elseif level > (r.runTo or r.to or 60) + 2 then state = GREY .. "you outlevel it|r"
    elseif #todo == 0 then state = GREY .. "no quests, run " .. r.runFrom .. "-" .. r.runTo .. "|r"
    else state = GREY .. #todo .. " quests, all from " .. d.allFrom .. "|r" end
    local due = #todo > 0 and level >= d.allFrom and level <= (r.runTo or r.to or 60) + 2
    local lines = { { section = id, icon = "Interface\\Icons\\INV_Misc_Key_03", open = open[id] or false,
                      title = d.name, inline = true, text = state, titleColor = due and { 0.12, 0.48, 0.12 } or nil } }
    if not open[id] then return lines end
    -- Where: the entrance (arrow), run levels, and every quest with its giver, zone and spot (3.33.1, user:
    -- "I need the quests listed and where to find them"). Quests sorted by zone, so one trip per city.
    local function where(m) return MapName(m) end
    local e = r.entrance
    table.insert(lines, { icon = "Interface\\Icons\\INV_Misc_Key_03", title = "Entrance", inline = true,
                          text = GREY .. (e and where(e.m, e.x, e.y) or (r.zone ~= "" and r.zone or "?")) .. ", run at " .. r.runFrom .. "-" .. r.runTo .. "|r",
                          point = e and { mapID = e.m, x = e.x, y = e.y, title = d.name .. " entrance" } or nil,
                          tip = { d.name, "Levels " .. r.from .. "-" .. r.to .. ", best run at " .. r.runFrom .. "-" .. r.runTo } })
    if #todo > 0 and taken == #todo then
        table.insert(lines, { text = GREEN_ .. "All quests taken: run the dungeon until they are done.|r" })
    end
    table.sort(todo, function(a, b)
        local za, zb = MapName(a.mapID), MapName(b.mapID)
        if za ~= zb then return za < zb end
        return (a.from or 1) < (b.from or 1)
    end)
    -- Chains to start first: a quest whose chain begins elsewhere (Leaders of the Fang starts with The
    -- Forgotten Pools). Shown until you have started it.
    local started = {}
    for _, q in ipairs(todo) do
        local st = q.start
        if st and not started[st.id] and not QuestDone(st.id) and not InLog(st.id) and not InLog(q.id) then
            started[st.id] = true
            local tag = (st.r or 1) > level and (GREY .. "  level " .. st.r .. "|r") or (GREEN_ .. "  now|r")
            table.insert(lines, { icon = ICON_TAKE, title = "Start: " .. st.n, inline = false,
                                  text = GREY .. st.npc .. ", " .. where(st.m, st.x, st.y) .. "|r" .. tag .. "\n" .. GREY .. "leads to " .. q.quest .. "|r",
                                  point = { mapID = st.m, x = st.x, y = st.y, title = st.npc, npc = st.npc, questID = st.id },
                                  tip = { "Start chain: " .. st.n, "NPC: " .. st.npc, MapName(st.m), "Leads to: " .. q.quest } })
        end
    end
    for _, q in ipairs(todo) do
        local tag = InLog(q.id) and (GREEN_ .. "  in log|r") or ((q.from or 1) > level and (GREY .. "  level " .. q.from .. "|r") or "")
        local detail = GREY .. q.npc .. ", " .. where(q.mapID, q.x, q.y) .. "|r" .. tag
        if InLog(q.id) then
            local objs = QuestObjectives(q.id)
            if #objs > 0 then detail = detail .. "\n" .. table.concat(objs, "\n") end
        end
        table.insert(lines, { icon = InLog(q.id) and ICON_TURNIN or ICON_TAKE, desat = InLog(q.id) and true or nil,
                              title = q.quest, inline = false, text = detail,
                              point = { mapID = q.mapID, x = q.x, y = q.y, title = q.npc, npc = q.npc, questID = q.id },
                              tip = { q.quest, "NPC: " .. q.npc, MapName(q.mapID) } })
    end
    return lines
end

-- Every zone of your class route (Plan.lua classes[].zones), one fold each: its route's quests in route order,
-- done ones left out, with level, giver and a check box. The zone you are in is shown above in full.
-- The class route with your route choices applied (Plan.lua routeChoices, e.g. 20-30: Kalimdor = Stonetalon +
-- Ashenvale, or Hillsbrad). Being in a zone of one option picks it (kept in WoWForeverLevelerUI.routeChoice);
-- the other options' zones are swapped for it.
ClassZones = function(zone)
    local _, classFile = UnitClass("player")
    local c = (PLAN.classes or {})[classFile or ""]
    if not (c and c.zones) then return nil end
    local s = Settings()
    s.routeChoice = s.routeChoice or {}
    local zones = {}
    for _, z in ipairs(c.zones) do table.insert(zones, z) end
    for _, ch in ipairs(PLAN.routeChoices or {}) do
        for _, o in ipairs(ch.options) do
            for _, z in ipairs(o.zones) do if z == zone then s.routeChoice[ch.id] = o.name end end
        end
        local pick
        for _, o in ipairs(ch.options) do if o.name == s.routeChoice[ch.id] then pick = o end end
        if pick then
            local drop, at = {}, nil
            for _, o in ipairs(ch.options) do for _, z in ipairs(o.zones) do drop[z] = true end end
            local out = {}
            for _, z in ipairs(zones) do
                if drop[z] then
                    if not at then at = true; for _, pz in ipairs(pick.zones) do table.insert(out, pz) end end
                else
                    table.insert(out, z)
                end
            end
            zones = out
        end
    end
    return { zones = zones }
end

local function RouteZoneLines(zone, level, open)
    local c = ClassZones(zone)
    if not (c and c.zones) then return {} end
    local lines = {}
    local skip, skills = Settings().skip or {}, Skills()
    -- Dungeons sit between the zones: after the last route zone that starts at or below the dungeon's level
    -- (the level where you can take all its quests, or its run level if that is higher).
    local dungeons = {}
    -- Dungeons of a dungeon chain (guide.json dungeonChains) become one stop that holds them, in their order.
    local inChain, chainEntry = {}, {}
    for _, ch in ipairs(PLAN.dungeonChains or {}) do
        for i, dn in ipairs(ch.dungeons) do inChain[dn] = { ch = ch, i = i } end
    end
    for _, d in ipairs(DungeonEntries(level)) do
        local c = inChain[d.name]
        if c then
            local e = chainEntry[c.ch.name]
            if not e then
                e = { chain = c.ch, members = {}, at = d.at }
                chainEntry[c.ch.name] = e
                table.insert(dungeons, e)
            end
            e.members[c.i] = d
            e.at = math.min(e.at, d.at)
        else
            table.insert(dungeons, d)
        end
    end
    local after = {}
    for _, d in ipairs(dungeons) do
        local slot = 1
        for i, zname in ipairs(c.zones) do
            local low = tonumber(((PLAN.zones or {})[zname] or {}).levels and PLAN.zones[zname].levels:match("^(%d+)") or "")
            if low and low <= d.at then slot = i end
        end
        after[slot] = after[slot] or {}
        table.insert(after[slot], d)
    end
    for zi, zname in ipairs(c.zones) do
        local z = (PLAN.zones or {})[zname] or {}
        local quests = {}
        for _, st in ipairs(z.route and z.route.steps or {}) do
            if st.k == "a" and not skip[st.id] and ClassFits(st.c) and (not st.p or skills[st.p]) and not QuestDone(st.id) then
                table.insert(quests, st)
            end
        end
        local id = "rz:" .. zname
        local isOpen = open[id] or false
        local here = zname == zone and (GREEN_ .. "here|r  ") or ""
        table.insert(lines, { section = id, open = isOpen, title = zname, inline = true,
                              text = here .. GREY .. (z.levels or "") .. ", " .. #quests .. " quests|r" })
        if isOpen then
            if #quests == 0 then table.insert(lines, { text = GREY .. "No route for this zone yet.|r" }) end
            for _, st in ipairs(quests) do
                local l = StepLine(st)
                if (st.r or 1) > level then l.text = l.text .. GREY .. "  level " .. st.r .. "|r" end
                table.insert(lines, l)
            end
        end
        for _, d in ipairs(after[zi] or {}) do
            if d.chain then
                local id = "chain:" .. d.chain.name
                local names, left = {}, 0
                for i = 1, #d.chain.dungeons do
                    local m = d.members[i]
                    if m then
                        table.insert(names, m.name)
                        for _, q in ipairs(m.quests) do if not QuestDone(q.id) then left = left + 1 end end
                    end
                end
                table.insert(lines, { section = id, icon = "Interface\\Icons\\INV_Misc_Key_14", open = open[id] or false,
                                      title = d.chain.name, inline = true, text = GREY .. left .. " quests left|r" })
                if open[id] then
                    table.insert(lines, { text = WHITE .. table.concat(names, " > ") .. "|r" })
                    if d.chain.note ~= "" then table.insert(lines, { text = GREY .. d.chain.note .. "|r" }) end
                    for i = 1, #d.chain.dungeons do
                        if d.members[i] then
                            for _, l in ipairs(DungeonLines(d.members[i], level, open)) do table.insert(lines, l) end
                        end
                    end
                end
            else
                for _, l in ipairs(DungeonLines(d, level, open)) do table.insert(lines, l) end
            end
        end
    end
    return lines
end

-- --- The three tabs (version D): Now, Route, Materials ---------------------------------------------------------

-- --- Plan: the big picture for this character (3.32.0) --------------------------------------------------------
-- Next stop on the route (zone or dungeon chain), the next Legacy points (level 25/45/60, crafting 150/225/300)
-- and rested XP across the account (WoWForeverLevelerDB, saved by each character): who to play next.
local LEGACY_LEVELS = { 25, 45, 60 }
local LEGACY_SKILLS = { 150, 225, 300 }
local CRAFTS = { Tailoring = true, Enchanting = true, Leatherworking = true, Alchemy = true, Blacksmithing = true, Engineering = true }

-- Rested XP now, in levels: the saved amount plus what built up since (5% of a level per 8 hours in an inn or a
-- city, a quarter of that outside), at most 1.5 levels.
local function RestedLevels(c)
    if not (c and c.maxXp and c.maxXp > 0) then return 0 end
    local now = (c.restedXp or 0) / c.maxXp
    local hours = (time() - (c.lastUpdated or time())) / 3600
    now = now + hours / 8 * 0.05 * (c.resting and 1 or 0.25)
    return math.min(1.5, now)
end

local function PlanLines(open, level, zone)
    local lines = {}
    -- 1. Next stop: a dungeon chain or dungeon whose quests open soon, else the next zone once this one is outlevelled.
    local stop
    for _, d in ipairs(DungeonEntries(level)) do
        local left = 0
        for _, q in ipairs(d.quests) do if not QuestDone(q.id) then left = left + 1 end end
        local runTo = (d.run.runTo or d.run.to or 60) + 2
        if left > 0 and level <= runTo and level >= d.allFrom - 3 then
            local chain
            for _, ch in ipairs(PLAN.dungeonChains or {}) do
                for _, dn in ipairs(ch.dungeons) do if dn == d.name then chain = ch end end
            end
            stop = (chain and chain.name or d.name) .. (level >= d.allFrom and ": collect its quests now" or (": collect its quests from level " .. d.allFrom))
            break
        end
    end
    if not stop then
        local z = (PLAN.zones or {})[zone]
        local top = z and tonumber((z.levels or ""):match("%-(%d+)$"))
        local nxt = NextZone(zone)
        if top and nxt and level >= top - 1 then stop = "Move on to " .. nxt end
    end
    if stop then table.insert(lines, { title = "Next:", inline = true, text = WHITE .. stop .. "|r" }) end
    -- 2. Legacy points: the next character level and each crafting profession's next checkpoint.
    local parts = {}
    for _, l in ipairs(LEGACY_LEVELS) do
        if level < l then table.insert(parts, "level " .. l .. " (" .. (l - level) .. " to go)") break end
    end
    for prof, sk in pairs(Skills()) do
        if CRAFTS[prof] then
            for _, cap in ipairs(LEGACY_SKILLS) do
                if sk.rank < cap then table.insert(parts, prof .. " " .. cap .. " (" .. (cap - sk.rank) .. " to go)") break end
            end
        end
    end
    if #parts > 0 then table.insert(lines, { title = "Legacy:", inline = true, text = WHITE .. table.concat(parts, ", ") .. "|r" }) end
    -- 3. Rested XP: yours and the character with the most; switch when yours is used up.
    local me = (GetXPExhaustion and GetXPExhaustion() or 0) / math.max(1, UnitXPMax and UnitXPMax("player") or 1)
    local myName = UnitName("player")
    local best, bestR
    for _, c in pairs(WoWForeverLevelerDB or {}) do
        if type(c) == "table" and c.name and c.name ~= myName and (c.level or 0) < 60 then
            local r = RestedLevels(c)
            if not bestR or r > bestR then best, bestR = c, r end
        end
    end
    local txt = "you " .. math.floor(me * 100 + 0.5) .. "% of a level"
    if best and bestR > 0.05 then
        txt = txt .. ", " .. best.name .. " " .. math.floor(bestR * 100 + 0.5) .. "%"
        if me < 0.02 and bestR >= 0.3 then txt = GREEN_ .. txt .. ": switch to " .. best.name .. "|r" end
    end
    table.insert(lines, { title = "Rested:", inline = true, text = WHITE .. txt .. "|r",
                          tip = { "Rested XP", "Doubles kill XP until used up. Builds in an inn or a city while logged out.", "Estimate for other characters from their last save." } })
    local isOpen = open.plan
    if isOpen == nil then isOpen = true end
    local out = { { section = "plan", icon = "Interface\\Icons\\INV_Misc_Book_08", open = isOpen, title = "Plan", inline = true,
                    text = GREY .. (UnitName("player") or "") .. ", level " .. level .. "|r" } }
    if isOpen then for _, l in ipairs(lines) do table.insert(out, l) end end
    return out
end

-- Now: Do next for this zone, a "Dungeon now" line, then the professions topics (train, cook, first aid, ...).
local function NowTabLines(open)
    open = open or {}
    local level = UnitLevel("player") or 1
    local zone = GetRealZoneText() or ""
    local z = (PLAN.zones or {})[zone]
    local lines = PlanLines(open, level, zone)
    -- At 60, quest XP turns into gold (Gillee): from level 50 on, keep level 51+ and dungeon quests for then.
    if level >= 50 then
        table.insert(lines, { plain = true, text = GREEN_ .. "At 60 quests give gold instead of XP: keep level 51+ and dungeon quests for then.|r" })
    end
    for _, l in ipairs(RouteLines(z, zone, level, open)) do table.insert(lines, l) end
    if not (z and z.route and z.route.steps and #z.route.steps > 0) then
        table.insert(lines, { plain = true, text = GOLD .. zone .. "|r  " .. GREY .. "level " .. level .. ": no quest route for this zone yet.|r" })
    end
    for _, d in ipairs(DungeonEntries(level)) do
        local left = 0
        for _, q in ipairs(d.quests) do if not QuestDone(q.id) then left = left + 1 end end
        if left > 0 and level >= d.allFrom and level <= (d.run.runTo or d.run.to or 60) + 2 then
            table.insert(lines, { plain = true, text = GREEN_ .. "Dungeon now: " .. d.name .. " (" .. left .. " quests, see Route)|r" })
            break
        end
    end
    for _, l in ipairs(NowLines(open, true)) do table.insert(lines, l) end
    return lines
end

-- Route: every zone and dungeon of your class route, and what this zone's route skips.
local function RouteTabLines(open)
    open = open or {}
    local level = UnitLevel("player") or 1
    local zone = GetRealZoneText() or ""
    local lines = RouteZoneLines(zone, level, open)
    for _, l in ipairs(SkippedLines((PLAN.zones or {})[zone], open)) do table.insert(lines, l) end
    return lines
end

-- Materials: per crafting profession of the team and skill bracket, each raw material with one bar "have / need".
-- "have" = bags + bank of every character of this account (WoWForeverLevelerUI.have, counted on each character).
local function MaterialHave(item)
    local n = 0
    for _, counts in pairs(Settings().have or {}) do n = n + (counts[item] or 0) end
    return n
end

-- Who holds an item: { { name = "Banka", n = 40 }, ... } from every character's saved bag and bank counts on this
-- realm, most first; the character you play is "You" (user, 2026-10-22: know whom to ask for a mail).
local function MaterialWhere(item)
    local out, realm, me = {}, GetRealmName and GetRealmName() or "", UnitName("player")
    for key, counts in pairs(Settings().have or {}) do
        local n = counts[item] or 0
        local name, r = key:match("^([^-]+)%-(.+)$")
        if n > 0 and (not r or r == realm) then
            table.insert(out, { name = (name == me) and "You" or (name or key), n = n })
        end
    end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out
end

local function ItemIcon(item)
    local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[item]
    local icon = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MaterialTabLines(open)
    open = open or {}
    local lines = {}
    local names = {}
    for prof in pairs(PLAN.matPlan or {}) do table.insert(names, prof) end
    table.sort(names)
    for _, prof in ipairs(names) do
        local mp = PLAN.matPlan[prof]
        local id = "mat:" .. prof
        local first = mp.brackets and mp.brackets[1]
        local count = 0
        for _ in pairs(first and first.mats or {}) do count = count + 1 end
        table.insert(lines, { section = id, open = open[id] or false, title = prof, inline = true,
                              text = GREY .. count .. " materials to " .. (first and first.to or "") .. "|r" })
        if open[id] then
            for _, b in ipairs(mp.brackets or {}) do
                table.insert(lines, { plain = true, text = GREY .. "Skill " .. b.from .. "-" .. b.to .. "|r" })
                local items = {}
                for item, n in pairs(b.mats) do table.insert(items, { item = item, n = n }) end
                table.sort(items, function(x, y) return x.n > y.n end)
                for _, x in ipairs(items) do
                    local need = (PLAN.matNeed or {})[x.item]
                    table.insert(lines, { icon = ItemIcon(x.item), item = x.item, text = WHITE .. x.item .. "|r", bar = { have = MaterialHave(x.item), need = x.n },
                                          tip = { x.item, "Team needs about " .. (need and need.total or x.n), need and need.by or "" } })
                end
            end
            local vendor = {}
            local vitems = {}
            for item in pairs(mp.vendor or {}) do table.insert(vitems, item) end
            table.sort(vitems)
            for _, item in ipairs(vitems) do table.insert(vendor, mp.vendor[item] .. " " .. item) end
            if #vendor > 0 then table.insert(lines, { plain = true, text = GREY .. "Buy from a vendor: " .. table.concat(vendor, ", ") .. "|r" }) end
        end
    end
    if #lines == 0 then lines[1] = { plain = true, text = GREY .. "No crafting professions planned.|r" } end
    return lines
end

-- Count the team's materials in bags and bank on this character (out of combat, at most every 2 seconds).
local countQueued
local function CountMaterials()
    countQueued = false
    -- The Forever client has only C_Item.GetItemCount (the old global is missing: 3.34 counted nothing).
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return end
    local s = Settings()
    s.have = s.have or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local counts = {}
    for item in pairs(PLAN.matNeed or {}) do
        local id = WoWForeverLevelerItemIDs and WoWForeverLevelerItemIDs[item]
        local n = count(id or item, true) or 0
        if n > 0 then counts[item] = n end
    end
    s.have[key] = counts
    if Refresh then pcall(Refresh) end
end
local function QueueCount()
    if countQueued or not C_Timer then return end
    countQueued = true
    C_Timer.After(2, function()
        local ok, err = pcall(CountMaterials)
        if not ok then LogError("count", err) end
    end)
end

-- --- Minimap button: click to show or hide, drag around the minimap ---------------------------------------------

-- On the edge of the minimap, whatever its size (the Forever client has the bigger modern minimap).
local function PlaceButton(button, ws)
    local a = math.rad(ws.angle or 200)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Right-click menu on the minimap button: one row per entry with an icon, a short name and, for switches,
-- their state. Sync is a secure button running /reload: this client blocks ReloadUI() from addon code.
-- Our own small frame, so it works the same on every client. More entries can go into MENU.
local menu
local MENU = {
    { text = "Sync", icon = "Interface\\Icons\\Spell_Holy_Restoration", secure = "/reload",
      tip = "Saves the game data now. The dashboard updates by itself." },
    { text = "Profession macro", icon = "Interface\\Icons\\INV_Misc_GroupLooking",
      tip = "Puts the WFL Prof macro on your cursor: it targets the NPC you ticked in the panel.",
      run = function()
          UpdateProfMacro()
          local idx = GetMacroIndexByName and GetMacroIndexByName("WFL Prof") or 0
          if idx > 0 and PickupMacro then PickupMacro(idx) end
      end },
    { text = "Quest macro", icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
      tip = "Puts the WFL Target macro on your cursor: click an empty action bar slot to place it.",
      run = function()
          local idx = GetMacroIndexByName and GetMacroIndexByName("WFL Target") or 0
          if idx > 0 and PickupMacro then PickupMacro(idx)
          else print("|cffffd100WoW Forever Leveler:|r no WFL Target macro yet: take a kill quest first.") end
      end },
}

local ROW = 26

local function UpdateMenuStates()
    for _, b in ipairs(menu.rows) do
        if b.item.state then
            local on = b.item.state()
            b.stateText:SetText(on and "|cff40ff40on|r" or "|cff9d9d9doff|r")
        end
    end
end

local function ShowMenu(anchor)
    if InCombatLockdown and InCombatLockdown() then return end
    if not menu then
        local ok, f = pcall(CreateFrame, "Frame", "WoWForeverLevelerMenu", UIParent, "BackdropTemplate")
        menu = ok and f or CreateFrame("Frame", "WoWForeverLevelerMenu", UIParent)
        menu:SetFrameStrata("DIALOG")
        if menu.SetBackdrop then
            menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                               edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            menu:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
            menu:SetBackdropBorderColor(1, 0.82, 0, 0.8)
        end
        local width = 230
        menu.rows = {}
        for i, item in ipairs(MENU) do
            local b = CreateFrame("Button", nil, menu, item.secure and "SecureActionButtonTemplate" or nil)
            b.item = item
            b:SetSize(width - 12, ROW - 2)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(item.icon)
            icon:SetSize(ROW - 6, ROW - 6)
            icon:SetPoint("LEFT", 2, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            t:SetText(item.text)
            b.stateText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.stateText:SetPoint("RIGHT", -4, 0)
            if item.secure then
                b:SetAttribute("type", "macro")
                b:SetAttribute("macrotext", item.secure)
                b:RegisterForClicks("AnyUp", "AnyDown")
            else
                b:SetScript("OnClick", function() item.run(); UpdateMenuStates() end)
            end
            if item.tip then
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:AddLine(item.tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            table.insert(menu.rows, b)
        end
        menu:SetSize(width, #MENU * ROW + 10)
        -- Closes by itself a moment after the mouse leaves it.
        menu:SetScript("OnUpdate", function(self, elapsed)
            if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then self.away = 0 return end
            self.away = (self.away or 0) + elapsed
            if self.away > 1.5 and not InCombatLockdown() then self:Hide() end
        end)
    end
    if menu:IsShown() then return menu:Hide() end
    menu.anchor = anchor
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
    menu.away = 0
    UpdateMenuStates()
    menu:Show()
end

-- One minimap button per window: click shows or hides it, right-click opens the menu, drag moves the button.
local function BuildMinimapButton(win, name, iconPath, title)
    if not Minimap then return end
    local ws = WinSettings(win)
    local b = CreateFrame("Button", name, Minimap)
    b:SetSize(31, 31)
    -- Above the minimap and its border frames.
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(iconPath)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ShowMenu(self) else ToggleWindow() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ws.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceButton(self, ws)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine("Click: show or hide. Right-click: menu (Sync). Drag: move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton(b, ws)
end

-- --- Item tooltip: one line saying what to do with the item ----------------------------------------------------
-- Keep (a planned recipe of your profession at this or the next step), Bank (own use later), Mail (a planned
-- recipe of another character's profession), else Sell on AH (Auctionator price, after the 5% cut, at least 1.5x
-- the vendor price) or Vendor. Only recipes in our plan count: far-away or Alliance-only recipes mean "sell".

local function Money(c)
    c = math.floor((c or 0) + 0.5)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then table.insert(out, g .. "g") end
    if sv > 0 then table.insert(out, sv .. "s") end
    if cu > 0 or #out == 0 then table.insert(out, cu .. "c") end
    return table.concat(out, " ")
end

local function AuctionPrice(link)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink) then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "WoWForeverLeveler", link)
    return ok and price or nil
end

local function ItemAdvice(name, link)
    local skills = Skills()
    local _, classFile = UnitClass("player")
    local plan = (PLAN.classes or {})[classFile or ""] or { profs = {} }
    local mine = {}
    for _, p in ipairs(plan.profs or {}) do mine[p] = true end
    for _, p in ipairs(SECONDARY) do mine[p] = true end
    local me = UnitName("player")
    local later, mail
    for _, r in ipairs((PLAN.reagents or {})[name] or {}) do
        local s = skills[r.prof]
        local rank = s and s.rank or 0
        if mine[r.prof] and rank < r.to then
            -- This step or the next one (within about 50 points): keep it; further away: bank it.
            if r.from <= rank + 50 then return GREEN .. "Keep: " .. r.prof .. " to " .. r.to .. " (" .. r.recipe .. ")|r" end
            later = later or (r.prof .. " from " .. r.from)
        elseif not mine[r.prof] then
            for _, who in ipairs((PLAN.crafters or {})[r.prof] or {}) do
                if who ~= me then mail = mail or (who .. " (" .. r.prof .. ")") break end
            end
        end
    end
    if later then return "|cffa0a0ffBank: " .. later .. "|r" end
    if mail then return "|cff80c0ffMail to " .. mail .. ", full stacks|r" end
    local vendor = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)) or 0
    local ah = AuctionPrice(link)
    if ah and ah * 0.95 >= 1.5 * vendor and ah >= 5 then return "|cffffd100Sell on AH (about " .. Money(ah) .. "), best Tue/Thu evening|r" end
    if vendor > 0 then return "|cffc0c0c0Vendor (" .. Money(vendor) .. ")|r" end
    return nil
end

local function AddAdvice(tooltip)
    if not (tooltip and tooltip.GetItem) then return end
    local name, link = tooltip:GetItem()
    if not (name and link) then return end
    local ok, advice = pcall(ItemAdvice, name, link)
    if ok and advice then
        tooltip:AddLine("|cffffd100WFL:|r " .. advice)
    end
    -- Skill needed to gather it (Plan.lua gatherNodes: herbs by name, ore as "<node> Ore"), red when yours is lower.
    local gather
    for prof, nodes in pairs(PLAN.gatherNodes or {}) do
        local skill = nodes[name] or nodes[(name:match("^(.-) Ore$") or "")]
        if skill then
            local s = Skills()[prof]
            local short = s and s.rank < skill
            gather = "|cffffd100WFL:|r " .. (short and "|cffff6060" or "|cffa0a0ff") .. prof .. " " .. skill .. " to gather"
                     .. (s and (" (you: " .. s.rank .. ")") or "") .. "|r"
            tooltip:AddLine(gather)
        end
    end
    -- How many the team needs to level its crafts (Save for crafting): save that many, sell the rest.
    local need = (PLAN.matNeed or {})[name]
    if need then
        tooltip:AddLine("|cffffd100WFL:|r |cffa0a0ffTeam needs about " .. need.total .. " (" .. need.by .. ")|r", 1, 1, 1, true)
    end
    -- Who on the team holds it (saved bag and bank counts), when someone other than you does (user, 2026-10-22).
    local held = MaterialWhere(name)
    local others = false
    for _, w in ipairs(held) do if w.name ~= "You" then others = true end end
    if others then
        local parts = {}
        for i, w in ipairs(held) do if i <= 5 then table.insert(parts, w.name .. " " .. w.n) end end
        tooltip:AddLine("|cffffd100WFL:|r |cffffffff" .. table.concat(parts, " \194\183 ") .. "|r", 1, 1, 1, true)
    end
    if (ok and advice) or need or gather or others then tooltip:Show() end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) AddAdvice(tooltip) end)
    else
        for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
            if t and t.HookScript then pcall(t.HookScript, t, "OnTooltipSetItem", AddAdvice) end
        end
    end
end

-- --- Shared parts for the window addons (3.33.0) ----------------------------------------------------------------
-- This addon is the core: data collection, Plan.lua, fonts, the window, rows, arrows, macros and tooltips. The
-- window addons (WoWForeverLeveler_Quests: Now / Route / Materials; WoWForeverLeveler_Planner: Plan /
-- Professions) load after it and call WFL.RegisterTabs. Without a window addon there is no window; data
-- collection and the item tooltip still work.
WFL = WFL or {}
-- --- Vendor search: who sells a material, nearest first ------------------------------------------------------------
-- Plan.lua vendors (NPC id -> { n, sub, at = { { mapID, x, y } } }) and vendorItems (item -> NPC ids), from QuestieDB
-- (scripts/vendor_items.py, Horde-friendly). Ctrl + click a material (profession window, bags, chat links), click a
-- material line in the window, press the WFL key (Key Bindings, no default key: Alt+V is the user's nameplates), or
-- type /wfl buy <item>: chat lists the 3 nearest, the arrow points at the first.
local function WorldXY(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
    if ok and cont and pos then return cont, pos.x, pos.y end
end

local function NearestVendors(item, count)
    local ids = (PLAN.vendorItems or {})[item]
    if not ids then return {} end
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local px, py, pc, wx, wy
    if here and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(here, "player")
        if pos then px, py = pos:GetXY(); px, py = px * 100, py * 100; pc, wx, wy = WorldXY(here, px, py) end
    end
    local myCont = Continent(here)
    local list = {}
    for _, id in ipairs(ids) do
        local v = (PLAN.vendors or {})[tostring(id)]
        for _, at in ipairs(v and v.at or {}) do
            local m, x, y = at[1], at[2], at[3]
            -- Yards on the world map when the client knows them; else your zone first, then your continent.
            local d
            local c2, vx, vy = WorldXY(m, x, y)
            if pc and c2 == pc then d = math.sqrt((vx - wx) ^ 2 + (vy - wy) ^ 2)
            elseif m == here and px then d = 10000 + math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            elseif myCont and Continent(m) == myCont then d = 100000
            else d = 1000000 end
            table.insert(list, { v = v, m = m, x = x, y = y, d = d })
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local out, seen = {}, {}
    for _, e in ipairs(list) do
        if not seen[e.v.n] then seen[e.v.n] = true; table.insert(out, e) end
        if #out >= (count or 3) then break end
    end
    return out
end

FindVendor = function(item, quiet)
    if not item then return end
    local print = quiet and function() end or print
    local list = NearestVendors(item, 1)
    if #list == 0 then
        print("|cffffd100WFL:|r no vendor known for " .. item .. ".")
        return
    end
    local e = list[1]
    local far = e.d < 10000 and string.format(" (%d yd)", e.d) or ""
    print(string.format("|cffffd100WFL:|r %s: %s%s, %s%s. Arrow on.", item, e.v.n,
                        e.v.sub ~= "" and (" <" .. e.v.sub .. ">") or "", MapName(e.m), far))
    -- The arrow to the nearest (kept selected, so a second press does not turn it off).
    local point = { mapID = e.m, x = e.x, y = e.y, title = e.v.n .. " (" .. item .. ")", npc = e.v.n }
    local st = Settings()
    st.selected = { key = PointKey(point), mapID = point.mapID, x = point.x, y = point.y, title = point.title, npc = point.npc }
    SetArrow(point)
    if Refresh then pcall(Refresh) end
end

-- /wfl buy <item>: the item by name (exact, else the first that contains the text).
local function FindVendorByName(text)
    text = string.lower((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then return end
    local best
    for item in pairs(PLAN.vendorItems or {}) do
        local low = string.lower(item)
        if low == text then best = item break end
        if not best and low:find(text, 1, true) then best = item end
    end
    if best then FindVendor(best) else print("|cffffd100WFL:|r no vendor known for " .. text .. ".") end
end

-- The key binding (Bindings.xml): the item under the mouse in any item tooltip (bags, profession window, chat links).
function WFL_FindVendorHovered()
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip:IsShown() and tip.GetItem then
            local name = tip:GetItem()
            if name and name ~= "" then FindVendor(name) return end
        end
    end
    print("|cffffd100WFL:|r hover an item first, then press the key.")
end
BINDING_HEADER_WFL = "WoW Forever Leveler"
BINDING_NAME_WFL_FIND_VENDOR = "Find the nearest vendor of the hovered item"

-- Ctrl, Alt (Option) or Command + click on a material: the vendor search, wherever its tooltip shows (the modern profession
-- window's reagent buttons, bags, auction house, chat links). The game's GLOBAL_MOUSE_DOWN event comes for every
-- click; with Ctrl held and an item in the tooltip, that item is searched. The modern profession window does not go
-- through HandleModifiedItemClick (3.38.2 listened there and saw nothing). Items you can wear keep Ctrl + click
-- (dressing room); Ctrl + Shift is left alone.
local lastVendorClick = 0
local function VendorClick()
    -- Ctrl, Alt (Option on a Mac) or Command: a Mac with Control and Command swapped sends another key than Ctrl.
    local held = (IsControlKeyDown and IsControlKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
    if not held or (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local tip = GameTooltip
    if not (tip and tip:IsShown() and tip.GetItem) then return end
    local name, link = tip:GetItem()
    if not name or name == "" then return end
    local equip = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
    if equip and link then
        local ok, wear = pcall(equip, link)
        if ok and wear then return end
    end
    local now = GetTime and GetTime() or 0
    if now - lastVendorClick < 0.3 then return end -- one search per click
    lastVendorClick = now
    FindVendor(name)
end

local function HookVendorClick()
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
    f:SetScript("OnEvent", function() local ok, err = pcall(VendorClick); if not ok then LogError("vendor click", err) end end)
    local ok = f.IsEventRegistered and f:IsEventRegistered("GLOBAL_MOUSE_DOWN")
    -- Without that event (older clients): item clicks that go through HandleModifiedItemClick (bags, chat links).
    if not ok and hooksecurefunc and HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function() pcall(VendorClick) end)
    end
    WoWForeverLevelerLog = WoWForeverLevelerLog or {}
    table.insert(WoWForeverLevelerLog, date("%Y-%m-%d %H:%M:%S") .. "  vendor click: " .. (ok and "GLOBAL_MOUSE_DOWN" or "HandleModifiedItemClick fallback"))
end

WFL.tabs = WFL.tabs or {}
function WFL.RegisterTabs(tabs)
    for _, t in ipairs(tabs) do table.insert(WFL.tabs, t) end
end
WFL.Settings, WFL.Skills, WFL.QuestDone, WFL.InLog, WFL.ClassFits = Settings, Skills, QuestDone, InLog, ClassFits
WFL.PlanLines, WFL.NowLines, WFL.NowTabLines, WFL.RouteTabLines = PlanLines, NowLines, NowTabLines, RouteTabLines
WFL.MaterialTabLines, WFL.DungeonEntries, WFL.DungeonLines, WFL.RestedLevels = MaterialTabLines, DungeonEntries, DungeonLines, RestedLevels
WFL.NextZone, WFL.ClassZones, WFL.CopperText, WFL.MapName = NextZone, ClassZones, CopperText, MapName
WFL.colors = { GOLD = GOLD, WHITE = WHITE, GREY = GREY, GREEN = GREEN_, RED = RED_ }
WFL.menu = MENU
WFL.ItemLink, WFL.InsertItem, WFL.TrainerPoint = ItemLink, InsertItem, TrainerPoint
WFL.OwnCount, WFL.ShopPrice, WFL.ItemVendorPoint, WFL.VendorPoint = OwnCount, ShopPrice, ItemVendorPoint, VendorPoint
WFL.FindVendor, WFL.FindVendorByName, WFL.NamedTrainerPoint = FindVendor, FindVendorByName, NamedTrainerPoint
WFL.MaterialWhere = MaterialWhere
-- The nearest vendor of an item (QuestieDB vendor lists in Plan.lua) as an arrow point and "NPC, zone", or nil.
WFL.NearestVendor = function(item)
    local e = (NearestVendors(item, 1) or {})[1]
    if not e then return nil end
    return { mapID = e.m, x = e.x, y = e.y, title = e.v.n .. " (" .. item .. ")", npc = e.v.n }, e.v.n .. ", " .. MapName(e.m)
end
-- Select a map point (arrow, map pin, WFL Prof macro); the same point again clears it.
WFL.Select = function(point) Select(point) end
-- Open the window on a tab with one card (section id) expanded and scrolled to: links between tabs (2026-10-22).
WFL.OpenTab = function(key, section, match)
    local win = windows.main
    if not win then return end
    local ws = WinSettings(win)
    if section then
        local k = key == "prof" and "open" or ("open_" .. key)
        ws[k] = ws[k] or {}
        ws[k][section] = true
        win.scrollTo, win.flash = section, { section = section, match = match }
    end
    win.panel:Show()
    win.showTab(key)
end
-- No arrow at all: our selection cleared and every waypoint from us or SkillUp Forever removed.
WFL.ClearArrows = function()
    local st = Settings()
    if st.selected then st.selected = nil; SetArrow(nil); UpdateProfMacro() end
    pcall(ClearOldWaypoints)
    if Refresh then pcall(Refresh) end
end
WFL.IsSelected = function(point) local sel = Settings().selected; return point and sel and sel.key == PointKey(point) or false end
WFL.AuctionPrice, WFL.MaterialHave, WFL.ItemIcon, WFL.QuestObjectives, WFL.Complete = AuctionPrice, MaterialHave, ItemIcon, QuestObjectives, Complete
WFL.Refresh = function() if Refresh then Refresh() end end
-- After a change that shows or hides tabs (the bank switch): lay the tabs out again and redraw.
WFL.Relayout = function()
    local win = windows.main
    if win and win.layoutTabs then win.layoutTabs(); win.showTab(WinSettings(win).tab) end
end
WFL.icons = { take = ICON_TAKE, turnin = ICON_TURNIN }

-- --- Events: build once the saved settings are loaded, refresh when skills, level or zone change -----------------

local events = CreateFrame("Frame")
local targetTimer
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
                     "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_REGEN_ENABLED",
                     "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_CLOSED",
                     "AUCTION_HOUSE_CLOSED", "UPDATE_PENDING_MAIL" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(function()
            -- The tabs come from the window addons that are enabled (both: all their tabs, in load order).
            if #WFL.tabs > 0 then
                local main = MakeWindow({ key = "main", frame = "WoWForeverLevelerPanel", title = WFL.title or "WoW Forever Leveler", tabs = WFL.tabs })
                BuildMinimapButton(main, "WoWForeverLevelerMinimapButton", "Interface\\Icons\\INV_Misc_Spyglass_02", "WoW Forever Leveler")
            end
            BuildTargetButton()
            HookTooltips()
            pcall(HookVendorClick)
        end)
        if not ok then print("|cffff4040WoW Forever Leveler:|r panel error: " .. tostring(err)); LogError("panel", err) end
        if C_Timer then C_Timer.After(3, function() pcall(UpdateTargets); pcall(CountMaterials) end) end
        -- No arrow at login: the arrow shows only after you select something. Forget the last selection and
        -- remove our waypoints that older versions saved in TomTom.
        Settings().selected = nil
        if C_Timer then C_Timer.After(6, function() pcall(ClearOldWaypoints); pcall(UpdateProfMacro) end) end
        return
    end
    if event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_CLOSED" or event == "MAIL_CLOSED" then
        QueueCount()
        return
    end
    if event == "MAIL_INBOX_UPDATE" or event == "UPDATE_PENDING_MAIL" or event == "AUCTION_HOUSE_CLOSED" then
        -- New mail, or Auctionator may have new prices: redraw a moment later.
        if C_Timer then C_Timer.After(1, function() pcall(Refresh) end) end
        return
    end
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        -- The quest log fires often: update at most once per second.
        if not targetTimer and C_Timer then
            targetTimer = true
            C_Timer.After(1, function() targetTimer = nil; pcall(UpdateTargets); pcall(Refresh) end)
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then pcall(UpdateTargets) end
        if pendingProf then pcall(UpdateProfMacro) end
        return
    end
    -- Level and skill values arrive a moment after the event.
    if C_Timer then C_Timer.After(1, function() pcall(Refresh) end) else pcall(Refresh) end
end)

-- TomTom's coordinate block (the coordinates in the middle of the screen): always off, as the user asked.
local function TomTomCoords(on)
    if not (TomTom and TomTom.profile and TomTom.profile.block and TomTom.ShowHideCoordBlock) then return false end
    TomTom.profile.block.enable = on
    TomTom:ShowHideCoordBlock()
    return true
end

local coordsFrame = CreateFrame("Frame")
coordsFrame:RegisterEvent("PLAYER_LOGIN")
coordsFrame:SetScript("OnEvent", function()
    local s = Settings()
    -- 3.12.1: the user wants the macro, not the on-screen button: switch the button off once.
    if not s.targetResetOnce then s.targetShown, s.targetResetOnce = false, true end
    -- TomTom's coordinate block stays off: the user never wants it (TomTom turns it on by default).
    if C_Timer then C_Timer.After(5, function() TomTomCoords(false) end) end
end)

SLASH_WFLLEVEL1 = "/wfll"
SlashCmdList["WFLLEVEL"] = function() ShowTab("route") end

SLASH_WFLPANEL1 = "/wflp"
SlashCmdList["WFLPANEL"] = function(msg)
    if msg == "target" then
        -- Show or hide the target button (the macro stays).
        local s = Settings()
        s.targetShown = not s.targetShown
        pcall(UpdateTargets)
        print("|cffffd100WoW Forever Leveler:|r target button " .. (s.targetShown and "on" or "off"))
        return
    end
    -- /wflp next | dungeons | prof | team: open the window on that tab (the same again closes it).
    local tab = ({ next = "next", dungeons = "dg", dg = "dg", prof = "prof2", professions = "prof2", team = "team" })[(msg or ""):lower()]
    if tab then ShowTab(tab) return end
    Toggle()
end

-- For key bindings (Bindings.xml) and macros: /run WFL_ShowTab("prof2").
function WFL_ToggleWindow() Toggle() end
function WFL_ShowTab(key) ShowTab(key) end
BINDING_NAME_WFL_TOGGLE = "Open or close the window"
BINDING_NAME_WFL_PROFESSIONS = "Open the Professions tab"

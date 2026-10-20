-- WoW Forever Leveler In-Game Sync Addon
-- Records character state, level, XP, professions and completed quests on login, level up, and logout.

-- Every profession the addon tracks: the primary ones plus the secondary Cooking, First Aid and Fishing.
local PRIMARY_PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
    Herbalism = true, Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
    Cooking = true, ["First Aid"] = true, Fishing = true,
}

local frame = CreateFrame("Frame")

-- Prints to chat and keeps a copy in the save file, so the dashboard maintainer can read it after /reload.
-- quiet = only the save file (background work the player does not need to see).
local MAX_LOG_LINES = 300
local function Log(text, quiet)
    if not quiet then print(text) end
    WoWForeverLevelerLog = WoWForeverLevelerLog or {}
    local plain = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    table.insert(WoWForeverLevelerLog, date("%Y-%m-%d %H:%M:%S") .. "  " .. plain)
    while #WoWForeverLevelerLog > MAX_LOG_LINES do table.remove(WoWForeverLevelerLog, 1) end
end

-- The WoW Forever client mixes Classic and modern APIs, and an unknown event name throws
-- and stops this file. Register every event defensively and skip the ones the client lacks.
local function TryRegister(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return
    end
    pcall(frame.RegisterEvent, frame, event)
end

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "SKILL_LINES_CHANGED",
    "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_COMPLETE", "PLAYER_MONEY",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
    "AUCTION_HOUSE_CLOSED", "QUEST_LOG_UPDATE",
    -- Entering or leaving an inn or city, and rested XP changes: saved while playing, because the logout
    -- values are empty on the Forever client.
    "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION",
    "TRAINER_SHOW", "TRAINER_UPDATE", "MERCHANT_SHOW", "ZONE_CHANGED_NEW_AREA",
}) do
    TryRegister(event)
end

local pendingTitles = {}

-- Each NPC is read once: WoWForeverLevelerScanTimes[key] = { build, level, seen }. A new game build
-- (patch) reads it again, and with a level so does a new character level (class trainers add skills).
local function GameBuild()
    local _, build = GetBuildInfo()
    return build
end

local function ScannedBefore(key, level)
    local t = (WoWForeverLevelerScanTimes or {})[key]
    return t ~= nil and t.build == GameBuild() and (level == nil or t.level == level)
end

local function MarkScanned(key, level)
    WoWForeverLevelerScanTimes = WoWForeverLevelerScanTimes or {}
    WoWForeverLevelerScanTimes[key] = { build = GameBuild(), level = level, seen = time() }
end

-- --- Auction house prices come from Auctionator ---------------------------
-- Auctionator scans the auction house and saves prices per item ID in AUCTIONATOR_PRICE_DATABASE.
-- The dashboard works with item names, so this addon saves, for every item Auctionator has seen:
--   WoWForeverLevelerItemIDs[name] = itemID, WoWForeverLevelerSellPrices[name] = vendor price,
-- and WoWForeverLevelerAuctionRealms[Auctionator realm key] = our price scope ("Realm-Faction").
-- scripts/build_roster.py reads Auctionator's save file and joins it with these tables.

local function PriceScope()
    return (GetRealmName() or "Unknown") .. "-" .. (UnitFactionGroup("player") or "Unknown")
end

-- What a vendor pays for one item, saved per item name, so the dashboard can tell "vendor it"
-- from "sell it at the auction house". Returns false while the item info is still loading.
local function RememberSellPrice(name, itemID)
    if not (name and itemID) then return false end
    WoWForeverLevelerSellPrices = WoWForeverLevelerSellPrices or {}
    if WoWForeverLevelerSellPrices[name] then return true end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local sellPrice = getInfo and select(11, getInfo(itemID))
    if sellPrice then WoWForeverLevelerSellPrices[name] = sellPrice end
    return sellPrice ~= nil
end

-- Returns nil when the item is not cached yet; it also asks the client to load it for next time.
-- The modern client moved GetItemInfo/GetItemCount into C_Item, so every call is guarded.
local function ItemNameByID(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then return name end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = getInfo and getInfo(itemID)
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return nil
end

local function ItemCountByID(itemID)
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    return (getCount and getCount(itemID)) or 0
end

-- Auctionator keeps the current realm's prices as a plain table while the game runs.
local function AuctionatorRealm()
    local variables = Auctionator and Auctionator.Variables
    if not (AUCTIONATOR_PRICE_DATABASE and variables and variables.GetConnectedRealmRoot) then return nil end
    local realm = variables.GetConnectedRealmRoot()
    local data = realm and AUCTIONATOR_PRICE_DATABASE[realm]
    if type(data) ~= "table" then return nil end
    return realm, data
end

local NAME_BATCH = 200
local NAME_RETRIES = 3
local naming = false

-- Names every Auctionator item that has no name or vendor price yet, a batch per frame so a big
-- price database does not freeze the game. Items still loading are tried again a little later.
local function NameAuctionatorItems(retry)
    if naming then return end
    local realm, data = AuctionatorRealm()
    if not realm then return end
    WoWForeverLevelerAuctionRealms = WoWForeverLevelerAuctionRealms or {}
    WoWForeverLevelerAuctionRealms[realm] = PriceScope()
    WoWForeverLevelerItemIDs = WoWForeverLevelerItemIDs or {}
    WoWForeverLevelerSellPrices = WoWForeverLevelerSellPrices or {}
    local done = {}
    for name, id in pairs(WoWForeverLevelerItemIDs) do
        if WoWForeverLevelerSellPrices[name] then done[id] = true end
    end
    local queue = {}
    for key in pairs(data) do
        local id = tonumber(key)
        if id and not done[id] then table.insert(queue, id) end
    end
    if #queue == 0 or not C_Timer then return end
    naming = true
    local index, named, loading = 1, 0, 0
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        for _ = 1, NAME_BATCH do
            local id = queue[index]
            if not id then break end
            index = index + 1
            local name = ItemNameByID(id)
            if name then
                -- Two items can share a name: only a name seen for the first time counts.
                local new = not WoWForeverLevelerSellPrices[name]
                WoWForeverLevelerItemIDs[name] = WoWForeverLevelerItemIDs[name] or id
                if RememberSellPrice(name, id) then if new then named = named + 1 end else loading = loading + 1 end
            else
                loading = loading + 1
            end
        end
        if index > #queue then
            ticker:Cancel()
            naming = false
            if named > 0 then
                Log(string.format("|cffffd100WoW Forever Leveler:|r %d Auctionator items named%s.",
                    named, loading > 0 and string.format(" (%d still loading)", loading) or ""), true)
            end
            retry = retry or 0
            if loading > 0 and retry < NAME_RETRIES then
                C_Timer.After(20, function() NameAuctionatorItems(retry + 1) end)
            end
        end
    end)
end

local ToggleTodo, RefreshTodo -- the trainer to-visit window, defined below; /wfl todo needs it first

SLASH_WOWFOREVERLEVELER1 = "/wfl"
SlashCmdList["WOWFOREVERLEVELER"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "todo" then
        ToggleTodo()
    elseif cmd == "check" then
        local function has(v) return v and "|cff00ff00yes|r" or "|cffff4040no|r" end
        Log("|cffffd100WoW Forever Leveler:|r client API check")
        Log("  Classic recipes (GetTradeSkillLine): " .. has(GetTradeSkillLine))
        Log("  Classic enchanting (GetCraftDisplaySkillLine): " .. has(GetCraftDisplaySkillLine))
        Log("  Modern recipes (C_TradeSkillUI): " .. has(C_TradeSkillUI))
        local realm, data = AuctionatorRealm()
        local items, named = 0, 0
        for _ in pairs(data or {}) do items = items + 1 end
        for _ in pairs(WoWForeverLevelerItemIDs or {}) do named = named + 1 end
        Log(string.format("  Auctionator prices: %s (%s, %d items) | item names saved: %d",
            has(realm), tostring(realm), items, named))
    else
        Log("|cffffd100WoW Forever Leveler:|r auction prices come from Auctionator: scan with it, then /reload and Sync. /wfl check - show which game systems this client has. /wfl todo - show or hide the trainers you still need to visit.")
    end
end

-- WoW Forever names have a first and a last name, and two characters can share the first name
-- (Lovac Ulmo, Lovac Kasapin). The key adds the end of the character's GUID, which never changes.
local function CharKey()
    local key = (GetRealmName() or "Unknown") .. "-" .. (UnitName("player") or "Unknown")
    local guid = UnitGUID and UnitGUID("player")
    local tail = guid and guid:match("([^-]+)$")
    return tail and (key .. "-" .. tail) or key
end

-- The last name, if this client tells it: UnitName's second value or the full unit name.
-- Every candidate is saved too (nameInfo), so the right source can be checked in the save file.
local function LastName()
    local first, second = UnitName("player")
    local full = GetUnitName and GetUnitName("player", true)
    local realm = GetRealmName()
    if second and second ~= "" and second ~= realm then return second, { second = second, full = full } end
    local last = full and full ~= first and full:match("^" .. (first or "") .. "[%s%-](.+)$")
    if last and last ~= realm and last ~= (realm or ""):gsub("%s", "") then return last, { second = second, full = full } end
    return nil, { second = second, full = full }
end

local function QuestLogForChar()
    WoWForeverLevelerQuestLog = WoWForeverLevelerQuestLog or {}
    local key = CharKey()
    WoWForeverLevelerQuestLog[key] = WoWForeverLevelerQuestLog[key] or { accepted = {}, done = {} }
    return WoWForeverLevelerQuestLog[key]
end

-- Journey: what the player does, in order. It is also the recorded quest route (scripts/build_routes.py):
-- log.journey = { { k = "zone"|"level"|"accept"|"turnin"|"done", t, level, zone, subzone, id, title, npc,
-- m (map ID), x, y }, ... }, newest last, at most 5000 entries (the oldest go first). "done" = the quest's
-- objectives just finished (where the last kill or item was).
local JOURNEY_MAX = 5000
local function Journey(entry)
    local log = QuestLogForChar()
    log.journey = log.journey or {}
    entry.t = time()
    entry.level = entry.level or UnitLevel("player")
    entry.zone = entry.zone or GetRealZoneText()
    entry.subzone = entry.subzone or GetSubZoneText()
    if entry.k ~= "zone" and entry.k ~= "level" and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            entry.m, entry.x, entry.y = mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
        end
    end
    table.insert(log.journey, entry)
    while #log.journey > JOURNEY_MAX do table.remove(log.journey, 1) end
end

-- A zone step only when the zone really changed (the event also fires inside one zone).
local function JourneyZone()
    local log = QuestLogForChar()
    local zone = GetRealZoneText()
    if not zone or zone == "" then return end
    for i = #(log.journey or {}), 1, -1 do
        local e = log.journey[i]
        if e.k == "zone" then
            if e.zone == zone then return end
            break
        end
    end
    Journey({ k = "zone", zone = zone })
end

local function OnQuestAccepted(questID)
    if questID then
        local log = QuestLogForChar()
        log.acceptedAt = log.acceptedAt or {}
        log.acceptedAt[questID] = { level = UnitLevel("player"), time = time() }
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        local npc = UnitName("questnpc") or UnitName("npc")
        pcall(Journey, { k = "accept", id = questID, title = title, npc = npc })
        QuestLogForChar().accepted[questID] = GetRealZoneText()
    end
end

local function OnQuestComplete()
    -- The reward window is the last point where the quest title is reliably readable.
    local questID = GetQuestID and GetQuestID()
    if questID and questID > 0 then
        pendingTitles[questID] = GetTitleText()
    end
end

local function OnQuestTurnedIn(questID, xpReward)
    local log = QuestLogForChar()
    local title = pendingTitles[questID]
    if not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID)
    end
    table.insert(log.done, {
        id = questID,
        title = title or ("Quest " .. questID),
        acceptZone = log.accepted[questID],
        acceptLevel = log.acceptedAt and log.acceptedAt[questID] and log.acceptedAt[questID].level or nil,
        acceptTime = log.acceptedAt and log.acceptedAt[questID] and log.acceptedAt[questID].time or nil,
        turnInZone = GetRealZoneText(),
        level = UnitLevel("player"),
        xp = xpReward or 0,
        time = time(),
    })
    log.accepted[questID] = nil
    if log.acceptedAt then log.acceptedAt[questID] = nil end
    pendingTitles[questID] = nil
    pcall(Journey, { k = "turnin", id = questID, title = title, npc = UnitName("questnpc") or UnitName("npc") })
end

-- "done" steps: a quest in the log whose objectives just finished. The first look after login only learns
-- what is already complete (no step); later looks record each quest that turned complete since.
local completeSeen
local function CheckQuestsComplete()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.IsComplete) then return end
    local first = completeSeen == nil
    completeSeen = completeSeen or {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 and not completeSeen[id] and C_QuestLog.IsComplete(id) then
            completeSeen[id] = true
            if not first then pcall(Journey, { k = "done", id = id, title = info.title }) end
        end
    end
end

local checkQueued
local function QueueQuestCheck()
    if checkQueued or not C_Timer then return end
    checkQueued = true
    C_Timer.After(0.5, function() checkQueued = false; pcall(CheckQuestsComplete) end)
end

local function GetPrimaryProfessions()
    local profs = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and PRIMARY_PROFESSIONS[name] then
                table.insert(profs, { name = name, rank = rank, maxRank = maxRank })
            end
        end
    elseif GetProfessions then
        local prof1, prof2 = GetProfessions()
        for _, idx in ipairs({ prof1, prof2 }) do
            local name, _, rank, maxRank = GetProfessionInfo(idx)
            table.insert(profs, { name = name, rank = rank, maxRank = maxRank })
        end
    end
    return profs
end

-- Every quest ID this character has finished (also quests done before the addon was installed),
-- so the dashboard can tick dungeon quests.
local function CompletedQuestIDs()
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        return C_QuestLog.GetAllCompletedQuestIDs() or {}
    end
    local ids = {}
    if GetQuestsCompleted then
        for id in pairs(GetQuestsCompleted()) do table.insert(ids, id) end
    end
    return ids
end

-- Records known recipes with reagents, difficulty colour and bag counts.
-- Classic uses the TradeSkill API for most professions and the Craft API for Enchanting.
local function SaveRecipes(api)
    local profName, rank, maxRank, count
    if api == "craft" then
        if not GetCraftDisplaySkillLine then return end
        profName, rank, maxRank = GetCraftDisplaySkillLine()
        count = GetNumCrafts()
    else
        if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillReagentInfo) then return end
        profName, rank, maxRank = GetTradeSkillLine()
        count = GetNumTradeSkills()
    end
    if not profName or not PRIMARY_PROFESSIONS[profName] then return end

    local recipes = {}
    for i = 1, count do
        local name, difficulty, numReagents, _
        if api == "craft" then
            name, _, difficulty = GetCraftInfo(i)
            numReagents = GetCraftNumReagents(i)
        else
            name, difficulty = GetTradeSkillInfo(i)
            numReagents = GetTradeSkillNumReagents(i)
        end
        if name and difficulty ~= "header" then
            local reagents = {}
            for r = 1, (numReagents or 0) do
                local rName, rCount, rHave
                if api == "craft" then
                    rName, _, rCount, rHave = GetCraftReagentInfo(i, r)
                else
                    rName, _, rCount, rHave = GetTradeSkillReagentInfo(i, r)
                end
                if rName then
                    table.insert(reagents, { name = rName, count = rCount or 1, have = rHave or 0 })
                end
            end
            recipes[name] = { difficulty = difficulty, reagents = reagents }
        end
    end

    WoWForeverLevelerRecipes = WoWForeverLevelerRecipes or {}
    local key = CharKey()
    WoWForeverLevelerRecipes[key] = WoWForeverLevelerRecipes[key] or {}
    WoWForeverLevelerRecipes[key][profName] = { rank = rank, maxRank = maxRank, scanned = time(), recipes = recipes }
end

-- Modern recipe API (C_TradeSkillUI). Difficulty numbers follow Enum.TradeskillRelativeDifficulty.
local MODERN_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local lastModernScan = 0

local function ModernProfessionLine()
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if info and info.professionName then
        return info.professionName, info.skillLevel, info.maxSkillLevel
    end
    if C_TradeSkillUI.GetTradeSkillLine then
        local _, name, rank, maxRank = C_TradeSkillUI.GetTradeSkillLine()
        return name, rank, maxRank
    end
end

-- Returns the reagent list and whether any reagent name was still loading.
local function ModernReagents(recipeID)
    local list, missing = {}, false
    if C_TradeSkillUI.GetRecipeSchematic then
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
            local reagent = slot.reagents and slot.reagents[1]
            local basic = slot.reagentType == nil or slot.reagentType == 1
            if reagent and reagent.itemID and basic then
                local name = ItemNameByID(reagent.itemID)
                if name then
                    table.insert(list, { name = name, count = slot.quantityRequired or 1, have = ItemCountByID(reagent.itemID) })
                else
                    missing = true
                end
            end
        end
    elseif C_TradeSkillUI.GetRecipeNumReagents and C_TradeSkillUI.GetRecipeReagentInfo then
        for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) or 0 do
            local name, _, count, have = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
            if name then table.insert(list, { name = name, count = count or 1, have = have or 0 }) end
        end
    end
    return list, missing
end

local MAX_NAME_RETRIES = 3
local modernRescanPending = false
local nameRetries = 0

local function SaveRecipesModern(isRetry)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
    if not C_Timer then return end
    -- The list-update event fires in bursts; read at most every 2 seconds, and always once after the burst.
    if not isRetry and GetTime() - lastModernScan < 2 then
        if not modernRescanPending then
            modernRescanPending = true
            C_Timer.After(2.1, function()
                modernRescanPending = false
                SaveRecipesModern()
            end)
        end
        return
    end
    lastModernScan = GetTime()
    if not isRetry then nameRetries = 0 end

    local profName, rank, maxRank = ModernProfessionLine()
    if not profName or not PRIMARY_PROFESSIONS[profName] then return end

    -- The open window's profession name can lag behind its recipe list, so file each
    -- recipe under the profession the client reports for that recipe.
    local byProfession, anyMissing = {}, false
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned and info.name then
            local owner = profName
            if C_TradeSkillUI.GetProfessionInfoByRecipeID then
                local p = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
                owner = (p and (p.parentProfessionName or p.professionName)) or profName
            end
            if PRIMARY_PROFESSIONS[owner] then
                local difficulty = MODERN_DIFFICULTY[info.relativeDifficulty] or info.difficulty or "optimal"
                local reagents, missing = ModernReagents(recipeID)
                anyMissing = anyMissing or missing
                byProfession[owner] = byProfession[owner] or {}
                byProfession[owner][info.name] = { difficulty = difficulty, reagents = reagents }
            end
        end
    end

    WoWForeverLevelerRecipes = WoWForeverLevelerRecipes or {}
    local key = CharKey()
    WoWForeverLevelerRecipes[key] = WoWForeverLevelerRecipes[key] or {}
    for owner, recipes in pairs(byProfession) do
        local isOpen = owner == profName
        WoWForeverLevelerRecipes[key][owner] = {
            rank = isOpen and rank or nil, maxRank = isOpen and maxRank or nil, scanned = time(), recipes = recipes,
        }
    end

    -- Uncached item names were requested from the server; read again once they have arrived.
    if anyMissing and nameRetries < MAX_NAME_RETRIES then
        nameRetries = nameRetries + 1
        C_Timer.After(2, function() SaveRecipesModern(true) end)
    end
end

-- --- Profession trainer scan -----------------------------------------------
-- Saves every recipe a profession trainer teaches (also ones not learnable yet) with the
-- skill, level and cost needed. Trainer lists are the same for every character, so they are
-- stored per profession for the whole account: WoWForeverLevelerTrainer[profession][recipe].
local TRAINER_FILTERS = { "available", "unavailable", "used" }
local trainerScanning = false

-- The modern client wants true/false for the filter; Classic clients want 1/0.
local function SetTrainerFilter(filter, on)
    if not pcall(SetTrainerServiceTypeFilter, filter, on) then
        SetTrainerServiceTypeFilter(filter, on and 1 or 0)
    end
end

-- "Apprentice Skinning" -> "Skinning" (a profession rank as one name), else nil.
local SKILL_RANKS = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true, Master = true }
local function RankProfession(name)
    local rank, prof = (name or ""):match("^(%a+) (.+)$")
    if SKILL_RANKS[rank] and PRIMARY_PROFESSIONS[prof] then return prof end
end

-- True when the open trainer teaches a profession. The Forever client has no IsTradeskillTrainer,
-- so the list decides: profession services need a profession skill or are a profession rank.
local function ListIsProfession()
    for i = 1, GetNumTrainerServices() or 0 do
        local name = GetTrainerServiceInfo(i)
        local skillName = GetTrainerServiceSkillReq(i)
        if (skillName and PRIMARY_PROFESSIONS[skillName]) or PRIMARY_PROFESSIONS[name or ""] or RankProfession(name) then
            return true
        end
    end
    return false
end

local SERVICE_STATES = { available = true, unavailable = true, used = true, header = true }
local trainerIsClass = false -- set when the trainer window opens; RememberTrainer reads it a second later

-- Returns (recipes found, recipes not seen before).
local function ReadTrainerServices()
    local found, added = 0, 0
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank, category = GetTrainerServiceInfo(i)
        local skillName, skillLevel = GetTrainerServiceSkillReq(i)
        -- The rank itself ("Skinning", rank "Apprentice") has no skill requirement: save it as
        -- "Apprentice Skinning" so its training cost is known too.
        if name and PRIMARY_PROFESSIONS[name] and rank and rank ~= "" then
            skillName, name = name, rank .. " " .. name
        elseif not skillName and RankProfession(name) then
            skillName = RankProfession(name)
        end
        if name and category ~= "header" and skillName and PRIMARY_PROFESSIONS[skillName] then
            WoWForeverLevelerTrainer = WoWForeverLevelerTrainer or {}
            WoWForeverLevelerTrainer[skillName] = WoWForeverLevelerTrainer[skillName] or {}
            if not WoWForeverLevelerTrainer[skillName][name] then added = added + 1 end
            WoWForeverLevelerTrainer[skillName][name] = {
                skill = skillLevel or 0,
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil,
                seen = time(),
            }
            found = found + 1
        end
    end
    return found, added
end

-- The profession this trainer teaches, read from the list as the player sees it (no filter changes).
-- The trainer's title under its name ("<Skinning Trainer>", "Junior Skinning Trainer"), when the client
-- offers unit tooltip data.
local function TrainerTitleProfession()
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local data = C_TooltipInfo.GetUnit("npc")
    for _, line in ipairs(data and data.lines or {}) do
        local prof = (line.leftText or ""):match("^<?(.-) Trainer>?$")
        if prof then
            prof = prof:gsub("^Junior ", "")
            if PRIMARY_PROFESSIONS[prof] then return prof end
        end
    end
end

local function TrainerProfession()
    for i = 1, GetNumTrainerServices() or 0 do
        local name = GetTrainerServiceInfo(i)
        local skillName = GetTrainerServiceSkillReq(i)
        if skillName and PRIMARY_PROFESSIONS[skillName] then return skillName end
        if PRIMARY_PROFESSIONS[name or ""] then return name end
        if RankProfession(name) then return RankProfession(name) end
    end
    -- A Junior trainer may list nothing that names the profession (e.g. once it is learned): use its title.
    return TrainerTitleProfession()
end

-- Class trainer: every skill and rank with the level it needs and its cost, per class for the
-- whole account: WoWForeverLevelerClassTrainer[class]["Arcane Shot (Rank 2)"] = { level, cost, seen }.
local function ReadClassTrainer()
    local _, classFile = UnitClass("player")
    if not classFile then return 0, 0 end
    WoWForeverLevelerClassTrainer = WoWForeverLevelerClassTrainer or {}
    local book = WoWForeverLevelerClassTrainer[classFile] or {}
    WoWForeverLevelerClassTrainer[classFile] = book
    local found, added = 0, 0
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank, category = GetTrainerServiceInfo(i)
        -- The Forever client returns the status ("available", "unavailable", "used") as the second
        -- value, where Classic gives the rank ("Rank 2").
        if SERVICE_STATES[rank or ""] then rank, category = nil, rank end
        if name and category ~= "header" then
            local key = (rank and rank ~= "") and string.format("%s (%s)", name, rank) or name
            if not book[key] then added = added + 1 end
            book[key] = {
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil,
                seen = time(),
            }
            found = found + 1
        end
    end
    return found, added
end

-- Shows every service while reading, then restores the player's own filter choice.
local function WithAllServices(read)
    trainerScanning = true
    local changed = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs(TRAINER_FILTERS) do
            if not GetTrainerServiceTypeFilter(f) then
                SetTrainerFilter(f, true)
                table.insert(changed, f)
            end
        end
    end
    local ok, found, added = pcall(read)
    for _, f in ipairs(changed) do SetTrainerFilter(f, false) end
    trainerScanning = false
    if not ok then error(found, 0) end
    return found, added
end

local function SaveClassTrainer()
    local _, classFile = UnitClass("player")
    local key, level = "class:" .. (classFile or "?"), UnitLevel("player")
    if ScannedBefore(key, level) then return 1 end
    local found, added = WithAllServices(ReadClassTrainer)
    if found > 0 then MarkScanned(key, level) end
    -- Only new skills are worth a chat line; a repeat visit stays quiet.
    if added > 0 then
        Log(string.format("|cffffd100WoW Forever Leveler:|r class trainer: %d new skills saved with their cost.", added), true)
    end
    return found
end

-- Returns the number of recipes read, so the caller knows whether the list was still empty.
local function SaveTrainer()
    if trainerScanning then return 0 end
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) then return 0 end
    local isProfession
    if IsTradeskillTrainer then
        isProfession = IsTradeskillTrainer() and true or false
    else
        isProfession = WithAllServices(function() return ListIsProfession(), 0 end)
    end
    trainerIsClass = not isProfession
    if trainerIsClass then return SaveClassTrainer() end
    local found, added = WithAllServices(ReadTrainerServices)
    if added > 0 then
        Log(string.format("|cffffd100WoW Forever Leveler:|r saved %d new trainer recipes.", added), true)
    end
    return found
end

-- Trainer APIs differ between clients; an error here must not break the trainer window.
-- It goes to the saved log instead, so it can be read from the save file after /reload.
local function SafeSaveTrainer()
    -- Checked here, and marked only after a real read, so a skipped visit does not renew the date.
    local visitKey, level = "trainer:" .. (UnitName("npc") or "?"), UnitLevel("player")
    if ScannedBefore(visitKey, level) then return 1 end
    local ok, result = pcall(SaveTrainer)
    if ok and (result or 0) > 0 then MarkScanned(visitKey, level) end
    if not ok then
        trainerScanning = false
        Log("|cffff4040WoW Forever Leveler:|r trainer scan error: " .. tostring(result))
        return 1
    end
    return result
end

-- --- Recipe vendor scan ----------------------------------------------------
-- Saves recipe items a vendor sells: WoWForeverLevelerVendors[recipe] = { item, profession, skill,
-- vendors = { [vendor] = { zone, subzone, price, limited, seen } } }.
local RECIPE_PREFIXES = {
    ["Pattern: "] = false, -- Tailoring or Leatherworking: decided from the tooltip
    ["Formula: "] = "Enchanting", ["Plans: "] = "Blacksmithing", ["Schematic: "] = "Engineering",
    ["Recipe: "] = false, -- Alchemy or Cooking: decided from the tooltip
    ["Design: "] = false, ["Manual: "] = "First Aid",
}

local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.name, info.price, info.numAvailable end
    end
    if GetMerchantItemInfo then
        local name, _, price, _, numAvailable = GetMerchantItemInfo(i)
        return name, price, numAvailable
    end
end

-- Reads "Requires Tailoring (75)" from the item's tooltip, when the client offers tooltip data.
-- Third value: true when the tooltip was readable, so a missing match means "not a tracked profession".
local function MerchantRequirement(i)
    if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return nil, nil, false end
    local data = C_TooltipInfo.GetMerchantItem(i)
    local lines = data and data.lines or {}
    for _, line in ipairs(lines) do
        local text = line.leftText or ""
        local prof, skill = text:match("Requires (.-) %((%d+)%)")
        if prof then
            return PRIMARY_PROFESSIONS[prof] and prof or nil, tonumber(skill), true
        end
    end
    return nil, nil, #lines > 0
end

local function SaveVendor()
    if not GetMerchantNumItems then return end
    local vendor = UnitName("npc") or "Unknown vendor"
    local added = 0
    for i = 1, GetMerchantNumItems() or 0 do
        local itemName, price, numAvailable = MerchantItem(i)
        for prefix, guessed in pairs(RECIPE_PREFIXES) do
            if itemName and itemName:sub(1, #prefix) == prefix then
                local recipe = itemName:sub(#prefix + 1)
                local prof, skill, readable = MerchantRequirement(i)
                if not readable then prof = guessed or nil end
                if prof then
                    WoWForeverLevelerVendors = WoWForeverLevelerVendors or {}
                    local entry = WoWForeverLevelerVendors[recipe] or { vendors = {} }
                    if not entry.vendors[vendor] then added = added + 1 end
                    entry.item, entry.profession, entry.skill = itemName, prof, skill or entry.skill
                    entry.vendors[vendor] = {
                        zone = GetRealZoneText(), subzone = GetSubZoneText(), price = price,
                        limited = (numAvailable and numAvailable >= 0) and numAvailable or nil, seen = time(),
                    }
                    WoWForeverLevelerVendors[recipe] = entry
                end
                break
            end
        end
    end
    if added > 0 then
        Log(string.format("|cffffd100WoW Forever Leveler:|r saved %d new recipes sold by %s.", added, vendor), true)
    end
end

-- --- Where trainers and recipe vendors stand ------------------------------------
-- WoWForeverLevelerNPCs[name] = { kind, profession, zone, subzone, mapID, x, y, seen }. Every visit
-- updates it, so the dashboard map follows the game. WoWForeverLevelerNPCPlan (NPCList.lua) is the
-- Classic list of city trainers, used for the reminder when you enter a city.
local function PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID end
    local x, y = pos:GetXY()
    return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function RememberNPC(kind, profession)
    local name = UnitName("npc")
    if not name then return end
    local mapID, x, y = PlayerPosition()
    WoWForeverLevelerNPCs = WoWForeverLevelerNPCs or {}
    local e = WoWForeverLevelerNPCs[name] or {}
    e.kind, e.profession = kind, profession or e.profession
    e.zone, e.subzone, e.mapID, e.x, e.y, e.seen = GetRealZoneText(), GetSubZoneText(), mapID, x, y, time()
    WoWForeverLevelerNPCs[name] = e
end

local function RememberTrainer()
    -- The map position is saved once per trainer (again after a patch); the to-visit window still refreshes.
    local key = "npc:" .. (UnitName("npc") or "?")
    -- A profession trainer saved without its profession is read again.
    local saved = (WoWForeverLevelerNPCs or {})[UnitName("npc") or "?"]
    local unknown = saved and saved.kind == "trainer" and not saved.profession
    if ScannedBefore(key) and not unknown then return RefreshTodo() end
    MarkScanned(key)
    if trainerIsClass then
        return RememberNPC("class trainer", (UnitClass("player")))
    end
    RememberNPC("trainer", TrainerProfession())
    RefreshTodo()
end

-- Bag vendors: WoWForeverLevelerBagVendors[vendor] = { zone, subzone, mapID, x, y, seen,
-- bags = { [bag] = { slots, price } } }, so the route can say where to buy a bag if none dropped.
local function MerchantItemID(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info and info.itemID then return info.itemID end
    end
    return GetMerchantItemID and GetMerchantItemID(i) or nil
end

local function MerchantBagSlots(i)
    if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return nil end
    local data = C_TooltipInfo.GetMerchantItem(i)
    for _, line in ipairs(data and data.lines or {}) do
        local slots = (line.leftText or ""):match("^(%d+) Slot")
        if slots then return tonumber(slots) end
    end
end

local function SaveBagVendor()
    if not GetMerchantNumItems then return end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local bags = {}
    for i = 1, GetMerchantNumItems() or 0 do
        local itemID = MerchantItemID(i)
        local classID = itemID and getInstant and select(6, getInstant(itemID))
        if classID == 1 then -- Container
            local name, price = MerchantItem(i)
            if name then bags[name] = { slots = MerchantBagSlots(i), price = price } end
        end
    end
    if not next(bags) then return end
    local vendor = UnitName("npc") or "Unknown vendor"
    local mapID, x, y = PlayerPosition()
    WoWForeverLevelerBagVendors = WoWForeverLevelerBagVendors or {}
    local isNew = not WoWForeverLevelerBagVendors[vendor]
    WoWForeverLevelerBagVendors[vendor] = { zone = GetRealZoneText(), subzone = GetSubZoneText(),
        mapID = mapID, x = x, y = y, seen = time(), bags = bags }
    if isNew then
        Log(string.format("|cffffd100WoW Forever Leveler:|r saved bag vendor %s.", vendor), true)
    end
end

-- Shop prices: WoWForeverLevelerShopPrices[item] = { price, per, stack, vendor, zone, seen } for every
-- item a vendor sells, the cheapest seen (prices drop with reputation). The dashboard's shopping lists
-- use them (cost and bag slots); stack is the item's max stack size, per the quantity one purchase gives.
local function ItemMaxStack(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemMaxStackSize then
        local ok, n = pcall(C_Item.GetItemMaxStackSize, itemID)
        if ok and n then return n end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, n = pcall(function() return select(8, getInfo(itemID)) end)
        if ok then return n end
    end
end

local function SaveShopPrices()
    if not GetMerchantNumItems then return end
    WoWForeverLevelerShopPrices = WoWForeverLevelerShopPrices or {}
    local vendor, zone = UnitName("npc") or "Unknown vendor", GetRealZoneText()
    for i = 1, GetMerchantNumItems() or 0 do
        local name, price, per
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then name, price, per = info.name, info.price, info.stackCount end
        elseif GetMerchantItemInfo then
            local _
            name, _, price, per = GetMerchantItemInfo(i)
        end
        if name and price and price > 0 then
            local old = WoWForeverLevelerShopPrices[name]
            local unit = price / math.max(per or 1, 1)
            if not old or unit < old.price / math.max(old.per or 1, 1) then
                WoWForeverLevelerShopPrices[name] = { price = price, per = per or 1, stack = ItemMaxStack(MerchantItemID(i)),
                    vendor = vendor, zone = zone, seen = time() }
            end
        end
    end
end

-- A vendor is saved only when it sells recipes; the professions come from the recipe names.
local function RememberVendor()
    if not GetMerchantNumItems then return end
    local profs, seen = {}, {}
    for i = 1, GetMerchantNumItems() or 0 do
        local itemName = MerchantItem(i)
        for prefix, guessed in pairs(RECIPE_PREFIXES) do
            if itemName and itemName:sub(1, #prefix) == prefix then
                -- "Pattern:" can be Tailoring or Leatherworking: the tooltip says which.
                local required = MerchantRequirement(i)
                local prof = required or guessed or "Recipes"
                if not seen[prof] then seen[prof] = true; table.insert(profs, prof) end
                break
            end
        end
    end
    if #profs > 0 then
        table.sort(profs)
        RememberNPC("vendor", table.concat(profs, ", "))
    end
end

local function SafeSaveVendor()
    -- Shop prices at every visit (a short loop, the cheapest price wins); recipes, bags and the map
    -- position once per vendor (again after a patch).
    local okShop, errShop = pcall(SaveShopPrices)
    if not okShop then Log("|cffff4040WoW Forever Leveler:|r shop price error: " .. tostring(errShop)) end
    local key = "vendor:" .. (UnitName("npc") or "?")
    if ScannedBefore(key) then return end
    MarkScanned(key)
    local ok, err = pcall(SaveVendor)
    if not ok then Log("|cffff4040WoW Forever Leveler:|r vendor scan error: " .. tostring(err)) end
    ok, err = pcall(SaveBagVendor)
    if not ok then Log("|cffff4040WoW Forever Leveler:|r bag vendor error: " .. tostring(err)) end
    ok, err = pcall(RememberVendor)
    if not ok then Log("|cffff4040WoW Forever Leveler:|r vendor map error: " .. tostring(err)) end
end

-- In a city, name the trainers for this character's professions that it has not visited yet.
-- A trainer counts as visited when any trainer of that profession was saved in this city.
-- Trainers for this character's professions not visited yet, per city: { {city, {lines}} }.
-- A trainer counts as visited when any trainer of that profession was saved in that city.
local function TrainersToVisit(onlyCity)
    local mine = {}
    for _, p in ipairs(GetPrimaryProfessions()) do mine[p.name] = true end
    local cities = {}
    for city in pairs(WoWForeverLevelerNPCPlan or {}) do
        if not onlyCity or city == onlyCity then table.insert(cities, city) end
    end
    table.sort(cities)
    local result = {}
    for _, city in ipairs(cities) do
        local visited = {}
        for _, e in pairs(WoWForeverLevelerNPCs or {}) do
            if e.zone == city and e.kind == "trainer" and e.profession then visited[e.profession] = true end
        end
        local lines = {}
        for _, npc in ipairs(WoWForeverLevelerNPCPlan[city]) do
            if mine[npc.profession] and not visited[npc.profession] then
                table.insert(lines, string.format("|cffffd100%s:|r %s (%s)", npc.profession, npc.name, npc.where))
            end
        end
        if #lines > 0 then table.insert(result, { city = city, lines = lines }) end
    end
    return result
end

-- A small movable window. In a city it lists that city; elsewhere every city. Its position is kept.
local todoFrame
local function EnsureTodoFrame()
    if todoFrame then return todoFrame end
    todoFrame = CreateFrame("Frame", "WoWForeverLevelerTodo", UIParent, "BasicFrameTemplateWithInset")
    todoFrame:SetSize(380, 120)
    todoFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -160)
    todoFrame:SetMovable(true)
    todoFrame:EnableMouse(true)
    todoFrame:RegisterForDrag("LeftButton")
    todoFrame:SetScript("OnDragStart", todoFrame.StartMoving)
    todoFrame:SetScript("OnDragStop", todoFrame.StopMovingOrSizing)
    todoFrame:SetClampedToScreen(true)
    todoFrame.title = todoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    todoFrame.title:SetPoint("TOP", todoFrame, "TOP", 0, -5)
    todoFrame.text = todoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    todoFrame.text:SetPoint("TOPLEFT", todoFrame, "TOPLEFT", 14, -32)
    todoFrame.text:SetWidth(352)
    todoFrame.text:SetJustifyH("LEFT")
    todoFrame.text:SetJustifyV("TOP")
    todoFrame.text:SetSpacing(3)
    todoFrame:Hide()
    return todoFrame
end

RefreshTodo = function()
    if not (todoFrame and todoFrame:IsShown()) then return end
    local zone = GetRealZoneText()
    local inCity = zone and (WoWForeverLevelerNPCPlan or {})[zone]
    local groups = TrainersToVisit(inCity and zone or nil)
    local out = {}
    for _, g in ipairs(groups) do
        if not inCity then table.insert(out, "|cff80c0ff" .. g.city .. "|r") end
        for _, line in ipairs(g.lines) do table.insert(out, line) end
    end
    if #out == 0 then
        table.insert(out, inCity and "All your trainers here are visited." or "All your trainers in the cities are visited.")
    else
        table.insert(out, "|cff999999Names are from Classic; ask a guard if one is missing.|r")
    end
    todoFrame.title:SetText(inCity and ("Trainers to visit: " .. zone) or "Trainers to visit")
    todoFrame.text:SetText(table.concat(out, "\n"))
    todoFrame:SetHeight(todoFrame.text:GetStringHeight() + 48)
end

ToggleTodo = function()
    local f = EnsureTodoFrame()
    if f:IsShown() then f:Hide() else f:Show(); RefreshTodo() end
end

-- Entering a city with trainers still to visit opens the window once per city and session.
local remindedZones = {}
local function RemindTrainers()
    local zone = GetRealZoneText()
    if RefreshTodo then RefreshTodo() end
    if not zone or not (WoWForeverLevelerNPCPlan or {})[zone] or remindedZones[zone] then return end
    remindedZones[zone] = true
    if #TrainersToVisit(zone) > 0 then
        local f = EnsureTodoFrame()
        f:Show()
        RefreshTodo()
    end
end

local function SaveCharacterState(event, arg1)
    WoWForeverLevelerDB = WoWForeverLevelerDB or {}
    -- Looting money fires often: only the gold changes, so skip the full save (quest list, professions).
    local known = WoWForeverLevelerDB[CharKey()]
    if event == "PLAYER_MONEY" and known then
        known.money = GetMoney()
        return
    end

    local realm = GetRealmName() or "Unknown"
    local name = UnitName("player") or "Unknown"
    local charKey = CharKey()
    local previous = WoWForeverLevelerDB[charKey] or {}
    local lastName, nameInfo = LastName()

    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local maxXP = UnitXPMax("player")

    -- XP and skill APIs can return empty values during logout; keep the last good values.
    local xp, xpMax = previous.xp, previous.maxXp
    if maxXP and maxXP > 0 then
        xp, xpMax = UnitXP("player"), maxXP
    end

    local profs = GetPrimaryProfessions()
    if #profs == 0 and previous.professions then
        profs = previous.professions
    end

    local completed = CompletedQuestIDs()
    if #completed == 0 and previous.completedQuests then
        completed = previous.completedQuests
    end
    table.sort(completed)
    local questCount = #completed
    if questCount == 0 and previous.completedQuestsCount then
        questCount = previous.completedQuestsCount
    end

    WoWForeverLevelerDB[charKey] = {
        name = name,
        lastName = lastName or previous.lastName,
        nameInfo = nameInfo,
        guid = UnitGUID and UnitGUID("player") or nil,
        realm = realm,
        class = classFile,
        race = raceFile,
        -- PLAYER_LEVEL_UP passes the new level before UnitLevel shows it, and at logout UnitLevel
        -- can report 1 on the Forever client: a level never goes down, so keep the highest.
        level = math.max((event == "PLAYER_LEVEL_UP" and tonumber(arg1)) or UnitLevel("player") or 0, previous.level or 0),
        xp = xp or 0,
        maxXp = xpMax or 0,
        -- Rested XP left (bonus XP for kills) and whether the character rests in an inn or a city,
        -- so the dashboard can show which character has the most rested XP. At logout the Forever client
        -- reports 0 and "not resting" (all beta characters were saved that way): keep the last values seen
        -- while playing (PLAYER_UPDATE_RESTING, UPDATE_EXHAUSTION and the other save events).
        restedXp = (event == "PLAYER_LOGOUT" and previous.restedXp) or (GetXPExhaustion and GetXPExhaustion()) or 0,
        resting = (event == "PLAYER_LOGOUT" and previous.resting ~= nil) and previous.resting or (IsResting and IsResting() or false),
        professions = profs,
        completedQuestsCount = questCount,
        completedQuests = completed,
        -- GetMoney() reports 0 during logout, so keep the last value seen while playing.
        money = (event == "PLAYER_LOGOUT") and previous.money or GetMoney(),
        lastUpdated = time(),
    }
end

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" and C_Timer then
        -- Logging in inside a city: remind once the chat is ready. PLAYER_LOGIN also saves state below.
        C_Timer.After(8, function() pcall(RemindTrainers) end)
        C_Timer.After(5, function() pcall(JourneyZone); pcall(CheckQuestsComplete) end)
        C_Timer.After(15, function() pcall(NameAuctionatorItems) end)
    end
    if event == "ADDON_LOADED" then
        if arg1 == "WoWForeverLeveler" then
            WoWForeverLevelerDB = WoWForeverLevelerDB or {}
            WoWForeverLevelerQuestLog = WoWForeverLevelerQuestLog or {}
        end
        return
    elseif event == "QUEST_ACCEPTED" then
        -- Classic passes (questLogIndex, questID); some clients pass only questID.
        return OnQuestAccepted(arg2 or arg1)
    elseif event == "QUEST_COMPLETE" then
        return OnQuestComplete()
    elseif event == "QUEST_LOG_UPDATE" then
        -- Fires often: one look per half second at most, and never a full save.
        if completeSeen then QueueQuestCheck() end
        return
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE" then
        if GetTradeSkillLine then return SaveRecipes("trade") end
        return SaveRecipesModern()
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        return SaveRecipes("craft")
    elseif event == "TRAINER_SHOW" then
        -- The list can still be loading when the window opens; only then read once more a moment later.
        if SafeSaveTrainer() == 0 and C_Timer then C_Timer.After(1, SafeSaveTrainer) end
        local function remember()
            local ok, err = pcall(RememberTrainer)
            if not ok then Log("|cffff4040WoW Forever Leveler:|r trainer map error: " .. tostring(err)) end
        end
        if C_Timer then C_Timer.After(1, remember) else remember() end
        return
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- The zone name can lag behind the event for a moment.
        if C_Timer then C_Timer.After(2, function() pcall(RemindTrainers); pcall(JourneyZone) end) end
        return
    elseif event == "MERCHANT_SHOW" then
        -- Item and tooltip data arrive a moment after the window opens: read once, a second later.
        if C_Timer then C_Timer.After(1, SafeSaveVendor) else SafeSaveVendor() end
        return
    elseif event == "TRAINER_UPDATE" then
        -- Our own filter changes fire this event; scanning here would loop.
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- Auctionator may have just scanned: name its new items while the player walks away.
        if C_Timer then C_Timer.After(2, function() pcall(NameAuctionatorItems) end) end
        return
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(arg1, arg2)
    elseif event == "PLAYER_LEVEL_UP" then
        -- The event passes the new level before UnitLevel shows it.
        pcall(Journey, { k = "level", level = tonumber(arg1) })
    end
    SaveCharacterState(event, arg1)
end)

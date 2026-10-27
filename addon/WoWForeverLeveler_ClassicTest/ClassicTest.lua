-- Classic alert test (user, 2026-10-26): WoW Forever is not out yet, so this small addon shows the Planner's big alert
-- (Alert.lua, the same file) on WoW Classic, fired by the same kinds of game events the Planner uses:
--   * money: the first time you reach 20c, 25c, 90c and 1s on this character (Skinning, bag, Fishing);
--   * character level: every level up;
--   * skill: every 5 skill points in any profession or weapon skill;
--   * new professions learned.
-- /wfltest        one test alert
-- /wfltest 3      three alerts at once (they queue)
-- /wfltest off    turn the event alerts off and on
-- Each alert and event goes into WFLClassicTestLog (the save file), so the result can be read after /reload.

local MONEY_STEPS = { 20, 25, 90, 100 }
local lastMoney, skills, ready = nil, nil, false

local function Log(s)
    WFLClassicTestLog = WFLClassicTestLog or {}
    table.insert(WFLClassicTestLog, date("%Y-%m-%d %H:%M:%S") .. "  " .. s)
    while #WFLClassicTestLog > 300 do table.remove(WFLClassicTestLog, 1) end
end

local function Alert(text, where, icon)
    Log("ALERT " .. text .. (where and (" (" .. where .. ")") or ""))
    WFL_Alert(text, where, icon)
end

local function Off() return WFLClassicTestLog and WFLClassicTestLog.off end

local function Skills()
    local out = {}
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name and not isHeader then out[name] = rank or 0 end
    end
    return out
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "SKILL_LINES_CHANGED" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(function()
        if event == "PLAYER_ENTERING_WORLD" then
            -- Start from what you have now, so login says nothing.
            lastMoney, skills = GetMoney(), Skills()
            ready = true
            Log("login: character level " .. (UnitLevel("player") or "?") .. ", money " .. lastMoney)
            return
        end
        if not ready or Off() then return end
        if event == "PLAYER_LEVEL_UP" then
            Alert("Character level " .. tostring(arg1) .. "!", "Level-up test", "Interface\\Icons\\Spell_Holy_SurgeOfLight")
        elseif event == "PLAYER_MONEY" then
            local now = GetMoney()
            for _, step in ipairs(MONEY_STEPS) do
                if lastMoney < step and now >= step then
                    Alert("You have " .. (step >= 100 and "1s" or (step .. "c")) .. " now.", "Money test", "Interface\\Icons\\INV_Misc_Coin_01")
                end
            end
            lastMoney = now
        elseif event == "SKILL_LINES_CHANGED" then
            local now = Skills()
            for name, rank in pairs(now) do
                local was = skills[name]
                if not was then
                    Alert("New skill: " .. name .. ".", "Skill test", "Interface\\Icons\\INV_Misc_Book_08")
                elseif math.floor(rank / 5) > math.floor(was / 5) then
                    Alert(name .. " skill " .. rank .. ".", "Skill test", "Interface\\Icons\\INV_Misc_Book_08")
                end
            end
            skills = now
        end
    end)
    if not ok then Log("ERROR " .. event .. ": " .. tostring(err)) end
end)

SLASH_WFLTEST1 = "/wfltest"
SlashCmdList["WFLTEST"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "off" then
        WFLClassicTestLog = WFLClassicTestLog or {}
        WFLClassicTestLog.off = not WFLClassicTestLog.off
        print("|cffffd100WFL test:|r event alerts " .. (WFLClassicTestLog.off and "off" or "on"))
        return
    end
    local n = tonumber(msg) or 1
    local samples = {
        { "When you have 20c: learn Skinning (10c) and buy a Skinning Knife (10c).", "Camp Narache: Nawka Wildsong" },
        { "Train Journeyman Skinning (5s).", "Dranh, The Barrens" },
        { "You can now gather Mageroyal and Swiftthistle.", "Herbalism skill 50" },
    }
    for i = 1, math.min(n, 3) do Alert(samples[i][1], samples[i][2]) end
end

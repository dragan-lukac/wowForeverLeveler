-- WoW Forever Leveler - Quests: the original window (version D, 3.30-3.32) with quest guidance. All code is shared
-- and lives in the core addon (WoWForeverLeveler/UI.lua); this addon only picks its tabs.
-- When the Planner is enabled too, the Planner wins and these tabs stay out (both together gave 7 tabs).
local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WoWForeverLeveler_Planner"))
    or (IsAddOnLoaded and IsAddOnLoaded("WoWForeverLeveler_Planner"))
local enabled = C_AddOns and C_AddOns.GetAddOnEnableState and UnitName
    and C_AddOns.GetAddOnEnableState("WoWForeverLeveler_Planner", UnitName("player")) or 0
if loaded or (type(enabled) == "number" and enabled > 0) or WFL.title == "WoW Forever Planner" then return end

WFL.RegisterTabs({
    { key = "now", label = "Now", lines = WFL.NowTabLines, search = true },
    { key = "route", label = "Route", lines = WFL.RouteTabLines },
    { key = "mat", label = "Materials", lines = WFL.MaterialTabLines },
})

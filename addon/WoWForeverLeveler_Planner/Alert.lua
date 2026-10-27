-- The big alert (user, 2026-10-24): a gold text in the middle of the screen with an icon and a place line under it,
-- the epic-loot sound, and the same text in chat so it stays there. Alerts queue: each shows 6 seconds, fades in 1,
-- then the next one comes. Nothing here needs the rest of the addon, so the Classic test addon
-- (WoWForeverLeveler_ClassicTest, a copy of this file made by `make addon`) shows exactly the same alert.
--
--   WFL_Alert(text, where, icon)   where and icon may be nil

local queue, showing, parts = {}, false, nil

local function Parts()
    if parts then return parts end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(760, 130)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:SetFrameStrata("HIGH")
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(52, 52)
    icon:SetPoint("TOP", f, "TOP", 0, 0)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
    title:SetWidth(760)
    title:SetTextColor(1, 0.82, 0)
    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetWidth(760)
    sub:SetTextColor(0.9, 0.9, 0.9)
    f:Hide()
    parts = { frame = f, icon = icon, title = title, sub = sub }
    return parts
end

local function ShowNext()
    local a = table.remove(queue, 1)
    if not a then showing = false return end
    showing = true
    local p = Parts()
    p.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_Note_01")
    p.title:SetText(a.text)
    p.sub:SetText(a.where or "")
    p.frame:SetAlpha(1)
    p.frame:Show()
    pcall(PlaySound, (SOUNDKIT and (SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.RAID_WARNING)) or 8959)
    local t = 0
    p.frame:SetScript("OnUpdate", function(_, e)
        t = t + (e or 0)
        if t > 6 then p.frame:SetAlpha(math.max(0, 7 - t)) end
        if t > 7 then
            p.frame:SetScript("OnUpdate", nil)
            p.frame:Hide()
            ShowNext()
        end
    end)
end

function WFL_Alert(text, where, icon)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100WFL:|r " .. text .. (where and (" |cff9d9d9d(" .. where .. ")|r") or ""))
    table.insert(queue, { text = text, where = where, icon = icon })
    if not showing then ShowNext() end
end

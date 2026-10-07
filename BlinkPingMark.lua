-- BlinkPingMark (WoW Forever / Retail API)
-- Click the left mouse button three times (or twice, see /bpm) on the same spot to open a ping
-- wheel there, drawn with the game's own radial wheel art. Addons may not call the ping API, so each wheel button is a secure button running
-- Blizzard's "/ping" macro command, which the client resolves itself:
--   clicked on a unit frame   -> that frame's unit        /ping [@unit] <type>
--   clicked on a world unit   -> that unit, when the client has a unit token for it (target,
--                                nameplate, party, raid...), else a contextual ping at the cursor
--   clicked on the ground     -> the spot under the cursor  /ping [@cursor] <type>
-- A ping made by a click lands where the cursor is at that click (the client hit-tests the cursor), so a
-- ground ping cannot be sent by clicking a wedge 80 px away from the wheel's middle. For the ground the
-- wedge is chosen by moving the cursor onto it (it stays selected) and the ping is sent by clicking the
-- wheel's middle, which is where the wheel opened. For a unit (frame or world unit) the spot does not
-- matter, so clicking the wedge sends at once.
-- Secure buttons cannot be shown or changed in combat, so the wheel only opens out of combat.
-- The other mouse button, clicked the same way on a unit frame, opens a wheel of raid target icons for
-- that unit (SetRaidTarget is not protected: plain buttons, works in combat too).
-- Settings: Options -> AddOns -> BlinkPingMark (clicks, mouse button, where it is active), or
--   /bpm                 open the settings
--   /bpm clicks 2|3      how many clicks open the wheel
--   /bpm button left|right
--   /bpm interval <s>    longest pause between clicks (default 0.4)
--   /bpm small           toggle the small wheel
--   /bpm quick           toggle: a wedge click always sends at once (ground pings land under the cursor)
--   /bpm mark            toggle the mark wheel (other mouse button on unit frames)
--   /bpm group           toggle "only in a group"
--   /bpm test            open the wheel at the cursor

local ADDON_NAME = ...

local DEFAULTS = { clicks = 3, button = "LeftButton", interval = 0.4, small = false, quick = false, mark = true, groupOnly = true, debug = false,
                   zones = { world = true, city = true, dungeon = true, raid = true, battleground = true, arena = true } }
local db

-- Where the player is: one of the keys of db.zones
local CITY_MAPS = { -- Classic capitals (uiMapID)
    [1453] = true, [1455] = true, [1457] = true, -- Stormwind, Ironforge, Darnassus
    [1454] = true, [1456] = true, [1458] = true, -- Orgrimmar, Thunder Bluff, Undercity
}
local ZoneKind

-- Pings and raid icons are for a group: with db.groupOnly nothing opens while solo
local function Allowed()
    if db.groupOnly and not IsInGroup() then return false end
    return db.zones[ZoneKind()]
end

function ZoneKind()
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "scenario" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    if instanceType == "pvp" then return "battleground" end
    if instanceType == "arena" then return "arena" end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and CITY_MAPS[map] then return "city" end
    if GetZonePVPInfo and GetZonePVPInfo() == "sanctuary" then return "city" end
    return "world"
end

local PREFIX = "|cff66ccffBlinkPingMark|r: "
local function Print(fmt, ...)
    print(PREFIX .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end
local function Debug(fmt, ...)
    if db and db.debug then Print(fmt, ...) end
end

---------------------------------------------------------------------------
-- Ping types: "/ping <n>" accepts these numbers (Blizzard_ChatFrameBase SlashCommandsOverrides.lua)
---------------------------------------------------------------------------
local E = Enum and Enum.PingSubjectType or {}
local TYPES = {
    { type = E.Attack or 0,  number = "1", kit = "Attack",  name = "Attack" },
    { type = E.Warning or 1, number = "2", kit = "Warning", name = "Warning" },
    { type = E.OnMyWay or 3, number = "3", kit = "OnMyWay", name = "On my way" },
    { type = E.Assist or 2,  number = "4", kit = "Assist",  name = "Assist" },
}
local NUMBER_OF = {}
for _, t in ipairs(TYPES) do NUMBER_OF[t.type] = t.number end

-- The client's own wheel order and texture kits, when it offers them
local function Wedges()
    local list = {}
    local ok, options = pcall(function() return C_Ping and C_Ping.GetDefaultPingOptions and C_Ping.GetDefaultPingOptions() end)
    if ok and type(options) == "table" and #options > 0 then
        table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        for _, o in ipairs(options) do
            if NUMBER_OF[o.type] then
                local name
                for _, t in ipairs(TYPES) do if t.type == o.type then name = t.name end end
                list[#list + 1] = { type = o.type, number = NUMBER_OF[o.type], kit = o.uiTextureKitID, name = name }
            end
        end
    end
    if #list == 0 then
        for _, t in ipairs(TYPES) do list[#list + 1] = t end
    end
    return list
end

---------------------------------------------------------------------------
-- Wheel: Blizzard's radial wheel look (atlases and geometry from Blizzard_SharedXML/Blizzard_RadialWheel.lua)
-- with secure macro buttons. The cursor's angle from the center picks the wedge, like the game's wheel:
-- the middle is Cancel, outside the ring is Cancel, and only the picked wedge's secure button takes the
-- mouse (the others are mouse-disabled), so the hit area is the real sector, not a rectangle.
---------------------------------------------------------------------------
local wheel = CreateFrame("Frame", "BlinkPingMarkWheel", UIParent)
wheel:SetFrameStrata("DIALOG")
wheel:EnableMouse(true) -- a click that is not on a wedge lands here: cancel
wheel:Hide()
tinsert(UISpecialFrames, "BlinkPingMarkWheel") -- Escape closes it (from Blizzard's secure code, so also in combat)

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Geometry per size (Blizzard: wedgeSpacing 80/40, selected 20/10, MinimumWedgeDistanceSquared 500/150)
local GEOMETRY = {
    normal = { suffix = "",       icon = 80, selected = 20, deadSq = 500, outer = 128, fallbackSize = 256 },
    small  = { suffix = "_Small", icon = 40, selected = 10, deadSq = 150, outer = 64,  fallbackSize = 128 },
}

wheel.Background = wheel:CreateTexture(nil, "BACKGROUND", nil, 1)
wheel.Background:SetPoint("CENTER")
wheel.Frame = wheel:CreateTexture(nil, "OVERLAY", nil, 1)
wheel.Frame:SetPoint("CENTER")
wheel.Pointer = wheel:CreateTexture(nil, "OVERLAY", nil, 2)
wheel.Pointer:SetPoint("CENTER")
wheel.CancelSelected = wheel:CreateTexture(nil, "ARTWORK")
wheel.CancelSelected:SetPoint("CENTER")
wheel.CancelIcon = wheel:CreateTexture(nil, "OVERLAY")
wheel.CancelIcon:SetPoint("CENTER")

local buttons = {}
local hideWhenSafe = false
local hover -- wedge button under the cursor, false for the middle, nil outside the ring
local armed -- the wedge last hovered: the middle sends it (ground pings)

-- The middle: cancel, or "send the armed wedge" when the ping must be clicked at the wheel's middle
local send = CreateFrame("Button", "BlinkPingMarkSend", wheel, "SecureActionButtonTemplate")
send:SetPoint("CENTER")
send:SetFrameLevel(wheel:GetFrameLevel() + 3)
send:RegisterForClicks("LeftButtonUp", "RightButtonUp")
send:SetAttribute("useOnKeyDown", false)
send:SetAttribute("type1", "macro")
send:EnableMouse(false)
send.Icon = send:CreateTexture(nil, "OVERLAY")
send.Icon:SetPoint("CENTER")
wheel.Hint = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
wheel.Hint:SetPoint("TOP", wheel, "BOTTOM", 0, -2)

local function Close()
    if not wheel:IsShown() then return end
    if InCombatLockdown() then
        wheel:SetAlpha(0) -- cannot Hide a secure frame's parent chain in combat; hide after combat
        hideWhenSafe = true
        return
    end
    wheel:Hide()
end
send:HookScript("OnClick", Close) -- runs after the secure action
-- A click on the wheel that no secure button took: the middle with nothing armed, or the ring's outside,
-- closes; a click on a wedge while the ground is the target only arms it (the middle sends)
wheel:SetScript("OnMouseDown", function(_, button)
    if button ~= db.button then return Close() end -- the other mouse button always closes
    if hover == false and armed and not wheel.sendOnWedge then return end
    if hover and not wheel.sendOnWedge then return end
    Close()
end)

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", "BlinkPingMarkButton" .. i, wheel, "SecureActionButtonTemplate")
    b:SetAllPoints(wheel) -- the sector is decided by angle, see UpdateSelection
    b:SetFrameLevel(wheel:GetFrameLevel() + 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false) -- act on mouse up, whatever ActionButtonUseKeyDown says
    b:SetAttribute("type1", "macro")      -- left: /ping; right: no action, just close
    b.Selected = b:CreateTexture(nil, "ARTWORK")
    b.Selected:Hide()
    b.Icon = b:CreateTexture(nil, "OVERLAY")
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.Text:SetJustifyH("CENTER")
    b:HookScript("OnClick", Close) -- runs after the secure action
    buttons[i] = b
    return b
end

-- Blizzard's wheel: first wedge at the top, then counterclockwise
local function Layout(target)
    local wedges = Wedges()
    local g = GEOMETRY[db.small and "small" or "normal"]
    local n = #wedges
    local atlases = HasAtlas("Radial_Wheel_BG" .. g.suffix)
    if atlases then
        wheel.Background:SetAtlas("Radial_Wheel_BG" .. g.suffix, true)
        wheel.Background:SetVertexColor(1, 1, 1)
        local frameAtlas = ("Radial_Wheel_Frame_Count_%d"):format(n) .. g.suffix
        wheel.Frame:SetAtlas(HasAtlas(frameAtlas) and frameAtlas or ("Radial_Wheel_Frame_Count_4" .. g.suffix), true)
        wheel.Frame:Show()
        wheel.Pointer:SetAtlas("Radial_Wheel_Select_Pointer" .. g.suffix, true)
        wheel.CancelSelected:SetAtlas("Radial_Wheel_Select_Close" .. g.suffix, true)
        wheel.CancelIcon:SetAtlas("Radial_Wheel_Icon_Close" .. g.suffix, true)
        wheel:SetSize(wheel.Background:GetSize())
    else
        -- the client has no radial wheel art: plain shapes
        wheel.Background:SetColorTexture(0, 0, 0, 0.6)
        wheel.Background:SetSize(g.fallbackSize, g.fallbackSize)
        wheel.Frame:Hide()
        wheel.Pointer:SetColorTexture(1, 0.82, 0, 0.9)
        wheel.Pointer:SetSize(6, 6)
        wheel.CancelSelected:SetColorTexture(1, 1, 1, 0.25)
        wheel.CancelSelected:SetSize(g.outer / 3, g.outer / 3)
        wheel.CancelIcon:SetColorTexture(0.8, 0.2, 0.2, 1)
        wheel.CancelIcon:SetSize(8, 8)
        wheel:SetSize(g.fallbackSize, g.fallbackSize)
    end
    wheel.CancelSelected:Hide()

    local quarterPi = math.pi / 4
    local interval = 2 * math.pi / n
    local angle = math.pi / 2
    for i, w in ipairs(wedges) do
        local b = Button(i)
        b.angle, b.name = angle, w.name
        local cx, cy = math.cos(angle), math.sin(angle)
        local selectedAtlas = ("Radial_Wheel_Select_Wedge_Count_%d"):format(n) .. g.suffix
        -- Blizzard anchors the highlight `selected` px out from the wedge frame, which itself sits `icon` px out
        b.Selected:ClearAllPoints()
        b.Selected:SetPoint("CENTER", wheel, "CENTER", cx * (g.icon + g.selected), cy * (g.icon + g.selected))
        if atlases and HasAtlas(selectedAtlas) then
            b.Selected:SetAtlas(selectedAtlas, true)
            b.Selected:SetRotation(angle)
        else
            b.Selected:SetColorTexture(1, 1, 1, 0.2)
            b.Selected:SetSize(g.icon * 0.9, g.icon * 0.9)
            b.Selected:SetRotation(0)
            b.Selected:ClearAllPoints()
            b.Selected:SetPoint("CENTER", wheel, "CENTER", cx * g.icon, cy * g.icon)
        end
        b.Icon:ClearAllPoints()
        b.Icon:SetPoint("CENTER", wheel, "CENTER", cx * g.icon, cy * g.icon)
        local iconAtlas = w.kit and ("Ping_Wheel_Icon_" .. w.kit .. g.suffix)
        if iconAtlas and HasAtlas(iconAtlas) then
            b.Icon:SetAtlas(iconAtlas, true)
            b.Icon:Show()
        elseif w.kit and HasAtlas("Ping_Wheel_Icon_" .. w.kit) then
            b.Icon:SetAtlas("Ping_Wheel_Icon_" .. w.kit, true)
            if db.small then b.Icon:SetSize(b.Icon:GetWidth() / 2, b.Icon:GetHeight() / 2) end
            b.Icon:Show()
        else
            b.Icon:Hide()
        end
        -- text on the outside of the wedge, as in Blizzard's wheel
        b.Text:SetText(w.name or "")
        b.Text:ClearAllPoints()
        if angle > quarterPi and angle <= math.pi - quarterPi then
            b.Text:SetPoint("BOTTOM", b.Icon, "TOP", 0, 6)
        elseif angle > math.pi - quarterPi and angle <= math.pi + quarterPi then
            b.Text:SetPoint("RIGHT", b.Icon, "LEFT", -2, 0)
        elseif angle > math.pi + quarterPi and angle <= 2 * math.pi - quarterPi then
            b.Text:SetPoint("TOP", b.Icon, "BOTTOM", 0, -6)
        else
            b.Text:SetPoint("LEFT", b.Icon, "RIGHT", 2, 0)
        end
        b.Text:SetShown(not db.small)
        b.Selected:Hide()
        local macro = target and string.format("/ping [@%s] %s", target, w.number) or ("/ping " .. w.number)
        b:SetAttribute("macrotext1", macro)
        b:EnableMouse(false)
        b:Show()
        angle = angle + interval
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    wheel.numWedges = n
    -- a unit ping does not depend on the cursor's spot: the wedge click sends it. A ground ping
    -- (@cursor or contextual) must be clicked at the wheel's middle.
    wheel.sendOnWedge = db.quick or (target ~= nil and target ~= "cursor")
    local dead = math.sqrt(g.deadSq) * 2
    send:SetSize(dead, dead)
    send:EnableMouse(false)
    send.Icon:Hide()
    wheel.Hint:SetText(wheel.sendOnWedge and "" or "Move to a ping, then click the middle")
    hover, armed = nil, nil
end

-- Which wedge (or the cancel zone) the cursor is on; mouse goes only to that wedge's secure button
local function UpdateSelection()
    if InCombatLockdown() then return end -- secure buttons cannot change now; the wheel is on its way out
    local g = GEOMETRY[db.small and "small" or "normal"]
    local x, y = GetCursorPosition()
    local scale = wheel:GetEffectiveScale()
    x, y = x / scale, y / scale
    local cx, cy = wheel:GetCenter()
    if not cx then return end
    local dx, dy = x - cx, y - cy
    local distSq = dx * dx + dy * dy
    local pick = false -- cancel
    if distSq > g.deadSq and distSq <= g.outer * g.outer then
        local angle = math.atan2(dy, dx)
        if angle < 0 then angle = angle + 2 * math.pi end
        wheel.Pointer:SetRotation(angle)
        wheel.Pointer:Show()
        -- wedges start at the top (pi/2) and go counterclockwise; each is centered on its angle
        local interval = 2 * math.pi / (wheel.numWedges or 4)
        local a = angle - math.pi / 2 + interval / 2
        if a < 0 then a = a + 2 * math.pi end
        local index = math.floor(a / interval) + 1
        if index > (wheel.numWedges or 4) then index = 1 end
        pick = buttons[index]
    elseif distSq > g.outer * g.outer then
        pick = nil -- outside: nothing highlighted, a click goes to the world or UI (handled elsewhere)
        wheel.Pointer:Hide()
    else
        wheel.Pointer:Hide()
    end
    if pick == hover then return end
    hover = pick
    if pick then armed = pick end -- a wedge stays chosen while the cursor goes back to the middle
    local lit = wheel.sendOnWedge and pick or armed
    wheel.CancelSelected:SetShown(pick == false)
    for i = 1, (wheel.numWedges or 0) do
        local b = buttons[i]
        b.Selected:SetShown(b == lit)
        b:EnableMouse(wheel.sendOnWedge and b == pick)
    end
    -- the middle sends the armed wedge (ground pings): its icon replaces the X
    local sendNow = not wheel.sendOnWedge and armed ~= nil
    if sendNow then
        send:SetAttribute("macrotext1", armed:GetAttribute("macrotext1"))
        local atlas = armed.Icon:IsShown() and armed.Icon:GetAtlas()
        if atlas then
            send.Icon:SetAtlas(atlas, true)
            send.Icon:SetSize(send:GetWidth() * 0.8, send:GetHeight() * 0.8)
            send.Icon:Show()
        else
            send.Icon:Hide()
        end
        wheel.CancelIcon:Hide()
        wheel.Hint:SetText(pick == false and ("Click to ping: " .. (armed.name or "")) or "Move to a ping, then click the middle")
    else
        send.Icon:Hide()
        wheel.CancelIcon:Show()
    end
    send:EnableMouse(sendNow and pick == false)
end

-- Unit tokens the client may hold for a unit the cursor is on (the "mouseover" token is gone once
-- the cursor is on a wheel button, so a stable one is needed in the macro)
local TOKENS = { "target", "focus", "pet", "player" }
for i = 1, 4 do TOKENS[#TOKENS + 1] = "party" .. i end
for i = 1, 4 do TOKENS[#TOKENS + 1] = "partypet" .. i end
for i = 1, 8 do TOKENS[#TOKENS + 1] = "boss" .. i end
for i = 1, 5 do TOKENS[#TOKENS + 1] = "arena" .. i end
for i = 1, 40 do TOKENS[#TOKENS + 1] = "nameplate" .. i end
for i = 1, 40 do TOKENS[#TOKENS + 1] = "raid" .. i end
for i = 1, 40 do TOKENS[#TOKENS + 1] = "raidpet" .. i end

local function TokenFor(guid)
    if not guid then return nil end
    for _, token in ipairs(TOKENS) do
        if UnitExists(token) and UnitGUID(token) == guid then return token end
    end
end

local function Open(kind, unit)
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("BlinkPingMark: the ping wheel cannot open in combat", 1, 0.3, 0.3)
        return
    end
    local ok, enabled = pcall(function() return C_Ping and C_Ping.IsPingSystemEnabled and C_Ping.IsPingSystemEnabled() end)
    if ok and enabled == false then
        return Print("the ping system is turned off in the game options.")
    end
    local target
    if kind == "frame" then
        target = unit
    elseif UnitExists("mouseover") then
        target = TokenFor(UnitGUID("mouseover"))
        Debug("world unit %s -> %s", tostring(UnitName("mouseover")), target or "contextual ping")
    else
        target = "cursor"
    end
    Layout(target)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    wheel:SetAlpha(1)
    wheel.openedAt = GetTime()
    wheel:Show()
    UpdateSelection()
    Debug("wheel opened: %s", target and ("@" .. target) or "contextual")
end

wheel:SetScript("OnUpdate", function(self)
    if self.openedAt and GetTime() - self.openedAt > 6 then return Close() end
    UpdateSelection()
end)

---------------------------------------------------------------------------
-- Mark wheel: the other mouse button on a unit frame; eight raid target icons, the same look.
-- SetRaidTarget is not protected, so this is an ordinary frame and works in combat.
---------------------------------------------------------------------------
local MARKS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function MarkButton()
    return db.button == "LeftButton" and "RightButton" or "LeftButton"
end

local mark = CreateFrame("Frame", "BlinkPingMarkMarkWheel", UIParent)
mark:SetFrameStrata("DIALOG")
mark:EnableMouse(true)
mark:Hide()
tinsert(UISpecialFrames, "BlinkPingMarkMarkWheel")
mark.Background = mark:CreateTexture(nil, "BACKGROUND", nil, 1)
mark.Background:SetPoint("CENTER")
mark.Frame = mark:CreateTexture(nil, "OVERLAY", nil, 1)
mark.Frame:SetPoint("CENTER")
mark.Pointer = mark:CreateTexture(nil, "OVERLAY", nil, 2)
mark.Pointer:SetPoint("CENTER")
mark.CancelSelected = mark:CreateTexture(nil, "ARTWORK")
mark.CancelSelected:SetPoint("CENTER")
mark.CancelIcon = mark:CreateTexture(nil, "OVERLAY")
mark.CancelIcon:SetPoint("CENTER")
mark.Hint = mark:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mark.Hint:SetPoint("TOP", mark, "BOTTOM", 0, -2)
mark.wedges = {}
local markHover -- wedge index, false for the middle, nil outside the ring

local function CloseMark()
    mark:Hide()
end

-- Blizzard's unit menu opens on the right button's mouse-up; close it so the clicks do not land in it
local function CloseBlizzardMenus()
    if Menu and Menu.GetManager then
        pcall(function() Menu.GetManager():CloseMenus() end)
    end
    if CloseDropDownMenus then pcall(CloseDropDownMenus) end
end

local function MarkWedge(i)
    local w = mark.wedges[i]
    if w then return w end
    w = {}
    w.Selected = mark:CreateTexture(nil, "ARTWORK")
    w.Glow = mark:CreateTexture(nil, "ARTWORK", nil, 1) -- fallback highlight when the 8-wedge atlas is missing
    w.Glow:SetColorTexture(1, 1, 1, 0.25)
    w.Icon = mark:CreateTexture(nil, "OVERLAY")
    w.Icon:SetTexture(RAID_ICONS)
    w.Text = mark:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.Text:SetJustifyH("CENTER")
    mark.wedges[i] = w
    return w
end

local function LayoutMark()
    local g = GEOMETRY[db.small and "small" or "normal"]
    local n = #MARKS
    local atlases = HasAtlas("Radial_Wheel_BG" .. g.suffix)
    local frameAtlas = ("Radial_Wheel_Frame_Count_%d"):format(n) .. g.suffix
    local selectedAtlas = ("Radial_Wheel_Select_Wedge_Count_%d"):format(n) .. g.suffix
    if atlases then
        mark.Background:SetAtlas("Radial_Wheel_BG" .. g.suffix, true)
        mark.Frame:SetShown(HasAtlas(frameAtlas))
        if HasAtlas(frameAtlas) then mark.Frame:SetAtlas(frameAtlas, true) end
        mark.Pointer:SetAtlas("Radial_Wheel_Select_Pointer" .. g.suffix, true)
        mark.CancelSelected:SetAtlas("Radial_Wheel_Select_Close" .. g.suffix, true)
        mark.CancelIcon:SetAtlas("Radial_Wheel_Icon_Close" .. g.suffix, true)
        mark:SetSize(mark.Background:GetSize())
    else
        mark.Background:SetColorTexture(0, 0, 0, 0.6)
        mark.Background:SetSize(g.fallbackSize, g.fallbackSize)
        mark.Frame:Hide()
        mark.Pointer:SetColorTexture(1, 0.82, 0, 0.9)
        mark.Pointer:SetSize(6, 6)
        mark.CancelSelected:SetColorTexture(1, 1, 1, 0.25)
        mark.CancelSelected:SetSize(g.outer / 3, g.outer / 3)
        mark.CancelIcon:SetColorTexture(0.8, 0.2, 0.2, 1)
        mark.CancelIcon:SetSize(8, 8)
        mark:SetSize(g.fallbackSize, g.fallbackSize)
    end
    mark.CancelSelected:Hide()
    local hasSelected = atlases and HasAtlas(selectedAtlas)
    local current = mark.unit and GetRaidTargetIndex(mark.unit) or 0
    local iconSize = db.small and 18 or 30
    local quarterPi = math.pi / 4
    local interval = 2 * math.pi / n
    local angle = math.pi / 2
    for i = 1, n do
        local w = MarkWedge(i)
        local cx, cy = math.cos(angle), math.sin(angle)
        w.Selected:ClearAllPoints()
        if hasSelected then
            w.Selected:SetAtlas(selectedAtlas, true)
            w.Selected:SetRotation(angle)
            w.Selected:SetPoint("CENTER", mark, "CENTER", cx * (g.icon + g.selected), cy * (g.icon + g.selected))
        end
        w.Selected:SetShown(false)
        w.Glow:ClearAllPoints()
        w.Glow:SetPoint("CENTER", mark, "CENTER", cx * g.icon, cy * g.icon)
        w.Glow:SetSize(iconSize * 1.4, iconSize * 1.4)
        w.Glow:Hide()
        w.Icon:ClearAllPoints()
        w.Icon:SetPoint("CENTER", mark, "CENTER", cx * g.icon, cy * g.icon)
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        w.Icon:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
        local size = i == current and iconSize * 1.3 or iconSize
        w.Icon:SetSize(size, size)
        w.Text:SetText(MARKS[i])
        w.Text:SetTextColor(i == current and 0.3 or 1, 1, i == current and 0.3 or 1)
        w.Text:ClearAllPoints()
        if angle > quarterPi and angle <= math.pi - quarterPi then
            w.Text:SetPoint("BOTTOM", w.Icon, "TOP", 0, 2)
        elseif angle > math.pi - quarterPi and angle <= math.pi + quarterPi then
            w.Text:SetPoint("RIGHT", w.Icon, "LEFT", -2, 0)
        elseif angle > math.pi + quarterPi and angle <= 2 * math.pi - quarterPi then
            w.Text:SetPoint("TOP", w.Icon, "BOTTOM", 0, -2)
        else
            w.Text:SetPoint("LEFT", w.Icon, "RIGHT", 2, 0)
        end
        w.Text:SetShown(not db.small)
        angle = angle + interval
    end
    mark.hasSelected = hasSelected
    markHover = nil
end

local function UpdateMark()
    local g = GEOMETRY[db.small and "small" or "normal"]
    local x, y = GetCursorPosition()
    local scale = mark:GetEffectiveScale()
    x, y = x / scale, y / scale
    local cx, cy = mark:GetCenter()
    if not cx then return end
    local dx, dy = x - cx, y - cy
    local distSq = dx * dx + dy * dy
    local pick = false
    if distSq > g.deadSq and distSq <= g.outer * g.outer then
        local angle = math.atan2(dy, dx)
        if angle < 0 then angle = angle + 2 * math.pi end
        mark.Pointer:SetRotation(angle)
        mark.Pointer:Show()
        local n = #MARKS
        local interval = 2 * math.pi / n
        local a = angle - math.pi / 2 + interval / 2
        if a < 0 then a = a + 2 * math.pi end
        pick = math.floor(a / interval) + 1
        if pick > n then pick = 1 end
    else
        mark.Pointer:Hide()
        if distSq > g.outer * g.outer then pick = nil end
    end
    if pick == markHover then return end
    markHover = pick
    mark.CancelSelected:SetShown(pick == false)
    for i, w in ipairs(mark.wedges) do
        w.Selected:SetShown(mark.hasSelected and i == pick)
        w.Glow:SetShown(not mark.hasSelected and i == pick)
    end
end

local function OpenMark(unit)
    if not (unit and UnitExists(unit)) then return end
    if not Allowed() then return end
    CloseBlizzardMenus()
    mark.unit = unit
    LayoutMark()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    mark.Hint:SetText("Mark " .. (UnitName(unit) or unit))
    mark.openedAt = GetTime()
    mark:Show()
    UpdateMark()
    Debug("mark wheel opened for %s", unit)
end

mark:SetScript("OnMouseDown", function()
    if markHover then
        local unit = mark.unit
        if unit and UnitExists(unit) then
            local current = GetRaidTargetIndex(unit)
            SetRaidTarget(unit, current == markHover and 0 or markHover) -- the same icon again clears it
        end
    end
    CloseMark()
end)

mark:SetScript("OnUpdate", function(self)
    local age = GetTime() - (self.openedAt or 0)
    if age > 6 then return CloseMark() end
    if age < 0.3 then CloseBlizzardMenus() end -- the menu from the last click's mouse-up
    UpdateMark()
end)

---------------------------------------------------------------------------
-- Click counting: the first click of a run decides what is under the cursor (later ones may land on
-- a menu that the first one opened); the run restarts on a pause, a move or another button.
---------------------------------------------------------------------------
local clicks, lastTime, lastX, lastY, lastButton = 0, 0, 0, 0, nil
local firstKind, firstUnit -- what the run's first click was on
local MOVE = 16 -- screen pixels the cursor may drift between the clicks

local function MouseFocus()
    if GetMouseFoci then
        local list = GetMouseFoci()
        return list and list[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
end

-- "world" (nothing but the game world under the cursor), "frame" + unit (a unit frame), or nil
local function Under()
    local focus = MouseFocus()
    if not focus or focus == WorldFrame then return "world" end
    local f = focus
    while f do
        if f.GetAttribute then
            local ok, unit = pcall(f.GetAttribute, f, "unit")
            if ok and type(unit) == "string" and unit ~= "" then return "frame", unit end
        end
        f = f.GetParent and f:GetParent()
    end
    return nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON_NAME then return end
        BlinkPingMarkDB = BlinkPingMarkDB or {}
        for k, v in pairs(DEFAULTS) do
            if BlinkPingMarkDB[k] == nil then BlinkPingMarkDB[k] = v end
        end
        db = BlinkPingMarkDB
        for k, v in pairs(DEFAULTS.zones) do
            if db.zones[k] == nil then db.zones[k] = v end
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hideWhenSafe then
            hideWhenSafe = false
            wheel:Hide()
        end
        return
    end
    -- GLOBAL_MOUSE_DOWN
    if not db then return end
    if wheel:IsShown() or mark:IsShown() then
        -- any button outside a wheel closes it; clicks on a wheel are handled by its frame and buttons
        if wheel:IsShown() and not wheel:IsMouseOver() then Close() end
        if mark:IsShown() and not mark:IsMouseOver() then CloseMark() end
        clicks = 0
        return
    end
    local isPing = arg == db.button
    local isMark = db.mark and arg == MarkButton()
    if not (isPing or isMark) then
        clicks = 0
        return
    end
    local now = GetTime()
    local x, y = GetCursorPosition()
    if arg ~= lastButton or now - lastTime > db.interval or math.abs(x - lastX) > MOVE or math.abs(y - lastY) > MOVE then
        clicks = 0
        local kind, unit = Under()
        if not kind or not Allowed() or (isMark and kind ~= "frame") then return end
        firstKind, firstUnit = kind, unit
    end
    clicks, lastTime, lastX, lastY, lastButton = clicks + 1, now, x, y, arg
    if isMark and clicks > 1 then CloseBlizzardMenus() end -- the unit menu from the previous click
    if clicks >= db.clicks then
        clicks = 0
        if isMark then OpenMark(firstUnit) else Open(firstKind, firstUnit) end
    end
end)

---------------------------------------------------------------------------
-- Settings panel (Options -> AddOns -> BlinkPingMark)
---------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "BlinkPingMark"
local category
local refreshers = {}
local PAD = 16
local cursorY = -16

local function Label(text, template, width)
    local fs = panel:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", PAD, cursorY)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    return fs
end

local function Header(text, first)
    if not first then
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.15)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", PAD, cursorY - 6)
        line:SetPoint("TOPRIGHT", -PAD, cursorY - 6)
        cursorY = cursorY - 14
    end
    Label(text, "GameFontNormalLarge")
    cursorY = cursorY - 26
end

local function Paragraph(text)
    local fs = Label(text, "GameFontHighlight", 600)
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    cursorY = cursorY - fs:GetStringHeight() - 12
end

-- A row of check buttons. get(key) -> checked; set(key, checked)
local function CheckRow(items, get, set)
    local x = PAD
    for _, item in ipairs(items) do
        local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        c:SetSize(26, 26)
        c:SetPoint("TOPLEFT", x, cursorY + 2)
        local l = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", c, "RIGHT", 2, 0)
        l:SetText(item.text)
        c:SetScript("OnClick", function(self)
            set(item.key, self:GetChecked() and true or false)
            panel.Refresh()
        end)
        if item.tip then
            c:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(item.text)
                GameTooltip:AddLine(item.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", GameTooltip_Hide)
        end
        refreshers[#refreshers + 1] = function() c:SetChecked(get(item.key)) end
        x = x + 30 + l:GetStringWidth() + 24
    end
    cursorY = cursorY - 32
end

-- Exactly one of the items is on (radio behaviour with check buttons)
local function RadioRow(items, key)
    CheckRow(items, function(v) return db[key] == v end, function(v, on) if on then db[key] = v end end)
end

Label("BlinkPingMark", "GameFontHighlightLarge")
cursorY = cursorY - 30
Paragraph("Click the mouse button several times on the same spot to open a ping wheel there."
    .. " On a unit frame or a unit, click a wedge: the ping goes to that unit."
    .. " On the ground, move the cursor onto a wedge and then click the wheel's middle: the ping lands where"
    .. " the wheel opened (a ping can only be sent at the cursor, so it must be clicked there)."
    .. " The right button, Escape or a click outside the wheel closes it."
    .. " The wheel cannot open in combat (the game forbids addons to show the buttons then).")

Header("Open the wheel with")
RadioRow({ { key = 3, text = "Triple click", tip = "Three clicks within the interval, without moving the mouse." },
           { key = 2, text = "Double click", tip = "Two clicks. Easier to trigger by accident while selecting targets." } },
    "clicks")
RadioRow({ { key = "LeftButton", text = "Left mouse button" },
           { key = "RightButton", text = "Right mouse button", tip = "On unit frames the right button also opens the unit menu, which may interrupt the clicks." } },
    "button")
CheckRow({ { key = "small", text = "Small wheel", tip = "The game's small radial wheel (half size, no labels)." },
           { key = "quick", text = "Send on wedge click", tip = "Always send as soon as a wedge is clicked. Faster, but a ground ping then lands under the cursor, about 80 px from the wheel's middle, instead of where the wheel opened." } },
    function(k) return db[k] end, function(k, on) db[k] = on end)

Header("Marking")
Paragraph("The same clicks with the other mouse button on a unit frame open a wheel of raid target icons"
    .. " for that unit. Clicking the icon the unit already has removes it. Works in combat.")
CheckRow({ { key = "mark", text = "Mark wheel", tip = "Three (or two) clicks with the other mouse button on a unit frame." } },
    function() return db.mark end, function(_, on) db.mark = on end)

Header("Active in")
CheckRow({ { key = "groupOnly", text = "Only in a group", tip = "Pings and raid icons are seen by the group. Unticked, the wheels also open while solo." } },
    function() return db.groupOnly end, function(_, on) db.groupOnly = on end)
CheckRow({
    { key = "world", text = "Open world" },
    { key = "city", text = "Cities", tip = "The capital cities and sanctuaries." },
    { key = "dungeon", text = "Dungeons" },
    { key = "raid", text = "Raids" },
    { key = "battleground", text = "Battlegrounds" },
    { key = "arena", text = "Arenas" },
}, function(k) return db.zones[k] end, function(k, on) db.zones[k] = on end)

function panel.Refresh()
    if not db then return end
    for _, fn in ipairs(refreshers) do fn() end
end
panel:SetScript("OnShow", panel.Refresh)

if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

local function OpenPanel()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_BLINKPINGMARK1 = "/bpm"
SlashCmdList.BLINKPINGMARK = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "clicks" and (arg == "2" or arg == "3") then
        db.clicks = tonumber(arg)
        Print("%d clicks open the wheel.", db.clicks)
    elseif cmd == "button" and (arg == "left" or arg == "right") then
        db.button = arg == "left" and "LeftButton" or "RightButton"
        Print("%s mouse button.", arg)
    elseif cmd == "interval" and tonumber(arg) then
        db.interval = math.max(0.15, math.min(1.5, tonumber(arg)))
        Print("clicks may be %.2f s apart.", db.interval)
    elseif cmd == "small" then
        db.small = not db.small
        Print("%s wheel.", db.small and "small" or "normal")
    elseif cmd == "group" then
        db.groupOnly = not db.groupOnly
        Print("wheels %s.", db.groupOnly and "only in a group" or "also while solo")
    elseif cmd == "mark" then
        db.mark = not db.mark
        Print("mark wheel %s.", db.mark and "on" or "off")
    elseif cmd == "quick" then
        db.quick = not db.quick
        Print("quick mode %s.", db.quick and "on: a wedge click sends at once, a ground ping lands under the cursor" or "off")
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug %s.", db.debug and "on" or "off")
    elseif cmd == "test" then
        Open("world")
    else
        OpenPanel()
        return
    end
    panel.Refresh()
end

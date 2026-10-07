-- EasyPing (WoW Forever / Retail API)
-- Click the left mouse button three times (or twice, see /easyping) on the same spot to open a ping
-- wheel there, drawn with the game's own radial wheel art. Addons may not call the ping API, so each wheel button is a secure button running
-- Blizzard's "/ping" macro command, which the client resolves itself:
--   clicked on a unit frame   -> that frame's unit        /ping [@unit] <type>
--   clicked on a world unit   -> that unit, when the client has a unit token for it (target,
--                                nameplate, party, raid...), else a contextual ping at the cursor
--   clicked on the ground     -> the spot under the cursor  /ping [@cursor] <type>
-- Secure buttons cannot be shown or changed in combat, so the wheel only opens out of combat.
-- Settings: Options -> AddOns -> EasyPing (clicks, mouse button, where it is active), or
--   /easyping                 open the settings
--   /easyping clicks 2|3      how many clicks open the wheel
--   /easyping button left|right
--   /easyping interval <s>    longest pause between clicks (default 0.4)
--   /easyping small           toggle the small wheel
--   /easyping test            open the wheel at the cursor

local ADDON_NAME = ...

local DEFAULTS = { clicks = 3, button = "LeftButton", interval = 0.4, small = false, debug = false,
                   zones = { world = true, city = true, dungeon = true, raid = true, battleground = true, arena = true } }
local db

-- Where the player is: one of the keys of db.zones
local CITY_MAPS = { -- Classic capitals (uiMapID)
    [1453] = true, [1455] = true, [1457] = true, -- Stormwind, Ironforge, Darnassus
    [1454] = true, [1456] = true, [1458] = true, -- Orgrimmar, Thunder Bluff, Undercity
}
local function ZoneKind()
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

local PREFIX = "|cff66ccffEasyPing|r: "
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
local wheel = CreateFrame("Frame", "EasyPingWheel", UIParent)
wheel:SetFrameStrata("DIALOG")
wheel:EnableMouse(true) -- a click that is not on a wedge lands here: cancel
wheel:Hide()
tinsert(UISpecialFrames, "EasyPingWheel") -- Escape closes it (from Blizzard's secure code, so also in combat)

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
local selected -- wedge button under the cursor, or false for the cancel zone, or nil

local function Close()
    if not wheel:IsShown() then return end
    if InCombatLockdown() then
        wheel:SetAlpha(0) -- cannot Hide a secure frame's parent chain in combat; hide after combat
        hideWhenSafe = true
        return
    end
    wheel:Hide()
end
wheel:SetScript("OnMouseDown", Close)

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", "EasyPingButton" .. i, wheel, "SecureActionButtonTemplate")
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
        b.Selected:ClearAllPoints()
        b.Selected:SetPoint("CENTER", wheel, "CENTER", cx * g.selected, cy * g.selected)
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
    selected = nil
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
    if pick == selected then return end
    selected = pick
    wheel.CancelSelected:SetShown(pick == false)
    for i = 1, (wheel.numWedges or 0) do
        local b = buttons[i]
        b.Selected:SetShown(b == pick)
        b:EnableMouse(b == pick)
    end
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
        UIErrorsFrame:AddMessage("EasyPing: the ping wheel cannot open in combat", 1, 0.3, 0.3)
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
-- Click counting
---------------------------------------------------------------------------
local clicks, lastTime, lastX, lastY = 0, 0, 0, 0
local MOVE = 16 -- screen pixels the cursor may drift between the clicks

local function MouseFocus()
    if GetMouseFoci then
        local list = GetMouseFoci()
        return list and list[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
end

local function IsOurs(frame)
    while frame do
        if frame == wheel then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
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
        EasyPingDB = EasyPingDB or {}
        for k, v in pairs(DEFAULTS) do
            if EasyPingDB[k] == nil then EasyPingDB[k] = v end
        end
        db = EasyPingDB
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
    if arg ~= db.button then
        clicks = 0
        return
    end
    if wheel:IsShown() then
        if IsOurs(MouseFocus()) then return end -- the button handles it
        Close()
        clicks = 0
        return
    end
    local kind, unit = Under()
    if not kind or not db.zones[ZoneKind()] then
        clicks = 0
        return
    end
    local now = GetTime()
    local x, y = GetCursorPosition()
    if now - lastTime > db.interval or math.abs(x - lastX) > MOVE or math.abs(y - lastY) > MOVE then
        clicks = 0
    end
    clicks, lastTime, lastX, lastY = clicks + 1, now, x, y
    if clicks >= db.clicks then
        clicks = 0
        Open(kind, unit)
    end
end)

---------------------------------------------------------------------------
-- Settings panel (Options -> AddOns -> EasyPing)
---------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "EasyPing"
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

Label("EasyPing", "GameFontHighlightLarge")
cursorY = cursorY - 30
Paragraph("Click the mouse button several times on the same spot to open a ping wheel there."
    .. " Pick a ping with the left mouse button; the right button, Escape or a click elsewhere closes the wheel."
    .. " On a unit frame or a unit the ping goes to that unit, on the ground to the spot under the cursor."
    .. " The wheel cannot open in combat (the game forbids addons to show the buttons then).")

Header("Open the wheel with")
RadioRow({ { key = 3, text = "Triple click", tip = "Three clicks within the interval, without moving the mouse." },
           { key = 2, text = "Double click", tip = "Two clicks. Easier to trigger by accident while selecting targets." } },
    "clicks")
RadioRow({ { key = "LeftButton", text = "Left mouse button" },
           { key = "RightButton", text = "Right mouse button", tip = "On unit frames the right button also opens the unit menu, which may interrupt the clicks." } },
    "button")
CheckRow({ { key = "small", text = "Small wheel", tip = "The game's small radial wheel (half size, no labels)." } },
    function() return db.small end, function(_, on) db.small = on end)

Header("Active in")
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
SLASH_EASYPING1 = "/easyping"
SlashCmdList.EASYPING = function(msg)
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

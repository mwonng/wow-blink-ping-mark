-- EasyPing (WoW Forever / Retail API)
-- Click the left mouse button three times (or twice, see /easyping) on the same spot to open a small
-- ping wheel there. Addons may not call the ping API, so each wheel button is a secure button running
-- Blizzard's "/ping" macro command, which the client resolves itself:
--   clicked on a unit frame   -> that frame's unit        /ping [@unit] <type>
--   clicked on a world unit   -> that unit, when the client has a unit token for it (target,
--                                nameplate, party, raid...), else a contextual ping at the cursor
--   clicked on the ground     -> the spot under the cursor  /ping [@cursor] <type>
-- Secure buttons cannot be shown or changed in combat, so the wheel only opens out of combat.
--   /easyping                 settings
--   /easyping clicks 2|3      how many clicks open the wheel
--   /easyping interval <s>    longest pause between clicks (default 0.4)
--   /easyping size <px>       icon size (default 28)
--   /easyping test            open the wheel at the cursor

local ADDON_NAME = ...

local DEFAULTS = { clicks = 3, interval = 0.4, size = 28, radius = 34, debug = false }
local db

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
-- Wheel: secure macro buttons around the click point
---------------------------------------------------------------------------
local wheel = CreateFrame("Frame", "EasyPingWheel", UIParent)
wheel:SetFrameStrata("DIALOG")
wheel:SetSize(2, 2)
wheel:Hide()
tinsert(UISpecialFrames, "EasyPingWheel") -- Escape closes it (from Blizzard's secure code, so also in combat)

wheel.spot = wheel:CreateTexture(nil, "OVERLAY")
wheel.spot:SetSize(6, 6)
wheel.spot:SetPoint("CENTER")
wheel.spot:SetColorTexture(1, 1, 1, 0.9)

local buttons = {}
local hideWhenSafe = false

local function Close()
    if not wheel:IsShown() then return end
    if InCombatLockdown() then
        wheel:SetAlpha(0) -- cannot Hide a secure frame's parent chain in combat; hide after combat
        hideWhenSafe = true
        return
    end
    wheel:Hide()
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", "EasyPingButton" .. i, wheel, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false) -- act on mouse up, whatever ActionButtonUseKeyDown says
    b:SetAttribute("type1", "macro")      -- left: /ping; right: no action, just close
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.name or "Ping")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:HookScript("OnClick", Close) -- runs after the secure action
    buttons[i] = b
    return b
end

-- Returns the icon setup for a wedge: atlas when the client has it, else a text label
local function Decorate(b, w)
    b.name = w.name
    local atlas = w.kit and ("Ping_Wheel_Icon_" .. w.kit)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info then
        b.icon:SetAtlas(atlas)
        b.icon:Show()
        b.label:SetText("")
    else
        b.icon:Hide()
        b.label:SetText(w.name or "?")
    end
end

-- target: unit token, "cursor", or nil (contextual: whatever is under the cursor when clicked)
local function Layout(target)
    local wedges = Wedges()
    local size, radius = db.size, db.radius
    for i, w in ipairs(wedges) do
        local b = Button(i)
        b:SetSize(size, size)
        local angle = math.rad(90 - (i - 1) * 360 / #wedges) -- first at the top, then clockwise
        b:ClearAllPoints()
        b:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        Decorate(b, w)
        local macro = target and string.format("/ping [@%s] %s", target, w.number) or ("/ping " .. w.number)
        b:SetAttribute("macrotext1", macro)
        b:Show()
    end
    for i = #wedges + 1, #buttons do buttons[i]:Hide() end
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
    Debug("wheel opened: %s", target and ("@" .. target) or "contextual")
end

wheel:SetScript("OnUpdate", function(self)
    if self.openedAt and GetTime() - self.openedAt > 6 then Close() end
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
    if arg ~= "LeftButton" then
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
    if not kind then
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
-- Slash commands
---------------------------------------------------------------------------
SLASH_EASYPING1 = "/easyping"
SlashCmdList.EASYPING = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "clicks" and (arg == "2" or arg == "3") then
        db.clicks = tonumber(arg)
        Print("%d clicks open the wheel.", db.clicks)
    elseif cmd == "interval" and tonumber(arg) then
        db.interval = math.max(0.15, math.min(1.5, tonumber(arg)))
        Print("clicks may be %.2f s apart.", db.interval)
    elseif cmd == "size" and tonumber(arg) then
        db.size = math.max(16, math.min(64, math.floor(tonumber(arg))))
        db.radius = db.size + 6
        Print("icon size %d px.", db.size)
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug %s.", db.debug and "on" or "off")
    elseif cmd == "test" then
        Open("world")
    else
        Print("%d clicks within %.2f s open the wheel; icons %d px.", db.clicks, db.interval, db.size)
        Print("/easyping clicks 2|3, interval <seconds>, size <px>, test, debug")
    end
end

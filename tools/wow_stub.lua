-- A small stand-in for the WoW API, enough to load BlinkPingMark.lua outside the game and drive it
-- from tools/test.py. Returns the stub table; its fields are the knobs the tests turn.
local stub = {
    cursor = { 100, 100 }, -- GetCursorPosition
    time = 0,              -- GetTime
    combat = false,        -- InCombatLockdown
    inGroup = true,        -- IsInGroup
    instance = "none",     -- IsInInstance type
    map = 1,               -- C_Map.GetBestMapForUnit
    pvp = "contested",     -- GetZonePVPInfo
    units = {},            -- [token] = { guid, name, icon }
    atlases = {},          -- [name] = { width, height }; filled below
    focus = nil,           -- GetMouseFoci()[1]
    printed = {},          -- print()
    errors = {},           -- UIErrorsFrame:AddMessage
    menusClosed = 0,
    macros = {},           -- macrotext of every secure click, in order
    frames = {},           -- every frame made by CreateFrame
}

for _, size in ipairs({ { "", 256 }, { "_Small", 128 } }) do
    local suffix, px = size[1], size[2]
    stub.atlases["Radial_Wheel_BG" .. suffix] = { width = px, height = px }
    stub.atlases["Radial_Wheel_Select_Pointer" .. suffix] = { width = px / 8, height = px / 8 }
    stub.atlases["Radial_Wheel_Select_Close" .. suffix] = { width = px / 4, height = px / 4 }
    stub.atlases["Radial_Wheel_Icon_Close" .. suffix] = { width = px / 8, height = px / 8 }
    for _, n in ipairs({ 4, 8 }) do
        stub.atlases[("Radial_Wheel_Frame_Count_%d"):format(n) .. suffix] = { width = px, height = px }
        stub.atlases[("Radial_Wheel_Select_Wedge_Count_%d"):format(n) .. suffix] = { width = px / 2, height = px / 2 }
    end
    for _, kit in ipairs({ "Attack", "Warning", "OnMyWay", "Assist" }) do
        stub.atlases["Ping_Wheel_Icon_" .. kit .. suffix] = { width = px / 5, height = px / 5 }
    end
end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
function Region:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then x, y = rel, relPoint end
    self.point = { point, rel, relPoint, x or 0, y or 0 }
    if point == "CENTER" and type(rel) == "table" and rel == UIParent and relPoint == "BOTTOMLEFT" then
        self.center = { x, y }
    end
end
function Region:ClearAllPoints() self.point = nil end
function Region:SetAllPoints(other) self.allPoints = other end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetSize() return self.w or 0, self.h or 0 end
function Region:GetWidth() return self.w or 0 end
function Region:GetHeight() return self.h or 0 end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown == true end
function Region:SetShown(v) self.shown = v and true or false end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha or 1 end
function Region:GetParent() return self.parent end
function Region:SetParent(p) self.parent = p end
function Region:GetName() return self.name end
function Region:GetObjectType() return self.kind end

local Texture = setmetatable({}, Region)
Texture.__index = Texture
function Texture:SetAtlas(name, useSize)
    self.atlas = name
    local info = stub.atlases[name]
    if useSize and info then self.w, self.h = info.width, info.height end
end
function Texture:GetAtlas() return self.atlas end
function Texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } self.atlas = nil end
function Texture:SetTexture(t) self.texture = t end
function Texture:SetTexCoord(...) self.texCoord = { ... } end
function Texture:SetVertexColor(...) self.vertex = { ... } end
function Texture:SetRotation(a) self.rotation = a end

local FontString = setmetatable({}, Region)
FontString.__index = FontString
function FontString:SetText(t) self.text = t end
function FontString:GetText() return self.text end
function FontString:SetJustifyH(j) self.justify = j end
function FontString:SetWordWrap(w) self.wrap = w end
function FontString:SetSpacing(s) self.spacing = s end
function FontString:SetTextColor(...) self.textColor = { ... } end
function FontString:SetFont(...) end
function FontString:GetStringHeight() return 14 end
function FontString:GetStringWidth() return #(self.text or "") * 7 end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Frame = setmetatable({}, Region)
Frame.__index = Frame
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:EnableMouse(v) self.mouse = v and true or false end
function Frame:IsMouseEnabled() return self.mouse == true end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter()
    if self.allPoints then return self.allPoints:GetCenter() end
    if self.center then return self.center[1], self.center[2] end
    -- "CENTER" on the parent (SetPoint("CENTER") or SetPoint("CENTER", x, y)): the parent's center plus offsets
    local p = self.point
    if p and p[1] == "CENTER" and type(p[2]) ~= "table" and self.parent then
        local cx, cy = self.parent:GetCenter()
        return cx + (p[4] or 0), cy + (p[5] or 0)
    end
    return 0, 0
end
function Frame:IsMouseOver()
    local cx, cy = self:GetCenter()
    local w, h = self:GetSize()
    if self.allPoints then w, h = self.allPoints:GetSize() end
    local x, y = stub.cursor[1], stub.cursor[2]
    return math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= h / 2
end
function Frame:IsVisible()
    local f = self
    while f do
        if f.shown == false then return false end
        f = f.parent
    end
    return true
end
function Frame:RegisterEvent(e)
    stub.events[e] = stub.events[e] or {}
    stub.events[e][self] = true
end
function Frame:UnregisterEvent(e) if stub.events[e] then stub.events[e][self] = nil end end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function Frame:SetAttribute(k, v) self.attributes[k] = v end
function Frame:GetAttribute(k) return self.attributes[k] end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetHighlightTexture(...) end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked == true end
function Frame:GetID() return self.id or 0 end
function Frame:CreateTexture(name, layer, template, sub)
    local t = setmetatable({ kind = "Texture", parent = self, shown = true, layer = layer }, Texture)
    return t
end
function Frame:CreateFontString(name, layer, template)
    local t = setmetatable({ kind = "FontString", parent = self, shown = true }, FontString)
    return t
end
-- Runs a script and then its hooks, like the game does
function Frame:Run(name, ...)
    local fn = self.scripts[name]
    if fn then fn(self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
end

stub.events = {}

function CreateFrame(kind, name, parent, template)
    local f = setmetatable({
        kind = kind, name = name, parent = parent, template = template, shown = true,
        scripts = {}, hooks = {}, attributes = {},
    }, Frame)
    if name then _G[name] = f end
    table.insert(stub.frames, f)
    return f
end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
WorldFrame = CreateFrame("Frame", "WorldFrame")
UIErrorsFrame = { AddMessage = function(_, msg) table.insert(stub.errors, msg) end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end,
                Show = function() end, Hide = function() end }
GameTooltip_Hide = function() end
UISpecialFrames = {}
tinsert = table.insert
SlashCmdList = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return 1 end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() stub.panelOpened = (stub.panelOpened or 0) + 1 end,
}
Enum = { PingSubjectType = { Attack = 0, Warning = 1, Assist = 2, OnMyWay = 3, AlertThreat = 4, AlertNotThreat = 5 } }
C_Ping = {
    IsPingSystemEnabled = function() return true end,
    GetDefaultPingOptions = function()
        return {
            { orderIndex = 3, type = 3, uiTextureKitID = "OnMyWay" },
            { orderIndex = 1, type = 0, uiTextureKitID = "Attack" },
            { orderIndex = 4, type = 2, uiTextureKitID = "Assist" },
            { orderIndex = 2, type = 1, uiTextureKitID = "Warning" },
        }
    end,
}
C_Texture = { GetAtlasInfo = function(name) return stub.atlases[name] end }
C_Map = { GetBestMapForUnit = function() return stub.map end }
Menu = { GetManager = function() return { CloseMenus = function() stub.menusClosed = stub.menusClosed + 1 end } end }
function CloseDropDownMenus() end
function GetCursorPosition() return stub.cursor[1], stub.cursor[2] end
function GetTime() return stub.time end
function InCombatLockdown() return stub.combat end
function IsInGroup() return stub.inGroup end
function IsInInstance() return stub.instance ~= "none", stub.instance end
function GetZonePVPInfo() return stub.pvp end
function UnitExists(token) return stub.units[token] ~= nil end
function UnitGUID(token) return stub.units[token] and stub.units[token].guid end
function UnitName(token) return stub.units[token] and stub.units[token].name end
function GetRaidTargetIndex(token) return stub.units[token] and stub.units[token].icon end
function GetMouseFoci() return { stub.focus } end
function date(fmt) return "00:00:00" end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(stub.printed, table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- Driving
---------------------------------------------------------------------------
function stub.Fire(event, ...)
    for f in pairs(stub.events[event] or {}) do
        local fn = f.scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

-- The topmost shown, mouse-enabled frame under the cursor (children above parents)
function stub.FrameUnderCursor()
    local best, bestLevel
    for _, f in ipairs(stub.frames) do
        if f.mouse and f:IsVisible() and f:IsMouseOver() and f ~= UIParent and f ~= WorldFrame then
            local level = f:GetFrameLevel()
            if not best or level > bestLevel then best, bestLevel = f, level end
        end
    end
    return best
end

-- A full mouse click at the cursor: GLOBAL_MOUSE_DOWN, then the frame under the cursor gets
-- OnMouseDown; a secure macro button records its macrotext and runs its OnClick hooks (mouse up).
function stub.Click(button)
    button = button or "LeftButton"
    local f = stub.FrameUnderCursor() -- what is there when the button goes down
    stub.Fire("GLOBAL_MOUSE_DOWN", button)
    if not f then return nil end
    f:Run("OnMouseDown", button)
    if f.attributes.type1 == "macro" and button == "LeftButton" then
        table.insert(stub.macros, f.attributes.macrotext1)
    end
    f:Run("OnClick", button)
    return f
end

function stub.Update(frame)
    if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.016) end
end

return stub

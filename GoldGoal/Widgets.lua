-- GoldGoal: the widgets the window is built from. Buttons, tabs, a dropdown
-- menu, column headers, list panels, progress bars, stat cells and the
-- pooled rows the pages fill. Everything is painted through Style.lua.
local _, ns = ...
local Style = ns.Style

local UI = {}
ns.UI = UI

-- Layout constants
UI.WIDTH = 400
UI.HEIGHT = 500
UI.PAD = 8            -- content inset from the window edge
UI.TITLE_H = 25       -- title band height
UI.TAB_H, UI.TAB_W = 22, 80
UI.ROW_H = 24         -- character / day row
UI.GUTTER = 12        -- scrollbar gutter right of a list
UI.COL_GOLD, UI.COL_SEEN = 104, 64          -- Characters tab
UI.COL_EARNED, UI.COL_QUOTA, UI.COL_MARK = 90, 84, 22 -- History tab

local ARROW_ATLAS = "Azerite-PointingArrow"
local CHECK_ATLAS

-- Row pools, one per list (the test harness reads them too).
UI.Pools = { charRows = {}, dayRows = {} }

-- Bumped whenever the looks change, so the progress bars know the fill
-- under them may have been repainted and their own colour has to go back
-- on even when it has not changed (see ProgressBar:SetColor).
UI.fillEpoch = 0
Style.OnLooksChanged(function() UI.fillEpoch = UI.fillEpoch + 1 end)

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
function UI.Tip(widget, anchor, title, ...)
    local lines = { ... }
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A single-line FontString with the given justification.
function UI.Line(parent, size, justify, r, g, b, a)
    local fs = Style.Text(parent, size, r, g, b, a)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Flat block button with a text label.
function UI.TextButton(parent, text, w, h, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 22)
    b.Text = Style.Text(b, size or 11)
    b.Text:SetPoint("CENTER", 0, 0)
    b.Text:SetText(text)
    Style.Button(b)
    return b
end

-- Title-bar glyph button (no block, like the close X).
function UI.GlyphButton(parent, atlas, size, file)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("CENTER", 0, 0)
    b.Icon:SetSize(size - 6, size - 6)
    if atlas then b.Icon:SetAtlas(atlas) else b.Icon:SetTexture(file) end
    b.Icon:SetVertexColor(1, 1, 1, 0.75)
    b:HookScript("OnEnter", function(self) self.Icon:SetVertexColor(1, 1, 1, 1) end)
    b:HookScript("OnLeave", function(self) self.Icon:SetVertexColor(1, 1, 1, 0.75) end)
    return b
end

function UI.Check(parent, size)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(size or 22, size or 22)
    Style.Checkbox(cb)
    return cb
end

-- Text input with the house look.
function UI.EditBox(parent, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetHeight(h or 20)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Style.EditBox(eb)
    return eb
end

-- A check mark in the accent colour (quota met).
function UI.CheckMark(parent, size)
    CHECK_ATLAS = CHECK_ATLAS or Style.FindAtlas({ "common-icon-checkmark", "checkmark-minimal" }) or false
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    if CHECK_ATLAS then t:SetAtlas(CHECK_ATLAS) else t:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") end
    local function Tint() t:SetVertexColor(Style.Accent()) end
    Tint()
    Style.OnLooksChanged(Tint)
    return t
end

-- A chevron: the dropdown's.
local function Arrow(parent, w, h, alpha)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetAtlas(ARROW_ATLAS)
    t:SetSize(w, h)
    t:SetVertexColor(1, 1, 1, alpha or 0.6)
    return t
end

-- Class colour hex for a class file name ("WARRIOR"), white when unknown.
function UI.ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return ns.HexColor(c.r, c.g, c.b) end
    return "|cffffffff"
end

-------------------------------------------------------------------------------
-- Dropdown: a block button showing the current choice; clicking it opens a
-- flat menu underneath. entries() returns { { text, checked, onClick, tip }, ... }.
-- One menu frame serves every dropdown; it closes on a click anywhere else.
-------------------------------------------------------------------------------
local menu
local MENU_ROW_H = 20

local function ShowRowTip(row)
    local tip = row.entry and row.entry.tip
    if not tip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if type(tip) == "function" then
        tip(GameTooltip)
    else
        local lines = type(tip) == "table" and tip or { tip }
        GameTooltip:AddLine(lines[1] or "")
        for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
end

function UI.CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

function UI.IsMenuShown()
    return (menu and menu:IsShown()) and true or false
end

local function MenuRow(i)
    local row = menu.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetHeight(MENU_ROW_H)
    row:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * MENU_ROW_H))
    row:SetPoint("TOPRIGHT", -1, -(1 + (i - 1) * MENU_ROW_H))
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.1)
    row.Mark = row:CreateTexture(nil, "ARTWORK")
    row.Mark:SetSize(6, 6)
    row.Mark:SetPoint("LEFT", 8, 0)
    row.Text = UI.Line(row, 11)
    row.Text:SetPoint("LEFT", 20, 0)
    row.Text:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self)
        UI.CloseMenu()
        if self.entry.onClick then self.entry.onClick() end
    end)
    row:SetScript("OnEnter", ShowRowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    menu.rows[i] = row
    return row
end

local function OpenMenu(owner, entries)
    if not menu then
        -- on the screen itself, above everything: the owner may sit in a
        -- window of ours or in EllesmereUI's panel, which is why it is not
        -- a child of either
        menu = CreateFrame("Frame", nil, UIParent)
        UI.Menu = menu
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel(100)
        menu:EnableMouse(true)
        menu:Hide()
        menu.rows = {}
        Style.Panel(menu)
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
        end)
        menu:SetScript("OnHide", function(self) self.owner = nil; GameTooltip:Hide() end)
    end
    if menu:IsShown() and menu.owner == owner then UI.CloseMenu(); return end
    GameTooltip:Hide()
    menu.owner = owner
    local r, g, b = Style.Accent()
    for i, entry in ipairs(entries) do
        local row = MenuRow(i)
        row.entry = entry
        row.Text:SetText(entry.text or "")
        row.Text:SetAlpha(entry.checked and 1 or 0.8)
        row.Mark:SetColorTexture(r, g, b, 1)
        row.Mark:SetShown(entry.checked and true or false)
        row:Show()
    end
    for i = #entries + 1, #menu.rows do menu.rows[i]:Hide() end
    -- the owner's scale, so the menu matches the panel it drops out of
    local os, us = owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if os and us and us > 0 then menu:SetScale(os / us) end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    menu:SetSize(math.max(owner:GetWidth() or 0, 120), #entries * MENU_ROW_H + 2)
    menu:Show()
end

-- w = nil leaves the width to the caller's anchors.
function UI.Dropdown(parent, w, h, entries)
    local b = CreateFrame("Button", nil, parent)
    if w then b:SetWidth(w) end
    b:SetHeight(h or 22)
    b.Arrow = Arrow(b, 12, 9, 0.7)
    b.Arrow:SetPoint("RIGHT", -6, 0)
    b.Text = UI.Line(b, 11)
    b.Text:SetPoint("LEFT", 6, 0)
    b.Text:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 0)
    Style.Button(b, { "Arrow" })
    b.entries = entries
    b:SetScript("OnClick", function(self) OpenMenu(self, self.entries()) end)
    b:HookScript("OnHide", function(self) if menu and menu.owner == self then UI.CloseMenu() end end)
    return b
end

-------------------------------------------------------------------------------
-- Tabs and headers
-------------------------------------------------------------------------------
local function NewTab(parent, w, h, text, tabID)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(w, h)
    tab.Text = Style.Text(tab, 11)
    tab.Text:SetPoint("CENTER", 0, 0)
    tab.Text:SetText(text)
    tab.tabID = tabID
    return tab
end

-- A row of small tabs. defs = { { id, text, tip }, ... }; onSelect(id).
function UI.TabStrip(parent, defs, w, onSelect)
    local tabs = CreateFrame("Frame", nil, parent)
    tabs:SetSize(#defs * w + (#defs - 1), 20)
    tabs.Tabs = {}
    local prev
    for _, def in ipairs(defs) do
        local tab = NewTab(tabs, w, 20, def[2], def[1])
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab:SetScript("OnClick", function(self)
            Style.SelectTab(tabs, self.tabID)
            onSelect(self.tabID)
        end)
        Style.Tab(tab)
        if def[3] then UI.Tip(tab, "ANCHOR_TOP", def[2], def[3]) end
        tabs.Tabs[def[1]] = tab
        prev = tab
    end
    return tabs
end

-- Column header tabs above a list: a full-width first tab plus fixed-width
-- columns. defs = { { id, text, width|nil, tip }, ... }; onSelect(id) sets the sort.
function UI.ColumnHeader(page, defs, onSelect, top)
    local colHead = CreateFrame("Frame", nil, page)
    colHead:SetPoint("TOPLEFT", 0, -(top or 0))
    colHead:SetPoint("TOPRIGHT", -UI.GUTTER, -(top or 0))
    colHead:SetHeight(20)
    local prev
    for i = #defs, 1, -1 do
        local def = defs[i]
        local tab = NewTab(colHead, def[3] or 1, 20, def[2], def[1])
        if not def[3] then tab:SetPoint("LEFT", 0, 0) end
        if prev then tab:SetPoint("RIGHT", prev, "LEFT", -1, 0) else tab:SetPoint("RIGHT", 0, 0) end
        tab:SetScript("OnClick", function()
            if onSelect then onSelect(def[1]) end
            Style.SelectTab(colHead, def[1])
            ns:RefreshWindow()
        end)
        Style.Tab(tab)
        if def[4] then UI.Tip(tab, "ANCHOR_TOP", def[2], def[4]) end
        prev = tab
    end
    return colHead
end

-- A strip along the top of a page (label on the left).
function UI.Strip(page, label)
    local strip = CreateFrame("Frame", nil, page)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", -UI.GUTTER, 0)
    strip:SetHeight(20)
    if label then
        strip.Label = Style.Text(strip, 11, 1, 1, 1, 0.53)
        strip.Label:SetPoint("LEFT", 4, 0)
        strip.Label:SetText(label)
    end
    return strip
end

-- Inset list panel with a scroll frame under a column header; returns list, content.
function UI.ListPanel(page, colHead, bottom)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", colHead, "BOTTOMLEFT", 0, -3)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom or 0)
    Style.Panel(list, { inset = true })
    local scroll, _, content = Style.ScrollFrame(list, UI.WIDTH - 2 * UI.PAD - UI.GUTTER - 4)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -UI.GUTTER, 2)
    return list, content
end

-- A section panel on the Goal page: an inset plate with a small uppercase
-- title in its top-left corner.
function UI.Section(page, title)
    local sec = CreateFrame("Frame", nil, page)
    Style.Panel(sec)
    sec.Title = Style.Text(sec, 10, 1, 1, 1, 0.41)
    sec.Title:SetPoint("TOPLEFT", 8, -7)
    sec.Title:SetText(string.upper(title))
    return sec
end

-------------------------------------------------------------------------------
-- Progress bar: a house status bar in an inset plate, with a text over it.
-- bar:Set(value, max, text) fills it (clamped to 0..1) and sets the text.
-------------------------------------------------------------------------------
function UI.ProgressBar(parent, h, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h or 18)
    Style.Panel(f, { inset = true })
    local function NewBar(level)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", -1, 1)
        bar:SetFrameLevel((f:GetFrameLevel() or 0) + level)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        Style.BarFill(bar)
        return bar
    end
    -- a dimmed second fill underneath, for a part of the value that is
    -- there but not yet gold (crafting stock at cost)
    f.Under = NewBar(2)
    f.Under:SetAlpha(0.35)
    local bar = NewBar(3)
    f.Bar = bar
    -- past 100% a brighter lap runs over the full bar: 150% is a full bar
    -- with a half-length lap on it
    f.Lap = NewBar(4)
    f.Lap:Hide()
    -- text and marks above everything
    f.Top = CreateFrame("Frame", nil, f)
    f.Top:SetAllPoints()
    f.Top:SetFrameLevel((f:GetFrameLevel() or 0) + 6)
    f.Top:EnableMouse(false)
    f.TickFrame = f.Top
    if size then
        f.Text = UI.Line(f.Top, size, "CENTER")
        f.Text:SetPoint("LEFT", 6, 0)
        f.Text:SetPoint("RIGHT", -6, 0)
    end
    local function LapColor(self)
        local c = self.color or { Style.Accent() }
        -- towards white
        self.Lap:SetStatusBarColor(c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5, 0.9)
    end
    -- `extra` fills on past `value` in the dimmed colour.
    function f:Set(value, max, text, extra)
        local frac, frac2, lap = 0, 0, 0
        value = value or 0
        if max and max > 0 then
            frac = math.max(0, math.min(1, value / max))
            frac2 = math.max(0, math.min(1, (value + (extra or 0)) / max))
            if value > max then lap = math.max(0, math.min(1, (value - max) / max)) end
        end
        self.Bar:SetValue(frac)
        self.Under:SetValue(frac2)
        self.Lap:SetValue(lap)
        self.Lap:SetShown(lap > 0)
        if lap > 0 then LapColor(self) end
        self.fraction, self.fraction2, self.lap = frac, frac2, lap
        if self.Text then self.Text:SetText(text or "") end
    end
    -- a colour of its own instead of the house fill (the goal bar). The
    -- colour is recomputed on every refresh and usually comes back the
    -- same; repainting it then is three status-bar writes for nothing.
    -- A looks change repaints the house fill underneath us, so the epoch
    -- it happened at is part of what has to match.
    function f:SetColor(r, g, b)
        local c = self.color
        if c and c[1] == r and c[2] == g and c[3] == b and self.colorEpoch == UI.fillEpoch then return end
        if c then c[1], c[2], c[3] = r, g, b else self.color = { r, g, b } end
        self.colorEpoch = UI.fillEpoch
        self.Bar:SetStatusBarColor(r, g, b, 0.95)
        self.Under:SetStatusBarColor(r, g, b, 0.95)
        LapColor(self)
    end
    -- thin marks at the given fractions (the tiers below the top one)
    f.Ticks = {}
    -- a tick is a light line with a dark edge either side, so it reads on
    -- the light fills and the dark track alike
    local function PlaceTicks(self)
        local w = (self:GetWidth() or 0) - 2
        for i, tick in ipairs(self.Ticks) do
            local frac = self.tickFracs and self.tickFracs[i]
            if frac and w > 0 then
                local x = 1 + math.floor(frac * w + 0.5)
                tick:ClearAllPoints()
                tick:SetPoint("TOP", self, "TOPLEFT", x, -1)
                tick:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, 1)
                tick:Show()
                tick.Shadow:Show()
            else
                tick:Hide()
                tick.Shadow:Hide()
            end
        end
    end
    -- The marks are worked out again on every refresh and hardly ever
    -- move; placing one costs a ClearAllPoints and two SetPoints, so an
    -- unchanged list is left where it is.
    local function SameFracs(old, fracs)
        if not old or #old ~= #fracs then return false end
        for i = 1, #fracs do
            if old[i] ~= fracs[i] then return false end
        end
        return true
    end
    function f:SetTicks(fracs)
        fracs = fracs or {}
        if SameFracs(self.tickFracs, fracs) then return end
        self.tickFracs = fracs
        for i = #self.Ticks + 1, #self.tickFracs do
            local t = self.TickFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetWidth(2)
            t:SetColorTexture(1, 1, 1, 0.9)
            local s = self.TickFrame:CreateTexture(nil, "OVERLAY", nil, 1)
            s:SetColorTexture(0, 0, 0, 0.6)
            s:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 0)
            s:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, 0)
            t.Shadow = s
            self.Ticks[i] = t
        end
        PlaceTicks(self)
    end
    f:SetScript("OnSizeChanged", PlaceTicks)
    return f
end

-- The goal bar's colour for a fill fraction: red through yellow to green
-- up to the hard goal (at `hardFrac` of the bar), then blue into the
-- accent colour from there to the end.
-- The stops are the shipped ones unless the look settings name others.
local DEF_RED, DEF_YELLOW, DEF_GREEN, DEF_BLUE = { 0.85, 0.22, 0.22 }, { 0.95, 0.80, 0.15 }, { 0.25, 0.80, 0.35 }, { 0.30, 0.55, 0.95 }
local function Lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end
function UI.GoalStops()
    local c = ns.db and ns.db.look and ns.db.look.colors or {}
    return c.red or DEF_RED, c.yellow or DEF_YELLOW, c.green or DEF_GREEN, c.blue or DEF_BLUE
end
function UI.GoalColor(frac, hardFrac, ar, ag, ab)
    local RED, YELLOW, GREEN, BLUE = UI.GoalStops()
    frac = math.max(0, math.min(1, frac or 0))
    hardFrac = math.max(0, math.min(1, hardFrac or 1))
    if frac <= hardFrac then
        local t = hardFrac > 0 and (frac / hardFrac) or 1
        if t < 0.5 then return Lerp(RED, YELLOW, t * 2) end
        return Lerp(YELLOW, GREEN, (t - 0.5) * 2)
    end
    if hardFrac >= 1 then return GREEN[1], GREEN[2], GREEN[3] end
    local accent = { ar or 1, ag or 1, ab or 1 }
    if not ar then accent = { Style.Accent() } end
    return Lerp(BLUE, accent, (frac - hardFrac) / (1 - hardFrac))
end

-- A stat cell: a dim label over a value.
function UI.Stat(parent, label, w)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 100, 30)
    f.Label = UI.Line(f, 10, "LEFT", 1, 1, 1, 0.53)
    f.Label:SetPoint("TOPLEFT", 0, 0)
    f.Label:SetPoint("TOPRIGHT", 0, 0)
    f.Label:SetText(label)
    f.Value = UI.Line(f, 12, "LEFT")
    f.Value:SetPoint("TOPLEFT", 0, -13)
    f.Value:SetPoint("TOPRIGHT", 0, -13)
    return f
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
function UI.RowBackground(row, index, highlighted)
    if highlighted then
        local r, g, b = Style.Accent()
        row.Bg:SetColorTexture(r, g, b, 0.15)
    elseif index % 2 == 0 then
        row.Bg:SetColorTexture(1, 1, 1, 0.03)
    else
        row.Bg:SetColorTexture(1, 1, 1, 0)
    end
end

local function RowBase(content, kind)
    local row = CreateFrame(kind or "Button", nil, content)
    row:SetHeight(UI.ROW_H)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints()
    row.Bg:SetColorTexture(1, 1, 1, 0)
    row.Hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.Hover:SetAllPoints()
    row.Hover:SetColorTexture(1, 1, 1, 0.06)
    return row
end

-- Characters tab: include box, class-coloured name, realm, gold, last seen.
function UI.NewCharRow(content, onCheck, onRightClick, onEnter)
    local row = RowBase(content)
    row.Check = UI.Check(row, 18)
    row.Check:SetPoint("LEFT", 2, 0)
    row.Check:SetScript("OnClick", function(self) onCheck(row, self:GetChecked() and true or false) end)
    row.Seen = UI.Line(row, 10, "RIGHT", 1, 1, 1, 0.53)
    row.Seen:SetWidth(UI.COL_SEEN)
    row.Seen:SetPoint("RIGHT", -4, 0)
    row.Gold = UI.Line(row, 12, "RIGHT")
    row.Gold:SetWidth(UI.COL_GOLD)
    row.Gold:SetPoint("RIGHT", row.Seen, "LEFT", -2, 0)
    row.Name = UI.Line(row, 12)
    row.Name:SetPoint("LEFT", row.Check, "RIGHT", 4, 0)
    row.Name:SetPoint("RIGHT", row.Gold, "LEFT", -4, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if onRightClick then onRightClick(self) end
        else
            self.Check:Click()
        end
    end)
    row:SetScript("OnEnter", function(self) if onEnter then onEnter(self) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- History tab: date, a slim bar of earned against the quota, earned, quota, a mark.
function UI.NewDayRow(content)
    local row = RowBase(content, "Frame")
    row.Mark = UI.CheckMark(row, 14)
    row.Mark:SetPoint("RIGHT", -6, 0)
    row.Quota = UI.Line(row, 11, "RIGHT", 1, 1, 1, 0.6)
    row.Quota:SetWidth(UI.COL_QUOTA)
    row.Quota:SetPoint("RIGHT", -UI.COL_MARK - 2, 0)
    row.Earned = UI.Line(row, 12, "RIGHT")
    row.Earned:SetWidth(UI.COL_EARNED)
    row.Earned:SetPoint("RIGHT", row.Quota, "LEFT", -2, 0)
    row.Date = UI.Line(row, 11)
    row.Date:SetWidth(76)
    row.Date:SetPoint("LEFT", 6, 0)
    row.Mini = UI.ProgressBar(row, 8)
    row.Mini:SetPoint("LEFT", row.Date, "RIGHT", 4, 0)
    row.Mini:SetPoint("RIGHT", row.Earned, "LEFT", -8, 0)
    return row
end

-------------------------------------------------------------------------------
-- Layout: rows taken from pools and stacked down a content frame.
-------------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function UI.Layout(content)
    return setmetatable({ content = content, y = 0, used = {} }, Layout)
end

-- The next row from `pool` (made by `factory` when the pool runs short),
-- placed at the cursor, `indent` from the left; the cursor moves `height` down.
function Layout:Add(pool, factory, height, indent)
    local i = (self.used[pool] or 0) + 1
    self.used[pool] = i
    local w = pool[i]
    if not w then w = factory(); pool[i] = w end
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent or 0, -self.y)
    w:SetWidth(self.content:GetWidth() - (indent or 0))
    w:Show()
    self.y = self.y + height
    return w
end

function Layout:Count(pool)
    return self.used[pool] or 0
end

function Layout:Gap(h)
    self.y = self.y + h
end

-- Hides the unused rows of the given pools and sizes the content.
function Layout:Finish(...)
    for _, pool in ipairs({ ... }) do
        for i = (self.used[pool] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.content:SetHeight(math.max(self.y, 1))
end

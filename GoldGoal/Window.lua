-- GoldGoal: the main window. A shell that EllesmereUI paints when present
-- (Style.lua) holding the Goal, Characters and History pages and the
-- Settings page, with the tab row hanging under it. Free-floating: drag
-- the title bar, the position is remembered.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local WIDTH, HEIGHT, PAD, TITLE_H = UI.WIDTH, UI.HEIGHT, UI.PAD, UI.TITLE_H
local frame

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.window.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

function ns:AnchorWindow()
    if not frame then return end
    frame:SetScale(self.db.window.scale or 1)
    frame:ClearAllPoints()
    local pos = self.db.window.pos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------
local function BuildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "GoldGoalFrame", UIParent)
    UI.Frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    Style.Shell(frame)

    -- title band, the drag handle
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    frame.TitleBar = title
    local titleText = Style.Text(title, 12)
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("GoldGoal")
    Style.OnLooksChanged(function() titleText:SetTextColor(Style.Accent()) end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetSize(24, 24)
    close:SetScript("OnClick", function() ns:HideWindow() end)
    Style.CloseButton(close)

    local cogAtlas = Style.FindAtlas({ "mechagon-projects", "GM-icon-settings" })
    local cog = UI.GlyphButton(title, cogAtlas, 20, "Interface\\Icons\\Trade_Engineering")
    cog:SetPoint("RIGHT", close, "LEFT", -2, 0)
    cog:SetScript("OnClick", function() ns:ToggleOptionsPanel() end)
    UI.Tip(cog, "ANCHOR_BOTTOM", "Settings", "Click again to come back.")
    frame.SettingsButton = cog

    frame.Pages = {}
    local function NewPage(key)
        local p = CreateFrame("Frame", nil, frame)
        p:SetPoint("TOPLEFT", PAD, -(TITLE_H + 6))
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        p:Hide()
        frame.Pages[key] = p
        return p
    end
    for _, tab in ipairs(UI.Tabs) do tab.Build(NewPage(tab.key), WIDTH - 2 * PAD) end
    ns:BuildSettingsPage(NewPage("settings"))

    -- the tab row under the frame; Settings is the cog in the title bar
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", PAD, 1)
    tabs:SetSize(#UI.Tabs * UI.TAB_W + (#UI.Tabs - 1), UI.TAB_H)
    frame.TabRow = tabs
    for i, def in ipairs(UI.Tabs) do
        local tab = CreateFrame("Button", nil, tabs)
        tab:SetSize(UI.TAB_W, UI.TAB_H)
        tab:SetPoint("LEFT", (i - 1) * (UI.TAB_W + 1), 0)
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def.label)
        tab.tabID = def.key
        tab:SetScript("OnClick", function() ns:ShowPage(def.key) end)
        Style.Tab(tab)
    end

    frame:SetScript("OnShow", function() ns:RefreshWindow() end)
    frame:SetScript("OnHide", function() UI.CloseMenu() end)
    tinsert(UISpecialFrames, "GoldGoalFrame")
    return frame
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
function ns:ShowPage(key)
    BuildFrame()
    if not frame.Pages[key] then key = "goal" end
    for k, p in pairs(frame.Pages) do p:SetShown(k == key) end
    UI.CloseMenu()
    if key ~= "settings" then frame.lastPage = key end
    frame.page = key
    Style.SelectTab(frame.TabRow, key)
    self:RefreshWindow()
end

function ns:CurrentPage()
    return frame and frame.page or "goal"
end

-- The cog: Settings, or back to the tab it came from.
function ns:ToggleOptionsPanel()
    self:ShowPage(self:CurrentPage() == "settings" and (frame and frame.lastPage or "goal") or "settings")
end

function ns:OpenOptions()
    self:ShowWindow()
    self:ShowPage("settings")
end

function ns:RefreshWindow()
    if not frame or not frame:IsShown() then return end
    local page = frame.page or "goal"
    if page == "settings" then
        self:RefreshSettings()
        return
    end
    for _, tab in ipairs(UI.Tabs) do
        if tab.key == page then tab.Refresh(frame.Pages[page]) end
    end
end

-------------------------------------------------------------------------------
-- Show and hide
-------------------------------------------------------------------------------
function ns:ShowWindow()
    BuildFrame()
    self:AnchorWindow()
    if not frame.page then self:ShowPage("goal") end
    frame:Show()
    self:RefreshWindow()
end

function ns:HideWindow()
    if frame then frame:Hide() end
end

-- The window itself, whatever EllesmereUI offers.
function ns:ToggleWindowFrame()
    if frame and frame:IsShown() then self:HideWindow() else self:ShowWindow() end
end

-- What /gg, the bar and the broker open: the GoldGoal page in
-- EllesmereUI's panel when it is there, the window otherwise.
function ns:ToggleWindow()
    if self.OpenEUIOptions and self:OpenEUIOptions(true) then return end
    self:ToggleWindowFrame()
end

function ns:IsWindowShown()
    return frame and frame:IsShown()
end

ns:On("DB_READY", function() BuildFrame() end)
for _, message in ipairs({ "WEALTH_CHANGED", "SETTINGS_CHANGED" }) do
    ns:On(message, function() ns:RefreshWindow() end)
end
Style.OnLooksChanged(function() ns:RefreshWindow() end)

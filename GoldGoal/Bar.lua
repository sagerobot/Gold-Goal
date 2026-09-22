-- GoldGoal: the on-screen bar. One progress bar showing today's (or this
-- week's) earnings against the quota. Click opens the window, right-click
-- flips daily/weekly, drag moves it (Shift-drag once locked).
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local bar
local BAR_H = 20
local NO_TICKS = {} -- shared, so a bar with no marks allocates nothing

local function SavePosition()
    local point, _, relPoint, x, y = bar:GetPoint(1)
    ns.db.bar.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("Button", "GoldGoalBar", UIParent)
    ns.Bar = bar
    bar:SetSize(ns.db.bar.width, BAR_H)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:RegisterForDrag("LeftButton")
    bar:Hide()

    bar.Progress = UI.ProgressBar(bar, BAR_H, 11)
    bar.Progress:SetAllPoints()
    bar.Label = UI.Line(bar.Progress.Top, 10, "LEFT", 1, 1, 1, 0.6)
    bar.Label:SetPoint("LEFT", 5, 0)
    -- a mark at the end once the quota is met
    bar.Check = UI.CheckMark(bar.Progress.Top, 12)
    bar.Check:SetPoint("RIGHT", -4, 0)
    bar.Check:Hide()
    bar.Progress.Text:ClearAllPoints()
    bar.Progress.Text:SetPoint("LEFT", bar.Label, "RIGHT", 4, 0)
    bar.Progress.Text:SetPoint("RIGHT", -5, 0)

    bar:SetScript("OnDragStart", function(self)
        if not ns.db.bar.locked or IsShiftKeyDown() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    bar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns:SetBarMode(ns.db.bar.mode == "daily" and "weekly" or "daily")
        else
            ns:ToggleWindow()
        end
    end)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        ns:PaceTooltip(GameTooltip)
        if not ns.db.bar.locked then GameTooltip:AddLine("|cff888888Drag to move; lock it in Settings.|r") end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bar
end

local function ApplyFont(fs, size)
    local font = fs:GetFont() or STANDARD_TEXT_FONT
    fs:SetFont(font, size, "")
end

function ns:AnchorBar()
    if not bar then return end
    local cfg, look = self.db.bar, self.db.look or {}
    bar:SetScale(cfg.scale or 1)
    bar:SetWidth(cfg.width or 220)
    bar:SetHeight(look.barHeight or BAR_H)
    bar:SetAlpha(look.barAlpha or 1)
    ApplyFont(bar.Progress.Text, look.barFont or 11)
    ApplyFont(bar.Label, math.max(8, (look.barFont or 11) - 1))
    bar.Label:SetShown(look.barLabel ~= false)
    bar:ClearAllPoints()
    local pos = cfg.pos
    if pos and pos.point then
        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -30)
    end
end

-- Whether the bar shows the week right now: its mode, or the day is met
-- and the option says to move on to the week (while the week is not).
function ns:BarShowsWeek(p)
    p = p or self:Projection()
    if self.db.bar.mode == "weekly" then return true end
    if self.db.bar.afterMet == "week" and p.quota and p.quota > 0 and p.today >= p.quota
        and p.weekQuota and p.weekQuota > 0 and p.week < p.weekQuota then
        return true
    end
    return false
end

-- The bar's text: "+8,450g / 14,000g  60%".
function ns:BarText(p, weekly)
    p = p or self:Projection()
    if weekly == nil then weekly = self:BarShowsWeek(p) end
    local earned = weekly and p.week or p.today
    local quota = weekly and p.weekQuota or p.quota
    if not quota then return self.FormatSigned(earned, true) .. "  |cff888888no deadline|r" end
    local pct = math.max(0, self.Percent(earned, quota) or 0)
    if self.db.look and self.db.look.barPercent == false then
        return string.format("%s / %s", self.FormatSigned(earned, true), self.FormatGoldShort(quota))
    end
    return string.format("%s / %s  %d%%", self.FormatSigned(earned, true), self.FormatGoldShort(quota), pct)
end

-- A keystone run in progress.
function ns:InMythicPlus()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active then return true end
    end
    if GetInstanceInfo then
        local ok, _, _, difficultyID = pcall(GetInstanceInfo)
        if ok and difficultyID == 8 then return true end -- Mythic Keystone
    end
    return false
end

-- Whether the instance rule hides the bar right now.
--   smart: Mythic+ always, raids while in combat (between pulls the AH
--          mount is a click away), battlegrounds and arenas always;
--          everything else, solo or grouped, keeps it.
--   group: any instance while grouped, battlegrounds and arenas always.
--   hide:  every instance. show: never.
function ns:BarHiddenByInstance()
    local mode = self.db.bar.instanceMode or "smart"
    if mode == "show" or not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType == "none" then return false end
    if mode == "hide" then return true end
    if instanceType == "pvp" or instanceType == "arena" then return true end
    if mode == "group" then return (IsInGroup and IsInGroup()) and true or false end
    if instanceType == "party" then return self:InMythicPlus() end
    if instanceType == "raid" then return InCombatLockdown() and true or false end
    return false
end

-- Shows the bar for a few seconds whatever the rules say, to find it.
local PEEK = 6
function ns:PeekBar()
    if not bar then return end
    self.barPeekUntil = (GetTime and GetTime() or time()) + PEEK
    self:RefreshBar()
    C_Timer.After(PEEK + 0.1, function() ns:RefreshBar() end)
end

-- Whether the rules let the bar be on screen at all right now.
function ns:BarAllowed()
    if self.barPeekUntil and (GetTime and GetTime() or time()) < self.barPeekUntil then return true end
    if not self.db.bar.shown then return false end
    if self.db.bar.hideInCombat and InCombatLockdown() then return false end
    if self:BarHiddenByInstance() then return false end
    return true
end

-- Combat, zoning, the group and keystones change whether the bar is on
-- screen, never what it says, and they fire far more often than gold
-- moves (a battleground is a stream of GROUP_ROSTER_UPDATE). So they
-- settle the visibility and only repaint for the trip back on screen.
function ns:UpdateBarVisibility()
    if not bar or not self.db then return end
    if not self:BarAllowed() then bar:Hide(); return end
    if bar:IsShown() then return end
    self:RefreshBar()
end

function ns:RefreshBar()
    if not bar or not self.db then return end
    if not self:BarAllowed() then bar:Hide(); return end
    local p = self:Projection()
    local weekly = self:BarShowsWeek(p)
    bar.Label:SetText(weekly and "Week" or "Today")
    local earned = weekly and p.week or p.today
    local quota = weekly and p.weekQuota or p.quota
    bar.Progress:Set(earned, quota, self:BarText(p, weekly))
    local met = quota and quota > 0 and earned >= quota and true or false
    bar.Check:SetShown(met)
    -- the text sits between the label and the check mark, both of which
    -- come and go; re-anchoring it is four layout calls, so it is only
    -- done when one of the two has actually changed
    local labelled = (self.db.look or {}).barLabel ~= false
    local anchoring = (labelled and "L" or "-") .. (met and "M" or "-")
    if bar.textAnchoring ~= anchoring then
        bar.textAnchoring = anchoring
        bar.Progress.Text:ClearAllPoints()
        bar.Progress.Text:SetPoint("LEFT", labelled and bar.Label or bar.Progress, labelled and "RIGHT" or "LEFT", labelled and 4 or 5, 0)
        bar.Progress.Text:SetPoint("RIGHT", met and bar.Check or bar.Progress, met and "LEFT" or "RIGHT", met and -4 or -5, 0)
    end
    -- the tiers on the quota: marks where each still needs the day to be,
    -- red to green up to the hard goal, blue into the accent past it
    if quota and quota > 0 and (self.db.look or {}).barColors ~= false then
        local ticks, hardFrac = self:QuotaTicks(p)
        bar.Progress:SetTicks(ticks)
        bar.Progress:SetColor(UI.GoalColor(earned / quota, hardFrac))
    else
        bar.Progress:SetTicks(NO_TICKS)
        bar.Progress:SetColor(Style.Accent())
    end
    bar:Show()
end

function ns:SetBarShown(on)
    self.db.bar.shown = on and true or false
    self:RefreshBar()
    self:Fire("SETTINGS_CHANGED")
end

function ns:SetBarLocked(on)
    self.db.bar.locked = on and true or false
    self:Fire("SETTINGS_CHANGED")
end

function ns:SetBarMode(mode)
    self.db.bar.mode = mode == "weekly" and "weekly" or "daily"
    self:RefreshBar()
    self:Fire("SETTINGS_CHANGED")
end

function ns:ResetBarPosition()
    self.db.bar.pos = nil
    self:AnchorBar()
end

ns:On("LOGIN", function()
    BuildBar()
    ns:AnchorBar()
    ns:RefreshBar()
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" }) do
        ns:RegisterEvent(event, function() ns:UpdateBarVisibility() end)
    end
end)
ns:On("WEALTH_CHANGED", function() ns:RefreshBar() end)
ns:On("SETTINGS_CHANGED", function() ns:AnchorBar(); ns:RefreshBar() end)
Style.OnLooksChanged(function() ns:RefreshBar() end)

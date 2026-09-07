-- GoldGoal: the three tabs. Goal shows the target, today, this week and the
-- pace; Characters lists everything the total is made of; History lists
-- the days (or weeks) against their quotas.
local _, ns = ...
local Style, UI = ns.Style, ns.UI
local P = UI.Pools

local ROW_H = UI.ROW_H
local SEC_GAP = 6

-- A page built more than once (the window and the EllesmereUI panel) keeps
-- its own row pools, since a row belongs to the content it was made in.
local function Pools(page)
    return page.pools or P
end

-------------------------------------------------------------------------------
-- Goal
-------------------------------------------------------------------------------
local TIER_ROW_H = 15
local BAR_H = 24           -- the goal and quota bars: room around the text
local TARGET_BASE_H = 102  -- the target section above its tier rows

local function BuildGoal(page, width)
    local w = width or (UI.WIDTH - 2 * UI.PAD)
    -- sections hang off each other, so the target section may grow with its tiers
    local prev
    local function Section(title, h)
        local sec = UI.Section(page, title)
        if prev then
            sec:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SEC_GAP)
            sec:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -SEC_GAP)
        else
            sec:SetPoint("TOPLEFT", 0, 0)
            sec:SetPoint("TOPRIGHT", 0, 0)
        end
        if h then sec:SetHeight(h) end
        prev = sec
        return sec
    end

    -- Target: the paced tier, the ladder bar with a mark per tier, and a
    -- row per tier that can be clicked to pace towards it
    local target = Section("Target", TARGET_BASE_H)
    page.Target = target
    page.TargetTitle = UI.Line(target, 13, "LEFT")
    page.TargetTitle:SetPoint("TOPLEFT", 8, -22)
    page.TargetTitle:SetWidth(200)
    page.TargetBy = UI.Line(target, 11, "RIGHT", 1, 1, 1, 0.6)
    page.TargetBy:SetPoint("TOPLEFT", 208, -24)
    page.TargetBy:SetPoint("TOPRIGHT", -8, -24)
    page.TargetBar = UI.ProgressBar(target, BAR_H, 11)
    page.TargetBar:SetPoint("TOPLEFT", 8, -42)
    page.TargetBar:SetPoint("TOPRIGHT", -8, -42)
    page.TargetLine = UI.Line(target, 10, "LEFT", 1, 1, 1, 0.6)
    page.TargetLine:SetPoint("TOPLEFT", 8, -72)
    page.TargetLine:SetPoint("TOPRIGHT", -8, -72)
    page.TargetLine2 = UI.Line(target, 10, "LEFT", 1, 1, 1, 0.6)
    page.TargetLine2:SetPoint("TOPLEFT", 8, -86)
    page.TargetLine2:SetPoint("TOPRIGHT", -8, -86)
    page.TierRows = {}
    for i = 1, ns.MAX_TIERS do
        local row = CreateFrame("Button", nil, target)
        row:SetHeight(TIER_ROW_H)
        row:SetPoint("TOPLEFT", 4, -(TARGET_BASE_H - 2 + (i - 1) * TIER_ROW_H))
        row:SetPoint("TOPRIGHT", -4, -(TARGET_BASE_H - 2 + (i - 1) * TIER_ROW_H))
        row.Bg = row:CreateTexture(nil, "BACKGROUND")
        row.Bg:SetAllPoints()
        row.Bg:SetColorTexture(1, 1, 1, 0)
        row.Hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.Hover:SetAllPoints()
        row.Hover:SetColorTexture(1, 1, 1, 0.06)
        row.Verdict = UI.Line(row, 10, "RIGHT")
        row.Verdict:SetPoint("RIGHT", -4, 0)
        row.Verdict:SetWidth(math.max(210, math.floor(w * 0.55)))
        row.Gold = UI.Line(row, 10, "RIGHT")
        row.Gold:SetWidth(76)
        row.Gold:SetPoint("RIGHT", row.Verdict, "LEFT", -6, 0)
        row.Name = UI.Line(row, 10)
        row.Name:SetPoint("LEFT", 4, 0)
        row.Name:SetPoint("RIGHT", row.Gold, "LEFT", -4, 0)
        row.index = i
        row:SetScript("OnClick", function(self) ns:SetTierIndex(self.index) end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local e = self.tier
            if e then
                GameTooltip:AddLine(e.name .. "  " .. ns.FormatGold(e.gold))
                GameTooltip:AddLine(e.reached and "Banked." or string.format("%s still to save.", ns.FormatGold(e.remaining)), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(e.paced and "The daily quota paces towards this tier." or (e.reached and "" or "Click to pace the daily quota towards this tier instead."), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine("|cff888888The pacing moves up to the next tier by itself once one is banked.|r", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        page.TierRows[i] = row
    end

    -- Today and this week
    local function PeriodSection(title)
        local sec = Section(title, 70)
        sec.Reset = UI.Line(sec, 10, "RIGHT", 1, 1, 1, 0.53)
        sec.Reset:SetPoint("TOPRIGHT", -8, -7)
        sec.Bar = UI.ProgressBar(sec, BAR_H, 11)
        sec.Bar:SetPoint("TOPLEFT", 8, -20)
        sec.Bar:SetPoint("TOPRIGHT", -8, -20)
        sec.Line = UI.Line(sec, 10, "LEFT", 1, 1, 1, 0.6)
        sec.Line:SetPoint("TOPLEFT", 8, -50)
        sec.Line:SetPoint("TOPRIGHT", -8, -50)
        return sec
    end
    page.Today = PeriodSection("Today")
    page.Week = PeriodSection("This week")

    -- Pace: a grid of stats and the status line, filling the rest
    local pace = Section("Pace")
    pace:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    local colW = math.floor((w - 16 - 8) / 3)
    local defs = { { "avg7", "7-day average" }, { "avg30", "30-day average" }, { "avgGoal", "Since goal start" },
        { "finish7", "Finish (7-day pace)" }, { "finish30", "Finish (30-day pace)" }, { "deadline", "Deadline" } }
    page.Stats = {}
    for i, def in ipairs(defs) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local stat = UI.Stat(pace, def[2], colW)
        stat:SetPoint("TOPLEFT", 8 + col * (colW + 4), -22 - row * 34)
        page.Stats[def[1]] = stat
    end
    page.Status = Style.Text(pace, 11)
    page.Status:SetPoint("TOPLEFT", 8, -92)
    page.Status:SetPoint("TOPRIGHT", -8, -92)
    page.Status:SetJustifyH("LEFT")
    page.Status:SetJustifyV("TOP")
    page.Status:SetHeight(40)
end

local function RefreshGoal(page)
    local p = ns:Projection()
    local db = ns.db
    local accent = Style.AccentHex()

    local many = #p.tiers > 1
    page.TargetTitle:SetText(accent .. ns.FormatGold(p.target) .. "|r  |cffaaaaaa" .. (p.tier and p.tier.name or ns.TARGET_PRESET_NAMES[db.targetPreset] or "Custom") .. "|r")
    if p.deadline then
        if ns:DeadlinePassed() then
            page.TargetBy:SetText(string.format("by %s  ·  |cffff5555passed|r", ns:DeadlineText()))
        else
            page.TargetBy:SetText(string.format("by %s  ·  %d day%s left", ns:DeadlineText(), p.daysLeft, p.daysLeft == 1 and "" or "s"))
        end
    else
        page.TargetBy:SetText("|cffff9900no deadline set|r")
    end
    -- the bar runs to the paced tier, with a mark at every tier below it;
    -- its colour runs red to green up to the hard goal (the cheapest
    -- tier, the one that goes away), then blue into the accent to the end
    local ticks = {}
    for _, e in ipairs(p.tiers) do
        if e.gold < p.target and p.target > 0 then ticks[#ticks + 1] = e.gold / p.target end
    end
    page.TargetBar:SetTicks(ticks)
    local hardFrac = (p.tiers[1] and p.target > 0) and (p.tiers[1].gold / p.target) or 1
    page.TargetBar:SetColor(UI.GoalColor(p.total / math.max(1, p.target), hardFrac))
    if p.allReached and p.liquidShort <= 0 then
        page.TargetBar:Set(1, 1, accent .. (many and "Every tier reached!" or "Goal reached!") .. "|r  " .. ns.FormatGold(p.total))
    else
        page.TargetBar:Set(p.liquid, p.target, string.format("%s / %s   %d%%", ns.FormatGold(p.total), ns.FormatGold(p.target), ns.Percent(p.total, p.target) or 0), p.crafting)
    end
    for i, row in ipairs(page.TierRows) do
        local e = p.tiers[i]
        row.tier = e
        if e then
            row.Name:SetText((e.paced and accent or (e.reached and ns.GREEN_HEX or "|cffdddddd")) .. e.name .. "|r")
            row.Gold:SetText(ns.FormatGold(e.gold))
            row.Gold:SetAlpha(e.paced and 1 or 0.7)
            row.Verdict:SetText(ns:TierText(e))
            if e.paced then
                local r, g, b = Style.Accent()
                row.Bg:SetColorTexture(r, g, b, 0.12)
            else
                row.Bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    page.Target:SetHeight(TARGET_BASE_H + #p.tiers * TIER_ROW_H + 4)
    page.TargetLine:SetText(string.format("Remaining %s  ·  earned since goal start %s", ns.FormatGold(p.remaining), ns.FormatSigned(p.saved)))
    if ns:HasCraftingData() then
        local tilde = p.craftingEstimated and "~" or ""
        if ns:CountsCrafting() then
            page.TargetLine2:SetText(string.format("Gold %s  +  crafting stock %s%s at cost%s", ns.FormatGold(p.liquid), tilde, ns.FormatGold(p.crafting),
                p.craftingProjected > 0 and ("  ·  ~" .. ns.FormatGold(p.craftingProjected) .. " if it sells") or ""))
        else
            page.TargetLine2:SetText(string.format("Crafting stock %s%s at cost is not counted (Settings)", tilde, ns.FormatGold(ns:CraftingAtCostAll())))
        end
    else
        page.TargetLine2:SetText("")
    end

    local quotaTicks, quotaHard = ns:QuotaTicks(p)
    local function Period(sec, earned, quota, resetSecs, line)
        sec.Reset:SetText("resets in " .. ns.Countdown(resetSecs))
        if quota and quota > 0 then
            sec.Bar:Set(earned, quota, string.format("%s / %s   %d%%", ns.FormatSigned(earned), ns.FormatGold(quota), math.max(0, ns.Percent(earned, quota) or 0)))
            sec.Bar:SetTicks(quotaTicks)
            sec.Bar:SetColor(UI.GoalColor(earned / quota, quotaHard))
        else
            sec.Bar:Set(0, 1, ns.FormatSigned(earned) .. "  |cff888888set a deadline for a quota|r")
            sec.Bar:SetTicks({})
            sec.Bar:SetColor(Style.Accent())
        end
        sec.Line:SetText(line)
    end
    Period(page.Today, p.today, p.quota, ns:SecondsUntilDailyReset(),
        p.quota and string.format("Quota %s/day%s", ns.FormatGold(p.quota),
            p.tomorrow and ("  ·  tomorrow " .. ns.FormatGold(p.tomorrow) .. "/day at this pace") or (p.daysLeft == 1 and "  ·  last day" or ""))
        or "The quota is what is left, spread over the days to the deadline.")
    local wk = db.weeks[ns:WeekID()]
    Period(page.Week, p.week, p.weekQuota, ns:SecondsUntilWeeklyReset(),
        p.weekQuota and string.format("Weekly quota %s  ·  %d day%s of this week count", ns.FormatGold(p.weekQuota), wk and wk.days or 7, (wk and wk.days == 1) and "" or "s")
        or "Weekly pacing needs a deadline too.")

    local S = page.Stats
    S.avg7.Value:SetText(ns.FormatGold(p.avg7) .. "|cff888888/day|r")
    S.avg30.Value:SetText(ns.FormatGold(p.avg30) .. "|cff888888/day|r")
    S.avgGoal.Value:SetText(ns.FormatGold(p.avgGoal) .. "|cff888888/day|r")
    S.finish7.Value:SetText(p.finish7 and ns.DateText(p.finish7, true) or "|cff888888-|r")
    S.finish30.Value:SetText(p.finish30 and ns.DateText(p.finish30, true) or "|cff888888-|r")
    S.deadline.Value:SetText(p.deadline and ns:DeadlineText(true) or "|cff888888none|r")
    page.Status:SetText(ns:StatusText(p))
end

-------------------------------------------------------------------------------
-- Characters
-------------------------------------------------------------------------------
UI.charSort = "gold"

local function CharTooltip(row)
    local c = row.char
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.crafting then
        ns:CraftingTooltip(GameTooltip, row.crafting)
    elseif row.warband then
        GameTooltip:AddLine("Warband Bank")
        local w = ns.db.warband
        GameTooltip:AddLine(w.money and ("Read " .. (w.source == "live" and "from the game" or "from Syndicator") .. (w.updated and (", " .. date("%b %d %H:%M", w.updated)) or "")) or "Not read yet: visit a bank once.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Always counted: gold moved here from a character is not income.", 0.8, 0.8, 0.8, true)
    elseif c then
        GameTooltip:AddLine(UI.ClassHex(c.class) .. (c.name or c.key) .. "|r" .. (c.realm and ("  |cffaaaaaa" .. c.realm .. "|r") or ""))
        GameTooltip:AddLine(ns.FormatGold(c.money), 1, 1, 1)
        if c.source == "live" then
            GameTooltip:AddLine("Seen live" .. (c.lastSeen and (", last " .. date("%b %d %H:%M", c.lastSeen)) or ""), 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("From Syndicator: log this character in for a live figure.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(c.include == false and "Excluded from the total." or "Counted in the total. Untick to leave it out.", 0.8, 0.8, 0.8, true)
        if c.key ~= ns:CharKey() then GameTooltip:AddLine("|cff888888Right-click to forget this character.|r", 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function BuildChars(page)
    page.ColHead = UI.ColumnHeader(page, {
        { "name", "Character", nil, "Sort by name." },
        { "gold", "Gold", UI.COL_GOLD, "Sort by gold, richest first." },
        { "seen", "Seen", UI.COL_SEEN, "Sort by when the character was last seen." },
    }, function(id) UI.charSort = id end, 0)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 20)
    page.Footer = UI.Line(page, 10, "LEFT", 1, 1, 1, 0.53)
    page.Footer:SetPoint("BOTTOMLEFT", 2, 3)
    page.Footer:SetPoint("BOTTOMRIGHT", -2, 3)
end

local function SortChars(list)
    local mode = UI.charSort
    table.sort(list, function(a, b)
        if mode == "name" then
            return (a.name or a.key):lower() < (b.name or b.key):lower()
        elseif mode == "seen" then
            if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        end
        if (a.money or 0) ~= (b.money or 0) then return (a.money or 0) > (b.money or 0) end
        return a.key < b.key
    end)
    return list
end

local function CharRowFactory(content)
    return function()
        return UI.NewCharRow(content, function(row, on)
            if row.warband then row.Check:SetChecked(true); return end
            if row.crafting then ns:SetCountCrafting(on); return end
            if row.char then ns:SetCharacterIncluded(row.char.key, on) end
        end, function(row)
            if row.crafting then
                ns:ForgetCraftingRealm(row.crafting)
                GameTooltip:Hide()
            elseif row.char and row.char.key ~= ns:CharKey() then
                ns:ForgetCharacter(row.char.key)
                GameTooltip:Hide()
            end
        end, CharTooltip)
    end
end

local function RefreshChars(page)
    if page.ColHead.selectedTabID ~= UI.charSort then Style.SelectTab(page.ColHead, UI.charSort) end
    local L = UI.Layout(page.Content)
    local factory = CharRowFactory(page.Content)
    local me = ns:CharKey()
    local db = ns.db
    local P = Pools(page)

    local row = L:Add(P.charRows, factory, ROW_H)
    row.warband, row.char, row.crafting = true, nil, nil
    row.Name:SetText("|cffffd100Warband Bank|r")
    row.Name:SetAlpha(db.warband.money and 1 or 0.5)
    row.Gold:SetText(db.warband.money and ns.FormatGold(db.warband.money) or "|cff888888not read|r")
    row.Seen:SetText(db.warband.updated and date("%b %d", db.warband.updated) or "")
    row.Check:SetChecked(true)
    row.Check:SetAlpha(0.4)
    UI.RowBackground(row, 1, false)

    -- crafting stock, one row per realm CraftSimPL has reported
    local counted = ns:CountsCrafting()
    for _, key in ipairs(ns:CraftingRealms()) do
        local e = db.crafting[key]
        row = L:Add(P.charRows, factory, ROW_H)
        row.warband, row.char, row.crafting = nil, nil, key
        row.Name:SetText("|cffffd100Crafting stock|r  |cff888888" .. key .. "|r")
        row.Name:SetAlpha(counted and 1 or 0.45)
        row.Gold:SetText((e.estimated and "~" or "") .. ns.FormatGold(ns.CraftingEntryAtCost(e)))
        row.Gold:SetAlpha(counted and 1 or 0.45)
        row.Seen:SetText(e.updated and date("%b %d", e.updated) or "")
        row.Check:SetChecked(counted)
        row.Check:SetAlpha(1)
        UI.RowBackground(row, L:Count(P.charRows), false)
    end

    local fromSyndicator = 0
    local offset = L:Count(P.charRows)
    for i, c in ipairs(SortChars(ns:SortedCharacters())) do
        row = L:Add(P.charRows, factory, ROW_H)
        row.warband, row.char, row.crafting = nil, c, nil
        local included = c.include ~= false
        row.Name:SetText(UI.ClassHex(c.class) .. (c.name or c.key) .. "|r" .. (c.realm and ("  |cff888888" .. c.realm .. "|r") or ""))
        row.Name:SetAlpha(included and 1 or 0.45)
        row.Gold:SetText(ns.FormatGold(c.money))
        row.Gold:SetAlpha(included and 1 or 0.45)
        row.Seen:SetText(c.source == "live" and (c.lastSeen and date("%b %d", c.lastSeen) or "") or "|cff888888Syndicator|r")
        row.Check:SetChecked(included)
        row.Check:SetAlpha(1)
        UI.RowBackground(row, i + offset, c.key == me)
        if c.source ~= "live" then fromSyndicator = fromSyndicator + 1 end
    end
    L:Finish(P.charRows)
    local n = ns:CountCharacters()
    page.Footer:SetText(string.format("Counted: %s across %d character%s%s%s%s", ns.FormatGold(ns:TotalWealth()), n, n == 1 and "" or "s",
        db.warband.money and ", the warband bank" or "", (counted and ns:HasCraftingData()) and " and crafting stock at cost" or "",
        fromSyndicator > 0 and string.format("  ·  %d from Syndicator", fromSyndicator) or ""))
end

-------------------------------------------------------------------------------
-- History
-------------------------------------------------------------------------------
UI.historyMode = "days"

local function BuildHistory(page)
    local strip = UI.Strip(page, "Show")
    strip.Tabs = UI.TabStrip(strip, {
        { "days", "Days", "The last 30 days, today at the top." },
        { "weeks", "Weeks", "The last 12 weeks, this week at the top." },
    }, 60, function(id) UI.historyMode = id; ns:RefreshWindow() end)
    strip.Tabs:SetPoint("LEFT", strip.Label, "RIGHT", 8, 0)
    page.Strip = strip
    page.ColHead = UI.ColumnHeader(page, {
        { "date", "Date" },
        { "earned", "Earned", UI.COL_EARNED },
        { "quota", "Quota", UI.COL_QUOTA },
        { "met", "", UI.COL_MARK, "Quota met." },
    }, nil, 24)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 20)
    page.Footer = UI.Line(page, 10, "LEFT", 1, 1, 1, 0.53)
    page.Footer:SetPoint("BOTTOMLEFT", 2, 3)
    page.Footer:SetPoint("BOTTOMRIGHT", -2, 3)
end

local function RefreshHistory(page)
    if page.Strip.Tabs.selectedTabID ~= UI.historyMode then Style.SelectTab(page.Strip.Tabs, UI.historyMode) end
    local weeks = UI.historyMode == "weeks"
    local list = weeks and ns:RecentWeeks(12) or ns:RecentDays(30)
    local startDay = ns.db.goalStartDay or ns:DayID()
    local L = UI.Layout(page.Content)
    local P = Pools(page)
    local function Factory() return UI.NewDayRow(page.Content) end
    local met, counted = 0, 0
    for i = #list, 1, -1 do
        local e = list[i]
        -- nothing before the goal started
        if weeks and e.id + 6 < startDay then break end
        if not weeks and e.id < startDay then break end
        local row = L:Add(P.dayRows, Factory, ROW_H)
        local current = i == #list
        row.Date:SetText((current and (weeks and "This week" or "Today")) or (weeks and ("Wk of " .. ns.DateText(ns:WeekDate(e.id))) or ns.DateText(ns:DayDate(e.id))))
        row.Date:SetAlpha(e.seen and 1 or 0.5)
        row.Earned:SetText(ns.FormatSigned(e.earned))
        row.Quota:SetText(e.quota and ns.FormatGold(e.quota) or "|cff555555-|r")
        row.Mini:Set(e.earned, e.quota)
        local hit = e.quota and e.earned >= e.quota
        row.Mark:SetShown(hit and true or false)
        if e.quota and not current then
            counted = counted + 1
            if hit then met = met + 1 end
        end
        UI.RowBackground(row, L:Count(P.dayRows), current)
    end
    L:Finish(P.dayRows)
    if counted > 0 then
        page.Footer:SetText(string.format("Quota met on %d of %d completed %s.", met, counted, weeks and (counted == 1 and "week" or "weeks") or (counted == 1 and "day" or "days")))
    else
        page.Footer:SetText("No completed " .. (weeks and "week" or "day") .. " yet.")
    end
end

-------------------------------------------------------------------------------
UI.Tabs = {
    { key = "goal", label = "Goal", Build = BuildGoal, Refresh = RefreshGoal },
    { key = "chars", label = "Characters", Build = BuildChars, Refresh = RefreshChars },
    { key = "history", label = "History", Build = BuildHistory, Refresh = RefreshHistory },
}

-- GoldGoal: the goal editor, one frame the window's Settings page and the
-- EllesmereUI page both embed. Goals are rows with a name and an amount
-- (cheapest first, the cheapest is the one that must be met), with add,
-- remove and preset buttons; one picker says which goal the daily quota
-- aims at; the deadline is a choice with a box that appears only for a
-- typed date or day count.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local ROW_H, GAP = 28, 6
local NAME_W, AMOUNT_W = 170, 120
local X = 12

-- The most the editor can take (four goals, a typed deadline), for a host
-- that lays out once.
UI.GOAL_EDITOR_MAX_H = 16 + 4 * ROW_H + GAP + (22 + GAP + 4) + (22 + 2) + (14 + GAP + 4) + 16 + (20 + GAP) + (22 + GAP) + (16 + GAP)

local function Commas(copper)
    return ns.Commas(ns.Gold(copper))
end

function UI.GoalEditor(parent, width)
    local ed = CreateFrame("Frame", nil, parent)
    ed:SetWidth(width or 372)
    ed.rows = {}

    -- column labels
    ed.NameHead = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
    ed.NameHead:SetPoint("TOPLEFT", X, -2)
    ed.NameHead:SetText("Goal")
    ed.AmountHead = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
    ed.AmountHead:SetPoint("TOPLEFT", X + NAME_W + 8, -2)
    ed.AmountHead:SetText("Gold")

    local function Relayout()
        if ed.onLayout then ed.onLayout() end
    end

    -- Reads the rows back into the saved goals; a bad amount is reported
    -- and the rows are refilled from what is saved.
    local function Commit()
        local list = {}
        for _, row in ipairs(ed.rows) do
            if row:IsShown() then
                local gold = ns.ParseGold(row.Amount:GetText() or "")
                if not gold then
                    ns:Print("Could not read \"" .. tostring(row.Amount:GetText()) .. "\" as gold. Try 5000000, 5,000,000 or 5m.")
                    ed:Refresh()
                    return false
                end
                local name = strtrim(row.Name:GetText() or "")
                if name == "" then name = "Goal " .. (#list + 1) end
                list[#list + 1] = { name = name, gold = gold }
            end
        end
        if #list == 0 then ed:Refresh(); return false end
        ns:SetTiers(list, "custom")
        ed:Refresh()
        Relayout()
        return true
    end
    ed.Commit = Commit

    for i = 1, ns.MAX_TIERS do
        local row = CreateFrame("Frame", nil, ed)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(16 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", 0, -(16 + (i - 1) * ROW_H))
        row.Name = UI.EditBox(row, 22)
        row.Name:SetPoint("LEFT", X, 0)
        row.Name:SetWidth(NAME_W)
        row.Amount = UI.EditBox(row, 22)
        row.Amount:SetPoint("LEFT", row.Name, "RIGHT", 8, 0)
        row.Amount:SetWidth(AMOUNT_W)
        row.Remove = UI.TextButton(row, "-", 22, 22, 13)
        row.Remove:SetPoint("LEFT", row.Amount, "RIGHT", 6, 0)
        row.Mark = UI.Line(row, 10, "LEFT", 1, 1, 1, 0.53)
        row.Mark:SetPoint("LEFT", row.Remove, "RIGHT", 8, 0)
        row.Mark:SetPoint("RIGHT", -4, 0)
        for _, box in ipairs({ row.Name, row.Amount }) do
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit() end)
            box:SetScript("OnEditFocusLost", function() if not ed.refreshing then Commit() end end)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ed:Refresh() end)
        end
        row.Remove:SetScript("OnClick", function()
            if #ns.db.tiers <= 1 then ns:Print("Keep at least one goal."); return end
            local list = {}
            for j, t in ipairs(ns.db.tiers) do
                if j ~= i then list[#list + 1] = { name = t.name, gold = t.gold } end
            end
            ns:SetTiers(list, "custom")
            ed:Refresh()
            Relayout()
        end)
        UI.Tip(row.Remove, "ANCHOR_RIGHT", "Remove this goal", "The quota moves to the next goal if this was the one it aimed at.")
        ed.rows[i] = row
    end

    -- add, and the presets
    ed.Add = UI.TextButton(ed, "+ Add a goal", 100, 22)
    ed.Add:SetScript("OnClick", function()
        local tiers = ns.db.tiers
        if #tiers >= ns.MAX_TIERS then return end
        local list = {}
        for _, t in ipairs(tiers) do list[#list + 1] = { name = t.name, gold = t.gold } end
        local top = tiers[#tiers] and tiers[#tiers].gold or 0
        list[#list + 1] = { name = "Goal " .. (#list + 1), gold = top + 1000000 * ns.COPPER }
        ns:SetTiers(list, "custom")
        ed:Refresh()
        Relayout()
        local row = ed.rows[#list]
        if row and row.Name.SetFocus then
            row.Name:SetFocus()
            if row.Name.HighlightText then row.Name:HighlightText() end
        end
    end)
    UI.Tip(ed.Add, "ANCHOR_RIGHT", "Add a goal", "Up to " .. ns.MAX_TIERS .. ". Goals sort themselves cheapest first.")
    ed.PresetLabel = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
    ed.PresetLabel:SetPoint("LEFT", ed.Add, "RIGHT", 14, 0)
    ed.PresetLabel:SetText("Presets")
    ed.PresetTabs = UI.TabStrip(ed, {
        { "mount", "Mount", "One goal: the mount, 5,000,000g." },
        { "set", "+ Vendors", "Two goals: the mount at 5,000,000g, then the mount with every vendor at 7,000,000g." },
        { "ladder", "Ladder", "Three goals: mount 5,000,000g, mount + vendors 7,000,000g, and a 10,000,000g buffer so there is gold left after buying." },
    }, 70, function(preset)
        ns:SetTargetPreset(preset)
        ed:Refresh()
        Relayout()
    end)
    ed.PresetTabs:SetPoint("LEFT", ed.PresetLabel, "RIGHT", 8, 0)

    -- which goal the quota aims at
    ed.PaceLabel = UI.Line(ed, 11, "LEFT", 1, 1, 1, 0.85)
    ed.PaceLabel:SetText("The daily quota aims at")
    ed.PaceDrop = UI.Dropdown(ed, 180, 22, function()
        local entries = {}
        local total = ns:TotalWealth()
        for i, t in ipairs(ns.db.tiers) do
            local reached = total >= t.gold
            entries[#entries + 1] = { text = t.name .. "  |cff888888" .. ns.FormatGoldShort(t.gold) .. (reached and "  banked" or "") .. "|r",
                checked = i == (ns.db.tierIndex or 1),
                onClick = function() ns:SetTierIndex(i); ed:Refresh() end,
                tip = reached and { t.name, "Already banked: the quota moves past it by itself." } or nil }
        end
        return entries
    end)
    ed.PaceDrop:SetPoint("LEFT", ed.PaceLabel, "RIGHT", 10, 0)
    ed.PaceNote = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
    ed.PaceNote:SetText("It moves up to the next goal by itself once one is banked.")

    -- the deadline
    ed.DeadlineLabel = UI.Line(ed, 11, "LEFT", 1, 1, 1, 0.85)
    ed.DeadlineLabel:SetText("Deadline")
    ed.DeadlineTabs = UI.TabStrip(ed, {
        { "expansion", "End of Midnight", "When the mount goes away: The Last Titan pre-patch. A guess (" .. ns.EXPANSION_END_GUESS .. ") until Blizzard announces it." },
        { "season", "End of Season 2", "When patch 12.2 lands. A guess (" .. ns.SEASON_END_GUESS .. ") until it is announced." },
        { "date", "A date", "A date you type, YYYY-MM-DD." },
        { "days", "Days from now", "A number of days, today included." },
    }, 86, function(preset)
        if ns.DEADLINE_GUESSES[preset] then
            ns:SetDeadlineGuess(preset)
        else
            ns.db.deadlinePreset = preset
            ns:Fire("SETTINGS_CHANGED")
        end
        ed:Refresh()
        Relayout()
        if ed.DeadlineBox:IsShown() and ed.DeadlineBox.SetFocus then ed.DeadlineBox:SetFocus() end
    end)
    ed.DeadlineBoxLabel = UI.Line(ed, 11, "LEFT", 1, 1, 1, 0.85)
    ed.DeadlineBox = UI.EditBox(ed, 22)
    ed.DeadlineBox:SetWidth(120)
    ed.DeadlineBox:SetPoint("LEFT", ed.DeadlineBoxLabel, "RIGHT", 10, 0)
    ed.DeadlineSet = UI.TextButton(ed, "Set", 50, 22)
    ed.DeadlineSet:SetPoint("LEFT", ed.DeadlineBox, "RIGHT", 6, 0)
    local function SetDeadline()
        local text = strtrim(ed.DeadlineBox:GetText() or "")
        ed.DeadlineBox:ClearFocus()
        local ok
        if ns.db.deadlinePreset == "days" then
            ok = ns:SetDeadlineDays(tonumber((text:match("^(%d+)"))))
            if not ok then ns:Print("Type a number of days.") end
        else
            ok = ns:SetDeadlineDate(text)
            if not ok then ns:Print("Type a date as YYYY-MM-DD.") end
        end
        ed:Refresh()
        return ok
    end
    ed.SetDeadline = SetDeadline
    ed.DeadlineSet:SetScript("OnClick", SetDeadline)
    ed.DeadlineBox:SetScript("OnEnterPressed", SetDeadline)
    ed.DeadlineBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ed:Refresh() end)
    ed.DeadlineInfo = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.6)

    -- Fills everything from the saved goal and lays the parts out; returns
    -- the height used.
    function ed:Refresh()
        if not ns.db then return 0 end
        self.refreshing = true
        local db = ns.db
        local tiers = db.tiers
        local total = ns:TotalWealth()
        for i, row in ipairs(self.rows) do
            local t = tiers[i]
            if t then
                if not (row.Name.HasFocus and row.Name:HasFocus()) then row.Name:SetText(t.name) end
                if not (row.Amount.HasFocus and row.Amount:HasFocus()) then row.Amount:SetText(Commas(t.gold)) end
                local parts = {}
                if total >= t.gold then parts[#parts + 1] = ns.GREEN_HEX .. "banked|r" end
                if i == (db.tierIndex or 1) then parts[#parts + 1] = Style.AccentHex() .. "quota aims here|r" end
                if i == 1 and total < t.gold and #tiers > 1 then parts[#parts + 1] = "|cff888888must be met|r" end
                row.Mark:SetText(table.concat(parts, "  "))
                row:Show()
            else
                row:Hide()
            end
        end
        local n = #tiers
        local y = 16 + n * ROW_H + GAP
        self.Add:ClearAllPoints()
        self.Add:SetPoint("TOPLEFT", X, -y)
        self.Add:SetEnabled(n < ns.MAX_TIERS)
        local presetID = db.targetPreset
        if presetID == "custom" then presetID = nil end
        if self.PresetTabs.selectedTabID ~= presetID then Style.SelectTab(self.PresetTabs, presetID) end
        y = y + 22 + GAP + 4
        self.PaceLabel:ClearAllPoints()
        self.PaceLabel:SetPoint("TOPLEFT", X, -y - 5)
        local paced = ns:PacedTier()
        self.PaceDrop.Text:SetText(paced and (paced.name .. "  |cff888888" .. ns.FormatGoldShort(paced.gold) .. "|r") or "")
        y = y + 22 + 2
        self.PaceNote:ClearAllPoints()
        self.PaceNote:SetPoint("TOPLEFT", X, -y)
        self.PaceNote:SetPoint("TOPRIGHT", -4, -y)
        y = y + 14 + GAP + 4
        self.DeadlineLabel:ClearAllPoints()
        self.DeadlineLabel:SetPoint("TOPLEFT", X, -y)
        y = y + 16
        self.DeadlineTabs:ClearAllPoints()
        self.DeadlineTabs:SetPoint("TOPLEFT", X, -y)
        local preset = db.deadlinePreset or "expansion"
        if self.DeadlineTabs.selectedTabID ~= preset then Style.SelectTab(self.DeadlineTabs, preset) end
        y = y + 20 + GAP
        local typed = preset == "date" or preset == "days"
        self.DeadlineBoxLabel:SetShown(typed)
        self.DeadlineBox:SetShown(typed)
        self.DeadlineSet:SetShown(typed)
        if typed then
            self.DeadlineBoxLabel:ClearAllPoints()
            self.DeadlineBoxLabel:SetPoint("TOPLEFT", X, -y - 5)
            self.DeadlineBoxLabel:SetText(preset == "days" and "Days left" or "Date")
            if not (self.DeadlineBox.HasFocus and self.DeadlineBox:HasFocus()) then
                if preset == "days" then
                    self.DeadlineBox:SetText(db.deadline and tostring(ns:DaysLeft()) or "")
                else
                    self.DeadlineBox:SetText(db.deadline and date("%Y-%m-%d", db.deadline - 43200) or "")
                end
            end
            y = y + 22 + GAP
        end
        self.DeadlineInfo:ClearAllPoints()
        self.DeadlineInfo:SetPoint("TOPLEFT", X, -y)
        self.DeadlineInfo:SetPoint("TOPRIGHT", -4, -y)
        if db.deadline then
            local left = ns:DaysLeft()
            local note = preset == "expansion" and "  ·  our guess at when the mount goes away"
                or preset == "season" and "  ·  our guess at when Season 2 ends" or ""
            self.DeadlineInfo:SetText(string.format("%s  ·  %d day%s left%s%s", ns:DeadlineText(true), left, left == 1 and "" or "s",
                ns:DeadlinePassed() and "  (passed)" or "", note))
        else
            self.DeadlineInfo:SetText("No deadline yet: the quotas need one.")
        end
        y = y + 16 + GAP
        self:SetHeight(y)
        self.refreshing = nil
        return y
    end

    return ed
end

-------------------------------------------------------------------------------
-- The splash level editor: a row per level, two lines each. Line one is
-- the gold it starts at and what it says; line two its text size, hold
-- time, sound, colour, glow and frame. Levels can be added and removed,
-- up to SPLASH_MAX_LEVELS. Same shape as the goal editor.
-------------------------------------------------------------------------------
local LROW_H = 54
local C1 = X + 30                      -- the first control column
local FROM_W, SAYS_W = 84, 118
local SAYS_X = C1 + FROM_W + 8
local REM_X = SAYS_X + SAYS_W + 6
local SIZE_X, HOLD_X, SOUND_X, COL_X, GLOW_X, FRAME_X = C1, C1 + 44, C1 + 88, C1 + 168, C1 + 240, C1 + 262
local SOUND_W, COL_W, FRAME_W = 76, 66, 66

UI.SPLASH_EDITOR_MAX_H = 30 + 10 * LROW_H + GAP + 22 + GAP + 14 + GAP

function UI.SplashLevelEditor(parent, width)
    local ed = CreateFrame("Frame", nil, parent)
    ed:SetWidth(width or 372)
    ed.rows = {}
    local function Head(text, x, y)
        local fs = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end
    Head("Level", X, -2)
    Head("From (gold)", C1, -2)
    Head("Says", SAYS_X, -2)
    Head("Size", SIZE_X, -16)
    Head("Hold", HOLD_X, -16)
    Head("Sound", SOUND_X, -16)
    Head("Colour", COL_X, -16)
    Head("Glow", GLOW_X - 2, -16)
    Head("Frame", FRAME_X, -16)

    local function Relayout()
        if ed.onLayout then ed.onLayout() end
    end

    -- Reads the rows back; a bad number is reported and the rows refilled.
    local function Commit()
        local list = {}
        for _, row in ipairs(ed.rows) do
            if row:IsShown() then
                local gold = ns.ParseGold(row.From:GetText() or "")
                if not gold then
                    ns:Print("Could not read \"" .. tostring(row.From:GetText()) .. "\" as gold. Try 500, 5,000 or 25k.")
                    ed:Refresh()
                    return false
                end
                local size, hold = tonumber(row.Size:GetText()), tonumber(row.Hold:GetText())
                if not size or not hold then
                    ns:Print("Size is a number of points (12 to 80), hold a number of seconds (0.3 to 10).")
                    ed:Refresh()
                    return false
                end
                list[#list + 1] = { gold = gold, flavor = strtrim(row.Say:GetText() or ""), size = size, hold = hold,
                    sound = row.sound, color = row.color, glow = row.Glow:GetChecked() and true or false, frame = row.frame }
            end
        end
        if #list == 0 then ed:Refresh(); return false end
        ns:SetSplashLevels(list)
        ed:Refresh()
        Relayout()
        return true
    end
    ed.Commit = Commit

    for i = 1, ns.SPLASH_MAX_LEVELS do
        local row = CreateFrame("Frame", nil, ed)
        row:SetHeight(LROW_H)
        row:SetPoint("TOPLEFT", 0, -(30 + (i - 1) * LROW_H))
        row:SetPoint("TOPRIGHT", 0, -(30 + (i - 1) * LROW_H))
        row.index = i
        row.Label = UI.Line(row, 11, "LEFT", 1, 1, 1, 0.85)
        row.Label:SetPoint("TOPLEFT", X, -7)
        row.Label:SetWidth(26)
        row.Label:SetText(tostring(i))
        local function Box(x, w, y)
            local b = UI.EditBox(row, 22)
            b:SetPoint("TOPLEFT", x, y)
            b:SetWidth(w)
            b:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit() end)
            b:SetScript("OnEditFocusLost", function() if not ed.refreshing then Commit() end end)
            b:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ed:Refresh() end)
            return b
        end
        row.From = Box(C1, FROM_W, -3)
        row.Say = Box(SAYS_X, SAYS_W, -3)
        row.Remove = UI.TextButton(row, "-", 22, 22, 13)
        row.Remove:SetPoint("TOPLEFT", REM_X, -3)
        row.Remove:SetScript("OnClick", function()
            if ns:RemoveSplashLevel(i) then ed:Refresh(); Relayout() else ns:Print("Keep at least one level.") end
        end)
        UI.Tip(row.Remove, "ANCHOR_RIGHT", "Remove this level", "The levels above it move down.")
        row.Preview = UI.TextButton(row, "Preview", 62, 22)
        row.Preview:SetPoint("TOPLEFT", REM_X + 28, -3)
        row.Preview:SetScript("OnClick", function() ns:PreviewSplash(i) end)
        UI.Tip(row.Preview, "ANCHOR_RIGHT", "Preview", "Shows a sample at this level as it is set now.")
        row.Size = Box(SIZE_X, 36, -29)
        UI.Tip(row.Size, "ANCHOR_TOP", "Text size", "Points, 12 to 80.")
        row.Hold = Box(HOLD_X, 36, -29)
        UI.Tip(row.Hold, "ANCHOR_TOP", "Hold", "Seconds it stays before drifting off, 0.3 to 10.")
        row.Sound = UI.Dropdown(row, SOUND_W, 22, function()
            local entries = {}
            for _, key in ipairs(ns.SPLASH_SOUND_ORDER) do
                entries[#entries + 1] = { text = ns.SPLASH_SOUNDS[key], checked = row.sound == key,
                    onClick = function() row.sound = key; Commit() end }
            end
            return entries
        end)
        row.Sound:SetPoint("TOPLEFT", SOUND_X, -29)
        row.Color = UI.Dropdown(row, COL_W, 22, function()
            local entries = {}
            for _, key in ipairs(ns.SPLASH_COLOR_ORDER) do
                entries[#entries + 1] = { text = ns.HexColor(ns:SplashColor(key)) .. ns.SPLASH_COLOR_NAMES[key] .. "|r", checked = row.color == key,
                    onClick = function() row.color = key; Commit() end }
            end
            return entries
        end)
        row.Color:SetPoint("TOPLEFT", COL_X, -29)
        row.Glow = UI.Check(row, 22)
        row.Glow:SetPoint("TOPLEFT", GLOW_X - 2, -29)
        row.Glow:SetScript("OnClick", function() Commit() end)
        UI.Tip(row.Glow, "ANCHOR_TOP", "Glow", "A soft golden glow behind the amount at this level.")
        row.Frame = UI.Dropdown(row, FRAME_W, 22, function()
            local entries = {}
            for _, key in ipairs(ns.SPLASH_FRAME_ORDER) do
                entries[#entries + 1] = { text = ns.SPLASH_FRAMES[key], checked = row.frame == key,
                    onClick = function() row.frame = key; Commit() end,
                    tip = key == "subtle" and { "Ripple", "A thin, slow, quiet flow of gold along the edges." }
                        or key == "gold" and { "Liquid gold", "Gold flowing clockwise along the edges while the splash is up." }
                        or key == "liquid" and { "Torrent", "Wide, bright and fast, with a second finer current running the other way." }
                        or nil }
            end
            return entries
        end)
        row.Frame:SetPoint("TOPLEFT", FRAME_X, -29)
        ed.rows[i] = row
    end

    ed.Add = UI.TextButton(ed, "+ Add a level", 100, 22)
    ed.Add:SetScript("OnClick", function()
        if ns:AddSplashLevel() then ed:Refresh(); Relayout() end
    end)
    UI.Tip(ed.Add, "ANCHOR_RIGHT", "Add a level", "A new top level at twice the gold of the last, in its style but a step bigger. Up to " .. ns.SPLASH_MAX_LEVELS .. ".")
    ed.Reset = UI.TextButton(ed, "Shipped levels", 100, 22)
    ed.Reset:SetPoint("LEFT", ed.Add, "RIGHT", 8, 0)
    ed.Reset:SetScript("OnClick", function()
        ns:SetSplashLevels(ns.DeepCopy(ns.SPLASH_LEVEL_DEFAULTS))
        ed:Refresh()
        Relayout()
    end)
    UI.Tip(ed.Reset, "ANCHOR_RIGHT", "Shipped levels", "The seven that come with the addon: 500g, 1,000g, 5,000g, 10,000g, 25,000g, 50,000g and 100,000g.")
    ed.Note = UI.Line(ed, 10, "LEFT", 1, 1, 1, 0.53)
    ed.Note:SetText("Gains under level 1 show nothing. Levels sort themselves by gold; the glow and the frame grow with the text size.")

    function ed:Refresh()
        if not ns.db then return 0 end
        self.refreshing = true
        local levels = ns:SplashLevels()
        for i, row in ipairs(self.rows) do
            local l = levels[i]
            if l then
                if not (row.From.HasFocus and row.From:HasFocus()) then row.From:SetText(ns.Commas(ns.Gold(l.gold))) end
                if not (row.Say.HasFocus and row.Say:HasFocus()) then row.Say:SetText(l.flavor or "") end
                if not (row.Size.HasFocus and row.Size:HasFocus()) then row.Size:SetText(tostring(l.size)) end
                if not (row.Hold.HasFocus and row.Hold:HasFocus()) then row.Hold:SetText(string.format("%.1f", l.hold)) end
                row.sound, row.color, row.frame = l.sound, l.color, l.frame
                row.Sound.Text:SetText(ns.SPLASH_SOUNDS[l.sound] or "None")
                row.Color.Text:SetText(ns.HexColor(ns:SplashColor(l.color)) .. (ns.SPLASH_COLOR_NAMES[l.color] or "White") .. "|r")
                row.Glow:SetChecked(l.glow and true or false)
                row.Frame.Text:SetText(ns.SPLASH_FRAMES[l.frame] or "None")
                row:Show()
            else
                row:Hide()
            end
        end
        local n = #levels
        local y = 30 + n * LROW_H + GAP
        self.Add:ClearAllPoints()
        self.Add:SetPoint("TOPLEFT", X, -y)
        self.Add:SetEnabled(n < ns.SPLASH_MAX_LEVELS)
        y = y + 22 + GAP
        self.Note:ClearAllPoints()
        self.Note:SetPoint("TOPLEFT", X, -y)
        self.Note:SetPoint("TOPRIGHT", -4, -y)
        y = y + 14 + GAP
        self:SetHeight(y)
        self.refreshing = nil
        return y
    end
    return ed
end

-- GoldGoal: the Settings page, and the entry in the game's Settings > AddOns list.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local panel
local ROW_H = 24

function ns:BuildSettingsPage(page)
    panel = page
    local scroll, _, c = Style.ScrollFrame(page, 300)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    panel.controls = {}

    local y = -2
    local rowIndex = 0
    -- Rows hang off each other, so an editor that grows pushes what is
    -- under it down. `y` still counts the height for the content frame.
    local prev
    local function Place(frame, height)
        frame:SetHeight(height)
        if prev then
            frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
            frame:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
        else
            frame:SetPoint("TOPLEFT", 0, -2)
            frame:SetPoint("TOPRIGHT", 0, -2)
        end
        prev = frame
        y = y - height
        return frame
    end
    local function Row(height)
        rowIndex = rowIndex + 1
        local row = CreateFrame("Frame", nil, c)
        Place(row, height or ROW_H)
        if rowIndex % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end
        return row
    end
    local function Header(text)
        local f = CreateFrame("Frame", nil, c)
        Place(f, 26)
        local fs = Style.Text(f, 11, 1, 1, 1, 0.41)
        fs:SetPoint("BOTTOMLEFT", 8, 4)
        fs:SetText(string.upper(text))
        rowIndex = 0
    end
    -- An editor row sized to its editor, resized whenever the editor changes shape.
    local fits = {}
    local function FitEditor(row, ed)
        local function Fit()
            local old = row:GetHeight() or 0
            local h = ed:Refresh() or old
            row:SetHeight(h)
            c:SetHeight((c:GetHeight() or 0) + (h - old))
        end
        ed.onLayout = Fit
        fits[#fits + 1] = Fit
    end
    local function RowLabel(row, text)
        local fs = Style.Text(row, 11, 1, 1, 1, 0.85)
        fs:SetPoint("LEFT", 8, 0)
        fs:SetText(text)
        return fs
    end
    local function AddCheck(label, tooltip, get, set)
        local row = Row()
        local cb = UI.Check(row, 22)
        cb:SetPoint("LEFT", 4, 0)
        cb.Label = UI.Line(row, 11, "LEFT", 1, 1, 1, 0.85)
        cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.Label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        cb.Label:SetText(label)
        cb.get, cb.set = get, set
        cb:SetScript("OnClick", function(self)
            self.set(self:GetChecked() and true or false)
            ns:RefreshSettings()
        end)
        if tooltip then UI.Tip(cb, "ANCHOR_RIGHT", label, tooltip) end
        table.insert(panel.controls, cb)
        return cb
    end
    local function Hint(text, height)
        local f = CreateFrame("Frame", nil, c)
        Place(f, (height or 26) + 4)
        local fs = Style.Text(f, 10, 1, 1, 1, 0.53)
        fs:SetPoint("TOPLEFT", 8, 0)
        fs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetHeight(height or 26)
        fs:SetText(text)
        return fs
    end
    local function Switch(row, defs, w, onSelect)
        local tabs = UI.TabStrip(row, defs, w, onSelect)
        tabs:SetPoint("RIGHT", -6, 0)
        return tabs
    end
    local function Stepper(row, onStep)
        local plus = UI.TextButton(row, "+", 22, 20, 13)
        plus:SetPoint("RIGHT", -6, 0)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(50, 20)
        box:SetPoint("RIGHT", plus, "LEFT", -1, 0)
        Style.Panel(box, { inset = true })
        local text = Style.Text(box, 11)
        text:SetPoint("CENTER", 0, 0)
        local minus = UI.TextButton(row, "-", 22, 20, 13)
        minus:SetPoint("RIGHT", box, "LEFT", -1, 0)
        plus:SetScript("OnClick", function() onStep(1) end)
        minus:SetScript("OnClick", function() onStep(-1) end)
        return text
    end

    if ns.OpenEUIOptions and EllesmereUI then
        local euiRow = Row(28)
        local euiBtn = UI.TextButton(euiRow, "Open in EllesmereUI", 140, 20)
        euiBtn:SetPoint("LEFT", 6, 0)
        euiBtn:SetScript("OnClick", function() ns:OpenEUIOptions() end)
        local euiHint = UI.Line(euiRow, 10, "LEFT", 1, 1, 1, 0.53)
        euiHint:SetPoint("LEFT", euiBtn, "RIGHT", 8, 0)
        euiHint:SetPoint("RIGHT", -6, 0)
        euiHint:SetText("the looks: colours, sizes, fonts, under Sagerobot's Addons")
    end

    Header("Goals and deadline")
    local goalRow = Row(1)
    panel.goalEditor = UI.GoalEditor(goalRow, UI.WIDTH - 2 * UI.PAD - 12)
    panel.goalEditor:SetPoint("TOPLEFT", 0, 0)
    FitEditor(goalRow, panel.goalEditor)

    Header("On-screen bar")
    AddCheck("Show the bar", "A small bar showing today's (or this week's) earnings against the quota. Click it to open this window.",
        function() return ns.db.bar.shown end, function(v) ns:SetBarShown(v) end)
    AddCheck("Lock the bar", "Stops the bar from being dragged; Shift-drag still moves it.",
        function() return ns.db.bar.locked end, function(v) ns:SetBarLocked(v) end)
    AddCheck("Hide the bar in combat", "The bar goes away when you enter combat and comes back when you leave it.",
        function() return ns.db.bar.hideInCombat end, function(v) ns.db.bar.hideInCombat = v; ns:RefreshBar() end)
    local instRow = Row(26)
    RowLabel(instRow, "In instances")
    panel.InstanceTabs = Switch(instRow, {
        { "show", "Show", "The bar stays in dungeons, raids and battlegrounds." },
        { "smart", "Smart", "Hidden in Mythic+ runs, in raids while in combat (between pulls it stays, the AH mount is a click away), and in battlegrounds and arenas. Normal and heroic dungeons, old content and delves keep it, grouped or not." },
        { "group", "Grouped", "Hidden in any dungeon or raid while you are in a group, and in battlegrounds and arenas. Farming old dungeons on your own keeps it." },
        { "hide", "Hide", "Hidden in every dungeon, raid, battleground and arena, grouped or not." },
    }, 66, function(mode)
        ns.db.bar.instanceMode = mode
        ns:RefreshBar()
        ns:RefreshSettings()
    end)
    local modeRow = Row(26)
    RowLabel(modeRow, "Shows")
    panel.BarModeTabs = Switch(modeRow, {
        { "daily", "Today", "Today's earnings against today's quota." },
        { "weekly", "Week", "This week's earnings against the weekly quota." },
    }, 60, function(mode) ns:SetBarMode(mode); ns:RefreshSettings() end)
    local metRow = Row(26)
    RowLabel(metRow, "Once today is met")
    panel.AfterMetTabs = Switch(metRow, {
        { "count", "Keep counting", "The bar stays on today and counts on: 105%, 240%, with a brighter lap running over the full bar." },
        { "week", "Show the week", "Once today's quota is met the bar shows the week instead, until that is met too." },
    }, 96, function(mode) ns.db.bar.afterMet = mode; ns:RefreshBar(); ns:RefreshSettings() end)
    local barScaleRow = Row(26)
    RowLabel(barScaleRow, "Scale")
    panel.barScaleText = Stepper(barScaleRow, function(d)
        ns.db.bar.scale = math.max(0.6, math.min(2.0, (ns.db.bar.scale or 1) + d * 0.1))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)
    local barHeightRow = Row(26)
    RowLabel(barHeightRow, "Height")
    panel.barHeightText = Stepper(barHeightRow, function(d)
        ns.db.look.barHeight = math.max(14, math.min(32, (ns.db.look.barHeight or 20) + d))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)
    local barFontRow = Row(26)
    RowLabel(barFontRow, "Font size")
    panel.barFontText = Stepper(barFontRow, function(d)
        ns.db.look.barFont = math.max(8, math.min(16, (ns.db.look.barFont or 11) + d))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)
    AddCheck("Goal colours and tier marks on the bar", "Colour the bar red to green up to what the mount needs and blue into the accent past it, with a mark per tier. Off, it is the plain accent fill.",
        function() return ns.db.look.barColors ~= false end, function(v) ns.db.look.barColors = v; ns:RefreshBar() end)
    local barWidthRow = Row(26)
    RowLabel(barWidthRow, "Width")
    panel.barWidthText = Stepper(barWidthRow, function(d)
        ns.db.bar.width = math.max(140, math.min(500, (ns.db.bar.width or 220) + d * 20))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)
    local barResetRow = Row(28)
    local barPeek = UI.TextButton(barResetRow, "Show me the bar", 110, 20)
    barPeek:SetPoint("LEFT", 6, 0)
    barPeek:SetScript("OnClick", function() ns:PeekBar() end)
    UI.Tip(barPeek, "ANCHOR_RIGHT", "Show me the bar", "Brings it up for a few seconds whatever the rules say, so you can see where it is.")
    local barReset = UI.TextButton(barResetRow, "Reset position", 110, 20)
    barReset:SetPoint("LEFT", barPeek, "RIGHT", 6, 0)
    barReset:SetScript("OnClick", function() ns:ResetBarPosition(); ns:PeekBar() end)

    Header("Gold splash")
    AddCheck("Show a splash when gold comes in",
        "A combat-text style pop in the middle of the screen when the total grows by more than level 1: bigger, golden and louder the more it is. Gains within the merge window are one event, and gold that moves in the shops is counted without a splash.",
        function() return ns.db.splash.enabled end, function(v) ns.db.splash.enabled = v end)
    local levelRow = Row(1)
    panel.splashEditor = UI.SplashLevelEditor(levelRow, UI.WIDTH - 2 * UI.PAD - 12)
    panel.splashEditor:SetPoint("TOPLEFT", 0, 0)
    FitEditor(levelRow, panel.splashEditor)
    AddCheck("Play a sound with it", "A coin clink for the small ones, the loot toasts for the big ones.",
        function() return ns.db.splash.sound end, function(v) ns.db.splash.sound = v end)
    AddCheck("Glow behind it", "A soft golden glow behind the amount.",
        function() return ns.db.look.splashGlow ~= false end, function(v) ns.db.look.splashGlow = v end)
    AddCheck("Golden frame around the screen", "Lights the edges of the screen gold for a moment. It only brightens, never darkens.",
        function() return ns.db.splash.frame ~= false end, function(v) ns.db.splash.frame = v end)
    AddCheck("Say what the gain moved", "A line under the amount: its share of today's quota, or of the goal once it is a real share of it.",
        function() return ns.db.splash.progress ~= false end, function(v) ns.db.splash.progress = v end)
    local iconRow = Row(26)
    RowLabel(iconRow, "Coin icon")
    panel.IconTabs = Switch(iconRow, {
        { "custom", "GoldGoal", "Our own coin, drawn at 128 pixels so it stays sharp at any size." },
        { "pile", "Pile", "The game's gold-pile item icon." },
        { "classic", "Money", "The game's small money icon." },
        { "none", "None", "No coin." },
    }, 62, function(key) ns.db.look.splashIcon = key; ns:RefreshSettings() end)
    AddCheck("Celebrate the daily quota", "A splash the moment today's quota is met, even on a small gain.",
        function() return ns.db.splash.celebrateQuota ~= false end, function(v) ns.db.splash.celebrateQuota = v end)
    AddCheck("Celebrate a banked goal", "The top splash when a goal is banked.",
        function() return ns.db.splash.celebrateBanked ~= false end, function(v) ns.db.splash.celebrateBanked = v end)
    AddCheck("Announce percent marks of the goal", "Each mark crossed gets a note, even when a copper crossed it: on the gold splash when there is one, on its own otherwise.",
        function() return ns.db.splash.marks ~= false end, function(v) ns.db.splash.marks = v end)
    local EVERY, BIG = { 1, 2, 5, 10, 20, 25 }, { 10, 20, 25, 50, 100 }
    local function StepList(list, cur, d)
        local at = 1
        for i, v in ipairs(list) do if v <= cur then at = i end end
        return list[math.max(1, math.min(#list, at + d))]
    end
    local everyRow = Row(26)
    RowLabel(everyRow, "A mark every (%)")
    panel.markEveryText = Stepper(everyRow, function(d)
        ns.db.splash.markEvery = StepList(EVERY, ns.db.splash.markEvery or 1, d)
        ns:RefreshSettings()
    end)
    local bigRow = Row(26)
    RowLabel(bigRow, "A bigger one every (%)")
    panel.markBigText = Stepper(bigRow, function(d)
        ns.db.splash.markBigEvery = StepList(BIG, ns.db.splash.markBigEvery or 10, d)
        ns:RefreshSettings()
    end)
    AddCheck("Show big spends too, in red", "A loss past level 1 shows as a red amount saying spent. No sound, glow or frame.",
        function() return ns.db.splash.losses end, function(v) ns.db.splash.losses = v end)
    AddCheck("Show every sale's profit", "With CraftSimPL, gold arriving as stock leaves at cost is a sale: it shows its profit however small, with the margin on cost under it. A sale at a loss shows in red.",
        function() return ns.db.splash.profit ~= false end, function(v) ns.db.splash.profit = v end)
    local shopRow = Row(26)
    RowLabel(shopRow, "In the shops")
    panel.ShopTabs = Switch(shopRow, {
        { "quiet", "Stay quiet", "The auction house, vendors, the mailbox, the profession window and crafting orders: gold mostly moves around in there, out for reagents and back as sale mail. It all counts, none of it splashes. A goal banked, the day's quota and a sale's profit still show; a percent mark keeps for the next gain out in the world. Mail gold with no cost behind it is silent too." },
        { "merge", "One number", "Held while a window is open, then the total when you leave it. What the mailbox used to do, for all of them." },
        { "show", "As it happens", "No special treatment: gold there splashes like any other." },
    }, 84, function(key) ns.db.splash.shops = key; ns:RefreshSettings() end)
    AddCheck("Follow the bar's hide rules", "Stay quiet wherever the bar is hidden: in combat, in Mythic+ and the rest of the instance rule.",
        function() return ns.db.splash.followBar end, function(v) ns.db.splash.followBar = v end)
    local mergeRow = Row(26)
    RowLabel(mergeRow, "Merge window")
    panel.splashMergeText = Stepper(mergeRow, function(d)
        ns.db.splash.merge = math.max(0.5, math.min(15, (ns.db.splash.merge or 2) + d * 0.5))
        ns:RefreshSettings()
    end)
    local mergeHint = UI.Line(mergeRow, 10, "LEFT", 1, 1, 1, 0.53)
    mergeHint:SetPoint("LEFT", 90, 0)
    mergeHint:SetPoint("RIGHT", -110, 0)
    mergeHint:SetText("seconds of quiet before a gain shows")
    local sScaleRow = Row(26)
    RowLabel(sScaleRow, "Scale")
    panel.splashScaleText = Stepper(sScaleRow, function(d)
        ns.db.splash.scale = math.max(0.5, math.min(2.5, (ns.db.splash.scale or 1) + d * 0.1))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)
    local sPosRow = Row(26)
    RowLabel(sPosRow, "Height")
    panel.splashOffsetText = Stepper(sPosRow, function(d)
        ns.db.splash.offsetY = math.max(-400, math.min(400, (ns.db.splash.offsetY or 150) + d * 20))
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshSettings()
    end)

    Header("Data bar text")
    local brokerRow = Row(26)
    RowLabel(brokerRow, "Shows")
    panel.BrokerTabs = Switch(brokerRow, {
        { "daily", "Today", "Today's earnings against the quota: 8,450g / 14,000g (60%)." },
        { "weekly", "Week", "This week's earnings against the weekly quota." },
        { "total", "Total", "Everything saved against the target: 3.21M / 5.00M (64%)." },
    }, 60, function(mode) ns:SetBrokerMode(mode); ns:RefreshSettings() end)
    Hint("GoldGoal is a LibDataBroker source: add it to an EllesmereUI data bar as a Broker Plugin block, or to any broker display. Right-click it there to switch what it shows.", 40)

    Header("Crafting stock (CraftSimPL)")
    AddCheck("Count crafting stock at cost",
        "Reagents you have bought and crafts you have not sold, at what they cost you, from CraftSimPL's cost pools and open batches. Buying reagents is then not spending, and a sale counts as its profit. CraftSimPL's projections are shown but never counted.",
        function() return ns:CountsCrafting() end, function(v) ns:SetCountCrafting(v) end)
    panel.craftingHint = Hint("", 30)

    Header("Window")
    local scaleRow = Row(26)
    RowLabel(scaleRow, "Scale")
    panel.scaleText = Stepper(scaleRow, function(d)
        ns.db.window.scale = math.max(0.6, math.min(1.5, (ns.db.window.scale or 1) + d * 0.05))
        ns:AnchorWindow()
        ns:RefreshSettings()
    end)

    Header("Goal and characters")
    local btnRow = Row(28)
    -- two clicks: the first arms it, the second within five seconds does it
    local newGoal = UI.TextButton(btnRow, "Start a new goal", 120, 20)
    newGoal:SetPoint("LEFT", 6, 0)
    newGoal:SetScript("OnClick", function(self)
        if self.armed and GetTime() - self.armed < 5 then
            self.armed = nil
            self.Text:SetText("Start a new goal")
            ns:StartNewGoal()
            ns:Print("New goal started: the history and the averages begin now. The target and deadline are kept. /gg undo puts the history back.")
            ns:RefreshSettings()
        else
            self.armed = GetTime()
            self.Text:SetText("|cffff9900Click again to confirm|r")
            C_Timer.After(5, function() if self.armed and GetTime() - self.armed >= 5 then self.armed = nil; self.Text:SetText("Start a new goal") end end)
        end
    end)
    UI.Tip(newGoal, "ANCHOR_RIGHT", "Start a new goal", "Clears the day and week history so the averages and the projection start over from now. Characters, the target and the deadline are kept. Click twice; Undo puts the history back.")
    panel.undoGoal = UI.TextButton(btnRow, "Undo", 50, 20)
    panel.undoGoal:SetPoint("LEFT", newGoal, "RIGHT", 6, 0)
    panel.undoGoal:SetScript("OnClick", function()
        if ns:UndoNewGoal() then ns:Print("History restored from before the last new goal.") end
        ns:RefreshSettings()
    end)
    UI.Tip(panel.undoGoal, "ANCHOR_RIGHT", "Undo", "Puts the history back as it was before the last Start a new goal.")
    local forget = UI.TextButton(btnRow, "Forget all characters", 140, 20)
    forget:SetPoint("LEFT", panel.undoGoal, "RIGHT", 6, 0)
    forget:SetScript("OnClick", function(self)
        if self.armed and GetTime() - self.armed < 5 then
            self.armed = nil
            self.Text:SetText("Forget all characters")
            ns:ForgetAllCharacters()
            ns:Print("Character list cleared and re-read.")
            ns:RefreshSettings()
        else
            self.armed = GetTime()
            self.Text:SetText("|cffff9900Click again to confirm|r")
            C_Timer.After(5, function() if self.armed and GetTime() - self.armed >= 5 then self.armed = nil; self.Text:SetText("Forget all characters") end end)
        end
    end)
    UI.Tip(forget, "ANCHOR_RIGHT", "Forget all characters", "Drops every character but this one, then reads Syndicator again. Nothing counts as earnings. Click twice.")
    local synRow = Row(28)
    panel.syndicatorButton = UI.TextButton(synRow, "Re-read Syndicator", 130, 20)
    panel.syndicatorButton:SetPoint("LEFT", 6, 0)
    panel.syndicatorButton:SetScript("OnClick", function()
        local n = ns:MergeSyndicator()
        ns:Print(string.format("Syndicator: %d character(s) added.", n))
        ns:RefreshSettings()
    end)
    panel.syndicatorHint = UI.Line(synRow, 10, "LEFT", 1, 1, 1, 0.53)
    panel.syndicatorHint:SetPoint("LEFT", panel.syndicatorButton, "RIGHT", 8, 0)
    panel.syndicatorHint:SetPoint("RIGHT", -6, 0)
    Hint("Only gold that changes while you play counts as earnings. A character seen for the first time, a Syndicator figure, an excluded character or a forgotten one moves the total but never today's earnings.", 40)

    local verRow = Row(20)
    local ver = Style.Text(verRow, 10, 1, 1, 1, 0.41)
    ver:SetPoint("LEFT", 8, 0)
    ver:SetText("GoldGoal v" .. tostring(ns.version))

    c:SetHeight(-y + 10)
    for _, fit in ipairs(fits) do fit() end
    panel:SetScript("OnShow", function() ns:RefreshSettings() end)
    return panel
end

function ns:RefreshSettings()
    if not panel or not panel:IsShown() then return end
    local db = self.db
    for _, cb in ipairs(panel.controls) do cb:SetChecked(cb.get() and true or false) end
    local function Select(tabs, id)
        if tabs.selectedTabID ~= id then Style.SelectTab(tabs, id) end
    end
    Select(panel.BarModeTabs, db.bar.mode)
    Select(panel.InstanceTabs, db.bar.instanceMode or "smart")
    Select(panel.AfterMetTabs, db.bar.afterMet or "count")
    Select(panel.IconTabs, db.look.splashIcon or "custom")
    Select(panel.ShopTabs, db.splash.shops or "quiet")
    Select(panel.BrokerTabs, db.broker.mode)
    panel.goalEditor:Refresh()
    panel.splashEditor:Refresh()
    panel.markEveryText:SetText(tostring(db.splash.markEvery or 1) .. "%")
    panel.markBigText:SetText(tostring(db.splash.markBigEvery or 10) .. "%")
    panel.splashMergeText:SetText(string.format("%.1fs", db.splash.merge or 2))
    panel.splashScaleText:SetText(string.format("%d%%", (db.splash.scale or 1) * 100 + 0.5))
    panel.splashOffsetText:SetText(tostring(db.splash.offsetY or 150))
    panel.barHeightText:SetText(tostring(db.look.barHeight or 20))
    panel.barFontText:SetText(tostring(db.look.barFont or 11))
    panel.barScaleText:SetText(string.format("%d%%", (db.bar.scale or 1) * 100 + 0.5))
    panel.barWidthText:SetText(tostring(db.bar.width or 220))
    panel.scaleText:SetText(string.format("%d%%", (db.window.scale or 1) * 100 + 0.5))
    if self:HasCraftingAPI() then
        local realms = self:CraftingRealms()
        panel.craftingHint:SetText(#realms > 0
            and string.format("CraftSimPL reports %s at cost for %d realm%s; the Characters tab has a row per realm.", self.FormatGold(self:CraftingAtCost()), #realms, #realms == 1 and "" or "s")
            or "CraftSimPL is loaded; its working capital is read whenever its ledger changes.")
    elseif CraftSimPL then
        panel.craftingHint:SetText("CraftSimPL is loaded but has no working-capital API (CraftSimPL.API:GetWorkingCapital); update it.")
    else
        panel.craftingHint:SetText("CraftSimPL is not loaded. With it, crafting stock counts as wealth at cost.")
    end
    panel.undoGoal:SetEnabled(self:CanUndoNewGoal())
    local has = self:HasSyndicator()
    panel.syndicatorButton:SetEnabled(has)
    panel.syndicatorHint:SetText(has and "Fills in characters not logged in since GoldGoal was installed." or "Syndicator (Baganator) is not loaded.")
end

-------------------------------------------------------------------------------
-- Entry in the game's Settings > AddOns list
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    if not Settings then return end
    local f = CreateFrame("Frame")
    f.name = "GoldGoal"
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GoldGoal")
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText("A savings plan for big gold targets: every character and the warband bank pooled, a daily quota that adjusts itself, and a projected finish date. Settings live in the window.\n\nCommands: /gg, /gg bar, /gg target <n>, /gg deadline <date>, /gg status")
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    open:SetText("Open GoldGoal")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns:OpenOptions()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, f, f.name)
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end)

-- GoldGoal: its home in EllesmereUI's options panel, under a "Sagerobot's
-- Addons" group in the sidebar. The Goal dashboard, the Characters and
-- History lists are the same pages the window shows, embedded; the rest
-- is built with EllesmereUI's own widgets. /gg opens here; the window is
-- the fallback and keeps everything.
--
-- EllesmereUI keeps RegisterModule for its own folders (it reads the
-- caller's folder off the stack), so the call goes through pcall, whose C
-- frame carries no folder. That is a gap in a guard, not an API: an
-- EllesmereUI update can close it. OpenEUIOptions notices when the page
-- never builds and falls back to the window for the session.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local FOLDER = "GoldGoal"
local E = EllesmereUI

if not (E and E.RegisterModule and E.ADDON_GROUPS and E._addonInfoByFolder) then
    function ns:OpenEUIOptions() return false end
    return
end

-------------------------------------------------------------------------------
-- Sidebar: our group and row, before the panel is built
-------------------------------------------------------------------------------
E._addonInfoByFolder[FOLDER] = E._addonInfoByFolder[FOLDER] or { folder = FOLDER, display = "GoldGoal", search_name = "GoldGoal Sagerobot" }
local group
for _, g in ipairs(E.ADDON_GROUPS) do
    if g.key == "sagerobot" then group = g end
end
if not group then
    group = { key = "sagerobot", label = "Sagerobot's Addons", members = {} }
    table.insert(E.ADDON_GROUPS, group)
end
local listed
for _, m in ipairs(group.members) do
    if m == FOLDER then listed = true end
end
if not listed then table.insert(group.members, FOLDER) end
if E._syncExempt then E._syncExempt[FOLDER] = true end -- no EllesmereUI profile to sync

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local C = ns.COPPER
local PAD = E.CONTENT_PAD or 20
local embedded = {}   -- the window pages living inside the panel
ns.euiSetup = {}      -- the text boxes, for the harness

local function Apply()
    ns:AnchorBar()
    ns:RefreshBar()
    ns:AnchorSplash()
    ns:Fire("SETTINGS_CHANGED")
end

local function PctGet(get) return function() return math.floor((get() or 1) * 100 + 0.5) end end

local function TabByKey(key)
    for _, tab in ipairs(UI.Tabs) do
        if tab.key == key then return tab end
    end
end

-- A line of plain text between rows.
local function Note(parent, y, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize((parent:GetWidth() or 600) - PAD * 2, 34)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    f._isSpacer = true
    local fs
    if E.MakeFont then fs = E.MakeFont(f, 13, nil, 1, 1, 1, 0.7) else fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -6)
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -6)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    f.Text = fs
    return f, 34
end

-- One of the window's pages, built into the panel with its own row pools.
local function Embed(parent, y, key, height)
    local tab = TabByKey(key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y)
    f:SetHeight(height)
    f.pools = { charRows = {}, dayRows = {} }
    f.tab = tab
    tab.Build(f, (parent:GetWidth() or 700) - PAD * 2)
    f:SetScript("OnShow", function(self) if ns.db then self.tab.Refresh(self) end end)
    embedded[#embedded + 1] = f
    if ns.db then tab.Refresh(f) end
    return f, height + 10
end

local function RefreshEmbedded()
    if not ns.db then return end
    for _, f in ipairs(embedded) do
        if f:IsVisible() then f.tab.Refresh(f) end
    end
end
ns.RefreshEUIPages = RefreshEmbedded

local function ColorGet(key)
    return function()
        local c = ns.db.look.colors[key] or {}
        return c[1] or 1, c[2] or 1, c[3] or 1, 1
    end
end

local function ColorSet(key)
    return function(r, g, b)
        ns.db.look.colors[key] = { r, g, b }
        Apply()
    end
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
local PAGES = {}

function PAGES.Goal(W, parent, y)
    local h
    _, h = Embed(parent, y, "goal", 470); y = y - h

    _, h = W:SectionHeader(parent, "GOALS AND DEADLINE", y); y = y - h
    local ed = UI.GoalEditor(parent, (parent:GetWidth() or 700) - PAD * 2)
    ed:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    ed.onLayout = function() E:RefreshPage(true) end
    embedded[#embedded + 1] = ed
    ed.tab = { Refresh = function(f) f:Refresh() end }
    ns.euiSetup.editor = ed
    h = ed:Refresh(); y = y - h - 10
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

-- Asks first when EllesmereUI has a dialog for it, otherwise just does it.
local function Confirm(title, message, confirmText, fn)
    if E.ShowConfirmPopup then
        E:ShowConfirmPopup({ title = title, message = message, confirmText = confirmText, cancelText = "Cancel", onConfirm = fn })
    else
        fn()
    end
end

function PAGES.Characters(W, parent, y)
    local h
    _, h = Note(parent, y, "Everything the total is made of. Untick a character to leave it out; right-click one to forget it. The Warband Bank is read when the game allows, at the latest when you open a bank."); y = y - h
    _, h = Embed(parent, y, "chars", 340); y = y - h
    _, h = W:SectionHeader(parent, "SOURCES", y); y = y - h
    _, h = W:Toggle(parent, "Count crafting stock at cost", y,
        function() return ns:CountsCrafting() end, function(v) ns:SetCountCrafting(v); RefreshEmbedded() end,
        "With CraftSimPL loaded. The Crafting stock rows show what it reports per realm."); y = y - h
    _, h = W:WideDualButton(parent, "Re-read Syndicator", "Forget all characters", y,
        function()
            local n = ns:MergeSyndicator()
            ns:Print(string.format("Syndicator: %d character(s) added.", n))
            RefreshEmbedded()
        end,
        function()
            Confirm("Forget all characters", "Drop every character but this one and read Syndicator again? Nothing counts as earnings, and the goal and history are kept.", "Forget them", function()
                ns:ForgetAllCharacters()
                ns:Print("Character list cleared and re-read.")
                RefreshEmbedded()
            end)
        end); y = y - h
    _, h = Note(parent, y, "Only gold that changes while you play counts as earnings. A character seen for the first time, a Syndicator figure, an excluded or forgotten character moves the total but never today's earnings."); y = y - h
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

function PAGES.History(W, parent, y)
    local h
    _, h = Embed(parent, y, "history", 440); y = y - h
    _, h = Note(parent, y, "Days run from one daily reset to the next, weeks from reset to reset. A mark means the quota was met."); y = y - h
    _, h = W:SectionHeader(parent, "START OVER", y); y = y - h
    local function NewGoal()
        ns:StartNewGoal()
        ns:Print("New goal started: the history and the averages begin now. Goals, deadline and characters are kept. Undo puts the history back.")
        E:RefreshPage()
    end
    _, h = W:WideDualButton(parent, "Start a new goal", ns:CanUndoNewGoal() and "Undo the last new goal" or "Nothing to undo", y,
        function()
            Confirm("Start a new goal", "Clear the day and week history? Goals, deadline and characters are kept, and Undo can bring the history back.", "Start over", NewGoal)
        end,
        function()
            if ns:UndoNewGoal() then ns:Print("History restored from before the last new goal.") end
            E:RefreshPage()
        end); y = y - h
    _, h = Note(parent, y, "Starting a new goal clears this history so the averages and the projection begin again from now, say after buying the mount."); y = y - h
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

function PAGES.Bar(W, parent, y)
    local h
    _, h = W:SectionHeader(parent, "SHOW", y); y = y - h
    _, h = W:Toggle(parent, "Show the bar", y, function() return ns.db.bar.shown end, function(v) ns:SetBarShown(v) end,
        "The slim on-screen bar with today's (or the week's) earnings against the quota."); y = y - h
    _, h = W:Toggle(parent, "Lock the bar", y, function() return ns.db.bar.locked end, function(v) ns:SetBarLocked(v) end,
        "Stops the bar from being dragged; Shift-drag still moves it."); y = y - h
    _, h = W:Toggle(parent, "Hide in combat", y, function() return ns.db.bar.hideInCombat end, function(v) ns.db.bar.hideInCombat = v; ns:RefreshBar() end,
        "The bar goes away when you enter combat and comes back when you leave it."); y = y - h
    _, h = W:Dropdown(parent, "In instances", y, { show = "Always show", smart = "Smart", group = "Hide when grouped", hide = "Always hide" },
        function() return ns.db.bar.instanceMode or "smart" end, function(v) ns.db.bar.instanceMode = v; ns:RefreshBar() end, { "show", "smart", "group", "hide" },
        "Smart hides it in Mythic+ runs, in raids while in combat (between pulls it stays), and in battlegrounds and arenas; normal dungeons, old content and delves keep it. Hide when grouped hides it in any instance while you are in a group."); y = y - h
    _, h = W:Dropdown(parent, "Shows", y, { daily = "Today", weekly = "The week" },
        function() return ns.db.bar.mode end, function(v) ns:SetBarMode(v) end, { "daily", "weekly" }, "Today against today's quota, or the week against the weekly quota. Right-click the bar to flip this too."); y = y - h
    _, h = W:Dropdown(parent, "Once today is met", y, { count = "Keep counting", week = "Show the week" },
        function() return ns.db.bar.afterMet or "count" end, function(v) ns.db.bar.afterMet = v; ns:RefreshBar() end, { "count", "week" },
        "What the bar does past 100% of today's quota: keep counting (105%, 240%, with a brighter lap running over the full bar), or show the week until that is met too. Either way a mark appears at its end, and tomorrow's quota comes down by what you went over."); y = y - h

    _, h = W:SectionHeader(parent, "LOOK", y); y = y - h
    _, h = W:Slider(parent, "Height", y, 14, 32, 1, function() return ns.db.look.barHeight end, function(v) ns.db.look.barHeight = v; Apply() end, "The bar's height in pixels."); y = y - h
    _, h = W:Slider(parent, "Font size", y, 8, 16, 1, function() return ns.db.look.barFont end, function(v) ns.db.look.barFont = v; Apply() end); y = y - h
    _, h = W:Slider(parent, "Width", y, 140, 500, 10, function() return ns.db.bar.width end, function(v) ns.db.bar.width = v; Apply() end); y = y - h
    _, h = W:Slider(parent, "Scale", y, 60, 200, 5, PctGet(function() return ns.db.bar.scale end), function(v) ns.db.bar.scale = v / 100; Apply() end, "In percent."); y = y - h
    _, h = W:Slider(parent, "Opacity", y, 30, 100, 5, PctGet(function() return ns.db.look.barAlpha end), function(v) ns.db.look.barAlpha = v / 100; Apply() end, "In percent."); y = y - h
    _, h = W:Toggle(parent, "Today / Week label", y, function() return ns.db.look.barLabel ~= false end, function(v) ns.db.look.barLabel = v; Apply() end,
        "The small word at the left of the bar."); y = y - h
    _, h = W:Toggle(parent, "Percent", y, function() return ns.db.look.barPercent ~= false end, function(v) ns.db.look.barPercent = v; Apply() end,
        "The percentage after the amounts."); y = y - h
    _, h = W:Toggle(parent, "Goal colours and tier marks", y, function() return ns.db.look.barColors ~= false end, function(v) ns.db.look.barColors = v; Apply() end,
        "Colour the bar red to green up to what the mount needs and blue into the accent past it, with a mark per tier. Off, it is the plain accent fill."); y = y - h
    _, h = W:WideDualButton(parent, "Show me the bar", "Reset its position", y,
        function() ns:PeekBar() end, function() ns:ResetBarPosition(); ns:PeekBar() end); y = y - h
    _, h = Note(parent, y, "Show me the bar brings it up for a few seconds whatever the rules say, so you can see where it is."); y = y - h

    _, h = W:SectionHeader(parent, "DATA BAR TEXT", y); y = y - h
    _, h = W:Dropdown(parent, "The broker text shows", y, { daily = "Today", weekly = "The week", total = "The total" },
        function() return ns.db.broker.mode end, function(v) ns:SetBrokerMode(v) end, { "daily", "weekly", "total" },
        "Today against the quota, the week against its quota, or everything saved against the goal. GoldGoal is a LibDataBroker source: add it to a DataBars bar as a Broker Plugin block."); y = y - h
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

function PAGES.Splash(W, parent, y)
    local h
    local cfg = ns.db.splash
    _, h = W:SectionHeader(parent, "SHOW", y); y = y - h
    _, h = W:Toggle(parent, "Gold splash", y, function() return cfg.enabled end, function(v) cfg.enabled = v end,
        "A combat-text style pop in the middle of the screen when the total grows by more than level 1, bigger and louder the more it is."); y = y - h
    _, h = W:Toggle(parent, "Follow the bar's hide rules", y, function() return cfg.followBar end, function(v) cfg.followBar = v end,
        "Stay quiet wherever the bar is hidden: in combat, in Mythic+ and the rest of the instance rule. The gold still counts."); y = y - h
    _, h = W:Toggle(parent, "Show big spends too, in red", y, function() return cfg.losses end, function(v) cfg.losses = v end,
        "A loss past level 1 shows as a red amount saying spent. No sound, glow or frame."); y = y - h

    _, h = W:SectionHeader(parent, "LEVELS", y); y = y - h
    local ed = UI.SplashLevelEditor(parent, (parent:GetWidth() or 700) - PAD * 2)
    ed:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    embedded[#embedded + 1] = ed
    ed.tab = { Refresh = function(f) f:Refresh() end }
    ns.euiSetup.splash = ed
    ed.onLayout = function() E:RefreshPage(true) end
    h = ed:Refresh(); y = y - h - 10

    _, h = W:SectionHeader(parent, "EFFECTS", y); y = y - h
    _, h = W:Toggle(parent, "Sound", y, function() return cfg.sound end, function(v) cfg.sound = v; RefreshEmbedded() end,
        "A coin clink for the small levels, the loot toasts for the big ones."); y = y - h
    _, h = W:Toggle(parent, "Glow", y, function() return ns.db.look.splashGlow ~= false end, function(v) ns.db.look.splashGlow = v; RefreshEmbedded() end,
        "A soft golden glow behind the amount."); y = y - h
    _, h = W:Toggle(parent, "Golden frame", y, function() return cfg.frame ~= false end, function(v) cfg.frame = v; RefreshEmbedded() end,
        "Lights the edges of the screen gold for a moment. It only brightens, never darkens."); y = y - h
    _, h = W:Toggle(parent, "Say what the gain moved", y, function() return cfg.progress ~= false end, function(v) cfg.progress = v end,
        "A line under the amount: its share of today's quota, or of the goal once it is a real share of it."); y = y - h
    _, h = W:Dropdown(parent, "Coin icon", y, ns.SPLASH_ICONS, function() return ns.db.look.splashIcon or "custom" end,
        function(v) ns.db.look.splashIcon = v end, ns.SPLASH_ICON_ORDER,
        "The coin next to the amount: GoldGoal's own coin (drawn at 128 pixels, so it stays sharp at any size), the game's gold-pile item icon, the game's small money icon, or none."); y = y - h

    _, h = W:SectionHeader(parent, "MOMENTS", y); y = y - h
    _, h = W:Toggle(parent, "Celebrate the daily quota", y, function() return cfg.celebrateQuota ~= false end, function(v) cfg.celebrateQuota = v end,
        "A splash the moment today's quota is met, even on a small gain."); y = y - h
    _, h = W:Toggle(parent, "Celebrate a banked goal", y, function() return cfg.celebrateBanked ~= false end, function(v) cfg.celebrateBanked = v end,
        "The top splash when a goal is banked."); y = y - h
    _, h = W:Toggle(parent, "Announce percent marks of the goal", y, function() return cfg.marks ~= false end, function(v) cfg.marks = v end,
        "Each mark crossed gets a note, even when a copper crossed it: on the gold splash when there is one, on its own otherwise."); y = y - h
    _, h = W:Dropdown(parent, "A mark every", y, { ["1"] = "1%", ["2"] = "2%", ["5"] = "5%", ["10"] = "10%", ["20"] = "20%", ["25"] = "25%" },
        function() return tostring(cfg.markEvery or 1) end, function(v) cfg.markEvery = tonumber(v) end, { "1", "2", "5", "10", "20", "25" },
        "How far apart the marks are, in percent of the goal."); y = y - h
    _, h = W:Dropdown(parent, "A bigger one every", y, { ["10"] = "10%", ["20"] = "20%", ["25"] = "25%", ["50"] = "50%", ["100"] = "100% only" },
        function() return tostring(cfg.markBigEvery or 10) end, function(v) cfg.markBigEvery = tonumber(v) end, { "10", "20", "25", "50", "100" },
        "Marks on these get level 3 at least."); y = y - h

    _, h = W:SectionHeader(parent, "TIMING AND PLACE", y); y = y - h
    _, h = W:Slider(parent, "Merge window (seconds)", y, 0.5, 15, 0.5, function() return cfg.merge end, function(v) cfg.merge = v end,
        "How long it stays quiet before a gain shows; everything inside the window is one event."); y = y - h
    _, h = W:Toggle(parent, "Hold while the mailbox is open", y, function() return cfg.holdMail ~= false end, function(v) cfg.holdMail = v end,
        "Nothing shows until the mailbox closes, so a run through the mails is one number. Off, gains show as they merge."); y = y - h
    _, h = W:Slider(parent, "Scale", y, 50, 250, 10, PctGet(function() return cfg.scale end), function(v) cfg.scale = v / 100; Apply() end, "In percent."); y = y - h
    _, h = W:Slider(parent, "Height on screen", y, -400, 400, 10, function() return cfg.offsetY end, function(v) cfg.offsetY = v; Apply() end,
        "Pixels above (or below) the centre of the screen."); y = y - h
    _, h = W:Slider(parent, "Time on screen", y, 50, 200, 10, PctGet(function() return ns.db.look.splashSpeed end), function(v) ns.db.look.splashSpeed = v / 100 end,
        "In percent of the usual: 200% holds each splash twice as long."); y = y - h

    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

function PAGES.Colours(W, parent, y)
    local h
    _, h = W:SectionHeader(parent, "GOAL BAR COLOURS", y); y = y - h
    _, h = Note(parent, y, "The bars run through these on the way to what the mount needs, then from the last one into your EllesmereUI accent colour."); y = y - h
    _, h = W:ColorPicker(parent, "Nothing saved yet", y, ColorGet("red"), ColorSet("red")); y = y - h
    _, h = W:ColorPicker(parent, "Halfway to the mount", y, ColorGet("yellow"), ColorSet("yellow")); y = y - h
    _, h = W:ColorPicker(parent, "The mount is safe", y, ColorGet("green"), ColorSet("green")); y = y - h
    _, h = W:ColorPicker(parent, "Just past the mount", y, ColorGet("blue"), ColorSet("blue")); y = y - h
    _, h = W:Button(parent, "Reset the colours", y, function()
        ns.db.look.colors = ns.DeepCopy(ns.DEFAULTS.look.colors)
        Apply()
        E:RefreshPage()
    end); y = y - h

    _, h = W:SectionHeader(parent, "WINDOW", y); y = y - h
    _, h = W:Slider(parent, "Window scale", y, 60, 150, 5, PctGet(function() return ns.db.window.scale end),
        function(v) ns.db.window.scale = v / 100; ns:AnchorWindow() end, "The size of the GoldGoal window (/gg window), the fallback for all of this."); y = y - h
    _, h = W:Button(parent, "Open the GoldGoal window", y, function() ns:ShowWindow() end); y = y - h
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------
local CONFIG = {
    title = "GoldGoal",
    description = "A savings plan for the 5,000,000g mount: every character and the warband bank pooled, a daily quota that adjusts itself, a bar and a gold splash.",
    searchTerms = "gold goal mount savings quota bar splash tiers deadline characters history sagerobot",
    pages = { "Goal", "Characters", "History", "Bar", "Splash", "Colours" },
    buildPage = function(pageName, parent, yOffset)
        local W = E.Widgets
        local build = PAGES[pageName]
        if not (W and build and ns.db) then return 100 end
        ns.euiPageBuilt = true
        ns.euiActive = true
        local ok, y = pcall(build, W, parent, yOffset or -6)
        if not ok then
            geterrorhandler()(y)
            return 100
        end
        return math.abs(y)
    end,
    onModuleLeave = function() ns.euiActive = false end,
    onReset = function()
        if not ns.db then return end
        for _, key in ipairs({ "bar", "splash", "look", "window", "broker" }) do
            ns.db[key] = ns.DeepCopy(ns.DEFAULTS[key])
        end
        Apply()
    end,
}
ns.EUIConfig = CONFIG

local registered = false
local function Register()
    if registered then return end
    -- through pcall: see the note at the top of the file
    local ok = pcall(E.RegisterModule, E, FOLDER, CONFIG)
    registered = ok and true or false
end

ns:On("LOGIN", Register)
ns:On("WEALTH_CHANGED", RefreshEmbedded)
ns:On("SETTINGS_CHANGED", RefreshEmbedded)
if E.RegisterOnShow then pcall(E.RegisterOnShow, E, RefreshEmbedded) end

-- Opens EllesmereUI's panel on the GoldGoal page (toggle: closes it when
-- it is already showing the page). Returns false when the panel is not
-- to be had, so the caller shows the window instead. If the page never
-- builds after opening, the guard has closed: the window takes over for
-- the rest of the session.
function ns:OpenEUIOptions(toggle)
    if self.euiBroken then return false end
    Register()
    if not (E.Show and E.SelectModule) then return false end
    if toggle and self.euiActive and E.IsShown and E:IsShown() then
        E:Hide()
        return true
    end
    E:Show()
    for _, delay in ipairs({ 0.1, 0.5, 1.0 }) do
        C_Timer.After(delay, function()
            if not (self.euiActive and E.IsShown and E:IsShown()) then pcall(E.SelectModule, E, FOLDER) end
        end)
    end
    C_Timer.After(2.0, function()
        if not ns.euiPageBuilt then
            ns.euiBroken = true
            ns:Print("EllesmereUI did not take the GoldGoal page; using the window instead.")
            if E.Hide then pcall(E.Hide, E) end
            ns:ShowWindow()
        end
    end)
    return true
end

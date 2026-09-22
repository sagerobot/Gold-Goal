-- GoldGoal: namespace, saved variables, events, shared helpers, slash commands.
local ADDON, ns = ...
GoldGoal = ns -- for /dump and other addons

ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-------------------------------------------------------------------------------
-- Saved variable defaults. Everything is account-wide (GoldGoalDB): the goal,
-- every character's gold, the warband bank and the day-by-day history.
-------------------------------------------------------------------------------
ns.DEFAULTS = {
    schema = 1,                 -- migrated in Goal.lua
    target = 5000000 * 10000,   -- copper: the paced tier's gold (Goal.lua keeps it in step)
    targetPreset = "ladder",    -- "mount" (5M) | "set" (5M, 7M) | "ladder" (5M, 7M, 10M) | "custom"
    tiers = {},                 -- { { name, gold }, ... } cheapest first (Goal.lua fills the default)
    tierIndex = 1,              -- the tier the quota paces towards
    deadline = nil,             -- unix time: the daily reset that ends the chosen day
    deadlinePreset = "expansion", -- "season" | "expansion" (shipped guesses) | "date" | "days"
    deadlineGuess = nil,        -- the guess the deadline was derived from, to follow updates
    goalStart = nil,            -- when the current goal was (re)started
    goalStartDay = nil,         -- the day id it started on (Ledger.lua)
    lastTotal = nil,            -- total wealth after the last observation
    chars = {},                 -- ["Name-Realm"] = { money, class, name, realm, lastSeen, include, source = "live" | "syndicator" }
    forgotten = {},             -- ["Name-Realm"] = true: never re-added from Syndicator
    warband = {},               -- { money, updated, source }
    crafting = {},              -- [realmKey] = CraftSimPL working capital at cost (Crafting.lua)
    countCrafting = true,       -- crafting stock at cost counts in the total
    days = {},                  -- [dayID] = { start, last, quota, week }
    weeks = {},                 -- [weekID] = { start, last, quota, days, firstDay }
    bar = { shown = true, locked = false, mode = "daily", pos = nil, scale = 1.0, width = 220, hideInCombat = true,
        instanceMode = "smart",     -- "show" | "smart" (M+ always, raids in combat, PvP) | "group" (any instance when grouped) | "hide"
        afterMet = "count" },       -- once today's quota is met: "count" (105%, a lap over the bar) | "week" (show the week)
    splash = { enabled = true, threshold = 500 * 10000, merge = 2.0, scale = 1.0, offsetY = 150, sound = true, frame = true,
        progress = true, marks = true,
        levels = {},                -- { { gold, flavor }, ... } x5, filled from Splash.lua's defaults
        soundFrom = 1, glowFrom = 3, frameFrom = 4,   -- the level each effect starts at
        markEvery = 1, markBigEvery = 10,             -- percent marks: how often, and when they get bigger
        celebrateQuota = true, celebrateBanked = true, -- the quota-met and goal-banked splashes
        losses = false,             -- show big spends too, in red
        profit = true,              -- a sale of crafting stock (gold in, stock out at cost) shows its profit and margin, whatever the size
        shops = "quiet",            -- gold that moves while the auction house, a vendor, the mailbox,
                                    -- the profession window or a crafting order is open:
                                    -- "quiet" (counted, never splashed) | "merge" (one number when
                                    -- you leave) | "show" (treated like any other gold)
        followBar = false },        -- keep quiet wherever the bar's hide rules hide it
    progressMark = nil,         -- { target, pct }: the last whole percent of the paced tier announced
    bankedTiers = {},           -- [tierIndex] = true once its splash has shown
    broker = { mode = "daily" },-- "daily" | "weekly" | "total"
    look = {                    -- the looks, editable in EllesmereUI's options panel (EUIOptions.lua)
        barHeight = 20, barFont = 11, barLabel = true, barPercent = true, barColors = true, barAlpha = 1.0,
        splashGlow = true, splashSpeed = 1.0, splashIcon = "custom", -- "custom" (our coin art) | "pile" | "classic" | "none"
        colors = { red = { 0.85, 0.22, 0.22 }, yellow = { 0.95, 0.80, 0.15 }, green = { 0.25, 0.80, 0.35 }, blue = { 0.30, 0.55, 0.95 } },
    },
    window = { pos = nil, scale = 1.0 },
    debug = false,
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end
ns.DeepCopy = DeepCopy

local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

ns.issecret = issecretvalue or function() return false end

ns.PREFIX_HEX = "|cffffd100"

function ns:Print(...)
    print(ns.PREFIX_HEX .. "GoldGoal|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then print("|cff888888GG|r:", ...) end
end

function ns:Round(v)
    return math.floor(v + 0.5)
end

-- A number the addon may read (not a 12.x secret value), else nil.
function ns.Num(v)
    if type(v) == "number" and not ns.issecret(v) then return v end
    return nil
end

function ns.HexColor(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

function ns.StripColor(s)
    return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-------------------------------------------------------------------------------
-- Internal messages, game events, timers
-------------------------------------------------------------------------------
local function Call(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

local listeners = {}
function ns:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

-- One message reaches the bar, the broker, the window and the options
-- page, and every one of them asks for the same projection. `dispatching`
-- is what lets them share one (Goal.lua caches it only while a message is
-- out): a listener cannot have moved the ledger without saying so, while
-- anything calling in from outside gets a reading taken there and then.
function ns:Fire(message, ...)
    if not listeners[message] then return end
    self.dispatching = (self.dispatching or 0) + 1
    Call(listeners[message], ...)
    self.dispatching = self.dispatching - 1
end

local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns:RegisterEvent(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    -- an unknown event name raises; never let that break a caller
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then self:Debug("Unknown event", event) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if handlers[event] then Call(handlers[event], ...) end
end)

-- Schedule(key, delay, fn) called again within `delay` runs fn once.
local pending = {}
function ns:Schedule(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end)
end

-------------------------------------------------------------------------------
-- Saved variables and login
-------------------------------------------------------------------------------
local function LoadSavedVariables()
    GoldGoalDB = CopyDefaults(GoldGoalDB, ns.DEFAULTS)
    ns.db = GoldGoalDB
    if ns.Invalidate then ns:Invalidate() end -- a reset swaps the whole table out
end
ns.LoadSavedVariables = LoadSavedVariables

ns:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    LoadSavedVariables()
    ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.playerClass = select(2, UnitClass("player"))
    ns.playerName = UnitName("player")
    ns.started = true
    ns:Fire("LOGIN")
end)

-------------------------------------------------------------------------------
-- /gg status
-------------------------------------------------------------------------------
function ns:PrintStatus()
    local p = self:Projection()
    self:Print("Status")
    print(string.format("  Target: %s (%s)  deadline: %s (%s), %s day(s) left", self.FormatGold(self.db.target), self.db.targetPreset,
        self.db.deadline and self:DeadlineText() or "none", self.db.deadlinePreset, tostring(p.daysLeft)))
    for _, e in ipairs(p.tiers) do
        print(string.format("    %s%-18s %14s  %s", e.paced and "> " or "  ", e.name, self.FormatGold(e.gold), self.StripColor(self:TierText(e))))
    end
    print(string.format("  Wealth: %s across %d character(s) + warband %s = remaining %s",
        self.FormatGold(p.total), self:CountCharacters(), self.db.warband.money and self.FormatGold(self.db.warband.money) or "unknown", self.FormatGold(p.remaining)))
    print(string.format("  Today (day %s): %s of %s; this week (week %s): %s of %s", tostring(self:DayID()), self.StripColor(self.FormatSigned(self:TodayEarned())),
        p.quota and self.FormatGold(p.quota) or "no quota", tostring(self:WeekID()), self.StripColor(self.FormatSigned(self:WeekEarned())),
        p.weekQuota and self.FormatGold(p.weekQuota) or "no quota"))
    print(string.format("  Averages: 7d %s/day, 30d %s/day, since start %s/day", self.FormatGold(p.avg7), self.FormatGold(p.avg30), self.FormatGold(p.avgGoal)))
    print("  " .. self.StripColor(self:StatusText(p)))
    print("  Style:", self.Style and self.Style.mode or "undecided", self.Style and self.Style.IsSkinned() and "(EllesmereUI skin)" or "")
    local _, _, shopOpen = self:SplashPending()
    print(string.format("  Splash: %s, level 1 from %s, in the shops %q%s", self.db.splash.enabled and "on" or "off",
        self.FormatGold(self:SplashThreshold()), self.db.splash.shops or "quiet", shopOpen and ("; open now: " .. shopOpen) or ""))
    for _, c in ipairs(self:SortedCharacters()) do
        print(string.format("    %-24s %14s  %s%s", c.key, self.FormatGold(c.money), c.source or "?", c.include == false and "  (excluded)" or ""))
    end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local HELP = {
    "  /gg                     open GoldGoal (in EllesmereUI's panel when it is there)",
    "  /gg window              the GoldGoal window itself",
    "  /gg bar                 show or hide the on-screen bar",
    "  /gg lock                lock or unlock the bar",
    "  /gg splash [gold]       preview the gold splash (at that amount)",
    "  /gg splash log          what came in this session and what the splash did with it",
    "  /gg splash profit       preview a sale's profit splash",
    "  /gg target <n|mount|set|ladder>   one amount, or a preset ladder of tiers",
    "  /gg tiers 5m Mount, 7m Mount + vendors, 10m Buffer   your own tiers",
    "  /gg tier <n>            pace towards tier n",
    "  /gg deadline <YYYY-MM-DD | <n>d | season | expansion>",
    "  /gg options             open settings",
    "  /gg eui                 open the GoldGoal page in EllesmereUI's options",
    "  /gg status              print what the addon knows",
    "  /gg crafting            the crafting stock readings this session (CraftSimPL)",
    "  /gg reset goal|chars|all",
    "  /gg undo                put the history back after a new goal was started by mistake",
    "  /gg debug               toggle debug output",
}

local function ResetCommand(what)
    if what == "goal" then
        ns:StartNewGoal()
        ns:Print("New goal started: the history begins now.")
    elseif what == "chars" then
        ns:ForgetAllCharacters()
        ns:Print("Character list cleared and re-read.")
    elseif what == "all" then
        wipe(GoldGoalDB)
        LoadSavedVariables()
        ns:Print("All settings reset. Reload the UI (/reload) to apply cleanly.")
    else
        ns:Print("Usage: /gg reset goal | chars | all")
    end
end

SLASH_GOLDGOAL1 = "/gg"
SLASH_GOLDGOAL2 = "/goldgoal"
SlashCmdList.GOLDGOAL = function(msg)
    local raw = strtrim(msg or "")
    local cmd, rest = raw:lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "toggle" then
        ns:ToggleWindow()
    elseif cmd == "window" then
        ns:ToggleWindowFrame()
    elseif cmd == "show" then
        ns:ShowWindow()
    elseif cmd == "hide" then
        ns:HideWindow()
    elseif cmd == "bar" then
        ns:SetBarShown(not ns.db.bar.shown)
        ns:Print("Bar", ns.db.bar.shown and "shown." or "hidden.")
    elseif cmd == "lock" then
        ns:SetBarLocked(not ns.db.bar.locked)
        ns:Print("Bar", ns.db.bar.locked and "locked. Shift-drag moves it." or "unlocked: drag it where you like.")
    elseif cmd == "splash" then
        local copper = ns.ParseGold(rest)
        if rest == "log" then ns:PrintSplashLog()
        elseif rest == "profit" then ns:PreviewProfitSplash()
        elseif copper then ns:ShowSplash(copper)
        else ns:PreviewSplash(3) end
    elseif cmd == "target" then
        if ns.TIER_PRESETS[rest] then
            ns:SetTargetPreset(rest)
            ns:Print("Tiers: " .. ns:TiersText() .. ". Pacing towards " .. ns:PacedTier().name .. ".")
        elseif ns.ParseGold(rest) then
            ns:SetTarget(ns.ParseGold(rest), "custom")
            ns:Print("Target set to " .. ns.FormatGold(ns.db.target) .. ".")
        else
            ns:Print("Usage: /gg target <gold | mount | set | ladder> (e.g. 5000000, 5m, 4.5m)")
        end
    elseif cmd == "tiers" then
        local list = ns.ParseTiers(raw:match("^%S+%s*(.-)$") or "")
        if list and ns:SetTiers(list, "custom") then
            ns:Print("Tiers: " .. ns:TiersText() .. ". Pacing towards " .. ns:PacedTier().name .. ".")
        else
            ns:Print("Usage: /gg tiers 5m Mount, 7m Mount + vendors, 10m Buffer (up to " .. ns.MAX_TIERS .. ")")
        end
    elseif cmd == "tier" then
        local i = tonumber(rest)
        if i and ns:SetTierIndex(i) then
            ns:Print("Pacing towards " .. ns:PacedTier().name .. " (" .. ns.FormatGold(ns.db.target) .. ").")
        else
            ns:Print("Usage: /gg tier <1-" .. #ns.db.tiers .. ">")
        end
    elseif cmd == "deadline" then
        if ns:SetDeadlineText(rest) then
            ns:Print("Deadline: " .. ns:DeadlineText(true) .. ", " .. tostring(ns:DaysLeft()) .. " day(s) left.")
        else
            ns:Print("Usage: /gg deadline <YYYY-MM-DD | <n>d | season | expansion>")
        end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        if not (ns.OpenEUIOptions and ns:OpenEUIOptions()) then ns:OpenOptions() end
    elseif cmd == "eui" then
        if not ns:OpenEUIOptions() then ns:Print("EllesmereUI is not taking the page; the window has everything (/gg window).") end
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("Debug output", ns.db.debug and "enabled" or "disabled")
    elseif cmd == "status" then
        ns:PrintStatus()
    elseif cmd == "crafting" then
        ns:PrintCraftingLog()
    elseif cmd == "reset" then
        ResetCommand(rest)
    elseif cmd == "undo" then
        if ns:UndoNewGoal() then
            ns:Print("History restored from before the last new goal.")
        else
            ns:Print("Nothing to undo: no new goal has been started since the last undo.")
        end
    else
        ns:Print("Commands:")
        for _, line in ipairs(HELP) do print(line) end
    end
end

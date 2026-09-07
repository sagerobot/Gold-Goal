-- Headless harness: stubs enough of the WoW API to load GoldGoal under
-- plain Lua 5.1 and exercise its logic. Run from the repo root:
--   lua tests/harness.lua
-- The clock is fake: NOW is 2026-09-05 10:00 UTC (a Saturday), the daily
-- reset is at 15:00 UTC and the weekly reset Tuesday 15:00 UTC, as on US
-- realms. Advance(seconds) moves the clock and rolls the resets forward.
local ROOT = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local ADDON_DIR = ROOT .. "/GoldGoal/"

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local function near(a, b, tol)
    return a and b and math.abs(a - b) <= (tol or 1)
end

-------------------------------------------------------------------------------
-- Generic widget stub: unknown method-shaped keys (SetX, GetX, IsX, ...) are
-- no-ops returning nil; any other key (regions such as .Text) is nil.
-------------------------------------------------------------------------------
local Widget = {}
local METHOD_PREFIXES = { "Set", "Get", "Is", "Register", "Unregister", "Enable", "Disable", "Hook",
    "Clear", "Show", "Hide", "Create", "Start", "Stop", "Add", "Remove", "Num", "Update", "Refresh",
    "Apply", "Play", "Raise", "Lower", "Can", "Has" }
Widget.__index = function(t, k)
    local v = rawget(Widget, k)
    if v ~= nil then return v end
    if type(k) ~= "string" then return nil end
    for _, p in ipairs(METHOD_PREFIXES) do
        if k:sub(1, #p) == p then
            local f = function() end
            rawset(t, k, f)
            return f
        end
    end
    return nil
end
local function NewWidget(kind, name, parent)
    local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {}, _points = {} }, Widget)
    if name then _G[name] = w end
    return w
end
function Widget:SetScript(ev, fn) self._scripts[ev] = fn end
function Widget:HookScript(ev, fn)
    local old = self._scripts[ev]
    self._scripts[ev] = function(...) if old then old(...) end fn(...) end
end
function Widget:GetScript(ev) return self._scripts[ev] end
function Widget:GetParent() return self._parent end
function Widget:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:IsMouseOver() return false end
function Widget:HasFocus() return false end
function Widget:GetHeight() return self._h or 400 end
function Widget:GetWidth() return self._w or 300 end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetHeight(h) self._h = h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
    self._points[#self._points + 1] = { point, rel, relPoint, x, y }
end
function Widget:ClearAllPoints() self._points = {} end
function Widget:GetPoint(i)
    local p = self._points[i or 1]
    if not p then return "CENTER", nil, "CENTER", 0, 0 end
    return p[1], p[2], p[3], p[4], p[5]
end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return 1 end
function Widget:GetRegions() end
function Widget:CreateFontString() return NewWidget("FontString", nil, self) end
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:GetFontString() return NewWidget("FontString", nil, self) end
function Widget:GetStringWidth() return 40 end
function Widget:GetChecked() return self._checked end
function Widget:SetChecked(v) self._checked = v end
function Widget:Click(button) if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end
function Widget:RegisterEvent(ev) self._events = self._events or {}; self._events[ev] = true end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetValue(v) self._value = v end
function Widget:GetValue() return self._value end
function Widget:SetAlpha(a) self._alpha = a end
function Widget:GetAlpha() return self._alpha or 1 end
function Widget:CreateAnimationGroup() return NewWidget("AnimationGroup", nil, self) end
function Widget:CreateAnimation(kind) return NewWidget(kind or "Animation", nil, self) end

-------------------------------------------------------------------------------
-- Globals
-------------------------------------------------------------------------------
_G.CreateFrame = function(kind, name, parent, template) return NewWidget(kind, name, parent) end
_G.UIParent = NewWidget("Frame", "UIParent")
_G.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
function GameTooltip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = tostring(l) .. "  " .. tostring(r) end
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.geterrorhandler = function() return function(err) print("  ERROR " .. tostring(err)); failures = failures + 1 end end
_G.hooksecurefunc = function() end
_G.securecallfunction = function(fn, ...) return fn(...) end
_G.strmatch = string.match
_G.IN_COMBAT = false
_G.InCombatLockdown = function() return IN_COMBAT end
_G.IN_INSTANCE, _G.INSTANCE_TYPE, _G.IN_GROUP, _G.IN_MPLUS = false, "none", false, false
_G.IsInInstance = function() return IN_INSTANCE, INSTANCE_TYPE end
_G.IsInGroup = function() return IN_GROUP end
_G.C_ChallengeMode = { IsChallengeModeActive = function() return IN_MPLUS end }
_G.GetInstanceInfo = function() return "Test", INSTANCE_TYPE, IN_MPLUS and 8 or 1 end
_G.PlaySound = function() end
_G.SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 120, UI_EPICLOOT_TOAST = 31578, UI_LEGENDARY_LOOT_TOAST = 63971 }
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
_G.IsShiftKeyDown = function() return false end
_G.HideUIPanel = function() end
_G.Settings = nil
_G.SlashCmdList = {}
_G.issecretvalue = function() return false end
_G.C_Texture = { GetAtlasInfo = function() return nil end }
_G.ScrollUtil = { InitScrollFrameWithScrollBar = function() end }
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
_G.Enum = { BankType = { Account = 2 } }
_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitName = function() return "Erunak", nil end
_G.GetRealmName = function() return "Test Realm" end
_G.GetNormalizedRealmName = function() return "TestRealm" end

-- the clock
local DAY = 86400
local NOW = 1788566400 + 10 * 3600            -- 2026-09-05 10:00 UTC, a Saturday
local DAILY_RESET = 1788566400 + 15 * 3600    -- 15:00 UTC
local WEEKLY_RESET = 1788566400 + 3 * DAY + 15 * 3600 -- Tuesday 15:00 UTC
_G.time = function(t) if t then return os.time(t) end return NOW end
_G.GetTime = function() return NOW end
_G.date = function(fmt, t) return os.date(fmt, t or NOW) end
_G.C_DateAndTime = {
    GetSecondsUntilDailyReset = function() return DAILY_RESET - NOW end,
    GetSecondsUntilWeeklyReset = function() return WEEKLY_RESET - NOW end,
}
local function Advance(secs)
    NOW = NOW + secs
    while DAILY_RESET <= NOW do DAILY_RESET = DAILY_RESET + DAY end
    while WEEKLY_RESET <= NOW do WEEKLY_RESET = WEEKLY_RESET + 7 * DAY end
end

-- timers: collected and run manually
local timers, tickers = {}, {}
_G.C_Timer = {
    After = function(delay, fn) table.insert(timers, { t = delay, fn = fn }) end,
    NewTicker = function(delay, fn) table.insert(tickers, fn) end,
}
local function RunTimers()
    local guard = 0
    while #timers > 0 and guard < 200 do
        guard = guard + 1
        local list = timers
        timers = {}
        for _, t in ipairs(list) do t.fn() end
    end
end
local function Tick() for _, fn in ipairs(tickers) do fn() end end

-- money
local C = 10000
_G.MONEY = 100000 * C
_G.GetMoney = function() return MONEY end
_G.WARBAND_LOCKED, _G.WARBAND_MONEY = true, 0
_G.C_PlayerInfo = { HasAccountInventoryLock = function() return not WARBAND_LOCKED end }
_G.C_Bank = { FetchDepositedMoney = function() return WARBAND_MONEY end }

-- a fake Syndicator: the current character, an alt and the warband bank
_G.SYN = {
    ["Erunak-TestRealm"] = { money = 99999 * C, details = { character = "Erunak", realm = "Test Realm", className = "WARRIOR" } },
    ["Alt-TestRealm"] = { money = 250000 * C, details = { character = "Alt", realm = "Test Realm", className = "MAGE" } },
}
_G.Syndicator = { API = {
    IsReady = function() return true end,
    GetAllCharacters = function() local t = {} for k in pairs(SYN) do t[#t + 1] = k end return t end,
    GetCharacter = function(name) return SYN[name] end,
    GetWarband = function() return { money = 50000 * C } end,
} }

-- a fake EllesmereUI options panel: the sidebar tables, RegisterModule, and a
-- widget factory that records every control with its get/set so the pages
-- can be driven; no RegisterSkin, so the style stays flat
_G.EUI_MODULES, _G.EUI_CONTROLS = {}, {}
_G.EllesmereUI = {
    ADDON_GROUPS = { { key = "qol", label = "QoL Addons", members = { "EllesmereUIQoL" } } },
    _addonInfoByFolder = {}, _syncExempt = {}, CONTENT_PAD = 20,
    RegisterModule = function(self, folder, config) EUI_MODULES[folder] = config end,
    L = function(s) return s end,
    RefreshPage = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    RegisterOnShow = function(self, fn) self.onShow = fn end,
    -- selecting a module builds its first page, as the real panel does
    SelectModule = function(self, f)
        self.selected = f
        local c = EUI_MODULES[f]
        if c then local p = NewWidget("Frame"); p:SetWidth(700); c.buildPage(c.pages[1], p, -6) end
    end,
    Widgets = {},
}
do
    local Wd = EllesmereUI.Widgets
    local function rec(kind, text, get, set)
        EUI_CONTROLS[#EUI_CONTROLS + 1] = { kind = kind, text = text, get = get, set = set }
        return NewWidget("Frame"), 50
    end
    function Wd:SectionHeader(parent, text) return rec("header", text) end
    function Wd:Toggle(parent, text, y, get, set) return rec("toggle", text, get, set) end
    function Wd:Slider(parent, text, y, min, max, step, get, set) return rec("slider", text, get, set) end
    function Wd:Dropdown(parent, text, y, values, get, set) return rec("dropdown", text, get, set) end
    function Wd:ColorPicker(parent, text, y, get, set) return rec("color", text, get, set) end
    function Wd:Button(parent, text, y, onClick) return rec("button", text, nil, onClick) end
    function Wd:WideDualButton(parent, t1, t2, y, f1, f2) rec("button", t1, nil, f1); return rec("button", t2, nil, f2) end
    function Wd:WideTripleButton(parent, t1, t2, t3, y, f1, f2, f3) rec("button", t1, nil, f1); rec("button", t2, nil, f2); return rec("button", t3, nil, f3) end
    function Wd:Spacer(parent, y, h) return NewWidget("Frame"), h or 16 end
end

-- a fake CraftSimPL working-capital API (nothing reported until WC is set)
_G.WC = nil
_G.WC_LISTENER = nil
_G.CraftSimPL = { API = {
    GetWorkingCapital = function() return WC end,
    RegisterWorkingCapitalListener = function(_, fn) WC_LISTENER = fn end,
} }

-------------------------------------------------------------------------------
-- Load the addon
-------------------------------------------------------------------------------
local ns = {}
local eventFrames = {}
for line in io.lines(ADDON_DIR .. "GoldGoal.toc") do
    local f = line:match("^([^#%s].-%.lua)%s*$")
    if f then
        f = f:gsub("\\", "/")
        local chunk, err = loadfile(ADDON_DIR .. f)
        if not chunk then error(err) end
        chunk("GoldGoal", ns)
    end
end
local function Fire(event, ...)
    local h = ns.eventFrame:GetScript("OnEvent")
    h(ns.eventFrame, event, ...)
end

print("Formatting")
check(ns.FormatGold(1234567 * C) == "1,234,567g", "FormatGold with commas")
check(ns.FormatGold(-1200 * C) == "-1,200g", "FormatGold negative")
check(ns.FormatGoldShort(3214500 * C) == "3.21M", "short: millions " .. ns.FormatGoldShort(3214500 * C))
check(ns.FormatGoldShort(52300 * C) == "52k", "short: thousands " .. ns.FormatGoldShort(52300 * C))
check(ns.FormatGoldShort(123760 * C) == "124k", "short: rounds thousands")
check(ns.FormatGoldShort(8450 * C) == "8,450g", "short: under 10k stays exact")
check(ns.FormatSigned(8450 * C):find("+8,450g", 1, true) and ns.FormatSigned(8450 * C):find(ns.GREEN_HEX, 1, true), "signed positive is green with a plus")
check(ns.FormatSigned(-1200 * C):find("-1,200g", 1, true) and ns.FormatSigned(-1200 * C):find(ns.RED_HEX, 1, true), "signed negative is red")
check(ns.ParseGold("5,000,000") == 5000000 * C, "parse 5,000,000")
check(ns.ParseGold("5m") == 5000000 * C and ns.ParseGold("4.5m") == 4500000 * C, "parse 5m and 4.5m")
check(ns.ParseGold("500k") == 500000 * C and ns.ParseGold("12,000g") == 12000 * C, "parse 500k and 12,000g")
check(ns.ParseGold("abc") == nil and ns.ParseGold("0") == nil and ns.ParseGold("") == nil, "parse rejects junk and zero")
check(ns.Percent(64, 100) == 64 and ns.Percent(1, 0) == nil, "Percent")
check(ns.Countdown(3 * DAY + 4 * 3600 + 100) == "3d 4h" and ns.Countdown(4 * 3600 + 12 * 60) == "4h 12m" and ns.Countdown(600) == "10m", "Countdown")

print("Login")
-- a saved file from before the tier ladder: migrated to it, and to the expansion deadline
_G.GoldGoalDB = { targetPreset = "mount", target = 5000000 * C, deadlinePreset = "season", deadline = 123 }
Fire("ADDON_LOADED", "GoldGoal")
check(ns.db and ns.db.target == 5000000 * C and ns.db.targetPreset == "ladder" and #ns.db.tiers == 3 and ns.db.tierIndex == 1 and ns.db.schema == 3, "old settings migrated to the 5/7/10 ladder, pacing the mount")
check(ns.db.deadlinePreset == "expansion" and ns.db.deadline ~= 123 and ns:DeadlineText(true) == "Aug 01, 2027", "season guess became the expansion-end guess: " .. tostring(ns:DeadlineText(true)))
check(ns.db.deadlineGuess == ns.EXPANSION_END_GUESS, "the guess used is remembered")
Fire("PLAYER_LOGIN")
RunTimers()
check(ns.Style.mode == "flat", "flat style without EllesmereUI")
local me = ns:CharKey()
check(me == "Erunak-TestRealm", "character key " .. me)
check(ns.db.chars[me] and ns.db.chars[me].money == 100000 * C and ns.db.chars[me].source == "live", "this character recorded live")
check(ns.db.chars["Alt-TestRealm"] and ns.db.chars["Alt-TestRealm"].source == "syndicator" and ns.db.chars["Alt-TestRealm"].class == "MAGE", "alt filled in from Syndicator")
check(ns.db.warband.money == 50000 * C and ns.db.warband.source == "syndicator", "warband bank from Syndicator while locked")
check(ns:TotalWealth() == 400000 * C, "total pools everything: " .. ns.FormatGold(ns:TotalWealth()))
check(ns:TodayEarned() == 0 and ns:WeekEarned() == 0, "first sight and Syndicator figures are not earnings")
local D0 = ns:DayID()
check(D0 == math.floor((DAILY_RESET + 1800) / DAY), "day id is the reset's UTC day number")
check(ns:WeekID() == math.floor((WEEKLY_RESET + 1800) / DAY), "week id is the weekly reset's UTC day number")
check(ns.db.goalStartDay == D0, "goal starts today")
local left = ns:DaysLeft()
local gy, gm, gd = ns.EXPANSION_END_GUESS:match("(%d+)-(%d+)-(%d+)")
local expectedLeft = ns:DayIDAt(os.time({ year = tonumber(gy), month = tonumber(gm), day = tonumber(gd), hour = 12 })) - D0 + 1
check(left == expectedLeft and left >= 330 and left <= 332, "days left to the expansion guess (game days through the one holding local noon): " .. tostring(left))
check(near(ns:DailyQuota(), ns:Remaining(400000 * C) / left, 1), "today's quota = remaining at day start / days left")
check(ns.db.days[D0].week == ns:WeekID(), "day records its week")

print("Live earnings")
MONEY = 110000 * C
Fire("PLAYER_MONEY")
check(ns:TotalWealth() == 410000 * C, "total follows the live figure")
check(ns:TodayEarned() == 10000 * C and ns:WeekEarned() == 10000 * C, "a live change counts for today and this week")
local bt = ns.StripColor(ns:BarText())
check(bt:match("^%+10k / %d+k  %d+%%$"), "bar text: " .. bt)

print("Baselines")
WARBAND_LOCKED, WARBAND_MONEY = false, 80000 * C
Fire("ACCOUNT_MONEY")
check(ns.db.warband.money == 80000 * C and ns.db.warband.source == "live", "warband read live once unlocked")
check(ns:TotalWealth() == 440000 * C and ns:TodayEarned() == 10000 * C, "first live warband read shifts the baseline, not the earnings")
WARBAND_MONEY = 90000 * C
Fire("ACCOUNT_MONEY")
check(ns:TodayEarned() == 20000 * C, "a live warband change is income (a sale paid into it)")
WARBAND_MONEY = 80000 * C
Fire("ACCOUNT_MONEY")
check(ns:TodayEarned() == 10000 * C, "and a withdrawal to a character nets out")
MONEY = 120000 * C -- the withdrawal arrived
Fire("PLAYER_MONEY")
check(ns:TodayEarned() == 20000 * C and ns:TotalWealth() == 450000 * C, "transfer between the bank and a character is neutral overall")
ns:SetCharacterIncluded("Alt-TestRealm", false)
check(ns:TotalWealth() == 200000 * C and ns:TodayEarned() == 20000 * C, "excluding a character drops the total, not the earnings")
ns:SetCharacterIncluded("Alt-TestRealm", true)
check(ns:TotalWealth() == 450000 * C and ns:TodayEarned() == 20000 * C, "including it again restores the total")
ns:ForgetCharacter("Alt-TestRealm")
check(ns.db.chars["Alt-TestRealm"] == nil and ns:TotalWealth() == 200000 * C and ns:TodayEarned() == 20000 * C, "forgetting a character is not spending")
check(ns:MergeSyndicator() == 0 and ns.db.chars["Alt-TestRealm"] == nil, "Syndicator does not bring a forgotten character back")
ns:ForgetCharacter(me)
check(ns.db.chars[me], "the logged-in character cannot be forgotten")
ns:ForgetAllCharacters()
check(ns.db.chars["Alt-TestRealm"] and ns:TotalWealth() == 450000 * C and ns:TodayEarned() == 20000 * C, "forget all re-reads Syndicator without touching the earnings")
SYN["Alt-TestRealm"].money = 260000 * C
ns:MergeSyndicator()
check(ns:TotalWealth() == 460000 * C and ns:TodayEarned() == 20000 * C, "a newer Syndicator figure for an alt is a baseline shift")
check(ns.db.chars[me].money == 120000 * C, "Syndicator never overwrites a live figure")
local n = 0
for _ in pairs(ns.db.chars) do n = n + 1 end
check(n == 2 and ns:CountCharacters() == 2, "two characters known")

print("Quotas")
check(ns:SetDeadlineDays(10), "deadline in 10 days")
check(ns:DaysLeft() == 10 and ns.db.deadlinePreset == "days", "days left = 10")
local dayStart = ns.db.days[D0].start
check(dayStart == 440000 * C, "day started at total minus earnings: " .. ns.FormatGold(dayStart))
check(near(ns:DailyQuota(), (5000000 - 440000) * C / 10), "today's quota recomputed on the deadline change: " .. ns.FormatGold(ns:DailyQuota()))
local weekDays = math.min(10, math.ceil((WEEKLY_RESET - NOW) / DAY))
check(near(ns:WeeklyQuota(), ns:DailyQuota() * weekDays) and ns.db.weeks[ns:WeekID()].days == weekDays, "weekly quota = daily quota x days of this week left (" .. weekDays .. ")")
check(near(ns:TomorrowQuota(), (5000000 - 460000) * C / 9), "tomorrow's quota uses what is left now over the days after today")
MONEY = MONEY + 1000000 * C
Fire("PLAYER_MONEY")
check(ns:TodayEarned() == 1020000 * C, "a big farm day")
check(ns:TomorrowQuota() < ns:DailyQuota(), "the big day lowers tomorrow's quota: " .. ns.FormatGold(ns:TomorrowQuota()) .. " < " .. ns.FormatGold(ns:DailyQuota()))
local expectedTomorrow = ns:TomorrowQuota()
Advance(6 * 3600) -- past the 15:00 reset
MONEY = MONEY + 5000 * C
Fire("PLAYER_MONEY") -- the first thing seen on the new day
check(ns:DayID() == D0 + 1, "the day turned")
check(ns:TodayEarned() == 5000 * C, "earnings straight after the reset land on the new day")
check(ns:Earned(D0) == 1020000 * C, "yesterday keeps its earnings")
check(ns:DaysLeft() == 9, "one day fewer")
check(near(ns:DailyQuota(), expectedTomorrow), "the new day's quota is yesterday's tomorrow figure")
check(near(ns:WeekEarned(), 1025000 * C), "the week carries on across the day")
Advance(7 * DAY) -- an idle week
Tick()
check(ns:DayID() == D0 + 8 and ns:DaysLeft() == 2, "a week later: two days left")
check(ns:TodayEarned() == 0 and ns:WeekEarned() == 0, "nothing earned in the idle week; a new week began")
check(ns:DailyQuota() > expectedTomorrow, "the idle week raises the quota: " .. ns.FormatGold(ns:DailyQuota()))
check(near(ns:DailyQuota(), ns:Remaining() / 2), "quota = remaining / 2")
local recent = ns:RecentWeeks(2)
check(recent[1].earned == 1025000 * C and recent[2].earned == 0, "last week earned, this week nothing")
check(near(ns:Average(7), 5000 * C / 7), "7-day average over the seven days before today: " .. ns.FormatGold(ns:Average(7)))
check(near(ns:Average(30), 1025000 * C / 8), "30-day average is bounded by the goal start")
check(near(ns:AverageSinceStart(), 1025000 * C / 8), "average since the goal started")
check(ns:SavedSinceStart() == 1025000 * C, "saved since start sums the days")
local days = ns:RecentDays(30)
check(#days == 30 and days[30].id == D0 + 8 and days[22].earned == 1020000 * C and days[23].earned == 5000 * C and not days[25].seen, "recent days list, oldest first, gaps unseen")

print("Projection")
local p = ns:Projection()
check(p.status == "behind" and p.finish7 > p.deadline, "far behind at 714g/day: " .. ns.StripColor(ns:StatusText(p)))
check(ns.StripColor(ns:StatusText(p)):find("^Behind on Mount:"), "status text says Behind on the paced tier")
ns:SetTarget(1000000 * C, "custom")
p = ns:Projection()
check(p.status == "reached" and p.remaining == 0 and ns:DailyQuota() == 0, "target under the total: reached, quota 0")
check(ns.StripColor(ns:StatusText(p)) == "Goal reached!", "status text says reached")
ns:SetTargetPreset("mount")
check(ns.db.target == 5000000 * C and ns.db.targetPreset == "mount", "back to the mount preset")
ns:StartNewGoal()
check(ns.db.goalStartDay == ns:DayID() and ns:TodayEarned() == 0 and ns:SavedSinceStart() == 0, "new goal: history cleared, nothing earned")
p = ns:Projection()
check(p.status == "stalled" and p.finish7 == nil, "no earnings yet: stalled")
ns:SetDeadlineDays(1000)
MONEY = MONEY + 100000 * C
Fire("PLAYER_MONEY")
p = ns:Projection()
check(near(p.avg7, 100000 * C), "with no completed day, today's earnings stand in for the average")
check(p.status == "ahead" and p.slack > 0, "ahead of a distant deadline: " .. ns.StripColor(ns:StatusText(p)))
check(ns.StripColor(ns:StatusText(p)):find("^On pace:"), "status text says On pace")
ns.db.deadline = nil
ns:RefreshQuotas()
p = ns:Projection()
check(p.status == "pace" and p.daysLeft == nil and p.quota == nil, "without a deadline: a pace line and no quota")
check(ns.StripColor(ns:BarText()):find("no deadline", 1, true), "bar says no deadline")
check(ns:SetDeadlineDate("2026-12-15", "season") and ns.db.deadlinePreset == "season", "season preset again")
check(not ns:SetDeadlineDate("2026-13-01") and not ns:SetDeadlineDays(0) and not ns:SetDeadlineText("nonsense"), "bad deadlines rejected")
check(ns:SetDeadlineText("30d") and ns:DaysLeft() == 30, "/gg deadline 30d")
check(ns:SetDeadlineText("2026-12-15") and ns:DeadlineText(true) == "Dec 15, 2026" and ns.db.deadlinePreset == "date", "/gg deadline <date>")
check(ns:SetDeadlineText("season") and ns.db.deadlinePreset == "season", "/gg deadline season")
GameTooltip:SetOwner()
ns:PaceTooltip(GameTooltip)
local joined = ns.StripColor(table.concat(GameTooltip.lines, "\n"))
check(joined:find("Target  5,000,000g", 1, true) and joined:find("7%-day average") and joined:find("Today  "), "pace tooltip lists the target, today and the averages")

ns:SetDeadlineDate("2026-12-15")

print("Window")
ns:ShowWindow()
check(GoldGoalFrame and GoldGoalFrame:IsShown() and ns:CurrentPage() == "goal", "window opens on the Goal page")
local goal = GoldGoalFrame.Pages.goal
check(goal.TargetBar.fraction > 0 and goal.TargetBar.Text:GetText():find("5,000,000g", 1, true), "target bar filled: " .. ns.StripColor(goal.TargetBar.Text:GetText()))
check(ns.StripColor(goal.Today.Bar.Text:GetText()):find("^%+100,000g / "), "today bar: " .. ns.StripColor(goal.Today.Bar.Text:GetText()))
check(goal.Stats.deadline.Value:GetText() == "Dec 15, 2026", "deadline stat")
ns:ShowPage("chars")
local P = ns.UI.Pools
local shownChars = 0
for _, r in ipairs(P.charRows) do if r:IsShown() then shownChars = shownChars + 1 end end
check(shownChars == 3 and P.charRows[1].warband and P.charRows[2].char, "Characters: warband row plus two characters")
check(ns.StripColor(P.charRows[2].Name:GetText()):find("Erunak") and P.charRows[2].Check:GetChecked(), "richest first, this character ticked")
P.charRows[3].Check:SetChecked(false)
P.charRows[3].Check:Click()
check(ns.db.chars["Alt-TestRealm"].include == false and ns:TotalWealth() == ns.db.chars[me].money + 80000 * C, "unticking a row excludes the character")
P.charRows[3].Check:SetChecked(true)
P.charRows[3].Check:Click()
check(ns.db.chars["Alt-TestRealm"].include == true, "ticking it back")
P.charRows[3]:GetScript("OnEnter")(P.charRows[3])
check(table.concat(GameTooltip.lines, "\n"):find("Right%-click to forget"), "alt tooltip offers to forget")
check(ns.StripColor(GoldGoalFrame.Pages.chars.Footer:GetText()):find("1 from Syndicator", 1, true), "footer counts Syndicator figures")
ns:ShowPage("history")
local shownDays = 0
for _, r in ipairs(P.dayRows) do if r:IsShown() then shownDays = shownDays + 1 end end
check(shownDays == 1 and P.dayRows[1].Date:GetText() == "Today", "History: only today since the new goal")
ns.UI.historyMode = "weeks"
ns:RefreshWindow()
check(P.dayRows[1].Date:GetText() == "This week", "History: weeks view")
ns.UI.historyMode = "days"
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "settings", "cog opens Settings")
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "history", "cog again returns to the last tab")
ns:HideWindow()
check(not ns:IsWindowShown(), "window hidden")
ns:ShowPage("settings")
ns:ShowWindow()
ns:RefreshSettings()

print("Bar and broker")
check(ns.Bar and ns.Bar:IsShown(), "bar shown by default")
ns:SetBarShown(false)
check(not ns.Bar:IsShown() and ns.db.bar.shown == false, "bar hidden")
ns:SetBarShown(true)
ns:SetBarMode("weekly")
check(ns.Bar.Label:GetText() == "Week", "bar in weekly mode")
ns.Bar:GetScript("OnClick")(ns.Bar, "RightButton")
check(ns.db.bar.mode == "daily" and ns.Bar.Label:GetText() == "Today", "right-click flips back to daily")
check(ns.brokerObject and ns.brokerObject.text:match("^[%d,%.]+[kMg]* / [%d,%.]+[kMg]* %(%d+%%%)$"), "broker text: " .. tostring(ns.brokerObject and ns.brokerObject.text))
ns:CycleBrokerMode()
check(ns.db.broker.mode == "weekly", "broker cycles to weekly")
ns:CycleBrokerMode()
check(ns.db.broker.mode == "total" and ns.brokerObject.text:match("^[%d%.]+[kM]* / 5%.00M %(%d+%%%)$"), "broker total: " .. ns.brokerObject.text)
ns:CycleBrokerMode()
check(ns.db.broker.mode == "daily", "broker cycles round to daily")

print("Slash commands")
SlashCmdList.GOLDGOAL("target 7m")
check(ns.db.target == 7000000 * C and ns.db.targetPreset == "custom", "/gg target 7m")
SlashCmdList.GOLDGOAL("target set")
check(ns.db.targetPreset == "set" and #ns.db.tiers == 2 and ns.db.target == 5000000 * C, "/gg target set: two tiers, pacing the first")
SlashCmdList.GOLDGOAL("target mount")
check(ns.db.targetPreset == "mount", "/gg target mount")
SlashCmdList.GOLDGOAL("deadline 45d")
check(ns:DaysLeft() == 45, "/gg deadline 45d")
SlashCmdList.GOLDGOAL("bar")
check(ns.db.bar.shown == false, "/gg bar hides")
SlashCmdList.GOLDGOAL("bar")
SlashCmdList.GOLDGOAL("lock")
check(ns.db.bar.locked == true, "/gg lock")
SlashCmdList.GOLDGOAL("window")
check(not ns:IsWindowShown(), "/gg window toggles the window closed")
print("Crafting stock (CraftSimPL)")
check(WC_LISTENER ~= nil and ns:HasCraftingAPI() and not ns:HasCraftingData(), "listener registered, nothing reported yet")
SlashCmdList.GOLDGOAL("target mount")
local liquidBefore, earnedBefore = ns:TotalWealth(), ns:TodayEarned()
WC = { apiVersion = 1, realmKey = "TestRealm", openBatches = 2, poolsAtCost = 100000 * C, stockAtCost = 300000 * C, estimated = false,
    listedNet = 250000 * C, presumedSoldNet = 0, restNet = 120000 * C, unpricedQty = 0, resetAt = 100 }
WC_LISTENER()
RunTimers()
check(ns:HasCraftingData() and ns:CraftingAtCost() == 400000 * C, "reagents and unsold crafts join the total at cost")
check(ns:TotalWealth() == liquidBefore + 400000 * C and ns:LiquidWealth() == liquidBefore, "total = gold + crafting at cost; liquid is gold alone")
check(ns:TodayEarned() == earnedBefore, "the first reading is a baseline shift, not income")
check(ns:CraftingProjected() == 370000 * C, "projected net summed for display")
MONEY = MONEY - 100000 * C
Fire("PLAYER_MONEY")
check(ns:TodayEarned() == earnedBefore - 100000 * C, "paying for reagents dips the day...")
WC.poolsAtCost = WC.poolsAtCost + 100000 * C
WC_LISTENER()
RunTimers()
check(ns:TodayEarned() == earnedBefore, "...until the pool grows by the same amount: buying reagents is not spending")
WC.stockAtCost = WC.stockAtCost - 20000 * C
WC_LISTENER()
RunTimers()
MONEY = MONEY + 30000 * C
Fire("PLAYER_MONEY")
check(ns:TodayEarned() == earnedBefore + 10000 * C, "a sale counts as its profit: 30k in, 20k of stock out")
local atCost = ns:CraftingAtCost()
ns:SetCountCrafting(false)
check(ns:CraftingAtCost() == 0 and ns:TotalWealth() == liquidBefore - 70000 * C and ns:TodayEarned() == earnedBefore + 10000 * C, "switching the stock off drops the total, not the earnings")
ns:SetCountCrafting(true)
check(ns:CraftingAtCost() == atCost and ns:TodayEarned() == earnedBefore + 10000 * C, "and back on")
WC.resetAt, WC.stockAtCost = 200, 0
WC_LISTENER()
RunTimers()
check(ns:CraftingAtCost() == 200000 * C and ns:TodayEarned() == earnedBefore + 10000 * C, "a CraftSimPL reset is not spending")
WC.estimated = true
WC_LISTENER()
RunTimers()
check(ns:CraftingEstimated(), "estimated costs flagged")
ns:SetTarget(ns:LiquidWealth() + 50000 * C, "custom")
p = ns:Projection()
check(p.status == "reached" and p.liquidShort == 50000 * C, "reached at cost but short in gold")
check(ns.StripColor(ns:StatusText(p)):find("^Goal reached at cost: sell 50,000g"), "status says how much stock to sell: " .. ns.StripColor(ns:StatusText(p)))
GameTooltip:SetOwner()
ns:PaceTooltip(GameTooltip)
check(ns.StripColor(table.concat(GameTooltip.lines, "\n")):find("in crafting, at cost  ~200,000g", 1, true), "pace tooltip shows the crafting line")
SlashCmdList.GOLDGOAL("target mount")
ns:ShowWindow()
ns:ShowPage("goal")
check(goal.TargetBar.Under:GetValue() > goal.TargetBar.Bar:GetValue(), "target bar: dimmed segment for the stock beyond the gold")
check(ns.StripColor(goal.TargetLine2:GetText()):find("crafting stock ~200,000g at cost", 1, true), "target line names the stock: " .. ns.StripColor(goal.TargetLine2:GetText()))
ns:ShowPage("chars")
check(P.charRows[2].crafting == "TestRealm" and ns.StripColor(P.charRows[2].Gold:GetText()) == "~200,000g", "Characters: crafting row after the warband bank")
P.charRows[2]:GetScript("OnEnter")(P.charRows[2])
check(table.concat(GameTooltip.lines, "\n"):find("Reagents %(cost pools%)"), "crafting row tooltip breaks the figure down")
P.charRows[2].Check:SetChecked(false)
P.charRows[2].Check:Click()
check(not ns:CountsCrafting() and ns:CraftingAtCost() == 0, "unticking the row stops counting the stock")
P.charRows[2].Check:SetChecked(true)
P.charRows[2].Check:Click()
check(ns:CountsCrafting(), "ticking it back")
ns:ForgetCraftingRealm("TestRealm")
check(not ns:HasCraftingData() and ns:TodayEarned() == earnedBefore + 10000 * C, "forgetting the realm is not spending")
WC_LISTENER()
RunTimers()
check(ns:CraftingAtCost() == 200000 * C and ns:TodayEarned() == earnedBefore + 10000 * C, "the next reading brings it back as a baseline")
check(ns.craftingLog and #ns.craftingLog >= 5 and ns.craftingLog[1].first and ns.craftingLog[1].baseline > 0, "readings are logged, the latest a first reading")
SlashCmdList.GOLDGOAL("crafting")
ns:HideWindow()

print("Tiers")
check(ns:SetTargetPreset("ladder") and #ns.db.tiers == 3 and ns.db.tierIndex == 1 and ns.db.target == 5000000 * C, "ladder preset: three tiers, pacing the mount")
local parsed = ns.ParseTiers("7m Mount + vendors, 5m Mount, 10m")
check(parsed and #parsed == 3 and parsed[1].name == "Mount + vendors" and parsed[3].name == "Tier 3", "tiers parsed with names, unnamed ones numbered")
check(ns.ParseTiers("abc") == nil and ns.ParseTiers("") == nil and ns.ParseTiers("1m a, 2m b, 3m c, 4m d, 5m e") == nil, "bad tier lists rejected")
check(ns:SetTiers(parsed, "custom") and ns.db.tiers[1].gold == 5000000 * C and ns.db.tiers[3].gold == 10000000 * C and ns.db.targetPreset == "custom", "tiers sorted cheapest first")
ns:SetTargetPreset("ladder")
p = ns:Projection()
check(#p.tiers == 3 and p.tier and p.tier.index == 1 and p.topGold == 10000000 * C, "projection carries every tier and the paced one")
check(p.tiers[1].remaining == 5000000 * C - p.total and near(p.tiers[1].need, p.tiers[1].remaining / p.daysLeft), "each tier has its own remaining and per-day need")
check(ns.StripColor(ns:StatusText(p)):find("Mount", 1, true), "status names the paced tier: " .. ns.StripColor(ns:StatusText(p)))
MONEY = MONEY + 5000000 * C
Fire("PLAYER_MONEY")
check(ns.db.tierIndex == 2 and ns.db.target == 7000000 * C, "banking the mount moves the pacing to the vendors")
p = ns:Projection()
check(p.tiers[1].reached and p.tiers[1].state == "reached" and not p.tiers[2].reached, "the first tier is reached, the second not")
check(ns.StripColor(ns:TierText(p.tiers[1])) == "reached" and ns.StripColor(ns:TierText(p.tiers[2])):find("^need "), "tier verdicts")
ns:SetTierIndex(1)
check(ns.db.tierIndex == 2, "a banked tier cannot be paced towards again")
check(ns:SetTierIndex(3) and ns.db.target == 10000000 * C and not ns:SetTierIndex(4), "pacing the buffer by hand; no fourth tier")
ns:SetTierIndex(2)
GameTooltip:SetOwner()
ns:PaceTooltip(GameTooltip)
joined = ns.StripColor(table.concat(GameTooltip.lines, "\n"))
check(joined:find("Mount + vendors  7,000,000g", 1, true) and joined:find("Buffer  10,000,000g", 1, true), "pace tooltip lists the tiers")
ns:ShowWindow()
ns:ShowPage("goal")
local shownTiers = 0
for _, r in ipairs(goal.TierRows) do if r:IsShown() then shownTiers = shownTiers + 1 end end
check(shownTiers == 3 and goal.TierRows[2].tier.paced and ns.StripColor(goal.TierRows[1].Verdict:GetText()) == "reached", "Goal page: a row per tier, the paced one marked")
check(#goal.TargetBar.tickFracs == 1 and near(goal.TargetBar.tickFracs[1], 5 / 7, 0.001), "pacing the vendors: the bar runs to 7M with a mark at 5M")
check(ns.StripColor(goal.TargetBar.Text:GetText()):find("/ 7,000,000g", 1, true), "bar text names the paced tier: " .. ns.StripColor(goal.TargetBar.Text:GetText()))
goal.TierRows[3]:GetScript("OnClick")(goal.TierRows[3])
check(ns.db.target == 10000000 * C and goal.TierRows[3].tier.paced, "clicking a tier row paces towards it")
check(#goal.TargetBar.tickFracs == 2 and near(goal.TargetBar.tickFracs[1], 0.5, 0.001) and near(goal.TargetBar.tickFracs[2], 0.7, 0.001), "pacing the buffer: marks at 5M and 7M of 10M")
local function rgb(r, g, b) return string.format("%.2f %.2f %.2f", r, g, b) end
check(rgb(ns.UI.GoalColor(0, 0.5, 0, 1, 1)) == rgb(0.85, 0.22, 0.22), "goal colour: red at nothing")
check(rgb(ns.UI.GoalColor(0.25, 0.5, 0, 1, 1)) == rgb(0.95, 0.80, 0.15), "yellow halfway to the hard goal")
check(rgb(ns.UI.GoalColor(0.5, 0.5, 0, 1, 1)) == rgb(0.25, 0.80, 0.35), "green at the hard goal")
check(rgb(ns.UI.GoalColor(0.5001, 0.5, 0, 1, 1)) == rgb(0.30, 0.55, 0.95), "blue just past it")
check(rgb(ns.UI.GoalColor(1, 0.5, 0, 1, 1)) == rgb(0, 1, 1), "the accent at the end")
check(rgb(ns.UI.GoalColor(1, 1, 0, 1, 1)) == rgb(0.25, 0.80, 0.35), "with the hard goal paced, the whole bar ends green")
local gc = goal.TargetBar.color
check(gc and gc[3] > 0.5 and gc[1] < 0.6, "at 66% of the buffer, past the 50% hard goal, the bar is in the blues: " .. rgb(gc[1], gc[2], gc[3]))
-- the tiers on the quota bars: a fresh 10M ladder puts the mount halfway along today's bar
local fake = { remaining = 10000000 * C, target = 10000000 * C, tiers = {
    { gold = 5000000 * C, remaining = 5000000 * C }, { gold = 7000000 * C, remaining = 7000000 * C }, { gold = 10000000 * C, remaining = 10000000 * C, paced = true } } }
local qt, qh = ns:QuotaTicks(fake)
check(#qt == 2 and near(qt[1], 0.5, 0.001) and near(qt[2], 0.7, 0.001) and near(qh, 0.5, 0.001), "quota marks at 50% and 70% of the day, the hard goal at 50%")
fake.remaining, fake.tiers[1].remaining, fake.tiers[2].remaining = 4000000 * C, 0, 1000000 * C
qt, qh = ns:QuotaTicks(fake)
check(#qt == 1 and near(qt[1], 0.25, 0.001) and qh == 0, "with the mount banked its mark is gone and the whole day is past the hard goal")
check(select(2, ns:QuotaTicks({ remaining = 0, target = 1, tiers = {} })) == 0, "nothing left: nothing to mark")
ns:RefreshBar()
check(ns.Bar.Progress.color and ns.Bar.Progress.tickFracs, "the on-screen bar carries the colour and the marks")
check(goal.Today.Bar.color and goal.Week.Bar.color, "so do the Today and This week bars")
ns:ShowPage("settings")
local settings = GoldGoalFrame.Pages.settings
local ged = settings.goalEditor
check(ns.StripColor(ged.PaceDrop.Text:GetText()):find("Buffer", 1, true) and ged.PresetTabs.selectedTabID == "ladder", "Settings shows the paced goal and the preset")
check(ged.rows[3]:IsShown() and not ged.rows[4]:IsShown() and ged.rows[3].Amount:GetText() == "10,000,000" and ns.StripColor(ged.rows[3].Mark:GetText()):find("quota aims here"), "the editor lists the three goals, the paced one marked")
ged.rows[2].Amount:SetText("8m")
ged.rows[2].Name:SetText("Vendors")
check(ged.Commit() and ns.db.tiers[2].gold == 8000000 * C and ns.db.tiers[2].name == "Vendors" and ns.db.targetPreset == "custom", "editing a row rewrites the goal")
ged.rows[2].Amount:SetText("lots")
check(not ged.Commit() and ns.db.tiers[2].gold == 8000000 * C and ged.rows[2].Amount:GetText() == "8,000,000", "a bad amount is refused and the row refilled")
ged.Add:Click()
check(#ns.db.tiers == 4 and ns.db.tiers[4].gold == 11000000 * C and ged.rows[4]:IsShown(), "Add a goal puts one above the top")
ged.rows[4].Remove:Click()
check(#ns.db.tiers == 3 and not ged.rows[4]:IsShown(), "and the minus takes it away")
ged.PresetTabs.Tabs.ladder:Click()
check(ns.db.targetPreset == "ladder" and ns.db.tiers[2].gold == 7000000 * C, "a preset tab restores the ladder")
ged.DeadlineTabs.Tabs.date:Click()
check(ns.db.deadlinePreset == "date" and ged.DeadlineBox:IsShown(), "choosing A date shows the box")
ged.DeadlineBox:SetText("2027-06-01")
check(ged.SetDeadline() and ns:DeadlineText(true) == "Jun 01, 2027", "typing a date sets it")
ged.DeadlineTabs.Tabs.expansion:Click()
check(ns.db.deadlinePreset == "expansion" and not ged.DeadlineBox:IsShown() and ns:DeadlineText(true) == "Aug 01, 2027", "End of Midnight hides the box and sets the guess")
check(ns:SetDeadlineText("expansion") and ns.db.deadlinePreset == "expansion" and ns:DeadlineText(true) == "Aug 01, 2027", "/gg deadline expansion")
check(ns:SetDeadlineText("season") and ns:DeadlineText(true) == "Jan 26, 2027", "/gg deadline season is the 12.2 guess")
check(ns:SetDeadlineDate("2027-03-01") and ns.db.deadlineGuess == nil, "a typed date forgets the guess")
ns:HideWindow()

print("Combat and the gold splash")
check(ns.db.bar.hideInCombat == true and ns.db.splash.enabled == true and ns.db.splash.threshold == 500 * C, "defaults: the bar hides in combat, the splash shows from 500g")
ns:SetBarShown(true)
IN_COMBAT = true
Fire("PLAYER_REGEN_DISABLED")
check(not ns.Bar:IsShown(), "the bar hides in combat")
IN_COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
check(ns.Bar:IsShown(), "and comes back after it")
ns.db.bar.hideInCombat = false
IN_COMBAT = true
ns:RefreshBar()
check(ns.Bar:IsShown(), "with the option off it stays through combat")
IN_COMBAT = false
ns.db.bar.hideInCombat = true
check(ns.db.bar.instanceMode == "smart", "default: the smart instance rule")
IN_INSTANCE, INSTANCE_TYPE, IN_GROUP = true, "party", false
Fire("PLAYER_ENTERING_WORLD")
check(ns.Bar:IsShown(), "a dungeon on your own keeps the bar")
IN_GROUP = true
Fire("GROUP_ROSTER_UPDATE")
check(ns.Bar:IsShown(), "a heroic dungeon in a group keeps it too")
IN_MPLUS = true
Fire("CHALLENGE_MODE_START")
check(not ns.Bar:IsShown(), "a keystone run hides it")
IN_MPLUS = false
Fire("CHALLENGE_MODE_COMPLETED")
check(ns.Bar:IsShown(), "and it is back when the key ends")
INSTANCE_TYPE = "raid"
Fire("ZONE_CHANGED_NEW_AREA")
check(ns.Bar:IsShown(), "a raid between pulls keeps it")
IN_COMBAT = true
ns.db.bar.hideInCombat = false
Fire("PLAYER_REGEN_DISABLED")
check(not ns.Bar:IsShown(), "raid combat hides it even with the combat option off")
IN_COMBAT = false
ns.db.bar.hideInCombat = true
Fire("PLAYER_REGEN_ENABLED")
check(ns.Bar:IsShown(), "the pull over, it returns")
INSTANCE_TYPE = "pvp"
Fire("ZONE_CHANGED_NEW_AREA")
check(not ns.Bar:IsShown(), "a battleground hides it")
INSTANCE_TYPE = "party"
ns.db.bar.instanceMode = "group"
ns:RefreshBar()
check(not ns.Bar:IsShown(), "Grouped: any grouped dungeon hides it")
IN_GROUP = false
ns:RefreshBar()
check(ns.Bar:IsShown(), "Grouped: solo keeps it")
INSTANCE_TYPE = "raid"
ns.db.bar.instanceMode = "hide"
ns:RefreshBar()
check(not ns.Bar:IsShown(), "Hide: hidden in a raid even solo")
ns.db.bar.instanceMode = "show"
IN_GROUP, IN_MPLUS = true, true
ns:RefreshBar()
check(ns.Bar:IsShown(), "Show: stays even in a key")
IN_MPLUS = false
ns.db.bar.instanceMode = "smart"
IN_INSTANCE, INSTANCE_TYPE, IN_GROUP = false, "none", true
ns:RefreshBar()
check(ns.Bar:IsShown(), "grouped in the open world keeps it (world quests with friends)")
IN_GROUP = false
_G.GoldGoalDB.schema, _G.GoldGoalDB.bar.instanceMode = 2, "group"
Fire("ADDON_LOADED", "GoldGoal")
check(ns.db.bar.instanceMode == "smart" and ns.db.schema == 3, "an earlier grouped default migrates to smart")
check(ns:SplashLevel(100 * C) == 0 and ns:SplashLevel(700 * C) == 1 and ns:SplashLevel(1000 * C) == 2 and ns:SplashLevel(5000 * C) == 3 and ns:SplashLevel(10000 * C) == 4
    and ns:SplashLevel(25000 * C) == 5 and ns:SplashLevel(50000 * C) == 6 and ns:SplashLevel(100000 * C) == 7 and ns:SplashLevel(500000 * C) == 7, "the seven shipped levels at 500, 1k, 5k, 10k, 25k, 50k and 100k")
check(ns.Splash and not ns.Splash:IsShown(), "the splash frame exists and is hidden")
ns.db.splash.marks = false -- the percent marks have their own section below
-- everything earned so far is still pending: the first flush carries the tiers banked along the way
ns.lastSplash = nil
ns:Fire("EARNED", 200 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.subtitle == "Mount banked!" and ns.lastSplash.level == 7 and ns.db.bankedTiers[1] and not ns.db.bankedTiers[2],
    "a banked tier is celebrated at the top level: " .. tostring(ns.lastSplash and ns.lastSplash.subtitle))
ns.lastSplash = nil
ns:Fire("EARNED", 200 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.subtitle == "Daily quota met!" and ns.db.days[ns:DayID()].met, "meeting the day's quota is celebrated once, even on a small gain")
ns.lastSplash = nil
ns:Fire("EARNED", 200 * C)
Advance(3); RunTimers()
check(ns.lastSplash == nil, "200g on its own is under the threshold")
ns:Fire("EARNED", 400 * C)
ns:Fire("EARNED", 400 * C)
Advance(1); RunTimers()
check(ns.lastSplash == nil, "nothing yet inside the merge window")
ns:Fire("EARNED", 400 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 1200 * C and ns.lastSplash.level == 2 and ns.lastSplash.subtitle == nil, "gains inside the merge window are one splash: " .. tostring(ns.lastSplash and ns.FormatGold(ns.lastSplash.amount)))
ns.lastSplash = nil
Fire("MAIL_SHOW")
ns:Fire("EARNED", 10000 * C)
Advance(10); RunTimers()
ns:Fire("EARNED", 30000 * C)
Advance(10); RunTimers()
local pend = ns:SplashPending()
check(ns.lastSplash == nil and pend == 40000 * C, "nothing shows while the mailbox is open, however long it stays open")
ns:Fire("EARNED", -20000 * C) -- the sold stock leaves at cost
Fire("MAIL_CLOSED")
check(ns.lastSplash == nil, "not at the instant it closes either")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 20000 * C and ns.lastSplash.level == 4 and ns.lastSplash.subtitle == nil, "the mailbox run shows once, net of the stock that left: " .. tostring(ns.lastSplash and ns.FormatGold(ns.lastSplash.amount)))
ns.lastSplash = nil
MONEY = MONEY + 150000 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 150000 * C and ns.lastSplash.level == 7 and ns.lastSplash.subtitle == "Legendary!", "a live gain reaches the splash through the ledger")
ns.db.splash.enabled = false
ns:Fire("EARNED", 5000 * C)
Advance(3); RunTimers()
check(ns.lastSplash.amount == 150000 * C, "switched off, nothing new shows")
ns.db.splash.enabled = true
ns:PreviewSplash(3)
check(ns.lastSplash.level == 3 and ns.lastSplash.amount == 5000 * C and ns.lastSplash.subtitle == nil, "preview at level 3")
SlashCmdList.GOLDGOAL("splash 2m")
check(ns.lastSplash.level == 7 and ns.lastSplash.subtitle == "Legendary!", "/gg splash 2m")

print("Progress marks")
ns.db.splash.marks = true
ns.db.progressMark = nil
ns:Fire("EARNED", 600 * C)
Advance(3); RunTimers()
check(ns.db.progressMark and ns.db.progressMark.target == ns.db.target, "the first gain sets the mark where the total stands, silently")
check(ns.lastSplash.subtitle == nil and ns.lastSplash.progress and ns.lastSplash.progress:find("^%+%d+%% of today's quota %(%d+%%%)$"),
    "a small gain is measured against today's quota: " .. tostring(ns.lastSplash.progress))
p = ns:Projection()
local nextPct = math.floor(p.total / p.target * 100) + 1
MONEY = MONEY + (nextPct / 100 * p.target - p.total) - 1 * C -- one gold short of the next percent
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash.title == nil and ns.lastSplash.subtitle ~= nextPct .. "% of Goal", "a gold short of the line: no mark")
check(ns.lastSplash.progress:find("^%+%d%.%d%% of Goal %(%d+%.%d%%%)$"), "a big gain is measured against the tier: " .. ns.lastSplash.progress)
ns.lastSplash = nil
MONEY = MONEY + 2 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.title == nextPct .. "%" and ns.lastSplash.subtitle == "of Goal" and ns.lastSplash.level == 1, "two gold across the line: a note of its own headed by the percent")
ns.lastSplash = nil
MONEY = MONEY + 2 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash == nil, "and not again for the same percent")
-- bank the vendors tier first (7M is also 70% of the buffer), then cross 80%
MONEY = MONEY + (7000000 * C - ns:TotalWealth()) + 1 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.subtitle == "Mount + vendors banked!" and ns.db.tierIndex == 3, "the vendors tier banked while pacing the buffer")
ns.db.progressMark.pct = 79
MONEY = MONEY + (0.80 * p.target - ns:TotalWealth()) + 1 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.subtitle == "80% of Goal" and ns.lastSplash.level >= 3, "a tenth percent rides on the gold splash at a bigger level: " .. tostring(ns.lastSplash and ns.lastSplash.subtitle))
ns.db.splash.marks = false
ns.db.progressMark.pct = 10
MONEY = MONEY + 2 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash.subtitle == "80% of Goal", "marks switched off: nothing")
ns.db.splash.marks = true

print("Past the quota")
check(ns.db.bar.afterMet == "count", "default: keep counting past today's quota")
ns:SetBarMode("daily")
ns:SetDeadlineDays(10)
local q = ns:DailyQuota()
check(q and q > 0 and ns:TodayEarned() > q, "today is well past its quota (" .. ns.FormatGold(ns:TodayEarned()) .. " of " .. ns.FormatGold(q) .. ")")
ns:RefreshBar()
local pr = ns.Bar.Progress
check(pr.fraction == 1 and pr.lap > 0 and pr.Lap:IsShown(), "the bar is full with a lap running over it")
check(ns.Bar.Label:GetText() == "Today" and ns.Bar.Check:IsShown(), "still Today, with a mark at the end")
local pct = tonumber(ns.StripColor(ns:BarText()):match("(%d+)%%$"))
check(pct and pct > 100, "the text keeps counting: " .. pct .. "%")
GameTooltip:SetOwner()
ns:PaceTooltip(GameTooltip)
check(ns.StripColor(table.concat(GameTooltip.lines, "\n")):find("Today  .-  met"), "the tooltip says today is met")
ns.db.bar.afterMet = "week"
ns:RefreshBar()
check(ns.Bar.Label:GetText() == "Today" and ns.Bar.Check:IsShown(), "Show the week: with the week met as well, it stays on today with the mark")
local wk = ns.db.weeks[ns:WeekID()]
local savedStart = wk.start
wk.start = wk.last - 1000 * C -- the week has 1,000g so far
ns:RefreshBar()
check(ns.Bar.Label:GetText() == "Week" and ns:BarShowsWeek() and not ns.Bar.Check:IsShown(), "Show the week: the bar moves on to the week once today is met")
wk.start = savedStart
ns.db.bar.afterMet = "count"
ns:RefreshBar()
check(ns.Bar.Label:GetText() == "Today", "Keep counting: back to today")
ns:SetDeadlineGuess("expansion")
local small = ns.UI.ProgressBar(NewWidget("Frame"), 8)
small:Set(50, 100)
check(small.lap == 0 and not small.Lap:IsShown(), "under the quota there is no lap")
small:Set(250, 100)
check(small.lap == 1 and small.fraction == 1, "at 250% the lap is full too")

print("Undo a new goal")
local daysBefore, earnedBefore2 = 0, ns:TodayEarned()
ns.db.goalBackup = nil -- an earlier section started a goal; start clean
for _ in pairs(ns.db.days) do daysBefore = daysBefore + 1 end
check(daysBefore > 0 and not ns:CanUndoNewGoal(), "history in place, nothing to undo yet")
ns:StartNewGoal()
check(ns:TodayEarned() == 0 and ns:CanUndoNewGoal(), "a new goal clears today and keeps a copy")
MONEY = MONEY + 700 * C
Fire("PLAYER_MONEY")
check(ns:UndoNewGoal() and not ns:CanUndoNewGoal(), "/gg undo restores it")
local daysAfter = 0
for _ in pairs(ns.db.days) do daysAfter = daysAfter + 1 end
check(daysAfter == daysBefore and ns:TodayEarned() == earnedBefore2 + 700 * C, "the history is back and the gold earned meanwhile counts for today")
check(not ns:UndoNewGoal(), "undo only once")
SlashCmdList.GOLDGOAL("undo")

print("Splash triggers")
local sedit = ns.UI.SplashLevelEditor(NewWidget("Frame"), 372)
sedit:Refresh()
check(sedit.rows[1].Sound.Text:GetText() == "Coin" and not sedit.rows[2].Glow:GetChecked() and sedit.rows[3].Glow:GetChecked() and sedit.rows[4].frame == "none"
    and sedit.rows[5].frame == "subtle" and sedit.rows[6].frame == "gold" and sedit.rows[7].frame == "liquid" and sedit.rows[7].Frame.Text:GetText() == "Torrent"
    and not sedit.rows[8]:IsShown(), "seven rows with each level's sound, glow and frame style")
ns:PreviewSplash(7)
check(ns.lastSplash.frame == "liquid" and ns.Splash and ns.Splash.Icon, "the top level lights the torrent")
ns:PreviewSplash(5)
check(ns.lastSplash.frame == "subtle", "level 5 the ripple")
ns:PreviewSplash(1)
check(ns.lastSplash.frame == "none", "level 1 none")
sedit.rows[5].Frame:Click()
check(ns.UI.Menu:IsShown() and #ns.UI.Menu.rows == 4 and ns.UI.Menu.rows[2].entry.text == "Ripple" and ns.UI.Menu.rows[4].entry.text == "Torrent", "the frame dropdown offers the four styles")
ns.UI.Menu.rows[3]:Click()
check(ns:SplashLevels()[5].frame == "gold", "and picking one sets it")
ns.db.splash.levels[5].frame = true
check(ns:SplashLevels()[5].frame == "gold", "a frame saved as on by the earlier version is the golden one")
sedit.Reset:Click()
check(sedit.rows[2].Size:GetText() == "28" and sedit.rows[2].Hold:GetText() == "1.6" and ns.StripColor(sedit.rows[2].Color.Text:GetText()) == "Gold", "size, hold and colour shown per level")
sedit.rows[2].Sound:Click()
local menu = ns.UI.Menu
check(menu and menu:IsShown() and menu._parent == UIParent and #menu.rows == 4 and menu.rows[2].entry.text == "Coin", "the sound dropdown opens on the screen itself, not inside a window")
menu.rows[4]:Click()
check(not menu:IsShown() and ns:SplashLevels()[2].sound == "legendary", "picking an entry sets the level and closes the menu")
sedit.rows[2].Color:Click()
check(menu:IsShown() and #menu.rows == 8, "the colour dropdown lists the eight colours")
menu.rows[6]:Click()
check(ns:SplashLevels()[2].color == "purple", "and picking one sets it")
sedit.Reset:Click()
sedit.rows[3].From:SetText("800")
sedit.rows[2].Say:SetText("Sweet!")
check(sedit.Commit(), "levels commit")
local lv = ns:SplashLevels()
check(lv[1].gold == 500 * C and lv[2].gold == 800 * C and lv[2].flavor == "" and lv[3].gold == 1000 * C and lv[3].flavor == "Sweet!", "levels sort themselves by gold, sayings travelling with them")
check(ns:SplashLevel(900 * C) == 2 and ns:SplashLevel(1200 * C) == 3, "the level of a gain follows the new amounts")
ns:PreviewSplash(3)
check(ns.lastSplash.subtitle == "Sweet!", "a custom saying shows")
sedit.rows[1].sound = "none"
sedit.rows[2].Size:SetText("30")
sedit.rows[2].Hold:SetText("2.5")
sedit.rows[2].color = "purple"
sedit.rows[2].frame = "liquid"
check(sedit.Commit(), "per-level fields commit")
lv = ns:SplashLevels()
check(lv[1].sound == "none" and lv[2].size == 30 and near(lv[2].hold, 2.5, 0.001) and lv[2].color == "purple" and lv[2].frame == "liquid", "sound, size, hold, colour and frame are per level")
ns:PreviewSplash(2)
check(ns.lastSplash.size == 30, "a preview uses the level's size")
sedit.rows[2].Size:SetText("huge")
check(not sedit.Commit() and ns:SplashLevels()[2].size == 30, "a bad size is refused")
check(ns:AddSplashLevel() and #ns:SplashLevels() == 8 and ns:SplashLevels()[8].gold == 200000 * C and ns:SplashLevels()[8].size == 72, "adding a level doubles the top gold and steps the size up")
sedit:Refresh()
check(sedit.rows[8]:IsShown() and sedit.rows[8].From:GetText() == "200,000", "the eighth row appears")
sedit.rows[8].Remove:Click()
check(#ns:SplashLevels() == 7 and not sedit.rows[8]:IsShown(), "and the minus takes it away")
for _ = 1, 6 do ns:AddSplashLevel() end
check(#ns:SplashLevels() == 10 and not ns:AddSplashLevel(), "ten levels at most")
ns.db.splash.levels = { { gold = 500 * C }, { gold = 5000 * C }, { gold = 25000 * C } }
ns.db.splash.soundFrom, ns.db.splash.glowFrom, ns.db.splash.frameFrom = 2, 3, 3
lv = ns:SplashLevels()
check(#lv == 3 and lv[1].sound == "none" and lv[2].sound == "coin" and lv[3].glow and lv[3].frame == "gold" and lv[2].frame == "none" and not lv[2].glow and lv[1].size == 22 and lv[3].color == "gold",
    "levels saved by the earlier version take their effects from the old from-level settings")
ns.db.splash.soundFrom, ns.db.splash.glowFrom, ns.db.splash.frameFrom = 1, 3, 4
sedit.Reset:Click()
check(#ns:SplashLevels() == 7 and ns:SplashLevels()[2].gold == 1000 * C and ns:SplashLevels()[5].flavor == "Nice!", "shipped levels restored")
ns:Fire("EARNED", 1 * C) -- absorb any mark the gold above crossed
Advance(3); RunTimers()
ns.lastSplash = nil
ns:Fire("EARNED", -5000 * C)
Advance(3); RunTimers()
check(ns.lastSplash == nil, "a loss shows nothing by default")
ns.db.splash.losses = true
ns:Fire("EARNED", -5000 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.loss and ns.lastSplash.amount == -5000 * C and ns.lastSplash.subtitle == "spent", "with losses on, a big spend shows in red")
ns.db.splash.losses = false
ns.lastSplash = nil
ns.db.splash.holdMail = false
Fire("MAIL_SHOW")
ns:Fire("EARNED", 700 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 700 * C, "with the hold off, gains show while the mailbox is open")
Fire("MAIL_CLOSED")
ns.db.splash.holdMail = true
ns.lastSplash = nil
ns.db.splash.followBar = true
IN_COMBAT = true
ns:Fire("EARNED", 700 * C)
Advance(3); RunTimers()
check(ns.lastSplash == nil, "following the bar, nothing shows in combat")
IN_COMBAT = false
ns:Fire("EARNED", 700 * C)
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 700 * C, "and it is back out of combat")
ns.db.splash.followBar = false
ns.db.splash.markEvery, ns.db.splash.markBigEvery = 5, 25
ns.db.progressMark = nil
ns:Fire("EARNED", 600 * C)
Advance(3); RunTimers()
p = ns:Projection()
local next5 = math.floor(p.total / p.target * 100 / 5) * 5 + 5
MONEY = MONEY + (next5 / 100 * p.target - p.total) + 1 * C
Fire("PLAYER_MONEY")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.subtitle == next5 .. "% of Goal", "marks every 5%: " .. tostring(ns.lastSplash and ns.lastSplash.subtitle))
ns.db.splash.markEvery, ns.db.splash.markBigEvery = 1, 10
check(ns:SplashIcon() == ns.COIN_TEXTURE, "the coin next to the amount is our own art by default")
ns:PreviewSplash(2)
check(ns.Splash.Icon:IsShown(), "and it shows on a preview")
ns.db.look.splashIcon = "none"
ns:PreviewSplash(2)
check(not ns.Splash.Icon:IsShown() and ns:SplashIcon() == nil, "None hides the coin")
ns.db.look.splashIcon = "pile"
check((ns:SplashIcon()):find("INV_Misc_Coin_01") and select(2, ns:SplashIcon()) == 0.08, "the game's gold pile comes cropped of its bevel")
ns.db.look.splashIcon = "custom"
ns.db.splash.celebrateBanked = false
ns.db.bankedTiers = {}
ns.lastSplash = nil
ns:Fire("EARNED", 700 * C)
Advance(3); RunTimers()
check(ns.lastSplash and not tostring(ns.lastSplash.subtitle):find("banked"), "with the celebration off, a banked goal passes quietly")
ns.db.splash.celebrateBanked = true
ns.db.bankedTiers = { true, true } -- the two tiers banked earlier stay celebrated
-- the log, and a mailbox hold that the mail frame says is stale
check(ns.splashLog and #ns.splashLog > 0 and ns.splashLog[1].kind == "flush", "every gain and flush is logged: " .. tostring(ns.splashLog[1].note))
_G.MailFrame = NewWidget("Frame", "MailFrame")
MailFrame:Hide()
Fire("MAIL_SHOW")
ns.lastSplash = nil
ns:Fire("EARNED", 956 * C)
check(ns.lastSplash == nil, "held at first...")
Advance(3); RunTimers()
check(ns.lastSplash and ns.lastSplash.amount == 956 * C, "...but with the mail frame not actually shown, the hold is released and the gain shows")
Fire("MAIL_CLOSED")
_G.MailFrame = nil
SlashCmdList.GOLDGOAL("splash log")

print("EllesmereUI options panel")
local grp
for _, g in ipairs(EllesmereUI.ADDON_GROUPS) do if g.key == "sagerobot" then grp = g end end
check(grp and grp.label == "Sagerobot's Addons" and grp.members[1] == "GoldGoal" and #EllesmereUI.ADDON_GROUPS == 2, "a sidebar group of our own with the GoldGoal row")
check(EllesmereUI._addonInfoByFolder.GoldGoal and EllesmereUI._addonInfoByFolder.GoldGoal.display == "GoldGoal" and EllesmereUI._syncExempt.GoldGoal, "row info registered, no profile sync icon")
local cfg = EUI_MODULES.GoldGoal
check(cfg and cfg.title == "GoldGoal" and #cfg.pages == 6 and cfg.pages[1] == "Goal" and cfg.pages[2] == "Characters" and cfg.pages[3] == "History", "module registered at login with six pages")
local function ctl(text)
    for _, c in ipairs(EUI_CONTROLS) do if c.text == text then return c end end
end
local pageParent = NewWidget("Frame")
pageParent:SetWidth(700)
for _, pageName in ipairs(cfg.pages) do
    wipe(EUI_CONTROLS)
    local hgt = cfg.buildPage(pageName, pageParent, -6)
    check(hgt > 100, pageName .. " page builds " .. #EUI_CONTROLS .. " controls, " .. hgt .. " tall")
end
wipe(EUI_CONTROLS)
cfg.buildPage("Bar", pageParent, -6)
ctl("Hide in combat").set(false)
check(ns.db.bar.hideInCombat == false and ctl("Hide in combat").get() == false, "Bar page: a toggle writes through")
ctl("Hide in combat").set(true)
ctl("Height").set(26)
check(ns.db.look.barHeight == 26 and ns.Bar:GetHeight() == 26, "Bar page: the height slider resizes the bar")
ctl("In instances").set("hide")
check(ns.db.bar.instanceMode == "hide" and ctl("In instances").get() == "hide", "Bar page: the instance dropdown")
ctl("In instances").set("smart")
ctl("Today / Week label").set(false)
check(ns.db.look.barLabel == false and not ns.Bar.Label:IsShown(), "Bar page: the label can go")
ctl("Today / Week label").set(true)
ctl("Percent").set(false)
check(not ns.StripColor(ns:BarText()):find("%%"), "Bar page: the percent can go: " .. ns.StripColor(ns:BarText()))
ctl("Percent").set(true)
ctl("Goal colours and tier marks").set(false)
ns:RefreshBar()
check(#ns.Bar.Progress.tickFracs == 0, "Bar page: without goal colours the bar has no marks")
ctl("Goal colours and tier marks").set(true)
IN_COMBAT = true
ns:RefreshBar()
check(not ns.Bar:IsShown(), "in combat the bar is hidden...")
ctl("Show me the bar").set()
check(ns.Bar:IsShown(), "...until Show me the bar brings it up regardless")
Advance(7); RunTimers()
check(not ns.Bar:IsShown(), "and the rules apply again a few seconds later")
IN_COMBAT = false
ns:RefreshBar()
wipe(EUI_CONTROLS)
cfg.buildPage("History", pageParent, -6)
check(ctl("Start a new goal") and (ctl("Undo the last new goal") or ctl("Nothing to undo")), "History page: start over and undo live with the history")
wipe(EUI_CONTROLS)
cfg.buildPage("Goal", pageParent, -6)
check(not ctl("Start a new goal") and not ctl("Count crafting stock at cost"), "Goal page: just the dashboard and the editor")
wipe(EUI_CONTROLS)
cfg.buildPage("Colours", pageParent, -6)
local r, g, b = ctl("The mount is safe").get()
check(rgb(r, g, b) == rgb(0.25, 0.80, 0.35), "Colours page: the swatch reads the stop")
ctl("The mount is safe").set(0, 1, 0, 1)
check(rgb(ns.UI.GoalColor(1, 1, 0, 1, 1)) == rgb(0, 1, 0), "a changed stop reaches the goal colour")
ctl("Reset the colours").set()
check(rgb(ns.UI.GoalColor(1, 1, 0, 1, 1)) == rgb(0.25, 0.80, 0.35), "and the reset button brings it back")
wipe(EUI_CONTROLS)
cfg.buildPage("Splash", pageParent, -6)
local sed = ns.euiSetup.splash
check(sed and sed.rows[1].From:GetText() == "500" and sed.rows[5].Say:GetText() == "Nice!" and sed.rows[7]:IsShown(), "Splash page: the level editor shows the shipped levels")
sed.rows[1].From:SetText("700")
check(sed.Commit() and ns:SplashThreshold() == 700 * C and ns.db.splash.threshold == 700 * C, "editing level 1 moves the threshold")
sed.Reset:Click()
check(ns:SplashThreshold() == 500 * C, "Shipped levels puts it back")
ctl("Time on screen").set(200)
check(ns.db.look.splashSpeed == 2 and ctl("Time on screen").get() == 200, "Splash page: time on screen in percent")
ctl("Time on screen").set(100)
sed.rows[3].Preview:Click()
check(ns.lastSplash.level == 3, "Splash page: each row previews its level")
wipe(EUI_CONTROLS)
cfg.buildPage("Goal", pageParent, -6)
ns:SetTierIndex(2)
check(ns.db.tierIndex == 3, "pacing a banked goal moves on to the next unbanked one")
local eed = ns.euiSetup.editor
check(eed and eed.rows[1]:IsShown() and eed.PaceDrop, "Goal page: the goal editor is embedded")
eed.rows[1].Amount:SetText("4,000,000")
check(eed.Commit() and ns.db.tiers[1].gold == 4000000 * C and ns.db.targetPreset == "custom", "editing a goal in the panel sets it")
ns:SetTargetPreset("ladder")
eed.DeadlineTabs.Tabs.date:Click()
eed.DeadlineBox:SetText("2027-06-01")
check(eed.SetDeadline() and ns.db.deadlinePreset == "date" and ns:DeadlineText(true) == "Jun 01, 2027", "typing a date in the panel sets the deadline")
ns:SetDeadlineGuess("expansion")
wipe(EUI_CONTROLS)
cfg.buildPage("Characters", pageParent, -6)
check(ctl("Re-read Syndicator") and ctl("Forget all characters") and ctl("Count crafting stock at cost"), "Characters page: the source buttons")
wipe(EUI_CONTROLS)
cfg.buildPage("Colours", pageParent, -6)
ctl("Window scale").set(120)
check(near(ns.db.window.scale, 1.2, 0.001) and ctl("Window scale").get() == 120, "Colours page: window scale in percent")
ctl("Window scale").set(100)
ns.db.look.barHeight = 30
cfg.onReset()
check(ns.db.look.barHeight == 20 and ns.db.splash.threshold == 500 * C and ns.db.bar.instanceMode == "smart", "reset restores the bar, splash and look defaults")
check(ns.db.tiers and #ns.db.tiers == 3 and ns.db.chars[me], "and leaves the goal and the ledger alone")
ns.euiActive = false -- the direct page builds above are not the panel showing us
SlashCmdList.GOLDGOAL("eui")
check(EllesmereUI.shown, "/gg eui opens the panel")
RunTimers()
check(EllesmereUI.selected == "GoldGoal" and ns.euiPageBuilt and ns.euiActive, "on the GoldGoal page, and the page built")
ns:HideWindow()
EllesmereUI.shown = false
SlashCmdList.GOLDGOAL("")
RunTimers()
check(EllesmereUI.shown and not ns:IsWindowShown(), "/gg opens the panel, not the window")
SlashCmdList.GOLDGOAL("")
check(not EllesmereUI.shown, "/gg again closes it")
SlashCmdList.GOLDGOAL("window")
check(ns:IsWindowShown(), "/gg window is the window itself")
ns:HideWindow()
ns.euiBroken = true
SlashCmdList.GOLDGOAL("")
check(ns:IsWindowShown() and not EllesmereUI.shown, "with the panel refused, /gg falls back to the window")
ns:HideWindow()
ns.euiBroken = nil
ns.euiPageBuilt = nil
EllesmereUI.SelectModule = function(self, f) self.selected = f end -- a panel that never builds the page
SlashCmdList.GOLDGOAL("")
RunTimers()
check(ns.euiBroken and ns:IsWindowShown(), "a page that never builds turns the fallback on for the session")
ns:HideWindow()

SlashCmdList.GOLDGOAL("status")
SlashCmdList.GOLDGOAL("help")

print(failures == 0 and "\nALL CHECKS PASSED" or ("\n" .. failures .. " CHECK(S) FAILED"))
os.exit(failures == 0 and 0 or 1)

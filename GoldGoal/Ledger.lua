-- GoldGoal: the ledger. Every character's gold and the warband bank, pooled
-- into one total; the day and week records that turn that total into
-- earnings; and the one rule that keeps the earnings honest:
--
--   Only changes seen live on the logged-in character (and the warband
--   bank) count as earnings. Everything else, a character seen for the
--   first time, a figure taken from Syndicator, an include/exclude toggle
--   or a forgotten character, shifts the current day's and week's starting
--   point by the same amount, so the total moves but the earnings do not.
local _, ns = ...

local DAY = 86400
local KEEP_DAYS, KEEP_WEEKS = 90, 26
local ID_SHIFT = 1800 -- see DayID

-------------------------------------------------------------------------------
-- Day and week ids. A day runs from one daily reset to the next; its id is
-- the UTC day number of the reset that ends it, which is the same number
-- anywhere inside the period and steps by one at the reset. Weeks likewise,
-- stepping by seven at the weekly reset. The half-hour shift keeps a reset
-- that sits within a second of UTC midnight from flickering between two
-- ids; it would take a reset at exactly 23:30 UTC to bring that back.
-------------------------------------------------------------------------------
local function SecondsUntil(fn)
    if C_DateAndTime and C_DateAndTime[fn] then
        local ok, v = pcall(C_DateAndTime[fn])
        if ok then return ns.Num(v) end
    end
    return nil
end

-- Both resets are asked for over and over inside one refresh: every
-- projection reads the day and week ids half a dozen times, and a single
-- gain refreshes the bar, the broker, the window and the splash. Neither
-- reset can move within a second, so each keeps its last answer and the
-- protected API call behind it runs once a second instead of sixty times
-- a gain.
local dailyFor, dailyAt, weeklyFor, weeklyAt

local function NextDailyReset(now)
    if dailyFor == now then return dailyAt end
    local secs = SecondsUntil("GetSecondsUntilDailyReset")
    -- UTC midnight without the API
    dailyFor, dailyAt = now, secs and (now + secs) or ((math.floor(now / DAY) + 1) * DAY)
    return dailyAt
end

local function NextWeeklyReset(now)
    if weeklyFor == now then return weeklyAt end
    local secs = SecondsUntil("GetSecondsUntilWeeklyReset")
    if secs then
        weeklyFor, weeklyAt = now, now + secs
    else
        -- Tuesday 15:00 UTC without the API; day 0 of the epoch was a Thursday
        local week = 7 * DAY
        local anchor = 5 * DAY + 15 * 3600
        weeklyFor, weeklyAt = now, math.floor((now - anchor) / week + 1) * week + anchor
    end
    return weeklyAt
end

function ns:DayID(now)
    now = now or time()
    return math.floor((NextDailyReset(now) + ID_SHIFT) / DAY)
end

function ns:WeekID(now)
    now = now or time()
    return math.floor((NextWeeklyReset(now) + ID_SHIFT) / DAY)
end

-- Seconds until the resets, for countdowns.
function ns:SecondsUntilDailyReset(now)
    now = now or time()
    return NextDailyReset(now) - now
end

function ns:SecondsUntilWeeklyReset(now)
    now = now or time()
    return NextWeeklyReset(now) - now
end

-- Where the daily reset falls inside a UTC day, so any day id can be turned
-- back into the instant that ends it (and any instant into a day id).
local resetOffset
function ns:ResetOffset(now)
    if not resetOffset then
        now = now or time()
        resetOffset = NextDailyReset(now) - self:DayID(now) * DAY
    end
    return resetOffset
end

function ns:DayEnd(dayID)
    return dayID * DAY + self:ResetOffset()
end

function ns:DayIDAt(t)
    return math.floor((t - self:ResetOffset()) / DAY) + 1
end

-- The calendar date a day id stands for: the local date at the middle of
-- the period (a US day runs 8am to 8am; its middle is that evening).
function ns:DayDate(dayID)
    return self:DayEnd(dayID) - DAY / 2
end

function ns:WeekDate(weekID)
    return self:DayEnd(weekID) - 7 * DAY + DAY / 2
end

-------------------------------------------------------------------------------
-- Characters
-------------------------------------------------------------------------------
function ns:CharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = (GetRealmName() or "Unknown"):gsub("[%s%-]", "") end
    return name .. "-" .. realm
end

function ns:TotalWealth()
    local total = 0
    for _, c in pairs(self.db.chars) do
        if c.include ~= false and c.money then total = total + c.money end
    end
    if self.db.warband.money then total = total + self.db.warband.money end
    if self.CraftingAtCost then total = total + self:CraftingAtCost() end
    return total
end

-- Gold alone: what the target has to be paid with.
function ns:LiquidWealth()
    return self:TotalWealth() - (self.CraftingAtCost and self:CraftingAtCost() or 0)
end

function ns:CountCharacters()
    local n = 0
    for _ in pairs(self.db.chars) do n = n + 1 end
    return n
end

-- Characters by gold, richest first: { key, money, ... } copies of the entries.
function ns:SortedCharacters()
    local list = {}
    for key, c in pairs(self.db.chars) do
        local e = { key = key }
        for k, v in pairs(c) do e[k] = v end
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        if (a.money or 0) ~= (b.money or 0) then return (a.money or 0) > (b.money or 0) end
        return a.key < b.key
    end)
    return list
end

function ns:SetCharacterIncluded(key, on)
    local c = self.db.chars[key]
    if not c then return end
    on = on and true or false
    if (c.include ~= false) == on then return end
    c.include = on
    self:Touch((on and 1 or -1) * (c.money or 0))
end

-- Drops a character from the pool; Syndicator will not bring it back.
function ns:ForgetCharacter(key)
    local c = self.db.chars[key]
    if not c or key == self:CharKey() then return end
    self.db.chars[key] = nil
    self.db.forgotten[key] = true
    self:Touch(c.include ~= false and -(c.money or 0) or 0)
end

function ns:ForgetAllCharacters()
    local me = self:CharKey()
    local mine = self.db.chars[me]
    local delta = 0
    for key, c in pairs(self.db.chars) do
        if key ~= me and c.include ~= false then delta = delta - (c.money or 0) end
    end
    wipe(self.db.chars)
    wipe(self.db.forgotten)
    if mine then self.db.chars[me] = mine end
    self:Touch(delta)
    self:MergeSyndicator()
end

-------------------------------------------------------------------------------
-- Observing. Observe() records what the client shows for this character
-- and the warband bank; Touch() carries the total into the day and week
-- records, shifting their starting points by any non-earnings delta.
-------------------------------------------------------------------------------
function ns:Observe()
    if not self.db then return end
    local db, now = self.db, time()
    local delta = 0
    local money = self:ReadPlayerMoney()
    if money then
        local key = self:CharKey()
        local c = db.chars[key]
        if not c then
            c = { include = true }
            db.chars[key] = c
            delta = delta + money -- first sight of this character: not income
        elseif c.source ~= "live" then
            delta = delta + (money - (c.money or 0)) -- a remembered figure, not income
        end
        c.money, c.source, c.lastSeen = money, "live", now
        c.name, c.realm = UnitName("player"), GetRealmName()
        c.class = select(2, UnitClass("player"))
        db.forgotten[key] = nil
    end
    local wb = self:ReadWarbandMoney()
    if wb then
        local w = db.warband
        if w.money == nil then
            delta = delta + wb
        elseif w.source ~= "live" then
            delta = delta + (wb - w.money)
        end
        w.money, w.source, w.updated = wb, "live", now
    end
    self:Touch(delta)
end

local function Prune(store, floor)
    for id in pairs(store) do
        if id < floor then store[id] = nil end
    end
end

-- baselineDelta: the part of any change since the last observation that is
-- not income (see the top of the file); craftingBaseline, the part of that
-- which is crafting stock (a first reading, a reset, the setting toggled).
-- EARNED carries the income and its split: the gold that moved and the
-- stock that moved at cost, so a sale's gross and cost can be told apart.
function ns:Touch(baselineDelta, craftingBaseline)
    if not self.db then return end
    self:Invalidate()
    local db, now = self.db, time()
    baselineDelta = baselineDelta or 0
    local total = self:TotalWealth()
    local crafting = self.CraftingAtCost and self:CraftingAtCost() or 0
    local craftingEarned = self.lastCrafting and (crafting - self.lastCrafting - (craftingBaseline or 0)) or 0
    self.lastCrafting = crafting
    local dayID, weekID = self:DayID(now), self:WeekID(now)
    if not db.goalStart then
        db.goalStart, db.goalStartDay = now, dayID
    end
    -- a period opens at the last total seen (nothing changes while logged
    -- out) plus this observation's non-earnings; a first-ever observation
    -- opens at the total itself
    local carry = db.lastTotal and (db.lastTotal + baselineDelta) or total
    local earned = total - carry
    local day = db.days[dayID]
    if not day then
        day = { start = carry, last = total, week = weekID }
        db.days[dayID] = day
        Prune(db.days, dayID - KEEP_DAYS)
    else
        day.start = day.start + baselineDelta
        day.last = total
    end
    local week = db.weeks[weekID]
    if not week then
        week = { start = carry, last = total, firstDay = dayID }
        db.weeks[weekID] = week
        Prune(db.weeks, weekID - 7 * KEEP_WEEKS)
    else
        week.start = week.start + baselineDelta
        week.last = total
    end
    db.lastTotal = total
    -- a banked tier moves the pacing up to the next one
    if self.AutoAdvanceTier then self:AutoAdvanceTier(total) end
    self:RefreshQuotas(now)
    self:Fire("WEALTH_CHANGED")
    if earned ~= 0 or craftingEarned ~= 0 then self:Fire("EARNED", earned, earned - craftingEarned, craftingEarned) end
end

-- Fills in characters Syndicator knows that this addon has not seen yet,
-- and the warband bank if it is still unknown. A live figure is never
-- replaced. Returns how many characters were added.
function ns:MergeSyndicator()
    local chars, wb = self:ReadSyndicator()
    if not chars then return 0 end
    local db, delta, added = self.db, 0, 0
    local me = self:CharKey()
    for key, s in pairs(chars) do
        if key ~= me and not db.forgotten[key] then
            local c = db.chars[key]
            if not c then
                db.chars[key] = { money = s.money, class = s.class, name = s.name, realm = s.realm, include = true, source = "syndicator" }
                delta = delta + s.money
                added = added + 1
            elseif c.source ~= "live" and c.money ~= s.money then
                if c.include ~= false then delta = delta + (s.money - (c.money or 0)) end
                c.money = s.money
            end
        end
    end
    if wb and db.warband.money == nil then
        db.warband.money, db.warband.source, db.warband.updated = wb, "syndicator", time()
        delta = delta + wb
    end
    self:Touch(delta)
    return added
end

-------------------------------------------------------------------------------
-- Earnings and history
-------------------------------------------------------------------------------
function ns:Earned(dayID)
    local d = self.db.days[dayID]
    return d and (d.last - d.start) or 0
end

-- Everything earned between two day ids, both included. A day with no
-- record earned nothing, so a span wider than the history worth keeping
-- (a goal started last year) walks the days that exist rather than every
-- id in between.
local function SumDays(days, first, last)
    local sum = 0
    if last < first then return sum end
    if last - first > KEEP_DAYS then
        for id, d in pairs(days) do
            if id >= first and id <= last then sum = sum + (d.last - d.start) end
        end
    else
        for id = first, last do
            local d = days[id]
            if d then sum = sum + (d.last - d.start) end
        end
    end
    return sum
end

function ns:TodayEarned()
    return self:Earned(self:DayID())
end

function ns:WeekEarned()
    local w = self.db.weeks[self:WeekID()]
    return w and (w.last - w.start) or 0
end

-- The first day seen in a week, for week records saved before they kept
-- it: the earliest day record that names the week.
function ns:FirstDayOfWeek(weekID)
    local first
    for id, d in pairs(self.db.days) do
        if d.week == weekID and (not first or id < first) then first = id end
    end
    return first
end

function ns:DailyQuota()
    local d = self.db.days[self:DayID()]
    return d and d.quota or nil
end

function ns:WeeklyQuota()
    local w = self.db.weeks[self:WeekID()]
    return w and w.quota or nil
end

-- The last n days, oldest first: { id, earned, quota, seen }. Days without
-- a record earned nothing.
function ns:RecentDays(n)
    local today = self:DayID()
    local out = {}
    for id = today - n + 1, today do
        local d = self.db.days[id]
        out[#out + 1] = { id = id, earned = d and (d.last - d.start) or 0, quota = d and d.quota or nil, seen = d and true or false }
    end
    return out
end

function ns:RecentWeeks(n)
    local this = self:WeekID()
    local out = {}
    for i = n - 1, 0, -1 do
        local id = this - 7 * i
        local w = self.db.weeks[id]
        out[#out + 1] = { id = id, earned = w and (w.last - w.start) or 0, quota = w and w.quota or nil, seen = w and true or false }
    end
    return out
end

-- Average earnings per day over the n days before today (days before the
-- goal started do not count, days without a record count as nothing).
-- With no completed day yet, today's earnings stand in.
function ns:Average(n)
    local today = self:DayID()
    local first = math.max(today - n, self.db.goalStartDay or today)
    local count = today - first
    if count <= 0 then return self:Earned(today) end
    return SumDays(self.db.days, first, today - 1) / count
end

function ns:AverageSinceStart()
    local today = self:DayID()
    local first = self.db.goalStartDay or today
    if first >= today then return self:Earned(today) end
    return SumDays(self.db.days, first, today - 1) / (today - first)
end

-- Everything earned since the goal started, today included.
function ns:SavedSinceStart()
    local today = self:DayID()
    return SumDays(self.db.days, self.db.goalStartDay or today, today)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("LOGIN", function()
    ns:Observe()
    ns:MergeSyndicator()
    for _, event in ipairs({ "PLAYER_MONEY", "ACCOUNT_MONEY", "BANKFRAME_OPENED", "PLAYER_ENTERING_WORLD" }) do
        ns:RegisterEvent(event, function() ns:Observe() end)
    end
    -- the day or week can turn while nothing changes hands
    if C_Timer.NewTicker then
        C_Timer.NewTicker(60, function() ns:Touch(0) end)
    end
end)

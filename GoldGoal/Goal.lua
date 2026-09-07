-- GoldGoal: the goal itself. The tiers (at least the mount, then the
-- vendors, then a buffer), the one being paced towards, the deadline, the
-- quotas they imply, the rolling averages and the projected finish. Pure
-- arithmetic on the ledger; nothing here touches a frame.
local _, ns = ...

local DAY = 86400
local COPPER = ns.COPPER

ns.MAX_TIERS = 4

-- The Sporebearer Fungal Strider (patch 12.1.5): 5,000,000g with a mailbox
-- and a repair vendor, another 2,000,000g for the optional vendors. Sold
-- until the end of the Midnight expansion.
local M = 1000000 * COPPER
ns.TIER_PRESETS = {
    mount = { { name = "Mount", gold = 5 * M } },
    set = { { name = "Mount", gold = 5 * M }, { name = "Mount + vendors", gold = 7 * M } },
    ladder = { { name = "Mount", gold = 5 * M }, { name = "Mount + vendors", gold = 7 * M }, { name = "Buffer", gold = 10 * M } },
}
ns.TARGET_PRESET_NAMES = { mount = "Mount", set = "Mount + vendors", ladder = "Ladder", custom = "Custom" }

-- PLACEHOLDERS, both guesses (see the README's timeline). Season 2 ends
-- when patch 12.2 lands: the 8-week cadence puts that in late January 2027.
-- The mount is sold until the end of Midnight, i.e. The Last Titan's
-- pre-patch: if Midnight runs the 18 months The War Within did, that is
-- around August 2027; it could well be later. Pick a date in Settings once
-- either is announced.
ns.SEASON_END_GUESS = "2027-01-26"
ns.EXPANSION_END_GUESS = "2027-08-01"
ns.DEADLINE_GUESSES = { season = ns.SEASON_END_GUESS, expansion = ns.EXPANSION_END_GUESS }

-------------------------------------------------------------------------------
-- Tiers. db.tiers is sorted, cheapest first; db.tierIndex is the tier the
-- daily quota paces towards, and db.target mirrors its gold so every quota
-- and projection can keep using one number. Once a tier is banked the
-- pacing moves up to the next one by itself.
-------------------------------------------------------------------------------
local function CopyTiers(list)
    local out = {}
    for _, t in ipairs(list or {}) do
        local gold = ns.Num(t.gold)
        if gold and gold > 0 and #out < ns.MAX_TIERS then
            out[#out + 1] = { name = tostring(t.name or ("Tier " .. (#out + 1))), gold = gold }
        end
    end
    table.sort(out, function(a, b) return a.gold < b.gold end)
    return out
end

function ns:Tiers()
    return self.db.tiers
end

function ns:PacedTier()
    local tiers = self.db.tiers
    return tiers[self.db.tierIndex or 1] or tiers[1]
end

function ns:TopTier()
    return self.db.tiers[#self.db.tiers]
end

-- The target follows the paced tier.
function ns:ApplyTier()
    local t = self:PacedTier()
    if t then self.db.target = t.gold end
end

-- Moves the pacing up past every tier the total already covers. Never
-- moves down. Returns true when it moved.
function ns:AutoAdvanceTier(total)
    local tiers = self.db.tiers
    if not tiers or #tiers == 0 then return false end
    total = total or self:TotalWealth()
    local i = self.db.tierIndex or 1
    local moved = false
    while tiers[i + 1] and total >= tiers[i].gold do
        i = i + 1
        moved = true
    end
    if moved then
        self.db.tierIndex = i
        self:ApplyTier()
    end
    return moved
end

function ns:SetTiers(list, preset)
    list = CopyTiers(list)
    if #list == 0 then return false end
    self.db.tiers = list
    self.db.targetPreset = preset or "custom"
    self.db.tierIndex = math.min(self.db.tierIndex or 1, #list)
    self:AutoAdvanceTier()
    self:ApplyTier()
    self:RefreshQuotas()
    self:Fire("SETTINGS_CHANGED")
    self:Fire("WEALTH_CHANGED")
    return true
end

function ns:SetTierIndex(i)
    if not self.db.tiers[i] then return false end
    self.db.tierIndex = i
    self:AutoAdvanceTier()
    self:ApplyTier()
    self:RefreshQuotas()
    self:Fire("SETTINGS_CHANGED")
    self:Fire("WEALTH_CHANGED")
    return true
end

-- One tier only.
function ns:SetTarget(copper, preset)
    local name = preset and self.TARGET_PRESET_NAMES[preset] or "Custom"
    return self:SetTiers({ { name = name, gold = copper } }, preset or "custom")
end

function ns:SetTargetPreset(preset)
    if preset == "custom" then
        self.db.targetPreset = "custom"
        self:Fire("SETTINGS_CHANGED")
        return true
    end
    local list = self.TIER_PRESETS[preset]
    if not list then return false end
    return self:SetTiers(list, preset)
end

-- "5m Mount, 7m Mount + vendors, 10m Buffer" -> tiers, or nil. Each part
-- is one amount and the rest of its words are the name.
function ns.ParseTiers(text)
    local out = {}
    for part in tostring(text or ""):gmatch("[^,]+") do
        local gold, name
        for token in part:gmatch("%S+") do
            local v = not gold and ns.ParseGold(token)
            if v then
                gold = v
            else
                name = name and (name .. " " .. token) or token
            end
        end
        if not gold then return nil end
        out[#out + 1] = { name = name or ("Tier " .. (#out + 1)), gold = gold }
    end
    if #out == 0 or #out > ns.MAX_TIERS then return nil end
    return out
end

function ns:TiersText()
    local parts = {}
    for _, t in ipairs(self.db.tiers) do parts[#parts + 1] = t.name .. " " .. self.FormatGold(t.gold) end
    return table.concat(parts, "  ·  ")
end

-------------------------------------------------------------------------------
-- Remaining and days left
-------------------------------------------------------------------------------
function ns:Remaining(total)
    return math.max(0, self.db.target - (total or self:TotalWealth()))
end

-- Days left including today, at least one (a passed deadline leaves today).
function ns:DaysLeft(now)
    local deadline = self.db.deadline
    if not deadline then return nil end
    now = now or time()
    return math.max(1, math.ceil((deadline - now) / DAY))
end

function ns:DeadlinePassed(now)
    return self.db.deadline and (now or time()) >= self.db.deadline or false
end

-------------------------------------------------------------------------------
-- Quotas. Today's quota is what was left at the start of the day spread
-- over the days left; it is frozen for the day, so the bar's target holds
-- still while you fill it. Tomorrow's quota is the same sum done again on
-- what is left now: a big day lowers it, an idle week raises it.
-------------------------------------------------------------------------------
function ns:QuotaFor(startTotal, daysLeft)
    if not daysLeft then return nil end
    return self:Remaining(startTotal) / daysLeft
end

-- This week's quota is the daily quota times the days of this week that
-- are left (never more than the days left to the deadline).
function ns:WeekQuotaFor(startTotal, now)
    now = now or time()
    local daysLeft = self:DaysLeft(now)
    if not daysLeft then return nil end
    local daysInWeek = math.min(daysLeft, math.max(1, math.ceil(self:SecondsUntilWeeklyReset(now) / DAY)))
    return self:QuotaFor(startTotal, daysLeft) * daysInWeek, daysInWeek
end

function ns:TomorrowQuota(now)
    now = now or time()
    local daysLeft = self:DaysLeft(now)
    if not daysLeft or daysLeft <= 1 then return nil end
    return self:Remaining() / (daysLeft - 1)
end

-- Recomputes today's and this week's quota from their starting totals (the
-- target, the deadline or a starting point changed).
function ns:RefreshQuotas(now)
    now = now or time()
    local day = self.db.days[self:DayID(now)]
    if day then day.quota = self:QuotaFor(day.start, self:DaysLeft(now)) end
    local week = self.db.weeks[self:WeekID(now)]
    if week then week.quota, week.days = self:WeekQuotaFor(week.start, now) end
end

-------------------------------------------------------------------------------
-- The deadline
-------------------------------------------------------------------------------
function ns:SetDeadline(t, preset)
    self.db.deadline = t
    self.db.deadlinePreset = preset or "date"
    if not self.DEADLINE_GUESSES[self.db.deadlinePreset] then self.db.deadlineGuess = nil end
    self:RefreshQuotas()
    self:Fire("SETTINGS_CHANGED")
    self:Fire("WEALTH_CHANGED")
end

-- "YYYY-MM-DD" -> the daily reset that ends that (local) date, or nil.
function ns:DeadlineFromDate(text)
    local y, m, d = tostring(text or ""):match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    local noon = time({ year = y, month = m, day = d, hour = 12 })
    if not noon then return nil end
    return self:DayEnd(self:DayIDAt(noon))
end

function ns:SetDeadlineDate(text, preset)
    local t = self:DeadlineFromDate(text)
    if not t then return false end
    self:SetDeadline(t, preset or "date")
    return true
end

-- n days left, today included.
function ns:SetDeadlineDays(n, now)
    n = tonumber(n)
    if not n or n < 1 then return false end
    now = now or time()
    self:SetDeadline(self:DayEnd(self:DayID(now) + math.floor(n) - 1), "days")
    return true
end

-- The shipped guesses: "season" or "expansion".
function ns:SetDeadlineGuess(preset)
    local guess = self.DEADLINE_GUESSES[preset]
    if not guess then return false end
    local ok = self:SetDeadlineDate(guess, preset)
    if ok then self.db.deadlineGuess = guess end
    return ok
end

function ns:SetDeadlineSeason() return self:SetDeadlineGuess("season") end
function ns:SetDeadlineExpansion() return self:SetDeadlineGuess("expansion") end

-- "2027-08-01", "45d", "45", "season", "expansion"
function ns:SetDeadlineText(text)
    text = strtrim(tostring(text or "")):lower()
    if self.DEADLINE_GUESSES[text] then return self:SetDeadlineGuess(text) end
    local days = text:match("^(%d+)%s*d?a?y?s?$")
    if days then return self:SetDeadlineDays(tonumber(days)) end
    return self:SetDeadlineDate(text)
end

-- Clears the history, keeping a copy so UndoNewGoal can bring it back.
function ns:StartNewGoal()
    local db = self.db
    db.goalBackup = { at = time(), days = self.DeepCopy(db.days), weeks = self.DeepCopy(db.weeks),
        goalStart = db.goalStart, goalStartDay = db.goalStartDay, lastTotal = db.lastTotal }
    wipe(db.days)
    wipe(db.weeks)
    db.goalStart, db.goalStartDay = nil, nil
    self:Touch(0)
    self:Fire("SETTINGS_CHANGED")
end

function ns:CanUndoNewGoal()
    return self.db.goalBackup ~= nil
end

-- Puts the history back as it was before the last Start a new goal; the
-- gold that came in since then lands on today.
function ns:UndoNewGoal()
    local db = self.db
    local b = db.goalBackup
    if not b then return false end
    db.days = self.DeepCopy(b.days or {})
    db.weeks = self.DeepCopy(b.weeks or {})
    db.goalStart, db.goalStartDay = b.goalStart, b.goalStartDay
    db.lastTotal = b.lastTotal
    db.goalBackup = nil
    self:Touch(0)
    self:Fire("SETTINGS_CHANGED")
    return true
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------
function ns.DateText(t, withYear)
    return date(withYear and "%b %d, %Y" or "%b %d", t)
end

-- With the year only when it is not this year.
function ns.DateTextSmart(t, now)
    return ns.DateText(t, date("%Y", t) ~= date("%Y", now or time()))
end

-- The calendar date the deadline stands for (the day it ends).
function ns:DeadlineText(withYear)
    if not self.db.deadline then return "no deadline" end
    return self.DateText(self.db.deadline - DAY / 2, withYear)
end

function ns.Countdown(secs)
    secs = math.max(0, math.floor(secs or 0))
    local d, h, m = math.floor(secs / DAY), math.floor(secs % DAY / 3600), math.floor(secs % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-------------------------------------------------------------------------------
-- Projection
-------------------------------------------------------------------------------
function ns:Projection(now)
    now = now or time()
    local total = self:TotalWealth()
    local remaining = self:Remaining(total)
    local p = {
        now = now, total = total, remaining = remaining, target = self.db.target,
        deadline = self.db.deadline, daysLeft = self:DaysLeft(now),
        today = self:TodayEarned(), quota = self:DailyQuota(), tomorrow = self:TomorrowQuota(now),
        week = self:WeekEarned(), weekQuota = self:WeeklyQuota(),
        avg7 = self:Average(7), avg30 = self:Average(30), avgGoal = self:AverageSinceStart(),
        saved = self:SavedSinceStart(),
        crafting = self:CraftingAtCost(), craftingProjected = self:CraftingProjected(), craftingEstimated = self:CraftingEstimated(),
    }
    p.liquid = total - p.crafting
    p.liquidShort = math.max(0, p.target - p.liquid)
    local function finish(avg, rem)
        rem = rem or remaining
        if avg and avg > 0 and rem > 0 then return now + rem / avg * DAY end
        return nil
    end
    p.finish7, p.finish30, p.finishGoal = finish(p.avg7), finish(p.avg30), finish(p.avgGoal)
    if remaining <= 0 then
        p.status = "reached"
    elseif not p.finish7 then
        p.status = "stalled"
    elseif not p.deadline then
        p.status = "pace"
    elseif p.finish7 <= p.deadline then
        p.status = "ahead"
    else
        p.status = "behind"
    end
    if p.deadline and p.finish7 then p.slack = (p.deadline - p.finish7) / DAY end

    -- every tier, for the ladder
    p.tiers = {}
    p.allReached = true
    for i, t in ipairs(self.db.tiers) do
        local rem = math.max(0, t.gold - total)
        local e = { index = i, name = t.name, gold = t.gold, remaining = rem, reached = rem <= 0, paced = i == (self.db.tierIndex or 1) }
        e.need = p.daysLeft and (rem / p.daysLeft) or nil
        e.finish = finish(p.avg7, rem)
        if e.reached then e.state = "reached"
        elseif not e.finish then e.state = "stalled"
        elseif not p.deadline then e.state = "pace"
        elseif e.finish <= p.deadline then e.state = "ahead"
        else e.state = "behind" end
        if not e.reached then p.allReached = false end
        p.tiers[i] = e
        if e.paced then p.tier = e end
    end
    p.topGold = self:TopTier() and self:TopTier().gold or p.target
    return p
end

-- One coloured line summing the projection up.
function ns:StatusText(p)
    p = p or self:Projection()
    local accent = self.Style and self.Style.AccentHex and self.Style.AccentHex() or "|cffffd100"
    local many = #self.db.tiers > 1
    local name = p.tier and p.tier.name or "the goal"
    if p.status == "reached" then
        if p.liquidShort > 0 then
            return string.format("%s%s reached at cost:|r sell %s of crafting stock to have it all in gold.", accent, many and name or "Goal", self.FormatGold(p.liquidShort))
        end
        return accent .. (many and (p.allReached and "Every tier reached!" or (name .. " reached!")) or "Goal reached!") .. "|r"
    elseif p.status == "stalled" then
        return self.GREY_HEX .. "No earnings yet: nothing to project from.|r"
    elseif p.status == "pace" then
        return string.format("%sAt this pace you reach %s %s.|r", accent, many and name or "the goal", self.DateText(p.finish7, true))
    elseif p.status == "ahead" then
        local days = math.floor(p.slack)
        return string.format("%sOn pace%s:|r finishes %s, %s early.", self.GREEN_HEX, many and (" for " .. name) or "", self.DateText(p.finish7),
            days >= 1 and string.format("%d day%s", days, days == 1 and "" or "s") or "just")
    else
        local days = math.ceil(-p.slack)
        return string.format("%sBehind%s:|r finishes %s, %d day%s late. Need %s/day, doing %s.", self.RED_HEX, many and (" on " .. name) or "", self.DateText(p.finish7),
            days, days == 1 and "" or "s", p.quota and self.FormatGold(p.quota) or "?", self.FormatGold(p.avg7))
    end
end

-- The tiers mapped onto a quota bar: each tier below the paced one sits
-- at the share of what is left that it still needs, so with 10M to go and
-- the mount at 5M its mark is halfway along today's (or the week's) bar.
-- A banked tier has no mark; once the cheapest tier is banked the whole
-- bar is past the hard goal.
function ns:QuotaTicks(p)
    p = p or self:Projection()
    local ticks, hardFrac = {}, 1
    if not p.remaining or p.remaining <= 0 then return ticks, 0 end
    for _, e in ipairs(p.tiers or {}) do
        if e.gold < p.target and e.remaining > 0 then ticks[#ticks + 1] = e.remaining / p.remaining end
    end
    local hard = p.tiers and p.tiers[1]
    if hard and hard.gold < p.target then hardFrac = hard.remaining / p.remaining end
    return ticks, hardFrac
end

-- A tier's one-line verdict: "need 5,400g/day · at pace Oct 12" in the
-- colour of its state.
function ns:TierText(e)
    if e.reached then return self.GREEN_HEX .. "reached|r" end
    local parts = {}
    if e.need then parts[#parts + 1] = "need " .. self.FormatGold(e.need) .. "/day" end
    if e.finish then
        local hex = e.state == "ahead" and self.GREEN_HEX or e.state == "behind" and self.RED_HEX or "|cffffffff"
        parts[#parts + 1] = hex .. "at pace " .. self.DateTextSmart(e.finish) .. "|r"
    else
        parts[#parts + 1] = self.GREY_HEX .. "no pace yet|r"
    end
    return table.concat(parts, "  ·  ")
end

-- The pace summary in a tooltip (the bar and the broker share it).
function ns:PaceTooltip(tip, p)
    p = p or self:Projection()
    tip:AddLine("GoldGoal")
    tip:AddDoubleLine("Target", (p.tier and #self.db.tiers > 1 and (p.tier.name .. "  ") or "") .. self.FormatGold(p.target) .. (p.deadline and ("  by " .. self:DeadlineText()) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddDoubleLine("Saved", string.format("%s  (%s%%)", self.FormatGold(p.total), self.Percent(p.total, p.target) or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    if p.crafting > 0 then
        tip:AddDoubleLine("  gold", self.FormatGold(p.liquid), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine("  in crafting, at cost", (p.craftingEstimated and "~" or "") .. self.FormatGold(p.crafting)
            .. (p.craftingProjected > 0 and ("  (~" .. self.FormatGold(p.craftingProjected) .. " if sold)") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tip:AddDoubleLine("Remaining", self.FormatGold(p.remaining) .. (p.daysLeft and string.format("  over %d day%s", p.daysLeft, p.daysLeft == 1 and "" or "s") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    if #p.tiers > 1 then
        tip:AddLine(" ")
        for _, e in ipairs(p.tiers) do
            tip:AddDoubleLine((e.paced and "|cffffffff" or "|cffaaaaaa") .. e.name .. "  " .. self.FormatGold(e.gold) .. "|r", self:TierText(e), 1, 1, 1, 1, 1, 1)
        end
    end
    tip:AddLine(" ")
    local todayMet = p.quota and p.quota > 0 and p.today >= p.quota
    tip:AddDoubleLine("Today", string.format("%s of %s%s", self.FormatSigned(p.today), p.quota and self.FormatGold(p.quota) or "no quota",
        todayMet and (self.GREEN_HEX .. "  met|r") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    if p.tomorrow then tip:AddDoubleLine("Tomorrow", self.FormatGold(p.tomorrow) .. "/day at this pace", 0.8, 0.8, 0.8, 1, 1, 1) end
    tip:AddDoubleLine("This week", string.format("%s of %s", self.FormatSigned(p.week), p.weekQuota and self.FormatGold(p.weekQuota) or "no quota"), 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddLine(" ")
    tip:AddDoubleLine("7-day average", self.FormatGold(p.avg7) .. "/day", 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddDoubleLine("30-day average", self.FormatGold(p.avg30) .. "/day", 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddLine(self:StatusText(p), 1, 1, 1, true)
    tip:AddLine(" ")
    tip:AddLine("|cff888888Click: open the window. Right-click: daily / weekly.|r")
end

-------------------------------------------------------------------------------
-- Defaults that need the clock, and migrations
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    local db = ns.db
    -- schema 2: the tier ladder, and the deadline is the expansion's end
    -- (the mount is sold until then), not the season's
    if (db.schema or 1) < 2 then
        db.tiers = CopyTiers(ns.TIER_PRESETS.ladder)
        db.tierIndex = 1
        db.targetPreset = "ladder"
        if db.deadlinePreset == "season" then db.deadlinePreset = "expansion" end
        db.schema = 2
    end
    -- schema 3: the instance rule's default became "smart"
    if (db.schema or 1) < 3 then
        if db.bar.instanceMode == "group" then db.bar.instanceMode = "smart" end
        db.schema = 3
    end
    if not db.tiers or #db.tiers == 0 then
        db.tiers = CopyTiers(ns.TIER_PRESETS.ladder)
        db.tierIndex = 1
    end
    ns:ApplyTier()
    -- a guessed deadline follows the shipped guess when that changes
    local guess = ns.DEADLINE_GUESSES[db.deadlinePreset]
    if guess and (not db.deadline or db.deadlineGuess ~= guess) then
        db.deadline = ns:DeadlineFromDate(guess)
        db.deadlineGuess = guess
    end
end)

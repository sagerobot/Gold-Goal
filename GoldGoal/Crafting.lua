-- GoldGoal: the crafting position, from CraftSimPL's working-capital API.
-- Reagents bought and crafts not yet sold are wealth at what they cost, so
-- buying reagents is not spending and a sale counts as its profit. One entry
-- per connected realm; only the realm you are on refreshes. CraftSimPL's
-- projected figures are carried along for display and never booked.
local _, ns = ...

function ns:HasCraftingAPI()
    local api = CraftSimPL and CraftSimPL.API
    return (api and api.GetWorkingCapital) and true or false
end

-- One reading of the current realm's working capital, or nil.
function ns:ReadWorkingCapital()
    if not self:HasCraftingAPI() then return nil end
    local api = CraftSimPL.API
    local ok, wc = pcall(api.GetWorkingCapital, api)
    if not ok or type(wc) ~= "table" or type(wc.realmKey) ~= "string" then return nil end
    local function n(v) return ns.Num(v) or 0 end
    return {
        realm = wc.realmKey, openBatches = n(wc.openBatches),
        stock = n(wc.stockAtCost), pools = n(wc.poolsAtCost), estimated = wc.estimated and true or false,
        listedNet = n(wc.listedNet), presumedSoldNet = n(wc.presumedSoldNet), restNet = n(wc.restNet), unpricedQty = n(wc.unpricedQty),
        resetAt = n(wc.resetAt),
    }
end

function ns.CraftingEntryAtCost(e)
    return (e.stock or 0) + (e.pools or 0)
end

function ns.CraftingEntryProjected(e)
    return (e.listedNet or 0) + (e.presumedSoldNet or 0) + (e.restNet or 0)
end

function ns:CountsCrafting()
    return self.db.countCrafting ~= false
end

function ns:HasCraftingData()
    return self.db and next(self.db.crafting) ~= nil or false
end

-- What the wealth total counts: every realm's stock and pools at cost.
function ns:CraftingAtCost()
    if not self.db or not self:CountsCrafting() then return 0 end
    local sum = 0
    for _, e in pairs(self.db.crafting) do sum = sum + ns.CraftingEntryAtCost(e) end
    return sum
end

-- The same sum whether or not it is counted (for the "not counted" note).
function ns:CraftingAtCostAll()
    local sum = 0
    for _, e in pairs(self.db.crafting) do sum = sum + ns.CraftingEntryAtCost(e) end
    return sum
end

-- What CraftSimPL thinks it would fetch (display only).
function ns:CraftingProjected()
    if not self.db then return 0 end
    local sum = 0
    for _, e in pairs(self.db.crafting) do sum = sum + ns.CraftingEntryProjected(e) end
    return sum
end

function ns:CraftingEstimated()
    for _, e in pairs(self.db.crafting) do if e.estimated then return true end end
    return false
end

-- Realm keys with a crafting entry, sorted.
function ns:CraftingRealms()
    local list = {}
    for key in pairs(self.db.crafting) do list[#list + 1] = key end
    table.sort(list)
    return list
end

-- Records the current realm's position. The first reading of a realm and a
-- CraftSimPL reset shift the baseline; everything else is profit or loss.
function ns:ObserveCrafting()
    if not self.db then return end
    local wc = self:ReadWorkingCapital()
    if not wc then return end
    local db = self.db
    local e = db.crafting[wc.realm]
    local delta = 0
    local counted = self:CountsCrafting()
    if not e then
        e = {}
        db.crafting[wc.realm] = e
        if counted then delta = ns.CraftingEntryAtCost(wc) end
    elseif (e.resetAt or 0) ~= wc.resetAt then
        if counted then delta = ns.CraftingEntryAtCost(wc) - ns.CraftingEntryAtCost(e) end
    end
    -- a short log of what moved, for /gg crafting
    local log = self.craftingLog or {}
    self.craftingLog = log
    table.insert(log, 1, { at = time(), realm = wc.realm, stock = wc.stock - (e.stock or 0), pools = wc.pools - (e.pools or 0),
        first = e.stock == nil, baseline = delta })
    while #log > 12 do table.remove(log) end
    for k, v in pairs(wc) do e[k] = v end
    e.updated = time()
    self:Touch(delta, delta)
end

-- The last readings: when, and how much the stock and the pools moved.
function ns:PrintCraftingLog()
    self:Print("Crafting stock readings this session (newest first):")
    local log = self.craftingLog or {}
    if #log == 0 then print("  none yet") end
    for _, l in ipairs(log) do
        print(string.format("  %s  %s  stock %s  pools %s%s", date("%H:%M:%S", l.at), l.realm,
            self.StripColor(self.FormatSigned(l.stock)), self.StripColor(self.FormatSigned(l.pools)),
            l.first and "  (first reading: baseline)" or (l.baseline ~= 0 and "  (baseline shift)" or "")))
    end
    for _, key in ipairs(self:CraftingRealms()) do
        local e = self.db.crafting[key]
        print(string.format("  now %s: stock %s, pools %s, %d open batch(es)%s", key, self.FormatGold(e.stock), self.FormatGold(e.pools), e.openBatches or 0,
            e.estimated and ", some costs estimated" or ""))
    end
end

function ns:SetCountCrafting(on)
    on = on and true or false
    if self:CountsCrafting() == on then return end
    local before = self:CraftingAtCost()
    self.db.countCrafting = on
    local delta = self:CraftingAtCost() - before
    self:Touch(delta, delta)
    self:Fire("SETTINGS_CHANGED")
end

function ns:ForgetCraftingRealm(key)
    local e = self.db.crafting[key]
    if not e then return end
    local delta = self:CountsCrafting() and -ns.CraftingEntryAtCost(e) or 0
    self.db.crafting[key] = nil
    self:Touch(delta, delta)
end

-- The breakdown of one realm's entry in a tooltip.
function ns:CraftingTooltip(tip, key)
    local e = self.db.crafting[key]
    if not e then return end
    local tilde = e.estimated and "~" or ""
    tip:AddLine("Crafting stock  |cffaaaaaa" .. key .. "|r")
    tip:AddDoubleLine("Reagents (cost pools)", self.FormatGold(e.pools), 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddDoubleLine(string.format("Unsold crafts, %d open batch%s", e.openBatches or 0, (e.openBatches or 0) == 1 and "" or "es"), tilde .. self.FormatGold(e.stock), 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddDoubleLine("At cost, counted", self:CountsCrafting() and self.FormatGold(ns.CraftingEntryAtCost(e)) or "|cff888888not counted|r", 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddLine(" ")
    tip:AddDoubleLine("Listed on the AH", "~" .. self.FormatGold(e.listedNet), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    if (e.presumedSoldNet or 0) > 0 then tip:AddDoubleLine("Sold, gold awaited", "~" .. self.FormatGold(e.presumedSoldNet), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
    tip:AddDoubleLine("Not yet listed", "~" .. self.FormatGold(e.restNet) .. ((e.unpricedQty or 0) > 0 and string.format(" (%d unpriced)", e.unpricedQty) or ""), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    tip:AddDoubleLine("If it all sells", "~" .. self.FormatGold(ns.CraftingEntryProjected(e)), 0.8, 0.8, 0.8, 1, 1, 1)
    if e.estimated then tip:AddLine("|cffff9900~ some reagent costs are CraftSim estimates.|r", 1, 1, 1, true) end
    tip:AddLine("Counted at cost, so buying reagents is not spending and a sale counts as its profit. Projections are CraftSimPL's and are never booked.", 0.8, 0.8, 0.8, true)
    tip:AddLine("|cff888888Untick to leave crafting out of the total. Right-click to forget this realm.|r", 1, 1, 1, true)
end

ns:On("LOGIN", function()
    if not ns:HasCraftingAPI() then return end
    ns:ObserveCrafting()
    local api = CraftSimPL.API
    local function Changed() ns:Schedule("crafting", 0.5, function() ns:ObserveCrafting() end) end
    if api.RegisterWorkingCapitalListener then
        pcall(api.RegisterWorkingCapitalListener, api, Changed)
    elseif CraftSimPL.RegisterInternal and CraftSimPL.CONST and CraftSimPL.CONST.EVENTS then
        local E = CraftSimPL.CONST.EVENTS
        for _, ev in ipairs({ E.LEDGER_UPDATED, E.POOLS_UPDATED }) do
            if ev then pcall(CraftSimPL.RegisterInternal, CraftSimPL, ev, Changed) end
        end
    end
end)

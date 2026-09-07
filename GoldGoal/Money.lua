-- GoldGoal: gold formatting, and reading gold from the client and from
-- Syndicator (Baganator's tracking) when it is loaded.
local _, ns = ...

local COPPER = 10000
ns.COPPER = COPPER

ns.GREEN_HEX = "|cff55dd55"
ns.RED_HEX = "|cffff5555"
ns.GREY_HEX = "|cff888888"

-------------------------------------------------------------------------------
-- Formatting. Amounts are copper; everything shows whole gold.
-------------------------------------------------------------------------------
function ns.Gold(copper)
    copper = copper or 0
    local sign = copper < 0 and -1 or 1
    return sign * math.floor(math.abs(copper) / COPPER)
end

local function Commas(n)
    local s = tostring(math.floor(math.abs(n)))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
ns.Commas = Commas

-- "1,234,567g"
function ns.FormatGold(copper)
    local g = ns.Gold(copper)
    return (g < 0 and "-" or "") .. Commas(g) .. "g"
end

-- "1.23M", "845k", "8,450g": for the bar and broker text.
function ns.FormatGoldShort(copper)
    local g = ns.Gold(copper)
    local sign, a = g < 0 and "-" or "", math.abs(g)
    if a >= 1000000 then return string.format("%s%.2fM", sign, a / 1000000) end
    if a >= 10000 then return string.format("%s%dk", sign, math.floor(a / 1000 + 0.5)) end
    return sign .. Commas(a) .. "g"
end

-- "+8,450g" in green, "-1,200g" in red, "0g" in grey.
function ns.FormatSigned(copper, short)
    local g = ns.Gold(copper)
    local text = short and ns.FormatGoldShort(copper) or ns.FormatGold(copper)
    if g > 0 then return ns.GREEN_HEX .. "+" .. text .. "|r" end
    if g < 0 then return ns.RED_HEX .. text .. "|r" end
    return ns.GREY_HEX .. text .. "|r"
end

-- "5000000", "5,000,000", "5m", "4.5m", "500k", "12,000g" -> copper, or nil.
function ns.ParseGold(text)
    if type(text) ~= "string" then return nil end
    local s = text:lower():gsub("[,%s_]", ""):gsub("g$", "")
    local num, suffix = s:match("^(%d+%.?%d*)([mk]?)$")
    if not num then return nil end
    local mult = (suffix == "m" and 1000000) or (suffix == "k" and 1000) or 1
    local gold = math.floor(tonumber(num) * mult + 0.5)
    if gold <= 0 then return nil end
    return gold * COPPER
end

function ns.Percent(value, max)
    if not max or max <= 0 then return nil end
    return math.floor(value / max * 100 + 0.5)
end

-------------------------------------------------------------------------------
-- Reading gold
-------------------------------------------------------------------------------
function ns:ReadPlayerMoney()
    return ns.Num(GetMoney())
end

-- The warband bank's gold, readable anywhere once the account inventory is
-- unlocked, or nil to keep the stored figure.
function ns:ReadWarbandMoney()
    if not (C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType and Enum.BankType.Account) then return nil end
    if C_PlayerInfo and C_PlayerInfo.HasAccountInventoryLock and not C_PlayerInfo.HasAccountInventoryLock() then return nil end
    local ok, v = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if not ok then return nil end
    return ns.Num(v)
end

-- What Syndicator remembers: { ["Name-Realm"] = { money, class, name, realm } }
-- and the warband bank's gold, or nil without it. Read only.
function ns:ReadSyndicator()
    local api = Syndicator and Syndicator.API
    if not (api and api.GetAllCharacters and api.GetCharacter) then return nil end
    if api.IsReady and not api.IsReady() then return nil end
    local ok, names = pcall(api.GetAllCharacters)
    if not ok or type(names) ~= "table" then return nil end
    local out = {}
    for _, name in ipairs(names) do
        local ok2, data = pcall(api.GetCharacter, name)
        if ok2 and type(data) == "table" and ns.Num(data.money) then
            local d = type(data.details) == "table" and data.details or {}
            out[name] = { money = data.money, class = d.className, name = d.character, realm = d.realm }
        end
    end
    local wb
    if api.GetWarband then
        local ok3, w = pcall(api.GetWarband, 1)
        if ok3 and type(w) == "table" then wb = ns.Num(w.money) end
    end
    return out, wb
end

function ns:HasSyndicator()
    return (Syndicator and Syndicator.API and Syndicator.API.GetAllCharacters) and true or false
end

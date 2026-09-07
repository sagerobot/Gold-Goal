-- GoldGoal: a LibDataBroker data object, so the quota can sit on any broker
-- display: EllesmereUI's data bar shows it as a "Broker Plugin" block.
local _, ns = ...

local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
local obj

ns.BROKER_MODES = { "daily", "weekly", "total" }

-- "8,450g / 14,000g (60%)", "52k / 124k (42%)" or "3.21M / 5.00M (64%)".
function ns:BrokerText(p)
    p = p or self:Projection()
    local mode = self.db.broker.mode
    local value, max
    if mode == "total" then
        value, max = p.total, p.target
    elseif mode == "weekly" then
        value, max = p.week, p.weekQuota
    else
        value, max = p.today, p.quota
    end
    if not max then return self.FormatGoldShort(value) .. " (no deadline)" end
    local pct = math.max(0, self.Percent(value, max) or 0)
    return string.format("%s / %s (%d%%)", self.FormatGoldShort(value), self.FormatGoldShort(max), pct)
end

function ns:RefreshBroker()
    if obj and self.db then obj.text = self:BrokerText() end
end

function ns:SetBrokerMode(mode)
    self.db.broker.mode = mode
    self:RefreshBroker()
    self:Fire("SETTINGS_CHANGED")
end

function ns:CycleBrokerMode()
    local modes = self.BROKER_MODES
    for i, m in ipairs(modes) do
        if m == self.db.broker.mode then
            self:SetBrokerMode(modes[i % #modes + 1])
            return
        end
    end
    self:SetBrokerMode(modes[1])
end

if LDB then
    ns:On("DB_READY", function()
        obj = LDB:NewDataObject("GoldGoal", {
            type = "data source",
            label = "GoldGoal",
            icon = "Interface\\AddOns\\GoldGoal\\media\\coin64.png",
            text = "GoldGoal",
            OnClick = function(_, button)
                if button == "RightButton" then ns:CycleBrokerMode() else ns:ToggleWindow() end
            end,
            OnTooltipShow = function(tip) ns:PaceTooltip(tip) end,
        })
        ns.brokerObject = obj
        ns:RefreshBroker()
    end)
    ns:On("WEALTH_CHANGED", function() ns:RefreshBroker() end)
    ns:On("SETTINGS_CHANGED", function() ns:RefreshBroker() end)
end

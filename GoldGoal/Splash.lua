-- GoldGoal: the gold splash. A combat-text style pop in the middle of the
-- screen whenever the total grows by more than a threshold, bigger and
-- louder the more it is. Gains are merged: everything that arrives within
-- a quiet window is one event.
-- The amount is the net change in what the addon counts, so with
-- CraftSimPL a sale shows its profit and a reagent buy shows nothing. A
-- sale (gold in while stock leaves at cost, the mailbox mostly) shows
-- however small it is, with its margin on cost under the amount.
--
-- In the shops -- the auction house, vendors, the mailbox, the profession
-- window, crafting orders -- gold is mostly only moving around: reagents
-- out, the same gold back as sale mail. By default what moves in there is
-- counted but never celebrated (db.splash.shops == "quiet"). A window on
-- screen is what counts as open; the events are only a fallback for the
-- ones whose frame is not loaded.
--
-- Crafting itself moves no gold at all: a batch whose gold did not budge
-- while the stock did is CraftSimPL revaluing the position, and that is
-- never income, whatever window is open and whatever the shop rule says.
--
-- A goal banked, the day's quota met and a sale's profit still show
-- through either rule; a percent mark is kept for the next gain out in
-- the world rather than eaten.
--
-- Every level is the user's (db.splash.levels, up to SPLASH_MAX_LEVELS):
-- the gold it starts at, what it says, its text size and hold time, its
-- sound, colour, glow and frame. So are how often the percent marks fire,
-- the celebrations, losses, the shop rule and the bar's hide rules.
local _, ns = ...
local Style = ns.Style

local frame, vignette
local pending, count, lastAt, armed = 0, 0, 0, false
local pendingGold, pendingStock = 0, 0 -- the split of `pending`: gold moved, and stock moved at cost
local pendingQuiet = nil               -- the shop window that was open when part of `pending` arrived

ns.SPLASH_MAX_LEVELS = 10

ns.SPLASH_SOUNDS = { none = "None", coin = "Coin", epic = "Epic toast", legendary = "Legendary toast" }
ns.SPLASH_SOUND_ORDER = { "none", "coin", "epic", "legendary" }
local SOUND_IDS = { coin = 120, epic = 31578, legendary = 63971 } -- LOOT_WINDOW_COIN_SOUND, UI_EPICLOOT_TOAST, UI_LEGENDARY_LOOT_TOAST
local SOUND_KEYS = { coin = "LOOT_WINDOW_COIN_SOUND", epic = "UI_EPICLOOT_TOAST", legendary = "UI_LEGENDARY_LOOT_TOAST" }

ns.SPLASH_COLORS = {
    white = { 1, 1, 1 }, gold = { 1, 0.82, 0.1 }, accent = "accent", green = { 0.35, 0.9, 0.4 },
    blue = { 0.4, 0.7, 1 }, purple = { 0.75, 0.45, 1 }, orange = { 1, 0.55, 0.15 }, red = { 1, 0.35, 0.35 },
}
ns.SPLASH_COLOR_NAMES = { white = "White", gold = "Gold", accent = "Accent", green = "Green", blue = "Blue", purple = "Purple", orange = "Orange", red = "Red" }
ns.SPLASH_COLOR_ORDER = { "white", "gold", "accent", "green", "blue", "purple", "orange", "red" }

-- The shipped levels.
ns.SPLASH_LEVEL_DEFAULTS = {
    { gold = 500 * 10000,    flavor = "",           size = 22, hold = 1.4, sound = "coin",      glow = false, frame = "none",   color = "gold" },
    { gold = 1000 * 10000,   flavor = "",           size = 28, hold = 1.6, sound = "coin",      glow = false, frame = "none",   color = "gold" },
    { gold = 5000 * 10000,   flavor = "",           size = 36, hold = 1.8, sound = "coin",      glow = true,  frame = "none",   color = "gold" },
    { gold = 10000 * 10000,  flavor = "",           size = 44, hold = 2.1, sound = "epic",      glow = true,  frame = "none",   color = "gold" },
    { gold = 25000 * 10000,  flavor = "Nice!",      size = 54, hold = 2.5, sound = "epic",      glow = true,  frame = "subtle", color = "gold" },
    { gold = 50000 * 10000,  flavor = "Jackpot!",   size = 60, hold = 2.5, sound = "epic",      glow = true,  frame = "gold",   color = "gold" },
    { gold = 100000 * 10000, flavor = "Legendary!", size = 66, hold = 2.5, sound = "legendary", glow = true,  frame = "liquid", color = "gold" },
}

-- The windows where gold is mostly only moving around: reagents bought,
-- crafts posted, the same gold back as sale mail. `frame` is the global
-- the hold is checked against when an open event is not followed by its
-- close; the load-on-demand ones are nil until first use, which reads as
-- "cannot tell" and is left alone. Player-to-player trade is deliberately
-- absent: that is real income and should splash.
-- A window on screen is the signal that matters; the events are a
-- fallback for the ones whose frame is not loaded (or is named something
-- we do not know). Relying on the events alone fails silently when a
-- client stops sending one, which is exactly the bug you cannot see.
local SHOPS = {
    { key = "mail",     name = "the mailbox",           open = "MAIL_SHOW",                    close = "MAIL_CLOSED",
      frames = { "MailFrame", "OpenMailFrame" } },
    { key = "merchant", name = "a vendor",              open = "MERCHANT_SHOW",                close = "MERCHANT_CLOSED",
      frames = { "MerchantFrame" } },
    { key = "auction",  name = "the auction house",     open = "AUCTION_HOUSE_SHOW",           close = "AUCTION_HOUSE_CLOSED",
      frames = { "AuctionHouseFrame", "AuctionFrame" } },
    { key = "trade",    name = "the profession window", open = "TRADE_SKILL_SHOW",             close = "TRADE_SKILL_CLOSE",
      frames = { "ProfessionsFrame", "TradeSkillFrame", "ProfessionsBookFrame" } },
    { key = "orders",   name = "crafting orders",       open = "CRAFTINGORDERS_SHOW_CUSTOMER", close = "CRAFTINGORDERS_HIDE_CUSTOMER",
      frames = { "ProfessionsCustomerOrdersFrame" } },
    { key = "crafter",  name = "crafting orders",       open = "CRAFTINGORDERS_SHOW_CRAFTER",  close = "CRAFTINGORDERS_HIDE_CRAFTER",
      frames = { "ProfessionsFrame" } },
}
local shopOpen = {}     -- [key] = the SHOPS entry, while its window is up

-- What happens to gold that moves while one of them is open.
ns.SPLASH_SHOP_MODES = { quiet = "Stay quiet", merge = "One number when you leave", show = "Show as it happens" }
ns.SPLASH_SHOP_ORDER = { "quiet", "merge", "show" }

-- The frame around the screen a level can light: liquid gold flowing
-- along the edges, at three strengths. (The keys are older than the
-- names: "gold" was once a still gradient.)
ns.SPLASH_FRAMES = { none = "None", subtle = "Ripple", gold = "Liquid gold", liquid = "Torrent" }
ns.SPLASH_FRAME_ORDER = { "none", "subtle", "gold", "liquid" }
ns.LIQUID_TEXTURE = "Interface\\AddOns\\GoldGoal\\media\\liquid.png"
-- strip height and width as a share of the screen, the brightness range
-- (by text size), the flow speed in tile lengths a second, and layers
local FRAME_STYLES = {
    subtle = { h = 0.06, w = 0.04, aMin = 0.30, aMax = 0.55, speed = 0.10, layers = 1 },
    gold   = { h = 0.12, w = 0.08, aMin = 0.60, aMax = 0.90, speed = 0.18, layers = 1 },
    liquid = { h = 0.18, w = 0.12, aMin = 0.90, aMax = 1.00, speed = 0.32, layers = 2 },
}

local function Now()
    return GetTime and GetTime() or time()
end

-- The coin next to the amount: our own 128px art, or the game's.
ns.SPLASH_ICONS = { custom = "GoldGoal coin", pile = "Gold pile (game icon)", classic = "Money icon (game)", none = "None" }
ns.SPLASH_ICON_ORDER = { "custom", "pile", "classic", "none" }
ns.COIN_TEXTURE = "Interface\\AddOns\\GoldGoal\\media\\coin.png"
ns.COIN_TEXTURE_SMALL = "Interface\\AddOns\\GoldGoal\\media\\coin64.png"

-- texture, then its crop, or nil for no icon.
function ns:SplashIcon()
    local key = (self.db.look or {}).splashIcon or "custom"
    if key == "none" then return nil end
    if key == "pile" then return "Interface\\Icons\\INV_Misc_Coin_01", 0.08, 0.92, 0.08, 0.92 end
    if key == "classic" then return "Interface\\MoneyFrame\\UI-GoldIcon", 0, 1, 0, 1 end
    return self.COIN_TEXTURE, 0, 1, 0, 1
end

-- The user's levels, in ascending order, every field filled in. A level
-- saved by an earlier version (gold and saying only) takes its sound, glow
-- and frame from the old "from level" settings, so nothing changes look.
function ns:SplashLevels()
    local cfg = self.db.splash
    local D = self.SPLASH_LEVEL_DEFAULTS
    if type(cfg.levels) ~= "table" or #cfg.levels == 0 then cfg.levels = self.DeepCopy(D) end
    while #cfg.levels > self.SPLASH_MAX_LEVELS do table.remove(cfg.levels) end
    for i, l in ipairs(cfg.levels) do
        local d = D[i] or D[#D]
        local extra = math.max(0, i - #D)
        if not self.Num(l.gold) or l.gold <= 0 then l.gold = d.gold end
        if l.flavor == nil then l.flavor = d.flavor end
        if not self.Num(l.size) then l.size = math.min(80, d.size + extra * 6) end
        if not self.Num(l.hold) then l.hold = math.min(10, d.hold + extra * 0.4) end
        if l.sound == nil then l.sound = (i >= (cfg.soundFrom or 1)) and d.sound or "none" end
        if l.glow == nil then l.glow = i >= (cfg.glowFrom or 3) end
        -- a frame saved as on/off by an earlier version is the golden one
        if l.frame == nil then l.frame = (i >= (cfg.frameFrom or 4)) and "gold" or "none"
        elseif l.frame == true then l.frame = "gold"
        elseif l.frame == false or not self.SPLASH_FRAMES[l.frame] then l.frame = "none" end
        if l.color == nil or not self.SPLASH_COLORS[l.color] then l.color = d.color end
    end
    return cfg.levels
end

-- Writes levels back, sorted by gold, and keeps the old threshold field in step.
function ns:SetSplashLevels(list)
    local out = {}
    for i, l in ipairs(list) do
        if i > self.SPLASH_MAX_LEVELS then break end
        out[#out + 1] = {
            gold = l.gold, flavor = l.flavor or "",
            size = math.max(12, math.min(80, l.size or 22)), hold = math.max(0.3, math.min(10, l.hold or 1.5)),
            sound = self.SPLASH_SOUNDS[l.sound] and l.sound or "none",
            glow = l.glow and true or false,
            frame = (l.frame == true and "gold") or (self.SPLASH_FRAMES[l.frame] and l.frame) or "none",
            color = self.SPLASH_COLORS[l.color] and l.color or "white",
        }
    end
    if #out == 0 then out[1] = self.DeepCopy(self.SPLASH_LEVEL_DEFAULTS[1]) end
    table.sort(out, function(a, b) return a.gold < b.gold end)
    self.db.splash.levels = out
    self.db.splash.threshold = out[1].gold
    self:Fire("SETTINGS_CHANGED")
end

-- A new level above the top one, in its style but a step bigger.
function ns:AddSplashLevel()
    local levels = self:SplashLevels()
    if #levels >= self.SPLASH_MAX_LEVELS then return false end
    local top = levels[#levels]
    local list = self.DeepCopy(levels)
    list[#list + 1] = { gold = top.gold * 2, flavor = "", size = math.min(80, top.size + 6), hold = math.min(10, top.hold + 0.4),
        sound = top.sound, glow = top.glow, frame = top.frame, color = top.color }
    self:SetSplashLevels(list)
    return true
end

function ns:RemoveSplashLevel(i)
    local levels = self:SplashLevels()
    if #levels <= 1 or not levels[i] then return false end
    local list = self.DeepCopy(levels)
    table.remove(list, i)
    self:SetSplashLevels(list)
    return true
end

function ns:SplashThreshold()
    return self:SplashLevels()[1].gold
end

function ns:SplashLevel(amount)
    local level = 0
    for i, l in ipairs(self:SplashLevels()) do
        if amount >= l.gold then level = i end
    end
    return level
end

-- Level n, or the top one when there are fewer.
local function LevelAtMost(n)
    return math.min(n, #ns:SplashLevels())
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------
local function SetFontSize(fs, size, flags)
    local font = fs:GetFont() or STANDARD_TEXT_FONT
    fs:SetFont(font, size, flags or "")
end

local function BuildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "GoldGoalSplash", UIParent)
    ns.Splash = frame
    frame:SetSize(420, 90)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    frame:Hide()

    frame.Glow = frame:CreateTexture(nil, "BACKGROUND")
    frame.Glow:SetTexture("Interface\\Cooldown\\star4")
    frame.Glow:SetBlendMode("ADD")
    frame.Glow:SetPoint("CENTER", 0, 4)
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Amount = Style.Text(frame, 22)
    frame.Amount:SetPoint("CENTER", 10, 6)
    frame.Icon:SetPoint("RIGHT", frame.Amount, "LEFT", -6, 0)
    frame.Sub = Style.Text(frame, 13)
    frame.Sub:SetPoint("TOP", frame.Amount, "BOTTOM", 0, -4)
    frame.Progress = Style.Text(frame, 12, 1, 1, 1, 0.85)
    frame.Progress:SetPoint("TOP", frame.Sub, "BOTTOM", 0, -3)

    -- pop in, hold, drift up and fade
    local group = frame:CreateAnimationGroup()
    frame.Anim = group
    local fadeIn = group:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
    local pop = group:CreateAnimation("Scale")
    if pop.SetScaleFrom then pop:SetScaleFrom(1.6, 1.6); pop:SetScaleTo(1, 1) else pop:SetScale(0.625, 0.625) end
    pop:SetDuration(0.2); pop:SetOrder(1)
    local drift = group:CreateAnimation("Translation")
    drift:SetOffset(0, 40); drift:SetDuration(1.2); drift:SetOrder(2)
    local fadeOut = group:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.9); fadeOut:SetOrder(2); fadeOut:SetSmoothing("IN")
    frame.Drift, frame.FadeOut = drift, fadeOut
    group:SetScript("OnFinished", function() frame:Hide(); frame:SetAlpha(0) end)

    -- liquid gold round the screen: four strips carrying a tiling texture
    -- of gold streaks, drawn additively (they only brighten) and scrolled
    -- along the edges while shown. Two layers; the second, finer and
    -- running the other way, comes in for the strongest style.
    vignette = CreateFrame("Frame", nil, UIParent)
    vignette:SetAllPoints(UIParent)
    vignette:SetFrameStrata("BACKGROUND")
    vignette:EnableMouse(false)
    vignette:Hide()
    local function NewLayer(layer)
        local set = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = vignette:CreateTexture(nil, "ARTWORK", nil, layer)
            t:SetTexture(ns.LIQUID_TEXTURE, "REPEAT", "CLAMP")
            t:SetBlendMode("ADD")
            if side == "TOP" then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
            elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
            elseif side == "LEFT" then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT")
            else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT") end
            t.side = side
            t.span = 4
            t:Hide()
            set[#set + 1] = t
        end
        return set
    end
    vignette.Liquid = NewLayer(1)
    vignette.Liquid2 = NewLayer(2)
    for _, t in ipairs(vignette.Liquid2) do t:SetAlpha(0.6) end
    -- the tile's s axis runs along the edge (and wraps), its t axis from
    -- the edge inwards; each side maps that onto its own corners so the
    -- flow goes clockwise round the screen (a negative u runs it back)
    local function Coords(t, u, k)
        if t.side == "TOP" then t:SetTexCoord(-u, 0, -u, 1, k - u, 0, k - u, 1)
        elseif t.side == "RIGHT" then t:SetTexCoord(-u, 1, k - u, 1, -u, 0, k - u, 0)
        elseif t.side == "BOTTOM" then t:SetTexCoord(u, 1, u, 0, u + k, 1, u + k, 0)
        else t:SetTexCoord(u, 0, u + k, 0, u, 1, u + k, 1) end
    end
    local function LiquidCoords(self)
        local u = self.flow or 0
        for _, t in ipairs(self.Liquid) do Coords(t, u, t.span) end
        for _, t in ipairs(self.Liquid2) do Coords(t, -u * 1.3, t.span) end
    end
    vignette.LiquidCoords = LiquidCoords
    vignette:SetScript("OnUpdate", function(self, elapsed)
        self.flow = ((self.flow or 0) + elapsed * (self.speed or 0.18)) % 1
        LiquidCoords(self)
    end)
    local vg = vignette:CreateAnimationGroup()
    vignette.Anim = vg
    local vin = vg:CreateAnimation("Alpha")
    vin:SetFromAlpha(0); vin:SetToAlpha(1); vin:SetDuration(0.2); vin:SetOrder(1)
    local vout = vg:CreateAnimation("Alpha")
    vout:SetFromAlpha(1); vout:SetToAlpha(0); vout:SetDuration(1.5); vout:SetOrder(2)
    vignette.FadeOut = vout
    vg:SetScript("OnFinished", function() vignette:Hide() end)
    return frame
end

function ns:AnchorSplash()
    if not frame then return end
    local cfg = self.db.splash
    frame:SetScale(cfg.scale or 1)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, cfg.offsetY or 150)
end

-- Lights the frame in a style: the strips' width, brightness and speed
-- follow the style, the brightness the text size too, and the flow starts.
local function ShowFrame(style, size, hold)
    local st = FRAME_STYLES[style] or FRAME_STYLES.gold
    local screenH, screenW = UIParent:GetHeight() or 768, UIParent:GetWidth() or 1024
    local fh, fw = screenH * st.h, screenW * st.w
    local alpha = math.max(st.aMin, math.min(st.aMax, size / 70))
    local function Fit(set, shown, finer)
        for _, t in ipairs(set) do
            t:SetShown(shown)
            if t.side == "TOP" or t.side == "BOTTOM" then
                t:SetHeight(fh)
                t.span = math.max(1, screenW / (fh * 4)) * finer
            else
                t:SetWidth(fw)
                t.span = math.max(1, screenH / (fw * 4)) * finer
            end
        end
    end
    Fit(vignette.Liquid, true, 1)
    Fit(vignette.Liquid2, st.layers >= 2, 1.7)
    vignette.style = style
    vignette.speed = st.speed
    vignette.flow = 0
    vignette.LiquidCoords(vignette)
    vignette:SetAlpha(alpha)
    vignette.FadeOut:SetStartDelay(hold)
    vignette:Show()
    vignette.Anim:Play()
end

-- A level's colour as r, g, b.
function ns:SplashColor(key)
    local c = self.SPLASH_COLORS[key] or self.SPLASH_COLORS.white
    if c == "accent" then return Style.Accent() end
    return c[1], c[2], c[3]
end

-- What a gain moved, one clause: "+23% of today's quota (81%)" for the
-- everyday amounts, "+1.2% of Goal (64.3%)" once it is a real share of
-- the paced tier. The bracket is where that stands now.
function ns:ProgressLine(p, amount)
    local name = "Goal"
    local tierShare = (p.target and p.target > 0) and (amount / p.target * 100) or 0
    if p.quota and p.quota > 0 and tierShare < 0.5 then
        local share = amount / p.quota * 100
        local now = math.max(0, math.floor(p.today / p.quota * 100 + 0.5))
        return string.format("%s of today's quota (%d%%)", math.abs(share) < 1 and "<1%" or string.format("%+d%%", math.floor(share + 0.5)), now)
    end
    if p.target and p.target > 0 then
        return string.format("%s of %s (%.1f%%)", tierShare < 0.05 and "<0.1%" or string.format("%+.1f%%", tierShare), name, p.total / p.target * 100)
    end
    return ""
end

-- Shows "+12,345g" at the level the amount earns (or `opts.level`), with
-- `opts.subtitle` under it in place of the level's saying and
-- `opts.progress` under that. `opts.title` replaces the amount (a
-- progress mark of its own: "64%"); `opts.loss` paints it red and
-- leaves out sound, glow and frame.
function ns:ShowSplash(amount, opts)
    opts = opts or {}
    BuildFrame()
    self:AnchorSplash()
    local cfg, look = self.db.splash, self.db.look or {}
    local levels = self:SplashLevels()
    local level = opts.level or self:SplashLevel(math.abs(amount))
    level = math.max(1, math.min(#levels, level))
    local L = levels[level]
    local flavor = L.flavor
    if flavor == "" then flavor = nil end
    local sub = opts.subtitle or flavor
    self.lastSplash = { amount = amount, level = level, subtitle = sub, title = opts.title, progress = opts.progress, loss = opts.loss, size = L.size }

    frame.Anim:Stop()
    vignette.Anim:Stop()
    local r, g, b
    if opts.loss then r, g, b = 1, 0.35, 0.35 elseif opts.title then r, g, b = 1, 0.82, 0.1 else r, g, b = self:SplashColor(L.color) end
    local size = L.size
    local flags = size >= 40 and "THICKOUTLINE" or size >= 32 and "OUTLINE" or ""
    SetFontSize(frame.Amount, size, flags)
    frame.Amount:SetTextColor(r, g, b, 1)
    frame.Amount:SetText(opts.title or ((amount >= 0 and "+" or "") .. self.FormatGold(amount)))
    local tex, l, rr, t, b = self:SplashIcon()
    if tex then
        frame.Icon:SetTexture(tex)
        frame.Icon:SetTexCoord(l, rr, t, b)
        local iconSize = size * (tex == self.COIN_TEXTURE and 0.95 or 0.8)
        frame.Icon:SetSize(iconSize, iconSize)
    end
    frame.Icon:SetShown(tex and not opts.title and true or false)
    frame.Sub:SetText(sub or "")
    SetFontSize(frame.Sub, math.max(12, math.floor(size * 0.45)), size >= 40 and "OUTLINE" or "")
    frame.Sub:SetTextColor(1, 1, 1, opts.subtitle and 1 or 0.8)
    frame.Progress:SetText(opts.progress or "")
    SetFontSize(frame.Progress, math.max(11, math.floor(size * 0.36)), size >= 40 and "OUTLINE" or "")
    local hold = L.hold * (look.splashSpeed or 1)
    local strength = size / 40
    if look.splashGlow ~= false and L.glow and not opts.loss then
        frame.Glow:SetSize(size * 9 * strength, size * 5 * strength)
        frame.Glow:SetVertexColor(1, 0.82, 0.2, math.min(0.6, 0.35 * strength))
        frame.Glow:Show()
    else
        frame.Glow:Hide()
    end
    frame.Drift:SetStartDelay(hold)
    frame.FadeOut:SetStartDelay(hold + 0.3)
    frame:SetAlpha(0)
    frame:Show()
    frame.Anim:Play()
    local style = L.frame
    if type(style) ~= "string" then style = style and "gold" or "none" end
    if cfg.frame == false or opts.loss or not self.SPLASH_FRAMES[style] then style = "none" end
    self.lastSplash.frame = style
    if style ~= "none" then ShowFrame(style, size, hold) end
    if cfg.sound and L.sound ~= "none" and PlaySound and not opts.loss then
        local id = SOUNDKIT and SOUNDKIT[SOUND_KEYS[L.sound]] or SOUND_IDS[L.sound]
        if id then pcall(PlaySound, id, "Master") end
    end
    self:Fire("SPLASH", amount, level, sub)
end

-- A sample at a level, for Settings.
function ns:PreviewSplash(level)
    local levels = self:SplashLevels()
    level = math.max(1, math.min(#levels, level or 1))
    self:ShowSplash(levels[level].gold, { level = level })
end

-- The line under a sale's profit: "43% profit on 830g at cost", or the
-- loss. The percent is the margin on what the stock cost.
function ns.ProfitLine(profit, cost)
    local atCost = ns.FormatGold(cost) .. " at cost"
    if profit == 0 then return "no profit on " .. atCost end
    local pct = math.abs(profit) / cost * 100
    local text = pct < 1 and "<1%" or string.format("%d%%", math.floor(pct + 0.5))
    return string.format("%s %s on %s", text, profit > 0 and "profit" or "loss", atCost)
end

-- A sample sale, for /gg splash profit.
function ns:PreviewProfitSplash()
    local cost = 830 * 10000
    local profit = 357 * 10000
    self:ShowSplash(profit, { subtitle = ns.ProfitLine(profit, cost), level = self:SplashLevel(profit),
        progress = self.db.splash.progress ~= false and self:ProgressLine(self:Projection(), profit) or nil })
end

-------------------------------------------------------------------------------
-- Merging
-------------------------------------------------------------------------------
-- A tier banked since the last splash, once each.
local function NewlyBanked(p)
    local banked = ns.db.bankedTiers
    local name
    for _, e in ipairs(p.tiers) do
        if e.reached and not banked[e.index] then
            banked[e.index] = true
            name = e.name
        end
    end
    return name
end

-- The percent mark of the paced tier crossed since the last one announced
-- (every `markEvery` percent), or nil. A high-water mark: spending and
-- earning it back says nothing until the old mark is passed. A new tier
-- starts the mark at wherever the total stands, so the jump is silent.
local function CrossedMark(p)
    if not (p.target and p.target > 0) then return nil end
    local db = ns.db
    local step = math.max(1, db.splash.markEvery or 1)
    local pct = math.min(100, math.floor(p.total / p.target * 100 / step) * step)
    local mark = db.progressMark
    if not mark or mark.target ~= p.target then
        db.progressMark = { target = p.target, pct = pct }
        return nil
    end
    if pct > mark.pct then
        mark.pct = pct
        return pct
    end
    return nil
end

-- Whether the bar's hide rules keep the splash quiet right now.
local function Suppressed()
    local cfg = ns.db.splash
    if not cfg.followBar then return false end
    if ns.db.bar.hideInCombat and InCombatLockdown() then return true end
    return ns.BarHiddenByInstance and ns:BarHiddenByInstance() or false
end

-- A short log of what came in and what the splash did with it, for
-- /gg splash log.
local function Log(kind, amount, note)
    local log = ns.splashLog or {}
    ns.splashLog = log
    table.insert(log, 1, { at = time(), kind = kind, amount = amount, note = note })
    while #log > 24 do table.remove(log) end
end

-- Whether a shop window is open, pruning any whose frame says otherwise:
-- a missed close event would otherwise keep the splash quiet for the rest
-- of the session. Called on every gain and every flush, not only from the
-- armed timer, so a stale hold is caught at the next thing that happens.
-- Returns the name of one open window, or nil.
-- true when one of a context's frames is on screen, false when they are
-- loaded and none is, nil when none is loaded yet and we cannot tell.
local function ShopVisible(def)
    local known
    for _, name in ipairs(def.frames) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown then
            known = true
            if f:IsShown() then return true end
        end
    end
    if known then return false end
    return nil -- nothing loaded: we cannot tell, so the event has the say
end

local function ShopOpen()
    local name
    for _, def in ipairs(SHOPS) do
        local vis = ShopVisible(def)
        if vis then
            -- on screen: open, whether or not its event ever reached us
            if not shopOpen[def.key] then
                shopOpen[def.key] = def
                Log("shop", nil, def.name .. " is up (seen on screen, no event needed)")
            end
            name = name or def.name
        elseif vis == false and shopOpen[def.key] then
            -- loaded and not shown: a close event went missing
            shopOpen[def.key] = nil
            Log("shop", nil, def.name .. ": the hold was stale, released")
        elseif shopOpen[def.key] then
            name = name or def.name -- held by its event; no frame to check
        end
    end
    return name
end

-- "quiet" | "merge" | "show": what to do with gold that moves in there.
local function ShopMode()
    return ns.db and ns.db.splash.shops or "quiet"
end

function ns:PrintSplashLog()
    self:Print("Gold splash, this session (newest first):")
    local log = self.splashLog or {}
    if #log == 0 then print("  nothing yet") end
    for _, l in ipairs(log) do
        print(string.format("  %s  %-8s %14s  %s", date("%H:%M:%S", l.at), l.kind, l.amount and self.StripColor(self.FormatSigned(l.amount)) or "", l.note or ""))
    end
    local where, mode = ShopOpen(), ShopMode()
    print(string.format("  now: pending %s in %d change(s), in the shops %q%s, level 1 from %s, splash %s",
        self.StripColor(self.FormatSigned(pending)), count, mode,
        where and (" (" .. where .. " open" .. (pendingQuiet and ", this batch will be dropped" or "") .. ")") or "",
        self.FormatGold(self:SplashThreshold()), self.db.splash.enabled and "on" or "OFF"))
end

local function Flush()
    local amount, n, gold, stock = pending, count, pendingGold, pendingStock
    local where = pendingQuiet
    ShopOpen() -- prune any hold the window itself says is stale
    pending, count, pendingGold, pendingStock, pendingQuiet = 0, 0, 0, 0, nil
    if n == 0 then return end
    if Suppressed() then Log("flush", amount, "kept quiet: the bar's hide rules apply"); return end
    local db = ns.db
    local cfg = db.splash
    local quiet = where and ShopMode() == "quiet"
    local threshold = ns:SplashThreshold()
    local p = ns:Projection()
    local tierName = "Goal"
    local subtitle, level, title
    local banked = cfg.celebrateBanked ~= false and NewlyBanked(p) or nil
    -- the day's quota, met for the first time today
    local day = db.days[ns:DayID()]
    local quotaMet = not banked and cfg.celebrateQuota ~= false and day and day.quota
        and day.quota > 0 and p.today >= day.quota and not day.met or false
    if quotaMet then day.met = true end
    -- a sale: gold came in while stock left at cost. It shows whatever
    -- the size, as its profit (or loss) with the margin on cost.
    local cost = -stock
    local sale = cfg.profit ~= false and cost > 0 and gold > 0
    -- Crafting moves no gold: reagents become crafts and CraftSimPL values
    -- the two a little differently, so the position is worth more (or
    -- less) with nothing bought or sold. That is a revaluation, never
    -- income, so it is never celebrated -- whatever window is open, and
    -- whatever the shop rule says. Without CraftSimPL stock is always 0
    -- and this can never fire.
    local revalued = gold == 0 and stock ~= 0
    -- Gold that only moved around in a shop is not celebrated. The two
    -- once-only moments would be lost for good, so they still show (as
    -- the moment alone, without the misleading amount), and a sale shows
    -- its profit, which is the honest number. CrossedMark is deliberately
    -- not called: the percent mark keeps for the next gain out in the world.
    if quiet or revalued then
        if banked then
            -- the moment on its own: the amount is mostly gold coming back
            ns:ShowSplash(0, { title = banked .. " banked!", subtitle = "", level = #ns:SplashLevels() })
            Log("flush", amount, "quiet: only the banked goal showed")
        elseif quotaMet then
            ns:ShowSplash(0, { title = "Daily quota met!", subtitle = "", level = LevelAtMost(2) })
            Log("flush", amount, "quiet: only the quota showed")
        elseif sale then
            subtitle = ns.ProfitLine(amount, cost)
            ns:ShowSplash(amount, { subtitle = subtitle, loss = amount < 0 or nil,
                progress = cfg.progress ~= false and ns:ProgressLine(p, amount) or nil })
            Log("flush", amount, "a sale, shown through the quiet: " .. subtitle)
        elseif quiet then
            Log("flush", amount, "quiet: " .. where .. " open")
        else
            Log("flush", amount, "crafting revalued the stock, no gold moved: not income")
        end
        return
    end
    local mark = cfg.marks ~= false and CrossedMark(p) or nil
    if banked then
        subtitle, level = banked .. " banked!", #ns:SplashLevels()
    elseif quotaMet then
        subtitle = "Daily quota met!"
        level = math.max(LevelAtMost(2), ns:SplashLevel(amount))
    elseif sale then
        subtitle = ns.ProfitLine(amount, cost)
        level = ns:SplashLevel(amount)
        if amount < 0 then
            ns:ShowSplash(amount, { loss = true, subtitle = subtitle, progress = cfg.progress ~= false and ns:ProgressLine(p, amount) or nil })
            Log("flush", amount, "a sale at a loss: " .. subtitle)
            return
        end
    elseif mark then
        local big = math.max(1, cfg.markBigEvery or 10)
        subtitle = mark .. "% of " .. tierName
        level = math.max(mark % big == 0 and LevelAtMost(3) or 1, ns:SplashLevel(amount))
    end
    -- a loss: only when asked for, and only past the threshold
    if not subtitle and amount < 0 then
        if cfg.losses and -amount >= threshold then
            ns:ShowSplash(amount, { loss = true, subtitle = "spent", progress = cfg.progress ~= false and ns:ProgressLine(p, amount) or nil })
            Log("flush", amount, "shown as a loss")
        else
            Log("flush", amount, "a loss: not shown")
        end
        return
    end
    if not subtitle and amount < threshold then Log("flush", amount, "under level 1 (" .. ns.FormatGold(threshold) .. ")"); return end
    if subtitle and amount < threshold then
        amount = math.max(amount, 0)
        -- a mark crossed by small change stands on its own: the percent is the headline
        if mark and not banked and subtitle == mark .. "% of " .. tierName then
            title, subtitle = mark .. "%", "of " .. tierName
        end
    end
    ns:ShowSplash(amount, { subtitle = subtitle, level = level, title = title, progress = cfg.progress ~= false and ns:ProgressLine(p, amount) or nil })
    Log("flush", amount, "shown at level " .. ns.lastSplash.level .. (subtitle and (", " .. subtitle) or ""))
end

-- An error in the splash must never eat the next one.
local function SafeFlush()
    local ok, err = pcall(Flush)
    if not ok then
        Log("error", nil, tostring(err))
        geterrorhandler()(err)
    end
end

-- Waits until nothing has arrived for the merge window (and the mailbox
-- is closed), then shows the merged amount.
local function Arm()
    if armed then return end
    armed = true
    local merge = ns.db.splash.merge or 2
    C_Timer.After(merge, function()
        armed = false
        -- only "merge" holds; "quiet" flushes on time and drops it there,
        -- so a close event that never arrives cannot silence the session
        if ShopMode() == "merge" then
            local where = ShopOpen()
            if where then
                Log("hold", pending, "held: " .. where .. " is open")
                if count > 0 then Arm() end -- keep the stale check running
                return
            end
        end
        if Now() - lastAt >= merge - 0.05 then SafeFlush() else Arm() end
    end)
end

-- delta is the income; gold and stock its split (the gold that moved and
-- the stock that moved at cost), both optional.
function ns:SplashEarned(delta, gold, stock)
    if not self.db or (delta == 0 and (stock or 0) == 0) then return end
    if not self.db.splash.enabled then Log("earned", delta, "splash is off"); return end
    local where, mode = ShopOpen(), ShopMode()
    pending = pending + delta
    pendingGold = pendingGold + (gold or delta)
    pendingStock = pendingStock + (stock or 0)
    if where and mode == "quiet" then pendingQuiet = where end
    count = count + 1
    lastAt = Now()
    Log("earned", delta, where and (where .. " open, " .. (mode == "merge" and "holding" or mode == "quiet" and "will be dropped" or "shown anyway")) or nil)
    if not (where and mode == "merge") then Arm() end
end

-- The batch waiting: how much, in how many changes, and what is open.
function ns:SplashPending()
    return pending, count, ShopOpen()
end

ns:On("EARNED", function(delta, gold, stock) ns:SplashEarned(delta, gold, stock) end)
ns:On("LOGIN", function()
    BuildFrame()
    ns:AnchorSplash()
    for _, def in ipairs(SHOPS) do
        ns:RegisterEvent(def.open, function()
            shopOpen[def.key] = def
            Log("shop", nil, def.name .. " opened")
        end)
        ns:RegisterEvent(def.close, function()
            shopOpen[def.key] = nil
            Log("shop", pending, def.name .. " closed")
            if count > 0 and not ShopOpen() then lastAt = Now(); Arm() end
        end)
    end
end)
-- Every window closes on a loading screen, and a close event can go
-- missing. Registered at load, not on LOGIN: the ledger registers its own
-- PLAYER_ENTERING_WORLD then (Ledger.lua), and handlers run in the order
-- they were added, so this has to clear the holds before the gold it
-- observes arrives here.
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if next(shopOpen) then
        wipe(shopOpen)
        Log("shop", nil, "a loading screen closed everything")
    end
end)
ns:On("SETTINGS_CHANGED", function() ns:AnchorSplash() end)

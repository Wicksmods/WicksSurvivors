-- Wick's Survivors — Skin.lua
-- "Obsidian Glass" skin. 100% SetColorTexture — NO texture files required.
-- API: WS.Skin.Panel / Header / Button / Card / Trough / Gloss / Segments
--
-- Look: near-black vertical-gradient panels, a top gloss sheen, and a bright
-- fel-lit inner edge. Cards are subtle green-tinted glass with a fel hairline.
-- Nothing here loads a .tga, so there is nothing to convert and nothing to break.

local ADDON, ns = ...
local WS = WicksSurvivors
local C  = WS.C

-- Palette extensions (referenced in UI.lua as C.arc / C.ember)
C.arc   = {r=0.608, g=0.482, b=0.831, a=1}  -- #9b7bd4 arcane purple (passive type)
C.ember = {r=0.910, g=0.518, b=0.235, a=1}  -- #e8843c ember orange  (weapon type)

-- Obsidian colors
local PANEL_TOP = {r=0.106, g=0.094, b=0.157}  -- #1b1828
local PANEL_BOT = {r=0.031, g=0.024, b=0.059}  -- #08060f
local CARD_TOP  = {r=0.110, g=0.149, b=0.125}  -- #1c2620 (faint fel-green glass)
local CARD_BOT  = {r=0.039, g=0.031, b=0.071}  -- #0a0812
local LIGHT     = {r=0.62,  g=0.58,  b=0.72 }
local FELDK     = {r=0.039, g=0.227, b=0.133}  -- #0a3a22 dark-green outer

WS.Skin = {}
local Skin = WS.Skin

-- ── Edge line ────────────────────────────────────────────────────────────────
-- A true 1px line hugging one side (optionally inset), on OVERLAY by default.
local function edge(frame, side, col, a, inset, sub)
    local t = frame:CreateTexture(nil, "OVERLAY")
    if sub then t:SetDrawLayer("OVERLAY", sub) end
    t:SetColorTexture(col.r, col.g, col.b, a)
    inset = inset or 0
    if side == "TOP" then
        t:SetHeight(1)
        t:SetPoint("TOPLEFT",  frame, "TOPLEFT",   inset, -inset)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT",  -inset, -inset)
    elseif side == "BOTTOM" then
        t:SetHeight(1)
        t:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   inset, inset)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  -inset, inset)
    elseif side == "LEFT" then
        t:SetWidth(1)
        t:SetPoint("TOPLEFT",    frame, "TOPLEFT",     inset, -inset)
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",  inset,  inset)
    else
        t:SetWidth(1)
        t:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -inset, -inset)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset,  inset)
    end
    return t
end

local function felBorder(frame, col, a, inset, sub)
    edge(frame, "TOP", col, a, inset, sub); edge(frame, "BOTTOM", col, a, inset, sub)
    edge(frame, "LEFT", col, a, inset, sub); edge(frame, "RIGHT", col, a, inset, sub)
end

-- ── Vertical gradient (stacked color bands — no SetGradient API needed) ────────
-- band count scales with height so the steps stay below perception (no visible
-- banding). ~4px per band, clamped 16..64.
local function vGradient(frame, fh, top, bot, layer, sub)
    local n = math.max(16, math.min(64, math.floor(fh / 4)))
    local stripH = fh / n
    for i = 0, n - 1 do
        local f0 = i / (n - 1)
        local t = frame:CreateTexture(nil, layer or "BACKGROUND")
        if sub then t:SetDrawLayer(layer or "BACKGROUND", sub) end
        t:SetColorTexture(
            top.r + (bot.r - top.r) * f0,
            top.g + (bot.g - top.g) * f0,
            top.b + (bot.b - top.b) * f0, 1)
        t:SetHeight(stripH + 1)
        t:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(i * stripH))
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(i * stripH))
    end
end

-- ── Top gloss sheen (subtle white sheen over top ~18% of height) ───────────────
local function topGloss(frame, fh, peak)
    local hpx = math.max(8, math.floor(fh * 0.18))
    local n   = math.max(8, math.min(32, math.floor(hpx / 2)))
    local sH  = hpx / n
    for i = 0, n - 1 do
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetDrawLayer("ARTWORK", 2)
        t:SetColorTexture(1, 1, 1, (peak or 0.06) * (1 - i / n))
        t:SetHeight(sH + 1)
        t:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(i * sH))
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(i * sH))
    end
end

-- ── Fel hover edge (hidden until OnEnter); frame must be a Button ──────────────
local function felHover(frame)
    local hl = {}
    for _, s in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
        local t = edge(frame, s, C.fel, 1, 0, 7)
        t:SetAlpha(0); hl[#hl + 1] = t
    end
    frame:HookScript("OnEnter", function() for _, t in ipairs(hl) do t:SetAlpha(1) end end)
    frame:HookScript("OnLeave", function() for _, t in ipairs(hl) do t:SetAlpha(0) end end)
end

-- ── Panel ─────────────────────────────────────────────────────────────────────
function Skin.Panel(frame, w, h)
    local fw, fh = w or 380, h or 280
    vGradient(frame, fh, PANEL_TOP, PANEL_BOT, "BACKGROUND", 0)
    topGloss(frame, fh, 0.10)

    -- outer near-black + dark-green ring
    felBorder(frame, C.void, 0.95, 0, 2)
    felBorder(frame, FELDK,  0.9,  1, 3)
    -- bright fel-lit inner edge + soft inset bloom
    felBorder(frame, C.fel, 0.45, 2, 4)
    felBorder(frame, C.fel, 0.16, 4, 5)

    -- fel L-bracket corners: 10px arms, 2px thick, 4px inset
    local arm, thick, ins = 10, 2, 4
    for _, co in ipairs({
        {a="TOPLEFT",     wx=arm,   wy=thick, ox= ins, oy=-ins},
        {a="TOPLEFT",     wx=thick, wy=arm,   ox= ins, oy=-ins},
        {a="TOPRIGHT",    wx=arm,   wy=thick, ox=-ins, oy=-ins},
        {a="TOPRIGHT",    wx=thick, wy=arm,   ox=-ins, oy=-ins},
        {a="BOTTOMLEFT",  wx=arm,   wy=thick, ox= ins, oy= ins},
        {a="BOTTOMLEFT",  wx=thick, wy=arm,   ox= ins, oy= ins},
        {a="BOTTOMRIGHT", wx=arm,   wy=thick, ox=-ins, oy= ins},
        {a="BOTTOMRIGHT", wx=thick, wy=arm,   ox=-ins, oy= ins},
    }) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetDrawLayer("OVERLAY", 6)
        t:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
        t:SetSize(co.wx, co.wy)
        t:SetPoint(co.a, frame, co.a, co.ox, co.oy)
    end
end

-- ── Header ────────────────────────────────────────────────────────────────────
-- Glassy near-black band + bottom separator + centered fel accent glow.
function Skin.Header(frame, danger)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.043, 0.035, 0.071, 0.95)
    bg:SetAllPoints(frame)
    topGloss(frame, frame:GetHeight() or 34, 0.06)

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetDrawLayer("ARTWORK", 3)
    sep:SetColorTexture(0.020, 0.016, 0.035, 0.9)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")

    local accentCol = danger and C.red or C.fel
    local soft = frame:CreateTexture(nil, "OVERLAY")
    soft:SetColorTexture(accentCol.r, accentCol.g, accentCol.b, 0.22)
    soft:SetHeight(4)
    soft:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   52, -1)
    soft:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -52, -1)

    local accent = frame:CreateTexture(nil, "OVERLAY")
    accent:SetDrawLayer("OVERLAY", 1)
    accent:SetColorTexture(accentCol.r, accentCol.g, accentCol.b, 0.9)
    accent:SetHeight(2)
    accent:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   52, 0)
    accent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -52, 0)
end

-- ── Button ────────────────────────────────────────────────────────────────────
-- primary=true: bright fel-green gradient. primary=false: obsidian glass ghost.
function Skin.Button(frame, primary, fw, fh)
    local bw = fw or frame:GetWidth()
    local bh = fh or frame:GetHeight()
    if not bw or bw == 0 then bw = 120 end
    if not bh or bh == 0 then bh = 30  end

    if primary then
        local BTN_TOP = {r=0.384, g=0.859, b=0.549}  -- #62db8c
        local BTN_BOT = {r=0.149, g=0.490, b=0.282}  -- #268048
        vGradient(frame, bh, BTN_TOP, BTN_BOT, "BACKGROUND", 0)

        -- 1px gloss highlight at top edge
        local gloss = frame:CreateTexture(nil, "ARTWORK")
        gloss:SetColorTexture(1, 1, 1, 0.35); gloss:SetHeight(2)
        gloss:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        gloss:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)

        felBorder(frame, FELDK, 1, 0, 2)
    else
        vGradient(frame, bh, PANEL_TOP, PANEL_BOT, "BACKGROUND", 0)
        topGloss(frame, bh, 0.07)
        felBorder(frame, C.void, 0.95, 0, 2)
        felBorder(frame, C.fel,  0.30, 1, 3)
    end

    felHover(frame)
end

-- ── Card ──────────────────────────────────────────────────────────────────────
-- Obsidian glass card: faint fel-green gradient + fel hairline. Hover lights fel.
-- Base on ARTWORK so UI.lua's icon textures still layer above it.
function Skin.Card(frame, w, h)
    local fw, fh = w or 128, h or 130
    vGradient(frame, fh, CARD_TOP, CARD_BOT, "ARTWORK", 0)
    felBorder(frame, C.void, 0.9,  0, 1)
    felBorder(frame, C.fel,  0.24, 1, 2)
    if frame.HookScript then felHover(frame) end
end

-- ── Trough ────────────────────────────────────────────────────────────────────
function Skin.Trough(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.020, 0.012, 0.035, 0.9)
    bg:SetAllPoints(frame)
    edge(frame, "TOP",    C.void, 0.9,  0, 0)
    edge(frame, "BOTTOM", LIGHT,  0.10, 0, 0)
end

-- ── Gloss ─────────────────────────────────────────────────────────────────────
function Skin.Gloss(frame)
    local g = frame:CreateTexture(nil, "OVERLAY")
    g:SetColorTexture(1, 1, 1, 0.14); g:SetHeight(2)
    g:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); g:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
end

-- ── Segments ────────────────────────────────────────────────────────────────────
function Skin.Segments(bar, totalWidth, spacing)
    spacing = spacing or 38
    local x = spacing
    while x < totalWidth do
        local s = bar:CreateTexture(nil, "OVERLAY")
        s:SetDrawLayer("OVERLAY", 2)
        s:SetColorTexture(0, 0, 0, 0.22); s:SetWidth(2)
        s:SetPoint("TOPLEFT",    bar, "TOPLEFT",    x, 0)
        s:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        x = x + spacing
    end
end

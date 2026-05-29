-- Wick's Survivors — Splash.lua
-- Title splash before the main menu.
-- Reproduces "Cover C — The Watcher Looms" from cover-art.js:
--   C'Thun dominates the upper half, two boss silhouettes flank it,
--   dread-light shafts fan downward, tiny Wick gazes up from below.
-- Fixed 1280×800 panel, scaled to fit any screen.

local ADDON, ns = ...
local WS = WicksSurvivors
local C  = WS.C

WS.Splash = {}
local Splash = WS.Splash

local ART    = "Interface\\AddOns\\WicksSurvivors\\Art\\"
local SND    = "Interface\\AddOns\\WicksSurvivors\\Sounds\\"
local CINZEL = "Interface\\AddOns\\WicksSurvivors\\Fonts\\Cinzel.ttf"
local FRIZQT = "Fonts\\FRIZQT__.TTF"

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local CFG = {
    USE_TITLE_TEXTURE = false,
    PLAY_ONCE         = true,
    AUTO_ADVANCE      = false,
    AUTO_DELAY        = 1.0,
    SOUND        = true,
    SND_REVEAL   = SND .. "reveal.ogg",
    SND_IMPACT   = SND .. "impact.ogg",
    SND_SHIMMER  = SND .. "shimmer.ogg",
    SND_MENU     = SND .. "menu.ogg",
    SND_AMBIENCE = SND .. "ambience.ogg",
    SND_SNARL    = SND .. "snarl.ogg",
    SNARL_MIN = 5, SNARL_MAX = 13,
}

local SW, SH = 1280, 800   -- reference scene size

-- Timeline beats
local T_REVEAL  = 0.12
local T_KICKER  = 0.75
local T_TITLE   = 1.07
local T_FOIL    = 1.30
local T_TAG     = 1.73
local T_PROMPT  = 2.63
local T_OUT     = 0.55

-- ── helpers ───────────────────────────────────────────────────────────────────
local function clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
local function seg(t, s, d)   return clamp((t - s) / d, 0, 1) end
local function easeOut(x)     return 1 - (1 - x)^3 end
local function easeOutStrong(x) return 1 - (1 - x)^4 end

local function tryFont(fs, size)
    if not pcall(fs.SetFont, fs, CINZEL, size, "") then fs:SetFont(FRIZQT, size, "") end
end

local function playCue(cue)
    if not CFG.SOUND or not cue then return end
    if type(cue) == "number" then PlaySound(cue, "SFX")
    else PlaySoundFile(cue, "SFX") end
end

local function fitScale()
    return math.min(GetScreenWidth() / SW, GetScreenHeight() / SH)
end

-- Set UV to a specific animation frame on a sprite strip
local function setFrame(tex, key, frameIdx)
    local a = WS.ANIM[key]
    if not a then tex:SetTexCoord(0,1,0,1); return end
    local n = a.frames
    local idx = frameIdx or 0
    local l = idx / n
    tex:SetTexCoord(l, l + 1/n, 0, 1)
end

-- ── backdrop layer builder ────────────────────────────────────────────────────
-- Reproduces paintC from cover-art.js as stacked WoW textures.
-- Cover C layout (all coords as fractions of SW/SH):
--   atmosphere: radial grad core #10241c→#121026, stone overlay
--   bloom:  center 50%×38%, radius 85% of W, fel green
--   boss_illidan: x=0.27 y=0.67, size=0.58W, dark-tinted, purple glow
--   boss_nef:     x=0.73 y=0.67, size=0.58W, dark-tinted, orange glow, flipped
--   light shafts: screen-mode fan from 50%×46% to bottom
--   boss_cthun:   x=0.50 y=0.37, size=1.02W  (dominant)
--   inner bloom:  50%×37%, radius 30%W
--   scrim bottom: H*0.6 → H*1.0
--   player:       x=0.50 y=0.735, size=0.22W
--   edge vignette: radial dark rim

local function addSprite(parent, texKey, cx, cy, size, strata, sublevel, alpha, r, g, b)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    -- cx/cy are absolute px from panel center-origin (same as JS x - W/2, y - H/2)
    f:SetPoint("CENTER", parent, "CENTER", cx, cy)
    local tex = f:CreateTexture(nil, strata or "ARTWORK", nil, sublevel or 0)
    tex:SetTexture(WS.TEX[texKey])
    tex:SetAllPoints(f)
    setFrame(tex, texKey, 0)
    if r then tex:SetVertexColor(r, g or r, b or r, alpha or 1)
    else tex:SetAlpha(alpha or 1) end
    return f, tex
end

local function addBloom(parent, cx, cy, size, r, g, b, alpha, strata, sub)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetPoint("CENTER", parent, "CENTER", cx, cy)
    local tex = f:CreateTexture(nil, strata or "BACKGROUND", nil, sub or 0)
    tex:SetTexture(ART .. "glow")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(r, g, b, alpha)
    tex:SetAllPoints(f)
    return f, tex
end

local function addColorTex(parent, r, g, b, a, strata, sub)
    local tex = parent:CreateTexture(nil, strata, nil, sub)
    tex:SetColorTexture(r, g, b, a)
    tex:SetAllPoints(parent)
    return tex
end

-- ── build (once) ──────────────────────────────────────────────────────────────
local splash, panel

-- refs for animated elements
local cthunTex, playerTex, bloomMain, bloomInner, bloomPlayer

local function BuildBackdrop(p)
    -- 1. Atmosphere base — radial gradient from stone-green core to near-black edges
    --    Approximated as two layered color textures + a glow texture for the green core.
    addColorTex(p, 0.063, 0.063, 0.063, 1, "BACKGROUND", -1)  -- dark base

    -- Stone texture overlay (50% alpha overlay — use glow.tga as a soft screen layer)
    local stone = p:CreateTexture(nil, "BACKGROUND", nil, 0)
    stone:SetTexture(ART .. "glow")
    stone:SetBlendMode("ADD")
    stone:SetVertexColor(0.14, 0.10, 0.22, 0.12)
    stone:SetAllPoints(p)

    -- Core atmosphere: green-teal glow at 50% x, 38% y (glowY=0.36)
    --   core #10241c = r0.063 g0.141 b0.110, mid #121026 = r0.071 g0.063 b0.149
    addBloom(p,  0,  SH*(0.5-0.36),  SW*0.85,  0.098, 0.196, 0.153, 0.55, "BACKGROUND", 1)
    addBloom(p,  0,  SH*(0.5-0.36),  SW*0.50,  0.047, 0.141, 0.098, 0.40, "BACKGROUND", 2)

    -- 2. Boss silhouettes (tinted very dark — "rgba(8,6,18,0.56)" tint over the sprite)
    --    Positioned at x=0.27/0.73, y=0.67 → panel-center-relative:
    --    cx = (0.27-0.5)*SW = -296, cy = (0.5-0.67)*SH = -136, size = 0.58*SW = 742
    --    But tinted dark so they read as silhouettes; alpha 0.82
    local illidanSize = math.floor(SW * 0.58)
    local illidanF, illidanT = addSprite(p, "boss_illidan",
        math.floor((0.27-0.5)*SW), math.floor((0.5-0.67)*SH),
        illidanSize, "BACKGROUND", 3, 0.35)
    -- purple glow behind illidan
    addBloom(p,  math.floor((0.27-0.5)*SW),  math.floor((0.5-0.67)*SH),
        illidanSize*1.1,  0.478, 0.314, 0.784, 0.22, "BACKGROUND", 2)

    local nefSize = math.floor(SW * 0.58)
    local nefF, nefT = addSprite(p, "boss_nef",
        math.floor((0.73-0.5)*SW), math.floor((0.5-0.67)*SH),
        nefSize, "BACKGROUND", 3, 0.35)
    nefT:SetTexCoord(1/4, 0, 0, 1)   -- flip horizontally, frame 0 of 4-frame strip
    -- orange glow behind nef
    addBloom(p,  math.floor((0.73-0.5)*SW),  math.floor((0.5-0.67)*SH),
        nefSize*1.1,  0.910, 0.471, 0.235, 0.20, "BACKGROUND", 2)

    -- 3. Dread light shafts — fan from 50%×46% downward (screen blend)
    --    Approximate as a narrow tall stretched glow, fanned out
    local shaftF = CreateFrame("Frame", nil, p)
    shaftF:SetSize(SW*0.46, SH*0.54)
    shaftF:SetPoint("TOP", p, "TOP", 0, -math.floor(SH*0.46))
    local shaftT = shaftF:CreateTexture(nil, "ARTWORK", nil, 0)
    shaftT:SetTexture(ART .. "glow")
    shaftT:SetBlendMode("ADD")
    shaftT:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.12)
    shaftT:SetAllPoints(shaftF)

    -- 4. C'Thun — dominant, size=1.02*SW, centered at 50%×37%
    --    cx=0, cy=(0.5-0.37)*SH = 104
    local cthunSize = math.floor(SW * 1.02)
    local cthunF, ct = addSprite(p, "boss_cthun",
        0, math.floor((0.5-0.37)*SH),
        cthunSize, "ARTWORK", 1, 1.0)
    cthunTex = ct
    -- fel glow around C'Thun
    addBloom(p, 0, math.floor((0.5-0.37)*SH), math.floor(SW*1.1),
        0.373, 0.878, 0.541, 0.35, "ARTWORK", 0)
    -- inner bright bloom at the eye
    local _, bi = addBloom(p, 0, math.floor((0.5-0.37)*SH), math.floor(SW*0.30),
        0.588, 1.0, 0.706, 0.28, "ARTWORK", 2)
    bloomInner = bi

    -- 5. Bottom scrim: H*0.6 to H*1.0 — dark gradient
    local scrimF = CreateFrame("Frame", nil, p)
    scrimF:SetSize(SW, math.floor(SH*0.45))
    scrimF:SetPoint("BOTTOM", p, "BOTTOM", 0, 0)
    local scrimT = scrimF:CreateTexture(nil, "ARTWORK", nil, 3)
    scrimT:SetColorTexture(0.020, 0.012, 0.035, 0)
    scrimT:SetAllPoints(scrimF)
    -- layered near-black to transparent (WoW textures can't gradient; stack two)
    local scrimT2 = scrimF:CreateTexture(nil, "ARTWORK", nil, 4)
    scrimT2:SetTexture(ART .. "glow")
    scrimT2:SetBlendMode("BLEND")
    scrimT2:SetVertexColor(0.020, 0.012, 0.035, 0.78)
    scrimT2:SetAllPoints(scrimF)

    -- 6. Player — tiny Wick gazing up, x=0.5 y=0.735, size=0.22*SW
    --    cx=0, cy=(0.5-0.735)*SH = -188
    local playerSize = math.floor(SW * 0.22)
    local playerF, pt = addSprite(p, "player",
        0, math.floor((0.5-0.735)*SH),
        playerSize, "ARTWORK", 5, 1.0)
    playerTex = pt
    -- fel bloom under Wick
    local _, bp = addBloom(p, 0, math.floor((0.5-0.735)*SH), math.floor(SW*0.18),
        C.fel.r, C.fel.g, C.fel.b, 0.38, "ARTWORK", 4)
    bloomPlayer = bp

    -- 7. Edge vignette — dark radial rim over everything
    local vigF = CreateFrame("Frame", nil, p)
    vigF:SetAllPoints(p)
    local vigT = vigF:CreateTexture(nil, "OVERLAY", nil, 0)
    vigT:SetTexture(ART .. "glow")
    vigT:SetBlendMode("BLEND")
    vigT:SetVertexColor(0.020, 0.012, 0.035, 0.88)
    vigT:SetAllPoints(vigF)
    -- second, wider pass for true edge darkness
    local vigT2 = vigF:CreateTexture(nil, "OVERLAY", nil, 1)
    vigT2:SetColorTexture(0.016, 0.008, 0.031, 1)
    vigT2:SetPoint("TOPLEFT",    vigF, "TOPLEFT",      0,   0)
    vigT2:SetPoint("BOTTOMLEFT", vigF, "BOTTOMLEFT",   SW*0.12, 0)
    vigT2:SetGradient("HORIZONTAL", CreateColor(0.016,0.008,0.031,0.7), CreateColor(0,0,0,0))
    local vigT3 = vigF:CreateTexture(nil, "OVERLAY", nil, 1)
    vigT3:SetColorTexture(0.016, 0.008, 0.031, 1)
    vigT3:SetPoint("TOPRIGHT",    vigF, "TOPRIGHT",    0,   0)
    vigT3:SetPoint("BOTTOMRIGHT", vigF, "BOTTOMRIGHT", -SW*0.12, 0)
    vigT3:SetGradient("HORIZONTAL", CreateColor(0,0,0,0), CreateColor(0.016,0.008,0.031,0.7))

    -- main bloom ref for animation
    bloomMain = bi
end

-- ── embers ─────────────────────────────────────────────────────────────────
local EMBER_COUNT = 14
local embers = {}

local function buildEmbers(p)
    for i = 1, EMBER_COUNT do
        local f  = (math.abs(math.sin(i * 12.9898 + 78.233) * 43758.5453)) % 1
        local ox = -SW/2 + (0.08 + f * 0.84) * SW
        local dur = 7 + f * 6
        local del = -(f * 9)
        local dx  = (f - 0.5) * 60
        local frm = CreateFrame("Frame", nil, p)
        frm:SetSize(3, 3)
        frm:SetPoint("BOTTOM", p, "BOTTOM", ox, -3)
        local tex = frm:CreateTexture(nil, "OVERLAY", nil, 5)
        tex:SetColorTexture(0.498, 0.941, 0.639, 0.85)
        tex:SetAllPoints(frm)
        frm:SetAlpha(0)
        embers[i] = { frame=frm, ox=ox, dur=dur, t0=del, dx=dx }
    end
end

local function tickEmbers(t)
    for _, e in ipairs(embers) do
        local age  = (t + e.t0) % e.dur
        local frac = age / e.dur
        local a
        if frac < 0.12 then a = (frac/0.12)*0.8
        elseif frac > 0.85 then a = ((1-frac)/0.15)*0.5
        else a = 0.55 end
        e.frame:SetAlpha(a)
        local rise  = frac * SH * 0.9
        local drift = e.dx * frac
        e.frame:SetPoint("BOTTOM", e.frame:GetParent(), "BOTTOM", e.ox + drift, rise)
    end
end

-- ── build ─────────────────────────────────────────────────────────────────────
local splash, panel

local function Build()
    if splash then return end

    splash = CreateFrame("Button", "WicksSurvivorsSplash", UIParent)
    splash:SetAllPoints(UIParent)
    splash:SetFrameStrata("FULLSCREEN_DIALOG")
    splash:SetToplevel(true)
    splash:EnableMouse(true)
    splash:Hide()

    -- screen dim behind panel
    local dim = splash:CreateTexture(nil, "BACKGROUND")
    dim:SetColorTexture(0, 0, 0, 0.75)
    dim:SetAllPoints(splash)

    -- fixed panel
    panel = CreateFrame("Frame", nil, splash)
    panel:SetSize(SW, SH)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetScale(fitScale())
    panel:SetClipsChildren(true)

    -- backdrop scene (cover C)
    BuildBackdrop(panel)

    -- embers (drawn over backdrop, under reveal)
    buildEmbers(panel)

    -- corner brackets: 46px arm, 3px thick, inset 22px
    local arm, thick, ins = 46, 3, 22
    local function bracket(anchor, ox, oy, w, h)
        local tex = panel:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
        tex:SetSize(w, h)
        tex:SetPoint(anchor, panel, anchor, ox, oy)
        tex:SetAlpha(0)
        return tex
    end
    splash.corners = {}
    for _, c in ipairs({
        {"TOPLEFT",      ins,-ins,  arm,thick}, {"TOPLEFT",      ins,-ins,  thick,arm},
        {"TOPRIGHT",    -ins,-ins,  arm,thick}, {"TOPRIGHT",    -ins,-ins,  thick,arm},
        {"BOTTOMLEFT",   ins, ins,  arm,thick}, {"BOTTOMLEFT",   ins, ins,  thick,arm},
        {"BOTTOMRIGHT", -ins, ins,  arm,thick}, {"BOTTOMRIGHT", -ins, ins,  thick,arm},
    }) do splash.corners[#splash.corners+1] = bracket(c[1],c[2],c[3],c[4],c[5]) end

    -- title block anchored at top 30% of panel
    local titleHolder = CreateFrame("Frame", nil, panel)
    titleHolder:SetSize(SW - 80, 280)
    titleHolder:SetPoint("TOP", panel, "TOP", 0, -math.floor(SH * 0.30))
    splash.titleHolder = titleHolder

    if CFG.USE_TITLE_TEXTURE then
        local tt = titleHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        tt:SetTexture(ART .. "splash_title")
        tt:SetPoint("CENTER")
        tt:SetSize(820, 220)
        splash.titleTex = tt
    else
        local kicker = titleHolder:CreateFontString(nil, "OVERLAY")
        tryFont(kicker, 30)
        kicker:SetText("WICK\226\128\153S")
        kicker:SetTextColor(C.text.r, C.text.g, C.text.b)
        kicker:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.5)
        kicker:SetShadowOffset(0, -1)
        kicker:SetPoint("TOP", titleHolder, "TOP", 0, 0)
        kicker:SetAlpha(0)
        splash.kicker = kicker

        local title = titleHolder:CreateFontString(nil, "OVERLAY")
        tryFont(title, 96)
        title:SetText("SURVIVORS")
        title:SetTextColor(0.957, 0.914, 0.784)
        title:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.6)
        title:SetShadowOffset(0, -2)
        title:SetPoint("TOP", kicker, "BOTTOM", 0, -6)
        title:SetAlpha(0)
        splash.title = title

        -- foil shimmer pass
        local foil = titleHolder:CreateFontString(nil, "OVERLAY")
        tryFont(foil, 96)
        foil:SetText("SURVIVORS")
        foil:SetTextColor(1, 1, 1, 0)
        foil:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
        splash.foil = foil
    end

    local tag = titleHolder:CreateFontString(nil, "OVERLAY")
    tag:SetFont(FRIZQT, 17, "")
    tag:SetText("Something ancient has woken.")
    tag:SetTextColor(C.fel.r, C.fel.g, C.fel.b)
    tag:SetPoint("TOP", splash.title or splash.titleTex, "BOTTOM", 0, -22)
    tag:SetAlpha(0)
    splash.tag = tag

    -- prompt at bottom 13%
    local prompt = panel:CreateFontString(nil, "OVERLAY")
    prompt:SetFont(FRIZQT, 15, "")
    prompt:SetText("CLICK TO BEGIN")
    prompt:SetTextColor(C.fel.r, C.fel.g, C.fel.b)
    prompt:SetPoint("BOTTOM", panel, "BOTTOM", 0, math.floor(SH * 0.13))
    prompt:SetAlpha(0)
    splash.prompt = prompt

    -- reveal black — covers everything, fades out
    local rev = panel:CreateTexture(nil, "OVERLAY", nil, 10)
    rev:SetColorTexture(0.016, 0.008, 0.039, 1)
    rev:SetAllPoints(panel)
    splash.revealTex = rev

    splash:SetScript("OnClick", function() Splash.Advance() end)
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)
end

-- ── runtime ───────────────────────────────────────────────────────────────────
local t, advancing, advT, onDone, struck, foilPhase, nextSnarl

function Splash.Tick(dt)
    t = t + dt
    panel:SetScale(fitScale())

    -- reveal lifts
    splash.revealTex:SetAlpha(1 - easeOut(seg(t, T_REVEAL, 0.9)))

    -- corners
    local cornA = easeOut(seg(t, T_REVEAL + 0.2, 0.8))
    for _, c in ipairs(splash.corners) do c:SetAlpha(cornA) end

    -- C'Thun flipbook animation
    if cthunTex then
        local a = WS.ANIM["boss_cthun"]
        local idx = math.floor(GetTime() * a.fps) % a.frames
        local l = idx / a.frames
        cthunTex:SetTexCoord(l, l + 1/a.frames, 0, 1)
    end

    -- player flipbook
    if playerTex then
        local a = WS.ANIM["player"]
        local idx = math.floor(GetTime() * a.fps) % a.frames
        local l = idx / a.frames
        playerTex:SetTexCoord(l, l + 1/a.frames, 0, 1)
    end

    -- bloom breathes (bgPulse: ~5.5s period)
    local pulse = 0.25 + 0.12 * math.abs(math.sin(t * 0.571))
    if bloomPlayer then bloomPlayer:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, pulse * 1.4) end

    -- embers
    tickEmbers(t)

    -- title entrance
    local pk  = easeOut(seg(t, T_KICKER, 0.7))
    local ptl = easeOutStrong(seg(t, T_TITLE, 0.85))
    local ptg = easeOut(seg(t, T_TAG, 0.7))

    if CFG.USE_TITLE_TEXTURE then
        splash.titleTex:SetAlpha(ptl)
    else
        splash.kicker:SetAlpha(pk)
        splash.title:SetAlpha(ptl)
        if foilPhase == nil and t >= T_FOIL then foilPhase = 0 end
        if foilPhase and foilPhase < 1 then
            foilPhase = math.min(1, foilPhase + dt / 1.05)
            local sweep = math.max(0, 1 - math.abs(foilPhase - 0.5) / 0.28)
            splash.foil:SetAlpha(sweep * 0.72)
        elseif foilPhase and foilPhase >= 1 then
            splash.foil:SetAlpha(0)
        end
    end
    splash.titleHolder:SetScale(1.14 - 0.14 * ptl)
    splash.tag:SetAlpha(ptg)

    -- impact cue
    if not struck and t >= T_TITLE + 0.35 then
        struck = true; playCue(CFG.SND_IMPACT); playCue(CFG.SND_SHIMMER)
    end

    -- prompt pulse
    if not CFG.AUTO_ADVANCE then
        local on = clamp((t - T_PROMPT) / 0.4, 0, 1)
        splash.prompt:SetAlpha(on * (0.35 + 0.65 * math.abs(math.sin(t * 1.745))))
    else
        splash.prompt:SetAlpha(0)
        if t >= T_PROMPT + CFG.AUTO_DELAY and not advancing then Splash.Advance() end
    end

    -- snarls
    if CFG.SOUND and nextSnarl and t >= nextSnarl then
        playCue(CFG.SND_SNARL)
        nextSnarl = t + CFG.SNARL_MIN + math.random() * (CFG.SNARL_MAX - CFG.SNARL_MIN)
    end

    -- fade out
    if advancing then
        advT = advT + dt
        local k = clamp(advT / T_OUT, 0, 1)
        splash:SetAlpha(1 - k)
        if k >= 1 then
            splash:Hide()
            splash:SetScript("OnUpdate", nil)
            if PlayMusic then pcall(StopMusic) end
            if onDone then onDone() end
        end
    end
end

function Splash.Advance()
    if advancing then return end
    advancing = true; advT = 0
    playCue(CFG.SND_MENU)
end

function Splash.Play(onComplete, force)
    Build()
    if CFG.PLAY_ONCE and Splash.seen and not force then
        if onComplete then onComplete() end
        return
    end
    Splash.seen = true

    t, advancing, advT, struck, foilPhase = 0, false, 0, false, nil
    onDone    = onComplete
    nextSnarl = CFG.SOUND and (2.5 + math.random() * 2) or nil

    splash.revealTex:SetAlpha(1)
    splash.prompt:SetAlpha(0)
    splash.tag:SetAlpha(0)
    splash.titleHolder:SetScale(1.14)
    for _, c in ipairs(splash.corners) do c:SetAlpha(0) end
    if not CFG.USE_TITLE_TEXTURE then
        splash.kicker:SetAlpha(0)
        splash.title:SetAlpha(0)
        splash.foil:SetAlpha(0)
    end

    splash:SetAlpha(1)
    panel:SetScale(fitScale())
    splash:Show()
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)

    playCue(CFG.SND_REVEAL)
    if CFG.SOUND and PlayMusic then pcall(PlayMusic, CFG.SND_AMBIENCE) end
end

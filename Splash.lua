-- Wick's Survivors — Splash.lua
-- Animated title splash before the main menu.
-- Fixed 1280x800 panel (fits-to-screen via SetScale), cover-art backdrop,
-- drifting fel embers, L-bracket corners, "WICK'S / SURVIVORS" title carve,
-- foil sweep, tagline, "Click to begin" prompt.
-- No AnimationGroups — single OnUpdate timeline, safe on 2.5.x (20505).

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
    USE_BG_TEXTURE    = false,   -- true once Art\splash_bg.tga exists
    USE_TITLE_TEXTURE = false,   -- true once Art\splash_title.tga exists
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

-- Scene dimensions (reference design: 1280x800)
local SW, SH = 1280, 800

-- Timeline beats (seconds) — mirrors the HTML prototype
local T_REVEAL  = 0.12   -- reveal starts immediately
local T_KICKER  = 0.75   -- "WICK'S" fades in
local T_TITLE   = 1.07   -- "SURVIVORS" carves in (0.75 + 0.32*1.0)
local T_FOIL    = 1.30   -- foil sweep starts
local T_TAG     = 1.73   -- tagline fades in  (0.75 + 0.98*1.0)
local T_PROMPT  = 2.63   -- prompt starts pulsing (T_TAG + 0.7 + 0.2)
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

-- Fit the fixed SW×SH panel to the current screen
local function fitScale()
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    return math.min(sw / SW, sh / SH)
end

-- ── ember system ──────────────────────────────────────────────────────────────
-- 14 drifting fel sparks, each with its own seed-driven position/timing
local EMBER_COUNT = 14
local function seedFloat(seed, mul, off)
    local v = math.abs(math.sin(seed * 12.9898 + 78.233) * 43758.5453) % 1
    return off + v * mul
end

local embers = {}   -- {tex, ox, oy, t0, dur, dx, size}
local function buildEmbers(panel)
    for i = 1, EMBER_COUNT do
        local f    = seedFloat(i, 1, 0)
        local ox   = -SW/2 + (0.08 + f * 0.84) * SW
        local dur  = 7 + f * 6
        local del  = -(f * 9)          -- negative → already mid-flight at t=0
        local dx   = (f - 0.5) * 60
        local sz   = 3

        local frame = CreateFrame("Frame", nil, panel)
        frame:SetSize(sz, sz)
        frame:SetPoint("BOTTOM", panel, "BOTTOM", ox, -sz)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(0.498, 0.941, 0.639, 0.8)
        tex:SetAllPoints(frame)
        frame:SetAlpha(0)
        embers[i] = { frame=frame, ox=ox, dur=dur, t0=del, dx=dx }
    end
end

local function tickEmbers(t)
    for _, e in ipairs(embers) do
        local age = (t + e.t0) % e.dur
        local frac = age / e.dur
        -- alpha: 0→0.8 in first 12%, hold, fade to 0 in last 15%
        local a
        if frac < 0.12 then a = (frac / 0.12) * 0.8
        elseif frac > 0.85 then a = ((1 - frac) / 0.15) * 0.5
        else a = 0.5 + 0.3 * (1 - math.abs(frac - 0.485) / 0.365) end
        e.frame:SetAlpha(a)
        local rise = frac * SH * 0.9
        local drift = e.dx * frac
        e.frame:SetPoint("BOTTOM", e.frame:GetParent(), "BOTTOM", e.ox + drift, rise)
    end
end

-- ── build (once) ──────────────────────────────────────────────────────────────
local splash, panel

local function Build()
    if splash then return end

    -- Fullscreen dim + click-catcher
    splash = CreateFrame("Button", "WicksSurvivorsSplash", UIParent)
    splash:SetAllPoints(UIParent)
    splash:SetFrameStrata("FULLSCREEN_DIALOG")
    splash:SetToplevel(true)
    splash:EnableMouse(true)
    splash:Hide()

    local dim = splash:CreateTexture(nil, "BACKGROUND")
    dim:SetColorTexture(0, 0, 0, 0.78)
    dim:SetAllPoints(splash)

    -- Fixed-size panel, scaled to screen
    panel = CreateFrame("Frame", nil, splash)
    panel:SetSize(SW, SH)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetScale(fitScale())

    -- Void fill
    local void = panel:CreateTexture(nil, "BACKGROUND")
    void:SetColorTexture(C.void.r, C.void.g, C.void.b, 1)
    void:SetAllPoints(panel)

    -- Optional baked cover art (reference uses a painted canvas; use a TGA once ready)
    if CFG.USE_BG_TEXTURE then
        local bg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetTexture(ART .. "splash_bg")
        bg:SetAllPoints(panel)
    end

    -- Radial fel bloom — reference: radial-gradient 42% at 50% 37%
    local bloom = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    bloom:SetTexture(ART .. "glow")
    bloom:SetBlendMode("ADD")
    bloom:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.20)
    bloom:SetSize(SW * 0.84, SH * 0.76)
    bloom:SetPoint("CENTER", panel, "CENTER", 0, SH * 0.13)   -- ~37% from top → 13% above center
    splash.bloom = bloom

    -- Embers
    buildEmbers(panel)

    -- Vignette (dark radial rim)
    local vig = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    vig:SetTexture(ART .. "glow")    -- reuse glow inverted via vertex color
    vig:SetBlendMode("BLEND")
    vig:SetVertexColor(C.void.r, C.void.g, C.void.b, 0.55)
    vig:SetSize(SW * 1.3, SH * 0.9)
    vig:SetPoint("BOTTOM", panel, "BOTTOM", 0, -SH * 0.08)
    -- (glow texture fades to transparent at center — put dark at edges via BLEND)

    -- Corner brackets: 46px arm, 3px thick, inset 22px (reference exact values)
    local arm, thick, ins = 46, 3, 22
    local function bracket(anchor, ox, oy, w, h)
        local t = panel:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
        t:SetSize(w, h)
        t:SetPoint(anchor, panel, anchor, ox, oy)
        return t
    end
    splash.corners = {}
    for _, c in ipairs({
        {"TOPLEFT",      ins, -ins, arm, thick}, {"TOPLEFT",      ins, -ins, thick, arm},
        {"TOPRIGHT",    -ins, -ins, arm, thick}, {"TOPRIGHT",    -ins, -ins, thick, arm},
        {"BOTTOMLEFT",   ins,  ins, arm, thick}, {"BOTTOMLEFT",   ins,  ins, thick, arm},
        {"BOTTOMRIGHT", -ins,  ins, arm, thick}, {"BOTTOMRIGHT", -ins,  ins, thick, arm},
    }) do
        local t = bracket(c[1], c[2], c[3], c[4], c[5])
        t:SetAlpha(0)
        splash.corners[#splash.corners+1] = t
    end

    -- Title block: positioned at top 30% (center of block ~37% down)
    -- "WICK'S" 30px kicker + "SURVIVORS" 118px main + tagline 17px
    local titleY = SH * 0.5 - SH * 0.30   -- 30% from top = SH*0.30 below top = SH*0.5 - SH*0.30 above center
    local titleHolder = CreateFrame("Frame", nil, panel)
    titleHolder:SetSize(SW - 80, 280)
    titleHolder:SetPoint("CENTER", panel, "CENTER", 0, titleY - SH * 0.5 + 280 * 0.5)
    -- Simpler: anchor top of holder at 30% from top of panel
    titleHolder:ClearAllPoints()
    titleHolder:SetPoint("TOP", panel, "TOP", 0, -SH * 0.30)
    splash.titleHolder = titleHolder

    if CFG.USE_TITLE_TEXTURE then
        local tt = titleHolder:CreateTexture(nil, "ARTWORK")
        tt:SetTexture(ART .. "splash_title")
        tt:SetPoint("CENTER")
        tt:SetSize(820, 220)
        splash.titleTex = tt
    else
        local kicker = titleHolder:CreateFontString(nil, "ARTWORK")
        tryFont(kicker, 30)
        kicker:SetText("WICK\226\128\153S")   -- "WICK'S" with right-single-quote
        kicker:SetTextColor(C.text.r, C.text.g, C.text.b, 1)
        kicker:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.5)
        kicker:SetShadowOffset(0, -1)
        kicker:SetPoint("TOP", titleHolder, "TOP", 0, 0)
        splash.kicker = kicker

        local title = titleHolder:CreateFontString(nil, "ARTWORK")
        tryFont(title, 96)
        title:SetText("SURVIVORS")
        title:SetTextColor(0.957, 0.914, 0.784)   -- gold-soft: ~#f4e9c8
        title:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.55)
        title:SetShadowOffset(0, -2)
        title:SetPoint("TOP", kicker, "BOTTOM", 0, -6)
        splash.title = title

        -- foil shimmer overlay (second FontString, same text, white with alpha)
        local foil = titleHolder:CreateFontString(nil, "ARTWORK")
        tryFont(foil, 96)
        foil:SetText("SURVIVORS")
        foil:SetTextColor(1, 1, 1, 0)   -- starts invisible
        foil:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
        splash.foil = foil
    end

    local tag = titleHolder:CreateFontString(nil, "ARTWORK")
    tag:SetFont(FRIZQT, 17, "")
    tag:SetText("Something ancient has woken.")
    tag:SetTextColor(C.fel.r, C.fel.g, C.fel.b, 1)
    tag:SetPoint("TOP", splash.title or splash.titleTex, "BOTTOM", 0, -22)
    splash.tag = tag

    -- "Click to begin" — bottom 13%
    local prompt = panel:CreateFontString(nil, "OVERLAY")
    prompt:SetFont(FRIZQT, 15, "")
    prompt:SetText("CLICK TO BEGIN")
    prompt:SetTextColor(C.fel.r, C.fel.g, C.fel.b, 1)
    prompt:SetPoint("BOTTOM", panel, "BOTTOM", 0, SH * 0.13)
    splash.prompt = prompt

    -- Reveal black over the whole panel — fades out to uncover the scene
    local rev = panel:CreateTexture(nil, "OVERLAY", nil, 7)
    rev:SetColorTexture(0.016, 0.008, 0.039, 1)
    rev:SetAllPoints(panel)
    splash.revealTex = rev

    splash:SetScript("OnClick", function() Splash.Advance() end)
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)
end

-- ── runtime state ─────────────────────────────────────────────────────────────
local t, advancing, advT, onDone, struck, shimmered, nextSnarl, foilPhase

function Splash.Tick(dt)
    t = t + dt

    -- rescale panel if screen size changed (e.g. resolution toggle)
    panel:SetScale(fitScale())

    -- 1. reveal black lifts
    local revA = 1 - easeOut(seg(t, T_REVEAL, 0.9))
    splash.revealTex:SetAlpha(revA)

    -- 2. corners fade in once reveal is mostly done
    local cornA = easeOut(seg(t, T_REVEAL + 0.2, 0.8))
    for _, c in ipairs(splash.corners) do c:SetAlpha(cornA) end

    -- 3. bloom breathes (pulse every ~5.5s)
    local bloomA = 0.20 + 0.15 * math.abs(math.sin(t * 0.571))  -- ~5.5s period
    splash.bloom:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, bloomA)

    -- 4. embers
    tickEmbers(t)

    -- 5. title entrance
    local pk  = easeOut(seg(t, T_KICKER, 0.7))
    local ptl = easeOutStrong(seg(t, T_TITLE, 0.85))
    local ptg = easeOut(seg(t, T_TAG, 0.7))

    if CFG.USE_TITLE_TEXTURE then
        splash.titleTex:SetAlpha(ptl)
    else
        -- kicker: rise + fade
        splash.kicker:SetAlpha(pk)
        -- title: carve-in (scale 1.14→1, blur clears via alpha approach)
        splash.title:SetAlpha(ptl)
        -- foil sweep: runs for ~1.05s starting at T_FOIL, one-shot
        if foilPhase and foilPhase < 1 then
            foilPhase = foilPhase + dt / 1.05
            if foilPhase > 1 then foilPhase = 1 end
            -- sweep a bright highlight across the text left→right via alpha wave
            local sweepPos = foilPhase          -- 0→1 across the sweep
            local sweepWidth = 0.28
            local center = sweepPos
            local brightness = math.max(0, 1 - math.abs(sweepPos - 0.5) / sweepWidth)
            splash.foil:SetAlpha(brightness * 0.75)
        elseif foilPhase == nil and t >= T_FOIL then
            foilPhase = 0
            playCue(CFG.SND_SHIMMER)
        end
    end
    -- scale carve for title (1.14 → 1.0 as ptl goes 0→1)
    splash.titleHolder:SetScale(1.14 - 0.14 * ptl)
    splash.tag:SetAlpha(ptg)

    -- 6. impact / shimmer cues
    if not struck and t >= T_TITLE + 0.35 then
        struck = true; playCue(CFG.SND_IMPACT)
    end

    -- 7. prompt pulse
    if not CFG.AUTO_ADVANCE then
        local on = clamp((t - T_PROMPT) / 0.4, 0, 1)
        splash.prompt:SetAlpha(on * (0.35 + 0.65 * math.abs(math.sin(t * 1.745))))  -- 1.8s period
    else
        splash.prompt:SetAlpha(0)
        if t >= T_PROMPT + CFG.AUTO_DELAY and not advancing then Splash.Advance() end
    end

    -- 8. snarls
    if CFG.SOUND and nextSnarl and t >= nextSnarl then
        playCue(CFG.SND_SNARL)
        nextSnarl = t + CFG.SNARL_MIN + math.random() * (CFG.SNARL_MAX - CFG.SNARL_MIN)
    end

    -- 9. fade-out on advance
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

    t, advancing, advT, struck, shimmered, foilPhase = 0, false, 0, false, false, nil
    onDone    = onComplete
    nextSnarl = CFG.SOUND and (2.5 + math.random() * 2) or nil

    -- reset all elements
    splash.revealTex:SetAlpha(1)
    splash.bloom:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.20)
    splash.prompt:SetAlpha(0)
    for _, c in ipairs(splash.corners) do c:SetAlpha(0) end
    if not CFG.USE_TITLE_TEXTURE then
        splash.kicker:SetAlpha(0)
        splash.title:SetAlpha(0)
        splash.foil:SetAlpha(0)
    end
    splash.tag:SetAlpha(0)
    splash.titleHolder:SetScale(1.14)

    splash:SetAlpha(1)
    splash:Show()
    panel:SetScale(fitScale())
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)

    playCue(CFG.SND_REVEAL)
    if CFG.SOUND and PlayMusic then pcall(PlayMusic, CFG.SND_AMBIENCE) end
end

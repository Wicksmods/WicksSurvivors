-- Wick's Survivors
-- Splash.lua: animated title splash that plays before the main menu.
--
-- Matches the addon's existing style: a single OnUpdate timeline driving alpha /
-- position / scale (same approach as the menu orb and particle effects) — no
-- AnimationGroups, safe on the 2.5.x (interface 20505) client.
--
-- Works with ZERO new assets: Cinzel FontString title + built-in TBC sound IDs.
-- Upgrade hooks (all optional, see CONFIG below):
--   * Art\splash_bg     baked cover backdrop (TGA/BLP)  -> set USE_BG_TEXTURE
--   * Art\splash_title  baked gold logotype (TGA/BLP)   -> set USE_TITLE_TEXTURE
--   * Sounds\*.ogg       custom audio cues               -> set the SND_* paths
--
-- .toc: add this line AFTER Skin.lua, BEFORE UI.lua:
--     Splash.lua
-- UI.lua: see the one-line hook in SPLASH_HANDOFF.md (UI.ToggleMenu).

local ADDON, ns = ...
local WS = WicksSurvivors
local C  = WS.C

WS.Splash = {}
local Splash = WS.Splash

local ART = "Interface\\AddOns\\WicksSurvivors\\Art\\"
local SND = "Interface\\AddOns\\WicksSurvivors\\Sounds\\"
local CINZEL = "Interface\\AddOns\\WicksSurvivors\\Fonts\\Cinzel.ttf"
local FRIZQT = "Fonts\\FRIZQT__.TTF"

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local CFG = {
    USE_BG_TEXTURE    = false,   -- true once Art\splash_bg exists (landscape cover)
    USE_TITLE_TEXTURE = false,   -- true once Art\splash_title exists (gold lockup)
    PLAY_ONCE         = true,    -- only auto-play the splash the first /survivors per session
    AUTO_ADVANCE      = false,   -- true = jump to menu on its own; false = wait for a click
    AUTO_DELAY        = 1.0,     -- extra hold after the intro before auto-advancing

    SOUND      = true,
    -- Custom cues bounced from the prototype synth (convert the provided .wav -> .ogg
    -- and drop them in WicksSurvivors\Sounds\). A number => PlaySound(id,"SFX");
    -- a string => PlaySoundFile(path,"SFX") which silently no-ops if the file is
    -- missing (so swap any line back to a built-in id if you prefer).
    SND_REVEAL   = SND .. "reveal.ogg",   -- low swell, on show
    SND_IMPACT   = SND .. "impact.ogg",   -- deep boom as the title lands
    SND_SHIMMER  = SND .. "shimmer.ogg",  -- dark metallic shimmer, just after impact
    SND_MENU     = SND .. "menu.ogg",     -- fel chord, on advance to menu
    SND_AMBIENCE = SND .. "ambience.ogg", -- PlayMusic loop (32s seamless)
    SND_SNARL    = SND .. "snarl.ogg",    -- random creature growl
    SNARL_MIN = 5, SNARL_MAX = 13,      -- seconds between snarls
}

-- timeline beats (seconds) — mirror the HTML prototype's pacing
local T_REVEAL  = 1.0
local T_KICKER  = 0.40
local T_TITLE   = 0.72
local T_TAG     = 1.30
local T_PROMPT  = 2.05
local T_OUT     = 0.55   -- fade-out duration on advance

-- ── helpers ─────────────────────────────────────────────────────────────────
local function clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
-- normalised 0..1 progress of a beat that starts at `start` and lasts `dur`
local function seg(t, start, dur) return clamp((t - start) / dur, 0, 1) end
local function easeOut(x) return 1 - (1 - x) * (1 - x) * (1 - x) end

local function font(fs, size)
    if not pcall(fs.SetFont, fs, CINZEL, size, "") then fs:SetFont(FRIZQT, size, "") end
end

local function playCue(cue)
    if not CFG.SOUND or cue == nil then return end
    if type(cue) == "number" then
        PlaySound(cue, "SFX")
    else
        PlaySoundFile(cue, "SFX")   -- silently no-ops if the file is absent
    end
end

-- ── build (once) ──────────────────────────────────────────────────────────────
local splash
local function Build()
    if splash then return end

    splash = CreateFrame("Button", "WicksSurvivorsSplash", UIParent)
    splash:SetAllPoints(UIParent)
    splash:SetFrameStrata("FULLSCREEN_DIALOG")
    splash:SetToplevel(true)
    splash:EnableMouse(true)
    splash:Hide()

    -- void backdrop fill
    local void = splash:CreateTexture(nil, "BACKGROUND")
    void:SetColorTexture(C.void.r, C.void.g, C.void.b, 1)
    void:SetAllPoints(splash)

    -- optional baked cover backdrop
    if CFG.USE_BG_TEXTURE then
        local bg = splash:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetTexture(ART .. "splash_bg")
        bg:SetAllPoints(splash)
        splash.bg = bg
    end

    -- centered fel bloom (reuses the menu's Art\glow)
    local bloom = splash:CreateTexture(nil, "BACKGROUND", nil, 2)
    bloom:SetTexture(ART .. "glow")
    bloom:SetBlendMode("ADD")
    bloom:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.5)
    bloom:SetSize(900, 900)
    bloom:SetPoint("CENTER", splash, "CENTER", 0, 40)
    splash.bloom = bloom

    -- corner brackets (fel L-marks), scaled up for fullscreen
    local arm, thick, ins = 28, 3, 26
    local function bracket(a, ox, oy, w, h)
        local t = splash:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
        t:SetSize(w, h); t:SetPoint(a, splash, a, ox, oy)
        return t
    end
    splash.corners = {}
    for _, c in ipairs({
        {"TOPLEFT",  ins,-ins, arm,thick},{"TOPLEFT",  ins,-ins, thick,arm},
        {"TOPRIGHT",-ins,-ins, arm,thick},{"TOPRIGHT",-ins,-ins, thick,arm},
        {"BOTTOMLEFT", ins,ins, arm,thick},{"BOTTOMLEFT", ins,ins, thick,arm},
        {"BOTTOMRIGHT",-ins,ins, arm,thick},{"BOTTOMRIGHT",-ins,ins, thick,arm},
    }) do splash.corners[#splash.corners+1] = bracket(c[1],c[2],c[3],c[4],c[5]) end

    -- title holder (scaled for the carve-in)
    local holder = CreateFrame("Frame", nil, splash)
    holder:SetSize(900, 220)
    holder:SetPoint("CENTER", splash, "CENTER", 0, 40)
    splash.holder = holder

    if CFG.USE_TITLE_TEXTURE then
        local tt = holder:CreateTexture(nil, "ARTWORK")
        tt:SetTexture(ART .. "splash_title")
        tt:SetPoint("CENTER")
        tt:SetSize(820, 220)   -- match your exported lockup's aspect
        splash.titleTex = tt
    else
        local kicker = holder:CreateFontString(nil, "ARTWORK")
        font(kicker, 30); kicker:SetText("WICK'S")
        kicker:SetTextColor(C.text.r, C.text.g, C.text.b)
        kicker:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.5); kicker:SetShadowOffset(0, 0)
        kicker:SetPoint("BOTTOM", holder, "CENTER", 0, 46)
        splash.kicker = kicker

        local title = holder:CreateFontString(nil, "ARTWORK")
        font(title, 96); title:SetText("SURVIVORS")
        title:SetTextColor(0.886, 0.831, 0.659)        -- parchment-gold
        title:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.6); title:SetShadowOffset(0, -2)
        title:SetPoint("CENTER", holder, "CENTER", 0, -6)
        splash.title = title
    end

    -- tagline
    local tag = splash:CreateFontString(nil, "OVERLAY")
    tag:SetFont(FRIZQT, 16, "")
    tag:SetText("Something ancient has woken.")
    tag:SetTextColor(C.fel.r, C.fel.g, C.fel.b)
    tag:SetPoint("TOP", holder, "BOTTOM", 0, -6)
    splash.tag = tag

    -- prompt
    local prompt = splash:CreateFontString(nil, "OVERLAY")
    prompt:SetFont(FRIZQT, 14, "")
    prompt:SetText("CLICK TO BEGIN")
    prompt:SetTextColor(C.fel.r, C.fel.g, C.fel.b)
    prompt:SetPoint("BOTTOM", splash, "BOTTOM", 0, 120)
    splash.prompt = prompt

    -- reveal black (fades OUT to reveal the scene)
    local reveal = splash:CreateTexture(nil, "OVERLAY", nil, 7)
    reveal:SetColorTexture(0.016, 0.008, 0.039, 1)
    reveal:SetAllPoints(splash)
    splash.reveal = reveal

    splash:SetScript("OnClick", function() Splash.Advance() end)
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)
end

-- ── runtime state ─────────────────────────────────────────────────────────────
local t, advancing, advT, onDone, struck, shimmered, nextSnarl

local function setEntrance(fs, holderRef, prog, rise)
    -- alpha + rise; for the FontString title we also carve via holder scale
    fs:SetAlpha(prog)
end

function Splash.Tick(dt)
    t = t + dt

    -- reveal black out
    splash.reveal:SetAlpha(1 - easeOut(seg(t, 0, T_REVEAL)))

    -- title entrance (kicker / title / tag), staggered with a rise + carve
    local pk = easeOut(seg(t, T_KICKER, 0.7))
    local ptl = easeOut(seg(t, T_TITLE, 0.85))
    local ptg = easeOut(seg(t, T_TAG, 0.7))

    if CFG.USE_TITLE_TEXTURE then
        splash.titleTex:SetAlpha(ptl)
    else
        splash.kicker:SetAlpha(pk)
        splash.kicker:SetPoint("BOTTOM", splash.holder, "CENTER", 0, 46 - (1 - pk) * 22)
        splash.title:SetAlpha(ptl)
    end
    -- carve: holder scales 1.10 -> 1.0 as the title lands
    splash.holder:SetScale(1.10 - 0.10 * ptl)
    splash.tag:SetAlpha(ptg)

    -- one-shot impact + shimmer as the title lands
    if not struck and t >= T_TITLE + 0.35 then
        struck = true
        playCue(CFG.SND_IMPACT)
    end
    if not shimmered and t >= T_TITLE + 0.55 then
        shimmered = true
        playCue(CFG.SND_SHIMMER)
    end

    -- prompt pulse (only when not auto-advancing)
    if not CFG.AUTO_ADVANCE then
        local on = clamp((t - T_PROMPT) / 0.4, 0, 1)
        splash.prompt:SetAlpha(on * (0.4 + 0.6 * math.abs(math.sin(t * 2.2))))
    else
        splash.prompt:SetAlpha(0)
        if t >= T_PROMPT + CFG.AUTO_DELAY and not advancing then Splash.Advance() end
    end

    -- random snarls under the bed
    if CFG.SOUND and nextSnarl and t >= nextSnarl then
        playCue(CFG.SND_SNARL)
        nextSnarl = t + CFG.SNARL_MIN + math.random() * (CFG.SNARL_MAX - CFG.SNARL_MIN)
    end

    -- fade-out on advance
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

-- Play the splash, then run onComplete (e.g. show the menu).
function Splash.Play(onComplete, force)
    Build()
    if CFG.PLAY_ONCE and Splash.seen and not force then
        if onComplete then onComplete() end
        return
    end
    Splash.seen = true

    t, advancing, advT, struck, shimmered = 0, false, 0, false, false
    onDone = onComplete
    nextSnarl = CFG.SOUND and (2.5 + math.random() * 2) or nil

    splash:SetAlpha(1)
    splash:Show()
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)

    playCue(CFG.SND_REVEAL)
    if CFG.SOUND and PlayMusic then pcall(PlayMusic, CFG.SND_AMBIENCE) end  -- loops; no-ops if missing
end

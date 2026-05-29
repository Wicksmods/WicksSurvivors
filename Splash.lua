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
    USE_BG_TEXTURE    = true,    -- uses Art\splash_bg.tga (shipped painterly atmosphere)
    USE_TITLE_TEXTURE = true,    -- uses Art\splash_title.tga (shipped); false = Cinzel FontString
    SHOW_SCENE        = true,    -- compose the cover scene from the in-game sprites
    BUBBLES           = true,    -- floating fel bubbles (like the HTML embers)
    SCENE_FPS_MULT    = 1,     -- splash-only flipbook speed (1 = same as gameplay)
    PLAY_ONCE         = false,   -- (debug: always play) set true later for once-per-session
    AUTO_ADVANCE      = false,   -- true = jump to menu on its own; false = wait for a click
    AUTO_DELAY        = 1.0,     -- extra hold after the intro before auto-advancing
    -- splash window size (it scales a 1280x800 design to fit). nil = the game arena.
    WIDTH  = nil,                -- e.g. 980 ; nil -> WS.ARENA_W (980)
    HEIGHT = nil,                -- e.g. 680 ; nil -> WS.ARENA_H (680)

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

-- flipbook frame (own copy so we can flip horizontally; WS.SetAnimFrame can't)
local function animFrame(tex, key, phase, flip)
    local a = WS.ANIM and WS.ANIM[key]
    if not a then return end
    local n = a.frames
    local idx = math.floor(GetTime() * a.fps * (CFG.SCENE_FPS_MULT or 1) + (phase or 0) * n) % n
    local l = idx / n
    if flip then tex:SetTexCoord(l + 1/n, l, 0, 1) else tex:SetTexCoord(l, l + 1/n, 0, 1) end
end

local function playCue(cue, fallbackId)
    if not CFG.SOUND or cue == nil then return end
    if type(cue) == "number" then
        PlaySound(cue, "SFX")
    else
        -- try the custom .ogg; if it isn't installed yet, play a built-in id so the
        -- splash still has audio (PlaySoundFile returns willPlay=false when missing)
        local willPlay = PlaySoundFile(cue, "SFX")
        if not willPlay and fallbackId then PlaySound(fallbackId, "SFX") end
    end
end

-- ── build (once) ──────────────────────────────────────────────────────────────
local splash
local function Build()
    if splash then return end

    splash = CreateFrame("Button", "WicksSurvivorsSplash", UIParent)
    -- Authored on a fixed 1280x800 design canvas (same as Title Splash.html), then
    -- SCALED to the game window so it's a framed window, not a fullscreen overlay.
    local DW, DH = 1280, 800
    local GW = CFG.WIDTH  or WS.ARENA_W or 980
    local GH = CFG.HEIGHT or WS.ARENA_H or 680
    splash:SetSize(DW, DH)
    splash:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    splash:SetScale(math.min(GW / DW, GH / DH))
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
    bloom:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.18)
    bloom:SetSize(1000, 1000)
    bloom:SetPoint("CENTER", splash, "CENTER", 0, 40)
    splash.bloom = bloom

    -- ── character scene, composed from the in-game sprites (echoes cover C) ──
    -- The painted cover is HTML canvas and can't render in-engine; instead we
    -- place the real sprite textures and flipbook-animate them in Tick.
    splash.scene = {}
    if CFG.SHOW_SCENE then
      local ok, err = pcall(function()
        local function addSprite(key, sub, anchor, ox, oy, size, opts)
            opts = opts or {}
            if opts.glow then
                local gl = splash:CreateTexture(nil, "BACKGROUND", nil, 3)
                gl:SetTexture(ART .. "glow"); gl:SetBlendMode("ADD")
                local g = opts.glow
                gl:SetVertexColor(g[1], g[2], g[3], opts.glowA or 0.45)
                local gs = (opts.glowS or 1.5) * size
                gl:SetSize(gs, gs)
                gl:SetPoint("CENTER", splash, anchor, ox, oy)
            end
            local tx = splash:CreateTexture(nil, "ARTWORK", nil, sub or 0)
            tx:SetTexture(WS.TEX[key])
            tx:SetSize(size, size)
            tx:SetPoint("CENTER", splash, anchor, ox, oy)
            if opts.tint then tx:SetVertexColor(opts.tint[1], opts.tint[2], opts.tint[3], opts.tint[4] or 1) end
            splash.scene[#splash.scene + 1] = { tex = tx, key = key, phase = opts.phase or 0, flip = opts.flip }
            return tx
        end

        -- looming boss archetypes behind the eye, dimmed
        addSprite("boss_illidan", 0, "CENTER", -310, 20, 440,
            { tint={0.22,0.17,0.32,0.9}, glow={0.48,0.31,0.78}, glowA=0.32, glowS=1.3, flip=true, phase=0.10 })
        addSprite("boss_nef", 0, "CENTER", 310, 20, 440,
            { tint={0.26,0.15,0.13,0.9}, glow={0.91,0.47,0.23}, glowA=0.28, glowS=1.3, phase=0.20 })

        -- the great eye, dominating the top
        addSprite("boss_cthun", 1, "TOP", 0, -250, 500,
            { glow={0.37,0.78,0.47}, glowA=0.50, glowS=1.5, phase=0.10 })

        -- (normal enemies removed — hero key art, like the HTML)

        -- bottom scrim to seat the horde — single smooth vertical fade (no banding)
        local scrim = splash:CreateTexture(nil, "ARTWORK", nil, 5)
        scrim:SetColorTexture(1, 1, 1, 1)
        scrim:SetHeight(240)
        scrim:SetPoint("BOTTOMLEFT", splash, "BOTTOMLEFT")
        scrim:SetPoint("BOTTOMRIGHT", splash, "BOTTOMRIGHT")
        local sr, sg, sb = 0.016, 0.010, 0.035
        if scrim.SetGradientAlpha then            -- legacy (2.5.x): opaque at bottom -> clear at top
            pcall(scrim.SetGradientAlpha, scrim, "VERTICAL", sr, sg, sb, 0.85, sr, sg, sb, 0)
        elseif scrim.SetGradient and CreateColor then
            pcall(scrim.SetGradient, scrim, "VERTICAL", CreateColor(sr, sg, sb, 0.85), CreateColor(sr, sg, sb, 0))
        else
            scrim:SetColorTexture(sr, sg, sb, 0.4)
        end

        -- Wick, lit, front and centre
        addSprite("player", 6, "BOTTOM", 0, 150, 280,
            { glow={0.31,0.78,0.47}, glowA=0.62, glowS=1.7, phase=0.05 })
      end)
      if not ok then print("|cffff5555WS Splash scene error:|r " .. tostring(err)) end
    end

    -- floating fel bubbles (like the embers drifting up in Title Splash.html)
    splash.bubbles = {}
    if CFG.BUBBLES then
        for i = 1, 16 do
            local bx = splash:CreateTexture(nil, "ARTWORK", nil, 4)
            bx:SetTexture(ART .. "glow"); bx:SetBlendMode("ADD")
            bx:SetVertexColor(0.45, 0.85, 0.55, 0.5)
            local sz = 8 + math.random() * 16
            bx:SetSize(sz, sz)
            splash.bubbles[i] = { tex = bx, x = math.random() * 1280, y = math.random() * 800,
                spd = 18 + math.random() * 42, drift = math.random() * 6.28 }
        end
    end

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
        tt:SetSize(900, 450)   -- splash_title.png is 1024x512 (2:1); keep this aspect
        splash.titleTex = tt
    else
        local kicker = holder:CreateFontString(nil, "ARTWORK")
        font(kicker, 42); kicker:SetText("WICK'S")
        kicker:SetTextColor(C.text.r, C.text.g, C.text.b)
        kicker:SetShadowColor(C.fel.r, C.fel.g, C.fel.b, 0.5); kicker:SetShadowOffset(0, 0)
        kicker:SetPoint("BOTTOM", holder, "CENTER", 0, 86)
        splash.kicker = kicker

        local title = holder:CreateFontString(nil, "ARTWORK")
        font(title, 140); title:SetText("SURVIVORS")
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
    prompt:SetPoint("BOTTOM", splash, "BOTTOM", 0, 280)
    splash.prompt = prompt

    -- scene dim (rises when the menu opens over the splash)
    local dim = splash:CreateTexture(nil, "ARTWORK", nil, 7)
    dim:SetColorTexture(0.02, 0.012, 0.04, 1)
    dim:SetAllPoints(splash)
    dim:SetAlpha(0)
    splash.dim = dim

    -- reveal black (fades OUT to reveal the scene)
    local reveal = splash:CreateTexture(nil, "OVERLAY", nil, 7)
    reveal:SetColorTexture(0.016, 0.008, 0.039, 1)
    reveal:SetAllPoints(splash)
    splash.reveal = reveal

    splash:SetScript("OnClick", function() Splash.Advance() end)
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)
end

-- ── runtime state ─────────────────────────────────────────────────────────────
local t, advancing, advT, onDone, struck, shimmered, menuOpened, nextSnarl

local function setEntrance(fs, holderRef, prog, rise)
    -- alpha + rise; for the FontString title we also carve via holder scale
    fs:SetAlpha(prog)
end

function Splash.Tick(dt)
    t = t + dt

    -- flipbook-animate the scene sprites
    if splash.scene then
        for i = 1, #splash.scene do
            local s = splash.scene[i]
            animFrame(s.tex, s.key, s.phase, s.flip)
        end
    end

    -- drifting fel bubbles
    if splash.bubbles then
        for i = 1, #splash.bubbles do
            local b = splash.bubbles[i]
            b.y = b.y + b.spd * dt
            if b.y > 820 then b.y = -20; b.x = math.random() * 1280 end
            local dx = math.sin(t * 0.6 + b.drift) * 18
            b.tex:SetPoint("CENTER", splash, "BOTTOMLEFT", b.x + dx, b.y)
            b.tex:SetAlpha(0.18 + 0.3 * math.abs(math.sin(t * 0.8 + b.drift)))
        end
    end

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
        splash.kicker:SetPoint("BOTTOM", splash.holder, "CENTER", 0, 86 - (1 - pk) * 22)
        splash.title:SetAlpha(ptl)
    end
    -- carve: holder scales 1.10 -> 1.0 as the title lands
    splash.holder:SetScale(1.10 - 0.10 * ptl)
    splash.tag:SetAlpha(ptg)

    -- one-shot impact + shimmer as the title lands
    if not struck and t >= T_TITLE + 0.35 then
        struck = true
        playCue(CFG.SND_IMPACT, 1386)
    end
    if not shimmered and t >= T_TITLE + 0.55 then
        shimmered = true
        playCue(CFG.SND_SHIMMER, 600)
    end

    -- prompt: hide once advancing; otherwise pulse (or auto-advance)
    if advancing then
        splash.prompt:SetAlpha(0)
    elseif not CFG.AUTO_ADVANCE then
        local on = clamp((t - T_PROMPT) / 0.4, 0, 1)
        splash.prompt:SetAlpha(on * (0.4 + 0.6 * math.abs(math.sin(t * 2.2))))
    else
        splash.prompt:SetAlpha(0)
        if t >= T_PROMPT + CFG.AUTO_DELAY then Splash.Advance() end
    end

    -- random snarls under the bed
    if CFG.SOUND and nextSnarl and t >= nextSnarl then
        playCue(CFG.SND_SNARL, 1391)
        nextSnarl = t + CFG.SNARL_MIN + math.random() * (CFG.SNARL_MAX - CFG.SNARL_MIN)
    end

    -- advancing: keep the splash as a backdrop, dock the title up, dim the scene,
    -- and open the menu OVER the top (via onDone). The splash is NOT hidden here;
    -- it's hidden when the menu closes (WS.Splash.Hide, wired in UI.ToggleMenu).
    if advancing then
        advT = advT + dt
        local e = easeOut(clamp(advT / T_OUT, 0, 1))
        splash.holder:SetScale(1 - 0.42 * e)
        splash.holder:SetPoint("CENTER", splash, "CENTER", 0, 40 + e * 150)
        splash.tag:SetAlpha(1 - e)
        if splash.dim then splash.dim:SetAlpha(0.5 * e) end
        if e >= 1 and not menuOpened then
            menuOpened = true
            if onDone then onDone() end
        end
    end
end

function Splash.Advance()
    if advancing then return end
    advancing = true; advT = 0; menuOpened = false
    splash:SetFrameStrata("MEDIUM")   -- drop below the HIGH-strata menu so it opens on top
    playCue(CFG.SND_MENU, 850)
end

-- Hide the splash backdrop (call when the menu closes / game starts).
function Splash.Hide()
    if not splash or not splash:IsShown() then return end
    splash:SetScript("OnUpdate", nil)
    splash:Hide()
    if PlayMusic then pcall(StopMusic) end
end

-- Play the splash, then run onComplete (e.g. show the menu).
function Splash.Play(onComplete, force)
    Build()
    if CFG.PLAY_ONCE and Splash.seen and not force then
        if onComplete then onComplete() end
        return
    end
    Splash.seen = true

    t, advancing, advT, struck, shimmered, menuOpened = 0, false, 0, false, false, false
    onDone = onComplete
    nextSnarl = CFG.SOUND and (2.5 + math.random() * 2) or nil

    -- reset any docked/dimmed state from a previous run
    splash:SetFrameStrata("FULLSCREEN_DIALOG")
    splash.holder:SetScale(1)
    splash.holder:SetPoint("CENTER", splash, "CENTER", 0, 40)
    if splash.dim then splash.dim:SetAlpha(0) end

    splash:SetAlpha(1)
    splash:Show()
    splash:SetScript("OnUpdate", function(self, dt) Splash.Tick(dt) end)

    playCue(CFG.SND_REVEAL, 3337)
    if CFG.SOUND and PlayMusic then pcall(PlayMusic, CFG.SND_AMBIENCE) end  -- loops; no-ops if missing
end

-- Test command: force-play the splash any time (bypasses PLAY_ONCE).
SLASH_WSSPLASH1 = "/wssplash"
SlashCmdList["WSSPLASH"] = function()
    Splash.Play(function() print("|cff4FC778WS Splash|r done") end, true)
end

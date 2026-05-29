-- Wick's Survivors
-- UI.lua: all frames, rendering, menus, effects

local ADDON, ns = ...
local WS = WicksSurvivors
WS.UI = {}
local UI = WS.UI

local C = WS.C

-- ── Sounds ───────────────────────────────────────────────────────────────────
-- Uses WoW built-in sound IDs (guaranteed present in TBC client)

local SFX = {
    hit        = "Interface\\AddOns\\WicksSurvivors\\Sounds\\hit.ogg",       -- fallback to built-in below
    pickup_xp  = 871,    -- LOOT_COIN  (soft clink)
    pickup_hp  = 569,    -- DRINK      (potion glug)
    levelup    = 888,    -- LEVELUP
    wave       = 3337,   -- READY_CHECK (soft bell)
    player_hit = 1386,   -- DAMAGE_TICK (low thud)
    death      = 1391,   -- CREATURE_DEATH generic
    combo      = 600,    -- UI_TALKINGHEAD_IN (bright chime)
}

function UI.PlaySFX(id)
    if type(id) == "number" then
        PlaySound(id, "SFX")
    end
end

-- ── Utility ──────────────────────────────────────────────────────────────────

local function MakeTex(parent, layer, col, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(col.r, col.g, col.b, a or col.a or 1)
    return t
end

local CINZEL = "Interface\\AddOns\\WicksSurvivors\\Fonts\\Cinzel.ttf"
local FRIZQT = "Fonts\\FRIZQT__.TTF"

-- MakeText: Cinzel for size>=13 (titles/headers), FRIZQT for smaller body text.
-- Pass useFriz=true to force FRIZQT (gameplay floaters, damage numbers need OUTLINE).
local function MakeText(parent, size, col, justify, useFriz)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local sz = size or 11
    if useFriz then
        f:SetFont(FRIZQT, sz, "OUTLINE")
    elseif sz >= 13 then
        local ok = pcall(f.SetFont, f, CINZEL, sz, "")
        if not ok then f:SetFont(FRIZQT, sz, "") end
    else
        f:SetFont(FRIZQT, sz, "")
    end
    if col then f:SetTextColor(col.r, col.g, col.b, col.a or 1) end
    if justify then f:SetJustifyH(justify) end
    return f
end

local function AddCornerAccents(frame)
    local arm, thick = 10, 2
    local corners = {
        {a="TOPLEFT",     w=arm,   h=thick, ox= 4, oy=-4},
        {a="TOPLEFT",     w=thick, h=arm,   ox= 4, oy=-4},
        {a="TOPRIGHT",    w=arm,   h=thick, ox=-4, oy=-4},
        {a="TOPRIGHT",    w=thick, h=arm,   ox=-4, oy=-4},
        {a="BOTTOMLEFT",  w=arm,   h=thick, ox= 4, oy= 4},
        {a="BOTTOMLEFT",  w=thick, h=arm,   ox= 4, oy= 4},
        {a="BOTTOMRIGHT", w=arm,   h=thick, ox=-4, oy= 4},
        {a="BOTTOMRIGHT", w=thick, h=arm,   ox=-4, oy= 4},
    }
    for _, c in ipairs(corners) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
        t:SetSize(c.w, c.h)
        t:SetPoint(c.a, frame, c.a, c.ox, c.oy)
    end
end

local function HpColor(pct)
    if pct > 0.6 then
        return 0.247, 0.561, 0.298   -- #3f8f4c design green
    elseif pct > 0.3 then
        local t = (pct - 0.3) / 0.3
        return 0.75, 0.35 + t * 0.2, 0.05
    else
        local flicker = math.abs(math.sin(GetTime() * 8)) * 0.3
        return 0.85 + flicker * 0.1, 0.08, 0.04
    end
end

-- ── Object pool ───────────────────────────────────────────────────────────────

local POOL_PARENT
local enemyPool   = {}
local projPool    = {}
local pickupPool  = {}

local function AcquireFrame(pool, parent, size)
    local f = table.remove(pool)
    if not f then
        f = CreateFrame("Frame", nil, parent or POOL_PARENT)
        f:SetSize(size or 16, size or 16)
        f.bg = f:CreateTexture(nil, "ARTWORK")
        f.bg:SetAllPoints(f)
    end
    f:SetParent(parent or POOL_PARENT)
    f:Show()
    return f
end

local function ReleaseFrame(pool, f)
    f:Hide()
    pool[#pool + 1] = f
end

-- ── Particle system ───────────────────────────────────────────────────────────

local particles    = {}
local particlePool = {}

local function AcquireParticle()
    local p = table.remove(particlePool)
    if not p then
        p = CreateFrame("Frame", nil, POOL_PARENT)
        p:SetSize(6, 6)
        p.tex = p:CreateTexture(nil, "OVERLAY")
        p.tex:SetColorTexture(1, 1, 1, 1)
        p.tex:SetAllPoints(p)
    end
    p:SetParent(POOL_PARENT)
    p:SetFrameLevel((POOL_PARENT:GetFrameLevel() or 0) + 8)
    return p
end

local function ReleaseParticle(p)
    p:Hide()
    particlePool[#particlePool + 1] = p
end

-- spark burst: many fast small particles
local function SpawnSparks(x, y, count, r, g, b, speedMult)
    speedMult = speedMult or 1
    for i = 1, count do
        local p = AcquireParticle()
        local angle = math.random() * math.pi * 2
        local speed = (80 + math.random() * 160) * speedMult
        p.x, p.y   = x, y
        p.vx       = math.cos(angle) * speed
        p.vy       = math.sin(angle) * speed
        p.life     = 0.3 + math.random() * 0.25
        p.maxLife  = p.life
        p.r, p.g, p.b = r, g, b
        p.sz       = 3 + math.random() * 4
        p.kind     = "spark"
        p:Show()
        particles[#particles + 1] = p
    end
end

-- ember: slower, drifts upward
local function SpawnEmbers(x, y, count, r, g, b)
    for i = 1, count do
        local p = AcquireParticle()
        local angle = -math.pi/2 + (math.random() - 0.5) * math.pi
        local speed = 30 + math.random() * 60
        p.x, p.y   = x + (math.random()-0.5)*20, y + (math.random()-0.5)*10
        p.vx       = math.cos(angle) * speed
        p.vy       = math.sin(angle) * speed - 20
        p.life     = 0.5 + math.random() * 0.4
        p.maxLife  = p.life
        p.r, p.g, p.b = r, g, b
        p.sz       = 2 + math.random() * 3
        p.kind     = "ember"
        p:Show()
        particles[#particles + 1] = p
    end
end

-- trail dot: short life, no velocity
local function SpawnTrailDot(x, y, r, g, b, sz)
    local p = AcquireParticle()
    p.x, p.y   = x, y
    p.vx, p.vy = 0, 0
    p.life     = 0.18
    p.maxLife  = p.life
    p.r, p.g, p.b = r, g, b
    p.sz       = sz or 8
    p.kind     = "trail"
    p:Show()
    particles[#particles + 1] = p
end

local function UpdateParticles(elapsed)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - elapsed
        if p.life <= 0 then
            ReleaseParticle(p)
            table.remove(particles, i)
        else
            p.x  = p.x + p.vx * elapsed
            p.y  = p.y + p.vy * elapsed
            if p.kind == "spark" or p.kind == "ember" then
                p.vx = p.vx * 0.85
                p.vy = p.vy * 0.85
            end
            local alpha = p.life / p.maxLife
            local sz    = p.sz * (p.kind == "trail" and alpha or (0.4 + alpha * 0.6))
            if sz < 1 then sz = 1 end
            p:SetSize(sz, sz)
            p:SetPoint("TOPLEFT", POOL_PARENT, "TOPLEFT", p.x - sz/2, -(p.y - sz/2))
            p.tex:SetVertexColor(p.r, p.g, p.b, alpha)
        end
    end
end

function UI.SpawnDeathBurst(x, y, r, g, b)
    if not POOL_PARENT then return end
    SpawnSparks(x, y, 18, r, g, b, 1.0)
    SpawnEmbers(x, y, 8,  r * 0.8, g * 0.8, b * 0.8)
    -- bright white core sparks
    SpawnSparks(x, y, 6, 1, 1, 1, 1.4)
end

function UI.SpawnHitSpark(x, y, r, g, b)
    if not POOL_PARENT then return end
    SpawnSparks(x, y, 5, r, g, b, 0.6)
end

function UI.SpawnHealBurst(x, y)
    if not POOL_PARENT then return end
    SpawnSparks(x, y, 14, 0.2, 1.0, 0.3, 0.8)
    SpawnEmbers(x, y, 6, 0.3, 1.0, 0.5)
end

-- ── Shockwave rings ───────────────────────────────────────────────────────────

local rings    = {}
local ringPool = {}

local function SpawnRing(x, y, r, g, b, maxSize, duration)
    local ring = table.remove(ringPool)
    if not ring then
        ring = CreateFrame("Frame", nil, POOL_PARENT)
        ring:SetSize(10, 10)
        ring.tex = ring:CreateTexture(nil, "OVERLAY")
        ring.tex:SetColorTexture(1, 1, 1, 1)
        ring.tex:SetAllPoints(ring)
    end
    ring:SetParent(POOL_PARENT)
    ring:SetFrameLevel((POOL_PARENT:GetFrameLevel() or 0) + 7)
    ring.x, ring.y  = x, y
    ring.r, ring.g, ring.b = r, g, b
    ring.life       = duration or 0.4
    ring.maxLife    = ring.life
    ring.maxSize    = maxSize or 80
    ring:Show()
    rings[#rings + 1] = ring
end

local function UpdateRings(elapsed)
    for i = #rings, 1, -1 do
        local ring = rings[i]
        ring.life = ring.life - elapsed
        if ring.life <= 0 then
            ring:Hide()
            ringPool[#ringPool + 1] = ring
            table.remove(rings, i)
        else
            local t     = 1 - (ring.life / ring.maxLife)
            local sz    = ring.maxSize * t
            local alpha = (ring.life / ring.maxLife) * 0.7
            ring:SetSize(math.max(2, sz), math.max(2, sz))
            ring:SetPoint("CENTER", POOL_PARENT, "TOPLEFT", ring.x, -ring.y)
            ring.tex:SetVertexColor(ring.r, ring.g, ring.b, alpha)
        end
    end
end

function UI.SpawnShockwave(x, y, r, g, b, size)
    if not POOL_PARENT then return end
    SpawnRing(x, y, r, g, b, size or 80, 0.35)
    SpawnRing(x, y, 1, 1, 1, (size or 80) * 0.55, 0.22)
end

-- ── Damage numbers ────────────────────────────────────────────────────────────

local dmgNumbers    = {}
local dmgNumberPool = {}

function UI.SpawnDmgNumber(x, y, dmg, isCrit)
    if not POOL_PARENT then return end
    local d = table.remove(dmgNumberPool)
    if not d then
        d = {}
        d.fs = POOL_PARENT:CreateFontString(nil, "OVERLAY")
    end
    -- jitter so stacked numbers don't overlap
    d.x       = x + (math.random() - 0.5) * 20
    d.y       = y
    d.vy      = 65 + math.random() * 30
    d.life    = isCrit and 1.1 or 0.85
    d.maxLife = d.life
    if isCrit then
        d.fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
        d.fs:SetTextColor(1, 0.9, 0.1, 1)
        d.fs:SetText("CRIT " .. dmg .. "!")
    elseif dmg >= 100 then
        d.fs:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
        d.fs:SetTextColor(1, 0.6, 0.1, 1)
        d.fs:SetText(dmg)
    else
        d.fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        d.fs:SetTextColor(1, 1, 1, 1)
        d.fs:SetText(dmg)
    end
    d.fs:Show()
    dmgNumbers[#dmgNumbers + 1] = d
end

local function UpdateDmgNumbers(elapsed)
    for i = #dmgNumbers, 1, -1 do
        local d = dmgNumbers[i]
        d.life = d.life - elapsed
        if d.life <= 0 then
            d.fs:Hide()
            dmgNumberPool[#dmgNumberPool + 1] = d
            table.remove(dmgNumbers, i)
        else
            d.y  = d.y - d.vy * elapsed
            d.vy = d.vy * 0.90
            local alpha = math.min(1, d.life / d.maxLife * 2)
            d.fs:SetPoint("TOPLEFT", POOL_PARENT, "TOPLEFT", d.x - 14, -(d.y - 6))
            d.fs:SetAlpha(alpha)
        end
    end
end

-- ── Combo system ──────────────────────────────────────────────────────────────

local comboCount  = 0
local comboTimer  = 0
local comboLabel
local COMBO_WINDOW = 0.6  -- seconds between kills to keep chain alive

local COMBO_COLORS = {
    {1.0, 1.0, 1.0},   -- 2x white
    {0.4, 1.0, 0.4},   -- 3x green
    {1.0, 0.8, 0.1},   -- 4x yellow
    {1.0, 0.4, 0.1},   -- 5x orange
    {1.0, 0.1, 0.8},   -- 6x+ magenta
}

local function GetComboColor(n)
    local idx = math.min(n - 1, #COMBO_COLORS)
    return COMBO_COLORS[idx] or COMBO_COLORS[#COMBO_COLORS]
end

local function BuildComboLabel(parent)
    local cf = CreateFrame("Frame", nil, parent)
    cf:SetAllPoints(parent)
    cf:SetFrameLevel((parent:GetFrameLevel() or 0) + 50)
    comboLabel = cf:CreateFontString(nil, "OVERLAY")
    comboLabel:SetFont("Fonts\\FRIZQT__.TTF", 28, "THICKOUTLINE")
    -- anchor inside arena bounds: center, slightly above middle
    comboLabel:SetPoint("CENTER", parent, "CENTER", 0, 30)
    comboLabel:SetAlpha(0)
end

local function TriggerCombo(x, y)
    comboCount = comboCount + 1
    comboTimer = COMBO_WINDOW

    -- only announce at milestones: 5, 10, 15, 20...
    if comboCount < 5 or comboCount % 5 ~= 0 then return end

    local col = GetComboColor(comboCount)
    local label
    if comboCount >= 20 then
        label = comboCount .. "x  INSANE!!"
    elseif comboCount >= 10 then
        label = comboCount .. "x  ON FIRE!"
    else
        label = comboCount .. "x COMBO"
    end

    if comboLabel then
        comboLabel:SetFont("Fonts\\FRIZQT__.TTF", math.min(40, 28 + (comboCount / 5) * 2), "THICKOUTLINE")
        comboLabel:SetTextColor(col[1], col[2], col[3], 1)
        comboLabel:SetText(label)
        comboLabel:SetAlpha(1)
    end
    PlaySound(600, "SFX")

    if x and y and POOL_PARENT then
        local d = table.remove(dmgNumberPool)
        if not d then d = {}; d.fs = POOL_PARENT:CreateFontString(nil, "OVERLAY") end
        d.x, d.y = x, y - 20
        d.vy     = 80
        d.life   = 1.2; d.maxLife = 1.2
        d.fs:SetFont("Fonts\\FRIZQT__.TTF", math.min(20, 14 + comboCount / 5), "THICKOUTLINE")
        d.fs:SetTextColor(col[1], col[2], col[3], 1)
        d.fs:SetText(label)
        d.fs:Show()
        dmgNumbers[#dmgNumbers + 1] = d
    end
end

local function UpdateCombo(elapsed)
    if comboTimer > 0 then
        comboTimer = comboTimer - elapsed
        if comboTimer <= 0 then
            comboCount = 0
            comboTimer = 0
            if comboLabel then comboLabel:SetAlpha(0) end
        end
    end
    if comboLabel then
        local a = comboLabel:GetAlpha()
        if a > 0 then
            comboLabel:SetAlpha(math.max(0, a - elapsed * 1.2))
        end
    end
end

-- ── Projectile trails ─────────────────────────────────────────────────────────

local TRAIL_COLORS = {
    bolt      = {0.5, 0.2, 1.0},
    nova      = {0.3, 0.7, 1.0},
    chain     = {0.4, 0.9, 1.0},
    orb       = {C.fel.r, C.fel.g, C.fel.b},
    boss_nova = {1.0, 0.2, 0.2},
}
local TRAIL_INTERVAL = 0.035
local projTrailAccum = {}  -- keyed by projectile ref

local function UpdateTrails(projs, elapsed)
    -- index current projectiles for fast lookup
    local alive = {}
    for _, p in ipairs(projs) do alive[p] = true end
    -- prune accumulators for dead projs
    for k in pairs(projTrailAccum) do
        if not alive[k] then projTrailAccum[k] = nil end
    end
    for _, p in ipairs(projs) do
        if p.weaponId ~= "aura" then
            local acc = projTrailAccum[p] or 0
            acc = acc + elapsed
            if acc >= TRAIL_INTERVAL then
                acc = acc - TRAIL_INTERVAL
                local col = TRAIL_COLORS[p.weaponId] or {1, 1, 1}
                local sz  = p.weaponId == "orb" and 12 or (p.weaponId == "bolt" and 10 or 8)
                SpawnTrailDot(p.x, p.y, col[1], col[2], col[3], sz)
            end
            projTrailAccum[p] = acc
        end
    end
end

-- ── Hit flash + screen shake ──────────────────────────────────────────────────

local hitFlash
local hitFlashTimer    = 0
local playerShakeTimer = 0
local shakeX, shakeY   = 0, 0

local function BuildHitFlash(parent)
    hitFlash = parent:CreateTexture(nil, "OVERLAY")
    hitFlash:SetColorTexture(0.9, 0.05, 0.05, 0)
    hitFlash:SetAllPoints(parent)
    hitFlash:SetDrawLayer("OVERLAY", 6)
end

function UI.TriggerHitFlash()
    hitFlashTimer    = 0.3
    playerShakeTimer = 0.35
    PlaySound(1386, "SFX")
end

local function UpdateHitFlash(elapsed)
    if hitFlashTimer > 0 then
        hitFlashTimer = hitFlashTimer - elapsed
        local alpha = math.max(0, hitFlashTimer / 0.3) * 0.45
        hitFlash:SetColorTexture(0.9, 0.05, 0.05, alpha)
    end
    if playerShakeTimer > 0 then
        playerShakeTimer = playerShakeTimer - elapsed
        local mag = math.min(6, playerShakeTimer * 18)
        shakeX = (math.random() * 2 - 1) * mag
        shakeY = (math.random() * 2 - 1) * mag
    else
        shakeX, shakeY = 0, 0
    end
end

-- ── Level-up flash ────────────────────────────────────────────────────────────

local levelFlash
local levelFlashTimer = 0
local levelFlashLabel

local function BuildLevelFlash(parent)
    levelFlash = parent:CreateTexture(nil, "OVERLAY")
    levelFlash:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0)
    levelFlash:SetAllPoints(parent)
    levelFlash:SetDrawLayer("OVERLAY", 6)

    levelFlashLabel = parent:CreateFontString(nil, "OVERLAY")
    levelFlashLabel:SetFont("Fonts\\FRIZQT__.TTF", 44, "THICKOUTLINE")
    levelFlashLabel:SetTextColor(C.fel.r, C.fel.g, C.fel.b, 0)
    levelFlashLabel:SetPoint("CENTER", parent, "CENTER", 0, 20)
    levelFlashLabel:SetText("LEVEL UP!")
end

function UI.TriggerLevelFlash()
    levelFlashTimer = 0.7
    PlaySound(888, "SFX")
end

local function UpdateLevelFlash(elapsed)
    if levelFlashTimer > 0 then
        levelFlashTimer = levelFlashTimer - elapsed
        local t     = levelFlashTimer / 0.7
        local alpha = t * (1 - t) * 4  -- peaks in middle
        levelFlash:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, alpha * 0.55)
        levelFlashLabel:SetTextColor(1, 1, 1, alpha)
    else
        levelFlash:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0)
        levelFlashLabel:SetTextColor(1, 1, 1, 0)
    end
end

-- ── HP bar flash ──────────────────────────────────────────────────────────────

local hpFlashTimer = 0

function UI.TriggerHpFlash()
    hpFlashTimer = 0.4
    PlaySound(569, "SFX")
end

-- ── Main menu ────────────────────────────────────────────────────────────────

local menuFrame

local function BuildMenu()
    if menuFrame then return end

    menuFrame = CreateFrame("Frame", "WicksSurvivorsMenu", UIParent)
    menuFrame:SetSize(380, 380)
    menuFrame:SetPoint("CENTER")
    menuFrame:SetFrameStrata("HIGH")
    menuFrame:Hide()
    WS.Skin.Panel(menuFrame, 380, 380)

    -- header strip
    local header = CreateFrame("Frame", nil, menuFrame)
    header:SetSize(380, 42)
    header:SetPoint("TOPLEFT")
    WS.Skin.Header(header)
    local title = MakeText(header, 18, C.text, "CENTER")
    title:SetPoint("CENTER")
    title:SetText("Wick's Survivors")

    -- orb icon in the panel body
    local orbFrame = CreateFrame("Frame", nil, menuFrame)
    orbFrame:SetSize(64, 64)
    orbFrame:SetPoint("TOP", header, "BOTTOM", 0, -18)
    local orbGlow = orbFrame:CreateTexture(nil, "BACKGROUND")
    orbGlow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
    orbGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.55)
    orbGlow:SetSize(96, 96)
    orbGlow:SetPoint("CENTER")
    local orbTex = orbFrame:CreateTexture(nil, "ARTWORK")
    orbTex:SetTexture(WS.TEX.proj_orb)
    orbTex:SetSize(48, 48)
    orbTex:SetPoint("CENTER")
    -- animate the orb
    orbFrame:SetScript("OnUpdate", function()
        local n, fps = 8, 14
        local idx = math.floor(GetTime() * fps) % n
        local l = idx / n
        orbTex:SetTexCoord(l, l + 1/n, 0, 1)
        local pulse = 0.4 + math.sin(GetTime() * 2.5) * 0.15
        orbGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, pulse)
    end)

    -- subtext
    local sub = MakeText(menuFrame, 10, C.text, "CENTER")
    sub:SetPoint("TOP", orbFrame, "BOTTOM", 0, -10)
    sub:SetText("Move your mouse to move.  |cffee3333Kill|r everything.  ESC to flee.")

    -- stat rows: label LEFT, value RIGHT in fel-green
    local statBox = CreateFrame("Frame", nil, menuFrame)
    statBox:SetSize(310, 100)
    statBox:SetPoint("TOP", sub, "BOTTOM", 0, -14)
    WS.Skin.Trough(statBox)

    local function StatRow(parent, label, yOff)
        local lbl = MakeText(parent, 13, C.text, "LEFT")
        lbl:SetPoint("TOPLEFT",  parent, "TOPLEFT",  14, yOff)
        lbl:SetText(label)
        local val = MakeText(parent, 13, C.fel, "RIGHT")
        val:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, yOff)
        return val
    end
    menuFrame.hs = StatRow(statBox, "High Score", -12)
    menuFrame.bw = StatRow(statBox, "Best Wave",  -42)
    menuFrame.tr = StatRow(statBox, "Total Runs", -72)

    -- buttons
    local playBtn = CreateFrame("Button", nil, menuFrame)
    playBtn:SetSize(200, 40)
    playBtn:SetPoint("BOTTOM", menuFrame, "BOTTOM", 0, 60)
    WS.Skin.Button(playBtn, true, 200, 40)
    local pLabel = MakeText(playBtn, 15, {r=0.031,g=0.075,b=0.047}, "CENTER")
    pLabel:SetPoint("CENTER")
    pLabel:SetText("PLAY")
    playBtn:SetScript("OnClick", function()
        menuFrame:Hide()
        WS.Game.Start()
    end)

    local closeBtn = CreateFrame("Button", nil, menuFrame)
    closeBtn:SetSize(110, 30)
    closeBtn:SetPoint("BOTTOM", menuFrame, "BOTTOM", 0, 22)
    WS.Skin.Button(closeBtn, false, 110, 30)
    local cLabel = MakeText(closeBtn, 13, C.text, "CENTER")
    cLabel:SetPoint("CENTER")
    cLabel:SetText("Close")
    closeBtn:SetScript("OnClick", function() menuFrame:Hide() end)
end

function UI.ToggleMenu()
    BuildMenu()
    if menuFrame:IsShown() then
        menuFrame:Hide()
    else
        menuFrame.hs:SetText(WS.db.highScore or 0)
        menuFrame.bw:SetText(WS.db.bestWave  or 0)
        menuFrame.tr:SetText(WS.db.totalRuns or 0)
        menuFrame:Show()
    end
end

-- ── HUD ──────────────────────────────────────────────────────────────────────

local hudFrame
local hpBar, hpBarFill, xpBar, xpBarFill
local hudScore, hudWave, hudTime, hudLevel
local waveAlert
local auraRingFrame
local scorePopup, scorePopupTimer = nil, 0
local lastScore = 0

local function BuildHUD(parent)
    if hudFrame then return end

    -- HUD is a sibling of the arena anchored to it, NOT a child that fills it.
    -- This prevents the strip frames from visually slicing the gameplay area.
    hudFrame = CreateFrame("Frame", nil, UIParent)
    hudFrame:SetSize(WS.ARENA_W, WS.ARENA_H)
    hudFrame:SetPoint("CENTER")
    hudFrame:SetFrameStrata("FULLSCREEN")
    hudFrame:SetFrameLevel(200)   -- above arena (100) but below dialogs
    hudFrame:Hide()

    -- ── Top info strip ───────────────────────────────────────────────────────
    local topStrip = CreateFrame("Frame", nil, hudFrame)
    topStrip:SetSize(WS.ARENA_W, 32)
    topStrip:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 0, 0)
    WS.Skin.Header(topStrip)

    local exitBtn = CreateFrame("Button", nil, topStrip)
    exitBtn:SetSize(28, 28)
    exitBtn:SetPoint("RIGHT", topStrip, "RIGHT", -2, 0)
    WS.Skin.Button(exitBtn, false, 28, 28)
    local eLabel = MakeText(exitBtn, 13, C.text, "CENTER")
    eLabel:SetPoint("CENTER")
    eLabel:SetText("x")
    exitBtn:SetScript("OnEnter", function() eLabel:SetTextColor(C.red.r, C.red.g, C.red.b) end)
    exitBtn:SetScript("OnLeave", function() eLabel:SetTextColor(C.text.r, C.text.g, C.text.b) end)
    exitBtn:SetScript("OnClick", function() WS.Game.Quit() end)

    hudWave = MakeText(topStrip, 13, C.fel, "LEFT")
    hudWave:SetPoint("LEFT", topStrip, "LEFT", 10, 0)
    hudWave:SetText("Wave 0")

    hudScore = MakeText(topStrip, 13, C.text, "CENTER")
    hudScore:SetPoint("CENTER", topStrip, "CENTER", 0, 0)
    hudScore:SetText("Score: 0")

    hudTime = MakeText(topStrip, 13, C.text, "RIGHT")
    hudTime:SetPoint("RIGHT", exitBtn, "LEFT", -8, 0)
    hudTime:SetText("0:00")

    -- ── HP bar (overlaid on top edge of arena, below strip) ──────────────────
    hpBar = CreateFrame("Frame", nil, hudFrame)
    hpBar:SetSize(WS.ARENA_W, 14)
    hpBar:SetPoint("TOPLEFT", topStrip, "BOTTOMLEFT", 0, 0)
    WS.Skin.Trough(hpBar)
    hpBarFill = hpBar:CreateTexture(nil, "ARTWORK")
    hpBarFill:SetColorTexture(0.247, 0.561, 0.298, 1)
    hpBarFill:SetPoint("LEFT", hpBar, "LEFT", 0, 0)
    hpBarFill:SetHeight(14)
    hpBarFill:SetWidth(0)
    WS.Skin.Gloss(hpBar)
    WS.Skin.Segments(hpBar, WS.ARENA_W)
    local hpLabel = MakeText(hpBar, 8, C.text, "CENTER")
    hpLabel:SetPoint("CENTER")
    hudFrame.hpLabel = hpLabel

    hpBar.shimmer = hpBar:CreateTexture(nil, "OVERLAY")
    hpBar.shimmer:SetColorTexture(1, 1, 1, 0)
    hpBar.shimmer:SetAllPoints(hpBar)

    -- ── XP bar (slim, below HP bar) ──────────────────────────────────────────
    xpBar = CreateFrame("Frame", nil, hudFrame)
    xpBar:SetSize(WS.ARENA_W, 5)
    xpBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    WS.Skin.Trough(xpBar)
    xpBarFill = xpBar:CreateTexture(nil, "ARTWORK")
    xpBarFill:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
    xpBarFill:SetPoint("LEFT", xpBar, "LEFT", 0, 0)
    xpBarFill:SetHeight(5)
    xpBarFill:SetWidth(0)

    -- level label — bottom left, below XP bar
    hudLevel = MakeText(hudFrame, 13, C.yellow, "LEFT")
    hudLevel:SetPoint("TOPLEFT", xpBar, "BOTTOMLEFT", 4, -2)
    hudLevel:SetText("Lv 1")

    -- floating score delta
    scorePopup = hudFrame:CreateFontString(nil, "OVERLAY")
    scorePopup:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
    scorePopup:SetTextColor(C.fel.r, C.fel.g, C.fel.b, 0)
    scorePopup:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -8, -30)

    -- wave alert — sits in the upper third of the play field (below HUD strips)
    waveAlert = CreateFrame("Frame", nil, hudFrame)
    waveAlert:SetSize(WS.ARENA_W, 60)
    waveAlert:SetPoint("TOP", xpBar, "BOTTOM", 0, -math.floor(WS.ARENA_H * 0.22))
    waveAlert:Hide()
    local waBg = MakeTex(waveAlert, "BACKGROUND", C.shadow, 0.92)
    waBg:SetAllPoints(waveAlert)
    local waLeft = MakeTex(waveAlert, "BORDER", C.fel, 1)
    waLeft:SetSize(3, 60); waLeft:SetPoint("LEFT")
    local waRight = MakeTex(waveAlert, "BORDER", C.fel, 1)
    waRight:SetSize(3, 60); waRight:SetPoint("RIGHT")
    waveAlert.waBg = waBg
    waveAlert.text = MakeText(waveAlert, 26, C.fel, "CENTER")
    waveAlert.text:SetPoint("CENTER", waveAlert, "CENTER", 0, 6)
    waveAlert.sub  = MakeText(waveAlert, 13, C.text, "CENTER")
    waveAlert.sub:SetPoint("BOTTOM", waveAlert, "BOTTOM", 0, 8)
    waveAlert.timer = 0

    -- aura ring overlay — soft radial glow using glow.tga
    -- Outer glow disc (large, low alpha) + inner bright ring edge (smaller, higher alpha)
    local GLOW = "Interface\\AddOns\\WicksSurvivors\\Art\\glow"
    auraRingFrame = CreateFrame("Frame", nil, UIParent)
    auraRingFrame:SetFrameStrata("FULLSCREEN")
    auraRingFrame:SetFrameLevel(102)
    auraRingFrame:Hide()
    auraRingFrame:SetSize(200, 200)
    -- outer soft glow disc — fills the whole frame, fades to transparent at edges
    local outerGlow = auraRingFrame:CreateTexture(nil, "ARTWORK")
    outerGlow:SetTexture(GLOW)
    outerGlow:SetAllPoints(auraRingFrame)
    outerGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.18)
    -- ring edge: a second glow at ~85% size, higher alpha — creates bright rim effect
    local ringEdge = auraRingFrame:CreateTexture(nil, "ARTWORK")
    ringEdge:SetTexture(GLOW)
    ringEdge:SetPoint("CENTER", auraRingFrame, "CENTER")
    ringEdge:SetSize(1, 1)  -- sized dynamically in update
    ringEdge:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.55)
    auraRingFrame.ringEdge = ringEdge
    auraRingFrame.outerGlow = outerGlow
end

function UI.OnWave(wave)
    if not waveAlert then return end
    PlaySound(3337, "SFX")
    waveAlert.text:SetText("Wave " .. wave)
    waveAlert.text:SetAlpha(1)
    if wave == 1 then
        waveAlert.sub:SetText("Survive!")
    elseif wave % WS.BOSS_EVERY == 0 then
        local bossIdx = ((wave / WS.BOSS_EVERY - 1) % #WS.BOSS_TYPES) + 1
        local bossName = WS.BOSS_TYPES[bossIdx] and WS.BOSS_TYPES[bossIdx].name or "???"
        waveAlert.sub:SetText("BOSS: " .. bossName)
        waveAlert.text:SetTextColor(WS.C.red.r, WS.C.red.g, WS.C.red.b, 1)
    else
        waveAlert.text:SetTextColor(WS.C.fel.r, WS.C.fel.g, WS.C.fel.b, 1)
        waveAlert.sub:SetText("The dead keep coming...")
    end
    waveAlert.sub:SetAlpha(1)
    waveAlert.waBg:SetColorTexture(C.shadow.r, C.shadow.g, C.shadow.b, 0.88)
    waveAlert:Show()
    waveAlert.timer = 2.5
    waveAlert:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer - elapsed
        local alpha = math.max(0, math.min(1, self.timer / 0.6))
        self.text:SetAlpha(alpha)
        self.sub:SetAlpha(alpha * 0.8)
        self.waBg:SetColorTexture(C.shadow.r, C.shadow.g, C.shadow.b, 0.88 * alpha)
        if self.timer <= 0 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ── Arena ─────────────────────────────────────────────────────────────────────

local arenaFrame
local playerDot
local playerTex
local playerGlow
local playerAngle      = 0
local activeEnemyFrames  = {}
local activeProjFrames   = {}
local activePickupFrames = {}

local function BuildArena()
    if arenaFrame then return end

    arenaFrame = CreateFrame("Frame", "WicksSurvivorsArena", UIParent)
    arenaFrame:SetSize(WS.ARENA_W, WS.ARENA_H)
    arenaFrame:SetPoint("CENTER")
    arenaFrame:SetFrameStrata("FULLSCREEN")
    arenaFrame:SetFrameLevel(100)
    arenaFrame:Hide()
    arenaFrame:EnableKeyboard(true)
    arenaFrame:SetPropagateKeyboardInput(true)
    arenaFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and WS.Game.gs and WS.Game.gs.running then
            WS.Game.Quit()
        end
    end)

    -- solid opaque background — use a child frame with a texture so it truly
    -- occludes everything behind the arena (plain textures on arenaFrame itself
    -- don't block child-frame transparency bleeding)
    local bgFrame = CreateFrame("Frame", nil, arenaFrame)
    bgFrame:SetAllPoints(arenaFrame)
    bgFrame:SetFrameLevel(arenaFrame:GetFrameLevel())
    local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetColorTexture(0.055, 0.043, 0.090, 1)
    bgTex:SetAllPoints(bgFrame)

    -- small dim center lift (glow.tga radial, 60% of arena size)
    local floorGlow = bgFrame:CreateTexture(nil, "ARTWORK")
    floorGlow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
    floorGlow:SetVertexColor(0.13, 0.10, 0.22, 0.45)
    floorGlow:SetSize(WS.ARENA_W * 0.6, WS.ARENA_H * 0.6)
    floorGlow:SetPoint("CENTER", arenaFrame, "CENTER")

    -- 1px border inset on the arena edge
    local borderTex = bgFrame:CreateTexture(nil, "BORDER")
    borderTex:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
    borderTex:SetPoint("TOPLEFT",     arenaFrame, "TOPLEFT",      0, 0)
    borderTex:SetPoint("BOTTOMRIGHT", arenaFrame, "BOTTOMRIGHT",  0, 0)

    -- dot grid on a dedicated sub-frame so it renders above the background
    local gridFrame = CreateFrame("Frame", nil, arenaFrame)
    gridFrame:SetAllPoints(arenaFrame)
    gridFrame:SetFrameLevel(arenaFrame:GetFrameLevel() + 1)
    for gx = 0, math.floor(WS.ARENA_W / 34) do
        for gy = 0, math.floor(WS.ARENA_H / 34) do
            local dot = gridFrame:CreateTexture(nil, "ARTWORK")
            dot:SetColorTexture(0.471, 0.392, 0.667, 0.18)  -- rgba(120,100,170,.18) exact design
            dot:SetSize(2, 2)
            dot:SetPoint("TOPLEFT", arenaFrame, "TOPLEFT", gx * 34, -(gy * 34))
        end
    end

    -- smooth vignette: 2px bands across 140px, quadratic falloff.
    -- 2px per band = 70 steps — imperceptible stepping at any display scale.
    local VIG = 140
    local BSIZE = 2
    local N = math.floor(VIG / BSIZE)
    local function vstrip(anchor, horiz)
        for b = 0, N - 1 do
            local t = 1 - b / N          -- 1 at wall, 0 at inner edge
            local a = 0.72 * t * t       -- quadratic: heavy at wall, smooth falloff
            local off = b * BSIZE
            local vt = gridFrame:CreateTexture(nil, "OVERLAY")
            vt:SetColorTexture(0, 0, 0, a)
            if horiz then
                vt:SetHeight(BSIZE + 1)
                vt:SetPoint("LEFT",  arenaFrame, "LEFT")
                vt:SetPoint("RIGHT", arenaFrame, "RIGHT")
                if anchor == "TOP" then
                    vt:SetPoint("TOP", arenaFrame, "TOP", 0, -off)
                else
                    vt:SetPoint("BOTTOM", arenaFrame, "BOTTOM", 0, off)
                end
            else
                vt:SetWidth(BSIZE + 1)
                vt:SetPoint("TOP",    arenaFrame, "TOP")
                vt:SetPoint("BOTTOM", arenaFrame, "BOTTOM")
                if anchor == "LEFT" then
                    vt:SetPoint("LEFT", arenaFrame, "LEFT", off, 0)
                else
                    vt:SetPoint("RIGHT", arenaFrame, "RIGHT", -off, 0)
                end
            end
        end
    end
    vstrip("TOP", true); vstrip("BOTTOM", true)
    vstrip("LEFT", false); vstrip("RIGHT", false)

    AddCornerAccents(arenaFrame)

    POOL_PARENT = arenaFrame
    BuildHitFlash(arenaFrame)
    BuildLevelFlash(arenaFrame)

    -- player frame
    playerDot = CreateFrame("Frame", nil, arenaFrame)
    playerDot:SetSize(40, 40)
    playerDot:SetFrameLevel(arenaFrame:GetFrameLevel() + 6)

    -- outer glow (large soft radial)
    playerGlow = playerDot:CreateTexture(nil, "BACKGROUND")
    playerGlow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
    playerGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.55)
    playerGlow:SetSize(72, 72)
    playerGlow:SetPoint("CENTER")

    -- mid glow
    local midGlow = playerDot:CreateTexture(nil, "BACKGROUND")
    midGlow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
    midGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, 0.30)
    midGlow:SetSize(50, 50)
    midGlow:SetPoint("CENTER")

    playerTex = playerDot:CreateTexture(nil, "ARTWORK")
    playerTex:SetTexture(WS.TEX.player)
    playerTex:SetAllPoints(playerDot)

    BuildHUD(arenaFrame)
    BuildComboLabel(arenaFrame)
end

local function ArenaToFrame(x, y)
    return x, -y
end

-- ── Entity rendering ──────────────────────────────────────────────────────────

local PROJ_TEX  = {orb="proj_orb", bolt="proj_bolt", nova="proj_nova", chain="proj_chain", aura="proj_aura", boss_nova="proj_nova"}
local PROJ_SIZE = {orb=26, bolt=19, nova=16, chain=22, aura=19, boss_nova=22}

local function RenderEnemies(enemies, elapsed)
    while #activeEnemyFrames > #enemies do
        ReleaseFrame(enemyPool, table.remove(activeEnemyFrames))
    end
    while #activeEnemyFrames < #enemies do
        local f = AcquireFrame(enemyPool, arenaFrame, 24)
        f:SetFrameLevel(arenaFrame:GetFrameLevel() + 3)
        if not f.hpBar then
            f.hpBar = f:CreateTexture(nil, "OVERLAY")
            f.hpBar:SetHeight(3)
            f.hpBar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 3)
        end
        if not f.shadow then
            -- shadow on a sub-frame one level below so it renders behind the icon
            local sf = CreateFrame("Frame", nil, f)
            sf:SetFrameLevel(f:GetFrameLevel() - 1)
            sf:SetAllPoints(f)
            f.shadow = sf:CreateTexture(nil, "BACKGROUND")
            f.shadow:SetColorTexture(0, 0, 0, 0.5)
        end
        if not f.glow then
            local gf = CreateFrame("Frame", nil, f)
            gf:SetFrameLevel(f:GetFrameLevel() - 1)
            gf:SetAllPoints(f)
            f.glow = gf:CreateTexture(nil, "ARTWORK")
            f.glow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
            f.glow:Hide()
        end
        f.lastTex   = nil
        f.wobble    = math.random() * math.pi * 2
        f.animPhase = math.random()
        activeEnemyFrames[#activeEnemyFrames + 1] = f
    end

    for i, e in ipairs(enemies) do
        local f   = activeEnemyFrames[i]
        local sz  = e.template.size
        local tex = WS.TEX[e.template.tex]

        -- subtle wobble scale
        f.wobble = (f.wobble or 0) + elapsed * 3
        local wobbleScale = 1 + math.sin(f.wobble) * 0.04
        local dsz = math.floor(sz * wobbleScale)

        f:SetSize(dsz, dsz)
        f:SetPoint("TOPLEFT", arenaFrame, "TOPLEFT", ArenaToFrame(e.x - dsz/2, e.y - dsz/2))

        f.shadow:SetSize(dsz * 0.75, dsz * 0.22)
        f.shadow:SetPoint("BOTTOM", f, "BOTTOM", 2, -3)

        if f.lastTex ~= tex then
            f.bg:SetTexture(tex)
            f.lastTex = tex
        end
        WS.SetAnimFrame(f.bg, e.template.tex, f.animPhase)

        if e.flashTimer > 0 then
            f.bg:SetVertexColor(1, 1, 1, 1)
            local t = e.template
            f.glow:SetVertexColor(t.deathR or 1, t.deathG or 0.5, t.deathB or 0.2, 0.7)
            f.glow:SetSize(dsz + 20, dsz + 20)
            f.glow:SetPoint("CENTER", f, "CENTER")
            f.glow:Show()
        else
            f.bg:SetVertexColor(1, 1, 1, 0.95)
            f.glow:Hide()
        end

        local hpPct = math.max(0, e.hp / e.maxHp)
        local hr, hg, hb = HpColor(hpPct)
        f.hpBar:SetColorTexture(hr, hg, hb, 1)
        f.hpBar:SetWidth(math.max(1, dsz * hpPct))
    end
end

local function RenderProjectiles(projs)
    while #activeProjFrames > #projs do
        ReleaseFrame(projPool, table.remove(activeProjFrames))
    end
    while #activeProjFrames < #projs do
        local f = AcquireFrame(projPool, arenaFrame, 16)
        f:SetFrameLevel(arenaFrame:GetFrameLevel() + 4)
        if not f.glow then
            f.glow = f:CreateTexture(nil, "BACKGROUND")
            f.glow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
        end
        f.lastTex = nil
        activeProjFrames[#activeProjFrames + 1] = f
    end

    for i, p in ipairs(projs) do
        local f   = activeProjFrames[i]
        local sz  = PROJ_SIZE[p.weaponId] or 16
        local tex = WS.TEX[PROJ_TEX[p.weaponId] or "proj_bolt"]
        f:SetSize(sz, sz)
        f:SetPoint("TOPLEFT", arenaFrame, "TOPLEFT", ArenaToFrame(p.x - sz/2, p.y - sz/2))
        if f.lastTex ~= tex then
            f.bg:SetTexture(tex)
            f.lastTex = tex
        end
        if p.vx and p.vy and (p.vx ~= 0 or p.vy ~= 0) and not p.orbRef then
            f.bg:SetRotation(math.atan2(p.vy, p.vx))
        else
            f.bg:SetRotation(0)
        end
        f.bg:SetVertexColor(1, 1, 1, 0.95)
        WS.SetAnimFrame(f.bg, PROJ_TEX[p.weaponId] or "proj_bolt", 0)

        -- glow behind projectile
        local col = TRAIL_COLORS[p.weaponId] or {1, 1, 1}
        f.glow:SetSize(sz + 16, sz + 16)
        f.glow:SetPoint("CENTER", f, "CENTER")
        f.glow:SetVertexColor(col[1], col[2], col[3], 0.5)
    end
end

local pickupPulseTime = 0

local function RenderPickups(pickups, elapsed)
    pickupPulseTime = pickupPulseTime + elapsed
    local pulse = 1 + math.sin(pickupPulseTime * 5) * 0.18

    while #activePickupFrames > #pickups do
        ReleaseFrame(pickupPool, table.remove(activePickupFrames))
    end
    while #activePickupFrames < #pickups do
        local f = AcquireFrame(pickupPool, arenaFrame, 16)
        f:SetFrameLevel(arenaFrame:GetFrameLevel() + 2)
        if not f.glow then
            f.glow = f:CreateTexture(nil, "BACKGROUND")
            f.glow:SetTexture("Interface\\AddOns\\WicksSurvivors\\Art\\glow")
        end
        if not f.ring then
            f.ring = f:CreateTexture(nil, "ARTWORK")
            f.ring:SetColorTexture(1, 1, 1, 0)
        end
        f.lastTex = nil
        activePickupFrames[#activePickupFrames + 1] = f
    end

    for i, pk in ipairs(pickups) do
        local f      = activePickupFrames[i]
        local tex    = pk.kind == "hp" and WS.TEX.pickup_hp or WS.TEX.pickup_xp
        local baseSz = pk.kind == "hp" and 20 or 16
        local sz     = math.floor(baseSz * pulse)
        f:SetSize(sz, sz)
        f:SetPoint("TOPLEFT", arenaFrame, "TOPLEFT", ArenaToFrame(pk.x - sz/2, pk.y - sz/2))
        if f.lastTex ~= tex then
            f.bg:SetTexture(tex)
            f.lastTex = tex
        end

        -- pulsing glow
        local glowAlpha = 0.28 + math.sin(pickupPulseTime * 5) * 0.12
        f.glow:SetSize(sz + 16, sz + 16)
        f.glow:SetPoint("CENTER", f, "CENTER")
        if pk.kind == "hp" then
            f.bg:SetVertexColor(1, 0.55, 0.55, 1)
            f.glow:SetVertexColor(0.9, 0.15, 0.15, glowAlpha)
        else
            f.bg:SetVertexColor(0.65, 1, 0.65, 1)
            f.glow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, glowAlpha)
        end
    end
end

-- ── Level-up panel ────────────────────────────────────────────────────────────

local levelUpFrame
local choiceButtons = {}

local function BuildLevelUp()
    if levelUpFrame then return end

    levelUpFrame = CreateFrame("Frame", nil, arenaFrame)
    levelUpFrame:SetSize(440, 230)
    levelUpFrame:SetPoint("CENTER")
    levelUpFrame:SetFrameLevel(arenaFrame:GetFrameLevel() + 20)
    levelUpFrame:Hide()

    WS.Skin.Panel(levelUpFrame, 440, 230)

    local header = CreateFrame("Frame", nil, levelUpFrame)
    header:SetSize(440, 40)
    header:SetPoint("TOPLEFT")
    WS.Skin.Header(header)
    local title = MakeText(header, 16, C.text, "CENTER")
    title:SetPoint("CENTER")
    title:SetText("Level Up!  Choose an upgrade.")

    for i = 1, 3 do
        local btn = CreateFrame("Button", nil, levelUpFrame)
        btn:SetSize(128, 130)
        btn:SetPoint("TOPLEFT", levelUpFrame, "TOPLEFT", 8 + (i-1) * 141, -50)

        WS.Skin.Card(btn, 128, 130)

        local iconBg = btn:CreateTexture(nil, "ARTWORK")
        iconBg:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
        iconBg:SetSize(44, 44)
        iconBg:SetPoint("TOP", btn, "TOP", 0, -8)

        -- hover tint overlay (sits above panel BACKGROUND, below icon ARTWORK)
        local bbg = btn:CreateTexture(nil, "BORDER")
        bbg:SetColorTexture(0, 0, 0, 0)
        bbg:SetAllPoints(btn)
        local bborder = btn:CreateTexture(nil, "BORDER")
        bborder:SetColorTexture(0, 0, 0, 0)
        bborder:SetAllPoints(btn)

        btn.iconGlow = btn:CreateTexture(nil, "ARTWORK")
        btn.iconGlow:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0)
        btn.iconGlow:SetSize(56, 56)
        btn.iconGlow:SetPoint("CENTER", iconBg, "CENTER")

        btn.iconTex = btn:CreateTexture(nil, "OVERLAY")
        btn.iconTex:SetSize(40, 40)
        btn.iconTex:SetPoint("CENTER", iconBg, "CENTER")

        btn.nameLabel = MakeText(btn, 13, C.fel, "CENTER")
        btn.nameLabel:SetPoint("TOP", iconBg, "BOTTOM", 0, -5)
        btn.nameLabel:SetWidth(120)

        btn.descLabel = MakeText(btn, 9, C.text, "CENTER")
        btn.descLabel:SetPoint("TOP", btn.nameLabel, "BOTTOM", 0, -4)
        btn.descLabel:SetWidth(120)
        btn.descLabel:SetWordWrap(true)

        btn.typeLabel = MakeText(btn, 9, C.arc, "CENTER")
        btn.typeLabel:SetPoint("BOTTOM", btn, "BOTTOM", 0, 8)

        btn:SetScript("OnEnter", function(self)
            bbg:SetColorTexture(C.purple.r * 0.4, C.purple.g * 0.4, C.purple.b * 0.4, 0.55)
            bborder:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0.8)
            btn.iconGlow:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0.35)
        end)
        btn:SetScript("OnLeave", function(self)
            bbg:SetColorTexture(0, 0, 0, 0)
            bborder:SetColorTexture(0, 0, 0, 0)
            btn.iconGlow:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 0)
        end)
        btn:SetScript("OnClick", function(self)
            levelUpFrame:Hide()
            WS.Game.ApplyChoice(self.choice)
        end)

        choiceButtons[i] = btn
    end
end

function UI.ShowLevelUp()
    BuildLevelUp()
    UI.TriggerLevelFlash()

    local gs = WS.Game.gs

    local function Shuffle(t)
        for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    end

    -- build weapon pool: unowned weapons + upgrades for owned weapons (max lv5)
    local weaponPool = {}
    for _, tmpl in ipairs(WS.WEAPONS) do
        local hasIt, lvl = false, 0
        for _, w in ipairs(gs.weapons) do
            if w.template.id == tmpl.id then hasIt = true; lvl = w.level; break end
        end
        if not hasIt or lvl < 5 then
            weaponPool[#weaponPool + 1] = {
                id=tmpl.id, name=tmpl.name..(hasIt and (" Lv"..(lvl+1)) or ""),
                desc=tmpl.desc, icon=tmpl.icon, passive=false,
                baseDmg=tmpl.baseDmg, cooldown=tmpl.cooldown,
                projSpeed=tmpl.projSpeed, pierce=tmpl.pierce,
                aoe=tmpl.aoe, range=tmpl.range,
            }
        end
    end

    -- build passive pool: exclude already-taken passives (except regen/hp which stack)
    local takenPassives = {}
    for _, id in ipairs(gs.passives or {}) do
        if id ~= "regen" and id ~= "hp" then
            takenPassives[id] = true
        end
    end
    local passivePool = {}
    for _, p in ipairs(WS.PASSIVES) do
        if not takenPassives[p.id] then
            passivePool[#passivePool + 1] = {
                id=p.id, name=p.name, desc=p.desc, icon=p.icon, passive=true, effect=p.effect,
            }
        end
    end
    -- if all passives taken, re-allow stackable ones
    if #passivePool == 0 then
        for _, p in ipairs(WS.PASSIVES) do
            passivePool[#passivePool + 1] = {
                id=p.id, name=p.name, desc=p.desc, icon=p.icon, passive=true, effect=p.effect,
            }
        end
    end

    Shuffle(weaponPool)
    Shuffle(passivePool)

    -- pick 3: guarantee at least 1 passive and at most 2 weapons
    local choices = {}
    local maxWeapons = math.min(2, #weaponPool)
    for i = 1, maxWeapons do
        choices[#choices + 1] = weaponPool[i]
    end
    -- fill rest with passives
    local pi = 1
    while #choices < 3 and passivePool[pi] do
        choices[#choices + 1] = passivePool[pi]
        pi = pi + 1
    end
    -- last resort: duplicate a passive if somehow still short
    while #choices < 3 do
        choices[#choices + 1] = passivePool[math.random(#passivePool)]
    end

    -- shuffle final 3 so passive isn't always slot 3
    Shuffle(choices)

    for i = 1, 3 do
        local btn = choiceButtons[i]
        local ch  = choices[i]
        btn.choice = ch
        btn.iconTex:SetTexture(ch.icon and WS.TEX[ch.icon] or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.nameLabel:SetText(ch.name)
        btn.descLabel:SetText(ch.desc)
        if ch.passive then
            btn.typeLabel:SetText("Passive")
            btn.typeLabel:SetTextColor(C.arc.r, C.arc.g, C.arc.b)
        else
            btn.typeLabel:SetText("Weapon")
            btn.typeLabel:SetTextColor(C.ember.r, C.ember.g, C.ember.b)
        end
    end
    levelUpFrame:Show()
end

-- ── Game Over panel ───────────────────────────────────────────────────────────

local gameOverFrame

local function BuildGameOver()
    if gameOverFrame then return end

    gameOverFrame = CreateFrame("Frame", nil, UIParent)
    gameOverFrame:SetSize(320, 280)
    gameOverFrame:SetPoint("CENTER")
    gameOverFrame:SetFrameStrata("DIALOG")
    gameOverFrame:Hide()

    WS.Skin.Panel(gameOverFrame, 320, 280)

    local header = CreateFrame("Frame", nil, gameOverFrame)
    header:SetSize(320, 38)
    header:SetPoint("TOPLEFT")
    WS.Skin.Header(header, true)   -- danger=true → red accent line
    local title = MakeText(header, 20, C.red, "CENTER")
    title:SetPoint("CENTER")
    title:SetText("You Died")

    gameOverFrame.scoreText = MakeText(gameOverFrame, 17, C.fel, "CENTER")
    gameOverFrame.scoreText:SetPoint("TOP", header, "BOTTOM", 0, -20)
    gameOverFrame.waveText = MakeText(gameOverFrame, 12, C.text, "CENTER")
    gameOverFrame.waveText:SetPoint("TOP", gameOverFrame.scoreText, "BOTTOM", 0, -8)
    gameOverFrame.timeText = MakeText(gameOverFrame, 12, C.text, "CENTER")
    gameOverFrame.timeText:SetPoint("TOP", gameOverFrame.waveText, "BOTTOM", 0, -5)
    gameOverFrame.newHSText = MakeText(gameOverFrame, 14, C.ember, "CENTER")
    gameOverFrame.newHSText:SetPoint("TOP", gameOverFrame.timeText, "BOTTOM", 0, -12)

    local againBtn = CreateFrame("Button", nil, gameOverFrame)
    againBtn:SetSize(130, 34)
    againBtn:SetPoint("BOTTOM", gameOverFrame, "BOTTOM", -75, 22)
    WS.Skin.Button(againBtn, true, 130, 34)
    local aLabel = MakeText(againBtn, 13, {r=0.031,g=0.075,b=0.047}, "CENTER")
    aLabel:SetPoint("CENTER")
    aLabel:SetText("Play Again")
    againBtn:SetScript("OnClick", function()
        gameOverFrame:Hide()
        WS.Game.Start()
    end)

    local closeBtn = CreateFrame("Button", nil, gameOverFrame)
    closeBtn:SetSize(90, 34)
    closeBtn:SetPoint("BOTTOM", gameOverFrame, "BOTTOM", 65, 22)
    WS.Skin.Button(closeBtn, false, 90, 34)
    local cLabel = MakeText(closeBtn, 12, C.text, "CENTER")
    cLabel:SetPoint("CENTER")
    cLabel:SetText("Menu")
    closeBtn:SetScript("OnClick", function()
        gameOverFrame:Hide()
        arenaFrame:Hide()
        UI.ToggleMenu()
    end)
end

function UI.ShowGameOver(finalGs)
    BuildGameOver()
    BuildArena()
    arenaFrame:Hide()
    hudFrame:Hide()

    for i = #activeEnemyFrames,  1, -1 do ReleaseFrame(enemyPool,  table.remove(activeEnemyFrames))  end
    for i = #activeProjFrames,   1, -1 do ReleaseFrame(projPool,   table.remove(activeProjFrames))   end
    for i = #activePickupFrames, 1, -1 do ReleaseFrame(pickupPool, table.remove(activePickupFrames)) end
    for i = #particles,  1, -1 do ReleaseParticle(particles[i]);          table.remove(particles, i)  end
    for i = #rings,      1, -1 do rings[i]:Hide(); ringPool[#ringPool+1]=rings[i]; table.remove(rings,i) end
    for i = #dmgNumbers, 1, -1 do dmgNumbers[i].fs:Hide(); dmgNumberPool[#dmgNumberPool+1]=dmgNumbers[i]; table.remove(dmgNumbers,i) end
    comboCount = 0; comboTimer = 0

    local mins = math.floor(finalGs.time / 60)
    local secs = math.floor(finalGs.time % 60)
    gameOverFrame.scoreText:SetText("Score: " .. finalGs.score)
    gameOverFrame.waveText:SetText("Reached Wave " .. finalGs.wave)
    gameOverFrame.timeText:SetText(string.format("Survived %d:%02d", mins, secs))
    if finalGs.score >= (WS.db.highScore or 0) and finalGs.score > 0 then
        gameOverFrame.newHSText:SetText("NEW HIGH SCORE!")
        gameOverFrame.newHSText:Show()
    else
        gameOverFrame.newHSText:Hide()
    end
    gameOverFrame:Show()
end

-- ── Public kill notification (called by Game.lua) ─────────────────────────────

function UI.OnEnemyKilled(x, y, template)
    TriggerCombo(x, y)
    UI.SpawnShockwave(x, y, template.deathR or 0.6, template.deathG or 0.1, template.deathB or 0.8, template.size * 2.5)
    PlaySound(1391, "SFX")
end

-- ── Start / Render ────────────────────────────────────────────────────────────

function UI.GetArenaFrame()
    return arenaFrame
end

function UI.StartGame(gs)
    BuildArena()
    if levelUpFrame  then levelUpFrame:Hide()  end
    if gameOverFrame then gameOverFrame:Hide()  end
    hitFlashTimer    = 0
    playerShakeTimer = 0
    shakeX, shakeY   = 0, 0
    pickupPulseTime  = 0
    levelFlashTimer  = 0
    hpFlashTimer     = 0
    comboCount       = 0
    comboTimer       = 0
    lastScore        = 0
    playerAngle      = 0
    -- clear trail accumulators
    for k in pairs(projTrailAccum) do projTrailAccum[k] = nil end
    hudFrame:Show()
    arenaFrame:Show()
end

function UI.Render(gs, elapsed)
    elapsed = elapsed or 0

    -- effect updates
    UpdateParticles(elapsed)
    UpdateRings(elapsed)
    UpdateDmgNumbers(elapsed)
    UpdateHitFlash(elapsed)
    UpdateLevelFlash(elapsed)
    UpdateCombo(elapsed)
    UpdateTrails(gs.projectiles, elapsed)

    -- HP bar shimmer on heal
    if hpFlashTimer > 0 then
        hpFlashTimer = hpFlashTimer - elapsed
        local a = math.max(0, hpFlashTimer / 0.4) * 0.5
        hpBar.shimmer:SetColorTexture(0.3, 1, 0.4, a)
    elseif hpBar and hpBar.shimmer then
        hpBar.shimmer:SetColorTexture(0.3, 1, 0.4, 0)
    end

    -- player position + shake
    local sx, sy = shakeX, shakeY
    if playerDot then
        playerDot:SetPoint("TOPLEFT", arenaFrame, "TOPLEFT",
            ArenaToFrame(gs.px - 17 + sx, gs.py - 17 + sy))
    end

    -- player sprite: animate flipbook, flicker during iframes
    if playerTex then
        WS.SetAnimFrame(playerTex, "player", 0)
        if gs.iframes and gs.iframes > 0 then
            if math.sin(gs.iframes * 32) > 0 then
                playerTex:SetVertexColor(1, 0.3, 0.3, 1)
            else
                playerTex:SetVertexColor(1, 1, 1, 1)
            end
        else
            playerTex:SetVertexColor(1, 1, 1, 1)
        end
        playerTex:SetRotation(0)
    end

    -- player glow pulse
    if playerGlow then
        local pulse = 0.18 + math.sin(GetTime() * 3) * 0.06
        playerGlow:SetVertexColor(C.fel.r, C.fel.g, C.fel.b, pulse)
    end

    -- HP bar
    local hpPct = gs.hp / gs.maxHp
    local hr, hg, hb = HpColor(hpPct)
    hpBarFill:SetColorTexture(hr, hg, hb, 1)
    hpBarFill:SetWidth(math.max(0, WS.ARENA_W * hpPct))
    hudFrame.hpLabel:SetText(gs.hp .. " / " .. gs.maxHp)

    -- XP bar
    xpBarFill:SetWidth(math.max(0, WS.ARENA_W * gs.xp / gs.xpNext))
    hudLevel:SetText("Lv " .. gs.level)

    -- score (with popup delta)
    local delta = gs.score - lastScore
    if delta > 0 and scorePopup then
        lastScore  = gs.score
        scorePopupTimer = 1.2
        scorePopup:SetText("+" .. delta)
        scorePopup:SetAlpha(1)
    end
    if scorePopupTimer > 0 then
        scorePopupTimer = scorePopupTimer - elapsed
        scorePopup:SetAlpha(math.max(0, scorePopupTimer / 1.2))
    end

    hudScore:SetText("Score: " .. gs.score)
    hudWave:SetText("Wave " .. gs.wave)
    local mins = math.floor(gs.time / 60)
    local secs = math.floor(gs.time % 60)
    hudTime:SetText(string.format("%d:%02d", mins, secs))

    -- aura ring
    local hasAura = false
    for _, w in ipairs(gs.weapons) do
        if w.template.id == "aura" then
            hasAura = true
            local r = (w.template.range or 80) * (1 + (w.level-1)*0.15) * 2
            auraRingFrame:SetSize(r, r)
            if auraRingFrame.ringEdge then
                auraRingFrame.ringEdge:SetSize(r * 0.85, r * 0.85)
            end
            auraRingFrame:SetPoint("CENTER", arenaFrame, "TOPLEFT", gs.px, -gs.py)
            auraRingFrame:Show()
            break
        end
    end
    if not hasAura and auraRingFrame then auraRingFrame:Hide() end

    RenderEnemies(gs.enemies, elapsed)
    RenderProjectiles(gs.projectiles)
    RenderPickups(gs.pickups, elapsed)
end

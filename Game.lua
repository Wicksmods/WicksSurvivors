-- Wick's Survivors
-- Game.lua: simulation loop, enemy AI, projectile logic, collision

local ADDON, ns = ...
local WS = WicksSurvivors
WS.Game = {}
local G = WS.Game

-- ── State ──────────────────────────────────────────────────────────────────

local gs  -- game state, initialized in G.Start()

local function NewGameState()
    return {
        running      = false,
        paused       = false,
        time         = 0,           -- elapsed seconds
        wave         = 0,
        nextWaveTick = 0,
        score        = 0,

        -- player
        hp           = 150,
        maxHp        = 150,
        xp           = 0,
        level        = 1,
        xpNext       = WS.XP_TABLE[1],
        px           = WS.ARENA_W / 2,   -- player position (arena coords)
        py           = WS.ARENA_H / 2,
        moveSpeed    = 91,               -- px/sec
        dmgMult      = 1.0,
        cdMult       = 1.0,
        pickupRadius = WS.PICKUP_RADIUS,
        regenRate    = 0,
        regenAccum   = 0,
        iframes      = 0,                -- invincibility seconds after hit

        weapons      = {},               -- {template, level, cdAccum, orbAngle}
        passives     = {},

        -- entities
        enemies      = {},    -- {x, y, hp, maxHp, template, flashTimer}
        projectiles  = {},    -- {x, y, vx, vy, dmg, pierce, angle, weaponId, life}
        pickups      = {},    -- {x, y, kind, value}

        levelUpPending = false,
    }
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx*dx + dy*dy)
end

local function Norm(dx, dy)
    local d = math.sqrt(dx*dx + dy*dy)
    if d < 0.001 then return 0, 0 end
    return dx/d, dy/d
end

local function RandEdge()
    local side = math.random(4)
    if side == 1 then return math.random(0, WS.ARENA_W), -20 end
    if side == 2 then return math.random(0, WS.ARENA_W), WS.ARENA_H + 20 end
    if side == 3 then return -20,               math.random(0, WS.ARENA_H) end
    return WS.ARENA_W + 20, math.random(0, WS.ARENA_H)
end

local function ClampArena(x, y)
    return math.max(0, math.min(WS.ARENA_W, x)),
           math.max(0, math.min(WS.ARENA_H, y))
end

local function WeaponDmg(w)
    return math.floor(w.template.baseDmg * (1 + (w.level - 1) * 0.3) * gs.dmgMult)
end

local function DropPickups(e)
    gs.xp    = gs.xp + e.template.xp
    gs.score = gs.score + e.template.xp * 5
    gs.pickups[#gs.pickups + 1] = {x=e.x, y=e.y, kind="xp", value=e.template.xp}
    if e.template.dropHp then
        gs.pickups[#gs.pickups + 1] = {x=e.x + 8, y=e.y + 8, kind="hp", value=25}
    end
end

local function WeaponCD(w)
    return w.template.cooldown * gs.cdMult
end

-- ── Enemy spawning ───────────────────────────────────────────────────────────

local function SpawnEnemy(tmpl, wave)
    local hpScale  = 1 + (wave - 1) * 0.20
    local spdScale = 1 + (wave - 1) * 0.05
    local x, y = RandEdge()
    gs.enemies[#gs.enemies + 1] = {
        x           = x,
        y           = y,
        hp          = math.floor(tmpl.hp * hpScale),
        maxHp       = math.floor(tmpl.hp * hpScale),
        speed       = tmpl.speed * spdScale,
        template    = tmpl,
        flashTimer  = 0,
        specialAccum= 0,
    }
end

local function SpawnWave(wave)
    -- Boss wave: one boss + a handful of escorts at higher waves
    if wave % WS.BOSS_EVERY == 0 then
        local bossIdx  = ((wave / WS.BOSS_EVERY - 1) % #WS.BOSS_TYPES) + 1
        local bossTmpl = WS.BOSS_TYPES[bossIdx]

        -- bosses scale HP much more aggressively than normal enemies
        local bossHpScale  = 1 + (wave - 1) * 0.45
        local bossSpdScale = 1 + (wave - 1) * 0.06
        local x, y = RandEdge()
        gs.enemies[#gs.enemies + 1] = {
            x            = x,
            y            = y,
            hp           = math.floor(bossTmpl.hp * bossHpScale),
            maxHp        = math.floor(bossTmpl.hp * bossHpScale),
            speed        = bossTmpl.speed * bossSpdScale,
            -- special cooldown tightens with each cycle
            template     = setmetatable({
                specialCd = math.max(1.5, bossTmpl.specialCd - (wave / WS.BOSS_EVERY - 1) * 0.5),
            }, {__index = bossTmpl}),
            flashTimer   = 0,
            specialAccum = 0,
        }

        -- wave 10+ gets 3 escorts, wave 15+ gets 6
        local escortCount = math.floor((wave / WS.BOSS_EVERY - 1) * 3)
        escortCount = math.min(escortCount, 6)
        for i = 1, escortCount do
            if #gs.enemies < WS.MAX_ENEMIES then
                SpawnEnemy(WS.ENEMY_TYPES[math.min(#WS.ENEMY_TYPES, math.random(2, math.max(2, math.floor(wave/3))))], wave)
            end
        end
        return
    end
    local count   = math.min(WS.MAX_ENEMIES, 5 + wave * 3)
    local maxType = math.min(#WS.ENEMY_TYPES, 1 + math.floor(wave / 2))
    for i = 1, count do
        if #gs.enemies < WS.MAX_ENEMIES then
            SpawnEnemy(WS.ENEMY_TYPES[math.random(1, maxType)], wave)
        end
    end
end

-- ── Weapon firing ────────────────────────────────────────────────────────────

local function NearestEnemy()
    local best, bd = nil, math.huge
    for _, e in ipairs(gs.enemies) do
        local d = Dist(gs.px, gs.py, e.x, e.y)
        if d < bd then best, bd = e, d end
    end
    return best
end

local function FireOrb(w)
    -- orbiting: spawn projectile at current angle, it will be updated each tick
    w.orbAngle = (w.orbAngle or 0)
    local radius = 60 + (w.level - 1) * 10
    local px = gs.px + math.cos(w.orbAngle) * radius
    local py = gs.py + math.sin(w.orbAngle) * radius
    gs.projectiles[#gs.projectiles + 1] = {
        x        = px,
        y        = py,
        vx       = 0,
        vy       = 0,
        dmg      = WeaponDmg(w),
        pierce   = 99,
        weaponId = "orb",
        orbRef   = w,
        orbRadius= radius,
        life     = 99,
        hits     = {},
    }
end

local function FireBolt(w)
    local target = NearestEnemy()
    if not target then return end
    local dx, dy = Norm(target.x - gs.px, target.y - gs.py)
    gs.projectiles[#gs.projectiles + 1] = {
        x        = gs.px,
        y        = gs.py,
        vx       = dx * w.template.projSpeed,
        vy       = dy * w.template.projSpeed,
        dmg      = WeaponDmg(w),
        pierce   = w.level,
        weaponId = "bolt",
        life     = 2.5,
        hits     = {},
    }
end

local function FireNova(w)
    local count = 8 + (w.level - 1) * 2
    for i = 0, count - 1 do
        local angle = (2 * math.pi * i) / count
        local spd   = w.template.projSpeed
        gs.projectiles[#gs.projectiles + 1] = {
            x        = gs.px,
            y        = gs.py,
            vx       = math.cos(angle) * spd,
            vy       = math.sin(angle) * spd,
            dmg      = WeaponDmg(w),
            pierce   = 99,
            weaponId = "nova",
            life     = 1.8,
            hits     = {},
        }
    end
end

local function FireChain(w)
    -- instant: find nearest, then chain to next, etc.
    local chainCount = w.template.pierce + (w.level - 1)
    local hit = {}
    local source = {x = gs.px, y = gs.py}
    for _ = 1, chainCount do
        local best, bd = nil, math.huge
        for i, e in ipairs(gs.enemies) do
            if not hit[i] then
                local d = Dist(source.x, source.y, e.x, e.y)
                if d < bd then best, bd = e, i end
            end
        end
        if not best then break end
        hit[best] = true
        local dmg = WeaponDmg(w)
        best.hp = best.hp - dmg
        best.flashTimer = 0.15
        gs.score = gs.score + dmg
        WS.UI.SpawnDmgNumber(best.x, best.y, dmg, false)
        WS.UI.SpawnHitSpark(best.x, best.y, best.template.deathR or 1, best.template.deathG or 0.5, best.template.deathB or 0.2)
        if best.hp <= 0 then
            WS.UI.SpawnDeathBurst(best.x, best.y, best.template.deathR or 0.6, best.template.deathG or 0.1, best.template.deathB or 0.8)
            WS.UI.OnEnemyKilled(best.x, best.y, best.template)
            DropPickups(best)
        end
        source = {x = best.x, y = best.y}
    end
    -- remove dead
    for i = #gs.enemies, 1, -1 do
        if gs.enemies[i].hp <= 0 then table.remove(gs.enemies, i) end
    end
end

local function FireAura(w)
    local r = (w.template.range or 80) * (1 + (w.level-1)*0.15)
    local dmg = WeaponDmg(w)
    for i = #gs.enemies, 1, -1 do
        local e = gs.enemies[i]
        if Dist(gs.px, gs.py, e.x, e.y) <= r then
            e.hp = e.hp - dmg
            e.flashTimer = 0.1
            gs.score = gs.score + dmg
            WS.UI.SpawnDmgNumber(e.x, e.y, dmg, false)
            WS.UI.SpawnHitSpark(e.x, e.y, e.template.deathR or 1, e.template.deathG or 0.5, e.template.deathB or 0.2)
            if e.hp <= 0 then
                WS.UI.SpawnDeathBurst(e.x, e.y, e.template.deathR or 0.6, e.template.deathG or 0.1, e.template.deathB or 0.8)
                WS.UI.OnEnemyKilled(e.x, e.y, e.template)
                DropPickups(e)
                table.remove(gs.enemies, i)
            end
        end
    end
end

local FIRE = {
    orb   = FireOrb,
    bolt  = FireBolt,
    nova  = FireNova,
    chain = FireChain,
    aura  = FireAura,
}

-- ── Movement input ───────────────────────────────────────────────────────────

-- Player moves toward the mouse cursor. Returns direction vector.
local function GetMoveDir()
    local arena = WS.UI.GetArenaFrame()
    if not arena then return 0, 0 end
    local cx, cy = GetCursorPosition()
    local scale  = arena:GetEffectiveScale()
    local left   = arena:GetLeft()
    local top    = arena:GetTop()
    if not left then return 0, 0 end
    -- convert cursor (screen px) to arena coords
    local mx = (cx / scale) - left
    local my = top - (cy / scale)
    local dx = mx - gs.px
    local dy = my - gs.py
    -- dead zone: stop jittering when cursor is very close
    if math.abs(dx) < 6 and math.abs(dy) < 6 then return 0, 0 end
    return Norm(dx, dy)
end

-- ── Level-up ─────────────────────────────────────────────────────────────────

local function CheckLevelUp()
    while gs.xp >= gs.xpNext do
        gs.xp = gs.xp - gs.xpNext
        gs.level = gs.level + 1
        gs.xpNext = WS.XP_TABLE[math.min(gs.level, #WS.XP_TABLE)] or (gs.xpNext * 1.5)
        gs.levelUpPending = true
        gs.paused = true
        -- spawn XP burst at player position
        WS.UI.SpawnDeathBurst(gs.px, gs.py, WS.C.fel.r, WS.C.fel.g, WS.C.fel.b)
        WS.UI.ShowLevelUp()
    end
end

function G.ApplyChoice(choice)
    if choice.passive then
        choice.effect(gs)
        gs.passives[#gs.passives + 1] = choice.id
    else
        -- weapon: add new or upgrade existing
        local found = false
        for _, w in ipairs(gs.weapons) do
            if w.template.id == choice.id then
                w.level = w.level + 1
                found = true
                break
            end
        end
        if not found then
            gs.weapons[#gs.weapons + 1] = {
                template = choice,
                level    = 1,
                cdAccum  = 0,
                orbAngle = 0,
            }
            -- orb: fire once to create the orbiting projectile
            if choice.id == "orb" then
                FireOrb(gs.weapons[#gs.weapons])
            end
        end
    end
    gs.paused = false
    gs.levelUpPending = false
end

-- ── Main tick ────────────────────────────────────────────────────────────────

local updateFrame = CreateFrame("Frame")

function G.Start()
    gs = NewGameState()
    G.gs = gs

    gs.weapons[1] = {template = WS.WEAPONS[1], level = 1, cdAccum = 0, orbAngle = 0}
    FireOrb(gs.weapons[1])
    gs.weapons[2] = {template = WS.WEAPONS[2], level = 1, cdAccum = 0}

    gs.running = true
    gs.nextWaveTick = 2

    updateFrame:SetScript("OnUpdate", G.OnUpdate)
    WS.UI.StartGame(gs)
end

function G.Stop()
    gs.running = false
    updateFrame:SetScript("OnUpdate", nil)

    if gs.score > (WS.db.highScore or 0) then WS.db.highScore = gs.score end
    if gs.wave  > (WS.db.bestWave  or 0) then WS.db.bestWave  = gs.wave  end
    WS.db.totalRuns = (WS.db.totalRuns or 0) + 1

    WS.UI.ShowGameOver(gs)
end

function G.Quit()
    gs.running = false
    updateFrame:SetScript("OnUpdate", nil)
    WS.UI.ShowGameOver(gs)
end

function G.OnUpdate(self, elapsed)
    if not gs or not gs.running then return end
    if gs.paused then return end

    gs.time = gs.time + elapsed

    -- wave spawner
    if gs.time >= gs.nextWaveTick then
        gs.wave = gs.wave + 1
        SpawnWave(gs.wave)
        gs.nextWaveTick = gs.time + WS.WAVE_INTERVAL
        WS.UI.OnWave(gs.wave)
    end

    -- player movement
    local dx, dy = GetMoveDir()
    if dx ~= 0 or dy ~= 0 then
        gs.px = gs.px + dx * gs.moveSpeed * elapsed
        gs.py = gs.py + dy * gs.moveSpeed * elapsed
        gs.px, gs.py = ClampArena(gs.px, gs.py)
    end

    -- regen
    if gs.regenRate > 0 then
        gs.regenAccum = gs.regenAccum + elapsed
        if gs.regenAccum >= 3 then
            gs.regenAccum = gs.regenAccum - 3
            gs.hp = math.min(gs.maxHp, gs.hp + gs.regenRate)
        end
    end

    -- iframes countdown
    if gs.iframes > 0 then gs.iframes = gs.iframes - elapsed end

    -- weapon cooldowns
    for _, w in ipairs(gs.weapons) do
        if w.template.id ~= "orb" then  -- orb is persistent, not fired on CD
            w.cdAccum = w.cdAccum + elapsed
            if w.cdAccum >= WeaponCD(w) then
                w.cdAccum = w.cdAccum - WeaponCD(w)
                if FIRE[w.template.id] then FIRE[w.template.id](w) end
            end
        end
    end

    -- update orb projectiles angle
    for _, w in ipairs(gs.weapons) do
        if w.template.id == "orb" then
            local angSpeed = 1.8 + (w.level - 1) * 0.3
            w.orbAngle = w.orbAngle + angSpeed * elapsed
            local r = 60 + (w.level-1)*10
            for _, p in ipairs(gs.projectiles) do
                if p.orbRef == w then
                    p.x    = gs.px + math.cos(w.orbAngle) * r
                    p.y    = gs.py + math.sin(w.orbAngle) * r
                    p.hits = {}   -- reset each tick so orb can re-hit enemies
                end
            end
        end
    end

    -- move non-orb projectiles
    for i = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[i]
        if not p.orbRef then
            p.x    = p.x + p.vx * elapsed
            p.y    = p.y + p.vy * elapsed
            p.life = p.life - elapsed
            if p.life <= 0
               or p.x < -40 or p.x > WS.ARENA_W + 40
               or p.y < -40 or p.y > WS.ARENA_H + 40 then
                table.remove(gs.projectiles, i)
            end
        end
    end

    -- projectile-enemy collision
    for pi = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[pi]
        if p then
            for ei = #gs.enemies, 1, -1 do
                local e = gs.enemies[ei]
                if not p.hits[e] and Dist(p.x, p.y, e.x, e.y) < WS.PROJ_RADIUS + e.template.size/2 then
                    p.hits[e] = true
                    p.pierce  = p.pierce - 1
                    e.hp      = e.hp - p.dmg
                    e.flashTimer = 0.15
                    gs.score  = gs.score + p.dmg
                    WS.UI.SpawnDmgNumber(e.x, e.y, p.dmg, false)
                    WS.UI.SpawnHitSpark(e.x, e.y, e.template.deathR or 1, e.template.deathG or 0.5, e.template.deathB or 0.2)
                    if e.hp <= 0 then
                        WS.UI.SpawnDeathBurst(e.x, e.y, e.template.deathR or 0.6, e.template.deathG or 0.1, e.template.deathB or 0.8)
                        WS.UI.OnEnemyKilled(e.x, e.y, e.template)
                        DropPickups(e)
                        table.remove(gs.enemies, ei)
                    end
                    if p.pierce <= 0 and not p.orbRef then
                        if gs.projectiles[pi] then table.remove(gs.projectiles, pi) end
                        break
                    end
                end
            end
        end
    end

    -- enemy movement + player collision + boss specials
    for i = #gs.enemies, 1, -1 do
        local e = gs.enemies[i]
        e.flashTimer = math.max(0, e.flashTimer - elapsed)

        -- boss special abilities
        local tmpl = e.template
        if tmpl.isBoss and tmpl.special then
            e.specialAccum = (e.specialAccum or 0) + elapsed
            if e.specialAccum >= tmpl.specialCd then
                e.specialAccum = 0

                if tmpl.special == "frostnova" then
                    -- burst of 8 slow projectiles outward from boss
                    for a = 0, 7 do
                        local ang = (a / 8) * math.pi * 2
                        gs.projectiles[#gs.projectiles + 1] = {
                            x        = e.x,
                            y        = e.y,
                            vx       = math.cos(ang) * 120,
                            vy       = math.sin(ang) * 120,
                            dmg      = tmpl.dmg,
                            pierce   = 1,
                            weaponId = "boss_nova",
                            life     = 3.0,
                            hits     = {},
                            isBossProj = true,
                        }
                    end

                elseif tmpl.special == "charge" then
                    -- brief speed burst straight at player
                    e.chargeVx = (gs.px - e.x)
                    e.chargeVy = (gs.py - e.y)
                    local d = math.sqrt(e.chargeVx^2 + e.chargeVy^2)
                    if d > 0 then
                        e.chargeVx = e.chargeVx / d * tmpl.speed * 5
                        e.chargeVy = e.chargeVy / d * tmpl.speed * 5
                    end
                    e.chargeTimer = 0.4

                elseif tmpl.special == "summon" then
                    -- spawn 3 normal ghouls
                    for s = 1, 3 do
                        if #gs.enemies < WS.MAX_ENEMIES + 5 then
                            local ang = (s / 3) * math.pi * 2
                            local sx  = e.x + math.cos(ang) * 40
                            local sy  = e.y + math.sin(ang) * 40
                            gs.enemies[#gs.enemies + 1] = {
                                x           = sx,
                                y           = sy,
                                hp          = WS.ENEMY_TYPES[1].hp,
                                maxHp       = WS.ENEMY_TYPES[1].hp,
                                speed       = WS.ENEMY_TYPES[1].speed,
                                template    = WS.ENEMY_TYPES[1],
                                flashTimer  = 0,
                                specialAccum= 0,
                            }
                        end
                    end

                elseif tmpl.special == "teleport" then
                    -- teleport to a random point just outside player
                    local ang = math.random() * math.pi * 2
                    local dist = WS.HIT_RADIUS + 60 + math.random(30)
                    e.x = math.max(0, math.min(WS.ARENA_W, gs.px + math.cos(ang) * dist))
                    e.y = math.max(0, math.min(WS.ARENA_H, gs.py + math.sin(ang) * dist))
                    WS.UI.SpawnDeathBurst(e.x, e.y, tmpl.deathR or 0.7, tmpl.deathG or 0.1, tmpl.deathB or 0.9)
                end
            end
        end

        -- charge movement overrides normal movement briefly
        if e.chargeTimer and e.chargeTimer > 0 then
            e.chargeTimer = e.chargeTimer - elapsed
            e.x = e.x + (e.chargeVx or 0) * elapsed
            e.y = e.y + (e.chargeVy or 0) * elapsed
            e.x, e.y = ClampArena(e.x, e.y)
        else
            local ndx, ndy = Norm(gs.px - e.x, gs.py - e.y)
            e.x = e.x + ndx * (e.speed or tmpl.speed) * elapsed
            e.y = e.y + ndy * (e.speed or tmpl.speed) * elapsed
        end

        if gs.iframes <= 0 and Dist(e.x, e.y, gs.px, gs.py) < WS.HIT_RADIUS then
            gs.hp      = gs.hp - tmpl.dmg
            gs.iframes = 1.0
            WS.UI.TriggerHitFlash()
            if gs.hp <= 0 then
                G.Stop()
                return
            end
        end
    end

    -- boss projectile-player collision
    for i = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[i]
        if p and p.isBossProj then
            if gs.iframes <= 0 and Dist(p.x, p.y, gs.px, gs.py) < WS.HIT_RADIUS then
                gs.hp      = gs.hp - p.dmg
                gs.iframes = 0.6
                WS.UI.TriggerHitFlash()
                table.remove(gs.projectiles, i)
                if gs.hp <= 0 then G.Stop(); return end
            end
        end
    end

    -- pickup collection
    for i = #gs.pickups, 1, -1 do
        local pk = gs.pickups[i]
        if Dist(pk.x, pk.y, gs.px, gs.py) < gs.pickupRadius then
            if pk.kind == "xp" then
                gs.xp = gs.xp + pk.value
                PlaySound(871, "SFX")
            elseif pk.kind == "hp" then
                gs.hp = math.min(gs.maxHp, gs.hp + pk.value)
                WS.UI.SpawnHealBurst(gs.px, gs.py)
                WS.UI.TriggerHpFlash()
            end
            table.remove(gs.pickups, i)
        end
    end

    -- check level up
    CheckLevelUp()

    -- render
    WS.UI.Render(gs, elapsed)
end

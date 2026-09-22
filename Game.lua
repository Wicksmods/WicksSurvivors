-- Wick's Survivors
-- Game.lua: simulation loop, biome waves, enemy AI/specials, weapon firing, collision
--
-- Ported to parity with the standalone Godot build: biome system, enemy
-- archetypes (armor/shield/ranged/swarm), 4 boss specials + empowered phase,
-- weapons (bolt/multishot/nova-split/void-tendril/aura/scythe/meteor/dreadhound),
-- stacking-rank upgrades, and the expanded pickup drop table.

local ADDON, ns = ...
local WS = WicksSurvivors
WS.Game = {}
local G = WS.Game

local gs  -- game state

-- ── State ──────────────────────────────────────────────────────────────────

local function NewGameState()
    return {
        running      = false,
        paused       = false,
        time         = 0,
        wave         = 0,
        nextWaveReady= 0,    -- earliest time the next wave may start after a clear
        waveHardCap  = 0,    -- absolute time the next wave is forced
        waveSpawned  = false,-- did the current wave finish spawning its enemies?
        score        = 0,

        hp           = 100,
        maxHp        = 100,
        xp           = 0,
        level        = 1,
        xpNext       = WS.XP_TABLE[1],
        px           = WS.ARENA_W / 2,
        py           = WS.ARENA_H / 2,
        moveSpeed    = 145,
        dmgMult      = 1.0,
        flatDmg      = 0,
        cdMult       = 1.0,
        projSpeedMult= 1.0,
        pickupRadius = WS.PICKUP_RADIUS,
        regenRate    = 0,
        regenAccum   = 0,
        armor        = 0,
        lifesteal    = 0,
        iframes      = 0,
        shield       = 0,            -- temp absorb pool (from shield pickup)
        hasteTimer   = 0,            -- speed boost remaining
        rageTimer    = 0,            -- damage boost remaining

        weapons      = {},           -- {template, level}
        passives     = {},           -- id -> rank count
        ranks        = {},           -- id -> rank count (weapons + passives, for level-up caps)

        biomeIdx     = -1,

        enemies      = {},
        projectiles  = {},           -- player + boss/enemy projectiles
        pickups      = {},
        scythes      = {},           -- {ownerAngleOffset...} rendered orbiting blades
        wolves       = {},           -- autonomous dreadhounds
        meteors      = {},           -- falling meteors (visual + impact)
        arcs         = {},           -- transient void-tendril / lightning visuals

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

-- Player damage for a weapon at its current rank.
local function WeaponDmg(w)
    local base = (w.template.baseDmg or 0)
    -- Fel Bolt scales +18% per rank (standalone "damage" upgrade); others use a
    -- gentler +25% per rank so weapon ranks still feel meaningful.
    local perRank = (w.template.id == "bolt") and 0.18 or 0.25
    local scaled  = base * (1 + (w.level - 1) * perRank) + (gs.flatDmg or 0)
    local boost   = (gs.rageTimer > 0) and 1.5 or 1.0
    return math.floor(scaled * gs.dmgMult * boost)
end

local function WeaponCD(w)
    return (w.template.cooldown or 1) * gs.cdMult
end

-- ── Damage application to an enemy (handles shield + armor) ───────────────────

local function DamageEnemy(e, dmg, isCrit)
    -- shield absorbs first, then armor reduces
    if (e.shieldCur or 0) > 0 then
        local absorbed = math.min(e.shieldCur, dmg)
        e.shieldCur = e.shieldCur - absorbed
        dmg = dmg - absorbed
        e.shieldRecharge = 4.0
    end
    dmg = math.max(0, dmg - (e.archetype.armor or 0))
    if dmg <= 0 then return false end

    e.hp = e.hp - dmg
    e.flashTimer = 0.15
    gs.score = gs.score + dmg
    WS.UI.SpawnDmgNumber(e.x, e.y, dmg, isCrit)
    WS.UI.SpawnHitSpark(e.x, e.y, e.deathR, e.deathG, e.deathB)
    return true
end

local function DropPickups(e)
    -- XP is granted on PICKUP collection, not on kill (avoids double-counting).
    gs.score = gs.score + e.xp * 5
    gs.pickups[#gs.pickups + 1] = {x=e.x, y=e.y, kind="xp", value=e.xp, tex="pickup_xp"}

    for _, d in ipairs(WS.PICKUP_DROPS) do
        if math.random() < d.chance then
            local v = d.value
            if d.kind == "xp2" then v = e.xp * 2 end
            local ox = math.random(-20, 20)
            local oy = math.random(-20, 20)
            gs.pickups[#gs.pickups + 1] = {x=e.x+ox, y=e.y+oy, kind=d.kind, value=v, tex=d.tex}
        end
    end
end

local function KillEnemy(e, idx)
    WS.UI.SpawnDeathBurst(e.x, e.y, e.deathR, e.deathG, e.deathB)
    WS.UI.OnEnemyKilled(e.x, e.y, e)
    DropPickups(e)
    if gs.lifesteal > 0 then
        gs.hp = math.min(gs.maxHp, gs.hp + gs.lifesteal)
    end
    if idx then table.remove(gs.enemies, idx) end
end

-- Spawn a transient writhing arc visual (void tendril / boss lightning).
local function SpawnArc(points, r, g, b, life)
    gs.arcs[#gs.arcs + 1] = {points = points, r=r, g=g, b=b, life=life, maxLife=life}
end

-- ── Enemy spawning ───────────────────────────────────────────────────────────

local function ResolveTex(baseType, biome)
    -- Reskinnable bases get the biome suffix; uniques/others use their own art.
    if WS.RESKIN_BASES[baseType] then
        return baseType .. biome.reskinSuffix
    end
    return baseType
end

local function MakeEnemy(baseType, biome, hp, speed, dmg, xp)
    local arch = WS.ARCHETYPE[baseType] or WS.ARCHETYPE.ghoul
    local vis  = WS.ENEMY_VISUAL[baseType] or WS.ENEMY_VISUAL.ghoul
    local x, y = RandEdge()
    local spd = speed * (arch.swarm and 1.08 or 1.0)
    local e = {
        x=x, y=y,
        hp=hp, maxHp=hp,
        speed=spd,
        dmg=math.floor(dmg * (arch.dmgMult or 1)),
        xp=xp,
        baseType   = baseType,
        tex        = ResolveTex(baseType, biome),
        archetype  = arch,
        size       = vis.size,
        deathR=vis.deathR, deathG=vis.deathG, deathB=vis.deathB,
        dropHp     = WS.ENEMY_BASE[baseType] and WS.ENEMY_BASE[baseType].dropHp or false,
        flashTimer = 0,
        shieldCur  = arch.shield or 0,
        shieldRecharge = 0,
        rangedTimer = arch.ranged and (1.2 + math.random()*1.2) or nil,
        orbitAngle  = math.random() * math.pi * 2,
        specialAccum= 0,
    }
    return e
end

-- Boss spawn (one per biome). hp scales with wave; special timer jitters.
local function SpawnBoss(biome, wave)
    local tmpl = WS.BOSS_TYPES[biome.boss]
    -- Single gentle HP scale (was double-compounding, producing 5k-20k HP slogs).
    local bossHp   = math.floor(tmpl.hp * (1 + wave * 0.04))
    local spdScale = 0.58
    local x, y = RandEdge()
    gs.enemies[#gs.enemies + 1] = {
        x=x, y=y,
        hp    = bossHp,
        maxHp = bossHp,
        speed = tmpl.speed * spdScale,
        dmg   = math.floor(tmpl.dmg * (1 + wave*0.02)),
        xp    = 28 + wave * 6,
        baseType  = biome.boss,
        tex       = tmpl.tex,
        empoweredTex = tmpl.empoweredTex,
        empowered = false,
        archetype = {armor=0, shield=0, dmgMult=1.0, ranged=false, swarm=false},
        size      = tmpl.size,
        deathR=tmpl.deathR, deathG=tmpl.deathG, deathB=tmpl.deathB,
        dropHp    = true,
        isBoss    = true,
        special   = tmpl.special,
        specialCd = tmpl.specialCd,
        flashTimer= 0,
        shieldCur = 0,
        orbitAngle= math.random() * math.pi * 2,
        specialAccum = 1.6 + math.random() * 1.2,
        tmpl = tmpl,
    }
    if WS.UI.PlaySFX then WS.UI.PlaySFX(8585) end  -- boss roar-ish
end

-- Build the enemy pool for a wave from the biome's reskinned bases + uniques.
local function WaveEnemyPool(biome, wave)
    local pool = {}
    -- ramp which base types are available with wave depth
    local bases = {"ghoul", "wraith", "abomination", "banshee", "lich"}
    local maxBase = math.min(#bases, 1 + math.floor(wave / 3))
    for i = 1, maxBase do pool[#pool+1] = bases[i] end
    for _, u in ipairs(biome.unique) do pool[#pool+1] = u end
    return pool
end

local function SpawnWave(wave)
    local biome = WS.BIOMES[gs.biomeIdx + 1]

    -- boss wave
    if wave % WS.BOSS_EVERY == 0 then
        SpawnBoss(biome, wave)
        -- a few escorts
        local escorts = math.min(6, math.floor((wave / WS.BOSS_EVERY) * 2))
        local pool = WaveEnemyPool(biome, wave)
        local hpScale = (1.025 ^ (wave-1)) * 0.98
        for i = 1, escorts do
            if #gs.enemies < WS.MAX_ENEMIES then
                local bt = pool[math.random(#pool)]
                local base = WS.ENEMY_BASE[bt]
                gs.enemies[#gs.enemies+1] = MakeEnemy(bt, biome,
                    math.floor(base.hp * hpScale),
                    base.speed * (1 + wave*0.012),
                    base.dmg + math.floor(wave*0.8),
                    base.xp)
            end
        end
        return
    end

    local pool    = WaveEnemyPool(biome, wave)
    local count   = math.min(WS.MAX_ENEMIES, 6 + wave * 2)
    local hpScale = (1.025 ^ (wave-1)) * 0.98
    for i = 1, count do
        if #gs.enemies < WS.MAX_ENEMIES then
            local bt = pool[math.random(#pool)]
            local base = WS.ENEMY_BASE[bt]
            gs.enemies[#gs.enemies+1] = MakeEnemy(bt, biome,
                math.floor(base.hp * hpScale),
                base.speed * (1 + wave*0.012),
                base.dmg + math.floor(wave*0.8),
                base.xp)
        end
    end
end

-- ── Weapon firing ────────────────────────────────────────────────────────────

local function NearestEnemy(fromX, fromY)
    fromX, fromY = fromX or gs.px, fromY or gs.py
    local best, bd = nil, math.huge
    for _, e in ipairs(gs.enemies) do
        local d = Dist(fromX, fromY, e.x, e.y)
        if d < bd then best, bd = e, d end
    end
    return best, bd
end

local function SpawnPlayerProj(dx, dy, dmg, spd, pierce, weaponId, life, forks)
    gs.projectiles[#gs.projectiles + 1] = {
        x=gs.px, y=gs.py,
        vx=dx*spd, vy=dy*spd,
        dmg=dmg, pierce=pierce or 1,
        weaponId=weaponId or "bolt",
        life=life or 2.5,
        forks=forks or 0,   -- fork-to-nearby count when this bolt lands a hit
        hits={},
    }
end

local VOID_R, VOID_G, VOID_B = 0.52, 0.22, 0.88   -- Void Tendril beam (purple)
local FORK_R, FORK_G, FORK_B = 0.42, 0.94, 0.62   -- Fel Bolt fork arcs (green)

-- Fel Bolt forks to nearby enemies on hit when the chain powerup is owned.
-- Green arcs (distinct from the purple Void Tendril beam weapon).
local function ForkBolt(fromE, forks, dmg)
    local hit = {[fromE]=true}
    local cur = fromE
    local d = math.floor(dmg * 0.78)
    for _ = 1, forks do
        local best, bd = nil, 360
        for _, e in ipairs(gs.enemies) do
            if not hit[e] then
                local dd = Dist(cur.x, cur.y, e.x, e.y)
                if dd < bd then best, bd = e, dd end
            end
        end
        if not best then break end
        hit[best] = true
        SpawnArc({cur.x, cur.y, best.x, best.y}, FORK_R, FORK_G, FORK_B, 0.26)
        DamageEnemy(best, math.max(1, d))
        d = math.floor(d * 0.72)
        cur = best
    end
    for i = #gs.enemies, 1, -1 do
        if gs.enemies[i].hp <= 0 then KillEnemy(gs.enemies[i], i) end
    end
end

-- Fel Bolt: auto-fire toward nearest, piercing green lightning. Pierce grows with
-- rank (rank 1 punches through 2 foes; +1 per rank).
local function FireBolt(w)
    local target = NearestEnemy()
    if not target then return end
    local dx, dy = Norm(target.x - gs.px, target.y - gs.py)
    local dmg = WeaponDmg(w)
    local spd = (w.template.projSpeed or 242) * gs.projSpeedMult
    local forks  = gs.ranks.chain or 0      -- chain powerup also makes the bolt fork
    local pierce = 2 + (w.level - 1)        -- pierce through multiple enemies
    SpawnPlayerProj(dx, dy, dmg, spd, pierce, "bolt", 2.5, forks)

    -- multishot: extra angled bolts at 80% dmg
    local ms = gs.ranks.multishot or 0
    for i = 1, ms do
        local sign = (i % 2 == 0) and -1 or 1
        local ang = math.rad(15 * i) * sign
        local cos, sin = math.cos(ang), math.sin(ang)
        local rdx = dx*cos - dy*sin
        local rdy = dx*sin + dy*cos
        SpawnPlayerProj(rdx, rdy, math.floor(dmg*0.8), spd, pierce, "bolt", 2.5, forks)
    end
end

-- Fel Explosion: 8-direction fireballs. Each fireball splits into 2 shards at
-- +-45deg after travelling SPLIT_AT pixels OR on first hit (whichever is first),
-- matching the standalone. Shards do not re-split.
local NOVA_SPLIT_AT = 120
local function FireNova(w)
    local dmg = WeaponDmg(w)
    local spd = (w.template.projSpeed or 260)
    for i = 0, 7 do
        local ang = (2*math.pi*i)/8
        gs.projectiles[#gs.projectiles+1] = {
            x=gs.px, y=gs.py,
            vx=math.cos(ang)*spd, vy=math.sin(ang)*spd,
            dmg=dmg, pierce=1, weaponId="nova",
            life=2.0, hits={}, canSplit=true, dist=0,
        }
    end
end

-- Spawn the 2 shards from a nova fireball at +-45deg of its travel direction.
local function NovaSplit(p)
    for _, s in ipairs({1, -1}) do
        local ang = math.atan2(p.vy, p.vx) + math.rad(45 * s)
        local spd = math.sqrt(p.vx^2 + p.vy^2)
        gs.projectiles[#gs.projectiles+1] = {
            x=p.x, y=p.y,
            vx=math.cos(ang)*spd, vy=math.sin(ang)*spd,
            dmg=math.floor(p.dmg * 0.6), pierce=1,
            weaponId="nova", life=1.5, hits={}, isShard=true, dist=0,
        }
    end
end

-- Void Tendril: a persistent purple beam (standalone VoidBeam) that lashes the
-- nearest foe in range each tick, drains 2 HP to the player, and splits to nearby
-- enemies. Rank raises the split count. Fired on a fast cooldown (DPS interval).
local function FireChain(w)
    local target, td = NearestEnemy()
    if not target then return end
    local range = w.template.range or 200
    if td > range then return end
    local dmg = WeaponDmg(w)
    DamageEnemy(target, dmg)
    -- main lash from the player to the target
    SpawnArc({gs.px, gs.py, target.x, target.y}, VOID_R, VOID_G, VOID_B, 0.30)
    -- void drain
    gs.hp = math.min(gs.maxHp, gs.hp + 2)
    -- splits (rank-based)
    local splits = w.level
    local splitR = w.template.splitRange or 220
    local splitDmg = math.floor(dmg * 0.6)
    local hit = {[target] = true}
    local from = target
    for _ = 1, splits do
        local best, bd = nil, splitR
        for _, e in ipairs(gs.enemies) do
            if not hit[e] then
                local d = Dist(from.x, from.y, e.x, e.y)
                if d < bd then best, bd = e, d end
            end
        end
        if not best then break end
        hit[best] = true
        SpawnArc({from.x, from.y, best.x, best.y}, VOID_R, VOID_G, VOID_B, 0.30)
        DamageEnemy(best, splitDmg)
        from = best
    end
    for i = #gs.enemies, 1, -1 do
        if gs.enemies[i].hp <= 0 then KillEnemy(gs.enemies[i], i) end
    end
end

-- Fel Aura: pulse damage to all enemies within range.
local function FireAura(w)
    local r = (w.template.range or 180) * (1 + (w.level-1)*0.10)
    local dmg = WeaponDmg(w)
    for i = #gs.enemies, 1, -1 do
        local e = gs.enemies[i]
        if Dist(gs.px, gs.py, e.x, e.y) <= r then
            DamageEnemy(e, dmg)
            if e.hp <= 0 then KillEnemy(e, i) end
        end
    end
    WS.UI.SpawnShockwave(gs.px, gs.py, WS.C.fel.r, WS.C.fel.g, WS.C.fel.b, r)
end

-- Meteor: strike nearest enemy position; AoE damage on impact.
local function FireMeteor(w)
    local target = NearestEnemy()
    if not target then return end
    local dmg = WeaponDmg(w)
    gs.meteors[#gs.meteors+1] = {
        tx=target.x, ty=target.y,
        dmg=dmg, radius=(w.template.range or 90),
        fall=0.55, elapsed=0,
    }
end

-- Soul Scythe / Dreadhound are persistent entities; (re)build on rank change.
local function RebuildScythes(w)
    gs.scythes = {}
    local count = w.level   -- 1 blade per rank, capped by maxRank
    for i = 1, count do
        gs.scythes[#gs.scythes+1] = {
            phaseOffset = (2*math.pi*(i-1))/count,
            template = w.template,
            weapon = w,
            hitCds = {},   -- enemy -> cd remaining
        }
    end
end

local function SpawnWolf(w)
    gs.wolves[#gs.wolves+1] = {
        x = gs.px + math.random(-30, 30),
        y = gs.py + math.random(-30, 30),
        dmg = WeaponDmg(w),
        speed = w.template.speed or 220,
        life = w.template.life or 10,
        elapsed = 0,
        returning = false,
        target = nil,
        hitCds = {},
        facing = 1,
        animPhase = math.random(),
    }
end

local FIRE = {
    bolt   = FireBolt,
    nova   = FireNova,
    aura   = FireAura,
    meteor = FireMeteor,
    chain  = FireChain,   -- Void Tendril: purple lashing beam (its own weapon)
    -- NOT CD-fired here (no entry on purpose):
    --   multishot: bolt modifier (extra bolts), handled in FireBolt
    --   scythe:    persistent orbiting blades (RebuildScythes), updated each tick
    --   wolf:      spawned on its own recurring timer in OnUpdate
    -- Note: taking the "chain" upgrade ALSO makes Fel Bolt fork (green arcs) via
    --       gs.ranks.chain in FireBolt -- mirrors the standalone's shared chain_count.
}

-- ── Level-up (stacking ranks) ────────────────────────────────────────────────

local function CheckLevelUp()
    while gs.xp >= gs.xpNext do
        gs.xp = gs.xp - gs.xpNext
        gs.level = gs.level + 1
        gs.xpNext = WS.XP_TABLE[math.min(gs.level, #WS.XP_TABLE)] or math.floor(gs.xpNext * 1.2)
        gs.levelUpPending = true
        gs.paused = true
        WS.UI.SpawnDeathBurst(gs.px, gs.py, WS.C.fel.r, WS.C.fel.g, WS.C.fel.b)
        WS.UI.TriggerLevelFlash()
        WS.UI.ShowLevelUp()
    end
end

-- Build the 3-card upgrade choice respecting per-id rank caps.
function G.RollChoices()
    local pool = {}
    for _, t in ipairs(WS.WEAPONS) do
        if (gs.ranks[t.id] or 0) < (t.maxRank or 3) then
            pool[#pool+1] = {kind="weapon", data=t}
        end
    end
    for _, t in ipairs(WS.PASSIVES) do
        if (gs.ranks[t.id] or 0) < (t.maxRank or 3) then
            pool[#pool+1] = {kind="passive", data=t}
        end
    end
    -- shuffle
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local choices = {}
    for i = 1, math.min(3, #pool) do choices[i] = pool[i] end
    -- pad (rare: everything capped) by repeating
    while #choices < 3 and #pool > 0 do choices[#choices+1] = pool[math.random(#pool)] end
    return choices
end

function G.ApplyChoice(choice)
    local data = choice.data
    local id = data.id
    gs.ranks[id] = (gs.ranks[id] or 0) + 1

    if choice.kind == "passive" then
        data.effect(gs)
        gs.passives[id] = gs.ranks[id]
    else
        -- weapon: add or rank-up
        local w
        for _, ww in ipairs(gs.weapons) do
            if ww.template.id == id then w = ww; break end
        end
        if not w then
            w = {template = data, level = 1}
            gs.weapons[#gs.weapons+1] = w
        else
            w.level = w.level + 1
        end
        -- weapon-specific (re)build hooks
        if id == "scythe" then RebuildScythes(w)
        elseif id == "wolf" then SpawnWolf(w)   -- each rank immediately summons one
        end
    end

    gs.paused = false
    gs.levelUpPending = false
end

-- ── Movement input ───────────────────────────────────────────────────────────

local function GetMoveDir()
    -- Mouse-move steering (matches addon's original control), with WASD fallback
    -- handled by WoW's own bindings is not available in a frame, so we stick to
    -- cursor steering like the standalone "Mouse Move" input mode.
    local arena = WS.UI.GetArenaFrame()
    if not arena then return 0, 0 end
    local cx, cy = GetCursorPosition()
    local scale  = arena:GetEffectiveScale()
    local left   = arena:GetLeft()
    local top    = arena:GetTop()
    if not left then return 0, 0 end
    local mx = (cx / scale) - left
    local my = top - (cy / scale)
    local dx = mx - gs.px
    local dy = my - gs.py
    if math.abs(dx) < 6 and math.abs(dy) < 6 then return 0, 0 end
    return Norm(dx, dy)
end

-- ── Enemy ranged shot ─────────────────────────────────────────────────────────

local function EnemyRangedShot(e)
    local dx, dy = Norm(gs.px - e.x, gs.py - e.y)
    gs.projectiles[#gs.projectiles+1] = {
        x=e.x, y=e.y,
        vx=dx*200, vy=dy*200,
        dmg=math.floor(e.dmg * 0.65),
        pierce=1, weaponId="enemy_shot",
        life=3.0, hits={}, isEnemyProj=true,
    }
end

-- ── Boss specials ──────────────────────────────────────────────────────────────

local function BossSpecial(e)
    local sp = e.special
    if sp == "frostnova" then
        SpawnArc({e.x, e.y, e.x, e.y}, 0.48, 0.82, 1.0, 0.46)
        WS.UI.SpawnShockwave(e.x, e.y, 0.48, 0.82, 1.0, 180)
        if Dist(e.x, e.y, gs.px, gs.py) < 160 and gs.iframes <= 0 then
            gs.hp = gs.hp - math.floor(e.dmg * 0.25)
            gs.hasteTimer = 0           -- frost cancels haste (slow flavor)
            gs.iframes = 0.6
            WS.UI.TriggerHitFlash()
        end
    elseif sp == "eyebeam" then
        local mx = (e.x + gs.px)/2 + math.random(-45,45)
        local my = (e.y + gs.py)/2 + math.random(-45,45)
        SpawnArc({e.x, e.y, mx, my, gs.px, gs.py}, 0.78, 0.52, 1.0, 0.34)
        WS.UI.SpawnHitSpark(gs.px, gs.py, 0.78, 0.52, 1.0)
        if Dist(e.x, e.y, gs.px, gs.py) < 340 and gs.iframes <= 0 then
            gs.hp = gs.hp - math.floor(e.dmg * 0.45); gs.iframes = 0.6; WS.UI.TriggerHitFlash()
        end
    elseif sp == "shadowflame" then
        local dx, dy = Norm(gs.px - e.x, gs.py - e.y)
        local pts = {e.x, e.y}
        for i = 1, 4 do
            local px = e.x + dx*(i*92) + math.random(-24,24)
            local py = e.y + dy*(i*92) + math.random(-24,24)
            pts[#pts+1] = px; pts[#pts+1] = py
            WS.UI.SpawnHitSpark(px, py, 1.0, 0.34, 0.14)
        end
        SpawnArc(pts, 1.0, 0.36, 0.16, 0.30)
        if Dist(e.x, e.y, gs.px, gs.py) < 380 and gs.iframes <= 0 then
            gs.hp = gs.hp - math.floor(e.dmg * 0.4); gs.iframes = 0.6; WS.UI.TriggerHitFlash()
        end
    elseif sp == "feldash" then
        e.chargeVx = (gs.px - e.x); e.chargeVy = (gs.py - e.y)
        local d = math.sqrt(e.chargeVx^2 + e.chargeVy^2)
        if d > 0 then
            e.chargeVx = e.chargeVx/d * e.speed * 4.4
            e.chargeVy = e.chargeVy/d * e.speed * 4.4
        end
        e.chargeTimer = 0.42
        SpawnArc({e.x, e.y, gs.px, gs.py}, 0.32, 1.0, 0.36, 0.22)
    end
end

-- ── Main tick ────────────────────────────────────────────────────────────────

local updateFrame = CreateFrame("Frame")
local wolfTimerAccum = 0

function G.Start(startWave)
    gs = NewGameState()
    G.gs = gs
    gs.biomeIdx = -1   -- -1 so wave 1 triggers OnBiome for the first (frost) biome

    -- starter weapon: Fel Bolt (auto-fire)
    gs.weapons[1] = {template = WS.WEAPONS[1], level = 1}
    gs.ranks.bolt = 1

    -- dev: jump straight to a wave. The spawner increments gs.wave before the
    -- first spawn (and the gs.wave==0 branch kicks off wave 1), so seeding
    -- gs.wave = startWave-1 makes the first spawned wave == startWave.
    if startWave and startWave > 1 then
        gs.wave = startWave - 1
    end

    gs.running = true

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

local function UpdateBiome()
    local biome, idx = WS.BiomeForWave(gs.wave)
    if biome and idx ~= gs.biomeIdx then
        gs.biomeIdx = idx
        WS.UI.OnBiome(biome)
    end
end

function G.OnUpdate(self, elapsed)
    if not gs or not gs.running then return end
    if gs.paused then return end

    gs.time = gs.time + elapsed

    -- timed buffs
    if gs.hasteTimer > 0 then gs.hasteTimer = gs.hasteTimer - elapsed end
    if gs.rageTimer  > 0 then gs.rageTimer  = gs.rageTimer  - elapsed end

    -- wave spawner: advance only when the current wave has been cleared (like the
    -- standalone). A long hard cap prevents a single fleeing straggler from
    -- stalling the run indefinitely.
    local startNext = false
    if not gs.waveSpawned then
        startNext = true                                  -- kick off the first wave
    elseif gs.waveSpawned and #gs.enemies == 0 and gs.time >= gs.nextWaveReady then
        startNext = true                                  -- arena cleared
    elseif gs.time >= gs.waveHardCap then
        startNext = true                                  -- safety ceiling
    end
    if startNext then
        gs.wave = gs.wave + 1
        UpdateBiome()
        SpawnWave(gs.wave)
        gs.waveSpawned   = true
        gs.nextWaveReady = gs.time + 1.5                  -- brief breather after a clear
        gs.waveHardCap   = gs.time + WS.WAVE_HARDCAP      -- absolute ceiling
        WS.UI.OnWave(gs.wave)
    end

    -- player movement (haste boosts speed)
    local dx, dy = GetMoveDir()
    local spd = gs.moveSpeed * ((gs.hasteTimer > 0) and 1.5 or 1.0)
    if dx ~= 0 or dy ~= 0 then
        gs.px = gs.px + dx * spd * elapsed
        gs.py = gs.py + dy * spd * elapsed
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

    if gs.iframes > 0 then gs.iframes = gs.iframes - elapsed end

    -- weapon cooldowns (CD-fired weapons only)
    for _, w in ipairs(gs.weapons) do
        if FIRE[w.template.id] and w.template.cooldown then
            w.cdAccum = (w.cdAccum or 0) + elapsed
            local cd = WeaponCD(w)
            if w.cdAccum >= cd then
                w.cdAccum = w.cdAccum - cd
                FIRE[w.template.id](w)
            end
        end
    end

    -- dreadhound recurring spawn (the wolf weapon keeps summoning)
    do
        local wolfW
        for _, w in ipairs(gs.weapons) do if w.template.id == "wolf" then wolfW = w break end end
        if wolfW then
            wolfTimerAccum = wolfTimerAccum + elapsed
            local interval = math.max(5, (wolfW.template.cooldown or 10) - (wolfW.level-1))
            if wolfTimerAccum >= interval and #gs.wolves < (wolfW.level * 2) then
                wolfTimerAccum = 0
                SpawnWolf(wolfW)
            end
        end
    end

    G.UpdateScythes(elapsed)
    G.UpdateWolves(elapsed)
    G.UpdateMeteors(elapsed)
    G.UpdateArcs(elapsed)

    -- move projectiles
    for i = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[i]
        local mvx, mvy = p.vx * elapsed, p.vy * elapsed
        p.x = p.x + mvx
        p.y = p.y + mvy
        p.life = p.life - elapsed
        -- nova fireballs split after travelling NOVA_SPLIT_AT even without a hit
        local removed = false
        if p.canSplit then
            p.dist = (p.dist or 0) + math.sqrt(mvx*mvx + mvy*mvy)
            if p.dist >= NOVA_SPLIT_AT then
                p.canSplit = false
                NovaSplit(p)
                table.remove(gs.projectiles, i)
                removed = true
            end
        end
        if not removed and (p.life <= 0
           or p.x < -40 or p.x > WS.ARENA_W + 40
           or p.y < -40 or p.y > WS.ARENA_H + 40) then
            table.remove(gs.projectiles, i)
        end
    end

    -- player projectile -> enemy collision
    for pi = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[pi]
        if p and not p.isEnemyProj then
            for ei = #gs.enemies, 1, -1 do
                local e = gs.enemies[ei]
                if not p.hits[e] and Dist(p.x, p.y, e.x, e.y) < WS.PROJ_RADIUS + e.size/2 then
                    p.hits[e] = true
                    p.pierce = p.pierce - 1
                    DamageEnemy(e, p.dmg)
                    -- bolt forks to nearby enemies (Void Tendril upgrade)
                    if p.weaponId == "bolt" and (p.forks or 0) > 0 then
                        ForkBolt(e, p.forks, p.dmg)
                        p.forks = 0   -- fork once per bolt
                    end
                    if e.hp <= 0 then KillEnemy(e, ei) end
                    -- nova split on first hit
                    if p.canSplit then
                        p.canSplit = false
                        NovaSplit(p)
                        if gs.projectiles[pi] then table.remove(gs.projectiles, pi) end
                        break
                    end
                    if p.pierce <= 0 then
                        if gs.projectiles[pi] then table.remove(gs.projectiles, pi) end
                        break
                    end
                end
            end
        end
    end

    -- enemy movement, ranged, specials, player collision
    for i = #gs.enemies, 1, -1 do
        local e = gs.enemies[i]
        e.flashTimer = math.max(0, e.flashTimer - elapsed)

        -- shield recharge
        if (e.shieldRecharge or 0) > 0 then
            e.shieldRecharge = e.shieldRecharge - elapsed
            if e.shieldRecharge <= 0 then e.shieldCur = e.archetype.shield or 0 end
        end

        -- boss empowered swap + specials
        if e.isBoss then
            if not e.empowered and e.hp / e.maxHp <= WS.BOSS_EMPOWER_PCT then
                e.empowered = true
                e.tex = e.empoweredTex or e.tex
                e.specialCd = math.max(2.0, (e.specialCd or 4) * 0.65)
                WS.UI.SpawnDeathBurst(e.x, e.y, e.deathR, e.deathG, e.deathB)
            end
            e.specialAccum = (e.specialAccum or 0) - elapsed
            if e.specialAccum <= 0 then
                BossSpecial(e)
                e.specialAccum = e.specialCd + math.random()*1.5
            end
        end

        -- ranged enemy shots
        if e.archetype.ranged and not e.isBoss then
            e.rangedTimer = (e.rangedTimer or 1.5) - elapsed
            if e.rangedTimer <= 0 then
                if Dist(e.x, e.y, gs.px, gs.py) < 480 then EnemyRangedShot(e) end
                e.rangedTimer = 1.8 + math.random()*1.2
            end
        end

        -- movement (charge override for feldash)
        if e.chargeTimer and e.chargeTimer > 0 then
            e.chargeTimer = e.chargeTimer - elapsed
            e.x = e.x + (e.chargeVx or 0) * elapsed
            e.y = e.y + (e.chargeVy or 0) * elapsed
            e.x, e.y = ClampArena(e.x, e.y)
        else
            -- head straight for the player; a small perpendicular wobble keeps
            -- the swarm from collapsing into one perfectly-stacked point.
            local ndx, ndy = Norm(gs.px - e.x, gs.py - e.y)
            e.orbitAngle = (e.orbitAngle or 0) + elapsed * 2.0
            local wob = math.sin(e.orbitAngle) * 0.18   -- small lateral drift
            local px, py = -ndy, ndx                      -- perpendicular
            e.x = e.x + (ndx + px*wob) * e.speed * elapsed
            e.y = e.y + (ndy + py*wob) * e.speed * elapsed
        end

        -- contact damage
        if gs.iframes <= 0 and Dist(e.x, e.y, gs.px, gs.py) < WS.HIT_RADIUS + e.size/3 then
            local dmg = math.max(0, e.dmg - gs.armor)
            if gs.shield > 0 then
                local absorbed = math.min(gs.shield, dmg)
                gs.shield = gs.shield - absorbed
                dmg = dmg - absorbed
            end
            gs.hp = gs.hp - dmg
            gs.iframes = 0.9
            WS.UI.TriggerHitFlash()
            if gs.hp <= 0 then G.Stop(); return end
        end
    end

    -- enemy projectile -> player
    for i = #gs.projectiles, 1, -1 do
        local p = gs.projectiles[i]
        if p and p.isEnemyProj then
            if gs.iframes <= 0 and Dist(p.x, p.y, gs.px, gs.py) < WS.HIT_RADIUS then
                local dmg = math.max(0, p.dmg - gs.armor)
                if gs.shield > 0 then
                    local absorbed = math.min(gs.shield, dmg)
                    gs.shield = gs.shield - absorbed
                    dmg = dmg - absorbed
                end
                gs.hp = gs.hp - dmg
                gs.iframes = 0.6
                WS.UI.TriggerHitFlash()
                table.remove(gs.projectiles, i)
                if gs.hp <= 0 then G.Stop(); return end
            end
        end
    end

    -- Authoritative death check: catches ALL damage sources (boss specials apply
    -- HP loss without their own check, so a special could otherwise drive HP
    -- negative and the run would continue until a contact hit finally triggered).
    if gs.hp <= 0 then
        gs.hp = 0
        G.Stop()
        return
    end

    -- pickups
    for i = #gs.pickups, 1, -1 do
        local pk = gs.pickups[i]
        -- magnet pull
        if pk._magnetized then
            local mdx, mdy = Norm(gs.px - pk.x, gs.py - pk.y)
            pk.x = pk.x + mdx * 400 * elapsed
            pk.y = pk.y + mdy * 400 * elapsed
        end
        if Dist(pk.x, pk.y, gs.px, gs.py) < gs.pickupRadius then
            G.CollectPickup(pk)
            table.remove(gs.pickups, i)
        end
    end

    CheckLevelUp()
    WS.UI.Render(gs, elapsed)
end

-- ── Pickup collection (mirrors Game.gd _on_pickup_collected) ─────────────────

function G.CollectPickup(pk)
    local k = pk.kind
    if k == "xp" or k == "xp2" then
        gs.xp = gs.xp + pk.value
        PlaySound(871, "SFX")
    elseif k == "hp" then
        gs.hp = math.min(gs.maxHp, gs.hp + pk.value)
        WS.UI.SpawnHealBurst(gs.px, gs.py)
        WS.UI.TriggerHpFlash()
    elseif k == "haste" then
        gs.hasteTimer = math.min((gs.hasteTimer or 0) + pk.value, 9)
    elseif k == "rage" then
        gs.rageTimer = math.min((gs.rageTimer or 0) + pk.value, 9)
    elseif k == "shield" then
        gs.shield = math.max(gs.shield, pk.value)
        WS.UI.TriggerHpFlash()
    elseif k == "magnet" then
        for _, p2 in ipairs(gs.pickups) do
            if p2.kind == "xp" or p2.kind == "xp2" then p2._magnetized = true end
        end
    end
end

-- ── Persistent entity updates ────────────────────────────────────────────────

function G.UpdateScythes(elapsed)
    for _, s in ipairs(gs.scythes) do
        s.angle = (s.angle or 0) + (s.template.orbitSpeed or 2.6) * elapsed
        local r = s.template.orbitRadius or 96
        s.x = gs.px + math.cos(s.angle + s.phaseOffset) * r
        s.y = gs.py + math.sin(s.angle + s.phaseOffset) * r
        -- tick hit cds
        for e, cd in pairs(s.hitCds) do
            s.hitCds[e] = cd - elapsed
            if s.hitCds[e] <= 0 then s.hitCds[e] = nil end
        end
        -- hits
        local dmg = WeaponDmg(s.weapon)
        local hitR = s.template.hitR or 28
        for i = #gs.enemies, 1, -1 do
            local e = gs.enemies[i]
            if not s.hitCds[e] and Dist(s.x, s.y, e.x, e.y) < hitR + e.size/2 then
                s.hitCds[e] = s.template.hitCd or 0.6
                DamageEnemy(e, dmg)
                WS.UI.SpawnHitSpark(s.x, s.y, 0.72, 1.0, 0.72)
                if e.hp <= 0 then KillEnemy(e, i) end
            end
        end
    end
end

function G.UpdateWolves(elapsed)
    for wi = #gs.wolves, 1, -1 do
        local w = gs.wolves[wi]
        w.elapsed = w.elapsed + elapsed
        if w.elapsed >= w.life then table.remove(gs.wolves, wi)
        else
            for e, cd in pairs(w.hitCds) do
                w.hitCds[e] = cd - elapsed
                if w.hitCds[e] <= 0 then w.hitCds[e] = nil end
            end
            if w.returning or not w.target or w.target.hp == nil or w.target.hp <= 0 then
                w.target = NearestEnemy(w.x, w.y)
                w.returning = (w.target == nil)
            end
            if w.returning then
                local dx, dy = Norm(gs.px - w.x, gs.py - w.y)
                if Dist(w.x, w.y, gs.px, gs.py) < 24 then w.returning = false; w.target = nil
                else
                    w.x = w.x + dx * w.speed * 0.85 * elapsed
                    w.y = w.y + dy * w.speed * 0.85 * elapsed
                    if dx ~= 0 then w.facing = (dx < 0) and -1 or 1 end
                end
            elseif w.target then
                local t = w.target
                local dx, dy = Norm(t.x - w.x, t.y - w.y)
                if Dist(w.x, w.y, t.x, t.y) < 18 then
                    if not w.hitCds[t] then
                        w.hitCds[t] = w.template and w.template.hitCd or 2.0
                        DamageEnemy(t, w.dmg)
                        WS.UI.SpawnHitSpark(t.x, t.y, 0.42, 1.0, 0.52)
                        for i = #gs.enemies, 1, -1 do
                            if gs.enemies[i] == t and t.hp <= 0 then KillEnemy(t, i) break end
                        end
                    end
                    w.returning = true
                else
                    w.x = w.x + dx * w.speed * elapsed
                    w.y = w.y + dy * w.speed * elapsed
                    if dx ~= 0 then w.facing = (dx < 0) and -1 or 1 end
                end
            end
        end
    end
end

function G.UpdateMeteors(elapsed)
    for mi = #gs.meteors, 1, -1 do
        local m = gs.meteors[mi]
        m.elapsed = m.elapsed + elapsed
        if not m.impacted and m.elapsed >= m.fall then
            m.impacted = true
            m.fadeOut = 0.5
            WS.UI.SpawnShockwave(m.tx, m.ty, 1.0, 0.45, 0.12, m.radius*2.2)
            WS.UI.SpawnDeathBurst(m.tx, m.ty, 1.0, 0.55, 0.2)
            for i = #gs.enemies, 1, -1 do
                local e = gs.enemies[i]
                if Dist(m.tx, m.ty, e.x, e.y) < m.radius then
                    DamageEnemy(e, m.dmg)
                    if e.hp <= 0 then KillEnemy(e, i) end
                end
            end
        end
        if m.impacted then
            m.fadeOut = m.fadeOut - elapsed
            if m.fadeOut <= 0 then table.remove(gs.meteors, mi) end
        end
    end
end

function G.UpdateArcs(elapsed)
    for ai = #gs.arcs, 1, -1 do
        local a = gs.arcs[ai]
        a.life = a.life - elapsed
        if a.life <= 0 then table.remove(gs.arcs, ai) end
    end
end

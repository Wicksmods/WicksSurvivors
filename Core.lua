-- Wick's Survivors
-- Core.lua: constants, data tables (biomes / enemies / weapons / passives), saved variables, addon load
--
-- This data layer mirrors the standalone Godot port (Game.gd / Enemy.gd /
-- Player.gd / LevelUp.gd) so the addon and the desktop game stay in sync.

local ADDON, ns = ...
WicksSurvivors = WicksSurvivors or {}
local WS = WicksSurvivors
ns.WS = WS

-- ── Brand palette ────────────────────────────────────────────────────────────
WS.C = {
    fel     = {r=0.310, g=0.780, b=0.471, a=1},
    void    = {r=0.051, g=0.039, b=0.078, a=1},
    shadow  = {r=0.090, g=0.067, b=0.141, a=1},
    purple  = {r=0.220, g=0.188, b=0.345, a=1},
    text    = {r=0.831, g=0.784, b=0.631, a=1},
    red     = {r=0.9,   g=0.2,   b=0.2,   a=1},
    yellow  = {r=1.0,   g=0.85,  b=0.2,   a=1},
    white   = {r=1,     g=1,     b=1,     a=1},
    -- level-up card accents (match standalone LevelUp.gd)
    ember   = {r=0.910, g=0.518, b=0.235, a=1},  -- weapon tag
    arc     = {r=0.608, g=0.482, b=0.831, a=1},  -- passive tag
}

-- ── Game balance constants ───────────────────────────────────────────────────
WS.ARENA_W      = 980
WS.ARENA_H      = 680
WS.TICK          = 0.05
WS.WAVE_HARDCAP  = 45     -- absolute ceiling: force the next wave after this many
                         -- seconds even if a straggler survives (waves normally
                         -- advance when the arena is CLEARED, not on a timer)
WS.MAX_ENEMIES   = 36     -- raised from 20; biome waves are denser
WS.PICKUP_RADIUS = 30
WS.HIT_RADIUS    = 18
WS.PROJ_RADIUS   = 10
WS.BOSS_EVERY    = 6      -- one boss every 6 waves (= one per biome cycle)
WS.WAVES_PER_BIOME = 6

-- XP curve. Enemy XP values here are higher than the standalone's, so the curve
-- is steeper (base 60, x1.28 growth) to keep leveling to ~one level per wave or
-- two early on rather than a level every few kills.
WS.XP_TABLE = {}
do
    for lvl = 1, 60 do
        WS.XP_TABLE[lvl] = math.floor(60 * (1.28 ^ (lvl - 1)))
    end
end

-- ── Sprite textures ──────────────────────────────────────────────────────────
-- TEX maps a logical key -> Art\ TGA path. Built programmatically so adding a
-- sprite only means dropping the TGA in Art\ and adding the key here.
local ART = "Interface\\AddOns\\WicksSurvivors\\Art\\"
WS.TEX = setmetatable({}, {__index = function(t, k)
    -- Lazily resolve any key to Art\<key>; cache it. Missing TGAs show a
    -- question-mark in-game rather than erroring. Guard nil/non-string keys.
    if type(k) ~= "string" then return ART .. "glow" end
    local p = ART .. k
    rawset(t, k, p)
    return p
end})
-- A couple of non-sprite helpers keep explicit names:
WS.TEX.glow = ART .. "glow"

-- ── Enemy archetypes (mirrors Enemy.gd ARCHETYPE) ────────────────────────────
-- armor: flat damage reduction. shield: absorb pool, recharges after 4s.
-- dmgMult: outgoing contact damage multiplier. ranged: fires shots.
-- swarm: faster + cheaper.
WS.ARCHETYPE = {
    ghoul         = {armor=0, shield=0,  dmgMult=1.0,  ranged=false, swarm=false},
    wraith        = {armor=0, shield=0,  dmgMult=0.85, ranged=true,  swarm=false},
    abomination   = {armor=2, shield=0,  dmgMult=1.3,  ranged=false, swarm=false},
    banshee       = {armor=0, shield=0,  dmgMult=0.7,  ranged=true,  swarm=true},
    lich          = {armor=2, shield=20, dmgMult=1.1,  ranged=true,  swarm=false},
    frost_revenant= {armor=2, shield=0,  dmgMult=1.2,  ranged=false, swarm=false},
    frostling     = {armor=0, shield=0,  dmgMult=0.6,  ranged=false, swarm=true},
    magma_hound   = {armor=0, shield=0,  dmgMult=1.1,  ranged=false, swarm=false},
    cinder_wisp   = {armor=0, shield=0,  dmgMult=0.8,  ranged=true,  swarm=true},
    deep_spawn    = {armor=2, shield=15, dmgMult=1.0,  ranged=false, swarm=false},
    gazer         = {armor=0, shield=0,  dmgMult=0.9,  ranged=true,  swarm=false},
    fel_imp       = {armor=0, shield=0,  dmgMult=0.65, ranged=false, swarm=true},
    wrathguard    = {armor=3, shield=20, dmgMult=1.5,  ranged=false, swarm=false},
}

-- Per-type display size + death-burst color. Keyed by base type (reskins share).
WS.ENEMY_VISUAL = {
    ghoul          = {size=30, deathR=0.5, deathG=0.9, deathB=0.2},
    wraith         = {size=28, deathR=0.6, deathG=0.4, deathB=1.0},
    abomination    = {size=44, deathR=0.9, deathG=0.5, deathB=0.1},
    banshee        = {size=34, deathR=0.9, deathG=0.9, deathB=0.3},
    lich           = {size=52, deathR=0.2, deathG=0.7, deathB=1.0},
    frost_revenant = {size=40, deathR=0.4, deathG=0.8, deathB=1.0},
    frostling      = {size=24, deathR=0.6, deathG=0.9, deathB=1.0},
    magma_hound    = {size=38, deathR=1.0, deathG=0.5, deathB=0.15},
    cinder_wisp    = {size=26, deathR=1.0, deathG=0.7, deathB=0.25},
    deep_spawn     = {size=42, deathR=0.6, deathG=0.3, deathB=0.9},
    gazer          = {size=36, deathR=0.7, deathG=0.4, deathB=1.0},
    fel_imp        = {size=24, deathR=0.5, deathG=1.0, deathB=0.4},
    wrathguard     = {size=46, deathR=0.4, deathG=1.0, deathB=0.35},
}

-- ── Biomes (mirrors Game.gd BIOMES) ──────────────────────────────────────────
-- 6 waves each; cycle repeats frost -> ember -> eldritch -> fel.
-- bg is the arena background tint {r,g,b}. reskinSuffix is applied to the
-- 5 base reskinnable types (ghoul/wraith/abomination/banshee/lich) to pick the
-- biome-tinted sprite. unique = enemies that only appear in this biome.
-- bg     : arena floor base tint {r,g,b} (opaque) -- shows through floor-tile gaps
-- grid   : dot-grid + accent color {r,g,b} so the floor reads as the biome
-- floors : tiled floor textures (512x512) laid as a grid across the arena
-- props  : scenery scattered each biome change. {key, floor=true} = laid flat /
--          larger; otherwise a standing decoration.
WS.BIOMES = {
    {key="frost",    name="Frozen Crypt",  boss="boss_kel",     reskinSuffix="_frost",
        bg={0.06, 0.10, 0.17}, grid={0.45, 0.68, 0.95}, unique={"frost_revenant","frostling"},
        floors={"floor_frost_01","floor_frost_02","floor_frost_03"},
        props={
            {key="fc_crystal"}, {key="fc_tomb"}, {key="fc_bones"},
            {key="fc_runestone"}, {key="fc_brazier"}, {key="fc_fissure", floor=true},
        }},
    {key="ember",    name="Ember Caldera", boss="boss_nef",     reskinSuffix="_ember",
        bg={0.17, 0.07, 0.04}, grid={0.95, 0.50, 0.25}, unique={"magma_hound","cinder_wisp"},
        floors={"floor_ember_01","floor_ember_02","floor_ember_03"},
        props={
            {key="em_obsidian"}, {key="em_pillar"}, {key="em_cinders"},
            {key="em_runestone"}, {key="em_vent"}, {key="em_magma", floor=true},
        }},
    {key="eldritch", name="Eldritch Deep", boss="boss_cthun",   reskinSuffix="_eldritch",
        bg={0.11, 0.05, 0.15}, grid={0.70, 0.40, 0.98}, unique={"deep_spawn","gazer"},
        floors={"floor_eldritch_01","floor_eldritch_02","floor_eldritch_03"},
        props={
            {key="el_crystal"}, {key="el_eye"}, {key="el_tentacle"},
            {key="el_idol"}, {key="el_pod"}, {key="el_rift", floor=true},
        }},
    {key="fel",      name="Fel Wastes",    boss="boss_illidan", reskinSuffix="_fel",
        bg={0.05, 0.12, 0.06}, grid={0.40, 0.90, 0.50}, unique={"fel_imp","wrathguard"},
        floors={"floor_fel_01","floor_fel_02","floor_fel_03"},
        props={
            {key="fl_crystal"}, {key="fl_obelisk"}, {key="fl_remains"},
            {key="fl_brazier"}, {key="fl_rift", floor=true}, {key="fl_circle", floor=true},
        }},
}

WS.RESKIN_BASES = {ghoul=true, wraith=true, abomination=true, banshee=true, lich=true}

-- Base enemy stats (pre wave-scaling). HP/speed/dmg/xp are baseline; the wave
-- system scales them. Each biome wave selects a mix of reskinned bases + uniques.
-- Speeds are tuned so the player (moveSpeed 145) out-kites the swarm. Even the
-- fastest swarm types (~95) stay just under the player so you can always create
-- space; big enemies are slow bruisers.
WS.ENEMY_BASE = {
    ghoul          = {hp=40,  speed=58,  dmg=10, xp=10, dropHp=false},
    wraith         = {hp=28,  speed=82,  dmg=8,  xp=12, dropHp=false},
    abomination    = {hp=180, speed=38,  dmg=22, xp=30, dropHp=true},
    banshee        = {hp=70,  speed=72,  dmg=14, xp=20, dropHp=false},
    lich           = {hp=320, speed=34,  dmg=35, xp=60, dropHp=true},
    frost_revenant = {hp=120, speed=50,  dmg=20, xp=28, dropHp=false},
    frostling      = {hp=22,  speed=92,  dmg=6,  xp=8,  dropHp=false},
    magma_hound    = {hp=90,  speed=68,  dmg=18, xp=22, dropHp=false},
    cinder_wisp    = {hp=30,  speed=88,  dmg=9,  xp=12, dropHp=false},
    deep_spawn     = {hp=160, speed=44,  dmg=24, xp=34, dropHp=true},
    gazer          = {hp=80,  speed=62,  dmg=16, xp=24, dropHp=false},
    fel_imp        = {hp=26,  speed=95,  dmg=7,  xp=10, dropHp=false},
    wrathguard     = {hp=240, speed=40,  dmg=30, xp=48, dropHp=true},
}

-- ── Boss templates (mirrors Enemy.gd boss specials) ──────────────────────────
-- One boss per biome. Each has a normal sprite + an "_empowered" sprite that
-- swaps in below a HP threshold. Specials map to Game.lua handlers.
WS.BOSS_TYPES = {
    -- dmg is CONTACT damage (pre wave-scaling). Specials deal a fraction of it.
    -- Tuned so an un-upgraded 100-HP player survives 3-4 contact hits.
    -- hp is BASE boss HP; SpawnBoss applies a single gentle wave scale on top.
    boss_kel = {
        name="Kel'Thuzad", tex="boss_kel", empoweredTex="boss_kel_empowered",
        size=80, hp=700, speed=55, dmg=22, xp=300, dropHp=true, isBoss=true,
        deathR=0.45, deathG=0.78, deathB=1.0,
        special="frostnova", specialCd=4.5,
    },
    boss_nef = {
        name="Nefarian", tex="boss_nef", empoweredTex="boss_nef_empowered",
        size=80, hp=850, speed=45, dmg=26, xp=400, dropHp=true, isBoss=true,
        deathR=1.0, deathG=0.32, deathB=0.12,
        special="shadowflame", specialCd=4.5,
    },
    boss_cthun = {
        name="C'Thun", tex="boss_cthun", empoweredTex="boss_cthun_empowered",
        size=80, hp=1000, speed=35, dmg=28, xp=500, dropHp=true, isBoss=true,
        deathR=0.72, deathG=0.43, deathB=1.0,
        special="eyebeam", specialCd=4.0,
    },
    boss_illidan = {
        name="Illidan", tex="boss_illidan", empoweredTex="boss_illidan_empowered",
        size=80, hp=1100, speed=48, dmg=32, xp=600, dropHp=true, isBoss=true,
        deathR=0.34, deathG=1.0, deathB=0.32,
        special="feldash", specialCd=3.5,
    },
}
WS.BOSS_EMPOWER_PCT = 0.4   -- below 40% HP the boss swaps to its empowered sprite

-- ── Weapons (mirrors LevelUp.gd WEAPON upgrades + Player.gd firing) ──────────
-- id           : matches a FIRE handler in Game.lua
-- maxRank      : stacking cap (from LevelUp.gd MAX_STACKS)
-- The Fel Orb starter is gone in the standalone; the starter is the auto-bolt.
WS.WEAPONS = {
    {
        id="bolt", name="Fel Bolt", tag="WEAPON", maxRank=5,
        desc="Your auto-fire bolt. Each rank +18% projectile damage.",
        icon="weapon_orb", baseDmg=12, cooldown=1/0.72, projSpeed=242, pierce=1,
    },
    {
        id="multishot", name="Twin Bolts", tag="WEAPON", maxRank=3,
        desc="Fire 1 extra projectile per shot. Each rank +1.",
        icon="weapon_bolt",
    },
    {
        id="nova", name="Fel Explosion", tag="WEAPON", maxRank=3,
        desc="Erupts fel fireballs in 8 directions every 5s. They split on hit.",
        icon="weapon_nova", baseDmg=15, cooldown=5.0, projSpeed=260,
    },
    {
        -- Standalone VoidBeam: a persistent short-range void tendril that lashes
        -- the nearest foe in range, ticks damage, siphons HP, and splits to nearby
        -- enemies. Rank raises the split count. Fired on a fast tick (DPS interval).
        id="chain", name="Void Tendril", tag="WEAPON", maxRank=3,
        desc="A void tendril lashes the nearest foe, draining life and splitting to those nearby.",
        icon="weapon_chain", baseDmg=14, cooldown=0.28, range=200, splitRange=220,
    },
    {
        id="aura", name="Fel Aura", tag="WEAPON", maxRank=3,
        desc="Constant damage pulse to nearby enemies every 2.5s.",
        icon="weapon_aura", baseDmg=10, cooldown=2.5, range=180,
    },
    {
        id="scythe", name="Soul Scythe", tag="WEAPON", maxRank=3,
        desc="Orbiting blade damages nearby foes. Each rank adds a blade.",
        icon="weapon_scythe", baseDmg=18, orbitRadius=96, orbitSpeed=2.6, hitR=28, hitCd=0.6,
    },
    {
        id="meteor", name="Meteor", tag="WEAPON", maxRank=3,
        desc="Calls a meteor on the nearest enemy every 4s, damaging all foes nearby.",
        icon="weapon_meteor", baseDmg=35, cooldown=4.0, range=90,
    },
    {
        id="wolf", name="Dreadhound", tag="WEAPON", maxRank=3,
        desc="Summons a fel dreadhound that hunts the nearest foe. Each rank spawns one more.",
        icon="weapon_dreadhound", baseDmg=7, cooldown=10.0, speed=220, life=10, hitCd=2.0,
    },
}

-- ── Passives (mirrors LevelUp.gd PASSIVE upgrades + Game.gd apply) ───────────
WS.PASSIVES = {
    {id="damage2", name="Dark Pact", tag="PASSIVE", maxRank=4, icon="passive_dmg",
        desc="Projectile damage +2.",
        effect=function(gs) gs.flatDmg = (gs.flatDmg or 0) + 2 end},
    {id="speed", name="Swift Form", tag="PASSIVE", maxRank=4, icon="passive_speed",
        desc="Movement speed +16.",
        effect=function(gs) gs.moveSpeed = gs.moveSpeed + 16 end},
    {id="hp", name="Life Tap", tag="PASSIVE", maxRank=6, icon="passive_hp",
        desc="Max HP +20, restore 20 HP.",
        effect=function(gs) gs.maxHp = gs.maxHp + 20; gs.hp = math.min(gs.hp + 20, gs.maxHp) end},
    {id="armor", name="Void Ward", tag="PASSIVE", maxRank=3, icon="passive_regen",
        desc="Take 3 less damage per hit.",
        effect=function(gs) gs.armor = (gs.armor or 0) + 3 end},
    {id="lifesteal", name="Soul Hunger", tag="PASSIVE", maxRank=3, icon="passive_dmg",
        desc="Gain 3 HP on every kill.",
        effect=function(gs) gs.lifesteal = (gs.lifesteal or 0) + 3 end},
    {id="proj_speed", name="Swiftness", tag="PASSIVE", maxRank=3, icon="passive_speed",
        desc="Projectile speed +10%.",
        effect=function(gs) gs.projSpeedMult = (gs.projSpeedMult or 1) * 1.10 end},
    {id="power", name="Power", tag="PASSIVE", maxRank=4, icon="passive_dmg",
        desc="All damage +8%.",
        effect=function(gs) gs.dmgMult = gs.dmgMult * 1.08 end},
    {id="cooldown", name="Haste", tag="PASSIVE", maxRank=3, icon="passive_cooldown",
        desc="Fire rate +8%.",
        effect=function(gs) gs.cdMult = gs.cdMult * 0.92 end},
    {id="pickup", name="Pickup Range", tag="PASSIVE", maxRank=2, icon="passive_pickup",
        desc="Pickup radius +25%.",
        effect=function(gs) gs.pickupRadius = gs.pickupRadius * 1.25 end},
    {id="regen", name="Regeneration", tag="PASSIVE", maxRank=3, icon="passive_regen",
        desc="Regenerate 1 HP every 3 seconds.",
        effect=function(gs) gs.regenRate = gs.regenRate + 1 end},
}

-- ── Pickups (mirrors Game.gd _spawn_death_effects drop table) ────────────────
-- kind -> {chance, ...}. xp always drops. Others roll independently.
WS.PICKUP_DROPS = {
    {kind="hp",     chance=0.30, value=20,  tex="pickup_hp"},
    {kind="haste",  chance=0.07, value=6,   tex="pickup_speed"},   -- 6s speed boost
    {kind="xp2",    chance=0.07, value=0,   tex="pickup_xp2"},     -- value computed = xp*2
    {kind="magnet", chance=0.02, value=0,   tex="pickup_magnet"},  -- pulls all xp
    {kind="rage",   chance=0.05, value=6,   tex="pickup_rage"},    -- 6s damage boost
    {kind="shield", chance=0.05, value=30,  tex="pickup_shield"},  -- flat 30 absorb
}

-- ── Saved variables ──────────────────────────────────────────────────────────
WS.defaultDB = {
    highScore = 0,
    bestWave  = 0,
    totalRuns = 0,
    optAutoOpenFlight = false,
    optAutoOpenLogin  = false,
    optAutoCloseFlight = false,
    optAutoCloseCombat = false,
    optSound          = true,
    optSplash         = true,
    optInputMode      = 1,  -- 1 = mouse-move (matches addon's original behavior)
    menuPos           = nil,
    arenaPos          = nil,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_CONTROL_LOST")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        WicksSurvivorsDB = WicksSurvivorsDB or {}
        for k, v in pairs(WS.defaultDB) do
            if WicksSurvivorsDB[k] == nil then WicksSurvivorsDB[k] = v end
        end
        WS.db = WicksSurvivorsDB

        SLASH_WICKSSURVIVORS1 = "/survivors"
        SlashCmdList["WICKSSURVIVORS"] = function(msg)
            local cmd = (msg or ""):match("^%s*(.-)%s*$")
            cmd = cmd and cmd:lower() or ""

            if cmd == "announce" then
                if SitStandOrDescendStart then
                    local standState = UnitStandState and UnitStandState("player")
                    if standState ~= 2 and standState ~= 3 then
                        SitStandOrDescendStart()
                    end
                elseif DoEmote then
                    DoEmote("SIT")
                end

                if SendChatMessage then
                    SendChatMessage("sits down and starts a game of Wick's Survivors", "EMOTE")
                end

                local function openSurvivors()
                    if WS.UI.OpenMenu then
                        WS.UI.OpenMenu()
                    else
                        WS.UI.ToggleMenu()
                    end
                end

                if C_Timer and C_Timer.After then
                    C_Timer.After(0.35, openSurvivors)
                else
                    openSurvivors()
                end
                return
            end

            -- hidden dev: "/survivors wave N" starts a run directly on wave N.
            -- Not user-documented; for testing late waves/bosses/biomes.
            local n = msg and msg:match("^%s*wave%s+(%d+)%s*$")
            if n then
                WS.Game.Start(tonumber(n))
                return
            end
            WS.UI.ToggleMenu()
        end

    elseif event == "PLAYER_LOGOUT" then
        WicksSurvivorsDB = WS.db

    elseif event == "PLAYER_LOGIN" then
        if WS.db and WS.db.optAutoOpenLogin then
            C_Timer.After(2, function() WS.UI.ToggleMenu() end)
        end

    elseif event == "PLAYER_CONTROL_LOST" then
        if WS.db and WS.db.optAutoOpenFlight and UnitOnTaxi("player") then
            WS.UI.ToggleMenu()
        end

    elseif event == "PLAYER_CONTROL_GAINED" then
        if WS.db and WS.db.optAutoCloseFlight then
            if WS.UI.CloseMenu then WS.UI.CloseMenu() end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        if WS.db and WS.db.optAutoCloseCombat then
            if WS.UI.CloseMenu then WS.UI.CloseMenu() end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- no action
    end
end)

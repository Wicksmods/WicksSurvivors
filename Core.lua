-- Wick's Survivors
-- Core.lua: constants, saved variables, addon load

local ADDON, ns = ...
WicksSurvivors = WicksSurvivors or {}
local WS = WicksSurvivors
ns.WS = WS

-- Brand palette
WS.C = {
    fel     = {r=0.310, g=0.780, b=0.471, a=1},
    void    = {r=0.051, g=0.039, b=0.078, a=1},
    shadow  = {r=0.090, g=0.067, b=0.141, a=1},
    purple  = {r=0.220, g=0.188, b=0.345, a=1},
    text    = {r=0.831, g=0.784, b=0.631, a=1},
    red     = {r=0.9,   g=0.2,   b=0.2,   a=1},
    yellow  = {r=1.0,   g=0.85,  b=0.2,   a=1},
    white   = {r=1,     g=1,     b=1,     a=1},
}

-- Game balance constants
WS.ARENA_W      = 980
WS.ARENA_H      = 680
WS.TICK          = 0.05
WS.WAVE_INTERVAL = 8
WS.MAX_ENEMIES   = 20
WS.PICKUP_RADIUS = 30
WS.HIT_RADIUS    = 18
WS.PROJ_RADIUS   = 10
WS.BOSS_EVERY    = 6    -- boss wave interval

-- XP required per level
WS.XP_TABLE = {50, 100, 175, 275, 400, 575, 800, 1100, 1500, 2000}

-- Sprite textures — point at Art\ custom TGAs exported from Sprite Forge.
-- Fallback: if a TGA is missing WoW shows a question-mark rather than crashing.
local ART = "Interface\\AddOns\\WicksSurvivors\\Art\\"
WS.TEX = {
    player          = ART .. "player",
    ghoul           = ART .. "ghoul",
    wraith          = ART .. "wraith",
    abomination     = ART .. "abomination",
    banshee         = ART .. "banshee",
    lich            = ART .. "lich",
    boss_kel        = ART .. "boss_kel",
    boss_nef        = ART .. "boss_nef",
    boss_cthun      = ART .. "boss_cthun",
    boss_illidan    = ART .. "boss_illidan",
    proj_orb        = ART .. "proj_orb",
    proj_bolt       = ART .. "proj_bolt",
    proj_nova       = ART .. "proj_nova",
    proj_chain      = ART .. "proj_chain",
    proj_aura       = ART .. "proj_aura",
    pickup_xp       = ART .. "pickup_xp",
    pickup_hp       = ART .. "pickup_hp",
    weapon_orb      = ART .. "weapon_orb",
    weapon_bolt     = ART .. "weapon_bolt",
    weapon_nova     = ART .. "weapon_nova",
    weapon_chain    = ART .. "weapon_chain",
    weapon_aura     = ART .. "weapon_aura",
    passive_hp      = ART .. "passive_hp",
    passive_speed   = ART .. "passive_speed",
    passive_dmg     = ART .. "passive_dmg",
    passive_cooldown= ART .. "passive_cooldown",
    passive_pickup  = ART .. "passive_pickup",
    passive_regen   = ART .. "passive_regen",
}

-- Normal enemy templates
WS.ENEMY_TYPES = {
    {name="Ghoul",      hp=40,  speed=65,  dmg=10, xp=10, dropHp=false, tex="ghoul",       size=30, deathR=0.5, deathG=0.9, deathB=0.2},
    {name="Wraith",     hp=28,  speed=100, dmg=8,  xp=12, dropHp=false, tex="wraith",      size=28, deathR=0.6, deathG=0.4, deathB=1.0},
    {name="Abomination",hp=180, speed=42,  dmg=22, xp=30, dropHp=true,  tex="abomination", size=44, deathR=0.9, deathG=0.5, deathB=0.1},
    {name="Banshee",    hp=70,  speed=85,  dmg=14, xp=20, dropHp=false, tex="banshee",     size=34, deathR=0.9, deathG=0.9, deathB=0.3},
    {name="Lich",       hp=320, speed=38,  dmg=35, xp=60, dropHp=true,  tex="lich",        size=52, deathR=0.2, deathG=0.7, deathB=1.0},
}

-- Boss templates (one spawns every BOSS_EVERY waves, alone)
-- hpMult scales with wave number in Game.lua
WS.BOSS_TYPES = {
    {
        name    = "Kel'Thuzad",
        tex     = "boss_kel",
        size    = 64,
        hp      = 1200,
        speed   = 55,
        dmg     = 40,
        xp      = 300,
        dropHp  = true,
        isBoss  = true,
        deathR  = 0.4, deathG = 0.7, deathB = 1.0,
        -- special: periodically fires a frost nova burst
        special = "frostnova",
        specialCd = 4.0,
    },
    {
        name    = "Nefarian",
        tex     = "boss_nef",
        size    = 64,
        hp      = 1600,
        speed   = 45,
        dmg     = 50,
        xp      = 400,
        dropHp  = true,
        isBoss  = true,
        deathR  = 1.0, deathG = 0.4, deathB  = 0.1,
        -- special: charges straight at player once briefly
        special = "charge",
        specialCd = 5.0,
    },
    {
        name    = "C'Thun",
        tex     = "boss_cthun",
        size    = 64,
        hp      = 2000,
        speed   = 35,
        dmg     = 45,
        xp      = 500,
        dropHp  = true,
        isBoss  = true,
        deathR  = 0.2, deathG = 0.9, deathB  = 0.3,
        -- special: spawns 3 adds
        special = "summon",
        specialCd = 6.0,
    },
    {
        name    = "Illidan",
        tex     = "boss_illidan",
        size    = 64,
        hp      = 2400,
        speed   = 48,
        dmg     = 55,
        xp      = 600,
        dropHp  = true,
        isBoss  = true,
        deathR  = 0.7, deathG = 0.1, deathB  = 0.9,
        -- special: teleports behind player
        special = "teleport",
        specialCd = 4.5,
    },
}

-- Weapon templates
WS.WEAPONS = {
    {
        id      = "orb",
        name    = "Fel Orb",
        desc    = "Orbiting projectile that damages nearby enemies.",
        icon    = "weapon_orb",
        baseDmg = 25,
        cooldown= 0.8,
        projSpeed = 0,
        pierce  = 99,
        aoe     = false,
    },
    {
        id      = "bolt",
        name    = "Shadow Bolt",
        desc    = "Fires a bolt toward the nearest enemy.",
        icon    = "weapon_bolt",
        baseDmg = 35,
        cooldown= 0.7,
        projSpeed = 320,
        pierce  = 1,
        aoe     = false,
    },
    {
        id      = "nova",
        name    = "Void Nova",
        desc    = "Explodes in all directions every few seconds.",
        icon    = "weapon_nova",
        baseDmg = 20,
        cooldown= 3.5,
        projSpeed = 200,
        pierce  = 99,
        aoe     = false,
    },
    {
        id      = "chain",
        name    = "Chain Lightning",
        desc    = "Instantly zaps the nearest enemy and chains to 2 more.",
        icon    = "weapon_chain",
        baseDmg = 40,
        cooldown= 2.0,
        projSpeed = 0,
        pierce  = 3,
        aoe     = false,
    },
    {
        id      = "aura",
        name    = "Fel Aura",
        desc    = "Constant damage pulse to all enemies within range.",
        icon    = "weapon_aura",
        baseDmg = 8,
        cooldown= 0.5,
        projSpeed = 0,
        pierce  = 99,
        aoe     = true,
        range   = 100,
    },
}

-- Passive upgrades
WS.PASSIVES = {
    {id="hp",      icon="passive_hp",       name="Vitality",     desc="+20 max HP, heals 20.",        effect=function(gs) gs.maxHp = gs.maxHp + 20; gs.hp = math.min(gs.hp + 20, gs.maxHp) end},
    {id="speed",   icon="passive_speed",    name="Swiftness",    desc="+15% movement speed.",         effect=function(gs) gs.moveSpeed = gs.moveSpeed * 1.15 end},
    {id="dmg",     icon="passive_dmg",      name="Power",        desc="+20% weapon damage.",          effect=function(gs) gs.dmgMult = gs.dmgMult * 1.20 end},
    {id="cooldown",icon="passive_cooldown", name="Haste",        desc="-15% weapon cooldowns.",       effect=function(gs) gs.cdMult = gs.cdMult * 0.85 end},
    {id="pickup",  icon="passive_pickup",   name="Magnetism",    desc="+50% pickup radius.",          effect=function(gs) gs.pickupRadius = gs.pickupRadius * 1.5 end},
    {id="regen",   icon="passive_regen",    name="Regeneration", desc="Regen 1 HP every 3 seconds.", effect=function(gs) gs.regenRate = gs.regenRate + 1 end},
}

WS.defaultDB = {
    highScore = 0,
    bestWave  = 0,
    totalRuns = 0,
    -- options
    optAutoOpenFlight = false,
    optAutoOpenLogin  = false,
    optAutoCloseFlight = false,
    optAutoCloseCombat = false,
    optSound          = true,
    optSplash         = true,
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
        -- merge in any new defaults without clobbering existing values
        for k, v in pairs(WS.defaultDB) do
            if WicksSurvivorsDB[k] == nil then WicksSurvivorsDB[k] = v end
        end
        WS.db = WicksSurvivorsDB

        SLASH_WICKSSURVIVORS1 = "/survivors"
        SlashCmdList["WICKSSURVIVORS"] = function()
            WS.UI.ToggleMenu()
        end

    elseif event == "PLAYER_LOGOUT" then
        WicksSurvivorsDB = WS.db

    elseif event == "PLAYER_LOGIN" then
        if WS.db and WS.db.optAutoOpenLogin then
            -- delay one frame so UI is ready
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
        -- no action on combat end by default
    end
end)

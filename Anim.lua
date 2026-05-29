-- Wick's Survivors
-- Anim.lua: flipbook animation for sprite strip textures

local ADDON, ns = ...
local WS = WicksSurvivors

-- Frame counts and playback rates for every animated sprite.
-- Static sprites (proj_bolt, proj_nova, proj_chain, all pickups, all icons)
-- are not listed here; SetAnimFrame is a no-op for those keys.
WS.ANIM = {
    player       = { frames = 4, fps = 6  },
    ghoul        = { frames = 8, fps = 10 },
    wraith       = { frames = 8, fps = 8  },
    abomination  = { frames = 8, fps = 7  },
    banshee      = { frames = 8, fps = 9  },
    lich         = { frames = 8, fps = 7  },
    boss_kel     = { frames = 4, fps = 6  },
    boss_nef     = { frames = 4, fps = 6  },
    boss_cthun   = { frames = 4, fps = 8  },
    boss_illidan = { frames = 4, fps = 7  },
    proj_orb     = { frames = 8, fps = 14 },
    proj_aura    = { frames = 8, fps = 12 },
}

-- Set the UV coords on texObj to show the correct animation frame.
-- key    : matches a WS.ANIM entry (e.g. "ghoul", "player")
-- phase  : 0-1 offset so pooled frames don't all sync together
function WS.SetAnimFrame(texObj, key, phase)
    local a = WS.ANIM[key]
    if not a then
        texObj:SetTexCoord(0, 1, 0, 1)
        return
    end
    local n   = a.frames
    local idx = math.floor(GetTime() * a.fps + (phase or 0) * n) % n
    local l   = idx / n
    texObj:SetTexCoord(l, l + 1 / n, 0, 1)
end

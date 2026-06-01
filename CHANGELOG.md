# Wick's Survivors -- Changelog

## 0.3.0 -- 2026-05-31

Brings the addon to parity with the standalone Wick's Survivors desktop build.

### Added

- Biome system: four rotating zones (Frozen Crypt, Ember Caldera, Eldritch Deep, Fel Wastes), six waves each. The arena background retints per biome.
- Biome-tinted enemy reskins and biome-unique foes: frost revenant, frostling, magma hound, cinder wisp, deep spawn, gazer, fel imp, wrathguard.
- Enemy archetypes: armor, recharging shields, ranged shooters, and faster swarm types.
- Four distinct boss fights with signature specials -- Kel'Thuzad (frost nova), Nefarian (shadowflame), C'Thun (eye beam), Illidan (fel dash) -- each with an empowered phase that swaps art and tightens its special timer below 40% HP.
- New weapons: Soul Scythe (orbiting blades), Meteor (AoE strike), and Dreadhound (autonomous pet that hunts foes).
- Fel Bolt now renders as green forking lightning (matching the desktop build), and Void Tendril upgrades make your bolts fork through nearby enemies on hit.
- Fel Explosion fireballs (now fel-green, not arcane) split into shards on first hit.
- Twin Bolts multishot.
- New passives: Dark Pact (flat damage), Void Ward (armor), Soul Hunger (lifesteal), Swiftness (projectile speed).
- New power-up pickups: Haste, Rage, Shield, Magnet, and double-XP motes.
- Stacking-rank upgrade model: each upgrade has a rank cap, and level-up cards show rank pips.

### Changed

- Waves now advance when the arena is cleared (with a safety cap), matching the desktop build, instead of on a fixed timer.
- Player is faster than the swarm again; enemy speeds rebalanced so you can always kite.
- All sprites re-exported from the standalone art kit (74 TGAs incl. reskins and empowered bosses, plus biome floors and props). Non-power-of-two strips are padded and oversized strips downscaled to stay within the client's texture limit so animation stays crisp.

## 0.2.0 -- 2026-05-29

### Added

- Animated title splash screen plays before the main menu on first open each session.
- Sprite scene on the splash: C'Thun looming above, flanking bosses, horde silhouettes, and Wick front-and-centre -- all flipbook-animated.
- Fel bloom, corner brackets, and a dark scrim layer the scene atmosphere.
- Six audio cues: reveal swell, impact boom, shimmer, menu chord, creature snarls, and a 32s seamless ambience loop (plays on SFX channel).
- Options panel (accessible from the main menu): Auto-Open on flight start or log-in, Auto-Close on flight end or combat, sound toggle, splash toggle.
- Closing the menu or typing /survivors again now dismisses the splash immediately.
- All glow textures switched to additive blend mode -- death bursts, projectile glows, and pickup glows no longer show as opaque blocks.

## 0.1.0 -- 2026-05-28

### Added

- Initial release. Vampire Survivors-style wave survival minigame for TBC Classic Anniversary.
- 5 auto-firing weapons with unlock and upgrade trees.
- Passive upgrades: lifesteal, move speed, area, cooldown reduction, and more.
- Boss waves every 6 rounds featuring scaled TBC encounters.
- Obsidian Glass skin included as an alternate full-art reskin.
- Drag-to-move frame, position saved per character.

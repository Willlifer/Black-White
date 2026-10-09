# Cast and spectacle VFX, hit feel (D167–D170)

The B/W rule holds: the element colour is the only hue. Every effect is white
body + black ink + the element colour, alpha-blended ("over"), never additive
(additive vanishes on white tiles). Effects are children of the combat screen
(`BWVfxCasts`), not the board, so the cutscene dim never touches them.

Files: `src/game/combat/vfx_casts.gd` (BWVfxCasts), `src/game/combat/hit_feel.gd`
(BWHitFeel), `shaders/vfx_ground.gdshader`, `vfx_column.gdshader`,
`vfx_particle.gdshader`, `vfx_ribbon.gdshader`. Review:
`RES=1600x900 SHOTS=<dir> [MODE=…] godot --path . --script res://tools/vfx_shots.gd`
then `python tools/vfx_strip.py <dir>` → `design/art/casts_*.png`.

## How much plays (weight)

| D122 tier | VFX weight |
|---|---|
| MINIMAL (and every event in the Minimal mode) | none (hit feel only) |
| SHORT, non-staff | circle flash + release, no converge |
| SHORT staff skill, any FULL | casting circle + converge on the staff head + release |

Staff skills are cd 2 (SHORT) under D122, but the author singled out Surge and
Ley Line, so staff casts play full whenever they get a cutscene. The Fast mode
drops one tier (Surge → MINIMAL tier → none); setup beats (Ley Line, War Cry,
Siphon: MINIMAL by tier) follow the mode directly: Default full, Fast reduced,
Minimal none. Hold-to-skip runs it all at ×4 (every timeline is game time), the
hit-stop and the final-KO slow-mo are skipped while skipping.

## Casts

- **Casting circle** (ground, r 1.45): white ground at 32 %, an ink outer ring,
  an element ring, a counter-rotating band of ink runes on white, a turning
  hexagram in the element, six inked nodes. Draws itself on round the clock in
  0.2 s, holds through the release, fades.
- **Converge** (FULL): 34 motes spiral onto the weapon tip (tracked live) over
  the windup; a four-point gleam at the tip as it closes.
- **Releases** (Y-billboarded quads standing on the target, + a ring, + particles):
  fire column of flame · water geyser that falls back · ice seven faceted spikes
  that shatter · thunder bolt from above with a ground flash · wind cyclone
  funnel with a spinning ground crescent · light hard-edged pillar · dark sphere
  that swells, implodes and rings out (its hit is the collapse, 0.7 s).
- **Surge**: the six ring hexes flare, their charge streaks into the centre,
  then a ×1.4 release and a 3-hex shockwave there. The release **engulfs** the
  unit on the centre hex (D388): each element's column drawn as a back shell
  0.85 behind the unit and a front shell 0.85 before it (`vfx_column` `push`),
  the front one's fills cut to 30% with its ink kept (`veil`), so the unit
  stands inside a translucent, inked column. Water is widened; thunder is a
  pillar with the bolt through it; dark keeps its sphere. Renders
  `vfx2_surge_*.png`.
- **Ley Line**: the line races out hex by hex (0.1 s/hex): an inked strip in
  the element, each hex laid with a flash and a ripple, motes; a second ring
  pulse runs the laid line (the travelling wave); allies on it flash and float
  "▲ +1 MOVE" in the element colour.
- **Saturate**: a stream pours from 6.5 above with droplets, splashes out.
- **Siphon**: whatever the hex shows (its fire/water and light/dark layers) rises
  out of it and streams into the caster's staff, which flashes.
- **Bolt**: a quick orb (≤ 0.3 s) with a trail, a burst on arrival.

## Spectacles

- **Tempest**: storm clouds (a swirling inked cloud annulus, element flickers)
  gather 5.2 above the area during the windup; the element then strikes all 19
  hexes, staggered over ~1.4 s, the victims' hexes together on the impact; a
  5-radius shockwave.
- **Dragoon Dive**: wind-up, dust; the lancer leaps 16 up out of frame; an ink
  shadow with a white rim and reticle ticks grows on the landing hex; a 0.13 s
  drop; crash: two rings, a flash, grey + element debris shards, dust, shake.
- **Hundred Fists**: each strike leaves four stick-figure afterimages (inked
  white strips along the skeleton, striking arm in the element) fading over
  0.28 s, and three impact flashes round the target.
- **Empty the Chamber**: four shots on the clip's four recoils (`strike_chamber`,
  `release`..`release4`, D389), a muzzle flash and a tracer each, swept her
  right to her left in bearing order; each target reacts to its own shot.
- **Whirlwind Blade / Fan of Knives**: a tapered ribbon swept behind the blade
  tip from launch to hit (white, ink rims, the element; D389) over two
  sweeping ground crescents. Fan of Knives flings a real spinning dagger at
  every ring hex (`BWRangedVFX.fan`, D387), each released as the blade sweeps
  past it; they stick in chests or the ground briefly, flash and lay the
  element; each victim reacts on its own knife.
- **The fists' jab**: an impact star at the chin on a hit (D389).
- **Elemental Truth**: two releases on the target, 0.17 s apart, the second full size.
- **War Cry**: two ground shockwaves, shout rings round the head, an aura of
  rising rings (Default) and sparks.
- **Triumph**: the windup holds 0.4 s longer with a gleam on the blade and dust.

## Hit feel (D170)

- Shake = 0.018 + 0.30 × (damage / max HP), ×1.3 on a crit, capped 0.14
  (the old fixed crit shake was 0.12). One shake per blow event (the biggest).
- Hit-stop: ≥ 20 % of max HP → 0.045 s, ≥ 35 % → 0.075 s, at time scale 0.03.
  A landed crit always stops: 0.1 s on FULL, 0.045 s otherwise (D530). Never in Minimal / while skipping.
- **Crit flash (D530, amends D101):** the flash plays the moment BEFORE the
  attacker's animation starts (after the camera settles and the callout), not
  on the impact frame: FULL's white-out with its freeze, else the tiny pulse;
  group turns none. One flash per blow; a multi-hit clip's later crit flashes
  0.14 s before its own hit marker. The sting (`crit_flashed`) is a glint and
  a rising whoosh; the crack is the impact's `hit_crit`.
- Numbers: font 34 → 74 by √(share / 0.4); a crit ×1.3; cap 96; a miss 30.
  They pop in from 1.25–1.75× scale.
- Final knockout (the rules ended the fight and no later blow KOs anyone):
  time ×0.25 for 0.85 s (Fast 0.47 s), the camera FOV pushes to 80 % and the
  pivot 35 % toward the fallen, then back. None in Minimal / while skipping.
- Settings → Combat → **Screen shake** (default on) gates every shake.

## Playback order (D390)

Wind that draws in plays its motion before the hit; wind that pushes out
plays the hit first. The rules already order skills that way; the screen's
`BWWindOrder.hoist` moves a Vortex basic's pull and a Vortex field fired by
the blow's paint in front of the blow (`test_wind_order`). A knockback
reaction never plays on a blow that more blows on the same target follow (a
flinch there; the last blow keeps it).

## Budget

One MultiMesh of 768 particles (one draw call, the instance buffer written once
a frame from packed arrays), pooled quad / disc / ribbon nodes per kind; each
shader is a few dozen ALU ops, no textures. Tempest measured: see D170.

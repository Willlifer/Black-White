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
  then a ×1.4 release and a 3-hex shockwave there.
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
- **Empty the Chamber**: muzzle flash + tracer per shot, swept in bearing order
  across the targets with strays between them (0.065 s apart).
- **Whirlwind Blade / Fan of Knives**: two sweeping crescent rings (waist,
  knee) through the spin; Fan adds twelve knife sparks outward on the hit.
- **Elemental Truth**: two releases on the target, 0.17 s apart, the second full size.
- **War Cry**: two ground shockwaves, shout rings round the head, an aura of
  rising rings (Default) and sparks.
- **Triumph**: the windup holds 0.4 s longer with a gleam on the blade and dust.

## Hit feel (D170)

- Shake = 0.018 + 0.30 × (damage / max HP), ×1.3 on a crit, capped 0.14
  (the old fixed crit shake was 0.12). One shake per blow event (the biggest).
- Hit-stop: ≥ 20 % of max HP → 0.045 s, ≥ 35 % → 0.075 s, at time scale 0.03.
  Not on a FULL crit (D101 already froze) nor in Minimal / while skipping.
- Numbers: font 34 → 74 by √(share / 0.4); a crit ×1.3; cap 96; a miss 30.
  They pop in from 1.25–1.75× scale.
- Final knockout (the rules ended the fight and no later blow KOs anyone):
  time ×0.25 for 0.85 s (Fast 0.47 s), the camera FOV pushes to 80 % and the
  pivot 35 % toward the fallen, then back. None in Minimal / while skipping.
- Settings → Combat → **Screen shake** (default on) gates every shake.

## Budget

One MultiMesh of 768 particles (one draw call, the instance buffer written once
a frame from packed arrays), pooled quad / disc / ribbon nodes per kind; each
shader is a few dozen ALU ops, no textures. Tempest measured: see D170.

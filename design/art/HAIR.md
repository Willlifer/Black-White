# Hair archetypes (v2)

Hair is the one place a character carries colour. Each style is one
swappable mesh on `socket_hair`, unlit, tinted by the unit's element.

| File | What | Edit? |
|---|---|---|
| `game/tools/blender/build_hair.py` | builds all 10 styles (and their variant 1) from nothing | **yes, this is the source** |
| `game/art/hair/<style>.glb`, `game/art/hair/alt/<style>.glb` (+ `.import`, LODs/shadow meshes/tangents off) | runtime meshes (variant 0 / variant 1), plus hair bones on long styles | generated (the `.import` files by hand) |
| `game/art/source/hair.blend` | working file, one collection per style and per variant | generated, don't hand-edit |
| `game/src/game/character/hair.gd` | `BWHair`: load, variant, tint, attach, pose the tail bones | yes |
| `game/shaders/hair.gdshader`, `hair_outline.gdshader` | unlit fill/shade/shine, same-hue hull contour | yes |
| `game/tests/test_hair.gd` | roster coverage, attach/swap, bones, slots, shine, budget, face window, every variant, variant seeds, cap clearance | yes |
| `game/tools/hair_preview.gd` | Godot renders with the real shaders | yes |
| `design/art/hair_*.png` | renders (below) | generated |

## Diagnosis: why v1 read as "bucket hat" and "coconut"

The v1 renders (left half of `hair_before_after.png`) missed the reference
panels for one root reason: **every crown was a single smooth shell**
(`cap()`), a hemisphere offset from the skull by a constant or slowly
varying amount. Every symptom came from that one shape:

- **Smooth dome silhouette.** Nothing broke the outline above the ears, so
  buzzed, bob, ponytail and high_and_tight read as solid helmets. Buzzed
  was the head in colour: a coconut.
- **A straight hem.** The shell ended in one continuous rolled lip at the
  hairline. Across the forehead that lip reads as a hat brim.
  high_and_tight's flat-topped block made it a bucket hat, and the bob's
  lip made it a mushroom cap.
- **Uniform thickness, no parting, no lock tips.** The panels draw hair as
  separate locks with pointed or rounded ends, a parting or whorl, lifted
  volume at the crown and a tapered nape. The v1 crowns had none of these.
  Only the curtains of the long styles had tips, and only at the hem.
- **No shine.** The panels' white highlight streaks were never built.
- **Same-style characters were identical**, and the roster puts every style
  on two characters.

v2 fixes the root cause: the crown is built from locks instead of a shell.

## How v2 is built

- **Lock crowns.** `fan()` grows one flat, tapered lock from a whorl or a
  parting to each tip. Each lock comes from `strand()` and is a six-sided
  tube about three times wider than it is deep. A lock:
  - lifts off the head in the middle (`volume`)
  - kicks its tip out (`flick`)
  - swirls (`bend`)
  - ends at an uneven length (`jag()`, a fixed, non-repeating pattern)
  - tapers to a point (`sharp`)

  Roots taper into the whorl, so the crown reads as a swirl and not a
  stem.
- **Hanging locks.** `drape()` makes a lock that follows the head down to a
  leave line and then falls. It can belly out, flare, sway, tuck its end
  under and gather toward the spine.
- **A thin scalp underneath.** `cap()` is kept from v1, but now it only
  fills the gaps between locks. Its hem either sits under lock tips or is a
  flush, wobbling hairline (`wobble()`, with `nape_v()` for a pointed
  nape). It never forms a lip.
- **Designed fringes.** Every style except the buzzed crop and the
  high_and_tight top gets one:
  - swept: bob, mullet, ponytail
  - a swoop: waterfall
  - curtain bangs from a centre part: long_hair, long_ponytail
  - C-curls: ringlets

  `strand()` stops every fringe tip at theta 79 over the face window
  (`BROW_THETA`), so the face-window test can't fail.
- **Clean fills.** A v2 lock shades only the face that points at the head
  (`under=True`). The same-hue hull draws the lock edges, plus the strand
  lines wherever locks overlap, the way the panels draw them.
- **Shine.** The `hair_shine` slot is an "angel ring": a band across the
  crown at theta 18–42.
  - It sits in three arcs: the front and one on each back quarter.
  - It covers the outer faces of the locks it crosses, so the lock edges
    break it into separate streaks.
  - It takes 4.6–7.5% of each style's fill area (the `shine` column in the
    build output).

## Rebuild

```
blender -b --factory-startup --python game/tools/blender/build_hair.py            # all + variants + .blend
blender -b --factory-startup --python game/tools/blender/build_hair.py -- --only bob,mullet
cd game
godot --headless --path . --import
godot --headless --path . -- --self-test
godot --path . --resolution 1600x900 -s res://tools/hair_preview.gd   # windowed; -- --only heads_ | variants | combat
```

The build is deterministic: there is no randomness, and every lump, wave
and tip comes from a closed-form function. Two builds produce byte-identical
glbs. The .blend is not byte-stable, but it wasn't in v1 either, because
Blender stamps the file.

Each style and each variant (for example `bob@1`) prints a `STYLE` line
with:

- triangles, shade share and shine share
- crown rise, islands and bones
- z-range and head clearance
- face-window hits
- the worst body clearance under head yaw ±30° and pitch/roll ±15°

The build prints `WARN` if a style enters the head or the face window, or
clips the body under yaw.

## Usage

```gdscript
var hair := BWHair.create(row.hair_style, row.element, BWHair.variant_for(row.id))   # null + error if unknown
hair.attach_to(rig)              # on socket_hair; replaces (frees) any hair already there
hair.set_element("ice")          # recolour in place; or set_color(Color)
hair.set_tail_rotation("hair_tail_02", Vector3(0.3, 0, 0))   # follow-through, +X = tip forward
BWLook.set_dim(rig, 1.0)         # fades hair with the figure (same `dim` contract)
```

`BWHair` also provides:

- `styles()`, `has_style()`, `path_for(style, alt)`, `variant_for(id)`
- `tail_bone_names()`, `reset_pose()`
- `triangle_count()`, `get_aabb()`
- `set_contour(same_hue, width)`
- the static `material_for(role)`, where the role is `hair`, `hair_shade`
  or `hair_shine`

## Variants (`hair_variant`)

Two characters with the same style never look identical:

- **Two meshes per style.** Each style is built twice:
  - `art/hair/<style>.glb` is variant 0, the style function's defaults.
  - `art/hair/alt/<style>.glb` is variant 1, set in the build script's
    `VARIANTS`. It changes the part side, sweep, volume, lock count, tip
    sharpness or length.

  Bone names and counts are the same in both meshes.
- **A seed per character.** `BWHair.variant_for(id)` derives a seed from 0
  to 7 from the unit id (FNV-1a, then a murmur finaliser, over
  `"hair79:" + id`). Its bits:
  - 1 picks the alt mesh.
  - 2 mirrors the hair left to right.
  - 4 widens it by 4% in x and z. Height is untouched, so hat clearance
    doesn't change.

  The salt was chosen so that all ten same-style pairs in the roster get
  different meshes (`test_variant_seed` checks this). Seven of the ten
  pairs also differ in mirroring.
- **Where it lives.** `BWCharacter.look_for()` puts the seed in the look as
  `hair_variant`. `cosmetics` can override it, and it is never stored in
  roster.csv.
- **Render.** `hair_variants.png` shows variants 0–3 of every style.

## Frame and fit

Socket space of rig v1: the origin is the head centre (world 1.92). In
Blender, Z is up, the character faces −Y and its left is +X; in Godot, Y is
up and it faces +Z. The head is the ellipsoid 0.31 × 0.295 × 0.28.

- **Lock inner faces sit about 0.042 off the head**, outside the head's
  0.026 black hull, so the head line never pokes through. Only buried
  roots (mohawk spikes, ringlet curls) come closer.
- **The face window stays clear.** No vertex sits in front of the face
  (z > 0.12 in Godot) within |x| < 0.20 and below world 1.95.
  - Fringe tips over the window stop at theta 79.
  - Face-framing locks hang outside |x| 0.20.
  - `test_hair` checks every vertex of every variant, including the
    mirrored and widened ones.
- **Napes reach theta ≈ 120–142°** and taper to a point, so the back of the
  head is covered.
- **Body clearance.** It is checked against clothing-inflated capsules
  (torso r 0.12, neck 0.06, sleeves 0.075 and 0.07) in the A-pose. Every
  style and variant clears them at rest and under head yaw ±30° (rendered
  in `hair_turns.png`). Long sheets and locks narrow toward the spine as
  they fall (`gather`).

## Colour and shade

- **Three material slots, one vertex colour.** Every vertex has COLOR 1.0,
  neutral white. The material slot does the work instead:
  - `hair`: the fill, in the element colour (`BWLook.element_color`).
  - `hair_shade`: the same hue at value 0.62 (perceptual) with +15%
    saturation. It covers:
    - the inside of every shell
    - the face of every lock that points at the head
    - stubble and fades on the shaved styles
    - the hair ties
    - the strand lines down the curtains
  - `hair_shine`: the highlight streaks. The fill is mixed 86% toward white
    by `BWHair.SHINE`, which drives the material uniform `shine`. The
    instance slots are unchanged.
- **Contour.** An inverted hull, 0.024 wide, at value 0.36 of the same hue
  (D52). Each lock is a separate island, so the hull also draws a strand
  line wherever one lock overlaps another.
- **One per-instance `tint`** drives the fill, shade, shine and contour.
  All hair of every element shares three materials and one outline.
  - `dim` follows the cutscene fade.
  - Instance slots are pinned to the project scheme: dim = 0, tint = 1.

## Rank colour (D146–D148)

Hair colour follows the unit's affinity ranks. The element colour is
always the majority; rank shows as contrast streaks that thin out with
mastery. `BWLook.hair_gradient(affinity, focus)` returns a Gradient over the
hair's root (0) → tip (1): rgb is the hair colour, alpha the contrast
streaks (`BWLook.streak_alpha`: 0.5 none, above = light streaks, below =
black streaks, |a − 0.5| × 2 = share of locks).

| Ranks | Look |
|---|---|
| none | unaligned mid grey |
| 1 | element colour, ~30% of locks in contrast streaks |
| 2 | element colour, ~12% contrast streaks |
| 3+ | solid element colour |
| 2+ elements | ombré over the element colours: weakest at the root, strongest at the tips, band length ∝ rank (ties → focus, then data order); half the streaks |

Streak colour by relative luminance (`HAIR_STREAK_LUM` 0.19): dark, thunder
and water get light-grey streaks; fire, wind, ice and light get black. The
same threshold lifts the contour of dark colours toward white so they keep
a silhouette on the black sky.

- Runtime: `BWHair.set_affinity(unit.affinity, unit.focus())`; `set_element` /
  `set_color` still give a solid colour (previews, swatches).
- Root→tip and lock azimuth are baked into vertex COLOR once per glb mesh
  (`BWHair._baked`, D147). Tunables: `SKULL_R`, `REACH`, `DROP_CURVE`,
  `LOCK_SHARE` in hair.gd; `HAIR_STREAKS`, `HAIR_MIX_STREAKS`, `HAIR_BLEND`,
  `HAIR_STREAK_LUM`, `HAIR_NONE` in look.gd; `streak_cells` in hair.gdshader.
- `BWCharacter.refresh_hair()` re-reads the unit at build, refresh, pose and
  set_wounded (D148).
- Review: `godot --path game --resolution 1800x1250 -s res://tools/hair_ranks_preview.gd`
  → `hair_ranks_front.png`, `hair_ranks_back.png`, `hair_ranks_combat.png`,
  `hair_ranks_combat_zoom.png`; roster screen at seed 1 → `hair_ranks_roster.png`.

## Archetypes

The triangle counts are variant 0 / variant 1. Rise is the crown height
that `BWEquipmentView.hair_rise` compares with a hat's `hair_clearance`:
baseball cap 0.10, feathered cap 0.13, beret 0.15, wizard hat 0.22.

| Style | Tris | Bones | Rise | Look |
|---|---|---|---|---|
| `buzzed` | 1848 / 1704 | 0 | 0.08 | Textured crop. 15 short tufts swirl from a crown whorl, their tips flicked up into a spiky outline and a choppy, high fringe. Dark fade on the lower sides and a pointed nape. Fits under a cap. |
| `high_and_tight` | 1992 / 1848 | 0 | 0.10 | Spiky top over tight sides. 13 locks kick up and out from the whorl, tallest at the front as a messy quiff. Below them, a short band and then a dark fade. The lifted top over the flat sides is the step. Fits under a cap. |
| `mullet` | 3080 / 2720 | 0 | 0.11 | A parted, choppy crown with a fringe swept off the part. The party is two layers of pointed locks down the neck that flare and sway. |
| `short_mohawk` | 1380 / 1284 | 0 | 0.31 | Burst fade: stubble only in a strip under the fin and down the nape, with the white skull bare on the sides. Eight tapered blade spikes curve back. |
| `bob` | 3044 / 2780 | 0 | 0.10 | A layered bob from a side part. 14 locks round out over the sides and tuck their ends under. Swept, pointed fringe and longer face-framing front locks. Fits under a cap. |
| `ponytail` | 3900 / 3900 | 2 | 0.08 | Low tie. 22 locks pull from the hairline to the tie, and every other one is raised so the hull draws the tension lines. Side-swept fringe, temple tendrils, and a tail of three locks that fan apart. |
| `long_ponytail` | 3942 / 3942 | 3 | 0.09 | High tie with tension lines up the back, a curtain fringe from the part, tendrils, and a three-lock tail that arcs up and then falls to the waist. |
| `waterfall` | 3952 / 3808 | 3 | 0.11 | Deep side part. A lock crown, a four-lock swoop across the brow, and two long locks down the far cheek. A short, flicked layer at the shoulders sits over the long, rippling under-layer. |
| `ringlets` | 4448 / 4040 | 2 | 0.13 | A crown of hooked C-curl locks with round ends, so the outline is lumpy and never smooth. Curly fringe and ten corkscrews to the shoulders. The heaviest style. |
| `long_hair` | 4036 / 3892 | 3 | 0.09 | Centre part. A lock crown, curtain bangs, face-framing locks to the collarbone, side panels, and a waist-length curtain overlaid with staggered, pointed locks. |

The roster uses all 10 styles, two characters each, and the two always get
different variants.

## Bones

The long styles carry their own small skeleton inside the glb. It rides the
head socket, so the base rig is untouched. Bone names and counts are the
same as in v1 and the same in both variants:

```
hair_root            (0,0,0) up; everything above the tail is 100% on it
└ hair_tail_01 → 02 → 03   chained down the tail / curtain
```

- **Weights are by height.** Each vertex goes to the bone whose span
  contains its z, with ±0.07 linear blends at each joint.
- **The rigid parts** (crown and fringe) are all on `hair_root`.
- **Rolls follow the rig convention:** local Z forward, and **+X pitches
  the tip forward**. Mirroring with the variant's −1 x scale leaves pitch
  unchanged.
- **No animations yet.** Follow-through can be keyed in `hair.blend`, or
  driven at runtime with `set_tail_rotation()`, for example with a spring.

## Adding a style

1. Write a function in `build_hair.py` with named shape parameters. Use the
   shared knobs (`part`, `sweep`, `volume`, `locks`, `sharp`) where they
   apply, and give the style a variant-1 entry in `VARIANTS`. The
   primitives:
   - `cap(edge, off, ...)`: a closed shell from the crown to a hairline,
     used as a gap filler. Options: rounded lip, flat top (`z_flat`),
     stubble (`shade_rows=0`), fades (`shade_fn`), strand bands.
   - `curtain(phi0, phi1, ...)`: a hanging sheet with a scalloped hem,
     wave, flare, gather and strand lines.
   - `lock(pts, w, h, ...)`: a tapered tube. Options: `sharp`, `shine`
     segments, `under` shading.
   - `blob(...)`: ties and puffs.
   - v2 helpers:
     - `strand(a, b, ...)`: a lock lying on the head.
     - `drape(a, phi, leave, z_end, ...)`: a lock that lies on the head,
       then hangs.
     - `fan(whorl, tips, ...)`: a rosette of locks.
     - `_tension()`: ponytail pull lines.
     - `jag()`, `wobble()`, `nape_v()`, `SHINE_BAND`.

   Return `(mesh, None)` for a rigid style, or `(mesh, joints)` for a style
   with hair bones (n joints make n−1 tail bones).
2. Add it to `STYLES`, then build. Fix any `WARN`, and check the `shine`
   (aim for 4–8%) and `rise` columns.
3. Add it to `BWHair.TAIL_BONES` and to the `hair_style` list in
   `design/SCHEMA.md`.
4. Run `--import`. Copy the `.import` settings of an existing style (LODs,
   shadow meshes and tangents off, no animation) into both new `.import`
   files (`art/hair/` and `art/hair/alt/`). Delete their `.godot/imported`
   entries and import again.
5. Run the self-test and `hair_preview.gd`, then look at the renders.

## Renders

- `design/art/hair_closeup_{front,34,back}.png`: 10 styles × fire / ice / dark, orthographic, on paper.
- `design/art/hair_detail_{front,34}.png`: larger, one element per style.
- `design/art/hair_heads_{front,34,back}.png`: head-and-shoulders close-ups, for judging the read up close.
- `design/art/hair_variants.png`: hair_variant 0–3 of every style (plain, alt, mirrored, alt + mirrored).
- `design/art/hair_combat_{front,34,back}.png`: the combat camera (24 u, FOV 34, 42°), hexes, starfield.
- `design/art/hair_turns.png`: head yaw −30° / +30° from behind (clipping).
- `design/art/hair_before_after.png`: v1 against v2 (heads from three sides, roster turntable, roster screen).

## Decisions I made

1. **Material slots instead of vertex channels for shade and shine.**
   - Surfaces split cleanly per face, with no gradients across shared
     verts.
   - The glb stays readable in any viewer.
   - The shader only multiplies a value or mixes toward white.
   - Vertex COLOR stays a neutral 1.0.
2. **Same-hue darker contour (D52), not black.** It's how the reference
   panels draw hair, and it separates hair from the black head line and the
   limbs.
3. **Strand lines come from geometry.** Locks are separate islands, so the
   hull draws lines where they overlap. No textures.
4. **Own skeleton per long style**, rather than adding bones to the base
   rig. Rig v1 and every other lane stay untouched.
5. **Short styles are rigid meshes** with no skeleton. The mullet stays
   rigid because it ends at the shoulders.
6. **Unlit, opaque, depth-sorted** (no ALPHA write), like `flat_opaque`.
7. **v2: locks, not shells.** The crown is a fan of separate lock islands,
   and the shell survives only as a thin gap filler. Building from locks is
   the change that removed both the dome and the hem; adjusting the shell
   did not.
8. **The shine sits on the crown geometry** as an angel-ring band, so the
   lock edges break it into streaks at no extra cost. That matches the
   broken white patches in the panels.
9. **Mohawk sides are bare skull** (a burst fade). v1's all-over stubble
   dome read as a helmet with a fin. A white skull with a coloured strip is
   the classic mohawk read. The other shaved styles keep a coloured fade.
10. **Variants are prebuilt meshes plus a mirror,** not runtime mesh
    deformation. They cost one extra glb per style, bones and budgets can be
    checked offline, and the mirror costs nothing.
11. **Short styles stay under a baseball cap.** buzzed, high_and_tight, bob
    and ponytail have a rise ≤ 0.10 in both variants, and a test checks it,
    so a cap never leaves them bald. The mohawk is still hidden under a cap.

## Known gaps and open items

- **The low `ponytail` from straight behind** still reads a little like a
  wrapped cap. The upper back is smooth, and the tension lines show mostly
  near the tie. A few strand bands down the upper back would help.
- **Small triangular gaps between fringe roots** on the side-parted styles
  (ponytail, bob) show the scalp's outline in the front view. They're
  harmless, but a filler lock could close them.
- **The alt variants differ only slightly by design.** At combat distance
  the mirror is the most visible difference.
- **No secondary motion yet.** Tail bones only follow the head rigidly
  until animation poses them. Bone names are unchanged from v1.
- **Head pitch back past ~15°** makes waist-length hair swing into the
  back. The tail bones exist for that; counter it in animation.
- **Clearance assumes clothing** no thicker than the `fit_body` proxy. The
  scarf (`sweater_scarf`) and chest armour aren't checked against long
  hair.
- **Hats.** A helmet hides the hair node (RIG.md), and there are no per-hat
  trimmed variants yet. Under the baseball cap, mullet, waterfall and
  ringlets (rise 0.11–0.13) are hidden, as the tall styles were in v1, and
  so is long_hair's variant 1 (0.108). Variant 0 of long_hair (0.094)
  stays visible.
- **`ringlets` is the heaviest style** at 4448 tris, against a budget of
  4500. Drop `curls` or `locks` before adding anything to it.

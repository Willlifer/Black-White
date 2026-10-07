# Clothing (v1)

Fourteen greyscale garments that any figure on the base rig (`RIG.md`) can
wear, each in a dark, mid or light shade picked by the roster's `clothing_shade`.

| File | What | Edit? |
|---|---|---|
| `game/tools/blender/build_clothing.py` | builds every garment, the palette and the working file | **yes, this is the source** |
| `game/art/clothing/<id>.glb` | one skinned garment each, 20 rig bones (+ `scarf_tail` on sweater_scarf) | generated |
| `game/art/clothing/<id>.glb.import` | import settings: no LODs, no shadow meshes, named skins, no animation | written once by the build, then by hand |
| `game/art/clothing/clothing_palette.png` | 3×3 palette: fill / fold / contour per shade | generated |
| `game/art/source/clothing.blend` | working file: rig, `fit_body`, every garment with its weights | generated, don't hand-edit |
| `game/src/game/character/clothing.gd` | `BWClothing`: wear / remove / shade at runtime, plus the scarf sway | yes |
| `game/shaders/clothing.gdshader`, `clothing_outline.gdshader` | fill and contour | yes |
| `game/tests/test_clothing.gd` | roster coverage, binding, bone names, materials, budget | yes |
| `game/tools/clothing_preview.gd` | Godot renders with the real shaders | yes |
| `design/art/clothing_*.png` | the renders listed under Verification | generated |

## Rebuild

```
blender -b --factory-startup --python game/tools/blender/build_clothing.py                 # all; fails on clipping
blender -b --factory-startup --python game/tools/blender/build_clothing.py -- --only hoodie,shorts
blender -b --factory-startup --python game/tools/blender/build_clothing.py -- --allow-clip  # export anyway
cd game
godot --headless --path . --import
godot --headless --path . -- --self-test
godot --path . --resolution 1600x900 -s res://tools/clothing_preview.gd    # windowed; -- --only tops_front,closeup
```

The build reads `base_rig.blend` and never writes it. It prints `STATS`
(triangles, vertices, bone groups), one `CLIP` line per garment, a `LAYER`
line, and `CLIP_FAILURES`. It exits 1 if any contour point is exposed (see
Weights). It is deterministic: two runs give byte-identical glbs.

## The garments

| id | slot | tris | silhouette | key parameters |
|---|---|---|---|---|
| `baggy_sweatpants` | bottom | 1004 | balloon legs, ankle cuffs, drawstrings | offset .016, bag .050 @ s .58, splay .035, cuff .045 |
| `sweatpants` | bottom | 1004 | relaxed legs, ankle cuffs, drawstrings | offset .012, bag .022, cuff .040 |
| `tight_pants` | bottom | 896 | close, slight boot flare | offset .008, seat .014, flare .006 |
| `ripped_tight_pants` | bottom | 1008 | tight_pants + 7 ink rips (thighs, knees, shin) | as tight_pants, `RIPS` table |
| `tight_shorts` | bottom | 368 | bike shorts, mid thigh | hem s .25, slant .05 |
| `shorts` | bottom | 512 | loose, above the knee, inseam notch | offset .020, hem .36, flare .010, slant .13 |
| `short_shorts` | bottom | 272 | high cut | hem .17, slant .045 |
| `tank_top` | top | 304 | scoop neck, armholes, two straps | hem z .94, offset .020, flare .016 |
| `crop_top` | top | 340 | boat neck, cap sleeves, cropped at z 1.20 | sleeve s .075 |
| `tshirt` | top | 580 | crew collar, short sleeves | sleeve .17, s_flare .018 |
| `sweater` | top | 1092 | ribbed collar, hem band, cuffs | offset .030, bag .010, sleeve .675 |
| `sweater_scarf` | top | 1326 | sweater + scarf loop and a swinging tail | + `scarf_tail` bone |
| `hoodie` | top | 1424 | hood down, strings, kangaroo pocket, hem band, cuffs | offset .036, bag .016 |
| `crop_hoodie` | top | 1280 | hoodie cropped at z 1.19, no pocket | |

The body is 2816 triangles, so a dressed figure stays under 4.3k. The budget
in the test is 1600 per garment.

Shape language follows the reference panels: flat shapes, bold contours,
one fold line where a real garment has a seam or band (waistband, cuffs,
hem bands, collars, the pocket, the hood opening, the scarf stripes).
Nothing is modelled smaller than about 1 px at the combat camera (24 u, FOV
34, where 1 px is about 0.016 u).

## Parameters

Every garment is one dict in `BOTTOMS` or `TOPS` at the top of the script.
Radii are **measured from `fit_body` at build time** (its torso rings and its
limb sleeves), then grown by the parameters, so a rig change carries
through. `s` is the distance along a limb from the hip or shoulder (knee at
s .42, ankle .865; elbow .36, wrist .69). Torso heights are world z.

| Param | Meaning |
|---|---|
| `offset` | clearance over fit_body everywhere |
| `hem` | bottoms: hem s; tops: hem z |
| `sleeve` | sleeve length s (`None` = sleeveless) |
| `bag`, `bag_at`, `bag_w` / `s_bag` | bagginess: gaussian extra radius (where, how wide) |
| `flare` / `s_flare` | extra radius ramping to the hem |
| `splay` | trouser leg axis leans outward by splay·s/hem |
| `slant` | inner hem is that much higher than the outer (shorts notch) |
| `inseam` | medial clearance over the ink contour, which keeps the legs from merging |
| `seat` | extra clearance round the hip balls (default .010) |
| `cuff`, `cuff_r` | elastic cuff length and its clearance, with a fold line at its top |
| `band` / `hem_band` / `collar` | waistband / ribbed hem / collar height (fold band) |
| `neck` | neck opening radius |
| `hood`, `pocket`, `strings`, `scarf`, `straps`, `drawstring`, `rips`, `hem_line` | extra parts |

Topology:
- **Trousers** use a pair-of-pants mesh. Waist rings (16 verts) run down to
  z .905. Each leg's first ring is half the waist ring plus a 3-vertex
  crotch seam at x = 0 (bottom z .815), so the crotch is one closed,
  manifold surface with no gap and no seam line. Below that, each leg is
  12-sided. A leg's inner side is clamped to the ink contour + `inseam`:
  the legs share one hip point, so the trousers read as one garment that
  splits lower down. The crease where the two legs meet draws a short
  contour inseam and a fly mark at the crotch front.
- **Tops**: a 16-sided torso from the hem to z 1.42, a yoke up to the neck
  opening at z 1.565, and 10-sided sleeves. Each sleeve starts with a dome
  over the shoulder ball. Sleeves and the hood are separate closed shells
  that overlap the torso. Where they intersect, the inverted hull draws the
  seam line, as an ink drawing would.
- **Decals** (pocket, hood opening, rips, strings, scarf fringe) are strips
  lifted 3–4 mm off the surface, with no contour of their own.

## Weights

1. **Copy from `fit_body`, nearest face interpolated, per part.** The build
   splits `fit_body` into its five islands (torso, arm_l/r, leg_l/r). Each
   garment vertex has a part (`waist seam leg_l leg_r torso yoke sleeve_l
   sleeve_r hood scarf tail`), finds the nearest face *on its own part's
   island*, and takes the barycentric blend of that face's weights. This is
   Blender's Data Transfer → Vertex Groups → Nearest Face Interpolated,
   written out so it is deterministic and can't pick up the other leg.
2. **Allowed bones per part.** Anything else is dropped. A left leg never
   takes `thigh_r`, sleeves never take `spine`, and the crotch seam is 100%
   `hips` so the gusset never rides up with a thigh.
3. **Hinge re-profiling at knees, elbows and hips.** Linear blend skinning
   (all Godot does) pulls a 50/50 ring in to cos(θ/2) of its radius around
   the pivot, which is 0.5 at 120°, so the ink knee ball would poke through.
   For every vertex in the joint zone the parent/child split is recomputed
   from its position: `t` along the child bone and `o` = which side of the
   bend it is on (+1 = outer, stretched). The child weight is
   `smoothstep(c-hw, c+hw, t)`, with c = 0 on the inner side and
   `c_outer` on the outer side. The stretched side transitions further
   down the child bone, so its blended ring sits far enough from the pivot
   to stay outside the ball. A 2D sweep picked the values; the 3D check
   confirmed them.

   | joint | outer side | c_outer | c_other | hw |
   |---|---|---|---|---|
   | knee (thigh→shin) | front | .105 | 0 | .05 |
   | elbow (upper_arm→forearm) | back | .11 | 0 | .05 |
   | hip (hips→thigh) | seat | .15 | .08 | .07 |
4. **Rigid sleeve root.** The shoulder ball is a sphere rigid on `upper_arm`.
   A sleeve cap rigid on `upper_arm` is a sphere about the same pivot, so it
   covers the ball at any arm angle (rigid to s .10, back to the copied
   weights by s .18; short sleeves are rigid to the hem).
5. **Scarf tail**: chest → `scarf_tail` over its first 22%.
6. Keep the top 4 influences, prune below 1.5%, normalise.

**The coverage check is the acceptance test.** The build poses the rig
(FK) in six poses and computes, for every ink-limb vertex pushed out by its
0.018 white contour, the generalised winding number against the garment.
Any point the garment covers at rest must stay covered.

| pose | what |
|---|---|
| `stress` | the rig's `rig_stress`: knees and elbows 120°, hip 100°/−25°, spine twist |
| `bend120` | both knees and elbows at 120° |
| `squat` | hips 95°, knees 120°, elbows 110° |
| `wide` | thighs abducted 38°, knees 45°, arms out 55° |
| `stride` | a walking extreme |
| `reach` | arms overhead (150°) |

Current result: **0 exposed points for all 14 garments in all poses, and
all 35 top-over-bottom pairs pass the layering check** (the waistband stays
inside the top's hem in every pose). `clothing_preview.gd` drives the same
poses bone by bone, and they match the baked `rig_stress` to 0.0°.

## Shading

- **One material for every garment**: `clothing.gdshader` with
  `clothing_outline.gdshader` as its next pass, shared through
  `BWClothing.material()`.
- **Palette = a texture, not uniforms**: `clothing_palette.png`, 3×3, nearest,
  lossless. Column = shade (0 dark, 1 mid, 2 light). Row 0 is the fill
  (`BWLook.GREY_DARK/MID/LIGHT`: .28 .55 .82), row 1 the darker fold line
  (.12 .33 .58), row 2 the contour colour. To retune every garment, edit
  `PALETTE_FILL` / `PALETTE_FOLD` in the build and rebuild, or paint the PNG.
- **The shade is per instance.** `instance uniform float shade`, at
  `instance_index(3)` (the project pins `dim` 0, `tint` 1, `accent` 2).
  `BWClothing.set_shade()` sets it.
- **Channels in vertex COLOR**:
  - `R`: 1 = fill, .5 = fold line, 0 = ink (black rips).
  - `G`: 1 = gets the contour, 0 = no contour (decals and strings). The
    hull push is multiplied by `COLOR.g`.
- **Two-sided fill**: back faces draw in the fold colour, so the inside of
  a hem, sleeve or neckline reads as a darker interior rather than a hole.
  The hull drawn behind it is hidden by depth.
- **Contour rule (D42 extended to grey)**: fill value < 0.5 → **white**
  contour, otherwise **black**. Dark gets white; mid and light get black.
  A dark garment keeps the limbs' white edge against the black sky. Mid
  and light garments carry their own value against the sky and get the ink
  line on white tiles. Width 0.020 (body ink 0.018, head 0.026).
  `BWClothing.contour_for()` states the rule and the test checks the
  palette against it.
- `dim` and `tint` behave as on the body, so `BWLook.set_dim(rig, x)`
  fades clothing with the figure.

## Runtime

```gdscript
var rig := BWCharacterRig.new()
add_child(rig)
BWClothing.dress_from_row(rig, BWData.row("roster", "kai"))   # top, bottom, clothing_shade (D379: a seated id; pool ids like "jet" roll only in a run)
BWClothing.wear(rig, "shorts", "light")    # replaces the bottom only
BWClothing.set_shade(rig, "dark")
BWClothing.garment(rig, "top")             # the MeshInstance3D, e.g. to hide under a chest plate
BWClothing.remove(rig, "top")
```

`wear()` instances the glb, takes its MeshInstance3D, reparents it under
`rig.skeleton` as `clothing_top` / `clothing_bottom`, and points its
`skeleton` path there. The skin binds by bone name (named skins), so it
rides every animation the rig plays. The rest of the glb scene is freed.

**Extra bones.** `BWClothing.EXTRA_BONES` lists the only bones a garment may
add. There is one: `scarf_tail` (parent `chest`, sweater_scarf only). It is
appended to the rig skeleton the first time the scarf is worn, with its
rest pose taken from the glb, so the 20 rig bones keep their indices. It is
driven by `BWClothing.ScarfSway`, a SkeletonModifier3D that runs after the
AnimationPlayer: a damped spring on the tail tip that lags the chest, hangs
partly toward gravity, never swings into the chest, and is clamped to 40°.
The bone stays after the scarf is removed. It is harmless and undriven.

## Adding a garment

1. Add a dict to `BOTTOMS` or `TOPS` in `build_clothing.py`. Start from the
   closest existing one and change the named parameters. New part types
   need a builder function, a `PART_SRC` entry and an `allowed()` rule.
2. Add the id to `BWClothing.TOPS` / `BOTTOMS` and, if roster data uses it,
   to `design/SCHEMA.md`.
3. Run the build. It must print `CLIP_FAILURES 0`. If not, the `_where`
   dict names the bones whose ink shows. Fix it with clearance (`offset`,
   `seat`, `inseam`) or a hinge profile, never by deleting check poses.
4. `--import`, `--self-test`, then render with `clothing_preview.gd` and look
   at the front, side, stress and zoom sheets.
5. A new bone means an `EXTRA_BONES` entry (the test refuses undocumented
   ones) and a line in this file.

## Armour that bends (chaps, platelegs, robes, tassets, tights)

Use this pipeline, not sockets:
- **Chaps / tights / platelegs**: a `BOTTOMS`-style entry. Tights are
  tight_pants with `offset` .004 and no band. Chaps are trouser legs with
  no waist rings and a strap decal. For platelegs, keep the shell and give
  the knee a rigid cap: a separate closed shell weighted 100% to `shin`
  around the knee ball, the same trick as the sleeve dome. Rigid plates
  should look rigid, so use fewer, flatter sides (6–8) and no bag.
- **Robes / robe bottoms / tassets** hang from the waist. Build them as
  `waist`-part rings continuing below the crotch (an open skirt shell), with
  weights blended between `hips` and the two thighs by side (the fit torso
  already gives this below z .97). Put the c_outer idea on the hem's front
  and back so a high knee pushes the cloth instead of passing through it.
  Tassets are the same in 3–4 separate overlapping plates, each skinned to
  `hips` + its side's thigh.
- Use the same material, or `equipment.gdshader` for coloured trim. The
  armour lane owns those files. Keep `COLOR.g` = 0 on decals if you reuse
  `clothing_outline`.
- An armour piece that replaces a garment should **hide** `clothing_top` /
  `clothing_bottom` (`BWClothing.garment(rig, slot).visible = false`), not
  remove it, so taking the armour off restores the outfit.
- Always run the coverage check. Add the piece's id to the build, or copy
  `check_coverage()`.

## Verification

All renders are Godot, real shaders, 1600×900, against the starfield.

| File | Shows |
|---|---|
| `clothing_tops_front/side/stress.png`, `clothing_bottoms_front/side/stress.png` | every garment × dark / mid / light rows |
| `clothing_tops_zoom.png`, `clothing_bottoms_zoom.png` | front close-ups of the garment zone |
| `clothing_tops_detail_1/2.png`, `clothing_bottoms_detail_1/2.png` | stress pose large, 3/4 front and back |
| `clothing_tops_poses.png`, `clothing_bottoms_poses.png` | wide stance, squat, stride, reach |
| `clothing_gamescale.png` | 12 roster outfits under the combat camera (24 u, FOV 34) |
| `clothing_closeup.png` | cutscene framing: dark hoodie + ripped pants (stress) vs light sweater_scarf + baggy (wide) |

Numeric checks: the build's CLIP/LAYER lines, and `test_clothing` (8
tests). The scarf sway was checked headless (it swings and stays inside its
clamps). No PNG shows it moving.

## Decisions I made

1. **Measure, don't hand-place.** Garment radii come from `fit_body` at build
   time, and the parameters only add on top. A rig proportion change
   rebuilds correctly.
2. **Coverage check as a build gate.** Every ink contour point covered at
   rest must stay covered in six poses, measured by winding number (robust
   to open hems and overlapping legs). This replaced eyeballing clipping.
3. **Hinge re-profiling over corrective shapes or helper bones.** Godot is
   linear-blend only. Shifting the stretched side's transition down the
   child bone fixes the knee and elbow at 120° with plain weights and no
   runtime cost.
4. **Rigid sleeve caps and a hips-only crotch seam.** Both come from the
   same insight: a shell rigid about a pivot can't collapse onto a ball
   centred there.
5. **Pair-of-pants topology** with the inner thigh clamped to the ink.
   Overlap between the legs is limited to what the narrow hip spacing
   forces, and the crotch stays manifold.
6. **Shorts get a shorter inseam (`slant`)**, since flare alone read as a
   skirt from the front.
7. **Palette as a 3×3 texture** (fill, fold, contour rows), with the shade
   per instance. One material serves every garment and character, and the
   contour colour lives in data next to the fill it belongs to.
8. **Contour by value**: < 0.5 white, else black (dark → white; mid and
   light → black).
9. **Two-sided fill with a fold-coloured interior** instead of capping hems.
10. **Hood down**, as a rolled collar plus a bag on the back. A raised hood
    would fight all ten hair styles and cover the head, which is the
    figure's main shape.
11. **The scarf gets one bone and a spring.** Follow-through on the tail
    suits the bouncy animation brief. It is documented in `EXTRA_BONES`,
    appended to the rig skeleton, and never changes the 20.
12. **Separate `clothing.blend`.** I don't save over `base_rig.blend` (the rig
    lane's generated file). The clothing file is a copy plus the garments.
13. **Build writes each `.import` only if missing**, with LODs and shadow
    meshes off as for the rig, so hand edits survive.

## Shared files

None changed. `character_rig.gd`, `look.gd` and the existing shaders are
untouched. Two new shaders were added (`clothing.gdshader`,
`clothing_outline.gdshader`), following the project's instance-slot pins;
`shade` takes slot 3.

## Open issues

- **short_shorts reads as a brief from the front.** Its inner hem is
  already at the crotch, and the hip spacing allows no deeper notch. It
  reads as shorts from the side and in motion.
- **Full-length trousers merge from the crotch to about the knee in a
  front view**, because the ink legs (contour included) overlap there. The
  contour inseam marks the split. Wider-hipped rigs would remove this.
- **Top hems and raised thighs**: tops are weighted to the torso only, so at
  hip flexion past about 90° the thigh passes through the front of the hem
  (it reads as the leg coming out from under the shirt). The coverage check
  covers ink, not cloth against cloth, except the waistband layering check.
- **Not checked against hair**: long styles against the hood bag and scarf
  (hair lane renders). Not checked against chest armour (equipment lane).
  The intended rule is "armour hides the garment".
- **Sweater vs hoodie at combat scale** differ mainly by the hood. The
  pocket and strings vanish below about 100 px figure height.
- The scarf sway is untested at a game frame rate in a real scene. Tune
  `stiffness` / `damping` / `gravity_mix` on `BWClothing.ScarfSway` once
  animations exist.

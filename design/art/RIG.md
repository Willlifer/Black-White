# Base character rig (v1)

Every character, hair style, clothing piece, armour piece and weapon in
Black | White is built on this rig, and every animation is keyed on it.

| File | What | Edit? |
|---|---|---|
| `game/tools/blender/build_base_rig.py` | builds everything below from nothing | **yes, this is the source** |
| `game/art/source/base_rig.blend` | working file: rig, IK controls, `fit_body` proxy, test actions | generated, don't hand-edit |
| `game/art/characters/base_rig.glb` | runtime: body, 20 deform bones, 6 socket empties, 2 baked actions | generated |
| `game/art/characters/base_rig.glb.import` | Godot import settings (LODs off, see below) | yes, by hand |
| `game/src/game/character/character_rig.gd` | `BWCharacterRig`: runtime loader | yes |
| `game/shaders/flat_opaque.gdshader` | flat shader without the ALPHA write (why: see Decisions) | yes |
| `game/tests/test_rig.gd` | bones, sockets, height, facing, materials, budget, actions | yes |
| `game/tools/rig_preview.gd` | Godot renders with the real shaders | yes |
| `design/art/base_rig_sheet.png`, `base_rig_stress.png` | Blender proportion sheet and joint close-ups | generated |
| `design/art/base_rig_godot_{gamescale,closeup,turntable}.png` | Godot renders | generated |

## Rebuild

```
blender -b --factory-startup --python game/tools/blender/build_base_rig.py            # all + sheet
blender -b --factory-startup --python game/tools/blender/build_base_rig.py -- --no-sheet
cd game
godot --headless --path . --import
godot --headless --path . -- --self-test
godot --path . --resolution 1600x900 -s res://tools/rig_preview.gd   # windowed, writes design/art/*.png
```

The build is deterministic: same script, same output. It prints `STATS`
(tris, bounds) and `POLES` (solved IK pole angles and their residuals).
`game/art/source/` has a `.gdignore`, so Godot never tries to import the .blend.

## Proportions (world units; 1 hex = 1.0 circumradius)

Read off the five reference panels: about 3.9 heads tall, head about 25% of
height, neck plus torso 33%, legs 42%. Limbs and torso share one line weight.
The arms leave the spine a short neck below the chin, and the hands hang to
the hip.

| Landmark | Height | Notes |
|---|---|---|
| top of head | 2.20 | total height |
| head centre | 1.92 | head radii 0.31 wide × 0.295 deep × 0.28 tall (squashed 10%) |
| chin | 1.64 | |
| head pivot | 1.66 | neck/head joint |
| neck base | 1.50 | |
| shoulders | 1.48 | joints at x = ±0.06, so arms branch off the spine with no yoke |
| chest pivot | 1.22 | |
| spine pivot | 1.02 | |
| hip / pelvis | 0.92 | hip joints at x = ±0.07 |
| knee | 0.50 | |
| ankle | 0.055 | foot nub bottom = 0.00 |

| Part | Size |
|---|---|
| upper arm / forearm / hand | 0.36 / 0.33 / 0.085 |
| thigh / shin | 0.42 / 0.445 |
| arm tube radius (shoulder → elbow → wrist) | 0.040 → 0.036 → 0.031 |
| leg tube radius (hip → knee → ankle) | 0.045 → 0.040 → 0.034 |
| torso tube radius (pelvis → neck) | 0.046 → 0.040 |
| joint balls | 1.08 × the tube radius at that pivot; pelvis ball 0.052 |
| hand nub | sphere r 0.043, centred 0.03 past the wrist |
| foot nub | ellipsoid 0.043 × 0.065 × 0.050, nudged forward |
| rest pose | A-pose, arms 35° from vertical; elbows and knees pre-bent a few degrees for IK |

**Budget: 2816 triangles, 1446 vertices** (head 616, limbs and torso tubes
~1180, joint balls and nubs ~1020). Material slots: `ink` (black, every
tube, ball and nub) and `skin` (white, the head only).

At the combat camera (21 u, FOV 38, 1600×900) the figure is about 135 px
tall, the head about 38 px, and a limb 4–5 px plus a 1 px white contour. In
the cutscene (FOV 24, ~11 u) it is about 420 px tall.

## Conventions

- **Axes.** In Blender, Z is up and the character faces −Y. In Godot, Y is
  up and it faces **+Z**. Its left is +X in both. Units are world units
  (Blender metres); the glTF exporter's +Y-up conversion does the mapping,
  and `test_rig` checks it.
- **Naming.** lower_snake, side suffix `_l` / `_r` (the character's own
  side). Controls are `ik_*` and `pole_*`; sockets are `socket_*`.
- **Rolls.** Every bone's local Z points to the character's front (the
  forward-pointing feet point Z up instead). So **+X rotation pitches a
  bone's tip forward** on every bone, on both sides: hip, shoulder and elbow
  flexion are +X, knee flexion is −X. The upright bones (root, hips, spine,
  chest, neck, head) have identity rest rotation in Godot.
- **Mirroring poses.** Left to right: keep X, negate Y and Z (`mirror()` in
  the build script).
- **Frame rate** 24 fps (the import is set to 24 too).

## Bones (20, all deform, all exported)

```
root                      (0,0,0) up; place/turn the unit with this
└ hips                    0.92
  ├ spine                 1.02
  │ └ chest               1.22
  │   ├ neck              1.50
  │   │ └ head            1.66 → 2.20
  │   ├ shoulder_l / _r   short clavicle, 1.48
  │   │ └ upper_arm → forearm → hand
  └ thigh_l / _r          0.92
    └ shin → foot
```

Controls (in the .blend only, never exported): `ik_foot_l/r`, `pole_knee_l/r`,
`ik_hand_l/r`, `pole_elbow_l/r`. The armature object carries the IK/FK blend
properties `ik_leg_l/r` (default 1 = IK) and `ik_arm_l/r` (default 0 = FK).
Drivers turn these into constraint influences. The IK uses 2-bone chains
with pole angles solved to reproduce the rest pose (legs 90°, arms −90°).
The feet and hands take their rotation from the IK targets. Bone
collections are `Deform` and `IK`.

## Sockets

Each socket is an empty parented to a bone. Godot imports each one as a
`BoneAttachment3D` (named after the bone) with the socket `Node3D` inside.
**At rest every socket is world-aligned: +Y up, +Z the character's forward,
+X its left.** Model attachments in that frame, with the origin at the
point listed here.

| Socket | Bone | Rest position (Godot) | Origin means |
|---|---|---|---|
| `socket_hair` | head | (0, 1.92, 0) | head centre: model hair around the head ellipsoid |
| `socket_hat` | head | (0, 2.20, 0) | crown: hat brims and helmet tops |
| `socket_weapon_r` | hand_r | (−0.48, 0.89, 0.02) | centre of the right fist: the grip |
| `socket_offhand_l` | hand_l | (+0.48, 0.89, 0.02) | centre of the left fist |
| `socket_chest` | chest | (0, 1.36, 0) | on the spine line at the chest: rigid chest pieces |
| `socket_back` | chest | (0, 1.36, −0.075) | behind the back: quivers, sheaths, capes' anchor |

```gdscript
var rig := BWCharacterRig.new()
add_child(rig)                     # builds in _ready (or call rig.build())
rig.attach(hair, "hair")           # or "socket_hair"
rig.play("rig_idle")
rig.socket_rest("weapon_r")        # rest transform, works outside the tree too
```

`BWCharacterRig` also provides `socket_names()`, `clear_socket()`,
`pose_at(anim, t)`, `animations()`, `set_outline_widths(ink, skin)`,
`triangle_count()` and the static `material_for(role)`.

## Look (runtime)

- `ink` → `flat_opaque` + inverted-hull outline pass, **white**, 0.018 (D42)
- `skin` → `flat_opaque` + inverted-hull outline pass, **black**, 0.026
- Colour is baked into vertex COLOR (ink 0, skin 1), so one shader serves
  both surfaces. The per-instance `tint` and `dim` uniforms behave as they
  do everywhere else, and `BWLook.set_dim(rig, 1.0)` fades the figure for
  the cutscene.

## How the next lanes attach

- **Hair.** One mesh per style, modelled around the head ellipsoid in
  socket space (origin at the head centre). It is rigid, so no skin is
  needed; attach it to `socket_hair`. Use an unlit colour material with
  the element colour from `BWLook.element_color()`, and a black hull
  outline. To keep the face blank, keep the fringe above about 1.95 at the
  front, or follow the reference panels, where hair frames the face.
- **Hats and helmets.** Rigid, on `socket_hat`, origin at the crown. A
  helmet that replaces hair should hide the hair node, not delete it.
- **Clothing (sweatpants … sweater).** Model it in `base_rig.blend` over the
  `fit_body` proxy, which has a slim torso volume plus sleeves, and copy the
  weights from it: Data Transfer, Vertex Groups, Nearest Face Interpolated.
  The proxy's falloffs are long (smoothstep, ±0.07–0.12) so cloth bends in
  arcs. Export each garment as its own glb, skinned to the same 20 bones
  (export deform bones only, same names). In Godot, set the garment's
  `skeleton` path to the rig's `Skeleton3D` and give it its own flat
  material or a 3-step grey palette texture.
- **Armour.** Pieces that bend (chaps, platelegs, robes) go the clothing
  route. Rigid plates go on `socket_chest` or `socket_back`, or are skinned
  100% to one bone.
- **Weapons.** Rigid, on `socket_weapon_r` (and `socket_offhand_l` for
  bows, shields and dual daggers). Model them grip at the origin, blade or
  shaft along +Y, edge facing +Z. At rest that stands the weapon upright
  in the fist, and animations rotate the hand.
- **Animation.** Animate in `base_rig.blend` with the IK controls, as one
  action per move, named like `idle` or `strike_sword`. Push the actions to
  NLA tracks (or give them a fake user) and export the deform bones with
  baked sampling, the same settings as `build_base_rig.py`. Godot plays them
  through the rig's AnimationPlayer. Pose names to cover from
  `unit_view.gd`: idle, windup, strike, cast, hit, kneel, dodge, block,
  fumble, fall, cheer. The two shipped actions, `rig_idle` (2 s loop) and
  `rig_stress` (rest to elbows/knees at 120°), exist for verification
  only.
- **Rig changes.** Bump `RIG_VERSION` in the script and in
  `character_rig.gd` whenever bone names, socket names or proportions
  change. Existing clothing and animations then need re-checking.

## Decisions I made

1. **Ball joints instead of long weight blends.** Godot skins with linear
   blending only (no dual quaternions). A thin tube bent 120° with a long
   smooth falloff collapses to cos(60°) = 50% of its width at the joint.
   Each limb is still one continuous tapered tube, with 5 loops per
   major joint weighted 0 / .25 / .5 / .75 / 1 over about ±0.9× the
   radius. A rigid ball 8% larger than the tube sits on every pivot
   (shoulder, elbow, hip, knee, pelvis), and the chords of the pinch stay
   inside it. The result has no gap and no crease at any angle, which the
   stress close-ups confirm. Wrist, ankle and spine joints use the hand
   nub, the foot nub or 3 loops: they bend less, and at 45° the pinch is
   only 8%.
2. **Smooth falloff lives on `fit_body`, not the ink.** Clothing needs soft
   arcs and the body needs round joints, so the .blend carries a separate
   weight-source proxy with long falloffs. It contains the slim torso
   volume the brief asked for (0.10 × 0.065 half-widths at the chest) plus
   limb sleeves. It is not exported: the stick figure stays a line, as in
   the references.
3. **Arms come off the spine** (shoulders at ±0.06), as in every reference
   panel, not off a shoulder bar. A short `shoulder_*` bone still exists
   for shrugs.
4. **A-pose at 35°** is the bind pose, for sleeve deformation. The relaxed
   look (arms at about 12°) is the idle animation.
5. **Socket empties, not socket bones.** Godot's importer turns
   bone-parented empties into `BoneAttachment3D` nodes, so the exported
   skeleton stays the 20 deform bones. Sockets are world-aligned at rest, so
   attachments never inherit a bone's roll.
6. **Vertex colours carry the palette.** The flat shader's tint is a
   per-instance uniform, so it can't differ per surface. Baking ink = 0
   and skin = 1 into COLOR keeps one shader and keeps dimming working.
7. **`flat_opaque.gdshader`.** `flat.gdshader` writes ALPHA, which puts it
   on Godot's transparent pipeline (no depth writes). On the one-mesh rig
   that made the neck draw through the head. `flat.gdshader` can't simply
   drop ALPHA because the downtime spotlight cone fades with it. So the rig
   uses an identical copy without the ALPHA write, and the shared shader
   is untouched.
8. **Mesh LODs, shadow meshes and tangents are off** in the import. Godot's
   auto-LOD shrinks silhouettes, which a hull outline exaggerates, and the
   figure is already under 3k tris. The import also adds a `RESET`
   animation.
9. **The root bone points up** (identity rest in Godot), so moving or
   turning a unit is a plain root transform.
10. **Outline widths** are 0.018 for the ink contour and 0.026 for the head.
   That is about 1 px and 1.6 px at combat distance and 3–5 px in the
   cutscene, close to the references' line weight. `set_outline_widths()`
   overrides them per figure.

## Known gaps / open

- `outline.gdshader` has no `dim` uniform, so in the cutscene a dimmed rig's
  white contour stays white. Adding `instance uniform float dim` to it
  would fix that for every figure. I left it alone because it is shared.
- Other opaque users of `flat()` (tiles, `unit_view` parts) would also
  sort better on `flat_opaque`. That is the combat lane's call.
- `rig_stress` drives the legs FK, so the figure lifts off the floor. This
  is intended, since it tests joints, not contact.
- Tests cover rest-pose structure. Deformation quality is verified by eye
  from the renders listed above.

# Weapon models (v1)

There are 25 low-poly main-hand weapons (22 + the 3 fists, D76), built on the base rig (`RIG.md`).
Each one is a white body with a black inverted hull (D42), plus a small
`accent` surface that the element aura tints.

| File | What | Edit? |
|---|---|---|
| `game/tools/blender/build_weapons.py` | builds everything below from nothing | **yes, this is the source** |
| `game/art/weapons/<id>.glb` | one rigid mesh per weapon, surfaces `body` + `accent` | generated |
| `game/art/weapons/<id>.glb.import` | import stub: LODs, shadow meshes and animation off | written once by the build, then by hand |
| `game/art/weapons/weapons.json` | **sidecar metadata, the single source of truth** | generated |
| `game/art/source/weapons.blend` | every weapon in a row, metadata points as empties | generated, reference only |
| `game/src/game/character/weapon_view.gd` | `BWWeaponView`: load, attach, aura, trail points | yes |
| `game/shaders/weapon.gdshader` | unlit fill, with a tintable accent | yes |
| `game/shaders/aura.gdshader` | fresnel rim on an inflated shell | yes |
| `game/tests/test_weapon_models.gd` | coverage vs equipment.csv, classes, sockets, aura, budget | yes |
| `game/tools/weapon_preview.gd` | Godot renders with the real shaders | yes |
| `design/art/weapons_{lineup,combat,aura,aura_elements}.png` | renders | generated |
| `game/tools/blender/build_projectiles.py` | arrow, bullet, bolt (imports the builder from build_weapons.py) | **yes, source** |
| `game/art/weapons/projectiles/<id>.glb`, `projectiles.json` | the projectile models and their sidecar | generated |
| `game/src/game/character/projectile_view.gd` | `BWProjectileView` (extends BWWeaponView): load, accent, aura | yes |
| `game/src/game/combat/projectile_flight.gd` | `BWProjectileFlight`: flight, stick, muzzle flash | yes |
| `game/shaders/muzzle_flash.gdshader` | the flash star | yes |
| `game/tests/test_projectiles.gd` | models, sidecar, string API, flights | yes |
| `design/art/projectiles.png`, `anim_bow_shot.gif`, `anim_pistol_shot.gif` | renders | generated |

## Rebuild

```
blender -b --factory-startup --python game/tools/blender/build_weapons.py
blender -b --factory-startup --python game/tools/blender/build_weapons.py -- --only sword,axe
blender -b --factory-startup --python game/tools/blender/build_projectiles.py
cd game
godot --headless --path . --import
godot --headless --path . -- --self-test
godot --path . --resolution 1600x900 -s res://tools/weapon_preview.gd   # windowed; add -- --only lineup,combat,aura,elements
```

The build is deterministic: two runs give byte-identical glbs and json
(checked by md5). Each run prints one `WEAPON` line per model, with its
class, hands, triangle count and length.

## Grip convention

- **The origin is the grip**, the centre of the fist that holds the weapon
  (the socket origin).
- Weapon-local axes match the socket frame at rest: **+Y runs up the blade
  or shaft, +Z is the edge or muzzle (the wielder's forward), and +X is the
  wielder's left.** So the `mount` is identity, and at rest every weapon
  stands upright in the fist. Animations rotate the hand. Blender's weapon
  space is (x, f, u) = (left, forward, up), stored as (x, −f, u), and the
  +Y-up glTF export maps it to Godot (x, u, f).
- Blade flats face ±X. A sword therefore shows its profile from the wielder's
  side and is edge-on from the front. That is the RIG.md convention ("edge
  facing +Z").
- Pistols hold the grip through the fist with the barrel forward (+Z) above it.
- Bows hold the riser in the fist, with the limbs along ±Y. The bow's back
  faces forward (+Z) and the string is behind it (−Z).

| hands | socket | second hand | used by |
|---|---|---|---|
| `one` | `socket_weapon_r` | none | sword, scimitar, axe, hatchet, javelin, pistol, flintlock, m1911 |
| `two` | `socket_weapon_r` | `second_hand = {hand:"l", point}`: the **left** hand's IK target on the grip | flamberge, double_axe, warhammer, anchor, lance, halberd, glaive, staff, moon_staff |
| `pair` | `socket_weapon_r`, plus an identical copy on `offhand_socket = socket_offhand_l` | none | dagger, jagged_dagger |
| `bow` | **`socket_offhand_l`** (bows are held in the left hand) | `{hand:"r", point}`: the right hand's **draw / nock** target on the string | shortbow, recurve_bow, compound_bow |
| `fists` | `socket_weapon_r` plus a **mirrored** piece (`offhand_glb`, `<id>_l.glb`) on `socket_offhand_l` | none | hand_wraps, brass_knuckles, gauntlets |

For swords and heavy weapons the left-hand point is below the right hand
(at the pommel or butt end). For polearms and staves it is about 0.48 up the
shaft, so the leading hand sits ahead of the right one.

## Metadata (`weapons.json`)

I chose a sidecar file over glb extras. Godot's handling of glTF `extras` on
import is not a stable contract. A JSON file can be read by tests and tools
without instancing a scene, and the same build run writes it, so it can't
drift from the meshes. All points are in **Godot weapon-local space**.

```json
"flamberge": {
  "class": "sword", "hands": "two",
  "socket": "socket_weapon_r", "offhand_socket": null,
  "mount": {"position": [0,0,0], "rotation_deg": [0,0,0]},
  "second_hand": {"hand": "l", "point": [0, -0.24, 0]},
  "tip": [0, 1.56, 0], "trail_base": [0, 0.24, 0],
  "aura_points": [[0, 0.3, 0], ...],
  "length": 1.99, "aabb": {"min": [...], "max": [...]},
  "scale": 1.0, "tris": 462, "accent_tris": 192,
  "glb": "res://art/weapons/flamberge.glb", "notes": "..."
}
```

Added keys (additive, still version 1): `"projectile"` is what the class
shoots (`bow` arrow, `pistols` bullet, `staff` bolt, else null), and bows
carry `"string": [top, bottom]`, the ends of the drawable string.

The top level also has `version` (1), `rig_version` (1), `space` and
`hands`, the conventions written out. `tip` and `trail_base` are the two
edges of a trail ribbon. For bows and pistols, `tip` is the projectile
spawn point (the arrow rest or the muzzle).

## Look

- `body` uses the fill shader `weapon.gdshader`. It is unlit and takes its
  colour from the vertex COLOR baked per face: blades and heads are white
  (1.0), shafts are wood grey (0.82), grips and wraps are dark (0.30), and
  mechanisms are iron grey (0.55). Strings are 0.12.
- `accent` covers the cutting-edge bevels (0.70), gems (0.26), the
  warhammer's striking face, the lance point, muzzle bands and the bow tip
  nocks. Most weapons keep it to 6–20% of their triangles; the flamberge
  and moon_staff are higher because their whole outline is edge. Its shader
  mixes in the per-instance uniform `accent` (rgb = colour, a = amount).
- The hull is `BWLook.outline(0.022, BLACK)`, about 1.4 px at the combat
  camera. Every island has smooth normals, so the hull never cracks. The
  fill is unlit, so smooth normals cost nothing visually.
- The fill pins its instance uniforms `dim:0, tint:1, accent:2`, so it
  agrees with `outline.gdshader`. `BWLook.set_dim()` fades weapons along
  with the cutscene.

## Aura API

```gdscript
var w := BWWeaponView.create("flamberge")   # null on an unknown id (error pushed)
w.attach_to(rig)                  # socket from metadata; daggers add the off-hand copy
w.set_aura("fire", 1.0)           # strength 0..2; ("", 0) or clear_aura() removes it
w.has_aura(); w.aura_element
w.tip_local(); w.tip_global()     # trail tip
w.trail_points()                  # [base, tip], world space
w.second_hand_target()            # Marker3D for IK, or null; w.second_hand() -> "l"/"r"/""
w.aura_points(); w.hands(); w.weapon_class(); w.socket_name(); w.triangle_count()
w.set_outline_width(0.03)         # e.g. a hero close-up
w.detach()                        # off the rig, the off-hand copy freed
BWWeaponView.ids(); BWWeaponView.meta_for(id); BWWeaponView.load_meta(true)
```

`set_aura` adds no new meshes. It does three things:

1. **Shell.** It adds a `MeshInstance3D` named `aura_shell` under each
   weapon mesh. The shell reuses the **same Mesh** with `aura.gdshader` as
   its override. That shader pushes vertices out along the normal (0.045,
   breathing with noise), draws a fresnel rim (`pow(1−N·V, 1.4)`) over a
   faint base, and moves bands of brightness up +Y. It is alpha-blended,
   not additive, so the hue survives on white tiles.
2. **Particles.** It adds one `CPUParticles3D` that emits billboard diamonds
   from `aura_points`. It uses `local_coords = false`, so a swing leaves a
   wake. Motion depends on the element: fire rises, water and dark sink,
   thunder crackles outward in short lives, ice drifts slowly, and wind
   sprays sideways. The seed is fixed, so renders repeat.
3. **Accent.** It tints the `accent` surface (edges and gems) to the element.

Colours come from `BWLook.element_color` through `aura_colors()`. Dark hues
(luminance under 0.3) get a lighter rim so they lift off the black sky.
Bright hues (light, ice) get a darker core so they hold on white tiles. The
test asserts both conditions for all 7 elements.

## Projectiles

Three low-poly projectiles in the weapon style, built by
`build_projectiles.py` (it imports `WeaponMesh` and the palette from
`build_weapons.py`, whose `main()` is now guarded so importing it builds
nothing). Same look: white body, black hull, an `accent` surface the element
tints.

| id | tris | read |
|---|---|---|
| `arrow` | 94 | 0.9 long (oversized like the bows): wood-grey shaft, a white four-sided bodkin, three swept vanes on the **accent** (the element), a dark nock |
| `bullet` | 56 | a white slug with an **accent** nose and a tapering white tracer streak behind it (the hull draws its ink rim) |
| `bolt` | 42 | a faceted crystal shard: the back half white, the front facets and two satellite shards **accent**; flown inside the weapon aura (shell + particles) |

**Projectile space:** the origin is the leading point (the arrow tip, so a
stuck arrow's origin is the point in the target), **+Z is the flight
direction**, +Y up: `Basis.looking_at(velocity, Vector3.UP, true)` orients
one. `projectiles.json` has `tip`, `tail`, `length`, `aura_points`, `aabb`,
`tris`, `accent_tris`, `used_by`, `glb`.

```gdscript
var p := BWProjectileView.create_projectile("arrow")
p.set_accent("fire")          # vanes / nose / facets only
p.set_aura("ice", 1.3)        # bolts: the full weapon aura
var f := BWProjectileFlight.launch(parent, "arrow", from_pos_or_xf, target_view, "fire", hit)
f.duration                    # seconds to the impact; it frees itself
```

**In combat** (`BWCombatScreen._projectile`, the kind from the attacker's
weapon class; spells always bolt):
- **arrow:** leaves exactly from the nocked arrow's transform, flies a
  ballistic arc oriented along its velocity, sinks 0.12 into the target's
  chest, rides the chest bone through the reaction for 0.7 s, then shrinks
  away. A miss flies on past.
- **bullet:** straight at 38 u/s, a muzzle flash (a camera-facing six-point
  star: white core, the element ring, an ink rim; it burns out from the
  middle) on the shot and a small one on the hit.
- **bolt:** a shallow arc, spinning about its flight line, wrapped in the
  element aura (its world-space particles are the trail); a flash on arrival.

**The bow draw.** Each bow's straight string run is its own `string`
surface. From the bow strike's `nock` marker to `release`, `BWCharacter`
nocks an arrow (tail in the draw hand, pointing through the arrow rest),
hides the straight string and draws it as two segments to the hand
(`BWWeaponView.set_string_draw(nock)`, null straightens it). After the
release the string buzzes for 0.22 s and snaps straight; `nocked_arrow()`
hands the last transform to the flight. The limbs don't flex (cheap).

## Fists (D76)

Worn, not held. The right piece is modelled in a hand-local frame
(`fist_frame()` in the build: lx along the knuckle row, lf the back of the
hand, lu the punch, out through the knuckles) and turned into weapon space
for `hand_r`'s rest direction (the socket is world-aligned, the hand points
down and out in the 35° A-pose). So at rest the knuckles point down the arm,
and `tip` is the knuckle face, a fist's width from the grip (the tests allow
0.04+, like bows). The left piece is the same mesh **mirrored in x and
rebuilt** (`<id>_l.glb`, its winding recalculated, so the hull stays whole);
`weapons.json` carries `offhand_glb` and `mirror_offhand: true`, and
`BWWeaponView` loads it for the off-hand copy and mirrors every metadata point
(`_side()`, `is_mirrored()`). The rig's fist is an ink ball (r 0.043, white
hull to 0.061), so covering pieces are ≥ 0.064 and no white rim shows.
`BWCharacterPose.FIST_KNUCKLE_R` / `FIST_BACK_R` are the same axes for the
pose solver; a test checks they agree with the models' tips.

| id | tris (each hand) | read |
|---|---|---|
| hand_wraps | 292 | a fat cloth mitten, two bands over the fist, a knuckle pad and a wrist band on the **accent** (the bands are the element) |
| brass_knuckles | 380 | over the bare black fist: four finger rings, a striking bar, four **accent** studs, a palm rest, a dark wrist wrap |
| gauntlets | 300 | plated fist, ridged **accent** knuckle plate, overlapping back plates, a flared cuff with an iron rim and a dark strap |

Review render: `design/art/weapons_fists.png` (`weapon_preview.gd -- --only
fists`): close-ups in the guard, plain and with the accent tinted fire and
ice, then game scale at the combat camera in guard, cross and palm.
Honest read: at game scale the fists are ~10 px, a white-and-colour blob at
each hand; the colour carries them. hand_wraps' accent covers most of its
face, so its tinted version reads as a coloured ball. The fists have no
clip set yet (static poses only; ANIMATION.md).

## Per-weapon notes

| id | class | hands | tris | read |
|---|---|---|---|---|
| sword | sword | one | 106 | straight double edge, flared guard, ball pommel |
| scimitar | sword | one | 162 | single edge that sweeps back and widens to a clipped point |
| flamberge | sword | two | 462 | 2.0 long, undulating blade, parrying lugs, horned guard: the biggest sword silhouette |
| axe | axe | one | 138 | bearded head, square poll, 1.06 long |
| double_axe | axe | two | 174 | labrys: twin crescents and a top spike |
| hatchet | axe | one | 98 | 0.61 long: a small wedge plus a hammer poll |
| warhammer | axe | two | 120 | chunky block head, grey striking face, back and top spikes |
| anchor | axe | two | 374 | held at the ring end; crown and flukes curl back toward the wielder |
| lance | lance | two | 146 | vamplate cone over the hand, long octagonal cone, 2.6 long |
| javelin | lance | one | 64 | thin, bound in the middle, four-sided head |
| halberd | lance | two | 180 | spear top, axe forward, hook back |
| glaive | lance | two | 176 | long single-edged knife blade on a pole, back spur |
| dagger | daggers | pair | 106 | leaf blade (×1.2) |
| jagged_dagger | daggers | pair | 138 | hooked tip, sawtooth spine, spike pommel (×1.2) |
| shortbow | bow | bow | 276 | simple D arc |
| recurve_bow | bow | bow | 304 | taller; tips curl forward; the string lies on the curls (the curl runs stay on the body; the straight run is the drawable string) |
| compound_bow | bow | bow | 368 | angular riser, split limbs, cams, crossing cable, stabiliser rod |
| pistol | pistols | one | 136 | revolver: hex cylinder bulge, thin barrel (×1.4) |
| flintlock | pistols | one | 228 | long thin barrel, curved stock, ball butt cap, cock on top (×1.3) |
| m1911 | pistols | one | 132 | boxy slide and frame, steep square grip (×1.4) |
| staff | staff | two | 270 | gnarled shaft, three-prong claw around a dark gem |
| moon_staff | staff | two | 296 | straight shaft, crescent head, gem floating in the hollow |

Total: 4,454 triangles for the 22 above, plus the fists (2 × 972 for the
three pairs); the largest is still the flamberge at 462. The test
budget is 600 per weapon.

## Adding a weapon

1. Add a row to `equipment.csv` (slot `main_hand`; `weight` = the class).
   The CSV belongs to the data lane.
2. Write `build_<id>(w)` in `build_weapons.py`. Use `w.plate()` for
   bevelled blades and heads (list the edge segments for the accent),
   `w.tube()` for shafts, cones and curves, `w.box()`/`w.slab()` for blocks,
   and `w.ellipsoid()`/`w.ring()` for the rest. Return
   `dict(tip, trail_base, aura, second?)` in weapon space (x, f, u).
3. Add `(id, class, hands, builder, notes)` to `WEAPONS`, plus a `SCALE`
   entry if the weapon is small.
4. Rebuild, run `--import` and `--self-test`, render the lineup, and look
   at it.

## Decisions I made

1. **Sidecar JSON, not glb extras** (see Metadata). The glbs carry only the mesh.
2. **The flamberge is two-handed** even though the brief's list omits it.
   equipment.csv calls it a "wavy two-hander", and a 2-unit sword held in
   one fist reads wrong.
3. **The bow is in the left hand on `socket_offhand_l`**, and its
   `second_hand` is the right hand's draw point on the string, so an
   animation can IK the draw.
4. **The dagger pair is the same model twice**, not mirrored. Mirroring
   with negative scale flips the winding, which breaks the hull. The blades
   are close enough to symmetric.
5. **Small weapons are oversized** (pistols ×1.3–1.4, daggers ×1.2, scaled
   about the grip). At true size they were about 15 px at the combat
   camera; this follows the RuneScape spirit.
6. **The "pistol" is a revolver.** This gives the three pistols three
   silhouettes: a cylinder bulge, a long barrel with a ball butt, and a box.
7. **Grey steps inside the white weapon.** Shafts are 0.82 and grips 0.30,
   so heads pop and the hand position reads. Everything that cuts or
   strikes is white.
8. **The aura is alpha-blended, not additive.** Additive blending vanishes
   on white tiles.
9. **The aura uses CPUParticles3D, not GPU.** The emitters are small, run
   headless for tests, and emit from explicit points with a fixed seed.
10. **Import stubs** turn off LODs, shadow meshes and animation, as the rig
    does (auto-LOD shrinks silhouettes under a hull). The build writes a
    stub only if one doesn't exist yet, so uids survive rebuilds.

## Known gaps / open

- **There is no weapon-holding pose yet.** In `rig_idle` the hand's roll
  tilts weapons across the body, so the renders use the rest pose. Grip
  poses per class (two-hand IK onto `second_hand`, bow draw) belong to the
  animation lane.
- **Plate weapons are edge-on from the front.** Axes and swords seen
  straight on at the combat camera shrink to their thickness (0.06–0.08).
  Facing changes during play mostly hide this. If it bothers you, a hand
  roll of about 30° in the hold pose fixes it.
- **Existing `dim` warning.** In `flat_opaque.gdshader`, `dim` is declared
  without `instance_index(0)`. That still triggers Godot's "same instance
  uniform with different indices" warning on the **rig**, and it fires more
  often now because the weapon tests build more rigs. Adding
  `instance_index(0)` to `dim` there would silence it. The file belongs to
  the rig lane, so I didn't touch it. The weapons themselves raise no
  warning.
- The dimmed cutscene doesn't fade the aura particles (StandardMaterial has
  no `dim`). Turn the aura off on bystanders.
- Exported builds must include `art/weapons/weapons.json` (non-resource
  file) in the export filter, as the CSVs do.

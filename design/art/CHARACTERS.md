# Characters (v1): assembly, layering, poses

This lane puts the four art lanes on the base rig (`RIG.md`) to make complete
roster characters: hair (`HAIR.md`), clothing (`CLOTHING.md`), armour
(`EQUIPMENT_MODELS.md`) and weapons (`WEAPON_MODELS.md`). It then swaps them
in for the primitive stand-in everywhere `BWUnitView` is used: combat, the
cutscene, roster, pre-battle and downtime.

| File | What |
|---|---|
| `game/src/game/character/character.gd` | `BWCharacter`: builds a dressed character from a `BWUnit`, plus the layering pass |
| `game/src/game/character/character_pose.gd` | `BWCharacterPose`: the key-pose table and the solver (FK spine, 2-bone IK for arms and legs) |
| `game/src/game/combat/unit_view.gd` | `BWUnitView`: same public API; it now builds a `BWCharacter` (`use_rig = false` gives the primitives) |
| `game/shaders/aura_particle.gdshader` | aura particle billboards with the project `dim` slot |
| `game/tests/test_character.gd` | 12 tests: roster coverage, layering toggles, boss, enemies, weapon holds, dim, sharing, view API |
| `game/tools/character_preview.gd` | renders the turntables, pose sheets and layering sheet |
| `game/tools/character_perf.gd` | measures roster-screen frame cost, rig vs primitive |

## Use

```gdscript
var c := BWCharacter.create(unit)       # rig, hair, clothes, armour, weapon, idle pose
add_child(c)
c.pose("strike")                        # 0.12 s blend to a key; pose("x", 0.0) snaps
c.refresh_equipment()                   # after unit.equipment changes
c.set_aura("fire", 1.0)                 # weapon aura; ("", 0) clears it
c.part("hair" | "top" | "bottom" | "weapon" | "offhand" | "head" | "chest" | "legs")
BWCharacter.look_for(unit)              # the resolved look dictionary
BWUnitView.use_rig = false              # primitive stand-in (read at setup)
```

`BWUnitView` keeps `setup`, `refresh`, `show_label`, `face`, `idle`,
`pose_named`, the floating HP bar and label, the team disc, and the boss's
×2.6 scale. It adds `refresh_equipment()` and `head_height()`. `refresh()`
also re-dresses the character on its own when it sees that the unit's gear
signature changed, so the pre-battle equip menus need no new calls.
`pose_named` turns the weapon aura on for windup (0.7), strike (1.0) and cast
(1.2), in the unit's attuned element, and off for every other pose.

## Assembly order

1. **Rig.** `BWCharacterRig`. Its AnimationPlayer is stopped, because the
   solver owns the skeleton.
2. **Hair** on `socket_hair`: `BWHair.create(hair_style, element, hair_variant)`.
   `hair_variant` is derived in code from the unit id
   (`BWHair.variant_for`, see HAIR.md), never stored in a CSV.
3. **Top and bottom**: `BWClothing.wear(id, clothing_shade)`.
4. **Armour**: `BWEquipmentView.equip(item)` for head, chest and legs from
   `unit.equipment`. The manifest's `hair_mode` hides the hair under helms.
5. **Layering pass** (below).
6. **Weapon**: `BWWeaponView.create(id).attach_to(rig)`. The id comes from
   `equipment.main_hand.base`, then `unit.weapon_model`, then the first
   model of the unit's class. The metadata picks the sockets: daggers get a
   copy on `socket_offhand_l`, and bows go in the left hand.
7. **Poses**: `BWCharacterPose.set_weapon(meta)` picks the weapon style.

`refresh_equipment()` reruns steps 3 to 7. The rig and hair stay. A step
whose result hasn't changed is a no-op: the same weapon id is kept, and a
garment already worn is only re-shown.

**Look data.** It comes from `unit.cosmetics` (`BWUnit.from_roster` already
copies hair_style, top, bottom and clothing_shade, so enemies from
`BWRun.enemies_for` carry their roster look and keep their rolled
equipment). A unit with no cosmetics gets a deterministic default from its id
hash. **The boss** (`id "boss"`, or a size-2 unit with no cosmetics) gets
`BOSS_LOOK`: buzzed, dark element, dark tank top and baggy sweatpants,
platemail and platelegs with dark accents, and the anchor. That armour is
visual only and is never written to `unit.equipment`, so core stats are
untouched.

## Layering rules

Armour hides or trims what it covers. Anything else layers by offset (the
lanes' published offsets clear each other). Garments are **hidden or
swapped, never deleted**, so taking armour off restores the outfit.

| Case | Rule | Why |
|---|---|---|
| Leg piece with `covers: legs` (platelegs, tights, robe_bottoms) | bottom hidden | squashed leg tubes clipped baggy and sweat pants (equipment lane's open issue) |
| Chaps | bottom swapped for `tight_shorts` in the same shade | chaps have no seat; hiding the bottom bared the hips |
| Leather tassets | bottom kept | the plates hang over pants |
| Closed chest piece covering torso (cuirass, brigandine, chain mail, platemail) | top **trimmed to its sleeves** | arms stay clothed; collar, hood and torso can't poke through the plate |
| Chest piece also covering arms (silken robe) | top hidden | robe sleeves replace them |
| Open pieces (vest, bandolier, scarf, shoulder guard, gladiator harness) | top kept | open fronts would bare the spine |
| Scarf piece over `sweater_scarf` | top swapped for `sweater` | no double scarf |
| Silken robe (knee-length skirt) over baggy_sweatpants or shorts | swapped for sweatpants or tight_shorts | the bag pushed through the skirt at the knee |
| Any skirt piece | pose stance narrowed (`stride`): robe_bottoms .35, silken_robe .45, chain_mail .8, platemail .85 | the one-mesh skirts stretch between the legs in lunges (equipment lane's open issue). This fixes it at the source, in the pose, not in the cloth |
| Long hair against a collar, hood, scarf or chest plate | `hair_tail_01` tilted back by a **measured** angle (≤ 0.6 rad) | see below |
| Helms and hats | `hair_mode` from the manifest (show, hide_top, hide_all) | unchanged equipment-lane contract |

**Sleeve trimming** builds, once per garment id and shared by every wearer,
an `ArrayMesh` that keeps only the triangles whose three vertices have more
than 50% of their skin weight on arm bones (upper_arm, forearm, hand). It
uses the same skin and material. The sleeve domes over the shoulder balls
are rigid on `upper_arm`, so they survive the trim.

**Hair push.** Per 5 cm band near the spine (|x| < 0.13, behind the body),
the rest-pose meshes give the outermost back depth of the worn top and the
chest armour, and the innermost depth of the hair curtain. The deficit in
each band, plus a 3.5 cm margin, becomes an angle about the
`hair_tail_01` pivot. The largest one is applied as a tip-back tilt.
Profiles are cached per mesh. On top of that, the solver keeps the tail
plumb: it counters 85% of the head's pitch, so a lean or a fall doesn't push
waist-length hair into the back (hair lane's open issue).

## Poses

Each pose is data, not bone angles. It holds eulers for hips, spine, chest,
neck and head; ankle targets for the feet (model space, with a knee pole and
foot pitch and yaw); and grip targets for the hands. Each grip is a position
plus `aim` (the weapon's +Y) and `edge` (the weapon's +Z) in the chest frame,
or in the unrotated `root` frame for aims that must stay on target (bow
draw, pistols). Every frame the solver runs FK down the spine, then 2-bone IK
for both legs (feet stay planted) and both arms. It writes local rotations.
The blend is 0.12 s with an ease-out, done in pose space (positions lerp,
directions slerp), so a two-hander's second hand stays on the grip the whole
way.

- **Two-handers.** A hand spec gives the centre between the fists. The right
  fist goes half the weapon's `second_hand` offset along the shaft, and the
  left fist is IK'd onto `second_hand.point` (weighted by `grip`, so a pose
  can let go). The same table therefore fits the flamberge (second hand
  below), the halberd and glaive (above) and the lance.
- **Bows.** The bow sits in the left hand. The right hand is either IK'd to
  the string point (`grip` 1) or free: drawn to the chin in windup, flung
  back on release.
- **Daggers.** Both hands are weapon hands.
- **Wrist twist** is moved into the forearm (a round tube with the elbow
  ball), so wrists don't candy-wrap.
- **Flat to camera.** Plate weapons vanish edge-on (weapons lane's open
  issue). Each frame, the weapon is rolled about its own axis to turn its
  flat (±X) toward the active camera. The roll is capped at 70° and scaled
  per pose by `flat` (idle 1.0, strikes 0.3 to 0.4, blocks 0, so the edge
  still leads a cut).
- **Breathing.** The chest pitch and hips height ride a sine (phase
  from the unit id, about 0.38 Hz). The hands follow because they live in
  the chest frame.

| Pose | Body | one (sword, axe) | heavy (2H sword or axe) | polearm / staff | pair | bow | pistol |
|---|---|---|---|---|---|---|---|
| idle | relaxed contrapposto | blade up and forward | low two-handed guard, head out to the side | upright at the side, one hand | both low and forward | bow low in the left hand | low ready, muzzle down |
| windup | coil right, head on target | blade back over the shoulder | both hands high, blade diagonal behind | pulled back, point forward | one forward, one back | side-on, bow arm out, hand at the chin | arm extended, support hand |
| strike | lunge, front foot out, back heel up | cross-body cut | two-handed chop forward | thrust | stab forward, off hand back | release: draw hand flung back | recoil, muzzle up |
| cast | open stance, lean back | weapon low, free palm forward | as one | staff raised forward and up | dagger palm forward | bow low, palm forward | as one |
| hit | recoil back, head snapped | weapon pulled in | two hands pulled in | as heavy | both in | bow in | as one |
| kneel | right knee down, toes curled | blade raised | weapon up in both hands | shaft planted as a prop | blades forward | bow resting | gun low |
| dodge | hop left, lean | weapon tucked high | tucked | as heavy | both up | bow up | as one |
| block | braced | blade across the face, edge out | blade across, hilt to the right | haft across, hands spread | crossed daggers | bow across as a shield | guard up |
| fumble | stagger back, toe up | arm flung wide | left hand lets go | as heavy | both flung | bow flung | as one |
| fall | on the back, legs out | arms splayed, weapon in hand | left hand lets go | as heavy | both splayed | splayed | as one |
| cheer | arms up | weapon raised | hoisted straight up, two hands | raised one-handed | both up | bow up, fist up | muzzle to the sky |

Style fallbacks: spear → one, pistol → one, heavy → two, polearm → two,
staff → polearm → two, then default. A new weapon class only needs a style
entry where it differs. The renders are `design/art/poses_<style>.png`
(one, heavy = flamberge, heavy_anchor, polearm = halberd, polearm_lance,
spear = javelin, staff, pair, bow, pistol). In each, the top row is the 3/4
front view and the bottom row the side view.

These are static keys for Phase 3. The animation lane (Phase 4) replaces
them with clips. The solver and the style table can stay as the hold layer
on top (second hand, string, flat roll, feet).

## Fallback flag

`BWUnitView.use_rig` (static, default `true`) is read in `setup()`. With
`false` the view builds the original capsule-and-sphere figure with its
hand-set poses, its own breathing and the old bar heights (2.2 / 2.38). The
test suite exercises both paths.

## Performance

Measured with `tools/character_perf.gd`: the real roster screen (20
characters plus the face-panel viewport), 1600×900, vsync off, Forward+, AMD
RX 9070, 300 frames after 90 warm-up frames.

| | rig | primitive |
|---|---|---|
| frame time, mean / p95 | **3.05 / 4.59 ms** (~330 fps) | 1.15 / 1.70 ms |
| GPU / CPU render | 1.14 / 0.48 ms | 0.79 / 0.26 ms |
| draw calls | **382** | 404 |
| objects / primitives | 603 / 320k | 597 / 106k |
| pose solver (all 21 characters) | 0.82 ms per frame (~39 µs each) | n/a |
| screen build (first load, glb import cache cold) | 239 ms | 21 ms |

Draw calls stay flat because the dressed figure is a few skinned meshes,
where the primitive figure was many capsules. Sharing:
- body, garment, hair, armour and weapon meshes come from cached glb
  resources
- each lane has one material per role (verified by `test_shared_resources`)
- trimmed sleeves are shared per garment
- the particle material is a single static resource

The per-instance values (tint, shade, dim, accent) are instance uniforms.
The solver cost is the main CPU addition. If it becomes an issue, it could
skip characters that are off-screen or not blending and update their
breathing at a lower rate.

## Verification

- `--import`, then `-- --self-test`: 160/160 tests in 18 suites
  (`test_character` added).
- `-- --ui-probe`: 10/10. `-- --flow-probe`: passed. No script errors.
- Renders (all Godot, real shaders):
  - `roster_turntable_1.png` and `_2.png`: the 20 characters, front, 3/4
    and back, at close range
  - `roster_turntable_combat.png`: all 20 at the combat camera
  - `poses_*.png`
  - `character_layers.png`: 10 armour-over-outfit cases, front and back
  - `characters_screen_roster.png`, `characters_screen_downtime.png` and
    `characters_screen_prebattle.png`
  - `characters_combat.png` and `characters_cutscene.png`: the arena with
    autoplay
- Rebuild the renders:
  `godot --path game --resolution 1600x900 -s res://tools/character_preview.gd [-- --only poses|turntable|combat|layers --style <s>]`.
  For the screens:
  `godot --path game --resolution 1600x900 -- --screen roster --shot <dir>` and
  `-- --combat arena --autoplay --shot <dir> --every 0.35 --count 60`.

## Decisions I made

1. **Poses are grip targets plus IK, not bone eulers.** It's the only way to
   keep feet planted, both fists on a two-hander, and the draw hand on a
   string across 8 weapon styles with one table. It is also what Phase 4
   will need as a hold layer.
2. **Hand specs live in the chest frame** by default. Lean and breathing
   carry the hands for free. The `root` frame is for aims that must hold a
   direction.
3. **Trim the top to its sleeves** under closed chest armour, rather than
   hiding or keeping it. Hiding bared ink arms under a sleeveless cuirass.
   Keeping it let hoods and collars poke through the plate.
4. **Swap, don't hide, where hiding exposes the body**: chaps get a snug
   short underneath, and a scarf on a sweater_scarf becomes a sweater.
5. **Skirts limit the stance** instead of re-weighting the cloth. One-mesh
   skirts on linear-blend skinning can't follow a lunge, so the pose doesn't
   lunge as far.
6. **Measured hair push.** Long hair is tilted back by exactly what the worn
   collar, hood or plate needs, from mesh profiles, using the hair lane's
   tail bones. Hair is never trimmed or hidden for clothing.
7. **A camera-aware flat roll** instead of a fixed 30° hand roll. A fixed
   roll still goes edge-on from half the camera angles.
8. **Aura only while acting** (windup, strike, cast), in the attuned
   element. Weapon enchantments carry no element, and 20 permanent emitters
   on the roster were noise.
9. **The boss look is presentation data** (`BOSS_LOOK`), not a core change.
   The armour is visual only.
10. **One shared aura-particle `ShaderMaterial` with `dim`** replaces the
    per-emitter StandardMaterial, so the cutscene fade covers particles.
    `BWLook.set_dim` also fades the HP-bar quads, through a `dim_alpha` meta.
11. **The Two-handed heavy idle is a low guard angled to the weapon side.**
    The first try, a shouldered carry, put flamberge and anchor heads through
    the hair and head from the front.

## Open issues

- **The bow string is rigid.** A drawn hand at the chin floats behind an
  undrawn string. That needs a string bone or a morph (weapons and
  animation lanes).
- **Dimmed bystanders still occlude.** In the cutscene, a faded unit
  between the camera and the fight blocks the view
  (`characters_cutscene.png` shows a pillar doing the same). That's the
  cutscene camera's choice, not the figure's.
- **Pose keys are static.** They have no anticipation, overshoot or
  follow-through. Since the Phase 4 clip matrix (`ANIMATION.md`) every
  weapon style plays a clip for every pose; these keys remain the safety
  fallback and the reviewed extremes some reaction clips hit (block,
  kneel, fumble, fall, cheer).
- **Rigid mullet vs hood.** The mullet has no tail bone, so the push can't
  help it. It clears today's hoodie, but a thicker collar would need a
  trimmed variant.
- **Hats with `hide_top` hide the mohawk and other tall crowns entirely.**
  This is the equipment-lane rule. A trimmed hair variant would look better.
- **Kneel with long blades.** The weapon is held up because planting it
  point-down went through the floor. An authored kneel per weapon length
  would read better.
- **Skinned skirts at strike.** The stride limit helps, but a robe at full
  lunge still stretches a little.
- **The solver runs every frame for every character.** That is fine at 20
  (0.8 ms). Gate it on visibility before scenes with many more units.

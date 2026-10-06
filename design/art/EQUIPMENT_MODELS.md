# Armour models (v1)

These are the 23 armour pieces in `game/data/equipment.csv` (8 head, 10 chest,
5 legs). They are chunky low poly in the old-school RuneScape style:
greyscale, white with a black contour, and one accent part that takes the
element colour. All of them sit on the base rig (`RIG.md`).

| File | What | Edit? |
|---|---|---|
| `game/tools/blender/build_equipment.py` | builds every piece from nothing, from `base_rig.blend` | **yes, this is the source** |
| `game/art/equipment/<id>.glb` | one runtime mesh per armour id | generated |
| `game/art/equipment/<id>.glb.import` | LODs, shadow meshes and tangents off; written only if missing | by hand after that |
| `game/art/equipment/equipment_models.json` | manifest: slot, attach, socket, hair_mode, hair_clearance, bones, tris, accent share | generated |
| `game/art/source/equipment.blend` | working file with every piece on the rig | generated, don't hand-edit |
| `game/src/game/character/equipment_view.gd` | `BWEquipmentView`: equip an item onto a `BWCharacterRig` | yes |
| `game/shaders/equipment.gdshader` | flat_opaque plus a per-material `paint` colour | yes |
| `game/tests/test_equipment_models.gd` | coverage, slots, attach, bone names, accent rule, hair_mode | yes |
| `game/tools/equipment_preview.gd` | Godot renders with the real shaders | yes |
| `design/art/equipment_*.png` | renders (listed below) | generated |

## Rebuild

```
blender -b --factory-startup --python game/tools/blender/build_equipment.py
blender -b --factory-startup --python game/tools/blender/build_equipment.py -- --only crown,vest
cd game
godot --headless --path . --import
godot --headless --path . -- --self-test
godot --path . --resolution 1600x900 -s res://tools/equipment_preview.gd            # all sheets
godot --path . --resolution 1600x900 -s res://tools/equipment_preview.gd -- --only head   # head|chest|legs|lineup|pose
```

The build is deterministic: two runs produce byte-identical glbs and
manifest. It refuses to run if `base_rig.blend` is missing, if its
`rig_version` isn't 1, or if a socket has moved. It also fails when an
armour id in the CSV has no builder, or a builder has no CSV row. It prints
one `PIECE` line per piece (attach type, slot, tris, accent %, bones).

## Use

```gdscript
var eq := BWEquipmentView.for_rig(rig)     # a child Node of the rig
eq.equip(item)                             # BWRun.make_item(): base, slot, enchant
eq.equip_model("crown", "ice")             # tools: by id + element ("" = plain)
eq.set_element("chest", "fire")            # recolour in place after a scroll (D203)
eq.unequip("head"); eq.clear()
eq.refresh_hair()                          # after attaching new hair
```

`equip()` refuses items that have no model (such as weapons) or whose slot
doesn't match the manifest. Equipping a slot replaces whatever was in it.
Pieces live under the rig's own nodes, so freeing the rig frees them too.

## Attachment

| Type | Pieces | How |
|---|---|---|
| `socket` (rigid) | all 8 head pieces on `socket_hat`; `bandolier` on `socket_chest` | Unskinned mesh, modelled in socket space with the origin at the socket. `rig.attach()`. |
| `skinned` | the other 14 | The glb carries the 20 deform bones. The view moves its `MeshInstance3D` under the rig's `Skeleton3D` and sets `skeleton = ".."`. The skin binds by bone name, so that is the whole rebind. |

Within a skinned piece, each island takes one of three weight modes:

- **rigid:<bone>**: 100% on one bone. Used for plates and pauldrons:
  platemail (chest, spine and hips hoops, both upper arms), platelegs
  (hips, thighs, shins, feet), the gladiator manica (`upper_arm_r`,
  `forearm_r`), the shoulder guard (`upper_arm_l`) and the shoulder straps
  (`chest`).
- **fit:torso | arms | legs**: nearest-face-interpolated weights from
  `fit_body`. This is the same transfer the clothing lane uses (RIG.md, and
  `build_clothing.py`), restricted to one family of fit_body islands so a
  torso shell never picks up an arm sleeve.
- **skirt**: procedural. Weight runs from hips at the waist toward the
  thigh on that side lower down, capped at 65% so the cloth lags the leg.
  Used by robe skirts, the chain-mail hem, the platemail tabard and the
  tassets.

`design/art/equipment_pose_check.png` puts every skinned or chest/legs piece
in `rig_stress` (elbows and knees at 120°, hip at 100°, spine twisted) to
show the rebind follows the skeleton.

### Layering

These are offsets over `fit_body`. The clothing offsets come from
`build_clothing.py`: pants 0.008–0.016 (baggy sweatpants up to +0.05) and
tops 0.020–0.036 (the hoodie +0.016).

| Layer | Offset | Pieces |
|---|---|---|
| snug | 0.030 | tights, chain sleeves |
| legs | 0.055 | chaps, legs waistbands |
| chest | 0.062 | vest, cuirass, brigandine, robe bodice (clears the hoodie) |
| plate | 0.078 | platemail, platelegs |

Chest armour sits outside legs armour at the waist. Leg tubes are squashed
side to side (`LEG_XS = 0.72`). The rig's hips are 0.05 apart and fit_body's
leg sleeves overlap down to the knee, so round tubes fused into one block.

## Colour: the accent rule

- Every piece has two material slots, **`armour`** and **`accent`**. Vertex
  COLOR holds a flat grey per face: the material tone (white 1.0, light
  0.80, mid 0.56, dark 0.30, ink 0) times a fixed facet shade (1.0, 0.88
  or 0.76 by face normal against an upper-front-left key). That is what
  makes the facets read inside the unlit shader. Normals stay smooth, so
  the inverted hull stays closed.
- **One mesh per piece.** The 7 "<Item> of <Element>" variants are only the
  accent's `paint` colour:
  `BWLook.element_color(BWRun.item_element(item))`. A piece with no
  enchantment uses neutral grey (`BWEquipmentView.NEUTRAL` = GREY_MID 0.55).
  The model id stays `<item_id>`. EQUIPMENT.md's `{item}_{element}` model id
  is now just a name for the tinted variant, not a separate file.
- Materials are shared: one `armour` material and one `accent|<element>`
  material, each with a black 0.020 hull pass. Instance slots follow the
  project rule (dim 0, tint 1), so `BWLook.set_dim` and tints work. The
  accent is a material uniform, not an instance uniform.
- **Accent share** is the accent's outer surface area, from the manifest.
  The target is about 10–15%. Exceptions: the scarf (53%, because its CSV
  note says the whole scarf is the splash, done as stripes and fringe) and
  the gladiator belt and shoulder-guard strap (17–23%). Platemail,
  platelegs and silken_robe are lowest at 6%; their tabard, rivets and sash
  still read at combat distance.

## Hair (hair_mode)

| Mode | Pieces | Effect |
|---|---|---|
| `show` | tiara, crown | hair untouched; the tiara and crown sit on top of the hair (pad 0.13 / 0.12) |
| `hide_top` | feathered_cap, wizard_hat, baseball_cap, tilted_beret | hair stays unless its crown rises above the hat's `hair_clearance` |
| `hide_all` | feathered_full_helm, dragoon_helm | hair node hidden, never deleted (RIG.md) |

`hair_rise()` measures a hair node's crown: the highest vertex within 0.22
of the head axis, in `socket_hair` space, minus the head top. Tails and side
locks don't count. The whole-hair tops of the 10 styles (an upper bound on the crown): buzzed 0.08, high_and_tight
0.10, bob 0.10, ponytail 0.11, long_hair 0.12, mullet 0.14, waterfall 0.15,
ringlets 0.16, long_ponytail 0.19, short_mohawk 0.31. The clearances are
cap 0.10, feathered cap 0.13, beret 0.15 and wizard hat 0.22, so a mohawk
under a cap disappears and a buzz cut shows. Hats are built over head + 0.08
(cap + 0.105), with polygon rings circumscribed so flat facets don't cut
into the hair. If a hair node implements `set_hair_mode(mode)`, the view
calls it, so the hair lane can later trim a style instead of hiding it.

## Pieces

| id | slot | attach | tris | accent | Notes |
|---|---|---|---|---|---|
| feathered_cap | head | socket_hat | 112 | feather 12% | Robin Hood cap: long front peak, crown rising to a back point, turned-up brim, broad feather sweeping up and back on the left |
| feathered_full_helm | head | socket_hat | 226 | plume 16% | octagonal great helm, ink eye slit, breath slots, rim band, arched plume crest |
| wizard_hat | head | socket_hat | 194 | band + star 11% | wide floppy brim, tall crooked cone |
| baseball_cap | head | socket_hat | 114 | patch + button 8% | dome, long bill with a dark underside |
| tilted_beret | head | socket_hat | 196 | pin + ribbons 7% | puffy disc tipped 17° to the right, dark band, stalk |
| tiara | head | socket_hat | 196 | gems 10% | band on the hair, rising to three front peaks |
| crown | head | socket_hat | 288 | gems 11% | six points, dark inside, gems on the tips and band |
| dragoon_helm | head | socket_hat | 190 | crest fin 17% | beaked helm, swept-back horns, jagged spine crest |
| single_shoulder_guard | chest | skinned | 306 | strap 17% | big domed pauldron + 2 lames on the left arm, strap to the right armpit |
| vest | chest | skinned | 304 | lapels 18% | open front, deep armholes, pocket flaps |
| chain_mail | chest | skinned | 792 | collar 8% | hauberk to mid-thigh, short sleeves, grey checker reads as rings |
| platemail | chest | skinned | 800 | tabard 6% | ridged breastplate, gorget, fauld hoops, big pauldrons, belt |
| silken_robe | chest | skinned | 868 | sash 6% | robe to below the knee, bell sleeves, crossed collar, sash tail |
| leather_cuirass | chest | skinned | 608 | stitching 12% | light-grey moulded barrel, shoulder pads, stitched seam and hem |
| brigandine | chest | skinned | 792 | cloth bands 12% | white plate rows with ink rivets between coloured cloth bands |
| scarf | chest | skinned | 240 | stripes 53% | fat wrap, two striped tails with fringe |
| bandolier | chest | socket_chest | 284 | cartridge caps 20% | light belt from left shoulder to right hip, 6 cartridges, buckle |
| gladiator_chestpiece | chest | skinned | 760 | belt 23% | segmented manica + bracer on the right arm, harness, chest disc |
| chaps | legs | skinned | 700 | fringe 9% | light-grey leggings with a fringe of teeth on the outer seams, belt with a V |
| platelegs | legs | skinned | 816 | knee rivets 6% | ridged cuisses, knee cops, greaves, sabatons, fauld and front tassets |
| leather_tassets | legs | skinned | 376 | lacing 10% | belt and five hanging plates tied on with X lacing |
| robe_bottoms | legs | skinned | 384 | hem 13% | floor-length flared skirt, dark sash |
| tights | legs | skinned | 688 | seam stripe 12% | white leggings, stripe down each outer seam, dark waistband |

The body is 2816 tris, so the heaviest full kit (robe + plate helm +
platelegs) adds about 1.9k.

## Renders

All renders come from `tools/equipment_preview.gd`, which uses the game's
shaders. Rows are pieces; the columns are plain, element A and element B,
each from the front and at 3/4. The two elements rotate per row, so all 7
appear. Head rows wear a hair style (it cycles per row) to show hair_mode.

- `equipment_{head,chest,legs}_closeup.png`: about 2× the cutscene scale
- `equipment_{head,chest,legs}_combat.png`: true combat-camera scale (21 u,
  FOV 38 over 900 px, pitch −52°)
- `equipment_lineup.png`: all 23 in one combat-camera frame
- `equipment_pose_check.png`: skinned pieces in `rig_stress`

## How to add a piece

1. Add the row to `equipment.csv` (that's the data lane's call).
2. In `build_equipment.py`, write `def my_piece(): P = Piece("my_piece",
   attach, socket, hair_mode, accent_part, covers=..., notes=...,
   hair_clearance=...)`. Then set `P.mode` before each island (`rigid:<bone>`,
   `fit:torso|arms|legs`, `skirt`) and build it from `loft`, `sheet`, `box`,
   `prism`, `gem` and `tube`. Every primitive is a closed solid. Use tone
   `"acc"` for the accent and keep it near 10–15%.
3. Append it to `BUILDERS`, rebuild, `--import`, run the self-test (it
   checks the CSV/glb/manifest agree, the bones, and the accent share range
   0.04–0.6), and render the preview to look at it.

## Decisions I made

1. **Accent is a per-material colour, not an instance uniform.** The fill and
   the accent share one MeshInstance, and instance uniforms can't differ
   per surface. `equipment.gdshader` is flat_opaque plus `paint`, with
   `dim` pinned to slot 0 like the outline.
2. **Facets are baked into vertex colour** (tone × 3-step shade). The game is
   unlit, so flat faces would otherwise render as flat silhouettes.
3. **The manifest is the runtime contract** (attach, socket, hair_mode,
   hair_clearance). It is generated beside the glbs, so the view never
   disagrees with the build.
4. **Rigid plates are skinned 100% to one bone** rather than parented to
   new sockets, so platemail's breastplate, hoops and pauldrons travel in
   one glb. The bandolier uses `socket_chest` to exercise the socket path
   for chest pieces.
5. **`hide_top` is measured, not trimmed.** The hair lane ships no trimmed
   variants, so hair that would pierce the hat is hidden, and the rest shows
   below the brim.
6. **Hat headroom is 0.08** (the brief's guess was 0.05). Real hair crowns
   sit 0.08–0.12 above the scalp.
7. **Leg armour is squashed to 72% side to side** so two legs read. That
   makes it narrower than the round clothing shells in X; see open issues.
8. **Scarf accent is about 50%**, following its CSV note ("the whole scarf
   is the splash") over the 10–15% guideline. It is done as stripes, so it
   still reads white-and-colour.
9. **Brigandine**: the CSV says the whole cloth cover takes the colour.
   I coloured only the bands between plate rows (12%) to keep the splash
   rule.
10. **Skirt cloth follows the thighs 65% at most.** At 80% the robe spiked
    at 100° hip flexion.

## Open issues

- **Layering against clothing is untested.** There is no clothing runtime
  view yet. The offsets clear the clothing lane's published offsets on the
  torso. The squashed leg tubes (tights especially) are narrower in X than
  baggy sweatpants and will clip them. The manifest's `covers` field lists
  the regions a piece covers, so the outfit code can hide the clothing
  bottoms under tights, chaps or platelegs.
- At combat distance, chest pieces on the upper torso are partly hidden
  under the head from the −52° camera. They read by colour and their
  hem, sleeves and pauldrons. Bulkier shoulders would help if
  playtests say so.
- Long hair isn't checked against chest armour collars (HAIR.md raises the
  same gap).
- The robe skirt still stretches between the legs in deep lunges. That is
  inherent to one-mesh skirts on linear-blend skinning.
- `rig_stress` and `rig_idle` are the only test poses. The real animations
  need another look when they land.

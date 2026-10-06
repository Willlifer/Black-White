class_name BWCharacter
extends Node3D
## One complete, dressed character on the base rig, built from a BWUnit:
##
##   var c := BWCharacter.create(unit)    # rig + hair + clothes + armour + weapon, idle
##   add_child(c)
##   c.pose("strike")                     # a clip if the weapon has a clip set (BWAnimator),
##                                        # else a 0.12 s blend to a static key (BWCharacterPose)
##   c.refresh_equipment()                # after unit.equipment changed
##   c.set_aura("fire", 1.0)              # weapon aura; ("", 0) clears
##
## Assembly order (design/art/CHARACTERS.md):
##   1. rig (BWCharacterRig)              body, skeleton, sockets
##   2. hair on socket_hair               BWHair, coloured by the unit's affinity ranks (D146)
##   3. top + bottom                      BWClothing, in cosmetics.clothing_shade
##   4. armour head / chest / legs        BWEquipmentView (manifest: covers, hair_mode)
##   5. layering pass                     hide / trim / swap what armour covers
##   6. weapon on its socket(s)           BWWeaponView; daggers paired, bows left hand
##   7. pose solver                       BWCharacterPose, keyed by weapon style
##   8. animator                          BWAnimator when the weapon has a clip set
##                                        (BWAnimClips.SETS); it drives the solver
## Only steps 3-7 rerun on refresh_equipment(); the rig and hair stay.
## Hair colour follows the unit's affinity (refresh_hair, D148): re-read at
## build, refresh_equipment(), pose() and set_wounded(), which is a key
## compare when the ranks haven't moved, so picks, Branch out, downtime and
## mid-fight rank-ups show on the next of those without any per-frame work.
##
## Look data comes from the unit (`cosmetics`, `element`, `equipment`,
## `weapon_model`). Units without cosmetics get a deterministic default; the
## boss (id "boss") gets BOSS_LOOK. Nothing here writes to the unit: default
## armour is visual only.
##
## Every part is a child of this node and keeps the project's instance-slot
## contract (dim 0, tint 1), so BWLook.set_dim(character, x) fades it all.
## Meshes and materials are shared across instances (glb resources are cached
## by the ResourceLoader; every lane keeps static material caches).

const BOSS_LOOK := {
	"hair_style": "buzzed", "top": "tank_top", "bottom": "baggy_sweatpants", "clothing_shade": "dark",
	"element": "dark", "weapon": "anchor", "armour": { "chest": "platemail", "legs": "platelegs" },
	"armour_element": "dark",
}
const DEFAULT_HAIR: PackedStringArray = ["buzzed", "bob", "mullet", "ponytail", "short_mohawk"]
const DEFAULT_TOPS: PackedStringArray = ["tshirt", "hoodie", "sweater", "tank_top"]
const DEFAULT_BOTTOMS: PackedStringArray = ["sweatpants", "tight_pants", "shorts"]
const SHADES: PackedStringArray = ["dark", "mid", "light"]
const ARMOUR_SLOTS: PackedStringArray = ["head", "chest", "legs"]

## Chest pieces worn OVER the top without hiding any of it (open or partial).
const OPEN_CHEST: PackedStringArray = ["vest", "bandolier", "scarf", "single_shoulder_guard", "gladiator_chestpiece"]
## Leg pieces that leave the bottom on (they hang over it).
const OVER_LEGS: PackedStringArray = ["leather_tassets"]
## Bottom swapped in under a leg piece that replaces the legs but leaves the
## seat open (chaps have no seat): a snug short keeps the hips clothed.
const UNDER_CHAPS := "tight_shorts"
## Bottoms too full to sit under a knee-length skirt: swapped for a slimmer cut.
const UNDER_SKIRT := { "baggy_sweatpants": "sweatpants", "shorts": "tight_shorts" }
## How far the stance may open (1 = authored) with a skirt-like piece on.
const STRIDE := { "robe_bottoms": 0.35, "silken_robe": 0.45, "chain_mail": 0.8, "platemail": 0.85 }

var unit: BWUnit
var look := {}
var rig: BWCharacterRig
var hair: BWHair
var weapon: BWWeaponView
var equipment: BWEquipmentView
var poser: BWCharacterPose
var layering := {}               ## what the last layering pass did (tests, docs)
var breathing := true
var animator: BWAnimator         ## null: static key poses only (no clip set for this weapon)
## false = never build an animator (static key poses everywhere). Read on refresh_equipment().
static var animate := true
## The roster stage: more weapon-handling variety (BWAnimator.set_showcase).
var showcase := false:
	set(v):
		showcase = v
		if animator:
			animator.set_showcase(v)
var _phase := 0.0
var _weapon_id := ""
var _last_pos := Vector3.INF     # root motion, for the animator (walk rate, inertia, turns)
var _last_vel := Vector3.ZERO
var _last_yaw := INF
var _yaw_vis := 0.0              # visual turn smoothing on the rig (s-curve, not a snap)
var _yaw_vis_v := 0.0
var _turning := false            # an authored turn clip drives _yaw_vis
var _turn_from := 0.0
var _nocked: BWProjectileView    # bows: the arrow on the string between nock and release
var _buzz := -1.0                # bows: seconds since the release (string vibration); < 0 = off
var _loosed := Transform3D()     # bows: the nocked arrow's last world transform (the release)
var _stowing := false            # bows: the arrow on the string is a handling one (no release)
var _nocks: Array[BWProjectileView] = []   # D164: the arrows on the string (3 for a fan); _nocked = _nocks[0]
var _drawn := 1                  # D164: how many were on the string at the last draw
var _loosed_all: Array = []      # D164: every loosed arrow's last world transform (a fan: 3)
## D164: the fletching's element for the arrows nocked now (null = attuned).
var nock_element: Variant = null
const FAN_SPREAD := 0.13         # radians between fanned arrows on the string
var _sparkle := -1.0             # staves: the aura strength a handling sparkle set (< 0: none)
var _sparkle_prev := ["", 0.0]   # the aura before the sparkle

static var _sleeves := {}        # garment id -> ArrayMesh (torso trimmed away)
static var _depth := {}          # mesh id -> {bin: z} back-depth profiles


static func create(u: BWUnit) -> BWCharacter:
	var c := BWCharacter.new()
	c.build(u)
	return c


## The resolved look for a unit: hair, clothes, shade, element, weapon, plus
## visual-only default armour for the boss.
static func look_for(u: BWUnit) -> Dictionary:
	var cos: Dictionary = u.cosmetics
	var h := absi(hash(u.id))
	var out := {
		"hair_style": str(cos.get("hair_style", DEFAULT_HAIR[h % DEFAULT_HAIR.size()])),
		# per-character hair variation, derived from the id (never stored in a CSV)
		"hair_variant": int(cos.get("hair_variant", BWHair.variant_for(u.id))),
		"top": str(cos.get("top", DEFAULT_TOPS[h % DEFAULT_TOPS.size()])),
		"bottom": str(cos.get("bottom", DEFAULT_BOTTOMS[(h / 7) % DEFAULT_BOTTOMS.size()])),
		"clothing_shade": str(cos.get("clothing_shade", SHADES[(h / 3) % 3])),
		"element": u.element, "armour": {}, "armour_element": "",
	}
	if u.id == "boss" or (u.size > 1 and not cos.has("hair_style")):
		out.merge(BOSS_LOOK, true)
		if u.element != "":
			out.element = u.element
	out["weapon"] = weapon_id_for(u, str(out.get("weapon", "")))
	return out


## The weapon model to show: the equipped main hand, else weapon_model, else
## the first model of the unit's weapon class.
static func weapon_id_for(u: BWUnit, fallback: String = "") -> String:
	var mh: Dictionary = u.equipment.get("main_hand", {})
	for id in [str(mh.get("base", "")), u.weapon_model, fallback]:
		if id != "" and not BWWeaponView.meta_for(id).is_empty():
			return id
	for id in BWWeaponView.ids():
		if str(BWWeaponView.meta_for(id).get("class", "")) == u.weapon_class:
			return id
	return "sword"


# ------------------------------------------------------------------ build

func build(u: BWUnit) -> bool:
	unit = u
	name = "character_" + u.id
	look = look_for(u)
	rig = BWCharacterRig.new()
	rig.name = "rig"
	add_child(rig)
	if not rig.build():
		return false
	if rig.anim:
		rig.anim.stop()
	poser = BWCharacterPose.new(rig.skeleton)
	poser.socket_r = rig.socket("weapon_r").transform
	poser.socket_l = rig.socket("offhand_l").transform
	_phase = float(absi(hash(u.id)) % 628) / 100.0
	hair = BWHair.create(str(look.hair_style), str(look.element), int(look.get("hair_variant", 0)))
	if hair == null:
		hair = BWHair.create("buzzed", str(look.element), int(look.get("hair_variant", 0)))
	if hair:
		hair.attach_to(rig)
		poser.hair_skeleton = hair.skeleton
		refresh_hair()
	equipment = BWEquipmentView.for_rig(rig)
	refresh_equipment()
	return true


## Re-dress from the unit: clothes, armour, layering, weapon, pose set.
## Safe to call any time; parts that didn't change are kept.
func refresh_equipment() -> void:
	if rig == null or unit == null:
		return
	look = look_for(unit)
	refresh_hair()
	# 3. clothes (base outfit; the layering pass may swap or trim them)
	_wear("top", str(look.top))
	_wear("bottom", str(look.bottom))
	# 4. armour
	equipment.clear()
	for slot in ARMOUR_SLOTS:
		var item: Dictionary = unit.equipment.get(slot, {})
		if not item.is_empty() and BWEquipmentView.has_model(str(item.get("base", ""))):
			equipment.equip(item)
		elif (look.armour as Dictionary).has(slot):
			equipment.equip_model(str(look.armour[slot]), str(look.armour_element))
	# 5. layering
	_layer()
	# 6. weapon
	var wid := str(look.weapon)
	if wid != _weapon_id or weapon == null:
		var aura := weapon.aura_element if weapon else ""
		var strength := weapon.aura_strength if weapon else 0.0
		if weapon:
			weapon.detach()
			weapon.free()
		weapon = BWWeaponView.create(wid)
		_weapon_id = wid
		if weapon:
			weapon.attach_to(rig)
			if aura != "":
				weapon.set_aura(aura, strength)
	# 7. poses
	poser.set_weapon(weapon.meta if weapon else {})
	if poser.current == "":
		poser.play("idle", 0.0)
	poser.update(0.0)
	# 8. clips
	var sid := BWAnimClips.set_for(weapon.meta) if weapon and animate else ""
	if animator and animator.set_id != sid:
		animator.dispose()
		animator = null
	if sid != "" and animator == null:
		animator = BWAnimator.new(self, sid)
		animator.set_showcase(showcase)
		animator.play(poser.current if poser.current != "" else "idle", 0.0)
		animator.update(0.0)


func _wear(slot: String, id: String) -> void:
	var mi := BWClothing.garment(rig, slot)
	if mi and str(mi.get_meta("clothing_id", "")) == id:
		mi.visible = true
		if mi.has_meta("full_mesh"):
			mi.mesh = mi.get_meta("full_mesh")
			mi.remove_meta("full_mesh")
		BWClothing._set_shade_on(mi, str(look.clothing_shade))
		return
	if id != "":
		BWClothing.wear(rig, id, str(look.clothing_shade))


# --------------------------------------------------------------- layering

## Resolve the lanes' open layering issues for what is worn now:
##  - chest armour that covers the torso trims the top to its sleeves (the
##    arms stay clothed, nothing pokes through the plate); one that also
##    covers the arms (robe) hides the top; open pieces (vest, bandolier,
##    scarf, pauldron, harness) layer over it by offset
##  - the scarf piece replaces the sweater's own scarf (sweater_scarf -> sweater)
##  - leg armour that covers the legs hides the bottom (tights / platelegs /
##    robe bottoms over baggy pants clipped); chaps have no seat, so a snug
##    short goes under them; tassets hang over whatever is worn
##  - a knee-length skirt (silken robe) swaps full bottoms for a slimmer cut,
##    and every skirt narrows the pose stance (poser.stride)
##  - long hair is tilted back by the measured amount that clears the collar,
##    hood or plate (hair_push)
## Garments are hidden or swapped, never deleted, so unequipping restores them.
func _layer() -> void:
	layering = { "top": "show", "bottom": "show", "swaps": {}, "stride": 1.0, "hair_push": 0.0 }
	var eq := equipment.equipped()
	var chest := str(eq.get("chest", ""))
	var legs := str(eq.get("legs", ""))
	var top_id := str(look.top)
	var bottom_id := str(look.bottom)
	if chest == "scarf" and top_id == "sweater_scarf":
		_swap("top", "sweater")
	if chest == "silken_robe" and UNDER_SKIRT.has(bottom_id) and legs == "":
		_swap("bottom", UNDER_SKIRT[bottom_id])
	if legs == "chaps":
		_swap("bottom", UNDER_CHAPS)
	elif legs != "" and not legs in OVER_LEGS and "legs" in _covers(legs):
		_hide("bottom")
	if chest != "" and not chest in OPEN_CHEST and "torso" in _covers(chest):
		if "arms" in _covers(chest):
			_hide("top")
		else:
			_trim_to_sleeves("top")
	var stride := 1.0
	for id in [chest, legs]:
		stride = minf(stride, float(STRIDE.get(id, 1.0)))
	layering.stride = stride
	poser.stride = stride
	poser.hair_push = _hair_push()
	layering.hair_push = poser.hair_push


static func _covers(base: String) -> Array:
	return BWEquipmentView.info(base).get("covers", [])


func _hide(slot: String) -> void:
	var mi := BWClothing.garment(rig, slot)
	if mi:
		mi.visible = false
	layering[slot] = "hidden"


func _swap(slot: String, id: String) -> void:
	var mi := BWClothing.garment(rig, slot)
	if mi == null or str(mi.get_meta("clothing_id", "")) != id:
		BWClothing.wear(rig, id, str(look.clothing_shade))
	layering.swaps[slot] = id


## Replace the garment's mesh with its sleeves only: triangles whose three
## vertices all lean mostly on arm bones. Built once per garment and shared.
func _trim_to_sleeves(slot: String) -> void:
	var mi := BWClothing.garment(rig, slot)
	if mi == null:
		return
	var id := str(mi.get_meta("clothing_id", ""))
	var full: Mesh = mi.get_meta("full_mesh") if mi.has_meta("full_mesh") else mi.mesh
	if not _sleeves.has(id):
		_sleeves[id] = _sleeves_of(full, mi.skin)
	var sl: ArrayMesh = _sleeves[id]
	if sl == null:
		_hide(slot)
		return
	mi.set_meta("full_mesh", full)
	mi.mesh = sl
	for i in sl.get_surface_count():
		mi.set_surface_override_material(i, BWClothing.material())
	layering[slot] = "sleeves"


static func _sleeves_of(mesh: Mesh, skin: Skin) -> ArrayMesh:
	if skin == null:
		return null
	var arm := {}
	for b in skin.get_bind_count():
		var bn := str(skin.get_bind_name(b))
		arm[b] = bn.begins_with("upper_arm") or bn.begins_with("forearm") or bn.begins_with("hand")
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		var on_arm := PackedByteArray()
		on_arm.resize(verts.size())
		for v in verts.size():
			var w := 0.0
			for k in per:
				if arm.get(bones[v * per + k], false):
					w += weights[v * per + k]
			on_arm[v] = 1 if w > 0.5 else 0
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if on_arm[idx[t]] and on_arm[idx[t + 1]] and on_arm[idx[t + 2]]:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if keep.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = keep
		var flags: int = mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return out if out.get_surface_count() > 0 else null


## Tilt (radians, tip back) that long hair needs to clear what is worn on the
## back. Measured from rest meshes: the hair curtain's innermost depth per
## height band vs the worn garments' / armour's outermost back depth.
func _hair_push() -> float:
	if hair == null or hair.skeleton == null or not hair.visible:
		return 0.0
	var tail := hair.skeleton.find_bone("hair_tail_01")
	if tail < 0:
		return 0.0
	var pivot_y := hair.skeleton.get_bone_global_rest(tail).origin.y + 1.92
	var back := {}      # band -> most negative z of clothing/armour at the back
	for mi in _worn_meshes():
		var prof := _profile(mi, true, 0.0)
		for k in prof:
			back[k] = minf(back.get(k, 1.0), prof[k])
	var need := 0.0
	for mi in hair.meshes:
		var prof := _profile(mi, false, 1.92)
		for k in prof:
			if not back.has(k):
				continue
			var y := (float(k) + 0.5) * 0.05
			if y > pivot_y - 0.06:
				continue
			var deficit: float = prof[k] - (back[k] - 0.035)
			if deficit > 0.0:
				need = maxf(need, atan(deficit / (pivot_y - y)))
	return minf(need, 0.6)


func _worn_meshes() -> Array:
	var out: Array = []
	for slot in ["top", "bottom"]:
		var mi := BWClothing.garment(rig, slot)
		if mi and mi.visible:
			out.append(mi)
	for slot in ["chest"]:
		var p := equipment.piece(slot)
		if p:
			for mi in BWEquipmentView.meshes_of(p):
				if mi.skin != null:
					out.append(mi)
	return out


## Per 5 cm height band, near the spine (|x| < 0.13) and behind it (z < 0):
## garments -> the most negative z (outer back surface); hair -> the largest z
## (the curtain's inner face). Rest pose, model space; cached per mesh.
static func _profile(mi: MeshInstance3D, garment: bool, y_off: float) -> Dictionary:
	var key := "%d|%s" % [mi.mesh.get_rid().get_id(), garment]
	if _depth.has(key):
		return _depth[key]
	var prof := {}
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		for p: Vector3 in arr[Mesh.ARRAY_VERTEX]:
			var y := p.y + y_off
			if absf(p.x) > 0.13 or p.z > -0.03 or y < 0.7 or y > 1.62:
				continue
			var k := int(floor(y / 0.05))
			if garment:
				prof[k] = minf(prof.get(k, 1.0), p.z)
			else:
				prof[k] = maxf(prof.get(k, -1.0), p.z)
	_depth[key] = prof
	return prof


## D146/D148: recolour the hair from the unit's affinity ranks (strongest
## element at the tips; rank 0 = unaligned grey). A look element with no affinity
## behind it (the boss look) stays solid. Returns true when it changed.
func refresh_hair() -> bool:
	if hair == null or unit == null:
		return false
	if BWLook.hair_ranks(unit.affinity).is_empty() and str(look.get("element", "")) != "":
		var c := BWLook.element_color(str(look.element))
		if hair.look_key == "#" + c.to_html(false):
			return false
		hair.set_element(str(look.element))
		return true
	return hair.set_affinity(unit.affinity, unit.focus())


# ------------------------------------------------------------------ poses

## Play a pose: the weapon's clip for it when it has one, else the static
## key. blend < 0 = the default (clips: BWAnimator.BLENDS; keys: 0.12 s);
## 0 snaps (a clip snaps to its "pose" marker frame: stills and tests).
func pose(pose_name: String, blend: float = -1.0) -> void:
	refresh_hair()
	if animator:
		animator.play(pose_name, blend)
		poser.current = pose_name if pose_name in BWCharacterPose.POSE_NAMES else poser.current
		if blend == 0.0:
			animator.update(0.0)
		return
	poser.play(pose_name, BWCharacterPose.BLEND if blend < 0.0 else blend)
	if blend == 0.0:
		poser.update(0.0)


func pose_name() -> String:
	if animator:
		return animator.current
	return poser.current if poser else ""


## True when the weapon's clip set animates this pose (else it is a static key).
func has_clip(pose_name: String) -> bool:
	return animator != null and animator.has_clip(pose_name)


## HP below BWAnimator.WOUNDED_HP of max: the wounded idle and the limp.
func set_wounded(v: bool) -> void:
	refresh_hair()
	if animator:
		animator.set_wounded(v)


func weapon_style() -> String:
	return poser.style if poser else ""


func set_aura(element: String, strength: float = 1.0) -> void:
	if weapon:
		weapon.set_aura(element, strength)


func _process(delta: float) -> void:
	if poser == null:
		return
	if breathing:
		_phase = fmod(_phase + delta * 2.4, TAU)
	poser.breathe = _phase
	var vp := get_viewport()
	poser.camera = vp.get_camera_3d() if vp else null
	if animator:
		_track_motion(delta)
		animator.update(delta)
		_update_bow(delta)
		_update_sparkle()
	else:
		poser.update(delta)


## Bows: inside a shot clip's arrow windows (meta.arrows, D164: [[nock s,
## release s], ...]; a volley has several) an arrow sits on the string (its
## tail at the draw hand, pointing through the arrow rest) and the string
## bends to the hand in two segments (BWWeaponView.set_string_draw); after
## each release the string snaps straight with a short buzz. A fan clip
## (meta.fan = 3, Split Arrow) nocks three arrows spread in the bow's plane.
## Fletching takes `nock_element` (the shot's element; null = attuned, "" =
## plain white). The flying arrows belong to the combat (BWRangedVFX).
func _update_bow(delta: float) -> void:
	if weapon == null or animator == null or not weapon.has_string() or poser.globals.is_empty():
		return
	var drawing := false
	var stow := false
	var fan := 1
	if not animator.layers.is_empty():
		var top: Dictionary = animator.layers.back()
		if top.kind == "clip":
			var cm := animator.clip_meta(str(top.clip))
			var t := float(top.t)
			if cm.has("arrows"):
				for w in cm.arrows:
					if t >= float(w[0]) - 0.5 / BWAnimClips.FPS and t < float(w[1]):
						drawing = true
				fan = int(cm.get("fan", 1))
			elif str(top.clip) == "strike":
				var n := animator.marker_time("strike", "nock")
				var r := animator.marker_time("strike", "release")
				drawing = n >= 0.0 and r > n and t >= n - 0.5 / BWAnimClips.FPS and t < r
			else:
				# weapon handling (act_sight): an arrow nocked, sighted and stowed
				var aw: Array = cm.get("arrow", [])
				if aw.size() == 2:
					drawing = t >= float(aw[0]) and t < float(aw[1])
					stow = true
	if drawing:
		_stowing = stow
	elif _stowing and is_instance_valid(_nocked) and _nocked.visible:
		# a stowed arrow just vanishes: no release, no string buzz
		_hide_nocked()
		_stowing = false
		_buzz = -1.0
		weapon.set_string_draw(null)
		return
	var G := poser.globals
	var bow: Transform3D = (G.hand_l as Transform3D) * poser.socket_l
	var nock: Vector3 = bow.affine_inverse() * ((G.hand_r as Transform3D) * poser.socket_r).origin
	if drawing:
		_buzz = 0.0
		weapon.set_string_draw(nock)
		while _nocks.size() < fan:
			var pv := BWProjectileView.create_projectile("arrow")
			if pv == null:
				return
			pv.name = "nocked_arrow" if _nocks.is_empty() else "nocked_arrow_%d" % _nocks.size()
			weapon.add_child(pv)
			_nocks.append(pv)
		_nocked = _nocks[0]
		var el: String = str(nock_element) if nock_element != null else (unit.attuned if unit else "")
		var rest := BWWeaponView.v3(weapon.meta.get("tip", [0, 0, 0.05]))
		var dir := (rest - nock).normalized()
		if dir.length() < 0.5:
			dir = Vector3.BACK
		# the fan spreads in the bow's plane (about the axis across the limbs)
		var across := dir.cross(Vector3.UP)
		across = across.normalized() if across.length() > 1e-3 else Vector3.RIGHT
		for i in _nocks.size():
			var pv: BWProjectileView = _nocks[i]
			if i >= fan:
				pv.visible = false
				continue
			var d := dir
			if fan > 1:
				d = dir.rotated(across, (float(i) - float(fan - 1) * 0.5) * FAN_SPREAD)
			pv.set_accent(el)
			pv.transform = Transform3D(Basis.looking_at(d, Vector3.UP, true), nock + d * pv.length())
			pv.visible = true
		_drawn = fan
		return
	if not _nocks.is_empty() and _nocks[0].visible and _nocks[0].is_inside_tree():
		_loosed = _nocks[0].global_transform
		_loosed_all = []
		for i in mini(_drawn, _nocks.size()):
			_loosed_all.append(_nocks[i].global_transform)
	_hide_nocked()
	if _buzz >= 0.0:
		_buzz += delta
		if _buzz < 0.22:
			var ends: Array = weapon.meta.string
			var mid := (BWWeaponView.v3(ends[0]) + BWWeaponView.v3(ends[1])) * 0.5
			weapon.set_string_draw(mid + Vector3(0, 0, -0.05 * absf(cos(_buzz * 75.0)) * exp(-_buzz * 16.0)))
			return
		_buzz = -1.0
	weapon.set_string_draw(null)


func _hide_nocked() -> void:
	for pv in _nocks:
		if is_instance_valid(pv):
			pv.visible = false


## Staves (weapon handling, act_twirl): the clip's meta.sparkle curve
## ([[s, strength], ...]) lights the weapon's aura in the unit's element;
## after it the aura goes back to what it was, unless something else (a
## cast) changed it meanwhile.
func _update_sparkle() -> void:
	if weapon == null or animator == null or animator.layers.is_empty():
		return
	var top: Dictionary = animator.layers.back()
	var curve: Array = animator.clip_meta(str(top.get("clip", ""))).get("sparkle", []) if top.kind == "clip" else []
	var el := (unit.attuned if unit.attuned != "" else unit.element) if unit else ""
	if curve.size() >= 2 and el != "":
		var t := float(top.t)
		var v := 0.0
		for i in range(1, curve.size()):
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			if t >= float(a[0]) and t <= float(b[0]):
				v = lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4))
		if _sparkle < 0.0:
			_sparkle_prev = [weapon.aura_element, weapon.aura_strength]
		if v > 0.02:
			weapon.set_aura(el, v)
			_sparkle = v
		elif _sparkle > 0.0:
			weapon.set_aura(str(_sparkle_prev[0]), float(_sparkle_prev[1]))
			_sparkle = 0.0
		return
	if _sparkle >= 0.0:
		if _sparkle > 0.0 and is_equal_approx(weapon.aura_strength, _sparkle):
			weapon.set_aura(str(_sparkle_prev[0]), float(_sparkle_prev[1]))
		_sparkle = -1.0


## The nocked arrow's world transform while a bow is drawn, or where it
## was loosed in the last 0.3 s (the combat launches its flying arrow from
## there, so the hand-over is seamless); null otherwise.
func nocked_arrow() -> Variant:
	if is_instance_valid(_nocked) and _nocked.visible and _nocked.is_inside_tree():
		return _nocked.global_transform
	if _buzz >= 0.0 and _buzz < 0.3:
		return _loosed
	return null


## D164: every arrow on the string (a fan: three) as world transforms, or
## the ones just loosed (0.3 s); [] otherwise.
func nocked_arrows() -> Array:
	var out: Array = []
	for pv in _nocks:
		if is_instance_valid(pv) and pv.visible and pv.is_inside_tree():
			out.append(pv.global_transform)
	if not out.is_empty():
		return out
	if _buzz >= 0.0 and _buzz < 0.3:
		return _loosed_all.duplicate()
	return []


## Root motion as the animator sees it: velocity / acceleration in the
## character's own frame and the yaw rate. A teleport (> 1.5 u in a frame)
## resets instead of reading as a huge acceleration. Also smooths turns:
## the view's yaw snaps (BWUnitView.face), the rig turns on an s-curve.
func _track_motion(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	var gp := global_position
	var yaw := atan2(global_basis.z.x, global_basis.z.z)
	if _last_pos == Vector3.INF or gp.distance_to(_last_pos) > 1.5:
		_last_pos = gp
		_last_vel = Vector3.ZERO
		_last_yaw = yaw
	var vel := (gp - _last_pos) / delta
	var acc := (vel - _last_vel) / delta
	if delta > 0.1:                          # a hitch: don't read it as a jolt
		acc = Vector3.ZERO
	var inv := global_basis.orthonormalized().inverse()
	animator.velocity = inv * vel
	animator.accel = animator.accel.lerp(inv * acc, 1.0 - exp(-delta * 30.0))
	var dyaw := wrapf(yaw - _last_yaw, -PI, PI)
	var vis0 := _yaw_vis
	_last_pos = gp
	_last_vel = vel
	_last_yaw = yaw
	# visual turn: keep facing where we were, then catch up (critically damped)
	_yaw_vis = wrapf(_yaw_vis - dyaw, -PI, PI)
	# a snap turn while standing plays an authored turn: its `turn` channel
	# (0..1) is the share of the angle done, so the steps and the yaw agree
	var started := false
	if absf(dyaw) > 0.5 and Vector2(vel.x, vel.z).length() < 0.3 and animator.can_turn():
		animator.start_turn(signf(dyaw))
		_turning = true
		_turn_from = _yaw_vis
		started = true
	if _turning:
		var tp := animator.turn_progress()
		if tp < 0.0:
			_turning = false
		else:
			if absf(dyaw) > 1e-4 and not started:
				_turn_from = wrapf(_turn_from - dyaw, -PI, PI)
			_yaw_vis = _turn_from * (1.0 - tp)
			_yaw_vis_v = 0.0
			rig.rotation.y = _yaw_vis + animator.spin_yaw()      # D102: a spin clip turns the whole body
			animator.yaw_rate = (dyaw + _yaw_vis - vis0) / delta
			return
	# exact critically damped step (stable at any frame time)
	var w := 22.0
	var e := exp(-w * delta)
	var tmp := (_yaw_vis_v + w * _yaw_vis) * delta
	_yaw_vis = (_yaw_vis + tmp) * e
	_yaw_vis_v = (_yaw_vis_v - w * tmp) * e
	if not (is_finite(_yaw_vis) and is_finite(_yaw_vis_v)):
		_yaw_vis = 0.0
		_yaw_vis_v = 0.0
	if absf(_yaw_vis) < 1e-4 and absf(_yaw_vis_v) < 1e-3:
		_yaw_vis = 0.0
		_yaw_vis_v = 0.0
	rig.rotation.y = _yaw_vis + animator.spin_yaw()      # D102: a spin clip turns the whole body
	# the turn the eye sees (snap + smoothing), for the head-leads-the-turn layer
	animator.yaw_rate = (dyaw + _yaw_vis - vis0) / delta


# ------------------------------------------------------------------ parts

## Named parts for tests and tools: hair, top, bottom, weapon, offhand,
## head, chest, legs (armour). Null when absent.
func part(part_name: String) -> Node3D:
	match part_name:
		"hair": return hair
		"top", "bottom": return BWClothing.garment(rig, part_name)
		"weapon": return weapon
		"offhand": return weapon.offhand_view if weapon else null
		"head", "chest", "legs": return equipment.piece(part_name)
	return null


## Triangles drawn for this character (body + visible parts), for budgets.
func triangle_count() -> int:
	var n := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree() or not is_inside_tree():
			if not (mi as MeshInstance3D).visible:
				continue
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null or str(mi.name) == "aura_shell":
				continue
			for i in m.get_surface_count():
				var c: int = m.surface_get_array_index_len(i)
				n += (c if c > 0 else m.surface_get_array_len(i)) / 3
	return n

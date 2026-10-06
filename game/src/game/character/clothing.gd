class_name BWClothing
extends RefCounted
## Clothing on a BWCharacterRig. Each garment is art/clothing/<id>.glb
## (built by tools/blender/build_clothing.py, never hand-edited): one skinned
## mesh bound to the rig's 20 bone names. Wearing it moves that mesh under
## the rig's own Skeleton3D and points its skin there, so it deforms with
## every animation the rig plays. See design/art/CLOTHING.md.
##
##   BWClothing.dress(rig, "hoodie", "tight_pants", "dark")
##   BWClothing.dress_from_row(rig, BWRosterGen.row_by_id(BWData.table("roster"), "kai"))
##   BWClothing.wear(rig, "shorts", "light")      # replaces the bottom only
##   BWClothing.set_shade(rig, "mid")             # recolour everything worn
##   BWClothing.remove(rig, "top")
##
## Shading: one shared material pair (clothing.gdshader + clothing_outline as
## next pass) for every garment. The shade is the per-instance `shade`
## uniform (0 dark, 1 mid, 2 light) indexing the 3x3 palette texture; the
## contour colour comes from the palette too (white on dark, black on mid
## and light: rule in CLOTHING.md). BWLook.set_dim fades garments like the
## body, since they share the `dim` instance slot.
##
## Extra bones: only the ones in EXTRA_BONES, added to the rig's skeleton on
## demand (the scarf tail). They are appended, so the 20 rig bones keep
## their indices and the rig's animations are untouched.
##
## Independent of the combat code: it needs BWCharacterRig and the shaders.

const DIR := "res://art/clothing/"
const CLOTHING_VERSION := 1
const RIG_VERSION := 1             ## base rig the garments were fitted to
const PALETTE := "res://art/clothing/clothing_palette.png"
const FILL_SHADER := "res://shaders/clothing.gdshader"
const OUTLINE_SHADER := "res://shaders/clothing_outline.gdshader"
const OUTLINE := 0.02              ## hull width (body ink 0.018, head 0.026)

const TOPS: PackedStringArray = ["tank_top", "crop_top", "hoodie", "crop_hoodie", "tshirt", "sweater", "sweater_scarf"]
const BOTTOMS: PackedStringArray = ["baggy_sweatpants", "sweatpants", "tight_pants", "ripped_tight_pants",
	"tight_shorts", "shorts", "short_shorts"]
const SHADES := {"dark": 0, "mid": 1, "light": 2}

## Bones a garment may add on top of BWCharacterRig.BONES:
## name -> {parent, garments}. Rest transforms come from the garment's glb.
const EXTRA_BONES := {
	"scarf_tail": {"parent": "chest", "garments": ["sweater_scarf"]},
}

static var _fill: ShaderMaterial
static var _scenes := {}


# ---------------------------------------------------------------- catalogue

static func ids() -> PackedStringArray:
	return TOPS + BOTTOMS


static func slot_of(id: String) -> String:
	if id in TOPS:
		return "top"
	if id in BOTTOMS:
		return "bottom"
	return ""


static func path_for(id: String) -> String:
	return DIR + id + ".glb"


static func has_garment(id: String) -> bool:
	return slot_of(id) != "" and ResourceLoader.exists(path_for(id))


static func shade_index(shade: String) -> int:
	return SHADES.get(shade, 1)


## The contour colour for a fill value (0..1, sRGB). The palette's row 2 is
## built from this rule; the test checks they agree.
static func contour_for(fill_value: float) -> Color:
	return Color.WHITE if fill_value < 0.5 else Color.BLACK


# ---------------------------------------------------------------- wearing

## Wear a top and a bottom (either may be "") in one shade.
static func dress(rig: BWCharacterRig, top: String, bottom: String, shade: String = "mid") -> bool:
	var ok := true
	for id in [top, bottom]:
		if id != "":
			ok = wear(rig, id, shade) != null and ok
	return ok


## Dress from a roster row (top, bottom, clothing_shade columns).
static func dress_from_row(rig: BWCharacterRig, row: Dictionary) -> bool:
	return dress(rig, str(row.get("top", "")), str(row.get("bottom", "")), str(row.get("clothing_shade", "mid")))


## Put one garment on, replacing whatever is in its slot. Returns the
## garment's MeshInstance3D (a child of rig.skeleton), or null on error.
static func wear(rig: BWCharacterRig, id: String, shade: String = "mid") -> MeshInstance3D:
	var slot := slot_of(id)
	if slot == "":
		push_error("BWClothing: unknown garment '%s'" % id)
		return null
	if rig.skeleton == null and not rig.build():
		return null
	var scene := _scene(id)
	if scene == null:
		return null
	var inst := scene.instantiate()
	var src_skel: Skeleton3D = null
	var sk := inst.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		src_skel = sk[0]
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty() or src_skel == null:
		push_error("BWClothing: %s has no skinned mesh" % path_for(id))
		inst.free()
		return null
	var mi: MeshInstance3D = found[0]
	if not _ensure_bones(rig.skeleton, src_skel, mi.skin, id):
		inst.free()
		return null
	remove(rig, slot)
	var xf := _relative(mi, src_skel)
	mi.get_parent().remove_child(mi)
	inst.free()
	mi.name = "clothing_" + slot
	mi.owner = null
	rig.skeleton.add_child(mi)
	mi.transform = xf
	mi.skeleton = mi.get_path_to(rig.skeleton)
	mi.set_meta("clothing_id", id)
	mi.set_meta("clothing_slot", slot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, material())
	_set_shade_on(mi, shade)
	if id == "sweater_scarf":
		_add_sway(rig.skeleton)
	return mi


## Take off the garment in a slot ("top" / "bottom"). Extra bones stay.
static func remove(rig: BWCharacterRig, slot: String) -> void:
	var mi := garment(rig, slot)
	if mi:
		if mi.get_meta("clothing_id", "") == "sweater_scarf":
			var sw := rig.skeleton.get_node_or_null("clothing_scarf_sway")
			if sw:
				sw.get_parent().remove_child(sw)
				sw.queue_free()
		mi.get_parent().remove_child(mi)
		mi.queue_free()


static func garment(rig: BWCharacterRig, slot: String) -> MeshInstance3D:
	if rig == null or rig.skeleton == null:
		return null
	return rig.skeleton.get_node_or_null("clothing_" + slot) as MeshInstance3D


## {"top": id, "bottom": id} of what the rig wears.
static func worn(rig: BWCharacterRig) -> Dictionary:
	var out := {}
	for slot in ["top", "bottom"]:
		var mi := garment(rig, slot)
		if mi:
			out[slot] = str(mi.get_meta("clothing_id", ""))
	return out


static func set_shade(rig: BWCharacterRig, shade: String) -> void:
	for slot in ["top", "bottom"]:
		var mi := garment(rig, slot)
		if mi:
			_set_shade_on(mi, shade)


static func _set_shade_on(mi: MeshInstance3D, shade: String) -> void:
	if not SHADES.has(shade):
		push_warning("BWClothing: unknown clothing_shade '%s', using mid" % shade)
	mi.set_meta("clothing_shade", shade if SHADES.has(shade) else "mid")
	mi.set_instance_shader_parameter("shade", float(shade_index(shade)))


# ---------------------------------------------------------------- material

## The one clothing material (fill + contour next pass), shared by all.
static func material() -> ShaderMaterial:
	if _fill == null:
		var pal := load(PALETTE) as Texture2D
		var ol := ShaderMaterial.new()
		ol.shader = load(OUTLINE_SHADER)
		ol.set_shader_parameter("palette", pal)
		ol.set_shader_parameter("width", OUTLINE)
		ol.resource_name = "bw_clothing_outline"
		_fill = ShaderMaterial.new()
		_fill.shader = load(FILL_SHADER)
		_fill.set_shader_parameter("palette", pal)
		_fill.next_pass = ol
		_fill.resource_name = "bw_clothing"
	return _fill


# ---------------------------------------------------------------- internals

static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		var p := path_for(id)
		var s := load(p) as PackedScene if ResourceLoader.exists(p) else null
		if s == null:
			push_error("BWClothing: cannot load %s (run --import?)" % p)
			return null
		_scenes[id] = s
	return _scenes[id]


## Every bone the skin names must be in the rig, or be a documented extra
## that this garment may add (appended with the rest pose from the glb).
static func _ensure_bones(target: Skeleton3D, src: Skeleton3D, skin: Skin, id: String) -> bool:
	if skin == null:
		push_error("BWClothing: %s has no skin" % id)
		return false
	for b in skin.get_bind_count():
		var bn := str(skin.get_bind_name(b))
		if target.find_bone(bn) >= 0:
			continue
		if not EXTRA_BONES.has(bn) or not (id in EXTRA_BONES[bn].garments):
			push_error("BWClothing: %s binds undocumented bone '%s'" % [id, bn])
			return false
		var si := src.find_bone(bn)
		var parent := target.find_bone(EXTRA_BONES[bn].parent)
		if si < 0 or parent < 0:
			push_error("BWClothing: cannot add bone '%s' for %s" % [bn, id])
			return false
		var ni := target.get_bone_count()
		target.add_bone(bn)
		target.set_bone_parent(ni, parent)
		target.set_bone_rest(ni, src.get_bone_rest(si))
		target.reset_bone_pose(ni)
	return true


## mi's transform relative to the skeleton it came with (normally identity).
static func _relative(mi: Node3D, skel: Node3D) -> Transform3D:
	var xf := mi.transform
	var n := mi.get_parent() as Node3D
	while n != null and n != skel:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


static func _add_sway(skel: Skeleton3D) -> void:
	if skel.get_node_or_null("clothing_scarf_sway"):
		return
	var sw := ScarfSway.new()
	sw.name = "clothing_scarf_sway"
	skel.add_child(sw)


## Follow-through for the scarf tail: a damped spring on the tail tip that
## lags the chest, hangs toward gravity, and never swings into the body.
## Runs after the AnimationPlayer as a SkeletonModifier3D.
class ScarfSway:
	extends SkeletonModifier3D

	const BONE := "scarf_tail"
	const LENGTH := 0.33
	var stiffness := 90.0          ## spring toward the rigid hang, 1/s^2
	var damping := 9.0             ## 1/s
	var gravity_mix := 0.35        ## 0 = rigid on the chest, 1 = plumb down
	var max_angle := deg_to_rad(40.0)
	var swing := 0.0               ## last applied deflection from the rigid hang, radians
	var _tip := Vector3.ZERO
	var _vel := Vector3.ZERO
	var _primed := false

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var bi := sk.find_bone(BONE)
		if bi < 0:
			return
		var pi := sk.get_bone_parent(bi)
		var parent_pose := sk.get_bone_global_pose(pi)
		var rest := sk.get_bone_rest(bi)
		var rigid := parent_pose * rest                    # skeleton space
		var to_world := sk.global_transform
		var anchor := to_world * rigid.origin
		var rigid_dir := (to_world.basis * rigid.basis.y).normalized()
		var fwd := (to_world.basis * parent_pose.basis.z).normalized()
		var hang := rigid_dir.lerp(Vector3.DOWN, gravity_mix).normalized()
		var target := anchor + hang * LENGTH
		if not _primed or delta <= 0.0 or delta > 0.25:
			_tip = target
			_vel = Vector3.ZERO
			_primed = true
		else:
			_vel += (target - _tip) * stiffness * delta
			_vel *= exp(-damping * delta)
			_tip += _vel * delta
		var dir := (_tip - anchor).normalized()
		if dir.length_squared() < 0.5:
			dir = hang
		# never into the chest: keep at least the rest pose's forward lean
		var min_fwd := rigid_dir.dot(fwd) - 0.02
		if dir.dot(fwd) < min_fwd:
			dir = (dir + fwd * (min_fwd - dir.dot(fwd))).normalized()
		var ang := rigid_dir.angle_to(dir)
		if ang > max_angle:
			dir = rigid_dir.slerp(dir, max_angle / ang).normalized()
		_tip = anchor + dir * LENGTH
		swing = rigid_dir.angle_to(dir)
		var q := Quaternion(rigid_dir, dir) if ang > 1e-4 else Quaternion.IDENTITY
		var world_basis := Basis(q) * (to_world.basis * rigid.basis)
		var local := (to_world.basis * parent_pose.basis).inverse() * world_basis
		sk.set_bone_pose_rotation(bi, local.get_rotation_quaternion())

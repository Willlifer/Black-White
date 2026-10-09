class_name BWShieldView
extends Node3D
## D505-D507: the cosmetic shield that comes with every lance-class weapon.
## No slot, no stats: a lance-class weapon's weapons.json entry names its
## shield ("shield": id) and BWWeaponView.attach_to() hangs that shield on
## the character's OFF HAND; detaching (or swapping to another class) frees
## it. Models are art/weapons/shields/<id>.glb, built by
## tools/blender/build_weapons.py with the weapon look (white fill, black
## hull, accent the element tints).
##
##   var s := BWShieldView.create("kite_shield")
##   s.attach_to(rig)                    # by the shield's own mount data
##   s.set_mount(pos, face, up)          # retune at runtime (tools, tests)
##   BWShieldView.shield_for("lance")    # -> "kite_shield" ("" = none)
##   BWShieldView.mount_for("kite_shield") -> Transform3D in the holder frame
##
## Mount data (weapons.json "shields"[id]), all in socket_offhand_l's REST
## frame (world-aligned at rest: +Y up, +Z her forward, +X her left):
##   kind      "hand": rides socket_offhand_l (held, a full shield)
##             "forearm": rides the forearm_l bone (a bracer: the wrist turns
##             under it and the hand stays free to grip a shaft)
##   mount     position (the strap), face (where the shield's face looks),
##             up (where its top points)
## Shield-local space: origin = the arm strap on the back face, +Z the face,
## +Y the top.

var shield_id := ""
var meta := {}
var model: Node3D
var rig: BWCharacterRig
var _holder: Node3D          # the forearm attachment we made (freed on detach)


static func ids() -> PackedStringArray:
	return PackedStringArray(BWWeaponView.load_meta().get("shields", {}).keys())


static func meta_for(id: String) -> Dictionary:
	return BWWeaponView.load_meta().get("shields", {}).get(id, {})


## The shield a weapon comes with ("" when none: every non-lance weapon).
static func shield_for(weapon_id: String) -> String:
	return str(BWWeaponView.meta_for(weapon_id).get("shield", ""))


static func create(id: String) -> BWShieldView:
	var s := BWShieldView.new()
	if not s.setup(id):
		s.free()
		return null
	return s


## The mount (position, face, up) as a transform in the holder's frame.
static func mount_for(id: String) -> Transform3D:
	var m: Dictionary = meta_for(id).get("mount", {})
	return mount_xf(BWWeaponView.v3(m.get("position", [0, 0, 0])), BWWeaponView.v3(m.get("face", [0, 0, 1])),
		BWWeaponView.v3(m.get("up", [0, 1, 0])))


static func mount_xf(pos: Vector3, face: Vector3, up: Vector3) -> Transform3D:
	var z := face.normalized()
	var y := (up - z * up.dot(z)).normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), pos)


func setup(id: String) -> bool:
	if model != null:
		return shield_id == id
	meta = meta_for(id)
	if meta.is_empty():
		push_error("BWShieldView: no shield '%s' in %s" % [id, BWWeaponView.META_PATH])
		return false
	var scene := load(str(meta.glb)) as PackedScene
	if scene == null:
		push_error("BWShieldView: cannot load %s (run --import?)" % meta.glb)
		return false
	shield_id = id
	name = "shield_" + id
	model = scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	set_outline_width(BWWeaponView.OUTLINE)
	transform = mount_for(id)
	return true


func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if model:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			out.append(n as MeshInstance3D)
	return out


func triangle_count() -> int:
	var n := 0
	for mi in meshes():
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_index_len(i) / 3
	return n


func kind() -> String:
	return str(meta.get("kind", "hand"))


## Hang the shield on the rig: "hand" shields on socket_offhand_l, "forearm"
## guards on the forearm_l bone (through a holder that reproduces the off-hand
## socket's rest frame, so the same mount numbers mean the same thing).
func attach_to(r: BWCharacterRig) -> bool:
	if model == null or r == null:
		return false
	detach()
	if kind() == "forearm":
		var bone := r.skeleton.find_bone("forearm_l") if r.skeleton else -1
		if bone < 0:
			push_error("BWShieldView: the rig has no forearm_l bone")
			return false
		_holder = BoneAttachment3D.new()
		_holder.name = "shield_forearm_l"
		(_holder as BoneAttachment3D).bone_name = "forearm_l"
		r.skeleton.add_child(_holder)
		var sock_skel := r.skeleton.transform.affine_inverse() * r.socket_rest("offhand_l")
		var frame := Node3D.new()
		frame.name = "frame"
		frame.transform = r.skeleton.get_bone_global_rest(bone).affine_inverse() * sock_skel
		_holder.add_child(frame)
		frame.add_child(self)
	elif not r.attach(self, str(meta.get("socket", "socket_offhand_l"))):
		return false
	rig = r
	return true


func detach() -> void:
	if get_parent():
		get_parent().remove_child(self)
	if is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
	_holder = null
	rig = null


## Retune the mount (holder frame; see the header).
func set_mount(pos: Vector3, face: Vector3, up: Vector3) -> void:
	transform = mount_xf(pos, face, up)


## The shield's face centre, world space (needs the tree).
func face_global() -> Vector3:
	return global_transform * BWWeaponView.v3(meta.get("center", [0, 0, 0]))


func set_outline_width(width: float) -> void:
	for mi in meshes():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, BWWeaponView.material_for(BWWeaponView.surface_role(mi.mesh, i), width))


## The accent (boss, stud) takes the weapon's element colour (a = amount).
func set_accent(c: Color) -> void:
	for mi in meshes():
		mi.set_instance_shader_parameter("accent", c)



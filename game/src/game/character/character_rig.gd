class_name BWCharacterRig
extends Node3D
## The base character rig at runtime. Instances base_rig.glb (built by
## tools/blender/build_base_rig.py, never hand-edited), swaps its materials
## to the project's flat shader with inverted-hull contours, and exposes the
## named sockets that hair, hats, weapons and gear hang from.
##
##   var rig := BWCharacterRig.new()
##   add_child(rig)                       # builds itself in _ready, or call build()
##   rig.attach(hair_mesh, "hair")        # "hair" or "socket_hair"
##   rig.play("rig_idle")
##
## Material roles come from the glb's material names:
##   ink  (black limbs) -> flat, WHITE contour (D42)
##   skin (white head)  -> flat, BLACK contour
## Colour is baked into vertex COLOR by the build script, so one flat shader
## (flat_opaque: flat.gdshader without ALPHA, see FLAT_SHADER)
## serves both surfaces and the per-instance `tint`/`dim` uniforms still work
## (BWLook.set_dim fades the whole figure for the attack cutscene).
##
## Independent of the combat code: it only needs BWLook and the shaders.

const DEFAULT_PATH := "res://art/characters/base_rig.glb"
const RIG_VERSION := 1

## Deform bones, in skeleton order. Sockets are BoneAttachment3D children.
const BONES: PackedStringArray = [
	"root", "hips", "spine", "chest", "neck", "head",
	"shoulder_l", "upper_arm_l", "forearm_l", "hand_l",
	"shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r",
]
## socket -> the bone it rides on
const SOCKETS := {
	"socket_hair": "head", "socket_hat": "head",
	"socket_weapon_r": "hand_r", "socket_offhand_l": "hand_l",
	"socket_chest": "chest", "socket_back": "chest",
}
const HEIGHT := 2.2
## The project's flat shader minus its ALPHA write, so the rig is opaque and
## depth-sorted (see the shader header). Same uniforms as flat.gdshader.
const FLAT_SHADER := "res://shaders/flat_opaque.gdshader"


## Contour widths in model units (the rig is 2.2 tall). Tuned against the
## combat camera (~21 u at FOV 38) and the cutscene close-up (FOV 24).
const INK_OUTLINE := 0.018
const SKIN_OUTLINE := 0.026

var path := DEFAULT_PATH
var model: Node3D          ## the instanced glb
var skeleton: Skeleton3D
var body: MeshInstance3D
var anim: AnimationPlayer
var _sockets := {}         # name -> Node3D

static var _materials := {}   # "role|width" -> ShaderMaterial


func _ready() -> void:
	if model == null:
		build()


## Instance the glb and wire it up. Safe to call once; returns false (and
## pushes an error) if the file is missing or not the rig we expect.
func build(p: String = path) -> bool:
	if model != null:
		return true
	path = p
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("BWCharacterRig: cannot load %s (run --import?)" % path)
		return false
	model = scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		push_error("BWCharacterRig: no Skeleton3D in %s" % path)
		return false
	skeleton = sk[0]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "body":
			body = mi
		_apply_materials(mi)
	var ap := model.find_children("*", "AnimationPlayer", true, false)
	anim = ap[0] if not ap.is_empty() else null
	if anim and anim.has_animation("rig_idle"):
		anim.get_animation("rig_idle").loop_mode = Animation.LOOP_LINEAR
	for n in model.find_children("socket_*", "Node3D", true, false):
		_sockets[str(n.name)] = n
	for s in SOCKETS:
		if not _sockets.has(s):
			push_error("BWCharacterRig: socket %s missing from %s" % [s, path])
	return true


# ------------------------------------------------------------- sockets

## The socket node. Accepts "socket_hair" or just "hair". Null if unknown.
## Socket axes at rest: +Y up, +Z the character's forward, +X its left.
func socket(socket_name: String) -> Node3D:
	if not socket_name.begins_with("socket_"):
		socket_name = "socket_" + socket_name
	return _sockets.get(socket_name)


func socket_names() -> PackedStringArray:
	var out := PackedStringArray(_sockets.keys())
	out.sort()
	return out


## Parent `item` to a socket, keeping the item's own local transform as the
## offset from the socket. Returns false if the socket doesn't exist.
func attach(item: Node3D, socket_name: String) -> bool:
	var s := socket(socket_name)
	if s == null:
		push_error("BWCharacterRig: no socket '%s'" % socket_name)
		return false
	if item.get_parent():
		item.get_parent().remove_child(item)
	s.add_child(item)
	return true


## Remove and free everything attached to a socket.
func clear_socket(socket_name: String) -> void:
	var s := socket(socket_name)
	if s:
		for c in s.get_children():
			c.queue_free()


## Socket transform in rig space at the bind pose. Works without the node
## being in the tree (BoneAttachment3D only updates inside it), so tools and
## tests can measure placement headlessly.
func socket_rest(socket_name: String) -> Transform3D:
	var s := socket(socket_name)
	if s == null or skeleton == null:
		return Transform3D()
	var att := s.get_parent() as BoneAttachment3D
	var bone := skeleton.find_bone(att.bone_name) if att else -1
	if bone < 0:
		return s.transform
	return skeleton.transform * skeleton.get_bone_global_rest(bone) * s.transform


# ---------------------------------------------------------- animation

func play(anim_name: String, blend: float = 0.15, speed: float = 1.0) -> bool:
	if anim == null or not anim.has_animation(anim_name):
		return false
	anim.play(anim_name, blend, speed)
	return true


## Freeze on one frame of an animation (tools, renders, tests).
func pose_at(anim_name: String, time: float) -> bool:
	if anim == null or not anim.has_animation(anim_name):
		return false
	anim.play(anim_name)
	anim.seek(time, true)
	anim.pause()
	return true


func animations() -> PackedStringArray:
	return anim.get_animation_list() if anim else PackedStringArray()


# ------------------------------------------------------------ looks

## Set the contour widths for this figure only (e.g. a hero close-up).
func set_outline_widths(ink: float, skin: float) -> void:
	if body:
		for i in body.mesh.get_surface_count():
			var role := _role(body.mesh, i)
			body.set_surface_override_material(i, material_for(role, ink if role == "ink" else skin))


## Triangle count of the body (budget check).
func triangle_count() -> int:
	var n := 0
	if body:
		for i in body.mesh.get_surface_count():
			n += body.mesh.surface_get_array_index_len(i) / 3
	return n


## Shared material per role and width: flat fill + inverted-hull next pass.
static func material_for(role: String, width: float = -1.0) -> ShaderMaterial:
	if width < 0.0:
		width = SKIN_OUTLINE if role == "skin" else INK_OUTLINE
	var key := "%s|%.4f" % [role, width]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load(FLAT_SHADER)
	# D42: white contour around black shapes, black around white ones.
	m.next_pass = BWLook.outline(width, Color.WHITE if role == "ink" else Color.BLACK)
	m.resource_name = "bw_" + role
	_materials[key] = m
	return m


func _apply_materials(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		var role := _role(mi.mesh, i)
		if (mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			push_warning("BWCharacterRig: surface %d of %s has no vertex colours; it will render white" % [i, mi.name])
		mi.set_surface_override_material(i, material_for(role))


static func _role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "":
		n = mesh.surface_get_name(i) if mesh is ArrayMesh else ""
	return "skin" if n.begins_with("skin") else "ink"

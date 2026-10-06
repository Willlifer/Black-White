class_name BWHair
extends Node3D
## One hair archetype at runtime: instances art/hair/<style>.glb (built by
## tools/blender/build_hair.py, never hand-edited), gives it the unlit hair
## materials, tints it with an element colour and hangs it on a
## BWCharacterRig's `socket_hair`.
##
##   var hair := BWHair.create("long_ponytail", "fire")
##   hair.attach_to(rig)                 # replaces any hair already there
##   hair.set_element("ice")             # recolour in place, solid
##   hair.set_affinity(unit.affinity, unit.focus())   # D146: colour by rank
##
## Material slots in every hair glb:
##   hair        fill  = the look's colour
##   hair_shade  inner contour / underside / stubble = same hue, darker
##   hair_shine  the old highlight streaks; shades like the fill (D64)
## All get an inverted-hull contour: same hue, darker (D52); a lighter line
## of the hue for dark colours, so they read on the black sky (D42).
##
## The look (D146) is a ramp texture over the hair's root -> tip coordinate,
## from BWLook.hair_gradient (the element colour with contrast streaks that
## thin out as rank rises; 2+ elements = an ombre). Ramps and materials are cached by look
## key, so every unit with the same ranks shares them. The root -> tip
## coordinate and the lock azimuth are baked into vertex COLOR once per glb
## mesh at load (D147, _baked); the glbs carry no UVs.
##
## Long styles carry their own Skeleton3D: `hair_root` plus a chain
## hair_tail_01..NN (TAIL_BONES). The skeleton rides the head socket, so the
## hair follows the head rigidly until something poses the tail bones
## (tail_bone_names(), set_tail_rotation()).
##
## Independent of the combat code: it only needs BWLook and the shaders.

const DIR := "res://art/hair/"
const ALT_DIR := "res://art/hair/alt/"   ## variant 1 of every style (same bones)
const HAIR_VERSION := 2         ## v2: lock-based crowns, hair_shine slot, alt variants
const RIG_VERSION := 1          ## base rig the meshes were fitted to

## Every archetype and how many hair_tail_* bones its glb carries.
## Keep in step with build_hair.py and design/art/HAIR.md.
const TAIL_BONES := {
	"buzzed": 0, "high_and_tight": 0, "mullet": 0, "short_mohawk": 0, "bob": 0,
	"ponytail": 2, "long_ponytail": 3, "waterfall": 3, "ringlets": 2, "long_hair": 3,
}

const FILL_SHADER := "res://shaders/hair.gdshader"
const OUTLINE_SHADER := "res://shaders/hair_outline.gdshader"
## Perceptual value of the shade slot and of the contour, relative to the
## element colour (1.0 = the colour itself, 0.0 = black).
const SHADE_VALUE := 0.62
const CONTOUR_VALUE := 0.36
## How far a dark colour's contour is lifted toward white (D146/D42: dark
## hair keeps its silhouette against the sky; the line vanishes on white).
const CONTOUR_LIFT := 0.55
## How far the shine slot is mixed toward white (a material uniform, so the
## instance slots stay dim = 0, tint = 1).
const SHINE := 0.0         ## author: remove the glare on top of the heads entirely (D64); the slot stays, shading like the fill
const OUTLINE := 0.024          ## hull width, model units (head contour is 0.026)

## hair_variant: a small per-character seed (0..7) so two people with the
## same style don't look identical. Bits:
##   1  ALT     the style's variant-1 mesh (art/hair/alt: other lock count,
##              part side, sweep, volume, tip sharpness; same bones)
##   2  MIRROR  mirrored left/right (part, swoop and tail swing flip sides)
##   4  WIDE    a touch more width (x and z only, so crown height and hat
##              clearance are unchanged)
## variant_for(id) derives it from a unit id; the salt was picked so every
## same-style pair in the roster gets different geometry.
const VARIANT_ALT := 1
const VARIANT_MIRROR := 2
const VARIANT_WIDE := 4
const VARIANT_COUNT := 8
const WIDE := 1.04
const VARIANT_SALT := "hair1192:"   # re-picked for the D150 roster (Gail long_ponytail, Lionel buzzed)

var style := ""
var variant := 0                ## hair_variant seed (see VARIANT_*)
var element := ""
var color := Color.WHITE
var model: Node3D               ## the instanced glb
var skeleton: Skeleton3D        ## null on rigid styles
var meshes: Array[MeshInstance3D] = []

var look_key := ""              ## the ramp in use: "" white, "#rrggbb" solid, else BWLook.hair_key
var _same_hue := true
var _width := OUTLINE

static var _materials := {}     # "role|contour|width|look" -> ShaderMaterial
static var _ramps := {}         # look key -> GradientTexture1D
static var _bakes := {}         # glb Mesh -> ArrayMesh with root->tip / azimuth in COLOR
const RAMP_WIDTH := 128
## Root->tip baking (D147), socket space (head centre origin): t is the
## larger of the drop from the style's crown (over its own height) and the
## reach out from the skull (|p| - SKULL_R) / REACH, so hanging hair, crown
## locks and upright spikes all run root -> tip.
const SKULL_R := 0.34
const REACH := 0.42
## A connected piece with fewer vertices than this share of its surface is a
## lock: it takes one azimuth (its centroid's), so a highlight is whole locks.
const LOCK_SHARE := 0.15
## The drop is eased (t = drop^DROP_CURVE) so the crown, which is most of
## what the combat camera sees from above, stays a short stretch of root
## and the tip colours carry the read (D147).
const DROP_CURVE := 0.6


## Build a hair node for a style, coloured for an element ("" = white),
## in a hair_variant (0..7, see VARIANT_*; 0 = the plain style).
## Returns null (and pushes an error) on an unknown style or missing glb.
static func create(style_id: String, element_id: String = "", variant_seed: int = 0) -> BWHair:
	var h := BWHair.new()
	if not h.build(style_id, variant_seed):
		h.free()
		return null
	if element_id != "":
		h.set_element(element_id)
	return h


static func styles() -> PackedStringArray:
	return PackedStringArray(TAIL_BONES.keys())


## The glb for a style; alt = its variant-1 mesh (falls back to the plain
## one in build() if that file is missing).
static func path_for(style_id: String, alt: bool = false) -> String:
	return (ALT_DIR if alt else DIR) + style_id + ".glb"


## Deterministic hair_variant for a unit id: FNV-1a + a murmur finaliser
## over VARIANT_SALT + id, low 3 bits. Same id, same look, every run.
static func variant_for(id: String) -> int:
	var h := 2166136261
	for b in (VARIANT_SALT + id).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x85ebca6b) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 0xc2b2ae35) & 0xFFFFFFFF
	h ^= h >> 16
	return h % VARIANT_COUNT


static func has_style(style_id: String) -> bool:
	return TAIL_BONES.has(style_id) and ResourceLoader.exists(path_for(style_id))


## Instance the style's glb in a hair_variant. Safe to call once.
func build(style_id: String, variant_seed: int = 0) -> bool:
	if model != null:
		return style_id == style
	if not TAIL_BONES.has(style_id):
		push_error("BWHair: unknown hair style '%s'" % style_id)
		return false
	variant = posmod(variant_seed, VARIANT_COUNT)
	var path := path_for(style_id, variant & VARIANT_ALT != 0)
	if not ResourceLoader.exists(path):
		path = path_for(style_id)
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("BWHair: cannot load %s (run --import?)" % path)
		return false
	style = style_id
	name = "hair_" + style
	model = scene.instantiate() as Node3D
	model.name = "model"
	var sx := WIDE if variant & VARIANT_WIDE else 1.0
	model.scale = Vector3(-sx if variant & VARIANT_MIRROR else sx, 1.0, sx)
	add_child(model)
	var sk := model.find_children("*", "Skeleton3D", true, false)
	skeleton = sk[0] if not sk.is_empty() else null
	meshes.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = _baked(mi.mesh, _xform_to(mi, model))
		meshes.append(mi)
		_apply_materials(mi)
	return true


## Hang this hair on a rig's socket_hair, replacing whatever hair is there.
func attach_to(rig: BWCharacterRig) -> bool:
	if rig.model == null:
		rig.build()
	var s := rig.socket("hair")
	if s == null:
		push_error("BWHair: rig has no socket_hair")
		return false
	for c in s.get_children():
		if c is BWHair and c != self:
			s.remove_child(c)
			c.queue_free()
	transform = Transform3D.IDENTITY
	return rig.attach(self, "hair")


## Solid element colour root to tip (the pre-D146 look; previews, the boss
## look without affinity). Units use set_affinity().
func set_element(element_id: String) -> void:
	element = element_id
	set_color(BWLook.element_color(element_id))


## One solid colour root to tip, e.g. a UI swatch. Shade and contour follow.
func set_color(c: Color) -> void:
	color = c
	var key := "#" + c.to_html(false)
	if not _ramps.has(key):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(c, 0.5), Color(c, 0.5)])   # alpha 0.5: no streaks
		_ramps[key] = _ramp_texture(g)
	_use_look(key)


## D146: colour by affinity rank (BWLook.hair_gradient). `affinity` holds
## points, as BWUnit.affinity. Returns true when the look changed; a call
## with the same ranks is a key compare and nothing else.
func set_affinity(affinity: Dictionary, focus: String = "") -> bool:
	var key := BWLook.hair_key(affinity, focus)
	if key == "":
		key = "none"
	if key == look_key:
		return false
	var ranks := BWLook.hair_ranks(affinity, focus)
	element = str(ranks[0][0]) if not ranks.is_empty() else ""
	color = BWLook.element_color(element) if element != "" else BWLook.HAIR_NONE
	if not _ramps.has(key):
		_ramps[key] = _ramp_texture(BWLook.hair_gradient(affinity, focus))
	_use_look(key)
	return true


func _use_look(key: String) -> void:
	look_key = key
	for mi: MeshInstance3D in meshes:
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, material_for(_role(mi.mesh, i), _same_hue, _width, look_key))


## The ramp texture for a look key (null if that look was never set).
static func ramp_for(key: String) -> GradientTexture1D:
	return _ramps.get(key)


static func _ramp_texture(g: Gradient) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = RAMP_WIDTH
	return t


## Contour colour mode for this hair: true = same hue, darker (default,
## D52); false = black like the head's contour. Width in model units.
func set_contour(same_hue: bool = true, width: float = OUTLINE) -> void:
	_same_hue = same_hue
	_width = width
	_use_look(look_key)


func tail_bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	if skeleton:
		for i in skeleton.get_bone_count():
			var n := skeleton.get_bone_name(i)
			if n.begins_with("hair_tail_"):
				out.append(n)
	return out


## Pose one tail bone relative to its rest (follow-through, wind). Local
## axes follow the rig convention: +X pitches the tip forward.
func set_tail_rotation(bone_name: String, euler: Vector3) -> bool:
	if skeleton == null:
		return false
	var i := skeleton.find_bone(bone_name)
	if i < 0:
		return false
	skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion() * Quaternion.from_euler(euler))
	return true


func reset_pose() -> void:
	if skeleton:
		skeleton.reset_bone_poses()


func triangle_count() -> int:
	var n := 0
	for mi: MeshInstance3D in meshes:
		for i in mi.mesh.get_surface_count():
			var idx: int = mi.mesh.surface_get_array_index_len(i)
			n += (idx if idx > 0 else mi.mesh.surface_get_array_len(i)) / 3
	return n


## Rest-pose bounds in this node's space (socket space: head centre origin).
func get_aabb() -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var b := _xform_to_self(mi) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Shared material per slot and look: unlit hair fill + darker same-hue
## (or black) hull. look = a key set through set_affinity / set_color
## ("" = plain white).
static func material_for(role: String, same_hue: bool = true, width: float = OUTLINE, look: String = "") -> ShaderMaterial:
	var key := "%s|%s|%.4f|%s" % [role, same_hue, width, look]
	if _materials.has(key):
		return _materials[key]
	if not _ramps.has(""):
		var w := Gradient.new()
		w.offsets = PackedFloat32Array([0.0, 1.0])
		w.colors = PackedColorArray([Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.5)])
		_ramps[""] = _ramp_texture(w)
	var ramp: Texture2D = _ramps.get(look, _ramps[""])
	var m := ShaderMaterial.new()
	m.shader = load(FILL_SHADER)
	m.set_shader_parameter("ramp", ramp)
	m.set_shader_parameter("value", SHADE_VALUE if role == "hair_shade" else 1.0)
	m.set_shader_parameter("saturate", 0.15 if role == "hair_shade" else 0.0)
	m.set_shader_parameter("shine", SHINE if role == "hair_shine" else 0.0)
	var ol := ShaderMaterial.new()
	ol.shader = load(OUTLINE_SHADER)
	ol.set_shader_parameter("width", width)
	ol.set_shader_parameter("value", CONTOUR_VALUE if same_hue else 0.0)
	ol.set_shader_parameter("lift", CONTOUR_LIFT if same_hue else 0.0)
	ol.set_shader_parameter("dark_lum", BWLook.HAIR_STREAK_LUM)
	ol.set_shader_parameter("ramp", ramp)
	m.next_pass = ol
	m.resource_name = "bw_" + role
	_materials[key] = m
	return m


func _apply_materials(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, material_for(_role(mi.mesh, i), _same_hue, _width, look_key))


## D147: a copy of a hair glb mesh with vertex COLOR = (root->tip, lock
## azimuth, 0, 1), made once per mesh and shared by every instance. `rel` is
## the mesh node's transform in the glb (socket space before the variant
## scale). Bones, weights, surface names and materials are kept.
static func _baked(mesh: Mesh, rel: Transform3D) -> Mesh:
	if _bakes.has(mesh):
		return _bakes[mesh]
	if not (mesh is ArrayMesh) or mesh.get_blend_shape_count() > 0:
		_bakes[mesh] = mesh
		return mesh
	var all: Array = []
	var top := -INF
	var bot := INF
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		all.append(a)
		for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
			var p := rel * v
			top = maxf(top, p.y)
			bot = minf(bot, p.y)
	var span := maxf(top - bot, 0.001)
	var out := ArrayMesh.new()
	out.resource_name = mesh.resource_name
	for i in mesh.get_surface_count():
		var a: Array = all[i]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var lock := _lock_centroids(vs, a[Mesh.ARRAY_INDEX], rel)
		var cols := PackedColorArray()
		cols.resize(vs.size())
		for k in vs.size():
			cols[k] = Color(root_to_tip(rel * vs[k], top, span), fposmod(atan2(lock[k].x, lock[k].z) / TAU, 1.0), 0.0, 1.0)
		a[Mesh.ARRAY_COLOR] = cols
		var flags: int = mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), a, [], {}, flags)
		out.surface_set_material(i, mesh.surface_get_material(i))
		out.surface_set_name(i, (mesh as ArrayMesh).surface_get_name(i))
	_bakes[mesh] = out
	return out


## The root (0) -> tip (1) coordinate of a socket-space point on a style
## whose crown is at `top` and which spans `span` in height.
static func root_to_tip(p: Vector3, top: float, span: float) -> float:
	var drop := clampf((top - p.y) / span, 0.0, 1.0)
	return clampf(maxf(pow(drop, DROP_CURVE), (p.length() - SKULL_R) / REACH), 0.0, 1.0)


## Per vertex: the point its azimuth is read from. Vertices of a lock (a
## connected piece smaller than LOCK_SHARE of the surface, welded by
## position) get the lock's centroid; a shell keeps its own positions.
static func _lock_centroids(vs: PackedVector3Array, idx: PackedInt32Array, rel: Transform3D) -> PackedVector3Array:
	var n := vs.size()
	var par: Array[int] = []   # by reference into _root/_union
	par.resize(n)
	for k in n:
		par[k] = k
	var weld := {}
	for k in n:
		var key := Vector3i((vs[k] * 2000.0).round())
		if weld.has(key):
			_union(par, k, weld[key])
		else:
			weld[key] = k
	for k in range(0, idx.size() - 2, 3):
		_union(par, idx[k], idx[k + 1])
		_union(par, idx[k], idx[k + 2])
	var sum := {}
	var cnt := {}
	for k in n:
		var r := _root(par, k)
		sum[r] = sum.get(r, Vector3.ZERO) + rel * vs[k]
		cnt[r] = cnt.get(r, 0) + 1
	var out := PackedVector3Array()
	out.resize(n)
	for k in n:
		var r := _root(par, k)
		out[k] = sum[r] / float(cnt[r]) if cnt[r] < n * LOCK_SHARE else rel * vs[k]
	return out


static func _root(par: Array[int], x: int) -> int:
	while par[x] != x:
		x = par[x]
	return x


static func _union(par: Array[int], a: int, b: int) -> void:
	var ra := _root(par, a)
	var rb := _root(par, b)
	if ra != rb:
		par[rb] = ra


func _xform_to_self(n: Node3D) -> Transform3D:
	return _xform_to(n, self)


static func _xform_to(n: Node3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != stop:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	if n.begins_with("hair_shade"):
		return "hair_shade"
	if n.begins_with("hair_shine"):
		return "hair_shine"
	return "hair"

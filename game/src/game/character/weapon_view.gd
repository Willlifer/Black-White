class_name BWWeaponView
extends Node3D
## One weapon model at runtime: instances art/weapons/<id>.glb (built by
## tools/blender/build_weapons.py, never hand-edited), gives it the weapon
## look (white fill, black inverted hull, tintable accent), hangs it on a
## BWCharacterRig socket, and can wrap it in an element aura.
##
##   var w := BWWeaponView.create("flamberge")
##   w.attach_to(rig)                  # socket from metadata; daggers and fists add the off-hand piece
##   w.set_aura("fire", 1.0)           # fresnel shell + billboard particles; ("", 0) clears
##   w.tip_global()                    # trail tip (world); trail_points() gives base + tip
##   w.second_hand_target()            # Marker3D for the other hand's IK (two-handers, bows)
##   w.shield_view                     # D505: lance class: its BWShieldView on the off hand, else null
##
## All placement data comes from the sidecar art/weapons/weapons.json (one
## source of truth, written by the same build script as the glbs). Points
## there are in weapon-local space: origin = centre of the holding fist, +Y up
## the blade, +Z the edge / muzzle, +X the wielder's left; the same frame as
## the rig sockets at rest, so the mount is identity.
##
## Independent of the combat code: needs BWLook, BWCharacterRig and the shaders.

const META_PATH := "res://art/weapons/weapons.json"
const META_VERSION := 1
const FILL_SHADER := "res://shaders/weapon.gdshader"
const AURA_SHADER := "res://shaders/aura.gdshader"
## Black hull width in weapon units. ~1.4 px at the combat camera, bolder
## than the rig's 0.018 limb contour: weapons are the "thick outline" brief.
const OUTLINE := 0.022
## Per-element particle motion: gravity y, speed min/max, lifetime, spread.
const MOTION := {
	"fire": [1.6, 0.25, 0.55, 0.65, 25.0],
	"water": [-0.9, 0.08, 0.25, 0.85, 40.0],
	"ice": [-0.2, 0.04, 0.14, 1.2, 60.0],
	"thunder": [0.0, 0.7, 1.2, 0.22, 180.0],
	"wind": [0.3, 0.45, 0.8, 0.6, 85.0],
	"dark": [-0.6, 0.06, 0.2, 1.0, 50.0],
	"light": [0.7, 0.12, 0.3, 0.9, 30.0],
}

const PARTICLE_SHADER := "res://shaders/aura_particle.gdshader"

static var _meta := {}
static var _particle_mat: ShaderMaterial
static var _materials := {}      # "role|width" -> ShaderMaterial

var weapon_id := ""
var meta := {}
var model: Node3D                ## the instanced glb
var offhand_view: BWWeaponView   ## daggers / fists: the piece on socket_offhand_l (owned by this view)
var shield_view: BWShieldView    ## D505: lance class: the cosmetic shield on the off hand (owned by this view)
## D505: false keeps attach_to() from hanging the shield (tools only; the game always shows it)
var with_shield := true
var rig: BWCharacterRig
var aura_element := ""
var aura_strength := 0.0
var is_offhand_copy := false
var _markers := {}               # "tip", "trail_base", "second_hand" -> Marker3D
var _aura_mat: ShaderMaterial
var _aura_nodes: Array[Node] = []
var _outline := OUTLINE
var _string_segs: Array[MeshInstance3D] = []   # bows: the string drawn bent to the hand
var _string_bent := false
static var _hidden_mat: ShaderMaterial


# ----------------------------------------------------------- metadata

## The parsed sidecar. Cached; `force` re-reads (tests, hot reload).
static func load_meta(force: bool = false) -> Dictionary:
	if not _meta.is_empty() and not force:
		return _meta
	_meta = {}
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		push_error("BWWeaponView: cannot open %s (run build_weapons.py)" % META_PATH)
		return _meta
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BWWeaponView: %s is not a JSON object" % META_PATH)
		return _meta
	if int(parsed.get("version", 0)) != META_VERSION:
		push_warning("BWWeaponView: %s version %s, expected %d" % [META_PATH, parsed.get("version"), META_VERSION])
	_meta = parsed
	return _meta


static func ids() -> PackedStringArray:
	return PackedStringArray(load_meta().get("weapons", {}).keys())


static func meta_for(id: String) -> Dictionary:
	var m: Dictionary = load_meta().get("weapons", {}).get(id, {})
	if not m.is_empty() and not m.has("id"):
		m["id"] = id          # ---- D520: style_for tells the shield spears (lance, trident) from the 2h polearms
	return m


static func create(id: String) -> BWWeaponView:
	var w := BWWeaponView.new()
	if not w.setup(id):
		w.free()
		return null
	return w


static func v3(a: Variant) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


# -------------------------------------------------------------- build

## Load the model and its markers. Returns false (and pushes an error) for
## an unknown id or a missing glb.
func setup(id: String) -> bool:
	if model != null:
		return weapon_id == id
	meta = meta_for(id)
	if meta.is_empty():
		push_error("BWWeaponView: no weapon '%s' in %s" % [id, META_PATH])
		return false
	# fists (D76): the off-hand copy is its own mirrored mesh, not the same one
	var glb := str(meta.offhand_glb) if is_offhand_copy and meta.get("offhand_glb") is String else str(meta.glb)
	var scene := load(glb) as PackedScene
	if scene == null:
		push_error("BWWeaponView: cannot load %s (run --import?)" % glb)
		return false
	weapon_id = id
	name = "weapon_" + id
	model = scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	for mi in meshes():
		_apply_materials(mi)
	var mount: Dictionary = meta.get("mount", {})
	var rot := v3(mount.get("rotation_deg", [0, 0, 0]))
	transform = Transform3D(Basis.from_euler(rot * PI / 180.0), v3(mount.get("position", [0, 0, 0])))
	_marker("tip", _side(v3(meta.tip)))
	_marker("trail_base", _side(v3(meta.trail_base)))
	var sh: Variant = meta.get("second_hand")
	if sh is Dictionary:
		_marker("second_hand", _side(v3(sh.point)))
	return true


## A metadata point for this copy's hand: the mirrored off-hand piece of a
## pair of fists flips x (the left hand's own model); everything else as is.
func _side(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z) if is_mirrored() else p


## True for the left piece of a mirrored pair (fists).
func is_mirrored() -> bool:
	return is_offhand_copy and bool(meta.get("mirror_offhand", false))


func _marker(key: String, at: Vector3) -> void:
	var m := Marker3D.new()
	m.name = key
	m.position = at
	add_child(m)
	_markers[key] = m


func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if model:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			if not str(n.name).begins_with("aura"):     # skip our own aura shells
				out.append(n as MeshInstance3D)
	return out


## Triangle count of the weapon (one copy).
func triangle_count() -> int:
	var n := 0
	for mi in meshes():
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_index_len(i) / 3
	return n


# ------------------------------------------------------------- attach

## Hang the weapon on the rig socket its metadata names; pairs (daggers)
## also put an identical copy on the off-hand socket, and fists their
## mirrored left piece (offhand_glb). Re-attaching moves it.
func attach_to(r: BWCharacterRig) -> bool:
	if model == null or r == null:
		return false
	detach()
	if not r.attach(self, str(meta.socket)):
		return false
	rig = r
	var off: Variant = meta.get("offhand_socket")
	if off is String and off != "" and not is_offhand_copy:
		offhand_view = BWWeaponView.new()
		offhand_view.is_offhand_copy = true
		offhand_view.setup(weapon_id)
		offhand_view.set_outline_width(_outline)
		r.attach(offhand_view, off)
		if aura_element != "":
			offhand_view.set_aura(aura_element, aura_strength)
		elif imbue_element != "":
			offhand_view.set_imbue(imbue_element)
	_attach_shield(r)
	return true


## D505: a lance-class weapon brings its shield (weapons.json "shield") onto
## the off hand; any other weapon brings none. Owned by this view.
func _attach_shield(r: BWCharacterRig) -> void:
	var sid := str(meta.get("shield", ""))
	if sid == "" or is_offhand_copy or not with_shield:
		return
	shield_view = BWShieldView.create(sid)
	if shield_view == null:
		return
	shield_view.set_outline_width(_outline)
	if not shield_view.attach_to(r):
		shield_view.free()
		shield_view = null
		return
	_shield_accent()


func _shield_accent() -> void:
	if not is_instance_valid(shield_view):
		return
	if aura_element != "":
		shield_view.set_accent(Color(aura_colors(BWLook.element_color(aura_element))[1], clampf(aura_strength, 0.0, 1.0)))
	else:
		shield_view.set_accent(_imbue_accent())


func _free_shield() -> void:
	if is_instance_valid(shield_view):
		shield_view.detach()
		shield_view.free()
	shield_view = null


## Take the weapon (and its off-hand copy) off the rig. The view survives.
func detach() -> void:
	if is_instance_valid(offhand_view):
		offhand_view.free()
	offhand_view = null
	_free_shield()
	if get_parent():
		get_parent().remove_child(self)
	rig = null


## "socket_weapon_r" etc. for the hand this weapon sits in.
func socket_name() -> String:
	return str(meta.get("offhand_socket")) if is_offhand_copy else str(meta.get("socket", ""))


func hands() -> String:
	return str(meta.get("hands", "one"))


func weapon_class() -> String:
	return str(meta.get("class", ""))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(offhand_view):
			offhand_view.free()
		_free_shield()


# ------------------------------------------------------------- points

## Trail tip in weapon space (blade point, axe edge, muzzle, arrow rest).
func tip_local() -> Vector3:
	return _side(v3(meta.get("tip")))


## Trail tip in world space. Needs the view in the tree.
func tip_global() -> Vector3:
	return (_markers.tip as Marker3D).global_position


## Base and tip of the trail ribbon, world space. Needs the view in the tree.
func trail_points() -> PackedVector3Array:
	return PackedVector3Array([(_markers.trail_base as Marker3D).global_position, tip_global()])


## Marker for the other hand's IK target: the left hand for two-handers,
## the right (draw) hand for bows. Null for one-handers and pairs.
func second_hand_target() -> Marker3D:
	return _markers.get("second_hand")


## Which hand second_hand_target() is for: "l", "r" or "".
func second_hand() -> String:
	var sh: Variant = meta.get("second_hand")
	return str(sh.hand) if sh is Dictionary else ""


func aura_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in meta.get("aura_points", []):
		out.append(_side(v3(p)))
	return out


# ------------------------------------------------------------- string

## Bows: the model has a drawable string surface (weapons.json "string":
## its two ends, weapon space).
func has_string() -> bool:
	return meta.get("string") is Array and (meta.string as Array).size() == 2


## Bend the bow string to `nock` (a weapon-space point, the draw hand) or
## straighten it (null). The straight string surface is hidden while two
## segments run from its ends to the nock; a nock in front of the string
## line leaves it straight. Cheap: two cylinders, no mesh rebuild.
func set_string_draw(nock: Variant) -> void:
	if not has_string():
		return
	var ends: Array = meta.string
	var top := v3(ends[0])
	var bot := v3(ends[1])
	if nock == null or (nock as Vector3).z > top.z - 0.004:
		if _string_bent:
			_string_bent = false
			for mi in meshes():
				_apply_materials(mi)
			for sg in _string_segs:
				sg.visible = false
		return
	var n: Vector3 = nock
	n.x = clampf(n.x, -0.06, 0.06)
	if _string_segs.is_empty():
		for k in 2:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0068
			cm.bottom_radius = 0.0068
			cm.height = 1.0
			cm.radial_segments = 4
			cm.rings = 0
			var sg := MeshInstance3D.new()
			sg.name = "string_drawn"
			sg.mesh = cm
			sg.material_override = material_for("body", _outline)
			sg.set_instance_shader_parameter("tint", Color(0.12, 0.12, 0.12))
			sg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sg)
			_string_segs.append(sg)
	if not _string_bent:
		_string_bent = true
		if _hidden_mat == null:
			_hidden_mat = ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = "shader_type spatial;
render_mode unshaded;
void fragment() { discard; }
"
			_hidden_mat.shader = sh
		for mi in meshes():
			for i in mi.mesh.get_surface_count():
				if _is_string_surface(mi.mesh, i):
					mi.set_surface_override_material(i, _hidden_mat)
	for k in 2:
		var a := top if k == 0 else bot
		var d := n - a
		var y := d.normalized()
		var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		var sg := _string_segs[k]
		sg.visible = true
		sg.transform = Transform3D(Basis(x, y * d.length(), z), a + d * 0.5)


static func _is_string_surface(mesh: Mesh, i: int) -> bool:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	return n.begins_with("string")


# -------------------------------------------------------------- looks

func set_outline_width(width: float) -> void:
	_outline = width
	for mi in meshes():
		_apply_materials(mi)
	_string_bent = false
	if is_instance_valid(offhand_view):
		offhand_view.set_outline_width(width)
	if is_instance_valid(shield_view):
		shield_view.set_outline_width(width)


## Turn on (or update) the element aura: an inflated fresnel shell of the
## weapon's own mesh, billboard particles from the metadata's aura points,
## and the accent surface (edges, gems) tinted to the element. strength 0..2
## (1 = normal; 0 or element "" clears).
func set_aura(element: String, strength: float = 1.0) -> void:
	if element == "" or strength <= 0.0:
		clear_aura()
		return
	var base := BWLook.element_color(element)
	var cols := aura_colors(base)
	if _aura_mat == null:
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = load(AURA_SHADER)
	_aura_mat.set_shader_parameter("color", cols[0])
	_aura_mat.set_shader_parameter("rim_color", cols[1])
	_aura_mat.set_shader_parameter("strength", strength)
	if element != aura_element or _aura_nodes.is_empty():
		_clear_aura_nodes()
		for mi in meshes():
			var shell := MeshInstance3D.new()
			shell.name = "aura_shell"
			shell.mesh = mi.mesh
			shell.material_override = _aura_mat
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(shell)
			_aura_nodes.append(shell)
		var p := _particles(element, cols, strength)
		add_child(p)
		_aura_nodes.append(p)
	else:
		for n in _aura_nodes:
			if n is CPUParticles3D:
				(n as CPUParticles3D).amount = _particle_amount(strength)
	aura_element = element
	aura_strength = strength
	for mi in meshes():
		mi.set_instance_shader_parameter("accent", Color(cols[1], clampf(strength, 0.0, 1.0)))
	if is_instance_valid(offhand_view):
		offhand_view.set_aura(element, strength)
	_shield_accent()


func clear_aura() -> void:
	_clear_aura_nodes()
	aura_element = ""
	aura_strength = 0.0
	for mi in meshes():
		mi.set_instance_shader_parameter("accent", _imbue_accent())
	if is_instance_valid(offhand_view):
		offhand_view.clear_aura()
	_shield_accent()


## D182: an imbued weapon's accent (edges, gems, fletching side) carries its
## element's colour at rest; an aura still overrides it while it burns.
var imbue_element := ""


func set_imbue(element: String) -> void:
	imbue_element = element
	if aura_element == "":
		for mi in meshes():
			mi.set_instance_shader_parameter("accent", _imbue_accent())
	if is_instance_valid(offhand_view):
		offhand_view.set_imbue(element)
	_shield_accent()


func _imbue_accent() -> Color:
	return Color(BWLook.element_color(imbue_element), 0.9) if imbue_element != "" else Color(1, 1, 1, 0)


func has_aura() -> bool:
	return aura_element != ""


## [core, rim] for an element colour: the shell's inner and outer colour.
## Very dark hues (dark) are lifted so the rim separates from the black sky;
## very bright ones (light, ice) are deepened so they hold on white tiles.
static func aura_colors(c: Color) -> Array:
	var lum := c.get_luminance()
	var core := c
	var rim := c
	if lum < 0.3:
		rim = c.lightened(0.28)
		core = c
	elif lum > 0.6:
		core = c.darkened(0.25)
		rim = c.darkened(0.1)
	return [core, rim]


func _clear_aura_nodes() -> void:
	for n in _aura_nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_aura_nodes.clear()


func _particle_amount(strength: float) -> int:
	return int(round((6 + 3 * meta.get("aura_points", []).size()) * clampf(strength, 0.25, 2.0)))


func _particles(element: String, cols: Array, strength: float) -> CPUParticles3D:
	var mo: Array = MOTION.get(element, [0.5, 0.1, 0.3, 0.8, 40.0])
	var p := CPUParticles3D.new()
	p.name = "aura_particles"
	p.amount = _particle_amount(strength)
	p.lifetime = mo[3]
	p.preprocess = mo[3]
	p.local_coords = false        # the wake trails behind a swing
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = aura_points()
	p.direction = Vector3.UP
	p.spread = mo[4]
	p.gravity = Vector3(0, mo[0], 0)
	p.initial_velocity_min = mo[1]
	p.initial_velocity_max = mo[2]
	p.angle_min = 45.0            # quads stand on a corner: low-poly diamonds
	p.angle_max = 45.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(0.2, 1.0))
	sc.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(cols[1], 0.95))
	g.set_color(1, Color(cols[0], 0.0))
	g.add_point(0.5, Color(cols[0], 0.85))
	p.color_ramp = g
	if "use_fixed_seed" in p:
		p.set("use_fixed_seed", true)
		p.set("seed", hash(weapon_id + element) & 0x7fffffff)
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	# Shared shader material (character lane): the StandardMaterial it replaced
	# had no `dim`, so the cutscene fade left particles bright.
	if _particle_mat == null:
		_particle_mat = ShaderMaterial.new()
		_particle_mat.shader = load(PARTICLE_SHADER)
	q.material = _particle_mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Shared fill material per role and outline width (white body or accent,
## black inverted hull as next pass).
static func material_for(role: String, width: float = OUTLINE) -> ShaderMaterial:
	var key := "%s|%.4f" % [role, width]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load(FILL_SHADER)
	m.set_shader_parameter("is_accent", role == "accent")
	m.next_pass = BWLook.outline(width, Color.BLACK)
	m.resource_name = "bw_weapon_" + role
	_materials[key] = m
	return m


static func surface_role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	return "accent" if n.begins_with("accent") else "body"


func _apply_materials(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mi.mesh.get_surface_count():
		if (mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			push_warning("BWWeaponView: %s surface %d has no vertex colours; it will render black" % [weapon_id, i])
		mi.set_surface_override_material(i, material_for(surface_role(mi.mesh, i), _outline))

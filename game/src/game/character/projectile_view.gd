class_name BWProjectileView
extends BWWeaponView
## One projectile model (arrow, bullet, bolt) at runtime, in the weapon look:
## white body, black inverted hull, an `accent` surface tinted by element
## (art/weapons/projectiles/<id>.glb, built by
## tools/blender/build_projectiles.py; metadata in projectiles.json).
##
##   var p := BWProjectileView.create_projectile("arrow")
##   p.set_accent("fire")              # tint the vanes / nose / facets only
##   p.set_aura("thunder", 1.2)        # bolts: the weapon aura (shell + particles)
##   p.basis = Basis.looking_at(velocity, Vector3.UP, true)   # +Z flies forward
##
## Projectile space: the origin is the leading point (arrow tip, bullet slug,
## bolt centre), +Z the flight direction. Inherits the aura, materials and
## outline from BWWeaponView; it is never attached to a rig.

const PROJ_PATH := "res://art/weapons/projectiles/projectiles.json"
const PROJ_VERSION := 1
## What each weapon class shoots (mirrors weapons.json "projectile").
const FOR_CLASS := { "bow": "arrow", "pistols": "bullet", "staff": "bolt" }

static var _proj := {}


static func load_projectile_meta(force: bool = false) -> Dictionary:
	if not _proj.is_empty() and not force:
		return _proj
	_proj = {}
	var f := FileAccess.open(PROJ_PATH, FileAccess.READ)
	if f == null:
		push_error("BWProjectileView: cannot open %s (run build_projectiles.py)" % PROJ_PATH)
		return _proj
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BWProjectileView: %s is not a JSON object" % PROJ_PATH)
		return _proj
	if int(parsed.get("version", 0)) != PROJ_VERSION:
		push_warning("BWProjectileView: %s version %s, expected %d" % [PROJ_PATH, parsed.get("version"), PROJ_VERSION])
	_proj = parsed
	return _proj


static func projectile_ids() -> PackedStringArray:
	return PackedStringArray(load_projectile_meta().get("projectiles", {}).keys())


static func projectile_meta(id: String) -> Dictionary:
	return load_projectile_meta().get("projectiles", {}).get(id, {})


static func create_projectile(id: String) -> BWProjectileView:
	var p := BWProjectileView.new()
	if not p.setup(id):
		p.free()
		return null
	return p


func setup(id: String) -> bool:
	if model != null:
		return weapon_id == id
	meta = projectile_meta(id)
	if meta.is_empty():
		push_error("BWProjectileView: no projectile '%s' in %s" % [id, PROJ_PATH])
		return false
	var scene := load(str(meta.glb)) as PackedScene
	if scene == null:
		push_error("BWProjectileView: cannot load %s (run --import?)" % meta.glb)
		return false
	weapon_id = id
	name = "projectile_" + id
	model = scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	for mi in meshes():
		_apply_materials(mi)
	_marker("tip", v3(meta.tip))
	_marker("trail_base", v3(meta.tail))
	return true


## Tint only the accent surface (vanes, nose, facets) with an element's colour.
func set_accent(element: String, amount: float = 1.0) -> void:
	var col := Color(1, 1, 1, 0)
	if element != "":
		col = Color(aura_colors(BWLook.element_color(element))[1], clampf(amount, 0.0, 1.0))
	for mi in meshes():
		mi.set_instance_shader_parameter("accent", col)


func length() -> float:
	return float(meta.get("length", 0.5))

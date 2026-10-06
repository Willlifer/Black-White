extends SceneTree
## D146 review renders: hair colour by affinity rank on dressed characters
## (BWCharacter, the game's real shaders). Needs a window (not --headless):
##
##   godot --path game --resolution 1800x1250 -s res://tools/hair_ranks_preview.gd [-- --out <dir>] [--only front|back|combat]
##
## Writes to design/art/ (or --out):
##   hair_ranks_front.png    4 archetypes x 9 looks, head-and-shoulders, 3/4 front
##   hair_ranks_back.png     the same, 3/4 back (where the long ombres show)
##   hair_ranks_combat.png   3 archetypes x 9 looks at the combat camera
##   hair_ranks_combat_zoom.png  the same board, camera pulled in to 11 u
##                           (24 u, FOV 34, pitch 42) on white hexes, black sky

const STYLES := ["bob", "long_ponytail", "short_mohawk", "mullet"]
const COMBAT_STYLES := ["bob", "long_hair", "high_and_tight"]
## [label, affinity in ranks, focus]
const LOOKS := [
	["rank 0", {}, ""],
	["fire 1", { "fire": 1 }, "fire"],
	["fire 2", { "fire": 2 }, "fire"],
	["fire 3", { "fire": 3 }, "fire"],
	["fire 3, water 1", { "fire": 3, "water": 1 }, "fire"],
	["light 2, dark 2", { "light": 2, "dark": 2 }, "light"],
	["ice 3, thunder 2, wind 1", { "ice": 3, "thunder": 2, "wind": 1 }, "ice"],
	["dark 1", { "dark": 1 }, "dark"],
	["water 1", { "water": 1 }, "water"],
]
const PAPER := Color(0.93, 0.93, 0.93)

var out_dir := ""
var only := ""
var _world: Node3D
var _cam: Camera3D
var _env: WorldEnvironment


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	i = args.find("--only")
	only = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	BWCharacter.animate = false
	_run.call_deferred()


func _run() -> void:
	_env = WorldEnvironment.new()
	root.add_child(_env)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	for view in [["front", -35.0], ["back", 150.0]]:
		if only != "" and only != view[0]:
			continue
		_reset(false)
		for r in STYLES.size():
			for c in LOOKS.size():
				var p := Vector3((c - 4.0) * 1.25, (1.5 - r) * 1.6 - 1.95, r * 3.0)
				_figure(p, view[1], STYLES[r], LOOKS[c])
			_label(STYLES[r].replace("_", " "), Vector3(-4.0 * 1.25 - 1.0, (1.5 - r) * 1.6 + 0.05, r * 3.0 + 1.0), 30, HORIZONTAL_ALIGNMENT_RIGHT)
		for c in LOOKS.size():
			_label(str(LOOKS[c][0]), Vector3((c - 4.0) * 1.25, 3.25, 12.0), 20)
		_ortho(Vector3(-0.6, 0.2, 0), 8.6)
		await _shot("hair_ranks_%s.png" % view[0])
	if only == "" or only == "combat":
		_reset(true)
		for r in COMBAT_STYLES.size():
			for c in LOOKS.size():
				var h := Vector2i(c - 4 - (r + 1) / 2 + 1, r - 1)
				var at := BWLook.world(h, 0)
				_hex(at)
				_figure(at + Vector3(0, BWLook.TILE_HEIGHT, 0), -20.0, COMBAT_STYLES[r], LOOKS[c])
		_aim(Vector3(0.0, 0.8, 0.0), -42.0, 0.0, 24.0, 34.0)
		await _shot("hair_ranks_combat.png")
		_aim(Vector3(0.0, 1.4, 0.0), -42.0, 0.0, 11.0, 34.0)
		await _shot("hair_ranks_combat_zoom.png")
	quit(0)


func _figure(at: Vector3, yaw_deg: float, style: String, look: Array) -> BWCharacter:
	var u := BWUnit.from_roster(BWData.table("roster")[0])
	u.id = "ranks_%s_%s" % [style, look[0]]
	u.cosmetics["hair_style"] = style
	u.cosmetics["hair_variant"] = 0
	u.affinity = {}
	var ranks: Dictionary = look[1]
	for el in ranks:
		u.affinity[el] = int(ranks[el]) * BWUnit.POINTS_PER_RANK
	u.element = ranks.keys()[0] if not ranks.is_empty() else ""
	u.focus_element = str(look[2])
	var c := BWCharacter.create(u)
	c.breathing = false
	_world.add_child(c)
	c.position = at
	c.rotation.y = deg_to_rad(yaw_deg)
	c.pose("idle", 0.0)
	return c


func _label(text: String, at: Vector3, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = Color.BLACK
	l.outline_size = 0
	l.horizontal_alignment = align
	l.position = at
	_world.add_child(l)


func _reset(sky: bool) -> void:
	if _world:
		_world.queue_free()
	_world = Node3D.new()
	root.add_child(_world)
	if sky:
		_env.environment = BWLook.starfield_environment()
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = PAPER
		e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_env.environment = e


## A white tile with a black rim and grey walls, like the board's.
func _hex(at: Vector3) -> void:
	var parts := [
		[1.0, BWLook.TILE_HEIGHT, BWLook.SIDE, at.y + BWLook.TILE_HEIGHT / 2.0],
		[0.98, 0.012, BWLook.INK, at.y + BWLook.TILE_HEIGHT + 0.006],
		[0.98 - BWLook.BORDER, 0.016, BWLook.WHITE, at.y + BWLook.TILE_HEIGHT + 0.008],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 6
		cm.rings = 1
		cm.top_radius = p[0]
		cm.bottom_radius = p[0]
		cm.height = p[1]
		mi.mesh = cm
		mi.rotation.y = deg_to_rad(30.0)
		mi.position = Vector3(at.x, p[3], at.z)
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[2])
		_world.add_child(mi)


func _aim(target: Vector3, pitch_deg: float, yaw_deg: float, dist: float, fov: float) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0))
	_cam.global_transform = Transform3D(basis, target + basis.z * dist)
	_cam.fov = fov


func _ortho(center: Vector3, size: float) -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = size
	_cam.near = 0.1
	_cam.far = 100.0
	_cam.global_transform = Transform3D(Basis.IDENTITY, center + Vector3(0, 0, 30))


func _shot(file: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path)

extends SceneTree
## Renders every hair archetype on the base rig with the game's real
## shaders, for visual checks. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/hair_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/hair_preview.gd -- --out <dir> --only front
##
## Writes to design/art/ (or --out):
##   hair_closeup_{front,34,back}.png  10 styles x 3 elements, paper background
##   hair_detail_{front,34}.png        10 styles, large, one element each
##   hair_heads_{front,34,back}.png    10 styles, head-and-shoulders close-ups
##   hair_variants.png                 hair_variant 0-3 of every style, 3/4 front
##   hair_combat_{front,34,back}.png   the combat camera (24 u, FOV 34, 42 deg)
##                                     on white hexes against the black sky
##   hair_turns.png                    head yaw -30 / +30 (clipping check)

const STYLES := ["buzzed", "high_and_tight", "mullet", "short_mohawk", "bob",
		"ponytail", "long_ponytail", "waterfall", "ringlets", "long_hair"]
const ELEMENTS := ["fire", "ice", "dark"]
const VIEWS := {"front": 0.0, "34": -40.0, "back": 180.0}
const COMBAT_PITCH := -42.0
const COMBAT_FOV := 34.0
const COMBAT_DIST := 24.0
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
	_run.call_deferred()


func _want(tag: String) -> bool:
	return only == "" or tag.contains(only)


func _run() -> void:
	_env = WorldEnvironment.new()
	root.add_child(_env)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()

	# --- close-ups: 3 element rows x 10 styles, orthographic, paper ground
	for view in VIEWS:
		if not _want("closeup_" + view):
			continue
		_reset(false)
		for r in ELEMENTS.size():
			for c in STYLES.size():
				var p := Vector3((c - 4.5) * 1.18, (1 - r) * 2.35 - 1.3, -r * 4.0)
				_figure(p, VIEWS[view], STYLES[c], ELEMENTS[r])
		_ortho(Vector3(0, 0.15, 0), 7.25)
		await _shot("hair_closeup_%s.png" % view)

	# --- detail: 2 rows of 5, bigger, elements cycling
	for view in ["front", "34"]:
		if not _want("detail_" + view):
			continue
		_reset(false)
		for k in STYLES.size():
			var c := k % 5
			var r := k / 5
			var p := Vector3((c - 2.0) * 1.75, (0.5 - r) * 2.75 - 1.55, -r * 4.0)
			_figure(p, VIEWS[view], STYLES[k], ["fire", "water", "light", "thunder", "wind", "ice", "dark"][k % 7])
		_ortho(Vector3(0, 0.0, 0), 5.0)
		await _shot("hair_detail_%s.png" % view)

	# --- heads: 2 rows of 5 head-and-shoulders close-ups, the read up close.
	# The lower row stands nearer the camera so it covers the upper row's tails.
	for view in VIEWS:
		if not _want("heads_" + view):
			continue
		_reset(false)
		for k in STYLES.size():
			var c := k % 5
			var r := k / 5
			var p := Vector3((c - 2.0) * 1.3, (0.5 - r) * 1.75 - 1.92, r * 3.0)
			_figure(p, VIEWS[view], STYLES[k], ["fire", "water", "light", "thunder", "wind", "ice", "dark"][k % 7])
		_ortho(Vector3(0, 0.05, 0), 3.7)
		await _shot("hair_heads_%s.png" % view)

	# --- variants: rows = hair_variant 0..3 (plain, alt, mirrored, alt +
	# mirrored), columns = styles, 3/4 front. Lower rows stand nearer.
	if _want("variants"):
		_reset(false)
		for v in 4:
			for c in STYLES.size():
				var p := Vector3((c - 4.5) * 1.2, (1.5 - v) * 1.55 - 1.92, v * 3.0)
				_figure(p, -30.0, STYLES[c], ELEMENTS[(c + v) % 3], v)
		_ortho(Vector3(0, -0.1, 0), 6.9)
		await _shot("hair_variants.png")

	# --- combat camera: white hexes, black sky, 3 rows of 10
	for view in VIEWS:
		if not _want("combat_" + view):
			continue
		_reset(true)
		for r in ELEMENTS.size():
			for c in STYLES.size():
				var h := Vector2i(c - 5 - (r + 1) / 2 + 1, r - 1)
				var at := BWLook.world(h, 0)
				_hex(at)
				_figure(at + Vector3(0, BWLook.TILE_HEIGHT, 0), VIEWS[view], STYLES[c], ELEMENTS[r])
		_aim(Vector3(0.0, 0.8, 0.0), COMBAT_PITCH, 0.0, COMBAT_DIST, COMBAT_FOV)
		await _shot("hair_combat_%s.png" % view)

	# --- head turns: every style at yaw -30 and +30, seen from 3/4 back
	if _want("turns"):
		_reset(false)
		for r in 2:
			for c in STYLES.size():
				var p := Vector3((c - 4.5) * 1.18, (0.5 - r) * 2.5 - 1.25, -r * 4.0)
				var rig := _figure(p, 150.0, STYLES[c], ELEMENTS[c % 3])
				var hb := rig.skeleton.find_bone("head")
				rig.skeleton.set_bone_pose_rotation(hb, Quaternion(Vector3.UP, deg_to_rad(-30.0 if r == 0 else 30.0)))
		_ortho(Vector3(0, 0.0, 0), 6.9)
		await _shot("hair_turns.png")
	quit(0)


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


func _figure(at: Vector3, yaw_deg: float, style: String, element: String, variant: int = 0) -> BWCharacterRig:
	var r := BWCharacterRig.new()
	_world.add_child(r)
	r.position = at
	r.rotation.y = deg_to_rad(yaw_deg)
	var h := BWHair.create(style, element, variant)
	if h:
		h.attach_to(r)
	else:
		push_error("hair_preview: no hair %s" % style)
	return r


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
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path)

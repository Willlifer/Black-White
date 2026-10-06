extends SceneTree
## Renders the base rig with the game's real shaders, for visual checks.
## Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/rig_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/rig_preview.gd -- --out <dir>
##
## Writes base_rig_godot_{gamescale,closeup,turntable}.png to design/art/
## (or --out). Each shot puts rigs on white hexes against the black
## starfield, so both contour cases (white-on-black, black-on-white) show.

const CAM_PITCH := -52.0    # combat camera (combat_screen.gd)
const CAM_FOV := 38.0
const CAM_DIST := 21.0
const CINE_FOV := 24.0      # attack cutscene

var out_dir := ""
var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = BWLook.starfield_environment()
	root.add_child(env)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()

	# --- game scale: the combat camera on a little patch of board
	_world = Node3D.new()
	root.add_child(_world)
	var spots := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]
	for h in spots:
		_hex(BWLook.world(h, 0))
	var cast := [
		[Vector2i(0, 0), 0.0, "rig_idle", 0.0], [Vector2i(1, 0), 200.0, "rig_idle", 1.0],
		[Vector2i(2, 0), 90.0, "rig_stress", 1.5], [Vector2i(1, 1), 35.0, "rig_idle", 0.5],
		[Vector2i(0, 1), -140.0, "rig_stress", 0.75],
	]
	for c in cast:
		_figure(BWLook.world(c[0], 0), c[1], c[2], c[3])
	# two figures off the board, straight on the black sky
	_figure(BWLook.world(Vector2i(3, 1), 0) + Vector3(0.6, 0, 0), 20.0, "rig_idle", 0.2)
	_figure(BWLook.world(Vector2i(-2, 0), 0), -30.0, "rig_stress", 1.5)
	_aim(BWLook.world(Vector2i(1, 0), 0) + Vector3(0, 0.6, 0.4), CAM_PITCH, 0.0, CAM_DIST, CAM_FOV)
	await _shot("base_rig_godot_gamescale.png")

	# --- cutscene close-up: the attack camera framing, two figures squared off
	_world.queue_free()
	_world = Node3D.new()
	root.add_child(_world)
	_hex(Vector3.ZERO)
	_hex(BWLook.world(Vector2i(1, 0), 0))
	var a := BWLook.world(Vector2i(0, 0), 0)
	var b := BWLook.world(Vector2i(1, 0), 0)
	_figure(a, 90.0, "rig_stress", 1.5)
	_figure(b, -90.0, "rig_idle", 0.4)
	_aim((a + b) / 2.0 + Vector3(0, 1.1, 0), -24.0, 0.0, 11.0, CINE_FOV)
	await _shot("base_rig_godot_closeup.png")

	# --- turntable: front, 3/4, side, back, stress, at eye level
	_world.queue_free()
	_world = Node3D.new()
	root.add_child(_world)
	var yaws := [0.0, 40.0, 90.0, 180.0, 215.0]
	for k in yaws.size():
		var p := Vector3((k - 2) * 1.9, 0, 0)
		_hex(p)
		_figure(p, yaws[k], "rig_stress" if k == 4 else "", 1.5)
	_aim(Vector3(0, 1.1, 0), -8.0, 0.0, 13.5, 30.0)
	await _shot("base_rig_godot_turntable.png")
	quit(0)


func _figure(at: Vector3, yaw_deg: float, anim_name: String, t: float) -> BWCharacterRig:
	var r := BWCharacterRig.new()
	_world.add_child(r)
	r.position = at + Vector3(0, BWLook.TILE_HEIGHT, 0)
	r.rotation.y = deg_to_rad(yaw_deg)
	if anim_name != "":
		r.pose_at(anim_name, t)
	return r


## A white tile with a black rim and grey walls, like the board's.
func _hex(at: Vector3) -> void:
	var parts := [
		[1.0, BWLook.TILE_HEIGHT, BWLook.SIDE, 0.0],
		[0.98, 0.012, BWLook.INK, BWLook.TILE_HEIGHT],
		[0.98 - BWLook.BORDER, 0.016, BWLook.WHITE, BWLook.TILE_HEIGHT],
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
		mi.position = at + Vector3(0, p[3] + p[1] / 2.0 - (p[1] if p[3] > 0 else 0.0) / 2.0 + (0.0 if p[3] == 0 else p[1] / 2.0 - 0.006), 0)
		if p[3] == 0.0:
			mi.position = at + Vector3(0, p[1] / 2.0, 0)
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[2])
		_world.add_child(mi)


func _aim(target: Vector3, pitch_deg: float, yaw_deg: float, dist: float, fov: float) -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0))
	_cam.global_transform = Transform3D(basis, target + basis.z * dist)
	_cam.fov = fov


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path)

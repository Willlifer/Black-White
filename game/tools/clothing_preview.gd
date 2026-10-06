extends SceneTree
## Renders every garment on the rig with the game's real shaders, in all
## three shades, for visual checks. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/clothing_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/clothing_preview.gd -- --out <dir> --only tops_front
##
## Writes design/art/clothing_*.png (or --out):
##   clothing_{tops,bottoms}_{front,side,stress}.png  rows = dark / mid / light
##   clothing_{tops,bottoms}_poses.png   wide stance, squat, stride, reach (mid)
##   clothing_{tops,bottoms}_zoom.png   front close-up of the garment zone
##   clothing_{tops,bottoms}_detail_{1,2}.png  stress pose close-ups, 3/4 and back
##   clothing_gamescale.png    roster outfits under the combat camera (24 u, FOV 34)
##   clothing_closeup.png      cutscene framing (FOV 24)
## Poses are driven bone by bone in code (no baked action), in the rig's
## convention: euler degrees in each bone's local frame, +X pitches forward.

const CAM_PITCH := -52.0
const CAM_FOV := 34.0
const CAM_DIST := 24.0
const CINE_FOV := 24.0

const STRESS := {   # rig_stress: elbows and knees at 120, hips past 90, twist
	"upper_arm_l": Vector3(80, 0, -10), "forearm_l": Vector3(120, 0, 0), "hand_l": Vector3(30, 0, 0),
	"upper_arm_r": Vector3(-20, 0, -60), "forearm_r": Vector3(120, 0, 0), "hand_r": Vector3(-20, 0, 0),
	"thigh_l": Vector3(100, 0, 0), "shin_l": Vector3(-120, 0, 0), "foot_l": Vector3(25, 0, 0),
	"thigh_r": Vector3(-25, 0, 0), "shin_r": Vector3(-120, 0, 0), "foot_r": Vector3(-10, 0, 0),
	"spine": Vector3(8, 12, 0), "chest": Vector3(10, 12, 0), "neck": Vector3(-8, 0, 0), "head": Vector3(6, 0, 10),
}

var out_dir := ""
var only := ""
var _world: Node3D
var _cam: Camera3D
var _abduct := 1.0     # sign of the outward Z rotation on the left thigh (solved)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	i = args.find("--only")
	only = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	# the game opens maximized (D51); sheets are a fixed 1600x900
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	_run.call_deferred()


func _want(n: String) -> bool:
	return only == "" or n in only.split(",")


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = BWLook.starfield_environment()
	root.add_child(env)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	_solve_abduct()

	for group in ["tops", "bottoms"]:
		var ids: PackedStringArray = BWClothing.TOPS if group == "tops" else BWClothing.BOTTOMS
		for view in ["front", "side", "stress"]:
			if not _want("%s_%s" % [group, view]):
				continue
			_new_world()
			var yaw: float = {"front": 0.0, "side": 90.0, "stress": 35.0}[view]
			for row in 3:
				var shade: String = ["dark", "mid", "light"][row]
				for col in ids.size():
					var p := Vector3((col - (ids.size() - 1) / 2.0) * 1.55, (1 - row) * 2.75, 0)
					var r := _figure(p, yaw, [ids[col]], shade, STRESS if view == "stress" else {})
					if view == "stress":
						r.position.y -= 0.3
			_ortho(Vector3(0, 1.05, 0), 8.6)
			await _shot("clothing_%s_%s.png" % [group, view])
		if _want("%s_zoom" % group):
			_new_world()
			for col in ids.size():
				for row in 2:
					var p := Vector3((col - (ids.size() - 1) / 2.0) * 1.0, 0, row * -40.0)
					var shade: String = ["dark", "mid", "light"][col % 3]
					var r := _figure(p + Vector3(0, -row * 0.0, 0), 0.0, [ids[col]], shade, {})
					r.visible = row == 0
			_ortho(Vector3(0, 1.25 if group == "tops" else 0.75, 0), 4.0)
			await _shot("clothing_%s_zoom.png" % group)
		for part in 2:
			if not _want("%s_detail_%d" % [group, part + 1]):
				continue
			_new_world()
			var sub := ids.slice(part * 4, part * 4 + 4)
			for k in sub.size():
				for back in 2:
					var p := Vector3((k - (sub.size() - 1) / 2.0) * 1.45, back * -2.35, 0)
					var shade: String = ["dark", "mid", "light"][(k + part) % 3]
					var r := _figure(p, 215.0 if back else 35.0, [sub[k]], shade, STRESS)
					r.position.y -= 0.35
			_ortho(Vector3(0, -0.15, 0), 4.9)
			await _shot("clothing_%s_detail_%d.png" % [group, part + 1])
		if _want("%s_poses" % group):
			_new_world()
			var poses := _poses()
			var names := poses.keys()
			for row in names.size():
				for col in ids.size():
					var p := Vector3((col - (ids.size() - 1) / 2.0) * 1.55, (1.5 - row) * 2.6, 0)
					var yaw := 25.0 if row % 2 == 0 else -30.0
					var r := _figure(p, yaw, [ids[col]], "mid", poses[names[row]])
					if names[row] == "squat":
						r.position.y += 0.35
					elif names[row] == "reach":
						r.position.y -= 0.3
			_ortho(Vector3(0, 1.0, 0), 10.9)
			await _shot("clothing_%s_poses.png" % group)

	if _want("gamescale"):
		_new_world()
		var rows := BWData.table("roster")
		var spots := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
			Vector2i(2, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(3, -1), Vector2i(-1, 2)]
		for k in spots.size():
			var h: Vector2i = spots[k]
			_hex(BWLook.world(h, 0))
			var row: Dictionary = rows[k % rows.size()]
			var pose: Dictionary = STRESS if k == 4 else ({} if k % 3 else _poses()["wide"])
			_figure(BWLook.world(h, 0), [0.0, 200.0, 35.0, -60.0, 90.0, 160.0][k % 6], [row.top, row.bottom], row.clothing_shade, pose)
		_aim(BWLook.world(Vector2i(1, 0), 0) + Vector3(0, 0.6, 0.4), CAM_PITCH, 0.0, CAM_DIST, CAM_FOV)
		await _shot("clothing_gamescale.png")

	if _want("closeup"):
		_new_world()
		var a := BWLook.world(Vector2i(0, 0), 0)
		var b := BWLook.world(Vector2i(1, 0), 0)
		_hex(a)
		_hex(b)
		_figure(a, 90.0, ["hoodie", "ripped_tight_pants"], "dark", STRESS)
		_figure(b, -90.0, ["sweater_scarf", "baggy_sweatpants"], "light", _poses()["wide"])
		_aim((a + b) / 2.0 + Vector3(0, 1.1, 0), -14.0, 0.0, 8.5, CINE_FOV)
		await _shot("clothing_closeup.png")
	quit(0)


func _poses() -> Dictionary:
	var a := _abduct
	return {
		"wide": _mirror({"thigh_l": Vector3(10, 0, a * 38), "shin_l": Vector3(-45, 0, 0), "foot_l": Vector3(0, 0, -a * 20),
			"upper_arm_l": Vector3(0, 0, a * 55), "forearm_l": Vector3(90, 0, 0)}),
		"squat": _mirror({"thigh_l": Vector3(95, 0, a * 12), "shin_l": Vector3(-120, 0, 0), "foot_l": Vector3(25, 0, 0),
			"upper_arm_l": Vector3(60, 0, 0), "forearm_l": Vector3(110, 0, 0), "spine": Vector3(12, 0, 0)}),
		"stride": {"thigh_l": Vector3(45, 0, 0), "shin_l": Vector3(-60, 0, 0), "thigh_r": Vector3(-30, 0, 0),
			"shin_r": Vector3(-30, 0, 0), "upper_arm_l": Vector3(-35, 0, 0), "upper_arm_r": Vector3(40, 0, 0),
			"forearm_r": Vector3(60, 0, 0), "forearm_l": Vector3(20, 0, 0), "spine": Vector3(0, 8, 0)},
		"reach": _mirror({"upper_arm_l": Vector3(150, 0, 0), "forearm_l": Vector3(30, 0, 0), "chest": Vector3(-8, 0, 0)}),
	}


func _mirror(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	for k in p:
		if str(k).ends_with("_l"):
			var r := str(k).trim_suffix("_l") + "_r"
			if not out.has(r):
				out[r] = Vector3(p[k].x, -p[k].y, -p[k].z)
	return out


## Same composition as Blender's Euler('XYZ'): R = Rz * Ry * Rx, in the
## bone's local frame, on top of its rest rotation.
static func pose_rig(rig: BWCharacterRig, pose: Dictionary) -> void:
	var sk := rig.skeleton
	if rig.anim:
		rig.anim.stop()
	for i in sk.get_bone_count():
		sk.reset_bone_pose(i)
	for name in pose:
		var bi := sk.find_bone(name)
		if bi < 0:
			continue
		var e: Vector3 = pose[name] * (PI / 180.0)
		var d := Basis(Vector3(0, 0, 1), e.z) * Basis(Vector3(0, 1, 0), e.y) * Basis(Vector3(1, 0, 0), e.x)
		sk.set_bone_pose_rotation(bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion() * d.get_rotation_quaternion())


func _solve_abduct() -> void:
	var r := BWCharacterRig.new()
	r.build()
	var sk := r.skeleton
	var knee0 := sk.get_bone_global_pose(sk.find_bone("shin_l")).origin.x
	pose_rig(r, {"thigh_l": Vector3(0, 0, 30)})
	sk.force_update_all_bone_transforms()
	var knee1 := sk.get_bone_global_pose(sk.find_bone("shin_l")).origin.x
	_abduct = 1.0 if knee1 > knee0 else -1.0
	r.free()


func _new_world() -> void:
	if _world:
		_world.queue_free()
	_world = Node3D.new()
	root.add_child(_world)


func _figure(at: Vector3, yaw_deg: float, garments: Array, shade: String, pose: Dictionary) -> BWCharacterRig:
	var r := BWCharacterRig.new()
	_world.add_child(r)
	r.position = at + Vector3(0, BWLook.TILE_HEIGHT, 0)
	r.rotation.y = deg_to_rad(yaw_deg)
	for g in garments:
		if str(g) != "":
			BWClothing.wear(r, str(g), shade)
	if not pose.is_empty():
		pose_rig(r, pose)
	elif r.anim:
		r.anim.stop()
	return r


func _hex(at: Vector3) -> void:
	for p in [[1.0, BWLook.TILE_HEIGHT, BWLook.SIDE, 0.0], [0.98, 0.012, BWLook.INK, 1.0], [0.98 - BWLook.BORDER, 0.016, BWLook.WHITE, 2.0]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 6
		cm.rings = 1
		cm.top_radius = p[0]
		cm.bottom_radius = p[0]
		cm.height = p[1]
		mi.mesh = cm
		mi.rotation.y = deg_to_rad(30.0)
		mi.position = at + Vector3(0, p[1] / 2.0 if p[3] == 0.0 else BWLook.TILE_HEIGHT + p[3] * 0.004, 0)
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[2])
		_world.add_child(mi)


func _ortho(center: Vector3, size: float) -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = size
	_cam.global_transform = Transform3D(Basis.IDENTITY, center + Vector3(0, 0, 30))
	_cam.near = 0.1
	_cam.far = 100.0


func _aim(target: Vector3, pitch_deg: float, yaw_deg: float, dist: float, fov: float) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0))
	_cam.global_transform = Transform3D(basis, target + basis.z * dist)
	_cam.fov = fov


func _shot(file: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path)

extends SceneTree
## Renders assembled roster characters (BWCharacter) with the game's real
## shaders. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/character_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/character_preview.gd -- --only poses --style heavy
##   ... -- --only turntable | poses | layers | combat     --out <dir>
##
## Writes to design/art/ (or --out):
##   roster_turntable_1.png / _2.png   10 characters each: front, 3/4, back, close range
##   roster_turntable_combat.png       all 20 at the combat camera (21 u, FOV 38, pitch -52)
##   poses_<style>.png                 the 11 key poses for one character per weapon
##                                     style, 3/4 front (top row) and side (bottom row)
##   character_layers.png              armour layering cases over clothes and hair

const POSE_CHARS := {
	"one": "stryker", "heavy": "della", "polearm": "rui", "spear": "dragtol",
	"staff": "jericho", "pair": "will", "bow": "gail", "pistol": "sala",
}
## Extra heavy-weapon wielders get their own sheet: the anchor and warhammer
## hold differently from the flamberge.
const EXTRA_POSE := { "heavy_anchor": "aureli", "polearm_lance": "bob" }

var out_dir := ""
var only := ""
var style_only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	i = args.find("--only")
	only = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	i = args.find("--style")
	style_only = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(k: String) -> bool:
	return only == "" or only == k


func _run() -> void:
	if _want("poses"):
		var all := POSE_CHARS.duplicate()
		all.merge(EXTRA_POSE)
		for st in all:
			if style_only == "" or style_only == st:
				await _pose_sheet(st, all[st])
	if _want("turntable"):
		var rows := BWData.table("roster")
		await _turntable(rows.slice(0, 10), "roster_turntable_1.png")
		await _turntable(rows.slice(10, 20), "roster_turntable_2.png")
	if _want("combat"):
		await _combat_lineup()
	if _want("layers"):
		await _layers()
	quit(0)


func _unit(id: String) -> BWUnit:
	return BWRosterKits.unit(id)


## One cell: its own world, a hex tile under the feet, the starfield.
func _cell(size: Vector2i, u: BWUnit, yaw_deg: float, pose: String, focus: Vector3, dist: float, fov: float, pitch_deg: float, sky := true) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	if sky:
		we.environment = BWLook.starfield_environment()
	else:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.5, 0.5, 0.5)
		we.environment = e
	vp.add_child(we)
	var tile := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95
	cm.bottom_radius = 0.95
	cm.height = 0.35
	cm.radial_segments = 6
	tile.mesh = cm
	tile.material_override = BWLook.flat()
	tile.set_instance_shader_parameter("tint", BWLook.PAPER)
	tile.position.y = -0.175
	tile.rotation.y = PI / 6
	vp.add_child(tile)
	var c := BWCharacter.create(u)
	vp.add_child(c)
	c.rotation.y = deg_to_rad(yaw_deg)
	c.pose(pose, 0.0)
	var cam := Camera3D.new()
	cam.fov = fov
	vp.add_child(cam)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), 0, 0))
	cam.global_transform = Transform3D(b, focus + b.z * dist)
	cam.make_current()
	vp.set_meta("character", c)
	return vp


func _grab(vps: Array, cell: Vector2i, cols: int, path: String, labels: Array = []) -> void:
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var rows := int(ceil(vps.size() / float(cols)))
	var img := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	for n in vps.size():
		var part: Image = vps[n].get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, cell), Vector2i((n % cols) * cell.x, (n / cols) * cell.y))
	for vp in vps:
		vp.queue_free()
	img.save_png(out_dir.path_join(path))
	print("saved ", out_dir.path_join(path))


func _pose_sheet(st: String, id: String) -> void:
	var u := _unit(id)
	var cell := Vector2i(300, 420)
	var vps: Array = []
	for yaw in [-35.0, -90.0]:
		for p in BWCharacterPose.POSE_NAMES:
			var vp := _cell(cell, u, yaw, p, Vector3(0, 1.35, 0), 8.6, 30.0, -10.0)
			if p in ["windup", "strike", "cast"]:
				(vp.get_meta("character") as BWCharacter).set_aura(u.element, 1.0)
			vps.append(vp)
	await _grab(vps, cell, BWCharacterPose.POSE_NAMES.size(), "poses_%s.png" % st)


func _turntable(rows: Array, path: String) -> void:
	var cell := Vector2i(200, 300)
	var vps: Array = []
	for row in rows:
		for yaw in [0.0, -40.0, 180.0]:
			vps.append(_cell(cell, BWUnit.from_roster(row), yaw, "idle", Vector3(0, 1.2, 0), 5.6, 30.0, -8.0))
	await _grab(vps, cell, 6, path)


## All 20 under the true combat camera: 21 u, FOV 38, pitch -52, 900 px tall.
func _combat_lineup() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	vp.add_child(we)
	var rows := BWData.table("roster")
	for i in rows.size():
		var u := BWUnit.from_roster(rows[i])
		var tile := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.95
		cm.bottom_radius = 0.95
		cm.height = 0.35
		cm.radial_segments = 6
		tile.mesh = cm
		tile.material_override = BWLook.flat()
		tile.set_instance_shader_parameter("tint", BWLook.PAPER)
		var at := Vector3((i % 5 - 2) * 2.0, 0, (i / 5 - 1.5) * 2.0)
		tile.position = at + Vector3(0, -0.175, 0)
		tile.rotation.y = PI / 6
		vp.add_child(tile)
		var c := BWCharacter.create(u)
		vp.add_child(c)
		c.position = at
		c.rotation.y = deg_to_rad(-25.0 + 15.0 * (i % 3))
		c.pose("idle", 0.0)
	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	var b := Basis.from_euler(Vector3(deg_to_rad(-52.0), 0, 0))
	cam.global_transform = Transform3D(b, Vector3(0, 0.8, 0) + b.z * 21.0)
	cam.make_current()
	await _grab([vp], Vector2i(1600, 900), 1, "roster_turntable_combat.png")


## Layering cases: each armour piece over a hostile outfit, 3/4 front + back.
func _layers() -> void:
	var cases := [
		["demeter", { "chest": "platemail", "legs": "platelegs" }],   # long hair + plate + baggy
		["aureli", { "legs": "tights" }],                          # baggy under tights
		["burt", { "legs": "chaps" }],                                   # chaps over shorts
		["jericho", { "chest": "silken_robe" }],                         # waterfall + robe + sweatpants
		["apollyon", { "chest": "scarf" }],                           # sweater_scarf + scarf piece
		["kai", { "chest": "leather_cuirass", "head": "baseball_cap" }],# hoodie + cuirass, mohawk + cap
		["wilona", { "chest": "chain_mail", "legs": "robe_bottoms" }], # long ponytail + chain + skirt
		["della", { "chest": "brigandine", "head": "feathered_full_helm" }],
		["kira", { "chest": "vest", "head": "wizard_hat" }],
		["bob", { "chest": "gladiator_chestpiece", "legs": "leather_tassets" }],
	]
	var cell := Vector2i(240, 330)
	var vps: Array = []
	var run := BWRun.start([], 3)
	for cs in cases:
		var u := _unit(cs[0])
		for slot in cs[1]:
			u.equipment[slot] = run.make_item(cs[1][slot], "E")
		for yaw in [-35.0, 160.0]:
			vps.append(_cell(cell, u, yaw, "idle", Vector3(0, 1.2, 0), 5.4, 30.0, -8.0))
	await _grab(vps, cell, 6, "character_layers.png")

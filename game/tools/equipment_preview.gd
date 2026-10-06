extends SceneTree
## Renders every armour piece on the rig with the game's real shaders, for
## visual checks. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/equipment_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/equipment_preview.gd -- --out <dir> --only head
##
## Writes to design/art/ (or --out):
##   equipment_<slot>_closeup.png   one row per piece: plain / element A / element B,
##                                  each front and 3/4, at ~2x the cutscene scale
##   equipment_<slot>_combat.png    the same grid at true combat-camera scale
##                                  (21 u, FOV 38 over 900 px, pitch -52)
##   equipment_lineup.png           all 23 pieces in one combat-camera frame
## The two elements rotate per row so all seven show up across a sheet.
## Head rows wear a hair style (cycling) so hair_mode is visible.

const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]
const CAM_PITCH := -52.0
const CAM_FOV := 38.0
const CAM_DIST := 21.0
const FRAME_H := 900.0
const YAW_34 := 40.0
## slot -> [focus height, units tall, units wide] for the close-up cells
const CLOSE := {
	"head": [2.28, 1.35, 1.2],
	"chest": [1.17, 1.25, 1.35],
	"legs": [0.52, 1.2, 0.95],
}
const CLOSE_PX_PER_U := 330.0
const COMBAT_CELL := Vector2i(150, 205)

var out_dir := ""
var only := ""
var hair_styles: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	i = args.find("--only")
	only = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	if ClassDB.class_exists("BWHair") or ResourceLoader.exists("res://src/game/character/hair.gd"):
		hair_styles = ["buzzed", "bob", "long_hair", "short_mohawk", "ponytail", "mullet", "ringlets", "long_ponytail"]
	_run.call_deferred()


func _ids(slot: String) -> Array:
	var out: Array = []
	for id in BWEquipmentView.model_ids():
		if str(BWEquipmentView.info(id).slot) == slot:
			out.append(id)
	return out


func _run() -> void:
	for slot in ["head", "chest", "legs"]:
		if only != "" and only != slot and only != "lineup":
			continue
		if only == "lineup":
			break
		var ids := _ids(slot)
		await _sheet(slot, ids, true)
		await _sheet(slot, ids, false)
	if only == "" or only == "lineup":
		await _lineup()
	if only == "" or only == "pose":
		await _pose_sheet()
	quit(0)


## Skinned pieces in the rig_stress pose (elbows/knees 120, hip 100, spine
## twist), front and back-3/4: proves the rebind follows the rig skeleton.
func _pose_sheet() -> void:
	var ids: Array = []
	for id in BWEquipmentView.model_ids():
		if str(BWEquipmentView.info(id).attach) == "skinned" or str(BWEquipmentView.info(id).slot) != "head":
			ids.append(id)
	var cell := Vector2i(300, 380)
	var vps: Array = []
	for k in ids.size():
		for yaw in [-35.0, 145.0]:
			var vp := _cell(cell, ids[k], ELEMENTS[k % 7], yaw, "chest", true, ids[k] if yaw < 0 else "", "")
			var r: BWCharacterRig = vp.get_meta("rig")
			r.pose_at("rig_stress", 1.5)
			var cam: Camera3D = vp.get_meta("cam")
			var basis := Basis.from_euler(Vector3(deg_to_rad(-8.0), 0, 0))
			cam.global_transform = Transform3D(basis, Vector3(0, BWLook.TILE_HEIGHT + 1.05, 0) + basis.z * 7.0)
			cam.fov = rad_to_deg(2.0 * atan(1.15 / 7.0))
			vps.append(vp)
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var cols := 10
	var rows := int(ceil(vps.size() / float(cols)))
	var img := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	for n in vps.size():
		var part: Image = vps[n].get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, cell), Vector2i((n % cols) * cell.x, (n / cols) * cell.y))
	for vp in vps:
		vp.queue_free()
	var path := out_dir.path_join("equipment_pose_check.png")
	img.save_png(path)
	print("saved ", path)


## One grid: rows = pieces, cols = (plain, A, B) x (front, 3/4).
func _sheet(slot: String, ids: Array, close: bool) -> void:
	var cell: Vector2i
	if close:
		var c: Array = CLOSE[slot]
		cell = Vector2i(int(c[2] * CLOSE_PX_PER_U), int(c[1] * CLOSE_PX_PER_U))
	else:
		cell = COMBAT_CELL
	var vps: Array = []
	for r in ids.size():
		var id: String = ids[r]
		var els := ["", ELEMENTS[(r * 2) % 7], ELEMENTS[(r * 2 + 1) % 7]]
		for k in 6:
			var el: String = els[k / 2]
			var yaw := 0.0 if k % 2 == 0 else YAW_34
			var hair := hair_styles[r % hair_styles.size()] if slot == "head" and not hair_styles.is_empty() else ""
			var label := "%s%s%s" % [id if k == 0 else "", "" if el == "" else el, "  3/4" if k % 2 == 1 else ""]
			if k == 0 and hair != "":
				label += "  [%s]" % hair
			vps.append(_cell(cell, id, el, yaw, slot, close, label, hair))
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := Image.create(cell.x * 6, cell.y * ids.size(), false, Image.FORMAT_RGBA8)
	for n in vps.size():
		var vp: SubViewport = vps[n]
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, cell), Vector2i((n % 6) * cell.x, (n / 6) * cell.y))
	for vp in vps:
		vp.queue_free()
	var path := out_dir.path_join("equipment_%s_%s.png" % [slot, "closeup" if close else "combat"])
	img.save_png(path)
	print("saved ", path)
	await process_frame


func _cell(size: Vector2i, id: String, element: String, yaw: float, slot: String, close: bool, label: String, hair: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = BWLook.starfield_environment()
	vp.add_child(env)
	var world := Node3D.new()
	vp.add_child(world)
	_hex(world, Vector3.ZERO)
	var rig := BWCharacterRig.new()
	world.add_child(rig)
	rig.position = Vector3(0, BWLook.TILE_HEIGHT, 0)
	rig.rotation.y = deg_to_rad(yaw)
	if hair != "":
		var h = load("res://src/game/character/hair.gd").create(hair, element if element != "" else "fire")
		if h:
			h.attach_to(rig)
	var eq := BWEquipmentView.for_rig(rig)
	eq.equip_model(id, element)
	rig.pose_at("rig_idle", 0.0)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.make_current()
	if close:
		var c: Array = CLOSE[slot]
		var dist := 7.0
		var target := Vector3(0, BWLook.TILE_HEIGHT + c[0], 0)
		var basis := Basis.from_euler(Vector3(deg_to_rad(-8.0), 0, 0))
		cam.global_transform = Transform3D(basis, target + basis.z * dist)
		cam.fov = rad_to_deg(2.0 * atan(c[1] * 0.5 / dist))
	else:
		var target := Vector3(0, BWLook.TILE_HEIGHT + 1.0, 0)
		var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH), 0, 0))
		cam.global_transform = Transform3D(basis, target + basis.z * CAM_DIST)
		cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(CAM_FOV * 0.5)) * size.y / FRAME_H))
	vp.set_meta("rig", rig)
	vp.set_meta("cam", cam)
	var lab := Label.new()
	lab.text = label
	lab.position = Vector2(4, 2)
	lab.add_theme_font_size_override("font_size", 15 if close else 10)
	lab.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vp.add_child(lab)
	return vp


## Everything at once through the real combat camera: one frame, 23 figures.
func _lineup() -> void:
	var env := WorldEnvironment.new()
	env.environment = BWLook.starfield_environment()
	root.add_child(env)
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var rows := [_ids("head"), _ids("chest"), _ids("legs")]
	for r in rows.size():
		var ids: Array = rows[r]
		for k in ids.size():
			var x := (k - (ids.size() - 1) / 2.0) * 1.75
			var z := (r - 1) * 2.6
			var at := Vector3(x, 0, z)
			_hex(world, at)
			var rig := BWCharacterRig.new()
			world.add_child(rig)
			rig.position = at + Vector3(0, BWLook.TILE_HEIGHT, 0)
			rig.rotation.y = deg_to_rad(20.0 if k % 2 == 0 else -25.0)
			var eq := BWEquipmentView.for_rig(rig)
			var el: String = "" if (k + r) % 3 == 0 else ELEMENTS[(k + r * 3) % 7]
			eq.equip_model(ids[k], el)
			rig.pose_at("rig_idle", 0.3 * k)
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH), 0, 0))
	cam.global_transform = Transform3D(basis, Vector3(0, 1.0, 0.6) + basis.z * CAM_DIST)
	cam.fov = CAM_FOV
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("equipment_lineup.png")
	img.save_png(path)
	print("saved ", path)


## A white tile with a black rim and grey walls (rig_preview.gd's tile).
func _hex(parent: Node3D, at: Vector3) -> void:
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
		if p[3] == 0.0:
			mi.position = at + Vector3(0, p[1] / 2.0, 0)
		else:
			mi.position = at + Vector3(0, p[3] + p[1] / 2.0 - 0.006, 0)
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[2])
		parent.add_child(mi)

extends SceneTree
## D501-D507 review renders (needs a window): the 11 new weapon models and
## the lance-class shields, on the real character (clips, solver, shaders).
##   godot --path . --resolution 1600x900 --script res://tools/wpn501_shots.gd [-- --only lineup,inhand,shields,icons] [--out <dir>]
## -> design/art/
##   wpn501_lineup.png          every class row: the old models, then the new ones (rest pose, side-on, grey)
##   wpn501_inhand_a.png / _b   per new weapon: idle 3/4, idle from her weapon side, the strike at its hit,
##                              and the idle at the combat camera (24 u, FOV 34, pitch -52) on a tile
##   wpn501_shield_inhand.png   per shield (on the lance it comes with): idle 3/4, idle from her left,
##                              the strike, and the combat camera
##   wpn501_shield_icons.png    the item icons (BWItemIcons) of the 6 lance-class weapons, with the staves
##                              for comparison, plain and imbued

const DT := 1.0 / 60.0
const NEW := ["scythe", "rapier", "katana", "divine_staff", "orb_scepter", "trident", "naginata", "kunai",
	"karambit", "longbow", "ancestral_bow"]
const ROWS := [
	["sword", "scimitar", "flamberge", "|", "rapier", "katana"],
	["axe", "double_axe", "hatchet", "warhammer", "anchor", "|", "scythe"],
	["lance", "javelin", "halberd", "glaive", "|", "trident", "naginata"],
	["dagger", "jagged_dagger", "|", "kunai", "karambit", "|", "shortbow", "recurve_bow", "compound_bow", "|", "longbow", "ancestral_bow"],
	["staff", "moon_staff", "|", "divine_staff", "orb_scepter"],
]
## The representative roster character per style (as test_animation.gd).
const REPS := { "one": "stryker", "heavy": "della", "polearm": "rui", "spear": "dragtol",
	"staff": "jericho", "pair": "rem", "bow": "gail", "pistol": "sala", "fists": "will" }
const SHIELD_ON := { "kite_shield": "lance", "buckler": "javelin", "square_shield": "trident", "hand_guard": "halberd" }

var out_dir := ""
var only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	var j := args.find("--only")
	only = args[j + 1] if j >= 0 and j + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(n: String) -> bool:
	return only == "" or n in only.split(",")


func _run() -> void:
	if _want("lineup"):
		await _lineup()
	if _want("inhand"):
		var rows_a: Array = []
		var rows_b: Array = []
		for k in NEW.size():
			var row: Array = await _inhand_row(NEW[k])
			(rows_a if k < 6 else rows_b).append({ "name": "%s (%s, %s)" % [NEW[k], BWWeaponView.meta_for(NEW[k]).class,
				BWCharacterPose.style_for(BWWeaponView.meta_for(NEW[k]))], "cells": row })
		await _compose(out_dir.path_join("wpn501_inhand_a.png"), "D501 new weapons in hand: idle 3/4 | idle, her weapon side | strike at the hit | combat camera", rows_a, 4)
		await _compose(out_dir.path_join("wpn501_inhand_b.png"), "D501 new weapons in hand: idle 3/4 | idle, her weapon side | strike at the hit | combat camera", rows_b, 4)
	if _want("shields"):
		var rows: Array = []
		for sid in SHIELD_ON:
			var wid: String = SHIELD_ON[sid]
			rows.append({ "name": "%s on %s (%s mount)" % [sid, wid, BWShieldView.meta_for(sid).get("kind", "")],
				"cells": await _inhand_row(wid, true) })
		await _compose(out_dir.path_join("wpn501_shield_inhand.png"), "D505-D507 shields on the off hand: idle 3/4 | idle from her left | strike | combat camera", rows, 4)
	if _want("icons"):
		await _icons()
	quit(0)


# ------------------------------------------------------------------ lineup

func _lineup() -> void:
	var vp := _viewport(Vector2i(3200, 2400), Color(0.55, 0.55, 0.55))
	var w := Node3D.new()
	vp.add_child(w)
	var gap := 1.5
	var row_h := 3.6
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var n := row.size()
		for k in n:
			var id: String = row[k]
			if id == "|":
				continue
			var x := (k - (n - 1) / 2.0) * gap
			var y := -r * row_h
			var m := BWWeaponView.meta_for(id)
			var yaw := 50.0 if str(m.get("socket")) == "socket_weapon_r" else -50.0
			if m.get("hands") == "pair":
				yaw = 60.0
			var rig := BWCharacterRig.new()
			w.add_child(rig)
			rig.position = Vector3(x, y, 0)
			rig.rotation.y = deg_to_rad(yaw)
			var view := BWWeaponView.create(id)
			view.with_shield = false
			view.attach_to(rig)
			var tag := "NEW " if id in NEW else ""
			_label3(w, "%s%s\n%s · %s · %d tris" % [tag, id, m.get("class"), m.get("hands"), int(m.get("tris", 0))],
				Vector3(x, y - 0.3, 0.6), 0.0024, Color(0.0, 0.0, 0.35) if tag != "" else Color.BLACK)
	_label3(w, "D501: the 11 new models (NEW, blue) after their class siblings; rest pose, 3/4 toward the holding hand, grey ground",
		Vector3(0, 3.3, 0.6), 0.004, Color.BLACK)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 19.2
	cam.look_at_from_position(Vector3(0, -6.0, 30), Vector3(0, -6.0, 0), Vector3.UP)
	cam.make_current()
	var img := await _grab(vp)
	img.save_png(out_dir.path_join("wpn501_lineup.png"))
	print("saved ", out_dir.path_join("wpn501_lineup.png"))
	vp.queue_free()


# ------------------------------------------------------------------ in hand

func _unit_with(wid: String) -> BWUnit:
	var st := BWCharacterPose.style_for(BWWeaponView.meta_for(wid))
	var u := BWRosterKits.unit(REPS.get(st, "stryker"))
	u.weapon_class = str(BWWeaponView.meta_for(wid).get("class", u.weapon_class))
	u.weapon_model = wid
	u.equipment.erase("main_hand")
	return u


## [image, label] x4 for one weapon on its style's representative.
func _inhand_row(wid: String, shield_side: bool = false) -> Array:
	var cells: Array = []
	var vp := _viewport(Vector2i(460, 520), Color(0.6, 0.6, 0.6))
	var stage := Node3D.new()
	vp.add_child(stage)
	_tile(stage, Vector3.ZERO)
	var c := BWCharacter.create(_unit_with(wid))
	stage.add_child(c)
	c.set_process(false)
	if c.animator:
		c.animator.rotate_idles = false
	for i in 40:
		c._process(DT)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.far = 200.0
	vp.add_child(cam)
	cam.make_current()
	var side := -1.0 if BWWeaponView.meta_for(wid).get("socket") == "socket_offhand_l" or shield_side else 1.0
	# 3/4 front (toward the holding hand), then side-on from the holding hand
	_aim(cam, Vector3(0, 1.15, 0), -35.0 * side, 8.0, 7.2)
	cells.append([await _grab(vp), "idle 3/4"])
	_aim(cam, Vector3(0, 1.15, 0), -90.0 * side, 6.0, 7.2)
	cells.append([await _grab(vp), "idle, %s side" % ("left" if side < 0 else "right")])
	# the strike, at its hit (or its release)
	c.pose("strike")
	var hit := -1.0
	if c.animator:
		hit = c.animator.time_to("hit")
		if hit <= 0.0:
			hit = c.animator.time_to("release")
	var steps := int(round(hit / DT)) if hit > 0.0 else 30
	for i in steps:
		c._process(DT)
	_aim(cam, Vector3(0, 1.15, 0.3), -45.0 * side, 10.0, 7.6)
	cells.append([await _grab(vp), "strike @ hit (%.2f s)" % maxf(hit, 0.5)])
	# back to idle, at the combat camera
	c.pose("idle", 0.0)
	for i in 90:
		c._process(DT)
	# the game's combat camera (24 u, FOV 34, pitch 52) at its on-screen
	# scale for a 900 px tall window: the cell is 520 px tall, so FOV 34 x 520/900
	cam.fov = 34.0 * 520.0 / 900.0
	_aim(cam, Vector3(0, 0.9, 0), -25.0 * side, 52.0, 24.0)
	cells.append([await _grab(vp), "combat camera (true scale), idle"])
	vp.queue_free()
	return cells


# ------------------------------------------------------------------ icons

func _icons() -> void:
	var r := BWItemIcons.ensure(root)
	var ids := ["lance", "javelin", "halberd", "glaive", "trident", "naginata", "staff", "moon_staff", "divine_staff", "orb_scepter"]
	var cells_plain: Array = []
	var cells_el: Array = []
	for el in ["", "fire"]:
		for id in ids:
			var k := BWItemIcons.key_for(id, el)
			BWItemIcons._cache.erase(k)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(BWItemIcons.DIR + k + ".png"))   # always fresh
			BWItemIcons.icon(id, el)
	var t := 0.0
	while t < 60.0:
		var done := true
		for el in ["", "fire"]:
			for id in ids:
				if not BWItemIcons._cache.has(BWItemIcons.key_for(id, el)):
					done = false
		if done:
			break
		await process_frame
		t += 1.0 / 60.0
	for el in ["", "fire"]:
		for id in ids:
			var tex: Texture2D = BWItemIcons._cache.get(BWItemIcons.key_for(id, el))
			var img: Image = tex.get_image() if tex else Image.create(128, 128, false, Image.FORMAT_RGBA8)
			img.convert(Image.FORMAT_RGBA8)
			var bg := Image.create(176, 176, false, Image.FORMAT_RGBA8)
			bg.fill(Color(0.93, 0.92, 0.89))
			var big := img.duplicate() as Image
			big.resize(160, 160, Image.INTERPOLATE_NEAREST)
			bg.blend_rect(big, Rect2i(0, 0, 160, 160), Vector2i(8, 8))
			var shield := BWShieldView.shield_for(id)
			(cells_plain if el == "" else cells_el).append([bg, "%s%s" % [id, (" + " + shield) if shield != "" else ""]])
	await _compose(out_dir.path_join("wpn501_shield_icons.png"),
		"D505: item icons (BWItemIcons v%d, 128 px shown at 160) - the 6 lance-class weapons carry their shield; the 4 staves for comparison. Top plain, bottom imbued fire" % BWItemIcons.VERSION,
		[{ "name": "plain", "cells": cells_plain }, { "name": "fire", "cells": cells_el }], 10)
	r.queue_free()


# ------------------------------------------------------------------ helpers

func _viewport(size: Vector2i, bg: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	vp.add_child(we)
	return vp


func _tile(parent: Node, at: Vector3) -> void:
	var tile := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.97
	cm.bottom_radius = 0.97
	cm.height = 0.35
	cm.radial_segments = 6
	tile.mesh = cm
	tile.material_override = BWLook.flat()
	tile.set_instance_shader_parameter("tint", BWLook.PAPER)
	tile.position = at + Vector3(0, -0.175, 0)
	tile.rotation.y = PI / 6
	parent.add_child(tile)
	var rim := MeshInstance3D.new()
	rim.mesh = cm
	rim.material_override = BWLook.outline(0.03, Color.BLACK)
	tile.add_child(rim)


func _aim(cam: Camera3D, focus: Vector3, yaw: float, pitch: float, dist: float) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
	cam.global_transform = Transform3D(b, focus + b.z * dist)


func _grab(vp: SubViewport) -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func _label3(w: Node3D, text: String, at: Vector3, px: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = px
	l.font_size = 64
	l.modulate = col
	l.outline_size = 0
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	w.add_child(l)


## Rows of [image, label] cells into one PNG with a title.
func _compose(path: String, title: String, rows: Array, per_row: int) -> void:
	var cell: Vector2i = (rows[0].cells[0][0] as Image).get_size()
	var lab := 18
	var h := 34
	for r in rows:
		h += 22 + int(ceil((r.cells as Array).size() / float(per_row))) * (cell.y + lab)
	var size := Vector2i(cell.x * per_row, h)
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.6, 0.6, 0.6)
	bg.size = Vector2(size)
	vp.add_child(bg)
	var y := 4
	vp.add_child(_label(title, Vector2(8, y), 16, Color.BLACK))
	y += 30
	for r in rows:
		vp.add_child(_label(str(r.name), Vector2(6, y), 15, Color(0.05, 0.05, 0.35)))
		y += 22
		var cells: Array = r.cells
		for i in cells.size():
			var at := Vector2((i % per_row) * cell.x, y + (i / per_row) * (cell.y + lab))
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(cells[i][0])
			tr.position = at
			vp.add_child(tr)
			vp.add_child(_label(str(cells[i][1]), at + Vector2(4, cell.y), 12, Color.BLACK))
		y += int(ceil(cells.size() / float(per_row))) * (cell.y + lab)
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
	print("saved ", path)
	vp.queue_free()


func _label(t: String, at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

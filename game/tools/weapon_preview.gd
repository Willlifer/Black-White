extends SceneTree
## Renders the 22 weapons in the base rig's hands with the game's real
## shaders, for visual checks. Needs a window (not --headless):
##
##   godot --path game --resolution 1600x900 -s res://tools/weapon_preview.gd
##   godot --path game --resolution 1600x900 -s res://tools/weapon_preview.gd -- --out <dir> --only lineup,aura
##
## Writes to design/art/ (or --out):
##   weapons_lineup.png         all 22 at rest in the rig's hand, side-on, grey ground, labelled
##   weapons_combat.png         all 22 at the combat camera (24 u, FOV 34, pitch -52) on tiles and void
##   weapons_aura.png           3 weapons x 3 elements, over white tiles (top) and the black sky (bottom)
##   weapons_aura_elements.png  one sword per element, both grounds: the full palette check
##   weapons_fists.png          the 3 fists (D76) on posed rigs: close-ups plain / fire / ice
##                              accent, then game scale at the combat camera (guard, cross, palm)
##
## Each shot renders in its own SubViewport at a fixed size, so the output does
## not depend on the window size.

const COMBAT_PITCH := -52.0
const COMBAT_FOV := 34.0
const COMBAT_DIST := 24.0

## Lineup order: the 7 classes in SCHEMA order, three rows.
const ROWS := [
	["sword", "scimitar", "flamberge", "axe", "double_axe", "hatchet", "warhammer", "anchor"],
	["lance", "javelin", "halberd", "glaive", "dagger", "jagged_dagger", "shortbow", "recurve_bow", "compound_bow"],
	["pistol", "flintlock", "m1911", "staff", "moon_staff", "hand_wraps", "brass_knuckles", "gauntlets"],
]
const AURA_SET := [["flamberge", "fire"], ["warhammer", "thunder"], ["moon_staff", "light"]]
const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]

var out_dir := ""
var only: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	var j := args.find("--only")
	if j >= 0 and j + 1 < args.size():
		only = args[j + 1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _run() -> void:
	if _want("lineup"):
		await _lineup()
	if _want("combat"):
		await _combat()
	if _want("aura"):
		await _aura()
	if _want("elements"):
		await _elements()
	if _want("fists"):
		await _fists()
	quit(0)


# ----------------------------------------------------------------- shots

func _lineup() -> void:
	var vp := _viewport(Vector2i(3000, 2100), _flat_env(Color(0.55, 0.55, 0.55)))
	var w: Node3D = vp.get_meta("world")
	var gap := 1.75
	var row_h := 3.9
	for r in ROWS.size():
		var row: Array = ROWS[r]
		for k in row.size():
			var id: String = row[k]
			var x := (k - (row.size() - 1) / 2.0) * gap
			var y := -r * row_h
			var m := BWWeaponView.meta_for(id)
			# side-on to the weapon's hand: right-hand weapons show the figure's right side
			var yaw := 50.0 if str(m.get("socket")) == "socket_weapon_r" else -50.0
			if m.get("hands") == "pair":
				yaw = 60.0
			_figure(w, Vector3(x, y, 0), yaw, id, "")
			_label(w, "%s\n%s · %s · %d tris" % [id, m.get("class"), m.get("hands"), int(m.get("tris", 0))], Vector3(x, y - 0.32, 0.6), 0.0024)
	_label(w, "Black | White weapons v%d   rest pose, 3/4 toward the holding hand   grey ground so the white fill and black hull both show" % BWWeaponView.META_VERSION,
		Vector3(0, 3.35, 0.6), 0.004)
	var cam := _cam(vp, Vector3(0, -2.6, 30), Vector3(0, -2.6, 0), 0.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 13.4
	await _save(vp, "weapons_lineup.png")


func _combat() -> void:
	var vp := _viewport(Vector2i(2400, 1350), BWLook.starfield_environment())
	var w: Node3D = vp.get_meta("world")
	var all: Array = ROWS[0] + ROWS[1] + ROWS[2]
	var k := 0
	for r in 3:
		var n := 8 if r != 1 else 7
		for c in n:
			if k >= all.size():
				break
			var at := Vector3((c - (n - 1) / 2.0) * 2.6, 0, (r - 1) * 2.7)
			var on_tile := (c + r) % 3 != 2      # every third figure stands over the void
			if on_tile:
				_hex(w, at)
			var id: String = all[k]
			var yaw: float = [55.0, 75.0, 35.0, 100.0][k % 4]
			if str(BWWeaponView.meta_for(id).get("socket")) != "socket_weapon_r":
				yaw = -yaw
			_figure(w, at + Vector3(0, BWLook.TILE_HEIGHT if on_tile else 0.0, 0), yaw, id, "")
			k += 1
	var target := Vector3(0, 0.8, 0.3)
	var basis := Basis.from_euler(Vector3(deg_to_rad(COMBAT_PITCH), 0, 0))
	_cam(vp, target + basis.z * COMBAT_DIST, target, COMBAT_FOV)
	await _save(vp, "weapons_combat.png")


func _aura() -> void:
	var a := await _aura_strip(AURA_SET, 3, -50.0, 10.0, true)
	var b := await _aura_strip(AURA_SET, 3, -6.0, 10.0, false)
	_stack([a, b], "weapons_aura.png")


func _elements() -> void:
	var set := []
	for e in ELEMENTS:
		set.append(["sword", e])
	var a := await _aura_strip(set, 2, -50.0, 20.0, true)
	var b := await _aura_strip(set, 2, -6.0, 19.0, false)
	_stack([a, b], "weapons_aura_elements.png")


## A row of figures with aura weapons, `step` hexes apart. Top panel: on a
## strip of white tiles under the combat pitch (the weapons are seen against
## the tiles). Bottom: eye level, the weapons against the black sky.
func _aura_strip(set: Array, step: int, pitch: float, dist: float, tiles: bool) -> Image:
	var vp := _viewport(Vector2i(2400, 900), BWLook.starfield_environment())
	var w: Node3D = vp.get_meta("world")
	var n := set.size()
	var q0 := -step * (n - 1) / 2
	if tiles:
		for q in range(q0 - 3, -q0 + 4):
			for r in [-1, 0, 1]:
				_hex(w, BWLook.world(Vector2i(q - (r + 1) / 2 if r < 0 else q - r / 2, r), 0))
	for i in n:
		var at := BWLook.world(Vector2i(q0 + i * step, 0), 0)
		var id: String = set[i][0]
		var fig := _figure(w, at + Vector3(0, BWLook.TILE_HEIGHT if tiles else 0.0, 0), 65.0, id, "")
		var view: BWWeaponView = fig.get_meta("weapon")
		view.set_aura(set[i][1], 1.0)
		if not tiles:
			_label(w, "%s · %s" % [id, set[i][1]], at + Vector3(0, -0.2, 0.5), 0.004, Color.WHITE)
	var target := Vector3(0, 1.3 if not tiles else 1.1, 0.4 if tiles else 0.0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), 0, 0))
	_cam(vp, target + basis.z * dist, target, 30.0)
	return await _grab(vp)


## D76: the three fists, worn on both hands, on rigs posed by the static
## fallback (BWCharacterPose "fists"; no clip set yet). Top: close-ups in the
## guard, each model plain and with its accent tinted fire and ice. Bottom:
## the same three at the combat camera on tiles, in guard, cross and palm.
const FISTS := ["hand_wraps", "brass_knuckles", "gauntlets"]


func _fists() -> void:
	var rows: Array = []
	for look in ["", "fire", "ice"]:
		var cells: Array = []
		for id in FISTS:
			var vp := _viewport(Vector2i(800, 560), _flat_env(Color(0.55, 0.55, 0.55)))
			var w: Node3D = vp.get_meta("world")
			_posed(w, Vector3.ZERO, 25.0, id, "idle", look)
			_label(w, "%s%s" % [id, (" · " + look + " accent") if look != "" else " · plain"], Vector3(-0.85, 2.05, 0.0), 0.0012)
			_cam(vp, Vector3(1.25, 1.75, 2.6), Vector3(0.0, 1.5, 0.15), 30.0)
			cells.append(await _grab(vp))
		rows.append(_row(cells))
	var vp2 := _viewport(Vector2i(2400, 900), BWLook.starfield_environment())
	var w2: Node3D = vp2.get_meta("world")
	var poses := ["idle", "strike", "cast"]
	for i in 3:
		for j in 3:
			var at := BWLook.world(Vector2i(-5 + j * 5, (i - 1) * 2), 0)
			_hex(w2, at)
			_posed(w2, at + Vector3(0, BWLook.TILE_HEIGHT, 0), [20.0, 55.0, -30.0][(i + j) % 3], FISTS[j], poses[i], ["", "fire", "thunder"][i])
	var target := Vector3(0, 0.8, 0.0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(COMBAT_PITCH), 0, 0))
	_cam(vp2, target + basis.z * 17.0, target, COMBAT_FOV)
	rows.append(await _grab(vp2))
	_stack(rows, "weapons_fists.png")


## A rig posed by BWCharacterPose (no BWCharacter: this tool stays free of
## the animation lane), wearing `id`; `accent` tints just the accent surface.
func _posed(w: Node3D, at: Vector3, yaw_deg: float, id: String, pose: String, accent: String) -> BWCharacterRig:
	var r := _figure(w, at, yaw_deg, id, "")
	if r.anim:
		r.anim.stop()
	var poser := BWCharacterPose.new(r.skeleton)
	poser.socket_r = r.socket("weapon_r").transform
	poser.socket_l = r.socket("offhand_l").transform
	var view: BWWeaponView = r.get_meta("weapon")
	poser.set_weapon(view.meta)
	poser.play(pose, 0.0)
	poser.update(0.0)
	if accent != "":
		var col: Color = BWWeaponView.aura_colors(BWLook.element_color(accent))[1]
		for v in [view, view.offhand_view]:
			for mi in v.meshes():
				mi.set_instance_shader_parameter("accent", Color(col, 1.0))
	return r


func _row(imgs: Array) -> Image:
	var wd := 0
	for im in imgs:
		wd += im.get_width()
	var out := Image.create(wd, imgs[0].get_height(), false, imgs[0].get_format())
	var x := 0
	for im in imgs:
		out.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, 0))
		x += im.get_width()
	return out


# --------------------------------------------------------------- helpers

func _viewport(size: Vector2i, env: Environment) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var w := Node3D.new()
	vp.add_child(w)
	vp.set_meta("world", w)
	return vp


func _flat_env(c: Color) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env


func _cam(vp: SubViewport, from: Vector3, to: Vector3, fov: float) -> Camera3D:
	var c := Camera3D.new()
	vp.add_child(c)
	c.look_at_from_position(from, to, Vector3.UP)
	if fov > 0.0:
		c.fov = fov
	c.far = 200.0
	c.make_current()
	return c


func _figure(w: Node3D, at: Vector3, yaw_deg: float, id: String, anim_name: String, t: float = 0.0) -> BWCharacterRig:
	var r := BWCharacterRig.new()
	w.add_child(r)
	r.position = at
	r.rotation.y = deg_to_rad(yaw_deg)
	if anim_name != "":
		r.pose_at(anim_name, t)
	var view := BWWeaponView.create(id)
	if view == null:
		push_error("weapon_preview: no weapon %s" % id)
		return r
	view.attach_to(r)
	r.set_meta("weapon", view)
	return r


func _label(w: Node3D, text: String, at: Vector3, px: float, col: Color = Color.BLACK, pitch: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = px
	l.font_size = 64
	l.modulate = col
	l.outline_size = 0
	l.position = at
	l.rotation.x = deg_to_rad(pitch)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	w.add_child(l)


## A white tile with a black rim and grey walls, like the board's.
func _hex(w: Node3D, at: Vector3) -> void:
	var parts := [
		[1.0, BWLook.TILE_HEIGHT, BWLook.SIDE, BWLook.TILE_HEIGHT / 2.0],
		[0.98, 0.012, BWLook.INK, BWLook.TILE_HEIGHT + 0.004],
		[0.98 - BWLook.BORDER, 0.016, BWLook.WHITE, BWLook.TILE_HEIGHT + 0.006],
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
		mi.position = at + Vector3(0, p[3], 0)
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", p[2])
		w.add_child(mi)


func _grab(vp: SubViewport) -> Image:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _save(vp: SubViewport, file: String) -> void:
	var img := await _grab(vp)
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path)


func _stack(imgs: Array, file: String) -> void:
	var wd: int = imgs[0].get_width()
	var ht := 0
	for im in imgs:
		ht += im.get_height()
	var out := Image.create(wd, ht, false, imgs[0].get_format())
	var y := 0
	for im in imgs:
		out.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(0, y))
		y += im.get_height()
	var path := out_dir.path_join(file)
	out.save_png(path)
	print("saved ", path)

extends SceneTree
## D219-D222 review sheets (needs a window): the special encounters' motion
## on the real unit views (scale, tint, runtime layers), stepped by hand at
## 60 Hz so every sheet is reproducible.
##   godot --path . --resolution 1600x900 --script res://tools/anim2_shots.gd [-- --only <name>] [--out <dir>]
## names: colossus_walk, colossus_thrust, being, horde, blank, jab (default: all)
## -> design/art/anim2_<name>.png. Each sheet: rows of cells, time under each.
## The skill clips' strips come from anim_preview.gd (--only strip).

const DT := 1.0 / 60.0
const HEX := BWAnimClips.HEX_STEP

var out_dir := ""
var only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = _arg(args, "--out", ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path())
	only = _arg(args, "--only", "")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _arg(args: PackedStringArray, k: String, d: String) -> String:
	var i := args.find(k)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else d


func _run() -> void:
	for n in ["colossus_walk", "colossus_thrust", "being", "horde", "blank", "jab"]:
		if only == "" or only == n:
			await call("_" + n)
	quit(0)


# ------------------------------------------------------------------ staging

func _unit(id: String, model: String, enc: String, element: String = "", size: int = 1) -> BWUnit:
	var wc := str(BWData.row("equipment", model).get("weight", model))
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "weapon_model": model, "element": element,
		"friendliness": "unfriendly", "con": 5, "str": 5, "dex": 5, "wil": 5, "def": 5, "res": 5, "spd": 5 })
	u.encounter = enc
	u.size = size
	match enc:
		"grunt": u.cosmetics = { "hair_style": "buzzed", "top": "tshirt", "bottom": "sweatpants", "clothing_shade": "mid", "voice_pitch": 0.9 }
		"colossus": u.cosmetics = { "hair_style": "short_mohawk", "top": "tank_top", "bottom": "tight_pants", "clothing_shade": "dark", "voice_pitch": 0.7 }
		"blank": u.cosmetics = { "hair_style": "none", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light", "voice_pitch": 1.0 }
		"being": u.cosmetics = { "hair_style": "buzzed", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light", "voice_pitch": 1.1 }
	u.team = "enemy"
	return u


func _view(parent: Node, u: BWUnit, at: Vector3) -> BWUnitView:
	var v := BWUnitView.new()
	parent.add_child(v)
	v.setup(u)
	v.position = at
	v.show_label(false)
	if v.get("_hp_bar"):
		v._hp_bar.visible = false
	v.set_process(false)
	if v.character:
		v.character.set_process(false)
	return v


func _step(vs: Array, n: int = 1) -> void:
	for i in n:
		for v in vs:
			if is_instance_valid(v) and v.character:
				v.character._process(DT)


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


## A hex floor of radius r around the origin (pointy-top odd-r spacing).
func _floor(parent: Node, r: int, z0: int = 0, z1: int = 0) -> void:
	for q in range(-r, r + 1):
		for k in range(-r + z0, r + 1 + z1):
			var x := q * HEX + (HEX * 0.5 if posmod(k, 2) == 1 else 0.0)
			_tile(parent, Vector3(x, 0, k * HEX * 0.866))


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.6, 0.6)
	we.environment = e
	vp.add_child(we)
	return vp


func _cam(vp: SubViewport, fov: float = 32.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 200.0
	vp.add_child(cam)
	cam.make_current()
	return cam


## Look at `focus` from a yaw / pitch (degrees) at a distance.
func _aim(cam: Camera3D, focus: Vector3, yaw: float, pitch: float, dist: float) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
	cam.global_transform = Transform3D(b, focus + b.z * dist)


func _grab(vp: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


## Compose rows of [image, label] cells into one PNG with a title.
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
	vp.add_child(_label(title, Vector2(8, y), 18, Color.BLACK))
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


## Walk `v` along +z by `hexes` on its move plan (as BWCombatScreen does),
## calling grab(t) every `every` ticks. Returns the time it took.
func _walk(v: BWUnitView, others: Array, hexes: int, every: int, grab: Callable, dir := Vector3(0, 0, 1)) -> float:
	var plan := v.plan_move(hexes * HEX, hexes)
	var s_of: Callable = plan.s
	var dur := float(plan.dur)
	var stop_at := float(plan.get("stop_at", -1.0))
	var home := v.position
	v.face(home + dir * 5.0)
	v.begin_move(plan)
	var t := 0.0
	var i := 0
	var stopped := false
	while t < dur:
		t += DT
		if stop_at >= 0.0 and t >= stop_at and not stopped:
			stopped = true
			v.pose_named("run_stop")
		v.position = home + dir * float(s_of.call(minf(t, dur)))
		_step([v] + others)
		i += 1
		if i % every == 0:
			await grab.call(t)
	return dur


# ------------------------------------------------------------------ sheets

## The Colossus walks 3 hexes and stomps: side and 3/4 rows.
func _colossus_walk() -> void:
	var vp := _viewport(Vector2i(300, 340))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 4, -1, 6)
	var c := _view(stage, _unit("colossus", "lance", "colossus", "", 2), Vector3.ZERO)
	var cam := _cam(vp)
	_step([c], 40)
	var side: Array = []
	var tq: Array = []
	var grab := func(t: float) -> void:
		var f := c.global_position + Vector3(0, 2.6, 0)
		_aim(cam, f, -90.0, 6.0, 17.0)
		side.append([await _grab(vp), "%.2fs %s" % [t, c.character.animator.top_clip()]])
		_aim(cam, f, -40.0, 18.0, 19.0)
		tq.append([await _grab(vp), "%.2fs" % t])
	var t0 := await _walk(c, [], 3, 8, grab)
	c.pose_named("stomp")
	var t := t0
	for i in 15:
		_step([c], 6)
		t += 6 * DT
		await grab.call(t)
	await _compose(out_dir.path_join("anim2_colossus_walk.png"),
		"Colossus: walk_colossus (3 hexes, a step every 0.67 s, the body drops on each plant; markers step / step_r shake the camera) then stomp_colossus",
		[{ "name": "side (every 0.133 s)", "cells": side }, { "name": "3/4", "cells": tq }], 12)
	vp.queue_free()


## The Colossus's line thrust at three grunts on its line.
func _colossus_thrust() -> void:
	var vp := _viewport(Vector2i(300, 300))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 3, -1, 6)
	var c := _view(stage, _unit("colossus", "lance", "colossus", "", 2), Vector3.ZERO)
	c.face(Vector3(0, 0, 10))
	var foes: Array = []
	for k in 3:
		var g := _view(stage, _unit("g%d" % k, "sword", "grunt"), Vector3(0, 0, (2 + k) * HEX))
		g.face(Vector3.ZERO)
		foes.append(g)
	var cam := _cam(vp)
	_step([c] + foes, 40)
	var side: Array = []
	var tq: Array = []
	var t := [0.0]
	var reacted := [false]
	var grab := func() -> void:
		_aim(cam, Vector3(0, 2.4, 2.6), -90.0, 4.0, 30.0)
		side.append([await _grab(vp), "%.2fs" % t[0]])
		_aim(cam, Vector3(0, 2.2, 3.2), -35.0, 18.0, 30.0)
		tq.append([await _grab(vp), "%.2fs" % t[0]])
	c.pose_named("windup")
	var hold: float = c.time_to_marker("coil") + 0.5
	var k := 0
	while t[0] < hold:
		_step([c] + foes)
		t[0] += DT
		k += 1
		if k % 5 == 0:
			await grab.call()
	c.pose_named("strike")
	var hit_at: float = float(t[0]) + c.time_to_marker("hit")
	var end: float = float(t[0]) + 2.0
	while t[0] < end:
		if not reacted[0] and float(t[0]) >= hit_at - (foes[0] as BWUnitView).lead_to_impact("stricken_knockback"):
			reacted[0] = true
			for g in foes:
				g.pose_named("stricken_knockback")
		_step([c] + foes)
		t[0] += DT
		k += 1
		if k % 5 == 0:
			await grab.call()
	await _compose(out_dir.path_join("anim2_colossus_thrust.png"),
		"Colossus: strike_colossus (coil held 0.5 s as the windup holds it, the lunge, hit f31 through all three on the line, the held follow-through)",
		[{ "name": "side (every 0.083 s = 2 authoring frames)", "cells": side }, { "name": "3/4", "cells": tq }], 13)
	vp.queue_free()


## Three Elemental Beings hovering (fire, water, thunder), then one glides.
func _being() -> void:
	var vp := _viewport(Vector2i(420, 300))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 3, -1, 4)
	var bs: Array = []
	var els := ["fire", "water", "thunder"]
	var models := ["sword", "staff", "dagger"]
	for i in 3:
		var b := _view(stage, _unit("being%d" % i, models[i], "being", els[i]), Vector3((i - 1) * HEX, 0, 0))
		b.face(Vector3((i - 1) * HEX, 0, 10))
		bs.append(b)
	var cam := _cam(vp)
	_step(bs, 30)
	var idle: Array = []
	var t := 0.0
	for i in 16:
		_step(bs, 15)
		t += 15 * DT
		_aim(cam, Vector3(0, 1.1, 0), -20.0, 12.0, 13.0)
		idle.append([await _grab(vp), "%.2fs" % t])
	var glide: Array = []
	var g: BWUnitView = bs[1]
	var grab := func(tt: float) -> void:
		_aim(cam, g.global_position + Vector3(0, 1.1, 0), -80.0, 8.0, 11.0)
		glide.append([await _grab(vp), "%.2fs" % tt])
	await _walk(g, [bs[0], bs[2]], 2, 6, grab)
	for i in 4:
		_step(bs, 6)
		await grab.call(-1.0)
	# the cast attack
	var cast: Array = []
	g.face(g.position + Vector3(0, 0, -5))
	g.pose_named("cast")
	for i in 12:
		_step(bs, 4)
		_aim(cam, g.global_position + Vector3(0, 1.1, 0), -100.0, 8.0, 11.0)
		cast.append([await _grab(vp), "cast f%d" % int(round((i + 1) * 4 * DT * 24.0))])
	await _compose(out_dir.path_join("anim2_being.png"),
		"Elemental Beings: hover 17 cm (+-2.5 cm sine, toes hanging, no contacts), the element flicker (two slow waves + a rare dip), a glide, the cast attack",
		[{ "name": "idle, every 0.25 s (fire / water / thunder)", "cells": idle }, { "name": "glide 2 hexes (side)", "cells": glide },
		{ "name": "cast (its basic attack)", "cells": cast }], 8)
	vp.queue_free()


## Ten grunts shuffle forward 2 hexes at once: out of step, each its pace.
func _horde() -> void:
	var vp := _viewport(Vector2i(520, 340))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 5, -2, 6)
	var gs: Array = []
	var models := ["sword", "hatchet", "axe", "lance"]
	for i in 10:
		var col := i % 5
		var row := i / 5
		var at := Vector3((col - 2) * HEX + (HEX * 0.5 if row == 1 else 0.0), 0, -row * HEX * 0.866)
		gs.append(_view(stage, _unit("grunt%d" % (i + 1), models[i % 4], "grunt"), at))
	var cam := _cam(vp, 34.0)
	_step(gs, 30)
	# everyone moves at once (the sheet's test of lockstep): each on its own plan
	var plans: Array = []
	var homes: Array = []
	for v in gs:
		var p: Dictionary = v.plan_move(2 * HEX, 2)
		plans.append(p)
		homes.append(v.position)
		v.face(v.position + Vector3(0, 0, 5))
		v.begin_move(p)
	var cells: Array = []
	var side: Array = []
	var t := 0.0
	var k := 0
	var longest := 0.0
	for p in plans:
		longest = maxf(longest, float(p.dur))
	var stopped := {}
	while t < longest + 0.4:
		t += DT
		for i in gs.size():
			var p: Dictionary = plans[i]
			var v: BWUnitView = gs[i]
			if float(p.stop_at) >= 0.0 and t >= float(p.stop_at) and not stopped.has(i):
				stopped[i] = true
				v.pose_named("run_stop")
			v.position = (homes[i] as Vector3) + Vector3(0, 0, float((p.s as Callable).call(minf(t, float(p.dur)))))
		_step(gs)
		k += 1
		if k % 9 == 0:
			_aim(cam, Vector3(0, 1.0, 1.4), -25.0, 22.0, 14.0)
			cells.append([await _grab(vp), "%.2fs" % t])
			_aim(cam, Vector3(0, 1.0, 1.4), -90.0, 5.0, 13.0)
			side.append([await _grab(vp), "%.2fs" % t])
	var paces: PackedStringArray = []
	for p in plans:
		paces.append("%.2f" % float(p.dur))
	await _compose(out_dir.path_join("anim2_horde.png"),
		"Horde: ten grunts start the same 2-hex move together: hunched, low shuffling feet, each its own pace (move times %s s)" % ", ".join(paces),
		[{ "name": "3/4, every 0.15 s", "cells": cells }, { "name": "side", "cells": side }], 9)
	vp.queue_free()


## A Blank beside a normal character: both walk 2 hexes, then stand.
func _blank() -> void:
	var vp := _viewport(Vector2i(360, 320))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 3, -1, 5)
	var b := _view(stage, _unit("blank1", "sword", "blank"), Vector3(-HEX * 0.5, 0, 0))
	var n := _view(stage, BWRosterKits.unit("stryker"), Vector3(HEX * 0.5, 0, 0))
	n.show_label(false)
	n.set_process(false)
	n.character.set_process(false)
	n.character.animator.rotate_idles = false
	if n.get("_hp_bar"):
		n._hp_bar.visible = false
	var cam := _cam(vp)
	_step([b, n], 30)
	var walk: Array = []
	var pb: Dictionary = b.plan_move(2 * HEX, 1)        # both walk (1-hex plan: the walk gait for the normal one too)
	var pn: Dictionary = n.plan_move(2 * HEX, 1)
	var hb := b.position
	var hn := n.position
	b.face(hb + Vector3(0, 0, 5))
	n.face(hn + Vector3(0, 0, 5))
	b.begin_move(pb)
	n.begin_move(pn)
	var t := 0.0
	var k := 0
	var dur := maxf(float(pb.dur), float(pn.dur))
	while t < dur + 0.3:
		t += DT
		b.position = hb + Vector3(0, 0, float((pb.s as Callable).call(minf(t, float(pb.dur)))))
		n.position = hn + Vector3(0, 0, float((pn.s as Callable).call(minf(t, float(pn.dur)))))
		if t >= float(pb.dur) and b.character.animator.current != "idle":
			b.idle()
		if t >= float(pn.dur) and n.character.animator.current != "idle":
			n.idle()
		_step([b, n])
		k += 1
		if k % 6 == 0:
			_aim(cam, (b.position + n.position) * 0.5 + Vector3(0, 1.1, 0), -58.0, 8.0, 11.0)
			walk.append([await _grab(vp), "%.2fs" % t])
	# standing: the Blank's shared head clock (real time), the other's idle
	var stand: Array = []
	var t0 := Time.get_ticks_msec()
	for i in 16:
		var until := t0 + int((i + 1) * 400.0)
		while Time.get_ticks_msec() < until:
			_step([b, n])
			await process_frame
		_aim(cam, (b.position + n.position) * 0.5 + Vector3(0, 1.2, 0), -30.0, 14.0, 8.0)
		stand.append([await _grab(vp), "%.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0)])
	await _compose(out_dir.path_join("anim2_blank.png"),
		"Blank (left, white) beside Stryker (right): the Blank's walk moves only the legs (torso, head, hands locked level, no bob); standing it holds the guard dead still and snaps its head on a shared clock",
		[{ "name": "walk 2 hexes, side, every 0.1 s", "cells": walk }, { "name": "standing, every 0.4 s", "cells": stand }], 10)
	vp.queue_free()


## The Horde's jab against the class strike (one: sword).
func _jab() -> void:
	var vp := _viewport(Vector2i(260, 300))
	var stage := Node3D.new()
	vp.add_child(stage)
	_floor(stage, 2, -1, 3)
	var g := _view(stage, _unit("grunt1", "sword", "grunt"), Vector3.ZERO)
	var n := _view(stage, BWRosterKits.unit("stryker"), Vector3(HEX * 1.2, 0, 0))
	n.show_label(false)
	n.set_process(false)
	n.character.set_process(false)
	n.character.animator.rotate_idles = false
	if n.get("_hp_bar"):
		n._hp_bar.visible = false
	g.face(Vector3(0, 0, 5))
	n.face(Vector3(HEX * 1.2, 0, 5))
	var cam := _cam(vp)
	_step([g, n], 30)
	g.pose_named("strike")
	n.pose_named("strike")
	var cells: Array = []
	var t := 0.0
	for i in 13:
		_step([g, n], 5)
		t += 5 * DT
		_aim(cam, Vector3(HEX * 0.6, 1.0, 0.4), -35.0, 8.0, 10.0)
		cells.append([await _grab(vp), "%.2fs  %s" % [t, g.character.animator.top_clip()]])
	await _compose(out_dir.path_join("anim2_jab.png"),
		"Horde jab (left, strike_jab 22 f, hit 0.27 s) vs the class strike (right, Stryker, 36 f, hit 0.5 s); every 0.083 s",
		[{ "name": "side", "cells": cells }], 11)
	vp.queue_free()

extends SceneTree
## D365-D370 review renders of wind shaping on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=ley,rain,single] godot --path . --resolution 1920x1080 --script res://tools/wind_shape_shots.gd
## → design/art/wind2_ley_left.png / wind2_ley_right.png (a wind Ley Line, the mouse
##   on either side of the line: Part left / Part right, one foe parted into fire),
##   wind2_ley_blast.png (Tab: Blast out), wind2_rain_draw.png / wind2_rain_burst.png
##   (a wind Rain of Arrows: Draw in vs Burst out, a slam), wind2_single_push.png /
##   wind2_single_hold.png (a wind Bolt pushed along the mouse's heading onto ice; Hold).
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p, "  shaping ", s.wind_shape.shown)


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _row(roster: Array, wc: String, el: String, skip: Array) -> Dictionary:
	for r in roster:
		if str(r.get("weapon_class", "")) == wc and not str(r.id) in skip:
			var d: Dictionary = r.duplicate()
			d["element"] = el
			skip.append(str(r.id))
			return d
	var any: Dictionary = roster[skip.size()].duplicate()
	any["weapon_class"] = wc
	any["weapon_model"] = wc
	any["element"] = el
	skip.append(str(any.id))
	return any


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	var roster := BWData.table("roster")
	var used: Array = []
	var stf := BWUnit.from_roster(_row(roster, "staff", "wind", used))
	var bow := BWUnit.from_roster(_row(roster, "bow", "wind", used))
	var axe := BWUnit.from_roster(_row(roster, "axe", "fire", used))
	var enemies: Array = []
	for wc in ["sword", "lance", "axe", "daggers"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in [stf, bow, axe] + enemies:
		u.stats["con"] = 40
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [stf, bow, axe], enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	for pair in [[stf, "ley_line"], [stf, "bolt"], [bow, "rain_of_arrows"]]:
		var u: BWUnit = pair[0]
		if not pair[1] in u.known_skills:
			u.known_skills.append(pair[1])
		u.overcap.append(pair[1])
	var f := _flat_centre(b)
	var park := _open(b, f, 300)
	# everyone off stage first, far from the focus
	var far_spots: Array = park.slice(park.size() - 8)
	for i in ([stf, bow, axe] + enemies).size():
		_place(([stf, bow, axe] + enemies)[i], far_spots[i])
	s.rig.pitch = deg_to_rad(58.0)

	if _want("ley"):
		var d := _best_dir(b, f, 4)
		var line: Array = []
		for i in range(1, 5):
			line.append(_step(f, d, i))
		_place(stf, f)
		_place(enemies[0], line[1])                  # on the line
		_place(enemies[1], line[2])                  # on the line
		var fwd := BWWindShape.forward(f, line[0])
		var left_d := BWWindShape.side_dir(fwd, 1)
		var right_d := BWWindShape.side_dir(fwd, -1)
		_place(enemies[2], BWHex.neighbors(line[3])[right_d])   # beside it (Blast out)
		b.paint([BWHex.neighbors(line[2])[left_d]], "fire", axe, 2)   # parting left drops one in fire
		_glaze(b, BWHex.neighbors(line[1])[right_d])                  # parting right slides one on ice
		_glaze(b, BWHex.neighbors(BWHex.neighbors(line[1])[right_d])[right_d])
		await _settle()
		_turn(stf)
		BWWindShape.set_choice(stf, "ley_line", "blast")
		s._skill = { "key": "ley_line", "element": "wind", "row": BWSkills.get_skill("ley_line") }
		s._aim_skill(stf, line[0])
		_look(f, line[3], 13.0)
		await _wait(0.8)
		_mouse_side(1)
		await _wait(1.0)
		print("ley left: ", BWWindShape.choice(stf, "ley_line"))
		await _shot("wind2_ley_left")
		_mouse_side(-1)
		await _wait(1.0)
		print("ley right: ", BWWindShape.choice(stf, "ley_line"))
		await _shot("wind2_ley_right")
		s.wind_shape.key(KEY_TAB)
		await _wait(1.0)
		print("ley tab: ", BWWindShape.choice(stf, "ley_line"))
		await _shot("wind2_ley_blast")
		s._on_action("cancel")
		s._on_action("cancel")
		await _wait(0.3)
		for e in enemies:
			_place(e, far_spots[3 + enemies.find(e)])
		_place(stf, far_spots[0])
		b.tiles.entries.clear()
		await _settle()

	if _want("rain"):
		var c := f
		_place(bow, _step(c, 3, 4))
		var ring1: Array = Array(BWHex.ring(c, 1))
		var ring2: Array = Array(BWHex.ring(c, 2))
		_place(enemies[0], ring1[0])                # in the area
		_place(enemies[1], ring1[1])                # in the area; a foe behind it: a slam on Burst out
		_place(enemies[3], BWHex.neighbors(ring1[1])[BWBattle.pulse_heading(c, ring1[1], true)])
		_place(enemies[2], ring2[7])                # beside the area: Draw in pulls it in
		await _settle()
		_turn(bow)
		bow.wind_shapes.erase("rain_of_arrows")      # D383: unset, so the frame shows the default (Draw in)
		s._skill = { "key": "rain_of_arrows", "element": "wind", "row": BWSkills.get_skill("rain_of_arrows") }
		s._aim_skill(bow, c)
		_look(c, c, 19.0)
		await _wait(1.0)
		print("rain: ", BWWindShape.choice(bow, "rain_of_arrows"), " moves ", s.readability.preview.last.get("moves", []))
		await _shot("wind2_rain_draw")
		s.wind_shape.key(KEY_TAB)
		await _wait(1.0)
		print("rain tab: ", BWWindShape.choice(bow, "rain_of_arrows"))
		await _shot("wind2_rain_burst")
		s._on_action("cancel")
		s._on_action("cancel")
		await _wait(0.3)
		for e in enemies:
			_place(e, far_spots[3 + enemies.find(e)])
		_place(bow, far_spots[1])
		await _settle()

	if _want("single"):
		_place(stf, f)
		var at := _step(f, 0, 2)
		_place(enemies[0], at)
		var d2 := BWWindShape.push_dir(f, at, 1)
		_glaze(b, BWHex.neighbors(at)[d2])
		_glaze(b, BWHex.neighbors(BWHex.neighbors(at)[d2])[d2])
		_place(enemies[1], BWHex.neighbors(BWHex.neighbors(BWHex.neighbors(at)[d2])[d2])[d2])   # it slides into this one: a slam
		await _settle()
		_turn(stf)
		BWWindShape.set_choice(stf, "bolt", "push", 0)
		s._skill = { "key": "bolt", "element": "wind", "row": BWSkills.get_skill("bolt") }
		s._aim_skill(stf, at)
		_look(f, BWHex.neighbors(at)[d2], 12.0)
		await _wait(0.8)
		var cam := root.get_viewport().get_camera_3d()
		var tp := cam.unproject_position(s.board_view.top_center(at))
		var np := cam.unproject_position(s.board_view.top_center(BWHex.neighbors(at)[d2]))
		s.wind_shape.hover(tp + (np - tp).normalized() * 120.0)
		await _wait(1.0)
		print("single: ", BWWindShape.choice(stf, "bolt"))
		await _shot("wind2_single_push")
		s.wind_shape.key(KEY_TAB)
		await _wait(1.0)
		await _shot("wind2_single_hold")
		s._on_action("cancel")
		s._on_action("cancel")
	await _wait(0.3)
	quit(0)


## The screen point on `side` of the aimed line (+1 the caster's left), as a mouse would hover.
func _mouse_side(side: int) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var ctx := s.wind_shape.ctx
	var fwd := BWWindShape.forward(ctx.from, ctx.hex)
	var l := BWWindShape.left_of(fwd) * float(side)
	var mid := s.board_view.top_center(ctx.from) + Vector3(fwd.x, 0, fwd.y) * 2.5 + Vector3(l.x, 0, l.y) * 1.6
	s.wind_shape.hover(cam.unproject_position(mid))


func _look(a: Vector2i, c: Vector2i, dist: float) -> void:
	var b := s.battle
	var mid := (BWLook.world(a, b.board.elevation(a)) + BWLook.world(c, b.board.elevation(c))) * 0.5
	s.rig.dist = dist
	var cam := root.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam else Vector3.ZERO
	right.y = 0.0
	s.rig.follow(mid + right.normalized() * dist * 0.16, true)   # the confirm box sits on the right


func _glaze(b: BWBattle, h: Vector2i) -> void:
	var e := b.tiles._entry(-1, 0, "", "", "cast")
	e.glaze = 2
	b.tiles.entries[h] = e


func _step(h: Vector2i, d: int, n: int) -> Vector2i:
	var c := h
	for i in n:
		c = BWHex.neighbors(c)[d]
	return c


## A heading from `c` with `n` open hexes and open ground on both sides.
func _best_dir(b: BWBattle, c: Vector2i, n: int) -> int:
	for d in [0, 5, 1, 2, 3, 4]:
		var ok := true
		for i in range(1, n + 1):
			var h := _step(c, d, i)
			for x in [h] + Array(BWHex.neighbors(h)):
				if not b.board.is_passable(x) or b.board.blocked(x) or absi(b.board.elevation(x) - b.board.elevation(c)) > 0:
					ok = false
		if ok:
			return d
	return 0


func _idle() -> void:
	var t := 0.0
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and t < 60.0:
		await _wait(0.2)
		t += 0.2


func _settle() -> void:
	s.board_view.refresh_tiles()
	await _wait(0.3)


func _turn(u: BWUnit) -> void:
	var b := s.battle
	b.queue = [u] + b.queue.filter(func(x): return x != u)
	b.turn_index = 0
	b._begin_turn()
	s._queue.clear()
	s._skill = {}
	u.acted = false
	u.moved = false
	u.cooldowns.clear()
	s.ui.set_acting(u, b.tiles)
	s._show_options()


func _place(u: BWUnit, h: Vector2i) -> void:
	if h == Vector2i(-1, -1):
		return
	u.pos = h
	var v: Node3D = s._views[u.id]
	v.position = s._unit_pos(h)


func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 3):
			if b.board.is_passable(a) and b.board.elevation(a) == b.board.elevation(h):
				k += 1
		k = k * 100 - BWHex.distance(h, b.board.camera_focus)
		if k > best_k:
			best_k = k
			best = h
	return best


func _open(b: BWBattle, c: Vector2i, n: int) -> Array:
	var out_h: Array = []
	for r in 12:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out_h.size() >= n:
				return out_h
			if b.board.is_passable(h) and not b.board.blocked(h) and b.unit_at(h) == null:
				out_h.append(h)
	return out_h

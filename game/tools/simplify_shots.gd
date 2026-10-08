extends SceneTree
## D405-D409 review renders on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=fuse,gale,push] godot --path . --resolution 1920x1080 --script res://tools/simplify_shots.gd
## → design/art/simplify_fuse_ice.png  (an ice Surge aimed at a thunder fuse: the blast
##     preview's IGNITES FUSE tag, the confirm box's "Ignites the fuse" line),
##   simplify_fuse_wind.png (the same with wind),
##   simplify_gale.png (a gale and a gale 2 on bare ground, one fired over fire: the one
##     swirl look, no arrows or rings; the tile card on the gale),
##   simplify_push.png (a wind staff's basic attack forecast: the "Gust" note and the
##     preview's push arrow), simplify_push_after.png (the foe one hex back).
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
	print("shot ", p)


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
	var stf := BWUnit.from_roster(_row(roster, "staff", "ice", used))
	var wst := BWUnit.from_roster(_row(roster, "staff", "wind", used))
	var axe := BWUnit.from_roster(_row(roster, "axe", "thunder", used))
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in [stf, wst, axe] + enemies:
		u.stats["con"] = 40
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [stf, wst, axe], enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	for u in [stf, wst]:
		if not "surge" in u.known_skills:
			u.known_skills.append("surge")
		u.overcap.append("surge")
	var f := _flat_centre(b)
	var park := _open(b, f, 300)
	var far_spots: Array = park.slice(park.size() - 8)
	var all: Array = [stf, wst, axe] + enemies
	for i in all.size():
		_place(all[i], far_spots[i])
	s.rig.pitch = deg_to_rad(58.0)

	if _want("fuse"):
		var x := _step(f, 0, 2)
		for pair in [[stf, "ice", "simplify_fuse_ice"], [wst, "wind", "simplify_fuse_wind"]]:
			var u: BWUnit = pair[0]
			b.tiles.entries.clear()
			b.tiles.apply([x], "thunder", axe.id)          # the fuse
			_place(u, f)
			_place(enemies[0], BWHex.neighbors(x)[0])     # beside it: the splash
			_place(enemies[1], BWHex.neighbors(x)[5])
			if pair[1] == "wind":
				BWWindShape.set_choice(u, "surge", "hold")  # nobody moved: the frame is about the fuse
			await _settle()
			_turn(u)
			s._skill = { "key": "surge", "element": pair[1], "row": BWSkills.get_skill("surge") }
			s._aim_skill(u, x)
			_look(f, x, 12.0)
			await _wait(1.2)
			print(pair[1], " preview: ", s.readability.preview.last.get("detonations", []))
			await _shot(pair[2])
			s._on_action("cancel")
			s._on_action("cancel")
			await _wait(0.3)
			for e in enemies:
				_place(e, far_spots[3 + enemies.find(e)])
			_place(u, far_spots[all.find(u)])
		b.tiles.entries.clear()
		await _settle()

	if _want("gale"):
		var g1 := _step(f, 0, 1)
		var g2 := _step(f, 3, 2)
		var g3 := _step(f, 1, 3)
		b.paint([g1], "wind", wst)                        # a gale
		b.paint([g2], "wind", wst)
		b.paint([g2], "wind", wst)                        # a gale 2
		b.paint([_step(g3, 0, 0)], "fire", wst)
		b.paint([g3], "wind", wst)                        # wind on fire: the gale fires, fire copied round it
		await _settle()
		_turn(stf)
		s._show_options()
		_look(g2, g3, 13.0)
		s._hover = g1
		await _wait(1.5)
		print("gale card: ", s.readability.card_text())
		await _shot("simplify_gale")
		s._hover = Vector2i(-99, -99)
		b.tiles.entries.clear()
		await _settle()

	if _want("push"):
		wst.attuned = "wind"
		_place(wst, f)
		var at := _step(f, 0, 1)
		_place(enemies[0], at)
		await _settle()
		_turn(wst)
		s._on_click(at)
		_look(f, _step(at, 0, 1), 10.0)
		await _wait(1.2)
		print("push preview moves: ", s.readability.preview.last.get("moves", []))
		await _shot("simplify_push")
		b.expected_rolls = true                          # a sure, unresisted blow for the frame
		s._on_action("confirm")
		var t := 0.0
		while s._busy and t < 20.0:
			await _wait(0.2)
			t += 0.2
		await _wait(0.6)
		print("push: ", at, " -> ", enemies[0].pos)
		await _shot("simplify_push_after")
	await _wait(0.3)
	quit(0)


func _look(a: Vector2i, c: Vector2i, dist: float) -> void:
	var b := s.battle
	var mid := (BWLook.world(a, b.board.elevation(a)) + BWLook.world(c, b.board.elevation(c))) * 0.5
	s.rig.dist = dist
	var cam := root.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam else Vector3.ZERO
	right.y = 0.0
	s.rig.follow(mid + right.normalized() * dist * 0.16, true)


func _step(h: Vector2i, d: int, n: int) -> Vector2i:
	var c := h
	for i in n:
		c = BWHex.neighbors(c)[d]
	return c


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

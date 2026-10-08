extends SceneTree
## Review renders for the systems pass (D418 Inversion, D424 Pressured), from
## the real combat screen with real mouse motion (needs a window):
##   RES=1920x1080 [SHOTS=<dir>] godot --path . --script res://tools/sys5_shots.gd
## sys5_inversion_preview.png  Kira aims Inversion: the radius-2 area rimmed,
##                             each charged tile hatched in its new colour
##                             with its swap tag ("FIRE 3 → WATER 3")
## sys5_inversion_cast.png     clicked (a no-damage ground skill casts on the click): mid-playback
## sys5_inversion_after.png    after it resolves: the flipped field
## sys5_pressured.png          Gail (bow) aims at a far foe with Rui 2 away:
##                             the confirm box's "Pressured" line
var out := ""
var s: BWCombatScreen
var kira: BWUnit
var gail: BWUnit
var stryker: BWUnit
var rui: BWUnit
var demeter: BWUnit
var bob: BWUnit
var T := Vector2i(-1, -1)


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _unit(id: String, keys: Array = []) -> BWUnit:
	var u := BWRosterKits.unit(id)
	for k in keys:
		u.known_skills.append(k)
	if not keys.is_empty():
		u.skill_loadout[u.weapon_class] = keys + BWSkillRegistry.starter(u.weapon_class).slice(0, 1)
	return u


func _go() -> void:
	var wres := OS.get_environment("RES")
	if wres.contains("x"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3:
			await process_frame
		DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
		for i in 3:
			await process_frame
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "default")
	kira = _unit("kira", ["inversion"])
	gail = _unit("gail")
	stryker = _unit("stryker")
	rui = _unit("rui")
	demeter = _unit("demeter")
	bob = _unit("bob")
	for u in [kira, gail, stryker]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [kira, gail, stryker], [rui, demeter, bob], [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	await _inversion()
	await _pressured()
	quit()


func _turn(u: BWUnit) -> void:
	s.ui.hide_forecast()
	s._skill = {}
	s._pending_skill = {}
	s._pending_target = null
	s.battle.queue = [u]
	s.battle.turn_index = 0
	u.acted = false
	u.moved = false
	u.follow_up = []
	u.cooldowns.clear()
	s.battle._begin_turn()
	s._queue.clear()
	s.ui.set_acting(u, s.battle.tiles)
	s._show_options()
	s.ui.set_actions_visible(true)
	await _wait(0.4)


func _place(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s.board_view.top_center(h)


func _cells() -> Array:
	var b := s.battle
	var cells: Array = []
	for h in b.board.cells():
		if b.board.is_passable(h) and b.tiles.can_hold(h):
			cells.append(h)
	return cells


func _move_mouse(h: Vector2i) -> void:
	var vp_pos := s.cam.unproject_position(s.board_view.top_center(h))
	var p := root.get_final_transform() * vp_pos
	for k in 2:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await process_frame


func _click(h: Vector2i) -> void:
	await _move_mouse(h)
	var vp_pos := s.cam.unproject_position(s.board_view.top_center(h))
	var p := root.get_final_transform() * vp_pos
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		Input.parse_input_event(mb)
		await process_frame


func _look(at: Vector2i, from: Vector2i, dist: float) -> void:
	var mid := (s.board_view.top_center(at) * 2.0 + s.board_view.top_center(from)) / 3.0
	s.rig.follow(mid, true)
	var axis := s.board_view.top_center(at) - s.board_view.top_center(from)
	var side := Vector3(-axis.z, 0, axis.x)
	s.rig.yaw = atan2(side.x, side.z) + deg_to_rad(-20.0)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(55.0)
	await _wait(0.6)


## A mixed field around T (fire 3, water 1, dark 2, light 1, a fuse, a gale,
## glaze); Stryker (an ally) stands on the enemy's fire, Rui on Kira's dark.
func _inversion() -> void:
	var b := s.battle
	var cells := _cells()
	for h in cells:
		var area: Array = Array(BWHex.area(h, 2)).filter(func(n): return n in cells)
		if area.size() < 15:
			continue
		for k in cells:
			if BWHex.distance(k, h) in [3, 4] and b.board.has_los(k, h) and b.board.elevation(k) <= 1:
				T = h
				_place(kira, k)
				break
		if T.x >= 0:
			break
	b.tiles.entries.clear()
	var ring1: Array = BWHex.ring(T, 1)
	var ring2: Array = BWHex.ring(T, 2)
	ring2.sort_custom(func(a, c): return BWHex.distance(a, kira.pos) > BWHex.distance(c, kira.pos))
	b.tiles.apply([T, ring1[0], ring1[1]], "fire", "rui", 3)
	b.tiles.apply([ring1[3]], "water", "map", 1)
	b.tiles.apply([ring2[0], ring2[1]], "dark", "kira", 2)
	b.tiles.apply([ring1[4]], "light", "map", 1)
	b.tiles.apply([ring2[3]], "thunder", "map")
	b.tiles.apply([ring2[5]], "wind", "map")
	b.tiles.apply([ring2[7]], "water", "map", 2)
	b.tiles.apply([ring2[7]], "ice", "map")
	_place(stryker, ring1[0])
	_place(rui, ring2[0])
	for u in [gail, demeter, bob]:
		for h in cells:
			if b.unit_at(h) == null and BWHex.distance(h, T) >= 5:
				_place(u, h)
				break
	s.board_view.refresh_tiles(true)
	s._face_all()
	print("inversion scene: T ", T, " kira ", kira.pos)
	await _turn(kira)
	await _look(T, kira.pos, 15.0)
	s.ui.skill_chosen.emit("inversion", "")
	await _wait(0.3)
	await _move_mouse(T)
	await _wait(0.8)
	var sim: Dictionary = s.readability.preview.last
	print("inversion preview: ", (sim.get("inversion", {}) as Dictionary).get("swaps", []))
	await _shot("sys5_inversion_preview")
	await _click(T)
	await _wait(0.6)
	pass
	await _shot("sys5_inversion_cast")
	await _click(T)
	await _wait(0.2)
	var t0 := Time.get_ticks_msec()
	while (s._busy or s.ui.forecast_open()) and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await _wait(1.2)
	await _shot("sys5_inversion_after")


## Gail shoots Demeter 4 away while Rui stands 2 from her: Pressured.
func _pressured() -> void:
	var b := s.battle
	b.tiles.entries.clear()
	s.board_view.refresh_tiles(true)
	var cells := _cells()
	var g := Vector2i(-1, -1)
	var far := Vector2i(-1, -1)
	var near := Vector2i(-1, -1)
	for h in cells:
		for k in cells:
			if BWHex.distance(h, k) == 4 and b.board.has_los(h, k):
				for n in cells:
					if BWHex.distance(h, n) == 2 and BWHex.distance(k, n) >= 3:
						g = h
						far = k
						near = n
						break
			if near.x >= 0:
				break
		if near.x >= 0:
			break
	var keep := [g, far, near]
	var used: Array = keep.duplicate()
	for u in [kira, stryker, bob]:
		for h in cells:
			if not h in used and BWHex.distance(h, g) >= 6 and BWHex.distance(h, far) >= 3:
				_place(u, h)
				used.append(h)
				break
	_place(gail, g)
	_place(demeter, far)
	_place(rui, near)
	s._face_all()
	await _turn(gail)
	await _look(far, g, 13.0)
	await _click(far)
	await _wait(0.8)
	var fc: Dictionary = b.forecast_basic(gail, demeter)
	print("pressured forecast notes: ", fc.get("notes", []), " dmg ", fc.damage.value)
	await _shot("sys5_pressured")

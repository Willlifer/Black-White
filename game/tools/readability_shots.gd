extends SceneTree
## Review renders for the readability pass (D160-D163), from the real combat
## screen with real mouse motion (needs a window):
##   RES=1920x1080 [SHOTS=<dir>] godot --path . --script res://tools/readability_shots.gd
## read_preview.png   Kira aims Bolt (thunder) at Rui on glazed water 3 + dark 3:
##                    the hatched blast, its splash ring, Demeter's fuse arc,
##                    the damage tags, Stryker's red friendly-fire tag
## read_confirm.png   the same, clicked: the confirm box with the ground lines
## read_beat.png      the detonation's slow beat (time at 30%, camera leaning in)
## read_recap.png     the recap line by the combat log after the playback
## read_card.png      the tile hover card over the blasted hex's neighbour
## read_card_fire.png the card on a burning hex under a unit (next-turn damage)
var out := ""
var s: BWCombatScreen
var kira: BWUnit
var stryker: BWUnit
var bob: BWUnit
var rui: BWUnit
var demeter: BWUnit
var gail: BWUnit


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
	kira = _unit("kira", ["bolt"])
	kira.affinity["thunder"] = 10
	stryker = _unit("stryker")
	bob = _unit("bob")
	rui = _unit("rui")
	demeter = _unit("demeter")
	gail = _unit("gail")
	for u in [kira, stryker, bob]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [kira, stryker, bob], [rui, demeter, gail], [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	await _scene()
	await _preview()
	await _confirm_and_play()
	await _cards()
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
	s.battle._begin_turn()
	s._queue.clear()
	s.ui.set_acting(u, s.battle.tiles)
	s._show_options()
	s.ui.set_actions_visible(true)
	await _wait(0.4)


func _place(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s.board_view.top_center(h)


var T := Vector2i(-1, -1)


## Kira 3 hexes from Rui's glazed water+dark hex; Demeter beside Rui on a
## fuse (conductive), Stryker beside Rui in the splash; Gail and Bob clear.
func _scene() -> void:
	var b := s.battle
	var cells: Array = []
	for h in b.board.cells():
		if b.board.is_passable(h) and b.tiles.can_hold(h):
			cells.append(h)
	# a target hex with a free, standable ring and a free hex 3 away for Kira
	for h in cells:
		var ring: Array = BWHex.neighbors(h).filter(func(n): return n in cells)
		if ring.size() < 6 or b.board.elevation(h) != 0:
			continue
		var from := Vector2i(-1, -1)
		for k in cells:
			if BWHex.distance(k, h) == 3 and b.board.has_los(k, h) and b.board.elevation(k) <= 1:
				from = k
				break
		if from.x >= 0:
			T = h
			_place(kira, from)
			break
	var ring2: Array = BWHex.neighbors(T)
	ring2.sort_custom(func(a, c): return BWHex.distance(a, kira.pos) > BWHex.distance(c, kira.pos))
	_place(rui, T)
	_place(demeter, ring2[0])                 # behind Rui, on a fuse
	_place(stryker, ring2[2])                 # a flank of Rui: in the splash
	for u in [gail, bob]:
		for h in cells:
			if b.unit_at(h) == null and BWHex.distance(h, T) >= 4 and BWHex.distance(h, kira.pos) >= 2:
				_place(u, h)
				break
	b.tiles.entries.clear()
	b.tiles.apply([T], "water", "map", 3)
	b.tiles.apply([T], "dark", "map", 3)
	b.tiles.apply([T], "ice", "map")
	b.tiles.apply([demeter.pos], "thunder", "map")
	b.tiles.apply([ring2[4]], "fire", "map", 2)
	s.board_view.refresh_tiles(true)
	s._face_all()
	await _turn(kira)
	var mid := (s.board_view.top_center(T) * 2.0 + s.board_view.top_center(kira.pos)) / 3.0
	s.rig.follow(mid, true)
	# look across the arc (T -> Demeter), from Kira's side, so the jump reads
	var axis := s.board_view.top_center(demeter.pos) - s.board_view.top_center(T)
	var side := Vector3(-axis.z, 0, axis.x)
	if side.dot(s.board_view.top_center(kira.pos) - s.board_view.top_center(T)) < 0:
		side = -side
	s.rig.yaw = atan2(side.x, side.z) + deg_to_rad(-20.0)
	s.rig.dist = 15.0
	s.rig.pitch = deg_to_rad(50.0)
	await _wait(0.6)
	print("scene: kira ", kira.pos, " T ", T, " demeter ", demeter.pos, " stryker ", stryker.pos)


func _move_mouse(h: Vector2i) -> void:
	var vp_pos := s.cam.unproject_position(s.board_view.top_center(h))
	var p := root.get_final_transform() * vp_pos
	for k in 2:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await process_frame


func _preview() -> void:
	s.ui.skill_chosen.emit("bolt", "thunder")
	await _wait(0.3)
	await _move_mouse(T)
	await _wait(0.8)
	var sim: Dictionary = s.readability.preview.last
	print("preview: dets ", sim.get("detonations", []), " chains ", sim.get("chains", []).size(),
		" units ", sim.get("units", {}).keys())
	await _shot("read_preview")


func _confirm_and_play() -> void:
	await _move_mouse(T)
	var vp_pos := s.cam.unproject_position(s.board_view.top_center(T))
	var p := root.get_final_transform() * vp_pos
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		Input.parse_input_event(mb)
		await process_frame
	await _wait(0.6)
	print("confirm open: ", s.ui.forecast_open())
	await _shot("read_confirm")
	var beats0 := s.readability.beats
	s._on_action("confirm")
	var shot_beat := false
	var t := 0
	while (s._busy or t < 5) and t < 3000:
		await process_frame
		t += 1
		if not shot_beat and s.readability.beats > beats0 and Engine.time_scale < 0.5:
			await _wait(0.08)
			await _shot("read_beat")
			shot_beat = true
	await _wait(0.5)
	print("recap: ", s.readability.last_recap)
	print("detail: ", s.readability.last_detail)
	await _shot("read_recap")


func _cards() -> void:
	await _wait(3.5)
	var b := s.battle
	if b.over:
		return
	await _turn(kira)
	# hover the fuse hex (or the target if it's gone)
	var h := demeter.pos if demeter.alive() else T
	var free := T
	for n in BWHex.neighbors(T):
		if b.board.is_passable(n) and b.tiles.can_hold(n) and b.unit_at(n) == null and b.tiles.at(n).is_empty():
			free = n
			break
	b.tiles.apply([free], "water", "map", 2)
	b.tiles.apply([free], "dark", "map", 2)
	b.tiles.apply([free], "ice", "map")
	s.board_view.refresh_tiles(true)
	await _move_mouse(kira.pos)
	await _wait(0.3)
	await _move_mouse(free)
	await _wait(0.6)
	print("card: ", s.readability.card_text())
	await _shot("read_card")
	b.tiles.apply([stryker.pos], "fire", "map", 2)
	b.tiles.apply([stryker.pos], "light", "map", 1)
	s.board_view.refresh_tiles(true)
	await _move_mouse(h)
	await _wait(0.2)
	await _move_mouse(stryker.pos)
	await _wait(0.6)
	print("card fire: ", s.readability.card_text())
	await _shot("read_card_fire")

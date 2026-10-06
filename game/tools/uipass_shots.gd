extends SceneTree
## Review renders for the UI polish pass (D109-D113), from the real combat
## screen driven through its own input handlers (needs a window):
##   RES=1920x1080 SHOTS=<dir> [MODE=all|callout|odds] godot --path . --script res://tools/uipass_shots.gd
## all     uipass_transfer_source / _transfer_dest / _grapple_landing /
##         _whirlwind_confirm / _callout_<w>x<h> (menu up before, hidden under
##         the band) / odds_hit / odds_miss / odds_crit
## callout only the callout frame (run again at RES=3840x2160 for 4K)
var out := ""
var s: BWCombatScreen
var a: BWUnit          # staff (Transfer)
var f: BWUnit          # fists (Grapple Throw)
var w: BWUnit          # sword (Whirlwind Blade)
var foes: Array = []


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


func _unit(id: String, wc: String = "", keys: Array = []) -> BWUnit:
	var row := BWRosterKits.row(id).duplicate()
	if wc != "":
		row["weapon_class"] = wc
		row["weapon_model"] = "hand_wraps"
	var u := BWUnit.from_roster(row)
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
	var mode := OS.get_environment("MODE")
	if mode == "":
		mode = "all"
	a = _unit("jericho", "", ["transfer"])
	f = _unit("burt", "fists", ["grapple_throw"])
	w = _unit("della", "", ["whirlwind_blade"])
	for id in ["gail", "demeter", "rui"]:
		foes.append(_unit(id))
	for u in [a, f, w]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [a, f, w], foes, [], 3)
	root.add_child(s)
	await _wait(7.0)                                  # past the "Battle start" banner and the opening bark
	var w_res := "%dx%d" % [int(root.size.x), int(root.size.y)]
	if mode == "callout":
		await _callout(w_res)
		quit()
		return
	if mode == "odds":
		await _odds()
		quit()
		return
	await _transfer()
	await _grapple()
	await _whirlwind()
	await _callout(w_res)
	await _odds()
	quit()


## Hand the turn to `u` with the board settled around it.
func _turn(u: BWUnit) -> void:
	s.ui.hide_forecast()
	s._skill = {}
	s._pending_skill = {}
	s.battle.queue = [u]
	s.battle.turn_index = 0
	u.acted = false
	u.moved = false
	u.follow_up = []
	s.battle._begin_turn()
	s._queue.clear()
	s.ui.set_acting(u, s.battle.tiles)
	s.rig.follow(s._views[u.id].global_position, true)
	s._show_options()
	s.ui.set_actions_visible(true)
	await _wait(0.5)


func _place(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s.board_view.top_center(h)


func _free_near(c: Vector2i, d: int, skip: Array = []) -> Vector2i:
	for h in s.battle.board.area(c, d):
		if BWHex.distance(c, h) == d and s.battle.board.is_passable(h) and s.battle.unit_at(h) == null \
				and s.battle.tiles.can_hold(h) and not h in skip:
			return h
	return c


func _transfer() -> void:
	await _turn(a)
	var src := a.pos
	for h in s.battle.board.area(a.pos, 2):
		if BWHex.distance(a.pos, h) == 2 and s.battle.board.is_passable(h) and s.battle.unit_at(h) == null 				and s.battle.tiles.can_hold(h) and s.battle.board.has_los(a.pos, h) and (src == a.pos or h.y > src.y):
			src = h                                   # nearest the camera
	s.battle.tiles.apply([src], "fire", foes[0].id, 3)
	s.board_view.refresh_tiles()
	s._on_skill_chosen("transfer", "")
	s._on_hover(src)
	await _wait(0.4)
	await _shot("uipass_transfer_source")
	s._on_click(src)
	await _wait(0.2)
	var seconds: Array = BWSkillRegistry.get_def("transfer").second_targets(s.battle, a, "", src)
	var dest: Vector2i = seconds[0]
	for h in seconds:
		if s.battle.unit_at(h) == null and BWHex.distance(h, src) == 3 and h.y >= dest.y:
			dest = h
	s._on_hover(dest)
	await _wait(0.4)
	await _shot("uipass_transfer_dest")
	s._on_click(dest)
	await _wait(0.3)
	await _shot("uipass_transfer_confirm")
	s._on_action("cancel")
	s._on_action("cancel")
	s._on_action("cancel")


## A hex whose whole ring is open ground, nearest `c` (so a ring reads).
func _open_hex(c: Vector2i) -> Vector2i:
	var best := c
	var bd := 99
	for h in s.battle.board.cells():
		if s.battle.unit_at(h) != null or not s.battle.board.is_passable(h):
			continue
		var ok := true
		for n in s.battle.board.neighbors(h):
			if not s.battle.board.is_passable(n) or s.battle.unit_at(n) != null:
				ok = false
		if ok and BWHex.distance(c, h) < bd:
			bd = BWHex.distance(c, h)
			best = h
	return best


func _grapple() -> void:
	_place(f, _open_hex(a.pos + Vector2i(0, -3)))
	var spot := f.pos + Vector2i(1, 0)
	_place(foes[1], spot)
	s._face_all()
	await _turn(f)
	s.rig.dist *= 0.75
	s._on_skill_chosen("grapple_throw", f.element)
	s._on_click(foes[1].pos)
	await _wait(0.6)
	await _shot("uipass_grapple_landing")
	s._on_action("cancel")
	s._on_action("cancel")


func _whirlwind() -> void:
	_place(w, _free_near(f.pos, 3, [f.pos]))
	_place(foes[2], _free_near(w.pos, 1))
	_place(foes[0], _free_near(w.pos, 1, [foes[2].pos]))
	s._face_all()
	await _turn(w)
	s._on_skill_chosen("whirlwind_blade", w.element)
	await _wait(0.4)
	await _shot("uipass_whirlwind_confirm")
	s._on_action("cancel")


## The callout over a live player turn: the menu is up first, then fades.
func _callout(w_res: String) -> void:
	await _turn(w)
	var d: BWUnit = foes[2]
	if BWHex.distance(w.pos, d.pos) > 1:
		_place(d, _free_near(w.pos, 1))
	var res := { "hit": true, "crit": false, "glance": false, "resisted": false, "damage": 21 }
	var fc := s.battle.forecast_basic(w, d)
	var results := [{ "target": d.id, "result": res, "ko": false, "target_hp": maxi(d.hp - 21, 1), "tags": [],
		"odds": BWBattle.odds(fc) }]
	var call := s._callout_for("whirlwind_blade", "fire")
	s._cutscene(w.id, results, str(call.name), [], "fire", "spin", call)
	await _wait(0.45 + BWCombatUI.CALLOUT_IN + 0.3)
	await _shot("uipass_callout_" + w_res)
	await _wait(5.0)


## The odds strip on a hit, a miss and a crit, at the result's highlight.
func _odds() -> void:
	await _turn(w)
	var d: BWUnit = foes[2]
	if BWHex.distance(w.pos, d.pos) > 1:
		_place(d, _free_near(w.pos, 1))
	for kind in ["hit", "miss", "crit"]:
		var res := { "hit": kind != "miss", "crit": kind == "crit", "glance": false, "resisted": false,
			"damage": 0 if kind == "miss" else (38 if kind == "crit" else 19) }
		var fc := s.battle.forecast_basic(w, d)
		var results := [{ "target": d.id, "result": res, "ko": false, "target_hp": maxi(d.hp - int(res.damage), 1),
			"tags": [], "odds": BWBattle.odds(fc) }]
		var done := [false]
		var go := func():
			await s._cutscene(w.id, results, "", [], "", "")
			done[0] = true
		go.call()
		# wait for the result highlight (odds_result runs right after the impact)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 6000:
			await process_frame
			if s.ui._odds_cells.has("miss") and _lit():
				break
		await _wait(0.25)
		await _shot("uipass_odds_" + kind)
		while not done[0]:
			await process_frame
		await _wait(0.4)


func _lit() -> bool:
	for k in s.ui._odds_cells:
		var sb: StyleBoxFlat = s.ui._odds_cells[k].get_theme_stylebox("panel")
		if sb.border_color.a > 0.5:
			return true
	return false

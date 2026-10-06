extends SceneTree
## Review renders for the UX pass (D122-D126), from the real screens (needs
## a window):
##   RES=1920x1080 SHOTS=<dir> [MODE=all|settings|pause|gloss|codex|tiers] godot --path . --script res://tools/ux_shots.gd
## settings  ux_settings.png          the settings panel (over the title)
## pause     ux_pause.png             the combat pause menu
## gloss     ux_glossary_tooltip.png  a glossary card hovered on a forecast line
## codex     ux_codex_glossary.png    the codex's Glossary tab
## tiers     ux_tier_minimal.png / ux_tier_full.png   a basic attack (in place) vs a once-per-battle skill (the full cutscene)
var out := ""
var s: BWCombatScreen
var a: BWUnit
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
	var mode := OS.get_environment("MODE")
	if mode == "":
		mode = "all"
	if mode in ["all", "settings"]:
		await _settings()
	if mode == "settings":
		quit()
		return
	await _combat()
	if mode in ["all", "pause"]:
		await _pause()
	if mode in ["all", "gloss"]:
		await _gloss()
	if mode in ["all", "codex"]:
		await _codex()
	if mode in ["all", "tiers"]:
		await _tiers()
	quit()


func _settings() -> void:
	var t := BWTitleScreen.new()
	root.add_child(t)
	await _wait(4.5)
	t.open_settings()
	await _wait(0.6)
	await _shot("ux_settings")
	t.settings.close()
	t.queue_free()
	await _wait(0.2)


func _unit(id: String, keys: Array = []) -> BWUnit:
	var u := BWRosterKits.unit(id)
	for k in keys:
		u.known_skills.append(k)
	if not keys.is_empty():
		u.skill_loadout[u.weapon_class] = keys + BWSkillRegistry.starter(u.weapon_class).slice(0, 1)
	return u


func _combat() -> void:
	a = _unit("jericho", ["tempest"])
	var b := _unit("aureli")
	var c := _unit("will")
	for id in ["gail", "demeter", "rui"]:
		foes.append(_unit(id))
	for u in [a, b, c]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", [a, b, c], foes, [], 3)
	root.add_child(s)
	await _wait(7.0)


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


func _free_near(c: Vector2i, d: int) -> Vector2i:
	for h in s.battle.board.area(c, d):
		if BWHex.distance(c, h) == d and s.battle.board.is_passable(h) and s.battle.unit_at(h) == null and s.battle.tiles.can_hold(h):
			return h
	return c


func _pause() -> void:
	await _turn(a)
	s.open_pause()
	await _wait(0.4)
	await _shot("ux_pause")
	s.pause_menu.resume()
	await _wait(0.3)


## A forecast whose notes carry glossary terms, a term hovered by real
## mouse motion so the engine's tooltip shows.
func _gloss() -> void:
	await _turn(a)
	var f: BWUnit = foes[0]
	_place(f, _free_near(a.pos, 2))
	s.battle.tiles.apply([f.pos], "fire", a.id, 2)
	s.board_view.refresh_tiles()
	var fc := s.battle.forecast_basic(a, f)
	fc["notes"] = (fc.get("notes", []) as Array) + ["Shatter: +15% on a glazed tile", "Pinned foes can't step back"]
	s._pending_target = f
	s.ui.show_forecast(a, f, fc)
	await _wait(0.3)
	var rt := _find_note(s.ui._fc_rows)
	if rt:
		var at := _find_hint(rt, "Shatter")
		var p := rt.get_global_transform_with_canvas() * at
		var wp := root.get_final_transform() * p
		for k in 4:
			var mm := InputEventMouseMotion.new()
			mm.position = wp + Vector2(k, 0)
			mm.global_position = mm.position
			Input.parse_input_event(mm)
			await process_frame
		await _wait(1.2)
	await _shot("ux_glossary_tooltip")
	s.ui.hide_forecast()
	s._pending_target = null


func _find_note(n: Node) -> RichTextLabel:
	for c in n.get_children():
		if c is RichTextLabel and (c as RichTextLabel).get_parsed_text().contains("Shatter"):
			return c
	return null


func _find_hint(rt: RichTextLabel, term: String) -> Vector2:
	var y := 2.0
	while y < rt.size.y:
		var x := 2.0
		while x < rt.size.x:
			if rt.get_tooltip(Vector2(x, y)).begins_with(term):
				return Vector2(x + 6, y + 2)
			x += 3.0
		y += 3.0
	return Vector2(10, 10)


func _codex() -> void:
	var c := BWCodex.summon(s, "glossary")
	await _wait(0.5)
	await _shot("ux_codex_glossary")
	c.close()
	await _wait(0.2)


## The same screen, two tiers: a basic attack plays in place (minimal), a
## once-per-battle Tempest gets the full cutscene. Frames at the impact.
func _tiers() -> void:
	await _turn(a)
	var f: BWUnit = foes[1]
	_place(f, _free_near(a.pos, 1))
	s.rig.follow(s._views[a.id].global_position, true)
	await _wait(0.6)
	var n := s.battle.history.size()
	s.battle.attack(a, f)
	print("minimal attack events: ", s.battle.history.slice(n).map(func(e): return e.type))
	s._after_events()
	await _wait(0.9)
	await _shot("ux_tier_minimal")
	while s._busy:
		await process_frame
	await _turn(a)
	_place(f, _free_near(a.pos, 2))
	var el := a.element
	var aim := f.pos
	var tg := s.battle.skill_targets(a, "tempest", el)
	for h in tg:
		if BWHex.distance(h, f.pos) < BWHex.distance(aim, f.pos) or not aim in tg:
			aim = h
	var n2 := s.battle.history.size()
	print("tempest targets: ", tg.size(), " aim ", aim, " f ", f.pos)
	s.battle.use_skill(a, "tempest", el, aim)
	print("full skill events: ", s.battle.history.slice(n2).map(func(e): return e.type))
	s._after_events()
	await _wait(1.25)
	await _shot("ux_tier_full")
	while s._busy:
		await process_frame

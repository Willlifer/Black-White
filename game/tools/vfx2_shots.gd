extends SceneTree
## D387-D390 review frames (needs a window): the VFX / animation polish pass
## on the real combat screen, each scenario on a fresh screen with the right
## weapon (the old vfx_shots strips put the spin and Hundred Fists on a
## pistol unit).
##   RES=1600x900 SHOTS=<dir> [MODE=all|fan|surge_fire|surge_ice|surge_water|chamber|haymaker|hundred|spin|jab|wind_draw|wind_burst]
##     godot --path . --script res://tools/vfx2_shots.gd
##   python tools/vfx_strip.py <dir> ../design/art vfx2_      -> design/art/vfx2_<mode>.png
var out := ""
var s: BWCombatScreen
var P: Array = []
var E: Array = []

const MODES := ["fan", "surge_fire", "surge_ice", "surge_water", "chamber", "haymaker", "hundred", "spin", "jab", "wind_draw", "wind_burst"]


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art/vfx2_frames")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


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
	var modes: Array = MODES if mode in ["", "all"] else Array(mode.split(","))
	for m in modes:
		await call("_" + m)
		if is_instance_valid(s):
			s.queue_free()
			await _wait(0.3)
	quit()


# ------------------------------------------------------------------ staging

func _kit(id: String, over: Dictionary = {}) -> BWUnit:
	var row := BWRosterKits.row(id)
	row.merge(over, true)
	var u := BWUnit.from_roster(row)
	u.stats["spd"] = 20
	return u


func _stage(caster: BWUnit) -> void:
	P = [caster, _kit("jericho" if caster.id != "jericho" else "stryker"), _kit("bob")]
	E = []
	for id in ["della", "demeter", "kira"]:
		E.append(BWRosterKits.unit(id))
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", P, E, [], 3)
	root.add_child(s)
	await _wait(1.8)
	await _reset()


func _u(id: String) -> BWUnit:
	return s.battle._unit(id)


func _free_hex(near: Vector2i, dist: int, avoid: Array = []) -> Vector2i:
	var best := Vector2i(-1, -1)
	for h in s.battle.board.area(near, dist):
		if BWHex.distance(near, h) != dist or not s.battle.board.is_passable(h) or h in avoid:
			continue
		if s.battle.unit_at(h) != null:
			continue
		if best == Vector2i(-1, -1) or s.battle.board.elevation(h) == s.battle.board.elevation(near):
			best = h
	return best


func _place(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s.board_view.top_center(h)
	s._views[u.id].visible = true
	s._views[u.id].scale = Vector3.ONE


func _reset() -> void:
	s.rig.following = true
	s.rig.input_enabled = true
	var c: Vector2i = s.battle.board.camera_focus
	for u in P + E:
		u.pos = Vector2i(-50, -50)
	_place(_u(P[0].id), c)
	for u in E.map(func(x): return _u(x.id)) + [_u(P[1].id), _u(P[2].id)]:   # only the cast and its foes on the board
		u.pos = Vector2i(-50, -50)
		s._views[u.id].position = Vector3(0, -100, 0)
	s._face_all()
	await _wait(0.2)


func _foe_at(k: int, h: Vector2i) -> BWUnit:
	var u := _u(E[k].id)
	_place(u, h)
	return u


func _res(u: BWUnit, dmg: int, hit := true) -> Dictionary:
	return { "target": u.id, "result": { "hit": hit, "crit": false, "glance": false, "resisted": false, "damage": dmg if hit else 0 },
		"ko": false, "target_hp": maxi(u.hp - dmg, 1), "tags": [] }


func _skill(unit: BWUnit, key: String, el: String, target: Vector2i, hexes: Array, results: Array) -> Dictionary:
	return { "type": "skill", "unit": unit.id, "skill": key, "element": el, "target": target, "hexes": hexes, "results": results, "ko": false }


## Play events in order while saving frames at the given real-time offsets.
func _capture(name: String, events: Array, times: Array) -> void:
	var dir := "%s/%s" % [out, name]
	DirAccess.make_dir_recursive_absolute(dir)
	var done := [false]
	var runner := func():
		for e in events:
			await s._play(e)
		done[0] = true
	runner.call()
	await _frames(dir, times)
	while not done[0]:
		await process_frame
	print("frames ", dir)


func _frames(dir: String, times: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var k := 0
	while k < times.size():
		await RenderingServer.frame_post_draw
		if float(Time.get_ticks_usec() - t0) / 1e6 >= float(times[k]):
			root.get_texture().get_image().save_png("%s/%02d.png" % [dir, k])
			k += 1


# ------------------------------------------------------------------ scenarios

func _fan() -> void:
	await _stage(_kit("will"))
	var a := _u(P[0].id)
	var ring := BWHex.neighbors(a.pos)
	var f := _foe_at(0, ring[1])
	var f2 := _foe_at(1, ring[4])
	await _capture("fan", [_skill(a, "fan_of_knives", "thunder", a.pos, ring, [_res(f, 10), _res(f2, 10)])],
		[1.25, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.05, 2.3, 2.6, 2.9, 3.2])


func _surge_el(el: String) -> void:
	await _stage(_kit("jericho"))
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 3)
	var f := _foe_at(0, t)
	await _capture("surge_" + el, [_skill(a, "surge", el, t, s.battle.board.area(t, 1), [_res(f, 26)])],
		[1.85, 2.0, 2.1, 2.2, 2.3, 2.4, 2.55, 2.7])


func _surge_fire() -> void:
	await _surge_el("fire")


func _surge_ice() -> void:
	await _surge_el("ice")


func _surge_water() -> void:
	await _surge_el("water")


func _chamber() -> void:
	await _stage(_kit("sala"))
	var a := _u(P[0].id)
	var fs: Array = []
	for k in 3:
		fs.append(_foe_at(k, _free_hex(a.pos, 2, fs.map(func(u): return u.pos))))
	var rs: Array = [_res(fs[0], 5), _res(fs[1], 5), _res(fs[2], 5, false), _res(fs[0], 5)]
	await _capture("chamber", [_skill(a, "empty_the_chamber", "", a.pos, [], rs)],
		[1.3, 1.42, 1.5, 1.58, 1.66, 1.74, 1.82, 1.9, 2.0, 2.15, 2.35, 2.6])


func _fists_kit() -> BWUnit:
	return _kit("will", { "weapon_class": "fists", "weapon_model": "hand_wraps", "element": "fire" })


func _haymaker() -> void:
	await _stage(_fists_kit())
	var a := _u(P[0].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	await _capture("haymaker", [_skill(a, "haymaker", "fire", f.pos, [f.pos], [_res(f, 30)])],
		[1.0, 1.25, 1.5, 1.75, 1.95, 2.05, 2.12, 2.2, 2.3, 2.45, 2.65, 2.9])


func _hundred() -> void:
	await _stage(_fists_kit())
	var a := _u(P[0].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	var evs: Array = [_skill(a, "hundred_fists", "fire", f.pos, [f.pos], [_res(f, 9)])]
	for k in range(1, 6):
		evs.append({ "type": "attack", "unit": a.id, "target": f.id, "result": { "hit": true, "crit": false, "glance": false, "resisted": false, "damage": 7 },
			"ko": false, "target_hp": 50, "strike": k, "strikes": 6, "pattern": "hundred_fists", "skill": "hundred_fists", "tags": [] })
	await _capture("hundred", evs, [1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7])


func _spin() -> void:
	await _stage(_kit("stryker"))
	var a := _u(P[0].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	await _capture("spin", [_skill(a, "whirlwind_blade", "light", a.pos, BWHex.neighbors(a.pos), [_res(f, 12)])],
		[1.3, 1.45, 1.55, 1.62, 1.7, 1.78, 1.86, 1.95, 2.1, 2.3])


func _jab() -> void:
	await _stage(_fists_kit())
	var a := _u(P[0].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	var mid: Vector3 = (s._views[a.id].global_position + s._views[f.id].global_position) * 0.5
	s.rig.following = false
	s.rig.pivot = mid + Vector3(0, 1.0, 0)
	s.rig.dist = 7.5
	s.rig.pitch = deg_to_rad(16.0)
	var side := atan2(s._views[f.id].global_position.x - s._views[a.id].global_position.x,
		s._views[f.id].global_position.z - s._views[a.id].global_position.z) + PI / 2.0
	s.rig.yaw = side
	await _wait(0.5)
	var e := { "type": "attack", "unit": a.id, "target": f.id, "result": { "hit": true, "crit": false, "glance": false, "resisted": false, "damage": 9 },
		"ko": false, "target_hp": 60, "tags": [] }
	await _capture("jab", [e], [0.05, 0.15, 0.22, 0.28, 0.32, 0.36, 0.42, 0.55])


## Wind order (D390): real battle events, the screen's own drain (hoisted).
func _wind(opt: String) -> void:
	var me := _kit("jericho", { "element": "wind" })
	await _stage(me)
	var a := _u(P[0].id)
	var tgt := _free_hex(a.pos, 3)
	var foe_hex := tgt
	if opt == "draw":
		foe_hex = _free_hex(tgt, 2)
	else:
		foe_hex = _free_hex(tgt, 1)
	var f := _foe_at(0, foe_hex)
	for k in ["surge"]:
		if not k in a.known_skills:
			a.known_skills.append(k)
		if not k in a.overcap:
			a.overcap.append(k)
	s.battle.queue = [a]
	s.battle.turn_index = 0
	s.battle._begin_turn()
	s._queue.clear()
	s.battle.expected_rolls = true
	BWWindShape.set_choice(a, "surge", opt)
	s.rig.following = false
	s.rig.pivot = s.board_view.top_center(tgt) + Vector3(0, 1.0, 0)
	s.rig.dist = 13.0
	await _wait(0.6)
	s.battle.use_skill(a, "surge", "wind", tgt)
	print("events ", BWWindOrder.hoist(s._queue).map(func(e): return str(e.type) + ":" + str(e.get("kind", ""))))
	var dir := "%s/wind_order_%s" % [out, opt]
	DirAccess.make_dir_recursive_absolute(dir)
	var done := [false]
	var runner := func():
		# the screen's drain, minus the AI turns after it: hoist, then play
		s._queue = BWWindOrder.hoist(s._queue)
		while not s._queue.is_empty():
			await s._play(s._queue.pop_front())
		done[0] = true
	runner.call()
	var times := [0.0, 0.05, 0.1, 0.16, 0.6, 1.1, 1.6, 2.0, 2.4, 2.8, 3.2, 3.6] if opt == "draw" else [0.1, 0.6, 1.1, 1.6, 2.0, 2.3, 2.6, 2.8, 2.95, 3.1, 3.3, 3.6]
	await _frames(dir, times)
	while not done[0]:
		await process_frame
	print("frames ", dir)


func _wind_draw() -> void:
	await _wind("draw")


func _wind_burst() -> void:
	await _wind("burst")

extends SceneTree
## Review frames for the cast / spectacle VFX (D167-D170), from the real
## combat screen playing synthetic skill events (needs a window):
##   RES=1600x900 [SHOTS=<dir>] [MODE=all|surge|ley|tempest|dive|elements|fists|chamber|spin|warcry|siphon|saturate|bolt|truth|triumph]
##     godot --path . --script res://tools/vfx_shots.gd
##   python tools/vfx_strip.py <dir>        -> design/art/casts_*.png
## Frames go to <dir>/<mode>/NN.png at fixed real-time offsets; Tempest also
## prints a frame-time / particle / draw-call readout ("PERF ...").
var out := ""
var s: BWCombatScreen
var P: Array = []
var E: Array = []


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art/vfx_frames")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _go() -> void:
	var wres := OS.get_environment("RES")
	if wres.contains("x"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3:
			await process_frame
		DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
		for i in 3:
			await process_frame
	var players := ["jericho", "rui", "sala"]
	var others := ["della", "stryker", "kira"]
	for id in players:
		P.append(BWRosterKits.unit(id))
	for id in others:
		E.append(BWRosterKits.unit(id))
	for u in P:
		u.stats["spd"] = 20
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", P, E, [], 3)
	root.add_child(s)
	await _wait(1.8)
	var mode := OS.get_environment("MODE")
	if mode == "":
		mode = "all"
	var modes := ["surge", "ley", "tempest", "dive", "elements", "fists", "chamber", "spin", "warcry", "siphon", "saturate", "bolt", "truth", "triumph"] if mode == "all" else [mode]
	for m in modes:
		await _reset()
		await call("_" + m)
		await _wait(0.6)
	quit()


# ------------------------------------------------------------------ staging

func _u(id: String) -> BWUnit:
	return s.battle._unit(id)


func _free_hex(near: Vector2i, dist: int, avoid: Array = []) -> Vector2i:
	var best := Vector2i(-1, -1)
	for h in s.battle.board.area(near, dist):
		if BWHex.distance(near, h) != dist or not s.battle.board.is_passable(h) or h in avoid:
			continue
		var occ := s.battle.unit_at(h)
		if occ != null:
			continue
		if best == Vector2i(-1, -1) or s.battle.board.elevation(h) == s.battle.board.elevation(near):
			best = h
	return best


func _place(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s.board_view.top_center(h)
	s._views[u.id].visible = true
	s._views[u.id].scale = Vector3.ONE


## Everyone home: a fixed layout around the board's middle.
func _reset() -> void:
	s.rig.following = true
	s.rig.input_enabled = true
	var c: Vector2i = s.battle.board.camera_focus
	var spots: Array = []
	for h in s.battle.board.area(c, 4):
		if s.battle.board.is_passable(h):
			spots.append(h)
	for u in P + E:
		u.pos = Vector2i(-50, -50)
	var caster := _u(P[0].id)
	_place(caster, c)
	for u in [_u(P[1].id), _u(P[2].id)]:
		_place(u, _free_hex(c, 2))
	for u in E.map(func(x): return _u(x.id)):
		u.pos = Vector2i(-50, -50)
		s._views[u.id].position = Vector3(0, -100, 0)
	s._face_all()
	await _wait(0.2)


func _foe_at(k: int, h: Vector2i) -> BWUnit:
	var u := _u(E[k].id)
	_place(u, h)
	return u


func _res(u: BWUnit, dmg: int, crit := false) -> Dictionary:
	return { "target": u.id, "result": { "hit": true, "crit": crit, "glance": false, "resisted": false, "damage": dmg },
		"ko": false, "target_hp": maxi(u.hp - dmg, 1), "tags": [] }


func _skill(unit: BWUnit, key: String, el: String, target: Vector2i, hexes: Array, results: Array) -> Dictionary:
	return { "type": "skill", "unit": unit.id, "skill": key, "element": el, "target": target, "hexes": hexes, "results": results, "ko": false }


## Play events in order while saving frames at the given real-time offsets.
func _capture(name: String, events: Array, times: Array, perf := false) -> void:
	var dir := "%s/%s" % [out, name]
	DirAccess.make_dir_recursive_absolute(dir)
	var done := [false]
	var runner := func():
		for e in events:
			await s._play(e)
		done[0] = true
	runner.call()
	var t0 := Time.get_ticks_usec()
	var k := 0
	var frames: Array = []
	var last := t0
	var peak_draw := 0
	var peak_parts := 0
	var saved := false
	while k < times.size() or (perf and not done[0]):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if perf and not saved:
			frames.append(float(now - last) / 1000.0)
			peak_draw = maxi(peak_draw, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			peak_parts = maxi(peak_parts, int(s.vfx.live().particles))
		saved = false
		if k < times.size() and float(now - t0) / 1e6 >= float(times[k]):
			root.get_texture().get_image().save_png("%s/%02d.png" % [dir, k])
			k += 1
			saved = true                 # the save stalls the next frame: not counted
		last = Time.get_ticks_usec()
	if perf and not frames.is_empty():
		var sorted := frames.duplicate()
		sorted.sort()
		var avg := 0.0
		for f in frames:
			avg += f
		avg /= frames.size()
		print("PERF tempest: %d frames, avg %.2f ms, p95 %.2f ms, max %.2f ms, peak particles %d (pool %d), peak vfx nodes %d, peak draw calls %d" % [
			frames.size(), avg, sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1], peak_parts, BWVfxCasts.POOL,
			int(s.vfx.stats.peak_nodes), peak_draw])
	while not done[0]:
		await process_frame
	print("frames ", dir)


# ------------------------------------------------------------------ scenarios

func _surge() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 3)
	var f := _foe_at(0, t)
	var f2 := _foe_at(1, _free_hex(t, 1))
	var hexes := s.battle.board.area(t, 1)
	await _capture("surge", [_skill(a, "surge", "fire", t, hexes, [_res(f, 26), _res(f2, 14)])],
		[1.0, 1.5, 1.9, 2.2, 2.4, 2.55, 2.7, 2.85, 3.0, 3.2, 3.4, 3.7])


func _ley() -> void:
	var a := _u(P[0].id)
	var ally := _u(P[1].id)
	var dir_hex := BWHex.neighbors(a.pos)[0]
	var line := s.battle.board.ray(a.pos, dir_hex, 4)
	if line.size() >= 2:
		_place(ally, line[1])
	s.rig.follow(s.board_view.top_center(line[mini(1, line.size() - 1)]))
	await _wait(0.5)
	await _capture("ley", [_skill(a, "ley_line", "light", dir_hex, line, [])], [0.12, 0.25, 0.38, 0.5, 0.65, 0.85, 1.05, 1.3])


func _tempest() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 3)
	var hexes := s.battle.board.area(t, 2)
	var f := _foe_at(0, t)
	var f2 := _foe_at(1, _free_hex(t, 1))
	var f3 := _foe_at(2, _free_hex(t, 2, [f2.pos]))
	# baseline: the same board with no VFX, for comparison with the readout below
	var base: Array = []
	var last := Time.get_ticks_usec()
	for i in 90:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		base.append(float(now - last) / 1000.0)
		last = now
	base.sort()
	var bavg := 0.0
	for ms in base:
		bavg += ms
	print("PERF idle: avg %.2f ms, p95 %.2f ms, draw calls %d" % [bavg / base.size(), base[int(base.size() * 0.95)],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	await _capture("tempest", [_skill(a, "tempest", "thunder", t, hexes, [_res(f, 22), _res(f2, 18), _res(f3, 18)])],
		[1.0, 1.4, 1.8, 2.2, 2.45, 2.7, 3.0, 3.4], true)


func _dive() -> void:
	var a := _u(P[1].id)
	var t := _free_hex(a.pos, 3)
	var ring: Array = []
	for n in BWHex.neighbors(t):
		if s.battle.board.is_passable(n) and s.battle.unit_at(n) == null:
			ring.append(n)
	var f := _foe_at(0, ring[0])
	var f2 := _foe_at(1, ring[2] if ring.size() > 2 else ring[1])
	s.rig.follow(s.board_view.top_center(t))
	await _wait(0.5)
	var mv := { "type": "move", "unit": a.id, "path": [a.pos, t], "kind": "leap" }
	a.pos = t
	var sk := _skill(a, "dragoon_dive", "dark", t, ring, [_res(f, 30), _res(f2, 24)])
	s._queue.append(sk)
	await _capture("dive", [mv], [0.12, 0.3, 0.55, 0.8, 1.0, 1.12, 1.2, 1.35])
	s._queue.clear()


func _elements() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 2)
	var at := s.board_view.top_center(t)
	s.rig.following = false
	s.rig.pivot = at + Vector3(0, 1.8, 0)
	s.rig.dist = 15.0
	s.rig.pitch = deg_to_rad(22.0)
	await _wait(0.6)
	var dir := "%s/elements" % out
	DirAccess.make_dir_recursive_absolute(dir)
	var peak := { "fire": 0.4, "water": 0.38, "ice": 0.3, "thunder": 0.1, "wind": 0.42, "light": 0.3, "dark": 0.5 }
	var k := 0
	for el in BWVfxCasts.ELEMENTS:
		s.vfx.release_at(el, at, 1.0)
		await _wait(peak[el])
		await _shot("%s/%02d_%s.png" % [dir, k, el])
		k += 1
		await _wait(1.3)
	s.rig.following = true
	print("frames ", dir)


func _fists() -> void:
	var a := _u(P[2].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	var evs: Array = [_skill(a, "hundred_fists", "thunder", f.pos, [f.pos], [_res(f, 9)])]
	for k in range(1, 4):
		evs.append({ "type": "attack", "unit": a.id, "target": f.id, "result": { "hit": true, "crit": false, "glance": false, "resisted": false, "damage": 7 },
			"ko": false, "target_hp": 50, "strike": k, "strikes": 4, "pattern": "hundred_fists", "skill": "hundred_fists", "tags": [] })
	await _capture("fists", evs, [1.1, 1.3, 1.5, 1.8, 2.1, 2.4])


func _chamber() -> void:
	var a := _u(P[2].id)
	var fs: Array = []
	for k in 3:
		fs.append(_foe_at(k, _free_hex(a.pos, 2, fs.map(func(u): return u.pos))))
	await _capture("chamber", [_skill(a, "empty_the_chamber", "", a.pos, [], fs.map(func(u): return _res(u, 12)))], [1.0, 1.2, 1.35, 1.5, 1.65, 1.9])


func _spin() -> void:
	var a := _u(P[2].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	var f2 := _foe_at(1, _free_hex(a.pos, 1, [f.pos]))
	await _capture("spin", [_skill(a, "fan_of_knives", "wind", a.pos, BWHex.neighbors(a.pos), [_res(f, 10), _res(f2, 10)])], [1.0, 1.2, 1.35, 1.5, 1.7, 1.9])


func _warcry() -> void:
	var a := _u(P[1].id)
	await _capture("warcry", [_skill(a, "war_cry", "", a.pos, [], [])], [0.05, 0.15, 0.3, 0.5, 0.8])


func _siphon() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 2)
	s.battle.tiles.author(t, 2, 0)
	s.board_view.refresh_tiles(true)
	s.rig.follow(s.board_view.top_center(t))
	await _wait(0.5)
	await _capture("siphon", [_skill(a, "siphon", "", t, [t], [])], [0.1, 0.25, 0.45, 0.65, 0.9])


func _saturate() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 3)
	var f := _foe_at(0, t)
	await _capture("saturate", [_skill(a, "saturate", "water", t, [t], [_res(f, 18)])], [1.0, 1.4, 1.75, 1.95, 2.1, 2.4])


func _bolt() -> void:
	var a := _u(P[0].id)
	var t := _free_hex(a.pos, 3)
	var f := _foe_at(0, t)
	await _capture("bolt", [_skill(a, "bolt", "ice", t, [t], [_res(f, 16)])], [1.0, 1.3, 1.55, 1.7, 1.85, 2.1])


func _truth() -> void:
	var a := _u(P[2].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	await _capture("truth", [_skill(a, "elemental_truth", "fire", f.pos, [f.pos], [_res(f, 40)])], [1.0, 1.25, 1.45, 1.6, 1.8, 2.1])


func _triumph() -> void:
	var a := _u(P[2].id)
	var f := _foe_at(0, _free_hex(a.pos, 1))
	await _capture("triumph", [_skill(a, "triumph", "light", f.pos, [f.pos], [_res(f, 60, true)])], [0.9, 1.05, 1.2, 1.4, 1.6, 1.9])

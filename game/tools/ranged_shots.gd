extends SceneTree
## D164-D166 review renders from the real combat screen (needs a window):
##
##   SHOTS=<dir> MODE=flat|arcing|rain|split|pierce|pin|throw|perf [RES=1280x720] [CUT=default|minimal]
##     godot --path . --script res://tools/ranged_shots.gd
##
## Every mode stages Gail (recurve bow) against three foes on the arena and
## plays one synthesized event through BWCombatScreen._play (the same path
## as a fight), saving every rendered frame to <dir>/<mode>_frames/NNN.png.
## tools/ranged_strip.py turns them into design/art/ranged_*.png / .gif.
## MODE=perf plays Rain of Arrows with no capture and prints the frame times
## (the pool must keep it from hitching).

var out := ""
var s: BWCombatScreen
var _cap_dir := ""
var _cap_n := 0
var _capturing := false


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("user://ranged_shots")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _go() -> void:
	var wres := OS.get_environment("RES") if OS.get_environment("RES") != "" else "1280x720"
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for i in 3:
		await process_frame
	DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
	for i in 3:
		await process_frame
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "flat"
	BWSettings.put("cutscenes", OS.get_environment("CUT") if OS.get_environment("CUT") != "" else "default")
	var archer_id := "will" if mode == "throw" else "gail"
	var p: Array = [BWRosterKits.unit(archer_id), BWRosterKits.unit("della"), BWRosterKits.unit("jericho")]
	var e: Array = [BWRosterKits.unit("burt"), BWRosterKits.unit("kira"), BWRosterKits.unit("rui")]
	for u in e:
		u.team = "enemy"
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	await _wait(1.4)
	var b := s.battle
	var a: BWUnit = b._unit(archer_id)
	# the archer at a central tile, the target hex 4 away, the foes in the blast
	var start := _free_near(b, Vector2i(b.board.cols / 2 - 2, b.board.rows / 2), [])
	_put(a, start)
	var tgt := start
	for dir in 6:
		var h := start
		for k in 4:
			h = BWHex.neighbors(h)[dir]
		if b.board.exists(h) and b.board.area(h, 2).size() >= 15:
			tgt = h
			break
	var foes: Array = []
	var spots := [tgt, BWHex.neighbors(tgt)[1], BWHex.neighbors(BWHex.neighbors(tgt)[4])[4]]
	if mode in ["split", "pierce"]:
		var di := BWHex.direction_index(start, tgt)
		var beyond := BWHex.neighbors(BWHex.neighbors(tgt)[di])[di]
		spots = [tgt, beyond, BWHex.neighbors(start)[(di + 1) % 6]]
		if mode == "split":
			var side := start
			for k in 3:
				side = BWHex.neighbors(side)[(di + 1) % 6]
			spots = [tgt, side, BWHex.neighbors(BWHex.neighbors(start)[(di + 5) % 6])[(di + 5) % 6]]
	if mode in ["flat", "pin", "throw", "aimed", "perf_flat"]:
		var di2 := BWHex.direction_index(start, tgt)
		spots[0] = BWHex.neighbors(BWHex.neighbors(start)[di2])[di2]
		tgt = spots[0]
	for k in e.size():
		var u: BWUnit = b._unit(e[k].id)
		_put(u, _free_near(b, spots[k], [a.pos]))
		u.hp = u.max_hp()
		foes.append(u)
	# the other two players out of the way
	for k in [1, 2]:
		var u: BWUnit = b._unit(p[k].id)
		_put(u, _free_near(b, BWHex.neighbors(BWHex.neighbors(start)[3])[3 + k - 1], [a.pos] + foes.map(func(x): return x.pos)))
	s._face_all()
	s.rig.follow(s._views[a.id].global_position, true)
	await _wait(0.6)
	var res := func(dmg: int, hit := true, crit := false) -> Dictionary:
		return { "hit": hit, "crit": crit, "glance": false, "resisted": false, "damage": dmg if hit else 0, "secondary": true }
	var row := func(u: BWUnit, r: Dictionary) -> Dictionary:
		return { "target": u.id, "result": r, "ko": false, "target_hp": u.hp - int(r.damage), "tags": [], "odds": {} }
	var ev := {}
	match mode:
		"flat":
			ev = { "type": "attack", "unit": a.id, "target": foes[0].id, "result": res.call(14), "ko": false, "target_hp": 100, "tags": [] }
		"miss":
			ev = { "type": "attack", "unit": a.id, "target": foes[0].id, "result": res.call(0, false), "ko": false, "target_hp": 100, "tags": [] }
		"aimed":
			ev = _skill(a, "aimed_shot", "wind", foes[0].pos, [foes[0].pos], [row.call(foes[0], res.call(22))])
		"pin":
			ev = _skill(a, "pinning_shot", "wind", foes[0].pos, [foes[0].pos], [row.call(foes[0], res.call(12))])
			b.add_status(foes[0], "pinned", a)
		"pierce":
			ev = _skill(a, "energized_shot", "wind", foes[0].pos, BWHex.trail(a.pos, foes[0].pos), [row.call(foes[0], res.call(16)), row.call(foes[1], res.call(9))])
			ev["pierce"] = foes[1].id
		"split":
			ev = _skill(a, "split_arrow", "wind", foes[0].pos, [foes[0].pos, foes[1].pos], [row.call(foes[0], res.call(9)), row.call(foes[1], res.call(8, false))])
		"throw":
			ev = _skill(a, "dualthrow", "thunder", foes[0].pos, BWHex.trail(a.pos, foes[0].pos), [row.call(foes[0], res.call(12))])
		"arcing":
			var hx := b._on_board(b.board.area(tgt, 1))
			var rs: Array = []
			for u in foes:
				if u.pos in hx:
					rs.append(row.call(u, res.call(15)))
			ev = _skill(a, "arcing_shot", "wind", tgt, hx, rs)
		"rain", "perf":
			var hx2 := b._on_board(b.board.area(tgt, 2))
			var rs2: Array = []
			for u in foes:
				if u.pos in hx2:
					rs2.append(row.call(u, res.call(9, u != foes[2])))
			ev = _skill(a, "rain_of_arrows", "wind", tgt, hx2, rs2)
	print("MODE ", mode, " archer ", a.pos, " target ", tgt, " foes ", foes.map(func(x): return x.pos), " results ", (ev.get("results", []) as Array).size())
	if mode == "perf":
		print("POOL prewarmed: ", s.ranged.pool_free(), " created ", s.ranged.stats.created)
		var t0 := Time.get_ticks_usec()
		var times: Array = []
		var done := [false]
		var run := func():
			await s._play(ev)
			done[0] = true
		run.call()
		var last := Time.get_ticks_usec()
		while not done[0]:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			if (now - last) > 40000:
				print("PERF hitch %.1f ms at %.2f s (live %d)" % [(now - last) / 1000.0, (now - t0) / 1e6, s.ranged.live_count()])
			last = now
		times.sort()
		var worst: float = times[times.size() - 1]
		var p99: float = times[int(times.size() * 0.99)]
		var mean := 0.0
		for x in times:
			mean += x
		mean /= times.size()
		print("PERF rain: %d frames over %.2f s, mean %.2f ms, p99 %.2f ms, worst %.2f ms; arrows created %d (pool %d), max live %d" % [
			times.size(), (Time.get_ticks_usec() - t0) / 1e6, mean, p99, worst, s.ranged.stats.created, POOL_SIZE(), s.ranged.stats.max_live])
		quit()
		return
	_cap_dir = "%s/%s_frames" % [out, mode]
	DirAccess.make_dir_recursive_absolute(_cap_dir)
	for f in DirAccess.get_files_at(_cap_dir):
		DirAccess.remove_absolute(_cap_dir + "/" + f)
	var done2 := [false]
	var go := func():
		if ev.type == "attack":
			# the cutscene (FULL), so the arrow and the stuck shaft read up close
			var rs := [{ "target": ev.target, "result": ev.result, "ko": false, "target_hp": 100, "tags": [], "odds": {} }]
			await s._cutscene(ev.unit, rs, "", [], "", "", {}, { "tier": BWCutsceneTier.FULL, "flash": "none" })
		else:
			await s._play(ev)
		done2[0] = true
	go.call()
	var t1 := Time.get_ticks_msec()
	var imgs: Array = []
	var t_done := -1
	while Time.get_ticks_msec() - t1 < 14000:
		await RenderingServer.frame_post_draw
		var im := root.get_texture().get_image()
		im.resize(im.get_width() / 2, im.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		imgs.append(im)
		if done2[0] and t_done < 0:
			t_done = Time.get_ticks_msec()
		if t_done >= 0 and Time.get_ticks_msec() - t_done > 300:
			break
	for im in imgs:
		im.save_png("%s/%03d.png" % [_cap_dir, _cap_n])
		_cap_n += 1
	print("captured ", _cap_n, " frames to ", _cap_dir)
	quit()


func POOL_SIZE() -> int:
	return BWRangedVFX.POOL


func _skill(a: BWUnit, key: String, el: String, tgt: Vector2i, hexes: Array, results: Array) -> Dictionary:
	return { "type": "skill", "unit": a.id, "skill": key, "element": el, "target": tgt, "hexes": hexes, "results": results, "ko": false }


func _put(u: BWUnit, h: Vector2i) -> void:
	u.pos = h
	s._views[u.id].position = s._unit_pos(h)


func _free_near(b: BWBattle, h: Vector2i, avoid: Array) -> Vector2i:
	for r in 4:
		for c in ([h] if r == 0 else BWHex.ring(h, r)):
			if b.board.exists(c) and b.board.is_passable(c) and not c in avoid and (b.unit_at(c) == null):
				return c
	return h

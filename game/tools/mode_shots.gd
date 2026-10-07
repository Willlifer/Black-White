extends SceneTree
## D327-D333 review renders of the 6v6 modes (needs a window):
##   [SHOTS=<dir>] [RES=1920x1080] godot --path . --resolution 1920x1080 --script res://tools/mode_shots.gd
## mode_split_fire|ice|wind.png  Split Front's opening, the whole map, one per divider element
## mode_split_prebattle.png      the pre-battle: the plate, WEST / EAST FRONT 3 / 3, the divider telegraphed
## mode_split_merge.png          the moment the divider opens (the enemy's break-through or the squad's)
## mode_horde_prebattle.png      the Horde's pre-battle: the plate, the exit, the first wave
## mode_horde_waves.png          mid-fight: a wave rung on the north edge, the plate (wave n of 4, escaped)
## mode_horde_exit.png           the exit row with grunts closing on it
var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	var res := OS.get_environment("RES")
	if res == "":
		res = "1920x1080"
	var wh := res.split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := "%s/%s.png" % [out, name]
	img.save_png(p)
	print("shot ", p)


func _go() -> void:
	BWSettings.put("cutscenes", "fast")
	BWMusic.ensure(root)
	var only := OS.get_environment("ONLY")
	if only == "" or only == "split":
		for el in BWSplitFront.ELEMENTS:
			await _split_open(el)
		await _prebattle("splitfront")
		await _split_merge()
	if only == "" or only == "horde":
		await _prebattle("horde")
		await _horde()
	quit()


## A run at fight n with its six levelled and geared (as --mode does).
func _run_at(n: int, seed_value: int) -> BWRun:
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), seed_value)
	for u in r.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(x): return x.slot == slot)
			u.equipment[slot] = r.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), r.tier_for(n))
		u.equipment["main_hand"] = r.make_item(u.weapon_model, r.tier_for(n))
	r.fight = n
	return r


func _sides(md: String, n: int, seed_value: int) -> Array:
	var r := _run_at(n, seed_value)
	var ps: Array = r.squad.slice(0, 6)
	r.prepare_for_battle(ps)
	var room := { "kind": BWRooms.STANDARD, "map": BWRun.MODE_MAPS[md], "fight": n, "mode": md,
		"enemies": BWRooms._draw_ids(r, n, [], false, 6) }
	return [ps, r.enemies_for(n, room)]


func _overview(sc: BWCombatScreen, focus: Vector2i, dist: float = 30.0, pitch: float = 62.0, yaw: float = 0.0) -> void:
	sc.rig.yaw = deg_to_rad(yaw)
	sc.rig.pitch = deg_to_rad(pitch)
	sc.rig.dist = dist
	sc.rig.follow(BWLook.world(focus, 0), true)


func _split_open(el: String) -> void:
	var sd := _sides("splitfront", 5, 3)
	s = BWCombatScreen.new()
	s.configure("res://maps/splitfront.json", sd[0], sd[1], [], 5)
	s.mode_opts = { "divider": el }
	s.autoplay = false
	root.add_child(s)
	await _wait(2.6)
	_overview(s, Vector2i(9, 8), 44.0, 64.0, 24.0 if el == "wind" else 0.0)
	await _wait(0.8)
	await _shot("mode_split_%s" % el)
	print("split %s: divider %s, plate %s" % [el, BWSplitFront.standing(s.battle), s.mode_view.shown.get("lines", [])])
	s.queue_free()
	await process_frame


func _prebattle(md: String) -> void:
	var seed_value := 1
	var n := BWRun.SPLIT_FIGHT
	if md == "horde":
		n = BWRun.SIX_FIGHTS[0]
		while BWRun.six_modes_for(seed_value)[0] != "horde":
			seed_value += 1
	var run := _run_at(n, seed_value)
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(2.8)
	await _shot("mode_%s_prebattle" % ("split" if md == "splitfront" else "horde"))
	print("%s prebattle: %s" % [md, pre._mode_plate.shown if pre._mode_plate else {}])
	pre.queue_free()
	await process_frame


func _split_merge() -> void:
	var sd := _sides("splitfront", 5, 3)
	s = BWCombatScreen.new()
	s.configure("res://maps/splitfront.json", sd[0], sd[1], [], 5)
	s.mode_opts = { "divider": "ice" }
	s.autoplay = true
	root.add_child(s)
	var t0 := Time.get_ticks_msec()
	while not s.battle.history.any(func(e): return e.type == "divider_open") and not s.battle.over and Time.get_ticks_msec() - t0 < 240000:
		await _wait(0.2)
	# the screen plays its queue: wait for the open event's banner
	while s._queue.any(func(e): return e.type == "divider_open"):
		await _wait(0.05)
	s.autoplay = false
	_overview(s, Vector2i(9, 7), 24.0, 55.0)
	await _wait(0.5)
	await _shot("mode_split_merge")
	var ev: Array = s.battle.history.filter(func(e): return e.type == "divider_open")
	print("merge: %s round %d" % [str(ev[0]) if not ev.is_empty() else "none", s.battle.cycle])
	s.queue_free()
	await process_frame


func _horde() -> void:
	var sd := _sides("horde", 8, 4)
	s = BWCombatScreen.new()
	s.configure("res://maps/horde.json", sd[0], sd[1], [], 8)
	s.autoplay = true
	root.add_child(s)
	var t0 := Time.get_ticks_msec()
	# a wave rung on the edge: the telegraph shows, the wave not yet landed
	while s.mode_view._tele.is_empty() and not s.battle.over and Time.get_ticks_msec() - t0 < 240000:
		await _wait(0.1)
	s.autoplay = false
	while s._busy:
		await _wait(0.1)
	_overview(s, Vector2i(9, 5), 38.0, 62.0)
	await _wait(0.6)
	await _shot("mode_horde_waves")
	print("horde waves: %s" % [s.mode_view.shown])
	s.autoplay = true
	s._after_events()
	while BWObjectives.escaped(s.battle) == 0 and s.battle.cycle < 7 and not s.battle.over and Time.get_ticks_msec() - t0 < 400000:
		await _wait(0.2)
	s.autoplay = false
	while s._busy:
		await _wait(0.1)
	_overview(s, Vector2i(9, 11), 27.0, 58.0)
	await _wait(0.6)
	await _shot("mode_horde_exit")
	print("horde exit: %s" % [s.mode_view.shown])
	s.queue_free()
	await process_frame

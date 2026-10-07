extends SceneTree
## D327-D333 review renders of the 6v6 modes (needs a window):
##   [SHOTS=<dir>] [RES=1920x1080] godot --path . --resolution 1920x1080 --script res://tools/mode_shots.gd
## mode_split_fire|ice|wind.png  Split Front's opening, the whole map, one per divider element
## mode_split_prebattle.png      the pre-battle: the plate, WEST / EAST FRONT 3 / 3, the divider telegraphed
## mode_split_merge.png          the moment the divider opens (the enemy's break-through or the squad's)
## mode_horde_prebattle.png      the Horde's pre-battle: the plate, the first wave
## horde2_group_move.png         D347: a group turn mid-move, every grunt walking at once
## horde2_fella_flee.png         D349: the Lil Fella running from the horde
## horde2_fella_close.png       the Lil Fella up close: hat, lantern, the tile ring
## horde2_plate.png              the plate (wave n of 4, the Lil Fella's HP), "Horde ×N" in the turn order
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
		n = 8
	var run := _run_at(n, seed_value)
	if md == "horde":
		run.mode_override = { n: "horde" }        # whatever the schedule draws (it is another lane's)
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


## D347-D350 (horde2_*): a group turn mid-move, the Lil Fella fleeing, the plate.
func _horde() -> void:
	var sd := _sides("horde", 8, 4)
	s = BWCombatScreen.new()
	s.configure("res://maps/horde.json", sd[0], sd[1], [], 8)
	s.autoplay = true
	var walking := [[]]
	s.group_walking.connect(func(ids): walking[0] = ids)
	root.add_child(s)
	var t0 := Time.get_ticks_msec()
	# 1. a group turn mid-move: many grunts walking at once
	while walking[0].size() < 5 and not s.battle.over and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
	var c := Vector2.ZERO
	for id in walking[0]:
		var u := s.battle._unit(str(id))
		c += Vector2(u.pos)
	c /= maxf(1.0, walking[0].size())
	_overview(s, Vector2i(roundi(c.x), roundi(c.y) - 2), 24.0, 52.0)
	await _wait(0.45)
	await _shot("horde2_group_move")
	print("horde2 group: %d walking, plays %s" % [walking[0].size(), str(s.group_plays.slice(-1))])
	# 2. the Lil Fella fleeing (its view on the move)
	var lv: Node3D = s._views.get("lil_fella")
	var last: Vector3 = lv.position
	var caught := false
	while not caught and not s.battle.over and Time.get_ticks_msec() - t0 < 600000:
		await process_frame
		if lv.position.distance_to(last) > 0.004 and s.battle.cycle >= 3:
			var lf0 := BWHordeMode.fella(s.battle)
			caught = s.battle.side("enemy").any(func(e): return BWHex.distance(e.pos, lf0.pos) <= 5)
		last = lv.position
	var lf := BWHordeMode.fella(s.battle)
	var nearest: BWUnit = null
	for e in s.battle.side("enemy"):
		if nearest == null or BWHex.distance(e.pos, lf.pos) < BWHex.distance(nearest.pos, lf.pos):
			nearest = e
	var mid: Vector2i = lf.pos if nearest == null else (lf.pos + nearest.pos) / 2
	_overview(s, mid + Vector2i(0, 1), 20.0, 50.0)
	await _wait(0.25)
	await _shot("horde2_fella_flee")
	print("horde2 flee: fella at %s hp %d/%d round %d" % [str(lf.pos), lf.hp, lf.max_hp(), s.battle.cycle])
	# 3. the plate and the turn order, on a quiet frame
	s.autoplay = false
	while s._busy:
		await _wait(0.1)
	_overview(s, lf.pos + Vector2i(0, -3), 30.0, 58.0)
	await _wait(0.6)
	await _shot("horde2_plate")
	print("horde2 plate: %s order %s" % [s.mode_view.shown, s.ui.group_shown])
	_overview(s, lf.pos, 11.0, 24.0, 20.0)
	await _wait(0.5)
	await _shot("horde2_fella_close")
	s.queue_free()
	await process_frame

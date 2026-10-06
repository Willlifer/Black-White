extends SceneTree
## End-of-battle summary review renders (D119–D121), from a real run the AI
## plays on both sides (the campaign sim's loop: top three by level, best
## legal gear, train weapon + rest, auto picks):
##   [SHOTS=<dir>] [SEED=n] godot --path . --script res://tools/summary_shots.gd
## summary_win.png   the results screen after the run's first won fight
## summary_loss.png  the results screen after its first lost fight (the
##                   Giant's, if every ladder fight was won)
## summary_run.png   the end screen after the Giant: the run summary
## Needs a window (real renders, not headless). Renders at 1920x1080
## (canvas_items stretch from the 1600x900 design size; 4K scales the same).
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", out.path_join(name + ".png"))


func _show(node: Control, name: String) -> void:
	root.add_child(node)
	await _wait(1.6)
	await _shot(name)
	node.queue_free()
	await _wait(0.2)


func _go() -> void:
	BWMusic.ensure(root)
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 9001
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = ids[i]; ids[i] = ids[j]; ids[j] = t
	var run := BWRun.start(ids.slice(0, BWRun.SQUAD), seed_value)
	for u in run.squad:
		BWPicks.auto_resolve(u)
	var got_win := false
	var got_loss := false
	var last := {}
	var won := false
	while run.fight <= BWRun.BOSS_FIGHT:
		var n := run.fight
		var deployed := _deploy(run)
		_gear(run, deployed)
		var enemies := run.enemies_for(n)
		run.prepare_for_battle(deployed)
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % run.map_for(n)), run.seed_value * 31 + n)
		b.setup(deployed, enemies, [])
		var guard := 0
		while not b.over and guard < 1500:
			BWAI.take_turn(b)
			guard += 1
		won = b.winner == "player"
		var defeated := enemies.filter(func(e): return not e.alive())
		last = run.after_fight(won, deployed, defeated, enemies, b.history)
		print("fight %d %s: %s" % [n, "won" if won else "lost", last.stats.highlights.map(func(h): return h.text)])
		for u in run.squad:
			u.hp = u.max_hp()
			BWPicks.auto_resolve(u)
		if n >= BWRun.BOSS_FIGHT:
			break
		if won and not got_win:
			got_win = true
			await _results(run, last, "summary_win")
		elif not won and not got_loss:
			got_loss = true
			await _results(run, last, "summary_loss")
		var plan: Array = []
		for u in run.squad:
			plan.append([u.id, "specialize"])      # D127
		run.progress_day(plan)
		for u in run.squad:
			BWPicks.auto_resolve(u)
	if not got_loss:
		await _results(run, last, "summary_loss")
	var e := BWEndScreen.new()
	e.run = run
	e.report = last
	e.text = "The squad stood against the Giant.\nNobody does that." if won else "The Giant wins.\nIt always does."
	await _show(e, "summary_run")
	quit()


func _results(run: BWRun, report: Dictionary, name: String) -> void:
	var s := BWResultsScreen.new()
	s.run = run
	s.report = report
	await _show(s, name)


## The three highest-level units (ties: most HP), as a player would.
func _deploy(run: BWRun) -> Array:
	var s := run.squad.duplicate()
	s.sort_custom(func(a, b): return a.level > b.level or (a.level == b.level and a.max_hp() > b.max_hp()))
	# rotate the third slot every other fight so the bench shows up in the tallies
	var top := s.slice(0, BWRun.DEPLOY)
	if run.fight % 2 == 0 and s.size() > BWRun.DEPLOY:
		top[2] = s[BWRun.DEPLOY + (run.fight / 2) % (s.size() - BWRun.DEPLOY)]
	return top


## Put the best legal loose piece (by stat total) into each weaker slot.
func _gear(run: BWRun, units: Array) -> void:
	for u in units:
		for slot in BWRun.SLOTS:
			var cur: Dictionary = u.equipment.get(slot, {})
			var best: Dictionary = {}
			var best_v := _value(cur)
			for it in run.inventory:
				if str(it.get("slot", "")) != slot or not run.can_equip(u, it):
					continue
				if _value(it) > best_v:
					best = it
					best_v = _value(it)
			if not best.is_empty():
				run.equip(u, best)


func _value(it: Dictionary) -> int:
	var v := 0
	for s in it.get("stats", {}):
		v += int(it.stats[s])
	return v

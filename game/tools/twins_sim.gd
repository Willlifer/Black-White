extends SceneTree
## D259: the Twins alone, fast: a run's first three, levelled and geared to
## fight 7 the way --combat --encounter builds them, AI both sides, against
## BWTwins.build. Prints the win rate, median rounds, which phases fired and
## when the rage came. The whole-run number is campaign_sim's fight 7 row.
##   [RUNS=n] [TWINS=hp,mult] [TRACE=1] godot --headless --path . --script res://tools/twins_sim.gd


func _init() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 24
	if OS.get_environment("TWINS") != "":
		var k := OS.get_environment("TWINS").split(",")
		BWTwins.TWINS_HP = float(k[0])
		if k.size() > 1:
			BWTwins.TWINS_MULT = float(k[1])
	var n := BWRun.TWINS_FIGHT
	var wins := 0
	var rounds: Array = []
	var phases := { "swap": 0, "rage": 0, "rage_denied": 0, "beam_hits": 0, "beam_breaks": 0 }
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	for s in runs:
		if OS.get_environment("ONLY") != "" and s != int(OS.get_environment("ONLY")):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = 7700 + s
		var pick := ids.duplicate()
		for i in range(pick.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t = pick[i]; pick[i] = pick[j]; pick[j] = t
		var run := BWRun.start(pick.slice(0, BWRun.SQUAD), 7700 + s)
		for u in run.squad:
			BWProgression.level_up(u, n - u.level)
			BWPicks.auto_resolve(u)
			for slot in BWRun.ARMOR_SLOTS:
				var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
				u.equipment[slot] = run.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), run.tier_for(n))
			u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
			u.sync_weapon()
		run.fight = n
		var players := run.squad.slice(0, 3)
		run.prepare_for_battle(players)
		var enemies := run.enemies_for(n)
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % run.map_for(n)), run.seed_value * 31 + n)
		b.setup(players, enemies, [])
		var guard := 0
		while not b.over and guard < 2000 and b.cycle <= 60:   # a stalemate past 60 cycles counts as a loss
			BWAI.take_turn(b)
			guard += 1
		if b.winner == "player":
			wins += 1
		rounds.append(b.cycle)
		for e in b.history:
			match str(e.type):
				"phase": phases[str(e.phase)] += 1
				"phase_cancel": phases.rage_denied += 1
				"beam_hit": phases.beam_hits += 1
				"beam_break": phases.beam_breaks += 1
		if OS.get_environment("DUMP") == "1":
			for e in b.history.slice(-60):
				print(JSON.stringify(e).left(220))
			for u in b.units:
				print("%s %s hp %d/%d at %s mv %d" % [u.team, u.name, u.hp, u.max_hp(), u.pos, u.move_range()])
		if OS.get_environment("TRACE") == "1":
			print("run %d: %s in %d, HP %s" % [s, b.winner, b.cycle, enemies.map(func(e): return "%s %d/%d" % [e.name, e.hp, e.max_hp()])])
	rounds.sort()
	print("Twins (HP x%.2f, mult %.2f): win %d%% (%d runs), rounds med %d [%d-%d]  %s" % [BWTwins.TWINS_HP, BWTwins.TWINS_MULT,
		100 * wins / runs, runs, rounds[rounds.size() / 2], rounds[0], rounds[-1], str(phases)])
	quit()

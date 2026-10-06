extends RefCounted
## A whole run, headless: ten fights and the boss, AI playing both sides,
## random downtime choices (D127: one of three each). Proves the run loop holds together end to end
## and prints the growth curve for balance (DECISIONS: open items).


func _play(r: BWRun, n: int, attempt: int = 0) -> Dictionary:
	# a retry also rotates the third slot through the bench: a trio that
	# lost the ranged answer to a kiting archer on the ravine can't win by
	# replaying itself, however many levels it gains
	var deployed: Array = r.squad.slice(0, 2) + [r.squad[2 + attempt % (r.squad.size() - 2)]]
	var enemies := r.enemies_for(n)
	r.prepare_for_battle(deployed)          # learned abilities go live (auto-equip)
	var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % r.map_for(n)), 1000 + n + 7919 * attempt)
	b.setup(deployed, enemies)
	var turns := 0
	while not b.over and turns < 900:
		BWAI.take_turn(b)
		turns += 1
	var defeated := enemies.filter(func(e): return not e.alive())
	var won := b.winner == "player"
	var rep := r.after_fight(won, deployed, defeated, enemies, b.history)
	for u in r.squad:
		u.hp = u.max_hp()
	return { "won": won, "over": b.over, "cycles": b.cycle, "loot": rep.loot.size() }


func test_full_run(t) -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))
	var r := BWRun.start(ids, 4242)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var log: PackedStringArray = []
	var safety := 0
	var attempt := 0
	while r.fight <= BWRun.BOSS_FIGHT and safety < 40:
		safety += 1
		var n := r.fight
		# a retry is a new fight (its own seed): replaying the same seed against
		# the same enemies could only lose the same way (D76: loot rolls moved)
		var res := _play(r, n, attempt)
		attempt = 0 if res.won else attempt + 1
		t.ok(res.over, "fight %d finishes" % n)
		var lv: Array = r.squad.map(func(u): return u.level)
		var top := 0
		for u in r.squad:
			for s in BWUnit.STATS:
				top = maxi(top, u.stat(s))
		log.append("fight %2d %-9s %s in %2d rounds, levels %s, best stat %d, items %d" % [
			n, r.map_for(n), "WON " if res.won else "lost", res.cycles, lv, top, r.inventory.size()])
		if n >= BWRun.BOSS_FIGHT:
			break
		if not res.won:
			continue            # the sim retries a lost fight; the game ends the run
		# downtime: equip anything better, then two random actions each
		for u in r.squad:
			for it in r.inventory.duplicate():
				if it.slot != "main_hand" and not u.equipment.has(it.slot):
					r.equip(u, it)
		var plan: Array = []
		for u in r.squad:
			plan.append([u.id, BWRun.DOWNTIME_CHOICES[rng.randi() % BWRun.DOWNTIME_CHOICES.size()]])
		for line in r.progress_day(plan):
			t.ok(line.ok, line.text)
		for u in r.squad:
			BWPicks.auto_resolve(u)
	t.ok(r.fight >= BWRun.BOSS_FIGHT, "reached the boss (fight %d)" % r.fight)
	for l in log:
		print("    [info] " + l)

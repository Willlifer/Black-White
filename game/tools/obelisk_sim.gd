extends SceneTree
## D144: the fight-4 damage scale and the Obelisks balance.
##   godot --headless --path . --script res://tools/obelisk_sim.gd
## Plays RUNS whole runs (the campaign sim's way: the AI plays your side,
## downtime by POLICY, default mixed) through fights 1-3, then fight 4 (the
## Obelisks) TRIES times on different seeds from the same squad. Prints:
##   the squad at fight 4 (levels, HP, classes), its damage per hit and per
##   swing on enemies and on the stones, damage per round, the enemies' HP and
##   damage, then win rate, rounds, which stone fell, what killed the squad.
## Env (tuning only, the game never reads them): RUNS (12), TRIES (4), POLICY,
## OB_HP (obelisk HP), PULSE_L / PULSE_W (pulse damage), ALL=1 (every policy).

const CampaignSim := preload("res://tools/campaign_sim.gd")


func _init() -> void:
	var runs := _env_int("RUNS", 12)
	var tries := _env_int("TRIES", 4)
	if _env_int("OB_HP", 0) > 0:
		BWObelisk.hp_override = _env_int("OB_HP", 0)
	var po := {}
	if _env_int("PULSE_L", -1) >= 0:
		po["lantern"] = _env_int("PULSE_L", 0)
	if _env_int("PULSE_W", -1) >= 0:
		po["well"] = _env_int("PULSE_W", 0)
	BWObelisk.pulse_override = po
	var pols: Array = CampaignSim.POLICIES.keys() if OS.get_environment("ALL") == "1" \
		else [OS.get_environment("POLICY") if OS.get_environment("POLICY") != "" else "mixed"]
	print("obelisk HP %d, pulses %s" % [BWObelisk.hp_override if BWObelisk.hp_override > 0 else BWObelisk.HP_MAX,
		str(po) if not po.is_empty() else str(BWObelisk.PULSE)])
	for pol in pols:
		_policy(str(pol), runs, tries)
	quit()


func _policy(pol: String, runs: int, tries: int) -> void:
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	var acc := { "fights": 0, "wins": 0, "rounds": [], "levels": [], "hp": [], "enemy_hp": [], "classes": {},
		"hit_enemy": [], "swing_enemy": [], "hit_stone": [], "swing_stone": [], "round_dealt": [],
		"round_stone": [], "enemy_hit": [], "fell": {}, "loss_cause": {}, "pulse_taken": [], "survivors": [],
		"enemy_wiped": 0, "stone_left": [], "f3_rounds": [], "speed": [], "first_stone": [], "acts": {} }
	for s in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + s
		var pick := ids.duplicate()
		for i in range(pick.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t = pick[i]; pick[i] = pick[j]; pick[j] = t
		var run := BWRun.start(pick.slice(0, BWRun.SQUAD), 9000 + s)
		for u in run.squad:
			BWPicks.auto_resolve(u)
		while run.fight < 4:
			var n := run.fight
			var deployed := _deploy(run)
			_gear(run, deployed)
			var enemies := run.enemies_for(n)
			run.prepare_for_battle(deployed)
			var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % run.map_for(n)), run.seed_value * 31 + n)
			b.setup(deployed, enemies, [])
			_play(b)
			if n == 3:
				acc.f3_rounds.append(b.cycle)
			run.after_fight(b.winner == "player", deployed, enemies.filter(func(e): return not e.alive()), enemies, b.history)
			for u in run.squad:
				u.hp = u.max_hp()
				BWPicks.auto_resolve(u)
			var plan: Array = []
			for i in run.squad.size():
				plan.append([run.squad[i].id, CampaignSim.choice_for(pol, i)])
			run.progress_day(plan)
			for u in run.squad:
				BWPicks.auto_resolve(u)
		# fight 4, TRIES seeds from the same squad (state restored between tries)
		var save := run.to_dict()
		for k in tries:
			var r2 := BWRun.from_dict(save)
			var deployed := _deploy(r2)
			_gear(r2, deployed)
			var enemies := r2.enemies_for(4)
			if _env_int("ENEMIES", 0) > 0:
				enemies = enemies.slice(0, _env_int("ENEMIES", 0))
			r2.prepare_for_battle(deployed)
			var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % r2.map_for(4)), r2.seed_value * 31 + 4 + 7919 * k)
			b.setup(deployed, enemies, [])
			for u in deployed:
				acc.levels.append(u.level)
				acc.hp.append(u.max_hp())
				acc.classes[u.weapon_class] = int(acc.classes.get(u.weapon_class, 0)) + 1
				acc.speed.append(u.speed())
			for e in enemies:
				acc.enemy_hp.append(e.max_hp())
			_play(b)
			if OS.get_environment("TRACE") == "1" and s == 0 and k == 0:
				_trace(b)
			_measure(b, acc)
	_report(pol, runs, tries, acc)


func _play(b: BWBattle) -> void:
	var guard := 0
	while not b.over and guard < 2000:
		BWAI.take_turn(b)
		guard += 1


func _measure(b: BWBattle, acc: Dictionary) -> void:
	acc.fights += 1
	if b.winner == "player":
		acc.wins += 1
	acc.rounds.append(b.cycle)
	var team := {}
	for u in b.units:
		team[u.id] = u.team
	var per_round := {}
	var stone_round := {}
	var first := 0
	for e in b.history:
		if e.type in ["attack", "skill"] and team.get(str(e.unit), "") == "player" and int(e.get("strike", 0)) == 0:
			var tgt := str(e.get("target", ""))
			if e.type == "skill" and not (e.get("results", []) as Array).is_empty():
				tgt = str(e.results[0].target)
			var what := "stone" if team.get(tgt, "") == BWObelisk.TEAM else ("enemy" if team.get(tgt, "") == "enemy" else "other")
			acc.acts[what] = int(acc.acts.get(what, 0)) + 1
			if what == "stone" and first == 0:
				first = int(e.cycle)
		var blows: Array = []
		if e.type in ["attack", "counter"]:
			blows.append([str(e.unit), str(e.target), e.result])
		elif e.type in ["skill", "riposte"]:
			for r in e.get("results", []):
				blows.append([str(e.unit), str(r.target), r.result])
		for bl in blows:
			var src := str(team.get(bl[0], ""))
			var dst := str(team.get(bl[1], ""))
			var dmg := int(bl[2].damage)
			if src == "player":
				var key := "stone" if dst == BWObelisk.TEAM else "enemy"
				acc["swing_" + key].append(dmg)
				if bl[2].hit:
					acc["hit_" + key].append(dmg)
				per_round[int(e.cycle)] = int(per_round.get(int(e.cycle), 0)) + dmg
				if key == "stone":
					stone_round[int(e.cycle)] = int(stone_round.get(int(e.cycle), 0)) + dmg
			elif src == "enemy" and bl[2].hit:
				acc.enemy_hit.append(dmg)
		if e.type == "tile_damage" and str(e.get("cause", "")) in ["pulse", "slam"] and team.get(str(e.unit), "") == "player":
			acc.pulse_taken.append(int(e.amount))
		if e.type == "ko" and team.get(str(e.unit), "") == "player":
			var c := str(e.get("cause", "blow"))
			acc.loss_cause[c] = int(acc.loss_cause.get(c, 0)) + 1
	for c in per_round:
		acc.round_dealt.append(per_round[c])
	for c in range(1, b.cycle + 1):
		acc.round_stone.append(int(stone_round.get(c, 0)))
	for o in b.objectives():
		if not o.alive():
			acc.fell[o.name] = int(acc.fell.get(o.name, 0)) + 1
		else:
			acc.stone_left.append(o.hp)
	if b.side("enemy").is_empty():
		acc.enemy_wiped += 1
	acc.first_stone.append(first)
	acc.survivors.append(b.side("player").size())


func _report(pol: String, runs: int, tries: int, a: Dictionary) -> void:
	var out: PackedStringArray = ["POLICY %s: %d runs x %d tries = %d fight-4s" % [pol, runs, tries, a.fights]]
	out.append("  squad at fight 4: level %s, max HP %s, speed %s, classes %s" % [_stat(a.levels), _stat(a.hp), _stat(a.speed), a.classes])
	out.append("  enemies at fight 4: max HP %s; their landed hits %s" % [_stat(a.enemy_hp), _stat(a.enemy_hit)])
	out.append("  player on enemies:  per landed hit %s, per swing %s" % [_stat(a.hit_enemy), _stat(a.swing_enemy)])
	out.append("  player on a stone:  per landed hit %s, per swing %s" % [_stat(a.hit_stone), _stat(a.swing_stone)])
	out.append("  squad damage per round (all targets) %s; on stones per round %s" % [_stat(a.round_dealt), _stat(a.round_stone)])
	out.append("  pulse + slam damage taken per player hit %s, total events %d" % [_stat(a.pulse_taken), a.pulse_taken.size()])
	out.append("  WIN %d%%  rounds %s  stones fell %s  enemy wiped in %d  survivors %s" % [100 * a.wins / maxi(a.fights, 1),
		_stat(a.rounds), a.fell, a.enemy_wiped, _stat(a.survivors)])
	out.append("  standing stones' HP left %s; player KOs by cause %s; fight 3 rounds %s" % [_stat(a.stone_left), a.loss_cause, _stat(a.f3_rounds)])
	out.append("  player actions by target %s; first round a stone was struck %s" % [a.acts, _stat(a.first_stone)])
	print("\n".join(out))


## "median (min-max) mean".
static func _stat(v: Array) -> String:
	if v.is_empty():
		return "-"
	var s := v.duplicate()
	s.sort()
	var tot := 0.0
	for x in s:
		tot += float(x)
	return "%s (%s-%s) avg %.1f" % [str(s[s.size() / 2]), str(s[0]), str(s[-1]), tot / s.size()]


static func _env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v != "" else d


# The campaign sim's deploy and gear habits (tools/campaign_sim.gd).
func _deploy(run: BWRun) -> Array:
	var s := run.squad.duplicate()
	s.sort_custom(func(a, b): return a.level > b.level or (a.level == b.level and a.max_hp() > b.max_hp()))
	return s.slice(0, BWRun.DEPLOY)


func _gear(run: BWRun, units: Array) -> void:
	for u in units:
		for slot in BWRun.SLOTS:
			var cur: Dictionary = u.equipment.get(slot, {})
			var best: Dictionary = {}
			var best_v := _value(cur)
			for it in run.inventory:
				var row := BWData.row("equipment", it.base)
				if (str(row.slot) if not row.is_empty() else "main_hand") != slot or not run.can_equip(u, it):
					continue
				if slot == "main_hand" and str(it.weight) != u.weapon_class and u.expertise_rank(str(it.weight)) < 1:
					continue
				if _value(it) > best_v:
					best = it
					best_v = _value(it)
			if not best.is_empty():
				run.equip(u, best)


func _value(it: Dictionary) -> int:
	var v := 0
	for k in it.get("stats", {}):
		v += int(it.stats[k])
	return v - (0 if not it.is_empty() else 1)


## TRACE=1: the first fight-4, turn by turn (who, where, what at whom, HP).
func _trace(b: BWBattle) -> void:
	var by_id := {}
	for u in b.units:
		by_id[u.id] = u
	for e in b.history:
		match str(e.type):
			"turn":
				print("  c%d turn %s" % [int(e.cycle), e.unit])
			"move":
				print("      move %s %s %s" % [e.unit, str(e.get("kind", "")), str(e.path[-1])])
			"attack":
				print("      %s hits %s for %d (hp %d)" % [e.unit, e.target, int(e.result.damage), int(e.target_hp)])
			"skill":
				var rs: Array = e.get("results", [])
				print("      %s uses %s on %s" % [e.unit, e.skill, rs.map(func(r): return "%s:%d" % [r.target, int(r.result.damage)])])
			"pulse":
				print("      PULSE %s %s %d" % [e.unit, e.kind, int(e.damage)])
			"ko":
				print("      KO %s (%s)" % [e.unit, str(e.get("cause", ""))])
			"battle_end":
				print("  END %s" % e.winner)

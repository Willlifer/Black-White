extends SceneTree
## D341: the castle modes alone, fast (Defend / Storm the Castle, D335-D342).
## A run's squad of six, levelled and geared to fight n the way --combat
## --mode builds them (BWCastle.quick_run), AI on both sides, against the mode's
## own enemies and waves. Prints the win rate, the rounds, how the fights end
## and the AI turn timings (mean / worst ms; the 6v6 budget is ~250 ms worst).
## The whole-run numbers are campaign_sim's fight 8 / 10 rows.
##   [MODE=defend|storm|both] [RUNS=n] [FIGHT=8] [GATE=x] [THRONE=x] [WARDEN=hp,mult]
##   [EMULT=x] [EHP=x] [TRACE=1] godot --headless --path . --script res://tools/castle_sim.gd
## CAMPAIGN=<dir>: instead of the quick squads, replay the real squads that
## campaign_sim SNAPSHOT=<dir> saved before fights 8 and 10 (gear, picks and
## keystones as played), each against the mode (RUNS is ignored).
## MODE=horde (D351, CAMPAIGN only): Stop the Horde on the same squads;
## HORDE="grunt_mult,grunt_hp,elite_mult,fella_pct", WAVES="c:g:e;..." tune it.
## Every mode also prints the headless wall time per fight and take_turn calls.


func _init() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 16
	var fights: Array = Array(OS.get_environment("FIGHT").split(",", false)).map(func(x): return int(x)) if OS.get_environment("FIGHT") != "" else [8, 10]
	var modes: Array = ["defend", "storm"] if OS.get_environment("MODE") in ["", "both"] else [OS.get_environment("MODE")]
	if OS.get_environment("GATE") != "":
		BWCastleDefend.GATE_HP = float(OS.get_environment("GATE"))
		BWCastleStorm.GATE_HP = float(OS.get_environment("GATE"))
	if OS.get_environment("THRONE") != "":
		BWCastleStorm.THRONE_HP = float(OS.get_environment("THRONE"))
	if OS.get_environment("WARDEN") != "":
		var k := OS.get_environment("WARDEN").split(",")
		BWCastleStorm.WARDEN_HP = float(k[0])
		if k.size() > 1:
			BWCastleStorm.WARDEN_MULT = float(k[1])
	if OS.get_environment("HORDE") != "":                  # D351: "grunt_mult,grunt_hp,elite_mult,fella_pct[,waves]"
		var hk := OS.get_environment("HORDE").split(",")
		BWHordeMode.GRUNT_MULT = float(hk[0]); BWHordeMode.GRUNT_HP = float(hk[1])
		BWHordeMode.ELITE_MULT = float(hk[2]); BWHordeMode.FELLA_PCT = float(hk[3])
	if OS.get_environment("WAVES") != "":                  # D351: "c:g:e;c:g:e;..."
		BWHordeMode.WAVES = Array(OS.get_environment("WAVES").split(";")).map(func(w): return Array(w.split(":")).map(func(x): return int(x)))
	if OS.get_environment("EMULT") != "":
		BWCastle.ENEMY_MULT = float(OS.get_environment("EMULT"))
	if OS.get_environment("EHP") != "":
		BWCastle.ENEMY_HP = float(OS.get_environment("EHP"))
	if OS.get_environment("CFIGHT") != "":                 # D357: "storm:9:0.6,defend:7:0.85" (BWCastle.FIGHT_MULT)
		for kv in OS.get_environment("CFIGHT").split(","):
			var p := kv.split(":")
			if not BWCastle.FIGHT_MULT.has(p[0]):
				BWCastle.FIGHT_MULT[p[0]] = {}
			BWCastle.FIGHT_MULT[p[0]][int(p[1])] = float(p[2])
	for mode in modes:
		for n in fights:
			_run(mode, n, runs)
	quit()


func _run(mode: String, n: int, runs: int) -> void:
	var wins := 0
	var rounds: Array = []
	var ends := {}
	var ai_ms: Array = []
	var wall_ms: Array = []                 # D352: headless wall time per fight
	var turns_n: Array = []
	var en_ms: Array = []                   # the enemy's turns only (the game's AI; the squad's is autoplay)
	var phase_round: Array = []
	var snaps: Array = []
	if OS.get_environment("CAMPAIGN") != "":
		var dir := OS.get_environment("CAMPAIGN")
		for f in DirAccess.get_files_at(dir):
			if f.ends_with("_f%d.json" % n):
				snaps.append(dir + "/" + f)
		snaps.sort()
		runs = snaps.size()
		if runs == 0:
			return
	for s in runs:
		var q := BWCastle.quick_run(mode, 7700 + s, n) if snaps.is_empty() else _snap(snaps[s], mode, n)
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % q.map), 7700 * 31 + s * 7 + n)
		b.setup(q.players, q.enemies, [])
		var guard := 0
		var w0 := Time.get_ticks_msec()
		while not b.over and guard < 3000 and b.cycle <= 40:
			var t0 := Time.get_ticks_usec()
			var who := b.current()
			var h0 := b.history.size()
			BWAI.take_turn(b)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			ai_ms.append(ms)
			if who != null and who.team == "enemy":
				en_ms.append(ms)
			if ms > 250.0 and OS.get_environment("SLOW") == "1" and who != null:
				print("  slow %.0f ms: %s %s (%s) %s" % [ms, who.team, who.name, who.weapon_class,
					b.history.slice(h0).filter(func(e): return e.type in ["attack", "skill", "move"]).map(func(e): return str(e.type) + ":" + str(e.get("skill", e.get("key", ""))))])
			guard += 1
		wall_ms.append(Time.get_ticks_msec() - w0)
		turns_n.append(guard)
		if b.winner == "player":
			wins += 1
		rounds.append(b.cycle)
		var why := _why(b, mode)
		ends[why] = int(ends.get(why, 0)) + 1
		for e in b.history:
			if str(e.type) == "castle_breach":
				phase_round.append(int(e.cycle))
		if OS.get_environment("TRACE") == "1":
			print("  run %d: %s in %d (%s) %s" % [s, b.winner, b.cycle, why, BWObjectives.hud_lines(b)])
	rounds.sort()
	ai_ms.sort()
	var mean := 0.0
	for x in ai_ms:
		mean += x
	mean /= maxf(1.0, ai_ms.size())
	phase_round.sort()
	en_ms.sort()
	var em := 0.0
	for x in en_ms:
		em += x
	em /= maxf(1.0, en_ms.size())
	wall_ms.sort()
	turns_n.sort()
	var pr := "" if phase_round.is_empty() else "  gate falls round med %d (%d of %d)" % [phase_round[phase_round.size() / 2], phase_round.size(), runs]
	print("%s fight %d: win %d%% (%d runs), rounds med %d [%d-%d], ends %s, AI turn mean %.0f ms, p95 %.0f, worst %.0f ms (enemy turns: mean %.0f, p95 %.0f, worst %.0f)%s" % [
		mode, n, 100 * wins / runs, runs, rounds[rounds.size() / 2], rounds[0], rounds[-1], str(ends),
		mean, ai_ms[int(ai_ms.size() * 0.95)], ai_ms[-1], em, en_ms[int(en_ms.size() * 0.95)] if not en_ms.is_empty() else 0.0,
		en_ms[-1] if not en_ms.is_empty() else 0.0, pr])
	print("  %s fight %d: wall per fight med %d ms [%d-%d], take_turn calls med %d [%d-%d]" % [mode, n, wall_ms[wall_ms.size() / 2], wall_ms[0], wall_ms[-1],
		turns_n[turns_n.size() / 2], turns_n[0], turns_n[-1]])


## A saved campaign squad (campaign_sim SNAPSHOT) against the mode's enemies.
func _snap(path: String, mode: String, n: int) -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var run := BWRun.from_dict(d.run)
	run.fight = n
	var players: Array = Array(d.deployed).map(func(id): return run.unit(str(id)))
	var room := { "kind": BWRooms.STANDARD, "map": BWRun.MODE_MAPS[mode], "fight": n, "mode": mode, "enemies": [] }
	var enemies := run.enemies_for(n, room)
	run.prepare_for_battle(players)
	return { "map": BWRun.MODE_MAPS[mode], "players": players, "enemies": enemies, "run": run }


func _why(b: BWBattle, mode: String) -> String:
	if not b.over:
		return "stalled"
	if b.side("player").is_empty():
		return "squad down"
	if mode == "horde":                     # D352
		if b.winner == "player":
			return "survived"
		var lf := BWHordeMode.fella(b)
		if lf != null and not lf.alive():
			return "little one down"
		return "?"
	if mode == "defend":
		var g := BWCastle.gate(b)
		if g != null and not g.alive():
			return "gate broke"
		if b.winner == "enemy":
			return "keep reached"
		return "held" if b.objective_state.get("held", false) else "wiped"
	if b.winner == "player":
		var t := BWCastleStorm.throne(b)
		return "throne" if t != null and not t.alive() else "warden"
	return "?"

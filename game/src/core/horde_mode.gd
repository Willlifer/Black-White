class_name BWHordeMode
extends BWObjectiveMode
## D331-D333: STOP THE HORDE, one of the fixed 6v6s at fights 8 and 10
## (D325). The squad holds the road in front of an EXIT (maps/horde.json: the
## whole south row). Horde grunts (the D208 encounter's grunts) come in WAVES
## from the north edge (BWObjectives' wave spawner: each wave is telegraphed
## on its hexes a round before it lands) and walk for the exit, striking only
## what stands in their way. Later waves bring ELITES: ordinary roster
## enemies on the fight's curve, who hunt the squad.
##   Lose: ESCAPE_LIMIT enemies reach the exit, or the squad falls.
##   Win:  every wave has landed and no enemy is left standing.
## The map seeds two water channels and grass for the area combos
## (electrified pools, Overheat, squalls, Vortex).

const TITLE := "Stop the Horde"
## [cycle it lands, grunts, elites] per wave (D333 tuning, campaign_sim).
static var WAVES := [[1, 5, 0], [3, 6, 0], [5, 6, 1], [7, 7, 2]]
static var ESCAPE_LIMIT := 8
## Grunt build: base stats x GRUNT_MULT on the encounter build (the curve
## held near 1), HP GRUNT_HP of their D137 HP. Elites: the fight's curve x ELITE_MULT.
static var GRUNT_MULT := 1.0
static var GRUNT_HP := 0.42
static var ELITE_MULT := 1.0


func title() -> String:
	return TITLE


func objective_text(b: BWBattle) -> String:
	return "Hold the road: %d waves are coming. Lose if %d reach the exit." % [
		total_waves(b), BWObjectives.escape_limit(b)]


## Every unit of the fight's waves, scaled to the squad's level now (grunts)
## and to the fight's curve (elites); each carries meta "wave" (1-based).
static func build(run: BWRun, n: int) -> Array:
	var b := BWRooms.enemy_build(n, BWRooms.STANDARD)
	b.mult = clampf(BWRun.enemy_curve(n).mult, BWEncounters.CURVE_MIN, BWEncounters.CURVE_MAX)
	var lvl := run.squad_level()
	var tier := run.tier_for(int(b.stage))
	var ranks: Array = BWRun.ENEMY_RANKS[tier]
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("horde-mode|%d|%d" % [run.seed_value, n])
	var elites := 0
	for w in WAVES:
		elites += int(w[2])
	var elite_units: Array = []
	if elites > 0:
		var ids := BWRooms._draw_ids(run, n, [], false, elites)
		elite_units = run._enemies_for(n, { "kind": BWRooms.STANDARD, "map": "horde", "enemies": ids, "fight": n })
		if ELITE_MULT != 1.0:
			for u in elite_units:
				BWRun.scale_stats(u, ELITE_MULT)
	var out: Array = []
	var gi := 0
	var ei := 0
	for wi in WAVES.size():
		var w: Array = WAVES[wi]
		for k in int(w[1]):
			gi += 1
			var wm: String = BWEncounters.GRUNT_WEAPONS[erng.randi() % BWEncounters.GRUNT_WEAPONS.size()]
			var u := BWEncounters._unit(run, n, "hgrunt%d" % gi, "Grunt %d" % gi, wm, "", lvl, tier, ranks, b, GRUNT_MULT, GRUNT_HP, erng)
			u.encounter = "grunt"
			u.cosmetics = { "hair_style": "buzzed", "top": "tshirt", "bottom": "sweatpants", "clothing_shade": "mid", "voice_pitch": 0.9 }
			u.set_meta("wave", wi + 1)
			out.append(u)
		for k in int(w[2]):
			if ei < elite_units.size():
				var e: BWUnit = elite_units[ei]
				ei += 1
				e.set_meta("wave", wi + 1)
				out.append(e)
	return out


static func wave_of(u: BWUnit) -> int:
	return int(u.get_meta("wave", 1)) if u.has_meta("wave") else 1


func setup(b: BWBattle) -> void:
	var by_wave := {}
	for u in b.units:
		if u.team == "enemy" and not BWObjective.is_object(u):
			var k := wave_of(u)
			if not by_wave.has(k):
				by_wave[k] = []
			by_wave[k].append(u)
	var ks: Array = by_wave.keys()
	ks.sort()
	var edge := BWObjectives.spawn_edge(b)
	for k in ks:
		if int(k) <= 1:
			continue
		var cyc := int(WAVES[mini(int(k) - 1, WAVES.size() - 1)][0])
		BWObjectives.schedule_wave(b, cyc, by_wave[k], _spread(b, edge, (by_wave[k] as Array).size(), int(k)))
	if BWObjectives.exit_hexes(b).is_empty():
		var ex: Array = []
		for q in b.board.cols:
			if b.board.is_passable(Vector2i(q, b.board.rows - 1)):
				ex.append(Vector2i(q, b.board.rows - 1))
		BWObjectives.set_exit(b, ex, ESCAPE_LIMIT)
	b.objective_state["horde"] = { "waves": ks.size(), "first": by_wave.get(1, []).size() }


## `n` hexes spread along the spawn edge's far row, shifted per wave.
static func _spread(b: BWBattle, edge: Array, n: int, wave: int) -> Array:
	var row: Array = edge.filter(func(h): return h.y == 0 and b.board.is_passable(h))
	if row.is_empty():
		row = edge.duplicate()
	row.sort()
	var out: Array = []
	if row.is_empty():
		return out
	for i in n:
		var t := (float(i) + 0.5 + 0.37 * float(wave % 3)) / float(n)
		out.append(row[clampi(int(t * row.size()), 0, row.size() - 1)])
	return out


## Waves in all: the first on the board plus the scheduled ones.
static func total_waves(b: BWBattle) -> int:
	return int(b.objective_state.get("horde", {}).get("waves", 1))


## Waves landed so far (the first counts from the start).
static func landed(b: BWBattle) -> int:
	return 1 + BWObjectives.waves_spawned(b) if int(b.objective_state.get("horde", {}).get("first", 0)) > 0 else BWObjectives.waves_spawned(b)


func verdict(b: BWBattle) -> String:
	if BWObjectives.escaped(b) >= BWObjectives.escape_limit(b) and BWObjectives.escape_limit(b) > 0:
		return "enemy"
	if b.side("player").is_empty():
		return "enemy"
	if BWObjectives.waves_left(b) == 0 and b.side("enemy").is_empty():
		return "player"
	return "-"


static func exit_field(b: BWBattle) -> Dictionary:
	if b.has_meta("_exit_field"):
		return b.get_meta("_exit_field")
	var f := BWObjectives.walk_field(b, BWObjectives.exit_hexes(b))
	b.set_meta("_exit_field", f)
	return f


static func is_grunt(u: BWUnit) -> bool:
	return u.encounter == "grunt" and u.team == "enemy"


func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	if is_grunt(u):
		_grunt_turn(b, u)
		return true
	if u.team == "player":
		_intercept(b, u)
	return false


## A grunt walks for the exit: the reachable stop nearest it (walking cost);
## then it strikes a foe in reach. Penned in (no progress): it fights its way.
static func _grunt_turn(b: BWBattle, u: BWUnit) -> void:
	var field := exit_field(b)
	var here := int(field.get(u.pos, 1 << 20))
	var reach := b.reachable(u)
	var best := u.pos
	var best_v := here
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop:
			continue
		var v := int(field.get(h, 1 << 20))
		if v < best_v:
			best_v = v
			best = h
	if best != u.pos:
		b.move(u, best)
	elif BWAI._best_target(b, u, u.pos).is_empty():
		var dest := BWAI._best_hex(b, u)                 # penned in: step to a blow
		if dest != u.pos:
			b.move(u, dest)
	if not b.over and u.alive():
		var t := BWAI._best_target(b, u, u.pos)
		if not t.is_empty():
			b.attack(u, t.target)
	if not b.over:
		b.end_turn()


## The squad's AI with nobody in reach: close on the enemy nearest the exit,
## not the nearest one (a defender, not a chaser).
static func _intercept(b: BWBattle, u: BWUnit) -> void:
	if not b.can_move(u) or not BWAI._best_target(b, u, u.pos).is_empty():
		return
	var dest := BWAI._best_hex(b, u)
	if dest != u.pos and not BWAI._best_target(b, u, dest).is_empty():
		b.move(u, dest)
		return
	var field := exit_field(b)
	var runner: BWUnit = null
	for f in b.side("enemy"):
		if runner == null or int(field.get(f.pos, 999)) < int(field.get(runner.pos, 999)):
			runner = f
	if runner == null:
		return
	var reach := b.reachable(u)
	var best := u.pos
	var best_d := BWHex.distance(u.pos, runner.pos) * 2 + int(field.get(u.pos, 0))
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop:
			continue
		var d := BWHex.distance(h, runner.pos) * 2 + int(field.get(h, 0))   # stay between it and the exit
		if d < best_d:
			best_d = d
			best = h
	if best != u.pos:
		b.move(u, best)


## The squad weighs a grunt by how close it is to the exit (up to x2 at the door).
func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	if u.team != "player" or f.team != "enemy":
		return 1.0
	var d := int(exit_field(b).get(f.pos, 99))
	return 1.0 + maxf(0.0, 8.0 - float(d)) / 8.0


func hud_lines(b: BWBattle) -> Array:
	var out: Array = []
	var nw := BWObjectives.next_wave(b)
	var wl := "Wave %d of %d" % [landed(b), total_waves(b)]
	if not nw.is_empty():
		var in_r := int(nw.cycle) - b.cycle
		wl += "  ·  next in %d round%s" % [in_r, "" if in_r == 1 else "s"] if in_r > 0 else "  ·  next now"
	else:
		wl += "  ·  last wave"
	out.append(wl)
	out.append("Escaped %d / %d" % [BWObjectives.escaped(b), BWObjectives.escape_limit(b)])
	return out

class_name BWHordeMode
extends BWObjectiveMode
## D331 / D347-D352: STOP THE HORDE, one of the fixed 6v6s at fights 8 and 10
## (D325). Horde grunts (the D208 encounter's grunts) come in WAVES from the
## north edge (BWObjectives' wave spawner: each wave is telegraphed on its
## hexes a round before it lands) and hunt the LIL FELLA (BWLilFella, D348):
## a little neutral NPC with HP_PCT of the squad's best max HP that the
## squad can't hurt, who flees on its own turn. Grunts walk for it and strike
## it, or whoever stands in their way. Later waves bring ELITES: ordinary
## roster enemies on the fight's curve, who hunt the squad (and the little one).
## D347: every grunt acts in ONE GROUP TURN ("Horde ×N" in the turn order):
## resolved one by one, nearest the Lil Fella first, played back together.
##   Lose: the Lil Fella falls, or the squad does.
##   Win:  every wave has landed and no enemy is left standing.
## D349 replaced the exit and its escape counter (D331).

const TITLE := "Stop the Horde"
const GROUP := "horde"
## [cycle it lands, grunts, elites] per wave (D351 tuning, castle_sim MODE=horde).
static var WAVES := [[1, 4, 0], [2, 4, 0], [4, 4, 1], [5, 4, 1]]
## Grunt build: base stats x GRUNT_MULT on the encounter build (the curve
## held near 1), HP GRUNT_HP of their D137 HP. Elites: the fight's curve x ELITE_MULT.
static var GRUNT_MULT := 0.9
static var GRUNT_HP := 0.42
static var ELITE_MULT := 1.15
## The Lil Fella's HP as a share of the squad's highest max HP (D348: 0.5).
static var FELLA_PCT := BWLilFella.HP_PCT
## Elites weigh a blow on the Lil Fella this much more (grunts always go for it).
const ELITE_FELLA_WEIGHT := 1.5


func title() -> String:
	return TITLE


func objective_text(b: BWBattle) -> String:
	return "Keep the little one alive: %d waves are coming, and they want the Lil Fella." % total_waves(b)


## Every unit of the fight's waves, scaled to the squad's level now (grunts)
## and to the fight's curve (elites); each carries meta "wave" (1-based).
## Grunts share the group turn (D347).
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
			u.group_turn = GROUP
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
			if u.encounter == "grunt":
				u.group_turn = GROUP                  # D347 (a unit built elsewhere, e.g. a test)
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
	var squad := b.side("player")
	var lf := BWLilFella.make_for(squad, fella_start(b))
	if FELLA_PCT != BWLilFella.HP_PCT:                       # tuning only (castle_sim FELLA=)
		var top := 0
		for p in squad:
			top = maxi(top, p.max_hp())
		lf.hp_cap = maxi(1, int(round(top * FELLA_PCT)))
		lf.hp = lf.hp_cap
	BWObjectives.place(b, lf)
	b.objective_state["horde"] = { "waves": ks.size(), "first": by_wave.get(1, []).size(), "fella": lf.id }


## D348: where the Lil Fella starts: behind the squad (a row south of its
## centre), the free passable hex nearest that.
static func fella_start(b: BWBattle) -> Vector2i:
	var squad := b.side("player")
	var c := Vector2.ZERO
	for p in squad:
		c += Vector2(p.pos)
	var want := Vector2i(b.board.cols / 2, b.board.rows - 1)
	if not squad.is_empty():
		c /= squad.size()
		want = Vector2i(roundi(c.x), mini(roundi(c.y) + 1, b.board.rows - 1))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 20
	for r in b.board.rows:
		for q in b.board.cols:
			var h := Vector2i(q, r)
			if not b.board.is_passable(h) or b.board.blocked(h) or b.unit_at(h) != null:
				continue
			var d := BWHex.distance(h, want)
			if d < best_d:
				best_d = d
				best = h
	return best


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


## The Lil Fella (standing or fallen); null off the mode.
static func fella(b: BWBattle) -> BWLilFella:
	for o in BWObjectives.objects(b, BWLilFella.TAG):
		if o is BWLilFella:
			return o
	return null


func verdict(b: BWBattle) -> String:
	var f := fella(b)
	if f != null and not f.alive():
		return "enemy"
	if b.side("player").is_empty():
		return "enemy"
	if BWObjectives.waves_left(b) == 0 and b.side("enemy").is_empty():
		return "player"
	return "-"


static func is_grunt(u: BWUnit) -> bool:
	return u.encounter == "grunt" and u.team == "enemy"


## Walking cost from every hex to the Lil Fella (units ignored), cached per
## its hex and the round (the board's blockers change with the ticks).
static func fella_field(b: BWBattle) -> Dictionary:
	var f := fella(b)
	if f == null:
		return {}
	var key := "%s|%d|%d" % [str(f.pos), b.cycle, b.tiles.pillars.size()]
	if b.has_meta("_fella_field_key") and str(b.get_meta("_fella_field_key")) == key:
		return b.get_meta("_fella_field")
	var fd := BWObjectives.walk_field(b, [f.pos])
	b.set_meta("_fella_field_key", key)
	b.set_meta("_fella_field", fd)
	return fd


## D347: grunts resolve nearest the Lil Fella first (walking cost), ties by id.
func group_order(b: BWBattle, u: BWUnit) -> float:
	return float(int(fella_field(b).get(u.pos, 999)))


func group_label(_b: BWBattle, key: String) -> String:
	return "Horde" if key == GROUP else ""


func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	if u is BWLilFella:
		_fella_turn(b, u)
		return true
	if is_grunt(u):
		_grunt_turn(b, u)
		return true
	if u.team == "player":
		_intercept(b, u)
	return false


## D350: a grunt goes for the Lil Fella: a reachable stop it can strike the
## little one from (the cheapest), else the stop nearest it (walking cost);
## then it strikes the Lil Fella if in reach, else whoever is (a squad unit in
## its way). Penned in with nothing to hit: it steps toward a blow.
static func _grunt_turn(b: BWBattle, u: BWUnit) -> void:
	var f := fella(b)
	var reach := b.reachable(u)
	var keys := reach.keys()
	keys.sort()
	if f != null and f.alive():
		var strike := BWBattle.NOWHERE
		var sc := 1 << 20
		for h in keys:
			if reach[h].stop and int(reach[h].cost) < sc and b.in_range(u, f, h):
				sc = int(reach[h].cost)
				strike = h
		if strike != BWBattle.NOWHERE:
			if strike != u.pos:
				b.move(u, strike)
		else:
			var field := fella_field(b)
			var best := u.pos
			var best_v := int(field.get(u.pos, 1 << 20))
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
				var dest := BWAI._best_hex(b, u)             # penned in: step to a blow
				if dest != u.pos:
					b.move(u, dest)
	elif BWAI._best_target(b, u, u.pos).is_empty():
		var d2 := BWAI._best_hex(b, u)
		if d2 != u.pos:
			b.move(u, d2)
	if not b.over and u.alive():
		if f != null and f.alive() and b.in_range(u, f):
			b.attack(u, f)
		else:
			var t := BWAI._best_target(b, u, u.pos)
			if not t.is_empty():
				b.attack(u, t.target)
	if not b.over:
		b.end_turn()


## D349: may the Lil Fella stand on `h`? Never on a hazard: fire, a dark 3
## drain, a live shock field, a fuse (whoever laid it: it can't read the
## source). (D397: glaze no longer slides it, so ice is fine.)
static func hazard(b: BWBattle, h: Vector2i, entry: Dictionary = {}) -> bool:
	var st := b.tiles.standing(h)
	if float(st.fire) > 0.0 or float(st.drain) > 0.0 or b.tiles.crossing_pct(h) > 0.0:
		return true
	if b.tiles.shock.has(h) or str(b.tiles.at(h).get("marker", "")) == "fuse":
		return true
	return false


## D349: the Lil Fella's turn: it runs from the nearest grunts to the safest
## reachable hex: far from the enemy (and out of their next reach), close to
## the squad, off the map's edge where it can be; never onto or across a
## hazard. Bounded by the map (BWBattle.reachable). Ties: stay, then hex order.
static func _fella_turn(b: BWBattle, u: BWUnit) -> void:
	if b.can_move(u):
		var reach := b.reachable(u)
		var keys := reach.keys()
		keys.sort()
		var best := u.pos
		var best_s := fella_score(b, u, u.pos)
		for h in keys:
			if h == u.pos or not reach[h].stop or not b.board.fits(h, 0) or hazard(b, h, reach[h]):
				continue
			var path := BWBoard.path_to(reach, h)
			if path.slice(1).any(func(p): return hazard(b, p)):
				continue
			var s := fella_score(b, u, h) - float(reach[h].cost) * 0.01
			if s > best_s:
				best_s = s
				best = h
		if best != u.pos:
			b.move(u, best)
	if not b.over:
		b.end_turn()


## Higher is safer: 2 a hex from the nearest enemy (to 8), -3 per enemy that
## could reach and strike it there next turn, -1 a hex past the nearest squad
## unit's side, -0.7 on the map's edge.
static func fella_score(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	var dmin := 99
	var threat := 0
	for e in b.side("enemy"):
		var d := BWHex.distance(h, e.pos)
		dmin = mini(dmin, d)
		if d <= e.move_range() + b.weapon_range(e):
			threat += 1
	var pmin := 0
	var first := true
	for p in b.side("player"):
		var d := BWHex.distance(h, p.pos)
		pmin = d if first else mini(pmin, d)
		first = false
	var edge := h.x == 0 or h.y == 0 or h.x == b.board.cols - 1 or h.y == b.board.rows - 1
	return 2.0 * float(mini(dmin, 8)) - 3.0 * float(threat) - float(maxi(pmin - 1, 0)) - (0.7 if edge else 0.0)


## The squad's AI with nobody in reach: close on the enemy nearest the Lil
## Fella, keeping between them (a bodyguard, not a chaser).
static func _intercept(b: BWBattle, u: BWUnit) -> void:
	if not b.can_move(u) or not BWAI._best_target(b, u, u.pos).is_empty():
		return
	var dest := BWAI._best_hex(b, u)
	if dest != u.pos and not BWAI._best_target(b, u, dest).is_empty():
		b.move(u, dest)
		return
	var field := fella_field(b)
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
		var d := BWHex.distance(h, runner.pos) * 2 + int(field.get(h, 0))   # stay between it and the little one
		if d < best_d:
			best_d = d
			best = h
	if best != u.pos:
		b.move(u, best)


## The squad weighs an enemy by how close it is to the Lil Fella (up to x2
## beside it); elites weigh the little one up.
func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	if u.team == "enemy" and f is BWLilFella:
		return ELITE_FELLA_WEIGHT
	if u.team != "player" or f.team != "enemy":
		return 1.0
	var d := int(fella_field(b).get(f.pos, 99))
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
	var f := fella(b)
	if f != null:
		out.append("Lil Fella  %d / %d" % [f.hp, f.max_hp()] if f.alive() else "Lil Fella  DOWN")
	return out

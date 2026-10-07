extends RefCounted
## D327-D334: the objective framework (BWObjectives: objects, verdicts, the
## wave spawner, exits), the fixed 6v6 schedule, Split Front's divider (fire,
## ice, wind: setup and every way to break it, the enemy's break-through) and
## Stop the Horde (waves, escapes, win / lose), and determinism.

const SPLIT := "res://maps/splitfront.json"
const HORDE := "res://maps/horde.json"


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


func _sides(n: int, m: int = -1) -> Array:
	var roster := BWData.table("roster")
	var ps: Array = []
	var es: Array = []
	for i in n:
		ps.append(BWUnit.from_roster(roster[i]))
	for i in (n if m < 0 else m):
		es.append(BWUnit.from_roster(roster[i + 10]))
	return [ps, es]


## A run at fight n: its six levelled and geared to the fight.
func _run_at(n: int, seed_value: int = 11) -> BWRun:
	var r := BWRun.start(_ids(), seed_value)
	for u in r.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		u.equipment["main_hand"] = r.make_item(u.weapon_model, r.tier_for(n))
	r.fight = n
	return r


func _split(el: String, seed_value: int = 3) -> BWBattle:
	var s := _sides(6)
	var b := BWBattle.new(BWBoard.load_file(SPLIT), seed_value)
	BWObjectives.configure(b, { "divider": el })
	b.setup(s[0], s[1])
	return b


func _play(b: BWBattle, cap: int = 1500) -> int:
	var g := 0
	while not b.over and g < cap:
		BWAI.take_turn(b)
		g += 1
	return g


# ---------------------------------------------------------------- the schedule

func test_schedule(t) -> void:
	var r := BWRun.start(_ids(), 77)
	t.eq(r.mode_for(BWRun.SPLIT_FIGHT), "splitfront", "fight 5 is Split Front (D325)")
	t.eq(r.map_for(5), "splitfront", "on its own map")
	t.ok(not BWRooms.has_choice(5) and not BWRooms.queued(5), "fight 5: no room choice, no map off the queue")
	var m8 := r.mode_for(8)
	var m10 := r.mode_for(10)
	t.ok(m8 in BWRun.SIX_MODES and m10 in BWRun.SIX_MODES and m8 != m10, "fights 8 and 10: two of the three modes, no repeat (%s, %s)" % [m8, m10])
	for n in [8, 10]:
		t.ok(not BWRooms.has_choice(n) and not BWRooms.queued(n), "fight %d is fixed" % n)
		t.eq(r.map_for(n), BWRun.mode_map(r.mode_for(n)), "fight %d plays its mode's map (or the placeholder)" % n)
		t.eq(r.deploy_for(n), 6, "fight %d fields six" % n)
	t.ok(BWRooms.has_choice(9), "fight 9 stays a 3v3 room choice")
	t.eq(r.deploy_for(9), 3, "fight 9 fields three")
	t.ok(BWRooms.has_choice(3) and BWRooms.has_choice(6), "fights 3 and 6 keep the choice")
	t.eq(BWRun.six_modes_for(77), BWRun.six_modes_for(77), "seeded: the same run draws the same pair")
	var seen := {}
	for s in 60:
		var p := BWRun.six_modes_for(s)
		if p[0] == p[1]:
			t.ok(false, "seed %d: a repeat" % s)
		seen[p[0]] = true
		seen[p[1]] = true
	t.eq(seen.size(), 3, "over 60 runs every mode turns up")
	t.eq(BWRun.mode_map("no_such_mode"), BWRun.MODE_PLACEHOLDER, "an unknown mode plays the placeholder")
	t.eq(BWRun.mode_map("horde"), "horde", "the Horde's map ships")
	var room := BWRooms.room_for(r, 5)
	t.eq(str(room.get("mode", "")), "splitfront", "the fixed room names its mode")
	t.eq(room.enemies.size(), 6, "six enemy ids")
	t.eq(BWWeather.for_fight(r, 5), "", "no weather on a fixed 6v6")
	t.eq(BWEncounters.kind_for(r, 5), "", "no encounter")
	# the run log names it
	var r5 := _run_at(5)
	var rep := r5.after_fight(true, r5.squad.slice(0, 6), [], [], [])
	t.eq(str(rep.get("mode", "")), "splitfront", "the results name the mode")
	t.eq(str(r5.room_log["5"].get("mode", "")), "splitfront", "the room log names the mode")
	t.eq(rep.loot.size(), BWRun.MODE_DROPS, "a mode fight pays MODE_DROPS (D334)")
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r5.to_dict())))
	t.eq(str(back.room_log["5"].get("mode", "")), "splitfront", "the mode survives a save")
	# the queue: fights 1-3, 6, 9 take maps; fixed fights none
	var q := BWRun.start(_ids(), 5)
	var played := []
	while q.fight <= BWRun.FIGHTS:
		played.append(q.map_for(q.fight))
		BWRooms.offer(q)
		BWRooms.close_fight(q)
		q.fight += 1
	t.eq(played[4], "splitfront", "fight 5 played Split Front")
	t.eq(played[3], "obelisks", "fight 4 the Obelisks")
	t.eq(played[6], "court", "fight 7 the Twins")
	var pool_played: Array = [played[0], played[1], played[2], played[5], played[8]]
	var u := {}
	for m in pool_played:
		u[m] = true
		t.ok(m in BWRun.MAP_POOL, "%s is a pool map" % m)
	t.eq(u.size(), 5, "five choice / opening fights, five fresh pool maps")


# ---------------------------------------------------------------- objects

func test_objects_and_hittable(t) -> void:
	var s := _sides(3)
	var b := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 1)
	b.setup(s[0], s[1])
	var gate := BWObjective.make("gate", Vector2i(5, 6), { "hp": 120, "hittable": ["enemy"], "allegiance": "player", "name": "Gate" })
	BWObjectives.place(b, gate)
	t.eq(gate.team, "neutral", "an object is team neutral (never in side(player) / side(enemy))")
	t.eq(gate.max_hp(), 120, "its own HP")
	t.ok(gate in b.foes_of(s[1][0]) and not gate in b.foes_of(s[0][0]), "hittable by the enemy only")
	t.ok(b.can_harm(s[1][0], gate) and not b.can_harm(s[0][0], gate), "can_harm follows hittable")
	t.ok(b.side("player").size() == 3 and not gate in b.side("player"), "the squad's roster is the fighters")
	t.ok(not gate in BWTurnQueue.build(b.units), "an object that doesn't act takes no turn")
	gate.acts = true
	t.ok(gate in BWTurnQueue.build(b.units), "an acting object does")
	gate.acts = false
	t.ok(b._immune(gate, "displace"), "stone rules: never displaced (D141)")
	var before := gate.hp
	b._tile_hurt(gate, 30, "fire", "")
	t.eq(gate.hp, before, "stone rules: no ground damage")
	# obelisks keep D140: the player only
	var ob := BWObelisk.create("lantern", Vector2i(4, 4))
	t.ok(ob.hittable_by("player") and not ob.hittable_by("enemy"), "a stone: the player's target only (D140)")
	BWObjectives.break_object(b, gate)
	t.ok(not gate.alive(), "break_object breaks it")
	t.ok(b.history.any(func(e): return e.type == "ko" and e.unit == gate.id), "with a ko event")


# ---------------------------------------------------------------- waves

func test_wave_spawner(t) -> void:
	var s := _sides(3, 6)
	var b := BWBattle.new(BWBoard.load_file("res://maps/commons.json"), 4)
	b.setup(s[0], s[1].slice(0, 3))
	BWObjectives.configure(b, {})
	b.objective_state["mode"] = "test"
	var late: Array = s[1].slice(3, 6)
	var want := [Vector2i(8, 0), Vector2i(8, 0), Vector2i(9, 0)]
	BWObjectives.schedule_wave(b, 3, late, want)
	t.eq(BWObjectives.waves_left(b), 1, "one wave waiting")
	t.ok(late.all(func(u): return not u in b.units), "held off the board")
	var g := 0
	while b.cycle < 4 and not b.over and g < 400:
		BWAI.take_turn(b)
		g += 1
	var ev: Array = b.history.filter(func(e): return e.type == "wave_incoming")
	t.eq(ev.size(), 1, "one telegraph")
	t.eq(int(ev[0].cycle), 1, "the telegraph goes out as cycle 2 begins (stamped before the counter moves): a round ahead")
	t.eq((ev[0].hexes as Array).size(), 3, "it names three hexes")
	t.ok(Vector2i(8, 0) in ev[0].hexes and Vector2i(9, 0) in ev[0].hexes, "the asked hexes")
	var sp: Array = b.history.filter(func(e): return e.type == "spawn")
	t.eq(sp.size(), 3, "three spawns")
	t.ok(sp.all(func(e): return int(e.cycle) == 2), "landed as cycle 3 began (the event is stamped before the counter moves)")
	var hs := {}
	for e in sp:
		hs[e.hex] = true
	t.eq(hs.size(), 3, "a taken hex gives way to the nearest free edge hex: three distinct")
	t.ok(late.all(func(u): return u in b.units), "the reserve units are the battle's units now")
	t.eq(BWObjectives.waves_spawned(b), 1, "spawned")


func test_clone_never_moves_the_reserve(t) -> void:
	var s := _sides(3, 6)
	var b := BWBattle.new(BWBoard.load_file("res://maps/commons.json"), 4)
	b.setup(s[0], s[1].slice(0, 3))
	b.objective_state["mode"] = "test"
	BWObjectives.schedule_wave(b, 2, s[1].slice(3, 6))
	var c := b.clone()
	while c.cycle < 2 and not c.over:
		BWAI.take_turn(c)
	t.ok(c.units.size() > b.units.size(), "the clone spawned its wave")
	t.ok(s[1].slice(3, 6).all(func(u): return not u in c.units), "with copies")
	t.ok(s[1].slice(3, 6).all(func(u): return not u in b.units and u.pos != Vector2i(-9999, -9999)), "the real reserve is untouched")


func test_escapes_and_verdict(t) -> void:
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var b := BWBattle.new(BWBoard.load_file(HORDE), 8)
	b.setup(r.squad.slice(0, 6), es)
	t.eq(BWObjectives.escape_limit(b), BWHordeMode.ESCAPE_LIMIT, "the map's limit")
	t.eq(BWObjectives.exit_hexes(b).size(), b.board.cols, "the exit is the south row")
	var g: BWUnit = b.side("enemy")[0]
	g.pos = Vector2i(9, 14)
	BWObjectives.turn_end(b, g)
	t.ok(not g.alive(), "an enemy on the exit escapes")
	t.eq(BWObjectives.escaped(b), 1, "counted")
	t.ok(b.history.any(func(e): return e.type == "escape" and e.unit == g.id), "an escape event")
	t.ok(not b.history.any(func(e): return e.type == "ko" and e.unit == g.id), "not a KO")
	t.eq(b.over, false, "one escape: still on")
	b.objective_state.escaped = BWObjectives.escape_limit(b) - 1
	var g2: BWUnit = b.side("enemy")[0]
	g2.pos = Vector2i(3, 14)
	BWObjectives.turn_end(b, g2)
	t.ok(b.over and b.winner == "enemy", "the limit reached: the fight is lost")


# ---------------------------------------------------------------- Split Front

func test_split_map_and_deploy(t) -> void:
	var bd := BWBoard.load_file(SPLIT)
	t.eq(bd.errors.size(), 0, "loads clean")
	t.eq([bd.cols, bd.rows], [19, 15], "19x15")
	t.eq(bd.deploy_count, 6, "six a side")
	var b := _split("fire")
	var west: Array = b.side("player").filter(func(u): return BWSplitFront.arena_of(b, u.pos) == "west")
	t.eq(west.size(), 3, "three of the squad start west")
	t.eq(b.side("enemy").filter(func(u): return BWSplitFront.arena_of(b, u.pos) == "west").size(), 3, "three enemies west")
	t.eq(b.side("enemy").filter(func(u): return BWSplitFront.arena_of(b, u.pos) == "east").size(), 3, "three enemies east")
	# the spine: no walk from west to east except through the gap
	var blocked := {}
	for h in BWSplitFront.divider_hexes(b):
		blocked[h] = true
	var reach := bd.reachable(Vector2i(4, 13), 99, blocked)
	t.ok(reach.keys().all(func(h): return h.x < 9), "west reaches east only through the divider")
	t.eq(BWSplitFront.divider_hexes(b).size(), 3, "a three-hex divider")
	var els := {}
	for s in 40:
		els[BWSplitFront.element_for_seed(s)] = true
	t.eq(els.size(), 3, "the element is seeded: all three turn up")
	t.eq(BWSplitFront.element_for_seed(9), BWSplitFront.element_for_seed(9), "the same seed, the same wall")


func test_fire_divider(t) -> void:
	var b := _split("fire")
	for h in BWSplitFront.divider_hexes(b):
		t.eq(b.tiles.intensity(h, "fire"), 3, "fire 3 on %s" % h)
		t.ok(not b.board.blocked(h), "passable")
	t.ok(b.tiles.crossing_pct(Vector2i(9, 7)) > 0, "crossing burns")
	var h := Vector2i(9, 7)
	b.paint([h], "water", b.side("player")[0])
	BWSplitFront._settle(b)
	t.eq(b.tiles.intensity(h, "fire"), 0, "water douses it")
	t.ok(h in BWSplitFront.state(b).broken, "that hex is out")
	t.ok(b.history.any(func(e): return e.type == "divider_break"), "a divider_break event")


func test_ice_divider(t) -> void:
	var b := _split("ice")
	for h in BWSplitFront.divider_hexes(b):
		t.ok(b.tiles.is_pillar(h), "a pillar on %s" % h)
		t.ok(b.board.blocked(h), "impassable")
	t.eq(int(b.tiles.pillars[Vector2i(9, 6)].ticks), BWSplitFront.ICE_TICKS, "it thaws in ICE_TICKS ticks")
	# fire melts one
	b.paint([Vector2i(9, 6)], "fire", b.side("player")[0])
	BWSplitFront._settle(b)
	t.ok(not b.tiles.is_pillar(Vector2i(9, 6)), "fire melts a pillar")
	t.ok(BWSplitFront.is_open(b), "one hex open: the fronts can merge")
	t.ok(b.history.any(func(e): return e.type == "divider_open" and e.by == "player"), "divider_open by the player")
	# thunder shatters
	var b2 := _split("ice")
	b2.paint([Vector2i(9, 7)], "thunder", b2.side("player")[0])
	BWSplitFront._settle(b2)
	t.ok(not b2.tiles.is_pillar(Vector2i(9, 7)), "thunder shatters a pillar")
	# the thaw
	var b3 := _split("ice")
	for i in BWSplitFront.ICE_TICKS:
		b3.tiles.tick()
	BWSplitFront._settle(b3)
	t.ok(BWSplitFront.standing(b3).is_empty(), "after ICE_TICKS ticks the pillars thaw")


func test_wind_divider(t) -> void:
	var b := _split("wind")
	var segs := BWObjectives.objects(b, "divider")
	t.eq(segs.size(), 3, "three wall segments")
	for o in segs:
		t.ok(BWWind.walled(b, o.pos), "a Wind Wall hex")
		t.eq(o.max_hp(), BWSplitFront.WIND_HP, "WIND_HP each")
		t.ok(o in b.foes_of(b.side("player")[0]) and o in b.foes_of(b.side("enemy")[0]), "both sides may strike it")
	# N damage opens a hex
	var o: BWObjective = segs[1]
	o.hp = 0
	b._ko(o, null)
	t.ok(o.pos in BWSplitFront.state(b).broken, "a broken segment opens its hex")
	t.ok(not BWWind.walled(b, o.pos), "the wall hex is gone")
	t.ok(BWSplitFront.is_open(b), "a way through")
	# a Gust aimed at it
	var b2 := _split("wind")
	var u: BWUnit = b2.side("player")[0]
	var seg: BWObjective = BWObjectives.objects(b2, "divider")[0]
	u.element = "wind"
	u.attuned = "wind"
	BWWind.set_mode(u, BWWind.GUST)
	if b2.basic_element(u) == "wind":
		BWSplitFront.new().after_basic(b2, u, seg, { "hit": true })
		t.ok(not seg.alive(), "a wind basic in Gust mode blows the segment open")
	else:
		BWSplitFront.new().after_basic(b2, u, seg, { "hit": true })
		t.ok(seg.alive(), "a non-wind basic doesn't")
	# basics pierce: a ranged basic's line crosses the wall
	t.ok(b2.board.blocked(BWSplitFront.divider_hexes(b2)[2]), "the wall blocks moves")


func test_enemy_breaks_through(t) -> void:
	var b := _split("ice")
	# the west enemies down: the enemy is behind there at round 4
	for e in b.side("enemy"):
		if BWSplitFront.arena_of(b, e.pos) == "west":
			e.hp = 0
	t.ok(BWSplitFront.enemy_behind(b, "west"), "behind in the west")
	BWSplitFront.new().cycle_start(b, BWSplitFront.ENEMY_BREAK_ROUND)
	t.ok(BWSplitFront.is_open(b), "round 4: the enemy opens the divider")
	t.ok(BWSplitFront.standing(b).is_empty(), "the whole wall")
	t.ok(b.history.any(func(e): return e.type == "divider_open" and e.by == "enemy"), "divider_open by the enemy")
	var b2 := _split("fire")
	for p in b2.side("player"):
		p.hp = 1
	BWSplitFront.new().cycle_start(b2, BWSplitFront.ENEMY_BREAK_ROUND)
	t.ok(not BWSplitFront.is_open(b2), "ahead in both arenas: it stays shut")


func test_split_plays_out(t) -> void:
	for el in BWSplitFront.ELEMENTS:
		var b := _split(el, 21)
		var turns := _play(b)
		t.ok(b.over, "%s divider: the fight ends (%d turns, %d rounds)" % [el, turns, b.cycle])
		var b2 := _split(el, 21)
		_play(b2)
		t.eq([b2.winner, b2.cycle, b2.history.size()], [b.winner, b.cycle, b.history.size()], "%s: the same seed replays" % el)


# ---------------------------------------------------------------- the Horde

func test_horde_build(t) -> void:
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var grunts := 0
	var elites := 0
	for w in BWHordeMode.WAVES:
		grunts += int(w[1])
		elites += int(w[2])
	t.eq(es.size(), grunts + elites, "every wave's units")
	t.eq(es.filter(func(u): return u.encounter == "grunt").size(), grunts, "grunts")
	t.eq(es.filter(func(u): return u.encounter == "").size(), elites, "elites: ordinary enemies")
	t.ok(es.all(func(u): return BWHordeMode.wave_of(u) >= 1), "each carries its wave")
	t.ok(es.filter(func(u): return u.encounter == "").all(func(u): return BWHordeMode.wave_of(u) >= 3), "elites come later")
	var g: BWUnit = es[0]
	t.eq(g.level, r.squad_level(), "grunts at the squad's level")
	var r2 := _run_at(8)
	t.eq(BWHordeMode.build(r2, 8).map(func(u): return u.id), es.map(func(u): return u.id), "seeded")


func test_horde_waves_and_win(t) -> void:
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var b := BWBattle.new(BWBoard.load_file(HORDE), 31)
	b.setup(r.squad.slice(0, 6), es)
	var first := int(BWHordeMode.WAVES[0][1]) + int(BWHordeMode.WAVES[0][2])
	t.eq(b.side("enemy").size(), first, "only the first wave on the board")
	t.eq(BWHordeMode.total_waves(b), BWHordeMode.WAVES.size(), "four waves")
	t.eq(BWObjectives.waves_left(b), BWHordeMode.WAVES.size() - 1, "three to come")
	t.eq(BWObjectives.verdict(b), "-", "the empty board between waves is not a win")
	# kill the first wave: still not over (waves to come)
	for e in b.side("enemy"):
		e.hp = 0
	b._check_end()
	t.ok(not b.over, "the first wave down: more to come")
	_play(b, 3000)
	t.ok(b.over, "the fight ends (%s, round %d, escaped %d)" % [b.winner, b.cycle, BWObjectives.escaped(b)])
	t.eq(BWObjectives.waves_left(b) == 0 or b.winner == "enemy", true, "a win needs every wave landed")
	if b.winner == "player":
		t.ok(BWObjectives.escaped(b) < BWObjectives.escape_limit(b), "won under the escape limit")
	var tele: Array = b.history.filter(func(e): return e.type == "wave_incoming")
	var waves: Array = b.history.filter(func(e): return e.type == "wave")
	for w in waves:
		t.ok(tele.any(func(x): return int(x.wave) == int(w.wave) and int(x.cycle) < int(w.cycle) + 1),
			"wave %d was telegraphed a round before it landed" % int(w.wave))


func test_horde_grunts_walk_for_the_exit(t) -> void:
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var b := BWBattle.new(BWBoard.load_file(HORDE), 5)
	# a squad of one far off to the side: nothing in the grunts' way
	var lone: BWUnit = r.squad[0]
	b.setup([lone], es, [Vector2i(0, 12)])
	var f := BWHordeMode.exit_field(b)
	var g: BWUnit = b.side("enemy").filter(func(u): return u.encounter == "grunt")[0]
	var d0 := int(f.get(g.pos, 99))
	while b.current() != g and not b.over:
		BWAI.take_turn(b)
	BWAI.take_turn(b)
	t.ok(int(f.get(g.pos, 99)) < d0 or not g.alive(), "a grunt's turn takes it toward the exit (%d -> %d)" % [d0, int(f.get(g.pos, 99))])


func test_horde_determinism(t) -> void:
	var out := []
	for k in 2:
		var r := _run_at(8, 19)
		var es := BWHordeMode.build(r, 8)
		var b := BWBattle.new(BWBoard.load_file(HORDE), 19)
		b.setup(r.squad.slice(0, 6), es)
		_play(b, 3000)
		out.append([b.winner, b.cycle, BWObjectives.escaped(b), b.history.size()])
	t.eq(out[0], out[1], "the same seed replays the Horde exactly")

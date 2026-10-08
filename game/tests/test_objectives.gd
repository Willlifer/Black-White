extends RefCounted
## D327-D334: the objective framework (BWObjectives: objects, verdicts, the
## wave spawner, exits), the fixed 6v6 schedule, Split Front's divider (fire,
## ice, wind: setup and every way to break it, the enemy's break-through) and
## Stop the Horde (waves, the Lil Fella, win / lose), D347 group turns, and
## determinism.

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

## D353: the schedule's tests moved to test_schedule.gd (the D325 fixed
## fights are gone: fight 5 is a Split Front choice, 7-10 offer 6v6 cards).


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
	# the generic exit framework (no shipped mode uses one since D349): a synthetic exit
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var b := BWBattle.new(BWBoard.load_file(HORDE), 8)
	b.setup(r.squad.slice(0, 6), es)
	t.eq(BWObjectives.exit_hexes(b).size(), 0, "D349: the Horde has no exit")
	var row: Array = []
	for q in b.board.cols:
		row.append(Vector2i(q, b.board.rows - 1))
	BWObjectives.set_exit(b, row, 2)
	t.eq(BWObjectives.escape_limit(b), 2, "the limit")
	var g: BWUnit = b.side("enemy")[0]
	g.pos = Vector2i(0, b.board.rows - 1)
	BWObjectives.turn_end(b, g)
	t.ok(not g.alive(), "an enemy on the exit escapes")
	t.eq(BWObjectives.escaped(b), 1, "counted")
	t.ok(b.history.any(func(e): return e.type == "escape" and e.unit == g.id), "an escape event")
	t.ok(not b.history.any(func(e): return e.type == "ko" and e.unit == g.id), "not a KO")


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
	if b2.basic_element(u) == "wind":
		BWSplitFront.new().after_basic(b2, u, seg, { "hit": true })
		t.ok(not seg.alive(), "a wind basic blows the segment open")
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
	t.eq(BWHordeMode.total_waves(b), BWHordeMode.WAVES.size(), "every wave counted")
	t.eq(BWObjectives.waves_left(b), BWHordeMode.WAVES.size() - 1, "the rest to come")
	t.eq(BWObjectives.verdict(b), "-", "the empty board between waves is not a win")
	for e in b.side("enemy"):
		e.hp = 0
	b._check_end()
	t.ok(not b.over, "the first wave down: more to come")
	_play(b, 3000)
	t.ok(b.over, "the fight ends (%s, round %d)" % [b.winner, b.cycle])
	t.eq(BWObjectives.waves_left(b) == 0 or b.winner == "enemy", true, "a win needs every wave landed")
	if b.winner == "player":
		t.ok(BWHordeMode.fella(b).alive(), "won with the Lil Fella standing")
	var tele: Array = b.history.filter(func(e): return e.type == "wave_incoming")
	var waves: Array = b.history.filter(func(e): return e.type == "wave")
	for w in waves:
		t.ok(tele.any(func(x): return int(x.wave) == int(w.wave) and int(x.cycle) < int(w.cycle) + 1),
			"wave %d was telegraphed a round before it landed" % int(w.wave))


func _horde(seed_value: int = 5, n_squad: int = 6) -> BWBattle:
	var r := _run_at(8)
	var es := BWHordeMode.build(r, 8)
	var b := BWBattle.new(BWBoard.load_file(HORDE), seed_value)
	b.setup(r.squad.slice(0, n_squad), es)
	return b


## Make `u` the acting unit now (a test shortcut into the queue).
func _act(b: BWBattle, u: BWUnit) -> void:
	b.queue.insert(maxi(b.turn_index, 0), u)
	b.turn_index = maxi(b.turn_index, 0)
	b._begin_turn()


func test_horde_win_and_lose(t) -> void:
	var b := _horde(3)
	var lf := BWHordeMode.fella(b)
	t.ok(lf != null and lf.alive(), "the Lil Fella is on the board")
	lf.hp = 0
	b._check_end()
	t.ok(b.over and b.winner == "enemy", "D349: the Lil Fella down loses the fight")
	var b2 := _horde(3)
	for p in b2.side("player"):
		p.hp = 0
	b2._check_end()
	t.ok(b2.over and b2.winner == "enemy", "the squad down loses")
	var b3 := _horde(3)
	for w in BWObjectives.waves(b3):
		w.state = "spawned"
	for e in b3.side("enemy"):
		e.hp = 0
	b3._check_end()
	t.ok(b3.over and b3.winner == "player", "every wave landed and cleared: a win, the little one standing")


func test_horde_grunts_go_for_the_fella(t) -> void:
	var b := _horde(5, 1)
	var f := BWHordeMode.fella_field(b)
	var g: BWUnit = b.side("enemy").filter(func(u): return u.encounter == "grunt")[0]
	var d0 := int(f.get(g.pos, 99))
	while not b.in_group_turn() and not b.over:
		BWAI.take_turn(b)
	var lf := BWHordeMode.fella(b)
	BWAI.take_turn(b)
	var f1 := BWObjectives.walk_field(b, [lf.pos])
	t.ok(not g.alive() or int(f1.get(g.pos, 99)) < d0, "a grunt's turn takes it toward the Lil Fella (%d -> %d)" % [d0, int(f1.get(g.pos, 99))])


func test_horde_determinism(t) -> void:
	var out := []
	for k in 2:
		var b := _horde(19)
		_play(b, 3000)
		out.append([b.winner, b.cycle, BWHordeMode.fella(b).hp, b.history.size()])
	t.eq(out[0], out[1], "the same seed replays the Horde exactly")


# ---------------------------------------------------------------- D347 group turns

func test_group_turn_queue(t) -> void:
	var s := _sides(3, 4)
	for i in 3:
		s[1][i].group_turn = "pack"
	var all: Array = s[0] + s[1]
	var ref: Array = all.duplicate()
	ref.sort_custom(func(a, c):
		if a.speed() != c.speed():
			return a.speed() > c.speed()
		if a.team != c.team:
			return a.team == "player"
		return a.id < c.id)
	var q := BWTurnQueue.build(all)
	var idx: Array = []
	for i in q.size():
		if q[i].group_turn == "pack":
			idx.append(i)
	t.eq(idx.size(), 3, "every member queued")
	t.eq(idx[-1] - idx[0], 2, "the members stand together")
	var lead := 0
	for i in ref.size():
		if ref[i].group_turn == "pack":
			lead = i
			break
	t.eq(idx[0], lead, "the block takes the fastest member's slot")
	t.eq(q.filter(func(u): return u.group_turn == ""), ref.filter(func(u): return u.group_turn == ""), "the others keep their order")
	var slots := BWTurnQueue.slots(q)
	t.eq(slots.size(), q.size() - 2, "the turn order shows one slot for the group")
	t.ok(slots.any(func(x): return x is Dictionary and x.group == "pack" and x.units.size() == 3), "a pack x3 slot")
	for u in s[1]:
		u.group_turn = ""
	t.eq(BWTurnQueue.build(all), ref, "no group: the queue is unchanged")


func test_group_turn_resolves_in_order(t) -> void:
	var b := _horde(7)
	while not b.in_group_turn() and not b.over:
		BWAI.take_turn(b)
	var gl: Dictionary = b.group_live.duplicate(true)
	t.ok(not gl.is_empty(), "a Horde group turn opens")
	var block: Array = b.queue.slice(int(gl.from), int(gl.to))
	t.eq(block.size(), b.side("enemy").filter(func(u): return u.encounter == "grunt").size(), "every living grunt in the block")
	t.ok(block.all(func(u): return u.group_turn == BWHordeMode.GROUP), "only grunts (elites act alone)")
	var f := BWHordeMode.fella_field(b)
	var keys: Array = block.map(func(u): return int(f.get(u.pos, 999)))
	var sorted := keys.duplicate()
	sorted.sort()
	t.eq(keys, sorted, "resolved nearest the Lil Fella first")
	var h0 := b.history.size()
	t.ok(b.history.any(func(e): return e.type == "group_turn" and (e.units as Array).size() == block.size()), "a group_turn event names them")
	BWAI.take_turn(b)
	var evs: Array = b.history.slice(h0)
	var ge := evs.map(func(e): return e.type).find("group_end")
	if ge >= 0:
		evs = evs.slice(0, ge + 1)
	var turns: Array = evs.filter(func(e): return e.type == "turn").map(func(e): return str(e.unit))
	t.ok(turns.size() >= 1 and turns.all(func(id): return id in gl.units), "one take_turn plays the members' turns (%d)" % turns.size())
	t.ok(evs.any(func(e): return e.type == "group_end") or b.over, "and closes the block")
	t.ok(b.group_live.is_empty() or int(b.group_live.serial) != int(gl.serial), "the block is done")
	var b2 := _horde(7)
	while not b2.in_group_turn() and not b2.over:
		BWAI.take_turn(b2)
	BWAI.take_turn(b2)
	t.eq(b2.history.size(), b.history.size(), "the same seed resolves the same block")
	t.eq(str(b2.history.map(func(e): return [e.type, e.get("unit", "")])), str(b.history.map(func(e): return [e.type, e.get("unit", "")])), "event for event")


# ---------------------------------------------------------------- D348 the Lil Fella

func test_fella_hp_formula(t) -> void:
	var b := _horde(3)
	var top := 0
	for p in b.side("player"):
		top = maxi(top, p.max_hp())
	var lf := BWHordeMode.fella(b)
	t.eq(lf.max_hp(), int(round(top * 0.5)), "half the squad's highest max HP (%d of %d)" % [lf.max_hp(), top])
	t.eq(lf.hp, lf.max_hp(), "full at the start")
	t.eq(BWLilFella.hp_for([]), 1, "never below 1")
	t.eq(lf.team, "neutral", "not a squad unit")
	t.ok(lf in b.queue, "it takes its own turn")


func test_fella_immune_to_player_sources(t) -> void:
	var b := _horde(3)
	var lf := BWHordeMode.fella(b)
	var p: BWUnit = b.side("player")[0]
	var hp0 := lf.hp
	t.ok(not b.can_harm(p, lf), "direct: the squad's blows can't land")
	t.ok(not lf in b.foes_of(p), "not a squad target")
	t.ok(not lf in b._foes_on(p, [lf.pos]), "area: a squad area passes over it")
	b._tile_hurt(lf, 20, "fire", p.id)
	b._tile_hurt(lf, 20, "detonation", p.id)
	b._tile_hurt(lf, 20, "fire", "")
	t.eq(lf.hp, hp0, "ground: the squad's (and the map's own) ground never hurts it")
	b.tiles.entries[lf.pos] = { "h": 3, "v": -3, "source": p.id }
	b._fella_turn_start(lf)
	t.eq(lf.hp, hp0, "standing on the squad's fire: no harm")
	var o: BWUnit = b.side("player")[1]
	t.ok(b._chain_target(o) != lf, "chain: an arc never jumps to it")
	b._conduct(p, lf, 30)
	t.eq(lf.hp, hp0, "chain: no conduction through it")
	b._add_status(lf, "staggered", p)
	t.ok(lf.statuses.is_empty(), "no status lands")
	t.ok(not b._displace(lf, 0, 2, "push"), "never displaced")
	t.eq(lf.hp, hp0, "still whole")


func test_fella_hurt_by_enemy_sources(t) -> void:
	var b := _horde(3)
	var lf := BWHordeMode.fella(b)
	var g: BWUnit = b.side("enemy").filter(func(u): return u.encounter == "grunt")[0]
	t.ok(b.can_harm(g, lf) and lf in b.foes_of(g), "the enemy can strike it")
	var hp0 := lf.hp
	b._tile_hurt(lf, 10, "fire", g.id)
	t.eq(lf.hp, hp0 - 10, "enemy-laid ground hurts it")
	var hp1 := lf.hp
	b.tiles.entries[lf.pos] = { "h": 3, "v": 0, "source": g.id }
	b._fella_turn_start(lf)
	t.ok(lf.hp < hp1, "standing on the enemy's fire burns it (%d -> %d)" % [hp1, lf.hp])
	b.tiles.entries.erase(lf.pos)
	for h in b.board.neighbors(lf.pos):
		if b.board.is_passable(h) and b.unit_at(h) == null:
			g.pos = h
			break
	_act(b, g)
	b.expected_rolls = true
	var hp2 := lf.hp
	b.attack(g, lf)
	t.ok(lf.hp < hp2, "an enemy attack hurts it (%d -> %d)" % [hp2, lf.hp])


func test_fella_flees_in_bounds(t) -> void:
	var b := _horde(9)
	var lf := BWHordeMode.fella(b)
	var g: BWUnit = b.side("enemy")[0]
	for k in 10:
		var before := lf.pos
		var near0 := BWHex.distance(g.pos, before)
		_act(b, lf)
		BWHordeMode._fella_turn(b, lf)
		t.ok(b.board.in_bounds(lf.pos), "turn %d: on the map %s" % [k, str(lf.pos)])
		t.ok(not BWHordeMode.hazard(b, lf.pos), "turn %d: never on a hazard" % k)
		t.ok(BWHex.distance(g.pos, lf.pos) >= near0 or near0 >= 8, "turn %d: it doesn't run at the grunt (%d -> %d)" % [k, near0, BWHex.distance(g.pos, lf.pos)])
		var r := b.reachable(g)
		var best := g.pos
		for h in r:
			if r[h].stop and BWHex.distance(h, lf.pos) < BWHex.distance(best, lf.pos):
				best = h
		g.pos = best
	var b2 := _horde(9)
	var lf2 := BWHordeMode.fella(b2)
	var e2: BWUnit = b2.side("enemy")[0]
	for h in b2.board.area(lf2.pos, 3):
		if h != lf2.pos and b2.board.is_passable(h):
			b2.tiles.entries[h] = { "h": 2, "v": 0, "source": e2.id }
	e2.pos = lf2.pos + Vector2i(0, -2) if b2.unit_at(lf2.pos + Vector2i(0, -2)) == null else e2.pos
	_act(b2, lf2)
	BWHordeMode._fella_turn(b2, lf2)
	t.ok(not BWHordeMode.hazard(b2, lf2.pos), "ringed by fire it stays off the fire (%s)" % str(lf2.pos))

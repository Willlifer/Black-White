extends RefCounted
## D335-D342: the castle modes (Defend / Storm the Castle): the maps, the gate's
## HP and damage rules, high ground, win and lose per mode, Storm's phase
## change (the gate falls: the throne unseals, reinforcements stop), the wave
## spawns, the Warden holding its post, the run wiring, determinism.


func _battle(mode: String, seed_value := 3, n := 8) -> BWBattle:
	var q := BWCastle.quick_run(mode, seed_value, n)
	var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % q.map), 1234 + seed_value)
	b.setup(q.players, q.enemies, [])
	return b


func _labels(mods: Array) -> String:
	return " | ".join(mods.map(func(m): return str(m.get("label", ""))))


func test_maps(t) -> void:
	for m in ["keep", "stronghold"]:
		var bd := BWBoard.load_file("res://maps/%s.json" % m)
		t.eq(bd.errors.size(), 0, "%s loads clean %s" % [m, bd.errors])
		t.eq(bd.deploy_count, 6, "%s is a 6v6 map" % m)
		t.eq([bd.cols, bd.rows], [19, 17], "%s is 19x17" % m)
		var g: Array = bd.objective.gate
		var gh := Vector2i(int(g[0]), int(g[1]))
		t.ok(bd.is_passable(gh) and bd.elevation(gh) == 0, "%s: the gate stands on ground level" % m)
		var walls := 0
		for n in bd.neighbors(gh):
			if bd.elevation(n) >= 3:
				walls += 1
		t.eq(walls, 2, "%s: wall walk either side of the gate" % m)
		t.eq(bd.statics.values().filter(func(s): return s == Vector2i(2, 0)).size(), 2, "%s: two braziers (static fire 2)" % m)
		t.ok(bd.statics.values().filter(func(s): return s == Vector2i(-2, 0)).size() >= 30, "%s: a moat of static water 2" % m)
	var k := BWBoard.load_file("res://maps/keep.json")
	var s := BWBoard.load_file("res://maps/stronghold.json")
	for h in k.cells():
		var f := Vector2i(h.x, 16 - h.y)
		if s.exists(f) and f.y > 0:
			t.ok(s.elevation(f) == k.elevation(h), "the stronghold is the keep flipped at %s" % h)
	t.eq(BWRun.MODE_MAPS.defend, "keep", "Defend plays the keep")
	t.eq(BWRun.MODE_MAPS.storm, "stronghold", "Storm plays the stronghold")


func test_gate_hp_and_targets(t) -> void:
	var b := _battle("defend")
	var g := BWCastle.gate(b)
	t.ok(g != null and g.alive(), "the iron gate is placed")
	t.eq(g.pos, BWCastle.gate_hex(b), "on the map's gate hex")
	t.eq(g.max_hp(), roundi(BWCastle.squad_hp(b) * BWCastleDefend.GATE_HP), "HP = the squad's mean max HP x GATE_HP")
	var p: BWUnit = b.side("player")[0]
	var e: BWUnit = b.side("enemy")[0]
	t.ok(not g in b.foes_of(p), "Defend: the squad never strikes its own gate")
	t.ok(g in b.foes_of(e), "Defend: the raiders may strike the gate")
	t.ok(not g in b.queue, "the gate takes no turn")
	b._add_status(g, "staggered", e)
	t.ok(not g.statuses.has("staggered"), "the gate takes no status")
	var hp := g.hp
	b._tile_hurt(g, 50, "fire", "")
	t.eq(g.hp, hp, "no ground damage on the gate")
	var sb := _battle("storm")
	var sg := BWCastle.gate(sb)
	t.ok(sg in sb.foes_of(sb.side("player")[0]), "Storm: the squad strikes the gate")
	t.ok(not sg in sb.foes_of(sb.side("enemy")[0]), "Storm: the guards never strike their own gate")
	t.eq(sg.kind, "wood_gate", "Storm's gate is wood")


func test_gate_damage_rules(t) -> void:
	var b := _battle("storm")
	var g := BWCastle.gate(b)
	var p: BWUnit = b.side("player")[0]
	p.pos = Vector2i(g.pos.x, g.pos.y + 1)
	var fire: Array = []
	BWCastle.mods(b, p, g, p.pos, "fire", fire)
	t.ok(_labels(fire).contains("Wood burns"), "fire on the wooden gate: x1.5 (%s)" % _labels(fire))
	t.near(float(fire.filter(func(m): return str(m.label).contains("Wood"))[0].value), BWCastle.WOOD_FIRE, 0.001, "x WOOD_FIRE")
	var water: Array = []
	BWCastle.mods(b, p, g, p.pos, "water", water)
	t.ok(not _labels(water).contains("Wood"), "only fire burns it")
	var thunder: Array = []
	BWCastle.mods(b, p, g, p.pos, "thunder", thunder)
	t.ok(not _labels(thunder).contains("shatters"), "thunder on an unglazed gate: no shatter")
	var e := b.tiles._entry(-1, 0, "", "", "")
	e.glaze = 2
	b.tiles.entries[g.pos] = e
	t.ok(b.tiles.is_glazed(g.pos), "the gate's hex glazed")
	thunder.clear()
	BWCastle.mods(b, p, g, p.pos, "thunder", thunder)
	t.ok(_labels(thunder).contains("glazed gate shatters"), "thunder on a glazed gate shatters it (%s)" % _labels(thunder))
	# the iron gate does not burn
	var d := _battle("defend")
	var ig := BWCastle.gate(d)
	var r: BWUnit = d.side("enemy")[0]
	var f2: Array = []
	BWCastle.mods(d, r, ig, Vector2i(ig.pos.x, ig.pos.y - 1), "fire", f2)
	t.ok(not _labels(f2).contains("Wood"), "the iron gate takes fire as usual")
	# the forecast carries it (a real blow): fire basic vs plain basic on the wood gate
	var plain := b.forecast_basic(p, g)
	t.ok(float(plain.damage.value) > 0.0, "a blow on the gate deals damage")
	t.ok(not plain.has("immune"), "the gate is never immune")


func test_high_ground(t) -> void:
	var b := _battle("defend")
	var p: BWUnit = b.side("player")[0]
	var e: BWUnit = b.side("enemy")[0]
	e.pos = Vector2i(8, 9)          # the berm, elevation 0
	var wall := Vector2i(8, 10)     # the wall walk, elevation 3
	t.eq(b.board.elevation(wall), 3, "the wall walk is elevation 3")
	var m: Array = []
	BWCastle.mods(b, p, e, wall, "", m)
	t.ok(_labels(m).contains("High ground (3 above): +15%"), "3 above: +15%% (%s)" % _labels(m))
	var up: Array = []
	BWCastle.mods(b, e, p, e.pos, "", up)
	p.pos = wall
	up.clear()
	BWCastle.mods(b, e, p, e.pos, "", up)
	t.ok(not _labels(up).contains("High ground"), "shooting up: no bonus, no penalty")
	var all := b._mods(p, e, BWFormulas.WEAPON, "", true, "", wall)
	t.ok(_labels(all).contains("High ground"), "the battle's own forecast terms include it")
	var plain := BWBattle.new(BWBoard.load_file("res://maps/commons.json"), 1)
	var none: Array = []
	BWCastle.mods(plain, p, e, wall, "", none)
	t.eq(none.size(), 0, "off a castle map: nothing")


func test_defend_win_and_lose(t) -> void:
	var b := _battle("defend")
	t.eq(BWObjectives.title(b), "Defend the Castle", "the banner names the mode")
	t.ok(BWObjectives.objective_text(b).contains("%d rounds" % BWCastleDefend.ROUNDS), "and the goal")
	b.side("enemy").map(func(u): u.hp = 0)
	b._check_end()
	t.ok(not b.over, "wiping the opening six does not end it while waves are to come")
	BWObjectives.handler(b).cycle_start(b, BWCastleDefend.ROUNDS + 1)
	t.ok(b.over and b.winner == "player", "surviving %d rounds wins" % BWCastleDefend.ROUNDS)
	var l := _battle("defend")
	BWObjectives.break_object(l, BWCastle.gate(l))
	t.ok(l.over and l.winner == "enemy", "the gate breaking loses")
	var s := _battle("defend")
	for u in s.side("player"):
		u.hp = 0
	s._check_end()
	t.ok(s.over and s.winner == "enemy", "the squad down loses")
	var w := _battle("defend")
	for wv in BWObjectives.waves(w):
		wv.state = "spawned"
	for u in w.side("enemy"):
		u.hp = 0
	w._check_end()
	t.ok(w.over and w.winner == "player", "every raider down with no wave left: a win")
	t.ok(BWCastleView.end_text(w, "player").contains("raiders"), "its end banner")


func test_defend_waves(t) -> void:
	var b := _battle("defend")
	var ws := BWObjectives.waves(b)
	t.eq(ws.size(), BWCastleDefend.WAVES.size(), "two waves after the opening six")
	t.eq(b.side("enemy").size(), 6, "six raiders on the board at the start")
	t.eq(b.objective_state.reserve.size(), 6, "six held back")
	t.eq(int(ws[0].cycle), int(BWCastleDefend.WAVES[0][0]), "wave 2 on its round")
	var lines := BWObjectives.hud_lines(b)
	t.ok(str(lines[0]).begins_with("Gate "), "the plate: the gate's HP (%s)" % [lines])
	t.ok(str(lines[1]).begins_with("Wave 1 / 3"), "the plate: the wave counter")
	t.ok(str(lines[2]).contains("of %d" % BWCastleDefend.ROUNDS), "the plate: the rounds")
	var n0 := b.history.size()
	BWObjectives.cycle_start(b, int(ws[0].cycle) - 1)
	t.ok(b.history.slice(n0).any(func(e): return e.type == "wave_incoming"), "telegraphed a round ahead")
	BWObjectives.cycle_start(b, int(ws[0].cycle))
	t.eq(b.side("enemy").size(), 6 + int(BWCastleDefend.WAVES[0][1]), "the wave lands")
	var at := BWCastle.hexes(b, "waves_at")
	for u in b.side("enemy").slice(6):
		t.ok(u.pos in at or b.board.deploy.enemy.has(u.pos) or u.pos.y <= 2, "%s lands on the north edge (%s)" % [u.name, u.pos])
	t.ok(str(BWObjectives.hud_lines(b)[1]).begins_with("Wave 2 / 3"), "the counter moves on")


func test_storm_phase_change(t) -> void:
	var b := _battle("storm")
	var th := BWCastleStorm.throne(b)
	var w := BWCastleStorm.warden(b)
	var p: BWUnit = b.side("player")[0]
	t.ok(th != null and w != null, "the throne and the Warden")
	t.eq(w.pos, Vector2i(int(b.board.objective.warden[0]), int(b.board.objective.warden[1])), "the Warden starts at its post")
	t.ok(not th in b.foes_of(p), "phase 1: the throne is sealed")
	t.ok(BWPhases.active(b) and BWPhases.kind(b) == "storm", "the phase framework runs the script")
	t.eq(BWObjectives.waves(b).size(), BWCastleStorm.REINFORCE_WAVES, "reinforcements scheduled")
	t.ok(str(BWObjectives.hud_lines(b)[1]).contains("SEALED"), "the plate says so")
	BWObjectives.break_object(b, BWCastle.gate(b))
	t.ok(not b.over, "the gate falling does not end it")
	t.ok(BWCastleStorm.phase2(b), "phase 2")
	t.ok(BWPhases.fired(b, "throne"), "the phase fired (BWPhases)")
	t.ok(b.history.any(func(e): return e.type == "phase" and str(e.phase) == "throne"), "a phase event")
	t.ok(b.history.any(func(e): return e.type == "castle_breach"), "a castle_breach event")
	t.ok(th in b.foes_of(p), "the throne is open")
	t.eq(BWObjectives.waves_left(b), 0, "no more reinforcements")
	t.ok(BWObjectives.objective_text(b).contains("throne"), "the goal moves on")
	BWObjectives.break_object(b, th)
	t.ok(b.over and b.winner == "player", "breaking the throne wins")
	var c := _battle("storm")
	var cw := BWCastleStorm.warden(c)
	cw.hp = 0
	c._ko(cw, null)
	c._check_end()
	t.ok(c.over and c.winner == "player", "downing the Warden wins")
	var d := _battle("storm")
	for u in d.side("player"):
		u.hp = 0
	d._check_end()
	t.ok(d.over and d.winner == "enemy", "the squad down loses")
	var e := _battle("storm")
	for u in e.side("enemy"):
		if u != BWCastleStorm.warden(e):
			u.hp = 0
	e._check_end()
	t.ok(not e.over, "the guards down is not a win: the throne or the Warden")


func test_storm_reinforcements_and_warden(t) -> void:
	var b := _battle("storm")
	var first := int(BWObjectives.waves(b)[0].cycle)
	t.eq(first, BWCastleStorm.REINFORCE_FROM, "the first reinforcements come on their round")
	var before := b.side("enemy").size()
	BWObjectives.cycle_start(b, first)
	t.eq(b.side("enemy").size(), before + BWCastleStorm.REINFORCE_COUNT, "they come in")
	var doors := BWCastle.hexes(b, "back_door")
	for u in b.side("enemy"):
		if b.history.any(func(e): return e.type == "spawn" and str(e.unit) == u.id):
			t.ok(u.pos in doors or u.pos.y <= 3, "%s enters by the back door (%s)" % [u.name, u.pos])
	# the Warden holds its post in phase 1
	var w := BWCastleStorm.warden(b)
	var guard := 0
	while b.current() != w and guard < 40 and not b.over:
		b.end_turn()
		guard += 1
	t.eq(b.current(), w, "the Warden's turn comes")
	var at := w.pos
	BWAI.take_turn(b)
	t.eq(w.pos, at, "phase 1: the Warden does not leave the throne")


func test_run_wiring(t) -> void:
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), 11)
	for u in r.squad:
		BWProgression.level_up(u, 8 - u.level)
	var d := BWCastleDefend.build(r, 8)
	t.eq(d.size(), 6 + 6, "Defend: six raiders and two waves of three")
	t.eq(d.filter(func(u): return BWCastle.wave_of(u) > 0).size(), 6, "the waves are marked")
	t.ok(d.all(func(u): return u.level == r.squad_level()), "built at the squad's level")
	var s := BWCastleStorm.build(r, 8)
	t.eq(s.size(), 6 + BWCastleStorm.REINFORCE_WAVES * BWCastleStorm.REINFORCE_COUNT, "Storm: six defenders and the reinforcements")
	t.eq(s.filter(func(u): return u.name == "The Warden").size(), 1, "one Warden")
	var room := { "kind": BWRooms.STANDARD, "map": "keep", "fight": 8, "mode": "defend", "enemies": [] }
	t.eq(r.enemies_for(8, room).size(), 12, "BWRun builds a defend room through the mode")
	room.mode = "storm"
	room.map = "stronghold"
	t.eq(r.enemies_for(8, room).size(), 12, "and a storm room")
	t.ok("defend" in BWRun.SIX_MODES and "storm" in BWRun.SIX_MODES, "both modes in the 6v6 draw")


func test_determinism(t) -> void:
	var out: Array = []
	for k in 2:
		var b := _battle("storm", 5)
		var guard := 0
		while not b.over and guard < 30:
			BWAI.take_turn(b)
			guard += 1
		out.append([b.history.size(), b.units.map(func(u): return "%s:%d@%s" % [u.id, u.hp, u.pos])])
	t.eq(out[0], out[1], "same seed, same fight (Storm, 30 turns)")
	var o2: Array = []
	for k in 2:
		var b := _battle("defend", 6)
		var guard := 0
		while not b.over and guard < 30:
			BWAI.take_turn(b)
			guard += 1
		o2.append([b.history.size(), b.cycle, b.units.map(func(u): return "%s:%d" % [u.id, u.hp])])
	t.eq(o2[0], o2[1], "same seed, same fight (Defend, waves included)")

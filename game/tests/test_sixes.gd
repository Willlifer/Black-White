extends RefCounted
## D319-D324: the 6v6 infrastructure: per-map deploy counts, the default
## starts and the pre-battle's six slots, the enemy layout of six, the AI's
## big-board pruning and its time guard, determinism.

const COMMONS := "res://maps/commons.json"


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


func _sides(n: int) -> Array:
	var roster := BWData.table("roster")
	var ps: Array = []
	var es: Array = []
	for i in n:
		ps.append(BWUnit.from_roster(roster[i]))
		es.append(BWUnit.from_roster(roster[i + 10]))
	return [ps, es]


func test_deploy_counts(t) -> void:
	t.eq(BWRun.deploy_count_of("commons"), 6, "Commons fields 6")
	t.eq(BWRun.deploy_count_of("arena"), 3, "the 3v3 maps field 3 (no deploy_count: the default)")
	t.eq(BWRun.deploy_count_of("no_such_map"), BWRun.DEPLOY, "an unknown map falls back to 3")
	var r := BWRun.start(_ids(), 5)
	t.eq(r.deploy_for(1), 3, "a run on its own maps fields 3")
	var plain := r.enemies_for(1)
	t.eq(plain.size(), 3, "three enemies on a 3v3 map")
	r.force_map = "commons"
	t.eq(r.map_for(1), "commons", "force_map wins (tools and tests)")
	t.eq(r.deploy_for(1), 6, "Commons: the squad fields 6")
	var six := r.enemies_for(1)
	t.eq(six.size(), 6, "Commons: six enemies")
	t.eq(six.slice(0, 3).map(func(u): return u.id), plain.map(func(u): return u.id), "the first three draws are the 3v3 squad (same rng order)")
	var ids := {}
	for u in six:
		ids[u.id] = true
		t.ok(r.unit(u.id.trim_suffix("_f1")) == null, "%s is not in the squad" % u.id)
	t.eq(ids.size(), 6, "six different enemies")
	# fewer owned: field them all (the rule: min(deploy_count, squad size))
	var small := BWRun.start(_ids().slice(0, 4), 5)
	small.force_map = "commons"
	t.eq(small.deploy_for(1), 4, "a squad of 4 fields 4 on a 6v6 map")
	t.eq(small.enemies_for(1).size(), 6, "the enemy still fields the map's 6")
	var rooms := BWRooms.room_for(r, 1)
	t.eq(rooms.enemies.size(), 6, "the room draws six ids for a 6v6 map")


func test_default_starts(t) -> void:
	var b := BWBoard.load_file(COMMONS)
	var six := b.default_starts("player", 6)
	t.eq(six, Array(b.spawns.player), "six starts are the six spawns, in order")
	var eight := b.default_starts("player", 8)
	t.eq(eight.size(), 8, "eight starts (recruits on a bigger map later)")
	var uniq := {}
	for h in eight:
		uniq[h] = true
		t.ok(h in b.deploy.player, "start %s in the deploy zone" % h)
	t.eq(uniq.size(), 8, "all distinct")
	var taken: Array = [b.spawns.player[0]]
	t.ok(not b.spawns.player[0] in b.default_starts("player", 6, taken), "taken hexes are skipped")
	var a := BWBoard.load_file("res://maps/arena.json")
	t.eq(a.default_starts("player", 3), Array(a.spawns.player), "3v3: the three spawns, as before")


func test_setup_six_a_side(t) -> void:
	var b := BWBattle.new(BWBoard.load_file(COMMONS), 3)
	var sd := _sides(6)
	b.setup(sd[0], sd[1])
	t.eq(b.side("player").size(), 6, "six players")
	t.eq(b.side("enemy").size(), 6, "six enemies")
	t.eq(b.side("player").map(func(u): return u.pos), Array(b.board.spawns.player), "players on the six spawns")
	t.eq(b.side("enemy").map(func(u): return u.pos), Array(b.board.spawns.enemy), "enemy layout of six: spawn i (D210/D211)")
	var occ := {}
	for u in b.units:
		occ[u.pos] = true
	t.eq(occ.size(), 12, "no two units share a hex")
	# placements for some, the rest fall back to the free default starts
	var b2 := BWBattle.new(BWBoard.load_file(COMMONS), 3)
	var sd2 := _sides(6)
	var first: Vector2i = b2.board.spawns.player[1]
	b2.setup(sd2[0], sd2[1], [first])
	var pos: Array = b2.side("player").map(func(u): return u.pos)
	t.eq(pos[0], first, "a placed unit keeps its hex")
	var u2 := {}
	for h in pos:
		u2[h] = true
	t.eq(u2.size(), 6, "the unplaced five skip the taken spawn")
	# six enemies on a 3-spawn map still lay out (D211's crowd rule)
	var lay := BWBattle.enemy_layout(BWBoard.load_file("res://maps/arena.json"), _sides(6)[1])
	var l2 := {}
	for h in lay:
		l2[h] = true
	t.eq(l2.size(), 6, "arena: six distinct enemy hexes")


func test_prebattle_six_slots(t) -> void:
	var r := BWRun.start(_ids(), 7)
	r.force_map = "commons"
	var pre := BWPrebattleScreen.new()
	pre.run = r
	pre._board = BWBoard.load_file(COMMONS)
	pre._need = r.deploy_for(r.fight)
	t.eq(pre._need, 6, "six slots on Commons")
	pre._auto_fill()
	t.eq(pre._deployed.size(), 6, "the auto-placement default fills all six")
	t.eq(pre._deployed.map(func(u): return pre._placed[u.id]), Array(pre._board.spawns.player), "each on a spawn")
	# a recruit makes 7: the highest levels go in, the bench keeps the rest
	var r7 := BWRun.start(_ids(), 7)
	r7.force_map = "commons"
	var nu := BWUnit.from_roster(BWData.table("roster")[12])     # a recruit, levelled past the squad
	r7.squad.append(nu)
	BWProgression.level_up(nu, 3)
	if true:
		var pre7 := BWPrebattleScreen.new()
		pre7.run = r7
		pre7._board = BWBoard.load_file(COMMONS)
		pre7._need = r7.deploy_for(r7.fight)
		pre7._auto_fill()
		t.eq(pre7._deployed.size(), 6, "seven owned: six go in")
		t.ok(nu in pre7._deployed, "the higher-level recruit is picked")
		pre7.free()
	# the Auto button re-seats everyone on the default starts
	pre._placed[pre._deployed[0].id] = pre._board.deploy.player[0]
	pre._auto_fill(true)
	t.eq(pre._placed[pre._deployed[0].id], pre._board.spawns.player[0], "Auto re-seats on the spawns")
	pre.free()
	var r3 := BWRun.start(_ids(), 7)
	t.eq(r3.deploy_for(r3.fight), 3, "3v3 maps keep three slots")


func test_ai_pruning(t) -> void:
	var big := BWBattle.new(BWBoard.load_file(COMMONS), 3)
	var sd := _sides(6)
	big.setup(sd[0], sd[1])
	var small := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 3)
	var sd3 := _sides(3)
	small.setup(sd3[0], sd3[1])
	t.ok(BWAI.big(big) and not BWAI.big(small), "big = a map fielding more than 3")
	var su := small.current()
	t.eq(BWAI._skip_hexes(small, su, small.reachable(su)), {}, "3v3: nothing pruned")
	t.eq(BWAI._pair_cap(small, su, BWAI.BIG_PREVIEWS), 0, "3v3: no preview cap")
	var targets: Array = []
	for q in 12:
		targets.append(Vector2i(q, 5))
	t.eq(BWAI._cap_targets(small, su, targets, 0), targets, "cap 0 keeps every target")
	t.eq(BWAI._cap_targets(big, big.current(), targets, 4).size(), 4, "a cap keeps that many")
	# a unit with every foe in reach: at most BIG_HEX_CAP hexes keep their forecast
	var u := big.current()
	for f in big.foes_of(u):
		f.pos = f.pos                                 # (as laid out)
	var reach := big.reachable(u)
	var skip := BWAI._skip_hexes(big, u, reach)
	var wr := big.weapon_range(u)
	var attack := reach.keys().filter(func(h): return (reach[h].stop or h == u.pos) and big.foes_of(u).any(func(f): return BWHex.distance(h, f.pos) <= wr))
	t.ok(attack.size() - skip.size() <= maxi(BWAI.BIG_HEX_CAP, 0) or skip.is_empty(), "at most BIG_HEX_CAP attack hexes forecast")


## The guard: a whole 6v6 AI-vs-AI fight on Commons, every turn timed. The
## tool (tools/sixes_perf.gd) measures the real thing at fight 6 (worst turn
## ~130 ms, mean ~30 ms on the dev machine); here the mean must stay under the
## 250 ms budget and no single turn over 4× it (headroom for a loaded machine).
func test_ai_time_budget(t) -> void:
	var b := BWBattle.new(BWBoard.load_file(COMMONS), 11)
	var sd := _sides(6)
	b.setup(sd[0], sd[1])
	var total := 0.0
	var worst := 0.0
	var n := 0
	while not b.over and n < 400:
		var t0 := Time.get_ticks_usec()
		BWAI.take_turn(b)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		n += 1
	t.ok(b.over, "the 6v6 finishes (%d turns, %d rounds)" % [n, b.cycle])
	t.ok(total / maxf(n, 1) < 250.0, "mean AI turn %.1f ms < 250" % (total / maxf(n, 1)))
	t.ok(worst < 1000.0, "worst AI turn %.1f ms < 1000" % worst)
	print("    [info] 6v6 Commons: %d turns, %d rounds, AI turn mean %.1f worst %.1f ms" % [n, b.cycle, total / maxf(n, 1), worst])


func test_determinism(t) -> void:
	var runs: Array = []
	for k in 2:
		var b := BWBattle.new(BWBoard.load_file(COMMONS), 21)
		var sd := _sides(6)
		b.setup(sd[0], sd[1])
		var n := 0
		while not b.over and n < 60:
			BWAI.take_turn(b)
			n += 1
		runs.append([b.history.size(), b.cycle, b.units.map(func(u): return [u.id, u.hp, u.pos])])
	t.eq(runs[0], runs[1], "the same seed replays the same 6v6 (pruning counts, never the clock)")


## D324: the turn order fits 12 at the 1600-wide HUD (1080p), keeps the old
## floor (8 this round, 13 in all) for 3v3 and crowds, and overflows to "+N".
func test_turn_order_fit(t) -> void:
	var f12 := BWCombatUI.order_fit(1600.0, 12, 12)
	t.eq(f12.now, 12, "12 units: the whole round shows")
	t.ok(f12.next >= 4, "and at least 4 of next round (%d)" % f12.next)
	var f6 := BWCombatUI.order_fit(1600.0, 6, 6)
	t.eq([f6.now, f6.next], [6, 6], "3v3: everything, as before")
	var narrow := BWCombatUI.order_fit(1000.0, 16, 16)
	t.eq(narrow.now, 8, "a narrow HUD keeps the floor of 8 this round (the rest is +N)")
	t.eq(narrow.now + narrow.next, 13, "and 13 in all, as D211")
	var crowd := BWCombatUI.order_fit(1600.0, 20, 20)
	t.ok(crowd.now < 20 and crowd.now >= 8, "a 20-unit crowd overflows to +%d" % (20 - crowd.now))

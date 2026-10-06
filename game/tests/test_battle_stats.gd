extends RefCounted
## BWBattleStats (D119–D121): the end-of-battle summary, on synthetic
## histories and on real AI-vs-AI battles (totals match the HP lost), and
## the run's stats (after_fight, save v3, migration of an older save).


func _units() -> Array:
	var roster := BWData.table("roster")
	var out: Array = []
	for i in 6:
		var u := BWUnit.from_roster(roster[i])
		u.team = "player" if i < 3 else "enemy"
		u.hp = u.max_hp()
		out.append(u)
	return out


func _res(dmg: int, hit: bool = true, crit: bool = false) -> Dictionary:
	return { "hit": hit, "crit": crit, "glance": false, "resisted": false, "damage": dmg if hit else 0, "secondary": true }


func test_synthetic_win(t) -> void:
	var u := _units()
	var p1: BWUnit = u[0]
	var p2: BWUnit = u[1]
	var p3: BWUnit = u[2]
	var e1: BWUnit = u[3]
	var e2: BWUnit = u[4]
	var e1hp := e1.max_hp()
	var e2hp := e2.max_hp()
	var p1hp := p1.max_hp()
	var h: Array = [
		{ "type": "battle_start", "cycle": 1 },
		{ "type": "attack", "unit": p1.id, "target": e1.id, "result": _res(20, true, true), "target_hp": e1hp - 20, "ko": false, "cycle": 1 },
		{ "type": "attack", "unit": p1.id, "target": e1.id, "result": _res(0, false), "target_hp": e1hp - 20, "ko": false, "cycle": 1 },
		{ "type": "skill", "unit": p2.id, "skill": "nonexistent_key", "results": [
			{ "target": e1.id, "result": _res(30), "target_hp": e1hp - 50 },
			{ "target": e2.id, "result": _res(10), "target_hp": e2hp - 10 }], "cycle": 2 },
		{ "type": "paint", "unit": p2.id, "element": "thunder", "hexes": [], "cycle": 2 },
		{ "type": "detonate", "hex": Vector2i(1, 1), "pct": 10, "radius": 1, "cycle": 2 },
		{ "type": "tile_damage", "unit": e2.id, "amount": 15, "cause": "detonation", "hp": e2hp - 25, "source": p2.id, "cycle": 2 },
		{ "type": "tile_damage", "unit": e1.id, "amount": 7, "cause": "detonation", "hp": e1hp - 57, "source": p2.id, "cycle": 2 },
		{ "type": "chain", "from": e2.id, "to": e1.id, "amount": 5, "hp": e1hp - 62, "by": p3.id, "cycle": 2 },
		{ "type": "counter", "unit": e1.id, "target": p1.id, "result": _res(12), "target_hp": p1hp - 12, "name": "Counter", "cycle": 2 },
		{ "type": "heal", "unit": p1.id, "amount": 6, "hp": p1hp - 6, "cycle": 3 },
		{ "type": "status", "unit": e1.id, "status": "scorched", "by": p3.id, "cycle": 3 },
		{ "type": "status", "unit": p2.id, "status": "frost_ward", "by": p3.id, "cycle": 3 },
		{ "type": "ward_break", "unit": p2.id, "source": "frost_ward", "by": p3.id, "what": "detonation", "cycle": 3 },
		{ "type": "attack", "unit": p1.id, "target": e1.id, "result": _res(999), "target_hp": 0, "ko": true, "cycle": 3 },
		{ "type": "ko", "unit": e1.id, "by": p1.id, "cycle": 3 },
		{ "type": "battle_end", "winner": "player", "cycle": 3 },
	]
	var s := BWBattleStats.tally(h, u)
	var a: Dictionary = s.units[p1.id]
	t.eq(s.winner, "player", "winner read from battle_end")
	t.eq(s.rounds, 3, "rounds = the last cycle")
	t.eq(a.dealt.basic, 20 + (e1hp - 62), "p1 basic: the crit plus the KO blow counted as HP left, not 999")
	t.eq([a.crits, a.misses, a.attempts, a.kos], [1, 1, 3, 1], "p1 crits / misses / swings / KOs")
	t.eq(a.taken, 12, "p1 took the counter")
	t.eq(a.healed, 6, "p1 healed")
	var b: Dictionary = s.units[p2.id]
	t.eq([b.dealt.skill, b.dealt.ground], [40, 22], "p2 skill 30+10, ground 15+7 (detonation)")
	var c: Dictionary = s.units[p3.id]
	t.eq([c.dealt.chain, c.statuses, c.wards], [5, 1, 1], "p3 chain 5, one status on a foe (the ward on an ally isn't), one ward save")
	t.eq(s.units[e1.id].taken, e1hp, "e1 lost exactly its HP")
	t.ok(s.units[e1.id].downed, "e1 downed")
	t.eq(s.units[e1.id].dealt.basic, 12, "a counter is a basic swing")
	t.eq(s.mvp, p1.id, "MVP: the biggest score")
	t.eq(int(a.score), int(a.dealt_total) + BWBattleStats.KO_PTS, "MVP score = dealt + KO points")
	var kinds: Array = s.highlights.map(func(x): return x.kind)
	t.ok(s.highlights.size() <= BWBattleStats.MAX_HIGHLIGHTS and "hit" in kinds, "highlights: at most 3, the big hit among them")
	var all := BWBattleStats.pick_highlights([
		{ "kind": "hit", "score": 999.0, "text": "a" }, { "kind": "hit", "score": 50.0, "text": "b" },
		{ "kind": "ward", "score": 24.0, "text": "c" }], 3)
	t.eq(all.map(func(x): return x.text), ["a", "c"], "one highlight per kind, best first")
	t.ok(str(s.highlights[0].text).find("999") >= 0 and str(s.highlights[0].text).find(p1.name) >= 0,
		"the best hit names its unit and its roll: %s" % s.highlights[0].text)
	t.eq(s.wrong, "", "no 'what went wrong' on a win")
	var det: Array = s.highlights.filter(func(x): return x.kind == "detonation")
	if not det.is_empty():
		t.ok(str(det[0].text).find("2 foes") >= 0 and str(det[0].text).find("22") >= 0, "the detonation groups per paint: %s" % det[0].text)
	else:
		t.ok(true, "detonation ranked below the top 3")


func test_undo_takes_back_crossing(t) -> void:
	var u := _units()
	var p1: BWUnit = u[0]
	var mx := p1.max_hp()
	var h: Array = [
		{ "type": "move", "unit": p1.id, "path": [], "cycle": 1 },
		{ "type": "tile_damage", "unit": p1.id, "amount": 8, "cause": "fire_cross", "hp": mx - 8, "source": u[3].id, "cycle": 1 },
		{ "type": "undo_move", "unit": p1.id, "hp": mx, "cycle": 1 },
	]
	var s := BWBattleStats.tally(h, u)
	t.eq(s.units[p1.id].taken, 0, "an undone move's fire damage is taken back")
	t.eq(s.units[u[3].id].dealt_total, 0, "and the tile's owner loses the credit")


func test_loss_reads(t) -> void:
	var u := _units()
	var p1: BWUnit = u[0]
	var h: Array = [
		{ "type": "attack", "unit": u[3].id, "target": p1.id, "result": _res(40), "target_hp": p1.max_hp() - 40, "cycle": 1 },
		{ "type": "attack", "unit": u[4].id, "target": u[1].id, "result": _res(10), "target_hp": u[1].max_hp() - 10, "cycle": 1 },
		{ "type": "battle_end", "winner": "enemy", "cycle": 1 },
	]
	var s := BWBattleStats.tally(h, u)
	t.eq(s.wrong, "%s took 80%% of the enemy's damage." % p1.name, "focus fire read")
	h[1].target = p1.id
	h[0].result = _res(10)
	h[0].target_hp = 200
	h.insert(2, { "type": "attack", "unit": u[0].id, "target": u[3].id, "result": _res(5), "target_hp": 100, "cycle": 1 })
	h.insert(2, { "type": "attack", "unit": u[0].id, "target": u[4].id, "result": _res(5), "target_hp": 100, "cycle": 1 })
	var s2 := BWBattleStats.tally(h, u)
	t.ok(s2.wrong.find(p1.name) >= 0, "all on p1: %s" % s2.wrong)
	var h3: Array = [
		{ "type": "attack", "unit": u[3].id, "target": u[0].id, "result": _res(10), "target_hp": 100, "cycle": 1 },
		{ "type": "attack", "unit": u[4].id, "target": u[1].id, "result": _res(10), "target_hp": 100, "cycle": 1 },
		{ "type": "attack", "unit": u[5].id, "target": u[2].id, "result": _res(10), "target_hp": 100, "cycle": 1 },
		{ "type": "attack", "unit": u[0].id, "target": u[3].id, "result": _res(5), "target_hp": 100, "cycle": 1 },
		{ "type": "attack", "unit": u[0].id, "target": u[4].id, "result": _res(5), "target_hp": 100, "cycle": 1 },
		{ "type": "battle_end", "winner": "enemy", "cycle": 1 },
	]
	var s3 := BWBattleStats.tally(h3, u)
	t.eq(s3.wrong, "No one landed a hit on their %s (%s)." % [u[5].weapon_class, u[5].name], "an enemy nobody reached")
	t.eq(BWBattleStats.tally([], u).wrong, "", "empty history: no verdict")


## Real fights, AI on both sides: every unit's taken − healed is exactly
## the HP it lost, and dealt never exceeds what the other side took.
func test_real_battles_match_hp(t) -> void:
	var roster := BWData.table("roster")
	var maps := ["arena", "paintball", "tinderbox", "bridge"]
	var seen := {}
	for i in maps.size():
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % maps[i]), 700 + i)
		var p: Array = []
		var e: Array = []
		for k in 3:
			p.append(BWUnit.from_roster(roster[(i * 3 + k) % roster.size()]))
			e.append(BWUnit.from_roster(roster[(i * 3 + k + 10) % roster.size()]))
		b.setup(p, e)
		var start := {}
		for x in b.units:
			start[x.id] = x.hp
		var guard := 0
		while not b.over and guard < 900:
			BWAI.take_turn(b)
			guard += 1
		var s := BWBattleStats.tally(b.history, b.units)
		var dealt := { "player": 0, "enemy": 0 }
		var taken := { "player": 0, "enemy": 0 }
		for x in b.units:
			var r: Dictionary = s.units[x.id]
			t.eq(int(r.taken) - int(r.healed), int(start[x.id]) - x.hp,
				"%s fight %d: %s taken − healed = HP lost" % [maps[i], i, x.name])
			dealt[x.team] += int(r.dealt_total)
			taken[x.team] += int(r.taken)
			var parts := 0
			for k in BWBattleStats.BUCKETS:
				parts += int(r.dealt[k])
				if int(r.dealt[k]) > 0:
					seen[k] = true
			t.eq(parts, int(r.dealt_total), "the four buckets add up")
			t.eq(r.downed, not x.alive(), "%s downed matches" % x.name)
		t.ok(dealt.player <= taken.enemy and dealt.enemy <= taken.player, "dealt never exceeds the other side's loss")
		t.eq(s.winner, b.winner, "winner")
		var kos := 0
		for x in b.units:
			kos += int(s.units[x.id].kos)
		t.ok(kos <= b.units.filter(func(x): return not x.alive()).size(), "KOs ≤ units down")
		if b.winner == "enemy":
			t.ok(s.wrong != "", "a loss has a verdict: %s" % s.wrong)
		if b.winner == "player":
			t.ok(s.mvp != "", "a win has an MVP")
	t.ok(seen.has("basic") and seen.has("skill"), "real fights fill the basic and skill buckets (seen %s)" % [seen.keys()])


func test_run_stats_save(t) -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var r := BWRun.start(ids, 4321)
	var deployed := r.squad.slice(0, 3)
	var enemies := r.enemies_for(1)
	r.prepare_for_battle(deployed)
	var b := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 9)
	b.setup(deployed, enemies)
	var guard := 0
	while not b.over and guard < 900:
		BWAI.take_turn(b)
		guard += 1
	var won := b.winner == "player"
	var rep := r.after_fight(won, deployed, enemies.filter(func(x): return not x.alive()), enemies, b.history)
	t.ok(rep.has("stats") and rep.stats.units.has(deployed[0].id), "the report carries the battle summary")
	t.eq(int(r.stats.won) + int(r.stats.lost), 1, "the record counts the fight")
	var total := 0
	for u in deployed:
		t.eq(int(r.stats.units[u.id].fights), 1, "%s deployed once" % u.name)
		total += int(r.stats.units[u.id].damage)
	t.ok(total > 0, "damage tallied")
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(back.stats.units, r.stats.units, "stats survive a save")
	t.eq([back.stats.won, back.stats.lost], [r.stats.won, r.stats.lost], "record survives a save")
	t.eq(typeof(back.stats.units[deployed[0].id].kos), TYPE_INT, "counts come back as ints")
	var old := r.to_dict()
	old.erase("stats")
	old.version = 2
	var mig := BWRun.from_dict(JSON.parse_string(JSON.stringify(old)))
	t.eq(mig.stats.untracked, r.fight - 1, "v2 save: earlier fights untracked")
	t.ok(mig.stats.units.is_empty(), "v2 save: no per-unit stats invented")
	t.eq(BWEndScreen.run_mvp(r.stats.units) != "", true, "the run has an MVP")

extends RefCounted
## D353-D358: the run schedule as data (BWSchedule.TABLE), the cards each
## fight offers, the 6v6 pool's no-repeat draw, the second Split Front map, the
## Twins at fight 4, weather rules on cards, and the v11 -> v12 save migration.


func _ids() -> Array:
	return BWData.table("roster").map(func(row): return str(row.id)).slice(0, BWRun.SQUAD)


func _run(s: int = 4242, at: int = 1, picks: Dictionary = {}) -> BWRun:
	BWEncounters.RATE = 0.0
	var r := BWRun.start(_ids(), s)
	while r.fight < at:
		if BWRooms.has_choice(r.fight):
			BWRooms.offer(r)
			BWRooms.choose(r, int(picks.get(r.fight, 0)))
		_play(r)
	return r


func _play(r: BWRun) -> Dictionary:
	var e := r.enemies_for(r.fight)
	for x in e:
		x.hp = 0
	return r.after_fight(true, r.squad.slice(0, 3), e, e, [])


func _restore() -> void:
	BWEncounters.RATE = BWEncounters.DEFAULT_RATE


func test_schedule_table(t) -> void:
	var want := {
		1: ["single"], 2: ["single"], 3: ["standard", "hard"], 4: ["obelisks", "twins"], 5: ["split", "split"],
		6: ["standard", "hard"], 7: ["standard", "six"], 8: ["six", "six"], 9: ["standard", "six"], 10: ["six", "six"], 11: ["giant"],
	}
	for n in want:
		t.eq(BWSchedule.slots(n), want[n], "fight %d's slots" % n)
	for n in [1, 2, 11]:
		t.ok(not BWRooms.has_choice(n), "fight %d: no choice" % n)
	for n in range(3, 11):
		t.ok(BWRooms.has_choice(n), "fight %d: a choice" % n)
	t.eq(range(1, 11).filter(func(n): return BWRooms.queued(n)), [1, 2, 3, 6, 7, 9], "the 3v3 queue fights")
	t.eq(BWRun.TWINS_FIGHT, 4, "the Twins sit at fight 4 (D355)")
	t.ok(BWRun.is_fixed(BWRun.BOSS_FIGHT) and not BWRun.is_fixed(4) and not BWRun.is_fixed(5), "only the Giant is fixed")
	var maps := BWSchedule.SIX_POOL.map(func(e): return str(e.map))
	t.eq(maps, ["splitfront", "fords", "keep", "stronghold", "horde"], "the 6v6 pool: both Split Fronts, both castles, the Horde")
	for m in maps:
		t.ok(FileAccess.file_exists("res://maps/%s.json" % m), "%s ships" % m)


func test_cards_offered_per_fight(t) -> void:
	for pick in [0, 1]:
		var r := _run(4242 + pick)
		while r.fight <= BWRun.FIGHTS:
			var n := r.fight
			var cs := BWRooms.offer(r)
			var kinds: Array = cs.map(func(c): return str(c.kind))
			match n:
				1, 2:
					t.eq(cs, [], "fight %d: no offer" % n)
				3, 6:
					t.eq(kinds, ["standard", "hard"], "fight %d: Standard vs Hard" % n)
				4:
					t.eq(cs.map(func(c): return str(c.get("boss", ""))), ["obelisks", "twins"], "fight 4: the Obelisks vs the Twins")
					t.eq(cs.map(func(c): return str(c.map)), ["obelisks", "court"], "fight 4: on their own maps")
					t.ok(cs.all(func(c): return not c.has("weather")), "fight 4: no weather on a boss")
				5:
					t.eq(cs.map(func(c): return str(c.get("mode", ""))), ["splitfront", "splitfront"], "fight 5: two Split Fronts")
					t.ok(cs[0].map != cs[1].map, "fight 5: two maps (%s / %s)" % [cs[0].map, cs[1].map])
					t.ok(str(cs[0].divider) != str(cs[1].divider), "fight 5: two dividers (%s / %s)" % [cs[0].divider, cs[1].divider])
				7, 9:
					t.eq(kinds, ["standard", "six"], "fight %d: a 3v3 room vs a 6v6" % n)
				8, 10:
					t.eq(kinds, ["six", "six"], "fight %d: two 6v6s" % n)
					t.ok(cs[0].map != cs[1].map, "fight %d: two different 6v6 maps" % n)
			for c in cs:
				if str(c.get("boss", "")) != "twins" and not c.has("encounter"):
					t.eq(c.enemies.size(), BWRun.deploy_count_of(str(c.map)), "fight %d %s: the map's count of enemy ids" % [n, c.map])
				if c.kind == BWRooms.SIX:
					t.ok(str(c.mode) in BWRun.SIX_MODES, "fight %d: %s is a 6v6 mode" % [n, c.mode])
					t.ok(not c.has("encounter"), "no encounter on a 6v6 card")
			if not cs.is_empty():
				BWRooms.choose(r, pick)
				t.eq(r.map_for(n), str(cs[pick].map), "fight %d plays the chosen card's map" % n)
				t.eq(r.deploy_for(n), 6 if cs[pick].kind == BWRooms.SIX else 3, "fight %d: pre-battle fields the card's count" % n)
			_play(r)
	_restore()


func test_no_repeat_pool(t) -> void:
	# a fresh run: never a mode already played while an unplayed one is left
	var seen := {}
	for s in 40:
		var r := _run(500 + s)
		while r.fight <= BWRun.FIGHTS:
			var cs := BWRooms.offer(r)
			var played := BWRooms.played_modes(r)
			var left: Array = BWRun.SIX_MODES.filter(func(m): return not m in played)
			for i in cs.size():
				if cs[i].kind == BWRooms.SIX and BWSchedule.slots(r.fight)[i] == BWSchedule.SIX:
					seen[str(cs[i].map)] = true
					if not left.is_empty() and i == 0:
						t.ok(str(cs[i].mode) in left, "seed %d fight %d: %s not repeated while %s are fresh" % [s, r.fight, cs[i].mode, left])
			var six: Array = cs.filter(func(c): return c.kind == BWRooms.SIX)
			if six.size() == 2:
				t.ok(six[0].map != six[1].map, "seed %d fight %d: never one map twice in an offer" % [s, r.fight])
			if not cs.is_empty():
				BWRooms.choose(r, (s + r.fight) % cs.size())
			_play(r)
	t.eq(seen.size(), 5, "over 40 runs every pool map is offered (%s)" % [seen.keys()])
	# the pure draw: fresh mode first, then a fresh map, then anything; seeded
	var e := BWSchedule.draw_six(7, 8, 0, ["splitfront", "horde", "defend"], ["splitfront", "horde", "keep"], [])
	t.eq(e.mode, "storm", "the one mode not played")
	e = BWSchedule.draw_six(7, 8, 0, BWRun.SIX_MODES, ["splitfront", "keep", "stronghold", "horde"], [])
	t.eq(e.map, "fords", "every mode played: the unplayed map")
	e = BWSchedule.draw_six(7, 8, 1, BWRun.SIX_MODES, ["splitfront", "fords", "keep", "stronghold", "horde"], ["keep"])
	t.ok(not e.is_empty() and e.map != "keep", "all played: anything but the other card (%s)" % e.map)
	t.eq(BWSchedule.draw_six(9, 7, 1, [], [], []), BWSchedule.draw_six(9, 7, 1, [], [], []), "seeded")
	var els := {}
	for s in 30:
		var d := BWSchedule.dividers(s, 5, 2)
		t.ok(d[0] != d[1], "seed %d: two dividers differ" % s)
		els[d[0]] = true
	t.eq(els.size(), 3, "every element leads some run")
	_restore()


func test_weather_on_cards(t) -> void:
	var castles := 0
	for s in 60:
		var r := BWRun.start(_ids(), 900 + s)
		for n in range(5, 11):
			for c in BWRooms.roll(r, n):
				if c.has("weather"):
					t.ok(c.kind in [BWRooms.STANDARD, BWRooms.HARD] or str(c.get("mode", "")) in ["splitfront", "horde"],
						"seed %d fight %d: weather only on 3v3, Split Front and Horde cards (%s)" % [s, n, c.map])
				if str(c.get("mode", "")) in ["defend", "storm"]:
					castles += 1
					t.ok(not c.has("weather"), "no weather in a castle (D357)")
	t.ok(castles > 0, "castle cards were rolled (%d)" % castles)


func test_split_front_cards_reach_battle(t) -> void:
	var r := _run(4242, 5)
	var cs := BWRooms.offer(r)
	BWRooms.choose(r, 1)
	t.eq(r.map_for(5), "fords", "the Fords card plays the Fords")
	t.eq(r.mode_for(5), "splitfront", "as Split Front")
	t.eq(BWRooms.battle_opts(r, 5), { "divider": str(cs[1].divider) }, "the card's divider goes to the battle")
	var b := BWBattle.new(BWBoard.load_file("res://maps/fords.json"), 1)
	BWObjectives.configure(b, BWRooms.battle_opts(r, 5))
	var es := r.enemies_for(5)
	var ps := r.squad.slice(0, 6)
	b.setup(ps, es)
	t.eq(BWSplitFront.element(b), str(cs[1].divider), "the battle raises that divider")
	t.eq(BWSplitFront.divider_hexes(b).size(), 3, "three fords")
	var rep := _play(r)
	t.eq(str(r.room_log["5"].get("map", "")), "fords", "logged the Fords")
	t.eq(str(r.room_log["5"].get("divider", "")), str(cs[1].divider), "and its divider")
	t.eq(rep.loot.size(), BWRun.MODE_DROPS, "a 6v6 pays MODE_DROPS")
	_restore()


func test_fords_map(t) -> void:
	var b := BWBoard.load_file("res://maps/fords.json")
	t.eq(b.deploy_count, 6, "six a side")
	t.eq(str(b.objective.get("mode", "")), "splitfront", "a Split Front map")
	var div: Array = Array(b.objective.divider).map(func(p): return Vector2i(int(p[0]), int(p[1])))
	t.eq(div.size(), 3, "three divider hexes")
	t.ok(div.all(func(h): return h.x == int(b.objective.split_q) and b.is_passable(h)), "the fords stand on the split column")
	t.ok(absi(div[0].y - div[1].y) > 1 and absi(div[1].y - div[2].y) > 1, "spread out: three separate crossings")
	# with the fords blocked, west and east never meet (the gorge holds)
	var west: Vector2i = b.spawns.player[0]
	var blocked := {}
	for h in div:
		blocked[h] = true
	var reach := b.reachable(west, 99, blocked)
	t.ok(reach.keys().all(func(h): return h.x < int(b.objective.split_q)), "without a ford nobody crosses")
	t.ok(b.reachable(west, 99).keys().any(func(h): return h.x > int(b.objective.split_q)), "through a ford you do")


func test_twins_at_fight_4(t) -> void:
	var r := _run(4242, 4)
	var cs := BWRooms.offer(r)
	BWRooms.choose(r, 1)
	t.ok(r.is_twins(), "the Twins card taken: it's the Twins")
	t.eq(r.map_for(4), "court", "on the court")
	var tw := r.enemies_for(4)
	t.eq(tw.map(func(u): return u.encounter), ["twin", "twin"], "Noon and Dusk")
	t.eq(tw[0].level, r.squad_level(), "built at the squad's level (fight 4)")
	t.ok(BWTwins.TWINS_HP * BWTwins.TWINS_MULT < 2.6 * 1.25, "tuned down from the fight-7 values (D355/D477: HP x%.2f, stats x%.2f)" % [BWTwins.TWINS_HP, BWTwins.TWINS_MULT])
	var ob := _run(4242, 4)
	BWRooms.offer(ob)
	BWRooms.choose(ob, 0)
	t.ok(not ob.is_twins(), "the Obelisks card: not the Twins")
	t.eq(ob.map_for(4), "obelisks", "the Obelisks map")
	var rep := _play(r)
	t.ok(rep.has("twins_reward"), "a Twins win pays the pick (D258)")
	t.eq(str(r.room_log["4"].get("boss", "")), "twins", "logged")
	t.ok(not _play(ob).has("twins_reward"), "the Obelisks don't")
	_restore()


## D358: a v11 save (the D325 schedule) loads mid-run: its log and queue carry
## over; an offer that no longer fits its fight is dropped and re-rolled.
func test_save_migration(t) -> void:
	var r := _run(4242, 9)
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	d.version = 11
	d.room_offer = { "fight": 9, "chosen": 1, "rooms": [
		{ "kind": "standard", "map": "arena", "fight": 9, "enemies": [] },
		{ "kind": "hard", "map": "lake", "fight": 9, "enemies": [] }] }
	var old := BWRun.from_dict(d)
	t.eq(old.fight, 9, "still at fight 9")
	t.eq(old.room_log.size(), r.room_log.size(), "the log carries over")
	t.eq(old.map_queue, r.map_queue, "the queue carries over")
	t.eq(BWRooms.chosen_index(old), -1, "the v11 Standard / Hard offer at fight 9 is dropped")
	var cs := BWRooms.offer(old)
	t.eq(cs.map(func(c): return str(c.kind)), ["standard", "six"], "re-rolled as the new fight 9")
	# a v11 save at fight 3 keeps its offer (it still fits)
	var r3 := _run(77, 3)
	var o3 := BWRooms.offer(r3)
	BWRooms.choose(r3, 1)
	var d3: Dictionary = JSON.parse_string(JSON.stringify(r3.to_dict()))
	d3.version = 11
	var old3 := BWRun.from_dict(d3)
	t.eq(BWRooms.offer(old3), o3, "fight 3's offer still fits: kept")
	t.eq(BWRooms.chosen_index(old3), 1, "and its choice")
	# a v11 save at fight 7 (the old Twins slot, no offer) gets the new fight 7
	var r7 := _run(77, 7)
	var d7: Dictionary = JSON.parse_string(JSON.stringify(r7.to_dict()))
	d7.version = 11
	d7.room_offer = {}
	t.eq(BWRooms.offer(BWRun.from_dict(d7)).map(func(c): return str(c.kind)), ["standard", "six"], "fight 7: a 3v3 room vs a 6v6")
	# a v12 boss offer round-trips with its fields
	var r4 := _run(5, 4)
	var o4 := BWRooms.offer(r4)
	BWRooms.choose(r4, 1)
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r4.to_dict())))
	t.eq(BWRooms.offer(back), o4, "a boss offer survives a save")
	t.ok(back.is_twins(), "and the Twins choice")
	t.eq(int(r4.to_dict().version), 13, "saves are v13 (D446: Keystones v3)")
	_restore()

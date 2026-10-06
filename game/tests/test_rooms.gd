extends RefCounted
## D186-D189: the room choice before each fight (not the Obelisks, not the
## Giant): two rooms, each its own map and enemies; Hard is tougher and pays
## more; the chosen room reaches combat; saves keep the offer.
## D208: fights 1-2 have no choice (one battle, the queue's front map); the
## choice starts at fight 3. These tests hold the encounter rate at 0 (the
## encounters have their own suite, test_encounters.gd, which restores it).


func _run(s: int = 4242, at: int = 1) -> BWRun:
	BWEncounters.RATE = 0.0
	var ids: Array = BWData.table("roster").map(func(row): return str(row.id)).slice(0, BWRun.SQUAD)
	var r := BWRun.start(ids, s)
	while r.fight < at:
		_play(r)
	return r


## Play the current fight on paper (won, every enemy down).
func _play(r: BWRun, won: bool = true) -> Dictionary:
	var e := r.enemies_for(r.fight)
	for x in e:
		x.hp = 0
	return r.after_fight(won, r.squad.slice(0, 3), e if won else [], e, [])


func test_two_distinct_rooms(t) -> void:
	var r := _run(4242, 3)
	var rooms := BWRooms.offer(r)
	t.eq(rooms.size(), 2, "two rooms")
	t.eq(rooms.map(func(x): return x.kind), ["standard", "hard"], "Standard, then Hard")
	t.ok(rooms[0].map != rooms[1].map, "distinct maps (%s / %s)" % [rooms[0].map, rooms[1].map])
	t.ok(rooms[0].map in BWRun.MAP_POOL and rooms[1].map in BWRun.MAP_POOL, "both from the pool")
	t.eq(rooms[0].enemies.size(), 3, "three enemies a room")
	t.ok(rooms[0].enemies.all(func(id): return not id in rooms[1].enemies), "distinct squads")
	for room in rooms:
		for id in room.enemies:
			t.ok(r.unit(id) == null, "%s is not in your squad" % id)
	t.eq(r.map_queue.slice(0, 2), rooms.map(func(x): return x.map), "the queue's front two")


func test_deterministic_per_seed(t) -> void:
	var a := BWRooms.offer(_run(77, 3))
	var b := BWRooms.offer(_run(77, 3))
	t.eq(a, b, "same seed, same two rooms")
	var c := BWRooms.offer(_run(78, 3))
	t.ok(c != a, "another seed, other rooms")
	var r := _run(77, 3)
	t.eq(BWRooms.offer(r), BWRooms.offer(r), "offering twice changes nothing")


func test_no_choice_at_obelisks_or_giant(t) -> void:
	t.ok(not BWRooms.has_choice(4), "fight 4 (Obelisks): no choice")
	t.ok(not BWRooms.has_choice(BWRun.BOSS_FIGHT), "the Giant: no choice")
	for n in [3, 5, 6, 7, 8, 9, 10]:
		t.ok(BWRooms.has_choice(n), "fight %d offers rooms" % n)
	var r := _run()
	for n in 3:
		_play(r)
	t.eq(r.fight, 4, "at fight 4")
	t.eq(BWRooms.offer(r), [], "no rooms offered at fight 4")
	t.ok(not BWRooms.choose(r, 1), "and none can be chosen")
	t.eq(r.map_for(4), "obelisks", "fight 4 stays the Obelisks")
	t.eq(r.map_for(BWRun.BOSS_FIGHT), "arena", "the Giant stays on the arena")
	var rep := _play(r)
	t.eq(rep.room, "standard", "fight 4 plays as a standard room")
	t.eq(BWRooms.offer(r).size(), 2, "fight 5 offers rooms again")


func test_hard_is_tougher_and_pays_more(t) -> void:
	var r := _run()
	for n in [3, 5, 6, 9, 10]:
		var rooms: Array = BWRooms.roll(r, n)
		var se := r.enemies_for(n, rooms[0])
		var he := r.enemies_for(n, rooms[1])
		var sl := se.map(func(u): return u.level)
		var hl := he.map(func(u): return u.level)
		t.ok(hl.min() >= sl.max(), "fight %d: Hard levels %s, no lower than %s" % [n, hl, sl])
		t.ok(_stat_total(he) > _stat_total(se), "fight %d: Hard stat total %d > %d" % [n, _stat_total(he), _stat_total(se)])
		t.ok(_power(he) > _power(se), "fight %d: Hard squad is stronger (%d vs %d)" % [n, _power(he), _power(se)])
		t.ok(he.all(func(u): return BWRun.ARMOR_SLOTS.filter(func(s): return u.equipment.has(s)).size() >= \
			mini(BWRun.enemy_curve(n).armor + 1, 3)), "fight %d: Hard wears one more armour piece" % n)
	# pay: a tier up and one extra drop on a win
	var s := _run(5, 3)
	BWRooms.offer(s)
	var rep_s := _play(s)
	t.eq(rep_s.room, "standard", "no choice made: the Standard room")
	t.eq(rep_s.loot.size(), 3, "Standard: one drop per enemy")
	t.ok(rep_s.loot.all(func(it): return it.tier == "D"), "Standard: the fight's tier")
	var h := _run(5, 3)
	BWRooms.choose(h, 1)
	var rep_h := _play(h)
	t.eq(rep_h.room, "hard", "the Hard room was played")
	t.eq(rep_h.loot.size(), 4, "Hard: one extra drop")
	t.ok(rep_h.loot.all(func(it): return it.tier == "C"), "Hard: every drop a tier up")
	var l := _run(5, 3)
	BWRooms.choose(l, 1)
	t.eq(_play(l, false).loot.size(), 0, "a lost Hard room pays nothing")
	t.ok(BWRooms.reward_text(h, { "kind": "hard" }) != BWRooms.reward_text(h, { "kind": "standard" }), "the reward lines differ")


func test_chosen_room_reaches_combat(t) -> void:
	var r := _run(4242, 3)
	var rooms := BWRooms.offer(r)
	t.eq(r.map_for(3), rooms[0].map, "before a choice: the Standard map")
	BWRooms.choose(r, 1)
	t.eq(r.map_for(r.fight), rooms[1].map, "the Hard room's map")
	var e := r.enemies_for(r.fight)
	t.eq(e.map(func(u): return u.id.split("_f")[0]), rooms[1].enemies, "the Hard room's enemies")
	t.eq(e.map(func(u): return u.level), r.enemies_for(3, rooms[1]).map(func(u): return u.level), "built as Hard")
	var rep := _play(r)
	t.eq(rep.map, rooms[1].map, "the report names the map played")
	t.eq(r.room_log["3"], { "kind": "hard", "map": rooms[1].map }, "logged")
	t.ok(not rooms[1].map in r.map_queue, "the played map left the queue")
	t.eq(r.map_queue.back(), rooms[0].map, "the unchosen map went to the back of the queue")
	t.ok(BWRooms.offer(r).all(func(x): return x.map != rooms[1].map), "the next offer doesn't repeat it")


## D187/D208: nine queued fights (two openers, seven choices), nine pool
## maps: always Standard plays each once; always Hard too (the last Hard room
## may replay a map, it can't always be fresh).
func test_maps_over_a_run(t) -> void:
	for pick in [0, 1]:
		var r := _run(4242 + pick)
		var played: Array = []
		var offered: Array = []
		var before: Array = []
		while r.fight <= BWRun.FIGHTS:
			if BWRooms.has_choice(r.fight):
				var rooms := BWRooms.offer(r)
				t.ok(rooms[0].map != rooms[1].map, "fight %d: two different maps" % r.fight)
				offered.append(rooms.map(func(x): return x.map))
				before.append(played.duplicate())
				BWRooms.choose(r, pick)
			if BWRooms.queued(r.fight):
				played.append(r.map_for(r.fight))
			_play(r)
		var uniq: Dictionary = {}
		for m in played:
			uniq[m] = true
		t.eq(played.size(), 9, "nine queued fights")
		t.eq(offered.size(), 7, "seven choice fights (3, 5-10)")
		if pick == 0:
			t.eq(uniq.size(), 9, "always Standard: every pool map once (%s)" % [played])
		else:
			t.ok(uniq.size() >= 8, "always Hard: at most one replay (%s)" % [played])
		for i in 6:
			t.ok(not offered[i][0] in before[i] and not offered[i][1] in before[i],
				"offer %d: no played map while fresh ones remain" % (i + 1))


func test_save_load_mid_choice(t) -> void:
	var r := _run(4242, 3)
	var rooms := BWRooms.offer(r)
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(BWRooms.offer(back), rooms, "a loaded run shows the same two rooms")
	t.eq(BWRooms.chosen_index(back), -1, "still to choose")
	t.eq(back.map_queue, r.map_queue, "the map queue")
	t.eq(back.room_log, r.room_log, "the room log")
	BWRooms.choose(r, 1)
	var back2 := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(BWRooms.chosen_index(back2), 1, "a made choice survives the save")
	t.eq(back2.map_for(back2.fight), rooms[1].map, "and its map")
	t.eq(back2.enemies_for(back2.fight).map(func(u): return u.id), r.enemies_for(r.fight).map(func(u): return u.id), "and its enemies")
	t.eq(back2.enemies_for(back2.fight).map(func(u): return u.stats), r.enemies_for(r.fight).map(func(u): return u.stats), "built the same")
	# a v6 save (no rooms): derived from map_order, nothing on offer
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	d.version = 6
	for k in ["map_queue", "room_offer", "room_log"]:
		d.erase(k)
	var old := BWRun.from_dict(d)
	t.eq(old.room_log, { "1": { "kind": "standard", "map": str(r.map_order[0]) }, "2": { "kind": "standard", "map": str(r.map_order[1]) } }, "v6: fights 1-2 played their D145 slots")
	t.eq(old.map_queue, r.map_order.slice(2), "v6: the rest of the order is the queue")
	t.eq(BWRooms.chosen_index(old), -1, "v6: nothing on offer yet")
	t.eq(BWRooms.offer(old).size(), 2, "v6: the room screen rolls a fresh offer")


func _stat_total(es: Array) -> int:
	var n := 0
	for u in es:
		for k in BWUnit.STATS:
			n += u.stat(k)
	return n


func _power(es: Array) -> int:
	var n := 0
	for u in es:
		n += u.max_hp()
		for k in BWUnit.STATS:
			n += 4 * u.stat(k)
	return n


## D208: fights 1 and 2 go straight to one battle: no offer, no choice, the
## queue's front map and the Standard squad; the choice starts at fight 3.
func test_no_choice_in_fights_1_and_2(t) -> void:
	var r := _run()
	for n in [1, 2]:
		t.ok(not BWRooms.has_choice(n), "fight %d: no room choice" % n)
		t.eq(BWRooms.offer(r), [], "fight %d: nothing offered" % n)
		t.ok(not BWRooms.choose(r, 1), "fight %d: nothing to choose" % n)
		t.eq(r.map_for(n), str(r.map_queue[0]), "fight %d: the queue's front map" % n)
		t.eq(r.enemies_for(n).size(), 3, "fight %d: three enemies" % n)
		var played := r.map_for(n)
		var rep := _play(r)
		t.eq(rep.room, "standard", "fight %d plays as Standard" % n)
		t.ok(not played in r.map_queue, "fight %d's map left the queue" % n)
	t.eq(r.fight, 3, "at fight 3")
	t.eq(BWRooms.offer(r).size(), 2, "fight 3 offers Standard vs Hard")

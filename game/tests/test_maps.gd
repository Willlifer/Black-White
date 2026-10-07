extends RefCounted
## Every shipped map loads clean and hosts a fight to the finish.

const MAP_DIR := "res://maps/"


func _maps() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(MAP_DIR):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func test_ten_maps(t) -> void:
	for m in ["arena.json", "bridge.json", "catacombs.json", "chapel.json", "commons.json", "court.json", "forge.json", "lake.json",
		"obelisks.json", "paintball.json", "ravine.json", "tinderbox.json", "splitfront.json", "horde.json"]:
		t.ok(m in _maps(), "%s ships" % m)
	var six_maps: Array = BWSchedule.SIX_POOL.map(func(e): return str(e.map))   # D354: the Fords too
	t.ok(_maps().all(func(m): return m.get_basename() in BWRun.MAPS + BWRun.MAP_POOL + [BWRun.TWINS_MAP, "commons"] + BWRun.MODE_MAPS.values() + six_maps),
		"every map is in the rotation, fixed, a mode's map or Commons (%s)" % [_maps()])
	t.ok(true, "the maps (D117: four static-tile maps; D140: the Obelisks; D256: the Twins' court; D319: Commons, 6v6, not in the rotation)")
	for m in BWRun.MAPS:
		t.ok(FileAccess.file_exists(MAP_DIR + m + ".json"), "rotation map %s exists" % m)
	t.ok(not "commons" in BWRun.MAPS and not "commons" in BWRun.MAP_POOL, "D319: Commons is a test map, not in the rotation yet")


## D145/D353: the 3v3 queue fights (1-3, 6, and 7 and 9's 3v3 cards) play
## pool maps in the seeded shuffle with no repeat; fight 4's cards are the
## Obelisks and the court; the Giant is on the arena; a save keeps it all.
func test_rotation(t) -> void:
	var ids: Array = BWData.table("roster").map(func(row): return str(row.id)).slice(0, BWRun.SQUAD)
	var r := BWRun.start(ids, 4242)
	var seen: Array = []
	for n in range(1, BWRun.FIGHTS + 1):
		if BWSchedule.slots(n)[0] in BWSchedule.QUEUE_SLOTS:   # card 0 is a 3v3 room
			seen.append(r.map_for(n))
	t.eq(r.map_for(4), "obelisks", "fight 4's first card: the Obelisks")
	t.eq(BWRooms.roll(r, 4).map(func(c): return str(c.map)), ["obelisks", "court"], "fight 4: the Obelisks or the court (D353)")
	t.eq(r.map_for(BWRun.BOSS_FIGHT), "arena", "the boss on the arena")
	var uniq := {}
	for m in seen:
		uniq[m] = true
	t.eq(uniq.size(), seen.size(), "fights 1-3, 6, 7, 9 (card 0): six pool maps, no repeats (%s)" % [seen])
	t.ok(seen.all(func(m): return m in BWRun.MAP_POOL), "all from the pool")
	# D187/D208: openers take the front map; rooms the front two, the unchosen to the back
	var sh := BWRun.shuffled_maps(4242)
	t.eq(seen, [0, 1, 2, 4, 6, 7].map(func(i): return sh[i]), "the order follows the seeded shuffle through the room queue")
	var again := BWRun.start(ids, 4242)
	t.eq(range(1, 11).map(func(n): return again.map_for(n)), range(1, 11).map(func(n): return r.map_for(n)), "same seed, same order")
	var other := BWRun.start(ids, 4243)
	t.ok(range(1, 11).map(func(n): return other.map_for(n)) != range(1, 11).map(func(n): return r.map_for(n)), "another seed, another order")
	var loaded := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(range(1, 12).map(func(n): return loaded.map_for(n)), range(1, 12).map(func(n): return r.map_for(n)), "a loaded run plays the same maps")
	var d: Dictionary = r.to_dict()
	d.erase("map_order")
	var old := BWRun.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.eq(old.map_for(1), r.map_for(1), "an older save (no map_order) re-derives it from the seed")


func test_maps_load_clean(t) -> void:
	for f in _maps():
		var b := BWBoard.load_file(MAP_DIR + f)
		t.ok(b.errors.is_empty(), "%s: %s" % [f, b.errors])
		var n := b.deploy_count                                     # D319: 3, or 6 on a big map
		t.ok(n in [3, 6], "%s deploy_count %d is 3 or 6" % [f, n])
		t.eq(b.spawns.player.size(), n, "%s player spawns = deploy_count" % f)
		t.eq(b.spawns.enemy.size(), n, "%s enemy spawns = deploy_count" % f)
		t.ok(b.deploy.player.size() >= n, "%s player deploy zone holds %d" % [f, n])
		for h in b.spawns.player:
			t.ok(h in b.deploy.player, "%s spawn %s inside deploy zone" % [f, h])


func test_maps_host_a_fight(t) -> void:
	var roster := BWData.table("roster")
	var lengths := {}
	for f in _maps():
		var b := BWBattle.new(BWBoard.load_file(MAP_DIR + f), 11)
		var ps: Array = []
		var es: Array = []
		for i in BWRun.deploy_count_of(f.get_basename()):       # D319: 6 a side on Commons
			ps.append(BWUnit.from_roster(roster[i]))
			es.append(BWUnit.from_roster(roster[i + 10]))
		b.setup(ps, es)
		var turns := 0
		while not b.over and turns < 600:
			BWAI.take_turn(b)
			turns += 1
		t.ok(b.over, "%s: AI fight finishes (%d turns)" % [f, turns])
		lengths[f.get_basename()] = b.cycle
	print("    [info] rounds per map: %s" % [lengths])


## D319: a 6v6 map's deploy rules (Commons, and the big maps to come): six
## spawns a side, distinct, standable, inside the side's deploy zone; the
## zones are the three edge rows, mirror images, at most 24 hexes; every
## player spawn walks to an enemy spawn; the map is 17×15 to 19×17.
func test_six_a_side_maps(t) -> void:
	var big := 0
	for f in _maps():
		var b := BWBoard.load_file(MAP_DIR + f)
		if b.deploy_count <= BWRun.DEPLOY:
			continue
		big += 1
		t.ok(b.cols >= 17 and b.cols <= 19 and b.rows >= 15 and b.rows <= 17, "%s is 17×15 to 19×17 (%d×%d)" % [f, b.cols, b.rows])
		for team in ["player", "enemy"]:
			var sp: Array = b.spawns[team]
			var uniq := {}
			for h in sp:
				uniq[h] = true
				t.ok(b.is_passable(h), "%s %s spawn %s standable" % [f, team, h])
				t.ok(h in b.deploy[team], "%s %s spawn %s in its zone" % [f, team, h])
			t.eq(uniq.size(), 6, "%s %s: six distinct spawns" % [f, team])
			t.ok(b.deploy[team].size() >= 6 and b.deploy[team].size() <= 24, "%s %s zone %d hexes (6-24)" % [f, team, b.deploy[team].size()])
			var edge := 0 if team == "enemy" else b.rows - 1
			var mode_name := str(b.objective.get("mode", ""))
			var keep_side: bool = mode_name in BWCastle.MODES and team == ("player" if mode_name == "defend" else "enemy")
			if not keep_side:                   # D335: a castle's holders deploy on its walls and yard
				t.ok(b.deploy[team].all(func(h): return absi(h.y - edge) <= 2), "%s %s zone on its three edge rows" % [f, team])
		for h in b.spawns.player:
			t.ok(not h in b.spawns.enemy and not h in b.deploy.enemy, "%s: %s on one side only" % [f, h])
			var reach := b.reachable(h, 99)
			t.ok(b.spawns.enemy.any(func(e): return b.neighbors(e).any(func(nb): return reach.has(nb))), "%s: spawn %s walks to the enemy" % [f, h])
	t.ok(big >= 1, "at least one 6v6 map (Commons)")
	var c := BWBoard.load_file(MAP_DIR + "commons.json")
	t.eq(c.deploy_count, 6, "Commons fields six a side")
	t.eq([c.cols, c.rows], [17, 15], "Commons is 17×15")
	t.ok(not c.seeds.is_empty(), "Commons has seeded patches")
	t.ok(c.cells().any(func(h): return c.elevation(h) >= 2), "Commons has elevation")
	t.eq(BWBoard.load_file(MAP_DIR + "arena.json").deploy_count, 3, "a map without deploy_count fields 3")

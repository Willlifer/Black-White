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
	t.eq(_maps(), ["arena.json", "bridge.json", "catacombs.json", "chapel.json", "commons.json", "court.json", "forge.json", "lake.json",
		"obelisks.json", "paintball.json", "ravine.json", "tinderbox.json"], "the twelve maps (D117: four static-tile maps; D140: the Obelisks; D256: the Twins' court; D319: Commons, 6v6, not in the rotation)")
	for m in BWRun.MAPS:
		t.ok(FileAccess.file_exists(MAP_DIR + m + ".json"), "rotation map %s exists" % m)
	t.ok(not "commons" in BWRun.MAPS and not "commons" in BWRun.MAP_POOL, "D319: Commons is a test map, not in the rotation yet")


## D145: fight 4 is always the Obelisks, the boss is on the arena, and the
## other nine fights play the nine pool maps once each in a seeded shuffle,
## the same after a save and load.
func test_rotation(t) -> void:
	var ids: Array = BWData.table("roster").map(func(row): return str(row.id)).slice(0, BWRun.SQUAD)
	var r := BWRun.start(ids, 4242)
	var seen: Array = []
	for n in range(1, BWRun.FIGHTS + 1):
		if n != BWRun.OBJECTIVE_FIGHT and n != BWRun.TWINS_FIGHT:
			seen.append(r.map_for(n))
	t.eq(r.map_for(4), "obelisks", "fight 4 is the Obelisks")
	t.eq(r.map_for(BWRun.TWINS_FIGHT), "court", "fight 7 is the Twins' court (D256)")
	t.eq(r.map_for(BWRun.BOSS_FIGHT), "arena", "the boss on the arena")
	var sorted := seen.duplicate()
	sorted.sort()
	var uniq: Array = []
	for m in sorted:
		if not m in uniq:
			uniq.append(m)
	t.eq(uniq.size(), sorted.size(), "fights 1-3, 5-6, 8-10: eight pool maps, no repeats (D256: fight 7 is fixed)")
	t.ok(sorted.all(func(m): return m in BWRun.MAP_POOL), "all from the pool")
	# D187/D208: fights 1-2 take the front map; rooms take the front two from fight 3; always Standard plays the first,
	# the unchosen Hard map goes to the back: slots 0, 1, 2, 4, 6, 8, 5, 3 (D256: fight 7 takes none).
	var sh := BWRun.shuffled_maps(4242)
	t.eq(seen, [0, 1, 2, 4, 6, 8, 5, 3].map(func(i): return sh[i]), "the order follows the seeded shuffle through the room queue")
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

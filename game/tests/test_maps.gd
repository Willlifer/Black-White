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
	t.eq(_maps(), ["arena.json", "bridge.json", "catacombs.json", "chapel.json", "court.json", "forge.json", "lake.json",
		"obelisks.json", "paintball.json", "ravine.json", "tinderbox.json"], "the eleven maps (D117: four static-tile maps; D140: the Obelisks; D256: the Twins' court)")
	for m in BWRun.MAPS:
		t.ok(FileAccess.file_exists(MAP_DIR + m + ".json"), "rotation map %s exists" % m)


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
		t.eq(b.spawns.player.size(), 3, "%s player spawns" % f)
		t.eq(b.spawns.enemy.size(), 3, "%s enemy spawns" % f)
		t.ok(b.deploy.player.size() >= 3, "%s player deploy zone" % f)
		for h in b.spawns.player:
			t.ok(h in b.deploy.player, "%s spawn %s inside deploy zone" % [f, h])


func test_maps_host_a_fight(t) -> void:
	var roster := BWData.table("roster")
	var lengths := {}
	for f in _maps():
		var b := BWBattle.new(BWBoard.load_file(MAP_DIR + f), 11)
		var ps: Array = []
		var es: Array = []
		for i in 3:
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

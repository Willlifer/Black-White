extends RefCounted
## design/ELEMENTS.md, rule by rule, including the §5.3 containment asserts.


func _tiles(terrain: String = "neutral", n: int = 9) -> BWTiles:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": terrain, "elevation": 0 })
	return BWTiles.new(BWBoard.from_dict({ "name": "t", "cols": n, "rows": n, "cells": cells }))


const C := Vector2i(4, 4)


func _check_invariants(t, tl: BWTiles, where: String) -> void:
	for hex in tl.entries:
		var e: Dictionary = tl.entries[hex]
		if e.marker != "":
			t.ok(e.h == 0 and e.v == 0 and e.glaze == 0, "%s: marker hex %s holds no charge" % [where, hex])
		else:
			t.ok(e.h != 0 or e.v != 0, "%s: no neutral entry at %s" % [where, hex])
		if e.glaze > 0:
			t.ok(e.h != 0 or e.v != 0, "%s: glaze only on charge at %s" % [where, hex])
		t.ok(absi(e.h) <= 3 and absi(e.v) <= 3, "%s: axes in range at %s" % [where, hex])


func test_axis_and_opposites(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a")
	tl.apply([C], "fire", "a")
	t.eq(tl.intensity(C, "fire"), 2, "fire stacks")
	tl.apply([C], "water", "b")
	t.eq(tl.intensity(C, "fire"), 1, "water walks fire back")
	tl.apply([C], "water", "b")
	t.ok(tl.at(C).is_empty(), "back to neutral = no entry")
	for i in 5:
		tl.apply([C], "dark", "a")
	t.eq(tl.intensity(C, "dark"), 3, "clamped at 3")
	t.eq(tl.hit_mod(C), -21, "dark 3 = -21 hit")
	t.eq(tl.standing(C).drain, 3, "dark 3 drains")


func test_effect_numbers(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a", 2)
	t.eq(tl.standing(C).fire, 8, "fire 2 burns 8%")
	t.eq(tl.crossing_pct(C), 4, "fire 2 crossing 4%")
	var w := Vector2i(2, 2)
	tl.apply([w], "water", "a", 3)
	t.eq(tl.move_penalty(w), 2, "water 3 +2 move")
	t.near(tl.conduct_mult(w, "thunder"), 1.3, 0.001, "conducts thunder ×1.3")
	t.near(tl.conduct_mult(w, "fire"), 1.0, 0.001, "only thunder conducts")
	tl.apply([w], "ice", "a")
	t.eq(tl.move_penalty(w), 0, "glazed water is walkable (E7)")


func test_detonation(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a")
	var r := tl.apply([C], "thunder", "b")
	t.eq(r.detonations.size(), 1, "thunder on charge detonates")
	t.near(r.detonations[0].pct, 9.0, 0.001, "fire 1 = 5 + 4 = 9%")
	t.ok(tl.at(C).is_empty(), "tile erased")
	tl.apply([C], "water", "a", 3)
	tl.apply([C], "dark", "a", 3)
	tl.apply([C], "ice", "a")
	r = tl.apply([C], "thunder", "b")
	# (5 + 4×6 + 2×3) × 1.5 = 52.5
	t.near(r.detonations[0].pct, 52.5, 0.001, "glazed water3/dark3 shatter")


func test_markers(t) -> void:
	var tl := _tiles()
	tl.apply([C], "thunder", "armer")
	t.eq(tl.at(C).marker, "fuse", "thunder arms a fuse on empty ground")
	var r := tl.apply([C], "fire", "lighter")
	t.eq(r.detonations.size(), 1, "fresh fire fires the fuse")
	t.eq(r.detonations[0].source, "armer", "credit goes to who armed it (§8.2)")
	t.ok(tl.at(C).is_empty(), "fuse spent, tile erased")
	tl.apply([C], "ice", "a")
	tl.apply([C], "light", "a")
	t.ok(tl.is_glazed(C) and tl.intensity(C, "light") == 1, "stasis glazes the arrival")
	tl.apply([C], "water", "a")
	t.eq(tl.intensity(C, "light"), 1, "axis casts wash off glaze")
	tl.apply([C], "fire", "a")
	t.ok(not tl.is_glazed(C) and tl.intensity(C, "light") == 1, "fire melts glaze and is spent")


func test_gale(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a", 2)
	tl.apply([C], "wind", "b")
	var lit := 0
	for n in BWHex.neighbors(C):
		lit += int(tl.intensity(n, "fire") == 2)
	t.eq(lit, 6, "gale copies fire 2 to six neighbours")
	t.eq(tl.intensity(C, "fire"), 2, "origin unchanged")


func test_containment_gale_field(t) -> void:
	# A 7-hex field of gale markers terminates after one cast (§5.3).
	var tl := _tiles()
	for h in BWHex.area(C, 1):
		tl.apply([h], "wind", "a")
	tl.apply([C], "fire", "b")
	var markers := 0
	for h in BWHex.area(C, 1):
		markers += int(tl.at(h).get("marker", "") == "gale")
	t.eq(markers, 6, "only the struck gale fired; the other six stay armed")
	_check_invariants(t, tl, "gale field")


func test_containment_grass(t) -> void:
	# All-grass map, one fire 3: never more than 7 burning, empty within 8 cycles.
	var tl := _tiles("grassy", 11)
	tl.apply([Vector2i(5, 5)], "fire", "a", 3)
	var peak := 0
	var cleared := -1
	for cycle in 12:
		tl.tick()
		_check_invariants(t, tl, "grass cycle %d" % cycle)
		var burning := 0
		for hex in tl.entries:
			burning += int(tl.entries[hex].h > 0)
		peak = maxi(peak, burning)
		if burning == 0 and cleared < 0:
			cleared = cycle + 1
	t.ok(peak <= 7, "peak burning %d ≤ 7" % peak)
	t.ok(cleared > 0 and cleared <= 8, "burnt out by cycle %d" % cleared)


func test_tick_never_raises(t) -> void:
	var tl := _tiles("grassy", 11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var els := ["fire", "water", "light", "dark", "thunder", "ice", "wind"]
	for i in 300:
		var hex := Vector2i(rng.randi_range(0, 10), rng.randi_range(0, 10))
		tl.apply(BWHex.area(hex, rng.randi_range(0, 1)), els[rng.randi() % els.size()], "x", rng.randi_range(1, 2))
		var before := {}
		for h in tl.entries:
			before[h] = [absi(tl.entries[h].h), absi(tl.entries[h].v)]
		var seeded := tl.tick()
		for h in tl.entries:
			if before.has(h) and not h in seeded:
				t.ok(absi(tl.entries[h].h) <= before[h][0] and absi(tl.entries[h].v) <= before[h][1],
					"tick %d never raises %s" % [i, h])
	_check_invariants(t, tl, "fuzz")


func test_decay(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a", 3)
	var life := 0
	while not tl.at(C).is_empty() and life < 20:
		tl.tick()
		life += 1
	t.eq(life, 6, "untouched fire 3 lasts 6 cycles")
	tl.author(C, 2, 0)
	for i in 10:
		tl.tick()
	t.eq(tl.intensity(C, "fire"), 2, "authored tiles never decay")


func test_jagged_holds_nothing(t) -> void:
	var tl := _tiles()
	tl.board.set_cell(C, "jagged")
	tl.apply([C], "fire", "a")
	t.ok(tl.at(C).is_empty(), "jagged never holds an entry")


func test_siphon(t) -> void:
	var tl := _tiles()
	tl.apply([C], "fire", "a", 3)
	tl.apply([C], "dark", "a")
	tl.siphon(C)
	t.eq(tl.intensity(C, "fire"), 1, "fire 3 -> 1")
	t.eq(tl.intensity(C, "dark"), 0, "dark 1 -> 0")


func test_tile_damage_resist(t) -> void:
	var u := BWUnit.from_roster({ "id": "u", "weapon_class": "sword", "element": "fire", "con": 4 })
	t.eq(BWTiles.tile_damage(u, 12.0, "fire"), 14, "D178 123 HP × 12% × (1 − 5%) = 14.0 → 14")
	u.affinity["fire"] = 1000
	t.eq(BWTiles.tile_damage(u, 12.0, "fire"), 7, "own rank 10 = 50%: 123 × 12% × 50% = 7.4 → 7")
	u.affinity["water"] = 1000
	u.affinity["ice"] = 1000
	t.eq(BWTiles.tile_damage(u, 12.0, "fire"), 4, "50 + 25 + 25 capped at 75%: 3.5 → 4")

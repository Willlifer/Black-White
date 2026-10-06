extends RefCounted
## Hex math, terrain folding, movement, line of sight, turn order.


func _flat(cols: int, rows: int) -> BWBoard:
	var cells: Array = []
	for r in rows:
		for c in cols:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": cols, "rows": rows, "cells": cells })


func test_hex_math(t) -> void:
	t.eq(BWHex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3, "row distance")
	t.eq(BWHex.distance(Vector2i(0, 0), Vector2i(0, 2)), 2, "odd-r diagonal")
	t.eq(BWHex.neighbors(Vector2i(2, 2)).size(), 6, "six neighbours")
	for n in BWHex.neighbors(Vector2i(3, 3)):
		t.eq(BWHex.distance(Vector2i(3, 3), n), 1, "neighbour %s at distance 1" % n)
	t.eq(BWHex.area(Vector2i(5, 5), 1).size(), 7, "radius 1 = 7 hexes (the boss footprint)")
	t.eq(BWHex.area(Vector2i(5, 5), 2).size(), 19, "radius 2 = 19")
	var p := BWHex.to_world(Vector2i(4, 3))
	t.eq(BWHex.from_world(p), Vector2i(4, 3), "world round trip")
	t.eq(BWHex.trail(Vector2i(0, 0), Vector2i(3, 0)).size(), 3, "trail excludes origin")
	t.eq(BWHex.ray(Vector2i(2, 2), Vector2i(3, 2), 3), [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)], "ray east")


func test_terrain_fold(t) -> void:
	t.eq(BWBoard.fold_terrain("forest"), "grassy", "forest -> grassy")
	t.eq(BWBoard.fold_terrain("mud"), "muddy", "mud -> muddy")
	t.eq(BWBoard.fold_terrain("deep_water"), "jagged", "deep water -> jagged")
	t.eq(BWBoard.fold_terrain("cobblestone"), "neutral", "unknown -> neutral")
	t.eq(BWBoard.fold_terrain("jagged"), "jagged", "native kinds pass through")


func test_movement(t) -> void:
	var b := _flat(10, 10)
	t.eq(b.reachable(Vector2i(5, 5), 1).size(), 7, "move 1 on flat = 7 hexes")
	b.set_cell(Vector2i(6, 5), "muddy")
	var reach := b.reachable(Vector2i(5, 5), 1)
	t.ok(not reach.has(Vector2i(6, 5)), "mud costs 2")
	t.ok(b.reachable(Vector2i(5, 5), 2).has(Vector2i(6, 5)), "mud reachable with 2")
	b.set_cell(Vector2i(4, 5), "jagged")
	t.ok(not b.reachable(Vector2i(5, 5), 4).has(Vector2i(4, 5)), "jagged impassable")
	b.set_cell(Vector2i(5, 4), "neutral", 3)
	t.ok(not b.reachable(Vector2i(5, 5), 4).has(Vector2i(5, 4)) or b.step_cost(Vector2i(5, 5), Vector2i(5, 4)) < 0,
		"a 3-level wall cannot be climbed directly")
	b.set_cell(Vector2i(5, 6), "neutral", 2)
	t.eq(b.step_cost(Vector2i(5, 5), Vector2i(5, 6)), 3, "climb 2 costs 1 + 2")
	t.eq(b.step_cost(Vector2i(5, 6), Vector2i(5, 5)), 1, "dropping is free")


func test_blockers_and_paths(t) -> void:
	var b := _flat(10, 10)
	var start := Vector2i(2, 5)
	var ally := Vector2i(3, 5)
	var reach := b.reachable(start, 3, {}, { ally: true })
	t.ok(reach.has(ally) and not reach[ally].stop, "ally hex is pass-through")
	t.eq(BWBoard.path_to(reach, ally), [] as Array[Vector2i], "cannot end on an ally")
	var goal := Vector2i(4, 5)
	var path := BWBoard.path_to(reach, goal)
	t.eq(path.front(), start, "path starts at the unit")
	t.eq(path.back(), goal, "path ends at the goal")
	var walled := b.reachable(start, 1, { Vector2i(3, 5): true })
	t.ok(not walled.has(Vector2i(3, 5)), "enemy hex cannot be entered")


func test_los(t) -> void:
	var b := _flat(10, 10)
	t.ok(b.has_los(Vector2i(0, 5), Vector2i(6, 5)), "clear line")
	b.set_cell(Vector2i(3, 5), "jagged")
	t.ok(not b.has_los(Vector2i(0, 5), Vector2i(6, 5)), "jagged blocks sight")
	b.set_cell(Vector2i(3, 5), "neutral", 2)
	t.ok(not b.has_los(Vector2i(0, 5), Vector2i(6, 5)), "a 2-high rise blocks sight")
	b.set_cell(Vector2i(0, 5), "neutral", 1)
	t.ok(b.has_los(Vector2i(0, 5), Vector2i(6, 5)), "shooting from 1 up clears a 2-high rise")


func test_turn_order(t) -> void:
	var mk := func(id: String, team: String, spd: int, wc: String) -> BWUnit:
		var u := BWUnit.from_roster({ "id": id, "weapon_class": wc, "spd": spd })
		u.team = team
		return u
	var units := [
		mk.call("a", "enemy", 4, "sword"),     # 4 + 1 = 5
		mk.call("b", "player", 2, "daggers"),  # 2 + 3 = 5
		mk.call("c", "player", 6, "axe"),      # 6 − 1 = 5
		mk.call("d", "enemy", 6, "sword"),     # 7
	]
	var q := BWTurnQueue.build(units)
	var ids := q.map(func(u): return u.id)
	t.eq(ids, ["d", "b", "c", "a"], "speed desc, players win ties, then id")
	units[3].hp = 0
	t.eq(BWTurnQueue.build(units).size(), 3, "the fallen are skipped")

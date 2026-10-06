extends RefCounted
## D115 static charge (design/ELEMENTS.md §5.5, design/MAPS.md "Static
## tiles"): a map hex's permanent floor state. Loading, persistence through
## ticks, painting on it, the detonation scar, the perks that read it, the
## inlaid rim, and the AI on the static maps.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)


## An n x n neutral board; `statics` is {Vector2i: {h, v}} laid per cell.
func _board(statics: Dictionary = {}, n: int = 11, terrain: String = "neutral") -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			var cell := { "q": c, "r": r, "terrain": terrain, "elevation": 0 }
			if statics.has(Vector2i(c, r)):
				cell["static"] = statics[Vector2i(c, r)]
			cells.append(cell)
	return BWBoard.from_dict({ "name": "s", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, perks: Array = [], extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	var u := BWUnit.from_roster(row)
	for p in perks:
		var pel := str(BWPicks.perk(p).element)
		if u.affinity_rank(pel) < 1:
			u.affinity[pel] = 10
		u.perks.append(p)
	return u


func _fight(board: BWBoard, players: Array, foes: Array, ppos: Array, fpos: Array) -> BWBattle:
	var b := BWBattle.new(board, 7)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1
		u.statuses = {}
		u.fx = {}
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _hv(tl: BWTiles, h: Vector2i) -> Vector2i:
	var e := tl.at(h)
	return Vector2i(int(e.get("h", 0)), int(e.get("v", 0)))


# ------------------------------------------------------------------ loading

func test_loader(t) -> void:
	var b := _board({ C: { "h": -3 }, E: { "v": 2 } })
	t.ok(b.errors.is_empty(), "per-cell static loads clean: %s" % [b.errors])
	t.eq(b.statics.get(C), Vector2i(-3, 0), "water 3")
	t.eq(b.statics.get(E), Vector2i(0, 2), "light 2")
	var d := { "name": "l", "cols": 3, "rows": 3, "cells": [
		{ "q": 0, "r": 0, "terrain": "neutral", "elevation": 0 },
		{ "q": 1, "r": 0, "terrain": "jagged", "elevation": 0 },
		{ "q": 2, "r": 0, "terrain": "neutral", "elevation": 0, "static": { "h": 9 } } ],
		"statics": [ { "q": 0, "r": 0, "v": -2 }, { "q": 1, "r": 0, "h": 1 } ] }
	var b2 := BWBoard.from_dict(d)
	t.eq(b2.statics.get(Vector2i(0, 0)), Vector2i(0, -2), "the top-level list (editor-safe form)")
	t.eq(b2.statics.get(Vector2i(2, 0)), Vector2i(3, 0), "clamped to 3")
	t.ok(not b2.statics.has(Vector2i(1, 0)), "no static on rock")
	t.eq(b2.errors.size(), 1, "and that is a load error")
	var tl := BWTiles.new(b)
	t.eq(_hv(tl, C), Vector2i(-3, 0), "BWTiles lays the floor at start")
	t.ok(tl.is_static(C) and tl.at(C).get("static", false), "flagged static")
	t.eq(str(tl.at(C).source), "", "nobody's")


# ------------------------------------------------------------------ rules

func test_persists_through_ticks(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": -3 }, E: { "v": -2 } }))
	for i in 12:
		tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, 0), "water 3 after 12 ticks")
	t.eq(_hv(tl, E), Vector2i(0, -2), "dark 2 after 12 ticks")
	t.eq(tl.move_penalty(C), 2, "deep water costs +2")


func test_opposite_painting(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": -3 } }))
	tl.apply([C], "fire", "a")
	t.eq(_hv(tl, C), Vector2i(-2, 0), "fire steps it to water 2 for the cycle")
	tl.apply([C], "fire", "a", 2)
	t.ok(tl.at(C).is_empty(), "three steps: dry for the cycle")
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, 0), "re-forms at the next tick")
	tl.apply([C], "water", "a")
	t.eq(_hv(tl, C), Vector2i(-3, 0), "more water clamps at 3")


func test_painted_axis_decays(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": -3 } }))
	tl.apply([C], "dark", "a", 2)
	t.eq(_hv(tl, C), Vector2i(-3, -2), "dark painted on top")
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, -2), "1 tick: both")
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, -1), "2 ticks: the painted dark steps down, the water stays")
	tl.tick()
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, 0), "4 ticks: back to the floor")
	t.ok(tl.at(C).get("static", false), "a plain static entry again")
	var tl2 := BWTiles.new(_board({ C: { "v": 2 } }))
	tl2.apply([C], "light", "a")
	t.eq(_hv(tl2, C), Vector2i(0, 3), "light on static light 2: 3 for the cycle")
	tl2.tick()
	t.eq(_hv(tl2, C), Vector2i(0, 2), "and back to 2")


func test_detonation_scar(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": -3 } }))
	var out := tl.apply([C], "thunder", "a")
	t.eq(out.detonations.size(), 1, "thunder detonates static water")
	t.near(float(out.detonations[0].pct), 23.0, 0.001, "5 + 4x3 + 2x3 = 23%")
	t.ok(tl.at(C).is_empty() and tl.is_scarred(C), "erased and scarred")
	tl.tick()
	t.ok(tl.at(C).is_empty(), "stays spent through the next cycle")
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(-3, 0), "re-formed at the tick after")
	t.ok(not tl.is_scarred(C), "scar gone")
	# a fuse armed while it was spent holds the floor off until it fades
	var tl2 := BWTiles.new(_board({ C: { "h": -3 } }))
	tl2.apply([C], "thunder", "a")
	tl2.tick()
	t.ok(tl2.apply([C], "thunder", "a").detonations.is_empty(), "no bomb while spent: thunder only arms a fuse")
	t.eq(str(tl2.at(C).marker), "fuse", "a fuse armed on the spent hex")
	tl2.tick()
	t.eq(str(tl2.at(C).marker), "fuse", "the floor waits under the fuse")
	for i in 3:
		tl2.tick()
	t.eq(_hv(tl2, C), Vector2i(-3, 0), "the fuse faded, the water is back")


func test_consume_scars(t) -> void:
	var tl := BWTiles.new(_board({ C: { "v": -2 } }))
	tl.clear(C)
	t.ok(tl.is_scarred(C), "Consume spends a static like a detonation")
	tl.tick()
	t.ok(tl.at(C).is_empty(), "spent for a cycle")
	tl.tick()
	t.eq(_hv(tl, C), Vector2i(0, -2), "then back")


func test_glaze_and_gale(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": -3 } }))
	tl.apply([C], "ice", "a")
	t.ok(tl.is_glazed(C), "ice glazes static water")
	t.eq(tl.move_penalty(C), 0, "frozen lake: walkable")
	tl.tick()
	tl.tick()
	t.ok(not tl.is_glazed(C), "the glaze runs out")
	t.eq(_hv(tl, C), Vector2i(-3, 0), "the water was never touched")
	var out := tl.apply([C], "wind", "a")
	t.eq(out.gales[0].copies.size(), 6, "a gale copies the static water to the ring")
	t.eq(_hv(tl, C), Vector2i(-3, 0), "and the origin keeps it")
	tl.tick()
	t.eq(_hv(tl, E), Vector2i(-2, 0), "copies decay like any charge")


func test_static_fire_never_ignites_grass(t) -> void:
	var tl := BWTiles.new(_board({ C: { "h": 3 } }, 9, "grassy"))
	for i in 4:
		t.ok(tl.tick().is_empty(), "tick %d seeds nothing" % i)
	tl.apply([C], "fire", "a")
	t.eq(tl.tick().size(), 6, "a real cast on it still does")


func test_static_fire_burns(t) -> void:
	var me := _u("me", "sword", "water")
	var b := _fight(_board({ C: { "h": 2 } }), [me], [_u("f", "axe", "water", [], { "con": 300 })], [C], [Vector2i(10, 10)])
	_turn(b, me)
	var hits := b.history.filter(func(e): return e.type == "tile_damage" and e.unit == "me")
	t.eq(hits.size(), 1, "standing on static fire 2 burns at turn start")
	t.ok(int(hits[0].amount) > 0, "for real damage")


# ------------------------------------------------------------------ perks

func test_undertow_on_static_water(t) -> void:
	var me := _u("me", "sword", "fire")
	var holder := _u("h", "axe", "water", ["water_undertow"], { "con": 300 })
	var b := _fight(_board({ Vector2i(10, 4): { "h": -3 } }), [me], [holder], [C], [Vector2i(10, 10)])
	_turn(b, me)
	var r := b.reachable(me)
	t.ok(r[Vector2i(9, 4)].stop, "a static pool pulls: +1 toward it")
	t.ok(not r[Vector2i(0, 4)].stop, "and -1 away")
	b.tiles.apply([Vector2i(10, 4)], "thunder", "x")
	_turn(b, me)
	t.ok(not b.reachable(me).has(Vector2i(9, 4)), "blown: no pool this cycle, no pull")
	b.tiles.tick()
	b.tiles.tick()
	_turn(b, me)
	t.ok(b.reachable(me)[Vector2i(9, 4)].stop, "re-formed: the pull is back")


func test_shadowstep_across_static_dark(t) -> void:
	var me := _u("me", "sword", "dark", ["dark_step"])
	var to := Vector2i(7, 4)
	var b := _fight(_board({ C: { "v": -2 }, to: { "v": -2 } }), [me], [_u("f", "axe", "water", [], { "con": 300 })], [C], [Vector2i(10, 10)])
	for h in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 3), Vector2i(5, 5), Vector2i(6, 3), Vector2i(6, 5)]:
		b.board.set_cell(h, "jagged")
	_turn(b, me)
	var r := b.reachable(me)
	t.eq(int(r[to].cost), 1, "static dark to static dark: 1 move through the rock")
	t.ok(b.move(me, to), "stepped")


# ------------------------------------------------------------------ view + maps

func test_rim_and_authored(t) -> void:
	var board := BWBoard.load_file("res://maps/lake.json")
	var bv := BWBoardView.new()
	bv.build(board, BWTileFX.authored(board, "res://maps/lake.json"))
	var deep := Vector2i(6, 5)
	t.eq(board.statics.get(deep), Vector2i(-3, 0), "lake (6,5) is static water 3")
	t.eq(int(bv.fx_state(deep).h.get("tier", 0)), 3, "pre-battle boards draw the static charge")
	t.eq(bv.hex_parts(deep).filter(func(n): return str(n.name).begins_with("static_")).size(), 1, "an inlaid rim, dimmed with the hex")
	t.eq(bv.hex_parts(Vector2i(6, 0)).filter(func(n): return str(n.name).begins_with("static_")).size(), 0, "plain hexes have none")
	bv.free()


func test_ai_on_static_maps(t) -> void:
	var roster := BWData.table("roster")
	for m in ["lake", "catacombs", "forge", "chapel"]:
		var board := BWBoard.load_file("res://maps/%s.json" % m)
		t.ok(not board.statics.is_empty(), "%s has static hexes" % m)
		var b := BWBattle.new(board, 23)
		var ps: Array = []
		var es: Array = []
		for i in 3:
			ps.append(BWUnit.from_roster(roster[i + 3]))
			es.append(BWUnit.from_roster(roster[i + 13]))
		# the perks that read static ground, on both sides
		for pair in [[ps[0], "water_undertow"], [ps[1], "dark_step"], [es[0], "fire_coal"], [es[1], "water_walk"]]:
			var u: BWUnit = pair[0]
			var pel := str(BWPicks.perk(pair[1]).element)
			if u.affinity_rank(pel) < 1:
				u.affinity[pel] = 10
			u.perks.append(pair[1])
		b.setup(ps, es)
		var turns := 0
		while not b.over and turns < 600:
			BWAI.take_turn(b)
			turns += 1
		t.ok(b.over, "%s: AI fight with static-reading perks finishes (%d turns)" % [m, turns])
		var still := 0
		for h in board.statics:
			if not b.tiles.at(h).is_empty():
				still += 1
		t.ok(still > board.statics.size() / 2, "%s: the statics are still there at the end (%d/%d)" % [m, still, board.statics.size()])


# ------------------------------------------------------------------ D134 seeded charge

## An n x n neutral board with seeded hexes ({Vector2i: {h, v}}, per cell).
func _seeded(seeds: Dictionary, n: int = 11, terrain: String = "neutral") -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			var cell := { "q": c, "r": r, "terrain": terrain, "elevation": 0 }
			if seeds.has(Vector2i(c, r)):
				cell["seed"] = seeds[Vector2i(c, r)]
			cells.append(cell)
	return BWBoard.from_dict({ "name": "s", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _ticks(tl: BWTiles, n: int) -> void:
	for i in n:
		tl.tick()


func test_seed_loader(t) -> void:
	var b := _seeded({ C: { "v": -2 }, E: { "h": 1, "v": -1 } })
	t.ok(b.errors.is_empty(), "per-cell seed loads clean: %s" % [b.errors])
	t.eq(b.seeds.get(C), Vector2i(0, -2), "dark 2 seed")
	t.eq(b.seeds.get(E), Vector2i(1, -1), "two-axis seed")
	t.ok(b.statics.is_empty(), "a seed is not a static")
	var d := { "name": "l", "cols": 4, "rows": 1, "cells": [
		{ "q": 0, "r": 0, "terrain": "neutral", "elevation": 0 },
		{ "q": 1, "r": 0, "terrain": "jagged", "elevation": 0 },
		{ "q": 2, "r": 0, "terrain": "neutral", "elevation": 0, "static": { "h": -3 }, "seed": { "h": -1 } },
		{ "q": 3, "r": 0, "terrain": "neutral", "elevation": 0 } ],
		"seeds": [ { "q": 0, "r": 0, "v": 2 }, { "q": 1, "r": 0, "h": 1 }, { "q": 3, "r": 0 } ] }
	var b2 := BWBoard.from_dict(d)
	t.eq(b2.seeds.get(Vector2i(0, 0)), Vector2i(0, 2), "the top-level seeds list (editor-safe form)")
	t.ok(not b2.seeds.has(Vector2i(1, 0)), "no seed on rock")
	t.ok(not b2.seeds.has(Vector2i(3, 0)), "no (0, 0) seed")
	t.eq(b2.statics.get(Vector2i(2, 0)), Vector2i(-3, 0), "static and seed on one hex: the static wins")
	t.ok(not b2.seeds.has(Vector2i(2, 0)), "and the seed is dropped")
	t.eq(b2.errors.size(), 3, "rock, (0, 0) and the clash are load errors: %s" % [b2.errors])
	var tl := BWTiles.new(b)
	t.eq(_hv(tl, C), Vector2i(0, -2), "BWTiles lays the seed at start")
	t.ok(tl.is_seeded(C) and not tl.is_static(C), "flagged seeded, not static")
	t.eq(str(tl.at(C).source), "", "nobody's")


func test_seed_holds_without_decay(t) -> void:
	var tl := BWTiles.new(_seeded({ C: { "v": -2 }, E: { "h": -1 } }))
	_ticks(tl, 20)
	t.eq(_hv(tl, C), Vector2i(0, -2), "dark 2 after 20 ticks")
	t.eq(_hv(tl, E), Vector2i(-1, 0), "water 1 after 20 ticks")
	t.ok(tl.is_seeded(C) and tl.is_seeded(E), "still untouched seeds")
	t.eq(tl.hit_mod(C), -14.0, "and still hiding (-14)")


func test_seed_light_negates_for_good(t) -> void:
	var tl := BWTiles.new(_seeded({ C: { "v": -2 } }))
	tl.apply([C], "light", "a")
	t.eq(_hv(tl, C), Vector2i(0, -1), "light steps seeded dark 2 toward neutral")
	t.ok(not tl.is_seeded(C), "changed: ordinary charge now")
	_ticks(tl, BWTiles.STEP_CYCLES)
	t.ok(tl.at(C).is_empty(), "the dark 1 left decays away")
	_ticks(tl, 12)
	t.ok(tl.at(C).is_empty(), "and never regrows")
	var tl2 := BWTiles.new(_seeded({ C: { "v": -2 } }))
	tl2.apply([C], "light", "a", 2)
	t.ok(tl2.at(C).is_empty(), "light 2 clears it outright")
	_ticks(tl2, 6)
	t.ok(tl2.at(C).is_empty(), "for good")


func test_seed_thunder_consumes(t) -> void:
	var tl := BWTiles.new(_seeded({ C: { "v": -2 } }))
	var out := tl.apply([C], "thunder", "a")
	t.eq(out.detonations.size(), 1, "thunder detonates a seed")
	t.near(float(out.detonations[0].pct), 13.0, 0.001, "5 + 4x2 = 13%")
	t.ok(tl.at(C).is_empty() and not tl.is_scarred(C), "erased, no scar (nothing to come back)")
	_ticks(tl, 8)
	t.ok(tl.at(C).is_empty(), "never regrows")
	var tl2 := BWTiles.new(_seeded({ C: { "v": -2 } }))
	tl2.clear(C)
	_ticks(tl2, 4)
	t.ok(tl2.at(C).is_empty() and not tl2.is_scarred(C), "Consume eats it for good")


func test_seed_fire_adds_then_decays(t) -> void:
	var tl := BWTiles.new(_seeded({ C: { "v": -2 } }))
	tl.apply([C], "fire", "a")
	t.eq(_hv(tl, C), Vector2i(1, -2), "fire adds on the other axis: fire 1 + dark 2")
	t.ok(not tl.is_seeded(C), "changed")
	t.eq(str(tl.at(C).source), "a", "and it is the caster's now")
	_ticks(tl, 12)
	t.ok(tl.at(C).is_empty(), "the whole entry decays like any charge")
	var tl2 := BWTiles.new(_seeded({ C: { "v": -2 } }))
	tl2.apply([C], "dark", "a")
	t.eq(_hv(tl2, C), Vector2i(0, -3), "more of the same: dark 3")
	_ticks(tl2, 12)
	t.ok(tl2.at(C).is_empty(), "then decays, not back to the seed")


func test_seed_operators(t) -> void:
	var tl := BWTiles.new(_seeded({ C: { "h": -2 } }))
	tl.apply([C], "ice", "a")
	t.ok(tl.is_glazed(C) and not tl.is_seeded(C), "ice glazes a seed and spends it")
	_ticks(tl, BWTiles.GLAZE_CYCLES)
	t.ok(not tl.is_glazed(C), "the glaze runs out")
	_ticks(tl, 10)
	t.ok(tl.at(C).is_empty(), "then the water decays")
	var tl2 := BWTiles.new(_seeded({ C: { "h": -2 } }))
	var out := tl2.apply([C], "wind", "a")
	t.eq(out.gales[0].copies.size(), 6, "a gale copies a seed to the ring")
	t.ok(not tl2.is_seeded(C) and not tl2.is_seeded(E), "neither the origin nor the copies are seeds")
	_ticks(tl2, 10)
	t.ok(tl2.at(C).is_empty() and tl2.at(E).is_empty(), "all of it decays")
	# grass fire drying a seeded wet hex makes it ordinary
	var tl3 := BWTiles.new(_seeded({ E: { "h": -1 } }, 11, "grassy"))
	tl3.apply([C], "fire", "a", 2)
	tl3.tick()
	t.ok(tl3.at(E).is_empty(), "grass fire dries seeded water 1")
	_ticks(tl3, 4)
	t.ok(not tl3.at(E).get("permanent", false), "and it never comes back as a seed")


func test_seed_rim_and_maps(t) -> void:
	var board := BWBoard.load_file("res://maps/catacombs.json")
	t.ok(board.errors.is_empty(), "catacombs loads clean: %s" % [board.errors])
	t.eq(board.seeds.size(), 58, "the lanes and the tomb ring are seeded dark")
	t.eq(board.statics.keys(), [Vector2i(6, 6)], "the dark 3 heart is the one static")
	var lane := Vector2i(3, 4)
	t.eq(board.seeds.get(lane), Vector2i(0, -2), "a lane is seeded dark 2")
	var tl := BWTiles.new(board)
	var bv := BWBoardView.new()
	bv.build(board, tl)
	var rim: Array = bv.hex_parts(lane).filter(func(n): return str(n.name).begins_with("seed_"))
	t.eq(rim.size(), 1, "a seeded hex gets the thin ring")
	t.ok(rim[0].visible, "shown while untouched")
	t.eq(bv.hex_parts(Vector2i(6, 6)).filter(func(n): return str(n.name).begins_with("seed_")).size(), 0,
		"the static heart keeps the static rim instead")
	tl.apply([lane], "light", "a", 2)
	bv.refresh_tiles(true)
	t.ok(not rim[0].visible, "overwritten: the ring goes")
	bv.free()
	for m in ["lake", "forge", "chapel"]:
		var b := BWBoard.load_file("res://maps/%s.json" % m)
		t.ok(b.errors.is_empty() and not b.seeds.is_empty() and not b.statics.is_empty(),
			"%s: seeded ground with a few static landmarks (%d seeded, %d static)" % [m, b.seeds.size(), b.statics.size()])

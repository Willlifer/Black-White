extends RefCounted
## D262-D266 the ice/water spine (design/ELEMENTS-v3.md §2, §4, rulings of
## 2026-10-07): pillars, pools (D421: fire douses, no steam), pool glaze and electrified fields
## (BWPools). D397 removed the D261 slides: glaze is ground (Unsteady footing,
## tests/test_unsteady.gd).

const W := 0     # heading east (same row, col + 1)


func _board(n: int = 13, elev: Dictionary = {}, terrain: Dictionary = {}) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			var h := Vector2i(c, r)
			cells.append({ "q": c, "r": r, "terrain": terrain.get(h, "neutral"), "elevation": int(elev.get(h, 0)) })
	return BWBoard.from_dict({ "name": "iw", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[n - 1, 0], [n - 1, 1], [n - 1, 2]] } })


func _u(id: String, wc: String = "sword", el: String = "ice", perks: Array = []) -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
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
	b.refresh_effects()
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


## Glazed water `hv` on each hex, or plain water when glaze 0.
func _lay(t: BWTiles, hexes: Array, h: int = -1, glaze: int = 2, v: int = 0) -> void:
	for x in hexes:
		var e := t._entry(h, v, "", "", "cast")
		e.glaze = glaze
		t.entries[x] = e


func _row(y: int, from: int, to: int) -> Array:
	var out: Array = []
	for x in range(from, to + 1):
		out.append(Vector2i(x, y))
	return out


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return str(e.type) == type)


# ------------------------------------------------------------------ glaze is ground (D397: no slides)

func test_walk_onto_glaze_is_ground(t) -> void:
	var bd := _board()
	var a := _u("a")
	var f := _u("f")
	var b := _fight(bd, [a], [f], [Vector2i(2, 6)], [Vector2i(12, 12)])
	_lay(b.tiles, _row(6, 3, 6))
	_turn(b, a)
	var r := b.reachable(a)
	for h in _row(6, 3, 6):
		t.ok(r.has(h) and r[h].stop, "a glazed hex is a stop: %s" % h)
		t.ok(not r[h].has("slide"), "no slide entry: %s" % h)
	t.eq(int(r[Vector2i(3, 6)].cost), 1, "one glazed hex costs 1, like ground")
	t.eq(int(r[Vector2i(5, 6)].cost), 3, "three cost 3: no fast lane")
	t.ok(b.move(a, Vector2i(4, 6)), "the move goes")
	t.eq(a.pos, Vector2i(4, 6), "it stops where it chose, on the ice")
	var mv := _events(b, "move")
	t.eq(mv.size(), 1, "one walk event, no slide event")
	t.ok(_events(b, "slam").is_empty(), "no slam")
	t.ok(not b.can_move(a), "no +1 move after walking on ice")


func test_push_onto_glaze_stops(t) -> void:
	var bd := _board(13, {}, { Vector2i(9, 6): "jagged" })
	var a := _u("a")
	var f := _u("f")
	var b := _fight(bd, [a], [f], [Vector2i(3, 6)], [Vector2i(4, 6)])
	_lay(b.tiles, _row(6, 5, 8))
	var hp := f.hp
	b._displace(f, W, 1, "knockback")
	t.eq(f.pos, Vector2i(5, 6), "pushed 1 onto the glaze, it stops there")
	t.eq(_events(b, "move").size(), 1, "the push only, no slide")
	t.ok(_events(b, "slam").is_empty(), "no slam")
	t.eq(f.hp, hp, "no damage")
	t.ok(BWUnsteady.unsteady(b, f), "and now it's Unsteady")
	# a wind push onto glaze stops too
	BWWind.push(b, f, W, 1, "push", a, false, true)
	t.eq(f.pos, Vector2i(6, 6), "a wind push: 1 hex, no slide")


# ------------------------------------------------------------------ pillars

func test_pillar_rules(t) -> void:
	var bd := _board()
	var a := _u("a", "bow", "ice")
	var f := _u("f")
	var b := _fight(bd, [a], [f], [Vector2i(2, 6)], [Vector2i(6, 6)])
	var p := Vector2i(4, 6)
	_lay(b.tiles, [p, Vector2i(6, 6)], -3, 0)                  # water 3: one empty, one under the foe
	t.ok(b.in_range(a, f), "the bow reaches before the pillar")
	b.paint([p, Vector2i(6, 6)], "ice", a)
	t.ok(b.tiles.is_pillar(p), "ice on empty water 3 raises a pillar")
	t.ok(not b.tiles.is_pillar(Vector2i(6, 6)), "occupied water 3 just glazes")
	t.ok(not bd.has_los(Vector2i(2, 6), Vector2i(6, 6)), "a pillar blocks line of sight")
	t.ok(not b.in_range(a, f), "so the basic ranged attack can't shoot through it")
	t.eq(bd.step_cost(Vector2i(3, 6), p), -1, "impassable")
	t.ok(not b.reachable(a).has(p), "not reachable")
	for i in 2:
		b.tiles.tick()
	t.ok(b.tiles.is_pillar(p), "still standing after 2 ticks")
	b.tiles.tick()
	t.ok(not b.tiles.is_pillar(p), "thaws after 3 ticks")
	t.eq(int(b.tiles.at(p).h), -3, "back to water 3")
	t.eq(int(b.tiles.at(p).glaze), 0, "unglazed")
	# fire melts
	b.paint([p], "ice", a)
	t.ok(b.tiles.is_pillar(p), "raised again")
	b.paint([p], "fire", a)
	t.ok(not b.tiles.is_pillar(p), "fire melts it")
	t.eq(int(b.tiles.at(p).h), -3, "to water 3")
	# thunder shatters it: 17% to the ring
	b.paint([p], "ice", a)
	f.pos = Vector2i(5, 6)
	var hp := f.hp
	b.paint([p], "thunder", a)
	t.ok(not b.tiles.is_pillar(p) and b.tiles.at(p).is_empty(), "thunder shatters it")
	var dets := _events(b, "detonate")
	t.ok(not dets.is_empty() and absf(float(dets[-1].pct) - 34.5) < 0.01, "a shatter detonation: 34%% centre (%s)" % [dets[-1].pct if not dets.is_empty() else "none"])
	var mult := 1.0 + BWFormulas.AFFINITY_DMG_PER_RANK * a.affinity_rank("thunder")
	t.eq(hp - f.hp, maxi(1, int(BWTiles.tile_damage(f, 34.5, "thunder", mult) / 2.0)), "the ring takes half (17%)")


func test_pillar_cap_and_slam(t) -> void:
	var bd := _board()
	var a := _u("a")
	var b := _fight(bd, [a], [_u("f")], [Vector2i(0, 0)], [Vector2i(12, 12)])
	var hexes := [Vector2i(2, 2), Vector2i(4, 2), Vector2i(6, 2), Vector2i(8, 2), Vector2i(10, 2)]
	_lay(b.tiles, hexes, -3, 0)
	for h in hexes:
		b.paint([h], "ice", a)
	var standing := hexes.filter(func(h): return b.tiles.is_pillar(h))
	t.eq(standing.size(), BWPools.PILLAR_MAX, "at most 4 pillars per caster")
	t.ok(not b.tiles.is_pillar(hexes[0]), "the fifth melts the oldest")
	# a push into a pillar stops (and slams like rock)
	_lay(b.tiles, [Vector2i(8, 4)], -3, 0)
	b.tiles.apply([Vector2i(8, 4)], "ice", "z")
	_lay(b.tiles, _row(4, 6, 7))
	a.pos = Vector2i(7, 4)
	t.eq(b.push_path(a, W, 1).stop, "rock", "a pillar stops a push (it slams like rock)")


# ------------------------------------------------------------------ pools

func test_pool_bfs_cap(t) -> void:
	var bd := _board(13)
	var tl := BWTiles.new(bd)
	var all: Array = []
	for h in bd.cells():
		all.append(h)
	_lay(tl, all, -1, 0)
	var c := Vector2i(6, 6)
	var pl := BWPools.pool(tl, c)
	t.eq(pl.size(), BWPools.POOL_MAX, "a pool stops at 19 hexes")
	var far := 0
	for h in pl:
		far = maxi(far, BWHex.distance(c, h))
	t.eq(far, 2, "nearest first: one radius-2 flower")
	t.eq(pl[0], c, "it starts at the cast hex")
	# glazed water breaks a pool; light/dark never travel
	_lay(tl, [Vector2i(7, 6)], -1, 2)
	t.ok(not Vector2i(7, 6) in BWPools.pool(tl, c), "glazed water isn't pool")
	var before := tl.entries.duplicate(true)
	tl.apply([c], "light", "x")
	var moved := 0
	for h in tl.entries:
		if h != c and str(tl.entries[h]) != str(before.get(h, {})):
			moved += 1
	t.eq(moved, 0, "light stays on its own hex")


## D421: no steam. Fire on a pool douses only the hex it lands on (fire and
## water both cleared), nothing pool-wide, no sight block; water on fire too.
func test_fire_on_pool_douses(t) -> void:
	var bd := _board()
	var a := _u("a", "bow", "fire")
	var f := _u("f")
	var b := _fight(bd, [a], [f], [Vector2i(3, 6)], [Vector2i(6, 6)])
	var lake: Array = _row(6, 4, 8) + _row(5, 4, 8)
	_lay(b.tiles, lake, -2, 0)
	var r := b.paint([Vector2i(8, 5)], "fire", a)
	t.ok(b.tiles.at(Vector2i(8, 5)).is_empty(), "the cast hex douses: fire and water both gone")
	t.eq(r.doused, [Vector2i(8, 5)], "reported as doused")
	t.ok(not (r.get("pools", {}) as Dictionary).has("steam"), "no steam over the pool")
	t.eq(int(b.tiles.at(Vector2i(6, 6)).h), -2, "the rest of the pool is untouched")
	t.ok(b.in_range(a, f), "nothing hides the foe in the water")
	t.ok(bd.has_los(Vector2i(3, 6), Vector2i(9, 6)), "nothing blocks sight")
	# water on fire, and a mixed hex keeps its light / dark
	b.tiles.entries[Vector2i(2, 2)] = b.tiles._entry(3, 2, "", "", "cast")
	var r2 := b.paint([Vector2i(2, 2)], "water", a)
	t.eq(r2.doused, [Vector2i(2, 2)], "water on fire douses too")
	t.eq(int(b.tiles.at(Vector2i(2, 2)).h), 0, "fire 3 + water: no fire, no water")
	t.eq(int(b.tiles.at(Vector2i(2, 2)).v), 2, "its light stays")
	var ev: Array = b.history.filter(func(e): return str(e.get("type", "")) == "paint" and e.has("doused"))
	t.eq(ev.size(), 2, "each paint event names its doused hexes (the hiss)")


func test_ice_on_pool_glazes_radius_one(t) -> void:
	var bd := _board()
	var a := _u("a", "staff", "ice")
	var b := _fight(bd, [a], [_u("f")], [Vector2i(0, 0)], [Vector2i(12, 12)])
	var lake: Array = []
	for h in bd.area(Vector2i(6, 6), 3):
		lake.append(h)
	_lay(b.tiles, lake, -1, 0)
	b.tiles.entries[Vector2i(7, 6)].h = -3                       # one empty water 3 beside the cast hex
	b.tiles.entries[Vector2i(6, 8)].h = -3                       # one outside radius 1
	var r := b.paint([Vector2i(6, 6)], "ice", a)
	var glazed := lake.filter(func(h): return b.tiles.is_glazed(h))
	t.eq(glazed.size(), 7, "ice on a pool glazes only radius 1 of the cast hex")
	for h in glazed:
		t.ok(BWHex.distance(h, Vector2i(6, 6)) <= 1, "glazed within 1: %s" % h)
	t.ok(b.tiles.is_pillar(Vector2i(7, 6)), "empty water 3 in the glazed ring becomes a pillar")
	t.ok(not b.tiles.is_pillar(Vector2i(6, 8)), "water 3 outside radius 1 doesn't")
	t.ok(Vector2i(7, 6) in r.pools.pillars, "reported")
	t.ok(BWUnsteady.on_glaze(b.tiles, Vector2i(6, 7)), "a glazed pool hex is Unsteady ground")
	t.ok(Vector2i(6, 7) in r.pools.glaze, "reported as glaze (no rink)")


func test_electrified(t) -> void:
	var bd := _board()
	var a := _u("a", "staff", "thunder")
	var f := _u("f")
	var g := _u("g")
	var b := _fight(bd, [a], [f, g], [Vector2i(0, 0)], [Vector2i(6, 6), Vector2i(9, 9)])
	var lake: Array = []
	for h in bd.area(Vector2i(6, 6), 2):
		lake.append(h)
	_lay(b.tiles, lake, -2, 0)
	var r := b.paint([Vector2i(6, 6)], "thunder", a)
	t.ok(_events(b, "detonate").is_empty(), "thunder on water never detonates")
	t.eq((r.pools.shock as Array).size(), 7, "it electrifies radius 1 of the cast hex")
	t.ok(b.tiles.shock.has(Vector2i(7, 6)) and not b.tiles.shock.has(Vector2i(8, 6)), "not the rest of the pool")
	t.ok(b.tiles.conductive(f.pos), "occupants are conductive")
	var mx := f.max_hp()
	var hp := f.hp
	_turn(b, f)
	t.eq(hp - f.hp, BWTiles.tile_damage(f, BWPools.SHOCK_PCT, "thunder"), "15% at turn start")
	t.ok(f.statuses.has("staggered"), "and Staggered")
	t.ok(b.skills_for(f).is_empty(), "no skills this turn")
	f.statuses = {}
	hp = f.hp
	_turn(b, f)
	t.eq(hp - f.hp, BWTiles.tile_damage(f, BWPools.SHOCK_PCT * 0.25, "thunder"), "25% at the next turn start")
	f.statuses = {}
	hp = f.hp
	_turn(b, f)
	t.eq(hp - f.hp, 0, "then immune for the rest of that field")
	t.ok(not f.statuses.has("staggered"), "no stagger when immune")
	# never refreshed
	var ticks := int(b.tiles.fields.values()[0].ticks)
	b.paint([Vector2i(7, 6)], "thunder", a)
	t.eq(b.tiles.fields.size(), 1, "thunder on a live field does nothing")
	t.eq(int(b.tiles.fields.values()[0].ticks), ticks, "the timer isn't refreshed")
	t.ok(_events(b, "detonate").is_empty(), "nor does it detonate")
	# fire clears a hex
	b.paint([Vector2i(5, 6)], "fire", a)
	t.ok(not b.tiles.shock.has(Vector2i(5, 6)), "fire on a hex clears it")
	# entry: 5% once per walk
	g.pos = Vector2i(9, 6)
	_turn(b, g)
	hp = g.hp
	var path: Array = [Vector2i(9, 6), Vector2i(8, 6), Vector2i(7, 6), Vector2i(7, 7)]
	BWPools.on_walk(b, g, path)
	t.eq(hp - g.hp, BWTiles.tile_damage(g, BWPools.SHOCK_ENTRY_PCT, "thunder"), "5% on entry, once per walk")
	# discharge after 2 ticks: water steps down 1
	b.tiles.tick()
	t.ok(b.tiles.shock.has(Vector2i(7, 6)), "live through the first tick, decay frozen")
	t.eq(int(b.tiles.at(Vector2i(7, 6)).h), -2, "water held")
	b.tiles.tick()
	t.ok(b.tiles.shock.is_empty() and b.tiles.fields.is_empty(), "discharged after 2 ticks")
	t.eq(int(b.tiles.at(Vector2i(7, 6)).h), -1, "each hex steps down 1 water")
	# a 1-hex puddle always electrifies; glazed water still shatters
	_lay(b.tiles, [Vector2i(2, 10)], -1, 0)
	b.paint([Vector2i(2, 10)], "thunder", a)
	t.ok(b.tiles.shock.has(Vector2i(2, 10)), "even a 1-hex puddle electrifies")
	_lay(b.tiles, [Vector2i(10, 10)], -1, 2)
	b.paint([Vector2i(10, 10)], "thunder", a)
	t.ok(not _events(b, "detonate").is_empty(), "glazed water still shatters")


func test_static_scar_and_seed(t) -> void:
	var cells: Array = []
	for r in 9:
		for c in 9:
			var cell := { "q": c, "r": r, "terrain": "neutral", "elevation": 0 }
			if Vector2i(c, r) == Vector2i(4, 4):
				cell["static"] = { "h": -3 }
			if Vector2i(c, r) == Vector2i(5, 4):
				cell["seed"] = { "h": -2 }
			cells.append(cell)
	var bd := BWBoard.from_dict({ "name": "s", "cols": 9, "rows": 9, "cells": cells })
	var tl := BWTiles.new(bd)
	tl.apply([Vector2i(4, 4)], "thunder", "x")
	t.ok(tl.shock.has(Vector2i(4, 4)) and tl.shock.has(Vector2i(5, 4)), "a static and a seed electrify together")
	t.ok(not tl.is_seeded(Vector2i(5, 4)), "a seed that reacts is ordinary water")
	tl.tick()
	tl.tick()
	t.ok(tl.is_scarred(Vector2i(4, 4)), "the static scars on discharge")


func test_preview_and_determinism(t) -> void:
	var run := func() -> Array:
		var bd := _board()
		var a := _u("a", "staff", "ice")
		var f := _u("f")
		var b := _fight(bd, [a], [f], [Vector2i(2, 6)], [Vector2i(9, 6)])
		_lay(b.tiles, _row(6, 3, 7))
		var lake: Array = []
		for h in bd.area(Vector2i(6, 10), 1):
			lake.append(h)
		_lay(b.tiles, lake, -3, 0)
		_turn(b, a)
		b.move(a, Vector2i(8, 6))
		b.paint([Vector2i(6, 10)], "ice", a)
		b.paint([Vector2i(9, 3)], "thunder", a)
		for i in 3:
			b.tiles.tick()
		return [b.history.map(func(e): return str(e)), str(b.tiles.entries), str(b.tiles.pillars), a.pos, a.hp, f.hp]
	var r1: Array = run.call()
	var r2: Array = run.call()
	t.eq(r1, r2, "same seed, same walks, pillars and pools")
	# the blast preview sees a push onto glaze stop there: no slide, no slam
	var bd2 := _board(13, {}, { Vector2i(9, 6): "jagged" })
	var c := _u("c")
	var g := _u("g")
	var b2 := _fight(bd2, [c], [g], [Vector2i(3, 6)], [Vector2i(4, 6)])
	_lay(b2.tiles, _row(6, 5, 8))
	var cl := b2.clone()
	cl.history.clear()
	cl._displace(cl._unit("g"), W, 1, "knockback")
	var dg := cl._digest(c, b2.tiles.entries.duplicate(true), { "g": g.hp, "c": c.hp })
	t.ok(not dg.moves.any(func(m): return str(m.kind) == "slide"), "the digest carries no slide")
	t.eq(dg.moves.size(), 1, "just the knockback")
	t.eq((dg.get("slams", []) as Array).size(), 0, "and no slam")
	t.eq(g.pos, Vector2i(4, 6), "the real battle is untouched")


## D308: a reach tree whose parents loop (a D261 slide end replaced a hex other
## routes walked through) once hung BWBoard.path_to in the campaign sim:
## path_to is bounded and returns no path rather than spinning.
func test_path_to_never_hangs(t) -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var r := { a: { "cost": 0, "from": a, "stop": true }, b: { "cost": 1, "from": c, "stop": true }, c: { "cost": 2, "from": b, "stop": true } }
	t.eq(BWBoard.path_to(r, c).size(), 0, "a from-cycle: no path, no hang")
	r[b].from = a
	t.eq(BWBoard.path_to(r, c), [a, b, c] as Array[Vector2i], "a sound tree: the route")

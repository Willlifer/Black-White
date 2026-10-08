extends RefCounted
## D293-D298 the wind, ice, water and dark keystones of C3 that live on as
## item enchantments since Keystones v3 (D443): Eye of the Vortex, the glaze
## carry, Sure-Footed, Wellspring, Contagion, Doom, Event Horizon; the cap
## (now D444's), determinism. Wind Wall, Jetstream, Flash Freeze, Glacier
## Wall, Tidal Release and Riptide were removed with their tests.

const C := Vector2i(4, 4)


func _board(n: int = 9, cells: Dictionary = {}) -> BWBoard:
	var out: Array = []
	for r in n:
		for c in n:
			var cell := { "q": c, "r": r, "terrain": "neutral", "elevation": 0 }
			cell.merge(cells.get(Vector2i(c, r), {}), true)
			out.append(cell)
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": out,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[8, 0], [8, 1], [8, 2]] } })


## D443: these keystones are item enchantments now; the tests append the old
## ids to the unit's list (BWKeystones.has reads it), and test_keystones_v3
## checks the enchantment route itself.
func _u(id: String, wc: String, el: String, ks: Array = []) -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	for k in ks:
		u.keystones.append(k)                     # has() reads the list: an old id still answers (tests only)
	return u


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


## `me` at C with the turn; `others` (any side) at `at`.
func _duel(me: BWUnit, foes: Array, at: Array, allies: Array = [], ally_at: Array = []) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
	b.setup([me] + allies, foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	for i in allies.size():
		allies[i].pos = ally_at[i]
	_give_turn(b, me)
	return b


func _nb(h: Vector2i, d: int, n: int = 1) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[d]
	return h


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _water(b: BWBattle, h: Vector2i, lvl: int, src: String = "") -> void:
	b.tiles.entries[h] = b.tiles._entry(-lvl, 0, "", src, "cast")


# ------------------------------------------------------------------ wind

## D408 Eye of the Vortex (reworked: no Vortex fields since D406): the
## holder's wind skills' Draw in reaches foes within 2 of the area and pulls
## each up to 2, step by step, no slam.
func test_eye_of_the_vortex(t) -> void:
	var me := _u("w", "staff", "wind", ["eye_of_vortex"])
	var f := _u("f", "axe", "fire")
	var x := Vector2i(4, 2)
	var far := _nb(x, 0, 3)                         # 2 beyond Surge's radius-1 area
	var b := _duel(me, [f], [far])
	var pv := b.skill_preview(me, "surge", "wind", x)
	t.ok(not pv.is_empty(), "the surge aims")
	t.eq(f.pos, far, "the preview moves nobody")
	t.ok(f.id in pv.units, "the preview counts the foe the Eye will draw in")
	b.use_skill(me, "surge", "wind", x)
	t.eq(BWHex.distance(f.pos, x), 1, "a foe 2 beyond the area is pulled 2, into it")
	t.ok(_ev(b, "slam").is_empty(), "an inward pull never slams")
	t.ok(b.history.any(func(e): return e.type == "move" and bool(e.get("eye", false))), "the pull is tagged for the view")
	# without the keystone Draw in reaches 1 beyond the area, pulls 1
	var plain := _u("p", "staff", "wind")
	var h := _u("h", "axe", "fire")
	var b2 := _duel(plain, [h], [far])
	b2.use_skill(plain, "surge", "wind", x)
	t.eq(h.pos, far, "without the keystone a foe 2 beyond the area isn't pulled")
	# no tile effect: a gale laid by the holder pulls nobody at the tick
	var g := _u("g", "axe", "fire")
	var b3 := _duel(me, [g], [_nb(Vector2i(2, 6), 0, 2)])
	b3.paint([Vector2i(2, 6)], "wind", me)
	var g0 := g.pos
	b3.cycle += 1
	BWWind.tick(b3)
	t.eq(g.pos, g0, "the holder's gale is still only a gale (D406)")


func test_eye_respects_the_cap(t) -> void:
	var me := _u("w", "staff", "wind", ["eye_of_vortex"])
	var f := _u("f", "axe", "fire")
	var x := Vector2i(4, 2)
	var far := _nb(x, 0, 3)
	var b := _duel(me, [f], [far])
	f.fx["wind_cycle"] = b.cycle
	f.fx["wind_hexes"] = 1                         # already moved 1 by wind this cycle
	b.use_skill(me, "surge", "wind", x)
	t.eq(BWHex.distance(f.pos, x), 2, "only 1 left of the 2-hex cycle budget")






func test_glaze_carry(t) -> void:
	var me := _u("w", "staff", "fire")
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	var x := Vector2i(4, 2)
	b.tiles.entries[x] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	var ice := _nb(x, 3)
	_water(b, ice, 1)
	b.tiles.entries[ice].glaze = 2
	var r := b.paint([x], "water", me)
	var glazed := 0
	for g in r.gales:
		for c in g.copies:
			if int(b.tiles.at(c).get("glaze", 0)) == BWKsWind.GLAZE_CARRY:
				glazed += 1
	t.ok(glazed > 0, "a gale firing beside glaze carries the glaze to its water copies (%d)" % glazed)
	t.ok(b.tiles.pillars.is_empty(), "carried glaze never raises a pillar")
	b.tiles.entries.clear()
	b.tiles.entries[x] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	_water(b, ice, 1)
	b.tiles.entries[ice].glaze = 2
	var r3 := b.paint([x], "fire", me)
	t.ok(r3.gales.all(func(g): return (g.copies as Array).all(func(c): return int(b.tiles.at(c).glaze) == 0)), "fire copies stay unglazed (only water copies take it)")
	b.tiles.entries.clear()
	b.tiles.entries[x] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	var r2 := b.paint([x], "water", me)
	t.ok(r2.gales.all(func(g): return (g.copies as Array).all(func(c): return int(b.tiles.at(c).glaze) == 0)), "no glaze beside it: no glaze")


# ------------------------------------------------------------------ ice

func test_sure_footed(t) -> void:
	var me := _u("s", "axe", "ice", ["skater"])
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	me.pos = Vector2i(1, 4)
	var line: Array = []
	var h := me.pos
	for i in 5:
		h = _nb(h, 0)
		line.append(h)
		_water(b, h, 1)
		b.tiles.entries[h].glaze = 2
	var r := b.reachable(me)
	t.ok(r.has(line[0]) and r[line[0]].stop, "it may stop on the first ice hex (anyone may now)")
	t.eq(int(r[line[3]].cost), 4, "D399: no free ice hexes any more, glaze costs like ground")
	b.move(me, line[2])
	t.ok(not BWUnsteady.unsteady(b, me), "Sure-Footed: never Unsteady on glaze")
	# a push onto ice stops it there, like everyone
	var b2 := _duel(_u("x", "axe", "fire"), [me], [Vector2i(2, 2)])
	var on := _nb(me.pos, 0)
	_water(b2, on, 1)
	b2.tiles.entries[on].glaze = 2
	_water(b2, _nb(on, 0), 1)
	b2.tiles.entries[_nb(on, 0)].glaze = 2
	b2._displace(me, 0, 1, "push")
	t.eq(me.pos, on, "pushed onto ice, it stops on it")






# ------------------------------------------------------------------ water







func test_wellspring(t) -> void:
	var me := _u("wa", "staff", "water", ["wellspring"])
	var a := _u("a", "axe", "fire")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(8, 8)], [a], [Vector2i(2, 2)])
	_water(b, a.pos, 2, me.id)
	_water(b, f.pos, 3, me.id)
	a.hp = a.max_hp() - 40
	f.hp = f.max_hp() - 40
	var a0 := a.hp
	var f0 := f.hp
	BWKsWater.tick(b)
	t.eq(a.hp - a0, maxi(1, roundi(a.max_hp() * 0.08)), "an ally in your water 2 heals 8%")
	t.eq(f.hp, f0, "a foe in it doesn't")
	# light on the hex: the higher counts, not both
	b.tiles.entries[a.pos].v = 1
	var a1 := a.hp
	BWKsWater.tick(b)
	t.eq(a.hp - a1, maxi(1, roundi(a.max_hp() * (0.08 - 0.03))), "with light 1 (3%) only the difference")
	b.tiles.entries[a.pos].v = 3
	var a2 := a.hp
	BWKsWater.tick(b)
	t.eq(a.hp, a2, "light 3 (9%) beats water 2's 8%: nothing extra")


# ------------------------------------------------------------------ dark

func test_contagion(t) -> void:
	var me := _u("d", "staff", "dark", ["contagion"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var h := _u("h", "axe", "fire")
	var b := _duel(me, [f, g, h], [Vector2i(4, 1), _nb(Vector2i(4, 1), 0, 2), Vector2i(8, 8)])
	f.fx["rot"] = 2
	g.fx["rot"] = 3
	f.hp = 0
	b._ko(f, me)
	t.eq(BWCurse.rot(g), 3, "capped at 3")
	t.eq(BWCurse.rot(h), 0, "a foe beyond 2 gets none")
	g.fx["rot"] = 1
	var k := _u("k", "axe", "fire")
	b.units.append(k)
	k.team = "enemy"
	k.pos = _nb(g.pos, 0)
	k.fx["rot"] = 1
	k.hp = 0
	b._ko(k, me)
	t.eq(BWCurse.rot(g), 2, "+1 stack to a foe within 2")
	var n := _ev(b, "contagion").size()
	var clean := _u("c", "axe", "fire")
	b.units.append(clean)
	clean.team = "enemy"
	clean.pos = _nb(g.pos, 3)
	clean.hp = 0
	b._ko(clean, me)
	t.eq(_ev(b, "contagion").size(), n, "no Rot on the fallen: no jump")


func test_doom(t) -> void:
	var me := _u("d", "staff", "dark", ["doom"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var b := _duel(me, [f, g], [Vector2i(4, 1), _nb(Vector2i(4, 1), 0)])
	BWCurse.add_rot(b, f, 3, me.id, "dark")
	t.ok(BWKsDark.doomed(f), "3 Rot: Doomed")
	var f0 := f.hp
	var g0 := g.hp
	_give_turn(b, f)
	var want := b._tile_dmg(f, 30.0, "dark")
	var want_g := b._tile_dmg(g, 15.0, "dark")
	b.end_turn()
	var d := _ev(b, "doom")
	t.eq(d.size(), 1, "the burst at the end of its next turn")
	t.near(float(d[0].pct), 30.0, 0.01, "15% + 5% per Rot (3)")
	t.eq(f0 - f.hp, want, "its own burst")
	t.eq(g0 - g.hp, want_g, "half of it to the adjacent foe")
	t.eq(BWCurse.rot(f), 0, "then its Rot clears")
	BWCurse.add_rot(b, f, 3, me.id, "dark")
	t.ok(not BWKsDark.doomed(f), "once per foe per battle")
	# doomed during its own turn: the burst waits for the next one
	var h := _u("h", "axe", "fire")
	var b2 := _duel(_u("d2", "staff", "dark", ["doom"]), [h], [Vector2i(6, 6)])
	_give_turn(b2, h)
	BWCurse.add_rot(b2, h, 3, "d2", "dark")
	b2.end_turn()
	t.ok(_ev(b2, "doom").is_empty() and BWKsDark.doomed(h), "not at the end of the turn it was doomed in")


func test_event_horizon(t) -> void:
	var me := _u("d", "staff", "dark", ["event_horizon"])
	var f := _u("f", "axe", "fire")
	var dk := Vector2i(4, 1)
	var b := _duel(me, [f], [_nb(dk, 0, 2)])
	b.tiles.entries[dk] = b.tiles._entry(0, -3, "", me.id, "cast")
	t.eq(BWCurse.gravity_reach(b, f), 2, "its gravity reaches 2")
	b.cycle += 1
	BWWind.tick(b)
	t.eq(BWHex.distance(f.pos, dk), 1, "pulled exactly 1 toward the dark 3 at the tick")
	t.ok(bool(_ev(b, "move").filter(func(e): return e.unit == "f")[-1].get("wind", false)), "a field move")
	f.pos = dk
	f.hp = f.max_hp() - 30
	var h0 := f.hp
	b._heal(f, 10.0, "light")
	t.eq(f.hp, h0, "a foe on the holder's dark 3 can't be healed")
	var p := _u("p", "staff", "dark")
	var g := _u("g", "axe", "fire")
	var b2 := _duel(p, [g], [_nb(dk, 0, 2)])
	b2.tiles.entries[dk] = b2.tiles._entry(0, -3, "", p.id, "cast")
	b2.cycle += 1
	BWWind.tick(b2)
	t.eq(BWHex.distance(g.pos, dk), 2, "no keystone: no tick pull")


# ------------------------------------------------------------------ AI







## D302 / D444: the cap of 2 binds every grant, one per element; a save
## trimmed on load; the old ids are no keystones any more.
func test_keystone_cap(t) -> void:
	var u := _u("k", "staff", "ice")
	t.ok(BWKeystones.grant(u, "sculptor"), "first")
	t.ok(not BWKeystones.grant(u, "shatterer"), "one per element: a second ice one is refused")
	t.ok(BWKeystones.grant(u, "lava_walker"), "second (another element)")
	t.ok(not BWKeystones.grant(u, "abyssal"), "a third is refused")
	t.ok(not BWKeystones.grant(u, "doom"), "an old (converted) id is no keystone")
	t.eq(u.keystones.size(), 2, "two held")
	u.keystones.append("hopekiller")
	t.eq(BWKeystones.enforce_cap(u), 1, "enforce_cap trims the extra")
	t.eq(u.keystones, ["sculptor", "lava_walker"], "keeping the first taken")


func _play(seed_value: int) -> String:
	var players: Array = [_u("p1", "staff", "ice", ["sculptor", "skater"]), _u("p2", "axe", "water", ["being_of_rain", "wellspring"]),
		_u("p3", "staff", "dark", ["doom", "event_horizon", "abyssal"])]
	var enemies: Array = [_u("e1", "axe", "wind", ["eye_of_vortex", "la_nina"]), _u("e2", "staff", "water", ["wellspring", "leviathan"]),
		_u("e3", "staff", "dark", ["contagion", "hopekiller"])]
	var b := BWBattle.new(_board(), seed_value)
	b.setup(players, enemies)
	var n := 0
	while not b.over and n < 80:
		BWAI.take_turn(b)
		n += 1
	return var_to_str(b.history.map(func(e): return [e.type, str(e.get("unit", "")), str(e.get("path", ""))]))


func test_determinism(t) -> void:
	var a := _play(11)
	var c := _play(11)
	t.ok(a.length() > 100, "the AI played a keystone fight")
	t.ok(a == c, "same seed, same fight, event for event")

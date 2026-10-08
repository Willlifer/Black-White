extends RefCounted
## D293-D298 the wind, ice, water and dark keystones (design/ELEMENTS-v3.md,
## the author's rulings of 2026-10-07; ELEMENTS.md §16.1-§16.4): each
## keystone, its caps and its once-per-battle rules, the AI's use of the
## action keystones, determinism.

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


func _u(id: String, wc: String, el: String, ks: Array = []) -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	for k in ks:
		u.keystones.append(k)
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


func _field(b: BWBattle, h: Vector2i, mode: String, owner: BWUnit, born: int = 1, heading: int = 0) -> void:
	var e := b.tiles._entry(0, 0, "gale", owner.id, "cast")
	e["mode"] = mode
	e["born"] = born
	if mode == "gust":
		e["heading"] = heading
	b.tiles.entries[h] = e


# ------------------------------------------------------------------ wind

func test_eye_of_the_vortex(t) -> void:
	var me := _u("w", "staff", "wind", ["eye_of_vortex"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var x := Vector2i(4, 2)
	var b := _duel(me, [f, g], [_nb(x, 0, 2), _nb(x, 3, 2)])
	me.pos = Vector2i(0, 8)
	_field(b, x, "vortex", me)
	b.cycle += 1
	BWWind.tick(b)
	t.eq(BWHex.distance(f.pos, x), 0, "a foe 2 out is pulled 2, onto the free centre")
	t.eq(BWHex.distance(g.pos, x), 1, "the next one stops beside it (the centre is taken: no slam)")
	t.ok(_ev(b, "slam").is_empty(), "an inward pull never slams")
	t.ok(not _ev(b, "eye_pull").is_empty(), "the eye_pull event for the view")
	# a plain Vortex field pulls only units beside it, 1
	var plain := _u("p", "staff", "wind")
	var h := _u("h", "axe", "fire")
	var b2 := _duel(plain, [h], [_nb(x, 0, 2)])
	_field(b2, x, "vortex", plain)
	b2.cycle += 1
	BWWind.tick(b2)
	t.eq(BWHex.distance(h.pos, x), 2, "without the keystone a unit 2 out isn't pulled")


func test_eye_one_field_per_tick_newest(t) -> void:
	var me := _u("w", "staff", "wind", ["eye_of_vortex"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var old := Vector2i(2, 2)
	var new := Vector2i(6, 6)
	var b := _duel(me, [f, g], [_nb(old, 0), _nb(new, 3)])
	me.pos = Vector2i(0, 8)
	_field(b, old, "vortex", me, 1)
	_field(b, new, "vortex", me, 2)
	var f0 := f.pos
	b.cycle += 1
	BWWind.tick(b)
	t.eq(f.pos, f0, "the older field doesn't act")
	t.eq(g.pos, new, "the newest one does")


func test_eye_respects_the_cap(t) -> void:
	var me := _u("w", "staff", "wind", ["eye_of_vortex"])
	var f := _u("f", "axe", "fire")
	var x := Vector2i(4, 2)
	var b := _duel(me, [f], [_nb(x, 0, 2)])
	me.pos = Vector2i(0, 8)
	_field(b, x, "vortex", me)
	f.fx["wind_cycle"] = b.cycle
	f.fx["wind_hexes"] = 1                         # already moved 1 by wind this cycle
	BWWind.tick(b)
	t.eq(BWHex.distance(f.pos, x), 1, "only 1 left of the 2-hex cycle budget")


func test_wind_wall_is_the_keystone(t) -> void:
	var me := _u("w", "staff", "wind")
	var b := _duel(me, [_u("f", "bow", "fire")], [Vector2i(4, 0)])
	t.ok(not b.skills_for(me).any(func(r): return r.key == "wind_wall"), "no keystone, no wall (the flag is gone)")
	me.fx["ks:wind_wall"] = true
	t.ok(not b.skills_for(me).any(func(r): return r.key == "wind_wall"), "the old fx flag no longer grants it")
	me.keystones.append("wind_wall")
	t.ok(b.skills_for(me).any(func(r): return r.key == "wind_wall"), "the keystone grants it")


func test_jetstream_gale_three(t) -> void:
	var me := _u("w", "staff", "wind", ["jetstream"])
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	var x := Vector2i(4, 2)
	var e := b.tiles._entry(0, 0, "gale", me.id, "cast")
	e["gale_level"] = 2
	b.tiles.entries[x] = e
	b.paint([x], "wind", me)
	t.eq(int(b.tiles.at(x).get("gale_level", 1)), 3, "wind on a gale 2 makes a gale 3")
	var r := b.paint([x], "fire", me)
	var far := false
	var timers := true
	for g in r.gales:
		for c in g.copies:
			if BWHex.distance(x, c) == 3:
				far = true
			if int(b.tiles.at(c).get("timer", 0)) < 2:
				timers = false
	t.ok(far, "a gale 3 copies to radius 3")
	t.ok(timers, "Jetstream copies last 2 cycles")
	# without the keystone, wind on a gale 2 stays a gale 2
	var p := _u("p", "staff", "wind")
	var b2 := _duel(p, [_u("f2", "axe", "fire")], [Vector2i(8, 8)])
	var e2 := b2.tiles._entry(0, 0, "gale", p.id, "cast")
	e2["gale_level"] = 2
	b2.tiles.entries[x] = e2
	b2.paint([x], "wind", p)
	t.eq(int(b2.tiles.at(x).get("gale_level", 1)), 2, "no keystone: a gale 2 refreshes")


func test_jetstream_gust_pushes_two(t) -> void:
	var me := _u("w", "staff", "wind", ["jetstream"])
	var f := _u("f", "axe", "fire")
	var x := Vector2i(2, 4)
	var b := _duel(me, [f], [x])
	me.pos = Vector2i(0, 8)
	_field(b, x, "gust", me, 1, 0)
	BWWind.turn_start(b, f)
	t.eq(BWHex.distance(f.pos, x), 2, "your Gust field pushes 2")
	BWWind.turn_start(b, f)
	t.eq(BWHex.distance(f.pos, x), 2, "and the 2-hex cycle cap holds")


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


func test_flash_freeze(t) -> void:
	var me := _u("i", "staff", "ice", ["flash_freeze"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var b := _duel(me, [f, g], [_nb(C, 0, 2), Vector2i(8, 8)])
	t.ok(b.skills_for(me).any(func(r): return r.key == "flash_freeze"), "the holder has the action")
	t.ok(not f.pos in [] and f.pos in b.skill_targets(me, "flash_freeze", ""), "a foe within 3")
	t.ok(not g.pos in b.skill_targets(me, "flash_freeze", ""), "not one beyond 3")
	var plain := float(b.forecast_basic(me, f).damage.value)
	b.use_skill(me, "flash_freeze", "", f.pos)
	t.ok(BWKsIce.frozen(f), "Frozen")
	t.ok(not "flash_freeze" in BWWind.keystone_actions(me), "once a battle: gone after use")
	var fc := b.forecast_basic(me, f)
	t.ok(float(fc.damage.value) >= 2.0 * float(plain) - 1.0, "its next hit is x2 (%s vs %s)" % [fc.damage.value, plain])
	t.ok(BWBattle._tags(fc).has("Shatter"), "it counts as glazed for Shatter")
	t.ok(not b._displace(f, 0, 1, "push"), "it can't be displaced")
	BWKsIce.after_blow(b, f, { "hit": true, "damage": 5 })
	t.ok(not BWKsIce.frozen(f), "a landed hit thaws it")
	# the skip
	BWKsIce.freeze(b, f, me)
	_give_turn(b, f)
	t.ok(not _ev(b, "frozen_skip").is_empty(), "a Frozen foe skips its turn")
	t.ok(_ev(b, "turn_end").any(func(e): return e.unit == "f"), "its turn ended at once")
	# a boss doesn't skip
	var boss := _u("bz", "axe", "fire")
	var b3 := _duel(_u("i2", "staff", "ice"), [boss], [Vector2i(6, 4)])
	boss.encounter = "twin"
	BWKsIce.freeze(b3, boss, null)
	t.ok(not BWKsIce.turn_start(b3, boss), "a boss doesn't skip")
	t.ok(BWKsIce.frozen(boss), "but stays encased for the x2")


func test_glacier_wall(t) -> void:
	var me := _u("i", "staff", "ice", ["glacier_wall"])
	var f := _u("f", "axe", "fire")
	var a := _u("a", "axe", "fire")
	var x := Vector2i(4, 2)
	var b := _duel(me, [f], [_nb(x, 0)], [a], [_nb(x, 3)])
	_water(b, x, 3)
	b.paint([x], "ice", me)
	t.ok(b.tiles.is_pillar(x), "a pillar rose")
	t.eq(int(b.tiles.pillars[x].ticks), BWKsIce.GLACIER_TICKS, "it lasts all battle")
	for i in 5:
		b.tiles.tick()
	t.ok(b.tiles.is_pillar(x), "still standing after 5 ticks")
	t.ok(b.skills_for(me).any(func(r): return r.key == "glacier_shatter"), "the Break Pillar row")
	var f0 := f.hp
	var a0 := a.hp
	for k in 3:                                    # D400: glaze behind the foe: the push stops on it, no slide
		var g := _nb(_nb(x, 0), 0, k + 1)
		_water(b, g, 1)
		b.tiles.entries[g].glaze = 2
	BWKsIce.shatter(b, me, x)
	t.ok(not b.tiles.is_pillar(x), "shattered")
	t.ok(f.hp < f0 and a.hp < a0, "12% to the neighbours, both teams")
	t.eq(f0 - f.hp, b._tile_dmg(f, BWKsIce.SHATTER_PCT, "ice"), "12% (ice)")
	t.eq(BWHex.distance(f.pos, x), 2, "and pushed 1 away, onto the glaze, where it stops (no slide)")
	t.ok(_ev(b, "slam").is_empty(), "no slam")
	# still capped at 4
	var hs: Array = [Vector2i(0, 6), Vector2i(2, 6), Vector2i(4, 6), Vector2i(6, 6), Vector2i(8, 6)]
	for h in hs:
		_water(b, h, 3)
		b.paint([h], "ice", me)
	t.eq(BWKsIce.own_pillars(b, me).size(), 4, "still 4 at most")
	# a skill shape on an older pillar shatters it; one raised in the same action doesn't
	var p0: Vector2i = BWKsIce.own_pillars(b, me)[0]
	b._action_serial += 1
	BWKsIce.after_skill(b, me, { "hexes": [p0] })
	t.ok(not b.tiles.is_pillar(p0), "your skill on your pillar shatters it")
	var p1: Vector2i = BWKsIce.own_pillars(b, me)[0]
	b.tiles.pillars[p1]["act"] = b._action_serial
	BWKsIce.after_skill(b, me, { "hexes": [p1] })
	t.ok(b.tiles.is_pillar(p1), "not one raised by that same action")
	# a plain pillar thaws as ever
	var q := _u("q", "staff", "ice")
	var b2 := _duel(q, [_u("f2", "axe", "fire")], [Vector2i(8, 8)])
	_water(b2, x, 3)
	b2.paint([x], "ice", q)
	for i in BWPools.PILLAR_TICKS:
		b2.tiles.tick()
	t.ok(not b2.tiles.is_pillar(x), "no keystone: it thaws after 3 ticks")


# ------------------------------------------------------------------ water

func test_tidal_release(t) -> void:
	var me := _u("wa", "staff", "water", ["tidal_release"])
	var f1 := _u("f1", "axe", "fire")
	var f2 := _u("f2", "axe", "fire")
	var s := Vector2i(1, 6)
	var line: Array = []
	for i in 5:
		line.append(_nb(s, 0, i))
	var b := _duel(me, [f1, f2], [line[1], line[3]])
	me.pos = Vector2i(1, 4)
	for h in line:
		_water(b, h, 3)
	var extra := _nb(line[2], 5)
	_water(b, extra, 1)
	t.ok(s in b.skill_targets(me, "tidal_release", ""), "a pool hex within 3")
	var seconds := BWSkillRegistry.get_def("tidal_release").second_targets(b, me, "", s)
	t.eq(seconds.size(), 6, "six headings")
	var d1 := f1.pos
	var d2 := f2.pos
	var pv := b.skill_preview(me, "tidal_release", "", s, _nb(s, 0))
	t.eq((pv.hexes as Array).size(), 6, "the wave's length is the pool's size (6 hexes)")
	b.use_skill(me, "tidal_release", "", s, _nb(s, 0))
	t.eq(BWHex.distance(d2, f2.pos), 3, "the front unit is pushed 3 along the line")
	t.ok(BWHex.distance(d1, f1.pos) >= 1, "the one behind it too (then it may slam)")
	t.eq(b.tiles.intensity(extra, "water"), 0, "the pool drained (off the line too)")
	t.eq(b.tiles.intensity(s, "water"), 2, "the line gets water 2")
	t.eq(int(me.cooldowns.get("tidal_release", 0)), 4, "cooldown 4")
	t.ok(not _ev(b, "tidal").is_empty(), "the tidal event for the view")


func test_tidal_wave_length_cap(t) -> void:
	var me := _u("wa", "staff", "water", ["tidal_release"])
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	for c in 9:
		_water(b, Vector2i(c, 6), 2)
		_water(b, Vector2i(c, 7), 2)
	var line := BWKsWater.wave_line(b, Vector2i(1, 6), 0)
	t.eq(line.size(), BWKsWater.WAVE_MAX, "max 6 hexes")


func test_riptide(t) -> void:
	var me := _u("wa", "staff", "water", ["riptide"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var b := _duel(me, [f, g], [_nb(C, 0, 3), _nb(C, 3, 3)])
	_water(b, f.pos, 1)
	var f0 := BWHex.distance(C, f.pos)
	_give_turn(b, me)
	t.eq(BWHex.distance(C, f.pos), f0 - 1, "a foe in water within 4 is pulled 1")
	t.eq(BWHex.distance(C, g.pos), 3, "a foe on dry ground isn't")
	t.ok(not _ev(b, "riptide").is_empty(), "the riptide event")
	var mv := _ev(b, "move").filter(func(e): return e.unit == "f")
	t.ok(not mv.is_empty() and bool(mv[-1].get("wind", false)), "a field move (it spends the wind budget)")


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

func test_ai_flash_freeze_targets_the_hitter(t) -> void:
	var me := _u("i", "staff", "ice", ["flash_freeze"])
	var weak := _u("w", "staff", "fire")
	var big := BWUnit.from_roster({ "id": "big", "name": "big", "weapon_class": "axe", "element": "fire",
		"con": 6, "str": 14, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	var b := _duel(me, [weak, big], [_nb(C, 0, 2), _nb(C, 3, 2)])
	var s := BWKsIce.ai_freeze(b, me, { "key": "flash_freeze" })
	t.eq(s.get("target", Vector2i(-1, -1)), big.pos, "it freezes the foe that hits hardest")


func test_ai_tidal_needs_two(t) -> void:
	var me := _u("wa", "staff", "water", ["tidal_release"])
	var f1 := _u("f1", "axe", "fire")
	var f2 := _u("f2", "axe", "fire")
	var s := Vector2i(1, 6)
	var b := _duel(me, [f1, f2], [_nb(s, 0, 1), _nb(s, 0, 2)])
	me.pos = Vector2i(1, 4)
	for i in 4:
		_water(b, _nb(s, 0, i), 2)
	var a := BWKsWater.ai_tidal(b, me, { "key": "tidal_release" })
	t.ok(not a.is_empty(), "two foes on a line: it releases")
	f2.pos = Vector2i(8, 0)
	var a2 := BWKsWater.ai_tidal(b, me, { "key": "tidal_release" })
	t.ok(a2.is_empty(), "one: it doesn't")


## D304: the AI's Wind Wall: a ranged foe threatening 2+ of us along lines a
## wall cuts, or a melee foe closing on a hurt ally; never one screened unit.
func test_ai_wind_wall(t) -> void:
	var me := _u("w", "staff", "wind", ["wind_wall"])
	var al := _u("a", "axe", "fire")
	var bow := _u("b", "bow", "fire")
	var b := _duel(me, [bow], [Vector2i(8, 4)], [al], [Vector2i(4, 5)])
	var s := BWKsWind.ai_wall(b, me, { "key": "wind_wall" })
	t.ok(not s.is_empty(), "a bow threatening two of us: raise a wall")
	if not s.is_empty():
		var wall := BWWind.wall_line(b, s.target, BWHex.direction_index(s.target, s.choice))
		var cut := 0
		for x in [me, al]:
			if BWHex.line(bow.pos, x.pos).slice(1, -1).any(func(h): return h in wall):
				cut += 1
		t.eq(cut, 2, "the wall cuts both lines")
		t.ok(not b.use_skill(me, "wind_wall", "", s.target, s.choice).is_empty(), "and it is a legal cast")
	al.pos = Vector2i(0, 8)
	t.ok(BWKsWind.ai_wall(b, me, { "key": "wind_wall" }).is_empty(), "one unit in its reach: no wall")
	# melee: an axe closing on a hurt ally
	var me2 := _u("w2", "staff", "wind", ["wind_wall"])
	var al2 := _u("a2", "staff", "fire")
	var axe := _u("x", "axe", "fire")
	var b2 := _duel(me2, [axe], [Vector2i(7, 2)], [al2], [Vector2i(5, 2)])
	me2.pos = Vector2i(3, 4)
	al2.pos = Vector2i(4, 2)
	t.ok(BWKsWind.ai_wall(b2, me2, { "key": "wind_wall" }).is_empty(), "a healthy ally: no wall")
	al2.hp = int(al2.max_hp() * 0.3)
	var s2 := BWKsWind.ai_wall(b2, me2, { "key": "wind_wall" })
	t.ok(not s2.is_empty(), "a hurt ally in an axe's reach: wall the approach")


## D302: the cap of 2 binds every grant (the C3 render's three came from a
## review tool appending past it); a save trimmed on load.
func test_keystone_cap(t) -> void:
	var u := _u("k", "staff", "ice")
	t.ok(BWKeystones.grant(u, "flash_freeze"), "first")
	t.ok(BWKeystones.grant(u, "glacier_wall"), "second")
	t.ok(not BWKeystones.grant(u, "tidal_release"), "a third is refused")
	t.eq(u.keystones.size(), 2, "two held")
	u.keystones.append("doom")
	t.eq(BWKeystones.enforce_cap(u), 1, "enforce_cap trims the extra")
	t.eq(u.keystones, ["flash_freeze", "glacier_wall"], "keeping the first taken")


func _play(seed_value: int) -> String:
	var players: Array = [_u("p1", "staff", "ice", ["flash_freeze", "glacier_wall"]), _u("p2", "axe", "water", ["riptide", "tidal_release"]),
		_u("p3", "staff", "dark", ["doom", "event_horizon"])]
	var enemies: Array = [_u("e1", "axe", "wind", ["eye_of_vortex", "wind_wall"]), _u("e2", "staff", "water", ["wellspring", "tidal_release"]),
		_u("e3", "staff", "dark", ["contagion", "skater"])]
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

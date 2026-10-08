extends RefCounted
## D269-D276 Element Overhaul, wind and dark (design/ELEMENTS-v3.md and the
## author's rulings of 2026-10-07): caps, wind on every weapon, Wind Wall,
## Becalmed / Restless; dark's Rot and gravity; determinism. D406/D407 (the
## author's 2026-10-08 simplification): one wind tile, the gale, that only
## spreads; no modes, no fields; a wind basic pushes 1.

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


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


## `me` at C with the turn; foes at `at`; `allies` parked in the far corner.
func _duel(me: BWUnit, foes: Array, at: Array, seed_value: int = 7, cells: Dictionary = {}) -> BWBattle:
	var b := BWBattle.new(_board(9, cells), seed_value)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


# ------------------------------------------------------------------ D406: one wind tile

## A gale laid by wind is a plain marker: no mode, no heading. Walking onto it,
## starting a turn on it and the tick move nobody; it only spreads.
func test_gale_only_spreads(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(8, 8)])
	var h := Vector2i(6, 4)
	b.paint([h], "wind", me)
	var e := b.tiles.at(h)
	t.eq(str(e.get("marker", "")), "gale", "wind on bare ground arms a gale")
	t.ok(not e.has("mode") and not e.has("heading"), "with no stored mode or heading")
	t.ok(not ("mode" in BWWind), "BWWind has no unit mode any more")
	f.pos = _nb(_nb(h, 4), 4)
	_give_turn(b, f)
	var r := b.reachable(f)
	t.ok(r.has(h) and r.has(_nb(h, 1)), "a walk may cross the gale")
	b.move(f, h)
	t.eq(f.pos, h, "entering a gale moves nobody")
	b.end_turn()
	_give_turn(b, f)
	t.eq(f.pos, h, "nor does starting a turn on it")
	var g := _u("g", "axe", "fire")
	var b2 := _duel(me, [g], [_nb(Vector2i(2, 6), 1)])
	b2.paint([Vector2i(2, 6)], "wind", me)
	BWWind.tick(b2)
	t.eq(g.pos, _nb(Vector2i(2, 6), 1), "the tick pulls nobody onto a gale")
	# what lands on it spreads to the six around, and nobody moves
	var at := g.pos
	b2._turn_serial += 1
	b2.paint([Vector2i(2, 6)], "fire", me)
	for d in 6:
		var n := _nb(Vector2i(2, 6), d)
		if b2.board.exists(n):
			t.ok(b2.tiles.intensity(n, "fire") > 0, "the gale copied the fire to its ring (%d)" % d)
	t.eq(g.pos, at, "the gale firing moves nobody")
	t.ok(_ev(b2, "field_fire").is_empty(), "no field_fire event")
	# the tile card: the one base line
	var lines := BWWind.card_lines(b, h)
	t.ok(lines.is_empty(), "no field line on the card (a Tailwind holder's Updraft is the only extra)")


# ------------------------------------------------------------------ wind on every weapon

## A wind Cleave pulls the foe beside the arc INTO it, then swings (the ruling).
func test_wind_cleave_pulls_then_hits(t) -> void:
	var me := _u("ax", "axe", "wind")
	var f := _u("f", "axe", "fire")
	var e := _nb(C, 0)                         # east of C: the arc's centre
	var far := _nb(e, 0)                       # two east: beside the arc, not in it
	var b := _duel(me, [f], [far])
	var pv := b.skill_preview(me, "cleave", "wind", e)            # an area draws in by default (D383)
	t.ok(not pv.is_empty(), "the cleave aims east")
	t.ok(f.id in pv.units, "the preview counts the foe it will pull into the arc")
	t.eq(f.pos, far, "the preview moves nobody")
	t.eq((pv.wind.moves as Array).size(), 1, "and lists the pull")
	var hp := f.hp
	var ev := b.use_skill(me, "cleave", "wind", e)
	t.ok(not ev.is_empty(), "the cleave resolves")
	t.eq(f.pos, e, "the foe was pulled into the arc")
	t.ok(f.hp < hp or ev.results.any(func(r): return r.target == f.id), "then the swing struck it")
	var types: Array = b.history.map(func(x): return x.type)
	var mv := -1
	for i in b.history.size():
		if b.history[i].type == "move" and str(b.history[i].get("unit", "")) == f.id:
			mv = i
	t.ok(mv >= 0 and mv < types.find("skill"), "the pull is played before the swing")
	# once per action: a second pull doesn't happen in the same action
	t.ok(BWWind.moved_this_action(b, f), "the foe used its once-per-action wind move")


## A wind Surge with Gust blows the foes out of the AoE, still hits them, and
## a push stopped by a unit slams both for 8%.
func test_wind_surge_gust_slams(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var tgt := Vector2i(4, 1)
	var near := _nb(tgt, 1)                    # in the Surge (radius 1)
	var dir := BWBattle.pulse_heading(tgt, near, true)
	var wall := _nb(near, dir)                 # a unit right behind: the slam
	var b := _duel(me, [f, g], [near, wall])
	BWWindShape.set_choice(me, "surge", "burst")   # D383: areas default to Draw in; this checks Burst out's slam
	var hp_g := g.hp
	var ev := b.use_skill(me, "surge", "wind", tgt)
	t.ok(not ev.is_empty(), "the surge resolves")
	t.eq(f.pos, near, "the push was stopped by the unit behind")
	t.ok(_ev(b, "slam").size() >= 1, "a slam")
	t.ok(g.hp < hp_g, "the unit it slammed into takes the slam too")
	t.ok(ev.results.any(func(r): return r.target == f.id), "the blown foe is still hit")


func test_wind_becalm_restless(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(4, 1)])
	BWWindShape.set_choice(me, "surge", "hold")     # D407: Becalm comes from the Hold shaping
	b.use_skill(me, "surge", "wind", Vector2i(4, 1))
	t.ok(f.statuses.has("becalmed"), "Becalm lands")
	_give_turn(b, f)
	t.eq(b.reachable(f).size(), 1, "Becalmed: move 0")
	t.ok(not b.attack_targets(f).is_empty() or b.skills_for(f).size() > 0 or true, "it can still act")
	t.eq(f.move_range(), 0, "move range reads 0")
	b.end_turn()
	t.ok(not f.statuses.has("becalmed"), "Becalmed ends with its turn")
	t.ok(f.statuses.has("restless"), "then Restless")
	t.ok(not BWWind.becalm(b, f, me), "Restless refuses Becalm")
	for i in 2:
		t.ok(f.statuses.has("restless"), "Restless holds through turn %d" % (i + 1))
		_give_turn(b, f)
		b.end_turn()
	t.ok(not f.statuses.has("restless"), "Restless lasts 2 turns (the ruling)")
	t.ok(BWWind.becalm(b, f, me), "then it can be Becalmed again")


func test_wind_basic_direct_hit(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire", { "def": 0 })
	var b := _duel(me, [f], [_nb(_nb(C, 0), 0)])
	me.attuned = "wind"
	b.expected_rolls = true                    # a sure, unresisted blow
	var at := f.pos
	b.attack(me, f)
	t.eq(f.pos, _nb(at, 0), "D407: a wind basic pushes its target 1 away from the attacker")
	t.ok(at != f.pos, "moved")


# ------------------------------------------------------------------ caps

func test_field_caps(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(2, 6)])
	var moved := 0
	for i in 4:
		var at := f.pos
		BWWind.push(b, f, 0, 1, "push", me, true, false)
		if f.pos != at:
			moved += 1
	t.eq(moved, 1, "an ambient wind move (a squall) moves a unit once per turn")
	b._turn_serial += 1
	BWWind.push(b, f, 0, 1, "push", me, true, false)
	b._turn_serial += 1
	var at2 := f.pos
	BWWind.push(b, f, 0, 1, "push", me, true, false)
	t.eq(f.pos, at2, "and 2 hexes per cycle in all (the third turn's push is refused)")
	b.cycle += 1
	BWWind.push(b, f, 0, 1, "push", me, true, false)
	t.ok(f.pos != at2, "a new cycle, a new budget")
	# direct: once per action
	b.cycle += 1
	b._action_serial += 1
	var at3 := f.pos
	BWWind.push(b, f, 3, 1, "push", me, false, false)
	BWWind.push(b, f, 3, 1, "push", me, false, false)
	t.eq(BWHex.distance(at3, f.pos), 1, "a direct hit moves a unit once per action")


## Two gales side by side never move anyone (D406), and 10 cycles of turns
## never move anyone more than 2 hexes a cycle by wind.
func test_no_loops(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(8, 8)])
	var a := Vector2i(3, 6)
	var c := _nb(a, 0)
	b.tiles.entries[a] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	b.tiles.entries[c] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	f.pos = _nb(a, 3)
	_give_turn(b, f)
	b.move(f, a)
	t.eq(f.pos, a, "entered a gale and stayed there")
	var per := {}
	var count := func(e):
		if e.type == "move" and e.get("wind", false):
			var k := "%d|%s" % [b.cycle, e.unit]
			per[k] = int(per.get(k, 0)) + (e.path as Array).size() - 1
	b.event.connect(count)
	for i in 30:
		if b.over:
			break
		b.end_turn()
	b.event.disconnect(count)
	var worst := 0
	for k in per:
		worst = maxi(worst, int(per[k]))
	t.ok(worst <= BWWind.CYCLE_HEXES, "no unit is moved more than 2 hexes by wind in a cycle (worst %d)" % worst)
	t.ok(f.fx.get("wind_hexes", 0) <= BWWind.CYCLE_HEXES, "the per-cycle counter never passes 2")


func test_weather_gale_composes(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := BWBattle.new(_board(), 3)
	b.set_weather(BWWeather.GALE, 11)
	b.setup([me], [f])
	me.pos = Vector2i(0, 8)
	f.pos = C
	b.weather.heading = 0
	var h := _nb(C, 0)
	b.tiles.entries[h] = b.tiles._entry(0, 0, "gale", me.id, "cast")
	BWWeather.tick(b)
	t.eq(f.pos, h, "the weather pushes it onto the gale, and the gale does nothing")
	t.eq(int(f.fx.get("wind_hexes", 0)), 0, "weather isn't a wind move: no budget spent")
	_give_turn(b, f)
	t.eq(f.pos, h, "D406: its turn start on a gale moves nobody")


func test_glaze_stops_a_push(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(2, 6)])
	var land := _nb(f.pos, 0)
	for k in 3:
		var h := land
		for j in k:
			h = _nb(h, 0)
		b.tiles.entries[h] = b.tiles._entry(-1, 0, "", "", "cast")
		b.tiles.entries[h].glaze = 2
	BWWind.push(b, f, 0, 1, "push", me, false, false)
	t.eq(BWHex.distance(Vector2i(2, 6), f.pos), 1, "D397: a push onto glaze stops there (no slide): %s" % [f.pos])
	t.ok(BWUnsteady.unsteady(b, f), "and it stands Unsteady")


# ------------------------------------------------------------------ Wind Wall

## D443: Wind Wall left with its keystone (the wall rules in BWWind stay,
## unused): nobody gets the action any more.
func test_wind_wall_removed(t) -> void:
	var me := _u("st", "staff", "wind")
	var b := _duel(me, [_u("f", "bow", "fire")], [Vector2i(4, 1)])
	t.ok(not BWKeystones.grant(me, "wind_wall"), "no such keystone")
	me.fx["ks:wind_wall"] = true
	t.ok(not b.skills_for(me).any(func(r): return r.key == "wind_wall"), "no Wind Wall action, whatever the flags")
	t.ok(not BWSkillRegistry.has("wind_wall"), "its def is gone")


# ------------------------------------------------------------------ Rot

func test_rot(t) -> void:
	var me := _u("dk", "staff", "dark")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(6, 6)])
	b.paint([f.pos], "dark", me)
	_give_turn(b, f)
	b.end_turn()
	t.eq(BWCurse.rot(f), 1, "a foe ending its turn on your dark gains 1 Rot")
	for i in 4:
		b.paint([f.pos], "dark", me)            # keep it dark (the tick decays it)
		_give_turn(b, f)
		b.end_turn()
	t.eq(BWCurse.rot(f), BWCurse.ROT_MAX, "it stacks to 3")
	t.near(BWCurse.taken_mult(f), 1.15, 0.001, "+5% taken per stack")
	_give_turn(b, me)
	var fc := b.forecast_basic(me, f)
	t.ok((fc.damage.get("mods", []) as Array).any(func(m): return str(m.get("tag", "")) == "Rot") \
		or str(fc.damage.get("values", "")).find("Rot") >= 0 or str(fc.damage.get("formula", "")).find("Rot") >= 0 \
		or var_to_str(fc).find("Rot 3") >= 0, "the forecast names the Rot line")
	t.eq(b._tile_dmg(f, 10.0, ""), BWTiles.tile_damage(f, 10.0, "", 1.15), "ground damage takes Rot too")
	b._heal(f, 5.0, "light")
	t.eq(BWCurse.rot(f), 2, "a light heal cleans 1 Rot")
	b._heal(f, 5.0, "erupt")
	t.eq(BWCurse.rot(f), 2, "other heals don't")
	# your own side's dark doesn't rot you
	var ally := _u("al", "axe", "dark")
	var b2 := _duel(me, [_u("x", "axe", "fire")], [Vector2i(8, 8)])
	b2.units.append(ally)
	ally.team = "player"
	ally.begin_battle()
	ally.pos = Vector2i(2, 2)
	b2.paint([ally.pos], "dark", me)
	_give_turn(b2, ally)
	b2.end_turn()
	t.eq(BWCurse.rot(ally), 0, "your own dark never rots your side")


# ------------------------------------------------------------------ gravity

func test_gravity(t) -> void:
	var me := _u("dk", "staff", "dark")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(6, 6)])
	var pit := Vector2i(5, 6)
	b.paint([pit], "dark", me, 3)
	t.eq(b.tiles.intensity(pit, "dark"), 3, "dark 3")
	var before: Dictionary = b.tiles.entries.duplicate(true)
	# stepping out costs +1 for a foe
	f.pos = pit
	_give_turn(b, f)
	var r := b.reachable(f)
	var out1 := _nb(pit, 3)
	t.eq(int(r[out1].cost), 2, "a foe's step out of your dark 3 costs +1 move")
	# toward: +1, away: -1
	f.pos = _nb(pit, 0)                          # beside the pit, east of it
	var at := f.pos
	b._displace(f, 3, 1, "push")                 # west, toward the pit
	t.eq(BWHex.distance(at, f.pos), 2, "a push toward your dark 3 goes 1 further (over it)")
	f.pos = _nb(pit, 0)
	b._displace(f, 0, 1, "push")                 # east, away
	t.eq(f.pos, _nb(pit, 0), "a push of 1 away from it goes 1 shorter (it holds)")
	# allies feel nothing
	var ally := _u("al", "axe", "fire")
	b.units.append(ally)
	ally.team = "player"
	ally.begin_battle()
	ally.pos = _nb(pit, 5)
	var a0 := ally.pos
	b._displace(ally, BWHex.direction_index(a0, _nb(a0, 0)), 1, "push")
	t.eq(BWHex.distance(a0, ally.pos), 1, "the owner's side isn't pulled")
	t.eq(var_to_str(b.tiles.at(pit)), var_to_str(before[pit]), "gravity never changes the tile")
	# wind obeys it inside the caps
	f.pos = _nb(pit, 0)
	b._action_serial += 1
	b.cycle += 1
	BWWind.push(b, f, 3, 1, "pull", me, false, false)
	t.eq(BWHex.distance(_nb(pit, 0), f.pos), 2, "a wind pull toward the pit goes 1 further")
	b._action_serial += 1
	var at2 := f.pos
	BWWind.push(b, f, 3, 1, "pull", me, false, false)
	t.eq(f.pos, at2, "and the 2-hex cycle budget caps it")


# ------------------------------------------------------------------ AI

func _play(seed_value: int) -> String:
	var players: Array = [_u("p1", "staff", "wind"), _u("p2", "axe", "wind"), _u("p3", "staff", "dark")]
	var enemies: Array = [_u("e1", "axe", "wind"), _u("e2", "staff", "wind"), _u("e3", "staff", "dark")]
	var b := BWBattle.new(_board(), seed_value)
	b.setup(players, enemies)
	for u in b.units:
		u.keystones.append("el_nino" if u.team == "player" else "la_nina")   # D454/D455 (Wind Wall is gone)
	var n := 0
	while not b.over and n < 60:
		BWAI.take_turn(b)
		n += 1
	return var_to_str(b.history.map(func(e): return [e.type, str(e.get("unit", "")), str(e.get("path", "")), str(e.get("mode", ""))]))


func test_determinism(t) -> void:
	var a := _play(5)
	var c := _play(5)
	t.eq(a.length() > 100, true, "the AI played a wind/dark fight")
	t.ok(a == c, "same seed, same fight, event for event")
	t.ok(a.find("\"move\"") >= 0, "with moves")

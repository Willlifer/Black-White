extends RefCounted
## D365-D370 wind shaping (BWWindShape, design/ELEMENTS.md §18): a wind
## skill's options follow its shape. Line: Part left / Part right / Blast out;
## area: Draw in / Burst out; single: a push heading; every shape: Hold.
## Results, the caps, slams and slides, the gale it lays, memory, the AI's
## pick and determinism.

const C := Vector2i(4, 4)
const EAST := 0


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


func _learn(u: BWUnit, key: String) -> void:
	if not key in u.known_skills:
		u.known_skills.append(key)
	if not key in u.overcap:
		u.overcap.append(key)


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _duel(me: BWUnit, foes: Array, at: Array, seed_value: int = 7, cells: Dictionary = {}) -> BWBattle:
	if me.weapon_class == "staff":
		_learn(me, "bolt")
	var b := BWBattle.new(_board(9, cells), seed_value)
	b.setup([me], foes)
	for k in me.known_skills:                 # setup clears the over-cap list
		_learn(me, k)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


# ------------------------------------------------------------------ shapes

func test_kinds_and_options(t) -> void:
	for k in ["ley_line", "tridentpierce", "energized_shot", "earthsplitter", "shockwave_palm", "lunge"]:
		t.eq(BWWindShape.kind_of(k), "line", "%s is a line" % k)
	for k in ["surge", "tempest", "rain_of_arrows", "arcing_shot", "whirlwind_blade", "fan_of_knives", "cleave", "sweep", "daggerleap"]:
		t.eq(BWWindShape.kind_of(k), "area", "%s is an area" % k)
	for k in ["bolt", "aimed_shot", "split_arrow", "haymaker", "charge"]:
		t.eq(BWWindShape.kind_of(k), "single", "%s is single-target" % k)
	t.eq(BWWindShape.kind_of("wind_wall"), "", "a keystone action carries no shaping")
	t.eq(BWWindShape.options("line"), ["part_left", "part_right", "blast", "hold"], "line options")
	t.eq(BWWindShape.options("area"), ["draw", "burst", "hold"], "area options")
	t.eq(BWWindShape.options("single"), ["push", "hold"], "single options")


func test_memory_and_defaults(t) -> void:
	var u := _u("w", "staff", "wind")
	t.eq(str(BWWindShape.choice(u, "surge").opt), "draw", "unset: an area defaults to Draw in, under Gust too (D383)")
	u.wind_mode = "vortex"
	t.eq(str(BWWindShape.choice(u, "surge").opt), "draw", "Vortex → Draw in")
	t.eq(int(BWWindShape.choice(u, "bolt").rel), 3, "Vortex → a single push straight back toward the caster")
	u.wind_mode = "becalm"
	t.eq(str(BWWindShape.choice(u, "ley_line").opt), "hold", "Becalm → Hold")
	BWWindShape.set_choice(u, "ley_line", "part_right")
	t.eq(str(BWWindShape.choice(u, "ley_line").opt), "part_right", "the last choice is remembered per skill")
	t.eq(str(BWWindShape.choice(u, "surge").opt), "hold", "and only for that skill")
	BWWindShape.set_choice(u, "ley_line", "draw")
	t.eq(str(BWWindShape.choice(u, "ley_line").opt), "part_right", "an option of another shape is refused")
	BWWindShape.set_choice(u, "bolt", "push", -1)
	t.eq(int(BWWindShape.choice(u, "bolt").rel), 5, "a push heading wraps (0-5)")


# ------------------------------------------------------------------ line

func _ley(opt: String, foes: Array, at: Array, cells: Dictionary = {}) -> BWBattle:
	var me := _u("st", "staff", "wind")
	_learn(me, "ley_line")
	var b := _duel(me, foes, at, 7, cells)
	BWWindShape.set_choice(me, "ley_line", opt)
	b.use_skill(me, "ley_line", "wind", _nb(C, EAST))
	return b


## The first neighbour of `h` on `side` of the eastward line from C.
func _side_nb(h: Vector2i, side: int) -> Vector2i:
	var fwd := BWWindShape.forward(C, _nb(C, EAST))
	for n in BWHex.neighbors(h):
		if BWWindShape.side_of(C, fwd, n) == side:
			return n
	return h


func test_line_part_left_right(t) -> void:
	var on := Vector2i(6, 4)                      # on the line, two east of the caster
	var fwd := BWWindShape.forward(C, _nb(C, EAST))
	var fl := _u("f", "axe", "fire")
	_ley("part_left", [fl], [on])
	t.eq(BWWindShape.side_of(C, fwd, fl.pos), 1, "Part left: the foe is now on the line's left")
	t.ok(fl.pos.y < on.y, "the caster's left, looking east, is north")
	var fr := _u("f", "axe", "fire")
	var b := _ley("part_right", [fr], [on])
	t.eq(BWWindShape.side_of(C, fwd, fr.pos), -1, "Part right: on its right")
	t.eq(BWHex.distance(on, fr.pos), 1, "pushed 1")
	var ws := _ev(b, "wind_shape")
	t.eq(ws.size(), 1, "one wind_shape event")
	t.eq(str(ws[0].opt), "part_right", "naming the option")
	t.eq((ws[0].moves as Array).size(), 1, "and the move")
	# a foe beside the line isn't parted
	var g := _u("g", "axe", "fire")
	var beside := _nb(on, 1)
	_ley("part_left", [g], [beside])
	t.eq(g.pos, beside, "Part moves only the foes ON the line")


func test_line_blast_out(t) -> void:
	var fwd := BWWindShape.forward(C, _nb(C, EAST))
	var on := Vector2i(6, 4)
	var a := _u("a", "axe", "fire")
	var n := _u("n", "axe", "fire")
	var s := _u("s", "axe", "fire")
	var north := _side_nb(Vector2i(7, 4), 1)      # beside the line, its left
	var south := _side_nb(Vector2i(5, 4), -1)     # beside it, its right
	_ley("blast", [a, n, s], [on, north, south])
	t.ok(BWWindShape.side_of(C, fwd, a.pos) != 0, "the foe on the line is blown off it")
	t.eq(BWWindShape.side_of(C, fwd, n.pos), 1, "the foe on the left stays left")
	t.eq(BWWindShape.side_of(C, fwd, s.pos), -1, "the foe on the right stays right")
	t.ok(absf((BWHex.to_world(n.pos) - BWHex.to_world(C)).dot(BWWindShape.left_of(fwd))) > absf((BWHex.to_world(north) - BWHex.to_world(C)).dot(BWWindShape.left_of(fwd))),
		"and farther from the line than before")


func test_line_hold(t) -> void:
	var f := _u("f", "axe", "fire")
	_ley("hold", [f], [Vector2i(7, 4)])
	t.eq(f.pos, Vector2i(7, 4), "Hold moves nobody")
	t.ok(f.statuses.has("becalmed"), "and Becalms the foe on the line")


# ------------------------------------------------------------------ area

func test_area_draw_in_vs_burst_out(t) -> void:
	var tgt := Vector2i(4, 1)
	var beside := _nb(_nb(tgt, 0), 0)            # two from the centre: outside the Surge
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [beside])
	BWWindShape.set_choice(me, "surge", "draw")
	var pv := b.skill_preview(me, "surge", "wind", tgt)
	t.ok(f.id in pv.units, "Draw in: the preview counts the foe it pulls into the area")
	t.eq(f.pos, beside, "the preview moves nobody")
	var ev := b.use_skill(me, "surge", "wind", tgt)
	t.eq(BWHex.distance(tgt, f.pos), 1, "pulled 1 toward the centre")
	t.ok(ev.results.any(func(r): return r.target == f.id), "then hit")
	var mv := -1
	for i in b.history.size():
		if b.history[i].type == "move" and str(b.history[i].get("unit", "")) == f.id:
			mv = i
	t.ok(mv >= 0 and mv < b.history.map(func(x): return x.type).find("skill"), "the pull plays before the hit")
	# Burst out: hit first, then pushed out of the area
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire")
	var inner := _nb(tgt, 0)
	var b2 := _duel(me2, [g], [inner])
	BWWindShape.set_choice(me2, "surge", "burst")
	var ev2 := b2.use_skill(me2, "surge", "wind", tgt)
	t.ok(ev2.results.any(func(r): return r.target == g.id), "Burst out: the foe in the area is hit")
	t.eq(BWHex.distance(tgt, g.pos), 2, "then pushed 1 away from the centre")
	var mv2 := -1
	for i in b2.history.size():
		if b2.history[i].type == "move" and str(b2.history[i].get("unit", "")) == g.id:
			mv2 = i
	t.ok(mv2 > b2.history.map(func(x): return x.type).find("skill"), "after the hit")
	var me3 := _u("st", "staff", "wind")
	var h := _u("h", "axe", "fire")
	var b3 := _duel(me3, [h], [beside])
	BWWindShape.set_choice(me3, "surge", "burst")
	b3.use_skill(me3, "surge", "wind", tgt)
	t.eq(h.pos, beside, "Burst out leaves a foe outside the area alone")


func test_area_burst_slams(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var tgt := Vector2i(4, 1)
	var near := _nb(tgt, 1)
	var behind := _nb(near, BWBattle.pulse_heading(tgt, near, true))
	var b := _duel(me, [f, g], [near, behind])
	BWWindShape.set_choice(me, "surge", "burst")
	var hp_g := g.hp
	b.use_skill(me, "surge", "wind", tgt)
	t.eq(f.pos, near, "a push blocked by a unit stays")
	t.ok(_ev(b, "slam").size() >= 1, "and slams")
	t.ok(g.hp < hp_g, "the unit behind takes the slam too")


# ------------------------------------------------------------------ single

func test_single_push_heading_and_hold(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var at := Vector2i(4, 2)
	var b := _duel(me, [f], [at])
	b.expected_rolls = true
	BWWindShape.set_choice(me, "bolt", "push", 2)
	var d := BWWindShape.push_dir(C, at, 2)
	b.use_skill(me, "bolt", "wind", at)
	t.eq(f.pos, _nb(at, d), "the target is pushed along the chosen heading (away + 2)")
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire")
	var b2 := _duel(me2, [g], [at])
	BWWindShape.set_choice(me2, "bolt", "hold")
	b2.use_skill(me2, "bolt", "wind", at)
	t.eq(g.pos, at, "Hold: it stays")
	t.ok(g.statuses.has("becalmed"), "Becalmed")


func test_single_push_slides_onto_ice(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var at := Vector2i(4, 2)
	var b := _duel(me, [f], [at])
	var d := BWWindShape.push_dir(C, at, 0)
	var ice := _nb(at, d)
	for h in [ice, _nb(ice, d)]:
		var e := b.tiles._entry(-1, 0, "", "", "cast")
		e.glaze = 2
		b.tiles.entries[h] = e
	BWWindShape.set_choice(me, "bolt", "push", 0)
	var sim := b.simulate(me, { "kind": "skill", "key": "bolt", "element": "wind", "hex": at })
	t.ok((sim.moves as Array).any(func(m): return m.kind == "slide"), "the preview shows the slide onto the ice")
	b.use_skill(me, "bolt", "wind", at)
	t.ok(BWHex.distance(at, f.pos) >= 2, "pushed onto the glaze, it slides on")


# ------------------------------------------------------------------ caps, fields, determinism

func test_caps(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var at := Vector2i(4, 2)
	var b := _duel(me, [f], [at])
	f.fx["wind_cycle"] = b.cycle
	f.fx["wind_hexes"] = BWWind.CYCLE_HEXES          # spent its 2 hexes this cycle
	BWWindShape.set_choice(me, "bolt", "push", 0)
	b.use_skill(me, "bolt", "wind", at)
	t.eq(f.pos, at, "the 2-hexes-a-cycle cap holds")
	# once per action: Draw in has moved it, so nothing after the hits moves it again
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire")
	var tgt := Vector2i(4, 1)
	var b2 := _duel(me2, [g], [_nb(_nb(tgt, 0), 0)])
	BWWindShape.set_choice(me2, "surge", "draw")
	b2.use_skill(me2, "surge", "wind", tgt)
	var moves := _ev(b2, "move").filter(func(e): return e.unit == g.id and e.get("wind", false))
	t.eq(moves.size(), 1, "one wind move per action")


func test_gale_takes_the_shaping(t) -> void:
	var tgt := Vector2i(4, 1)
	for row in [["draw", "vortex"], ["burst", "gust"], ["hold", "becalm"]]:
		var me := _u("st", "staff", "wind")
		var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
		me.wind_mode = "gust"
		BWWindShape.set_choice(me, "surge", row[0])
		b.use_skill(me, "surge", "wind", tgt)
		t.eq(str(BWWind.field_at(b, tgt).get("mode", "")), row[1], "%s lays a %s gale" % row)
	var me2 := _u("st", "staff", "wind")
	_learn(me2, "ley_line")
	var b2 := _duel(me2, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	BWWindShape.set_choice(me2, "ley_line", "part_right")
	b2.use_skill(me2, "ley_line", "wind", _nb(C, EAST))
	var f2 := BWWind.field_at(b2, Vector2i(6, 4))
	t.eq(str(f2.get("mode", "")), "gust", "Part lays gust gales")
	t.eq(int(f2.get("heading", -1)), BWWindShape.side_dir(BWWindShape.forward(C, _nb(C, EAST)), -1), "heading to the parting side")
	t.ok(BWWindShape.active(b2, me2).is_empty(), "the shaping ends with the action")
	b2.paint([Vector2i(2, 7)], "wind", me2)
	t.eq(str(BWWind.field_at(b2, Vector2i(2, 7)).get("mode", "")), "gust", "a paint outside a skill keeps the unit's mode")


func _run_once(opt: String) -> Array:
	var me := _u("st", "staff", "wind")
	_learn(me, "ley_line")
	var b := _duel(me, [_u("a", "axe", "fire"), _u("b", "axe", "fire")], [Vector2i(6, 4), Vector2i(7, 3)], 11)
	BWWindShape.set_choice(me, "ley_line", opt)
	b.use_skill(me, "ley_line", "wind", _nb(C, EAST))
	return b.history.map(func(e): return var_to_str(e))


func test_determinism(t) -> void:
	for opt in ["part_left", "part_right", "blast", "hold"]:
		t.eq(_run_once(opt), _run_once(opt), "%s: the same seed gives the same events" % opt)


# ------------------------------------------------------------------ AI

func test_ai_options_capped(t) -> void:
	var me := _u("st", "staff", "wind")
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(4, 2)])
	for key in ["bolt", "surge"]:
		var opts := BWWindShape.ai_options(b, me, key, Vector2i(4, 2))
		t.ok(opts.size() >= 2 and opts.size() <= BWWindShape.AI_MAX, "%s: 2-%d options" % [key, BWWindShape.AI_MAX])
	_learn(me, "ley_line")
	t.eq(BWWindShape.ai_options(b, me, "ley_line", _nb(C, EAST)).size(), 4, "a line: 4 options")


## The AI parts a foe into rock (a slam) rather than into the open.
func test_ai_picks_the_slam(t) -> void:
	var on := Vector2i(6, 4)
	var fwd := BWWindShape.forward(C, _nb(C, EAST))
	var right := _nb(on, BWWindShape.side_dir(fwd, -1))
	var me := _u("st", "staff", "wind")
	_learn(me, "ley_line")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [on], 7, { right: { "terrain": "jagged" } })
	BWWindShape.set_choice(me, "ley_line", "part_left")
	BWWindShape.ai_refine(b, me, "ley_line", "wind", _nb(C, EAST))
	t.eq(str(BWWindShape.choice(me, "ley_line").opt), "part_right", "parts it into the rock (an 8% slam)")
	# single target: the push heading into rock
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire")
	var at := Vector2i(4, 2)
	var rock := _nb(at, BWWindShape.push_dir(C, at, 1))
	var b2 := _duel(me2, [g], [at], 7, { rock: { "terrain": "jagged" } })
	BWWindShape.ai_refine(b2, me2, "bolt", "wind", at)
	var ch := BWWindShape.choice(me2, "bolt")
	t.eq([str(ch.opt), int(ch.rel)], ["push", 1], "pushes the target into the rock")
	var a := BWWindShape.ai_options(b2, me2, "bolt", at)
	BWWindShape.ai_refine(b2, me2, "bolt", "wind", at)
	t.eq(BWWindShape.ai_options(b2, me2, "bolt", at), a, "deterministic")

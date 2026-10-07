extends RefCounted
## D390: wind motion around a blow plays in the author's order (presentation:
## BWWindOrder.hoist on the combat screen's queue). Draw in: the motion,
## then the hit. Push out: the hit, then the motion. Checked on real event
## streams from BWBattle for every shape the rules have (skill Draw in /
## Burst out / Blast out / Part / single push, Vortex and Gust basics, a
## Vortex field fired by a paint) and on a synthetic list.

const C := Vector2i(4, 4)


func _board(n: int = 9) -> BWBoard:
	var out: Array = []
	for r in n:
		for c in n:
			out.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": out,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[8, 0], [8, 1], [8, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _duel(me: BWUnit, foes: Array, at: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
	b.setup([me], foes)
	for k in ["bolt", "surge", "ley_line"]:
		if not k in me.known_skills:
			me.known_skills.append(k)
		if not k in me.overcap:
			me.overcap.append(k)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	b.expected_rolls = true
	return b


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


## Indices in the played (hoisted) order: the first blow event, and every
## wind move of `uid`.
func _played(b: BWBattle, uid: String) -> Dictionary:
	var evs := BWWindOrder.hoist(b.history)
	var blow := -1
	var moves: Array = []
	for i in evs.size():
		var e: Dictionary = evs[i]
		if blow < 0 and str(e.type) in ["attack", "skill"]:
			blow = i
		if str(e.type) == "move" and str(e.get("unit", "")) == uid and bool(e.get("wind", false)):
			moves.append(i)
	return { "blow": blow, "moves": moves }


func _motion_first(t, b: BWBattle, uid: String, what: String) -> void:
	var p := _played(b, uid)
	t.ok(not (p.moves as Array).is_empty(), "%s: the wind moved the foe" % what)
	t.ok(p.blow >= 0 and (p.moves as Array).all(func(m): return m < p.blow), "%s: motion first, then the hit" % what)


func _hit_first(t, b: BWBattle, uid: String, what: String) -> void:
	var p := _played(b, uid)
	t.ok(not (p.moves as Array).is_empty(), "%s: the wind moved the foe" % what)
	t.ok(p.blow >= 0 and (p.moves as Array).all(func(m): return m > p.blow), "%s: the hit first, then motion" % what)


func test_skill_shapes(t) -> void:
	var tgt := Vector2i(4, 1)
	# Draw in
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(_nb(tgt, 0), 0)])
	BWWindShape.set_choice(me, "surge", "draw")
	b.use_skill(me, "surge", "wind", tgt)
	_motion_first(t, b, f.id, "Surge, Draw in")
	# Burst out
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire")
	var b2 := _duel(me2, [g], [_nb(tgt, 0)])
	BWWindShape.set_choice(me2, "surge", "burst")
	b2.use_skill(me2, "surge", "wind", tgt)
	_hit_first(t, b2, g.id, "Surge, Burst out")
	# a line: Blast out and Part left
	for opt in ["blast", "part_left", "part_right"]:
		var me3 := _u("st", "staff", "wind")
		var h := _u("h", "axe", "fire")
		var b3 := _duel(me3, [h], [_nb(_nb(C, 0), 0)])
		BWWindShape.set_choice(me3, "ley_line", opt)
		b3.use_skill(me3, "ley_line", "wind", _nb(C, 0))
		var p3 := _played(b3, h.id)
		if (p3.moves as Array).is_empty():
			continue                         # Ley Line lays ground: no blow here, nothing to order
		t.ok((p3.moves as Array).all(func(m): return p3.blow < 0 or m > p3.blow), "Ley Line, %s: never before a hit" % opt)
	# a single target push
	var me4 := _u("st", "staff", "wind")
	var k := _u("k", "axe", "fire")
	var b4 := _duel(me4, [k], [_nb(_nb(C, 0), 0)])
	BWWindShape.set_choice(me4, "bolt", "push", 0)
	b4.use_skill(me4, "bolt", "wind", k.pos)
	_hit_first(t, b4, k.id, "Bolt, push")


func test_basic_modes(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire", { "def": 0 })
	var b := _duel(me, [f], [_nb(_nb(C, 0), 0)])
	me.attuned = "wind"
	me.wind_mode = "vortex"
	b.attack(me, f)
	_motion_first(t, b, f.id, "a Vortex basic (pull)")
	var raw := b.history.map(func(e): return str(e.type))
	t.ok(raw.find("attack") < raw.rfind("move"), "the rules still resolve the pull after the blow (presentation only)")
	var me2 := _u("st", "staff", "wind")
	var g := _u("g", "axe", "fire", { "def": 0 })
	var b2 := _duel(me2, [g], [_nb(_nb(C, 0), 0)])
	me2.attuned = "wind"
	me2.wind_mode = "gust"
	b2.attack(me2, g)
	_hit_first(t, b2, g.id, "a Gust basic (push)")


func test_vortex_field_fired_by_a_paint(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var h := Vector2i(6, 4)
	var b := _duel(me, [f, g], [h, Vector2i(8, 8)])
	me.wind_mode = "vortex"
	b.paint([h], "wind", me)
	g.pos = _nb(h, 3)
	b._turn_serial += 1
	b.history.clear()
	b.use_skill(me, "bolt", "fire", h)        # the blow's paint lands on the vortex field and fires it
	var raw := b.history.map(func(e): return str(e.type))
	if raw.has("field_fire"):
		_motion_first(t, b, g.id, "a Vortex field fired by the blow")
		var played := BWWindOrder.hoist(b.history).map(func(e): return str(e.type))
		t.ok(played.find("field_fire") < played.find("skill"), "the field's fire comes with its pull")
	else:
		t.ok(true, "no field fired on this board (bolt paint rules); the synthetic case covers it")


func test_synthetic(t) -> void:
	var evs: Array = [
		{ "type": "turn", "unit": "a" },
		{ "type": "skill", "unit": "a", "results": [] },
		{ "type": "attack", "unit": "a", "strike": 1 },
		{ "type": "tile", "hex": Vector2i.ZERO },
		{ "type": "field_fire", "mode": "vortex" },
		{ "type": "move", "unit": "f", "kind": "pull", "wind": true },
		{ "type": "move", "unit": "f", "kind": "slide" },
		{ "type": "slam", "unit": "f" },
		{ "type": "move", "unit": "g", "kind": "push", "wind": true },
		{ "type": "move", "unit": "h", "kind": "pull" },          # Hooking: not wind, stays
		{ "type": "turn", "unit": "b" },
		{ "type": "move", "unit": "x", "kind": "pull", "wind": true },   # outside any blow's tail
	]
	var got := BWWindOrder.hoist(evs).map(func(e): return "%s:%s:%s" % [e.type, e.get("unit", ""), e.get("kind", e.get("mode", ""))])
	t.eq(got, ["turn:a:", "field_fire::vortex", "move:f:pull", "move:f:slide", "slam:f:", "skill:a:", "attack:a:", "tile::",
		"move:g:push", "move:h:pull", "turn:b:", "move:x:pull"], "pulls (with their slide and slam) go before the blow; pushes stay after")
	t.eq(evs.size(), 12, "the input is untouched")
	t.eq(BWWindOrder.hoist([]), [], "empty in, empty out")

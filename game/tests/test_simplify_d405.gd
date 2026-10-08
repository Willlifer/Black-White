extends RefCounted
## D405-D410 (the author, 2026-10-08): "Casting an element on thunder should
## ignite it" (every element sets off a fuse) and "Simplify wind to just one
## hex type" (the gale only spreads; a wind basic pushes 1; Eye of the Vortex
## reworked). design/ELEMENTS.md §3.3, §19.

const C := Vector2i(4, 4)


func _board(n: int = 9) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[8, 0], [8, 1], [8, 2]] } })


func _tiles() -> BWTiles:
	return BWTiles.new(_board())


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _duel(me: BWUnit, foes: Array, at: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	return b


func _fuse(tl: BWTiles, h: Vector2i, src: String = "a") -> void:
	tl.apply([h], "thunder", src)


# ------------------------------------------------------------------ D405 the fuse

func test_every_element_ignites_a_fuse(t) -> void:
	for el in ["fire", "light", "dark"]:
		var tl := _tiles()
		_fuse(tl, C)
		var r := tl.apply([C], el, "b")
		t.eq(r.detonations.size(), 1, "%s on a fuse detonates (as before)" % el)
		t.ok(tl.at(C).is_empty(), "%s: the fuse is spent" % el)
	for el in ["ice", "wind"]:
		var tl2 := _tiles()
		_fuse(tl2, C, "a")
		var r2 := tl2.apply([C], el, "b")
		t.eq(r2.detonations.size(), 1, "%s on a fuse now detonates it (was: replaced it)" % el)
		t.near(float(r2.detonations[0].pct), float(BWTiles.DETONATE_BASE_PCT), 0.01, "%s: the empty fuse's base blast" % el)
		t.eq(str(r2.detonations[0].source), "a", "%s: credited to the fuse's owner" % el)
		t.ok(C in r2.marker_fired, "%s: a fired marker (Daisy Chain reads it)" % el)
		t.ok(tl2.at(C).is_empty(), "%s: the arrival is consumed (no stasis / gale left)" % el)
	# water electrifies instead (the D262/D264 thunder + water rule, radius 1)
	var tw := _tiles()
	_fuse(tw, C)
	var rw := tw.apply([C], "water", "b")
	t.eq(rw.detonations.size(), 0, "water on a fuse: no blast")
	t.ok(tw.shock.has(C), "water on a fuse electrifies it")
	# thunder refreshes it
	var tt := _tiles()
	_fuse(tt, C)
	tt.entries[C].timer = 1
	var rt := tt.apply([C], "thunder", "b")
	t.eq(rt.detonations.size(), 0, "thunder on a fuse doesn't blow it")
	t.eq(str(tt.at(C).marker), "fuse", "it stays a fuse")
	t.eq(int(tt.at(C).timer), BWTiles.MARK_CYCLES, "re-armed, timer refreshed")


func test_spread_never_ignites(t) -> void:
	var tl := _tiles()
	_fuse(tl, C)
	var r := tl.apply([C], "ice", "b", 1, { "propagated": true })
	t.eq(r.detonations.size(), 0, "a propagated ice arrival does nothing (containment)")
	t.eq(str(tl.at(C).marker), "fuse", "the fuse stays armed")
	# a gale copy never lands on a marker (§3.4)
	var t2 := _tiles()
	_fuse(t2, BWHex.neighbors(C)[0])
	t2.apply([C], "fire", "b")
	t2.apply([C], "wind", "b")
	t.eq(str(t2.at(BWHex.neighbors(C)[0]).marker), "fuse", "gale copies skip the fuse")


func test_static_field_still_guards(t) -> void:
	var tl := _tiles()
	_fuse(tl, C, "ally")
	var r := tl.apply([C], "ice", "me", 1, { "fuse_guard": ["ally"] })
	t.eq(r.detonations.size(), 0, "Static Field: an ally's ice doesn't set off the fuse")
	t.eq(str(tl.at(C).marker), "fuse", "it stands")


func test_preview_says_ignites(t) -> void:
	var me := _u("st", "staff", "ice")
	var f := _u("f", "axe", "fire")
	var x := Vector2i(4, 2)
	var b := _duel(me, [f], [BWHex.neighbors(x)[0]])
	b.tiles.apply([x], "thunder", f.id)
	var sim := b.simulate(me, { "kind": "skill", "key": "surge", "element": "ice", "hex": x })
	if sim.is_empty():
		sim = b.simulate(me, { "kind": "skill", "key": "bolt", "element": "ice", "hex": x })
	t.ok(not sim.is_empty(), "an ice cast on the fuse simulates")
	t.ok(sim.detonations.any(func(d): return bool(d.get("fuse", false))), "the detonation is flagged as a fuse ignition")
	t.ok("fuse" in (sim.hexes[x].kinds as Array), "the hex reads as an ignited fuse")
	var lines := BWReadability.confirm_lines(sim)
	t.ok(lines.any(func(l): return str(l.text).begins_with("Ignites the fuse")), "the confirm box says it ignites the fuse")
	t.ok(int(sim.units.get(f.id, {}).get("damage", 0)) > 0, "the splash shows on the foe beside it")
	var card := BWReadability.card_bbcode(b, x)
	t.ok(card.find("any element cast here ignites it") >= 0, "the fuse's tile card")


# ------------------------------------------------------------------ D406-D408 wind

func test_gale_card_and_no_fields(t) -> void:
	var me := _u("st", "staff", "wind")
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	var h := Vector2i(6, 4)
	b.paint([h], "wind", me)
	var card := BWReadability.card_bbcode(b, h)
	t.ok(card.find("spreads whatever lands here to adjacent hexes") >= 0, "the gale's one line")
	for word in ["Gust field", "Vortex field", "Becalm field", "arrow"]:
		t.ok(card.find(word) < 0, "no '%s' on the card" % word)
	b.paint([h], "wind", me)
	t.ok(BWReadability.card_bbcode(b, h).find("within 2") >= 0, "a gale 2 spreads within 2")


func test_wind_basic_pushes_one(t) -> void:
	var me := _u("st", "staff", "wind")
	var f := _u("f", "axe", "fire", { "def": 0 })
	var at := BWHex.neighbors(C)[0]
	var b := _duel(me, [f], [at])
	me.attuned = "wind"
	b.expected_rolls = true
	b.attack(me, f)
	t.eq(f.pos, BWHex.neighbors(at)[0], "a landed wind basic pushes the target 1 away")
	t.ok(not b.history.any(func(e): return str(e.type) == "becalm"), "and nothing else (no mode)")


func test_updraft_survives(t) -> void:
	var me := _u("st", "staff", "wind")
	me.perks = ["wind_tail"]
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(8, 8)])
	var h := Vector2i(6, 4)
	b.paint([h], "wind", me)
	t.ok(BWWind.card_lines(b, h).any(func(l): return str(l).begins_with("Updraft")), "Tailwind's Updraft line rides on its holder's gale")

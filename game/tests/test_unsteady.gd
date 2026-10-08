extends RefCounted
## D397-D401 Unsteady footing (the author, 2026-10-07: "remove rink as a
## status, have ice apply 'unsteady footing', dropping dodge and glance chance
## for units on the tile"): the values, stacking with Shatter, what counts as
## glaze (not stasis), both teams, Ice Legs, Sure-Footed and its lingering
## status, the AI's read, the forecast lines.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)
const FAR := Vector2i(10, 10)


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, el: String = "ice", extra: Dictionary = {}, perks: Array = [], ks: Array = []) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": "sword", "element": el,
		"con": 40, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	var u := BWUnit.from_roster(row)
	for p in perks:
		var pel := str(BWPicks.perk(p).element)
		if u.affinity_rank(pel) < 1:
			u.affinity[pel] = 10
		u.perks.append(p)
	for k in ks:
		u.keystones.append(k)
	return u


func _fight(players: Array, foes: Array, ppos: Array, fpos: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
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


func _glaze(b: BWBattle, h: Vector2i, src: String = "x") -> void:
	b.tiles.apply([h], "water", src)
	b.tiles.apply([h], "ice", src)


func _mod(fc: Dictionary, label_start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(label_start):
			return m
	return {}


# ------------------------------------------------------------------ the numbers

func test_values(t) -> void:
	var me := _u("me", "fire")
	var foe := _u("f", "water", { "def": 30 })          # DEF 30: glance 40, so -15 shows whole
	var b := _fight([me], [foe], [C], [E])
	var dry := b.forecast_basic(me, foe)
	_glaze(b, E)
	t.ok(b.tiles.is_glazed(E), "the foe's hex is glazed")
	t.ok(BWUnsteady.unsteady(b, foe), "a unit on glaze is Unsteady")
	var wet := b.forecast_basic(me, foe)
	t.near(float(wet.avoid.value), float(dry.avoid.value) - 10.0, 0.001, "-10 avoid")
	t.near(float(wet.glance.value), float(dry.glance.value) - 15.0, 0.001, "-15 glance")
	t.ok(float(wet.hit.value) > float(dry.hit.value), "so it's easier to hit")
	t.ok("Unsteady footing −10 avoid" in wet.notes, "a named forecast line for the avoid")
	t.ok("Unsteady footing −15 glance" in wet.notes, "and one for the glance")
	t.ok(str(wet.avoid.formula).contains("Unsteady footing"), "the avoid hover names it")
	t.ok("Unsteady" in BWBattle._tags(wet), "the cutscene tag")
	# glance never goes below 0
	var thin := _u("g", "water", { "def": 0 })
	var b2 := _fight([_u("m2", "fire")], [thin], [C], [E])
	_glaze(b2, E)
	t.eq(float(b2.forecast_basic(b2.units[0], thin).glance.value), 0.0, "glance 10 - 15 holds at 0")


func test_stacks_with_shatter(t) -> void:
	var me := _u("me", "fire")
	var foe := _u("f", "water", { "def": 30 })
	var b := _fight([me], [foe], [C], [E])
	_glaze(b, E)
	var fc := b.forecast_basic(me, foe)
	t.near(float(_mod(fc, "Shatter").get("value", 0)), 1.15, 0.001, "Shatter +15% still applies")
	t.ok(not _mod(fc, "Unsteady footing −10").is_empty() and not _mod(fc, "Unsteady footing −15").is_empty(), "with Unsteady on top")
	t.ok(fc.notes.any(func(n): return str(n).begins_with("Shatter")), "both named")


func test_stasis_and_pillars_dont_count(t) -> void:
	var me := _u("me", "fire")
	var foe := _u("f", "water", { "def": 30 })
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([E], "ice", "x")                       # empty ground: a stasis marker, glaze 0
	t.eq(str(b.tiles.at(E).get("marker", "")), "stasis", "a stasis marker")
	t.ok(not BWUnsteady.unsteady(b, foe), "stasis isn't Unsteady footing")
	var fc := b.forecast_basic(me, foe)
	t.ok(_mod(fc, "Unsteady").is_empty(), "no Unsteady lines")
	t.ok(_mod(fc, "Shatter").is_empty(), "and no Shatter")
	var p := Vector2i(7, 7)
	b.tiles.apply([p], "water", "x", 3)
	b.tiles.apply([p], "ice", me.id)
	t.ok(b.tiles.is_pillar(p) and not BWUnsteady.on_glaze(b.tiles, p), "a pillar is glazed but not ground")


func test_both_teams(t) -> void:
	var me := _u("me", "ice")
	var foe := _u("f", "water")
	var b := _fight([me], [foe], [C], [E])
	_glaze(b, C, me.id)
	t.ok(BWUnsteady.unsteady(b, me), "the ice caster on its own glaze is Unsteady too")
	t.ok(not _mod(b.forecast_basic(foe, me), "Unsteady footing").is_empty(), "the foe's forecast shows it")
	_turn(b, me)
	b.move(me, Vector2i(3, 4))
	t.ok(not BWUnsteady.unsteady(b, me), "off the glaze it's gone")


# ------------------------------------------------------------------ immunities

func test_ice_legs(t) -> void:
	var me := _u("me", "ice", {}, ["ice_skate"])
	var foe := _u("f", "water")
	var b := _fight([me], [foe], [C], [E])
	_glaze(b, C)
	t.ok(not BWUnsteady.unsteady(b, me), "Ice Legs is never Unsteady")
	var fc := b.forecast_basic(foe, me)
	t.ok(_mod(fc, "Unsteady footing −").is_empty(), "no avoid / glance lines")
	t.ok(fc.notes.any(func(n): return str(n).contains("Ice Legs ignores it")), "a note says why")
	t.near(float(_mod(fc, "Shatter").get("value", 0)), 1.15, 0.001, "Shatter still applies")


func test_sure_footed_cover(t) -> void:
	var me := _u("me", "ice", {}, [], ["skater"])
	var near := _u("n", "fire")
	var far := _u("z", "fire")
	var foe := _u("f", "water")
	var b := _fight([me, near, far], [foe], [C, Vector2i(4, 6), Vector2i(4, 8)], [Vector2i(8, 4)])
	t.eq(BWKeystones.name_of("skater"), "Sure-Footed", "the keystone's new name (id kept)")
	for h in [C, Vector2i(4, 6), Vector2i(4, 8), Vector2i(8, 4)]:
		_glaze(b, h, me.id)
	t.ok(not BWUnsteady.unsteady(b, me), "the holder ignores Unsteady")
	t.ok(not BWUnsteady.unsteady(b, near), "an ally 2 away too")
	t.ok(BWUnsteady.unsteady(b, far), "an ally 4 away doesn't")
	t.ok(BWUnsteady.unsteady(b, foe), "nor does a foe")
	t.ok(b.forecast_basic(foe, near).notes.any(func(n): return str(n).contains("Sure-Footed")), "the note names the cover")


func test_sure_footed_lingers(t) -> void:
	var me := _u("me", "ice", {}, [], ["skater"])
	var foe := _u("f", "water")
	var b := _fight([me], [foe], [Vector2i(0, 0)], [E])
	_glaze(b, E, me.id)
	_turn(b, foe)
	t.ok(b.move(foe, Vector2i(7, 4)), "the foe walks off the holder's glaze")
	t.ok(foe.statuses.has("unsteady"), "and stays Unsteady")
	t.ok(BWUnsteady.unsteady(b, foe), "off the ice")
	t.ok(str(b.forecast_basic(me, foe).avoid.formula).contains("stepped off the ice"), "the line says why")
	b.end_turn()
	t.ok(foe.statuses.has("unsteady"), "through the rest of the round")
	_turn(b, foe)
	t.ok(BWUnsteady.unsteady(b, foe), "during its next turn")
	b.end_turn()
	t.ok(not foe.statuses.has("unsteady"), "gone at the end of its next turn")
	# off glaze that isn't a holder's: nothing lingers
	var foe2 := _u("g", "water")
	var b2 := _fight([_u("p", "ice")], [foe2], [Vector2i(0, 0)], [E])
	_glaze(b2, E, "p")
	_turn(b2, foe2)
	b2.move(foe2, Vector2i(7, 4))
	t.ok(not BWUnsteady.unsteady(b2, foe2), "without Sure-Footed, off the ice is fine")


# ------------------------------------------------------------------ the AI

func test_ai_reads_it(t) -> void:
	var me := _u("me", "fire")
	var legs := _u("l", "ice", {}, ["ice_skate"])
	var b := _fight([me, legs], [_u("f", "water")], [C, Vector2i(2, 2)], [FAR])
	_glaze(b, E)
	t.near(BWPools.hazard_pct(b, me, E), BWUnsteady.AI_HAZARD, 0.001, "standing Unsteady is a hazard to the AI")
	t.near(BWPools.hazard_pct(b, me, Vector2i(3, 4)), 0.0, 0.001, "dry ground isn't")
	t.near(BWPools.hazard_pct(b, legs, E), 0.0, 0.001, "nor glaze for Ice Legs")
	# the foe on glaze is worth more to hit: its expected damage rises
	var foe: BWUnit = b.units[2]
	foe.pos = Vector2i(6, 4)
	var dry := float(b.forecast_basic(me, foe, 1.0, "", E).expected.value)
	_glaze(b, Vector2i(6, 4))
	var wet := float(b.forecast_basic(me, foe, 1.0, "", E).expected.value)
	t.ok(wet > dry * 1.14, "Shatter + Unsteady lift the expected value (%.1f -> %.1f)" % [dry, wet])


# ------------------------------------------------------------------ the tile card

func test_tile_card(t) -> void:
	var me := _u("me", "fire")
	var b := _fight([me], [_u("f", "water")], [C], [FAR])
	_glaze(b, E)
	var rep: Array = BWPools.report(b, E)
	t.ok(rep.any(func(r): return str(r[0]) == "Unsteady" and str(r[1]).contains("−10 avoid")), "the tile hover names Unsteady")
	t.ok(not rep.any(func(r): return str(r[0]) == "Rink"), "no Rink line any more")

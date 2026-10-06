extends RefCounted
## Whole fights, headless: rules hold, fights end, seeds reproduce.


func _board() -> BWBoard:
	var cells: Array = []
	for r in 10:
		for c in 10:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "t", "cols": 10, "rows": 10, "cells": cells,
		"spawns": { "player": [[1, 4], [1, 5], [1, 6]], "enemy": [[8, 4], [8, 5], [8, 6]] } })


func _squad(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var row := BWData.row("roster", id)
		if row.is_empty():
			row = { "id": id, "weapon_class": "sword", "element": "fire",
				"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
		out.append(BWUnit.from_roster(row))
	return out


func _ids(n: int, offset: int) -> Array:
	var r := BWData.table("roster")
	var out: Array = []
	for i in n:
		out.append(str(r[(i + offset) % r.size()].id) if not r.is_empty() else "u%d" % (i + offset))
	return out


func _autoplay(b: BWBattle, max_turns: int = 400) -> int:
	var turns := 0
	while not b.over and turns < max_turns:
		BWAI.take_turn(b)
		turns += 1
	return turns


func test_turn_rules(t) -> void:
	var b := BWBattle.new(_board(), 3)
	b.setup(_squad(["a1", "a2", "a3"]), _squad(["e1", "e2", "e3"]))
	var u := b.current()
	t.ok(u != null, "someone has the first turn")
	var far := Vector2i(9, 9)
	t.ok(not b.move(u, far), "cannot move past move range")
	var r := b.reachable(u)
	var dest: Vector2i = u.pos
	for h in r:
		if r[h].stop and h != u.pos:
			dest = h
			break
	t.ok(b.move(u, dest), "legal move")
	t.ok(not b.move(u, u.pos + Vector2i(0, 1)), "only one move per turn")
	var other: BWUnit = b.units[0] if b.units[0] != u else b.units[1]
	t.ok(not b.move(other, other.pos), "not your turn")


func test_fights_end_and_reproduce(t) -> void:
	var lengths: Array = []
	for s in 5:
		var b1 := BWBattle.new(_board(), 100 + s)
		b1.setup(_squad(_ids(3, s)), _squad(_ids(3, s + 3)))
		var n1 := _autoplay(b1)
		t.ok(b1.over, "seed %d: fight ends (turns %d)" % [s, n1])
		t.ok(b1.winner in ["player", "enemy"], "seed %d: has a winner" % s)
		var b2 := BWBattle.new(_board(), 100 + s)
		b2.setup(_squad(_ids(3, s)), _squad(_ids(3, s + 3)))
		_autoplay(b2)
		t.eq(JSON.stringify(b1.history), JSON.stringify(b2.history), "seed %d: identical replay" % s)
		lengths.append(b1.cycle)
	print("    [info] AI-vs-AI fight length in cycles: %s" % [lengths])


func test_ko_and_growth(t) -> void:
	var b := BWBattle.new(_board(), 9)
	b.setup(_squad(_ids(3, 0)), _squad(_ids(3, 3)))
	_autoplay(b)
	var kos := b.history.filter(func(e): return e.type == "ko")
	t.ok(kos.size() >= 3, "a finished 3v3 has at least 3 KOs")
	# One award per action (attack or skill): 30 if it knocked anyone out, else 10
	# (ELEMENTS §8.4); tile knockouts credit their hostile source 30.
	var actions := b.history.filter(func(e): return e.type == "attack" or e.type == "skill")
	var xp_total := 0
	for u in b.units:
		xp_total += u.xp + (u.level - 1) * BWProgression.XP_PER_LEVEL
	var action_xp := 0
	for e in actions:
		action_xp += 30 if e.ko else 10
	var tile_kos := kos.filter(func(e): return e.has("cause") and e.cause != "riposte" and e.by != "").size()
	t.eq(xp_total, action_xp + tile_kos * 30, "xp = 10 per action, 30 per knockout action")
	for e in b.history:
		if e.type == "attack":
			t.ok(e.result.damage >= 0 and (e.result.damage > 0) == e.result.hit, "damage iff hit")


func test_ground_in_battle(t) -> void:
	var b := BWBattle.new(_board(), 4)
	b.setup(_squad(["a1", "a2", "a3"]), _squad(["e1", "e2", "e3"]))
	var u := b.current()
	var hp0 := u.hp
	# Standing fire hurts at turn start; light heals; water raises move cost.
	var ahead := u.pos + Vector2i(1, 0)
	b.tiles.apply([ahead], "water", "x", 3)
	var r := b.reachable(u)
	t.eq(r[ahead].cost, 3, "water 3 costs 1 + 2 to enter")
	var foe: BWUnit = b.foes_of(u)[0]
	b.tiles.apply([foe.pos], "light", "x", 2)
	var fc := b.forecast_basic(u, foe)
	var base: float = BWFormulas.hit_chance(u, foe, BWFormulas.WEAPON).value
	t.near(fc.hit.value, minf(100.0, base + 14.0), 0.001, "light 2 under target: +14 hit")
	b.tiles.apply([u.pos], "fire", "x", 2)
	b.end_turn()
	while b.current() != u and not b.over:
		b.end_turn()
	t.eq(u.hp, hp0 - BWTiles.tile_damage(u, 8.0, "fire"), "fire 2 burns 8% at turn start")


func test_detonation_in_battle(t) -> void:
	var b := BWBattle.new(_board(), 4)
	b.setup(_squad(["a1", "a2", "a3"]), _squad(["e1", "e2", "e3"]))
	var me := b.current()
	var foe: BWUnit = b.foes_of(me)[0]
	b.tiles.apply([foe.pos], "fire", me.id, 3)
	var hp_foe := foe.hp
	b.paint([foe.pos], "thunder", me)
	# 5 + 4×3 = 17%; me has no thunder rank so no bonus.
	t.eq(hp_foe - foe.hp, BWTiles.tile_damage(foe, 17.0, "thunder"), "occupant takes the full blast")
	t.ok(b.tiles.at(foe.pos).is_empty(), "detonated tile is erased")


func test_undo_move(t) -> void:
	var b := BWBattle.new(_board(), 4)
	b.setup(_squad(["a1", "a2", "a3"]), _squad(["e1", "e2", "e3"]))
	var u := b.current()
	var start := u.pos
	var hp0 := u.hp
	var dest := start + Vector2i(1, 0)
	b.tiles.apply([dest], "fire", "x", 3)
	var tiles_before := JSON.stringify(b.tiles.entries)
	t.ok(not b.can_undo_move(u), "nothing to undo before moving")
	t.ok(b.move(u, dest), "move into fire")
	t.ok(u.hp < hp0, "fire crossing hurt")
	t.ok(b.undo_move(u), "undo")
	t.eq(u.pos, start, "back on the starting tile")
	t.eq(u.hp, hp0, "crossing damage reverted")
	t.ok(not u.moved and b.can_move(u), "can move again")
	t.eq(JSON.stringify(b.tiles.entries), tiles_before, "tiles restored")
	t.ok(b.move(u, dest), "move again")
	var foe: BWUnit = b.foes_of(u)[0]
	foe.pos = dest + Vector2i(1, 0)
	b.attack(u, foe)
	t.ok(not b.can_undo_move(u), "attacking makes the move final")

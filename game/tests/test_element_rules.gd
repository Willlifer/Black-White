extends RefCounted
## D86, the author-approved element rules (design/ELEMENTS.md §8.5): chain
## lightning on fuse tiles (conductive), Spark (thunder on uncharged ground)
## and Shatter (any attack on a glazed hex).

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _foe(id: String, extra: Dictionary = {}) -> BWUnit:
	return _u(id, "axe", "water", extra)


func _fight(me: BWUnit, foes: Array, at: Array, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	return b


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _has_mod(fc: Dictionary, label_start: String) -> bool:
	return fc.mods.any(func(m): return str(m.label).begins_with(label_start))


# ------------------------------------------------------------------ chain lightning

func test_chain_arcs_half_to_nearest_teammate(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var near := _foe("near", { "con": 300 })
	var far := _foe("far", { "con": 300 })
	var b := _fight(me, [foe, near, far], [E, Vector2i(8, 4), Vector2i(10, 10)])
	b.tiles.apply([E], "thunder", "x")                 # a fuse under the target
	t.ok(b.tiles.conductive(E), "a fuse makes its hex conductive")
	var fc := b.forecast_basic(me, foe)
	t.ok(fc.notes.has("Conductive (thunder tile): 50% arcs to near"), "forecast names the arc and who it reaches (%s)" % [fc.notes])
	t.ok(float(fc.get("arc_ev", 0.0)) > 0.0, "the AI sees the arc's expected damage")
	var hp := near.hp
	var res := b.attack(me, foe)
	t.ok(res.hit, "hit lands (dex 100)")
	var ch := _events(b, "chain")
	t.eq(ch.size(), 1, "one arc")
	t.eq([ch[0].from, ch[0].to], ["f", "near"], "from the conductive target to its nearest teammate")
	t.eq(int(ch[0].amount), maxi(1, roundi(res.damage * 0.5)), "half the damage (no thunder resistance here)")
	t.eq(hp - near.hp, int(ch[0].amount), "the arc is dealt")
	t.eq(far.hp, far.max_hp(), "only the nearest takes it")
	t.ok(b.tiles.conductive(E), "the fuse stays (a hit doesn't fire a marker)")


func test_chain_no_range_limit_and_ties(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var lone := _foe("lone", { "con": 300 })
	var b := _fight(me, [foe, lone], [E, Vector2i(10, 10)])
	b.tiles.apply([E], "thunder", "x")
	b.attack(me, foe)
	t.eq(_events(b, "chain").map(func(e): return e.to), ["lone"], "no range limit: 9 hexes away still takes it")
	# two teammates at the same distance: setup order breaks the tie
	var me2 := _u("me", "sword", "fire", { "dex": 100 })
	var f2 := _foe("f", { "con": 300 })
	var a := _foe("a", { "con": 300 })
	var z := _foe("z", { "con": 300 })
	var b2 := _fight(me2, [f2, z, a], [E, Vector2i(7, 4), Vector2i(5, 6)])
	t.eq(BWHex.distance(E, Vector2i(7, 4)), BWHex.distance(E, Vector2i(5, 6)), "set-up: equidistant")
	b2.tiles.apply([E], "thunder", "x")
	b2.attack(me2, f2)
	t.eq(_events(b2, "chain").map(func(e): return e.to), ["z"], "tie goes to the earlier unit in setup order")


func test_chain_only_once(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var n2 := _foe("n2", { "con": 300 })
	var n3 := _foe("n3", { "con": 300 })
	var b := _fight(me, [foe, n2, n3], [E, Vector2i(7, 4), Vector2i(9, 4)])
	b.tiles.apply([E, Vector2i(7, 4)], "thunder", "x")      # the second unit is on a fuse too
	b.attack(me, foe)
	t.eq(_events(b, "chain").size(), 1, "the arc never arcs again, even onto another fuse")
	t.eq(n3.hp, n3.max_hp(), "no loop onward")


func test_chain_ko_credit_and_tile_damage(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100, "str": 60 })
	var foe := _foe("f", { "con": 300 })
	var weak := _foe("weak")
	var b := _fight(me, [foe, weak], [E, Vector2i(8, 4)])
	weak.hp = 1
	b.tiles.apply([E], "thunder", "x")
	b.attack(me, foe)
	var kos := _events(b, "ko").filter(func(e): return e.unit == "weak")
	t.eq(kos.size(), 1, "the arc knocks out")
	t.eq(kos[0].by, "me", "credit goes to the attacker")
	t.eq(str(kos[0].get("cause", "")), "chain", "cause: chain")
	# tile damage arcs too: detonation splash onto a neighbour standing on a fuse
	var me2 := _u("me", "staff", "thunder")
	var on_fuse := _foe("of", { "con": 300 })
	var mate := _foe("mate", { "con": 300 })
	var X := Vector2i(7, 4)
	var N := Vector2i(8, 4)
	var b2 := _fight(me2, [on_fuse, mate], [N, Vector2i(9, 6)])
	b2.tiles.apply([N], "thunder", "x")
	b2.tiles.apply([X], "fire", "x")
	b2.paint([X], "thunder", me2)                      # detonates X; N takes the splash
	var td := _events(b2, "tile_damage").filter(func(e): return e.unit == "of")
	t.eq(td.size(), 1, "splash on the conductive neighbour")
	var ch := _events(b2, "chain")
	t.eq(ch.map(func(e): return [e.from, e.to]), [["of", "mate"]], "tile damage arcs from a fuse")
	t.eq(int(ch[0].amount), maxi(1, roundi(int(td[0].amount) * 0.5)), "half of the splash")


func test_conductive_then_detonation(t) -> void:
	# A thunder-fuse occupant hit by a fire Channel: the hit arcs first (pre-action
	# ground), then the fire lands on the fuse and detonates it; the blast does not
	# arc from that hex because the fuse is spent.
	var me := _u("me", "staff", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var mate := _foe("mate", { "con": 300 })
	var T := Vector2i(6, 4)
	var b := _fight(me, [foe, mate], [T, Vector2i(9, 8)])
	b.tiles.apply([T], "thunder", "x")
	b.attack(me, foe)
	var types := b.history.map(func(e): return e.type)
	t.eq(_events(b, "chain").size(), 1, "one arc: from the hit only")
	t.eq(_events(b, "detonate").size(), 1, "the fire on the fuse still detonates (§3.3, unchanged)")
	t.ok(types.find("chain") < types.find("detonate"), "the arc comes before the blast")
	t.ok(not b.tiles.conductive(T), "the fuse is spent")


# ------------------------------------------------------------------ spark

func test_spark(t) -> void:
	var me := _u("me", "staff", "thunder")
	var foe := _foe("f")
	var b := _fight(me, [foe], [Vector2i(6, 4)])
	var fc := b.forecast_basic(me, foe)
	t.ok(_has_mod(fc, "Spark: +10%"), "thunder Channel on bare ground: Spark")
	t.ok(fc.damage.formula.contains("Spark: +10%"), "named in the damage breakdown")
	t.ok(fc.notes.has("Spark: +10%"), "and listed under the numbers")
	var no: Array = fc.mods.filter(func(m): return not str(m.label).begins_with("Spark"))
	var plain := BWFormulas.forecast(me, foe, BWFormulas.SPELL, 11, "thunder", 0.0, 0.0, 1.0, no)
	t.eq(fc.damage.value, maxf(1.0, roundf(plain.damage.value * 1.1)), "+10% after mitigation")
	t.ok(_has_mod(b.skill_preview(me, "surge", "thunder", Vector2i(6, 4)).forecasts["f"], "Spark"), "thunder skills spark")
	b.tiles.apply([Vector2i(6, 4)], "thunder", "x")
	t.ok(_has_mod(b.forecast_basic(me, foe), "Spark"), "a fuse is not charge: still sparks")
	b.tiles.apply([Vector2i(6, 4)], "fire", "x")       # fires the fuse: blast erases the tile
	b.tiles.apply([Vector2i(6, 4)], "fire", "x")
	t.ok(b.tiles.charged(Vector2i(6, 4)), "set-up: charged hex")
	t.ok(not _has_mod(b.forecast_basic(me, foe), "Spark"), "charged ground: no spark")
	var fire := _u("me", "staff", "fire")
	var b2 := _fight(fire, [_foe("g")], [Vector2i(6, 4)])
	t.ok(not _has_mod(b2.forecast_basic(fire, b2.units[1]), "Spark"), "only thunder sparks")
	# pistols: a thunder round sparks, plain lead doesn't
	var gun := _u("me", "pistols", "thunder")
	var tgt := _foe("p")
	var b3 := _fight(gun, [tgt], [Vector2i(8, 4)])
	t.ok(not _has_mod(b3.forecast_basic(gun, tgt), "Spark"), "unloaded pistol: no spark")
	b3.use_skill(gun, "reload", "thunder", C)
	var pf := b3.forecast_basic(gun, tgt)
	t.ok(_has_mod(pf, "Spark"), "thunder round: spark")
	t.ok(_has_mod(pf, "Own round (thunder)"), "and it's the pistolero's own element (D87)")


# ------------------------------------------------------------------ shatter

func test_shatter(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe("f")
	var b := _fight(me, [foe], [E])
	var plain: float = b.forecast_basic(me, foe).damage.value
	b.tiles.apply([E], "water", "x")
	b.tiles.apply([E], "ice", "x")
	t.ok(b.tiles.is_glazed(E), "set-up: glazed")
	var fc := b.forecast_basic(me, foe)
	t.ok(_has_mod(fc, "Shatter (glazed): +15%"), "basic attack on a glazed hex: Shatter")
	t.eq(fc.damage.value, maxf(1.0, roundf(plain * 1.15)), "+15%")
	t.ok(_has_mod(b.skill_preview(me, "striketwice", "fire", E).forecasts["f"], "Shatter"), "skills shatter")
	var staff := _u("st", "staff", "thunder")
	var b2 := _fight(staff, [_foe("g")], [Vector2i(6, 4)])
	b2.tiles.apply([Vector2i(6, 4)], "water", "x")
	b2.tiles.apply([Vector2i(6, 4)], "ice", "x")
	var sf := b2.forecast_basic(staff, b2.units[1])
	t.ok(_has_mod(sf, "Shatter"), "spells shatter")
	t.ok(not _has_mod(sf, "Spark"), "glazed ground is charged: no Spark alongside")
	t.ok(_has_mod(sf, "Conducted through Water 1"), "and it stacks with conduction")
	var res := b.attack(me, foe)
	t.ok(not res.is_empty(), "the attack resolves")
	t.ok(b.tiles.is_glazed(E), "the glaze is not consumed")
	t.ok(_events(b, "attack")[0].tags.has("Shatter"), "the attack event carries the Shatter tag")

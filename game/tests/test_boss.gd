extends RefCounted
## The multi-hex boss (BWRun.make_boss, size 2 = 7 hexes): placement,
## occupancy, movement, reach, area hits once, tiles at the centre (E15), and
## a whole fight on the arena with its basic AI.

const N := 13
const B := Vector2i(6, 6)          # boss centre on the test board


func _board(enemy_spawns: Array = [[6, 6]]) -> BWBoard:
	var cells: Array = []
	for r in N:
		for c in N:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "boss", "cols": N, "rows": N, "cells": cells,
		"spawns": { "player": [[0, 12], [1, 12], [2, 12]], "enemy": enemy_spawns } })


func _u(id: String, wc: String = "sword", el: String = "fire", extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _boss() -> BWUnit:
	return BWRun.new().make_boss()


func _fight(players: Array, ppos: Array, board: BWBoard = null, seed_value: int = 3) -> BWBattle:
	var b := BWBattle.new(board if board else _board(), seed_value)
	b.setup(players, [_boss()])
	for i in players.size():
		players[i].pos = ppos[i]
	return b


func _boss_of(b: BWBattle) -> BWUnit:
	return b.side("enemy")[0]


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


## Every living footprint on passable ground, no two overlapping.
func _sound(b: BWBattle) -> bool:
	var seen := {}
	for u in b.units:
		if not u.alive():
			continue
		for f in u.footprint():
			if not b.board.is_passable(f) or seen.has(f):
				return false
			seen[f] = true
	return true


func test_the_giant(t) -> void:
	var g := _boss()
	t.eq(g.size, 2, "size 2")
	t.eq(g.max_hp(), BWRun.GIANT_HP, "D485: 5000 HP")
	t.eq(BWRun.GIANT_HP, 5000, "10× the brief's 500")
	g.pos = B
	t.eq(g.footprint().size(), 7, "centre + 6 around it")
	t.ok(B in g.footprint() and BWHex.neighbors(B).all(func(h): return h in g.footprint()), "exactly its ring")


func test_placement(t) -> void:
	var b := _fight([_u("p")], [Vector2i(0, 12)])
	t.eq(_boss_of(b).pos, B, "a spawn whose ring fits: placed there")
	# Edge spawn: its ring falls off the map, so the nearest hex that fits.
	var b2 := _fight([_u("p")], [Vector2i(0, 12)], _board([[6, 0]]))
	var g := _boss_of(b2)
	t.eq(BWHex.distance(g.pos, Vector2i(6, 0)), 1, "nearest fitting hex to the edge spawn")
	t.ok(b2.board.fits(g.pos, 1), "whole footprint on the board")
	# Second spawn used when the first doesn't fit.
	var b3 := _fight([_u("p")], [Vector2i(0, 12)], _board([[6, 0], [6, 6]]))
	t.eq(_boss_of(b3).pos, B, "falls through to a spawn that fits")
	# Jagged ground and units are respected.
	var bd := _board([[6, 6]])
	bd.set_cell(Vector2i(7, 6), "jagged")
	var b4 := _fight([_u("p")], [Vector2i(0, 12)], bd)
	t.ok(_boss_of(b4).pos != B, "a jagged hex in the ring moves it off the spawn")
	t.ok(b4.board.fits(_boss_of(b4).pos, 1) and _sound(b4), "onto ground that fits")
	# On the real arena (all spawns on the back rows).
	var arena := BWBoard.load_file("res://maps/arena.json")
	var b5 := BWBattle.new(arena, 1)
	b5.setup([_u("a"), _u("b"), _u("c")], [_boss()])
	t.ok(_sound(b5), "arena: the boss stands on 7 passable hexes, clear of the squad")


func test_occupancy(t) -> void:
	var b := _fight([_u("p")], [Vector2i(0, 12)])
	var g := _boss_of(b)
	t.ok(g.footprint().all(func(h): return b.unit_at(h) == g), "unit_at answers for all 7 hexes")
	t.ok(b.unit_at(Vector2i(6, 4)) == null, "and not beyond")
	var p: BWUnit = b.side("player")[0]
	t.ok(not b.can_stand(p, Vector2i(7, 6)), "nobody stands inside the boss")
	p.pos = Vector2i(6, 9)
	_turn(b, p)
	var r := b.reachable(p)
	t.ok(g.footprint().all(func(h): return not r.has(h)), "a unit can't walk through its footprint")


func test_boss_movement(t) -> void:
	var bd := _board()
	bd.set_cell(Vector2i(9, 6), "jagged")
	var p := _u("p")
	var b := _fight([p], [Vector2i(6, 9)], bd)
	var g := _boss_of(b)
	_turn(b, g)
	var r := b.reachable(g)
	var ok := true
	var hits_rock := false
	for h in r:
		if r[h].stop and h != g.pos:
			ok = ok and b.can_stand(g, h)
			hits_rock = hits_rock or BWHex.distance(h, Vector2i(9, 6)) <= 1
	t.ok(ok, "every stop fits the whole footprint")
	t.ok(not hits_rock, "no stop puts a footprint hex on jagged ground")
	t.ok(not r.has(Vector2i(6, 8)), "nor on the player")
	var dest := Vector2i(4, 5)
	t.ok(r.has(dest) and b.move(g, dest), "it moves")
	t.ok(_sound(b), "and still fits")


func test_reach_both_ways(t) -> void:
	var p := _u("p", "sword", "fire")
	var b := _fight([p], [Vector2i(8, 6)])        # 2 from the centre: touching the ring
	var g := _boss_of(b)
	t.ok(b.in_range(p, g), "a sword reaches the boss by its ring")
	t.ok(b.in_range(g, p), "and the boss's axe reaches back from its ring")
	p.pos = Vector2i(9, 6)
	t.ok(not b.in_range(p, g), "3 from the centre: out of sword reach")
	var archer := _u("a", "bow", "fire")
	var b2 := _fight([archer], [Vector2i(6, 11)])
	var targets := b2.skill_targets(archer, "energized_shot", "fire")
	var on_boss := targets.filter(func(h): return b2.unit_at(h) == _boss_of(b2))
	t.ok(on_boss.size() >= 3, "a unit-targeted skill can click any reachable boss hex")
	_turn(b2, archer)
	var ring_hex: Vector2i = on_boss.filter(func(h): return h != B)[0]
	var e := b2.use_skill(archer, "energized_shot", "fire", ring_hex)
	t.eq(e.results.size(), 1, "aimed at a ring hex, it hits the boss")


func test_area_hits_once(t) -> void:
	var mage := _u("m", "staff", "fire")
	var b := _fight([mage], [Vector2i(6, 10)])
	var g := _boss_of(b)
	_turn(b, mage)
	var target := Vector2i(6, 7)                  # the ring's lower edge: surge covers 3+ boss hexes
	var pv := b.skill_preview(mage, "surge", "fire", target)
	var covered := (pv.hexes as Array).filter(func(h): return b.unit_at(h) == g).size()
	t.ok(covered >= 3, "the shape covers several boss hexes (%d)" % covered)
	t.eq(pv.units, [g.id], "and lists the boss once")
	var e := b.use_skill(mage, "surge", "fire", target)
	t.eq(e.results.size(), 1, "one roll, one damage number")


func test_tiles_read_the_centre(t) -> void:
	var p := _u("p")
	var b := _fight([p], [Vector2i(0, 12)])
	var g := _boss_of(b)
	var ring := BWHex.neighbors(B)[0]
	b.tiles.apply([ring], "fire", "", 3)
	_turn(b, g)
	t.eq(b.history.filter(func(e): return e.type == "tile_damage" and e.unit == g.id).size(), 0,
		"fire under a ring hex: no burn (E15)")
	b.tiles.apply([B], "fire", "", 3)
	_turn(b, g)
	var burns := b.history.filter(func(e): return e.type == "tile_damage" and e.unit == g.id)
	t.eq(burns.size(), 1, "fire under the centre burns")
	t.eq(int(burns[0].amount), BWTiles.tile_damage(g, 12.0, "fire"), "once, at 12% of 500 after resistance")
	# A detonation on a ring hex is splash (centre 1 away), not a direct blast.
	var zap := _u("z", "staff", "thunder")
	var b2 := _fight([zap], [Vector2i(0, 12)])
	var g2 := _boss_of(b2)
	b2.tiles.apply([ring], "fire", "")
	var h := g2.hp
	b2.paint([ring], "thunder", zap)
	t.eq(h - g2.hp, maxi(1, int(BWTiles.tile_damage(g2, 9.0, "thunder", 1.05) / 2.0)), "half, as a neighbour")


func test_displacing_the_boss(t) -> void:
	# Charge: the walk stops at the boss's edge and shoves it 1 hex.
	var axe := _u("x", "axe", "fire")
	var b := _fight([axe], [Vector2i(9, 6)])
	var g := _boss_of(b)
	_turn(b, axe)
	var e := b.use_skill(axe, "charge", "fire", Vector2i(8, 6))
	t.ok(not e.is_empty(), "charge resolves")
	t.eq(g.pos, Vector2i(5, 6), "the boss is shoved 1 hex along the heading")
	t.eq(axe.pos, Vector2i(7, 6), "the charger stops where the ring was")
	t.ok(_sound(b), "nobody overlaps")
	# Impact: pushed only if its whole footprint fits.
	var hammer := _u("h", "axe", "fire", { "dex": 60 })
	hammer.equipment["main_hand"] = { "uid": "w", "base": "axe", "slot": "main_hand", "weight": "axe",
		"tier": "E", "stats": {}, "enchant": "impact", "worn": {} }
	var bd := _board()
	for r in N:
		bd.set_cell(Vector2i(4, r), "jagged")      # a wall just past the far side of the ring
	var b2 := _fight([hammer], [Vector2i(8, 6)], bd)
	var g2 := _boss_of(b2)
	_turn(b2, hammer)
	b2.attack(hammer, g2)
	t.eq(g2.pos, B, "no room behind it: it stays put")
	t.ok(_sound(b2), "still sound")


func test_boss_fight_on_the_arena(t) -> void:
	var ids := BWData.table("roster").slice(0, 3).map(func(x): return str(x.id))
	var squad: Array = ids.map(func(id): return BWUnit.from_roster(BWData.row("roster", id)))
	var b := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 11)
	b.setup(squad, [_boss()])
	var g := _boss_of(b)
	var sound := true
	var turns := 0
	while not b.over and turns < 600:
		BWAI.take_turn(b)
		turns += 1
		sound = sound and _sound(b)
	t.ok(b.over, "the boss fight ends (%d turns, %s wins)" % [turns, b.winner])
	t.ok(sound, "after every turn: footprints on passable ground, never overlapping")
	var mine := b.history.filter(func(e): return e.get("unit", "") == g.id)
	t.ok(mine.any(func(e): return e.type == "move"), "the boss moves")
	t.ok(mine.any(func(e): return e.type == "attack"), "and hits")
	t.ok(not mine.any(func(e): return e.type == "skill"), "basic AI: no skills")


## D485-D486: the 10× Giant. 5000 HP, percentages against 500, no Fatigue.
func test_giant10_d485(t) -> void:
	var g := _boss()
	t.eq(g.hp, 5000, "starts full at 5000")
	t.eq(g.pct_base_hp(), BWRun.GIANT_PCT_BASE, "the pct base is the old 500")
	t.eq(g.stat("con"), 50, "CON untouched (fixed_hp bypasses it)")
	var p := _u("p")
	t.eq(p.pct_base_hp(), p.max_hp(), "everyone else: the pct base is max HP")
	# A tile percentage: 12% of 500, not of 5000.
	var res := minf(BWFormulas.elemental_resist(g, "fire"), BWTiles.ELEM_RESIST_CAP)
	t.eq(BWTiles.tile_damage(g, 12.0, "fire"), maxi(1, roundi(500 * 0.12 * (1.0 - res / 100.0))), "fire 12% reads 500")
	t.ok(BWTiles.tile_damage(g, 12.0, "fire") < 100, "a burn is a dent, not 600")
	t.ok(BWFormulas.hp(g).formula.contains("% of 500 (the Giant's pct base)"), "the HP breakdown says so")
	t.eq(BWFormulas.pct_note(g), " (% of 500, the Giant's pct base)", "the % HP lines' tag")
	t.eq(BWFormulas.pct_note(p), "", "no tag on anyone else")
	# A heal on the Giant: 10% of 500 = 50.
	var b := _fight([p], [Vector2i(0, 12)])
	var gb := _boss_of(b)
	gb.hp = 1000
	b._heal(gb, 10.0, "test")
	t.eq(gb.hp, 1050, "a 10% heal on the Giant is 50")
	# No Fatigue at 15/20 in the Giant fight; the far backstop still holds.
	t.ok(b.giant_fight(), "the fight knows it is the Giant's")
	b.cycle = BWFormulas.FATIGUE_NONE + 5
	t.eq(b.heal_fade(), 1.0, "round 25: heals whole against the Giant")
	b.cycle = BWFormulas.GIANT_FATIGUE_HALF
	t.eq(b.heal_fade(), 0.5, "the backstop halves at %d" % BWFormulas.GIANT_FATIGUE_HALF)
	b.cycle = BWFormulas.GIANT_FATIGUE_NONE
	t.eq(b.heal_fade(), 0.0, "and stops at %d" % BWFormulas.GIANT_FATIGUE_NONE)
	var nb := BWBattle.new(_board(), 3)
	nb.setup([_u("a")], [_u("e")])
	nb.cycle = BWFormulas.FATIGUE_NONE
	t.ok(not nb.giant_fight() and nb.heal_fade() == 0.0, "an ordinary fight keeps D474")


## D487 (author: "Bring the 6 man squad"): the Giant fight fields the whole squad.
func test_giant_six_d488(t) -> void:
	var ids: Array = BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))
	var r := BWRun.start(ids, 5)
	t.eq(BWRun.deploy_count_of("arena"), 3, "the arena itself still fields 3 in normal rooms")
	t.eq(r.deploy_for(BWRun.BOSS_FIGHT), 6, "the Giant: all six")
	t.eq(r.map_for(BWRun.BOSS_FIGHT), "arena", "on the arena")
	t.eq(r.enemies_for(BWRun.BOSS_FIGHT).size(), 1, "still one Giant")
	var small := BWRun.start(ids.slice(0, 4), 5)
	t.eq(small.deploy_for(BWRun.BOSS_FIGHT), 4, "a squad of 4 brings its 4")
	var squad: Array = ids.map(func(id): return BWUnit.from_roster(BWData.row("roster", id)))
	var b := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 11)
	b.setup(squad, [_boss()])
	var g := _boss_of(b)
	var seen := {}
	for p in squad:
		t.ok(p.pos in b.board.deploy.player or p.pos in b.board.spawns.player, "%s starts in the player zone" % p.id)
		t.ok(not p.pos in g.footprint(), "%s is clear of the Giant's ring" % p.id)
		seen[p.pos] = true
	t.eq(seen.size(), 6, "six different hexes")
	t.ok(_sound(b), "every footprint sound")

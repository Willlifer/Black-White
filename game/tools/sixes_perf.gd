extends SceneTree
## D323: the AI's turn time with 12 units (6v6), headless.
##   godot --headless --path . --script res://tools/sixes_perf.gd
## Env: FIGHT (default 6: levels, gear tier, enemy keystones), SEEDS (default 3),
## BOARD (commons | big19: a generated open 19×17 board with Commons-style
## spawns | both, default both), CAPS="hexes,targets" (BWAI.BIG_HEX_CAP and
## BIG_TARGET_CAP; "0,0" = no pruning, the D323 baseline).
## Prints per fight: turns, rounds, winner, total ms, AI turn mean / p95 / worst.


func _initialize() -> void:
	var fight := int(OS.get_environment("FIGHT")) if OS.get_environment("FIGHT") != "" else 6
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 3
	var which := OS.get_environment("BOARD") if OS.get_environment("BOARD") != "" else "both"
	if OS.get_environment("CAPS") != "":                 # "hexes,targets" (0,0 = no pruning)
		var c := OS.get_environment("CAPS").split(",")
		BWAI.BIG_HEX_CAP = int(c[0])
		BWAI.BIG_TARGET_CAP = int(c[1])
		if int(c[0]) <= 0:
			BWAI.BIG_SWAP_HEXES = 0
	var boards: Array = []
	if which in ["commons", "both"]:
		boards.append(["commons", BWBoard.load_file("res://maps/commons.json")])
	if which in ["big19", "both"]:
		boards.append(["big19", big_board()])
	for bb in boards:
		var all_turns: Array = []
		for s in seeds:
			var res := fight_on(bb[1], fight, 500 + s)
			all_turns.append_array(res.turn_ms)
			res.turn_ms.sort()
			print("%s fight %d seed %d: %dv%d turns %d rounds %d winner %s total %d ms  AI turn mean %.1f p95 %.1f worst %.1f ms" % [
				bb[0], fight, 500 + s, res.p, res.e, res.turns, res.rounds, res.winner, res.total_ms,
				_mean(res.turn_ms), _pct(res.turn_ms, 0.95), res.turn_ms.back() if not res.turn_ms.is_empty() else 0.0])
		all_turns.sort()
		print("%s ALL: %d turns, mean %.1f p95 %.1f worst %.1f ms (caps %d hexes, %d targets)" % [bb[0], all_turns.size(), _mean(all_turns),
			_pct(all_turns, 0.95), all_turns.back() if not all_turns.is_empty() else 0.0, BWAI.BIG_HEX_CAP, BWAI.BIG_TARGET_CAP])
	quit()


## A run at fight n on Commons: its first six levelled and geared to the
## fight, against the six that fight's room draws (the 6v6 path end to end).
static func sides(n: int, seed_value: int) -> Array:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
	run.force_map = "commons"
	for u in run.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
			u.equipment[slot] = run.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), run.tier_for(n))
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
	run.fight = n
	var players: Array = run.squad.slice(0, run.deploy_for(n))
	run.prepare_for_battle(players)
	return [players, run.enemies_for(n)]


static func fight_on(board: BWBoard, n: int, seed_value: int) -> Dictionary:
	var sd := sides(n, seed_value)
	var b := BWBattle.new(board, seed_value)
	b.setup(sd[0], sd[1])
	var turn_ms: Array = []
	var guard := 0
	var t0 := Time.get_ticks_msec()
	while not b.over and guard < 2000:
		var t := Time.get_ticks_usec()
		BWAI.take_turn(b)
		turn_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		guard += 1
	return { "p": sd[0].size(), "e": sd[1].size(), "turns": guard, "rounds": b.cycle, "winner": b.winner,
		"total_ms": Time.get_ticks_msec() - t0, "turn_ms": turn_ms }


## An open 19×17 board: Commons' features scaled out (a knoll, four hills,
## rocks), six spawns a side two rows in from each edge.
static func big_board() -> BWBoard:
	var cells: Array = []
	for r in 17:
		for q in (19 if r % 2 == 0 else 18):
			var h := Vector2i(q, r)
			var e := 0
			var kind := "neutral"
			var dk := mini(BWHex.distance(h, Vector2i(8, 8)), BWHex.distance(h, Vector2i(9, 8)))
			if dk == 0:
				e = 2
			elif dk == 1:
				e = 1
			for c in [Vector2i(4, 5), Vector2i(14, 5), Vector2i(4, 11), Vector2i(14, 11)]:
				var d := BWHex.distance(h, c)
				e = maxi(e, 2 if d == 0 else (1 if d == 1 else 0))
			if h in [Vector2i(7, 6), Vector2i(11, 6), Vector2i(7, 10), Vector2i(11, 10), Vector2i(1, 8), Vector2i(17, 8)]:
				kind = "jagged"
			if h.x in [2, 3, 15, 16] and h.y in [7, 9]:
				kind = "grassy"
			cells.append({ "q": q, "r": r, "terrain": kind, "elevation": e })
	var p := [[8, 15], [9, 15], [9, 16], [6, 15], [11, 15], [9, 14]]
	var en := [[9, 1], [8, 1], [9, 0], [11, 1], [6, 1], [9, 2]]
	return BWBoard.from_dict({ "name": "Big 19x17", "cols": 19, "rows": 17, "deploy_count": 6, "cells": cells,
		"spawns": { "player": p, "enemy": en } })


static func _mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(1.0, a.size())


static func _pct(sorted: Array, p: float) -> float:
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * p))]) if not sorted.is_empty() else 0.0

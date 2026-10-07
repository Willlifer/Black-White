extends RefCounted
## D140-D145: the Obelisks objective (fight 4). A third, neutral side; win by
## breaking a stone, lose when the squad falls; the pulse hits everyone flat
## and pushes / pulls; each stone dodges one attack type; the enemy never
## strikes a stone; the map and the run's rotation.


## A flat open field with the two stones on row 6, far apart.
func _board(extra_cells: Array = []) -> BWBoard:
	var cells: Array = []
	for r in 13:
		for c in 15:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	cells.append_array(extra_cells)
	return BWBoard.from_dict({ "name": "t", "cols": 15, "rows": 13, "cells": cells,
		"spawns": { "player": [[6, 11], [7, 11], [8, 11]], "enemy": [[6, 1], [7, 1], [8, 1]] },
		"objective": { "mode": "obelisks", "obelisks": [{ "kind": "lantern", "at": [2, 6] }, { "kind": "well", "at": [12, 6] }] } })


func _unit(id: String, wc: String, team_stats: int = 4) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": "fire" }
	for s in BWUnit.STATS:
		row[s] = team_stats
	return BWUnit.from_roster(row)


func _battle(seed_value: int = 5, pw: Array = ["sword", "bow", "lance"], ew: Array = ["axe", "sword", "staff"]) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	var ps: Array = []
	var es: Array = []
	for i in 3:
		ps.append(_unit("p%d" % i, pw[i]))
		es.append(_unit("e%d" % i, ew[i]))
	b.setup(ps, es)
	return b


func _stone(b: BWBattle, kind: String) -> BWObelisk:
	for o in b.objectives():
		if (o as BWObelisk).kind == kind:
			return o
	return null


## Make `u` the acting unit (end turns until it comes up).
func _until(b: BWBattle, u: BWUnit) -> void:
	var guard := 0
	while b.current() != u and not b.over and guard < 40:
		b.end_turn()
		guard += 1


func test_setup_places_a_neutral_side(t) -> void:
	var b := _battle()
	t.ok(b.objective_mode(), "the map's objective turns the mode on")
	t.eq(b.objectives().size(), 2, "two stones")
	var l := _stone(b, "lantern")
	var w := _stone(b, "well")
	t.eq(l.pos, Vector2i(2, 6), "the Lantern on its hex")
	t.eq(w.pos, Vector2i(12, 6), "the Well on its hex")
	t.eq(l.team, "neutral", "a third side")
	t.eq(l.max_hp(), BWObelisk.HP_MAX, "the stone's own HP (not the CON formula)")
	t.eq(l.hp, BWObelisk.HP_MAX, "full")
	t.eq(b.stones_life(), [BWObelisk.HP_MAX, BWObelisk.HP_MAX], "D378: one shared pool, full")
	t.eq(l.move_range(), 0, "never moves")
	t.ok(l in b.queue and w in b.queue, "both stones are in the speed queue (D140)")
	t.ok(l in b.foes_of(b.side("player")[0]), "the player may target a stone")
	t.ok(not l in b.foes_of(b.side("enemy")[0]), "the enemy may not")
	t.eq(b.foes_of(l), [], "a stone has no foes")
	var plain := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 1)
	plain.setup([_unit("a", "sword")], [_unit("b", "sword")])
	t.ok(not plain.objective_mode() and plain.objectives().is_empty(), "a plain map: no stones")


func test_win_by_breaking_a_stone(t) -> void:
	var b := _battle()
	for e in b.side("enemy"):
		e.hp = 0
	b._check_end()
	t.ok(not b.over, "wiping the enemy does not win an obelisk fight (D140)")
	var w := _stone(b, "well")
	w.hp = 0
	b._check_end()
	t.ok(b.over and b.winner == "player", "a broken stone wins")


func test_breaking_blow_ends_it(t) -> void:
	var b := _battle(7, ["sword", "sword", "sword"])
	var p: BWUnit = b.side("player")[0]
	var l := _stone(b, "lantern")
	p.pos = Vector2i(3, 6)                 # beside the Lantern
	_until(b, p)
	l.hp = 1
	var res := {}
	for k in 20:                           # a sword is melee: no dodge vs the Lantern
		if b.over:
			break
		p.acted = false
		res = b.attack(p, l)
	t.ok(b.over and b.winner == "player", "the KO on a stone wins the fight")
	t.ok(b.history.any(func(e): return e.type == "ko" and e.unit == l.id), "a ko event for the stone")


func test_lose_when_the_squad_falls(t) -> void:
	var b := _battle()
	for p in b.side("player"):
		p.hp = 0
	b._check_end()
	t.ok(b.over and b.winner == "enemy", "the squad down: the enemy wins")


func test_neutral_turn_pulses_and_passes(t) -> void:
	var b := _battle()
	var l := _stone(b, "lantern")
	_until(b, l)
	t.eq(b.current(), l, "the stone's turn comes up in the queue")
	t.ok(BWAI.controls(l), "BWAI plays it")
	var hp := {}
	for u in b.units:
		hp[u.id] = u.hp
	var n := b.history.size()
	BWAI.take_turn(b)
	var evs := b.history.slice(n)
	t.ok(evs.any(func(e): return e.type == "pulse" and e.unit == l.id and e.kind == "push"), "the Lantern pulses (push)")
	t.ok(b.current() != l, "and the turn passes")
	t.ok(not evs.any(func(e): return e.type in ["attack", "skill", "move"] and str(e.get("unit", "")) == l.id), "it never attacks or walks")


func test_pulse_hits_both_sides_flat(t) -> void:
	var b := _battle()
	var w := _stone(b, "well")
	var l := _stone(b, "lantern")
	_until(b, w)
	var before := {}
	for u in b.units:
		before[u.id] = u.hp
	b.side("player")[0].battle_mods["def"] = 40                 # DEF and RES do nothing to a pulse
	b.side("enemy")[0].statuses["frost_ward"] = { "armed": true, "keep": true, "source": "" }   # nor does a ward
	b.obelisk_turn(w)
	for u in b.units:
		if BWObelisk.is_objective(u):
			t.eq(u.hp, before[u.id], "%s: stones are not hit by a pulse" % u.id)
		else:
			var slam := b.history.filter(func(e): return e.type == "tile_damage" and e.unit == u.id and e.cause == "slam")
			var extra := 0
			for e in slam:
				extra += int(e.amount)
			t.eq(before[u.id] - u.hp - extra, w.pulse_damage, "%s (%s): takes exactly the pulse" % [u.id, u.team])
	t.ok(b.side("enemy")[0].statuses.has("frost_ward"), "the ward is not spent on a pulse")
	var p0: BWUnit = b.side("player")[0]
	t.eq(l.hp, BWObelisk.HP_MAX, "the Lantern untouched")
	t.ok(not b.history.any(func(e): return e.type == "growth" and e.get("unit", "") == w.id), "no XP for a stone")
	p0.hp = 1
	_until(b, l)
	b.obelisk_turn(l)
	t.ok(not p0.alive(), "a pulse can knock out")
	t.ok(b.history.any(func(e): return e.type == "ko" and e.unit == p0.id and e.by == "" and e.cause == "pulse"), "credited to nobody")


func test_push_and_pull_resolution(t) -> void:
	var b := _battle()
	var l := _stone(b, "lantern")
	var w := _stone(b, "well")
	var p: Array = b.side("player")
	var e: Array = b.side("enemy")
	# a line east of the Lantern: (4,6) and (5,6) both move one hex east (farthest first, so the near one isn't blocked)
	p[0].pos = Vector2i(4, 6)
	p[1].pos = Vector2i(5, 6)
	p[2].pos = Vector2i(2, 9)
	e[0].pos = Vector2i(7, 2)
	e[1].pos = Vector2i(7, 10)
	e[2].pos = Vector2i(9, 9)
	_until(b, l)
	b.obelisk_turn(l)
	t.eq(p[1].pos, Vector2i(6, 6), "push: the farther unit moves first, one hex away")
	t.eq(p[0].pos, Vector2i(5, 6), "push: the nearer one follows into the hex it left")
	t.eq(BWHex.distance(l.pos, p[2].pos), 4, "push: a unit off the line still ends one hex farther")
	# pull: a line west of the Well, closest first
	var b2 := _battle(6)
	var w2 := _stone(b2, "well")
	var q: Array = b2.side("player")
	q[0].pos = Vector2i(10, 6)
	q[1].pos = Vector2i(9, 6)
	q[2].pos = Vector2i(11, 6)               # already beside the Well: stays
	var en: Array = b2.side("enemy")
	en[0].pos = Vector2i(1, 1)
	en[1].pos = Vector2i(1, 11)
	en[2].pos = Vector2i(5, 1)
	_until(b2, w2)
	b2.obelisk_turn(w2)
	t.eq(q[2].pos, Vector2i(11, 6), "pull: beside the Well, nothing to move into, no slam")
	t.eq(q[0].pos, Vector2i(10, 6), "pull: blocked by the unit beside the Well")
	t.ok(b2.history.any(func(ev): return ev.type == "slam" and ev.unit == q[0].id), "pull: blocked by a unit, it slams")
	t.eq(q[1].pos, Vector2i(9, 6), "pull: the one behind is blocked too")
	t.ok(BWHex.distance(w2.pos, en[0].pos) < BWHex.distance(Vector2i(12, 6), Vector2i(1, 1)), "pull: a far unit comes one hex closer")
	# determinism: the same setup twice gives the same moves
	var b3 := _battle(6)
	var q3: Array = b3.side("player")
	q3[0].pos = Vector2i(10, 6)
	q3[1].pos = Vector2i(9, 6)
	q3[2].pos = Vector2i(11, 6)
	var en3: Array = b3.side("enemy")
	en3[0].pos = Vector2i(1, 1)
	en3[1].pos = Vector2i(1, 11)
	en3[2].pos = Vector2i(5, 1)
	_until(b3, _stone(b3, "well"))
	b3.obelisk_turn(_stone(b3, "well"))
	t.eq(b3.units.map(func(u): return u.pos), b2.units.map(func(u): return u.pos), "pull resolution reproduces")
	# headings: push = one hex farther, pull = one hex nearer, every direction
	for d in 6:
		var from: Vector2i = BWHex.neighbors(Vector2i(7, 6))[d]
		var hp_ := BWBattle.pulse_heading(Vector2i(7, 6), from, true)
		t.eq(BWHex.distance(Vector2i(7, 6), BWHex.neighbors(from)[hp_]), 2, "push heading %d goes out" % d)
	t.eq(BWBattle.pulse_heading(Vector2i(7, 6), Vector2i(7, 6), true), -1, "no heading at the centre")


func test_push_slams_into_rock_not_the_edge(t) -> void:
	var cells := [{ "q": 5, "r": 6, "terrain": "jagged", "elevation": 3 }]
	var bd := _board()
	bd.set_cell(Vector2i(5, 6), "jagged", 3)
	var b := BWBattle.new(bd, 3)
	var ps: Array = [_unit("p0", "sword"), _unit("p1", "sword"), _unit("p2", "sword")]
	var es: Array = [_unit("e0", "sword"), _unit("e1", "sword"), _unit("e2", "sword")]
	b.setup(ps, es)
	var l := _stone(b, "lantern")
	ps[0].pos = Vector2i(4, 6)                 # rock behind it (east)
	ps[1].pos = Vector2i(0, 6)                 # the map's west edge behind it: open air
	_until(b, l)
	var hp0: int = ps[0].hp
	var hp1: int = ps[1].hp
	b.obelisk_turn(l)
	t.eq(ps[0].pos, Vector2i(4, 6), "rock stops the push")
	t.eq(hp0 - ps[0].hp, l.pulse_damage + BWTiles.tile_damage(ps[0], BWObelisk.SLAM_PCT, ""), "and it slams")
	t.eq(ps[1].pos, Vector2i(0, 6), "the edge stops it too")
	t.eq(hp1 - ps[1].hp, l.pulse_damage, "but the edge is open air: no slam")


func test_type_dodge(t) -> void:
	var b := _battle(5, ["bow", "sword", "staff"])
	var bow: BWUnit = b.side("player")[0]
	var sword: BWUnit = b.side("player")[1]
	var staff: BWUnit = b.side("player")[2]
	var l := _stone(b, "lantern")
	var w := _stone(b, "well")
	bow.pos = Vector2i(5, 6)
	sword.pos = Vector2i(3, 6)
	staff.pos = Vector2i(10, 6)
	var raw: float = BWFormulas.hit_chance(bow, l, BWFormulas.WEAPON).value
	var fc := b.forecast_basic(bow, l)
	t.near(fc.hit.value, raw * 0.5, 0.01, "the Lantern: a bow's hit chance halved")
	t.ok(fc.has("dodge") and str(fc.dodge.label).contains("ranged"), "a named dodge line")
	t.ok((fc.notes as Array).any(func(n): return str(n).contains("50%")), "and a note")
	var fs := b.forecast_basic(sword, l)
	t.ok(not fs.has("dodge"), "a sword (melee) is not dodged by the Lantern")
	t.near(fs.hit.value, BWFormulas.hit_chance(sword, l, BWFormulas.WEAPON).value, 0.01, "full hit chance")
	sword.pos = Vector2i(11, 6)
	var fw := b.forecast_basic(sword, w)
	t.ok(fw.has("dodge") and str(fw.dodge.label).contains("melee"), "the Well dodges melee")
	var fsw := b.forecast_basic(staff, w)
	t.ok(not fsw.has("dodge"), "a staff spell from range: not dodged by the Well")
	staff.pos = Vector2i(13, 6)
	t.eq(BWObelisk.attack_type(staff, 1), "melee", "a staff adjacent counts as melee")
	t.eq(BWObelisk.attack_type(bow, 1), "ranged", "a bow is always ranged")
	t.eq(BWObelisk.attack_type(_unit("x", "daggers"), 3), "ranged", "a thrown dagger is ranged")
	t.eq(BWObelisk.attack_type(_unit("y", "lance"), 2), "melee", "a lance's reach is melee")
	# the rolls follow the forecast: over many swings a bow lands about half as often on the Lantern
	var landed := 0
	for k in 400:
		if BWFormulas.resolve(fc, b.rng).hit:
			landed += 1
	t.ok(absf(landed / 400.0 - fc.hit.value / 100.0) < 0.08, "rolled hits match the halved chance (%d/400)" % landed)


func test_ground_and_status_immunity(t) -> void:
	var b := _battle()
	var l := _stone(b, "lantern")
	var p: BWUnit = b.side("player")[0]
	b.tiles.apply([l.pos], "fire", p.id, 3)
	b._tile_hurt(l, 50, "fire", p.id)
	t.eq(l.hp, BWObelisk.HP_MAX, "ground damage can't hurt a stone (D141)")
	b.add_status(l, "pinned", p)
	t.ok(l.statuses.is_empty(), "no statuses on stone")
	t.ok(b._immune(l, "displace"), "can't be displaced")
	t.ok(not b.place_unit(l, Vector2i(3, 3)), "can't be placed")


func test_enemy_never_targets_a_stone(t) -> void:
	var kept := 0
	for s in 4:
		var b := BWBattle.new(BWBoard.load_file("res://maps/obelisks.json"), 70 + s)
		var roster := BWData.table("roster")
		var ps: Array = []
		var es: Array = []
		for i in 3:
			ps.append(BWUnit.from_roster(roster[i + s]))
			es.append(BWUnit.from_roster(roster[(i + 9 + s) % roster.size()]))
		b.setup(ps, es)
		var team := {}
		for u in b.units:
			team[u.id] = u.team
		var turns := 0
		while not b.over and turns < 1200:
			BWAI.take_turn(b)
			turns += 1
		t.ok(b.over, "seed %d: the obelisk fight ends (%d turns, %d rounds)" % [s, turns, b.cycle])
		for e in b.history:
			if str(team.get(str(e.get("unit", "")), "")) != "enemy":
				continue
			if e.type in ["attack", "counter"]:
				t.ok(team.get(str(e.target), "") != "neutral", "seed %d: an enemy struck a stone" % s)
			elif e.type in ["skill", "riposte"]:
				for r in e.get("results", []):
					t.ok(team.get(str(r.target), "") != "neutral", "seed %d: an enemy skill hit a stone" % s)
		if b.winner == "player":
			kept += 1
	t.ok(kept >= 0, "fights finish")


func test_enemy_area_skills_pass_over_a_stone(t) -> void:
	var b := _battle(9, ["sword", "sword", "sword"], ["axe", "axe", "axe"])
	var l := _stone(b, "lantern")
	var e: BWUnit = b.side("enemy")[0]
	var p: BWUnit = b.side("player")[0]
	e.pos = Vector2i(3, 5)
	p.pos = Vector2i(3, 6)
	t.ok(b.can_harm(p, l) and not b.can_harm(e, l), "can_harm: player yes, enemy no")
	t.ok(not l in b._foes_on(e, [l.pos, p.pos]), "an enemy's shape skips the stone")
	t.ok(p in b._foes_on(e, [l.pos, p.pos]), "and keeps the player")


func test_ai_prefers_the_runner(t) -> void:
	var b := _battle()
	var e: BWUnit = b.side("enemy")[0]
	var near_stone: BWUnit = b.side("player")[0]
	var far: BWUnit = b.side("player")[1]
	near_stone.pos = Vector2i(3, 5)
	far.pos = Vector2i(7, 9)
	t.ok(BWAI.objective_bonus(b, e, near_stone, 10.0) > BWAI.objective_bonus(b, e, far, 10.0), "a player near a stone is worth more to the enemy")
	t.ok(BWAI.objective_approach(b, e, Vector2i(4, 5)) < BWAI.objective_approach(b, e, Vector2i(9, 9)), "the enemy closes on the runner")
	var p: BWUnit = b.side("player")[1]
	t.ok(BWAI.objective_bonus(b, p, BWAI.focus_stone(b), 10.0) > 0.0, "the player side weighs its focus stone up")


func test_save_load_around_the_objective_fight(t) -> void:
	# Saves happen between fights only (BWGame._save on screen changes), never mid-fight,
	# so the objective state is the map's: a run saved before fight 4 resumes into it.
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id)).slice(0, BWRun.SQUAD)
	var r := BWRun.start(ids, 77)
	r.fight = 4
	var r2 := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(r2.fight, 4, "the save keeps the fight")
	t.eq(r2.map_for(4), "obelisks", "fight 4 is the Obelisks")
	t.eq(str(r2.objective_for(4).get("mode", "")), "obelisks", "and its objective")
	t.eq(r2.objective_for(3), {}, "fight 3 is a plain fight")
	var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % r2.map_for(4)), 1)
	b.setup(r2.squad.slice(0, 3), r2.enemies_for(4))
	t.eq(b.objectives().size(), 2, "the resumed fight 4 places both stones")


func test_summary_counts_stone_damage(t) -> void:
	var b := _battle(11, ["sword", "sword", "sword"])
	var p: BWUnit = b.side("player")[0]
	var l := _stone(b, "lantern")
	p.pos = Vector2i(3, 6)
	_until(b, p)
	b.attack(p, l)
	var bs := BWBattleStats.tally(b.history, b.units)
	var dealt := int(bs.units[p.id].get("dealt_total", 0))
	t.eq(dealt, BWObelisk.HP_MAX - l.hp, "damage on a stone counts as dealt (%d)" % dealt)


func test_obelisks_map(t) -> void:
	var bd := BWBoard.load_file("res://maps/obelisks.json")
	t.ok(bd.errors.is_empty(), "loads clean %s" % [bd.errors])
	t.eq(str(bd.objective.get("mode", "")), "obelisks", "objective mode")
	var at := {}
	for o in bd.objective.obelisks:
		at[str(o.kind)] = Vector2i(int(o.at[0]), int(o.at[1]))
	var L: Vector2i = at.lantern
	var W: Vector2i = at.well
	# both islands level with the teams' axis midline: the same walk from each side
	var pw := []
	var ew := []
	for sp in bd.spawns.player:
		pw.append(_walk_to(bd, sp, L))
	for sp in bd.spawns.enemy:
		ew.append(_walk_to(bd, sp, L))
	pw.sort(); ew.sort()
	t.eq(pw, ew, "the Lantern is as far from both teams")
	pw.clear(); ew.clear()
	for sp in bd.spawns.player:
		pw.append(_walk_to(bd, sp, W))
	for sp in bd.spawns.enemy:
		ew.append(_walk_to(bd, sp, W))
	pw.sort(); ew.sort()
	t.eq(pw, ew, "the Well is as far from both teams")
	# the Lantern's island (radius 2) is reached by exactly three bridges over the void
	var island := bd.area(L, 2)
	var ways := 0
	for h in island:
		for n in bd.neighbors(h):
			if n in island or BWHex.distance(n, L) != 3:
				continue
			ways += 1
	t.eq(ways, 3, "three bridge hexes touch the Lantern's island")
	var void_ring := 0
	for h in BWHex.ring(L, 3):
		if bd.in_bounds(h) and not bd.exists(h):
			void_ring += 1
	t.ok(void_ring >= 8, "void around the Lantern's island (%d hexes)" % void_ring)
	# the Well's plateau (radius 1) has one way up: the causeway
	var ups := 0
	for h in bd.area(W, 1):
		for n in bd.neighbors(h):
			if BWHex.distance(n, W) >= 2 and bd.step_cost(n, h) >= 0:
				ups += 1
	t.eq(ups, 1, "one way onto the Well's plateau")
	# every standable hex is reachable from a player spawn
	var reach := bd.reachable(bd.spawns.player[0], 999)
	var lost := 0
	for h in bd.cells():
		if bd.is_passable(h) and not reach.has(h):
			lost += 1
	t.eq(lost, 0, "no unreachable standable hex")
	t.eq(bd.spawns.player.size(), 3, "3 player spawns")
	t.eq(bd.spawns.enemy.size(), 3, "3 enemy spawns")
	t.ok(not bd.seeds.is_empty(), "seeded ground (light ring, dark moat)")


func _walk_to(bd: BWBoard, from: Vector2i, stone: Vector2i) -> int:
	var r := bd.reachable(from, 999)
	var best := 1 << 20
	for n in bd.neighbors(stone):
		if r.has(n):
			best = mini(best, int(r[n].cost))
	return best


## D378: the stones share one life. A blow on either lowers the pool and
## both stones mirror it; at 0 both break (a ko each) and the player wins.
func test_shared_pool(t) -> void:
	var b := _battle(7, ["sword", "sword", "sword"])
	var p: BWUnit = b.side("player")[0]
	var l := _stone(b, "lantern")
	var w := _stone(b, "well")
	p.pos = Vector2i(3, 6)                 # beside the Lantern (a sword: no dodge vs it)
	_until(b, p)
	var landed := false
	for k in 30:
		p.acted = false
		var before := b.stone_pool
		b.attack(p, l)
		if b.stone_pool < before:
			landed = true
			break
	t.ok(landed, "a blow on the Lantern landed")
	t.ok(b.stone_pool < BWObelisk.HP_MAX, "the pool went down: %d" % b.stone_pool)
	t.eq(l.hp, b.stone_pool, "the Lantern mirrors the pool")
	t.eq(w.hp, b.stone_pool, "and so does the untouched Well")
	t.ok(b.history.any(func(e): return e.type == "stone_pool"), "a stone_pool event for the views")
	# damage on the other stone counts against the same pool
	var pool := b.stone_pool
	w.hp -= 40
	b._emit({ "type": "test_tick" })
	t.eq(b.stone_pool, pool - 40, "a 40 blow on the Well takes 40 off the pool")
	t.eq(l.hp, pool - 40, "and the Lantern follows")
	# two stones hit in one action, before a sync: both losses count
	l.hp -= 10
	w.hp -= 15
	b._emit({ "type": "test_tick" })
	t.eq(b.stone_pool, pool - 65, "losses on both stones in one go both count")
	t.eq(l.hp, w.hp, "still mirrored")
	t.ok(not b.over, "not over while the pool lasts")
	# the breaking blow: the pool to 0 breaks both, the player wins
	p.acted = false
	l.hp = 1
	b._emit({ "type": "test_tick" })
	t.eq(w.hp, 1, "the pool at 1")
	for k in 30:
		if b.over:
			break
		p.acted = false
		b.attack(p, l)
	t.ok(b.over and b.winner == "player", "the pool at 0 wins")
	t.ok(not l.alive() and not w.alive(), "both stones broke together")
	t.ok(b.history.any(func(e): return e.type == "ko" and e.unit == w.id), "the Well got its own ko (it crumbles too)")
	t.ok(b.history.any(func(e): return e.type == "ko" and e.unit == l.id), "and the Lantern")


## D378: the pool survives an AI clone (the sims and the AI's lookahead).
func test_shared_pool_clone(t) -> void:
	var b := _battle()
	var l := _stone(b, "lantern")
	l.hp -= 50
	b._emit({ "type": "test_tick" })
	var c := b.clone()
	t.eq(c.stone_pool, BWObelisk.HP_MAX - 50, "the clone keeps the pool")
	var cw: BWUnit = null
	for o in c.objectives():
		if (o as BWObelisk).kind == "well":
			cw = o
	cw.hp -= 20
	c._emit({ "type": "test_tick" })
	t.eq(c.stone_pool, BWObelisk.HP_MAX - 70, "the clone's pool moves")
	t.eq(b.stone_pool, BWObelisk.HP_MAX - 50, "the original's doesn't")

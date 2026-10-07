extends RefCounted
## D359–D364, D371–D374: movement by weapon (BWWeaponMove). Move by the
## class drawn at turn start, jump (2; lance 4; the bow's HighGrounder pick
## 4), the axe's and daggers' mud, the high-ground leaps and charges, and the
## Move breakdown text.

const C := Vector2i(5, 5)


## An n x n neutral board at elevation 0; `cells` = {Vector2i: [terrain, elev]}.
func _board(cells: Dictionary = {}, n: int = 13) -> BWBoard:
	var out: Array = []
	for r in n:
		for c in n:
			var h := Vector2i(c, r)
			var d: Array = cells.get(h, ["neutral", 0])
			out.append({ "q": c, "r": r, "terrain": d[0], "elevation": d[1] })
	return BWBoard.from_dict({ "name": "wm", "cols": n, "rows": n, "cells": out,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[12, 12], [12, 11], [12, 10]] } })


func _u(id: String, wc: String, team: String = "player") -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": "fire",
		"con": 5, "str": 5, "dex": 5, "wil": 5, "def": 5, "res": 5, "spd": 5 })
	u.team = team
	return u


func _fight(board: BWBoard, players: Array, foes: Array, ppos: Array, fpos: Array) -> BWBattle:
	var b := BWBattle.new(board, 7)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1
		u.statuses = {}
		u.fx = {}
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


## A heading from `from` whose ray of `n` hexes stays on the board.
func _dir(b: BWBattle, from: Vector2i, n: int) -> Vector2i:
	for nb in BWHex.neighbors(from):
		if b.board.ray(from, nb, n).size() == n:
			return nb
	return from


# ---------------------------------------------------------------- D359 move

func test_move_by_class(t) -> void:
	var want := { "bow": 4, "pistols": 4, "staff": 4, "sword": 5, "daggers": 5, "fists": 5, "axe": 4, "lance": 4 }
	for wc in want:
		t.eq(_u("u", wc).move_range(), want[wc], "%s: move %d" % [wc, want[wc]])
	var s := _u("s", "sword")
	s.statuses["swift"] = { "armed": true }
	t.eq(s.move_range(), 6, "modifiers still add on top (Swift +1)")


func test_turn_start_lock_vs_swap(t) -> void:
	var run := BWRun.new()
	var u := _u("me", "sword")
	u.equipment["main_hand"] = run.make_item("sword", "E", "")
	u.equipment["second"] = run.make_item("shortbow", "E", "")
	u.sync_weapon()
	t.eq(u.move_range(), 5, "sheet: the drawn sword's 5")
	var b := _fight(_board(), [u], [_u("f", "axe", "enemy")], [C], [Vector2i(12, 12)])
	_turn(b, u)
	t.ok(b.swap_weapon(u) and u.weapon_class == "bow", "swapped to the bow mid-turn")
	t.eq(u.move_range(), 5, "this turn keeps the sword's move 5")
	t.ok(BWFormulas.move_text(u).begins_with("Move 5 (Sword)"), "and the breakdown says why: %s" % BWFormulas.move_text(u))
	u.known_skills.append(BWWeaponMove.HIGH_GROUNDER)
	t.eq(BWWeaponMove.jump(u), 2, "and the sword's jump: HighGrounder waits for a bow turn (the lock covers the jump too)")
	_turn(b, u)
	t.eq(u.move_range(), 4, "next turn: the bow's move 4")
	t.eq(BWWeaponMove.jump(u), 4, "and the HighGrounder jump 4")
	u.fx.erase("move_class")
	t.ok(b.swap_weapon(u), "swap back")
	t.eq(u.move_range(), 5, "between turns the sheet follows the drawn weapon")


# ---------------------------------------------------------------- D360 / D371 / D372 jump

## A bow unit that owns the HighGrounder pick.
func _hg(id: String = "hg") -> BWUnit:
	var u := _u(id, "bow")
	u.known_skills.append(BWWeaponMove.HIGH_GROUNDER)
	return u


func test_jump_two_vs_four(t) -> void:
	var nbs := BWHex.neighbors(C)
	var up1: Vector2i = nbs[3]
	var up2: Vector2i = nbs[0]
	var up3: Vector2i = nbs[1]
	var up4: Vector2i = nbs[2]
	var bd := _board({ up1: ["neutral", 1], up2: ["neutral", 2], up3: ["neutral", 3], up4: ["neutral", 4] })
	t.eq(BWBoard.DEFAULT_JUMP, 2, "D371: the base jump is 2")
	t.eq(bd.step_cost(C, up2, { "jump": 2 }), 3, "jump 2: a 2-level step for 1 + 2")
	t.eq(bd.step_cost(C, up3, { "jump": 2 }), -1, "jump 2: a 3-level step is a wall")
	t.eq(bd.step_cost(C, up4, { "jump": 4 }), 5, "jump 4: 1 + 4 levels")
	t.eq(bd.step_cost(C, up3), -1, "forced moves keep D20's cap of 2")
	t.eq(bd.step_cost(up4, C, { "jump": 2 }), 1, "dropping is free and unlimited")
	var cases := { "sword": false, "axe": false, "bow": false, "staff": false, "lance": true, "hg": true }
	for k in cases:
		var u := _hg() if k == "hg" else _u("u", k)
		var b := _fight(bd, [u], [_u("f", "axe", "enemy")], [C], [Vector2i(12, 12)])
		_turn(b, u)
		u.statuses["swift"] = { "armed": true }       # +1 move: the 4-level step costs 5
		var r := b.reachable(u)
		t.eq(int(r[up2].cost), 3, "%s climbs 2 levels for 3" % k)
		var four: bool = cases[k]
		t.eq(r.has(up3) and int(r[up3].cost) == 4, four, "%s %s the 3-level step" % [k, "climbs" if four else "can't take"])
		t.eq(r.has(up4) and int(r[up4].cost) == 5, four, "%s %s the 4-level step" % [k, "climbs" if four else "can't take"])


## D372: HighGrounder is the bow's pickable passive, not a trait.
func test_high_grounder_pick(t) -> void:
	t.ok(not BWWeaponMove.HIGH_GROUNDER in BWWeaponMove.traits("bow"), "no longer an innate bow trait")
	t.eq(BWWeaponMove.passives_of("bow"), [BWWeaponMove.HIGH_GROUNDER], "the bow's pickable passive")
	t.eq(BWWeaponMove.passives_of("pistols"), [], "pistols have none")
	var bow := _u("b", "bow")
	t.eq(BWWeaponMove.jump(bow), 2, "a bow without the pick: jump 2")
	t.eq(BWWeaponMove.jump_source(bow), "", "the plain 2 has no source")
	t.eq(BWWeaponMove.card_lines(bow), [], "and no card line")
	# offered in the bow's expertise pick, passive first
	bow.expertise["bow"] = 10                         # E -> D: one skill pick
	t.eq(BWPicks.skill_choices(bow, "bow")[0], "passive:" + BWWeaponMove.HIGH_GROUNDER, "a bow pick can take it")
	var req := { "kind": "skill", "weapon": "bow" }
	var opt: Array = BWPicks.all_options(bow, req).filter(func(o): return o.kind == "passive")
	t.eq(opt.size(), 1, "one passive card in the pool")
	t.eq(str(opt[0].name), "HighGrounder", "named")
	t.ok(str(opt[0].text).contains("no skill slot"), "says it takes no slot: %s" % opt[0].text)
	var seen := false
	for sd in 64:                                     # a seed whose two cards include it
		bow.pick_seed = sd
		if ("passive:" + BWWeaponMove.HIGH_GROUNDER) in BWPicks.offered(bow, req):
			seen = true
			break
	t.ok(seen, "some seed's two cards offer it")
	var slots: Array = bow.loadout("bow").duplicate()
	t.ok(not BWPicks.apply(bow, req, "passive:" + BWWeaponMove.HIGH_GROUNDER).is_empty(), "taken")
	t.ok(BWWeaponMove.owns(bow, BWWeaponMove.HIGH_GROUNDER), "owned (known_skills)")
	t.eq(bow.loadout("bow"), slots, "no loadout slot taken")
	t.ok(not BWWeaponMove.HIGH_GROUNDER in bow.known("bow"), "never in the skill lists")
	t.eq(int(bow.skill_picks.get("bow", 0)), 1, "the pick is spent")
	t.ok(not ("passive:" + BWWeaponMove.HIGH_GROUNDER) in BWPicks.skill_choices(bow, "bow"), "not offered again")
	t.eq(BWWeaponMove.jump(bow), 4, "HighGrounder: jump 4 (double)")
	t.eq(BWWeaponMove.jump_source(bow), "HighGrounder", "named by the pick")
	t.eq(BWWeaponMove.card_lines(bow), [["HighGrounder", "jump 4 with a bow drawn"]], "on the unit card when owned")
	t.ok(BWPicks.describe(bow, { "kind": "skill", "weapon": "bow", "id": "passive:high_grounder" }).contains("HighGrounder"), "the feed line")
	t.ok(BWWeaponMove.HIGH_GROUNDER in Array(bow.to_dict().get("known_skills", [])), "saved with the known skills")
	# only while a bow is the moving class
	var run := BWRun.new()
	var u := _hg("sw")
	u.equipment["main_hand"] = run.make_item("sword", "E", "")
	u.sync_weapon()
	t.eq(BWWeaponMove.jump(u), 2, "owned but a sword drawn: jump 2")
	t.eq(str(BWWeaponMove.card_lines(u)[0][0]), "HighGrounder", "still listed on the card")
	t.eq(BWWeaponMove.jump_source(_u("l", "lance")), "Lance", "the lance's own 4 is named by the class")
	t.ok(BWWeaponMove.class_line("bow").contains("HighGrounder (pick): jump 4"), "the bow's item card: %s" % BWWeaponMove.class_line("bow"))
	t.ok(BWWeaponMove.class_line("lance").contains("Jump 4"), "the lance's card: %s" % BWWeaponMove.class_line("lance"))
	t.ok(not BWWeaponMove.class_line("sword").contains("Jump"), "the plain 2 isn't on item cards: %s" % BWWeaponMove.class_line("sword"))


## D372: an enemy bow resolves its stage picks the AI's way and takes
## HighGrounder whenever its two cards offer it.
func test_enemy_bow_may_roll_high_grounder(t) -> void:
	var took := 0
	var offered := 0
	for sd in 40:
		var e := _u("e%d" % sd, "bow", "enemy")
		e.pick_seed = sd
		e.expertise["bow"] = 10
		var has_it: bool = ("passive:" + BWWeaponMove.HIGH_GROUNDER) in BWPicks.offered(e, { "kind": "skill", "weapon": "bow" })
		BWPicks.auto_resolve(e)
		if has_it:
			offered += 1
		if BWWeaponMove.owns(e, BWWeaponMove.HIGH_GROUNDER):
			took += 1
	t.ok(offered > 0 and offered < 40, "offered on some seeds, not all (%d of 40)" % offered)
	t.eq(took, offered, "taken exactly when offered")


# ---------------------------------------------------------------- D361 mud

func test_axe_and_daggers_on_mud(t) -> void:
	var m := BWHex.neighbors(C)[0]
	var bd := _board({ m: ["muddy", 0] })
	for wc in ["axe", "daggers", "sword", "lance"]:
		var u := _u("u", wc)
		var b := _fight(bd, [u], [_u("f", "axe", "enemy")], [C], [Vector2i(12, 12)])
		_turn(b, u)
		var rough: bool = wc in ["axe", "daggers"]
		t.eq(int(b.reachable(u)[m].cost), 1 if rough else 2, "%s: mud costs %d" % [wc, 1 if rough else 2])
		b.tiles.apply([m], "water", "x", 3)
		t.eq(int(b.reachable(u)[m].cost), (1 if rough else 2) + 2, "%s: water 3's +2 still applies" % wc)


# ---------------------------------------------------------------- D362 high ground

func test_daggerleap_high_ground(t) -> void:
	var u := _u("d", "daggers")
	var b := _fight(_board({ C: ["neutral", 2] }), [u], [_u("f", "axe", "enemy")], [C], [Vector2i(12, 12)])
	_turn(b, u)
	var far := b.board.ray(C, _dir(b, C, 4), 4)[3]
	t.ok(far in b.skill_targets(u, "daggerleap", "fire"), "from 2 up: a hex 4 away below is in reach")
	var pv := b.skill_preview(u, "daggerleap", "fire", far)
	t.eq((pv.hexes as Array).size(), 18, "the landing ring is radius 2 (18 hexes)")
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("High ground")), "named in the notes")
	b.board.set_cell(C, "neutral", 0)
	t.ok(not far in b.skill_targets(u, "daggerleap", "fire"), "on the level: 3 is the reach")
	var near := b.board.ray(C, _dir(b, C, 4), 4)[2]
	t.eq((b.skill_preview(u, "daggerleap", "fire", near).hexes as Array).size(), 6, "and the ring is 1")


func test_charge_high_ground(t) -> void:
	var u := _u("a", "axe")
	var foe := _u("f", "sword", "enemy")
	var b := _fight(_board({ C: ["neutral", 1] }), [u], [foe], [C], [C])
	var nb := _dir(b, C, 7)
	var line := b.board.ray(C, nb, 7)
	foe.pos = line[1]
	_turn(b, u)
	var pv := b.skill_preview(u, "charge", "fire", nb)
	t.eq(pv.dest, line[3], "downhill: reach 4 (ends on the 4th hex)")
	t.eq(pv.shove.to, line[5], "and the foe is shoved 2 hexes past")
	b.board.set_cell(C, "neutral", 0)
	var pv2 := b.skill_preview(u, "charge", "fire", nb)
	t.eq(pv2.dest, line[2], "level: reach 3")
	t.eq(pv2.shove.to, line[3], "and a 1-hex shove")


func test_vault_and_dive_high_ground(t) -> void:
	var u := _u("l", "lance")
	var foe := _u("f", "sword", "enemy")
	var b := _fight(_board({ C: ["neutral", 1] }), [u], [foe], [C], [C])
	var nb := _dir(b, C, 6)
	var line := b.board.ray(C, nb, 6)
	foe.pos = line[3]
	_turn(b, u)
	t.ok(foe.pos in b.skill_targets(u, "vault", "fire"), "Vault from above: a foe 4 away")
	t.ok(line[4] in b.skill_targets(u, "dragoon_dive", "fire"), "Dive from above: 5 away")
	t.eq((b.skill_preview(u, "dragoon_dive", "fire", line[4]).hexes as Array).size(), 18, "the Dive's ring is radius 2")
	b.board.set_cell(C, "neutral", 0)
	t.ok(not foe.pos in b.skill_targets(u, "vault", "fire"), "level: 3 is the Vault's reach")
	t.ok(not line[4] in b.skill_targets(u, "dragoon_dive", "fire"), "and 4 the Dive's")


# ---------------------------------------------------------------- breakdown

func test_breakdown_text(t) -> void:
	var d := _u("d", "daggers")
	t.ok(BWFormulas.move_text(d).begins_with("Move 5 (Daggers)"), BWFormulas.move_text(d))
	t.ok(BWFormulas.move_text(d).contains("no mud penalty"), "Rough-Footed named")
	d.statuses["swift"] = { "armed": true }
	t.ok(BWFormulas.move_text(d).contains("Move 5 (Daggers) +1 Swift"), "a status by name: %s" % BWFormulas.move_text(d))
	t.ok(BWFormulas.move_text(_u("s", "sword")).ends_with(" · Climb 2"), "the plain jump: %s" % BWFormulas.move_text(_u("s", "sword")))
	t.ok(BWFormulas.move_text(_u("l", "lance")).contains("Climb 4 (Lance)"), BWFormulas.move_text(_u("l", "lance")))
	t.ok(BWFormulas.move_text(_u("b", "bow")).ends_with(" · Climb 2"), "a bow without the pick: %s" % BWFormulas.move_text(_u("b", "bow")))
	t.ok(BWFormulas.move_text(_hg()).contains("Climb 4 (HighGrounder)"), BWFormulas.move_text(_hg()))
	var mv := BWFormulas.move(_u("s", "sword"))
	t.eq(int(mv.value), 5, "the hover's value")
	t.eq(str(mv.formula), "Sword move", "the hover's formula names the class")
	t.eq(BWWeaponMove.card_text(_u("l", "lance")), "Move 4", "the unit card's stat line")
	t.eq(BWWeaponMove.card_lines(_u("l", "lance")), [["Jump 4", "climbs 4 levels a step"]], "the lance's jump line")
	t.eq(str(BWWeaponMove.card_lines(_hg())[0][0]), "HighGrounder", "the pick's line")
	t.eq(BWWeaponMove.card_lines(_u("s", "sword")), [], "no line at the plain jump 2")


## The coordinator's check (horde2_group_move.png showed a dagger at Move 3):
## a plain daggers unit shows and gets 5; a Leaden piece (cursed, -2) is the
## 3, now on the sheet too and named in the breakdown and the card's hover.
func test_daggers_plain_is_five_and_leaden_is_named(t) -> void:
	var run := BWRun.new()
	var d := _u("d", "daggers")
	d.equipment["main_hand"] = run.make_item("dagger", "E", "")
	d.sync_weapon()
	d.refresh_effects()
	t.eq(d.weapon_class, "daggers", "a dagger drawn")
	t.eq(d.move_range(), 5, "no modifiers: move 5 on the sheet")
	t.eq(BWWeaponMove.card_text(d), "Move 5", "and on the card")
	var b := _fight(_board(), [d], [_u("f", "axe", "enemy")], [C], [Vector2i(12, 12)])
	_turn(b, d)
	t.eq(d.move_range(), 5, "and in battle")
	t.eq(int(b.reachable(d).values().map(func(x): return int(x.cost)).max()), 5, "and it walks 5")
	var legs: Array = BWData.table("equipment").filter(func(x): return str(x.slot) == "legs" and "chaps" in str(x.id))
	var p := _u("p", "daggers")
	p.equipment["main_hand"] = run.make_item("dagger", "E", "")
	if not legs.is_empty():
		p.equipment["legs"] = run.make_item(str(legs[0].id), "B", "leaden")
	p.sync_weapon()
	p.refresh_effects()
	t.eq(p.move_range(), 3, "Leaden (cursed, -2): 3 on the sheet as in battle")
	t.ok(BWFormulas.move_text(p).contains("-2 ") and BWFormulas.move_text(p).contains("cursed"), "named: %s" % BWFormulas.move_text(p))
	t.ok(BWWeaponMove.card_bb(p).contains("cursed"), "the card's hover carries it")

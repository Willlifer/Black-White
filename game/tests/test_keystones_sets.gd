extends RefCounted
## D277-D284: the keystone framework (BWKeystones, data/keystones.csv), enemy
## keystones by stage, and the element sets (BWSets, data/sets.csv): counting
## (head, chest, legs + the DRAWN weapon's imbue), the 2-piece records and the
## 3-piece hooks. The ladder and seeded offers are in test_picks.gd.

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


## An armour piece of `ench`'s colour in `slot`.
func _piece(u: BWUnit, slot: String, ench: String) -> void:
	u.equipment[slot] = { "uid": "%s_%s" % [u.id, slot], "base": "", "slot": slot, "tier": "E",
		"stats": {}, "enchant": ench, "worn": {} }


func _weapon(imbue: String, uid: String) -> Dictionary:
	return { "uid": uid, "base": "sword", "slot": "main_hand", "weight": "sword", "tier": "C",
		"stats": {}, "enchant": "keen", "imbue": imbue, "imbue_enchant": "", "worn": {} }


func _fight(players: Array, foes: Array, ppos: Array, fpos: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.statuses = {}
		u.fx = {}
	b.history.clear()
	return b


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


# ------------------------------------------------------------------ the contract

## D443: Keystones v3: 14 keystones, 2 per element, each with a title.
func test_keystone_table(t) -> void:
	var ids := BWKeystones.all_ids()
	t.eq(ids.size(), 14, "14 keystones")
	for el in BWFormulas.ELEMENTS:
		t.eq(BWKeystones.of_element(el).size(), 2, "two %s keystones" % el)
		for id in BWKeystones.of_element(el):
			var r := BWKeystones.row(str(id))
			t.ok(not r.is_empty(), "%s has a row" % id)
			t.eq(str(r.get("element", "")), el, "%s is %s" % [id, el])
			t.ok(str(r.get("kind", "")) in ["passive", "action"], "%s: a known kind" % id)
			t.ok(str(r.get("text", "")).length() > 40, "%s: real text" % id)
			t.ok(BWKeystones.title_of(str(id)) != "", "%s: a title" % id)
	t.eq(BWKeystones.all_ids().filter(func(id): return BWKeystones.is_action(str(id))), ["abyssal", "sunburst"], "the two action keystones")
	var u := _u("k", "sword", "wind")
	t.ok(BWKeystones.grant(u, "la_nina"), "grant")
	t.ok(not BWKeystones.grant(u, "la_nina"), "no duplicate")
	t.ok(not BWKeystones.grant(u, "nope"), "unknown refused")
	t.ok(BWKeystones.grant(u, "abyssal"), "a second, another element")
	t.eq(BWKeystones.actions(u), ["abyssal"], "actions() lists the action keystones")
	t.eq(BWKeystones.skills(u), ["pitch_black"], "skills() its menu rows")
	t.eq(BWKeystones.of(u), ["la_nina", "abyssal"], "of()")
	t.eq(BWKeystones.line(u), "Keystones: La Niña, Abyssal", "the card line")


# ------------------------------------------------------------------ enemies by stage (D279)

func test_enemy_keystones_by_stage(t) -> void:
	var run := BWRun.start(["aureli", "della"], 3)
	for n in range(1, 12):
		var es: Array = run.enemies_for(n)
		if n in BWRun.SIX_FIGHTS:
			es = es.filter(func(u): return u.encounter == "")   # D331: a mode's grunts carry none; its roster enemies do
		var with: Array = es.filter(func(u): return not u.keystones.is_empty())
		if n <= 3:
			t.eq(with.size(), 0, "fight %d: no keystones" % n)
		elif n <= 6:
			t.eq(with.size(), 1, "fight %d: one enemy per squad" % n)
		elif n == BWRun.TWINS_FIGHT:
			var ks: Array = es.map(func(u): return u.keystones)
			t.eq(ks, [["judicator"], ["hopekiller"]], "the Twins (D454): Judicator (Noon) and Hopekiller (Dusk)")
		elif n < BWRun.BOSS_FIGHT:
			t.eq(with.size(), es.size(), "fight %d: every enemy has one" % n)
		else:
			t.eq(with.size(), 1, "the Giant: one")
		for u in with:
			t.eq(u.keystones.size(), 1, "%s: one keystone" % u.id)
			if u.encounter != "twin":
				t.eq(BWKeystones.element_of(str(u.keystones[0])), str(u.element), "%s: of its own element" % u.id)
		for u in es:
			t.ok(BWPicks.pending(u).filter(func(q): return q.kind == "keystone").is_empty(), "%s owes no keystone" % u.id)
	var again := BWRun.start(["aureli", "della"], 3)
	t.eq(again.enemies_for(9).map(func(u): return u.keystones), run.enemies_for(9).map(func(u): return u.keystones), "seeded: the same picks")


func test_enemy_takes_the_first_card(t) -> void:
	var u := _u("e", "sword", "fire")
	u.pick_seed = 12345
	var first := str(BWPicks.options(u, { "kind": "keystone", "element": "fire" })[0].id)
	var made := BWKeystones.arm_enemies([u], 8)
	t.eq(made, [first], "the AI takes the first offered (D174)")
	t.eq(u.keystone_cap, 1, "capped at what it was given")


# ------------------------------------------------------------------ set counting (D282)

func test_set_counting(t) -> void:
	var u := _u("s", "sword", "fire")
	_piece(u, "head", "kindled")
	_piece(u, "chest", "explosive")
	t.eq(BWSets.pieces(u, "fire"), 2, "two fire armour pieces")
	t.eq(BWSets.tier(u, "fire"), 2, "a 2-piece")
	u.equipment["main_hand"] = _weapon("fire", "w1")
	t.eq(BWSets.pieces(u, "fire"), 3, "the drawn weapon's imbue counts toward its element")
	t.eq(BWSets.tier(u, "fire"), 3, "a 3-piece")
	u.equipment["legs"] = { "uid": "l", "base": "", "slot": "legs", "tier": "E", "stats": {}, "enchant": "kindled", "worn": {} }
	t.eq(BWSets.tier(u, "fire"), 3, "a 4th adds nothing")
	u.equipment.erase("legs")
	var w: Dictionary = u.equipment["main_hand"]
	u.equipment[BWUnit.SECOND] = w
	u.equipment["main_hand"] = _weapon("water", "w2")
	t.eq(BWSets.pieces(u, "fire"), 2, "the carried weapon counts for nothing (D180)")
	t.eq(BWSets.pieces(u, "water"), 1, "the drawn one counts toward its own imbue")
	u.swap_weapons()
	t.eq(BWSets.pieces(u, "fire"), 3, "a swap updates the count at once")
	t.ok(u.effects.any(func(e): return e.key == "set_bonus" and e.params.kind == "fire"), "and the 3-piece record")
	var v := _u("v", "sword", "water")
	_piece(v, "head", "kindled")
	_piece(v, "chest", "kindled")
	t.eq(BWSets.tier(v, "fire"), 0, "a set sleeps until its element is learned")
	_piece(v, "legs", "warded")
	v.equipment["legs"]["ward"] = "water"
	v.equipment["head"]["enchant"] = "brimming"
	t.eq(BWSets.pieces(v, "water"), 2, "a Warded piece counts toward its ward")


func test_set_lines(t) -> void:
	var u := _u("s", "sword", "fire")
	_piece(u, "head", "kindled")
	_piece(u, "chest", "kindled")
	t.eq(BWSets.card_line(u.equipment.head, u), "Set: Fire 2/3 · next: Flashpoint", "the item card's dim line")
	t.eq(BWSets.summary(u), "Sets: Fire 2/3", "the gear panel's line")
	var loose := { "uid": "x", "base": "", "slot": "legs", "tier": "E", "stats": {}, "enchant": "explosive" }
	t.eq(BWSets.card_line(loose, u, true), "Set: Fire → 3/3 · Flashpoint", "a loose piece counts as if equipped")
	t.eq(BWSets.card_line({ "uid": "y", "slot": "legs", "enchant": "keen" }), "", "an uncoloured piece: no line")


func test_two_piece_records(t) -> void:
	var u := _u("s", "sword", "dark", { "spd": 20 })
	_piece(u, "head", "abyssal")
	_piece(u, "chest", "abyssal")
	u.refresh_effects()
	var b := _fight([u], [_u("f", "axe", "water", { "con": 300 })], [C], [Vector2i(8, 8)])
	t.eq(u.stat("spd"), 20, "off dark: nothing")
	b.tiles.apply([C], "dark", "x", 2)
	t.eq(u.stat("spd"), 24, "Dark set (2): +10% SPD per dark level")
	t.ok(BWSets.no_drain(u), "and no dark drain")
	var w := _u("w", "sword", "wind")
	_piece(w, "head", "gusting")
	_piece(w, "chest", "gusting")
	w.refresh_effects()
	t.eq(w.move_range(), 6, "Wind set (2): +1 move (sword 5)")


# ------------------------------------------------------------------ 3-pieces

func test_flashpoint(t) -> void:
	var u := _u("s", "sword", "fire", { "con": 30 })
	for s in ["head", "chest", "legs"]:
		_piece(u, s, "kindled")
	u.refresh_effects()
	var b := _fight([u], [_u("f", "axe", "water")], [C], [Vector2i(8, 8)])
	u.hp = int(u.max_hp() * 0.6)
	b._tile_hurt(u, int(u.max_hp() * 0.2), "slam", "")
	t.eq(b.tiles.intensity(C, "fire"), 3, "under 50%: fire 3 under it")
	t.ok(BWHex.neighbors(C).all(func(h): return b.tiles.intensity(h, "fire") == 3), "and on the ring")
	t.eq(_ev(b, "set_trigger").size(), 1, "the trigger floats once")
	t.ok(u.hp > int(u.max_hp() * 0.4), "healed 20%")
	b._tile_hurt(u, int(u.max_hp() * 0.05), "slam", "")
	t.eq(_ev(b, "set_trigger").size(), 1, "once a battle")


func test_dawnward(t) -> void:
	var u := _u("s", "staff", "light")
	for s in ["head", "chest", "legs"]:
		_piece(u, s, "dawning")
	u.refresh_effects()
	var mate := _u("m", "sword", "fire")
	var foe := _u("f", "axe", "water", { "str": 200, "dex": 100 })
	var b := _fight([u, mate], [foe], [C, Vector2i(4, 6)], [Vector2i(4, 7)])
	mate.hp = 1
	var res := { "hit": true, "damage": 50 }
	BWEnchant.land(b, foe, mate, res)
	t.eq(int(res.damage), 0, "a KO blow on an ally within 3 holds it at 1 HP")
	t.eq(b.tiles.intensity(mate.pos, "light"), 3, "its hex goes to light 3")
	var res2 := { "hit": true, "damage": 50 }
	BWEnchant.land(b, foe, mate, res2)
	t.eq(int(res2.damage), 50, "once a battle")


func test_breakwater(t) -> void:
	var u := _u("s", "sword", "water")
	for s in ["head", "chest", "legs"]:
		_piece(u, s, "brimming")
	u.refresh_effects()
	var foe := _u("f", "axe", "fire", { "con": 300 })
	var at := BWHex.neighbors(C)[0]
	var b := _fight([u], [foe], [C], [at])
	BWSets.after_blow(b, foe, u, { "hit": true, "damage": 5 })
	t.eq(BWHex.distance(foe.pos, C), 3, "the attacker is swept 2 away")
	t.ok(foe.statuses.has("drenched"), "and Drenched")
	var p := foe.pos
	BWSets.after_blow(b, foe, u, { "hit": true, "damage": 5 })
	t.eq(foe.pos, p, "once a battle")


func test_slipstream_sure_hit(t) -> void:
	var u := _u("s", "sword", "wind")
	for s in ["head", "chest", "legs"]:
		_piece(u, s, "gusting")
	u.refresh_effects()
	var m := BWSets.mods(u, _u("f", "axe", "fire"), { "moved": 4 })
	t.ok(m.any(func(x): return str(x.stage) == "hit" and float(x.value) >= 1000.0), "moved 4: can't be avoided")
	t.ok(not BWSets.mods(u, _u("g", "axe", "fire"), { "moved": 3 }).any(func(x): return str(x.stage) == "hit"), "moved 3: no")

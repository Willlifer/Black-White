extends RefCounted
## Weapon and staff skills (design/ELEMENTS.md §7, §9; BWSkills, BWBattle.use_skill).

const C := Vector2i(4, 4)          # the actor's hex, mid-board
const E := Vector2i(5, 4)          # C's east neighbour (cube direction 0)
const T := Vector2i(4, 2)          # a hex two rows up from C


func _board(n: int = 9) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[8, 0], [8, 1], [8, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


## `me` at C with the turn; foes placed at `at`.
func _duel(me: BWUnit, foes: Array = [], at: Array = [], seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _foe(id: String = "f", extra: Dictionary = {}) -> BWUnit:
	return _u(id, "axe", "water", extra)


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for h in a:
		if not h in b:
			return false
	return true


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


# ------------------------------------------------------------------ the table

func test_kits(t) -> void:
	t.eq(BWSkills.kit("staff").map(func(s): return s.key), ["surge", "saturate", "ley_line", "siphon"],
		"staff kit (blank CSV cell falls back to the table)")
	t.eq(BWSkills.kit("pistols").map(func(s): return s.key), ["reload", "quick_shot"], "pistols take V8's flintlock kit")
	t.ok("striketwice_second" in BWSkills.kit("sword").map(func(s): return s.key), "follow-up halves ride along")
	t.eq(BWSkills.kit("fists").map(func(s): return s.key), ["flurry", "uppercut", "palm_burst"], "fists kit (D76)")
	for wc in ["sword", "axe", "lance", "daggers", "bow", "pistols", "staff", "fists"]:
		t.ok(not BWSkills.kit(wc).is_empty(), "%s has skills" % wc)
		for s in BWSkills.kit(wc):
			for k in ["key", "name", "weapon", "desc", "targeting", "needs_element", "range", "cd", "power"]:
				t.ok(s.has(k), "%s has %s" % [s.key, k])
	t.eq(BWSkills.get_skill("cleave").power, 13, "V8 CLEAVE_DMG")
	t.eq(BWSkills.cd_key("cleave", "fire"), "cleave_fire", "cooldown key per skill+element")


# ------------------------------------------------------------------ shapes

func _shape(wc: String, key: String, el: String, target: Vector2i, foes_at: Array = []) -> Dictionary:
	var me := _u("me", wc, el)
	var foes: Array = []
	for i in foes_at.size():
		foes.append(_foe("f%d" % i))
	var b := _duel(me, foes, foes_at)
	return { "b": b, "me": me, "pv": b.skill_preview(me, key, el, target) }


func test_shapes_flat(t) -> void:
	var s := _shape("bow", "arcing_shot", "fire", T)
	t.ok(_same(s.pv.hexes, Array(BWHex.area(T, 1))), "arcing shot: target + 6")

	s = _shape("bow", "energized_shot", "fire", Vector2i(7, 4), [Vector2i(7, 4), Vector2i(6, 4)])
	t.eq(s.pv.hexes, [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)], "energized: archer-exclusive trail")
	t.eq(s.pv.units, ["f0"], "energized: target only")

	s = _shape("lance", "tridentpierce", "fire", E)
	var want := Array(BWHex.fringe([E, Vector2i(6, 4)], 1)).filter(func(h): return h != C)
	t.ok(_same(s.pv.hexes, want) and s.pv.hexes.size() == 9, "tridentpierce: 2 forward + adjacent, minus wielder")

	s = _shape("axe", "cleave", "fire", E)
	t.eq(s.pv.hexes.size(), 3, "cleave: 3-hex arc")
	t.ok(s.pv.hexes.all(func(h): return BWHex.distance(C, h) == 1) and E in s.pv.hexes, "cleave arc is beside the user, centred on the heading")
	var arc: Array = s.pv.hexes
	s.b.tiles.apply([arc[0]], "fire", "x")
	var pv2: Dictionary = s.b.skill_preview(s.me, "cleave", "fire", E)
	var ext := Array(BWHex.fringe(arc, 1)).filter(func(h): return h != C)
	t.ok(_same(pv2.hexes, ext), "cleave extends when an arc hex carries the element")
	var pv3: Dictionary = s.b.skill_preview(s.me, "cleave", "water", E)
	t.eq(pv3, {}, "cleave in an unlearned element is not a legal click")

	s = _shape("daggers", "daggerleap", "fire", Vector2i(4, 1))
	t.eq(s.pv.dest, Vector2i(4, 1), "daggerleap lands on the click")
	t.ok(_same(s.pv.hexes, Array(BWHex.ring(Vector2i(4, 1), 1))), "daggerleap: ring around landing")

	s = _shape("daggers", "dualthrow", "fire", Vector2i(7, 4), [Vector2i(7, 4)])
	t.eq(s.pv.hexes, [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)], "dualthrow: trail to the target")

	s = _shape("sword", "striketwice", "fire", E, [E])
	t.eq(s.pv.hexes, [E], "striketwice first cut: the target hex")

	s = _shape("sword", "riposte", "fire", C)
	t.ok(_same(s.pv.hexes, Array(BWHex.ring(C, 1))), "riposte: the duelist's ring")

	s = _shape("axe", "charge", "fire", E)
	t.eq(s.pv.hexes, [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)], "charge: 3 hexes charged through")
	t.eq(s.pv.dest, Vector2i(7, 4), "charge ends 3 out")

	# D105: Vault is aimed at a foe 2-3 away; the shape is the takeoff hex
	s = _shape("lance", "vault", "fire", Vector2i(7, 4), [Vector2i(7, 4)])
	t.eq(s.pv.hexes, [C], "vault: the takeoff hex takes the element")
	t.eq(s.pv.dest, Vector2i(6, 4), "vault: lands beside the foe")

	s = _shape("staff", "surge", "fire", T, [T])
	t.ok(_same(s.pv.hexes, Array(BWHex.area(T, 1))), "surge: hex + 6")
	t.eq(s.pv.forecasts["f0"].kind, BWFormulas.SPELL, "staff skills use the spell formula")

	s = _shape("staff", "saturate", "fire", T)
	t.eq(s.pv.hexes, [T], "saturate: one hex")
	t.eq(s.pv.steps, 2, "saturate pours 2 steps")

	s = _shape("staff", "ley_line", "fire", E)
	t.eq(s.pv.hexes, [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4)], "ley line: 4 in a line")

	s = _shape("staff", "siphon", "", T)
	t.eq(s.pv, {}, "siphon on bare ground is not a click")
	s.b.tiles.apply([T], "fire", "x")
	t.eq(s.b.skill_preview(s.me, "siphon", "", T).hexes, [T], "siphon: one hex")

	var skill_fc: Dictionary = _shape("axe", "cleave", "fire", E, [E]).pv.forecasts["f0"]
	t.eq(skill_fc.kind, BWFormulas.SKILL, "weapon skills use the skill formula")
	t.ok(skill_fc.magic and skill_fc.has("resist"), "an elemental skill rolls resist (D25)")


func test_basic_attacks_never_paint(t) -> void:
	for wc in ["sword", "axe", "lance", "daggers", "bow", "pistols", "fists"]:
		var me := _u("me", wc, "fire", { "dex": 100 })
		var b := _duel(me, [_foe()], [E])
		b.attack(me, b.foes_of(me)[0])
		t.ok(b.tiles.entries.is_empty() and _events(b, "paint").is_empty(), "%s basic attack paints nothing" % wc)


# ------------------------------------------------------------------ cooldowns, follow-ups

func test_cooldowns_per_element(t) -> void:
	var me := _u("me", "axe", "fire")
	me.affinity["water"] = 10
	var b := _duel(me, [_foe()], [Vector2i(8, 8)])
	t.eq(b.learned_elements(me), ["fire", "water"], "learned = rank ≥ 1")
	t.ok(not b.use_skill(me, "cleave", "fire", E).is_empty(), "cleave fire resolves")
	t.ok(me.acted, "a skill spends the action")
	t.eq(me.attuned, "fire", "attuned follows the element")
	t.eq(me.cooldowns.get("cleave_fire", 0), 2, "cleave-fire on cooldown")
	t.eq(b.use_skill(me, "cleave", "water", E), {}, "no second action this turn")
	_give_turn(b, me)
	var row: Array = b.skills_for(me).filter(func(s): return s.key == "cleave")
	t.ok(not row.is_empty() and row[0].elements == ["water"], "next turn: cleave-water open, cleave-fire locked")
	t.eq(b.use_skill(me, "cleave", "fire", E), {}, "cleave-fire refused while cooling")
	_give_turn(b, me)
	row = b.skills_for(me).filter(func(s): return s.key == "cleave")
	t.ok("fire" in row[0].elements, "cleave-fire back after 2 turns")


func test_follow_up_gating(t) -> void:
	# D105: Vault no longer grants a follow-up (it strikes at once); the
	# follow-up gate is shown with Charge (basic) instead.
	var me := _u("me", "axe", "fire")
	var foe := _foe()
	var b := _duel(me, [foe], [Vector2i(8, 4)])
	b.use_skill(me, "charge", "fire", E)
	t.eq(me.pos, Vector2i(7, 4), "charged 3")
	t.eq(me.follow_up, ["basic"], "charge grants a basic follow-up")
	t.ok(not me.acted, "action re-armed for the follow-up")
	t.eq(b.skills_for(me).map(func(s): return s.key), [], "only the follow-up is offered (no skills)")
	t.ok(not b.move(me, Vector2i(6, 5)), "no moving inside a follow-up")
	t.eq(b.use_skill(me, "charge", "fire", Vector2i(8, 4)), {}, "charge refused as a follow-up")
	t.ok(not b.attack(me, foe).is_empty(), "the basic follow-up resolves")
	t.ok(me.follow_up.is_empty() and me.acted, "follow-up spent")
	var lancer := _u("me", "lance", "fire")
	var b3 := _duel(lancer, [_foe()], [Vector2i(7, 4)])
	b3.use_skill(lancer, "vault", "fire", Vector2i(7, 4))
	t.eq(_events(b3, "move")[-1].kind, "leap", "vault animates as a leap")
	t.ok(lancer.follow_up.is_empty() and lancer.acted, "vault: no follow-up, the strike is part of it")

	var sw := _u("me", "sword", "fire")
	var b2 := _duel(sw, [_foe()], [E])
	b2.use_skill(sw, "striketwice", "fire", E)
	t.eq(sw.follow_up, ["striketwice_second"], "striketwice grants its second cut")
	t.eq(b2.attack(sw, b2.foes_of(sw)[0]), {}, "basic attack not allowed after striketwice")
	b2.end_turn()
	t.ok(sw.follow_up.is_empty(), "waiting declines the follow-up")
	t.ok(BWSkills.kit("sword").any(func(s): return s.key == "striketwice_second"), "second cut is in the kit")
	_give_turn(b2, sw)
	t.ok(not b2.skills_for(sw).any(func(s): return s.key == "striketwice_second"), "second cut never offered outside a follow-up")


# ------------------------------------------------------------------ movement skills

func test_charge_shove(t) -> void:
	var me := _u("me", "axe", "fire")
	var foe := _foe()
	var b := _duel(me, [foe], [Vector2i(6, 4)])
	b.tiles.apply([Vector2i(7, 4)], "fire", "x", 3)
	var hp := foe.hp
	b.use_skill(me, "charge", "fire", E)
	t.eq(me.pos, Vector2i(7, 4), "charger runs the full 3")
	t.eq(foe.pos, Vector2i(8, 4), "foe shoved to the hex beyond")
	t.eq(foe.hp, hp, "shoved units take no crossing damage (and Charge deals none)")
	var kinds := _events(b, "move").map(func(e): return e.kind)
	t.eq(kinds, ["charge", "shove"], "move events carry their kind")
	t.eq(me.follow_up, ["basic"], "charge grants a swing")
	t.ok(not b.attack(me, foe).is_empty(), "follow-up basic lands")

	# Shoved into a blocked hex: the charge stops short and the foe stays.
	var me2 := _u("me", "axe", "fire")
	var foe2 := _foe()
	var b2 := _duel(me2, [foe2], [Vector2i(7, 4)])
	b2.board.set_cell(Vector2i(8, 4), "jagged")
	var pv := b2.skill_preview(me2, "charge", "fire", E)
	t.eq(pv.shove, {}, "no shove into jagged")
	b2.use_skill(me2, "charge", "fire", E)
	t.eq(me2.pos, Vector2i(6, 4), "charge stops short of the stuck foe")
	t.eq(foe2.pos, Vector2i(7, 4), "the foe stays put")
	# Adjacent and stuck: the heading goes nowhere, so it is not a click.
	var me3 := _u("me", "axe", "fire")
	var b3 := _duel(me3, [_foe(), _foe("g")], [E, Vector2i(6, 4)])
	t.ok(not E in b3.skill_targets(me3, "charge", "fire"), "a charge that cannot move is not offered")


func test_daggerleap_far(t) -> void:
	var me := _u("me", "daggers", "fire")
	var b := _duel(me, [_foe()], [Vector2i(0, 8)])
	var far := Vector2i(8, 8)
	t.ok(not far in b.skill_targets(me, "daggerleap", "fire"), "bare far hex is out of reach")
	b.tiles.apply([far], "fire", "x")
	t.ok(far in b.skill_targets(me, "daggerleap", "fire"), "far hex carrying fire is in reach")
	b.use_skill(me, "daggerleap", "fire", far)
	t.eq(me.pos, far, "leapt")
	t.eq(_events(b, "move")[-1].kind, "leap", "leap move event")
	for h in b.board.neighbors(far):
		t.eq(b.tiles.intensity(h, "fire"), 1, "flourish fire on %s" % h)


# ------------------------------------------------------------------ damage riders

func test_consume(t) -> void:
	var me := _u("me", "daggers", "fire")
	var foe := _foe()
	var b := _duel(me, [foe], [E])
	t.ok(b.skill_targets(me, "consume").is_empty(), "nothing to eat on bare ground")
	b.tiles.apply([E], "water", "x")
	t.ok(b.skill_targets(me, "consume").is_empty(), "cannot eat an unlearned element")
	b.tiles.apply([E], "fire", "x", 4)                 # water 1 -> fire 3
	var pv := b.skill_preview(me, "consume", "", E)
	var fc: Dictionary = pv.forecasts[foe.id]
	t.eq(fc.power.value, 20, "14 + 2 × 3 points eaten")
	t.eq(fc.damage.value, BWFormulas.damage_taken(me, foe, BWFormulas.SKILL, 20, "fire").value, "damage uses the bonus power")
	b.use_skill(me, "consume", "", E)
	t.ok(b.tiles.at(E).is_empty(), "eaten hex is bare")
	for h in b.board.neighbors(C):
		if h != E:
			t.eq(b.tiles.intensity(h, "fire"), 1, "flourish on %s" % h)
	t.eq(me.attuned, "fire", "attuned to what was eaten")


func test_striketwice_flood(t) -> void:
	var me := _u("me", "sword", "fire")
	me.affinity["water"] = 10
	var b := _duel(me, [_foe()], [E])
	b.use_skill(me, "striketwice", "fire", E)
	b.use_skill(me, "striketwice_second", "fire", E)
	t.eq(b.tiles.intensity(E, "fire"), 2, "target hex took both cuts")
	for h in b.board.neighbors(E):
		if h != C:
			t.eq(b.tiles.intensity(h, "fire"), 1, "flooded %s" % h)
	t.ok(b.tiles.at(C).is_empty(), "never the user's own hex")

	var me2 := _u("me", "sword", "fire")
	me2.affinity["water"] = 10
	var b2 := _duel(me2, [_foe()], [E])
	b2.use_skill(me2, "striketwice", "fire", E)
	b2.use_skill(me2, "striketwice_second", "water", E)
	t.eq(b2.tiles.entries.size(), 0, "mismatched second cut walks the hex back, no flood")


func test_riposte(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe("f", { "dex": 100 })
	var b := _duel(me, [foe], [E])
	var plain: float = b.forecast_basic(foe, me).damage.value
	b.use_skill(me, "riposte", "fire", C)
	t.eq(me.riposte, { "element": "fire" }, "guard set")
	var fc := b.forecast_basic(foe, me)
	t.eq(fc.damage.value, maxf(1.0, roundf(plain * 0.5)), "forecast shows the halved blow")
	t.ok(fc.damage.formula.contains("riposte"), "halving is in the breakdown")
	_give_turn(b, foe)
	var hp := me.hp
	var res := b.attack(foe, me)
	t.ok(res.hit, "the blow lands (hit 100)")
	t.eq(hp - me.hp, res.damage, "took the rolled damage")
	t.ok(res.damage <= maxi(1, roundi(plain * 0.5 * BWFormulas.CRIT_MULT)), "halved")
	t.ok(me.riposte.is_empty(), "guard spent")
	var r := _events(b, "riposte")
	t.eq(r.size(), 1, "answered once")
	t.eq(r[0].results.map(func(x): return x.target), [foe.id], "the answer hits the attacker on the ring")
	t.eq(b.tiles.intensity(C + Vector2i(-1, 0), "fire"), 1, "ring takes the element")
	t.eq(b.forecast_basic(foe, me).damage.value, plain, "next blow is not halved")


func test_reload_quick_shot(t) -> void:
	var me := _u("me", "pistols", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 200 })           # survives two shots
	var b := _duel(me, [foe], [Vector2i(8, 4)])
	t.ok(not b.skills_for(me).any(func(s): return s.key == "quick_shot"), "no quick shot before a reload")
	b.use_skill(me, "reload", "fire", C)
	t.eq(me.loaded, "fire", "round seated")
	t.ok(me.acted, "reload costs the action")
	t.ok(b.tiles.entries.is_empty(), "reload paints nothing yet")
	_give_turn(b, me)
	t.ok(not b.use_skill(me, "quick_shot", "", foe.pos).is_empty(), "quick shot fires")
	t.ok(not me.acted, "quick shot is free")
	for h in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4)]:
		t.eq(b.tiles.intensity(h, "fire"), 1, "trail fire on %s" % h)
	t.eq(me.loaded, "", "round spent")
	# D87 fan the hammer: unmoved, a second Quick Shot per reload (plain lead), then no more
	t.ok(b.skills_for(me).any(func(s): return s.key == "quick_shot"), "unmoved: the hammer fans a second shot")
	var paints0 := _events(b, "paint").size()
	t.ok(not b.use_skill(me, "quick_shot", "", foe.pos).is_empty(), "second quick shot fires")
	t.eq(_events(b, "paint").size(), paints0, "the fanned shot is plain lead (the round was spent)")
	t.ok(not b.skills_for(me).any(func(s): return s.key == "quick_shot"), "twice per reload at most")
	var paints := _events(b, "paint").size()
	t.ok(not b.attack(me, foe).is_empty(), "the action is still there")
	t.eq(_events(b, "paint").size(), paints, "an empty pistol fires plain lead")

	# Reload then a basic shot: the basic shot lays the trail and spends the quick shot.
	var me2 := _u("me", "pistols", "water", { "dex": 100 })
	var b2 := _duel(me2, [_foe()], [Vector2i(7, 4)])
	b2.use_skill(me2, "reload", "water", C)
	_give_turn(b2, me2)
	b2.attack(me2, b2.foes_of(me2)[0])
	t.eq(b2.tiles.intensity(Vector2i(6, 4), "water"), 1, "basic shot lays the loaded trail")
	t.ok(not me2.quick_shot_ready, "firing at all spends the quick shot")


# ------------------------------------------------------------------ staff

func test_staff_skills(t) -> void:
	var me := _u("me", "staff", "fire", { "dex": 100 })
	var foe := _foe()
	var b := _duel(me, [foe], [T])
	var hp := foe.hp
	var ev := b.use_skill(me, "surge", "fire", T)
	t.eq(ev.results.size(), 1, "surge hits the enemy in the burst")
	t.ok(foe.hp < hp, "spell damage dealt")
	for h in BWHex.area(T, 1):
		t.eq(b.tiles.intensity(h, "fire"), 1, "surge fire on %s" % h)

	_give_turn(b, me)
	var S := Vector2i(2, 4)
	b.use_skill(me, "saturate", "fire", S)
	t.eq(b.tiles.intensity(S, "fire"), 2, "saturate: bare ground to 2")
	me.cooldowns.clear()
	_give_turn(b, me)
	var W := Vector2i(3, 6)
	b.tiles.apply([W], "water", "x")
	b.use_skill(me, "saturate", "fire", W)
	t.eq(b.tiles.intensity(W, "fire"), 1, "saturate flips water 1 to fire 1")

	_give_turn(b, me)
	b.board.set_cell(Vector2i(7, 4), "jagged")
	b.use_skill(me, "ley_line", "fire", E)
	t.eq(b.tiles.intensity(Vector2i(5, 4), "fire"), 1, "ley line lays fire")
	t.eq(b.tiles.intensity(Vector2i(6, 4), "fire"), 1, "ley line second hex")
	t.ok(b.tiles.at(Vector2i(8, 4)).is_empty(), "ley line stops at jagged")
	t.eq(me.follow_up, ["basic"], "ley line grants a Channel")

	var me2 := _u("me", "staff", "fire", { "dex": 100 })
	var foe2 := _foe()
	var b2 := _duel(me2, [foe2], [T])
	b2.tiles.apply([T], "fire", "x", 3)
	b2.tiles.apply([T], "light", "x", 1)
	b2.use_skill(me2, "siphon", "", T)
	t.eq(b2.tiles.at(T).h, 1, "siphon: fire 3 -> 1")
	t.eq(b2.tiles.at(T).v, 0, "siphon: light 1 -> 0")
	t.eq(me2.follow_up, ["basic"], "siphon grants a Channel")
	t.ok(not b2.attack(me2, foe2).is_empty(), "Channel follow-up resolves")
	t.eq(b2.tiles.at(T).h, 2, "Channel repaints the stripped hex")


# ------------------------------------------------------------------ fists (D76)

## Equip a fists item carrying `ench` ("" = plain).
func _fists(u: BWUnit, base: String = "hand_wraps", ench: String = "") -> BWUnit:
	u.equipment["main_hand"] = { "uid": "t_" + base, "base": base, "slot": "main_hand", "weight": "fists",
		"tier": "E", "stats": {}, "enchant": ench, "worn": {} }
	u.refresh_effects()
	return u


func test_fists_shapes(t) -> void:
	var w := BWData.row("weapons", "fists")
	t.eq([int(w.base_dmg), int(w.range), int(w.speed_mod), int(w.move_mod), str(w.levels), str(w.damage_type)],
		[8, 1, 2, 1, "str", "martial"], "fists: jab 8, range 1, speed +2, move +1, levels str, martial")
	t.eq(_u("me", "fists", "fire").move_range(), 5, "fists move 4 + 1")
	var s := _shape("fists", "flurry", "fire", E, [E])
	t.eq(s.pv.hexes, [E], "flurry lays on the target's hex")
	t.eq(s.pv.units, ["f0"], "flurry: the one adjacent target")
	t.eq(s.pv.hits, 3, "flurry: three strikes")
	var fc: Dictionary = s.pv.forecasts["f0"]
	t.eq(fc.kind, BWFormulas.SKILL, "flurry uses the skill formula")
	t.ok(fc.mods.any(func(m): return str(m.label).contains("strike 1 of 3 at 45%") and is_equal_approx(float(m.value), 0.45)),
		"the 45% share is in the breakdown")
	s = _shape("fists", "palm_burst", "fire", E, [E])
	t.eq(s.pv.hexes, [E], "palm burst: the target's hex")
	t.eq(s.pv.steps, 2, "palm burst pours 2 steps")
	s = _shape("fists", "uppercut", "", E, [E])
	t.eq(s.pv.hexes, [], "uppercut paints nothing")
	t.eq(s.pv.knockback.path, [E, Vector2i(6, 4)], "uppercut: 1 hex straight back")
	t.eq(s.pv.knockback.slam, "", "open ground: no slam")
	t.ok(s.b.skill_targets(s.me, "uppercut").has(E), "uppercut targets an adjacent foe")
	var far := _shape("fists", "flurry", "fire", Vector2i(6, 4), [Vector2i(6, 4)])
	t.eq(far.pv, {}, "a foe 2 hexes away is not a flurry click")


func test_flurry_three_hits_last_lays(t) -> void:
	var me := _u("me", "fists", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })            # survives all three
	var b := _duel(me, [foe], [E])
	var pv := b.skill_preview(me, "flurry", "fire", E)
	var per: float = pv.forecasts[foe.id].damage.value
	var hp := foe.hp
	var ev := b.use_skill(me, "flurry", "fire", E)
	t.ok(not ev.is_empty(), "flurry resolves")
	t.eq(int(ev.get("hits", 0)), 3, "the skill event says 3 hits")
	var extra := _events(b, "attack")
	t.eq(extra.size(), 2, "strikes 2 and 3 are their own events")
	t.eq(extra.map(func(x): return [int(x.strike), int(x.strikes), str(x.skill)]), [[1, 3, "flurry"], [2, 3, "flurry"]], "strike k of 3")
	var dealt := int(ev.results[0].result.damage)
	for x in extra:
		dealt += int(x.result.damage)
	t.eq(hp - foe.hp, dealt, "three strikes of damage")
	# the per-strike number is 45% of the same blow at full power
	var full: float = BWFormulas.forecast(me, foe, BWFormulas.SKILL, BWSkills.FLURRY_DMG, "fire").damage.value
	t.ok(absf(per - full * 0.45) <= 1.0, "strike = 45%% of %d (got %d)" % [full, per])
	t.eq(b.tiles.intensity(E, "fire"), 1, "the last strike lays fire on the target's hex")
	var paints := _events(b, "paint")
	t.eq(paints.size(), 1, "laid once, after the strikes")
	t.ok(b.history.find(paints[0]) > b.history.find(extra[-1]), "the element lands with the last strike")
	t.eq(me.cooldowns.get("flurry_fire", 0), 2, "cooldown per skill and element")
	t.eq(me.attuned, "fire", "attuned to the flurry's element")
	t.eq(_events(b, "growth").size(), 1, "one growth award for the action")
	# a KO mid-flurry stops it
	var me2 := _u("me", "fists", "fire", { "dex": 100, "str": 60 })
	var weak := _foe("w")
	var b2 := _duel(me2, [weak], [E])
	weak.hp = 3
	b2.use_skill(me2, "flurry", "fire", E)
	t.ok(not weak.alive(), "first strike knocks out")
	t.eq(_events(b2, "attack").size(), 0, "no strikes into a knocked-out foe")
	t.eq(b2.tiles.intensity(E, "fire"), 1, "the ground still takes the element")


func test_uppercut_knockback_and_slam(t) -> void:
	# open ground: knocked 1 back, no bonus
	var me := _u("me", "fists", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var b := _duel(me, [foe], [E])
	var plain: float = b.skill_preview(me, "uppercut", "", E).forecasts[foe.id].damage.value
	b.use_skill(me, "uppercut", "", E)
	t.eq(foe.pos, Vector2i(6, 4), "knocked 1 hex straight back")
	t.eq(_events(b, "move")[-1].kind, "knockback", "a knockback move event")
	t.eq(_events(b, "slam").size(), 0, "no slam on open ground")
	t.eq(me.cooldowns.get("uppercut", 0), 2, "uppercut cools without an element")
	# jagged or a unit behind: it can't move, so it slams for +50%
	for wall in ["rock", "unit"]:
		var me2 := _u("me", "fists", "fire", { "dex": 100 })
		var foe2 := _foe("f", { "con": 300 })
		var foes := [foe2]
		var at := [E]
		if wall == "unit":
			foes.append(_foe("g", { "con": 300 }))
			at.append(Vector2i(6, 4))
		var b2 := _duel(me2, foes, at)
		if wall == "rock":
			b2.board.set_cell(Vector2i(6, 4), "jagged")
		var pv := b2.skill_preview(me2, "uppercut", "", E)
		t.eq(pv.knockback.slam, wall, "%s behind: slam" % wall)
		var fc: Dictionary = pv.forecasts[foe2.id]
		t.ok(absf(fc.damage.value - roundf(plain * 1.5)) <= 1.0, "%s slam: +50%% (%d vs %d)" % [wall, fc.damage.value, plain])
		t.ok(fc.mods.any(func(m): return str(m.label).begins_with("Slammed into")), "%s slam is in the breakdown" % wall)
		var hp := foe2.hp
		b2.use_skill(me2, "uppercut", "", E)
		t.eq(foe2.pos, E, "%s: the target stays put" % wall)
		t.ok(foe2.hp < hp, "%s: damage dealt" % wall)
		t.eq(_events(b2, "slam").map(func(x): return x.into), [wall], "%s: a slam event" % wall)
	# the map edge is open air, and an immune target braced: neither slams
	var me3 := _u("me", "fists", "fire")
	var b3 := _duel(me3, [_foe()], [Vector2i(8, 4)])
	me3.pos = Vector2i(7, 4)
	t.eq(b3.skill_preview(me3, "uppercut", "", Vector2i(8, 4)).knockback.slam, "", "map edge: no slam")
	var me4 := _u("me", "fists", "fire")
	var rooted := _foe("r")
	rooted.abilities["passive"] = { "id": "unbowed", "rank": 1 }
	var b4 := _duel(me4, [rooted], [E])
	b4.refresh_effects()
	b4.board.set_cell(Vector2i(6, 4), "jagged")
	t.eq(b4.skill_preview(me4, "uppercut", "", E).knockback.slam, "", "immune (Unbowed, D245: Rooted merged in): braced, no slam")
	# Rebound: 2 hexes; a wall 2 out stops the second hex and slams
	var me5 := _fists(_u("me", "fists", "fire", { "dex": 100 }), "gauntlets", "rebound")
	var foe5 := _foe("f", { "con": 300 })
	var b5 := _duel(me5, [foe5], [E])
	t.eq(b5.skill_preview(me5, "uppercut", "", E).knockback.path, [E, Vector2i(6, 4), Vector2i(7, 4)], "Rebound: 2 hexes back")
	b5.board.set_cell(Vector2i(7, 4), "jagged")
	t.eq(b5.skill_preview(me5, "uppercut", "", E).knockback.slam, "rock", "Rebound: stopped after 1 still slams")
	b5.use_skill(me5, "uppercut", "", E)
	t.eq(foe5.pos, Vector2i(6, 4), "Rebound: travelled the 1 it could")
	# Rebound never rides a basic attack
	_give_turn(b5, me5)
	me5.pos = Vector2i(5, 4)
	b5.attack(me5, foe5)
	t.eq(foe5.pos, Vector2i(6, 4), "Rebound is Uppercut-only (the basic jab does not push)")


func test_palm_burst_pours_two(t) -> void:
	var me := _u("me", "fists", "fire", { "dex": 100 })
	var foe := _foe("f", { "con": 300 })
	var b := _duel(me, [foe], [E])
	var hp := foe.hp
	b.use_skill(me, "palm_burst", "fire", E)
	t.ok(foe.hp < hp, "palm burst deals skill damage")
	t.eq(b.tiles.intensity(E, "fire"), 2, "two steps of fire into the target's hex")
	t.eq(b.tiles.entries.size(), 1, "only the target's hex")
	t.eq(me.cooldowns.get("palm_burst_fire", 0), 2, "cooldown per skill and element")
	# combo bait: thunder on the charged hex detonates it
	var r := b.tiles.apply([E], "thunder", "x")
	t.ok(not r.detonations.is_empty(), "thunder detonates the poured charge")
	# water 1 under it: 2 steps flip it to fire 1, like Saturate
	var me2 := _u("me", "fists", "fire", { "dex": 100 })
	var b2 := _duel(me2, [_foe("f", { "con": 300 })], [E])
	b2.tiles.apply([E], "water", "x")
	b2.use_skill(me2, "palm_burst", "fire", E)
	t.eq(b2.tiles.intensity(E, "fire"), 1, "water 1 flips to fire 1")
	# Welling: 3 steps
	var me3 := _fists(_u("me", "fists", "fire", { "dex": 100 }), "gauntlets", "welling")
	var b3 := _duel(me3, [_foe("f", { "con": 300 })], [E])
	t.eq(b3.skill_preview(me3, "palm_burst", "fire", E).steps, 3, "Welling: 3 steps")
	b3.use_skill(me3, "palm_burst", "fire", E)
	t.eq(b3.tiles.intensity(E, "fire"), 3, "Welling pours to the cap")


func test_pummeling_fourth_strike(t) -> void:
	var me := _fists(_u("me", "fists", "fire", { "dex": 100 }), "hand_wraps", "pummeling")
	var foe := _foe("f", { "con": 300 })
	var b := _duel(me, [foe], [E])
	t.eq(b.skill_preview(me, "flurry", "fire", E).hits, 4, "Pummeling: 4 strikes")
	b.use_skill(me, "flurry", "fire", E)
	t.eq(_events(b, "attack").size(), 3, "strikes 2..4")
	t.eq(b.basic_strikes(me, foe).size(), 1, "the basic jab stays one strike")


func test_ai_uses_fist_skills(t) -> void:
	var used := {}
	for s in 6:
		var cells: Array = []
		for r in 8:
			for c in 8:
				cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
		var b := BWBattle.new(BWBoard.from_dict({ "name": "m", "cols": 8, "rows": 8, "cells": cells,
			"spawns": { "player": [[1, 3], [1, 4], [1, 5]], "enemy": [[6, 3], [6, 4], [6, 5]] } }), 300 + s)
		b.setup([_u("a1", "fists", "fire"), _u("a2", "fists", "thunder"), _u("a3", "fists", "water")],
			[_u("e1", "axe", "wind"), _u("e2", "sword", "light"), _u("e3", "fists", "dark")])
		var n := 0
		while not b.over and n < 400:
			BWAI.take_turn(b)
			n += 1
		t.ok(b.over, "seed %d: fists fight ends" % s)
		for e in _events(b, "skill"):
			used[e.skill] = true
	for k in ["flurry", "uppercut"]:
		t.ok(used.has(k), "the AI throws %s (%s)" % [k, used.keys()])
	# Palm Burst out-damages the jab but not Flurry or Uppercut; the AI does
	# not plan ground (BWAI), so it reaches for it while the other two cool.
	var me := _u("me", "fists", "fire")
	var b2 := _duel(me, [_foe("f", { "con": 300 })], [E])
	me.cooldowns["flurry_fire"] = 2
	me.cooldowns["uppercut"] = 2
	BWAI.take_turn(b2)
	t.eq(_events(b2, "skill").map(func(x): return x.skill), ["palm_burst"], "with Flurry and Uppercut cooling, Palm Burst beats the jab")


# ------------------------------------------------------------------ whole fights

func _mixed(seed_value: int) -> BWBattle:
	var cells: Array = []
	for r in 10:
		for c in 10:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	var b := BWBattle.new(BWBoard.from_dict({ "name": "m", "cols": 10, "rows": 10, "cells": cells,
		"spawns": { "player": [[1, 4], [1, 5], [1, 6]], "enemy": [[8, 4], [8, 5], [8, 6]] } }), seed_value)
	var a := [_u("a1", "bow", "fire"), _u("a2", "staff", "thunder"), _u("a3", "daggers", "water")]
	var e := [_u("e1", "axe", "wind"), _u("e2", "lance", "light"), _u("e3", "sword", "dark")]
	b.setup(a, e)
	return b


func test_ai_fights_with_skills(t) -> void:
	var skills_used := 0
	for s in 4:
		var b1 := _mixed(200 + s)
		var n := 0
		while not b1.over and n < 400:
			BWAI.take_turn(b1)
			n += 1
		t.ok(b1.over, "seed %d: AI-vs-AI fight ends" % s)
		skills_used += _events(b1, "skill").size()
		var b2 := _mixed(200 + s)
		n = 0
		while not b2.over and n < 400:
			BWAI.take_turn(b2)
			n += 1
		t.eq(JSON.stringify(b1.history), JSON.stringify(b2.history), "seed %d: identical replay with skills" % s)
	t.ok(skills_used > 0, "the AI uses damaging skills (%d)" % skills_used)


func test_scripted_determinism(t) -> void:
	var logs: Array = []
	for i in 2:
		var me := _u("me", "sword", "fire")
		var b := _duel(me, [_foe()], [E], 42)
		b.use_skill(me, "striketwice", "fire", E)
		b.use_skill(me, "striketwice_second", "fire", E)
		logs.append(JSON.stringify(b.history))
	t.eq(logs[0], logs[1], "same seed, same skill rolls")

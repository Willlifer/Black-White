extends RefCounted
## Enchantments v2 and the shop redesign (design/ENCHANTMENTS-v2.md, D196-D205):
## the scaling retune, each new key (on_event, pity, drawback, swap), the §5
## loop caps, Advantage's 3-turn cooldown, the curse display, the shop's stock,
## the scrolls (re-roll per battle, the 2-for-1, the overwrite) and the tiers.

const N := 11
const C := Vector2i(5, 5)
const FAR := Vector2i(10, 10)


func _board() -> BWBoard:
	var cells: Array = []
	for r in N:
		for c in N:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "fx2", "cols": N, "rows": N, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String = "sword", el: String = "fire", extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 40, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


## Enchantment `id` on the first base of `slot` its row lists (weapon rows on
## the unit's own class when it lists it).
func _ench(u: BWUnit, id: String, slot: String = "") -> BWUnit:
	var row := BWData.row("enchantments", id)
	var pick := ""
	for b in BWData.list(row.applies_to):
		var s := str(BWData.row("equipment", b).slot)
		if slot != "" and s != slot:
			continue
		if s == "main_hand" and str(BWData.row("equipment", b).weight) != u.weapon_class and pick != "":
			continue
		pick = b
		if s != "main_hand" or str(BWData.row("equipment", b).weight) == u.weapon_class:
			break
	var base := BWData.row("equipment", pick)
	u.equipment[str(base.slot)] = { "uid": "t_" + id, "base": pick, "slot": str(base.slot),
		"weight": str(base.weight), "tier": "E", "stats": {}, "enchant": id, "worn": {} }
	u.refresh_effects()
	return u


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


func _fight(players: Array, foes: Array, ppos: Array, fpos: Array, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1
		u.statuses = {}
	b.refresh_effects()
	_turn(b, players[0])
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _fired(b: BWBattle, name_part: String) -> Array:
	return _ev(b, "enchant").filter(func(e): return str(e.name).contains(name_part) or str(e.text).contains(name_part))


func _mod(fc: Dictionary, part: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).contains(part):
			return m
	return {}


func _foe(id: String, extra: Dictionary = {}) -> BWUnit:
	var x := { "dex": 4 }
	x.merge(extra, true)
	return _u(id, "axe", "water", x)


# ------------------------------------------------------------------ §1 scaling

func test_scaling_pct_with_the_flat_floor(t) -> void:
	var hi := _ench(_u("hi", "staff", "light", { "wil": 34 }), "sunlit")
	var lo := _ench(_u("lo", "staff", "light", { "wil": 6 }), "sunlit")
	var b := _fight([hi, lo], [_foe("f")], [C, Vector2i(2, 2)], [FAR])
	b.tiles.apply([C, Vector2i(2, 2)], "light", "x", 3)
	t.eq(hi.stat("wil"), 34 + 10, "Sunlit: +10% WIL per light point (34 x 30% = +10)")
	t.eq(lo.stat("wil"), 6 + 3, "the floor: never less than +1 per point (+3 at WIL 6)")
	var rim := _ench(_u("r", "sword", "ice", { "def": 30 }), "rimed")
	var b2 := _fight([rim], [_foe("f2")], [C], [FAR])
	b2.tiles.apply([C], "fire", "x")
	b2.tiles.apply([C], "ice", "x")
	t.eq(rim.stat("def"), 36, "Rimed: +20% DEF on a glaze (30 -> +6, over the +2 floor)")
	for id in ["fireproof", "grounded", "windbreak", "nightforged"]:
		t.eq(int(BWEffects.parse_params(BWData.row("enchantments", id).params).pct), -20, "%s: the resist rows sit at 20%%" % id)


# ------------------------------------------------------------------ on_event: on kill

func test_death_knell_fires_and_never_chains(t) -> void:
	var me := _ench(_u("me"), "death_knell")
	var v := _foe("v", { "con": 1 })
	var w := _foe("w")
	var x := _foe("x")
	var E := _nb(C, 0)
	var b := _fight([me], [v, w, x], [C], [E, _nb(E, 0), _nb(_nb(E, 0), 0)])
	v.hp = 1
	w.hp = 2                              # the burst KOs w: that KO must not burst again
	var hx := x.hp
	b.attack(me, v)
	t.ok(not v.alive(), "the blow KOs v")
	t.eq(_fired(b, "Death Knell").size(), 1, "Death Knell fires once (an event: the floater)")
	t.ok(_ev(b, "tile_damage").any(func(e): return e.cause == "knell" and e.unit == "w"), "the burst hits the foe within 1")
	t.ok(not w.alive(), "and KOs it")
	t.eq(x.hp, hx, "on-kill never triggers on-kill: w's KO doesn't burst onto x")


func test_relentless_once_per_turn_attack_only(t) -> void:
	var me := _ench(_u("me"), "relentless")
	var a := _foe("a")
	var c := _foe("c")
	var b := _fight([me], [a, c], [C], [_nb(C, 0), _nb(C, 3)])
	a.hp = 1
	c.hp = 1
	b.attack(me, a)
	t.eq(me.follow_up, ["basic"], "a KO grants one more attack")
	t.ok(not me.acted and not b.can_move(me), "an attack only: no move")
	b.attack(me, c)
	t.ok(not c.alive(), "the extra attack lands")
	t.ok(me.follow_up.is_empty() and me.acted, "once per turn: the second KO grants nothing")


func test_pursuit_feast_and_wake(t) -> void:
	var me := _ench(_ench(_u("me"), "pursuit"), "feast")
	var v := _foe("v")
	var E := _nb(C, 0)
	var b := _fight([me], [v, _foe("stay")], [C], [E, FAR])     # a foe left, so the battle goes on
	var mv := me.move_range()
	me.hp = me.max_hp() / 2
	var h0 := me.hp
	v.hp = 1
	b.attack(me, v)
	t.eq(me.move_range(), mv + 2, "Pursuit: a KO gives +2 move this turn")
	t.eq(me.hp - h0, roundi(me.max_hp() * 0.15), "Feast: a KO heals 15% max HP")
	# Wake of Ash: kill paint arrives as spread, so a fuse beside the victim never fires.
	var ash := _ench(_u("ash"), "wake_fire", "chest")
	var v2 := _foe("v2")
	var b2 := _fight([ash], [v2, _foe("far")], [C], [E, FAR])
	var ring := _nb(E, 0)
	b2.tiles.apply([ring], "thunder", "x")
	v2.hp = 1
	b2.attack(ash, v2)
	t.ok(b2.tiles.intensity(E, "fire") >= 1, "Wake of Ash: fire on the victim's hex")
	t.eq(str(b2.tiles.at(ring).get("marker", "")), "fuse", "the fuse in the ring is untouched (no marker fires)")
	t.ok(_ev(b2, "detonate").is_empty(), "no detonation")


func test_vengeance_and_tag_team(t) -> void:
	var avenger := _ench(_u("av"), "vengeance")
	var tag := _ench(_u("tg"), "tag_team")
	var killer := _u("k")
	var foe := _foe("f")
	var b := _fight([killer, avenger, tag], [foe, _foe("stay")], [C, Vector2i(1, 1), _nb(C, 3)], [_nb(C, 0), FAR])
	foe.hp = 1
	b.attack(killer, foe)
	t.eq(int(tag.fx.get("next_move", 0)), 2, "Tag Team: an ally within 2 KO'd a foe: +2 move next turn")
	_turn(b, tag)
	t.ok(tag.move_notes().any(func(n): return str(n[0]).contains("Tag Team")), "banked into the next turn, named on the Move line")
	b._tile_hurt(killer, 9999, "fire", "")
	var em: Array = avenger.fx.get("empower", [])
	t.ok(em.any(func(x): return float(x.dmg_pct) == 50.0 and x.sure), "Vengeance: an ally falls: +50% and can't be avoided")


# ------------------------------------------------------------------ on_event: recovery + the heal cap

func test_leeching_and_the_heal_cap(t) -> void:
	var me := _ench(_u("me", "sword", "fire", { "str": 60 }), "leeching")
	var foe := _foe("f", { "con": 400 })
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	me.hp = 10
	b.attack(me, foe)
	var dealt := int(_ev(b, "attack")[0].result.damage)
	var heal: Array = _ev(b, "heal")
	t.ok(dealt > 0 and not heal.is_empty(), "Leeching heals off a direct hit")
	t.eq(int(heal[0].amount), mini(roundi(dealt * 0.15), roundi(me.max_hp() * 0.20)), "15% of the damage, held to 20% max HP")
	BWEnchant.begin_action(b, me)
	b._action_serial += 1
	me.hp = 1
	BWEnchant.ev_heal(b, me, 15.0, "A")
	BWEnchant.ev_heal(b, me, 15.0, "B")
	t.eq(me.hp, 1 + roundi(me.max_hp() * 0.15) + roundi(me.max_hp() * 0.05), "the cap: 20% max HP per action, across rows")
	# Leeching reads direct hits only: tile damage dealt heals nothing
	me.hp = 10
	var heals := _ev(b, "heal").size()
	b._tile_hurt(foe, 30, "fire", me.id)
	t.eq(_ev(b, "heal").size(), heals, "never from tiles")


func test_second_breath_hearthbound_mend_link(t) -> void:
	var me := _ench(_ench(_u("me", "staff", "light"), "hearth_light", "head"), "mend_link")
	var mate := _u("m")
	var b := _fight([me, mate], [_foe("f")], [C, _nb(C, 0)], [FAR])
	b.paint([C], "light", me)
	me.hp = me.max_hp() / 2
	mate.hp = mate.max_hp() / 2
	var h0 := me.hp
	var m0 := mate.hp
	_turn(b, me)
	t.ok(_fired(b, "Hearthbound").size() + _ev(b, "heal").filter(func(e): return str(e.get("cause", "")).contains("Hearthbound")).size() > 0,
		"Hearthbound: start on your own light: heal 3% per level")
	t.ok(me.hp > h0, "the holder healed")
	t.ok(mate.hp > m0, "Mend-Link: the heal echoes to the most-hurt ally within 2")
	t.ok(_ev(b, "heal").any(func(e): return e.unit == "m" and e.get("cause", "") == "mend_link"), "as a mend_link heal (which never echoes)")


# ------------------------------------------------------------------ pity

func test_steady_hand_graze_second_chance(t) -> void:
	var me := _ench(_ench(_u("me"), "graze"), "steady_hand", "head")
	var foe := _foe("f", { "dex": 2000, "con": 300 })
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	var h0 := foe.hp
	var res := b.attack(me, foe)
	t.ok(not res.hit, "a 5% shot misses")
	t.ok(foe.hp < h0, "Graze: the missed basic still deals 25%")
	t.ok(not _fired(b, "Graze").is_empty(), "named as it fires")
	t.eq(str(me.fx.get("steady", "")) != "", true, "Steady Hand: the action missed completely, so it's armed")
	_turn(b, me)
	var fc := b.forecast_basic(me, foe)
	t.eq(float(fc.hit.value), 100.0, "the next attack can't be avoided")
	t.ok(not _mod(fc, "can't be avoided").is_empty(), "and the forecast says why")
	b.attack(me, foe)
	t.ok(not me.fx.has("steady"), "spent by that attack")
	# Second Chance: one re-roll a battle
	var sc := _ench(_u("sc"), "second_chance", "head")
	var f2 := _foe("f2", { "dex": 2000, "con": 300 })
	var b2 := _fight([sc], [f2], [C], [_nb(C, 0)])
	b2.attack(sc, f2)
	_turn(b2, sc)
	b2.attack(sc, f2)
	t.eq(_fired(b2, "Second Chance").size(), 1, "Second Chance: the first miss is re-rolled, once per battle")


func test_follow_through_and_building_pressure(t) -> void:
	var me := _ench(_u("me"), "follow_through")
	var wall := _foe("w", { "def": 300, "con": 300 })
	var b := _fight([me], [wall], [C], [_nb(C, 0)])
	b.attack(me, wall)
	t.eq(float(me.fx.get("follow_mult", 0)), 2.0, "Follow-Through: a glance arms x2")
	_turn(b, me)
	var fc := b.forecast_basic(me, wall)
	t.ok(not _mod(fc, "after a glance").is_empty(), "the x2 is a forecast line")
	t.eq(float(fc.crit.value), 0.0, "and that strike can't crit")
	var bp := _ench(_u("bp"), "building_pressure")
	var f := _foe("f", { "def": 0, "con": 300 })
	var b2 := _fight([bp], [f], [C], [_nb(C, 0)])
	bp.statuses["blinded"] = { "armed": false, "source": "" }      # no crit possible
	var c0 := float(b2.forecast_basic(bp, f).crit.value)
	b2.attack(bp, f)
	bp.statuses.clear()
	_turn(b2, bp)
	t.eq(float(bp.fx.get("pressure", 0)), 8.0, "Building Pressure: +8 crit after a hit that didn't crit")
	t.near(float(b2.forecast_basic(bp, f).crit.value), 0.1 * bp.stat("dex") + 8.0, 0.01, "shown on the crit line")
	t.ok(c0 == 0.0, "(blinded: no crit while it built)")


func test_advantage_on_a_three_turn_cooldown(t) -> void:
	var me := _ench(_u("me", "staff", "fire", { "dex": 60 }), "second_opinion", "head")
	var foe := _foe("f", { "res": 30, "con": 300 })
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	var fc := b.forecast_basic(me, foe)
	t.ok(fc.magic, "a staff basic is magic")
	var base := float(fc.resist_base)
	t.near(float(fc.resist.value), base * base / 100.0, 0.01, "Second Opinion: the foe's resist rolls twice, you keep the better (r²)")
	t.eq(int(fc.resist_adv), 1, "the attacker's advantage")
	b.attack(me, foe)
	t.eq(int(me.fx.get("adv_cd", 0)), 3, "spent on the roll: 3 turns to recharge")
	t.ok(not _fired(b, "Advantage").is_empty(), "a floater says it fired")
	for k in 2:
		_turn(b, me)
		t.ok(not b.forecast_basic(me, foe).has("resist_adv"), "not ready yet (turn %d)" % (k + 1))
	_turn(b, me)
	t.eq(int(b.forecast_basic(me, foe).get("resist_adv", 0)), 1, "ready again on the third turn")
	# Stubborn: the defender's side
	var mule := _ench(_u("mu", "axe", "water", { "res": 30, "con": 300 }), "stubborn", "chest")
	var caster := _u("ca", "staff", "fire")
	var b2 := _fight([caster], [mule], [C], [_nb(C, 0)])
	var f2 := b2.forecast_basic(caster, mule)
	var r := float(f2.resist_base) / 100.0
	t.near(float(f2.resist.value), 100.0 * (1.0 - (1.0 - r) * (1.0 - r)), 0.01, "Stubborn: you roll the resist twice and keep the better")


# ------------------------------------------------------------------ drawback (cursed)

func test_drawbacks(t) -> void:
	var me := _ench(_u("me"), "bloodpact")
	var foe := _foe("f", { "con": 300 })
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	t.ok(not _mod(b.forecast_basic(me, foe), "Bloodpact").is_empty(), "Bloodpact: +25% in the forecast")
	var h0 := me.hp
	b.attack(me, foe)
	t.eq(h0 - me.hp, roundi(me.max_hp() * 0.04), "every action costs 4% max HP")
	var hol := _ench(_u("ho"), "hollow", "chest")
	var b2 := _fight([hol], [_foe("g")], [C], [FAR])
	hol.hp = 10
	b2._heal(hol, 50.0, "light")
	t.eq(hol.hp, 10, "Hollow: nothing can heal you")
	t.ok(not _ev(b2, "enchant").filter(func(e): return str(e.text).contains("can't be healed")).is_empty(), "said as it happens")
	var gl := _ench(_u("gl"), "glass", "head")
	var att := _u("a")
	var b3 := _fight([att], [gl], [C], [_nb(C, 0)])
	t.ok(not _mod(b3.forecast_basic(att, gl), "always Scorched").is_empty(), "Glass: always Scorched (+10% on you)")
	var lead := _ench(_u("le"), "leaden", "legs")
	var plain := _u("pl")
	var b4 := _fight([lead, plain], [_foe("h")], [C, Vector2i(1, 1)], [FAR])
	t.eq(lead.move_range(), plain.move_range() - 2, "Leaden: -2 move")
	var rk := _ench(_u("rk"), "reckless", "head")
	var b5 := _fight([att], [rk], [C], [_nb(C, 0)])
	t.eq(float(b5.forecast_basic(att, rk).glance.value), 0.0, "Reckless: you can't glance")


func test_curse_display(t) -> void:
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), 7)
	var it := r.make_item("sword", "B", "bloodpact")
	t.ok(BWEffects.cursed("bloodpact") and not BWEffects.cursed("keen"), "cursed rows are flagged in the data")
	t.ok(BWRun.item_name(it).contains(BWRun.CURSE_MARK), "the name carries the curse mark")
	var line := BWItemCard.curse_line(BWData.row("enchantments", "bloodpact"))
	t.ok(line.contains("Cursed") and line.contains("4%"), "the card spells out the cost")
	t.eq(BWItemCard.curse_line(BWData.row("enchantments", "keen")), "", "no line on a plain row")
	for row in BWData.table("enchantments"):
		if BWEffects.cursed(row):
			t.ok(str(row.cost_text) != "" and str(row.drawback) != "", "%s names its cost" % row.id)


# ------------------------------------------------------------------ swap

func test_bodyguard_and_lifeline(t) -> void:
	var me := _ench(_u("me"), "bodyguard", "legs")
	var mate := _u("m")
	var at := Vector2i(5, 7)
	var b := _fight([me, mate], [_foe("f")], [C, at], [FAR])
	var r := b.reachable(me)
	t.eq(str(r.get(at, {}).get("swap", "")), "m", "Bodyguard: an ally within 2 is a move target")
	t.ok(b.move(me, at), "the swap is the move")
	t.eq([me.pos, mate.pos], [at, C], "they trade places")
	t.ok(not b.can_move(me), "and the move is spent")
	var life := _ench(_u("li"), "lifeline", "chest")
	var hurt := _u("h")
	var b2 := _fight([life, hurt], [_foe("g")], [C, at], [FAR])
	b2._tile_hurt(hurt, roundi(hurt.max_hp() * 0.8), "fire", "")
	t.eq([life.pos, hurt.pos], [at, C], "Lifeline: an ally dropping below 25% trades places with you")
	t.ok(not _fired(b2, "Lifeline").is_empty(), "named as it fires")


# ------------------------------------------------------------------ team rows (new, D202)

func test_team_rows(t) -> void:
	var tend := _ench(_u("te"), "tending", "chest")
	var mate := _u("m")
	var b := _fight([tend, mate], [_foe("f")], [C, _nb(C, 0)], [FAR])
	mate.hp = 10
	b.end_turn()
	t.eq(mate.hp, 10 + roundi(mate.max_hp() * 0.04), "Tending: end your turn, allies beside you heal 4%")
	var sh := _ench(_u("sh"), "sheltering", "head")
	var m2 := _u("m2")
	var foe := _foe("f2")
	var b2 := _fight([sh, m2], [foe], [C, _nb(C, 0)], [_nb(_nb(C, 0), 0)])
	m2.hp = m2.max_hp() / 2
	_turn(b2, sh)
	t.eq(float(m2.fx.get("parry", 0)), 30.0, "Sheltering: the most-hurt ally within 2 is Sheltered")
	t.ok(not _mod(b2.forecast_basic(foe, m2), "Sheltering").is_empty(), "the -30% is a forecast line")
	var pin := _ench(_u("pi"), "pincer")
	var helper := _u("he")
	var vic := _foe("v", { "con": 300 })
	var E := _nb(C, 0)
	var b3 := _fight([pin, helper], [vic], [C, _nb(E, 1)], [E])
	b3.attack(pin, vic)
	t.ok(_ev(b3, "counter").any(func(e): return e.get("cause", "") == "assist" and e.unit == "he"), "Pincer: the ally beside the foe strikes too")
	var ls := _ench(_u("ls"), "lockstep", "legs")
	var pal := _u("pal")
	var b4 := _fight([ls, pal], [_foe("f4")], [C, _nb(C, 0)], [FAR])
	t.ok(b4._auras(ls, "dmg_pct").any(func(a): return str(a.label).contains("Lockstep")), "Lockstep: you get it with an ally beside you")
	t.ok(b4._auras(pal, "dmg_pct").any(func(a): return str(a.label).contains("Lockstep")), "and so does the ally")
	var rc := _ench(_u("rc"), "rally_cry", "chest")
	var low := _u("lo")
	var b5 := _fight([rc, low], [_foe("f5")], [C, FAR - Vector2i(1, 1)], [FAR])
	b5._tile_hurt(low, roundi(low.max_hp() * 0.7), "fire", "")
	t.eq(float(low.fx.get("guard", 0)), 25.0, "Rally Cry: below 35% HP, a 25% guard")


# ------------------------------------------------------------------ forecast lines for the positional rows

func test_positional_rows_are_forecast_lines(t) -> void:
	var fl := _ench(_u("fl"), "flanker")
	var foe := _foe("f")
	var b := _fight([fl], [foe], [C], [_nb(C, 0)])
	foe.facing = BWHex.direction_index(foe.pos, _nb(foe.pos, 0))      # facing away from C
	t.ok(not _mod(b.forecast_basic(fl, foe), "from behind").is_empty(), "Flanker: +20% from behind")
	var rs := _ench(_u("rs"), "resonance")
	var f2 := _foe("f2")
	var b2 := _fight([rs], [f2], [C], [_nb(C, 0)])
	b2.tiles.apply([f2.pos], "fire", "x", 2)
	var m := _mod(b2.forecast_basic(rs, f2), "charge levels")
	t.near(float(m.get("value", 0)), 1.08, 0.001, "Resonance: +4% per charge level (fire 2: +8%)")


# ------------------------------------------------------------------ tiers (D200)

func test_tiers_unlock_and_weigh_double(t) -> void:
	var b_row := BWData.row("enchantments", "relentless")
	var d_row := BWData.row("enchantments", "graze")
	var e_row := BWData.row("enchantments", "keen")
	t.eq(BWRun.ench_weight(b_row, "D"), 0, "a B row can't drop at D")
	t.eq(BWRun.ench_weight(b_row, "B"), 2, "at its own tier it weighs double")
	t.eq(BWRun.ench_weight(b_row, "A"), 1, "and plain after")
	t.eq(BWRun.ench_weight(d_row, "D"), 2, "D rows double at D")
	t.eq(BWRun.ench_weight(e_row, "E"), 1, "the E rows weigh 1")
	t.eq(BWRun.ench_weight(BWData.row("enchantments", "bloodpact"), "B"), BWRun.ench_weight(b_row, "B"), "cursed rows drop at the same weight")
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), 3)
	var only_e := true
	for i in 300:
		var it := r.random_item("E")
		if str(BWData.row("enchantments", it.enchant).get("tier", "E")) != "E":
			only_e = false
	t.ok(only_e, "an E item rolls only E rows")
	for id in ["quickened", "plunder", "trophy", "vampiric", "bloodletter", "stitchwork", "berserkers"]:
		t.ok(BWData.row("enchantments", id).is_empty(), "removed: %s" % id)
	t.ok(not BWData.row("enchantments", "forsaken").is_empty(), "Berserker's is Forsaken")


# ------------------------------------------------------------------ the shop (D203)

func _run(p_seed: int = 11) -> BWRun:
	return BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), p_seed)


func test_shop_stock_composition(t) -> void:
	var r := _run()
	t.eq(r.shop.map(func(it): return str(it.slot)), ["head", "chest", "legs", "main_hand", "main_hand"], "1 head, 1 chest, 1 legs, 2 weapons")
	t.ok(r.shop.all(func(it): return str(it.tier) == r.tier_for(r.fight)), "all at the current tier")
	var mine := r.random_item("E")
	r.inventory.append(mine)
	var take: Dictionary = r.shop[0]
	t.ok(r.trade(mine, take), "trades are still 1-for-1")
	t.ok(take in r.inventory and mine in r.shop, "items swapped")


func test_scrolls_per_element_and_rerolled_each_battle(t) -> void:
	var r := _run()
	t.eq(r.scrolls.map(func(s): return str(s.element)), BWFormulas.ELEMENTS, "seven scrolls, one per element")
	for s in r.scrolls:
		var row := BWData.row("enchantments", str(s.enchant))
		t.eq(str(row.get("element", "")), str(s.element), "the %s scroll holds a %s row (%s)" % [s.element, s.element, s.enchant])
		t.ok(BWRun.ench_weight(row, r.tier_for(r.fight)) > 0, "unlocked at the shop's tier")
	var before := r.scrolls.map(func(s): return str(s.uid) + ":" + str(s.enchant))
	var e := r.enemies_for(1)
	r.after_fight(true, r.squad.slice(0, 3), e, e, [])
	var after := r.scrolls.map(func(s): return str(s.uid) + ":" + str(s.enchant))
	t.ok(before != after, "re-rolled after the battle")
	t.ok(r.scrolls.all(func(s): return not s.get("sold", false)), "fresh: none sold")
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	var r2 := BWRun.from_dict(d)
	t.eq(r2.scrolls.map(func(s): return str(s.enchant)), r.scrolls.map(func(s): return str(s.enchant)), "saved and loaded (v8)")
	d.erase("scrolls")
	t.eq(BWRun.from_dict(d).scrolls.size(), 7, "an older save rolls them")


func test_scroll_two_for_one_and_overwrite(t) -> void:
	var r := _run()
	var fire: Dictionary = r.scrolls[0]
	var a := r.make_item("chaps", "E")
	var b := r.make_item("tights", "E")
	var c := r.make_item("crown", "E", "radiant")
	r.inventory.append_array([a, b, c])
	var n := r.inventory.size()
	t.ok(not r.can_use_scroll(fire, [a], c), "one item isn't enough")
	t.ok(not r.can_use_scroll(fire, [a, c], c), "the target can't be part of the price")
	var worn: Dictionary = r.squad[0].equipment.main_hand
	t.ok(not r.can_use_scroll(fire, [a, worn], c), "only loose items pay")
	t.ok(r.use_scroll(fire, [a, b], c), "two loose items for the scroll")
	t.eq(r.inventory.size(), n - 2, "the two given are gone")
	t.ok(not a in r.inventory and not b in r.inventory, "both of them")
	t.eq(str(c.enchant), str(fire.enchant), "armour: the scroll overwrites its enchantment")
	t.ok(fire.sold, "the scroll is spent until the next battle")
	var v1 := r.make_item("vest", "E")
	var v2 := r.make_item("scarf", "E")
	r.inventory.append_array([v1, v2])
	t.ok(not r.use_scroll(fire, [v1, v2], c), "a sold scroll can't be used again")
	# a weapon: the scroll sets its imbue; its own enchantment stays (D203)
	var water: Dictionary = r.scrolls[1]
	var x := r.make_item("chaps", "E")
	var y := r.make_item("tights", "E")
	r.inventory.append_array([x, y])
	var ench0 := str(worn.enchant)
	t.ok(r.use_scroll(water, [x, y], worn), "a worn E weapon can take a scroll (it gains an imbue)")
	t.eq(str(worn.get("imbue", "")), "water", "D206: the imbue becomes the scroll's element")
	t.eq(str(worn.get("imbue_enchant", "")), str(water.enchant), "and carries the scroll's enchantment")
	t.eq(str(worn.enchant), ench0, "the weapon's own enchantment stays")


## D206: an imbue = an element + one of that element's rows; it works only drawn.
func test_imbue_carries_an_element_enchantment(t) -> void:
	var r := _run()
	for i in 40:
		var w := r.make_item("flamberge", "C")
		var row := BWData.row("enchantments", str(w.get("imbue_enchant", "")))
		if str(row.get("element", "")) != str(w.imbue) or BWRun.ench_weight(row, "C") <= 0:
			t.ok(false, "C weapon %s: imbue %s with %s" % [w.uid, w.imbue, w.get("imbue_enchant", "")])
			return
	t.ok(true, "C weapons roll an imbue with an enchantment of its element, unlocked at C")
	var u := _u("u")
	var w2 := r.make_item("sword", "C", "keen")
	w2.imbue = "fire"
	w2.imbue_enchant = "blazing"
	u.equipment["main_hand"] = w2
	u.refresh_effects()
	t.ok(u.effects.any(func(e): return e.source == "blazing"), "the drawn weapon's imbue enchantment is active")
	t.ok(u.effects.any(func(e): return e.source == "keen"), "next to its weapon enchantment")
	u.equipment["second"] = w2
	u.equipment["main_hand"] = r.make_item("axe", "E", "impact")
	u.refresh_effects()
	t.ok(not u.effects.any(func(e): return e.source == "blazing"), "carried, it gives nothing (D180)")
	# save v9 migration: an old imbued weapon rolls its enchantment
	var old := r.make_item("axe", "C")
	old.erase("imbue_enchant")
	r.inventory.append(old)
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	d.version = 8
	var back := BWRun.from_dict(d)
	var mig: Dictionary = back.inventory.back()
	t.eq(str(BWData.row("enchantments", str(mig.get("imbue_enchant", ""))).get("element", "")), str(mig.imbue), "migrated: an enchantment of its imbue's element")


# ------------------------------------------------------------------ Waterwalking (D204)

func test_waterwalking_first_water_hex_free(t) -> void:
	var me := _u("me", "sword", "water")
	me.affinity["water"] = 10
	me.perks.append("water_walk")
	me.refresh_effects()
	var b := _fight([me], [_foe("f")], [C], [FAR])
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	b.tiles.apply([E, E2], "water", "x", 3)
	var r := b.reachable(me)
	t.eq(int(r[E].cost), 0, "the first water hex costs no move")
	b.move(me, E)
	t.ok(me.fx.get("free_water_used", false), "spent for this turn")
	_turn(b, me)
	t.ok(not me.fx.get("free_water_used", false), "back at the next turn")
	me.fx["free_water_used"] = true
	t.eq(int(b.reachable(me)[E2].cost), 3, "once spent, water costs as usual (1 + 2)")

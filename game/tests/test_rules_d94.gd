extends RefCounted
## D94 statuses (Staggered, Blinded, Pinned), D96 facing in the hit formula,
## D97 engine hooks (zone, overwatch, free placement), D98 loadout overcap,
## D95 gale 2, D99 enemy scaling.

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


func _foe(id: String = "f", extra: Dictionary = {}, wc: String = "axe") -> BWUnit:
	var x := { "con": 300 }
	x.merge(extra, true)
	return _u(id, wc, "water", x)


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
		u.fx = {}
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _mod(fc: Dictionary, label_start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(label_start):
			return m
	return {}


# ------------------------------------------------------------------ D94 statuses

func test_staggered_is_basic_only(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	_turn(b, me)
	t.ok(not b.skills_for(me).is_empty(), "skills before")
	b.add_status(me, "staggered", foe)
	t.eq(b.skills_for(me), [], "Staggered: no skills")
	t.eq(b.use_skill(me, "striketwice", "fire", E), {}, "use_skill refuses")
	t.ok(_mod(b.forecast_basic(me, foe), "Staggered").is_empty(), "no hit penalty")
	t.ok(not b.attack(me, foe).is_empty(), "the basic attack still works")
	# the AI obeys: a staggered enemy only makes basic attacks
	var ai := _foe("ai", { "con": 4 }, "sword")
	var target := _u("t", "sword", "fire", { "con": 300 })
	var b2 := _fight([target], [ai], [C], [E])
	_turn(b2, ai)
	b2.add_status(ai, "staggered", target)
	BWAI.take_turn(b2)
	t.eq(_ev(b2, "skill").size(), 0, "the AI used no skill")
	t.eq(_ev(b2, "attack").size(), 1, "it attacked")


func test_steadied_after_stagger(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.add_status(foe, "staggered", me)
	_turn(b, foe)
	b.end_turn()
	t.ok(not foe.statuses.has("staggered"), "Staggered ended")
	t.ok(foe.statuses.has("steadied"), "now Steadied (unit card)")
	t.eq(BWSkills.STATUS.steadied[0], "Steadied", "named in the statuses table")
	t.ok(b.forecast_basic(me, foe).notes.has("Steadied: immune to stagger"), "the forecast says so")
	b.add_status(foe, "staggered", me)
	t.ok(not foe.statuses.has("staggered"), "immune")
	t.eq(_ev(b, "status_resisted").size(), 1, "the attempt is reported")
	_turn(b, foe)
	b.end_turn()
	t.ok(foe.statuses.has("steadied"), "still steadied after its 1st turn")
	_turn(b, foe)
	b.end_turn()
	t.ok(not foe.statuses.has("steadied"), "gone after its 2nd turn")
	b.add_status(foe, "staggered", me)
	t.ok(foe.statuses.has("staggered"), "can be Staggered again")


func test_blinded_range_and_crit(t) -> void:
	var me := _u("me", "bow", "fire", { "dex": 100 })
	var near := _foe("n")
	var far := _foe("x")
	var b := _fight([me], [near, far], [C], [Vector2i(6, 4), Vector2i(8, 4)])
	_turn(b, me)
	t.eq(b.attack_targets(me).size(), 2, "range 6 sees both")
	b.add_status(me, "blinded", near)
	t.eq(b.attack_targets(me).map(func(u): return u.id), ["n"], "Blinded: only within 2")
	var fc := b.forecast_basic(me, near)
	t.eq(fc.crit.value, 0.0, "can't crit")
	t.ok(_mod(fc, "Blinded").get("stage", "") == "crit_x", "named on the crit line, no hit term")
	for key in ["arcing_shot", "energized_shot"]:
		for h in b.skill_targets(me, key, "fire"):
			t.ok(BWHex.distance(C, h) <= 2, "%s targets within 2" % key)
	# the AI moves in or holds rather than shooting past 2
	var ai := _foe("ai", { "dex": 100 }, "bow")
	var tg := _u("t", "sword", "fire", { "con": 300 })
	var b2 := _fight([tg], [ai], [C], [Vector2i(9, 4)])
	_turn(b2, ai)
	b2.add_status(ai, "blinded", tg)
	BWAI.take_turn(b2)
	for e in _ev(b2, "attack"):
		t.ok(BWHex.distance(ai.pos, tg.pos) <= 2, "a blinded AI shoots only within 2")


func test_pinned(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.add_status(me, "pinned", foe)
	t.eq(me.move_range(), 3, "Pinned: -2 move (sword 5)")
	t.ok(me.move_notes().has(["Pinned", -2]), "named on the Move hover")
	_turn(b, me)
	b.end_turn()
	t.ok(not me.statuses.has("pinned"), "gone after its next turn")
	t.eq(BWSkills.STATUS.pinned[0], "Pinned", "in the statuses table")


# ------------------------------------------------------------------ D95 gale 2

func test_gale_two(t) -> void:
	var b := BWBattle.new(_board(13), 1)
	var g := Vector2i(6, 6)
	b.tiles.apply([g], "wind", "x")
	t.eq(int(b.tiles.at(g).get("gale_level", 1)), 1, "a gale")
	b.tiles.apply([g], "wind", "x")
	t.eq(int(b.tiles.at(g).get("gale_level", 1)), 2, "wind on a gale: gale 2")
	b.tiles.apply([g], "wind", "x")
	t.eq(int(b.tiles.at(g).gale_level), 2, "wind on gale 2: still 2")
	t.eq(int(b.tiles.at(g).timer), BWTiles.MARK_CYCLES, "refreshed")
	var r := b.tiles.apply([g], "fire", "x")
	t.eq(r.gales[0].copies.size(), 18, "fires to rings 1 and 2")
	t.ok(BWHex.area(g, 2).all(func(h): return b.tiles.intensity(h, "fire") == 1), "fire 1 on all 19")
	# same skip rules: a marker in ring 2 stays armed
	var b2 := BWBattle.new(_board(13), 1)
	b2.tiles.apply([g], "wind", "x")
	b2.tiles.apply([g], "wind", "x")
	var m := Vector2i(8, 6)
	b2.tiles.apply([m], "thunder", "x")
	b2.tiles.apply([g], "fire", "x")
	t.eq(str(b2.tiles.at(m).marker), "fuse", "a fuse in ring 2 is skipped")
	var b3 := BWBattle.new(_board(13), 1)
	b3.tiles.apply([g], "wind", "x")
	t.eq(b3.tiles.apply([g], "water", "x").gales[0].copies.size(), 6, "a plain gale: ring 1 only")


# ------------------------------------------------------------------ D96 facing

func test_facing_in_the_hit_formula(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [Vector2i(5, 5)])
	var nb := BWHex.neighbors(foe.pos)
	foe.facing = 0
	var want := { 0: ["Facing the blow", "glance", 10.0], 1: ["Front flank", "glance", 5.0], 5: ["Front flank", "glance", 5.0],
		2: ["Rear flank", "hit", 5.0], 4: ["Rear flank", "hit", 5.0], 3: ["Rear attack", "hit", 15.0] }
	for d in 6:
		var at: Vector2i = nb[d]
		var rel := (BWHex.direction_index(foe.pos, at) - foe.facing + 6) % 6
		var fc := b.forecast_basic(me, foe, 1.0, "", at)
		var m := _mod(fc, want[rel][0])
		t.eq(str(m.get("stage", "")), want[rel][1], "side %d: %s" % [rel, want[rel][0]])
		t.eq(float(m.get("value", 0)), want[rel][2], "side %d: value" % rel)
	foe.facing = -1
	var fc0 := b.forecast_basic(me, foe, 1.0, "", nb[3])
	t.ok(_mod(fc0, "Rear").is_empty() and _mod(fc0, "Facing").is_empty(), "unknown facing: no term")
	# the AI weighs it through the forecasts: it goes round to the back
	var ai := _foe("ai", { "con": 300, "dex": 1 }, "sword")
	var tg := _u("t", "sword", "fire", { "con": 300 })
	var b2 := _fight([tg], [ai], [C], [Vector2i(6, 4)])
	tg.facing = BWHex.direction_index(C, E)          # facing the AI
	_turn(b2, ai)
	var back := Vector2i(-1, -1)
	for n in BWHex.neighbors(C):
		if (BWHex.direction_index(C, n) - tg.facing + 6) % 6 == 3:
			back = n
	var reach := b2.reachable(ai)
	t.ok(reach.has(back) and reach[back].stop, "set-up: the AI can reach the hex behind")
	BWAI.take_turn(b2)
	var rel2 := (BWHex.direction_index(tg.pos, ai.pos) - tg.facing + 6) % 6
	t.eq(rel2, 3, "the AI attacks from directly behind")


# ------------------------------------------------------------------ D97 hooks

class ZoneProbe:
	extends BWSkillDef
	var entered: Array = []
	var answered: Array = []
	func _init() -> void:
		define({ "key": "test_zone_probe", "name": "Probe", "weapon": "lance", "clip": "", "desc": "test",
			"targeting": "self", "needs_element": false, "range": 0, "cd": 1, "power": 0 }, 999)
	func zone(b: BWBattle, u: BWUnit, _p: Dictionary, _h: Vector2i) -> Array:
		return Array(b.board.area(u.pos, 2))
	func on_zone_enter(_b: BWBattle, holder: BWUnit, mover: BWUnit) -> void:
		entered.append([holder.id, mover.id])
	func overwatch(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> int:
		return 3


func test_zone_control(t) -> void:
	var probe := ZoneProbe.new()
	t.ok(BWSkillRegistry.register(probe), "probe registered")
	var me := _u("me", "lance", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [Vector2i(9, 4)])
	me.known_skills.append("test_zone_probe")
	me.skill_loadout["lance"] = ["test_zone_probe"]
	_turn(b, me)
	t.ok(not b.use_skill(me, "test_zone_probe", "", C).is_empty(), "the skill resolves")
	t.eq(me.zone.get("skill", ""), "test_zone_probe", "a zone is held (BWSkillDef.zone)")
	_turn(b, foe)
	var r := b.reachable(foe)
	t.ok(r.has(Vector2i(6, 4)) and r[Vector2i(6, 4)].stop, "the zone's edge can be entered")
	t.ok(not r.has(Vector2i(5, 4)), "but not passed through")
	t.ok(b.move(foe, Vector2i(6, 4)), "moved in")
	t.eq(_ev(b, "zone_stop").size(), 1, "zone_stop emitted")
	t.eq(probe.entered, [["me", "f"]], "on_zone_enter called")
	_turn(b, me)
	t.ok(me.zone.is_empty(), "expires at the holder's next turn")
	t.eq(_ev(b, "zone_end").size(), 1, "zone_end emitted")
	BWSkillRegistry.unregister("test_zone_probe")


func test_overwatch(t) -> void:
	var probe := ZoneProbe.new()
	BWSkillRegistry.register(probe)
	var gun := _u("g", "lance", "fire", { "dex": 100 })      # reach 2
	var mate := _u("m", "sword", "fire", { "con": 300 })
	var foe := _foe("f", { "dex": 100 })
	var b := _fight([gun, mate], [foe], [C, E], [Vector2i(6, 4)])
	gun.known_skills.append("test_zone_probe")
	gun.skill_loadout["lance"] = ["test_zone_probe"]
	_turn(b, gun)
	b.use_skill(gun, "test_zone_probe", "", C)
	t.eq(int(gun.overwatch.get("radius", 0)), 3, "overwatch set (BWSkillDef.overwatch)")
	_turn(b, foe)
	b.attack(foe, mate)
	t.eq(_ev(b, "overwatch").size(), 1, "the first attack on an ally within 3 triggers it")
	var shot := _ev(b, "counter").filter(func(e): return e.get("cause", "") == "overwatch")
	t.eq(shot.size(), 1, "one basic attack")
	t.eq(str(shot[0].target), "f", "at the attacker")
	var i_ow := b.history.find(_ev(b, "overwatch")[0])
	var i_at := b.history.find(_ev(b, "attack")[0])
	t.ok(i_at < i_ow, "after the triggering attack resolves")
	_turn(b, foe)
	b.attack(foe, mate)
	t.eq(_ev(b, "overwatch").size(), 1, "only the first time")
	BWSkillRegistry.unregister("test_zone_probe")


func test_free_placement(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([Vector2i(5, 6)], "fire", "x", 3)
	b.board.set_cell(Vector2i(3, 6), "jagged")
	t.ok(not b.place_unit(foe, Vector2i(3, 6)), "not onto jagged")
	t.ok(not b.place_unit(foe, C), "not onto a unit")
	t.ok(not b.place_unit(foe, Vector2i(20, 20)), "not out of bounds")
	t.ok(b.place_unit(foe, Vector2i(5, 6)), "a free hex")
	t.eq(foe.pos, Vector2i(5, 6), "moved there")
	t.eq(_ev(b, "move")[-1].kind, "place", "a placement move")
	t.ok(_ev(b, "tile_damage").is_empty(), "no crossing damage")
	var d := BWSkillDef.new()
	t.ok(d.place(b, foe, Vector2i(6, 6)), "BWSkillDef.place wraps it")


# ------------------------------------------------------------------ D98 loadout

func test_overcap_mid_fight(t) -> void:
	var me := _u("me", "daggers", "fire")
	BWPicks.auto_resolve(me)
	t.eq(me.loadout("daggers").size(), 3, "a full loadout")
	t.eq(BWUnit.loadout_cap("staff"), 4, "camp cap: staff 4")
	t.eq(BWUnit.loadout_cap("daggers"), 3, "everyone else 3")
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.picks_live = true
	_turn(b, me)
	me.expertise["daggers"] = 10
	var pend := b.pending_picks("player")
	t.eq(pend[0][1].kind, "skill", "a skill pick owed")
	var learn := ""
	for k in 64:                                     # D174: re-salt until a Learn is among the two
		if BWPicks.options(me, pend[0][1]).any(func(o): return o.kind == "learn"):
			break
		me.pick_seed += 1
	for o in BWPicks.options(me, pend[0][1]):
		if o.kind == "learn":
			learn = o.skill
			break
	t.ok(learn != "", "something to learn")
	t.ok(b.apply_pick(me, pend[0][1], "learn:" + learn), "learned mid-fight")
	t.eq(me.overcap, [learn], "over the cap for this battle")
	t.ok(b.skills_for(me).any(func(r): return r.key == learn), "usable immediately")
	t.eq(me.loadout("daggers").size(), 3, "the camp loadout is unchanged")
	foe.hp = 0
	b._check_end()
	t.eq(me.overcap, [], "gone when the battle ends")
	t.ok(learn in me.known("daggers"), "still known")
	t.ok(not me.set_equipped("daggers", learn, true), "camp: equip at the normal cap")


func test_improve_needs_a_plus_rider(t) -> void:
	var u := _u("p", "sword", "fire")
	BWPicks.auto_resolve(u)
	u.expertise["sword"] = 10
	var req := BWPicks.next_request(u)
	var imp := BWPicks.all_options(u, req).filter(func(o): return o.kind == "improve")
	t.ok(not imp.is_empty(), "something improvable")
	for o in imp:
		var row := BWSkills.get_skill(o.skill)
		t.ok(str(row.get("plus", "")) != "", "%s has a plus rider" % o.skill)
		t.eq(o.text, str(row.plus), "the card shows row.plus")
	for c in BWPicks.skill_choices(u, "sword"):
		if str(c).begins_with("improve:"):
			t.ok(BWPicks.improvable(str(c).trim_prefix("improve:")), "%s offered only with a rider" % c)
	var no_plus := BWSkillRegistry.keys().filter(func(k): return not BWPicks.improvable(k) and not BWSkills.get_skill(k).get("follow_up_only", false))
	if not no_plus.is_empty():
		var k: String = no_plus[0]
		var wc := str(BWSkills.get_skill(k).weapon)
		var v := _u("q", wc, "fire")
		v.known_skills.append(k)
		t.ok(not ("improve:" + k) in BWPicks.skill_choices(v, wc), "%s (no plus) is never offered" % k)


# ------------------------------------------------------------------ D99 enemy scaling

func test_enemy_scaling(t) -> void:
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 1234)
	t.eq(BWRun.enemy_stage(1), 1, "floored at fight 1")
	t.eq(BWRun.enemy_stage(5), 3, "fight 5 uses fight 3 (D133: two behind for 3-5)")
	t.eq(BWRun.enemy_stage(7), 6, "fight 7 uses fight 6 (one behind for 6-8)")
	t.eq(BWRun.enemy_stage(9), 9, "fight 9 is level with you")
	# fight: [tier, level, expertise rank]; D194: an enemy's level is its stage
	# (D256: fight 7 is the Twins; D327: 8 and 10 are 6v6 modes, so fight 6 stands in for "one behind")
	var want := { 1: ["E", 1, 0], 5: ["D", 3, 1], 6: ["C", 5, 2], 9: ["A", 9, 4] }
	for n in want:
		var es := run.enemies_for(n)
		for u in es:
			t.eq(u.equipment.main_hand.tier, want[n][0], "fight %d: tier %s" % [n, want[n][0]])
			t.eq(u.level, want[n][1], "fight %d: level %d" % [n, want[n][1]])
			t.eq(u.expertise_rank(u.weapon_class), want[n][2], "fight %d: expertise from the stage" % n)
			if BWRun.enemy_curve(n).perks:
				t.eq(BWPicks.pending(u), [], "fight %d: every pick made" % n)
			t.eq(int(u.skill_picks.get(u.weapon_class, 0)), want[n][2], "fight %d: one skill pick per letter" % n)
			t.ok(run.can_equip(u, u.equipment.main_hand), "fight %d: the weapon is legal for it" % n)
		t.eq(es.map(func(u): return u.perks), run.enemies_for(n).map(func(u): return u.perks), "deterministic")
	t.ok(run.enemies_for(9)[0].perks.size() >= 2, "fight 9 (tier A): affinity rank 3, two perks (D277 ladder)")


## D133: the curve is data; fights 1-2 are gentle (no perks, 90% base stats).
func test_enemy_curve(t) -> void:
	t.eq(BWRun.ENEMY_CURVE.size(), BWRun.FIGHTS, "one row per fight (the Giant is off the curve)")
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 1234)
	for n in [1, 2]:
		var c := BWRun.enemy_curve(n)
		t.ok(not c.perks, "fight %d: no perks" % n)
		for u in run.enemies_for(n):
			t.eq(u.perks, [], "fight %d: %s has no perks" % [n, u.name])
			var row := BWData.row("roster", u.id.split("_f")[0])
			var base := 0
			var now := 0
			for k in BWUnit.STATS:
				base += int(row[k])
				now += int(u.stats[k])
			if u.level == 1:
				t.eq(now, roundi(base * c.mult), "fight %d: %s's base stats total x%.2f" % [n, u.name, c.mult])
			else:                        # D194: levelled first (its stage), then scaled
				t.ok(now >= roundi(base * c.mult), "fight %d: %s levelled, then x%.2f" % [n, u.name, c.mult])
			t.eq(u.hp, u.max_hp(), "HP follows CON")
	t.ok(BWRun.enemy_curve(1).mult < 1.0, "fight 1: below full strength")
	# D139: armour 0 / 1 / 2 / full by fight, at the stage's tier
	for n in [1, 2, 3, 4, 6, 9]:               # D327: fight 10 is a 6v6 mode (its own build)
		var want := mini(n - 1, 3)
		t.eq(BWRun.enemy_curve(n).armor, want, "fight %d: %d armour pieces" % [n, want])
		for e in run.enemies_for(n):
			var worn := BWRun.ARMOR_SLOTS.filter(func(s): return e.equipment.has(s))
			t.eq(worn.size(), want, "fight %d: %s wears %d" % [n, e.name, want])
			for s in worn:
				t.eq(str(e.equipment[s].tier), str(e.equipment.main_hand.tier), "fight %d: %s at the stage tier" % [n, s])
				t.eq(str(BWData.row("equipment", e.equipment[s].base).slot), s, "the base fits the slot")
	for u in run.enemies_for(3):
		t.ok(u.perks.size() >= 1, "fight 3: perks are back")
	var u := BWUnit.from_roster({ "id": "x", "con": 6, "str": 6, "dex": 2, "wil": 1, "def": 6, "res": 3, "spd": 2 })
	BWRun.scale_stats(u, 0.9)
	t.eq(u.stats, { "con": 5, "str": 5, "dex": 2, "wil": 1, "def": 5, "res": 3, "spd": 2 }, "26 x 0.9 = 23: off the three best")
	BWRun.scale_stats(u, 0.1)
	t.ok(BWUnit.STATS.all(func(k): return int(u.stats[k]) >= 1), "never below 1")

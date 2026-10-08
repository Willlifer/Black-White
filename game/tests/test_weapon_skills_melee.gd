extends RefCounted
## D103 (sword) and D104 (axe): the new weapon skills and their Improve
## riders. Every new skill is previewed and resolved.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)          # C's east neighbour (cube direction 0)


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


func _foe(id: String = "f", extra: Dictionary = {}) -> BWUnit:
	var x := { "con": 300 }
	x.merge(extra, true)
	return _u(id, "axe", "water", x)


## Equip `keys` (learned) for the unit's weapon.
func _equip(u: BWUnit, keys: Array) -> BWUnit:
	for k in keys:
		if not k in u.known_skills:
			u.known_skills.append(k)
	u.skill_loadout[u.weapon_class] = keys
	return u


func _fight(me: BWUnit, foes: Array, at: Array, seed_value: int = 7, mates: Array = [], mate_at: Array = []) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me] + mates, foes)
	me.pos = C
	for i in mates.size():
		mates[i].pos = mate_at[i]
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _mod(fc: Dictionary, label_start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(label_start):
			return m
	return {}


func _line(n: int) -> Array:
	return Array(BWHex.ray(C, E, n))


## Preview then resolve; both must be legal.
func _use(t, b: BWBattle, u: BWUnit, key: String, el: String, h: Vector2i) -> Dictionary:
	var pv := b.skill_preview(u, key, el, h)
	t.ok(not pv.is_empty(), "%s: a legal preview" % key)
	var ev := b.use_skill(u, key, el, h)
	t.ok(not ev.is_empty(), "%s: resolves" % key)
	return ev


# ------------------------------------------------------------------ registry

func test_new_skills_join_their_pools(t) -> void:
	var want := {
		"sword": ["thread_needle", "tapestry", "whirlwind_blade", "lunge", "en_passant"],   # D426, D438, D439
		"axe": ["reckless_arc", "hook", "sunder", "earthsplitter", "bellow"],               # D435-D437
		"lance": ["sweep", "set_spear", "phalanx", "dragoon_dive", "lance_charge"],   # D428; D442: no Guardrush
		"bow": ["split_arrow", "retreating_shot", "pinning_shot", "rain_of_arrows"],  # D442: no Aimed Shot
		"staff": ["bolt", "transfer", "inversion", "tempest"],                         # D442: no Aegis
		"daggers": ["tumble", "manipulate", "kindle", "fan_of_knives", "overload"],   # D440, D441
		"pistols": ["point_blank", "pistol_whip", "flash_round", "covering_fire", "empty_the_chamber"],
		"fists": ["shockwave_palm", "brace", "grapple_throw", "haymaker", "hundred_fists"],
	}
	for wc in want:
		var pool := BWSkillRegistry.pool(wc)
		for k in want[wc]:
			t.ok(k in pool, "%s learnable by %s" % [k, wc])
			var r := BWSkills.get_skill(k)
			t.ok(str(r.get("desc", "")).length() > 20, "%s has a codex description" % k)
			t.ok(not k in BWSkillRegistry.starter(wc), "%s is learned, not a starter" % k)
	for k in ["tapestry", "dragoon_dive", "rain_of_arrows", "tempest", "empty_the_chamber", "hundred_fists"]:
		t.ok(BWSkills.get_skill(k).get("once_per_battle", false), "%s is once per battle" % k)
	t.eq(BWSkillRegistry.clip("whirlwind_blade"), "spin", "Whirlwind Blade spins")
	t.eq(BWSkillRegistry.clip("fan_of_knives"), "spin", "Fan of Knives spins")
	t.eq(BWSkillRegistry.clip("pistol_whip"), "pistol_whip", "Pistol Whip has its clip")


# ------------------------------------------------------------------ sword

func test_whirlwind_blade_hits_the_ring_not_allies(t) -> void:
	var me := _equip(_u("me", "sword", "wind"), ["whirlwind_blade"])
	var a := _foe("a")
	var c := _foe("c")
	var mate := _u("m", "sword", "fire")
	var nb := BWHex.neighbors(C)
	var b := _fight(me, [a, c], [nb[0], nb[3]], 7, [mate], [nb[1]])
	var pv := b.skill_preview(me, "whirlwind_blade", "wind", C)
	t.eq(pv.units.size(), 2, "both foes on the ring, not the ally")
	t.ok(BWSkillRegistry.get_def("whirlwind_blade").ai_considers(BWSkills.get_skill("whirlwind_blade")), "the AI weighs it")
	_use(t, b, me, "whirlwind_blade", "wind", C)
	t.eq(_events(b, "paint")[0].element, "wind", "the chosen element paints the ring")
	t.eq(me.cooldowns.get("whirlwind_blade_wind", 0), 3, "cd 3")


func test_lunge_dashes_to_the_first_foe(t) -> void:
	var me := _equip(_u("me", "sword", "fire"), ["lunge"])
	var foe := _foe()
	var line := _line(3)
	var b := _fight(me, [foe], [line[2]])
	var pv := b.skill_preview(me, "lunge", "fire", E)
	t.eq(pv.dest, line[1], "stops beside the foe")
	t.eq(pv.units, ["f"], "the foe takes the hit")
	_use(t, b, me, "lunge", "fire", E)
	t.eq(me.pos, line[1], "dashed 2")
	# an ally in the way: no lunge that heading
	var me2 := _equip(_u("me", "sword", "fire"), ["lunge"])
	var mate := _u("m", "sword", "fire")
	var b2 := _fight(me2, [_foe()], [line[2]], 7, [mate], [line[0]])
	t.eq(b2.skill_preview(me2, "lunge", "fire", E), {}, "an ally just stops you: nothing to lunge at")


## D426: Elemental Truth is retired (never offered; En Passant took its
## place). Its rules still resolve for an old replay (test_kit2 covers the
## save migration).
func test_elemental_truth_retired(t) -> void:
	t.ok(not "elemental_truth" in BWSkillRegistry.pool("sword"), "never offered")
	t.ok(BWSkillRegistry.has("elemental_truth"), "the def stays for old saves")


func test_riposte_plus_answers_two_blows(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	me.skill_ranks["riposte"] = 2
	var a := _foe("a", { "dex": 100 })
	var c := _foe("c", { "dex": 100 })
	var nb := BWHex.neighbors(C)
	var b := _fight(me, [a, c], [nb[0], nb[3]])
	t.ok(b.skill_preview(me, "riposte", "fire", C).notes.any(func(n): return str(n).begins_with("Riposte+")), "named")
	b.use_skill(me, "riposte", "fire", C)
	_give_turn(b, a)
	b.attack(a, me)
	_give_turn(b, c)
	var fc := b.forecast_basic(c, me)
	t.ok(fc.get("guarded", false), "the guard is back up for the second blow")
	b.attack(c, me)
	t.eq(_events(b, "riposte").size(), 2, "two answers")
	_give_turn(b, a)
	t.ok(not b.forecast_basic(a, me).get("guarded", false), "only two")


func test_striketwice_plus_third_cut(t) -> void:
	var landed := 0
	for sd in 6:
		var me := _u("me", "sword", "fire", { "dex": 100 })
		me.skill_ranks["striketwice"] = 2
		var a := _foe("a")
		var c := _foe("c", { "con": 200 })
		var nb := BWHex.neighbors(C)
		var b := _fight(me, [a, c], [nb[0], nb[2]], 20 + sd)
		b.use_skill(me, "striketwice", "fire", nb[0])
		var pv := b.skill_preview(me, "striketwice_second", "fire", nb[0])
		t.ok(pv.notes.any(func(n): return str(n).begins_with("Striketwice+")), "the forecast names the third cut")
		var ev := b.use_skill(me, "striketwice_second", "fire", nb[0])
		var third := _events(b, "attack").filter(func(e): return e.get("pattern", "") == "third_cut")
		t.eq(third.size(), 1 if ev.results[0].result.hit else 0, "a third cut iff both landed (seed %d)" % sd)
		if not third.is_empty():
			landed += 1
			t.eq(third[0].target, "c", "to the weakest adjacent foe")
	t.ok(landed > 0, "the third cut happened")


# ------------------------------------------------------------------ axe

func test_hook_pulls_adjacent(t) -> void:
	var pulled := 0
	for sd in 6:
		var me := _equip(_u("me", "axe", "fire"), ["hook"])
		var foe := _foe("f", { "res": 0 })
		var line := _line(3)
		var b := _fight(me, [foe], [line[2]], 30 + sd)
		var pv := b.skill_preview(me, "hook", "fire", line[2])
		t.ok(pv.notes.any(func(n): return str(n).begins_with("Pull")), "the pull is in the forecast")
		var ev := _use(t, b, me, "hook", "fire", line[2])
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.pos == E, sec, "hauled next to you iff the secondary landed")
		if sec:
			pulled += 1
	t.ok(pulled > 0, "pulled at least once")


func test_sunder_ignores_def_and_cant_glance(t) -> void:
	var me := _equip(_u("me", "axe", "fire"), ["sunder"])
	var b := _fight(me, [_foe("f", { "def": 20 })], [E])
	var fc: Dictionary = b.skill_preview(me, "sunder", "fire", E).forecasts["f"]
	t.eq(fc.glance.value, 0.0, "can't glance")
	t.near(float(_mod(fc, "Sunder (30%)").get("value", 0)), 0.3, 0.001, "30% of DEF ignored")
	t.ok(str(fc.damage.formula).contains("DEF ×"), "the damage formula shows the ignored DEF")
	_use(t, b, me, "sunder", "fire", E)


func test_earthsplitter_line(t) -> void:
	var me := _equip(_u("me", "axe", "fire"), ["earthsplitter"])
	var line := _line(3)
	var b := _fight(me, [_foe("a"), _foe("c")], [line[0], line[2]])
	var pv := b.skill_preview(me, "earthsplitter", "fire", E)
	t.eq(pv.hexes, line, "3 hexes ahead")
	t.eq(pv.units.size(), 2, "both foes on the line")
	var ev := _use(t, b, me, "earthsplitter", "fire", E)
	t.ok(not line.any(func(h): return b.tiles.carries(h, "fire")), "D416: the line is not painted (Sunder's is)")
	for r in ev.results:
		var v: BWUnit = b._unit(str(r.target))
		var was: Vector2i = line[0] if r.target == "a" else line[2]
		var back: Vector2i = BWHex.neighbors(was)[0]
		t.eq(v.pos, back if r.result.secondary else was, "%s heaved 1 back iff the secondary landed" % r.target)


func test_cleave_plus(t) -> void:
	var me := _u("me", "axe", "fire")
	me.skill_ranks["cleave"] = 2
	var nb := BWHex.neighbors(C)
	var b := _fight(me, [_foe("a"), _foe("c")], [nb[0], nb[1]])
	var fc: Dictionary = b.skill_preview(me, "cleave", "fire", nb[0]).forecasts["a"]
	t.near(float(_mod(fc, "Cleave+").get("value", 0)), 1.15, 0.001, "+15% per extra foe")


func test_charge_plus(t) -> void:
	var me := _u("me", "axe", "fire")
	me.skill_ranks["charge"] = 2
	var b := BWBattle.new(_board(15), 7)
	var f := _foe()
	b.setup([me], [f])
	me.pos = C
	f.pos = Vector2i(14, 14)
	_give_turn(b, me)
	var pv := b.skill_preview(me, "charge", "fire", E)
	t.eq(pv.dest, _line(8)[7], "reach 8 (D414)")
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Charge+")), "named")
	var me2 := _u("me", "axe", "fire")
	me2.skill_ranks["charge"] = 2
	var line := _line(3)
	var x := _foe("x")
	var y := _foe("y")
	var b2 := _fight(me2, [x, y], [line[1], line[2]])
	b2.use_skill(me2, "charge", "fire", E)
	var slams := _events(b2, "tile_damage").filter(func(e): return e.cause == "slam")
	t.eq(slams.size(), 2, "the caught foe slams into the next")
	t.eq(int(slams[0].amount), BWTiles.tile_damage(x, 12, ""), "slam 12%")


# ------------------------------------------------------------------ D414-D416: the axe pass

func _fight_big(me: BWUnit, foes: Array, at: Array, n: int = 15) -> BWBattle:
	var b := BWBattle.new(_board(n), 7)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func test_charge_seven_pushes_along(t) -> void:
	var line := _line(9)
	var me := _u("me", "axe", "fire")
	var f := _foe("f")
	var b := _fight_big(me, [f], [line[1]])
	var pv := b.skill_preview(me, "charge", "fire", E)
	t.eq(pv.dest, line[6], "D414: the run is 7")
	t.eq(pv.shove.to, line[7], "the caught foe is pushed along, ending just ahead of the runner")
	b.use_skill(me, "charge", "fire", E)
	t.eq(me.pos, line[6], "charged 7")
	t.eq(f.pos, line[7], "pushed 6")
	var sh: Array = _events(b, "move").filter(func(e): return e.kind == "shove")
	t.eq(sh.size(), 1, "one shove move")
	t.eq(sh[0].path, line.slice(1, 8), "its path is every hex it was pushed along")
	t.eq(_events(b, "slam").size(), 0, "no slam when the run just ends")
	# rock partway: it is pushed up to the rock and slams there; the run stops behind it
	var me2 := _u("me", "axe", "fire")
	var f2 := _foe("f")
	var b2 := _fight_big(me2, [f2], [line[1]])
	b2.board.set_cell(line[4], "jagged")
	var pv2 := b2.skill_preview(me2, "charge", "fire", E)
	t.ok(pv2.notes.any(func(n): return str(n).begins_with("Slam: f")), "the preview names the slam on the stop")
	b2.use_skill(me2, "charge", "fire", E)
	t.eq(f2.pos, line[3], "pushed to the rock")
	t.eq(me2.pos, line[2], "the run stops behind it")
	var sl := _events(b2, "tile_damage").filter(func(e): return e.cause == "slam")
	t.eq(sl.map(func(e): return e.unit), ["f"], "it slams the rock on the stop")
	# a second unit down the line: both slam
	var me3 := _u("me", "axe", "fire")
	var f3 := _foe("f")
	var g3 := _foe("g")
	var b3 := _fight_big(me3, [f3, g3], [line[1], line[5]])
	b3.use_skill(me3, "charge", "fire", E)
	t.eq(f3.pos, line[4], "pushed up to the unit")
	t.eq(me3.pos, line[3], "the run stops behind it")
	t.eq(g3.pos, line[5], "the one it hits stays")
	var sl3 := _events(b3, "tile_damage").filter(func(e): return e.cause == "slam")
	t.eq(sl3.map(func(e): return e.unit), ["f", "g"], "both slam")
	# the map's edge: it just stops there (open air, no slam)
	var me4 := _u("me", "axe", "fire")
	var f4 := _foe("f")
	var b4 := _fight(me4, [f4], [line[1]])           # 11 wide: the edge is 6 out
	b4.use_skill(me4, "charge", "fire", E)
	t.eq(f4.pos, line[5], "pushed to the edge")
	t.eq(me4.pos, line[4], "the run stops behind it")
	t.eq(_events(b4, "slam").size(), 0, "the edge is open air")


func test_ai_charges_into_reach(t) -> void:
	var line := _line(9)
	var axe := _equip(_u("axe", "axe", "fire"), ["charge"])
	var foe := _u("p", "sword", "water", { "con": 300 })
	var b := BWBattle.new(_board(15), 7)
	b.setup([foe], [axe])
	axe.pos = C
	foe.pos = line[7]                       # 8 out: a move (4) leaves it 4 away, out of a swing
	_give_turn(b, axe)
	BWAI.take_turn(b)
	var used := _events(b, "skill").map(func(e): return e.skill)
	t.ok("charge" in used, "the AI charges to reach the foe (%s)" % [used])
	t.ok(_events(b, "attack").any(func(e): return e.unit == "axe"), "and swings on the follow-up")


func test_sunder_fissure(t) -> void:
	var line := _line(6)
	var me := _equip(_u("me", "axe", "fire"), ["sunder"])
	var f := _foe("f", { "def": 20 })
	var g := _foe("g", { "def": 20 })
	var h := _foe("h", { "def": 20 })
	var b := _fight(me, [f, g, h], [line[0], line[2], line[4]])
	var pv := b.skill_preview(me, "sunder", "fire", E)
	t.eq(pv.hexes, line.slice(0, 5), "D415: the fissure runs from you through the target, 5 hexes")
	t.eq(pv.units, ["f", "g", "h"], "the target and every foe on the line")
	var ff: Dictionary = pv.forecasts["f"]
	var fg: Dictionary = pv.forecasts["g"]
	t.near(float(_mod(ff, "Sunder (30%)").get("value", 0)), 0.3, 0.001, "the blow ignores 30% DEF")
	t.eq(_mod(fg, "Sunder (30%)"), {}, "the fissure's graze doesn't")
	t.eq(fg.glance.value > 0.0, true, "and can glance")
	t.near(float(_mod(fg, "Sunder fissure").get("value", 0)), 0.6, 0.001, "60% power on the line")
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Fissure: 5")), "the preview names the fissure")
	var ev := _use(t, b, me, "sunder", "fire", E)
	t.eq(ev.results.size(), 3, "three blows")
	t.ok(line.slice(0, 5).all(func(x): return b.tiles.carries(x, "fire")), "every hex of the line takes the element")
	t.ok(not b.tiles.carries(line[5], "fire"), "and no further")
	# rock stops the split
	var me2 := _equip(_u("me", "axe", "fire"), ["sunder"])
	var b2 := _fight(me2, [_foe("f"), _foe("h")], [line[0], line[4]])
	b2.board.set_cell(line[3], "jagged")
	var pv2 := b2.skill_preview(me2, "sunder", "fire", E)
	t.eq(pv2.hexes, line.slice(0, 3), "rock stops the fissure")
	t.eq(pv2.units, ["f"], "the foe past the rock is safe")
	b2.use_skill(me2, "sunder", "fire", E)
	t.ok(not b2.tiles.carries(line[4], "fire"), "nothing painted past the rock")


## D435-D442: the retired skills' tests moved to test_kit3 (their replacements; the defs stay only for old saves).

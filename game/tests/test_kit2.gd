extends RefCounted
## D425-D432, weapon kit pass 2 (design/SKILLS.md): Riposte's release, En
## Passant (and Elemental Truth's retirement), Blade Dance, Lance Charge,
## Daggerleap's hit and run, Consume's barrier, Fan of Knives radius 2 with
## its reaction shield. Helpers come from test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _rock(b: BWBattle, h: Vector2i) -> void:
	b.board.set_cell(h, BWBoard.JAGGED, 0)


# ------------------------------------------------------------------ Riposte (D425)

func test_riposte_releases_when_unanswered(t) -> void:
	var me: BWUnit = K._u("me", "sword", "fire")
	var foe: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [foe], [Vector2i(9, 9)])
	var pv := b.skill_preview(me, "riposte", "fire", C)
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Unanswered by your next turn")), "the guard previews its release")
	b.use_skill(me, "riposte", "fire", C)
	K._give_turn(b, foe)
	K._give_turn(b, me)
	var rel := _ev(b, "riposte_release")
	t.eq(rel.size(), 1, "released at the next turn start")
	t.eq((rel[0].hexes as Array).size(), 18, "six lines of 3 on open ground")
	for n in BWHex.neighbors(C):
		for h in BWHex.ray(C, n, 3):
			t.eq(b.tiles.intensity(h, "fire"), 1, "line hex %s painted" % h)
	t.ok(me.riposte.is_empty(), "the guard is down")
	# rock stops a line
	var me2: BWUnit = K._u("me", "sword", "water")
	var b2: BWBattle = K._fight(me2, [K._foe("f")], [Vector2i(9, 9)])
	_rock(b2, E)
	var d = BWSkillRegistry.get_def("riposte")
	t.eq((d.release_hexes(b2, me2) as Array).size(), 15, "rock right beside: that line is empty")


func test_riposte_answered_does_not_release(t) -> void:
	var me: BWUnit = K._u("me", "sword", "fire")
	var foe: BWUnit = K._foe("f", { "dex": 100 })
	var b: BWBattle = K._fight(me, [foe], [E])
	b.use_skill(me, "riposte", "fire", C)
	K._give_turn(b, foe)
	b.attack(foe, me)
	t.eq(_ev(b, "riposte").size(), 1, "answered")
	K._give_turn(b, me)
	t.eq(_ev(b, "riposte_release").size(), 0, "an answered guard never releases")


# ------------------------------------------------------------------ En Passant (D426)

func test_en_passant_dashes_through(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "sword", "fire"), ["en_passant"])
	var line: Array = K._line(4)
	var foe: BWUnit = K._foe("f")
	var side: BWUnit = K._foe("s")
	var land: Vector2i = line[2]
	var nb := BWHex.neighbors(land)
	var b: BWBattle = K._fight(me, [foe, side], [line[1], nb[1]])
	t.ok(line[1] in b.skill_targets(me, "en_passant", "fire"), "a foe 2 away in a line is a target")
	var pv := b.skill_preview(me, "en_passant", "fire", line[1])
	t.eq(pv.dest, land, "lands on the hex beyond")
	t.eq(pv.units, ["f"], "strikes the foe it passes")
	t.eq(pv.follow_up, ["en_passant_strike"], "grants the Passing Cut")
	K._use(t, b, me, "en_passant", "fire", line[1])
	t.eq(me.pos, land, "dashed through")
	for h in [line[0], line[1], land]:
		t.ok(b.tiles.carries(h, "fire"), "travelled hex %s takes the element" % h)
	t.eq(me.follow_up, ["en_passant_strike"], "the Passing Cut is offered")
	t.eq(me.cooldowns.get("en_passant_fire", 0), 3, "cd 3")
	t.ok(b.skill_targets(me, "en_passant_strike", "water").is_empty(), "the cut is in the dash's element only")
	var cut := b.skill_targets(me, "en_passant_strike", "fire")
	t.ok(side.pos in cut, "any adjacent foe")
	var ev := b.use_skill(me, "en_passant_strike", "fire", side.pos)
	t.ok(not ev.is_empty(), "the second elemental strike resolves")
	t.ok(b.tiles.carries(side.pos, "fire"), "its hex takes the element")
	t.ok(me.follow_up.is_empty(), "spent")


func test_en_passant_blocked_landing(t) -> void:
	var line: Array = K._line(4)
	var me: BWUnit = K._equip(K._u("me", "sword", "fire"), ["en_passant"])
	var foe: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [foe], [line[1]])
	_rock(b, line[2])
	t.ok(not line[1] in b.skill_targets(me, "en_passant", "fire"), "rock beyond: not a target")
	var bl: Dictionary = BWSkillRegistry.get_def("en_passant").blocked(b, me, line[1])
	t.eq(str(bl.get("why", "")), "landing", "the aim says why (shown red)")
	t.eq(bl.get("hex", Vector2i.ZERO), line[2], "on the blocked landing")
	var me2: BWUnit = K._equip(K._u("me", "sword", "fire"), ["en_passant"])
	var b2: BWBattle = K._fight(me2, [K._foe("f"), K._foe("g")], [line[1], line[2]])
	t.ok(not line[1] in b2.skill_targets(me2, "en_passant", "fire"), "a unit on the landing: not a target")
	t.eq(b2.skill_preview(me2, "en_passant", "fire", line[1]), {}, "no preview")


func test_elemental_truth_migrates(t) -> void:
	var u: BWUnit = K._u("me", "sword", "fire")
	u.known_skills = ["elemental_truth", "lunge"]
	u.skill_ranks = { "elemental_truth": 2 }
	u.skill_loadout = { "sword": ["striketwice", "elemental_truth"] }
	t.ok(BWSkillRegistry.migrate_unit(u), "an old save's unit changes")
	t.ok("en_passant" in u.known_skills and not "elemental_truth" in u.known_skills, "known")
	t.eq(int(u.skill_ranks.get("en_passant", 1)), 2, "its Improve carries over")
	t.eq(u.skill_loadout.sword, ["striketwice", "en_passant"], "equipped in its slot")
	t.ok("en_passant" in u.loadout("sword"), "and it fights with it")


# ------------------------------------------------------------------ Blade Dance (D427)

func test_blade_dance_step(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "sword", "fire", { "dex": 100 }), ["lunge"])
	me.known_skills.append(BWKit2.BLADE_DANCE)
	var foe: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [foe], [E])
	t.ok(BWKit2.BLADE_DANCE in BWWeaponMove.passives_of("sword"), "the sword's pickable passive")
	var ev := K._use(t, b, me, "lunge", "fire", E) as Dictionary
	t.ok(ev.results[0].result.hit, "the cut lands")
	t.ok(BWKit2.dance_pending(b, me), "a step is owed")
	t.eq(_ev(b, "blade_dance").size(), 1, "announced")
	var hexes := BWKit2.dance_hexes(b, me)
	t.ok(not E in hexes and hexes.size() == 16, "free hexes within 2 (author: 2, not 1); not the foe's, nor the one straight behind it (no path past a unit) (%d)" % hexes.size())
	var to: Vector2i = BWHex.ray(C, BWHex.neighbors(C)[3], 2)[1]
	t.ok(to in hexes, "two hexes away is a step")
	t.ok(not BWKit2.dance_step(b, me, Vector2i(9, 9)), "only within 2")
	t.ok(BWKit2.dance_step(b, me, to), "steps")
	t.eq(me.pos, to, "moved 2")
	t.ok(not me.moved and b.can_move(me), "the turn's move is still there")
	t.ok(not BWKit2.dance_pending(b, me), "spent")
	# skip, and no passive: no step
	var me2: BWUnit = K._equip(K._u("me", "sword", "fire", { "dex": 100 }), ["lunge"])
	me2.known_skills.append(BWKit2.BLADE_DANCE)
	var b2: BWBattle = K._fight(me2, [K._foe("f")], [E])
	b2.use_skill(me2, "lunge", "fire", E)
	BWKit2.dance_skip(b2, me2)
	t.ok(not BWKit2.dance_pending(b2, me2) and me2.pos == C, "skipped")
	var me3: BWUnit = K._equip(K._u("me", "sword", "fire", { "dex": 100 }), ["lunge"])
	var b3: BWBattle = K._fight(me3, [K._foe("f")], [E])
	b3.use_skill(me3, "lunge", "fire", E)
	t.ok(not BWKit2.dance_pending(b3, me3), "no passive, no dance")


func test_blade_dance_ai_steps_or_skips(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "sword", "fire", { "dex": 100 }), ["lunge"])
	me.known_skills.append(BWKit2.BLADE_DANCE)
	var b: BWBattle = K._fight(me, [K._foe("f")], [E])
	b.use_skill(me, "lunge", "fire", E)
	BWKit2.ai_dance(b, me)
	t.ok(not BWKit2.dance_pending(b, me), "the AI settles it (a step or a skip)")


# ------------------------------------------------------------------ Lance Charge (D428)

func _lancer() -> BWUnit:
	return K._equip(K._u("me", "lance", "fire"), ["lance_charge"])


func test_lance_charge_cast_then_pierce(t) -> void:
	var me := _lancer()
	var line: Array = K._line(6)
	var a: BWUnit = K._foe("a")
	var c: BWUnit = K._foe("c")
	var b: BWBattle = K._fight(me, [a, c], [Vector2i(9, 9), Vector2i(9, 8)])
	t.ok(line[5] in b.skill_targets(me, "lance_charge", "fire"), "6 away in a line")
	t.ok(not line[0] in b.skill_targets(me, "lance_charge", "fire"), "not a 1-hex step")
	var ev := K._use(t, b, me, "lance_charge", "fire", line[5]) as Dictionary
	t.ok((ev.results as Array).is_empty(), "the cast strikes nobody")
	t.eq((me.fx.lance_charge.line as Array).size(), 6, "the line is set")
	t.eq(_ev(b, "lance_charge_set").size(), 1, "telegraphed")
	t.eq(me.cooldowns.get("lance_charge_fire", 0), 4, "cd 4")
	t.ok(BWKit2.ai_avoid(b, a, line[2]) > 0.0 and BWKit2.ai_avoid(b, a, Vector2i(9, 9)) == 0.0, "the AI sees the line")
	t.ok(BWKit2.charge_lines(b, "enemy").has("me"), "shown to the other side")
	# the foes step onto it anyway; the next turn it runs
	a.pos = line[1]
	c.pos = line[3]
	K._give_turn(b, me)
	var hits := _ev(b, "attack").filter(func(e): return str(e.get("skill", "")) == "lance_charge")
	t.eq(hits.map(func(e): return e.target), ["a", "c"], "each foe on the line is struck, in order")
	t.eq(me.pos, line[5], "pierced through both to the end")
	for h in line:
		t.ok(b.tiles.carries(h, "fire"), "trail on %s" % h)
	t.ok(not me.fx.has("lance_charge"), "spent")
	t.ok(not me.acted and not me.moved and b.can_move(me), "then a whole turn: move and action")


func test_lance_charge_slam_and_block(t) -> void:
	var line: Array = K._line(6)
	var me := _lancer()
	var a: BWUnit = K._foe("a")
	var b: BWBattle = K._fight(me, [a], [Vector2i(9, 9)])
	b.use_skill(me, "lance_charge", "fire", line[5])
	a.pos = line[2]
	_rock(b, line[3])
	K._give_turn(b, me)
	t.eq(me.pos, line[1], "rock beyond the foe: stops in front of it")
	t.eq(_ev(b, "slam").size(), 1, "and it slams into the rock")
	t.ok(_ev(b, "attack").any(func(e): return str(e.get("skill", "")) == "lance_charge"), "struck first")
	# an ally in the way just stops it
	var me2 := _lancer()
	var mate: BWUnit = K._u("m", "sword", "water")
	var b2: BWBattle = K._fight(me2, [K._foe("f")], [Vector2i(9, 9)], 7, [mate], [Vector2i(0, 9)])
	b2.use_skill(me2, "lance_charge", "fire", line[5])
	mate.pos = line[2]
	K._give_turn(b2, me2)
	t.eq(me2.pos, line[1], "an ally in the way: stops there")


func test_lance_charge_ai_sets_a_line(t) -> void:
	var me := _lancer()
	var line: Array = K._line(6)
	var b: BWBattle = K._fight(me, [K._foe("a")], [line[5]])
	var row: Dictionary = b.skills_for(me).filter(func(r): return r.key == "lance_charge")[0]
	var s: Dictionary = BWSkillRegistry.get_def("lance_charge").ai_support(b, me, row)
	t.ok(not s.is_empty() and float(s.score) > 0.0, "a foe on a line: worth setting")
	t.ok(s.target in b.skill_targets(me, "lance_charge", str(s.element)), "a legal target")


# ------------------------------------------------------------------ Daggers (D429, D430)

func test_daggerleap_hit_and_run(t) -> void:
	var me: BWUnit = K._u("me", "daggers", "fire", { "dex": 100 })
	var foe: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [foe], [Vector2i(7, 4)])
	var land := Vector2i(6, 4)
	var back := Vector2i(6, 6)
	var d = BWSkillRegistry.get_def("daggerleap")
	t.eq(str(BWSkills.get_skill("daggerleap").get("second_pick", "")), "hex", "asks where to leap away")
	var secs: Array = d.second_targets(b, me, "fire", land)
	t.ok(back in secs and land in secs and not foe.pos in secs, "within 2 of the landing (staying counts), free hexes only")
	var pv := b.skill_preview(me, "daggerleap", "fire", land, back)
	t.eq(pv.units, ["f"], "the flourish strikes")
	var ev := b.use_skill(me, "daggerleap", "fire", land, back)
	t.ok(not ev.is_empty() and ev.results.size() == 1, "struck")
	t.eq(me.pos, back, "then leapt away")
	var moves := _ev(b, "move").filter(func(e): return e.unit == "me")
	t.eq(moves.size(), 2, "two leaps")
	t.eq(moves[-1].path, [land, back], "the leap away")
	# automatic (the AI): a legal hex
	var me2: BWUnit = K._u("me", "daggers", "fire")
	var b2: BWBattle = K._fight(me2, [K._foe("f")], [Vector2i(7, 4)])
	b2.use_skill(me2, "daggerleap", "fire", land)
	t.ok(BWHex.distance(me2.pos, land) <= 2, "automatic leap away stays within 2")


func test_consume_barrier(t) -> void:
	var me: BWUnit = K._u("me", "daggers", "fire")
	var foe: BWUnit = K._foe("f", { "dex": 100, "str": 10 })
	var b: BWBattle = K._fight(me, [foe], [E])
	b.tiles.apply([E], "fire", "x", 2)
	var pts := int(b.tiles.dominant(E).points)
	b.use_skill(me, "consume", "", E)
	var want := roundi(me.max_hp() * BWSkills.CONSUME_HEAL_PCT * pts / 100.0)
	t.eq(BWKit2.barrier_hp(me), want, "a barrier the size of the heal (%d points)" % pts)
	K._give_turn(b, foe)
	var hp := me.hp
	var res := b.attack(foe, me)
	if res.hit:
		var hit := _ev(b, "barrier_hit")
		t.eq(hit.size(), 1, "the blow hits the barrier first")
		t.ok(int(hit[0].absorbed) > 0, "it soaked some")
		t.eq(hp - me.hp, int(res.damage), "only the rest gets through (the result is what landed)")
	else:
		t.ok(true, "missed (seed): nothing to soak")
	K._give_turn(b, me)
	t.eq(BWKit2.barrier_hp(me), 0, "gone at your next turn")


func test_fan_of_knives_radius_two_and_shield(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "daggers", "thunder"), ["fan_of_knives"])
	var near: BWUnit = K._foe("n")
	var far: BWUnit = K._foe("r")
	var away: BWUnit = K._foe("z")
	var nb := BWHex.neighbors(C)
	var two: Vector2i = BWHex.ray(C, nb[3], 2)[1]
	var mate: BWUnit = K._u("m", "sword", "water", { "con": 300 })
	var b: BWBattle = K._fight(me, [near, far, away], [nb[0], two, Vector2i(9, 9)], 7, [mate], [nb[2]])
	var pv := b.skill_preview(me, "fan_of_knives", "thunder", C)
	t.eq((pv.units as Array).size(), 2, "foes at 1 and 2, not 5")
	t.eq((pv.hexes as Array).size(), 18, "radius 2 painted (not your own hex)")
	# a charged hex beside you (and beside the ally): thunder blows it
	b.tiles.apply([nb[1]], "fire", "x", 2)
	var hp := me.hp
	var mate_hp := mate.hp
	K._use(t, b, me, "fan_of_knives", "thunder", C)
	t.ok(not _ev(b, "detonate").is_empty(), "the fan's thunder set off the charge")
	t.eq(me.hp, hp, "its blast can't hurt you")
	t.ok(_ev(b, "immune").any(func(e): return e.unit == "me"), "shown as immune")
	t.ok(mate.hp < mate_hp, "your ally isn't spared")
	t.ok(not me.fx.has(BWKit2.SHIELD), "the shield drops with the action")

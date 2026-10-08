extends RefCounted
## D108 (daggers and fists): the new skills and the Improve riders, plus an
## AI smoke run with every new skill equipped. Helpers come from
## test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


# ------------------------------------------------------------------ daggers

func test_tumble_after_the_attack(t) -> void:
	# set after attacking: the move comes at once
	var me: BWUnit = K._equip(K._u("me", "daggers", "fire"), ["tumble"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	b.attack(me, foe)
	var before: int = me.move_range()
	K._use(t, b, me, "tumble", "", C)
	t.ok(me.acted, "(the attack spent the action; Tumble spends nothing)")
	t.eq(me.move_range(), before + 2, "unmoved: +2 on top of the move")
	t.eq(me.cooldowns.get("tumble", 0), 1, "cd 1")
	# set before attacking: it waits for the attack
	var me2: BWUnit = K._equip(K._u("me", "daggers", "fire"), ["tumble"])
	var f2: BWUnit = K._foe()
	var b2: BWBattle = K._fight(me2, [f2], [K._line(2)[1]])
	b2.move(me2, E)
	b2.use_skill(me2, "tumble", "", me2.pos)
	t.ok(not me2.acted, "free")
	t.eq(int(me2.fx.get("bonus_move", 0)), 0, "nothing yet")
	b2.attack(me2, f2)
	t.eq(int(me2.fx.get("bonus_move", 0)), 2, "after the attack: a 2-hex move")
	t.ok(b2.can_move(me2), "and it can take it")


func test_manipulate_counts_statuses_and_charge(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "daggers", "fire"), ["manipulate"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	t.ok(b.skill_preview(me, "manipulate", "fire", E).forecasts["f"].notes.any(func(n): return str(n).begins_with("No status")), "nothing to work")
	b.add_status(foe, "scorched", me)
	b.add_status(foe, "pinned", me)
	b.tiles.apply([E], "water", "x")
	var fc: Dictionary = b.skill_preview(me, "manipulate", "fire", E).forecasts["f"]
	t.near(float(K._mod(fc, "Manipulate").get("value", 0)), 1.3, 0.001, "2 statuses + charge: +30%")
	for k in ["staggered", "blinded", "drenched", "shrouded", "swift"]:
		b.add_status(foe, k, me)
	fc = b.skill_preview(me, "manipulate", "fire", E).forecasts["f"]
	t.near(float(K._mod(fc, "Manipulate").get("value", 0)), 1.6, 0.001, "capped at +60%")
	K._use(t, b, me, "manipulate", "fire", E)


func test_fan_of_knives(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "daggers", "dark"), ["fan_of_knives"])
	var nb := BWHex.neighbors(C)
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("c"), K._foe("z")], [nb[0], nb[4], Vector2i(9, 9)])
	var pv := b.skill_preview(me, "fan_of_knives", "dark", C)
	t.eq(pv.units.size(), 2, "the two beside you")
	K._use(t, b, me, "fan_of_knives", "dark", C)
	t.ok(Array(BWHex.ring(C, 1)).all(func(h): return b.tiles.carries(h, "dark")), "the ring is painted")


func test_dagger_improves(t) -> void:
	# Daggerleap+: backstab +75%
	var me: BWUnit = K._u("me", "daggers", "fire")
	me.skill_ranks["daggerleap"] = 2
	var foe: BWUnit = K._foe()
	var spot := Vector2i(6, 4)
	var b: BWBattle = K._fight(me, [foe], [spot])
	foe.facing = BWHex.direction_index(spot, Vector2i(7, 4))
	var land := Vector2i(5, 4)
	t.near(float(K._mod(b.skill_preview(me, "daggerleap", "fire", land).forecasts["f"], "Backstab").get("value", 0)), 1.75, 0.001,
		"Daggerleap+: +75%")
	# Dualthrow+: a second bounce at 50%
	var me2: BWUnit = K._u("me", "daggers", "fire")
	me2.skill_ranks["dualthrow"] = 2
	var line: Array = K._line(4)
	var a: BWUnit = K._foe("a")
	var c: BWUnit = K._foe("c")
	var d: BWUnit = K._foe("d")
	var b2: BWBattle = K._fight(me2, [a, c, d], [line[1], BWHex.neighbors(line[1])[1], BWHex.neighbors(BWHex.neighbors(line[1])[1])[1]])
	b2.use_skill(me2, "dualthrow", "fire", line[1])
	var pv := b2.skill_preview(me2, "dualthrow_second", "fire", line[1])
	t.near(float(K._mod(pv.forecasts["c"], "Bounce (off").get("value", 0)), 0.75, 0.001, "first bounce 75%")
	t.near(float(K._mod(pv.forecasts["d"], "Second bounce").get("value", 0)), 0.5, 0.001, "Dualthrow+: second bounce 50%")
	# Consume+: 7% a point
	var me3: BWUnit = K._u("me", "daggers", "fire")
	me3.skill_ranks["consume"] = 2
	var b3: BWBattle = K._fight(me3, [K._foe()], [E])
	b3.tiles.apply([E], "fire", "x", 2)
	t.ok(b3.skill_preview(me3, "consume", "", E).notes.any(func(n): return str(n).begins_with("Consume heals you 14%")), "Consume+: 7% x 2 points")


# ------------------------------------------------------------------ fists

func test_shockwave_palm(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["shockwave_palm"])
	var line: Array = K._line(4)
	var a: BWUnit = K._foe("a")
	var c: BWUnit = K._foe("c")
	var b: BWBattle = K._fight(me, [a, c], [line[0], line[1]])
	var pv := b.skill_preview(me, "shockwave_palm", "fire", E)
	t.eq(pv.hexes, line.slice(0, 3), "line 3")
	var ev: Dictionary = K._use(t, b, me, "shockwave_palm", "fire", E)
	var sec := {}
	for r in ev.results:
		sec[r.target] = r.result.secondary
	if sec.a and sec.c:
		t.eq([a.pos, c.pos], [line[1], line[2]], "both shoved 1 along the line (far one first)")
	t.ok(line.slice(0, 3).all(func(h): return b.tiles.carries(h, "fire")), "the line is painted")


func test_brace(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["brace", "flurry"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	K._use(t, b, me, "brace", "", C)
	t.ok(not me.acted, "free")
	t.near(float(K._mod(b.forecast_basic(foe, me), "Brace").get("value", 0)), 0.75, 0.001, "-25% damage taken")
	var pv := b.skill_preview(me, "flurry", "fire", E)
	t.eq(pv.hits, 4, "the next Flurry throws 4")
	b.use_skill(me, "flurry", "fire", E)
	t.ok(not me.fx.has("brace_flurry"), "spent")
	K._give_turn(b, me)
	t.ok(K._mod(b.forecast_basic(foe, me), "Brace").is_empty(), "the guard drops at your next turn")
	t.ok(BWSkillRegistry.get_def("brace").ai_free_wanted(b, me), "the AI braces with a foe near")


func test_grapple_throw(t) -> void:
	var thrown := 0
	for sd in 6:
		var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["grapple_throw"])
		var foe: BWUnit = K._foe()
		var b: BWBattle = K._fight(me, [foe], [E], 100 + sd)
		var spot: Vector2i = BWHex.neighbors(C)[3]
		b.tiles.apply([spot], "fire", "me")
		var pv := b.skill_preview(me, "grapple_throw", "fire", E)
		t.ok(pv.notes.any(func(n): return str(n).contains("your charge")), "throws onto your own charge")
		t.near(float(K._mod(pv.forecasts["f"], "Thrown onto your charge").get("value", 0)), 1.5, 0.001, "+50%")
		var ev: Dictionary = K._use(t, b, me, "grapple_throw", "fire", E)
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.pos == spot, sec, "thrown iff not resisted")
		thrown += 1 if sec else 0
		if sec:
			t.eq(K._events(b, "move").filter(func(e): return e.get("kind", "") == "place").size(), 1, "a placement move")
	t.ok(thrown > 0, "thrown at least once")


func test_haymaker(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["haymaker"])
	var b: BWBattle = K._fight(me, [K._foe()], [E])
	var fc: Dictionary = b.skill_preview(me, "haymaker", "fire", E).forecasts["f"]
	t.near(float(K._mod(fc, "Haymaker").get("value", 0)), 25.0, 0.01, "+25 crit unmoved")
	K._use(t, b, me, "haymaker", "fire", E)
	t.eq(me.cooldowns.get("haymaker_fire", 0), 4, "cd 4")


func test_hundred_fists(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["hundred_fists"])
	var b: BWBattle = K._fight(me, [K._foe()], [E])
	var pv := b.skill_preview(me, "hundred_fists", "fire", E)
	t.eq(pv.hits, 6, "six blows")
	t.near(float(K._mod(pv.forecasts["f"], "Hundred Fists: strike").get("value", 0)), 0.3, 0.001, "30% each")
	K._use(t, b, me, "hundred_fists", "fire", E)
	t.eq(K._events(b, "attack").filter(func(e): return e.get("skill", "") == "hundred_fists").size(), 5, "five more rolled strikes")
	t.eq(b.tiles.intensity(E, "fire"), 2, "the last pours 2 steps")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "hundred_fists"), "once per battle")


func test_fist_improves(t) -> void:
	# Flurry+: the last strike +30 crit
	var me: BWUnit = K._u("me", "fists", "fire")
	me.skill_ranks["flurry"] = 2
	var b: BWBattle = K._fight(me, [K._foe()], [E])
	var p := { "hits": 3, "victims": [], "shares": {} }
	var fc := b._skill_forecast(me, BWSkills.get_skill("flurry"), "fire", b.units[1], p, 2)
	t.near(float(K._mod(fc, "Flurry+ finisher").get("value", 0)), 30.0, 0.01, "Flurry+: +30 crit")
	# Uppercut+: slam +75% and the slammed foe Staggers
	var me2: BWUnit = K._u("me", "fists", "fire")
	me2.skill_ranks["uppercut"] = 2
	var x: BWUnit = K._foe("x")
	var y: BWUnit = K._foe("y")
	var b2: BWBattle = K._fight(me2, [x, y], [E, K._line(2)[1]])
	var pv := b2.skill_preview(me2, "uppercut", "", E)
	t.near(float(K._mod(pv.forecasts["x"], "Slammed").get("value", 0)), 1.75, 0.001, "Uppercut+: +75%")
	b2.use_skill(me2, "uppercut", "", E)
	t.ok(x.statuses.has("staggered"), "the slammed foe is Staggered")
	# Palm Burst+: push 2 on a primed hex
	var pushed := false
	for sd in 8:
		var me3: BWUnit = K._u("me", "fists", "fire")
		me3.skill_ranks["palm_burst"] = 2
		var f3: BWUnit = K._foe()
		var b3: BWBattle = K._fight(me3, [f3], [E], 110 + sd)
		b3.tiles.apply([E], "fire", "x")
		t.ok(b3.skill_preview(me3, "palm_burst", "fire", E).notes.any(func(n): return str(n).ends_with("back 2")), "named")
		var ev := b3.use_skill(me3, "palm_burst", "fire", E)
		if ev.results[0].result.secondary:
			t.eq(f3.pos, K._line(3)[2], "pushed 2")
			pushed = true
			break
	t.ok(pushed, "pushed within 8 seeds")


# ------------------------------------------------------------------ AI smoke

## Every new skill in some unit's loadout; three AI-vs-AI fights run without
## a script error, and the new skills get used.
func test_ai_plays_the_new_skills(t) -> void:
	var kits := {
		"sword": ["thread_needle", "whirlwind_blade", "lunge"], "axe": ["reckless_arc", "hook", "sunder"],
		"lance": ["lance_charge", "sweep", "vault"], "bow": ["retreating_shot", "split_arrow", "pinning_shot"],
		"staff": ["bolt", "tempest", "surge"], "daggers": ["manipulate", "kindle", "fan_of_knives"],
		"pistols": ["point_blank", "pistol_whip", "empty_the_chamber"], "fists": ["shockwave_palm", "haymaker", "hundred_fists"],
	}
	var used := {}
	var classes: Array = kits.keys()
	for game in 3:
		var ps: Array = []
		var es: Array = []
		for i in 3:
			var wc: String = classes[(game * 3 + i) % classes.size()]
			var wc2: String = classes[(game * 3 + i + 4) % classes.size()]
			ps.append(K._equip(K._u("p%d" % i, wc, BWFormulas.ELEMENTS[i], { "con": 10 }), kits[wc]))
			es.append(K._equip(K._u("e%d" % i, wc2, BWFormulas.ELEMENTS[i + 3], { "con": 10 }), kits[wc2]))
		var b := BWBattle.new(K._board(), 500 + game)
		b.setup(ps, es)
		b._new_cycle()
		var guard := 0
		while not b.over and guard < 400:
			BWAI.take_turn(b)
			guard += 1
		for e in b.history:
			if e.type == "skill":
				used[e.skill] = true
	t.ok(used.size() >= 3, "the AI used new skills: %s" % [used.keys()])


## D109: Grapple Throw's landing is the player's pick; the AI keeps dest_for.
func test_grapple_second_pick(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "fists", "fire"), ["grapple_throw"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	var d: BWSkillDef = BWSkillRegistry.get_def("grapple_throw")
	var seconds: Array = d.second_targets(b, me, "fire", E)
	t.eq(seconds.size(), 5, "the free hexes next to the thrower")
	t.ok(not E in seconds, "not the foe's own hex")
	var pick: Vector2i = BWHex.neighbors(C)[3]
	t.ok(b.skill_preview(me, "grapple_throw", "fire", E, pick).notes.any(func(n): return str(n).contains(str(pick))), "the note names the pick")
	var ev := b.use_skill(me, "grapple_throw", "fire", E, pick)
	t.ok(not ev.is_empty(), "resolves")
	if ev.results[0].result.secondary:
		t.eq(foe.pos, pick, "lands where picked")
	t.ok(d.second_targets(b, me, "fire", Vector2i(9, 9)).is_empty(), "no foe there: nothing to pick")


## D112: the support skills' AI conditions.
func test_ai_support_conditions(t) -> void:
	# Bellow (D436, was War Cry): nothing in reach now, a foe in reach next turn, a Cleave to double
	var ax: BWUnit = K._equip(K._u("me", "axe", "fire"), ["bellow", "cleave"])
	var b: BWBattle = K._fight(ax, [K._foe()], [Vector2i(4, 8)])
	t.ok(not BWAI._best_support(b, ax).is_empty() and BWAI._best_support(b, ax).key == "bellow", "Bellow before closing in")
	var b2: BWBattle = K._fight(K._equip(K._u("me", "axe", "fire"), ["bellow", "cleave"]), [K._foe()], [E])
	t.ok(BWAI._best_support(b2, b2.current()).is_empty(), "a foe in reach now: attack instead")
	# Phalanx: an ally beside you and a foe within 3
	var ln: BWUnit = K._equip(K._u("me", "lance", "fire"), ["phalanx"])
	var mate: BWUnit = K._u("m", "axe", "fire")
	var b3: BWBattle = K._fight(ln, [K._foe()], [Vector2i(4, 7)], 7, [mate], [Vector2i(3, 4)])
	t.eq(str(BWAI._best_support(b3, ln).get("key", "")), "phalanx", "Phalanx with a mate and a foe near")
	# (Aegis is retired, D442)
	# Tumble: after attacking, when a safer hex is near
	var dg: BWUnit = K._equip(K._u("me", "daggers", "fire"), ["tumble"])
	var f5: BWUnit = K._foe()
	var b5: BWBattle = K._fight(dg, [f5], [E])
	t.ok(not BWSkillRegistry.get_def("tumble").ai_free_wanted(b5, dg), "not before attacking")
	b5.attack(dg, f5)
	BWAI._guard_up(b5, dg)
	t.ok(K._events(b5, "skill").any(func(e): return e.skill == "tumble"), "tumbles after the attack")


## D435-D442: the retired skills' tests moved to test_kit3 (their replacements; the defs stay only for old saves).

extends RefCounted
## D105 (lance): the new skills, the Vault rework and the Improve riders.
## Helpers come from test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


func test_guardrush_shoves_and_slams(t) -> void:
	var line: Array = K._line(3)
	var shoved := 0
	for sd in 6:
		var me: BWUnit = K._equip(K._u("me", "lance", "fire"), ["guardrush"])
		var foe: BWUnit = K._foe("f", { "res": 0 })
		var b: BWBattle = K._fight(me, [foe], [line[1]], 40 + sd)
		var pv := b.skill_preview(me, "guardrush", "fire", line[1])
		t.ok(pv.notes.any(func(n): return str(n).begins_with("Shove")), "the shove is in the forecast")
		var ev: Dictionary = K._use(t, b, me, "guardrush", "fire", line[1])
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.pos == line[2], sec, "shoved back 1 iff the secondary landed (seed %d)" % sd)
		shoved += 1 if sec else 0
	t.ok(shoved > 0, "shoved at least once")
	# blocked by a unit: both slam for 8% (when the secondary lands)
	var slammed := false
	for sd in 10:
		var me2: BWUnit = K._equip(K._u("me", "lance", "fire"), ["guardrush"])
		var x: BWUnit = K._foe("x")
		var y: BWUnit = K._foe("y")
		var b2: BWBattle = K._fight(me2, [x, y], [line[1], line[2]], 60 + sd)
		t.ok(b2.skill_preview(me2, "guardrush", "fire", line[1]).notes.any(func(n): return str(n).contains("slams into y")), "slam named")
		var ev2 := b2.use_skill(me2, "guardrush", "fire", line[1])
		var slams: Array = K._events(b2, "tile_damage").filter(func(e): return e.cause == "slam")
		if not ev2.results[0].result.secondary:
			t.ok(slams.is_empty(), "resisted: no slam")
			continue
		t.eq(slams.map(func(e): return e.unit), ["x", "y"], "the foe and what it hits")
		t.eq(int(slams[0].amount), BWTiles.tile_damage(x, 8, ""), "8% max HP")
		t.eq(x.pos, line[1], "it didn't move")
		slammed = true
		break
	t.ok(slammed, "a slam within 10 seeds")


func test_sweep_clears_the_front(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._equip(K._u("me", "lance", "fire"), ["sweep"])
	var a: BWUnit = K._foe("a")
	var c: BWUnit = K._foe("c")
	var b: BWBattle = K._fight(me, [a, c], [nb[0], nb[1]])
	var pv := b.skill_preview(me, "sweep", "fire", nb[0])
	t.eq(pv.hexes.size(), 3, "the 3-hex front arc")
	t.ok(pv.hexes.all(func(h): return BWHex.distance(C, h) == 1), "adjacent to the user")
	t.eq(pv.units.size(), 2, "both foes")
	var ev: Dictionary = K._use(t, b, me, "sweep", "fire", nb[0])
	for r in ev.results:
		var v: BWUnit = a if r.target == "a" else c
		var from: Vector2i = nb[0] if v == a else nb[1]
		t.eq(v.pos == BWHex.step_beyond(C, from), bool(r.result.secondary), "%s shoved straight away iff the secondary landed" % v.id)
	t.ok(pv.hexes.all(func(h): return b.tiles.carries(h, "fire")), "the arc is painted")
	t.eq(me.cooldowns.get("sweep_fire", 0), 3, "cd 3")


func test_set_spear_zone(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "lance", "fire"), ["set_spear"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [K._line(4)[3]])
	K._use(t, b, me, "set_spear", "", C)
	t.ok(not me.acted, "free: no action spent")
	t.eq(K._events(b, "zone").size(), 1, "a zone is set")
	var zone: Array = me.zone.get("hexes", [])
	t.eq(zone.size(), BWHex.area(C, 2).size() - 1, "every hex within reach 2")
	t.eq(me.cooldowns.get("set_spear", 0), 3, "cd 3")
	# the foe's moves: it may stop in the zone but never path past it
	K._give_turn(b, foe)
	var r := b.reachable(foe)
	var entered := 0
	for h in r:
		if not r[h].stop or h == foe.pos:
			continue
		var path := BWBoard.path_to(r, h)
		for i in range(0, path.size() - 1):
			t.ok(not path[i] in zone or path[i] == foe.pos, "no path runs through the zone (to %s)" % str(h))
		if h in zone:
			entered += 1
	t.ok(entered > 0, "it can still step into the zone and stop")
	K._give_turn(b, me)
	t.ok(me.zone.is_empty(), "the zone ends at the holder's next turn")


func test_phalanx_guards_the_line(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._equip(K._u("me", "lance", "fire"), ["phalanx"])
	var mate: BWUnit = K._u("m", "sword", "fire")
	var far_mate: BWUnit = K._u("fm", "sword", "fire")
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [nb[3]], 7, [mate, far_mate], [nb[0], Vector2i(9, 9)])
	K._use(t, b, me, "phalanx", "", C)
	t.ok(me.acted, "it uses the action")
	var fc := b.forecast_basic(foe, me)
	t.near(float(K._mod(fc, "Phalanx").get("value", 0)), 0.85, 0.001, "-15% damage taken")
	t.ok(not K._mod(b.forecast_basic(foe, mate), "Phalanx").is_empty(), "the adjacent ally too")
	t.ok(K._mod(b.forecast_basic(foe, far_mate), "Phalanx").is_empty(), "not a distant ally")
	t.ok(b._immune(me, "displace"), "the user can't be displaced")
	K._give_turn(b, me)
	t.ok(not b._immune(me, "displace"), "until its next turn")
	t.ok(K._mod(b.forecast_basic(foe, me), "Phalanx").is_empty(), "the guard drops at its turn")


func test_dragoon_dive(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "lance", "fire"), ["dragoon_dive"])
	var land: Vector2i = K._line(4)[3]
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [BWHex.neighbors(land)[1]])
	t.ok(not K._line(5)[4] in b.skill_targets(me, "dragoon_dive", "fire"), "5 is too far")
	var pv := b.skill_preview(me, "dragoon_dive", "fire", land)
	t.eq(pv.units, ["f"], "a foe beside the landing is hit")
	K._use(t, b, me, "dragoon_dive", "fire", land)
	t.eq(me.pos, land, "landed 4 away")
	t.ok(Array(BWHex.ring(land, 1)).all(func(h): return b.tiles.carries(h, "fire")), "the landing ring is painted")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "dragoon_dive"), "once per battle")


func test_vault_one_click(t) -> void:
	# D105: click a foe 2..3 away, leap beside it over anything, strike at once
	var line: Array = K._line(3)
	var me: BWUnit = K._u("me", "lance", "fire", { "dex": 100 })
	var mate: BWUnit = K._u("m", "sword", "fire")
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [line[2]], 7, [mate], [line[0]])
	t.ok(line[2] in b.skill_targets(me, "vault", "fire"), "a foe 3 away, an ally in between: still a target")
	var pv := b.skill_preview(me, "vault", "fire", line[2])
	t.eq(pv.dest, line[1], "lands on the free hex beside it nearest you")
	t.ok(pv.forecasts.is_empty(), "one click: no confirm window (the strike is in the notes)")
	t.ok(pv.notes.any(func(n): return str(n).contains("momentum +25%")), "momentum named")
	var ev := b.use_skill(me, "vault", "fire", line[2])
	t.ok(not ev.is_empty(), "resolves")
	t.eq(me.pos, line[1], "vaulted")
	t.ok(b.tiles.carries(C, "fire"), "the takeoff hex takes the element")
	var hits: Array = K._events(b, "attack")
	t.eq(hits.size(), 1, "struck at once with the weapon basic")
	t.ok("Momentum" in hits[0].tags, "with momentum")
	t.ok(me.follow_up.is_empty() and me.acted, "no follow-up menu; the action is spent")
	t.ok(not me.fx.has("momentum"), "momentum spent")
	t.eq(me.cooldowns.get("vault_fire", 0), 2, "cd 2")
	# not adjacent foes, not over 3; rock in the way doesn't matter
	var me2: BWUnit = K._u("me", "lance", "fire")
	var b2: BWBattle = K._fight(me2, [K._foe("a"), K._foe("z")], [E, K._line(4)[3]])
	t.ok(b2.skill_targets(me2, "vault", "fire").is_empty(), "adjacent and 4-away foes aren't targets")
	var me3: BWUnit = K._u("me", "lance", "fire")
	var b3: BWBattle = K._fight(me3, [K._foe()], [line[2]])
	b3.board.set_cell(line[0], "jagged", 0)
	t.ok(line[2] in b3.skill_targets(me3, "vault", "fire"), "it vaults over rock")
	t.ok(BWSkillRegistry.get_def("vault").ai_score(b3, me3, b3.skill_preview(me3, "vault", "fire", line[2])) > 0.0,
		"the AI scores the strike")


func test_vault_plus(t) -> void:
	var me: BWUnit = K._u("me", "lance", "fire", { "dex": 100 })
	me.skill_ranks["vault"] = 2
	var at: Vector2i = K._line(4)[3]
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [at])
	t.ok(at in b.skill_targets(me, "vault", "fire"), "Vault+: range 4")
	var pv := b.skill_preview(me, "vault", "fire", at)
	t.ok(pv.notes.any(func(n): return str(n).contains("momentum +35%")), "momentum +35%")
	var plain := b.forecast_basic(me, foe)
	b.use_skill(me, "vault", "fire", at)
	var hit: Dictionary = K._events(b, "attack")[0]
	t.ok(hit.result.hit, "struck")
	t.ok(me.effects.all(func(e): return e.source != "vault_plus"), "the one-blow record is gone after")
	t.ok(plain.damage.value > 0, "sanity")


func test_tridentpierce_plus(t) -> void:
	var line: Array = K._line(3)
	var me: BWUnit = K._u("me", "lance", "fire")
	me.skill_ranks["tridentpierce"] = 2
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("b"), K._foe("d")], line)
	var pv := b.skill_preview(me, "tridentpierce", "fire", E)
	t.ok(not K._mod(pv.forecasts["b"], "Pierce (in line").is_empty(), "the second is pierced")
	t.near(float(K._mod(pv.forecasts["d"], "Pierce+").get("value", 0)), 1.2, 0.001, "the pierce carries to the third")
	var me2: BWUnit = K._u("me", "lance", "fire")
	var b2: BWBattle = K._fight(me2, [K._foe("a"), K._foe("b"), K._foe("d")], line)
	t.ok(K._mod(b2.skill_preview(me2, "tridentpierce", "fire", E).forecasts["d"], "Pierce").is_empty(), "not without the Improve")

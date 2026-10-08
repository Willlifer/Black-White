extends RefCounted
## D433-D442, weapon kit pass 3 (design/SKILLS.md): axe Momentum, Cleave
## widening, no speed penalty, a free Hook, Reckless Arc, Bellow; sword
## Lunge paints, Thread the Needle, Tapestry; daggers Overload, Kindle;
## Guardrush / Aegis / Aimed Shot removed; the save migration. Helpers come
## from test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _mod(fc: Dictionary, start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(start):
			return m
	return {}


# ------------------------------------------------------------------ axe

func test_charge_momentum(t) -> void:
	var line: Array = K._line(9)
	var me: BWUnit = K._u("me", "axe", "fire")
	var g: BWUnit = K._foe("g")
	var b: BWBattle = K._fight_big(me, [K._foe("f"), g], [Vector2i(13, 13), Vector2i(0, 12)])
	var pv := b.skill_preview(me, "charge", "fire", E)
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Momentum: 7 hexes run, the swing after +21%")), "the run's momentum is in the preview")
	b.use_skill(me, "charge", "fire", E)
	t.eq(me.pos, line[6], "ran 7")
	t.eq(int(me.fx.get("charge_momentum", 0)), 7, "7 hexes ride into the swing")
	g.pos = BWHex.neighbors(me.pos)[0]
	var fc := b.forecast_basic(me, g)
	var m := _mod(fc, "Momentum (Charge, 7 hexes): +21%")
	t.near(float(m.get("value", 0.0)), 1.21, 0.001, "a named +21% line on the end swing")
	b.attack(me, g)
	t.ok(not me.fx.has("charge_momentum"), "spent by the swing")
	t.eq(_mod(b.forecast_basic(me, g), "Momentum (Charge"), {}, "gone after")


func test_cleave_widens_on_element(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._u("me", "axe", "fire")
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("r")], [nb[0], nb[3]])
	var pv := b.skill_preview(me, "cleave", "fire", nb[0])
	t.eq((pv.hexes as Array).size(), 3, "a plain arc is 3")
	t.ok(not "r" in pv.units, "the rear foe is safe")
	b.tiles.apply([nb[1]], "fire", "x", 1)
	var pv2 := b.skill_preview(me, "cleave", "fire", nb[0])
	t.eq((pv2.hexes as Array).size(), 6, "D433: your element in the arc widens it to all 6 around you")
	t.ok("r" in pv2.units, "the rear foe is caught")
	t.ok((pv2.notes as Array).any(func(n): return str(n).contains("widens to all 6")), "named")
	var b2: BWBattle = K._fight(K._u("me", "axe", "fire"), [K._foe("a")], [nb[0]])
	b2.tiles.apply([nb[1]], "water", "x", 1)
	t.eq((b2.skill_preview(b2.current(), "cleave", "fire", nb[0]).hexes as Array).size(), 3, "another element's ground doesn't")


func test_axe_has_no_speed_penalty(t) -> void:
	t.eq(int(BWData.row("weapons", "axe").get("speed_mod", 9)), 0, "D433: axe speed_mod 0")
	var u: BWUnit = K._u("me", "axe", "fire")
	t.eq(u.speed(), u.stat("spd"), "speed = SPD")


func test_hook_is_free(t) -> void:
	var line: Array = K._line(3)
	var pulled := 0
	for sd in 6:
		var me: BWUnit = K._equip(K._u("me", "axe", "fire"), ["hook"])
		var foe: BWUnit = K._foe("f", { "res": 0 })
		var b: BWBattle = K._fight(me, [foe], [line[2]], 40 + sd)
		t.ok(BWSkills.get_skill("hook").get("free_action", false), "a free action")
		var ev: Dictionary = K._use(t, b, me, "hook", "fire", line[2])
		t.ok(not me.acted, "D437: Hook spends no action")
		t.eq(int(me.cooldowns.get("hook_fire", 0)), 2, "cd 2")
		if ev.results[0].result.secondary and foe.alive():
			pulled += 1
			t.ok(not b.attack(me, foe).is_empty(), "then a swing at the hauled foe")
	t.ok(pulled > 0, "pulled at least once")


func test_ai_hooks_then_acts(t) -> void:
	var line: Array = K._line(3)
	var ax: BWUnit = K._equip(K._u("ax", "axe", "fire", { "dex": 100 }), ["hook", "reckless_arc"])
	var foe: BWUnit = K._u("p", "sword", "water", { "con": 300, "res": 0 })
	var b := BWBattle.new(K._board(), 9)
	b.setup([foe], [ax])
	ax.pos = C
	foe.pos = line[2]
	K._give_turn(b, ax)
	BWAI.take_turn(b)
	var acts: Array = b.history.filter(func(e): return e.type in ["skill", "attack"] and e.unit == "ax").map(func(e): return str(e.get("skill", "basic")))
	t.ok(acts.size() >= 2 and acts[0] == "hook", "the AI opens with Hook and still acts (%s)" % [acts])


func test_reckless_arc(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._equip(K._u("me", "axe", "fire"), ["reckless_arc"])
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("s"), K._foe("r")], [nb[0], nb[2], nb[3]])
	var pv := b.skill_preview(me, "reckless_arc", "fire", nb[0])
	t.eq((pv.hexes as Array).size(), 5, "the 5 hexes in front: all but the rear")
	t.ok(not nb[3] in pv.hexes, "not the hex behind")
	t.eq(pv.units, ["a", "s"], "the front and the flank foe")
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Reckless")), "the cost is in the forecast")
	K._use(t, b, me, "reckless_arc", "fire", nb[0])
	t.ok(me.statuses.has("scorched"), "the swinger is Scorched")
	t.ok((pv.hexes as Array).all(func(h): return b.tiles.carries(h, "fire")), "the arc is painted")
	t.ok(not "reckless_swing" in BWSkillRegistry.pool("axe"), "Reckless Swing is retired")


func test_bellow_doubles_cleave(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._equip(K._u("me", "axe", "fire"), ["bellow", "cleave"])
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("far")], [nb[0], Vector2i(4, 2)])
	K._use(t, b, me, "bellow", "", C)
	t.ok(me.acted, "it uses the action")
	t.ok(me.fx.get("bellow", false), "held")
	t.ok(b.skill_targets(me, "bellow", "").is_empty(), "no second Bellow while one is held")
	K._give_turn(b, me)
	var pv := b.skill_preview(me, "cleave", "fire", nb[0])
	t.eq((pv.hexes as Array).size(), 11, "the six around you and five beyond in front")
	t.ok(nb[3] in pv.hexes, "behind too")
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Bellow")), "named")
	b.use_skill(me, "cleave", "fire", nb[0])
	t.ok(not me.fx.has("bellow"), "spent")
	t.eq(_ev(b, "bellow_spent").size(), 1, "announced")


func test_bellow_doubles_sunder(t) -> void:
	var line: Array = K._line(11)
	var me: BWUnit = K._equip(K._u("me", "axe", "fire"), ["bellow", "sunder"])
	var b: BWBattle = K._fight_big(me, [K._foe("f"), K._foe("g")], [line[0], line[8]])
	b.use_skill(me, "bellow", "", C)
	K._give_turn(b, me)
	var pv := b.skill_preview(me, "sunder", "fire", E)
	t.eq(pv.hexes, line.slice(0, 10), "a 10-hex fissure")
	t.ok("g" in pv.units, "the foe 9 out is on it")
	b.use_skill(me, "sunder", "fire", E)
	t.ok(not me.fx.has("bellow"), "spent")
	K._give_turn(b, me)
	me.cooldowns.clear()
	t.eq((b.skill_preview(me, "sunder", "fire", E).hexes as Array).size(), 5, "back to 5")


# ------------------------------------------------------------------ sword

func test_lunge_paints_its_path(t) -> void:
	var line: Array = K._line(3)
	var me: BWUnit = K._equip(K._u("me", "sword", "fire"), ["lunge"])
	var b: BWBattle = K._fight(me, [K._foe("f")], [line[2]])
	K._use(t, b, me, "lunge", "fire", E)
	t.eq(me.pos, line[1], "dashed to the foe")
	for h in line:
		t.ok(b.tiles.carries(h, "fire"), "D438: %s takes the element" % h)


func test_thread_the_needle(t) -> void:
	var line: Array = K._line(5)
	var me: BWUnit = K._equip(K._u("me", "sword", "fire"), ["thread_needle"])
	var f: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [f], [line[0]])
	t.ok(b.skill_targets(me, "thread_needle", "fire").is_empty(), "not on bare ground")
	b.tiles.apply(line.slice(0, 5), "fire", "x", 1)
	t.ok(line[0] in b.skill_targets(me, "thread_needle", "fire"), "a foe on your element")
	t.ok(b.skill_targets(me, "thread_needle", "water").is_empty(), "the element you cast in")
	var pv := b.skill_preview(me, "thread_needle", "fire", line[0])
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Then dash 3")), "the dash is in the preview")
	K._use(t, b, me, "thread_needle", "fire", line[0])
	t.eq(me.pos, line[3], "dashed through it, 3 along the line")
	t.eq(f.pos, line[0], "the foe stays")
	# a unit on the line stops the run before it
	var me2: BWUnit = K._equip(K._u("me", "sword", "fire"), ["thread_needle"])
	var b2: BWBattle = K._fight(me2, [K._foe("f"), K._foe("g")], [line[0], line[2]])
	b2.tiles.apply(line.slice(0, 5), "fire", "x", 1)
	b2.use_skill(me2, "thread_needle", "fire", line[0])
	t.eq(me2.pos, line[1], "stops before a unit")
	# the line ends: the run ends there
	var me3: BWUnit = K._equip(K._u("me", "sword", "fire"), ["thread_needle"])
	var b3: BWBattle = K._fight(me3, [K._foe("f")], [line[0]])
	b3.tiles.apply([line[0], line[1]], "fire", "x", 1)
	b3.use_skill(me3, "thread_needle", "fire", line[0])
	t.eq(me3.pos, line[1], "to the line's far end")
	t.ok(not "heart_seeker" in BWSkillRegistry.pool("sword"), "Heart Seeker is retired")


func test_tapestry(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "sword", "fire"), ["tapestry"])
	var f: BWUnit = K._foe("f")
	var g: BWUnit = K._foe("g")
	var m: BWUnit = K._u("m", "axe", "fire")
	var b: BWBattle = K._fight(me, [f, g], [Vector2i(7, 7), Vector2i(8, 2)], 7, [m], [Vector2i(2, 6)])
	b.tiles.apply([f.pos, m.pos, C, Vector2i(1, 1)], "fire", "x", 1)
	var want := b._tile_dmg(f, 10.0, "fire")
	var pv := b.skill_preview(me, "tapestry", "fire", C)
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Tapestry: 4 tiles")), "every tile of the element")
	K._use(t, b, me, "tapestry", "fire", C)
	var hurt := _ev(b, "tile_damage").filter(func(e): return e.cause == "tapestry")
	t.eq(hurt.map(func(e): return e.unit), ["f"], "the foe on it takes the pulse, the one off it doesn't")
	t.eq(int(hurt[0].amount), want, "10% of max HP, as ground")
	t.ok(m.statuses.has("swift") and me.statuses.has("swift"), "allies on it (you too) are Swift")
	t.ok(b.tiles.carries(f.pos, "fire"), "nothing consumed")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "tapestry"), "once per battle")
	t.ok(BWSkills.get_skill("tapestry").get("once_per_battle", false), "flagged once")


# ------------------------------------------------------------------ daggers

func test_overload(t) -> void:
	var nb := BWHex.neighbors(C)
	var me: BWUnit = K._equip(K._u("me", "daggers", "fire", { "con": 300 }), ["overload"])
	var f: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [f], [nb[0]])
	var two := BWHex.neighbors(nb[3])[3]                  # 2 out, behind
	var three := BWHex.neighbors(two)[3]                  # 3 out: untouched
	b.tiles.apply([C, nb[0], two, three], "fire", "x", 1)
	var pv := b.skill_preview(me, "overload", "", C)
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Overload: 3 charged tiles")), "3 within 2")
	t.ok((pv.notes as Array).any(func(n): return str(n).contains("me (you)")), "the preview warns you're in it")
	var hp0 := me.hp
	var fh0 := f.hp
	K._use(t, b, me, "overload", "", C)
	var det := _ev(b, "detonate")
	t.eq(det.size(), 3, "three blasts")
	t.near(float(det[0].pct), (BWTiles.DETONATE_BASE_PCT + BWTiles.DETONATE_PER_POINT_PCT) * 1.5, 0.001, "a fuse blast +50%")
	for h in [C, nb[0], two]:
		t.ok(b.tiles.at(h).is_empty(), "%s spent" % h)
	t.ok(b.tiles.carries(three, "fire"), "3 out stays")
	t.ok(f.hp < fh0, "the foe is hurt")
	t.ok(me.hp < hp0, "and so are you: no immunity")
	t.eq(int(me.cooldowns.get("overload", 0)), 4, "cd 4")
	t.ok(not "assassinate" in BWSkillRegistry.pool("daggers"), "Assassinate is retired")


func test_kindle(t) -> void:
	var line: Array = K._line(3)
	var me: BWUnit = K._equip(K._u("me", "daggers", "fire"), ["kindle"])
	var f: BWUnit = K._foe("f")
	var b: BWBattle = K._fight(me, [f], [line[2]])
	t.ok(line[2] in b.skill_targets(me, "kindle", "fire"), "a foe 3 away")
	var hp0 := f.hp
	K._use(t, b, me, "kindle", "fire", line[2])
	for n in BWHex.neighbors(line[2]):
		t.ok(b.tiles.carries(n, "fire"), "%s round it takes the element" % n)
	t.ok(not b.tiles.carries(line[2], "fire"), "its own hex doesn't")
	t.eq(f.hp, hp0, "no damage")
	t.ok(not "hamstring" in BWSkillRegistry.pool("daggers"), "Hamstring is retired")


# ------------------------------------------------------------------ removals + saves (D442)

func test_removed_skills(t) -> void:
	t.ok(not "guardrush" in BWSkillRegistry.pool("lance"), "Guardrush is not offered")
	t.ok(not "aegis" in BWSkillRegistry.pool("staff"), "Aegis is not offered")
	t.ok(not "aimed_shot" in BWSkillRegistry.pool("bow"), "Aimed Shot is not offered")
	for k in ["guardrush", "aegis", "aimed_shot", "war_cry", "triumph"]:
		t.ok(BWSkillRegistry.has(k), "%s stays loadable for old saves" % k)
	# picks never draw a retired one
	for wc in ["sword", "axe", "lance", "bow", "staff", "daggers"]:
		for k in BWSkillRegistry.pool(wc):
			t.ok(not BWSkillRegistry.row(k).get("retired", false), "%s offered and not retired" % k)


func test_saves_migrate(t) -> void:
	var u: BWUnit = K._u("me", "sword", "fire")
	u.known_skills = ["heart_seeker", "triumph", "lunge"]
	u.skill_ranks = { "heart_seeker": 2 }
	u.skill_loadout = { "sword": ["striketwice", "heart_seeker", "triumph"] }
	t.ok(BWSkillRegistry.migrate_unit(u), "changed")
	t.ok("thread_needle" in u.known_skills and "tapestry" in u.known_skills, "renamed")
	t.ok(not "heart_seeker" in u.known_skills and not "triumph" in u.known_skills, "old keys gone")
	t.eq(int(u.skill_ranks.get("thread_needle", 1)), 2, "an Improve carries over")
	t.eq(u.skill_loadout.sword, ["striketwice", "thread_needle", "tapestry"], "slots kept")
	var map := { "reckless_swing": "reckless_arc", "war_cry": "bellow", "assassinate": "overload", "hamstring": "kindle",
		"guardrush": "sweep", "aegis": "transfer", "aimed_shot": "pinning_shot" }
	for old in map:
		var v: BWUnit = K._u("v", str(BWSkills.get_skill(old).weapon), "fire")
		v.known_skills = [old]
		BWSkillRegistry.migrate_unit(v)
		t.eq(v.known_skills, [map[old]], "%s → %s" % [old, map[old]])
	# a removal onto a skill already known: dropped, no free Improve
	var w: BWUnit = K._u("w", "bow", "fire")
	w.known_skills = ["aimed_shot", "pinning_shot"]
	w.skill_ranks = { "aimed_shot": 2 }
	w.skill_loadout = { "bow": ["arcing_shot", "aimed_shot", "pinning_shot"] }
	BWSkillRegistry.migrate_unit(w)
	t.eq(w.known_skills, ["pinning_shot"], "one pinning shot")
	t.eq(int(w.skill_ranks.get("pinning_shot", 1)), 1, "no free Improve")
	t.eq(w.skill_loadout.bow, ["arcing_shot", "pinning_shot"], "the slot just goes")


# ------------------------------------------------------------------ AI smoke

## Kit-3 skills in AI-vs-AI fights: no script error, and they get used.
func test_ai_plays_kit3(t) -> void:
	var kits := {
		"axe": ["reckless_arc", "hook", "cleave", "bellow"], "sword": ["thread_needle", "lunge", "tapestry"],
		"daggers": ["overload", "kindle", "fan_of_knives"],
	}
	var used := {}
	for game in 3:
		var ps: Array = []
		var es: Array = []
		var i := 0
		for wc in kits:
			ps.append(K._equip(K._u("p%d" % i, wc, BWFormulas.ELEMENTS[i], { "con": 10 }), kits[wc]))
			es.append(K._equip(K._u("e%d" % i, wc, BWFormulas.ELEMENTS[i + 2], { "con": 10 }), kits[wc]))
			i += 1
		var b := BWBattle.new(K._board(), 700 + game)
		b.setup(ps, es)
		b._new_cycle()
		var guard := 0
		while not b.over and guard < 400:
			BWAI.take_turn(b)
			guard += 1
		for e in b.history:
			if e.type == "skill":
				used[e.skill] = true
	var kit3 := ["reckless_arc", "hook", "bellow", "thread_needle", "lunge", "tapestry", "overload", "kindle"]
	t.ok(kit3.filter(func(k): return used.has(k)).size() >= 3, "the AI used kit-3 skills: %s" % [used.keys()])

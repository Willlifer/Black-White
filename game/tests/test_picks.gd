extends RefCounted
## D89 the skill registry, D90/D91 picks (element perks, weapon-skill picks),
## D92 the save's version 2. BWSkillRegistry, BWPicks, BWBattle picks_live.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)


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


func _duel(me: BWUnit, foe: BWUnit, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me], [foe])
	me.pos = C
	foe.pos = E
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	return b


## A skill def built in code, for pool tests (the registry's register()).
func _fake(key: String, wc: String, order: int) -> BWSkillDef:
	var d := BWSkillDef.new()
	d.define({ "key": key, "name": key.capitalize(), "weapon": wc, "clip": "", "desc": "test skill",
		"targeting": "adjacent_unit", "needs_element": false, "range": 1, "cd": 2, "power": 5 }, order)
	return d


## Temporarily pad an element to five perks (the placeholder table has two).
func _pad_perks(el: String) -> Array:
	var rows := BWData.table("perks")
	var by_id: Dictionary = BWData._cache[BWData.DATA_DIR + "perks.csv"].by_id
	var added: Array = []
	for i in 3:
		var r := { "id": "%s_test%d" % [el, i], "element": el, "name": "Test %d" % i,
			"effect_text": "test", "effect_key": "element_damage_pct", "params": "pct=1" }
		rows.append(r)
		by_id[r.id] = r
		added.append(r.id)
	return added


func _unpad(ids: Array) -> void:
	var rows := BWData.table("perks")
	var by_id: Dictionary = BWData._cache[BWData.DATA_DIR + "perks.csv"].by_id
	for id in ids:
		by_id.erase(id)
		for i in range(rows.size() - 1, -1, -1):
			if str(rows[i].id) == id:
				rows.remove_at(i)


# ------------------------------------------------------------------ registry (D89)

func test_registry_loads_every_skill(t) -> void:
	var keys := BWSkillRegistry.keys()
	t.eq(keys.size(), 62, "20 skills + 2 follow-up halves + 40 learnable (D103-D108), one file each")
	for k in keys:
		var r := BWSkillRegistry.row(k)
		for f in ["key", "name", "weapon", "cd", "targeting", "range", "desc", "clip"]:
			t.ok(r.has(f), "%s has %s" % [k, f])
		t.ok(r.is_read_only(), "%s: the row is read-only (shared)" % k)
	var n := 0
	for wc in ["sword", "axe", "lance", "daggers", "bow", "pistols", "staff"]:
		n += BWSkillRegistry.pool(wc).size()
	t.eq(n, 17 + 35, "17 weapon skills + 35 learnable (D103-D108)")
	t.eq(BWSkillRegistry.pool("fists").slice(0, 3), ["flurry", "uppercut", "palm_burst"], "plus the three fists skills first")
	t.eq(BWSkillRegistry.pool("fists").size(), 8, "and five learnable fists skills")
	t.eq(BWSkillRegistry.clip("palm_burst"), "palm_burst", "fists skills name their clip")
	t.eq(BWSkills.get_skill("cleave").get("aoe", false), true, "Cleave is an AoE skill (aoe_radius_plus)")


func test_kit_for_defaults_to_the_weapon(t) -> void:
	for wc in ["sword", "axe", "lance", "daggers", "bow", "pistols", "staff", "fists"]:
		var u := _u("k", wc, "fire")
		t.eq(BWSkillRegistry.kit_for(u).map(func(r): return r.key), BWSkills.kit(wc).map(func(r): return r.key),
			"%s: no loadout = the starter kit" % wc)
	t.eq(BWUnit.loadout_cap("staff"), 4, "the staff keeps its four (cap = max(3, starter))")
	t.eq(BWUnit.loadout_cap("sword"), 3, "everyone else: 3")


func test_upgraded_flag(t) -> void:
	var u := _u("up", "sword", "fire")
	var d := BWSkillRegistry.get_def("striketwice")
	t.ok(not d.upgraded(u), "not improved at start")
	BWPicks.auto_resolve(u)                         # the native perk first
	u.expertise["sword"] = 10                       # E -> D: one skill pick
	var req := BWPicks.next_request(u)
	t.eq(req, { "kind": "skill", "weapon": "sword" }, "a letter owes a skill pick")
	t.ok(not BWPicks.apply(u, req, "improve:striketwice").is_empty(), "improve Striketwice")
	t.ok(d.upgraded(u) and u.skill_upgraded("striketwice"), "the def reads the flag")
	t.ok(not BWSkillRegistry.get_def("riposte").upgraded(u), "only that skill")
	var foe := _u("f", "axe", "water", { "con": 300 })
	var b := _duel(u, foe)
	var row: Dictionary = b.skills_for(u).filter(func(r): return r.key == "striketwice")[0]
	t.ok(row.get("upgraded", false), "the battle's menu row says improved")
	t.ok(not b.skills_for(u).filter(func(r): return r.key == "riposte")[0].has("upgraded"), "others don't")


func test_loadout_capped_at_three(t) -> void:
	var extra := [_fake("test_jab", "daggers", 95), _fake("test_feint", "daggers", 96)]
	for d in extra:
		t.ok(BWSkillRegistry.register(d), "registered %s" % d.id)
	var u := _u("lo", "daggers", "fire")
	t.eq(u.loadout("daggers"), ["consume", "daggerleap", "dualthrow"], "starter kit: three")
	BWPicks.auto_resolve(u)
	u.expertise["daggers"] = 10
	var req := BWPicks.next_request(u)
	var opts := BWPicks.options(u, req).map(func(o): return o.id)
	t.ok("learn:test_jab" in opts and "improve:consume" in opts, "learn or improve: %s" % [opts])
	BWPicks.apply(u, req, "learn:test_jab")
	t.ok("test_jab" in u.known("daggers"), "learned")
	t.eq(u.loadout("daggers").size(), 3, "loadout full: the new skill is known, not equipped")
	t.ok(not u.set_equipped("daggers", "test_jab", true), "a fourth can't be equipped")
	t.ok(u.set_equipped("daggers", "consume", false), "unequip one")
	t.ok(u.set_equipped("daggers", "test_jab", true), "then equip the new one")
	t.eq(u.loadout("daggers"), ["daggerleap", "dualthrow", "test_jab"], "three again")
	t.ok(not u.set_equipped("daggers", "test_feint", true), "unknown skills can't be equipped")
	var keys := BWSkillRegistry.kit_for(u).map(func(r): return r.key)
	t.eq(keys, ["daggerleap", "dualthrow", "dualthrow_second", "test_jab"], "the fight kit follows the loadout")
	for d in extra:
		BWSkillRegistry.unregister(d.id)


# ------------------------------------------------------------------ perks (D90)

func test_run_start_owes_one_perk(t) -> void:
	var u := _u("p", "sword", "fire")
	t.eq(BWPicks.pending(u), [{ "kind": "perk", "element": "fire" }], "rank 1 native: one pick")
	var opts := BWPicks.options(u, BWPicks.pending(u)[0])
	t.eq(opts.size(), BWPicks.perks_of("fire").size(), "a card per fire perk")
	t.ok(BWPicks.apply(u, { "kind": "perk", "element": "water" }, "fire_rush").is_empty(), "wrong element refused")
	t.ok(not BWPicks.apply(u, { "kind": "perk", "element": "fire" }, "fire_rush").is_empty(), "picked")
	t.eq(BWPicks.pending(u), [], "nothing owed after")
	t.ok(BWPicks.apply(u, { "kind": "perk", "element": "fire" }, "fire_skin").is_empty(), "no banking: rank 1 = one pick")
	t.ok(BWPicks.options(u, { "kind": "perk", "element": "fire" })[0].owned, "the taken perk shows as owned")


func test_rank_crossing_triggers_a_pick(t) -> void:
	var u := _u("rc", "sword", "fire")
	BWPicks.auto_resolve(u)
	t.eq(BWPicks.pending(u), [], "settled")
	u.affinity["fire"] = 19
	t.eq(BWPicks.pending(u), [], "19 points: still rank 1")
	BWProgression.award(u, false, "fire")           # +1 → 20: rank 2
	t.eq(BWPicks.pending(u), [{ "kind": "perk", "element": "fire" }], "rank 2: the second pick")
	u.affinity["water"] = 10                        # trained a new element: its first pick
	t.eq(BWPicks.pending(u).size(), 2, "water rank 1 adds one")
	# downtime: training that crosses a rank owes a pick after the day
	var run := BWRun.start(["aureli"], 5)
	var bart: BWUnit = run.squad[0]
	BWPicks.auto_resolve(bart)
	t.eq(run.pending_picks(), [], "start picks done")
	bart.affinity[bart.element] = 15
	bart.expertise[bart.weapon_class] = 5
	run.progress_day([[bart.id, "specialize"]])       # D127: +5 each crosses both ranks
	t.eq(run.pending_picks().size(), 1, "the trained rank owes a pick")
	t.eq(run.pending_picks()[0][1].kind, "perk", "a perk pick")
	var kinds := BWPicks.pending(bart).map(func(r): return r.kind)
	t.ok("skill" in kinds, "specializing the weapon to D owes a skill pick: %s" % [kinds])


func test_rank_three_grants_all_five(t) -> void:
	var u := _u("r3", "sword", "fire")
	for el in BWFormulas.ELEMENTS:
		t.eq(BWPicks.perks_of(el).size(), 5, "five %s perks (D93)" % el)
	BWPicks.apply(u, { "kind": "perk", "element": "fire" }, "fire_skin")
	u.affinity["fire"] = 30
	var made := BWPicks.settle(u)
	t.eq(made.size(), 4, "the other four granted")
	t.eq(BWPicks.owned(u, "fire").size(), 5, "all five owned")
	t.eq(BWPicks.pending(u), [], "rank 3 asks nothing")
	t.ok(made.all(func(r): return r.auto), "granted, not chosen")


func test_perks_feed_the_effects_pipeline(t) -> void:
	var u := _u("fx", "sword", "fire")
	BWPicks.apply(u, { "kind": "perk", "element": "fire" }, "fire_kindling")
	u.refresh_effects()
	var rec: Array = u.effects.filter(func(e): return e.kind == "perk")
	t.eq(rec.size(), 1, "one perk record")
	t.eq(rec[0].key, "stand_on_mod", "a D93 perk key")
	var foe := _u("f", "axe", "water", { "con": 300 })
	var b := _duel(u, foe)
	b.tiles.apply([E], "fire", "x")
	var pv := b.skill_preview(u, "striketwice", "fire", E)
	var fc: Dictionary = pv.forecasts[foe.id]
	t.ok(fc.mods.any(func(m): return str(m.label).begins_with("Kindling")), "the forecast names the perk")
	var pv2 := b.skill_preview(u, "striketwice", "water", E) if "water" in b.learned_elements(u) else {}
	t.ok(pv2.is_empty(), "(fire is the only element learned)")
	# every row uses a key the engine knows (D93), and parses
	t.eq(BWData.table("perks").size(), 35, "35 perks")
	for r in BWData.table("perks"):
		var made := BWEffects.make(r, "perk")
		t.ok(made.key in BWEffects.KEYS, "%s uses a known effect_key (%s)" % [r.id, made.key])
		t.ok(not str(r.effect_text).contains("PLACEHOLDER"), "%s is final text" % r.id)
		t.ok(str(r.element) in BWFormulas.ELEMENTS, "%s names an element" % r.id)


# ------------------------------------------------------------------ mid-fight + AI

func test_battle_rank_up_pauses_for_the_player(t) -> void:
	var me := _u("me", "sword", "fire")
	BWPicks.auto_resolve(me)
	me.affinity["fire"] = 19
	var foe := _u("f", "axe", "water", { "con": 300 })
	var b := _duel(me, foe)
	b.picks_live = true
	b.use_skill(me, "striketwice", "fire", E)
	t.eq(me.affinity_rank("fire"), 2, "the cut crossed rank 2")
	var pend := b.pending_picks("player")
	t.eq(pend.size(), 1, "the player owes a pick")
	t.eq(pend[0][1], { "kind": "perk", "element": "fire" }, "a fire perk")
	t.ok(b.history.filter(func(e): return e.type == "pick").is_empty(), "nothing chosen for the player")
	t.ok(b.apply_pick(me, pend[0][1], "fire_skin"), "the screen applies the choice")
	t.ok(me.effects.any(func(e): return e.source == "fire_skin"), "effects refreshed mid-fight")
	t.eq(b.pending_picks("player"), [], "resolved")
	t.eq(b.history.filter(func(e): return e.type == "pick").size(), 1, "one pick event")


func test_ai_auto_picks_deterministically(t) -> void:
	var a := _u("a", "lance", "thunder")
	var c := _u("a", "lance", "thunder")
	for x in [a, c]:
		x.affinity["thunder"] = 20
		x.affinity["wind"] = 10
		x.expertise["lance"] = 20
	var ra := BWPicks.auto_resolve(a)
	var rc := BWPicks.auto_resolve(c)
	t.eq(ra, rc, "same unit, same picks")
	t.eq(a.perks, ["thunder_step", "thunder_grounded", "wind_tail"], "data order, element order")
	t.eq(a.skill_ranks, { "tridentpierce": 2, "vault": 2 }, "improves its equipped skills first")
	t.eq(BWPicks.pending(a), [], "nothing left owed")
	# enemies in a run arrive with their native pick made
	var run := BWRun.start(["aureli", "della"], 11)
	var e1 := run.enemies_for(3)
	var e2 := run.enemies_for(3)
	t.eq(e1.map(func(u): return u.perks), e2.map(func(u): return u.perks), "same fight, same enemy picks")
	t.ok(e1.all(func(u): return u.perks.size() == 1 and BWPicks.pending(u).is_empty()), "one perk each, none owed")
	# mid-fight: an enemy crossing a rank picks at once (picks_live)
	var me := _u("me", "axe", "water", { "con": 300 })
	var foe := _u("foe", "sword", "fire")
	BWPicks.auto_resolve(foe)
	foe.affinity["fire"] = 19
	var b := BWBattle.new(_board(), 3)
	b.setup([me], [foe])
	b.picks_live = true
	me.pos = C
	foe.pos = E
	b.queue = [foe]
	b.turn_index = 0
	b._begin_turn()
	b.use_skill(foe, "striketwice", "fire", C)
	var picks := b.history.filter(func(e): return e.type == "pick")
	t.eq(picks.size(), 1, "the enemy picked")
	t.ok(picks[0].auto and picks[0].id == "fire_skin", "deterministically: the next fire perk")


# ------------------------------------------------------------------ save (D92)

func test_picks_persist(t) -> void:
	var run := BWRun.start(["aureli", "della"], 21)
	var u: BWUnit = run.squad[0]
	BWPicks.apply(u, BWPicks.next_request(u), str(BWPicks.perks_of(u.element)[1].id))
	u.expertise[u.weapon_class] = 10
	var req := BWPicks.next_request(u)
	BWPicks.apply(u, req, BWPicks.auto_choice(u, req))
	u.skill_loadout[u.weapon_class] = [BWSkillRegistry.starter(u.weapon_class)[0]]
	var d := run.to_dict()
	t.eq(int(d.version), BWRun.SAVE_VERSION, "save version current (2 added picks; 3, D121, stats)")
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(d)))
	var v: BWUnit = back.squad[0]
	t.eq(v.perks, u.perks, "perks")
	t.eq(v.skill_ranks, u.skill_ranks, "upgrades")
	t.eq(v.skill_picks, u.skill_picks, "picks made")
	t.eq(v.loadout(v.weapon_class), u.loadout(u.weapon_class), "loadout")
	t.eq(BWPicks.pending(v), BWPicks.pending(u), "the same picks owed (none banked)")
	t.eq(BWPicks.pending(back.squad[1]), [{ "kind": "perk", "element": back.squad[1].element }],
		"an unmade start pick is still owed after a load")


func test_save_v1_migrates(t) -> void:
	var run := BWRun.start(["aureli"], 31)
	var d := run.to_dict()
	d.version = 1
	for ud in d.squad:
		for k in ["perks", "known_skills", "skill_ranks", "skill_loadout", "skill_picks"]:
			ud.erase(k)
		ud.affinity[ud.element] = 20               # rank 2 in an old save
		ud.expertise[ud.weapon_class] = 10         # D
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(d)))
	var u: BWUnit = back.squad[0]
	t.eq(u.perks.size(), 2, "rank 2: two perks picked on load")
	t.eq(int(u.skill_picks.get(u.weapon_class, 0)), 1, "the D letter's pick made")
	t.eq(BWPicks.pending(u), [], "nothing owed after the migration")
	t.eq(int(back.to_dict().version), BWRun.SAVE_VERSION, "saves as the current version")

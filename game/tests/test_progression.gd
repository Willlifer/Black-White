extends RefCounted
## Levels, affinity and expertise growth (D179: no XP; every fight, won or lost, = a level (D194)).


func _u(wc: String = "sword") -> BWUnit:
	return BWUnit.from_roster({ "id": "u", "weapon_class": wc, "element": "fire",
		"con": 3, "str": 3, "dex": 3, "wil": 3, "def": 3, "res": 3, "spd": 3 })


func test_starting_affinity(t) -> void:
	t.eq(_u().affinity_rank("fire"), 1, "starts at rank 1 in own element (D22)")
	t.eq(_u().expertise_letter("sword"), "E", "starts at E")


func test_attack_award(t) -> void:
	var u := _u()
	var ev0 := BWProgression.award(u, false, "fire")
	t.ok(not ev0.any(func(e): return e.type in ["xp", "level"]), "an attack gives no XP and no level (D179)")
	t.eq(u.level, 1, "still level 1")
	t.eq(u.affinity["fire"], 11, "+1 affinity")
	t.eq(u.expertise["sword"], 1, "+1 expertise")
	BWProgression.award(u, true, "fire")
	t.eq(u.affinity["fire"], 14, "+3 affinity")
	t.eq(u.expertise["sword"], 4, "+3 expertise")


func test_level_up_bias(t) -> void:
	var u := _u("sword")
	var ev := BWProgression.level_up(u)
	t.eq(u.level, 2, "one level")
	t.eq(ev.size(), 1, "one level event")
	t.eq(u.stats["str"], 5, "sword levels STR by 2")
	t.eq(u.stats["dex"], 4, "everything else by 1")
	var b := _u("bow")
	BWProgression.level_up(b, 2)
	t.eq(b.level, 3, "two levels")
	t.eq(b.stats["dex"], 7, "bow levels DEX by 2, twice")
	var s := _u("staff")
	s.equipment = { "head": { "weight": "wizard" }, "chest": { "weight": "wizard" }, "legs": { "weight": "heavy" } }
	var g := BWProgression.level_gains(s)
	t.eq(g["wil"], 2, "staff -> WIL")
	t.eq(g["res"], 2, "two wizard pieces -> RES")
	t.eq(g["def"], 1, "one heavy piece is not enough")


func test_ranks_from_points(t) -> void:
	var u := _u()
	u.expertise["sword"] = 35
	t.eq(u.expertise_letter("sword"), "B", "35 points = B")
	u.expertise["sword"] = 999
	t.eq(u.expertise_letter("sword"), "A", "caps at A")
	u.affinity["fire"] = 5000
	t.eq(u.affinity_rank("fire"), 10, "affinity caps at rank 10")


## D179/D194: every fight, won or lost, levels every squad unit (deployed or
## benched) once (LEVEL_ON_LOSS true); recruits join at the squad's level.
func test_level_per_fight(t) -> void:
	t.eq(BWProgression.LEVEL_ON_LOSS, true, "D194: a loss levels too")
	var ids: Array = BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 77)
	var deployed: Array = run.squad.slice(0, 3)
	var before := run.squad.map(func(u): return u.stats.duplicate())
	var en := run.enemies_for(1)
	var rep := run.after_fight(true, deployed, en, en, [])
	t.ok(run.squad.all(func(u): return u.level == 2), "every unit, benched too, is level 2")
	t.eq(rep.levels.size(), 6, "the report lists each unit's gains")
	for i in run.squad.size():
		var u: BWUnit = run.squad[i]
		t.ok(BWUnit.STATS.all(func(k): return int(u.stats[k]) > int(before[i][k])), "%s: every stat grew" % u.id)
	var en2 := run.enemies_for(2)
	var rep2 := run.after_fight(false, deployed, [], en2, [])
	t.ok(run.squad.all(func(u): return u.level == 3), "a loss levels too (D194)")
	t.eq(rep2.levels.size(), 6, "and it is reported")
	run.last_enemies = en2.map(func(e): return e.to_dict())
	var nu := run.recruit()
	if nu != null:
		t.eq(nu.level, 3, "a recruit joins at the squad's level")

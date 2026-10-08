extends RefCounted
## D419-D420: benched weapon classes (weapons.csv `benched`: pistols, fists)
## never appear in play, and a save holding them converts on load
## (pistols -> bow, fists -> daggers).

const BENCHED := ["pistols", "fists"]


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


func _benched_item(it: Dictionary) -> bool:
	return str(it.get("weight", "")) in BENCHED


func test_bench_column(t) -> void:
	for wc in BENCHED:
		t.ok(BWRun.is_benched(wc), "%s is benched" % wc)
		t.ok(not wc in BWRun.weapon_classes(), "%s is not an active class" % wc)
		t.ok(wc in BWRun.all_weapon_classes(), "%s keeps its weapons.csv row" % wc)
		t.ok(not BWSkills.kit(wc).is_empty(), "%s keeps its skills" % wc)
	t.eq(BWRun.weapon_classes().size(), 6, "six active classes")
	t.eq(BWRun.active_class("pistols"), "bow", "pistols stand in as bow")
	t.eq(BWRun.active_class("fists"), "daggers", "fists stand in as daggers")
	t.ok(BWRun.gear_rows().all(func(r): return not _benched_item(r) or str(r.slot) != "main_hand"), "no benched weapon in the gear pool")
	for id in ["pummeling", "rebound", "welling"]:
		t.ok(not BWRun.enchant_active(BWData.row("enchantments", id)), "%s (fists only) is never offered" % id)
	t.ok(BWRun.enchant_active(BWData.row("enchantments", "quickdraw")), "a shared enchantment still is")


func test_rolls_have_no_benched_class(t) -> void:
	for s in [1, 2, 3, 7, 42, 99, 1234, 5150]:
		var rows := BWRosterGen.roll(BWData.identities(), s, BWData.pool_identities())
		t.ok(rows.all(func(r): return not BWRun.is_benched(str(r.weapon_class))), "seed %d: the roster has no benched class" % s)
		t.ok(rows.all(func(r): return str(BWData.row("equipment", str(r.weapon_model)).get("weight", "")) == str(r.weapon_class)),
			"seed %d: models match the re-rolled class" % s)
		var res := BWRosterGen.reserve(BWData.all_identities(), rows, s)
		t.ok(res.all(func(r): return not BWRun.is_benched(str(r.weapon_class))), "seed %d: the reserve has no benched class" % s)


func test_run_never_offers_benched(t) -> void:
	for s in [1, 5, 77]:
		var r := BWRun.start(_ids(), s)
		var items: Array = []
		for k in 40:
			items.append(r.random_item("C"))
		for k in 8:
			r.restock_shop()
			items += r.shop
		t.ok(not items.any(_benched_item), "seed %d: drops and the shop hold no benched weapon" % s)
		var enemies: Array = []
		for n in [1, 3, 5, 6, 9]:
			enemies += r.enemies_for(n)
		t.ok(enemies.all(func(u): return not BWRun.is_benched(u.weapon_class)), "seed %d: no enemy holds a benched class" % s)
		t.ok(enemies.all(func(u): return u.equipment.values().all(func(it): return not _benched_item(it))), "seed %d: no enemy carries one" % s)
		for u in r.squad:
			for o in r.branch_options(u):
				t.ok(not BWRun.is_benched(str(o.weapon)), "seed %d: Branch out never offers %s" % [s, o.weapon])


func test_encounters_have_no_benched_class(t) -> void:
	var r := BWRun.start(_ids(), 3)
	for kind in ["blank", "being", "horde"]:
		var es: Array = BWEncounters.build(r, 5, kind)
		t.ok(es.all(func(u): return not BWRun.is_benched(u.weapon_class)), "%s: no benched class" % kind)
	var guards: Array = BWCastleStorm.build(r, 8)
	t.ok(guards.all(func(u): return not BWRun.is_benched(u.weapon_class)), "castle guards: no benched class (pistols -> bow)")


func test_save_converts_benched(t) -> void:
	var r := BWRun.start(_ids(), 1234)
	var u: BWUnit = r.squad[0]
	var pistol := r.make_item("m1911", "C", "quickdraw")
	var fists := r.make_item("brass_knuckles", "E", "pummeling")
	u.equipment["main_hand"] = pistol
	u.equipment[BWUnit.SECOND] = fists
	u.sync_weapon()
	u.expertise["pistols"] = 25
	u.expertise["bow"] = 12
	u.known_skills.append("pistol_whip")
	u.skill_ranks["pistol_whip"] = 2
	u.skill_loadout["pistols"] = ["pistol_whip"]
	u.skill_picks["pistols"] = 2
	var loose := r.make_item("hand_wraps", "D", "quickdraw")
	r.inventory.append(loose)
	r.roster_rows[0]["weapon_class"] = "pistols"
	r.roster_rows[0]["weapon_model"] = "flintlock"
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	var bu: BWUnit = back.unit(u.id)
	t.eq(bu.weapon_class, "bow", "the pistol unit now holds a bow")
	var mh: Dictionary = bu.equipment.main_hand
	t.eq(str(mh.weight), "bow", "the main hand is a bow")
	t.eq(str(mh.uid), str(pistol.uid), "the same item (uid kept)")
	t.eq(str(mh.tier), "C", "tier kept")
	t.eq(str(mh.enchant), "quickdraw", "Quickdraw kept: valid on a bow model (%s)" % mh.base)
	t.eq(str(mh.get("imbue", "")), str(pistol.get("imbue", "")), "the imbue kept")
	var sec: Dictionary = bu.equipment[BWUnit.SECOND]
	t.eq(str(sec.weight), "daggers", "the fists became daggers")
	t.ok(str(sec.enchant) != "pummeling" and str(sec.enchant) != "", "fists-only Pummeling re-rolled for the daggers (%s)" % sec.enchant)
	t.eq(int(bu.expertise.get("bow", 0)), 25, "expertise merged: the higher points")
	t.ok(not bu.expertise.has("pistols"), "no pistols expertise left")
	t.ok(not "pistol_whip" in bu.known_skills and not bu.skill_ranks.has("pistol_whip"), "pistol skills dropped")
	t.ok(not bu.skill_loadout.has("pistols") and not bu.skill_picks.has("pistols"), "pistol loadout and picks dropped")
	var bl: Array = back.inventory.filter(func(it): return str(it.uid) == str(loose.uid))
	t.ok(bl.size() == 1 and str(bl[0].weight) == "daggers" and str(bl[0].enchant) == "quickdraw", "loose hand wraps -> daggers, Quickdraw kept")
	t.eq(str(back.roster_rows[0].weapon_class), "bow", "a roster row converts too")
	t.eq(str(BWData.row("equipment", str(back.roster_rows[0].weapon_model)).weight), "bow", "with a bow model")
	t.ok(not BWPicks.pending(bu).any(func(q): return str(q.get("weapon", "")) == "pistols"), "no pistol picks owed")


## D419 (author: "Don't forget to take them off roster rolling."): no roster
## identity, core or rolling pool, locked or not, can roll a benched class,
## on any of many seeds: the full roll, the seated roll, the reserve, a
## single re-roll of every identity, and the enemies a run fields.
func test_no_benched_on_any_roster_seed(t) -> void:
	var bad := 0
	var checked := 0
	var all: Array = BWData.all_identities()
	for s in range(1, 201):
		var rows := BWRosterGen.roll(BWData.identities(), s, BWData.pool_identities())
		rows += BWRosterGen.reserve(all, rows, s)
		for r in rows:
			checked += 1
			if BWRun.is_benched(str(r.weapon_class)) or str(BWData.row("equipment", str(r.weapon_model)).get("weight", "")) in BENCHED:
				bad += 1
	for i in all.size():
		for stream in 25:
			checked += 1
			var one := BWRosterGen.roll_one(all[i], stream * 1000 + i)
			if BWRun.is_benched(str(one.weapon_class)):
				bad += 1
	t.eq(bad, 0, "%d roster rolls over 200 seeds and every identity: none benched" % checked)
	var ebad := 0
	for s in [2, 11, 23, 61, 404]:
		var r := BWRun.start(_ids(), s)
		for n in range(1, 11):
			for u in r.enemies_for(n):
				if BWRun.is_benched(u.weapon_class) or u.equipment.values().any(_benched_item):
					ebad += 1
		for u in r.squad:
			if BWRun.is_benched(u.weapon_class):
				ebad += 1
	t.eq(ebad, 0, "no squad unit or enemy (fights 1-10, 5 seeds) holds a benched class")

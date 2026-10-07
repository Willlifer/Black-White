extends RefCounted
## D149–D154: the renamed roster's identities and the seeded roll
## (BWRosterGen), the run keeping it, old saves refused.

const SEEDS := [1, 2, 3, 7, 42, 99, 1234, 5150, 80085, 271828]


func _ids() -> Array:
	return BWData.identities()


func test_identities(t) -> void:
	var ids := _ids()
	t.eq(ids.size(), 20, "20 identities")
	var names := ["Aureli", "Della", "Jericho", "Will", "Gail", "Kira", "Demeter", "Stryker", "Burt", "Rui",
		"Bob", "Sala", "Rem", "Wilona", "Lionel", "Dragtol", "Apollyon", "Kai", "Alexandra", "Opus"]
	var hairs := {}
	for i in ids.size():
		var r: Dictionary = ids[i]
		t.eq(str(r.name), names[i], "seat %d is %s" % [i + 1, names[i]])
		t.eq(str(r.id), names[i].to_lower(), "%s: id is the lowercase name" % names[i])
		t.eq(int(r.seat), i + 1, "%s: seat" % names[i])
		t.ok(str(r.gender) in ["f", "m", "a"], "%s: gender f/m/a" % names[i])
		t.ok(str(r.friendliness) in ["unfriendly", "neutral", "friendly"], "%s: friendliness" % names[i])
		t.ok(float(r.voice_pitch) >= 0.75 and float(r.voice_pitch) <= 1.35, "%s: voice 0.75-1.35" % names[i])
		t.ok(not r.has("tagline"), "%s: no personality line (D153)" % names[i])
		hairs[str(r.hair_style)] = true
	t.eq(hairs.size(), 10, "all 10 hair archetypes used (%s)" % [hairs.keys()])
	t.eq(str(BWRosterGen.row_by_id(ids, "alexandra").hair_style), "long_hair", "Alexandra keeps her long hair")
	for f in ["aureli", "della", "gail", "kira", "rui", "sala", "rem", "wilona", "alexandra"]:
		t.eq(str(BWRosterGen.row_by_id(ids, f).gender), "f", "%s is f" % f)
	for m in ["jericho", "will", "stryker", "burt", "bob", "lionel"]:
		t.eq(str(BWRosterGen.row_by_id(ids, m).gender), "m", "%s is m" % m)


func test_roll_is_deterministic(t) -> void:
	var a := BWRosterGen.roll(_ids(), 77)
	var b := BWRosterGen.roll(_ids(), 77)
	t.eq(a, b, "the same seed gives the same twenty")
	var c := BWRosterGen.roll(_ids(), 78)
	t.ok(a != c, "another seed gives another roll")
	t.eq(_ids().size(), 20, "roll leaves the identities alone")
	t.ok(not _ids()[0].has("weapon_class"), "identity rows stay identity-only")


func test_identity_is_fixed(t) -> void:
	var ids := _ids()
	for s in SEEDS:
		var rows := BWRosterGen.roll(ids, s)
		var ok := true
		for i in rows.size():
			for k in ["id", "name", "gender", "seat", "hair_style", "friendliness", "voice_pitch"]:
				if str(rows[i][k]) != str(ids[i][k]):
					ok = false
		t.ok(ok, "seed %d: name, gender, seat, hair, friendliness, voice unchanged" % s)


func test_locks_hold(t) -> void:
	for s in SEEDS + range(200, 260):
		var rows := BWRosterGen.roll(_ids(), s)
		t.eq(str(BWRosterGen.row_by_id(rows, "aureli").element), "light", "seed %d: Aureli is light" % s)
		t.eq(str(BWRosterGen.row_by_id(rows, "rem").element), "ice", "seed %d: Rem is ice" % s)


func test_weapons_and_elements_spread(t) -> void:
	var models_seen := {}
	var el_by_char := {}
	for s in SEEDS:
		var rows := BWRosterGen.roll(_ids(), s)
		var classes := {}
		var els := {}
		for r in rows:
			classes[str(r.weapon_class)] = int(classes.get(str(r.weapon_class), 0)) + 1
			els[str(r.element)] = true
			var w := BWData.row("equipment", str(r.weapon_model))
			t.ok(str(w.get("weight", "")) == str(r.weapon_class), "seed %d %s: %s is a %s" % [s, r.id, r.weapon_model, r.weapon_class])
			models_seen[str(r.weapon_model)] = true
			if str(r.id) == "della":
				el_by_char[str(r.element)] = true
		t.eq(classes.size(), 7, "seed %d: all 7 classes held" % s)
		t.ok(classes.values().all(func(n): return n >= 2), "seed %d: each class at least twice (%s)" % [s, classes])
		t.eq(els.size(), 7, "seed %d: all 7 elements" % s)
		t.ok(not classes.has("fists"), "seed %d: nobody starts with fists (D76)" % s)
	t.ok(models_seen.size() >= 20, "the models vary across seeds (%d seen)" % models_seen.size())
	t.ok(el_by_char.size() >= 3, "an unlocked character's element varies (%s)" % [el_by_char.keys()])


func test_stats_follow_profile(t) -> void:
	for s in SEEDS + range(300, 340):
		var rows := BWRosterGen.roll(_ids(), s)
		for r in rows:
			var prof: Array = BWRosterGen.PROFILES[str(r.weapon_class)]
			var total := 0
			var ptotal := 0
			var off := 0
			var ok := true
			for k in BWRosterGen.STATS.size():
				var v := int(r[BWRosterGen.STATS[k]])
				total += v
				ptotal += int(prof[k])
				if v < 1 or v > 6 or absi(v - int(prof[k])) > 1:
					ok = false
				if v != int(prof[k]):
					off += 1
			t.ok(ok and absi(total - ptotal) <= 1 and off <= 3,
				"seed %d %s: %s profile within ±1 per stat, total ±1, ≤3 stats moved" % [s, r.id, r.weapon_class])


func test_clothing_coverage_and_shades(t) -> void:
	var tops_all := {}
	var bottoms_all := {}
	for s in SEEDS:
		var rows := BWRosterGen.roll(_ids(), s)
		var tops := {}
		var bottoms := {}
		var shades := {}
		for r in rows:
			tops[str(r.top)] = true
			bottoms[str(r.bottom)] = true
			shades[str(r.clothing_shade)] = int(shades.get(str(r.clothing_shade), 0)) + 1
			t.ok(str(r.top) in BWClothing.TOPS and str(r.bottom) in BWClothing.BOTTOMS, "seed %d %s: real garments" % [s, r.id])
		t.eq(tops.size(), 7, "seed %d: every top worn" % s)
		t.eq(bottoms.size(), 7, "seed %d: every bottom worn" % s)
		t.ok(shades.size() == 3 and shades.values().all(func(n): return n >= 6), "seed %d: dark/mid/light all ≥6 (%s)" % [s, shades])
		tops_all.merge(tops)
		bottoms_all.merge(bottoms)
	t.eq(tops_all.size() + bottoms_all.size(), 14, "every clothing type across seeds")


func test_gender_leaning(t) -> void:
	var fem := ["crop_top", "crop_hoodie", "tight_shorts", "short_shorts"]
	var masc := ["baggy_sweatpants", "shorts", "tshirt"]
	var n := { "f": 0, "m": 0, "a": 0 }
	var f_fem := { "f": 0, "m": 0, "a": 0 }
	var f_masc := { "f": 0, "m": 0, "a": 0 }
	for s in range(500, 560):
		for r in BWRosterGen.roll(_ids(), s):
			var g := str(r.gender)
			n[g] += 2
			for piece in [str(r.top), str(r.bottom)]:
				if piece in fem:
					f_fem[g] += 1
				if piece in masc:
					f_masc[g] += 1
	var rate := func(d: Dictionary, g: String) -> float: return float(d[g]) / maxf(1.0, float(n[g]))
	t.ok(rate.call(f_fem, "f") > rate.call(f_fem, "m") * 2.0, "f wear the cropped and short pieces more than m (%.2f vs %.2f)" % [rate.call(f_fem, "f"), rate.call(f_fem, "m")])
	t.ok(rate.call(f_masc, "m") > rate.call(f_masc, "f") * 1.5, "m wear the baggy / shorts / tees more than f (%.2f vs %.2f)" % [rate.call(f_masc, "m"), rate.call(f_masc, "f")])
	t.ok(rate.call(f_fem, "m") > 0.0, "outliers happen: some m in f-leaning pieces")
	var a_fem: float = rate.call(f_fem, "a")
	t.ok(a_fem < rate.call(f_fem, "f") and a_fem > rate.call(f_fem, "m") * 0.5, "ambiguous sits between (%.2f)" % a_fem)


func test_run_keeps_the_roll(t) -> void:
	var rows := BWRosterGen.roll(_ids(), 4242)
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 9, rows, 4242)
	t.eq(run.roster_seed, 4242, "the run stores the roster seed")
	for u in run.squad:
		var r := BWRosterGen.row_by_id(rows, u.id)
		t.ok(u.weapon_model == str(r.weapon_model) and u.element == str(r.element) and str(u.cosmetics.top) == str(r.top),
			"%s starts with its rolled weapon, element, clothes" % u.id)
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	t.ok(BWRun.can_load(run.to_dict()), "a v5 save loads")
	t.eq(back.roster_seed, 4242, "load: roster seed")
	t.eq(back.roster_rows, rows, "load: the 20 rolled rows, identical")
	for i in run.squad.size():
		var a: BWUnit = run.squad[i]
		var b: BWUnit = back.squad[i]
		var same_stats := BWUnit.STATS.all(func(k): return int(a.stats[k]) == int(b.stats[k]))
		t.ok(a.element == b.element and a.weapon_model == b.weapon_model and same_stats and str(a.cosmetics.top) == str(b.cosmetics.top) 			and str(a.cosmetics.clothing_shade) == str(b.cosmetics.clothing_shade),
			"load: %s identical" % a.id)
	t.eq(back.enemies_for(3).map(func(e): return e.weapon_model), run.enemies_for(3).map(func(e): return e.weapon_model), "load: same enemies")


func test_old_save_refused(t) -> void:
	var run := BWRun.start(["aureli", "della", "jericho"], 5)
	var d := run.to_dict()
	t.eq(int(d.version), BWRun.SAVE_VERSION, "saves the current version (5+ since D150; 7 since D189)")
	t.ok(int(d.version) >= 5, "save version 5 or later (D150)")
	var old: Dictionary = d.duplicate(true)
	old.version = 4
	old.erase("roster")
	old.erase("roster_seed")
	for ud in old.squad:
		ud.id = "bartholomew"
	t.ok(not BWRun.can_load(old), "a v4 save (old names) is refused, not loaded")
	t.ok(not BWRun.can_load(null) and not BWRun.can_load("junk"), "a broken save is refused")


func test_enemies_use_rolled_rows(t) -> void:
	var rows := BWRosterGen.roll(_ids(), 31337)
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 11, rows, 31337)
	var differs := false
	for n in [1, 4, 9]:                     # D327: 8 and 10 are 6v6 modes (grunts, castle units)
		for e in run.enemies_for(n):
			var base: String = e.id.split("_f")[0]
			var r := BWRosterGen.row_by_id(rows, base)
			t.ok(not r.is_empty(), "fight %d: %s is a roster character outside the squad" % [n, base])
			t.ok(e.weapon_model == str(r.weapon_model) and e.element == str(r.element), "fight %d: %s fights with its rolled kit" % [n, base])
			t.eq(str(e.cosmetics.get("top", "")), str(r.top), "fight %d: %s wears its rolled clothes" % [n, base])
			var dflt := BWData.row("roster", base)
			if str(dflt.weapon_model) != str(r.weapon_model) or str(dflt.element) != str(r.element):
				differs = true
	t.ok(differs, "the run's roll, not the default table")


func test_default_roster(t) -> void:
	var rows := BWData.table("roster")
	t.eq(rows.size(), 20, "BWData.table(roster) is the active 20")
	t.ok(rows[0].has("weapon_class") and rows[0].has("top"), "rolled columns present")
	t.eq(BWData.row("roster", "rem").element, "ice", "row() reads the active roll")

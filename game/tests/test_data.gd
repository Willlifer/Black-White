extends RefCounted
## The data tables obey design/SCHEMA.md. Tables that do not exist yet are
## skipped, not failed: Phase 1 lanes land them one by one.

const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]


func test_weapons(t) -> void:
	var w := BWData.table("weapons")
	t.eq(w.size(), 8, "eight weapon classes (fists: D76)")
	for row in w:
		t.ok(row.damage_type in ["martial", "dexterous", "spell"], "%s damage_type" % row.id)
		t.ok(row.levels in BWUnit.STATS, "%s levels a real stat" % row.id)


func test_roster(t) -> void:
	if not BWData.has_table("roster"):
		t.ok(true, "roster not written yet")
		return
	var r := BWData.table("roster")
	t.eq(r.size(), 20, "twenty characters")
	var names := {}
	for row in r:
		names[row.name] = true
		t.ok(row.element in ELEMENTS, "%s element" % row.id)
		t.ok(not BWData.row("weapons", row.weapon_class).is_empty(), "%s weapon class" % row.id)
		t.ok(row.friendliness in ["unfriendly", "neutral", "friendly"], "%s friendliness" % row.id)
		var total := 0
		for s in BWUnit.STATS:
			var v: int = row[s]
			t.ok(v >= 1 and v <= 6, "%s %s in 1..6" % [row.id, s])
			total += v
		# D151: the class profile's total (24-26) within ±1
		t.ok(total >= 23 and total <= 27, "%s stat total %d in 23..27" % [row.id, total])
	for seed_name in ["Aureli", "Della", "Jericho", "Will", "Gail", "Kira"]:
		t.ok(names.has(seed_name), "author's name %s is in" % seed_name)


func test_roster_builds_units(t) -> void:
	if not BWData.has_table("roster"):
		t.ok(true, "roster not written yet")
		return
	for row in BWData.table("roster"):
		var u := BWUnit.from_roster(row)
		t.ok(u.max_hp() >= 117 and u.max_hp() <= 127, "%s hp %d" % [u.id, u.max_hp()])
		t.ok(u.move_range() >= 4, "%s can move" % u.id)


func test_tables_are_not_translations(t) -> void:
	# Godot imports .csv as translations unless told otherwise (tools/keep_csv.py).
	for f in DirAccess.get_files_at(BWData.DATA_DIR):
		if f.ends_with(".csv"):
			var imp := FileAccess.get_file_as_string(BWData.DATA_DIR + f + ".import")
			t.ok(imp.contains("importer=\"keep\""), "%s is import=keep (run tools/keep_csv.py)" % f)
		t.ok(not f.ends_with(".translation"), "no stray translation file %s" % f)


## Cross-references between the Phase 1 tables: every id one table names
## must exist in the table it points at.
func test_equipment_tables(t) -> void:
	if not BWData.has_table("equipment"):
		t.ok(true, "equipment not written yet")
		return
	var weapons := BWData.table("weapons").map(func(r): return str(r.id))
	var abilities := {}
	for a in BWData.table("abilities"):
		abilities[str(a.id)] = a
		t.ok(a.type in ["reactive", "supportive", "passive"], "ability %s type" % a.id)
		for src in BWData.list(a.source_item):
			t.ok(not BWData.row("equipment", src).is_empty(), "ability %s source %s exists" % [a.id, src])
	for it in BWData.table("equipment"):
		t.ok(it.slot in ["head", "chest", "legs", "main_hand"], "%s slot" % it.id)
		if it.slot == "main_hand":
			t.ok(str(it.weight) in weapons, "%s weapon class %s" % [it.id, it.weight])
		else:
			t.ok(it.weight in ["heavy", "ranger", "wizard"], "%s armour weight" % it.id)
			t.ok(BWData.list(it.ability_id).size() >= 1, "%s teaches an ability" % it.id)
		for s in BWData.list(it.stat_lines):
			t.ok(s in BWUnit.STATS, "%s stat line %s" % [it.id, s])
		for ab in BWData.list(it.ability_id):
			t.ok(abilities.has(ab), "%s ability %s exists" % [it.id, ab])
	var per_item := {}
	for e in BWData.table("enchantments"):
		for target in BWData.list(e.applies_to):
			t.ok(not BWData.row("equipment", target).is_empty(), "enchant %s target %s exists" % [e.id, target])
			per_item[target] = int(per_item.get(target, 0)) + 1
	for it in BWData.table("equipment"):
		t.ok(int(per_item.get(str(it.id), 0)) >= 3, "%s has 3+ enchantments (%d)" % [it.id, per_item.get(str(it.id), 0)])


func test_barks_table(t) -> void:
	if not BWData.has_table("barks"):
		t.ok(true, "barks not written yet")
		return
	var events := ["ally_attacking", "ally_ko", "healing_received", "downtime_advice", "self_ko",
		"crit_landed", "dodged", "enemy_ko", "battle_start", "battle_won", "level_up", "recruited"]
	var clips := ["Dying", "Hey", "Hiyah", "Hmm", "Laugh", "Mmhmm", "No", "Oof", "Oogh", "Ouch grunt", "Yah", "Yeah"]
	var f := ["unfriendly", "neutral", "friendly"]
	for b in BWData.table("barks"):
		t.ok(b.event in events, "%s event" % b.id)
		t.ok(b.speaker_friendliness in f, "%s speaker" % b.id)
		t.ok(b.toward_friendliness in f or b.toward_friendliness == "any", "%s toward" % b.id)
		t.ok(b.trust in ["strangers", "acquainted", "trusted"], "%s trust" % b.id)
		t.ok(b.voice_clip in clips, "%s clip %s" % [b.id, b.voice_clip])


func test_elements_table(t) -> void:
	var els := BWData.table("elements")
	t.eq(els.size(), 7, "seven elements, no life")
	for e in els:
		t.ok(e.id in BWFormulas.ELEMENTS, "%s is a known element" % e.id)
		t.ok(str(e.hair_hex).begins_with("#"), "%s hair colour" % e.id)


## D76: the fists class, its three items, and 3+ enchantments on each.
func test_fists_rows(t) -> void:
	var w := BWData.row("weapons", "fists")
	t.ok(not w.is_empty(), "fists is a weapons.csv row")
	t.eq(str(w.get("damage_type")), "martial", "fists are martial (STR)")
	t.eq(Array(BWData.list(w.get("skills", ""))), ["flurry", "uppercut", "palm_burst"], "fists skills column")
	for k in BWData.list(w.get("skills", "")):
		t.ok(BWSkills.has_skill(k) and BWSkills.get_skill(k).weapon == "fists", "%s is a fists skill" % k)
	var items := BWData.table("equipment").filter(func(r): return str(r.weight) == "fists")
	t.eq(items.map(func(r): return str(r.id)), ["hand_wraps", "brass_knuckles", "gauntlets"], "three fists items")
	var keys := ["tile_duration_plus", "tile_erupt", "effect_repeat", "cast_step_plus", "element_area_plus",
		"tile_potency_pct", "lay_on", "stand_on_bonus", "damage_taken_mod", "immune", "element_damage_pct",
		"affinity_gain_plus", "aoe_radius_plus", "range_mod", "multi_hit", "move_after_attack", "knockback",
		"counter_attack", "attack_mod", "skill_cd_minus", "guard", "trigger_stat", "aura_mod", "glance_mod", "stat_share"]
	for it in items:
		t.eq(str(it.slot), "main_hand", "%s is a main-hand item" % it.id)
		t.ok("str" in BWData.list(it.stat_lines), "%s rolls str" % it.id)
		var n := 0
		for e in BWData.table("enchantments"):
			if str(it.id) in BWData.list(e.applies_to):
				n += 1
				t.ok(str(e.effect_key) in keys or str(e.effect_key) in BWEffects.KEYS, "%s: %s reuses the effect_key vocabulary (%s)" % [it.id, e.id, e.effect_key])
				t.eq(str(e.element), "", "%s: %s is a weapon row (no element)" % [it.id, e.id])
		t.ok(n >= 3, "%s rolls %d enchantments (3+)" % [it.id, n])
	# the skill riders name a real fists skill and stay off the basic attack
	for id in ["pummeling", "rebound", "welling"]:
		var e := BWData.row("enchantments", id)
		var p := BWEffects.parse_params(e.params)
		t.ok(BWSkills.has_skill(str(p.get("skill", ""))), "%s names a skill" % id)
		if str(e.effect_key) == "knockback":
			t.eq(str(p.get("on", "")), "skill", "%s: on=skill (not hit)" % id)
	t.eq(BWRun.new().make_item("hand_wraps", "E").weight, "fists", "make_item builds fists")

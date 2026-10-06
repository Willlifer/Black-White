extends RefCounted
## D122-D126: cutscene tiers, settings defaults, the glossary (markup and
## the CSV). Pure: no nodes.


func _blow(crit := false, ko := false, hit := true) -> Dictionary:
	return { "target": "x", "result": { "hit": hit, "crit": crit, "damage": 10, "glance": false, "resisted": false }, "ko": ko }


func _attack(crit := false, ko := false) -> Dictionary:
	var e := _blow(crit, ko)
	e["type"] = "attack"
	e["unit"] = "a"
	return e


func _skill(row: Dictionary, results: Array = [], ko := false) -> Dictionary:
	return { "type": "skill", "skill": str(row.get("key", "x")), "results": results, "ko": ko, "_row": row }


func _tier(e: Dictionary, mode := "default") -> int:
	return int(BWCutsceneTier.tier_for(e, mode, e.get("_row", null)).tier)


func test_tier_defaults(t) -> void:
	var M := BWCutsceneTier.MINIMAL
	var S := BWCutsceneTier.SHORT
	var F := BWCutsceneTier.FULL
	t.eq(_tier(_attack()), M, "a basic attack is minimal")
	var extra := _attack()
	extra["strike"] = 1
	extra["strikes"] = 2
	t.eq(_tier(extra), M, "an extra strike is minimal")
	var c := _blow()
	c["type"] = "counter"
	c["cause"] = "overwatch"
	t.eq(_tier(c), M, "an overwatch shot is minimal")
	t.eq(_tier({ "type": "riposte", "results": [_blow()] }), M, "a riposte answer is minimal")
	t.eq(_tier(_skill({ "key": "war_cry", "cd": 4, "power": 0 })), M, "a setup skill (no power) is minimal even at cd 4")
	t.eq(_tier(_skill({ "key": "bolt", "cd": 1, "power": 10 }, [_blow()])), S, "a damaging cd 1 skill is short")
	t.eq(_tier(_skill({ "key": "heart_seeker", "cd": 2, "power": 10 }, [_blow()])), S, "cd 2 is short")
	t.eq(_tier(_skill({ "key": "sunder", "cd": 3, "power": 13 }, [_blow()])), F, "cd 3 is full")
	t.eq(_tier(_skill({ "key": "tempest", "cd": 0, "power": 9, "once_per_battle": true }, [_blow()])), F, "once per battle is full")
	t.eq(_tier(_skill({ "key": "quick", "basic": true, "power": 0 }, [_blow()])), M, "a basic-type skill is minimal")


func test_tier_upgrades_and_modes(t) -> void:
	var M := BWCutsceneTier.MINIMAL
	var S := BWCutsceneTier.SHORT
	var F := BWCutsceneTier.FULL
	t.eq(_tier(_attack(true)), F, "a crit upgrades a basic attack to full")
	t.eq(_tier(_attack(false, true)), F, "a KO upgrades a basic attack to full")
	var miss_crit := _blow(true, false, false)
	miss_crit["type"] = "attack"
	t.eq(_tier(miss_crit), M, "a 'crit' flag on a miss doesn't count")
	var bolt := { "key": "bolt", "cd": 1, "power": 10 }
	t.eq(_tier(_skill(bolt, [_blow(), _blow(true)])), F, "a crit on any target upgrades")
	t.eq(_tier(_skill(bolt, [_blow()], true)), F, "the skill event's own ko flag upgrades")
	var c := _blow(true)
	c["type"] = "counter"
	t.eq(_tier(c), F, "a critting counter upgrades too")
	# fast: one tier lower
	t.eq(_tier(_attack(true), "fast"), S, "fast: full -> short")
	t.eq(_tier(_skill(bolt, [_blow()]), "fast"), M, "fast: short -> minimal")
	t.eq(_tier(_attack(), "fast"), M, "fast: minimal stays minimal")
	# minimal: everything minimal, crits keep a tiny flash
	var tc: Dictionary = BWCutsceneTier.tier_for(_attack(true), "minimal")
	t.eq(int(tc.tier), M, "minimal mode: a crit is minimal")
	t.eq(str(tc.flash), "tiny", "minimal mode: a crit keeps a tiny flash")
	t.eq(str(BWCutsceneTier.tier_for(_attack(true)).flash), "full", "default: a crit gets the full flash")
	t.eq(str(BWCutsceneTier.tier_for(_attack()).flash), "none", "no crit, no flash")
	t.eq(str(BWCutsceneTier.tier_for(_attack(true), "fast").flash), "tiny", "fast: the crit (now short) flashes tiny")
	t.ok(BWCutsceneTier.tier_for(_skill(bolt, [_blow()]), "default", bolt).callout, "a short skill calls out")
	t.ok(not BWCutsceneTier.tier_for(_attack(true)).callout, "a basic attack never calls out")
	t.eq(BWCutsceneTier.next_mode("default"), "fast", "F: default -> fast")
	t.eq(BWCutsceneTier.next_mode("fast"), "minimal", "F: fast -> minimal")
	t.eq(BWCutsceneTier.next_mode("minimal"), "default", "F: minimal -> default")


## The real skill rows the author named land where the author put them.
func test_tier_real_skills(t) -> void:
	var M := BWCutsceneTier.MINIMAL
	var F := BWCutsceneTier.FULL
	for k in ["transfer", "inversion", "set_spear", "aegis", "phalanx", "brace", "tumble", "war_cry", "covering_fire", "reload"]:
		if BWSkills.has_skill(k):
			t.eq(BWCutsceneTier.skill_base(BWSkills.get_skill(k)), M, "%s is minimal (setup)" % k)
	for k in ["tempest", "rain_of_arrows", "assassinate", "hundred_fists", "empty_the_chamber", "triumph", "dragoon_dive"]:
		if BWSkills.has_skill(k):
			t.eq(BWCutsceneTier.skill_base(BWSkills.get_skill(k)), F, "%s is full (once per battle)" % k)


func test_settings_isolated_defaults(t) -> void:
	var was := BWSettings.isolated
	var saved_path := BWSettings.path
	BWSettings.path = "user://test_settings_d124.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BWSettings.path))
	# a "player's" file with odd values
	var cf := ConfigFile.new()
	cf.set_value("settings", "cutscenes", "minimal")
	cf.set_value("settings", "show_odds", false)
	cf.set_value("settings", "vol_music", 0.3)
	cf.save(BWSettings.path)
	BWSettings.init(true)                        # --defaults / probes
	t.eq(str(BWSettings.value("cutscenes")), "default", "isolated: the saved file is ignored")
	t.eq(BWSettings.value("show_odds"), true, "isolated: odds on")
	BWSettings.init(false)
	t.eq(str(BWSettings.value("cutscenes")), "minimal", "loaded: the saved mode")
	t.eq(BWSettings.value("show_odds"), false, "loaded: odds off")
	t.near(float(BWSettings.value("vol_music")), 0.3, 0.001, "loaded: music volume")
	BWSettings._v["cutscenes"] = BWSettings._clean("cutscenes", "bogus")
	t.eq(str(BWSettings.value("cutscenes")), "default", "an unknown mode falls back to default")
	BWSettings.init(true)
	BWSettings._v["cutscenes"] = "fast"
	BWSettings.save()                            # isolated: must not write
	var cf2 := ConfigFile.new()
	cf2.load(BWSettings.path)
	t.eq(str(cf2.get_value("settings", "cutscenes", "")), "minimal", "isolated runs never write the file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BWSettings.path))
	BWSettings.path = saved_path
	BWSettings.init(was)


# ---------------------------------------------------------------- glossary

func _rows() -> Array:
	return [
		{ "id": "gale", "term": "Gale", "aliases": "gales", "category": "operator", "definition": "Copies a charge.", "see": "" },
		{ "id": "gale_2", "term": "Gale 2", "aliases": "", "category": "operator", "definition": "A bigger gale.", "see": "gale" },
		{ "id": "crit", "term": "Crit", "aliases": "crits|critical hit", "category": "roll", "definition": "x1.5.", "see": "" },
		{ "id": "hit", "term": "Hit", "aliases": "hit chance", "category": "roll", "definition": "The roll to land.", "see": "" },
	]


func _count(s: String, sub: String) -> int:
	return s.count(sub)


func test_glossary_markup(t) -> void:
	BWGlossary.build(_rows())
	var m := BWGlossary.markup("Gale 2 then a gale")
	t.ok(m.begins_with("[hint=Gale 2: A bigger gale.]Gale 2[/hint]"), "longest match wins: 'Gale 2' over 'Gale' (%s)" % m)
	t.ok(m.ends_with("[hint=Gale: Copies a charge.]gale[/hint]"), "the plain 'gale' links to Gale, keeping its case")
	t.eq(_count(m, "[hint="), 2, "two links, nothing nested")
	var c := BWGlossary.markup("a CRITICAL HIT and crits")
	t.ok(c.contains("]CRITICAL HIT[/hint]") and c.contains("]crits[/hint]"), "case-insensitive, multi-word aliases (%s)" % c)
	t.eq(BWGlossary.markup(m), m, "idempotent: linked text is never linked again")
	t.eq(BWGlossary.markup("[color=#ffffff]Hit chance[/color]"), "[color=#ffffff][hint=Hit: The roll to land.]Hit chance[/hint][/color]",
		"tags are kept; their text is linked")
	t.eq(BWGlossary.markup("[url=gale]gale[/url]"), "[url=gale]gale[/url]", "no links inside [url]")
	t.eq(BWGlossary.markup("galeforce hitting"), "galeforce hitting", "whole words only")
	t.eq(BWGlossary.markup("[hint=x]crit[/hint] crit"), "[hint=x]crit[/hint] [hint=Crit: x1.5.]crit[/hint]", "an existing hint is left alone")
	t.eq(BWGlossary.terms_in("[b]Gale 2[/b] crit, gale"), ["gale_2", "crit", "gale"], "terms_in lists ids in order")
	t.eq(str(BWGlossary.lookup("critical  hit").get("id", "")), "crit", "lookup by alias, spaces normalised")
	BWGlossary.reset()


func test_glossary_csv(t) -> void:
	t.ok(BWData.has_table("glossary"), "data/glossary.csv exists")
	var imp := FileAccess.get_file_as_string("res://data/glossary.csv.import")
	t.ok(imp.contains("importer=\"keep\""), "glossary.csv is import=keep (tools/keep_csv.py)")
	BWGlossary.reset()
	var rows := BWData.table("glossary")
	t.ok(rows.size() >= 50, "the lexicon has %d terms" % rows.size())
	var seen := {}
	var ids := {}
	for r in rows:
		ids[str(r.id)] = true
	for r in rows:
		for k in ["id", "term", "aliases", "category", "definition", "see"]:
			t.ok(r.has(k), "%s has %s" % [r.get("id", "?"), k])
		var d := str(r.definition)
		t.ok(d.length() >= 30 and not d.contains("[") and not d.contains("]"), "%s: a one-line definition, no brackets" % r.id)
		t.ok(str(r.category) in BWGlossary.CATEGORY_ORDER, "%s: known category %s" % [r.id, r.category])
		t.ok(str(r.see) == "" or ids.has(str(r.see)), "%s: see -> %s exists" % [r.id, r.see])
		for w in [str(r.term)] + Array(BWData.list(r.aliases)):
			var k: String = str(w).to_lower()
			t.ok(not seen.has(k), "'%s' names one term only (%s, %s)" % [k, seen.get(k, ""), r.id])
			seen[k] = r.id
	for need in ["fire", "water", "ice", "thunder", "wind", "dark", "light", "fuse", "detonate", "stasis", "glaze", "gale",
			"gale_2", "shatter", "spark", "conductive", "staggered", "steadied", "blinded", "pinned", "drenched", "scorched",
			"shrouded", "frost_ward", "hit", "avoid", "glance", "crit", "resist", "rear", "front", "affinity_rank", "expertise",
			"perk", "improve", "overcap", "once_per_battle", "cooldown", "momentum", "backstab", "push", "slam", "zone",
			"overwatch", "static_tile", "charge", "decay"]:
		t.ok(ids.has(need), "the lexicon covers %s" % need)
	# the real lexicon links forecast-style text
	var m := BWGlossary.markup("Shatter: +15% on a glazed tile · Pinned")
	t.ok(m.contains("]Shatter[/hint]") and m.contains("]glazed[/hint]") and m.contains("]Pinned[/hint]"), "real terms link (%s)" % m.left(80))
	t.ok(BWGlossary.markup("Front Flank").count("[hint=") == 1, "Front Flank is one link, not Front + Flank")

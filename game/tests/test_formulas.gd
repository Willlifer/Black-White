extends RefCounted
## Every formula from the brief, against numbers worked by hand.


func _att() -> BWUnit:
	var u := BWUnit.from_roster({ "id": "att", "weapon_class": "sword", "element": "fire",
		"con": 4, "str": 5, "dex": 4, "wil": 6, "def": 2, "res": 2, "spd": 3 })
	return u


func _dfn() -> BWUnit:
	var u := BWUnit.from_roster({ "id": "dfn", "weapon_class": "axe", "element": "water",
		"con": 6, "str": 4, "dex": 2, "wil": 1, "def": 3, "res": 2, "spd": 2 })
	return u


func test_hp(t) -> void:
	t.eq(BWFormulas.hp(_dfn()).value, 122, "HP = 100 + 2 × 6 + 10 × 1")
	t.eq(_dfn().max_hp(), 122, "unit max_hp agrees")
	t.eq(str(BWFormulas.hp(_dfn()).values), "100 + 2 × 6 + 10 × 1", "the breakdown shows the level term")
	var u := _dfn()
	u.level = 7
	t.eq(u.max_hp(), 182, "D137: level 7 = 100 + 12 + 70")
	t.eq(BWFormulas.hp(u).value, 182, "the calc agrees")
	u.fixed_hp = 500
	t.eq(u.max_hp(), 500, "D138: a fixed pool overrides the formula")
	t.eq(BWFormulas.hp(u).value, 500, "and the calc shows it")


func test_weapon_damage(t) -> void:
	var a := _att()
	t.near(BWFormulas.damage_base(a, BWFormulas.WEAPON, 12).value, 17.0, 0.001, "martial: 12 + STR 5")
	# 17 − 0.75 × 3 = 14.75 → 15
	t.eq(BWFormulas.damage_taken(a, _dfn(), BWFormulas.WEAPON, 12).value, 15.0, "weapon taken")
	a.weapon_class = "bow"
	t.near(BWFormulas.damage_base(a, BWFormulas.WEAPON, 11).value, 15.0, 0.001, "dexterous: 11 + DEX 4")


func test_skill_damage(t) -> void:
	var a := _att()
	t.near(BWFormulas.damage_base(a, BWFormulas.SKILL, 10).value, 14.5, 0.001, "10 + 2.5 + 2")
	# 14.5 − 0.75 × (2 + 3) / 2 = 12.625 → 13
	t.eq(BWFormulas.damage_taken(a, _dfn(), BWFormulas.SKILL, 10).value, 13.0, "skill taken")


func test_spell_damage_with_affinity(t) -> void:
	var a := _att()
	# (11 + WIL 6) × 1.05 (fire rank 1) = 17.85; − 0.75 × RES 2 = 16.35 → 16
	t.near(BWFormulas.damage_base(a, BWFormulas.SPELL, 11, "fire").value, 17.85, 0.001, "spell base")
	t.eq(BWFormulas.damage_taken(a, _dfn(), BWFormulas.SPELL, 11, "fire").value, 16.0, "spell taken")


func test_min_damage(t) -> void:
	var d := _dfn()
	d.stats["def"] = 900
	t.eq(BWFormulas.damage_taken(_att(), d, BWFormulas.WEAPON, 12).value, 1.0, "never below 1")


func test_hit_avoid(t) -> void:
	var a := _att()
	t.near(BWFormulas.hit_basis(a, BWFormulas.WEAPON).value, 84.0, 0.001, "80 + DEX 4 + 0 expertise")
	a.expertise["sword"] = 25      # rank C = 2
	t.near(BWFormulas.hit_basis(a, BWFormulas.WEAPON).value, 94.0, 0.001, "+5 per expertise rank")
	t.near(BWFormulas.avoid(_dfn()).value, 5.2, 0.001, "5 + 0.1 × DEX 2")
	t.near(BWFormulas.hit_chance(_att(), _dfn(), BWFormulas.WEAPON).value, 78.8, 0.001, "84 − 5.2")
	t.near(BWFormulas.hit_basis(_att(), BWFormulas.SPELL, "fire").value, 89.0, 0.001, "spell uses affinity rank")


func test_glance_crit(t) -> void:
	t.near(BWFormulas.glance_chance(_dfn()).value, 13.0, 0.001, "10 + DEF 3")
	t.near(BWFormulas.crit_chance(_att()).value, 0.4, 0.001, "0.1 × DEX 4")


func test_resist_and_opposites(t) -> void:
	var d := _dfn()     # water rank 1
	# fire attack: 10 + RES 2 + opposite water 2.5
	t.near(BWFormulas.resist_chance(d, "fire").value, 14.5, 0.001, "opposite rank gives 2.5")
	t.near(BWFormulas.resist_chance(d, "water").value, 17.0, 0.001, "same element gives 5")
	t.near(BWFormulas.resist_chance(d, "thunder").value, 12.0, 0.001, "unrelated gives 0")
	d.affinity["ice"] = 20     # ice rank 2 -> 5 against everything else
	t.near(BWFormulas.resist_chance(d, "thunder").value, 17.0, 0.001, "ice resists all")
	t.near(BWFormulas.resist_chance(d, "ice").value, 22.0, 0.001, "ice vs ice is the same-element 5/rank")
	t.ok(not BWFormulas.is_magic(BWFormulas.WEAPON, "fire"), "basic attacks never resist")
	t.ok(BWFormulas.is_magic(BWFormulas.SKILL, "fire"), "elemental skills resist")


func test_every_number_explains_itself(t) -> void:
	var fc := BWFormulas.forecast(_att(), _dfn(), BWFormulas.SPELL, 11, "fire")
	for k in ["hit", "avoid", "glance", "crit", "damage", "resist", "expected"]:
		t.ok(fc.has(k), "forecast has " + k)
		if fc.has(k):
			t.ok(str(fc[k].formula) != "" and str(fc[k].values) != "", k + " has formula and values")


func test_resolve_is_deterministic(t) -> void:
	var fc := BWFormulas.forecast(_att(), _dfn(), BWFormulas.SKILL, 10, "fire")
	var r1 := RandomNumberGenerator.new()
	r1.seed = 42
	var r2 := RandomNumberGenerator.new()
	r2.seed = 42
	var a: Array = []
	var b: Array = []
	for i in 200:
		a.append(BWFormulas.resolve(fc, r1))
		b.append(BWFormulas.resolve(fc, r2))
	t.eq(JSON.stringify(a), JSON.stringify(b), "same seed, same 200 outcomes")


func test_resolve_statistics(t) -> void:
	# 20k rolls land within 1.5 points of the forecast rates.
	var fc := BWFormulas.forecast(_att(), _dfn(), BWFormulas.SKILL, 10, "fire")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 20000
	var hits := 0
	var glances := 0
	var resists := 0
	var total := 0.0
	for i in n:
		var r := BWFormulas.resolve(fc, rng)
		hits += int(r.hit)
		glances += int(r.glance)
		resists += int(r.resisted)
		total += r.damage
	t.near(100.0 * hits / n, fc.hit.value, 1.5, "hit rate")
	t.near(100.0 * glances / maxf(hits, 1), fc.glance.value, 1.5, "glance rate among hits")
	t.near(100.0 * resists / maxf(hits, 1), fc.resist.value, 1.5, "resist rate among hits")
	t.near(total / n, fc.expected.value, 0.6, "mean damage matches expected (rounding slack)")


func test_avoid_keeps_secondary(t) -> void:
	var fc := BWFormulas.forecast(_att(), _dfn(), BWFormulas.SKILL, 10, "fire")
	fc.hit.value = 0.0
	var rng := RandomNumberGenerator.new()
	var r := BWFormulas.resolve(fc, rng)
	t.ok(not r.hit and r.damage == 0 and r.secondary, "avoided: no damage, effects still land")
	fc.hit.value = 100.0
	fc.resist.value = 100.0
	r = BWFormulas.resolve(fc, rng)
	t.ok(r.resisted and not r.secondary, "resisted: secondary effects blocked")

extends RefCounted
## D424 (author: "Ranged attacks damage reduced by 10% if an enemy is within 2
## tiles. Does not apply to AOE-targeted spells."): Pressured, a ×0.9 dmg
## stage on a ranged blow (a ranged class's basic, a single-target skill with
## reach 3+) while any foe stands within 2 of the attacker.

const C := Vector2i(4, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


func _pressured(fc: Dictionary) -> bool:
	return fc.mods.any(func(m): return str(m.get("tag", "")) == BWFormulas.PRESSURE_TAG)


func test_constants(t) -> void:
	t.eq(BWFormulas.PRESSURE_MULT, 0.9, "×0.9")
	t.eq(BWFormulas.PRESSURE_RADIUS, 2, "within 2")
	t.eq(str(BWFormulas.pressure_mod().label), "Pressured (enemy within 2) −10%", "the forecast line")


func test_bow_basic(t) -> void:
	var far: Array = K._line(4)
	var me: BWUnit = K._u("me", "bow", "fire")
	var b: BWBattle = K._fight(me, [K._foe("a")], [far[3]])
	var free: Dictionary = b.forecast_basic(me, b.units[1])
	t.ok(not _pressured(free), "nobody within 2: a clean shot")
	var me2: BWUnit = K._u("me", "bow", "fire")
	var b2: BWBattle = K._fight(me2, [K._foe("a"), K._foe("n")], [far[3], far[1]])
	var fc: Dictionary = b2.forecast_basic(me2, b2.units[1])
	t.ok(_pressured(fc), "a foe 2 away: Pressured")
	t.eq(float(fc.damage.value), maxf(1.0, roundf(float(free.damage.value) * 0.9)), "×0.9 on the damage")
	t.ok((fc.notes as Array).has("Pressured (enemy within 2) −10%"), "a named forecast line: %s" % [fc.notes])
	var me3: BWUnit = K._u("me", "bow", "fire")
	var b3: BWBattle = K._fight(me3, [K._foe("a"), K._foe("n")], [far[3], far[2]])
	t.ok(not _pressured(b3.forecast_basic(me3, b3.units[1])), "3 away doesn't press")
	var me4: BWUnit = K._u("me", "bow", "fire")
	var mate: BWUnit = K._u("m", "sword", "fire")
	var b4: BWBattle = K._fight(me4, [K._foe("a")], [far[3]], 7, [mate], [far[0]])
	t.ok(not _pressured(b4.forecast_basic(me4, b4.units[2])), "an ally beside you doesn't")
	# the target itself pressing counts too (a bow shooting point blank)
	var me5: BWUnit = K._u("me", "bow", "fire")
	var b5: BWBattle = K._fight(me5, [K._foe("a")], [far[0]])
	t.ok(_pressured(b5.forecast_basic(me5, b5.units[1])), "shooting an adjacent foe: Pressured")


func test_melee_and_lance_exempt(t) -> void:
	var near: Array = K._line(2)
	for wc in ["lance", "sword", "axe"]:
		var me: BWUnit = K._u("me", wc, "fire")
		var b: BWBattle = K._fight(me, [K._foe("a")], [near[0] if wc != "lance" else near[1]])
		t.ok(not _pressured(b.forecast_basic(me, b.units[1])), "%s: melee, never Pressured" % wc)


func test_staff_bolt_and_areas(t) -> void:
	var far: Array = K._line(4)
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["bolt", "surge", "tempest"])
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("n")], [far[3], far[0]])
	t.ok(_pressured(b.forecast_basic(me, b.units[1])), "a staff basic is a ranged spell")
	var pv := b.skill_preview(me, "bolt", "fire", far[3])
	t.ok(_pressured(pv.forecasts["a"]), "Bolt (one target, reach 4): Pressured")
	for k in ["surge", "tempest"]:
		var pa := b.skill_preview(me, k, "fire", far[3])
		t.ok(not pa.is_empty(), "%s previews" % k)
		for id in pa.get("forecasts", {}):
			t.ok(not _pressured(pa.forecasts[id]), "%s (an area spell): exempt" % k)
	t.ok(BWBattle.ranged_skill(BWSkills.get_skill("aimed_shot")), "Aimed Shot is ranged single-target")
	t.ok(not BWBattle.ranged_skill(BWSkills.get_skill("rain_of_arrows")), "Rain of Arrows (an area) is exempt")
	t.ok(not BWBattle.ranged_skill(BWSkills.get_skill("arcing_shot")), "Arcing Shot (radius) is exempt")
	t.ok(not BWBattle.ranged_skill(BWSkills.get_skill("ley_line")), "Ley Line (a line) is exempt")
	t.ok(not BWBattle.ranged_skill(BWSkills.get_skill("guardrush")), "Guardrush (reach 2) is melee")


func test_resolve_uses_it(t) -> void:
	var far: Array = K._line(4)
	var me: BWUnit = K._u("me", "bow", "fire", { "dex": 400 })
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("n")], [far[3], far[1]])
	var fc: Dictionary = b.forecast_basic(me, b.units[1])
	var hp0: int = b.units[1].hp
	var r: Dictionary = b.attack(me, b.units[1])
	var res: Dictionary = r.get("result", r)
	if bool(res.get("hit", false)) and not bool(res.get("crit", false)) and not bool(res.get("glanced", res.get("glance", false))):
		t.eq(hp0 - b.units[1].hp, int(fc.damage.value), "the landed clean hit is the pressured number")
	else:
		t.ok(true, "the roll wasn't a clean hit (%s); the forecast carries it" % res)

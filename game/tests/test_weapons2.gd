extends RefCounted
## D180-D184 weapons pass: two weapon slots and no expertise gate, the free
## once-a-turn swap (class, range, skills, forecast, cooldowns), the AI's
## swap, C+ weapons rolling an enchantment AND an elemental imbue that paints,
## re-imbue with two parts, and the save round trip.


func _run() -> BWRun:
	return BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 4242)


func _board() -> BWBoard:
	var cells: Array = []
	for r in 12:
		for c in 12:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "t", "cols": 12, "rows": 12, "cells": cells,
		"spawns": { "player": [[1, 4], [1, 6], [1, 8]], "enemy": [[10, 4], [10, 6], [10, 8]] } })


func _unit(id: String, spd: int, team: String = "player") -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": "sword", "weapon_model": "sword", "element": "fire",
		"con": 5, "str": 5, "dex": 5, "wil": 3, "def": 3, "res": 3, "spd": spd }
	var u := BWUnit.from_roster(row)
	u.team = team
	return u


## A sword in hand (tier E, no enchantment), a bow carried.
func _armed(run: BWRun, id: String, spd: int, team: String = "player") -> BWUnit:
	var u := _unit(id, spd, team)
	u.equipment["main_hand"] = run.make_item("sword", "E", "")
	u.equipment["second"] = run.make_item("shortbow", "E", "")
	u.sync_weapon()
	return u


## One player unit (fast, acts first) and three slow dummies far off.
func _battle(run: BWRun, u: BWUnit, foe_at: Vector2i) -> BWBattle:
	var b := BWBattle.new(_board(), 9)
	var foes: Array = []
	for i in 3:
		var f := _unit("dummy%d" % i, 1, "enemy")
		f.equipment["main_hand"] = run.make_item("sword", "E", "")
		foes.append(f)
	b.setup([u], foes)
	u.pos = Vector2i(2, 6)
	foes[0].pos = foe_at
	foes[1].pos = Vector2i(11, 0)
	foes[2].pos = Vector2i(11, 11)
	return b


func test_two_slots_and_no_expertise_gate(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	var other := "lance" if u.weapon_class != "lance" else "axe"
	var model: String = BWData.table("equipment").filter(func(x): return x.slot == "main_hand" and x.weight == other)[0].id
	var big := r.make_item(model, "A")
	r.inventory.append(big)
	t.eq(u.expertise_rank(other), 0, "no %s expertise at all" % other)
	t.ok(r.can_equip(u, big), "D180: an A %s needs no expertise" % other)
	var str0 := u.stat("str")
	var wc0 := u.weapon_class
	t.ok(r.equip(u, big, "second"), "equip it as the second weapon")
	t.eq(u.second_weapon(), big, "it rides in the second slot")
	t.eq(u.weapon_class, wc0, "the class still follows the main hand")
	t.eq(u.stat("str"), str0, "the carried weapon adds no stats")
	t.ok(not r.equip(u, r.make_item("platemail", "E"), "second"), "armour never goes in the second slot")
	r.unequip(u, "second")
	t.ok(u.second_weapon().is_empty() and big in r.inventory, "the second weapon comes off freely")
	t.ok(r.equip(u, big, "second"), "back on")
	t.ok(r.swap_weapons(u), "swap outside a battle")
	t.eq(u.weapon_class, other, "the drawn weapon sets the class")
	t.eq(u.equipment.main_hand, big, "it is in hand now")
	t.eq(str(u.second_weapon().get("weight", "")), wc0, "the old one is carried")
	t.ok(BWGearText.equip_check(r, u, big)[1].begins_with("Anyone can wield it"), "the card says anyone can wield it")


func test_c_plus_weapons_roll_an_imbue(t) -> void:
	var r := _run()
	var weapons: Array = BWData.table("equipment").filter(func(x): return x.slot == "main_hand")
	for tier in BWRun.TIERS:
		var n_imb := 0
		var n_ench := 0
		for row in weapons:
			var it := r.make_item(str(row.id), tier)
			n_imb += 1 if str(it.get("imbue", "")) != "" else 0
			n_ench += 1 if str(it.enchant) != "" else 0
			if str(it.get("imbue", "")) != "":
				t.ok(it.imbue in BWFormulas.ELEMENTS, "%s imbue is an element" % it.base)
				t.ok(BWRun.item_name(it).contains(str(it.imbue).capitalize()), "the name says it: %s" % BWRun.item_name(it))
				t.eq(BWRun.item_element(it), str(it.imbue), "the item's colour is its imbue")
		var plus: bool = BWRun.TIERS.find(tier) >= BWRun.TIERS.find("C")
		t.eq(n_imb, weapons.size() if plus else 0, "tier %s: imbued weapons" % tier)
		t.eq(n_ench, weapons.size(), "tier %s: every weapon still has its enchantment" % tier)
	t.ok(not r.make_item("platemail", "A").has("imbue"), "armour is never imbued")
	# the imbue has its own rng: the run's stream is untouched
	var a := _run()
	var b := _run()
	a.make_item("flamberge", "C")
	b.make_item("flamberge", "E")
	t.eq(str(a.rng.state), str(b.rng.state), "rolling an imbue leaves the run's rng alone")
	var it := a.make_item("flamberge", "C", "cleaving")
	it.imbue = "fire"
	t.eq(BWRun.item_name(it), "Fire Flamberge of Cleaving [C]", "short name with the element")


func test_swap_changes_class_range_skills_forecast(t) -> void:
	var r := _run()
	var u := _armed(r, "hero", 30)
	u.skill_loadout["bow"] = ["energized_shot"]
	var b := _battle(r, u, Vector2i(7, 6))
	var foe: BWUnit = b.units.filter(func(x): return x.id == "dummy0")[0]
	t.eq(b.current(), u, "the fast unit acts first")
	t.eq(b.weapon_range(u), 1, "a sword reaches 1")
	t.ok(not b.in_range(u, foe), "the foe 5 away is out of reach")
	var sword_keys: Array = b.skills_for(u).map(func(x): return str(x.key))
	t.ok("striketwice" in sword_keys, "sword skills on the bar")
	var fc_sword := b.forecast_basic(u, foe)
	u.cooldowns["striketwice"] = 2
	t.ok(b.can_swap(u), "can swap")
	t.ok(b.swap_weapon(u), "swap")
	t.eq(u.weapon_class, "bow", "the class follows the drawn bow")
	t.eq(b.weapon_range(u), 6, "the bow reaches 6")
	t.ok(b.in_range(u, foe), "now the foe is in reach")
	t.ok(foe in b.attack_targets(u), "the range overlay's targets follow")
	var bow_keys: Array = b.skills_for(u).map(func(x): return str(x.key))
	t.eq(bow_keys, ["energized_shot"], "the bar shows the bow's own loadout")
	var fc_bow := b.forecast_basic(u, foe)
	t.ok(fc_bow.damage.formula != fc_sword.damage.formula or fc_bow.damage.value != fc_sword.damage.value,
		"the forecast is the bow's (DEX) not the sword's (STR)")
	t.ok(not u.acted and b.can_move(u), "free: no action, no move spent")
	t.ok(b.can_swap(u), "D195: swap again, freely")
	t.ok(b.swap_weapon(u) and u.weapon_class == "sword", "swapped back to the sword")
	t.ok(b.swap_weapon(u) and u.weapon_class == "bow", "and to the bow again")
	t.ok(not u.acted and b.can_move(u), "still no action, no move spent")
	t.eq(int(u.cooldowns.get("striketwice", 0)), 2, "cooldowns are per skill and stay")
	t.ok(b.history.any(func(e): return str(e.type) == "swap" and str(e.weapon_class) == "bow"), "a swap event for the view")
	t.ok(not b.attack(u, foe).is_empty(), "and the bow shoots")
	b.end_turn()
	var guard := 0
	while b.current() != u and not b.over and guard < 20:
		b.end_turn()
		guard += 1
	t.eq(b.current(), u, "its next turn")
	t.ok(b.can_swap(u), "the swap is back next turn")


func test_imbue_carries_and_paints(t) -> void:
	var r := _run()
	var u := _unit("hero", 30)
	var w := r.make_item("sword", "C", "")
	w.imbue = "ice"
	u.equipment["main_hand"] = w
	u.sync_weapon()
	var b := _battle(r, u, Vector2i(3, 6))
	var foe: BWUnit = b.units.filter(func(x): return x.id == "dummy0")[0]
	t.eq(u.imbue(), "ice", "the weapon in hand is ice-imbued")
	var fc := b.forecast_basic(u, foe)
	t.eq(str(fc.element), "ice", "the basic attack carries ice")
	t.ok(not bool(fc.magic), "still a weapon blow (no resist roll)")
	var att := u.attuned
	b.attack(u, foe)
	t.ok(b.tiles.intensity(foe.pos, "ice") > 0 or b.tiles.is_glazed(foe.pos) or b.history.any(func(e): return str(e.type) == "paint" and str(e.element) == "ice"),
		"ice painted on the target's hex")
	t.eq(u.attuned, att, "the attunement is unchanged")


func test_ai_swaps_when_the_other_weapon_is_better(t) -> void:
	var r := _run()
	var u := _armed(r, "raider", 30, "enemy")
	var b := BWBattle.new(_board(), 5)
	var mark := _unit("mark", 1)
	mark.equipment["main_hand"] = r.make_item("sword", "E", "")
	var p2 := _unit("p2", 1)
	var p3 := _unit("p3", 1)
	b.setup([mark, p2, p3], [u])
	u.pos = Vector2i(10, 6)
	mark.pos = Vector2i(2, 6)          # 8 away: past sword reach (move 4 + 1), inside bow reach
	p2.pos = Vector2i(0, 0)
	p3.pos = Vector2i(0, 11)
	t.eq(b.current(), u, "the raider acts first")
	BWAI.take_turn(b)
	t.ok(b.history.any(func(e): return str(e.type) == "swap" and str(e.unit) == "raider"), "the AI draws the bow")
	t.ok(b.history.any(func(e): return str(e.type) in ["attack", "skill"] and str(e.unit) == "raider"), "and shoots")
	# a strong swordsman with a foe beside it keeps the sword
	var u2 := _armed(r, "brawler", 30, "enemy")
	u2.stats["str"] = 20                  # a strong arm, a poor eye: the sword is the better weapon
	u2.stats["dex"] = 1
	var b2 := BWBattle.new(_board(), 5)
	var m2 := _unit("m2", 1)
	b2.setup([m2, _unit("q2", 1), _unit("q3", 1)], [u2])
	u2.pos = Vector2i(5, 6)
	m2.pos = Vector2i(6, 6)
	BWAI.take_turn(b2)
	t.ok(b2.history.any(func(e): return str(e.type) in ["attack", "skill"] and str(e.unit) == "brawler"), "the brawler attacks")
	t.ok(not b2.history.any(func(e): return str(e.type) == "swap"), "and keeps its sword (no swap)")


## D202: re-imbue is gone (D183's two-part move with it). A weapon's imbue
## stays a rolled property; only a shop scroll changes it (test_enchant_v2).
func test_reimbue_is_gone(t) -> void:
	var r := _run()
	t.ok(not r.has_method("reimbue") and not r.has_method("can_reimbue"), "no re-imbue on the run")
	var src := r.make_item("flamberge", "C", "cleaving")
	t.ok(str(src.get("imbue", "")) in BWFormulas.ELEMENTS, "a C weapon still rolls its imbue (D182)")


func test_save_round_trip_and_v5(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	var w := r.make_item("javelin", "B")
	r.inventory.append(w)
	r.equip(u, w, "second")
	var d: Variant = JSON.parse_string(JSON.stringify(r.to_dict()))
	t.ok(int(d.version) >= 6, "save version 6+ (D184)")
	var r2 := BWRun.from_dict(d)
	var u2 := r2.unit(u.id)
	t.eq(str(u2.second_weapon().get("base", "")), "javelin", "the second weapon survives a save")
	t.eq(str(u2.second_weapon().get("imbue", "")), str(w.imbue), "and its imbue")
	t.eq(u2.weapon_class, u.weapon_class, "the class still follows the main hand")
	# a version-5 save: no second slot, no imbues
	var d5: Dictionary = JSON.parse_string(JSON.stringify(_run().to_dict()))
	d5.version = 5
	t.ok(BWRun.can_load(d5), "a v5 save still loads")
	var r5 := BWRun.from_dict(d5)
	t.ok(r5.squad.all(func(x): return x.second_weapon().is_empty()), "every second slot empty")


## D193: enemies carry a second weapon (another class, the same tier, the same
## expertise) from fight ENEMY_SECOND_FROM; earlier fights and the Giant don't.
func test_enemies_carry_a_second_weapon_from_fight_3(t) -> void:
	var r := _run()
	for e in r.enemies_for(BWRun.ENEMY_SECOND_FROM - 1):
		t.ok(e.second_weapon().is_empty(), "%s: no second weapon before fight %d" % [e.id, BWRun.ENEMY_SECOND_FROM])
	for n in [BWRun.ENEMY_SECOND_FROM, 9]:
		for e in r.enemies_for(n):
			var w: Dictionary = e.second_weapon()
			t.ok(not w.is_empty(), "%s: carries a second weapon" % e.id)
			t.ok(str(w.get("weight", "")) != e.weapon_class, "%s: of another class" % e.id)
			t.eq(str(w.get("tier", "")), str(e.equipment.main_hand.tier), "%s: the same tier" % e.id)
			t.eq(int(e.expertise.get(str(w.weight), 0)), int(e.expertise.get(e.weapon_class, 0)), "%s: the same expertise" % e.id)

extends RefCounted
## The run layer: setup, items, enemies, loot, learning, recruits, shop,
## save/load. (Re-imbue is gone, D202; the scrolls are in test_enchant_v2.)


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


func _run() -> BWRun:
	return BWRun.start(_ids(), 1234)


func test_start(t) -> void:
	var r := _run()
	t.eq(r.squad.size(), 6, "six chosen")
	for u in r.squad:
		var w: Dictionary = u.equipment.get("main_hand", {})
		t.ok(not w.is_empty(), "%s holds a weapon" % u.id)
		t.eq(w.get("tier"), "E", "%s starts at tier E" % u.id)
		t.ok(str(w.get("enchant", "")) != "", "%s weapon has a built-in enchantment" % u.id)
	t.eq(r.shop.size(), 5, "shop stocks 5")


func test_tiers_and_rolls(t) -> void:
	var r := _run()
	t.eq([r.tier_for(1), r.tier_for(2), r.tier_for(3), r.tier_for(9), r.tier_for(10)], ["E", "E", "D", "A", "A"], "two fights per tier")
	for i in 200:
		var tier: String = BWRun.TIERS[i % 5]
		var it := r.random_item(tier)
		var band: Array = BWRun.TIER_RANGE[tier]
		for s in it.stats:
			t.ok(it.stats[s] >= band[0] and it.stats[s] <= band[1], "%s %s roll %d in band" % [it.base, s, it.stats[s]])


func test_enemies(t) -> void:
	var r := _run()
	var a := r.enemies_for(4)
	var b := r.enemies_for(4)
	t.eq(a.map(func(u): return u.id), b.map(func(u): return u.id), "same fight, same enemies")
	for e in a:
		t.ok(r.unit(e.id.split("_f")[0]) == null, "%s is not in your squad" % e.id)
		t.eq(e.equipment.main_hand.tier, "E", "D99: fight 4 enemies carry fight 2's tier, E")
	for e in r.enemies_for(5):
		t.eq(e.equipment.main_hand.tier, "D", "D99: fight 5 enemies carry fight 3's tier, D")
	t.ok(r.enemies_for(9)[0].level > r.enemies_for(1)[0].level, "enemies grow over the run")
	var boss: BWUnit = r.enemies_for(11)[0]
	t.eq(boss.max_hp(), 500, "the boss has 500 HP")
	t.eq(boss.stat("str"), 50, "and 50 in the rest")


func test_after_fight(t) -> void:
	var r := _run()
	var deployed := r.squad.slice(0, 3)
	var enemies := r.enemies_for(1)
	var rep := r.after_fight(true, deployed, enemies, enemies, [])
	t.eq(rep.loot.size(), 3, "one item per enemy defeated")
	t.eq(r.inventory.size(), BWRun.STARTING_KIT + 3, "loot goes to inventory (on top of the starting kit)")
	t.eq(r.fight, 2, "advance to fight 2")
	t.eq(r.trust_stage(deployed[0].id, deployed[1].id), "strangers", "1 fight together = strangers")
	rep = r.after_fight(true, deployed, enemies, enemies, [])
	t.ok(rep.has("learned"), "learning report present")
	r.add_trust(deployed[0].id, deployed[1].id, 1)
	t.eq(r.trust_stage(deployed[0].id, deployed[1].id), "acquainted", "3 points = acquainted")


func test_learning_from_armour(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	var helm := r.make_item("feathered_cap", "E")
	r.inventory.append(helm)
	t.ok(r.equip(u, helm), "equip a cap")
	var e := r.enemies_for(1)
	r.after_fight(true, [u], e, e, [])
	t.ok(not "deadeye" in r.learned[u.id], "not learned after 1 battle")
	r.after_fight(true, [u], e, e, [])
	t.ok("deadeye" in r.learned[u.id], "learned after 2 battles (brief)")


func test_recruit(t) -> void:
	var r := _run()
	var e := r.enemies_for(1)
	r.after_fight(true, r.squad.slice(0, 3), e, e, [])
	var nu := r.recruit()
	t.ok(nu != null, "a past enemy joins")
	t.eq(r.squad.size(), 7, "the recruit joins")
	var gift: Array = r.inventory.filter(func(it): return it.weight == "fists")
	t.ok(gift.size() == 1 and gift[0].tier == "E", "the recruit brings a tier-E pair of fists (D76)")
	t.ok(r.can_equip(r.squad[0], gift[0]), "anyone can wear tier-E fists")
	r.last_enemies.clear()
	t.ok(r.recruit() == null, "nobody left: no recruit")
	var r2 := _run()
	# D382: the enemy side draws from every identity (seats + reserve); a full 6v6 side stays outside
	for id in r2.enemy_ids():
		if r2.enemy_ids().size() > BWRun.ENEMY_SIDE_MAX:
			r2.squad.append(BWUnit.from_roster(r2.roster_row(id)))
	r2.last_enemies = e.map(func(x): return x.to_dict())
	t.eq(r2.enemy_ids().size(), BWRun.ENEMY_SIDE_MAX, "six left outside")
	t.ok(not r2.can_recruit() and r2.recruit() == null, "the roster keeps a 6v6 side outside the squad for the enemies")


func test_weapon_rank_gate(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	var big := r.make_item("halberd", "C")
	r.inventory.append(big)
	t.ok(r.equip(u, big), "D180: a C weapon needs no expertise")
	t.eq(u.weapon_class, "lance", "switching weapon class follows the item")


func test_shop_trade(t) -> void:
	var r := _run()
	var mine := r.random_item("E")
	r.inventory.append(mine)
	var take: Dictionary = r.shop[0]
	t.ok(r.trade(mine, take), "1-for-1 trade")
	t.ok(take in r.inventory and mine in r.shop, "items swapped")
	t.ok(not r.has_method("reimbue"), "D202: no re-imbue")


func test_save_round_trip(t) -> void:
	var r := _run()
	var e := r.enemies_for(1)
	r.after_fight(true, r.squad.slice(0, 3), e, e, [])
	r.progress_day([[r.squad[0].id, "wander"]])
	var text := JSON.stringify(r.to_dict())
	var r2 := BWRun.from_dict(JSON.parse_string(text))
	t.eq(r2.fight, r.fight, "fight survives")
	t.eq(r2.squad.size(), r.squad.size(), "squad survives")
	t.eq(r2.inventory.size(), r.inventory.size(), "inventory survives")
	t.eq(r2.squad[0].level, r.squad[0].level, "the level survives")
	t.eq(r2.squad[0].max_hp(), r.squad[0].max_hp(), "stats + gear survive")
	t.eq(r2.random_item("E").stats, r.random_item("E").stats, "rng continues identically")


func test_loss_continues(t) -> void:
	# Author 2026-10-04: losing a regular fight doesn't end the run.
	var r := _run()
	var e := r.enemies_for(1)
	var rep := r.after_fight(false, r.squad.slice(0, 3), [], e, [])
	t.eq(rep.loot.size(), 0, "no spoils from a loss")
	t.eq(r.fight, 2, "the run moves on to fight 2")
	r.fight = BWRun.BOSS_FIGHT
	r.after_fight(false, r.squad.slice(0, 3), [], [r.make_boss()], [])
	t.eq(r.fight, BWRun.BOSS_FIGHT, "losing to the Giant doesn't advance past it (the run ends there)")


func test_starting_kit(t) -> void:
	var r := _run()
	t.eq(r.inventory.size(), BWRun.STARTING_KIT, "five starting pieces (author 10/4)")
	var slots := {}
	var bases := {}
	for it in r.inventory:
		slots[it.slot] = true
		bases[it.base] = true
		t.eq(it.tier, "E", "%s is tier E" % it.base)
		t.ok(it.slot != "main_hand", "%s is armour" % it.base)
	t.ok(slots.has("head") and slots.has("chest") and slots.has("legs"), "every armour slot covered")
	t.eq(bases.size(), BWRun.STARTING_KIT, "no duplicates")



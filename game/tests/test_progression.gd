extends RefCounted
## XP, levels, affinity and expertise growth.


func _u(wc: String = "sword") -> BWUnit:
	return BWUnit.from_roster({ "id": "u", "weapon_class": wc, "element": "fire",
		"con": 3, "str": 3, "dex": 3, "wil": 3, "def": 3, "res": 3, "spd": 3 })


func test_starting_affinity(t) -> void:
	t.eq(_u().affinity_rank("fire"), 1, "starts at rank 1 in own element (D22)")
	t.eq(_u().expertise_letter("sword"), "E", "starts at E")


func test_attack_award(t) -> void:
	var u := _u()
	BWProgression.award(u, false, "fire")
	t.eq(u.xp, 10, "attack = 10 xp")
	t.eq(u.affinity["fire"], 11, "+1 affinity")
	t.eq(u.expertise["sword"], 1, "+1 expertise")
	BWProgression.award(u, true, "fire")
	t.eq(u.xp, 40, "knockout = 30 xp")
	t.eq(u.affinity["fire"], 14, "+3 affinity")
	t.eq(u.expertise["sword"], 4, "+3 expertise")


func test_level_up_bias(t) -> void:
	var u := _u("sword")
	var ev := BWProgression.add_xp(u, 100)
	t.eq(u.level, 2, "100 xp = one level (D14)")
	t.eq(u.xp, 0, "xp carries remainder")
	t.eq(u.stats["str"], 5, "sword levels STR by 2")
	t.eq(u.stats["dex"], 4, "everything else by 1")
	var b := _u("bow")
	BWProgression.add_xp(b, 250)
	t.eq(b.level, 3, "250 xp = two levels")
	t.eq(b.xp, 50, "remainder 50")
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

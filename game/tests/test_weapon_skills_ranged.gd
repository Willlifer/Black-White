extends RefCounted
## D106 (bow and pistols): the new skills and their Improve riders.
## Helpers come from test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


# ------------------------------------------------------------------ bow

func test_split_arrow_fans(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "bow", "fire"), ["split_arrow"])
	var nb := BWHex.neighbors(C)
	var mid: Vector2i = K._line(3)[2]
	var up: Vector2i = BWHex.ray(C, nb[1], 2)[1]
	var down: Vector2i = BWHex.ray(C, nb[5], 3)[2]
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("u"), K._foe("d")], [mid, up, down])
	var pv := b.skill_preview(me, "split_arrow", "fire", mid)
	t.eq(pv.units.size(), 3, "three arrows, three foes")
	for id in ["a", "u", "d"]:
		t.near(float(K._mod(pv.forecasts[id], "Split Arrow").get("value", 0)), 0.6, 0.001, "60%% each (%s)" % id)
	var ev: Dictionary = K._use(t, b, me, "split_arrow", "fire", mid)
	t.eq(ev.results.size(), 3, "each arrow rolled")


func test_retreating_shot_moves_after(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "bow", "fire"), ["retreating_shot"])
	var at: Vector2i = K._line(4)[3]
	var b: BWBattle = K._fight(me, [K._foe()], [at])
	b.move(me, Vector2i(3, 4))
	K._use(t, b, me, "retreating_shot", "fire", at)
	t.eq(int(me.fx.get("bonus_move", 0)), 2, "move 2 more")
	t.ok(b.can_move(me), "it can move again")
	var far := 0
	var r := b.reachable(me)
	for h in r:
		if r[h].stop:
			far = maxi(far, int(r[h].cost))
	t.eq(far, 2, "exactly 2 more")


func test_pinning_shot(t) -> void:
	var pinned := 0
	for sd in 6:
		var me: BWUnit = K._equip(K._u("me", "bow", "fire"), ["pinning_shot"])
		var foe: BWUnit = K._foe()
		var at: Vector2i = K._line(5)[4]
		var b: BWBattle = K._fight(me, [foe], [at], 70 + sd)
		t.ok(b.skill_preview(me, "pinning_shot", "fire", at).notes.any(func(n): return str(n).contains("Pinned")), "named")
		var ev: Dictionary = K._use(t, b, me, "pinning_shot", "fire", at)
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.statuses.has("pinned"), sec, "Pinned iff the secondary landed")
		if sec:
			pinned += 1
			K._give_turn(b, foe)
			t.eq(foe.move_range(), maxi(BWUnit.BASE_MOVE - 2, 1), "-2 move")
	t.ok(pinned > 0, "pinned at least once")


func test_rain_of_arrows(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "bow", "fire"), ["rain_of_arrows"])
	var centre: Vector2i = K._line(4)[3]
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("c")], [centre, BWHex.ring(centre, 2)[0]])
	var pv := b.skill_preview(me, "rain_of_arrows", "fire", centre)
	t.eq(pv.hexes.size(), 19, "radius 2: 19 hexes")
	t.eq(pv.units.size(), 2, "every foe in it")
	K._use(t, b, me, "rain_of_arrows", "fire", centre)
	t.ok((pv.hexes as Array).all(func(h): return b.tiles.carries(h, "fire")), "all 19 painted")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "rain_of_arrows"), "once per battle")


func test_arcing_shot_plus(t) -> void:
	for up in [false, true]:
		var me: BWUnit = K._u("me", "bow", "fire")
		if up:
			me.skill_ranks["arcing_shot"] = 2
		var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)])
		b.board.set_cell(C, "neutral", 1)
		var tgt: Vector2i = K._line(3)[2]
		var pv := b.skill_preview(me, "arcing_shot", "fire", tgt)
		t.eq(pv.hexes.size(), 19 if up else 7, "1 level up: radius 2 only with Arcing Shot+ (%s)" % up)


func test_energized_shot_plus(t) -> void:
	var line: Array = K._line(6)
	var me: BWUnit = K._u("me", "bow", "fire")
	me.skill_ranks["energized_shot"] = 2
	var b: BWBattle = K._fight(me, [K._foe("a"), K._foe("z")], [line[0], line[5]])
	var pv := b.skill_preview(me, "energized_shot", "fire", line[0])
	t.near(float(K._mod(pv.forecasts["z"], "Pierced through").get("value", 0)), 0.8, 0.001, "80%, 5 past the target")
	var me2: BWUnit = K._u("me", "bow", "fire")
	var b2: BWBattle = K._fight(me2, [K._foe("a"), K._foe("z")], [line[0], line[5]])
	t.eq(b2.skill_preview(me2, "energized_shot", "fire", line[0]).units, ["a"], "5 past is too far without it")


# ------------------------------------------------------------------ pistols

func test_point_blank(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "pistols", "fire"), ["point_blank"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	var fc: Dictionary = b.skill_preview(me, "point_blank", "", E).forecasts["f"]
	t.near(float(K._mod(fc, "Point blank").get("value", 0)), 1.2, 0.001, "+20%")
	t.ok(not fc.magic, "plain lead: no resist roll")
	K._use(t, b, me, "point_blank", "", E)
	t.eq(foe.pos, BWHex.step_beyond(C, E), "shoved back 1")


func test_pistol_whip(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "pistols", "fire"), ["pistol_whip"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	t.ok(not me.quick_shot_ready, "no quick shot yet")
	K._use(t, b, me, "pistol_whip", "", E)
	t.ok(foe.statuses.has("staggered"), "Staggered")
	t.ok(me.quick_shot_ready, "Quick Shot ready again")
	t.eq(BWSkillRegistry.clip("pistol_whip"), "pistol_whip", "its own clip")


func test_flash_round(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "pistols", "fire"), ["flash_round", "reload"])
	var at: Vector2i = K._line(4)[3]
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [at])
	me.loaded = "fire"
	var pv := b.skill_preview(me, "flash_round", "", at)
	t.ok(pv.notes.any(func(n): return str(n).contains("Blinded")), "named")
	K._use(t, b, me, "flash_round", "", at)
	t.ok(foe.statuses.has("blinded"), "Blinded")
	t.ok(K._line(4).all(func(h): return b.tiles.carries(h, "fire")), "the loaded trail is laid")
	t.eq(me.loaded, "", "the round is spent")


func test_covering_fire(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "pistols", "fire", { "dex": 100 }), ["covering_fire"])
	var mate: BWUnit = K._u("m", "sword", "fire")
	var foe: BWUnit = K._foe()
	var mate_at: Vector2i = K._line(2)[1]
	var b: BWBattle = K._fight(me, [foe], [K._line(3)[2]], 7, [mate], [mate_at])
	K._use(t, b, me, "covering_fire", "", C)
	t.eq(K._events(b, "overwatch_set").size(), 1, "overwatch set")
	K._give_turn(b, foe)
	b.attack(foe, mate)
	t.eq(K._events(b, "overwatch").size(), 1, "the attack on an ally draws the shot")
	var shots: Array = K._events(b, "counter").filter(func(e): return e.get("cause", "") == "overwatch")
	t.eq(shots.size(), 1, "one basic shot")
	t.eq(shots[0].unit, "me", "from the gunner")


func test_empty_the_chamber(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "pistols", "fire"), ["empty_the_chamber"])
	var a: BWUnit = K._foe("a")
	var c: BWUnit = K._foe("c")
	var b: BWBattle = K._fight(me, [a, c], [K._line(2)[1], K._line(4)[3]])
	me.loaded = "fire"
	var pv := b.skill_preview(me, "empty_the_chamber", "", C)
	t.eq(pv.units, ["a", "c", "a", "c"], "4 shots over 2 foes, nearest first")
	t.near(float(K._mod(pv.forecasts["a"], "Empty the Chamber").get("value", 0)), 0.35, 0.001, "35% a shot")
	var ev: Dictionary = K._use(t, b, me, "empty_the_chamber", "", C)
	t.eq(ev.results.size(), 4, "each shot rolled")
	t.ok(K._line(4).all(func(h): return b.tiles.carries(h, "fire")), "the round trails the shots")
	t.eq(me.loaded, "", "spent")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "empty_the_chamber"), "once per battle")


func test_quick_shot_plus_fans_three(t) -> void:
	var me: BWUnit = K._u("me", "pistols", "fire")
	me.skill_ranks["quick_shot"] = 2
	var at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [at])
	b.use_skill(me, "reload", "fire", C)
	var n := 0
	for i in 4:
		if not b.use_skill(me, "quick_shot", "", at).is_empty():
			n += 1
	t.eq(n, 3, "three quick shots unmoved")


func test_reload_plus_two_rounds(t) -> void:
	var me: BWUnit = K._u("me", "pistols", "fire")
	me.skill_ranks["reload"] = 2
	var at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [at])
	b.use_skill(me, "reload", "fire", C)
	b.use_skill(me, "quick_shot", "", at)
	t.eq(me.loaded, "fire", "the second round drops in")
	b.use_skill(me, "quick_shot", "", at)
	t.eq(me.loaded, "", "two trailed shots, then empty")
	var trails: Array = K._events(b, "paint").filter(func(e): return e.unit == "me" and e.element == "fire")
	t.eq(trails.size(), 2, "both shots laid the trail")


## D435-D442: the retired skills' tests moved to test_kit3 (their replacements; the defs stay only for old saves).

extends RefCounted
## D496-D500 (2026-10-09 playtest notes): light heals only its owner's side,
## Haloed (a light cast also lights your own hex + ring), duo perks always
## offered at 3 tree picks each (test_keystones_v3), Pressured scaled by the
## target's distance, the bow at range 5 with Eagle Eye (+1 at expertise A).

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)

var P: Object = preload("res://tests/test_perks.gd").new()


func _heals(b: BWBattle) -> Array:
	return P._ev(b, "heal")


func test_foe_light_heals_no_one_of_yours(t) -> void:
	var me: BWUnit = P._u("me", "staff", "light")
	var foe: BWUnit = P._foe()
	var b: BWBattle = P._fight([me], [foe], [C], [Vector2i(10, 10)])
	me.hp -= 50
	b.tiles.apply([C], "light", foe.id, 2)
	t.eq(b.tiles.light_owner(C), foe.id, "the foe's light")
	P._turn(b, me)
	t.ok(_heals(b).is_empty(), "a foe's light doesn't heal me")


func test_own_light_heals_own_side(t) -> void:
	var me: BWUnit = P._u("me", "staff", "light")
	var mate: BWUnit = P._u("m", "sword", "fire", { "con": 100 })
	var b: BWBattle = P._fight([me, mate], [P._foe()], [C, Vector2i(4, 7)], [Vector2i(10, 10)])
	mate.hp -= 40
	b.tiles.apply([mate.pos], "light", me.id, 1)
	P._turn(b, mate)
	t.eq(_heals(b).size(), 1, "my light heals my ally")


func test_fire_on_light_keeps_its_owner(t) -> void:
	var me: BWUnit = P._u("me", "staff", "light")
	var foe: BWUnit = P._foe()
	var b: BWBattle = P._fight([me], [foe], [C], [Vector2i(10, 10)])
	b.tiles.apply([E], "light", me.id, 2)
	b.tiles.apply([E], "fire", foe.id, 1)
	t.eq(str(b.tiles.at(E).source), foe.id, "the fire is the foe's")
	t.eq(b.tiles.light_owner(E), me.id, "the light under it is still mine")
	b.tiles.apply([E], "light", foe.id, 1)
	t.eq(b.tiles.light_owner(E), foe.id, "the foe's light on it takes it over")


func test_map_light_heals_anyone(t) -> void:
	var foe: BWUnit = P._foe()
	var b: BWBattle = P._fight([P._u("me", "staff", "light")], [foe], [C], [E])
	foe.hp -= 50
	b.tiles.entries[E] = b.tiles._entry(0, 2, "", "", "spread")
	P._turn(b, foe)
	t.eq(_heals(b).size(), 1, "authored light (no owner) heals whoever stands on it")


func test_haloed_lights_your_own_ring(t) -> void:
	var E2: Object = preload("res://tests/test_effects.gd").new()
	var me: BWUnit = E2._ench(P._u("me", "staff", "light"), "haloed")
	me.pos = C
	var board: BWBoard = P._board()
	var target := Vector2i(8, 4)
	var o := BWEffects.paint_opts(me, "light", [target], board, true)
	var ring: Dictionary = o.get("ring", {})
	t.ok(ring.has(C), "your own hex")
	t.eq(BWHex.fringe([C], 1).filter(func(h): return h != C and ring.has(h)).size(), 6, "and the 6 around you")
	t.ok(not ring.has(target + Vector2i(1, 0)), "not around the target")
	var fire := BWEffects.paint_opts(me, "fire", [target], board, true)
	t.ok(not fire.has("ring"), "light casts only")


func test_bow_range_and_eagle_eye(t) -> void:
	var u: BWUnit = P._u("b", "bow", "fire")
	var b: BWBattle = P._fight([u], [P._foe()], [C], [Vector2i(10, 10)])
	t.eq(b.weapon_range(u), 5, "the bow reaches 5")
	u.expertise["bow"] = BWUnit.POINTS_PER_RANK * (BWUnit.EXPERTISE_RANKS.size() - 1)
	t.ok(BWEffects.bow_mastery(u), "expertise A: Eagle Eye")
	t.eq(b.weapon_range(u), 6, "Eagle Eye: +1")


func test_pressure_scales_with_target_distance(t) -> void:
	var u: BWUnit = P._u("b", "bow", "fire")
	var near: BWUnit = P._foe("n")
	var b: BWBattle = P._fight([u], [near], [C], [E])
	var m: Dictionary = P._mod(b.forecast_basic(u, near), "Pressured")
	t.eq(float(m.get("value", 0.0)), 0.75, "adjacent: −25%")
	var far: BWUnit = P._foe("x")
	var b2: BWBattle = P._fight([u], [P._foe("n2"), far], [C], [Vector2i(6, 4), Vector2i(8, 4)])
	t.eq(float(P._mod(b2.forecast_basic(u, far), "Pressured").get("value", 0.0)), 0.9, "a foe within 2, target 4 away: −10%")

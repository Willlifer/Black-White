extends BWSkillDef
## D451 Solar Flare, Sunburst's free action (Keystones v3): Pitch Black's twin
## for light. Once per turn, range 3, a light 3 hex (anyone's). It is
## overcharged (light 4 for the rest of your turn, light 3 after) and
## explodes: 15% (light) to every foe within 1 (2 with Superconductor), and
## allies within 1 heal 5%. The hex is not consumed. Weapon "keystone": in no
## class's pool; BWKeystones.skills lists it for a holder. Rules:
## BWKs3Dark.burst.


func _init() -> void:
	define({
		"key": "solar_flare", "name": "Solar Flare", "weapon": "keystone", "clip": "cast",
		"desc": "Free (Sunburst), once a turn, range 3: overcharge a light 3 hex. It explodes: 15% to every foe within 1, allies within 1 heal 5%. The hex stays (light 4 until your turn ends)",
		"targeting": "hex", "needs_element": false, "range": 3, "cd": 0, "min_range": 0,
		"power": 0, "free_action": true, "keystone": true,
	}, 9041)


func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	return BWKs3Dark.targets(b, u, "solar_flare")


func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	return h in BWKs3Dark.targets(b, u, "solar_flare")


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var r := BWKs3Dark.radius(u, "solar_flare")
	p.hexes = b.board.area(target, r)
	var n := BWKs3Dark.near(b, u, target, r, true).size()
	var a := BWKs3Dark.near(b, u, target, r, false).size()
	p.notes.append("Solar Flare: %d%% to %d foe%s within %d, %d all%s heal %d%%; the hex stays (light 4 this turn)" % [
		int(BWKeystones.param("sunburst", "pct", 15)), n, "" if n == 1 else "s", r, a, "y" if a == 1 else "ies",
		int(BWKeystones.param("sunburst", "heal_pct", 5))])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	BWKs3Dark.burst(b, u, target_hex, "solar_flare")
	return 0


## The AI opens its turn with it when a foe is in a burst.
func ai_opener(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	return BWKs3Dark.ai_pick(b, u, "solar_flare")

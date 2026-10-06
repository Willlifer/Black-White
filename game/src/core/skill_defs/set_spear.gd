extends BWSkillDef
## Lance. Free (no action spent): plant the spear. Until your next turn,
## every hex within your weapon's reach becomes a zone (BWSkillDef.zone, the
## D97 engine hook): an enemy entering one must stop there and can't path
## past it. No strike; it is there to keep people off your back line.

const CD := 3


func _init() -> void:
	define({
		"key": "set_spear", "name": "Set Spear", "weapon": "lance", "clip": "brace",
		"desc": "Free: plant the spear. Until your next turn, enemies entering any tile within your reach must stop there and can't get past",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0, "free_action": true,
	}, 323)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.notes.append("Set Spear: %d tiles within reach %d hold enemies until your next turn" % [
		reach_hexes(b, u).size(), b.weapon_range(u)])


## The hexes within the weapon's reach (not your own).
func reach_hexes(b: BWBattle, u: BWUnit) -> Array:
	return b._without(b._on_board(b.board.area(u.pos, b.weapon_range(u))), u.pos).filter(
		func(h): return b.board.is_passable(h))


func zone(b: BWBattle, u: BWUnit, _p: Dictionary, _target_hex: Vector2i) -> Array:
	return reach_hexes(b, u)


## Set last in the AI's turn when a foe could walk into reach.
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	return u.zone.is_empty() and b.foes_of(u).any(func(f): return b.gap(u, f) <= f.move_range() + b.weapon_range(u))

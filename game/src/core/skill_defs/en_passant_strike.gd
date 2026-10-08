extends BWSkillDef
## Sword, follow-up only (D426): En Passant's Passing Cut. A second strike at
## any adjacent foe, in the element the dash carried; its hex takes the
## element. Waiting (T) declines it.

const POWER := 9


func _init() -> void:
	define({
		"key": "en_passant_strike", "name": "Passing Cut", "weapon": "sword", "clip": "",
		"desc": "En Passant's follow-through: an elemental strike at any foe beside you, in the dash's element",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": 0,
		"power": POWER, "follow_up_only": true,
	}, 306)


## Only in the element the dash carried.
func targets(b: BWBattle, u: BWUnit, element: String) -> Array[Vector2i]:
	if element != u.follow_up_element:
		var none: Array[Vector2i] = []
		return none
	return super.targets(b, u, element)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])

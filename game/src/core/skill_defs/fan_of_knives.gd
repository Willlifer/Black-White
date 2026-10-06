extends BWSkillDef
## Daggers. Spin and loose knives at every foe on the ring around you
## (POWER each); the ring takes 1 step of the element.

const POWER := 8
const CD := 3


func _init() -> void:
	define({
		"key": "fan_of_knives", "name": "Fan of Knives", "weapon": "daggers", "clip": "spin",
		"desc": "Spin and loose knives at every enemy beside you; the ring around you takes your element",
		"targeting": "self", "needs_element": true, "range": 0, "cd": CD,
		"power": POWER, "radius": 1, "aoe": true,
	}, 354)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._without(b._on_board(b.board.area(u.pos, 1)), u.pos)
	p.victims = b._foes_on(u, p.hexes)


## A self-centred attack: the AI weighs it like any other.
func ai_considers(_row: Dictionary) -> bool:
	return true

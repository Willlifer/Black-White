extends BWSkillDef
## Sword (D103). Spin: every foe on the ring around you takes POWER, and the
## ring takes 1 step of the element you chose (any you have affinity in; the
## element menu is the choice).

const POWER := 9
const CD := 3


func _init() -> void:
	define({
		"key": "whirlwind_blade", "name": "Whirlwind Blade", "weapon": "sword", "clip": "spin",
		"desc": "Spin: every enemy beside you is cut, and the ring around you takes 1 step of the element you choose",
		"targeting": "self", "needs_element": true, "range": 0, "cd": CD,
		"power": POWER, "radius": 1, "aoe": true,
	}, 303)


func plan(b: BWBattle, u: BWUnit, element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._without(b._on_board(b.board.area(u.pos, 1)), u.pos)
	p.victims = b._foes_on(u, p.hexes)
	if element != "":
		p.notes.append("Paints the ring 1 step of %s" % element)


## A self-centred attack: the AI weighs it like any other.
func ai_considers(_row: Dictionary) -> bool:
	return true

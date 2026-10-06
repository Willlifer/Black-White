extends BWSkillDef
## Axe (D104). An overhead blow that splits the ground LEN hexes ahead: every
## foe on the line takes POWER, and the line takes 1 step of the element.
## Jagged rock stops the split.

const POWER := 11
const CD := 4
const LEN := 3


func _init() -> void:
	define({
		"key": "earthsplitter", "name": "Earthsplitter", "weapon": "axe", "clip": "",
		"desc": "An overhead blow that splits the ground 3 tiles ahead: every enemy on the line is hit, and the line takes your element",
		"targeting": "dir", "needs_element": true, "range": LEN, "cd": CD,
		"power": POWER, "aoe": true,
	}, 314)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	for h in b.board.ray(u.pos, target, LEN):
		if b.board.terrain(h) == BWBoard.JAGGED:
			break
		p.hexes.append(h)
	p.victims = b._foes_on(u, p.hexes)

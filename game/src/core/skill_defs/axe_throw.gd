extends BWSkillDef
## Axe (D531, author: "basically Saturate but only one level of element").
## Toss the axe underhanded at a hex within RANGE (sight needed): a foe
## standing there takes the blow (skill POWER), and the hex takes 1 step of
## your element whoever stands on it, or no one. A new axe is drawn: the
## thrown one doesn't come back and nothing is unequipped. A ranged
## single-target blow, so Pressured applies (D424 / D499) when a foe is
## within 2 of the thrower. No Improve rider.
## The clip is "throw_under" (the underhand toss); until a style has it the
## class strike plays and the axe itself flies (BWRangedVFX._throw_axe).

const POWER := 10
const CD := 1
const RANGE := 3
const STEPS := 1


func _init() -> void:
	define({
		"key": "axe_throw", "name": "Axe Throw", "weapon": "axe", "clip": "throw_under",
		"desc": "Toss your axe underhand at a tile up to 3 away: an enemy there is hit, and the tile takes 1 step of your element. A new axe is drawn",
		"targeting": "hex", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER, "steps": STEPS, "min_range": 1, "los": true,
	}, 316)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, p.hexes)

extends BWSkillDef
## Bow (D106). Once per battle: a volley into the sky at a hex within RANGE.
## Every foe within RADIUS of it takes POWER, and all 19 hexes take 1 step
## of the element (the author kept the massive AoE).

const POWER := 9
const RANGE := 6
const RADIUS := 2
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "rain_of_arrows", "name": "Rain of Arrows", "weapon": "bow", "clip": "shot_volley",
		"desc": "Once per battle: a volley onto a tile up to 6 away; every enemy within 2 of it is hit and all 19 tiles take your element",
		"targeting": "hex", "needs_element": true, "range": RANGE, "cd": 0, "once_per_battle": true,
		"power": POWER, "radius": RADIUS, "min_range": 1, "aoe": true,
	}, 335)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(b.board.area(target, RADIUS))
	p.victims = b._foes_on(u, p.hexes)


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

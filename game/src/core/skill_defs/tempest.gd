extends BWSkillDef
## Staff spell (D107). Once per battle: a storm on a hex within RANGE (sight
## needed). Every foe within RADIUS takes POWER, and all 19 hexes take 1
## step of the element.

const POWER := 9
const RANGE := 4
const RADIUS := 2
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "tempest", "name": "Tempest", "weapon": "staff", "clip": "tempest",   # D519: the floating cast (cast_tempest)
		"desc": "Once per battle: a storm on a tile up to 4 away; every enemy within 2 of it is hit and all 19 tiles take your element",
		"targeting": "hex", "needs_element": true, "range": RANGE, "cd": 0, "once_per_battle": true,
		"power": POWER, "radius": RADIUS, "min_range": 0, "los": true, "spell": true, "aoe": true,
	}, 345)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(b.board.area(target, RADIUS))
	p.victims = b._foes_on(u, p.hexes)


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

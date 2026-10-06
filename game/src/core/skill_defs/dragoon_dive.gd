extends BWSkillDef
## Lance (D105). Once per battle: leap up to RANGE hexes (a free hex; over
## anything) and come down spear-first: every foe on the ring around the
## landing takes POWER, and the ring takes 1 step of the element.

const POWER := 13
const RANGE := 4
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "dragoon_dive", "name": "Dragoon Dive", "weapon": "lance", "clip": "",
		"desc": "Once per battle: leap up to 4 tiles and land spear-first; every enemy beside the landing is hit and the ring takes your element",
		"targeting": "leap", "needs_element": true, "range": RANGE, "cd": 0, "once_per_battle": true,
		"power": POWER, "radius": 1, "aoe": true,
	}, 325)


## Up to RANGE only (not Daggerleap's "any tile carrying the element").
func target_ok(_b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	return BWHex.distance(u.pos, h) <= RANGE


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.dest = target
	p.hexes = b._without(b._on_board(b.board.area(target, 1)), target)
	p.victims = b._foes_on(u, p.hexes)


## A leap: straight to the landing, no fire crossing (D44).
func relocate(b: BWBattle, u: BWUnit, p: Dictionary, _target_hex: Vector2i) -> void:
	b.skill_relocate(u, p, [u.pos, p.dest], "leap")


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

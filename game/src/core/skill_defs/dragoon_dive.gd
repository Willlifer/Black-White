extends BWSkillDef
## Lance (D105). Once per battle: leap up to RANGE hexes (a free hex; over
## anything) and come down spear-first: every foe on the ring around the
## landing takes POWER, and the ring takes 1 step of the element. D362 high
## ground: onto a hex 1+ level below, reach +1 and the ring 1 wider.

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
func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	return BWHex.distance(u.pos, h) <= RANGE + (1 if BWWeaponMove.above(b, u, h) else 0)


## D362: the base list stops at RANGE; add the high-ground ring beyond it.
func targets(b: BWBattle, u: BWUnit, element: String) -> Array[Vector2i]:
	var out := super.targets(b, u, element)
	for h in b.board.cells():
		if BWHex.distance(u.pos, h) == RANGE + 1 and b.can_stand(u, h) and BWWeaponMove.above(b, u, h) and not h in out:
			out.append(h)
	return out


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.dest = target
	var high := BWWeaponMove.above(b, u, target)
	p.hexes = b._without(b._on_board(b.board.area(target, 2 if high else 1)), target)
	if high:
		p.notes.append("High ground: diving down, reach +1 and the ring radius 2")
	p.victims = b._foes_on(u, p.hexes)


## A leap: straight to the landing, no fire crossing (D44).
func relocate(b: BWBattle, u: BWUnit, p: Dictionary, _target_hex: Vector2i) -> void:
	b.skill_relocate(u, p, [u.pos, p.dest], "leap")


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

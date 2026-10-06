extends BWSkillDef
## Fists. Once per battle: HITS blows at an adjacent foe, each PCT% of POWER
## and rolled on its own (Flurry's multi-strike); the last pours STEPS steps
## of the element into its hex.

const POWER := 12
const HITS := 6
const PCT := 30
const STEPS := 2
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "hundred_fists", "name": "Hundred Fists", "weapon": "fists", "clip": "hundred",
		"desc": "Once per battle: six blows at an adjacent enemy, 30% each and rolled one by one; the last pours two steps of your element into its tile",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": 0, "once_per_battle": true,
		"power": POWER, "hits": HITS, "hit_pct": PCT, "steps": STEPS,
	}, 375)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.steps = STEPS
	p.victims = b._foes_on(u, [target])
	p["hits"] = HITS


func forecast_mods(_b: BWBattle, _u: BWUnit, el: String, _v: BWUnit, p: Dictionary, strike: int,
		_mods: Array, notes: Array) -> void:
	if strike == 0:
		notes.append("The last blow pours %d steps of %s" % [int(p.get("steps", STEPS)), el])


## Once per battle: every element of it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

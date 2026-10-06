extends BWSkillDef
## Fists. A wound-up haymaker at an adjacent foe: +CRIT crit if you haven't
## moved this turn.

const POWER := 14
const CD := 4
const CRIT := 25


func _init() -> void:
	define({
		"key": "haymaker", "name": "Haymaker", "weapon": "fists", "clip": "uppercut",
		"desc": "A wound-up haymaker at an adjacent enemy: +25 crit if you haven't moved",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 374)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(_b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	if not u.moved:
		mods.append({ "stage": "crit", "value": float(CRIT), "label": "Haymaker, unmoved: +%d crit" % CRIT })
	else:
		notes.append("You moved: no +%d crit" % CRIT)

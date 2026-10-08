extends BWSkillDef
## RETIRED (D442: removed): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Bow (D106). A long, drawn shot at a foe within RANGE: +HIT hit, and +CRIT
## crit if you haven't moved this turn. The arrow lays the element on the
## target's hex.

const POWER := 13
const CD := 2
const RANGE := 8
const HIT := 20
const CRIT := 10


func _init() -> void:
	define({
		"key": "aimed_shot", "name": "Aimed Shot", "weapon": "bow", "clip": "shot_aimed",
		"desc": "A long, drawn shot at an enemy up to 8 tiles away: +20 hit, and +10 crit if you haven't moved",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER,
		"retired": true,
	}, 331)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(_b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	mods.append({ "stage": "hit", "value": float(HIT), "label": "Aimed Shot: +%d hit" % HIT })
	if not u.moved:
		mods.append({ "stage": "crit", "value": float(CRIT), "label": "Aimed Shot, unmoved: +%d crit" % CRIT })
	else:
		notes.append("You moved: no +%d crit" % CRIT)

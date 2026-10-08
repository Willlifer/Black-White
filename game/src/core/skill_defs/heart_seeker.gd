extends BWSkillDef
## RETIRED (D438 Thread the Needle): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Sword (D103). A precise thrust at an adjacent foe: +CRIT crit chance.

const POWER := 10
const CD := 2
const CRIT := 25


func _init() -> void:
	define({
		"key": "heart_seeker", "name": "Heart Seeker", "weapon": "sword", "clip": "thrust",
		"desc": "A precise thrust at an adjacent enemy: +25 crit chance",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
		"retired": true,
	}, 301)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "crit", "value": float(CRIT), "label": "Heart Seeker: +%d crit" % CRIT })

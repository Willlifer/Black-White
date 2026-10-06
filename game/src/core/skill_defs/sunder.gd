extends BWSkillDef
## Axe (D104). A splitting blow at an adjacent foe that ignores DEF_IGNORE%
## of its DEF and can't glance.

const POWER := 13
const CD := 3
const DEF_IGNORE := 30


func _init() -> void:
	define({
		"key": "sunder", "name": "Sunder", "weapon": "axe", "clip": "",
		"desc": "A splitting blow at an adjacent enemy: ignores 30% of its DEF and can't glance",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 313)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "def_ignore", "value": DEF_IGNORE / 100.0, "label": "Sunder (%d%%)" % DEF_IGNORE })
	mods.append({ "stage": "glance_x", "value": 0.0, "label": "Sunder: can't glance" })

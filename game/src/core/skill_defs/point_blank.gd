extends BWSkillDef
## Pistols. Both barrels into an adjacent foe: +BONUS_PCT%, and the blast
## shoves it PUSH straight away from you (a secondary effect; no slam).
## Plain lead: no element, no trail.

const Guardrush := preload("res://src/core/skill_defs/guardrush.gd")

const POWER := 13
const CD := 2
const BONUS_PCT := 20
const PUSH := 1


func _init() -> void:
	define({
		"key": "point_blank", "name": "Point Blank", "weapon": "pistols", "clip": "",
		"desc": "Fire into an adjacent enemy at point-blank range: +20%, and the blast shoves it back 1",
		"targeting": "adjacent_unit", "needs_element": false, "range": 1, "cd": CD,
		"power": POWER,
	}, 361)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	for v in p.victims:
		Guardrush.note(b, v, BWHex.direction_index(u.pos, v.pos), PUSH, 0, p.notes)


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "dmg", "value": 1.0 + BONUS_PCT / 100.0, "label": "Point blank: +%d%%" % BONUS_PCT })


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	for v in Guardrush.landed(p, results):
		Guardrush.shove(b, u, v, BWHex.direction_index(u.pos, v.pos), PUSH, 0, id)

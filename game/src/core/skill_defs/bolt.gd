extends BWSkillDef
## Staff spell (D107). A quick bolt at a foe within RANGE (sight needed):
## +GROUND_PCT% if the target's hex already carries the element you cast.
## The bolt lays the element on that hex.

const POWER := 10
const CD := 1
const RANGE := 4
const GROUND_PCT := 20


func _init() -> void:
	define({
		"key": "bolt", "name": "Bolt", "weapon": "staff", "clip": "",
		"desc": "A quick bolt at an enemy up to 4 tiles away; +20% if its tile already carries your element",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER, "spell": true,
	}, 341)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(b: BWBattle, _u: BWUnit, el: String, v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	if el != "" and b.tiles.carries(v.pos, el):
		mods.append({ "stage": "dmg", "value": 1.0 + GROUND_PCT / 100.0,
			"label": "Bolt (%s on its tile): +%d%%" % [el, GROUND_PCT], "tag": "Bolt" })
	else:
		notes.append("+%d%% if its tile already carried %s" % [GROUND_PCT, el])

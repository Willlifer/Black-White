extends BWSkillDef
## Daggers (drafted as Twist the Knife). Work the wound on an adjacent foe:
## +PER_STATUS% for each short status on it, and +CHARGE_PCT% if it stands
## on any charge (an axis tile), up to +CAP_PCT% in all.

const POWER := 9
const CD := 2
const PER_STATUS := 10
const CHARGE_PCT := 10
const CAP_PCT := 60


func _init() -> void:
	define({
		"key": "manipulate", "name": "Manipulate", "weapon": "daggers", "clip": "",
		"desc": "Work the wound on an adjacent enemy: +10% for each status on it, +10% if it stands on charge (up to +60%)",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 352)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func forecast_mods(b: BWBattle, _u: BWUnit, _el: String, v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	var n := v.statuses.size()
	var pct := PER_STATUS * n
	var why: Array = []
	if n > 0:
		why.append("%d status%s" % [n, "es" if n > 1 else ""])
	if b.tiles.charged(v.pos):
		pct += CHARGE_PCT
		why.append("on charge")
	pct = mini(pct, CAP_PCT)
	if pct > 0:
		mods.append({ "stage": "dmg", "value": 1.0 + pct / 100.0,
			"label": "Manipulate (%s): +%d%%" % [", ".join(why), pct], "tag": "Manipulate" })
	else:
		notes.append("No status and no charge on it: no bonus")

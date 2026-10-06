extends BWSkillDef
## Pistols. Club an adjacent foe with the grip: it is Staggered (a secondary
## effect: an avoid still staggers, a resist can't happen on plain lead),
## and the hammer is cocked again: Quick Shot is ready.

const POWER := 9
const CD := 2


func _init() -> void:
	define({
		"key": "pistol_whip", "name": "Pistol Whip", "weapon": "pistols", "clip": "pistol_whip",
		"desc": "Club an adjacent enemy with the grip: it is Staggered, and your Quick Shot is ready again",
		"targeting": "adjacent_unit", "needs_element": false, "range": 1, "cd": CD,
		"power": POWER,
	}, 362)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	for v in p.victims:
		p.notes.append("%s is Staggered (%s)" % [v.name, BWSkills.STATUS.staggered[1]])
	p.notes.append("Quick Shot ready again")


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	if not results.is_empty() and not p.victims.is_empty():
		var v: BWUnit = p.victims[0]
		if v.alive() and results[0].result.secondary:
			b._add_status(v, "staggered", u)
	u.quick_shot_ready = true

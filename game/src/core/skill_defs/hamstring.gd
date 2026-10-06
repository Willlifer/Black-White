extends BWSkillDef
## Daggers. Cut the tendon of an adjacent foe: it is Pinned (-2 move until
## the end of its next turn; a secondary effect, so a resist stops it).

const POWER := 8
const CD := 3


func _init() -> void:
	define({
		"key": "hamstring", "name": "Hamstring", "weapon": "daggers", "clip": "",
		"desc": "Cut the tendon of an adjacent enemy: it is Pinned (-2 move)",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 353)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	for v in p.victims:
		p.notes.append("%s is Pinned (%s)" % [v.name, BWSkills.STATUS.pinned[1]])


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	if not results.is_empty() and not p.victims.is_empty():
		var v: BWUnit = p.victims[0]
		if v.alive() and results[0].result.secondary:
			b.add_status(v, "pinned", u)

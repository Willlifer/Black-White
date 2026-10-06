extends BWSkillDef
## Bow. An arrow through the boot at a foe within RANGE: it is Pinned (-2
## move until the end of its next turn; a secondary effect, so a resist
## stops it). The arrow lays the element on the target's hex.

const POWER := 10
const CD := 3
const RANGE := 6


func _init() -> void:
	define({
		"key": "pinning_shot", "name": "Pinning Shot", "weapon": "bow", "clip": "",
		"desc": "An arrow through the boot of an enemy up to 6 tiles away: it is Pinned (-2 move)",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER,
	}, 334)


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

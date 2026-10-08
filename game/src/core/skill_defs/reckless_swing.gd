extends BWSkillDef
## RETIRED (D435 Reckless Arc): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Axe (D104). A wild, heavy swing at an adjacent foe. It leaves you open:
## you are Scorched (attacks on you +10%) through your next turn.

const POWER := 14
const CD := 1


func _init() -> void:
	define({
		"key": "reckless_swing", "name": "Reckless Swing", "weapon": "axe", "clip": "",
		"desc": "A wild, heavy swing at an adjacent enemy. It leaves you open: you are Scorched (attacks on you +10%) until your next turn is over",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
		"retired": true,
	}, 311)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	p.notes.append("Reckless: you are Scorched (attacks on you +%d%%) until your next turn ends" % BWSkills.SCORCH_PCT)


func after_hits(b: BWBattle, u: BWUnit, _p: Dictionary, _results: Array) -> void:
	if u.alive():
		b._add_status(u, "scorched", u)

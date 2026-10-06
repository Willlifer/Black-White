extends BWSkillDef
## Daggers. Throw, laying the element on the blade's trail; every foe on the
## trail is hit (D44). Grants the Second Dagger as a follow-up.


func _init() -> void:
	define({
		"key": "dualthrow", "name": "Dualthrow", "weapon": "daggers", "clip": "throw",
		"desc": "Throw, leaving the element behind the blade, then throw again",
		"plus": "Dualthrow+: the bounce goes twice (75%, then 50%)",
		"targeting": "unit", "needs_element": true, "range": BWSkills.DUALTHROW_RANGE, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.DUALTHROW_DMG, "follow_up": ["dualthrow_second"],
	}, 90)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(BWHex.trail(u.pos, target))
	p.victims = b._foes_on(u, p.hexes)                   # enemies on the flight path

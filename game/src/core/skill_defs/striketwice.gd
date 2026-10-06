extends BWSkillDef
## Sword. The first of two cuts at an adjacent foe; grants the Second Cut,
## which remembers who this one hit (D87: same foe twice, or retarget) and
## whether it landed (Striketwice+, D103: read by the Second Cut).


func _init() -> void:
	define({
		"key": "striketwice", "name": "Striketwice", "weapon": "sword", "clip": "",
		"desc": "Two cuts; the second may go to any adjacent foe. Same foe twice: the second can't glance and staggers. Same element: floods the ground. Opposite elements: a reaction",
		"plus": "Striketwice+: if both cuts land, a third cut hits an adjacent foe at 50%",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.STRIKE_DMG, "follow_up": ["striketwice_second"],
	}, 110)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])


func on_follow_up(_b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	u.fx["first_cut"] = p.victims[0].id if not p.victims.is_empty() else ""


## Striketwice+ (D103) needs to know the first cut landed.
func after_hits(_b: BWBattle, u: BWUnit, _p: Dictionary, results: Array) -> void:
	u.fx["first_cut_hit"] = not results.is_empty() and bool(results[0].result.hit)

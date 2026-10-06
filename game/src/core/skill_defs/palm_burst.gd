extends BWSkillDef
## Fists (D76). A melee Saturate: strike an adjacent foe and pour `steps`
## (Welling: cast_step_plus skill=palm_burst, more) into its hex. D87: if the
## hex already carried the element, the burst pushes the foe 1 (secondary);
## Palm Burst+ pushes it PLUS_PUSH.

const PLUS_PUSH := 2


func _init() -> void:
	define({
		"key": "palm_burst", "name": "Palm Burst", "weapon": "fists", "clip": "palm_burst",
		"desc": "Strike an adjacent enemy with an open palm and pour two steps of your element into its hex. If the hex already carried it, the burst pushes the foe 1",
		"plus": "Palm Burst+: push 2 on a hex that already carried the element",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.PALM_DMG, "steps": 2,
	}, 180)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.steps = int(data.get("steps", 2)) + b._skill_rider(u, "cast_step_plus", "palm_burst", "steps")
	p.victims = b._foes_on(u, [target])
	if not p.victims.is_empty() and b.tiles.carries(target, element):
		p["palm_push"] = 1
		if upgraded(u):
			p.palm_push = PLUS_PUSH
		p.notes.append("%s already on the hex: the burst pushes %s back %d" % [element.capitalize(), p.victims[0].name, p.palm_push])


func after_paint(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary,
		results: Array, _stripped: int) -> void:
	if int(p.get("palm_push", 0)) <= 0 or p.victims.is_empty():
		return
	var first_res: Dictionary = results[0].result if not results.is_empty() else {}
	var v: BWUnit = p.victims[0]
	if v.alive() and not first_res.is_empty() and first_res.secondary:
		b._displace(v, BWHex.direction_index(u.pos, v.pos), int(p.palm_push), "push")

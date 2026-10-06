extends BWSkillDef
## Fists. A palm strike that sends a shockwave LEN hexes ahead (jagged rock
## stops it): every foe on the line takes POWER and is shoved PUSH further
## along the heading (a secondary effect; no slam), and the line takes 1 step
## of the element. The far foe moves first, so a line shoves cleanly.

const Guardrush := preload("res://src/core/skill_defs/guardrush.gd")

const POWER := 9
const CD := 3
const LEN := 3
const PUSH := 1


func _init() -> void:
	define({
		"key": "shockwave_palm", "name": "Shockwave Palm", "weapon": "fists", "clip": "palm_burst",
		"desc": "A palm strike that sends a shockwave 3 tiles ahead: every enemy on the line is hit and shoved 1, and the line takes your element",
		"targeting": "dir", "needs_element": true, "range": LEN, "cd": CD,
		"power": POWER, "aoe": true,
	}, 371)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	for h in b.board.ray(u.pos, target, LEN):
		if b.board.terrain(h) == BWBoard.JAGGED:
			break
		p.hexes.append(h)
	p.victims = b._foes_on(u, p.hexes)
	var di := BWHex.direction_index(u.pos, target)
	for v in p.victims:
		Guardrush.note(b, v, di, PUSH, 0, p.notes)


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	var di := BWHex.direction_index(u.pos, p.hexes[0]) if not p.hexes.is_empty() else -1
	var vs := Guardrush.landed(p, results)
	vs.reverse()                                   # the far end moves first
	for v in vs:
		Guardrush.shove(b, u, v, di, PUSH, 0, id)

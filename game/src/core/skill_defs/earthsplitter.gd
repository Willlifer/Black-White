extends BWSkillDef
## Axe (D104; D416). An overhead blow that splits the ground LEN hexes ahead:
## every foe on the line takes POWER, and the ground HEAVES: each foe on it
## is thrown HEAVE hex back along the line (a secondary: it lands on an
## avoid, a resist or an immune foe stops it; farthest first). Jagged rock
## stops the split. D416: it no longer paints the line. Sunder (D415) is the
## axe's fissure that marks the earth with the element; Earthsplitter is the
## one aimed anywhere that breaks a line up.

const POWER := 11
const CD := 4
const LEN := 3
const HEAVE := 1


func _init() -> void:
	define({
		"key": "earthsplitter", "name": "Earthsplitter", "weapon": "axe", "clip": "sweep_under",   # D512: the underhand sweep
		"desc": "A rising underhand blow that splits the ground 3 tiles ahead: every enemy on the line is hit and heaved 1 tile back along it",
		"targeting": "dir", "needs_element": true, "range": LEN, "cd": CD,
		"power": POWER, "aoe": true,
	}, 314)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	for h in b.board.ray(u.pos, target, LEN):
		if b.board.terrain(h) == BWBoard.JAGGED:
			break
		p.hexes.append(h)
	p.victims = b._foes_on(u, p.hexes)
	if not p.victims.is_empty():
		p.notes.append("Heave: %s thrown %d back" % [", ".join(p.victims.map(func(v): return v.name)), HEAVE])


## D416: the line is not painted (Sunder's fissure is the one that is).
func ground(_b: BWBattle, _u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	return 0


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	if p.hexes.is_empty() or b.over:
		return
	var dir := BWHex.direction_index(u.pos, p.hexes[0])
	var landed := {}
	for r in results:
		landed[str(r.target)] = bool(r.result.get("secondary", false))
	var order: Array = (p.victims as Array).duplicate()
	order.sort_custom(func(a, c): return BWHex.distance(u.pos, a.pos) > BWHex.distance(u.pos, c.pos))
	for v in order:
		if v.alive() and landed.get(v.id, false) and not b.over:
			b._displace(v, dir, HEAVE, "knockback")

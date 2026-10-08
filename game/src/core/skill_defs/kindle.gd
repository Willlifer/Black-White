extends BWSkillDef
## Daggers. D441 (replaces Hamstring, retired): flick a knife at a foe within
## RANGE and your element takes all six hexes around it (1 step each; its own
## hex is left alone). No damage of its own: it sets the ground for Consume,
## Manipulate, Daggerleap (onto your element anywhere) and Overload. Rock and
## the map's edge just leave a hex out. Uses the action.

const CD := 3
const RANGE := 3


func _init() -> void:
	define({
		"key": "kindle", "name": "Kindle", "weapon": "daggers", "clip": "throw",
		"desc": "Mark an enemy up to 3 tiles away: all 6 tiles around it take your element (no damage)",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": 0,
	}, 353)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	var v := b._centre_at(target)
	if v == null or v.team == u.team:
		return
	p.hexes = ring(b, v)
	p.notes.append("Kindle: %d tiles round %s take %s" % [(p.hexes as Array).size(), v.name, element])


## The hexes around `v` that can hold a charge.
static func ring(b: BWBattle, v: BWUnit) -> Array:
	var out: Array = []
	for h in BWHex.fringe(v.footprint(), 1):
		if not h in v.footprint() and b.tiles.can_hold(h):
			out.append(h)
	return out


## D112: kindle a foe a dagger can reach next turn when no blow is in hand
## (the ring sets up Consume / Overload); more for foes standing in the ring.
func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	if not b.attack_targets(u).is_empty():
		return {}
	var best := {}
	for el in row.get("elements", []):
		for h in b.skill_targets(u, id, str(el)):
			var v := b._centre_at(h)
			if v == null:
				continue
			var r := ring(b, v)
			var score := 2.0 + 0.5 * r.size()
			for o in b.foes_of(u):
				if o != v and o.alive() and o.pos in r:
					score += 3.0
			if best.is_empty() or score > float(best.score):
				best = { "target": h, "element": el, "score": score }
	return best

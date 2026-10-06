extends BWSkillDef
## Pistols. Overwatch (the D97 ally-attacked hook): until your next turn,
## the first enemy action that attacks an ally within RADIUS of you draws
## your basic shot, if it is in range (BWBattle's default answer). Uses the
## action; no damage of its own.

const CD := 3
const RADIUS := 3


func _init() -> void:
	define({
		"key": "covering_fire", "name": "Covering Fire", "weapon": "pistols", "clip": "",
		"desc": "Watch your allies: until your next turn, the first enemy to attack an ally within 3 tiles of you gets shot (if it's in range)",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0, "radius": RADIUS,
	}, 364)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	var who: Array = b.side(u.team).filter(func(a): return a != u and b.gap(u, a) <= RADIUS).map(func(a): return a.name)
	p.notes.append("Covering Fire: watching %s until your next turn" % (", ".join(who) if not who.is_empty() else "allies within %d" % RADIUS))


func overwatch(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> int:
	return RADIUS


## D112: watch when allies within the radius are in a foe's reach.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var watched := 0
	for a in b.side(u.team):
		if a != u and b.gap(u, a) <= RADIUS and BWAI.threat(b, a, a.pos) > 0:
			watched += 1
	if watched == 0:
		return {}
	return { "target": u.pos, "element": "", "score": 3.0 + 2.0 * watched }

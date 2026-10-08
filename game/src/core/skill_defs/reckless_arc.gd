extends BWSkillDef
## Axe. D435 (replaces Reckless Swing, retired): a wild sweep of the five
## hexes in front of you, every neighbour but the one straight behind the
## heading (the three front hexes and both flanks). Every foe there is hit,
## the arc takes your element, and you are left open: Scorched (attacks on
## you +10%) through your next turn, whatever the swing hit.

const POWER := 12
const CD := 2


func _init() -> void:
	define({
		"key": "reckless_arc", "name": "Reckless Arc", "weapon": "axe", "clip": "cut",
		"desc": "A wild sweep through the 5 tiles in front of you (all but the one behind): every enemy there is hit and the arc takes your element. It leaves you open: you are Scorched (attacks on you +10%) until your next turn is over",
		"targeting": "dir", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER, "aoe": true,
	}, 311)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = arc(b, u.pos, target)
	p.victims = b._foes_on(u, p.hexes)
	p.notes.append("Reckless: you are Scorched (attacks on you +%d%%) until your next turn ends" % BWSkills.SCORCH_PCT)


## The five neighbours of `from` other than the one opposite `toward`.
static func arc(b: BWBattle, from: Vector2i, toward: Vector2i) -> Array:
	var di := BWHex.direction_index(from, toward)
	if di < 0:
		return []
	var nb := BWHex.neighbors(from)
	var out: Array = []
	for off in [-2, -1, 0, 1, 2]:
		var h: Vector2i = nb[(di + off + 6) % 6]
		if b.board.exists(h):
			out.append(h)
	return out


func after_hits(b: BWBattle, u: BWUnit, _p: Dictionary, _results: Array) -> void:
	if u.alive():
		b._add_status(u, "scorched", u)

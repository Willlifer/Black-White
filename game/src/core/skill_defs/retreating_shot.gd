extends BWSkillDef
## Bow (D106). Shoot a foe within RANGE, then fall back: MOVE more hexes of
## movement this turn (grant_move: a second move of MOVE if you'd already
## moved, else MOVE on top of your move). The arrow lays the element on the
## target's hex.

const POWER := 10
const CD := 2
const RANGE := 5
const MOVE := 2


func _init() -> void:
	define({
		"key": "retreating_shot", "name": "Retreating Shot", "weapon": "bow", "clip": "shot_quick",
		"desc": "Shoot an enemy up to 5 tiles away, then move 2 more tiles this turn",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER,
	}, 333)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	p.notes.append("Then move %d more" % MOVE)


func after_paint(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary,
		_results: Array, _stripped: int) -> void:
	grant_move(b, u, MOVE)


## +n move after acting (shared with Tumble), the battle's own convention
## (BWBattle._after_action_move): a unit that already moved gets a second
## move of n (`bonus_move`); one that hasn't gets n on top of its move
## (`extra_move`, read by the move total).
static func grant_move(b: BWBattle, u: BWUnit, n: int) -> void:
	if u.moved:
		u.fx["bonus_move"] = int(u.fx.get("bonus_move", 0)) + n
		b._emit({ "type": "bonus_move", "unit": u.id, "hexes": u.fx.bonus_move })
	else:
		u.fx["extra_move"] = int(u.fx.get("extra_move", 0)) + n
		b._emit({ "type": "move_bonus", "unit": u.id, "amount": n, "notes": [] })

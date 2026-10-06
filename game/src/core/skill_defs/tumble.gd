extends BWSkillDef
## Daggers (D108). Free (spends nothing): after you attack this turn, move
## MOVE more (the FX `bonus_move`, Retreating Shot's grant_move). Set after
## attacking, it grants the move at once; set before, it waits for your
## attack (a basic or a damaging skill, heard on BWBattle.event) and lapses
## when your turn ends.

const RetreatingShot := preload("res://src/core/skill_defs/retreating_shot.gd")

const CD := 1
const MOVE := 2


func _init() -> void:
	define({
		"key": "tumble", "name": "Tumble", "weapon": "daggers", "clip": "",
		"desc": "Free: after you attack this turn, move 2 more tiles",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0, "free_action": true,
	}, 351)


func target_ok(_b: BWBattle, u: BWUnit, _h: Vector2i, _element: String) -> bool:
	return not u.fx.get("tumble", false)


func plan(_b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.notes.append("Tumble: move %d more %s" % [MOVE, "now" if u.acted else "after you attack"])


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	if u.acted:
		RetreatingShot.grant_move(b, u, MOVE)
		return 0
	u.fx["tumble"] = true
	if not u.fx.get("tumble_listen", false):
		u.fx["tumble_listen"] = true
		b.event.connect(_wait.bind(u, weakref(b)))
	return 0


func _wait(e: Dictionary, u: BWUnit, wb: WeakRef) -> void:
	if str(e.get("unit", "")) != u.id or not u.fx.get("tumble", false):
		return
	var b: BWBattle = wb.get_ref()
	if e.type == "turn_end" or b == null:
		u.fx.erase("tumble")
	elif e.type == "attack" or (e.type == "skill" and BWSkills.is_damaging(str(e.get("skill", "")))):
		u.fx.erase("tumble")
		RetreatingShot.grant_move(b, u, MOVE)


## D112: the AI moves before it acts, so it tumbles after attacking (the
## move comes at once), when a hex within MOVE is safer (fewer foes in reach, then farther).
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	if not u.acted or u.fx.get("tumble", false):
		return false
	if BWAI.threat(b, u, u.pos) == 0:
		return false
	var here := BWAI.danger(b, u, u.pos)
	for h in b.board.area(u.pos, MOVE):
		if h != u.pos and b.can_stand(u, h) and b.board.is_passable(h) and BWAI.danger(b, u, h) < here:
			return true
	return false

extends BWSkillDef
## Lance (D105). The lance's crowd-spacing tool (Tridentpierce pierces a
## line; Sweep clears a front): the 3 hexes of the front arc beside you
## (Cleave's arc) take POWER each, every foe there is shoved PUSH straight
## away from you (slamming for SLAM_PCT% if blocked, Guardrush's rule), and
## the arc takes 1 step of the element.

const Guardrush := preload("res://src/core/skill_defs/guardrush.gd")
const Cleave := preload("res://src/core/skill_defs/cleave.gd")

const POWER := 9
const CD := 3
const PUSH := 1
const SLAM_PCT := 8


func _init() -> void:
	define({
		"key": "sweep", "name": "Sweep", "weapon": "lance", "clip": "sweep",
		"desc": "Sweep the 3 tiles in front of you: every enemy there is hit and shoved 1 away from you (slamming for 8% if blocked), and the arc takes your element",
		"targeting": "dir", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER, "aoe": true,
	}, 322)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = Cleave.arc_from(b, u.pos, target)
	p.victims = b._foes_on(u, p.hexes)
	for v in p.victims:
		Guardrush.note(b, v, BWHex.direction_index(u.pos, v.pos), PUSH, SLAM_PCT, p.notes)


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	for v in Guardrush.landed(p, results):
		Guardrush.shove(b, u, v, BWHex.direction_index(u.pos, v.pos), PUSH, SLAM_PCT, id)

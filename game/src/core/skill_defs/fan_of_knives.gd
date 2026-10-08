extends BWSkillDef
## Daggers. D430 rework (the author: "a massive radius-2 self-targeted AoE
## that grants the user immunity to reactions caused by this AoE"; the dagger
## is the spellblade AoE merchant, "like staff but higher risk, higher
## reward"): spin and loose knives at every foe within RADIUS (POWER each),
## and every hex within RADIUS but your own takes 1 step of the element. The
## detonations, shocks, overheats and overfreezes that paint sets off can't
## hurt you (BWKit2 SHIELD, read by BWBattle._tile_hurt / _arc); your allies
## standing in it are not spared. Was: the ring, radius 1.

const POWER := 8
const CD := 3
const RADIUS := 2


func _init() -> void:
	define({
		"key": "fan_of_knives", "name": "Fan of Knives", "weapon": "daggers", "clip": "spin",
		"desc": "Spin and loose knives at every enemy within 2 tiles; everything within 2 takes your element, and the blasts and shocks it sets off can't hurt you (your allies aren't spared)",
		"targeting": "self", "needs_element": true, "range": 0, "cd": CD,
		"power": POWER, "radius": RADIUS, "aoe": true,
	}, 354)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._without(b._on_board(b.board.area(u.pos, RADIUS)), u.pos)
	p.victims = b._foes_on(u, p.hexes)
	p.notes.append("Radius %d: %d tiles take the element; its reactions can't hurt you" % [RADIUS, (p.hexes as Array).size()])
	var mates: Array = b.side(u.team).filter(func(a): return a != u and a.alive() and a.pos in p.hexes)
	if not mates.is_empty():
		p.notes.append("Allies in the area aren't spared its reactions: %s" % ", ".join(mates.map(func(a): return a.name)))


## The paint, with the user shielded from what it sets off (D430).
func ground(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary) -> int:
	u.fx[BWKit2.SHIELD] = true
	super.ground(b, u, el, target_hex, p)
	u.fx.erase(BWKit2.SHIELD)
	return 0


## A self-centred attack: the AI weighs it like any other.
func ai_considers(_row: Dictionary) -> bool:
	return true

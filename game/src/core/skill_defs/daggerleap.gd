extends BWSkillDef
## Daggers. Leap up to LEAP_RANGE hexes, or to any free hex already carrying
## the element (§7.4), and flourish on the ring where you land. D87: foes you
## land behind (BWBattle.behind) take +BACKSTAB_PCT%; Daggerleap+ +PLUS_BACKSTAB_PCT%.
## D362 high ground: leaping down to a hex 1+ level below you reaches 1
## farther and the flourish ring is 1 wider (BWWeaponMove.above).

const PLUS_BACKSTAB_PCT := 75


func _init() -> void:
	define({
		"key": "daggerleap", "name": "Daggerleap", "weapon": "daggers", "clip": "",
		"desc": "Leap up to 3 tiles, or to any tile already carrying your element, and land in a flourish. Foes you land behind take +50%",
		"plus": "Daggerleap+: the backstab is +75%",
		"targeting": "leap", "needs_element": true, "range": BWSkills.LEAP_RANGE, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.LEAP_DMG, "radius": BWSkills.LEAP_RADIUS, "aoe": true,
	}, 80)


## D362: the leap's targets, with +1 reach onto lower hexes.
func targets(b: BWBattle, u: BWUnit, element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rng_max := int(data.get("range", 0))
	for h in b.board.cells():
		if h == u.pos or not b.can_stand(u, h):
			continue
		var reach := rng_max + (1 if BWWeaponMove.above(b, u, h) else 0)
		if BWHex.distance(u.pos, h) <= reach or b.tiles.carries(h, element):
			out.append(h)
	return out


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.dest = target
	var high := BWWeaponMove.above(b, u, target)
	var radius := BWSkills.LEAP_RADIUS + (1 if high else 0)
	p.hexes = b._without(b._on_board(b.board.area(target, radius)), target)
	if high:
		p.notes.append("High ground: leaping down, reach +1 and the landing ring radius %d" % radius)
	p.victims = b._foes_on(u, p.hexes)
	var pct := BWSkills.BACKSTAB_PCT
	if upgraded(u):
		pct = PLUS_BACKSTAB_PCT
	for v in p.victims:                 # D87: landing behind a foe
		if b.behind(v, target):
			p.shares[v.id] = [1.0 + pct / 100.0, "Backstab (landed behind): +%d%%" % pct, "Backstab"]


## A leap: straight to the landing, no fire crossing (D44).
func relocate(b: BWBattle, u: BWUnit, p: Dictionary, _target_hex: Vector2i) -> void:
	b.skill_relocate(u, p, [u.pos, p.dest], "leap")

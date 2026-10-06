extends BWSkillDef
## Bow (D106). Three arrows in a fan: one at the clicked foe (within RANGE),
## one down each neighbouring heading, each at the first foe it meets within
## RANGE (an ally or rock stops a side arrow). Every arrow is PCT% of POWER
## and rolled on its own; each foe struck takes the element on its hex.

const POWER := 12
const CD := 2
const RANGE := 5
const PCT := 60


func _init() -> void:
	define({
		"key": "split_arrow", "name": "Split Arrow", "weapon": "bow", "clip": "shot_fan",
		"desc": "Three arrows in a fan, up to 5 tiles: one at the target and one down each heading beside it, 60% each",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER,
	}, 332)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	var di := BWHex.direction_index(u.pos, target)
	if di >= 0:
		for off in [-1, 1]:
			var d: int = (di + off + 6) % 6
			var nb: Vector2i = BWHex.neighbors(u.pos)[d]
			for h in b.board.ray(u.pos, nb, RANGE):
				if b.board.terrain(h) == BWBoard.JAGGED or not b._reaches(u.pos, h, RANGE):
					break
				var o := b.unit_at(h)
				if o == null:
					continue
				if o.team != u.team and not o in p.victims:
					p.victims.append(o)
				break
	for v in p.victims:
		p.hexes.append(v.pos)
		p.shares[v.id] = [PCT / 100.0, "Split Arrow: %d%% each" % PCT]
	if p.victims.size() > 1:
		p.notes.append("Split Arrow: %d foes in the fan" % p.victims.size())

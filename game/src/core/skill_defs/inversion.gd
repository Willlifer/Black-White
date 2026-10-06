extends BWSkillDef
## Staff spell (D107). Flip the axes on one hex within RANGE: fire 3 becomes
## water 3, dark 2 becomes light 2; a fuse and a gale swap; stasis and glaze
## stay. Then a basic follow-up. Inversion+: the hex and its ring flip.

const CD := 3
const RANGE := 4
const SWAP := { "fuse": "gale", "gale": "fuse" }


func _init() -> void:
	define({
		"key": "inversion", "name": "Inversion", "weapon": "staff", "clip": "",
		"desc": "Flip a tile's charge: fire becomes water, dark becomes light, a fuse becomes a gale and back. Then act again",
		"plus": "Inversion+: the hex and its ring flip",
		"targeting": "hex", "needs_element": false, "range": RANGE, "cd": CD,
		"power": 0, "follow_up": ["basic"], "min_range": 0, "los": true, "spell": true,
	}, 343)


func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	return flips(b, h)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	if upgraded(u):
		for h in b.board.neighbors(target):
			if flips(b, h):
				p.hexes.append(h)
		p.notes.append("Inversion+: %d tiles flip" % p.hexes.size())
	else:
		p.notes.append("Flip the tile's charge")


## Is there anything on `h` that flipping changes?
func flips(b: BWBattle, h: Vector2i) -> bool:
	var e := b.tiles.at(h)
	return not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0 or SWAP.has(str(e.marker)))


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	for h in p.hexes:
		var e: Dictionary = b.tiles.entries.get(h, {})
		if e.is_empty():
			continue
		e.h = -int(e.h)
		e.v = -int(e.v)
		e.marker = SWAP.get(str(e.marker), str(e.marker))
	b._emit({ "type": "paint", "unit": u.id, "element": "", "hexes": p.hexes, "kind": "inversion" })
	return 0


## D112: flip ground that hurts us into ground that helps (enemy fire under
## an ally becomes water, a fuse beside an ally becomes a gale), or kind
## ground under a foe into harm. BWAI adds the basic follow-up's value.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var best := {}
	for h in b.skill_targets(u, id, ""):
		var e := b.tiles.at(h)
		var o := b._centre_at(h)
		if o == null:
			continue
		var bad := int(e.h) > 0 or int(e.v) < 0 or str(e.marker) == "fuse"
		var weight := absi(int(e.h)) + absi(int(e.v)) + (3 if SWAP.has(str(e.marker)) else 0)
		var score := 0.0
		if bad and o.team == u.team:
			score = 2.0 * weight + (1.0 if str(e.get("source", "")) != u.id else 0.0)
		elif not bad and o.team != u.team:
			score = 1.5 * weight
		if score >= 4.0 and (best.is_empty() or score > best.score):
			best = { "target": h, "element": "", "score": score }
	return best

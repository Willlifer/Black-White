extends BWSkillDef
## Staff spell (D107; D418 author: "Make staff Inversion target a radius of 2.
## So big AOE. And just the element swap on all tiles."). Aim at a hex within
## RANGE (sight needed): every tile within RADIUS of it (19 hexes) has its
## axes flipped by the inversion pairs: fire n <-> water n, dark n <-> light n;
## a fuse and a gale swap; stasis and glaze stay. Nothing else: no damage, no
## status, no follow-up (the old basic follow-up is gone). Inversion+: the
## cooldown drops to CD_PLUS.

const CD := 4
const CD_PLUS := 3
const RANGE := 4
const RADIUS := 2
const SWAP := { "fuse": "gale", "gale": "fuse" }
## D418: the inversion pairs, for the preview's swap tags.
const PAIR := { "fire": "water", "water": "fire", "dark": "light", "light": "dark" }


func _init() -> void:
	define({
		"key": "inversion", "name": "Inversion", "weapon": "staff", "clip": "",
		"desc": "Flip every tile within 2 of a tile up to 4 away: fire becomes water, dark becomes light, a fuse becomes a gale, and back. Nothing else happens",
		"plus": "Inversion+: cooldown 3 (not 4)",
		"targeting": "hex", "needs_element": false, "range": RANGE, "cd": CD, "radius": RADIUS,
		"power": 0, "min_range": 0, "los": true, "spell": true,
	}, 343)


func cooldown(u: BWUnit) -> int:
	return CD_PLUS if upgraded(u) else CD


## A target is any hex in range whose area has something to flip.
func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	for a in b._on_board(b.board.area(h, RADIUS)):
		if flips(b, a):
			return true
	return false


func plan(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p["area"] = b._on_board(b.board.area(target, RADIUS))
	p.hexes = (p.area as Array).filter(func(h): return flips(b, h))
	p.notes.append("Inversion: %d tile%s within %d flip" % [p.hexes.size(), "" if p.hexes.size() == 1 else "s", RADIUS])


## Is there anything on `h` that flipping changes?
func flips(b: BWBattle, h: Vector2i) -> bool:
	var e := b.tiles.at(h)
	return not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0 or SWAP.has(str(e.marker)))


## D418: one tile's swap as text ("fire 3 → water 3", "fuse → gale"), for the
## preview's tags and the log. Pure.
static func swap_text(e: Dictionary) -> String:
	var parts: Array = []
	if bool(e.get("lava", false)) and int(e.get("h", 0)) > 0:         # D494: lava flips one step, as fire 1
		parts.append("lava %d → %d" % [int(e.h), int(e.h) - 1])
		if int(e.get("v", 0)) != 0:
			var lv := "light" if int(e.v) > 0 else "dark"
			parts.append("%s %d → %s %d" % [lv, absi(int(e.v)), PAIR[lv], absi(int(e.v))])
		return ", ".join(parts)
	for pair in [["h", "fire", "water"], ["v", "light", "dark"]]:
		var n := int(e.get(pair[0], 0))
		if n != 0:
			var from: String = pair[1] if n > 0 else pair[2]
			parts.append("%s %d → %s %d" % [from, absi(n), PAIR[from], absi(n)])
	var mk := str(e.get("marker", ""))
	if SWAP.has(mk):
		parts.append("%s → %s" % [mk, SWAP[mk]])
	return ", ".join(parts)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	var swaps: Array = []
	for h in p.hexes:
		var e: Dictionary = b.tiles.entries.get(h, {})
		if e.is_empty():
			continue
		swaps.append({ "hex": h, "text": swap_text(e) })
		if b.tiles.is_lava(h):
			# D494: lava flips as fire 1: that step turns to water and douses
			# against the rest, so the lava drops a step (light / dark still flip)
			e.h = int(e.h) - 1
			e.v = -int(e.v)
			if int(e.v) > 0:
				e["lsrc"] = u.id                   # D496
			if int(e.h) <= 0:
				e.erase("lava")
			if int(e.h) == 0 and int(e.v) == 0:
				b.tiles.entries.erase(h)
			continue
		e.h = -int(e.h)
		e.v = -int(e.v)
		if int(e.v) > 0:
			e["lsrc"] = u.id                       # D496: flipped to light, it's the inverter's
		e.marker = SWAP.get(str(e.marker), str(e.marker))
	b._emit({ "type": "paint", "unit": u.id, "element": "", "hexes": p.hexes, "kind": "inversion",
		"area": p.get("area", p.hexes), "swaps": swaps })
	return 0


## D112 / D418: the whole area's net value. Ground that hurts our side
## (fire, water under an enemy's feet is good for them ... ) is weighed per
## unit standing in the area: a flip that turns harm under an ally into help,
## or help under a foe into harm, scores; the reverse costs. Empty tiles count
## a little (a fuse near allies becoming a gale). Fires when the net is clear.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var best := {}
	for t in b.skill_targets(u, id, ""):
		var score := 0.0
		for h in b._on_board(b.board.area(t, RADIUS)):
			var e := b.tiles.at(h)
			if e.is_empty() or not flips(b, h):
				continue
			var bad := int(e.h) > 0 or int(e.v) < 0 or str(e.marker) == "fuse"
			var weight := absi(int(e.h)) + absi(int(e.v)) + (3 if SWAP.has(str(e.marker)) else 0)
			var o := b._centre_at(h)
			if o == null:
				continue
			var mine := o.team == u.team
			if bad == mine:
				score += (2.0 if mine else 1.5) * weight      # harm under us goes, or harm arrives under them
			else:
				score -= (2.0 if mine else 1.5) * weight      # the flip would hand them help / us harm
		if score >= 4.0 and (best.is_empty() or score > best.score):
			best = { "target": t, "element": "", "score": score }
	return best

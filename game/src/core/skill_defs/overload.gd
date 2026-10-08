extends BWSkillDef
## Daggers. D440 (replaces Assassinate, retired): set off every charge
## within RADIUS of you, your own hex included. Each hex holding charge (fire,
## water, light or dark steps, or a thunder fuse) blows like a fuse
## detonation (BWTiles: 5% + 4% per step, x1.5 on glaze) at OVERLOAD_PCT%
## more, and is spent (cleared). Each blast hits its own hex in full and the
## six around it at half (the detonation rule), both teams: no immunity for
## the user (pure risk / reward; Fan of Knives is the shielded paint). Ice
## stasis and gale marks are not charge. Uses the action.

const CD := 4
const RADIUS := 2
const OVERLOAD_PCT := 50


func _init() -> void:
	define({
		"key": "overload", "name": "Overload", "weapon": "daggers", "clip": "brace",
		"desc": "Set off every charged tile within 2 of you (yours too): each blows like a fuse detonation at +50%, hitting its tile in full and the ring around it at half. You are not spared",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0,
	}, 355)


## The charged hexes within RADIUS: [{hex, pct, mix}], hex order.
static func blasts(b: BWBattle, u: BWUnit) -> Array:
	var out: Array = []
	var area := Array(b.board.area(u.pos, RADIUS))
	area.sort()
	for h in area:
		var e := b.tiles.at(h)
		if e.is_empty():
			continue
		var pts := absi(int(e.get("h", 0))) + absi(int(e.get("v", 0)))
		if pts == 0 and str(e.get("marker", "")) != "fuse":
			continue
		var pct := float(BWTiles.DETONATE_BASE_PCT + BWTiles.DETONATE_PER_POINT_PCT * pts)
		if int(e.get("glaze", 0)) > 0:
			pct *= BWTiles.SHATTER_MULT
		pct *= 1.0 + OVERLOAD_PCT / 100.0
		out.append({ "hex": h, "pct": pct, "points": pts, "mix": BWTiles.blast_mix(e) })
	return out


## What the blasts do to each unit: { unit: damage }, the detonation rule
## (its hex in full, the ring at half, min 1).
static func damage(b: BWBattle, bl: Array) -> Dictionary:
	var hurt := {}
	for d in bl:
		for o in b.units:
			if not o.alive():
				continue
			var dist := BWHex.distance(o.pos, d.hex)
			if dist > 1:
				continue
			var dmg := b._tile_dmg(o, float(d.pct), "thunder")
			if dist >= 1:
				dmg = maxi(1, int(dmg / 2.0))
			hurt[o] = int(hurt.get(o, 0)) + dmg
	return hurt


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	var bl := blasts(b, u)
	p["blasts"] = bl                      # p.hexes stays empty: nothing is painted
	p.notes.append("Overload: %d charged tiles within %d blow at +%d%%" % [bl.size(), RADIUS, OVERLOAD_PCT])
	var words: Array = []
	var hurt := damage(b, bl)
	for o in hurt:
		words.append("%s%s %d" % [o.name, " (you)" if o == u else "", int(hurt[o])])
	if not words.is_empty():
		p.notes.append("Blasts: " + ", ".join(words))


func decorate(e: Dictionary, p: Dictionary) -> void:
	e["blasts"] = (p.get("blasts", []) as Array).map(func(d): return d.hex)


## The blasts: every tile is spent, then everyone in reach is hurt at once.
func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	var bl: Array = p.get("blasts", [])
	if bl.is_empty():
		return 0
	for d in bl:
		b.tiles.clear(d.hex)
		b._emit({ "type": "detonate", "hex": d.hex, "pct": d.pct, "radius": 1, "mix": d.mix, "by": u.id, "skill": id })
	b._emit({ "type": "overload", "unit": u.id, "hexes": bl.map(func(d): return d.hex) })   # the view clears the spent tiles
	var hurt := damage(b, bl)
	u.fx["detonated"] = true
	for o in hurt:
		if b.over:
			break
		b._tile_hurt(o, int(hurt[o]), "detonation", u.id)
	return 0


## D112: set it off when the blasts hurt the foes more than your side
## (you count double: you're the one standing in it).
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var bl := blasts(b, u)
	if bl.is_empty():
		return {}
	var score := 0.0
	var hurt := damage(b, bl)
	for o in hurt:
		var d := float(hurt[o])
		if o.team == u.team:
			score -= d * (2.0 if o == u else 1.0) + (1000.0 if d >= o.hp else 0.0)
		elif b.can_harm(u, o):
			score += d + (1000.0 if d >= o.hp else 0.0)
	if score < 8.0:
		return {}
	return { "target": u.pos, "element": "", "score": score }

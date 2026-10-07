class_name BWSlides
extends RefCounted
## D261 ice slides (design/ELEMENTS-v3.md §2 with the author's 2026-10-07
## rulings). Glaze is slippery: a unit that ENTERS a glazed hex (walking,
## pushed or pulled) keeps going in its direction of travel, one hex at a
## time and at no cost, until:
##   * the next hex is non-ice standable ground: it slides onto it and stops;
##   * the next hex is blocked (rock, a unit, a pillar or a wall, a rise of 1
##     or more up): it stops before it, and if it slid at least 1 hex that's
##     a SLAM, SLAM_PCT to it and to the unit it hit;
##   * the next hex is lower (a ledge of any height): it drops onto it and
##     stops there (no fall damage);
##   * the map's edge or void: it stops, no slam (nothing slides off the map);
##   * SLIDE_MAX slide hexes.
## A slide ends a walk, then the unit gets +1 move (the author's ruling; once
## a turn). Crossing damage applies on the slide hexes, whatever started it.
## Skate and Skater holders (D294) and multi-hex units never slide.
##
## Pure parts (slide_path, slippery) read only the board and the tiles; the
## battle parts (walk_reach, after_walk, after_push) take the battle.

const SLIDE_MAX := 6
const SLAM_PCT := 8.0
const AFTER_MOVE := 1             # the author's ruling: a slide ends the walk, then +1 move


## A glazed (slippery) hex: a charged hex with glaze above 0 that isn't a
## pillar. Stasis markers don't slip.
static func slippery(tiles: BWTiles, hex: Vector2i) -> bool:
	return tiles.is_glazed(hex) and not tiles.is_pillar(hex)


## Does `u` slide at all? Skate (it may stop on the first ice hex it enters,
## so it simply does) and multi-hex units don't.
static func slides(u: BWUnit) -> bool:
	return u != null and maxi(u.size, 1) <= 1 and not BWEffects.has(u, "skate") and not BWKsIce.never_slides(u)   # D294 Skater


## Where a unit that just ENTERED `from` heading `dir` (0-5) slides to. Pure.
## { path: [from, ...slide hexes], stop: "" (no slide) | "ground" | "ledge" |
##   "rock" | "unit" | "pillar" | "edge" | "cap", slam_target: BWUnit or null,
##   slam: bool (slid >= 1 and stopped by rock, a unit or a pillar),
##   into: what it hit, in words }
## `from` not slippery, or a unit that doesn't slide: path [from], stop "".
## Units block through tiles.occupant (unset = nobody).
static func slide_path(board: BWBoard, tiles: BWTiles, unit: BWUnit, from: Vector2i, dir: int) -> Dictionary:
	var out := { "path": [from], "stop": "", "slam_target": null, "slam": false, "into": "" }
	if dir < 0 or dir > 5 or not board.exists(from) or not slippery(tiles, from) or not slides(unit):
		return out
	var cur := from
	var stop := "cap"
	for i in SLIDE_MAX:
		var nxt: Vector2i = BWHex.neighbors(cur)[dir]
		if not board.exists(nxt):
			stop = "edge"
			break
		var o: BWUnit = tiles.occupant.call(nxt) if tiles.occupant.is_valid() else null
		if o != null and o != unit:
			stop = "unit"
			out.slam_target = o
			out.into = o.name
			break
		if board.terrain(nxt) == BWBoard.JAGGED:
			stop = "rock"
			out.into = "rock"
			break
		if board.blocked(nxt):
			stop = "pillar"
			out.into = "an ice pillar" if tiles.is_pillar(nxt) else "a wall"
			break
		var rise := board.elevation(nxt) - board.elevation(cur)
		if rise >= 1:
			stop = "rock"
			out.into = "a rise"
			break
		out.path.append(nxt)
		cur = nxt
		if rise < 0:
			stop = "ledge"
			break
		if not slippery(tiles, nxt):
			stop = "ground"
			break
	out.stop = stop
	out.slam = (out.path as Array).size() > 1 and stop in ["rock", "unit", "pillar"]
	return out


# ---------------------------------------------------------------- walking (BWBattle.reachable)

## The slippery hexes `u`'s walk must treat as "enter = slide" ({} for a unit
## that doesn't slide, or a board with no glaze: the search is unchanged).
static func ice_for(b: BWBattle, u: BWUnit) -> Dictionary:
	var out := {}
	if not slides(u):
		return out
	for h in b.tiles.entries:
		if h != u.pos and slippery(b.tiles, h):
			out[h] = true
	return out


## The search ran with every slippery hex blocked (a walk can't cross ice:
## entering it slides). Now add each slide: from every reached hex, a step onto
## an adjacent slippery hex that the budget pays for slides to its end, which
## becomes a stop with { cost, from, stop, path (walk + slide), slide }. A hex
## already reachable on foot for the same cost or less keeps the walk.
static func walk_reach(b: BWBattle, u: BWUnit, r: Dictionary, budget: int, opts: Dictionary, rules: Dictionary, ice: Dictionary) -> void:
	if ice.is_empty():
		return
	var cand := {}
	var keys := r.keys()
	keys.sort()
	for h in keys:
		var c := int(r[h].cost)
		for n in b.board.neighbors(h):
			if not ice.has(n) or b.unit_at(n) != null:
				continue
			var sc := b.board.step_cost(h, n, opts)
			if sc < 0:
				continue
			if not rules.is_empty():
				sc = b._perk_step(rules, h, n, sc)
			if c + sc > budget:
				continue
			var sp := slide_path(b.board, b.tiles, u, n, BWHex.direction_index(h, n))
			var end: Vector2i = sp.path[-1]
			if end == u.pos and (sp.path as Array).size() == 1:
				continue
			var walk := _route(r, h)
			var full: Array = walk + Array(sp.path)
			var prev: Dictionary = cand.get(end, {})
			if prev.is_empty() or c + sc < int(prev.cost):
				cand[end] = { "cost": c + sc, "from": full[-2], "stop": true, "path": full, "slide": sp }
	var parents := {}                      # D308: hexes other routes walk through
	for h in r:
		if r[h].from != h:
			parents[r[h].from] = true
	for end in cand:
		var old: Dictionary = r.get(end, {})
		if not old.is_empty() and bool(old.get("stop", true)) and int(old.cost) <= int(cand[end].cost):
			continue
		if not old.is_empty() and parents.has(end):
			continue                           # D308: replacing a parent hex broke its children's routes (a from-cycle hung path_to)
		r[end] = cand[end]


static func _route(r: Dictionary, h: Vector2i) -> Array:
	if r[h].has("path"):
		return Array(r[h].path).duplicate()
	var out: Array = []
	var k := h
	for _i in r.size() + 1:                 # D308: bounded, never hangs on a bad tree
		out.push_front(k)
		var prev: Vector2i = r[k].from
		if prev == k or not r.has(prev):
			break
		k = prev
	return out


## The walking part of a reach entry's path (the slide's hexes taken off).
static func walk_part(path: Array, slide: Dictionary) -> Array:
	if slide.is_empty():
		return path
	return path.slice(0, path.size() - (slide.path as Array).size() + 1)


## Emit the slide of a walk (a `move` of kind "slide").
static func emit_slide(b: BWBattle, u: BWUnit, slide: Dictionary) -> void:
	if slide.is_empty() or (slide.path as Array).size() < 2:
		return
	b._emit({ "type": "move", "unit": u.id, "path": slide.path, "kind": "slide", "stop": slide.stop })


## After a walk that slid (crossing damage is already paid on the whole
## path): the slam, then +1 move once a turn.
static func after_walk(b: BWBattle, u: BWUnit, slide: Dictionary) -> void:
	if slide.is_empty() or (slide.path as Array).size() < 2:
		return
	if bool(slide.slam):
		_slam(b, u, slide, "")
		b._undo = {}                                  # a slam hurt someone else: no take-back
	if b.over or not u.alive():
		return
	if int(u.fx.get("slide_turn", -1)) != b._turn_serial:
		u.fx["slide_turn"] = b._turn_serial
		u.fx["bonus_move"] = maxi(int(u.fx.get("bonus_move", 0)), AFTER_MOVE)
		b._emit({ "type": "bonus_move", "unit": u.id, "hexes": u.fx.bonus_move, "perks": ["Slide"] })


# ---------------------------------------------------------------- displacement

## A push or pull just left `v` on its hex heading `dir`: if that hex is
## slippery it slides on (pushes, then slides, then slams). Crossing damage
## on the slide hexes, the electrified pool's entry shock, then the slam.
## `by`: who caused it (slam credit), "" = nobody. Returns the slide.
static func after_push(b: BWBattle, v: BWUnit, dir: int, by: String = "") -> Dictionary:
	if b.over or v == null or not v.alive():
		return {}
	var sp := slide_path(b.board, b.tiles, v, v.pos, dir)
	if (sp.path as Array).size() < 2:
		return sp
	v.pos = sp.path[-1]
	b._emit({ "type": "move", "unit": v.id, "path": sp.path, "kind": "slide", "stop": sp.stop })
	for i in range(1, (sp.path as Array).size()):
		var pct := b.tiles.crossing_pct(sp.path[i])
		if pct > 0 and v.alive() and not BWEffects.has(v, "heat_rush") and not BWOverheat.no_cross(v):   # D286 Trailblazer
			b._tile_hurt(v, b._tile_dmg(v, pct, "fire"), "fire_cross", str(b.tiles.at(sp.path[i]).get("source", "")))
	BWPools.on_walk(b, v, sp.path)
	if bool(sp.slam) and v.alive() and not b.over:
		_slam(b, v, sp, by)
	return sp


static func _slam(b: BWBattle, v: BWUnit, sp: Dictionary, by: String) -> void:
	var o: BWUnit = sp.slam_target
	b._emit({ "type": "slam", "unit": v.id, "by": by, "into": sp.stop, "name": "Slide", "target": o.id if o != null else "",
		"hex": (sp.path as Array)[-1] })
	if v.alive():
		var pv := BWPerkRules.slam_pct(b, v, by, SLAM_PCT, false)     # D281: Rime Armour, Fault Lines
		if pv > 0.0:
			b._tile_hurt(v, b._tile_dmg(v, pv, ""), "slam", by)
	if o != null and o.alive() and not b.over:
		var po := BWPerkRules.slam_pct(b, o, by, SLAM_PCT, false)
		if po > 0.0:
			b._tile_hurt(o, b._tile_dmg(o, po, ""), "slam", by)
	var pth: Array = sp.path
	if str(sp.stop) == "pillar" and pth.size() >= 2:        # D281 Frostbite: slammed into a pillar
		BWPerkRules.after_slam(b, v, by, false, BWHex.neighbors(pth[-1])[BWHex.direction_index(pth[-2], pth[-1])])


## The slam % a slide would cost `u` (preview words, the AI).
static func slam_text(sp: Dictionary) -> String:
	if not bool(sp.get("slam", false)):
		return ""
	return "slam %d%%" % int(SLAM_PCT)

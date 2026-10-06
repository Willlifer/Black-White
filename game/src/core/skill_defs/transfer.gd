extends BWSkillDef
## Staff spell (D107). Lift one hex's whole charge (axes, marker and glaze;
## the source hex within RANGE) and set it down on an empty hex within RANGE
## of you, then a basic follow-up. The lifted tile becomes yours (source)
## and starts its timers fresh. Transfer+: the charge also spreads onto the
## destination's ring (empty, holdable hexes).
##
## D109 second pick: the player clicks the source, then the destination
## (second_targets: every empty, holdable hex within RANGE of the caster but
## the source). With no choice (the AI) the destination is automatic
## (dest_for): harmful ground (fire, dark, fuse, stasis) under the nearest foe
## standing on an empty hex, kind ground (light, water, gale) under the most
## hurt ally, else the empty hex nearest the source.

const CD := 3
const RANGE := 4
const NOWHERE := Vector2i(-9999, -9999)


func _init() -> void:
	define({
		"key": "transfer", "name": "Transfer", "weapon": "staff", "clip": "",
		"desc": "Lift one tile's whole charge or marker and set it down on an empty tile within 4 (click the tile, then where it goes), then act again",
		"plus": "Transfer+: the lifted charge spreads onto the destination and its ring",
		"targeting": "hex", "needs_element": false, "range": RANGE, "cd": CD, "second_pick": "hex",
		"power": 0, "follow_up": ["basic"], "min_range": 0, "los": true, "spell": true,
	}, 342)


## Something to lift, and somewhere to put it.
func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	return not b.tiles.at(h).is_empty() and dest_for(b, u, h) != NOWHERE


## D109: where the lifted charge may go.
func second_targets(b: BWBattle, u: BWUnit, _element: String, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if b.tiles.at(target).is_empty():
		return out
	for h in candidates(b, u, target):
		out.append(h)
	return out


## Empty, holdable hexes within RANGE of the caster, not the source.
func candidates(b: BWBattle, u: BWUnit, src: Vector2i) -> Array:
	var out: Array = []
	for h in b.board.area(u.pos, RANGE):
		if h != src and b.tiles.can_hold(h) and b.tiles.at(h).is_empty():
			out.append(h)
	return out


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var picked: Vector2i = p.get("choice", NOWHERE)
	var dest := picked if picked != NOWHERE else dest_for(b, u, target)
	if dest == NOWHERE:
		return
	p["lift_to"] = dest
	p.hexes = [target, dest]
	var spread: Array = [dest]
	if upgraded(u):
		for h in b.board.neighbors(dest):
			if h != target and b.tiles.can_hold(h) and b.tiles.at(h).is_empty():
				spread.append(h)
		p.hexes.append_array(spread.slice(1))
		p.notes.append("Transfer+: the charge spreads onto %d tiles" % spread.size())
	p["spread"] = spread
	var o := b.unit_at(dest)
	p.notes.append("Lift %s from %s to %s%s" % [describe(b, target), str(target), str(dest),
		(" (under %s)" % o.name) if o != null else ""])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, p: Dictionary) -> int:
	if not p.has("lift_to"):
		return 0
	var e: Dictionary = b.tiles.at(target_hex).duplicate(true)
	b.tiles.clear(target_hex)
	b._emit({ "type": "paint", "unit": u.id, "element": "", "hexes": [target_hex], "kind": "transfer" })
	e.source = u.id
	e.permanent = false
	e.erase("erupt")
	e.timer = BWTiles.MARK_CYCLES if str(e.marker) != "" else BWTiles.STEP_CYCLES
	for h in p.spread:
		b.tiles.entries[h] = e.duplicate(true)
	b._emit({ "type": "paint", "unit": u.id, "element": element_of(e), "hexes": p.spread, "kind": "transfer" })
	return 0


## The tile's main element in words, for the hint.
func describe(b: BWBattle, h: Vector2i) -> String:
	var e := b.tiles.at(h)
	var parts: Array = []
	if int(e.h) != 0:
		parts.append("%s %d" % ["fire" if int(e.h) > 0 else "water", absi(int(e.h))])
	if int(e.v) != 0:
		parts.append("%s %d" % ["light" if int(e.v) > 0 else "dark", absi(int(e.v))])
	if str(e.marker) != "":
		parts.append(str(e.marker))
	if int(e.glaze) > 0:
		parts.append("glaze")
	return " + ".join(parts)


static func element_of(e: Dictionary) -> String:
	if str(e.get("marker", "")) != "":
		return BWTiles.MARKER_ELEMENT[e.marker]
	if absi(int(e.h)) >= absi(int(e.v)):
		return "fire" if int(e.h) > 0 else "water"
	return "light" if int(e.v) > 0 else "dark"


## Is this ground bad to stand on (lift it under a foe)?
static func harmful(e: Dictionary) -> bool:
	return int(e.h) > 0 or int(e.v) < 0 or str(e.marker) in ["fuse", "stasis"]


## The automatic destination: an empty, holdable hex within RANGE of the
## caster (not the source). Harmful charge goes under the nearest foe;
## helpful charge under the most hurt ally; otherwise nearest the source.
func dest_for(b: BWBattle, u: BWUnit, src: Vector2i) -> Vector2i:
	var e := b.tiles.at(src)
	if e.is_empty():
		return NOWHERE
	var cands := candidates(b, u, src)
	if cands.is_empty():
		return NOWHERE
	var bad := harmful(e)
	var best := NOWHERE
	var best_score := -INF
	for h in cands:
		var o := b._centre_at(h)
		var score := -0.01 * BWHex.distance(src, h)
		if o != null:
			if bad and o.team != u.team:
				score += 100.0 - BWHex.distance(u.pos, h)
			elif not bad and o.team == u.team:
				score += 100.0 + 50.0 * (1.0 - float(o.hp) / maxf(o.max_hp(), 1.0))
			else:
				score -= 50.0
		if score > best_score:
			best_score = score
			best = h
	return best


## D112: the AI lifts harmful ground under a foe (a fuse or a strong charge:
## a detonation or a burn waiting there) or off an ally, or kind ground under
## a badly hurt ally. BWAI adds the basic follow-up's value.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var best := {}
	for src in b.skill_targets(u, id, ""):
		var e := b.tiles.at(src)
		var dest := dest_for(b, u, src)
		var o := b._centre_at(dest)
		var under := b._centre_at(src)
		var weight := absi(int(e.h)) + absi(int(e.v)) + (3 if str(e.marker) == "fuse" else 0)
		var score := 0.0
		if harmful(e):
			if o != null and o.team != u.team:
				score += 2.0 * weight
			if under != null and under.team == u.team:
				score += 2.0 * weight
		elif o != null and o.team == u.team and float(o.hp) / maxf(o.max_hp(), 1.0) < 0.6:
			score += 1.5 * weight
		if score >= 5.0 and (best.is_empty() or score > best.score):
			best = { "target": src, "element": "", "score": score }
	return best

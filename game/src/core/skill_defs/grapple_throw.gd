extends BWSkillDef
## Fists. Seize an adjacent foe and throw it down on a free hex next to you
## (the D97 free-placement hook, BWSkillDef.place): +GROUND_PCT% if it lands
## on charge you laid. The throw is a secondary effect (an avoid still
## throws, a resist stops it; an immune foe braces).
##
## D109 second pick: the player clicks the foe, then the landing
## (second_targets: the free hexes next to you). With no choice (the AI) the
## landing is automatic (dest_for: your own charge first, then hurtful
## ground, then the hex nearest the foe's own).

const POWER := 9
const CD := 3
const GROUND_PCT := 50
const NOWHERE := Vector2i(-9999, -9999)


func _init() -> void:
	define({
		"key": "grapple_throw", "name": "Grapple Throw", "weapon": "fists", "clip": "grapple",
		"desc": "Seize an adjacent enemy and throw it down on a free tile next to you; +50% if it lands on charge you laid",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER, "second_pick": "hex",
	}, 373)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	if p.victims.is_empty():
		return
	var v: BWUnit = p.victims[0]
	var picked: Vector2i = p.get("choice", NOWHERE)
	var dest := picked if picked != NOWHERE else dest_for(b, u, v)
	if dest == NOWHERE or b._immune(v, "displace"):
		p.notes.append("Nowhere to throw %s" % v.name if dest == NOWHERE else "%s braces: no throw" % v.name)
		return
	p["throw_to"] = dest
	p.notes.append("Throw %s down on %s%s" % [v.name, str(dest), " (your charge: +%d%%)" % GROUND_PCT if own_charge(b, u, dest) else ""])


func forecast_mods(b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	var dest: Vector2i = p.get("throw_to", NOWHERE)
	if dest != NOWHERE and own_charge(b, u, dest):
		mods.append({ "stage": "dmg", "value": 1.0 + GROUND_PCT / 100.0,
			"label": "Thrown onto your charge: +%d%%" % GROUND_PCT, "tag": "Grapple" })
	elif dest != NOWHERE:
		notes.append("+%d%% if thrown onto charge you laid" % GROUND_PCT)


func after_hits(b: BWBattle, _u: BWUnit, p: Dictionary, results: Array) -> void:
	var dest: Vector2i = p.get("throw_to", NOWHERE)
	if dest == NOWHERE or results.is_empty() or p.victims.is_empty() or b.over:
		return
	var v: BWUnit = p.victims[0]
	if v.alive() and results[0].result.secondary:
		place(b, v, dest)


## D109: where the foe on `target` may land (none if it can't be thrown).
func second_targets(b: BWBattle, u: BWUnit, _element: String, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var v := b.unit_at(target)
	if v == null or v.team == u.team or b._immune(v, "displace"):
		return out
	for h in b.board.neighbors(u.pos):
		if h != v.pos and b.can_place(v, h):
			out.append(h)
	return out


## Charge (an axis tile) on `h` that `u` laid.
static func own_charge(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	return b.tiles.charged(h) and str(b.tiles.at(h).get("source", "")) == u.id


## The landing: a free hex next to the thrower (not the foe's own). Your own
## charge first, then the most hurtful ground (fire, dark, a fuse), then the
## hex nearest the foe's, then row/column order.
func dest_for(b: BWBattle, u: BWUnit, v: BWUnit) -> Vector2i:
	var best := NOWHERE
	var best_score := -INF
	for h in b.board.neighbors(u.pos):
		if h == v.pos or not b.can_place(v, h):
			continue
		var score := 0.0
		if own_charge(b, u, h):
			score += 100.0
		score += 10.0 * b.tiles.intensity(h, "fire") + 10.0 * b.tiles.intensity(h, "dark")
		if b.tiles.conductive(h):
			score += 5.0
		score -= BWHex.distance(v.pos, h)
		if score > best_score:
			best_score = score
			best = h
	return best

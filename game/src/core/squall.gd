class_name BWSquall
extends RefCounted
## D309-D311 Wind: SQUALL, wind's explosion (the author, 2026-10-07: "Wind
## having a type of explosion is fine, some type of 'wildfire' spread that
## would affect light and dark perhaps."). Rules as built: ELEMENTS.md §17.1.
## Pure rules; state lives on BWBattle.wind["squalls"] (ids, hexes and
## numbers only, so clone() copies it).
##
## START: a FRESH wind arrival on a hex holding light >= 2 or dark >= 2 (a wind
## cast that gales it, or a fresh light/dark arrival that fires a gale marker
## and leaves the hex at 2+) starts a squall front from that hex, owned by the
## caster (a firing gale: the gale's owner). Its gale copies are ring 1 (2 or
## 3 for a gale 2/3) as ever; the front starts one ring beyond them.
## ADVANCE: at each of the next TICKS cycle ticks (inside BWWind.tick, after
## the vortex fields, before the beams and the decay), the front advances one
## ring outward. Every hex of that ring:
##   * gets a PROPAGATED +1 step of the squall's light or dark (owner = its
##     source): it never fires a marker, skips glazed hexes, pillars and walls,
##     and a seed or static it lands on follows the usual rules (§5.5, §5.6);
##   * pushes the unit on it 1 outward (away from the origin), both teams, as a
##     wind FIELD move: inside the wind caps (2 hexes a cycle, a field once a
##     turn), with dark 3 gravity, a slam (8%) when blocked by rock, a unit, a
##     pillar or a wall (onto glaze it just stops, D397).
## The ring is always outward (Claude, D310): a squall is an explosion, so the
## caster's Gust heading doesn't bend it; the push already goes "away".
## Light and dark only (fire has Overheat and wildfire, water has pools).
## One squall per owner: a new one replaces the old.

const TICKS := 3
const MIN_LEVEL := 2


static func squalls(b: BWBattle) -> Dictionary:
	return b.wind.get("squalls", {})


## The light/dark element a charge (h, v) can carry into a squall, or "".
static func element_of(v: int) -> String:
	if v >= MIN_LEVEL:
		return "light"
	if v <= -MIN_LEVEL:
		return "dark"
	return ""


## The hexes the front of `s` reaches at the next tick (on the board).
static func next_ring(b: BWBattle, s: Dictionary) -> Array:
	var out: Array = []
	for h in BWHex.ring(s.origin, int(s.ring)):
		if b.board.exists(h):
			out.append(h)
	out.sort()
	return out


# ---------------------------------------------------------------- start (BWBattle.paint)

## After a paint: a fresh gale on light/dark 2+ starts its owner's squall.
## `snap`: BWWind.before_paint's fields (a firing gale's owner).
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary, snap: Dictionary) -> void:
	if b.over or by == null:
		return
	var best := {}                                   # owner id -> [|v|, origin, el, radius]
	for g in r.get("gales", []):
		if not bool(g.get("fresh", false)):
			continue
		var hv: Array = g.get("hv", [0, 0])
		var el := element_of(int(hv[1]))
		if el == "":
			continue
		var owner := by
		if snap.has(g.origin):
			var o := b._unit(str((snap[g.origin] as Dictionary).get("source", "")))
			if o != null:
				owner = o
		var radius := maxi(1, int(g.get("level", 1)))
		for c in g.copies:
			radius = maxi(radius, BWHex.distance(g.origin, c))
		var lv := absi(int(hv[1]))
		var cur: Array = best.get(owner.id, [])
		if cur.is_empty() or lv > int(cur[0]) or (lv == int(cur[0]) and g.origin < cur[1]):
			best[owner.id] = [lv, g.origin, el, radius]
	if best.is_empty():
		return
	if not b.wind.has("squalls"):
		b.wind["squalls"] = {}
	var keys := best.keys()
	keys.sort()
	for id in keys:
		var row: Array = best[id]
		var replaced: bool = b.wind.squalls.has(id)
		b.wind["serial"] = int(b.wind.get("serial", 0)) + 1
		var s := { "owner": id, "origin": row[1], "element": row[2], "ring": int(row[3]) + 1,
			"left": TICKS, "born": int(b.wind.serial) }
		b.wind.squalls[id] = s
		b._emit({ "type": "squall", "unit": id, "hex": row[1], "element": row[2], "ring": int(s.ring),
			"next": next_ring(b, s), "left": TICKS, "replaced": replaced })


# ---------------------------------------------------------------- advance (BWWind.tick)

## The tick: every squall advances one ring (owners in id order).
static func tick(b: BWBattle) -> void:
	var all := squalls(b)
	if all.is_empty():
		return
	var keys := all.keys()
	keys.sort()
	for id in keys:
		if b.over:
			return
		var s: Dictionary = all[id]
		advance(b, s)
		s.ring = int(s.ring) + 1
		s.left = int(s.left) - 1
		if int(s.left) <= 0:
			all.erase(id)
			b._emit({ "type": "squall_end", "unit": id, "hex": s.origin })


## One ring: +1 light/dark (propagated), then the push outward.
static func advance(b: BWBattle, s: Dictionary) -> void:
	var t := b.tiles
	var ring := next_ring(b, s)
	var owner := str(s.owner)
	var painted: Array = []
	for h in ring:
		if not _paintable(t, h):
			continue
		var p := t.route_at(h, str(s.element), false, 1, owner)      # D494: lava meets it as fire 1
		match str(p.op):
			"none":
				continue
			"erase":
				t.entries.erase(h)
			_:
				t.entries[h] = p.entry
				(p.entry as Dictionary).erase("seeded")
		painted.append(h)
	b._emit({ "type": "squall_advance", "unit": owner, "hex": s.origin, "element": s.element,
		"ring": ring, "painted": painted, "left": int(s.left) - 1 })
	if not painted.is_empty():
		b._emit({ "type": "paint", "unit": owner, "element": s.element, "hexes": painted, "kind": "lay_on" })
	var by := b._unit(owner)
	var who: Array = []
	for v in b.units:
		if v.alive() and v.pos in ring and maxi(v.size, 1) <= 1 and not BWObelisk.is_objective(v):
			if by != null and BWSets.spares_allies(by, v):   # D282: the Wind set's fields skip allies
				continue
			who.append(v)
	for v in who:
		if b.over or not v.alive():
			continue
		var dir := BWBattle.pulse_heading(s.origin, v.pos, true)
		if dir < 0:
			dir = BWHex.direction_index(s.origin, v.pos)
		BWWind.push(b, v, dir, 1, "push", by, true, true)


static func _paintable(t: BWTiles, h: Vector2i) -> bool:
	if not t.can_hold(h) or t.is_glazed(h) or t.is_pillar(h):
		return false
	if str(t.at(h).get("marker", "")) != "":
		return false                                  # never fires (or washes) a marker
	if t.board.blocker.is_valid() and bool(t.board.blocker.call(h)):
		return false
	return true


# ---------------------------------------------------------------- readability

## A forecast line for a skill that starts a squall.
static func plan_notes(b: BWBattle, _u: BWUnit, p: Dictionary) -> void:
	var el := str(p.get("element", ""))
	var lv := _would_start(b, p.hexes, el, int(p.get("steps", 1)))
	if lv != "":
		p.notes.append("Squall: the %s spreads 1 ring a tick for %d ticks (+1 %s, everyone on the front pushed 1 out)" % [lv, TICKS, lv])


## Which squall element a cast of `el` (`steps`) on `hexes` would start ("" =
## none): wind on light/dark 2+, or light/dark landing on a gale marker at 2+.
static func _would_start(b: BWBattle, hexes: Array, el: String, steps: int = 1) -> String:
	for h in hexes:
		var e := b.tiles.at(h)
		if e.is_empty() or int(e.get("glaze", 0)) > 0:
			continue
		if el == "wind" and str(e.get("marker", "")) == "":
			var s := element_of(int(e.v))
			if s != "":
				return s
		elif el in ["light", "dark"] and str(e.get("marker", "")) == "gale":
			var s2 := element_of(clampi(int(e.v) + (steps if el == "light" else -steps), -3, 3))
			if s2 != "":
				return s2
	return ""


## The tile card's lines for `h` (plain text; the view colours them).
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var all := squalls(b)
	var keys := all.keys()
	keys.sort()
	for id in keys:
		var s: Dictionary = all[id]
		if h in next_ring(b, s):
			var o := b._unit(str(id))
			out.append("Squall: advances next tick (%s's %s): +1 %s here, a unit here is pushed 1 outward; %d tick%s left" % [
				o.name if o != null else "a", s.element, s.element, int(s.left), "" if int(s.left) == 1 else "s"])
		elif h == s.origin:
			out.append("Squall origin (%s): the front is %d ring%s out" % [s.element, int(s.ring) - 1, "" if int(s.ring) == 2 else "s"])
	return out


# ---------------------------------------------------------------- AI

## A cast that may start a squall: simulate it (only then) and score the
## front's three rings: dark under foes (Rot), light under allies (heals,
## beams), foes on the first front ring (the push).
static func ai_skill(b: BWBattle, u: BWUnit, key: String, el: String, h: Vector2i, pv: Dictionary) -> float:
	if not el in ["wind", "light", "dark"] or _would_start(b, pv.get("hexes", []), el, int(pv.get("steps", 1))) == "":
		return 0.0
	var sim := b.simulate(u, { "kind": "skill", "key": key, "element": el, "hex": h })
	if sim.is_empty():
		return 0.0
	var score := 0.0
	for e in sim.events:
		if str(e.type) != "squall" or str(e.unit) != u.id:
			continue
		var r0 := int(e.ring)
		for v in b.units:
			if not v.alive() or BWObelisk.is_objective(v):
				continue
			var d := BWHex.distance(v.pos, e.hex)
			if d < r0 or d > r0 + TICKS - 1:
				continue
			var foe: bool = v.team != u.team
			var w: float = v.pct_base_hp() * 0.03
			if str(e.element) == "dark":
				score += w if foe else 0.0
			else:
				score += w if not foe else 0.0
			if d == r0 and foe:
				score += 1.0
	return score

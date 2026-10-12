class_name BWBrim
extends RefCounted
## D564-D565 (author, 2026-10-11): water and light at 3 react to more of
## themselves, as fire's Overheat (BWOverheat) and ice's Overfreeze do.
## Pure rules: begin / finish wrap BWTiles.apply; after_paint takes the
## battle at the hook marked "D564" in battle.gd.
##
##   RUNNETH OVER  a FRESH water arrival on a hex that was already water 3
##                 (unglazed, no marker, not lava, before the action). The hex
##                 stays water 3; each of its six neighbours gets a PROPAGATED
##                 +1 water through BWTiles._route (empty -> water 1, fire 1
##                 douses, water 1 -> water 2); every foe of the caster on the
##                 hex and its ring is Drenched.
##   GLINTING      a FRESH light arrival on a hex that was already light 3
##                 (same terms). Every foe of the caster on the hex and its
##                 ring is Blinded; the hex dims to light 2 (DIM_TO).
## Ring hexes skip what Overheat's ring skips (glazed, marked, pillars,
## walls, lava). A hex reacts once per action; the ring is propagated, so it
## never reacts again. Both are reactions: Overflow heals for them
## (BWKs3.after_paint). No damage: the status is the reaction.

const RING_WATER := 1
const DIM_TO := 2
const STATUS := { "water": "drenched", "light": "blinded" }
const NAME := { "water": "Runneth Over", "light": "Glinting" }
const EVENT := { "water": "runneth_over", "light": "glinting" }


static func is_target(t: BWTiles, h: Vector2i, element: String) -> bool:
	if not t.can_hold(h) or t.is_glazed(h) or t.is_pillar(h) or t.is_lava(h):
		return false
	if str(t.at(h).get("marker", "")) != "":
		return false
	return t.intensity(h, element) >= BWTiles.AXIS_MAX


# ---------------------------------------------------------------- BWTiles.apply hooks

## Before routing: the hexes this cast sets off (the pre-action board). Sorted.
static func begin(t: BWTiles, hexes: Array, element: String, fresh: bool, opts: Dictionary) -> Array:
	var out: Array = []
	if not fresh or not STATUS.has(element):
		return out
	var all: Array = hexes.duplicate()
	all.append_array((opts.get("ring", {}) as Dictionary).keys())
	for h in all:
		if not h in out and is_target(t, h, element):
			out.append(h)
	out.sort()
	return out


## After the plans are applied: Runneth Over spills +1 water onto each
## centre's ring (the centre stays water 3); Glinting dims the centre to
## light 2. Adds out.brim = [{hex, element, ring, painted, source}].
static func finish(t: BWTiles, centres: Array, element: String, caster: String, out: Dictionary) -> void:
	if centres.is_empty():
		return
	var recs: Array = []
	for c in centres:
		var ring: Array = []
		var painted: Array = []
		for n in t.board.area(c, 1):
			if n == c or not t.board.exists(n):
				continue
			ring.append(n)
			if element != "water" or n in centres or not BWOverheat._paintable(t, n) or t.is_lava(n):
				continue
			var p := t._route(t.at(n), "water", false, RING_WATER, caster)
			match str(p.op):
				"none":
					continue
				"erase":
					t.entries.erase(n)
				_:
					t.entries[n] = p.entry
					(p.entry as Dictionary).erase("seeded")
			painted.append(n)
			if not n in out.changed:
				out.changed.append(n)
		if element == "light":
			var e := t.at(c)
			if not e.is_empty() and int(e.v) > DIM_TO:
				e.v = DIM_TO
				e.erase("seeded")
				if not c in out.changed:
					out.changed.append(c)
		recs.append({ "hex": c, "element": element, "ring": ring, "painted": painted, "source": caster })
	var all: Array = out.get("brim", [])
	all.append_array(recs)
	out["brim"] = all


# ---------------------------------------------------------------- the battle's side

## After a paint's detonations: the events, then the status on every foe of
## the caster on a centre or its ring (once per unit per paint).
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	var recs: Array = r.get("brim", [])
	if recs.is_empty() or b.over or by == null:
		return
	var marked := {}
	for rec in recs:
		var el := str(rec.element)
		var area: Array = (rec.ring as Array).duplicate()
		area.append(rec.hex)
		var hit: Array = []
		for u in b.units:
			if not u.alive() or u.team == by.team or BWObelisk.is_objective(u) or marked.has(u):
				continue
			for f in u.footprint():
				if f in area:
					hit.append(u.id)
					marked[u] = el
					break
		b._emit({ "type": EVENT[el], "hex": rec.hex, "ring": rec.ring, "painted": rec.painted,
			"unit": by.id, "element": el, "hit": hit })
	for u in marked:
		if u.alive() and not b.over:
			b._add_status(u, STATUS[marked[u]], by, 1)


## A forecast line for a water or light action that will set one off.
static func plan_notes(b: BWBattle, _u: BWUnit, p: Dictionary) -> void:
	var el := str(p.get("element", ""))
	if not STATUS.has(el):
		return
	var n := begin(b.tiles, p.hexes, el, true, {}).size()
	if n == 0:
		return
	var what := "%s erupt%s" % ["1 hex" if n == 1 else "%d hexes" % n, "s" if n == 1 else ""]
	if el == "water":
		p.notes.append("Runneth Over: %s, the ring to water +1, foes there Drenched" % what)
	else:
		p.notes.append("Glinting: %s, foes on and around it Blinded; it dims to light 2" % what)


## The tile card's lines for `h`.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if is_target(b.tiles, h, "water"):
		out.append("Runneth Over: fresh water here spills water 1 onto the ring and Drenches the foes on and around it; it stays water 3")
	if is_target(b.tiles, h, "light"):
		out.append("Glinting: fresh light here Blinds the foes on and around it; it dims to light 2")
	return out


## AI: foes a water / light skill would mark, minus nothing (no friendly fire).
static func ai_skill(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	var el := str(pv.get("element", ""))
	if not STATUS.has(el):
		return 0.0
	var score := 0.0
	var seen := {}
	for c in begin(b.tiles, pv.get("hexes", []), el, true, {}):
		for n in b.board.area(c, 1):
			var o := b.unit_at(n)
			if o != null and o.team != u.team and not seen.has(o) and not BWObelisk.is_objective(o):
				seen[o] = true
				score += o.pct_base_hp() * 0.05
	return score

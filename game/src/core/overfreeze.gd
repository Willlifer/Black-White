class_name BWOverfreeze
extends RefCounted
## D312-D313 Ice: Overfreeze (the author, 2026-10-07: "Maybe casting ice on an
## ice water tile turns it into over freeze and shatters it."). Rules as built:
## ELEMENTS.md §17.2. Pure rules: begin / finish wrap BWTiles.apply (like
## BWOverheat), the rest takes the battle at the hooks marked "D312".
##
## A FRESH ice arrival on a hex that was already GLAZED WATER before the action
## (water, glaze > 0, not a pillar, no marker) overfreezes and shatters:
##   * damage: PCT (ice class) to every unit on the hex and its six
##     neighbours, both teams (the caster too). One burst per unit per action,
##     however many centres reach it (an area ice cast over a rink must not
##     stack 7 bursts on one unit). Shattering's potency (whoever glazed the
##     centre) scales it, as it scales thunder's shatter.
##   * the rink: the hex and its ring glaze for GLAZE_CYCLES, as a PROPAGATED
##     arrival: charged unglazed hexes glaze, empty ground gets a thin ice
##     sheet (water 1, glazed); hexes already glazed, marked hexes, pillars and
##     walls are left as they are. Slippery (BWSlides), so units entering slide.
##   * NO pillar (Claude, D313): the centre just shattered, so even empty
##     water 3 stays a flat rink (BWPools.finish skips the centres).
##   * a hex overfreezes once per action; the rink it makes is propagated, so
##     it never overfreezes anything (no chaining).
## Separate from thunder: thunder on glazed water still detonates with the x1.5
## shatter (ELEMENTS.md §3.2). Weather Blizzard glazes directly (not an
## arrival), so it never overfreezes.

const PCT := 12.0
const SHEET_WATER := 1


static func is_target(t: BWTiles, h: Vector2i) -> bool:
	if not t.can_hold(h) or t.is_pillar(h):
		return false
	var e := t.at(h)
	return not e.is_empty() and int(e.h) < 0 and int(e.glaze) > 0 and str(e.get("marker", "")) == ""


# ---------------------------------------------------------------- BWTiles.apply hooks

## Before routing: the hexes this cast overfreezes (fresh ice on glazed
## water, the pre-action board). Sorted.
static func begin(t: BWTiles, hexes: Array, element: String, fresh: bool, opts: Dictionary) -> Array:
	var out: Array = []
	if not fresh or element != "ice":
		return out
	var all: Array = hexes.duplicate()
	all.append_array((opts.get("ring", {}) as Dictionary).keys())
	var act := int(opts.get("ofz_act", -1))
	for h in all:
		if not h in out and is_target(t, h) and (act < 0 or int(t.at(h).get("ofz_act", -2)) != act):
			out.append(h)   # D343: a hex shatters once per ACTION (not per paint)
	out.sort()
	return out


## After the plans and the pools: each centre's radius-1 rink. Adds
## out.overfreeze = [{hex, ring, glazed, pct, source}] and the glazed hexes
## to out.changed.
static func finish(t: BWTiles, centres: Array, caster: String, out: Dictionary) -> void:
	if centres.is_empty():
		return
	var recs: Array = []
	for c in centres:
		var gsrc := str(t.at(c).get("glaze_source", caster))
		var glazed: Array = []
		var ring: Array = []
		for h in t.board.area(c, 1):
			if not t.board.exists(h):
				continue
			if h != c:
				ring.append(h)
			if _sheet(t, h, caster):
				glazed.append(h)
				if not h in out.changed:
					out.changed.append(h)
		var e := t.at(c)
		if not e.is_empty():
			e.glaze = maxi(int(e.glaze), BWTiles.GLAZE_CYCLES)   # the centre is a fresh rink too
			e.permanent = false
			e.erase("seeded")
		recs.append({ "hex": c, "ring": ring, "glazed": glazed, "source": caster,
			"pct": PCT * t.pot(Vector2i.ZERO, "ice", gsrc) })
	out["overfreeze"] = recs


## One rink hex (a propagated glaze). True when it changed.
static func _sheet(t: BWTiles, h: Vector2i, caster: String) -> bool:
	if not t.can_hold(h) or t.is_pillar(h) or t.is_glazed(h):
		return false
	if t.board.blocker.is_valid() and bool(t.board.blocker.call(h)):
		return false
	var e := t.at(h)
	if not e.is_empty() and str(e.get("marker", "")) != "":
		return false
	if e.is_empty():
		e = t._entry(-SHEET_WATER, 0, "", caster, "spread")
		t.entries[h] = e
	e.glaze = BWTiles.GLAZE_CYCLES
	e["glaze_source"] = caster
	e.permanent = false
	e.erase("seeded")
	return true


# ---------------------------------------------------------------- the battle's side

## Before a paint (BWBattle.paint): tag the opts with the action, so
## `begin` skips hexes that already shattered in it (D343).
static func paint_opts(b: BWBattle, o: Dictionary) -> void:
	o["ofz_act"] = b._action_serial


## After a paint: the bursts' events and damage, one burst per unit per
## ACTION (D343: one blow can paint twice, Frostbitten's lay_on and then the
## staff's channel, and the centre is still glazed water for the second).
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	var recs: Array = r.get("overfreeze", [])
	if recs.is_empty() or b.over:
		return
	var hurt := {}
	for rec in recs:
		var ce := b.tiles.at(rec.hex)
		if not ce.is_empty():
			ce["ofz_act"] = b._action_serial
		var hit: Array = []
		for u in b.units:
			if not u.alive() or BWObelisk.is_objective(u):
				continue
			for f in u.footprint():
				if BWHex.distance(f, rec.hex) <= 1:
					hit.append(u.id)
					if not hurt.has(u) and int(u.fx.get("ofz_act", -1)) != b._action_serial:
						hurt[u] = float(rec.pct)
					break
		b._emit({ "type": "overfreeze", "hex": rec.hex, "ring": rec.ring, "glazed": rec.glazed,
			"unit": str(rec.source), "pct": float(rec.pct), "units": hit })
	var src := str(recs[0].source)
	for u in b.units:
		if hurt.has(u) and u.alive() and not b.over:
			u.fx["ofz_act"] = b._action_serial
			b._tile_hurt(u, b._tile_dmg(u, float(hurt[u]), "ice"), "overfreeze", src)


## The skill's forecast note.
static func plan_notes(b: BWBattle, _u: BWUnit, p: Dictionary) -> void:
	if str(p.get("element", "")) != "ice":
		return
	var ring := {}
	for h in p.get("ring", []):
		ring[h] = 1
	var n := begin(b.tiles, p.hexes, "ice", true, { "ring": ring }).size()
	if n > 0:
		p.notes.append("Overfreeze: %s shatter%s, %d%% to every unit on and around, then a rink (no pillar)" % [
			"1 glazed water hex" if n == 1 else "%d glazed water hexes" % n, "s" if n == 1 else "", int(PCT)])


## The basic attack's forecast note (an ice blow on a unit on glazed water).
static func basic_mods(b: BWBattle, dfn: BWUnit, el: String, basic: bool, mods: Array) -> void:
	if basic and el == "ice" and is_target(b.tiles, dfn.pos):
		mods.append({ "stage": "note", "value": 1.0,
			"label": "Overfreeze: the blow's ice shatters this glazed water, %d%% to every unit on and around it" % int(PCT) })


# ---------------------------------------------------------------- AI

## An ice skill over glazed water: simulate it (only then) and score the
## bursts' damage on foes minus allies.
static func ai_skill(b: BWBattle, u: BWUnit, key: String, el: String, h: Vector2i, pv: Dictionary) -> float:
	if el != "ice":
		return 0.0
	var any := false
	for x in (pv.get("hexes", []) as Array) + (pv.get("ring", []) as Array):
		if is_target(b.tiles, x):
			any = true
			break
	if not any:
		return 0.0
	var sim := b.simulate(u, { "kind": "skill", "key": key, "element": el, "hex": h })
	if sim.is_empty():
		return 0.0
	var score := 0.0
	for id in sim.units:
		var rec: Dictionary = sim.units[id]
		for s in rec.sources:
			if str(s.kind) == "overfreeze":
				var v := float(s.amount) + (1000.0 if bool(rec.ko) and not bool(rec.friendly) else 0.0)
				score += -1.5 * float(s.amount) if bool(rec.friendly) else v
	return score


# ---------------------------------------------------------------- readability

static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if is_target(b.tiles, h):
		out.append("Overfreeze: fresh ice here shatters it: %d%% to every unit on it and the six around, then they glaze (a rink, no pillar)" % int(PCT))
	return out

class_name BWKs3Ice
extends RefCounted
## D458b-D459 ice's keystones (Keystones v3, design/ELEMENTS.md). Permafrost
## (the ice + dark duo, D462) reads "glazed" through glazed_for() here too.
##
## Shatterer  when YOUR blow Shatters (its target stands on glaze, or counts as
##            glazed: Permafrost, Frozen), the glaze on the hexes around the
##            target shatters too (not pillars): PCT% (ice, cause "shatter")
##            to anyone standing on them, and the blow itself deals +PER_HEX%
##            for each hex shattered (a forecast line counts them). Once an
##            action (a multi-strike's later blows find the glaze gone).
## Sculptor   your ICE landing on ice (a glazed hex or a stasis mark) raises a
##            PILLAR there (Claude, D459: an ice column; the hex becomes glazed
##            water 3 under it), never on a unit. You may keep PILLAR_MAX (6,
##            not 4: Claude raised the cap); the oldest melts past it. You and
##            your allies can step onto your pillars from next to them (they
##            stay impassable to foes) and stand LIFT levels up: high ground.
##            Your pillars shatter for double (a detonation on one: x2).

const SHATTERER := "shatterer"
const SCULPTOR := "sculptor"


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


## Does `h` count as glazed footing for `u` (the glaze, or Permafrost's dark 3)?
static func glazed_for(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	return BWUnsteady.on_glaze(b.tiles, h) or BWDuo.permafrost(b, u, h)


## Is `att`'s blow on `dfn` a Shatter (glazed, Permafrost, Frozen)?
static func shatters(b: BWBattle, dfn: BWUnit) -> bool:
	return glazed_for(b, dfn, dfn.pos) or BWKsIce.frozen(dfn)


## The glazed (non-pillar) hexes around `dfn`'s hex.
static func glazed_ring(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	for n in b.board.neighbors(h):
		if BWUnsteady.on_glaze(b.tiles, n):
			out.append(n)
	return out


# ---------------------------------------------------------------- Shatterer

## BWBattle._mods: Permafrost's Shatter (+15%) on a foe on the duo holder's
## dark 3; Shatterer's +15% per glazed hex around a shattered target.
static func blow_mods(b: BWBattle, att: BWUnit, dfn: BWUnit, mods: Array) -> void:
	if att == null or dfn == null:
		return
	if not b.tiles.is_glazed(dfn.pos) and BWDuo.permafrost(b, dfn, dfn.pos) and not BWEffects.has(dfn, "rime_armour"):
		mods.append({ "stage": "dmg", "value": 1.0 + BWTiles.SHATTER_HIT_PCT / 100.0,
			"label": "Shatter (Permafrost: dark 3 counts as glazed): +%d%%" % BWTiles.SHATTER_HIT_PCT, "tag": "Shatter" })
	if not ks(att, SHATTERER) or not shatters(b, dfn) or int(att.fx.get("shatterer_act", -1)) == b._action_serial:
		return
	var n := glazed_ring(b, dfn.pos).size()
	if n <= 0:
		return
	var per := BWKeystones.param(SHATTERER, "per_hex", 15)
	mods.append({ "stage": "dmg", "value": 1.0 + per * n / 100.0,
		"label": "Shatterer (%d glazed hex%s around): +%d%%" % [n, "" if n == 1 else "es", int(per * n)], "tag": "Shatterer" })


## BWBattle._after_blow: a landed Shatter by a holder breaks the glaze around.
static func after_blow(b: BWBattle, att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	if att == null or v == null or not ks(att, SHATTERER) or not bool(res.get("hit", false)) or b.over:
		return
	if int(att.fx.get("shatterer_act", -1)) == b._action_serial:
		return
	var h := v.pos
	if not (glazed_for(b, v, h) or BWKsIce.frozen(v)):
		return
	var ring := glazed_ring(b, h)
	if ring.is_empty():
		return
	att.fx["shatterer_act"] = b._action_serial
	for n in ring:
		b.tiles.break_glaze(n)
	var hit: Array = []
	for n in ring:
		var o := b.unit_at(n)
		if o != null and o.alive() and not o in hit and not BWObelisk.is_objective(o):
			hit.append(o)
	b._emit({ "type": "shatterer", "unit": att.id, "hex": h, "hexes": ring, "units": hit.map(func(o): return o.id) })
	var pct := BWKeystones.param(SHATTERER, "pct", 8)
	for o in hit:
		if not b.over and o.alive():
			b._tile_hurt(o, b._tile_dmg(o, pct, "ice"), "shatter", att.id)
	BWKs3Thunder.overflow(b, att, 1)


# ---------------------------------------------------------------- Sculptor

## BWTiles.apply (fresh ice from a Sculptor on hexes that held ice before):
## each becomes a pillar (no unit on it), under the Sculptor's cap.
static func sculpt(t: BWTiles, hexes: Array, caster: String, out: Dictionary, opts: Dictionary) -> void:
	var cap := int(opts.get("pillar_cap", BWPools.PILLAR_MAX))
	hexes.sort()
	var raised: Array = []
	var melted: Array = []
	for h in hexes:
		if t.is_pillar(h) or not t.can_hold(h):
			continue
		if t.occupant.is_valid() and t.occupant.call(h) != null:
			continue
		var mine: Array = []
		for p in t.pillars:
			if str(t.pillars[p].owner) == caster:
				mine.append(p)
		if mine.size() >= cap:
			mine.sort_custom(func(a, c): return int(t.pillars[a].born) < int(t.pillars[c].born))
			BWPools.melt(t, mine[0])
			melted.append(mine[0])
		var e := t.at(h)
		if e.is_empty():
			e = t._entry(-3, 0, "", caster, "cast")
			t.entries[h] = e
		e.h = -3
		e.v = 0
		e.marker = ""
		e.glaze = maxi(int(e.glaze), BWTiles.GLAZE_CYCLES)
		e["glaze_source"] = caster
		e.permanent = false
		e.erase("seeded")
		e.erase("lava")
		t.spine_serial += 1
		t.pillars[h] = { "owner": caster, "ticks": BWPools.PILLAR_TICKS + int(t.get_meta("pillar_plus", 0)),
			"born": t.spine_serial, "sculpt": true }
		raised.append(h)
		if not h in out.changed:
			out.changed.append(h)
	if raised.is_empty():
		return
	var rep: Dictionary = out.get("pools", { "glaze": [], "shock": [], "pillars": [], "melted": [] })
	(rep.pillars as Array).append_array(raised)
	(rep.melted as Array).append_array(melted)
	out["pools"] = rep
	out["sculpted"] = raised


## A Sculptor's pillar at `h` (standing, from a holder's ice)?
static func sculpted(t: BWTiles, h: Vector2i) -> bool:
	return t.is_pillar(h) and bool(t.pillars[h].get("sculpt", false))


## The elevation a Sculptor's pillar adds (BWBoard.lift through BWTiles).
static func lift(t: BWTiles, h: Vector2i) -> int:
	return int(BWKeystones.param(SCULPTOR, "height", 2)) if sculpted(t, h) else 0


## Can `u` stand on the pillar at `h` (its own side's Sculptor's)?
static func climbable(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	if u == null or maxi(u.size, 1) > 1 or not sculpted(b.tiles, h):
		return false
	var o := b._unit(str(b.tiles.pillars[h].owner))
	return o != null and o.team == u.team


## Every pillar `u` may climb ({hex: true}), for BWBoard's step costs.
static func climb_hexes(b: BWBattle, u: BWUnit) -> Dictionary:
	var out := {}
	for h in b.tiles.pillars:
		if climbable(b, u, h):
			out[h] = true
	return out


## BWAI._best_skill: a Sculptor likes raising pillars (a little), a Shatterer
## counts its ring.
static func ai_skill(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	if str(pv.get("element", "")) != "ice" or not ks(u, SCULPTOR):
		return 0.0
	var n := 0
	for h in pv.get("hexes", []):
		if (b.tiles.is_glazed(h) or str(b.tiles.at(h).get("marker", "")) == "stasis") and not b.tiles.is_pillar(h) \
				and b.unit_at(h) == null:
			n += 1
	return 2.0 * mini(n, 2)


static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if sculpted(b.tiles, h):
		var o := b._unit(str(b.tiles.pillars[h].owner))
		out.append("Sculpted pillar (%s): its side can climb on it, %d levels up (high ground); it shatters for double" % [
			o.name if o else "?", lift(b.tiles, h)])
	var u := b._centre_at(h)
	if u != null and u.alive() and ks(u, SHATTERER):
		out.append("%s (Shatterer): its Shatter breaks the glaze around the target too, +%d%% a hex" % [u.name, int(BWKeystones.param(SHATTERER, "per_hex", 15))])
	return out

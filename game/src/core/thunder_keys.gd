class_name BWThunderKeys
extends RefCounted
## Thunder's keystone leftovers after Keystones v3 (D443): Static Blades and
## Blast Rider were REMOVED; Daisy Chain is an item enchantment now (the
## keystone effect key, BWKeystones.has still answers "daisy_chain"); D306
## Self-detonate is kept PROVISIONALLY (D452), granted by Superconductor
## (BWKs3Thunder): free, once per turn, blow the charge or your own fuse
## under you. Superconductor's own-hex rule makes you immune to that blast
## (the old Blast Rider launch is gone with Blast Rider).
##
##   daisy_chain    once per turn, when your fuse detonates, one other fuse of
##                  yours within DAISY_RADIUS detonates in the same action (an
##                  empty fuse: the DETONATE_BASE_PCT 5%). Nothing chains on.

const DAISY_RADIUS := 3


static func ks(u: BWUnit, id: String) -> bool:
	return BWOverheat.ks(u, id)


## The thunder bonus on a blast credited to `src` (as BWBattle.paint's
## detonations: affinity rank, element_damage_pct thunder).
static func det_mult(src: BWUnit) -> float:
	if src == null:
		return 1.0
	var mult := 1.0 + BWFormulas.AFFINITY_DMG_PER_RANK * src.affinity_rank("thunder")
	for e in BWEffects.list(src, "element_damage_pct", "thunder"):
		if int(BWEffects.p(e, "next_same", 0)) != 1:
			mult *= 1.0 + float(BWEffects.p(e, "pct", 0)) / 100.0
	return mult


static func _my_fuse(b: BWBattle, h: Vector2i, u: BWUnit) -> bool:
	var e := b.tiles.at(h)
	return str(e.get("marker", "")) == "fuse" and str(e.get("source", "")) == u.id


## Right after BWTiles.apply in BWBattle.paint: Daisy Chain adds a detonation.
static func after_apply(b: BWBattle, _by: BWUnit, _element: String, r: Dictionary) -> void:
	var dets: Array = r.get("detonations", [])
	if dets.is_empty():
		return
	var extra: Array = []
	for d in dets:
		if d.get("daisy", false) or not d.hex in r.get("marker_fired", []):
			continue
		var owner := b._unit(str(d.source))
		var dz := daisy_from(b, owner, d.hex)
		if dz.is_empty():
			continue
		b.tiles.clear(dz.hex)
		extra.append({ "hex": dz.hex, "pct": float(dz.pct), "source": owner.id, "points": 0, "daisy": true })
	dets.append_array(extra)


# ---------------------------------------------------------------- Self-detonate (D306)

const SELF_DET := "self_detonate"


## D306 / D452: may `u` blow its own hex now? A Superconductor holder, not
## yet this turn, standing on its own fuse or on a charge that thunder
## detonates (anything charged except unglazed water, which electrifies).
static func self_det_ready(b: BWBattle, u: BWUnit) -> bool:
	if u == null or not u.alive() or not ks(u, "superconductor"):
		return false
	if int(u.fx.get("selfdet_turn", -1)) == b._turn_serial:
		return false
	var e := b.tiles.at(u.pos)
	if e.is_empty():
		return false
	if _my_fuse(b, u.pos, u) and not b.tiles.charged(u.pos):
		return true
	if not b.tiles.charged(u.pos):
		return false
	return not (int(e.get("h", 0)) < 0 and int(e.get("glaze", 0)) == 0)


## D306 / D452: blow `u`'s own hex (paint does the rest: Superconductor's
## radius 2 and its own-hex immunity, Daisy Chain). A charge takes thunder
## like any cast; the holder's own empty fuse blows at the 5% base
## (BWBattle.paint's `self_det` option, see inject_self_det). Once per turn.
static func self_detonate(b: BWBattle, u: BWUnit) -> Dictionary:
	if not self_det_ready(b, u):
		return {}
	u.fx["selfdet_turn"] = b._turn_serial
	if _my_fuse(b, u.pos, u) and not b.tiles.charged(u.pos):
		return b.paint([], "thunder", u, 1, false, { "self_det": u.pos })
	return b.paint([u.pos], "thunder", u, 1, false)


## BWBattle.paint, right after BWTiles.apply: an own empty fuse blown by
## Self-detonate becomes a detonation (and a fired marker, for Daisy Chain).
static func inject_self_det(b: BWBattle, by: BWUnit, o: Dictionary, r: Dictionary) -> void:
	if not o.has("self_det") or by == null:
		return
	var h: Vector2i = o.self_det
	if not _my_fuse(b, h, by):
		return
	b.tiles.clear(h)
	r.changed.append(h)
	r.marker_fired.append(h)
	r.detonations.append({ "hex": h, "pct": float(BWTiles.DETONATE_BASE_PCT), "source": by.id, "points": 0 })


## D306 AI: self-detonate when the blast's net ground damage (foes minus
## allies, simulated) is worth it.
static func ai_self_det(b: BWBattle, u: BWUnit) -> bool:
	if not self_det_ready(b, u):
		return false
	var sim := b.simulate(u, { "kind": "skill", "key": SELF_DET, "element": "", "hex": u.pos })
	if sim.is_empty():
		return false
	var net := 0
	for id in sim.units:
		var rec: Dictionary = sim.units[id]
		for s in rec.sources:
			if str(s.kind) in ["blast", "splash"]:
				net += int(s.amount) * (-1 if bool(rec.friendly) else 1)
	return net > 0


# ---------------------------------------------------------------- Daisy Chain

## Once per turn, `owner`'s fuse at `hex` just blew: its nearest other fuse
## within DAISY_RADIUS (ties by hex order) blows too. {hex, pct} or {}.
static func daisy_from(b: BWBattle, owner: BWUnit, hex: Vector2i) -> Dictionary:
	if owner == null or not ks(owner, "daisy_chain") or int(owner.fx.get("daisy_turn", -1)) == b._turn_serial:
		return {}
	var best := BWBattle.NOWHERE
	var bd := 1 << 20
	var keys: Array = b.tiles.entries.keys()
	keys.sort()
	for h in keys:
		if h == hex or not _my_fuse(b, h, owner):
			continue
		var d := BWHex.distance(h, hex)
		if d <= DAISY_RADIUS and d < bd:
			bd = d
			best = h
	if best == BWBattle.NOWHERE:
		return {}
	owner.fx["daisy_turn"] = b._turn_serial
	b._emit({ "type": "daisy", "unit": owner.id, "from": hex, "hex": best })
	return { "hex": best, "pct": float(BWTiles.DETONATE_BASE_PCT) }


# ---------------------------------------------------------------- readability

static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var e := b.tiles.at(h)
	if str(e.get("marker", "")) == "fuse":
		var src := b._unit(str(e.get("source", "")))
		if src != null and ks(src, "daisy_chain"):
			out.append("Daisy Chain (%s): when this blows, %s's nearest fuse within %d blows too (once a turn)" % [src.name, src.name, DAISY_RADIUS])
	return out

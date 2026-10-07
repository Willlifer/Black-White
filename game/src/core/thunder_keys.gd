class_name BWThunderKeys
extends RefCounted
## D290-D291 Thunder's keystones (design/ELEMENTS-v3.md §7 with the author's
## rulings of 2026-10-07; rules as built: ELEMENTS.md §15.5). Thunder's base
## rules are kept as they are (water electrifies: D264). Pure rules; the
## battle calls the hooks marked "D290" in battle.gd.
##
##   static_blades  each basic hit you land arms YOUR fuse on the target's hex
##                  if the hex holds nothing (one Static fuse per foe). A
##                  backstab (the rear three, D96) on a foe standing on your
##                  fuse detonates it as a BLADE BURST: BLADE_PCT to the
##                  occupant, BLADE_SPLASH_PCT to the ring, times your thunder
##                  bonus (affinity rank, Stormcaller's). Once per turn.
##   blast_rider    you take nothing from your own detonations (blast and
##                  splash). A detonation you cause ON YOUR OWN HEX launches
##                  you: move LAUNCH after the action (it replaces Bolt Step's
##                  +2; no stacking). The splash stays the normal half (the
##                  ruling: no full ring). Once per turn; the blast spends the
##                  charge, and you can't re-arm that hex until your next turn.
##   daisy_chain    once per turn, when your fuse detonates, one other fuse of
##                  yours within DAISY_RADIUS detonates in the same action (an
##                  empty fuse: the DETONATE_BASE_PCT 5%). Nothing chains on.

const BLADE_PCT := 12.0
const BLADE_SPLASH_PCT := 6.0
const LAUNCH := 2
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


static func _rear(v: BWUnit, at_hex: Vector2i, from: Vector2i) -> bool:
	if v.facing < 0 or from == at_hex:
		return false
	var d := BWHex.direction_index(at_hex, from)
	return d >= 0 and ((d - v.facing + 6) % 6) in [2, 3, 4]


static func _my_fuse(b: BWBattle, h: Vector2i, u: BWUnit) -> bool:
	var e := b.tiles.at(h)
	return str(e.get("marker", "")) == "fuse" and str(e.get("source", "")) == u.id


# ---------------------------------------------------------------- Static Blades

## After a basic attack (BWBattle.attack): the burst, else the arming.
static func after_basic(b: BWBattle, u: BWUnit, target: BWUnit, first: Dictionary, target_hex: Vector2i) -> void:
	if b.over or not u.alive() or not ks(u, "static_blades") or first.is_empty() or not bool(first.get("hit", false)):
		return
	if BWFormulas.strips_element(target):
		return                                       # D209: a Blank takes no rider
	if _my_fuse(b, target_hex, u) and _rear(target, target_hex, u.pos) and int(u.fx.get("blade_turn", -1)) != b._turn_serial:
		u.fx["blade_turn"] = b._turn_serial
		blade_burst(b, u, target_hex, target)
		return
	if not target.alive() or target.pos != target_hex or not b.tiles.at(target_hex).is_empty():
		return
	if locked(b, u, target_hex):
		return
	var reg: Dictionary = u.fx.get("static_fuses", {})
	if reg.has(target.id) and _my_fuse(b, reg[target.id], u):
		return                                       # one Static fuse per foe
	b.paint([target_hex], "thunder", u, 1, false)
	if not _my_fuse(b, target_hex, u):
		return
	b.tiles.at(target_hex)["static"] = true
	reg[target.id] = target_hex
	u.fx["static_fuses"] = reg
	b._emit({ "type": "static_arm", "unit": u.id, "hex": target_hex, "target": target.id })


## The blade burst on `hex` (your fuse under `target`): the fuse is spent.
static func blade_burst(b: BWBattle, u: BWUnit, hex: Vector2i, target: BWUnit) -> void:
	b.tiles.clear(hex)
	u.fx["detonated"] = true                         # D93 Bolt Step reads it
	b._emit({ "type": "blade_burst", "unit": u.id, "hex": hex, "target": target.id, "pct": BLADE_PCT })
	b._emit({ "type": "detonate", "hex": hex, "pct": BLADE_PCT, "radius": 1, "blade": true })
	var blasts: Array = [[hex, BLADE_PCT, BLADE_SPLASH_PCT]]
	var dz := daisy_from(b, u, hex)
	if not dz.is_empty():
		b.tiles.clear(dz.hex)
		b._emit({ "type": "detonate", "hex": dz.hex, "pct": float(dz.pct), "radius": 1, "daisy": true })
		blasts.append([dz.hex, float(dz.pct), float(dz.pct) / 2.0])
	_blast(b, u, blasts)


## Damage for blasts [[hex, centre %, ring %]] credited to `u`, summed per unit.
static func _blast(b: BWBattle, u: BWUnit, blasts: Array) -> void:
	var mult := det_mult(u)
	var hurt := {}
	for bl in blasts:
		for w in b.units:
			if not w.alive():
				continue
			var d := BWHex.distance(w.pos, bl[0])
			if d > 1:
				continue
			var dmg := b._tile_dmg(w, float(bl[1]) if d == 0 else float(bl[2]), "thunder", mult)
			hurt[w] = int(hurt.get(w, 0)) + dmg
	for w in b.units:
		if hurt.has(w) and w.alive() and not b.over:
			b._tile_hurt(w, int(hurt[w]), "detonation", u.id)


# ---------------------------------------------------------------- Blast Rider

## BWOverheat.filter_hurt: a holder takes nothing from its own detonations.
static func rider_immune(b: BWBattle, u: BWUnit, cause: String, source: String) -> bool:
	if cause != "detonation" or source != u.id or not ks(u, "blast_rider"):
		return false
	b._emit({ "type": "rider_immune", "unit": u.id })
	return true


## Has `u` locked `hex` (its launch hex, until its next turn)?
static func locked(b: BWBattle, u: BWUnit, hex: Vector2i) -> bool:
	var lk: Dictionary = u.fx.get("rider_lock", {})
	return not lk.is_empty() and lk.get("hex") == hex


## BWBattle.paint: thunder from `by` can't re-arm its locked hex (an empty one).
static func filter_rearm(b: BWBattle, by: BWUnit, element: String, hexes: Array) -> Array:
	if element != "thunder" or by == null or not by.fx.has("rider_lock"):
		return hexes
	return hexes.filter(func(h): return not (locked(b, by, h) and b.tiles.at(h).is_empty()))


## Right after BWTiles.apply in BWBattle.paint: Daisy Chain adds a detonation;
## Blast Rider notes a self-detonation (the launch is paid after the action).
static func after_apply(b: BWBattle, by: BWUnit, element: String, r: Dictionary) -> void:
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
	if by == null or not ks(by, "blast_rider") or int(by.fx.get("rider_turn", -1)) == b._turn_serial:
		return
	for d in dets:
		if d.hex == by.pos and (str(d.source) == by.id or by == b.current()):
			by.fx["rider_turn"] = b._turn_serial
			by.fx["launch"] = true
			by.fx["rider_lock"] = { "hex": d.hex }
			b._emit({ "type": "launch", "unit": by.id, "hex": d.hex, "move": LAUNCH })
			return


# ---------------------------------------------------------------- Self-detonate (D306)

const SELF_DET := "self_detonate"


## D306: may `u` blow its own hex now? A Blast Rider holder, its launch not
## spent this turn, standing on its own fuse or on a charge that thunder
## detonates (anything charged except unglazed water, which electrifies).
static func self_det_ready(b: BWBattle, u: BWUnit) -> bool:
	if u == null or not u.alive() or not ks(u, "blast_rider"):
		return false
	if int(u.fx.get("rider_turn", -1)) == b._turn_serial:
		return false
	var e := b.tiles.at(u.pos)
	if e.is_empty():
		return false
	if _my_fuse(b, u.pos, u) and not b.tiles.charged(u.pos):
		return true
	if not b.tiles.charged(u.pos):
		return false
	return not (int(e.get("h", 0)) < 0 and int(e.get("glaze", 0)) == 0)


## D306: blow `u`'s own hex under the Blast Rider rules (paint does the rest:
## immunity, the normal half splash, the launch, the lock, Daisy Chain). A
## charge takes thunder like any cast; the holder's own empty fuse blows at
## the 5% base (BWBattle.paint's `self_det` option, see inject_self_det).
static func self_detonate(b: BWBattle, u: BWUnit) -> Dictionary:
	if not self_det_ready(b, u):
		return {}
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
## allies, simulated) is worth it; the launch then carries it out.
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


## _after_action_move: the launch replaces Bolt Step's +2 (no stacking).
## Returns the new `more`; edits `names`.
static func launch_move(u: BWUnit, more: int, names: Array) -> int:
	if not u.fx.has("launch"):
		return more
	u.fx.erase("launch")
	var bolt := 0
	for e in BWEffects.list(u, "bolt_step"):
		bolt += int(BWEffects.p(e, "hexes", 2))
		names.erase(e.name)
	names.append("Blast Rider")
	return maxi(0, more - bolt) + LAUNCH


## Turn start: the launch lock lifts.
static func turn_start(_b: BWBattle, u: BWUnit) -> void:
	u.fx.erase("rider_lock")


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


# ---------------------------------------------------------------- AI

## A basic from `from` on `f`: the blade burst it would set off (HP points).
static func ai_target(b: BWBattle, u: BWUnit, f: BWUnit, from: Vector2i) -> float:
	if not ks(u, "static_blades") or int(u.fx.get("blade_turn", -1)) == b._turn_serial:
		return 0.0
	if not _my_fuse(b, f.pos, u) or not _rear(f, f.pos, from):
		return 0.0
	return f.max_hp() * BLADE_PCT / 100.0 * det_mult(u)


## Blast Rider's dive: a thunder skill whose shape covers the holder's own
## charged hex is scored by simulating it (its ground damage on foes, minus
## allies, plus the launch). 0 for anything else.
static func ai_skill(b: BWBattle, u: BWUnit, key: String, el: String, h: Vector2i, pv: Dictionary) -> float:
	if el != "thunder" or not ks(u, "blast_rider") or int(u.fx.get("rider_turn", -1)) == b._turn_serial:
		return 0.0
	var mine := u.pos
	if not mine in pv.get("hexes", []) and pv.get("dest", mine) == mine:
		return 0.0
	if b.tiles.at(pv.get("dest", mine)).is_empty() and b.tiles.at(mine).is_empty():
		return 0.0
	var sim := b.simulate(u, { "kind": "skill", "key": key, "element": el, "hex": h })
	if sim.is_empty():
		return 0.0
	var score := 0.0
	for id in sim.units:
		var rec: Dictionary = sim.units[id]
		var ground := 0
		for s in rec.sources:
			if str(s.kind) in ["blast", "splash"]:
				ground += int(s.amount)
		score += ground if not bool(rec.friendly) else -ground
	for e in sim.events:
		if str(e.type) == "launch":
			score += 3.0
	return score


# ---------------------------------------------------------------- readability

static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var e := b.tiles.at(h)
	if str(e.get("marker", "")) == "fuse":
		var src := b._unit(str(e.get("source", "")))
		if src != null and ks(src, "static_blades"):
			out.append("%s fuse (%s's): a backstab by %s on a foe here bursts %d%% (+%d%% splash)" % [
				"Static" if bool(e.get("static", false)) else "Fuse", src.name, src.name, int(BLADE_PCT), int(BLADE_SPLASH_PCT)])
		if src != null and ks(src, "daisy_chain"):
			out.append("Daisy Chain (%s): when this blows, %s's nearest fuse within %d blows too (once a turn)" % [src.name, src.name, DAISY_RADIUS])
	var u := b._centre_at(h)
	if u != null and u.alive() and ks(u, "blast_rider"):
		out.append("%s (Blast Rider): immune to its own blasts; a blast on its own hex launches it (move %d)" % [u.name, LAUNCH])
	return out

class_name BWOverheat
extends RefCounted
## D285-D286 Fire: Overheat and the fire keystones (design/ELEMENTS-v3.md §5,
## "Fire: approved as drafted"; rules as built: ELEMENTS.md §15). Pure rules:
## begin / finish wrap BWTiles.apply (like BWPools), the rest takes the battle
## at the hooks marked "D285" in battle.gd.
##
## OVERHEAT: a FRESH fire arrival on a hex that was already fire 3 (unglazed,
## before the action) erupts:
##   * ring: each of the six neighbours gets a PROPAGATED +2 fire through
##     BWTiles._route (water 3 -> water 1, fire 1 -> fire 3). Glazed hexes,
##     marked hexes, pillars, walls and hexes erupting in the same action are
##     skipped. Propagated fire never erupts and never ignites grass.
##   * damage: RING_PCT to every unit on the ring, both teams (fire class),
##     summed per unit over the action's eruptions (one event per unit).
##   * centre: vents to fire 2 (VENT_TO), so a second eruption needs a recast.
##   * a hex erupts once per action.
## Item enchantments since Keystones v3 (D443; BWKeystones.has still answers
## the old ids; Trailblazer was REMOVED):
##   conflagration  your eruptions chain once: a ring hex your eruption RAISED
##                  to fire 3 erupts too, depth DEPTH_MAX at most.
##   phoenix_heart  your own fire never hurts you; starting your turn on fire 3
##                  heals what it would burn (PHOENIX_HEAL_PCT); once a battle,
##                  a KO (blow or ground) while you stand on fire leaves you at
##                  1 HP and Overheats your hex.
## Keystones v3 riders (opts from BWKs3.paint_opts): Lava Walker erupts at its
## own cap (fire_max 5, not 3) and its ring never cools lava; Island Maker and
## Superconductor widen the ring (overheat_radius 2).

const RING_STEPS := 2
const RING_PCT := 6.0
const VENT_TO := 2
const DEPTH_MAX := 2
const PHOENIX_HEAL_PCT := 12.0
const FIRE_CAUSES := ["fire", "fire_cross", "overheat"]


## Keystone check (C1's BWKeystones), plus the dev / review flag fx["ks:<id>"].
static func ks(u: BWUnit, id: String) -> bool:
	return u != null and (BWKeystones.has(u, id) or bool(u.fx.get("ks:" + id, false)))


# ---------------------------------------------------------------- BWTiles.apply hooks

## Before routing: the hexes this cast will erupt (fresh fire on unglazed
## fire 3, the pre-action board).
static func begin(t: BWTiles, hexes: Array, element: String, fresh: bool, opts: Dictionary) -> Array:
	var out: Array = []
	if not fresh or element != "fire":
		return out
	var cap := int(opts.get("fire_max", BWTiles.AXIS_MAX))   # D447: a Lava Walker erupts at 5
	var all: Array = hexes.duplicate()
	all.append_array((opts.get("ring", {}) as Dictionary).keys())
	for h in all:
		if h in out or not t.can_hold(h) or t.is_glazed(h) or str(t.at(h).get("marker", "")) != "":
			continue
		if t.intensity(h, "fire") >= cap:
			out.append(h)
	out.sort()
	return out


## After the plans are applied: each centre erupts (its ring gets +2 fire,
## the centre vents to fire 2). Conflagration (opts.conflagration) chains
## once. Adds out.overheat = [{hex, ring, painted, depth, source}] and the
## painted ring hexes to out.changed.
static func finish(t: BWTiles, centres: Array, caster: String, out: Dictionary, opts: Dictionary = {}) -> void:
	if centres.is_empty():
		return
	var conflag := bool(opts.get("conflagration", false))
	var reach := maxi(1, int(opts.get("overheat_radius", 1)))   # D448 Island Maker / D452 Superconductor: radius 2
	var erupted := {}
	var planned := {}
	for c in centres:
		planned[c] = true
	var queue: Array = []
	for c in centres:
		queue.append([c, 1])
	var recs: Array = []
	var i := 0
	while i < queue.size():
		var c: Vector2i = queue[i][0]
		var depth: int = queue[i][1]
		i += 1
		if erupted.has(c):
			continue
		erupted[c] = true
		var ring: Array = []
		var painted: Array = []
		for n in t.board.area(c, reach):
			if n == c or not t.board.exists(n):
				continue
			ring.append(n)
			if not _paintable(t, n) or erupted.has(n) or planned.has(n) or not t._lava_ok(n, "fire", caster):
				continue
			var before := t.intensity(n, "fire")
			var p := t._route(t.at(n), "fire", false, RING_STEPS, caster, opts)
			match str(p.op):
				"none":
					continue
				"erase":
					t.entries.erase(n)
				_:
					t.entries[n] = p.entry
					(p.entry as Dictionary).erase("seeded")
			if t.shock.has(n):
				BWPools._unshock(t, n)                 # fire on an electrified hex clears it there
			if opts.has("wild") and t.entries.has(n) and t.intensity(n, "fire") >= int(opts.wild) and int(t.entries[n].glaze) == 0:
				t.entries[n]["wild"] = true            # D307 Wildfire: your eruption ring is wild too
			painted.append(n)
			if not n in out.changed:
				out.changed.append(n)
			if conflag and depth < DEPTH_MAX and before < 3 and t.intensity(n, "fire") >= 3 and int(opts.get("fire_max", 3)) <= 3:
				planned[n] = true
				queue.append([n, depth + 1])
		_vent(t, c, caster)
		recs.append({ "hex": c, "ring": ring, "painted": painted, "depth": depth, "source": caster })
	BWPools.prune(t)
	out["overheat"] = recs


static func _paintable(t: BWTiles, h: Vector2i) -> bool:
	if not t.can_hold(h) or t.is_glazed(h) or t.is_pillar(h):
		return false
	if str(t.at(h).get("marker", "")) != "":
		return false
	if t.board.blocker.is_valid() and bool(t.board.blocker.call(h)):
		return false                                # a Wind Wall (or anything the board blocks)
	return true


## The centre vents to fire 2 (light/dark kept).
static func _vent(t: BWTiles, c: Vector2i, caster: String) -> void:
	var e := t.at(c)
	if e.is_empty():
		return
	e.h = VENT_TO
	e.timer = BWTiles.STEP_CYCLES
	e.permanent = false
	e.erase("seeded")
	if str(e.get("source", "")) == "":
		e.source = caster


# ---------------------------------------------------------------- the battle's side

## BWBattle.paint: the caster's options (Conflagration).
static func paint_opts(by: BWUnit, element: String, o: Dictionary) -> void:
	if element == "fire" and ks(by, "conflagration"):
		o["conflagration"] = true
	BWKs3.paint_opts(by, element, o)            # D447-D452: lava, Island Maker / Superconductor radius


## After a paint's detonations: the eruptions' events and ring damage, summed
## per unit. Phoenix Heart's holder takes none from its own.
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	var recs: Array = r.get("overheat", [])
	if recs.is_empty() or b.over:
		return
	var hurt := {}
	for rec in recs:
		b._emit({ "type": "overheat", "hex": rec.hex, "ring": rec.ring, "painted": rec.painted,
			"depth": int(rec.depth), "unit": str(rec.source), "pct": RING_PCT })
		for u in b.units:
			if not u.alive() or BWObelisk.is_objective(u):
				continue
			var on := false
			for f in u.footprint():
				if f in rec.ring:
					on = true
			if on:
				hurt[u] = float(hurt.get(u, 0.0)) + RING_PCT
	var src := str(recs[0].source)
	for u in b.units:
		if hurt.has(u) and u.alive() and not b.over:
			b._tile_hurt(u, b._tile_dmg(u, float(hurt[u]), "fire"), "overheat", src)


## A forecast line for a fire action that will erupt (the skill's plan).
static func plan_notes(b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	if str(p.get("element", "")) != "fire":
		return
	var o := {}
	BWKs3.paint_opts(u, "fire", o)
	var n := begin(b.tiles, p.hexes, "fire", true, o).size()
	if n > 0:
		p.notes.append("Overheat: %s erupt%s, the ring%s to fire +2, %d%% to every unit on it" % [
			"1 hex" if n == 1 else "%d hexes" % n, "s" if n == 1 else "",
			" (radius %d)" % int(o.overheat_radius) if int(o.get("overheat_radius", 1)) > 1 else "", int(RING_PCT)])
		if ks(u, "conflagration"):
			p.notes.append("Conflagration: a ring hex raised to fire 3 erupts too (once)")


## The basic attack's forecast note (an imbued or staff fire blow on fire 3).
static func basic_mods(b: BWBattle, att: BWUnit, dfn: BWUnit, el: String, basic: bool, mods: Array) -> void:
	if basic and el == "fire" and b.tiles.intensity(dfn.pos, "fire") >= 3 and not b.tiles.is_glazed(dfn.pos):
		mods.append({ "stage": "note", "value": 1.0,
			"label": "Overheat: the blow's fire erupts here, the ring to fire +2, %d%% to every unit on it" % int(RING_PCT) })


## D443: Trailblazer is gone; nothing in fire skips the crossing burn here
## (Lava Walker's aura is BWKs3Fire.fire_immune).
static func no_cross(_u: BWUnit) -> bool:
	return false


## Every ground hurt passes here (BWBattle._tile_hurt), before it lands:
## the Keystones v3 filters (Lava Walker's aura, Superconductor's own-hex
## immunity, Island Maker's 75% less), Ward of Light absorbs, Phoenix Heart
## ignores its own fire, turns a fire 3 turn-start burn into a heal and holds
## a KO on fire at 1 HP (the eruption follows in after_hurt).
static func filter_hurt(b: BWBattle, u: BWUnit, amount: int, cause: String, source: String) -> int:
	if amount <= 0 or u == null:
		return amount
	amount = BWKs3.filter_hurt(b, u, amount, cause, source)
	if amount <= 0:
		return 0
	if ks(u, "phoenix_heart"):
		if cause == "fire" and b.tiles.intensity(u.pos, "fire") >= 3:
			b._emit({ "type": "phoenix", "unit": u.id, "what": "heal" })
			b._heal(u, PHOENIX_HEAL_PCT, "phoenix")
			return 0
		if cause in FIRE_CAUSES and source == u.id:
			b._emit({ "type": "phoenix", "unit": u.id, "what": "own_fire" })
			return 0
	amount = BWBeams.ward_absorb(b, u, amount)
	return hold_ko(b, u, amount)


## A blow (BWEnchant.land): the Ward of Light, then Phoenix Heart's KO hold.
static func hold_blow(b: BWBattle, v: BWUnit, dmg: int) -> int:
	dmg = BWBeams.ward_absorb(b, v, dmg)
	return hold_ko(b, v, dmg)


## Phoenix Heart, once a battle: a KO while standing on fire leaves 1 HP and
## the hex Overheats (after the damage lands: after_hurt / after_blow).
static func hold_ko(b: BWBattle, v: BWUnit, dmg: int) -> int:
	if dmg < v.hp or v.hp <= 1 or not ks(v, "phoenix_heart") or v.fx.has("phoenix_used"):
		return dmg
	if b.tiles.intensity(v.pos, "fire") <= 0:
		return dmg
	v.fx["phoenix_used"] = true
	v.fx["phoenix_pending"] = true
	return v.hp - 1


## After a hurt or a blow on `v`: a pending Phoenix Overheat goes off.
static func after_hurt(b: BWBattle, v: BWUnit) -> void:
	if v == null or not v.fx.has("phoenix_pending"):
		return
	v.fx.erase("phoenix_pending")
	if not v.alive() or b.over:
		return
	b._emit({ "type": "phoenix", "unit": v.id, "what": "rise", "hex": v.pos })
	erupt_at(b, v.pos, v)


## Overheat `hex` now, as `owner`'s eruption (Phoenix Heart).
static func erupt_at(b: BWBattle, hex: Vector2i, owner: BWUnit) -> void:
	var out := { "changed": [] }
	finish(b.tiles, [hex], owner.id, out, { "conflagration": ks(owner, "conflagration") })
	var changed: Array = out.changed
	b._emit({ "type": "paint", "unit": owner.id, "element": "fire", "hexes": changed, "kind": "lay_on" })
	after_paint(b, owner, out)


# ---------------------------------------------------------------- AI

## An Overheat a fire skill sets off: ring damage on foes minus allies (HP
## points), plus a little for hexes it brings to fire 3 beside a foe (setups).
static func ai_skill(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	if str(pv.get("element", "")) != "fire":
		return 0.0
	var score := 0.0
	var po := {}
	BWKs3.paint_opts(u, "fire", po)
	for c in begin(b.tiles, pv.hexes, "fire", true, po):
		for n in b.board.area(c, maxi(1, int(po.get("overheat_radius", 1)))):
			if n == c:
				continue
			var o := b.unit_at(n)
			if o == null or BWObelisk.is_objective(o):
				continue
			var v := o.max_hp() * RING_PCT / 100.0
			if o == u and ks(u, "phoenix_heart"):
				v = 0.0
			score += v if o.team != u.team else -v
	for h in pv.hexes:
		if b.tiles.intensity(h, "fire") == 2:
			for n in b.board.neighbors(h):
				var o2 := b.unit_at(n)
				if o2 != null and o2.team != u.team:
					score += 0.5
					break
	return score


# ---------------------------------------------------------------- readability

## The tile card's lines for `h`.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if b.tiles.intensity(h, "fire") >= 3 and not b.tiles.is_glazed(h) and not b.tiles.is_lava(h):
		out.append("Overheat: fresh fire here erupts; the ring gets fire +2 and every unit on it takes %d%%; this hex vents to fire 2" % int(RING_PCT))
	var u := b._centre_at(h)
	if u != null and u.alive():
		if ks(u, "phoenix_heart"):
			out.append("%s (Phoenix Heart): its own fire never burns it; fire 3 heals it %d%%%s" % [u.name, int(PHOENIX_HEAL_PCT),
				"" if u.fx.has("phoenix_used") else "; a KO on fire leaves it at 1 HP and Overheats the hex (once)"])
	return out

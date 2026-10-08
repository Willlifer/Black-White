class_name BWBeams
extends RefCounted
## D287-D289 Light: beams, Empowered, dawn and the light keystones
## (design/ELEMENTS-v3.md §3 with the author's rulings of 2026-10-07: Dawn
## Relay REMOVED, the third keystone is Magnify; rules as built: ELEMENTS.md
## §16). Pure rules; the battle calls the hooks marked "D287" in battle.gd.
##
## BEAM: two allies, each on light 1+, on one straight hex line, 2..MAX_GAP
## hexes apart, nothing blocking between (rock, a pillar, a wall). Every hex
## between is a beam hex. One beam per pair; a unit is the end of at most
## MAX_ENDS beams (shortest pairs first, then setup order). Beams are read
## from the board whenever asked: they form and break as units move.
## At the tick (v3 step 3, after the vortex pull, before decay):
##   * foes on beam hexes take BASE_PCT + PER_LIGHT_PCT x the lower end's
##     light (6/8/10%, light class), once per tick (the strongest beam);
##   * allies on beam hexes and both ends become EMPOWERED: +EMPOWER_PCT% on
##     their next attack (a basic or a damaging skill), until the end of their
##     next turn. Empowered once (the stronger one stands).
## DAWN: an ally starting its turn on light 2+ takes 1 off its longest skill
## cooldown, once per turn.
## Item enchantments since Keystones v3 (D443; Prism was REMOVED, so beams
## never bend; BWKeystones.has still answers the old ids):
##   overflow  ("{item} of the Ward of Light", renamed: thunder has the new
##             Overflow keystone) light healing a holder lays (its light tiles, its Prism heals)
##             beyond max HP becomes a Ward of Light: a shield of the excess,
##             up to WARD_PCT of max HP, until hit or WARD_CYCLES cycles. A beam
##             the holder is part of Empowers +OVERFLOW_EMPOWER_PCT%.
##   magnify   (the ruling's enabler) an ALLY standing on the holder's light
##             casts magnified, once per turn: an area skill of radius 1-2 gets
##             +1 radius (the new ring is hit and painted: radius 2 becomes 3,
##             never more); any other element skill gets +1 charge step on its
##             paint (the axis caps at 3). The forecast names it.

const MAX_GAP := 4
const MIN_GAP := 2
const MAX_ENDS := 2
const BASE_PCT := 4.0
const PER_LIGHT_PCT := 2.0
const EMPOWER_PCT := 15
const OVERFLOW_EMPOWER_PCT := 25
const WARD_PCT := 15.0
const WARD_CYCLES := 2
const DAWN_LIGHT := 2
const MAGNIFY_MAX_RADIUS := 2      # shapes up to radius 2 widen (to 3 at most)


static func ks(u: BWUnit, id: String) -> bool:
	return BWOverheat.ks(u, id)


# ---------------------------------------------------------------- forming

static func lit(b: BWBattle, u: BWUnit) -> int:
	if u == null or not u.alive() or BWObelisk.is_objective(u) or u.size > 1:
		return 0
	return b.tiles.intensity(u.pos, "light")


## The hexes strictly between a and c when they are on one straight, clear
## line MIN_GAP..MAX_GAP apart; null otherwise.
static func span(b: BWBattle, a: Vector2i, c: Vector2i) -> Variant:
	var d := BWHex.distance(a, c)
	if d < MIN_GAP or d > MAX_GAP:
		return null
	var ca := BWHex.to_cube(a)
	var cc := BWHex.to_cube(c)
	if ca.x != cc.x and ca.y != cc.y and ca.z != cc.z:
		return null
	var ln := BWHex.line(a, c)
	var out: Array = []
	for i in range(1, ln.size() - 1):
		var h: Vector2i = ln[i]
		if not b.board.exists(h) or b.board.terrain(h) == BWBoard.JAGGED:
			return null
		if b.board.blocker.is_valid() and bool(b.board.blocker.call(h)):
			return null
		out.append(h)
	return out


## Every beam on the board now: [{team, ends: [id, id], bend: id | "",
## hexes (beam hexes), points ([end, (bend,) end] hexes), light, prism,
## overflow, empower}], deterministic.
static func beams(b: BWBattle) -> Array:
	var out: Array = []
	for team in ["player", "enemy"]:
		out.append_array(_team_beams(b, team))
	return out


static func _team_beams(b: BWBattle, team: String) -> Array:
	var cands: Array = []
	for u in b.units:
		if u.team == team and lit(b, u) >= 1:
			cands.append(u)
	var out: Array = []
	if cands.size() < 2:
		return out
	var pairs: Array = []
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var sp = span(b, cands[i].pos, cands[j].pos)
			if sp != null:
				pairs.append([BWHex.distance(cands[i].pos, cands[j].pos), i, j, sp])
	pairs.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]))))
	var ends := {}
	var paired := {}
	for p in pairs:
		var a: BWUnit = cands[p[1]]
		var c: BWUnit = cands[p[2]]
		if int(ends.get(a.id, 0)) >= MAX_ENDS or int(ends.get(c.id, 0)) >= MAX_ENDS:
			continue
		ends[a.id] = int(ends.get(a.id, 0)) + 1
		ends[c.id] = int(ends.get(c.id, 0)) + 1
		paired[_pk(a, c)] = true
		out.append(_beam(b, team, [a, c], null, p[3]))
	return out


static func _pk(a: BWUnit, c: BWUnit) -> String:
	return "%s|%s" % [a.id, c.id] if a.id < c.id else "%s|%s" % [c.id, a.id]


static func _beam(b: BWBattle, team: String, ends: Array, bend: BWUnit, hexes: Array) -> Dictionary:
	var who: Array = ends.duplicate()
	if bend != null:
		who.append(bend)
	var light := 3
	for w in who:
		light = mini(light, lit(b, w))
	var prism := false                              # D443: Prism is gone
	var overflow := who.any(func(w): return ks(w, "overflow"))
	var pts: Array = [ends[0].pos]
	if bend != null:
		pts.append(bend.pos)
	pts.append(ends[1].pos)
	return { "team": team, "ends": [ends[0].id, ends[1].id], "bend": bend.id if bend != null else "",
		"hexes": hexes, "points": pts, "light": light, "prism": prism, "overflow": overflow,
		"pct": BASE_PCT + PER_LIGHT_PCT * light, "empower": (OVERFLOW_EMPOWER_PCT if overflow else EMPOWER_PCT)
			+ (roundi(BWSets.empower_plus(ends[0])) if BWSets.empower_plus(ends[0]) > 0 else roundi(BWSets.empower_plus(ends[1]))) }   # D282: the Light set's +5%


## D307 Sunpath: is `u` on a beam `holder` is an end of (on its hexes, the
## bend, or the other end)? Read live, like every beam.
static func on_beam_of(b: BWBattle, holder: BWUnit, u: BWUnit) -> bool:
	for bm in _team_beams(b, holder.team):
		if not holder.id in bm.ends:
			continue
		if u.id in bm.ends or str(bm.bend) == u.id or u.pos in bm.hexes:
			return true
	return false


## Hex -> the strongest beam over it, for one team's beams ("" = all teams).
static func beam_hexes(b: BWBattle, team: String = "") -> Dictionary:
	var out := {}
	for bm in beams(b):
		if team != "" and bm.team != team:
			continue
		for h in bm.hexes:
			if not out.has(h) or float(bm.pct) > float(out[h].pct):
				out[h] = bm
	return out


# ---------------------------------------------------------------- the tick (v3 step 3)

## Beams resolve: foes on beam hexes are hurt, allies on them (and the ends)
## Empowered, Prism heals. Wards of Light past their time fade.
static func tick(b: BWBattle) -> void:
	if b.over:
		return
	for u in b.units:
		var w: Dictionary = u.fx.get("light_ward", {})
		if not w.is_empty() and b.cycle >= int(w.get("until", 0)):
			u.fx.erase("light_ward")
			b._emit({ "type": "light_ward_end", "unit": u.id })
	var all := beams(b)
	if all.is_empty():
		return
	var hit := {}            # unit -> [pct, source id]
	var emp := {}            # unit -> pct
	for bm in all:
		var on: Array = []
		for u in b.units:
			if u.alive() and not BWObelisk.is_objective(u) and u.pos in bm.hexes:
				on.append(u)
		for u in on:
			if u.team != bm.team:
				if not hit.has(u) or float(bm.pct) > float(hit[u][0]):
					hit[u] = [float(bm.pct), str(bm.ends[0])]
		var allies: Array = on.filter(func(x): return x.team == bm.team)
		for id in bm.ends + ([bm.bend] if str(bm.bend) != "" else []):
			var x := b._unit(str(id))
			if x != null and not x in allies:
				allies.append(x)
		for x in allies:
			emp[x] = maxi(int(emp.get(x, 0)), int(bm.empower))
	b._emit({ "type": "light_beams", "beams": all.map(func(x): return { "team": x.team, "points": x.points,
		"hexes": x.hexes, "pct": x.pct, "ends": x.ends, "bend": x.bend }),
		"hit": hit.keys().map(func(u): return u.id), "empowered": emp.keys().map(func(u): return u.id) })
	for u in b.units:
		if hit.has(u) and u.alive() and not b.over:
			b._tile_hurt(u, b._tile_dmg(u, float(hit[u][0]), "light"), "light_beam", str(hit[u][1]))
	for u in b.units:
		if emp.has(u) and u.alive() and not b.over:
			empower(b, u, int(emp[u]))


# ---------------------------------------------------------------- Empowered

static func empowered(u: BWUnit) -> int:
	return int((u.fx.get("empowered", {}) as Dictionary).get("pct", 0)) if u != null else 0


## Empower `u` (the stronger of two stands; a unit is Empowered once).
static func empower(b: BWBattle, u: BWUnit, pct: int) -> void:
	if empowered(u) >= pct:
		return
	if BWKs3Dark.buff_blocked(b, u, "Empowered"):
		return                                       # D450 Hopekiller: no buffs on its dark
	u.fx["empowered"] = { "pct": pct }
	b._emit({ "type": "empowered", "unit": u.id, "pct": pct })


## The blow's forecast term (BWBattle._mods): only on its own turn.
static func mods(b: BWBattle, att: BWUnit, mods_out: Array) -> void:
	var p := empowered(att)
	if p > 0 and att == b.current():
		mods_out.append({ "stage": "dmg", "value": 1.0 + p / 100.0, "label": "Empowered: +%d%%" % p, "tag": "Empowered" })


## After its own attacking action: Empowered is spent.
static func after_action(b: BWBattle, u: BWUnit, attacked: bool) -> void:
	if attacked and empowered(u) > 0 and u == b.current():
		u.fx.erase("empowered")
		b._emit({ "type": "empowered_end", "unit": u.id, "why": "spent" })


## The end of its turn: Empowered ends (granted at the tick, it lasts through
## the unit's next turn).
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if empowered(u) > 0:
		u.fx.erase("empowered")
		b._emit({ "type": "empowered_end", "unit": u.id, "why": "faded" })


# ---------------------------------------------------------------- dawn, healing, Overflow

## Turn start (after the light heal): Dawn takes 1 off the longest cooldown.
static func turn_start(b: BWBattle, u: BWUnit) -> void:
	if not u.alive() or b.over or BWObelisk.is_objective(u):
		return
	if b.tiles.intensity(u.pos, "light") < DAWN_LIGHT:
		return
	var best := ""
	var keys: Array = u.cooldowns.keys()
	keys.sort()
	for k in keys:
		if int(u.cooldowns[k]) > 0 and (best == "" or int(u.cooldowns[k]) > int(u.cooldowns[best])):
			best = str(k)
	if best == "":
		return
	u.cooldowns[best] = int(u.cooldowns[best]) - 1
	b._emit({ "type": "dawn", "unit": u.id, "skill": best, "cd": int(u.cooldowns[best]) })


## A light heal on `u` laid by `source` (a tile): Ward of Light (the old
## light Overflow) turns the excess into a shield.
static func light_heal(b: BWBattle, u: BWUnit, pct: float, source: String) -> void:
	if pct <= 0.0 or not u.alive():
		return
	var room := u.max_hp() - u.hp
	var fade := BWFormulas.fatigue_heal_mult(b.cycle)   # D474: the overheal shield wanes with the heal
	var amt := maxi(1, roundi(u.max_hp() * pct * fade / 100.0)) if fade > 0.0 else 0
	b._heal(u, pct, "light")
	var src := b._unit(source)
	if src == null or src.team != u.team or not ks(src, "overflow"):
		return
	var excess := amt - room
	if excess <= 0 or not u.alive():
		return
	var cap := roundi(u.max_hp() * WARD_PCT / 100.0)
	var cur := int((u.fx.get("light_ward", {}) as Dictionary).get("hp", 0))
	var hp := mini(cap, cur + excess)
	if hp <= cur or BWKs3Dark.buff_blocked(b, u, "Ward of Light"):
		return
	u.fx["light_ward"] = { "hp": hp, "until": b.cycle + WARD_CYCLES, "by": src.id }
	b._emit({ "type": "light_ward", "unit": u.id, "hp": hp, "by": src.id })


## Damage about to land on `u`: a Ward of Light absorbs what it can, then
## breaks (it lasts until hit).
static func ward_absorb(b: BWBattle, u: BWUnit, dmg: int) -> int:
	dmg = BWKit2.barrier_absorb(b, u, dmg)        # D429: Consume's barrier soaks first
	var w: Dictionary = u.fx.get("light_ward", {})
	if dmg <= 0 or w.is_empty():
		return dmg
	var took := mini(dmg, int(w.hp))
	u.fx.erase("light_ward")
	b._emit({ "type": "light_ward_break", "unit": u.id, "absorbed": took })
	return dmg - took


# ---------------------------------------------------------------- Magnify

## The ally whose Magnify lights `u`'s hex (not `u` itself), else null.
static func magnifier(b: BWBattle, u: BWUnit) -> BWUnit:
	if u == null or b.tiles.intensity(u.pos, "light") <= 0:
		return null
	var src := b._unit(str(b.tiles.at(u.pos).get("source", "")))
	if src == null or src == u or src.team != u.team or not ks(src, "magnify"):
		return null
	return src


static func magnify_ready(b: BWBattle, u: BWUnit) -> bool:
	return int(u.fx.get("magnify_turn", -1)) != b._turn_serial


## BWBattle._plan: widen an area skill by a ring, else +1 step on its paint.
static func magnify(b: BWBattle, u: BWUnit, d: BWSkillDef, p: Dictionary) -> void:
	if p.has("magnify") or not magnify_ready(b, u):
		return
	var src := magnifier(b, u)
	if src == null:
		return
	var el := str(p.get("element", ""))
	var r := _radius(p.hexes, [u.pos, p.get("dest", u.pos)])
	if bool(d.data.get("aoe", false)) and d.data.has("radius") and r >= 1 and r <= MAGNIFY_MAX_RADIUS:
		var mine := u.footprint(p.get("dest", u.pos))
		var ring: Array = []
		for h in BWHex.fringe(p.hexes, 1):
			if b.board.exists(h) and not h in p.hexes and not h in mine:
				ring.append(h)
		if ring.is_empty():
			return
		(p.hexes as Array).append_array(ring)
		for o in b._foes_on(u, ring):
			if not o in p.victims:
				p.victims.append(o)
		p["magnify"] = { "by": src.id, "kind": "radius", "ring": ring, "radius": r + 1 }
		p.notes.append("Magnify (%s's light): +1 radius, %d → %d" % [src.name, r, r + 1])
	elif el != "":
		p.steps = int(p.steps) + 1
		p["magnify"] = { "by": src.id, "kind": "step" }
		p.notes.append("Magnify (%s's light): +1 charge step (caps at 3)" % src.name)


## The shape's radius about its best centre (the shape's hexes, the caster).
static func _radius(hexes: Array, extra: Array) -> int:
	if hexes.is_empty():
		return 0
	var best := 1 << 20
	for c in hexes + extra:
		var m := 0
		for h in hexes:
			m = maxi(m, BWHex.distance(c, h))
		best = mini(best, m)
	return best


## BWBattle.use_skill: the plan was magnified: spend it for this turn.
static func spend_magnify(b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	if not p.has("magnify"):
		return
	u.fx["magnify_turn"] = b._turn_serial
	var m: Dictionary = p.magnify
	b._emit({ "type": "magnify", "unit": u.id, "by": str(m.by), "kind": str(m.kind), "ring": m.get("ring", []) })


# ---------------------------------------------------------------- simulate / AI

## BWBattle._digest: the beams the board would hold after the action.
static func digest(b: BWBattle, out: Dictionary) -> void:
	out["beams"] = beams(b)


## Where to stand (HP points): a beam this hex would form with an ally on
## light (the damage it would deal to foes on it at the tick, plus a little
## for Empowered); minus an enemy beam over the hex.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if u.size > 1:
		return 0.0
	var score := 0.0
	for bm in beams(b):
		if bm.team != u.team and h in bm.hexes and not str(u.id) in bm.ends:
			score -= float(bm.pct) * u.max_hp() / 100.0
	var lt := b.tiles.intensity(h, "light")
	if lt <= 0:
		return score
	for a in b.side(u.team):
		if a == u or lit(b, a) <= 0:
			continue
		var sp = span(b, h, a.pos)
		if sp == null:
			continue
		var pct := BASE_PCT + PER_LIGHT_PCT * mini(lt, lit(b, a))
		var gain := 2.0
		for x in sp:
			var o := b.unit_at(x)
			if o != null and o.team != u.team and not BWObelisk.is_objective(o):
				gain += o.max_hp() * pct / 100.0
		score += gain
	return score


# ---------------------------------------------------------------- readability

## The tile card's lines for `h`.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	for bm in beams(b):
		if h in bm.hexes:
			var a := b._unit(str(bm.ends[0]))
			var c := b._unit(str(bm.ends[1]))
			out.append("Beam (%s–%s%s): %d%% to their foes here at the tick; their allies on it are Empowered +%d%%" % [
				a.name if a else "?", c.name if c else "?", ", bent" if str(bm.bend) != "" else "", int(bm.pct), int(bm.empower)])
	if b.tiles.intensity(h, "light") >= DAWN_LIGHT:
		out.append("Dawn: a unit starting its turn here takes 1 off its longest cooldown")
	var src := b._unit(str(b.tiles.at(h).get("source", "")))
	if b.tiles.intensity(h, "light") > 0 and src != null and ks(src, "magnify"):
		out.append("Magnify (%s's light): %s's allies here cast magnified, once a turn (+1 radius, or +1 charge step)" % [src.name, src.name])
	var u := b._centre_at(h)
	if u != null and u.alive():
		if empowered(u) > 0:
			out.append("%s: Empowered, +%d%% on its next attack (this turn)" % [u.name, empowered(u)])
		var w: Dictionary = u.fx.get("light_ward", {})
		if not w.is_empty():
			out.append("%s: Ward of Light, absorbs %d (until hit)" % [u.name, int(w.hp)])
	return out

class_name BWKsDark
extends RefCounted
## D296 dark's keystones (the author's rulings of 2026-10-07, "Dark": curse
## and void, NOT the stealth draft; ELEMENTS.md §16.4). Pure rules; BWCurse's
## Lane C hooks (add_rot, turn_end, on_ko, tick, gravity_reach) call them.
##
## Contagion      a foe with Rot is KO'd (by anyone): its Rot jumps to every
##                foe within CONTAGION_RADIUS of it, +1 stack each (capped at
##                3). One jump per KO, however many holders.
## Doom           a foe reaching 3 Rot is DOOMED (once per foe per battle). At
##                the end of its NEXT turn (a skipped Frozen turn counts) it
##                takes DOOM_BASE + DOOM_PER_ROT per Rot % of its max HP (dark),
##                and each foe adjacent to it (its own side) half that % of
##                theirs (Claude: the detonation convention); then its Rot
##                clears. Credited to the holder.
## Event Horizon  your dark 3's gravity reaches 2 (BWCurse.gravity_reach); at
##                the tick, each foe within EH_RADIUS of your dark 3 (and not
##                on it) is pulled 1 toward the nearest, closest first: a field
##                move under BWWind's caps, gravity's extra hex not added (the
##                ruling says "pulled 1"). A foe standing on your dark 3 can't
##                be healed (any source).

const CONTAGION := "contagion"
const DOOM := "doom"
const HORIZON := "event_horizon"
const CONTAGION_RADIUS := 2
const DOOM_BASE := 15.0
const DOOM_PER_ROT := 5.0
const DOOM_SPLASH := 0.5
const EH_RADIUS := 2
const EH_REACH := 2


static func has(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


## A living holder of `id` among the foes of `v` (first in setup order).
static func holder(b: BWBattle, v: BWUnit, id: String) -> BWUnit:
	for o in b.units:
		if o.alive() and o.team != v.team and not BWObelisk.is_objective(o) and has(o, id):
			return o
	return null


# ---------------------------------------------------------------- Contagion

static func on_ko(b: BWBattle, victim: BWUnit, rot_before: int) -> void:
	if rot_before <= 0 or b.over:
		return
	var h := holder(b, victim, CONTAGION)
	if h == null:
		return
	var to: Array = []
	for w in b.units:
		if w == victim or not w.alive() or w.team != victim.team or BWObelisk.is_objective(w):
			continue
		if b.gap(victim, w) <= CONTAGION_RADIUS:
			to.append(w)
	if to.is_empty():
		return
	b._emit({ "type": "contagion", "unit": victim.id, "hex": victim.pos, "by": h.id, "to": to.map(func(x): return x.id) })
	for w in to:
		BWCurse.add_rot(b, w, 1, h.id, "contagion")


# ---------------------------------------------------------------- Doom

static func doomed(u: BWUnit) -> bool:
	return u != null and not (u.fx.get("doom", {}) as Dictionary).is_empty()


## BWCurse.add_rot reached ROT_MAX.
static func on_rot_max(b: BWBattle, v: BWUnit) -> void:
	if doomed(v) or bool(v.fx.get("doom_done", false)):
		return
	var h := holder(b, v, DOOM)
	if h == null:
		return
	v.fx["doom"] = { "at": b._turn_serial, "by": h.id }
	v.fx["doom_done"] = true                      # once per foe per battle
	b._emit({ "type": "doomed", "unit": v.id, "by": h.id, "hex": v.pos })


## The burst's % for `v` now.
static func doom_pct(v: BWUnit) -> float:
	return DOOM_BASE + DOOM_PER_ROT * BWCurse.rot(v)


## BWCurse.turn_end (before the Rot gain): the end of the doomed unit's next turn.
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if not doomed(u) or b.over or not u.alive():
		return
	var d: Dictionary = u.fx.doom
	if int(d.at) >= b._turn_serial:
		return                                     # doomed during this very turn: the next one
	u.fx.erase("doom")
	var pct := doom_pct(u)
	var by := str(d.by)
	var near: Array = []
	for w in b.units:
		if w != u and w.alive() and w.team == u.team and not BWObelisk.is_objective(w) and b.gap(u, w) <= 1:
			near.append(w)
	b._emit({ "type": "doom", "unit": u.id, "hex": u.pos, "by": by, "pct": pct, "rot": BWCurse.rot(u),
		"splash": near.map(func(x): return x.id) })
	b._tile_hurt(u, b._tile_dmg(u, pct, "dark"), "doom", by)
	for w in near:
		if b.over or not w.alive():
			continue
		b._tile_hurt(w, b._tile_dmg(w, pct * DOOM_SPLASH, "dark"), "doom", by)
	if u.alive():
		BWCurse.add_rot(b, u, -BWCurse.ROT_MAX, "", "doom")


# ---------------------------------------------------------------- Event Horizon

static func gravity_reach(b: BWBattle, v: BWUnit, base: int) -> int:
	return maxi(base, EH_REACH) if holder(b, v, HORIZON) != null else base


## Dark 3 hexes laid by `o` (sorted).
static func own_dark3(b: BWBattle, o: BWUnit) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		if b.tiles.intensity(h, "dark") >= BWCurse.GRAVITY_LEVEL and str(b.tiles.at(h).get("source", "")) == o.id:
			out.append(h)
	out.sort()
	return out


## The tick (BWCurse.tick, inside the wind tick): the pulls.
static func tick(b: BWBattle) -> void:
	for o in b.units:
		if b.over:
			return
		if not o.alive() or not has(o, HORIZON):
			continue
		var g := own_dark3(b, o)
		if g.is_empty():
			continue
		var rows: Array = []
		for f in b.foes_of(o):
			if BWObelisk.is_objective(f) or maxi(f.size, 1) > 1 or f.pos in g:
				continue
			var near := Vector2i.ZERO
			var dn := 1 << 20
			for h in g:
				var dd := BWHex.distance(f.pos, h)
				if dd < dn or (dd == dn and h < near):
					dn = dd
					near = h
			if dn <= EH_RADIUS:
				rows.append([dn, b.units.find(f), f, near])
		rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
		var moved: Array = []
		for r in rows:
			if b.over:
				break
			var f: BWUnit = r[2]
			var res := BWWind.push(b, f, BWBattle.pulse_heading(r[3], f.pos, false), 1, "pull", o, true, false, [], false, true)
			if res.moved:
				moved.append(f.id)
		if not moved.is_empty():
			b._emit({ "type": "event_horizon", "unit": o.id, "units": moved, "hexes": g })


## BWBattle._heal: a foe of a holder standing on the holder's dark 3.
static func heal_blocked(b: BWBattle, u: BWUnit) -> bool:
	if b.tiles.intensity(u.pos, "dark") < BWCurse.GRAVITY_LEVEL:
		return false
	var src := b._unit(str(b.tiles.at(u.pos).get("source", "")))
	return src != null and src.team != u.team and has(src, HORIZON)


## The AI: a foe of an Event Horizon holder avoids standing within its pull
## or on its dark 3 (no heals), a little.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	var s := 0.0
	for o in b.foes_of(u):
		if not has(o, HORIZON):
			continue
		for g in own_dark3(b, o):
			var d := BWHex.distance(h, g)
			if d == 0:
				s -= 4.0
			elif d <= EH_RADIUS:
				s -= 1.5
	return s


## The tile card's lines.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u != null and doomed(u):
		out.append("%s is DOOMED: at the end of its next turn %d%% to it, half to its neighbours; then its Rot clears" % [u.name, int(doom_pct(u))])
	if u != null and heal_blocked(b, u):
		out.append("Event Horizon: %s can't be healed here" % u.name)
	if b.tiles.intensity(h, "dark") >= BWCurse.GRAVITY_LEVEL:
		var src := b._unit(str(b.tiles.at(h).get("source", "")))
		if has(src, HORIZON):
			out.append("Event Horizon (%s): pulls its foes within %d in by 1 at the tick; its foes here can't be healed" % [src.name, EH_RADIUS])
	return out

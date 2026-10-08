class_name BWKs3Dark
extends RefCounted
## D449-D450 dark's keystones (Keystones v3, design/ELEMENTS.md). Pitch Black
## and its light twin Solar Flare share the OVERCHARGE rules here.
##
## Abyssal     a free action, once per turn (skill def pitch_black, D449,
##             Claude: a free action, not a cast): pick a dark 3 hex within 3
##             (anyone's). It is OVERCHARGED and explodes as PITCH BLACK:
##             PCT% (dark) to every FOE within 1 (2 with Superconductor) and
##             +1 Rot each. The hex is not consumed: it is dark 4 for the rest
##             of your turn, then dark 3 again (revert_overcharge at your
##             turn's end). Foes only (Claude: a keystone burst never hits your
##             own side).
## Hopekiller  foes standing on your dark (any level) can't be healed or
##             buffed (Empowered, Ward of Light, an enchantment's empower):
##             any heal they'd get hurts them for the same amount instead
##             (cause "hopekiller", no resistance: it is their own heal). A
##             foe KO'd on your dark leaves dark 3 there.

const ABYSSAL := "abyssal"
const HOPEKILLER := "hopekiller"


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


# ---------------------------------------------------------------- the overcharge (Pitch Black, Solar Flare)

## Which keystone and element an overcharge kind belongs to.
const KINDS := {
	"pitch_black": { "ks": "abyssal", "element": "dark", "sign": -1, "name": "Pitch Black" },
	"solar_flare": { "ks": "sunburst", "element": "light", "sign": 1, "name": "Solar Flare" },
}


## Has `u` used its `kind` this turn?
static func spent(b: BWBattle, u: BWUnit, kind: String) -> bool:
	return int(u.fx.get(kind + "_turn", -1)) == b._turn_serial


## The hexes `u` may overcharge now: its element at 3 (not already
## overcharged), within the keystone's range of `u`. [] when not held or spent.
static func targets(b: BWBattle, u: BWUnit, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var k: Dictionary = KINDS[kind]
	if u == null or not u.alive() or not ks(u, str(k.ks)) or spent(b, u, kind):
		return out
	var rng := int(BWKeystones.param(str(k.ks), "range", 3))
	for h in b.board.area(u.pos, rng):
		if b.tiles.intensity(h, str(k.element)) == 3 and not b.tiles.is_glazed(h):
			out.append(h)
	return out


## The burst's radius for `u` (1; Superconductor 2).
static func radius(u: BWUnit, kind: String) -> int:
	var r := int(BWKeystones.param(str(KINDS[kind].ks), "radius", 1))
	if ks(u, "superconductor"):
		r = maxi(r, int(BWKeystones.param("superconductor", "radius", 2)))
	return r


## Units of `team` (or its foes when `foes`) within `r` of `h` (footprints).
static func near(b: BWBattle, u: BWUnit, h: Vector2i, r: int, foes: bool) -> Array:
	var out: Array = []
	for o in b.units:
		if not o.alive() or BWObelisk.is_objective(o) or (o.team != u.team) != foes:
			continue
		if foes and not b.can_harm(u, o):
			continue
		var d := 1 << 20
		for f in o.footprint():
			d = mini(d, BWHex.distance(f, h))
		if d <= r:
			out.append(o)
	return out


## Overcharge `h` and explode it (Pitch Black / Solar Flare). Returns the foes hit.
static func burst(b: BWBattle, u: BWUnit, h: Vector2i, kind: String) -> Array:
	var k: Dictionary = KINDS[kind]
	u.fx[kind + "_turn"] = b._turn_serial
	var e := b.tiles.at(h)
	if not e.is_empty():
		e.v = int(k.sign) * 4                       # dark 4 / light 4 until the turn ends
		e.permanent = false
		e.erase("seeded")
		var oc: Array = u.fx.get("overcharged", [])
		oc.append([h, int(k.sign)])
		u.fx["overcharged"] = oc
	var r := radius(u, kind)
	var pkey := str(k.ks)
	var foes := near(b, u, h, r, true)
	var allies := near(b, u, h, r, false) if kind == "solar_flare" else []
	b._emit({ "type": kind, "unit": u.id, "hex": h, "radius": r, "units": foes.map(func(o): return o.id),
		"allies": allies.map(func(o): return o.id), "pct": BWKeystones.param(pkey, "pct", 15) })
	var pct := BWKeystones.param(pkey, "pct", 15)
	for f in foes:
		if b.over or not f.alive():
			continue
		b._tile_hurt(f, b._tile_dmg(f, pct, str(k.element)), kind, u.id)
		if kind == "pitch_black" and f.alive() and not b.over:
			BWCurse.add_rot(b, f, int(BWKeystones.param(pkey, "rot", 1)), u.id, "pitch_black")
	for a in allies:
		if not b.over and a.alive():
			b._heal(a, BWKeystones.param(pkey, "heal_pct", 5), "solar_flare")
	if not b.over and u.alive():
		BWKs3Thunder.overflow(b, u, 1)               # D453: a burst is a reaction you set off
	return foes


## The end of `u`'s turn: its overcharged hexes go back to 3.
static func revert_overcharge(b: BWBattle, u: BWUnit) -> void:
	var oc: Array = u.fx.get("overcharged", [])
	if oc.is_empty():
		return
	u.fx.erase("overcharged")
	var back: Array = []
	for rec in oc:
		var h: Vector2i = rec[0]
		var e := b.tiles.at(h)
		if not e.is_empty() and int(e.v) == int(rec[1]) * 4:
			e.v = int(rec[1]) * 3
			back.append(h)
	if not back.is_empty():
		b._emit({ "type": "overcharge_end", "unit": u.id, "hexes": back })


## The AI: the overcharge worth the most (foes' HP points; Solar Flare adds
## the allies it heals). {target, element, score} or {}.
static func ai_pick(b: BWBattle, u: BWUnit, kind: String) -> Dictionary:
	var best := {}
	var k: Dictionary = KINDS[kind]
	var pct := BWKeystones.param(str(k.ks), "pct", 15)
	for h in targets(b, u, kind):
		var sc := 0.0
		for f in near(b, u, h, radius(u, kind), true):
			var d := float(b._tile_dmg(f, pct, str(k.element)))
			sc += d + (1000.0 if d >= f.hp else 0.0)
		if kind == "solar_flare":
			for a in near(b, u, h, radius(u, kind), false):
				sc += minf(a.max_hp() - a.hp, a.pct_base_hp() * BWKeystones.param("sunburst", "heal_pct", 5) / 100.0) * 0.5
		if sc > 0.0 and (best.is_empty() or sc > float(best.score)):
			best = { "target": h, "element": "", "score": sc }
	return best


# ---------------------------------------------------------------- Hopekiller

## The Hopekiller whose dark `u` (a foe of it) stands on, else null.
static func hopekiller_on(b: BWBattle, u: BWUnit) -> BWUnit:
	if u == null or b.tiles.intensity(u.pos, "dark") <= 0:
		return null
	var src := b._unit(str(b.tiles.at(u.pos).get("source", "")))
	if src == null or src.team == u.team or not ks(src, HOPEKILLER):
		return null
	return src


## BWBattle._heal: a heal on a foe on Hopekiller's dark hurts instead. True
## = handled.
static func heal_to_harm(b: BWBattle, u: BWUnit, pct: float, cause: String) -> bool:
	var hk := hopekiller_on(b, u)
	if hk == null or u.fx.get("_hopekiller", false):
		return false
	var amt := maxi(1, roundi(u.pct_base_hp() * pct / 100.0))   # D485
	u.fx["_hopekiller"] = true
	b._emit({ "type": "hopekiller", "unit": u.id, "by": hk.id, "amount": amt, "cause": cause })
	b._tile_hurt(u, amt, "hopekiller", hk.id)
	u.fx.erase("_hopekiller")
	return true


## A buff about to land on `u` (Empowered, a Ward of Light, an enchantment's
## empower): blocked on Hopekiller's dark (emits the feed line).
static func buff_blocked(b: BWBattle, u: BWUnit, what: String) -> bool:
	var hk := hopekiller_on(b, u)
	if hk == null:
		return false
	b._emit({ "type": "enchant", "unit": u.id, "name": "Hopekiller", "text": "%s blocked: can't be buffed" % what })
	return true


## BWBattle._ko: a foe KO'd on Hopekiller's dark leaves dark 3.
static func on_ko(b: BWBattle, victim: BWUnit) -> void:
	var hk := hopekiller_on(b, victim)
	if hk == null or b.over and not hk.alive():
		return
	var h := victim.pos
	var e := b.tiles.at(h)
	if e.is_empty():
		return
	e.v = -3
	e.source = hk.id
	e.timer = BWTiles.STEP_CYCLES
	e.permanent = false
	e.erase("seeded")
	e.erase("ecl")
	b._emit({ "type": "hopekiller_mark", "unit": hk.id, "hex": h, "victim": victim.id })
	b._emit({ "type": "paint", "unit": hk.id, "element": "dark", "hexes": [h], "kind": "lay_on" })


# ---------------------------------------------------------------- AI and cards

## A foe of a Hopekiller, hurt, avoids its dark a little.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if b.tiles.intensity(h, "dark") <= 0 or u.hp >= u.max_hp():
		return 0.0
	var src := b._unit(str(b.tiles.at(h).get("source", "")))
	if src != null and src.team != u.team and ks(src, HOPEKILLER):
		return -3.0
	return 0.0


static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var dk := b.tiles.intensity(h, "dark")
	if dk > 0:
		var src := b._unit(str(b.tiles.at(h).get("source", "")))
		if src != null and ks(src, HOPEKILLER):
			out.append("Hopekiller (%s): its foes here can't be healed or buffed; a heal hurts them instead; a foe KO'd here leaves dark 3" % src.name)
	if dk >= 4 or b.tiles.intensity(h, "light") >= 4:
		out.append("Overcharged: counts as %s 4 until its caster's turn ends" % ("dark" if dk >= 4 else "light"))
	return out

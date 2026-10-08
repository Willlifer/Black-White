class_name BWKs3Wind
extends RefCounted
## D454-D455 wind's keystones (Keystones v3, design/ELEMENTS.md).
##
## El Niño  your wind AREAS reach 1 ring further: a wind skill whose shape is
##          an area of radius 1-3 (the def's `aoe` + `radius`) grows by 1 (the
##          new ring is hit and painted), and your gales spread 1 ring further
##          (the paint option gale_radius, BWKs3.paint_opts). Stacks with
##          Magnify's ring (that one stops at 3; El Niño may reach 4).
## La Niña  at the start of your turn every foe takes PCT% of its max HP
##          (wind class, cause "la_nina") and is pulled 1 toward you (a field
##          move under BWWind's caps; a multi-hex foe or an anchored one
##          stays). Closest first.

const NINO := "el_nino"
const NINA := "la_nina"
const MAX_RADIUS := 3


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


## BWBattle._plan: El Niño widens a wind area by one ring.
static func widen(b: BWBattle, u: BWUnit, d: BWSkillDef, p: Dictionary) -> void:
	if str(p.get("element", "")) != "wind" or not ks(u, NINO) or p.has("el_nino"):
		return
	if not bool(d.data.get("aoe", false)) or not d.data.has("radius"):
		return
	var r := BWBeams._radius(p.hexes, [u.pos, p.get("dest", u.pos)])
	if r < 1 or r > MAX_RADIUS:
		return
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
	p["el_nino"] = { "ring": ring, "radius": r + 1 }
	p.notes.append("El Niño: +1 radius, %d → %d" % [r, r + 1])


## At the start of `u`'s own turn: La Niña's chip and pull.
static func la_nina(b: BWBattle, u: BWUnit) -> void:
	if not ks(u, NINA) or not u.alive() or b.over:
		return
	var pct := BWKeystones.param(NINA, "pct", 2.5)
	var rows: Array = []
	for f in b.foes_of(u):
		if BWObelisk.is_objective(f) or not f.alive():
			continue
		rows.append([b.gap(u, f), b.units.find(f), f])
	if rows.is_empty():
		return
	rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
	b._emit({ "type": "la_nina", "unit": u.id, "units": rows.map(func(r): return (r[2] as BWUnit).id), "pct": pct })
	for r in rows:
		var f: BWUnit = r[2]
		if b.over or not f.alive():
			continue
		b._tile_hurt(f, b._tile_dmg(f, pct, "wind"), "la_nina", u.id)
	var moved: Array = []
	for r in rows:
		var f: BWUnit = r[2]
		if b.over or not f.alive() or maxi(f.size, 1) > 1 or b.gap(u, f) <= 1:
			continue
		var res := BWWind.push(b, f, BWBattle.pulse_heading(u.pos, f.pos, false), int(BWKeystones.param(NINA, "pull", 1)),
			"pull", u, true, false)
		if res.moved:
			moved.append(f.id)
	if not moved.is_empty():
		b._emit({ "type": "la_nina_pull", "unit": u.id, "units": moved })


## BWAI: a La Niña holder likes being central (every foe is pulled toward it,
## so nearer is better for the melee; it costs little to a bow).
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if not ks(u, NINA):
		return 0.0
	var s := 0.0
	for f in b.foes_of(u):
		var d := BWHex.distance(h, f.pos)
		if d >= 3 and d <= 6:
			s += 0.5
	return s

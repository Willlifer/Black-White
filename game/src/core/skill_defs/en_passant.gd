extends BWSkillDef
## Sword. D426 (the author: "Lunging to a unit within 3 tiles in a line.
## Traveling through the target. Leaving behind element and allowing for a
## second elemental single-target strike."). It replaces Elemental Truth in
## the sword's pool (elemental_truth.gd stays, retired, for old saves).
## Click a foe up to LEN hexes away on one of the six straight lines, with
## the hexes before it clear and a free hex right beyond it to land on: you
## dash through it, striking it on the way, and land beyond. Every hex you
## travelled takes your element (the target's too, and the landing). Then
## the Passing Cut (en_passant_strike): a second elemental strike at any
## adjacent foe. A blocked landing (rock, a unit, the map's edge, a climb too
## steep) means no En Passant at that foe; the aim shows it in red
## (`blocked`). Running, so fire on the way burns (like Lunge).

const POWER := 11
const CD := 3
const LEN := 3


func _init() -> void:
	define({
		"key": "en_passant", "name": "En Passant", "weapon": "sword", "clip": "thrust",
		"desc": "Dash through an enemy up to 3 tiles away in a straight line, striking it, and land on the tile beyond. Every tile you cross takes your element; then a second elemental strike at any foe beside you",
		"targeting": "unit", "needs_element": true, "range": LEN, "cd": CD,
		"power": POWER, "follow_up": ["en_passant_strike"],
	}, 305)


## Foes on a straight line within LEN with a clear run and a free landing.
func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for f in b.foes_of(u):
		if f.size <= 1 and not run_for(b, u, f).has("blocked"):
			out.append(f.pos)
	return out


## The run at `f`: { line (hexes before it), landing } or { blocked: why }
## ("" keys absent when not on a line at all: { blocked: "line" }).
func run_for(b: BWBattle, u: BWUnit, f: BWUnit) -> Dictionary:
	var d := BWHex.distance(u.pos, f.pos)
	if d < 1 or d > LEN or f.size > 1:
		return { "blocked": "line" }
	var ray := BWHex.ray(u.pos, f.pos, d + 1)
	if ray.size() < d + 1 or ray[d - 1] != f.pos:
		return { "blocked": "line" }
	var opts := { "jump": BWWeaponMove.jump(u) }
	var prev := u.pos
	var line: Array = []
	for i in d - 1:
		var h: Vector2i = ray[i]
		if b.board.step_cost(prev, h, opts) < 0 or not b.can_stand(u, h):
			return { "blocked": "path", "at": h }
		line.append(h)
		prev = h
	var land: Vector2i = ray[d]
	if not b.board.exists(land):
		return { "blocked": "edge", "at": land }
	if b.board.step_cost(f.pos, land, opts) < 0 or not b.can_stand(u, land):
		return { "blocked": "landing", "at": land }
	return { "line": line, "landing": land }


## The aim's red: a foe in a straight line within reach whose landing (or
## run) is blocked. { hex, why } or {}.
func blocked(b: BWBattle, u: BWUnit, h: Vector2i) -> Dictionary:
	var f := b.unit_at(h)
	if f == null or f.team == u.team:
		return {}
	var r := run_for(b, u, f)
	if not r.has("blocked") or str(r.blocked) == "line":
		return {}
	return { "hex": r.get("at", h), "why": str(r.blocked) }


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var f := b.unit_at(target)
	if f == null:
		return
	var r := run_for(b, u, f)
	if r.has("blocked"):
		return
	p.walk = (r.line as Array) + [f.pos, r.landing]
	p.dest = r.landing
	p.victims = [f]
	p.hexes = (p.walk as Array).duplicate()          # every hex travelled takes the element
	p["passed"] = f
	p.notes.append("Dash %d through %s and land beyond; %d tiles take the element" % [
		(p.walk as Array).size(), f.name, (p.hexes as Array).size()])
	p.notes.append("Then the Passing Cut: a second elemental strike at a foe beside you")


func relocate(b: BWBattle, u: BWUnit, p: Dictionary, target_hex: Vector2i) -> void:
	if p.walk.is_empty():
		super.relocate(b, u, p, target_hex)
		return
	var path: Array = [u.pos] + (p.walk as Array)
	b.skill_relocate(u, p, path, "charge")
	for h in p.walk:                    # running, so the ground burns
		var pct := b.tiles.crossing_pct(h)
		if pct > 0 and u.alive() and not BWEffects.has(u, "heat_rush"):
			b._tile_hurt(u, b._tile_dmg(u, pct, "fire"), "fire_cross", str(b.tiles.at(h).get("source", "")))
	b._lay_on_move(u, path)
	var f: BWUnit = p.get("passed", null)
	if f != null and u.alive():
		b._face(u, f.pos)                # turns back on the foe it passed


## A damaging skill with a follow-up: the AI still weighs it (and plays the
## Passing Cut after, BWAI).
func ai_considers(_row: Dictionary) -> bool:
	return true


## The dash's blow, plus a rough worth for the Passing Cut (a foe beside the
## landing), minus fire crossed.
func ai_score(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	var score := super.ai_score(b, u, pv)
	var land: Vector2i = pv.dest
	for f in b.foes_of(u):
		if f.alive() and BWHex.distance(land, f.pos) == 1:
			score += 0.6 * float(BWSkills.get_skill("en_passant_strike").get("power", 9))
			break
	return score

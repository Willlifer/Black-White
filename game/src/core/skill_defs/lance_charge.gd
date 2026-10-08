extends BWSkillDef
## Lance. D428 (the author: "set destination tile in a line. Then charges up
## to 10 tiles as next turn starts, allowing for action and movement after
## the charge. This is elemental and leaves behind a trail.").
##
## Cast (your action): pick a hex up to LEN away on one of the six straight
## lines (rock or a climb too steep ends what you can pick). The line is
## telegraphed to both sides (u.fx.lance_charge; BWKit2View draws it) and
## the AI steps off it. At the start of your next turn, before you act, you
## charge along it (`run`, called by BWKit2.turn_start):
##   - each foe in the way is struck (POWER, the element) and PIERCED: you
##     run on through it when the hex beyond is free and still on the line;
##   - where you can't go on past a foe (rock, a unit, the line's end) you
##     stop in front of it; if rock or a unit stopped it, it slams (Charge's
##     8%, to it and to the unit behind);
##   - an ally, rock or a climb in the way just stops you there;
##   - every hex you ran over takes the element (the pierced foes' hexes too).
## Then your turn is whole: move and action. Running, so fire burns.

const LEN := 10
const POWER := 10
const CD := 4


func _init() -> void:
	define({
		"key": "lance_charge", "name": "Lance Charge", "weapon": "lance", "clip": "brace",
		"desc": "Set a charge up to 10 tiles in a straight line, shown to everyone. At the start of your next turn you charge it: every enemy in the way is struck and pierced (one that can't be passed slams), and the path takes your element. Then you still move and act",
		"targeting": "hex", "needs_element": true, "range": LEN, "cd": CD,
		"power": 0, "min_range": 2,
	}, 330)


## Hexes up to LEN along each heading, until rock or a climb too steep.
func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u.fx.has("lance_charge"):
		return out
	for n in BWHex.neighbors(u.pos):
		var line := line_to(b, u, n, LEN)
		for i in line.size():
			if i >= 1:                      # 2+ hexes: a charge, not a step
				out.append(line[i])
	return out


## The open line from `u` toward `toward` (ground only; units ignored).
func line_to(b: BWBattle, u: BWUnit, toward: Vector2i, n: int) -> Array:
	var out: Array = []
	var prev := u.pos
	for h in b.board.ray(u.pos, toward, n):
		if b.board.step_cost(prev, h) < 0:
			break
		out.append(h)
		prev = h
	return out


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	var line := line_to(b, u, target, BWHex.distance(u.pos, target))
	if line.is_empty() or line[-1] != target:
		return
	p["line"] = line
	p.notes.append("Next turn start: charge %d tile%s along this line, striking and piercing each enemy (%d power, %s), painting the path; then move and act" % [
		line.size(), "" if line.size() == 1 else "s", POWER, element if element != "" else "plain"])
	var foes: Array = line.filter(func(h): return b.unit_at(h) != null and b.unit_at(h).team != u.team)
	if not foes.is_empty():
		p.notes.append("On the line now: %s (they see it coming)" % ", ".join(foes.map(func(h): return b.unit_at(h).name)))


## The cast sets the line; nothing is struck or painted yet.
func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	var line: Array = p.get("line", [])
	if line.is_empty():
		return 0
	u.fx["lance_charge"] = { "element": el, "line": line.duplicate(), "dir": BWHex.direction_index(u.pos, line[0]) }
	b._emit({ "type": "lance_charge_set", "unit": u.id, "element": el, "hexes": line.duplicate() })
	return 0


## The strikes' power (the row's power is 0: the cast itself hits nobody).
func power_formula(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary) -> Dictionary:
	return BWFormulas.calc("Skill power", POWER, "Lance Charge", "%d (the charge's strike)" % POWER)


# ---------------------------------------------------------------- the run

## Where the run goes as things stand: { walk, struck [units], slam {} }.
func simulate_run(b: BWBattle, u: BWUnit, line: Array) -> Dictionary:
	var walk: Array = []
	var struck: Array = []
	var slam := {}
	var prev := u.pos
	var dir := BWHex.direction_index(u.pos, line[0]) if not line.is_empty() else -1
	for i in line.size():
		var h: Vector2i = line[i]
		if b.board.step_cost(prev, h) < 0:
			break
		var o := b.unit_at(h)
		if o == null:
			if not b.can_stand(u, h):
				break
			walk.append(h)
			prev = h
			continue
		if o.team == u.team or not b.can_harm(u, o):
			break                                          # an ally (or a stone) stops the run
		struck.append(o)
		if o.size > 1:
			break                                          # a big foe: struck, the run ends at it
		var nxt: Vector2i = line[i + 1] if i + 1 < line.size() else BWBattle.NOWHERE
		if nxt != BWBattle.NOWHERE and b.board.step_cost(h, nxt) >= 0 and b.unit_at(nxt) == null and b.can_stand(u, nxt):
			walk.append(h)                                 # pierced: on through it
			prev = h
			continue
		if nxt != BWBattle.NOWHERE:                        # blocked beyond: it slams into what stopped it
			var beyond: Vector2i = BWHex.neighbors(h)[dir]
			var why := _blocked(b, u, o, h, beyond)
			if why in ["rock", "unit"]:
				slam = { "unit": o, "kind": why, "into": b.unit_at(beyond) if why == "unit" else null }
		break
	return { "walk": walk, "struck": struck, "slam": slam }


## Why a struck foe can't be carried past `at` to `nxt` (Charge's rule):
## "immune", "edge", "unit", "rock" or "".
func _blocked(b: BWBattle, u: BWUnit, v: BWUnit, at: Vector2i, nxt: Vector2i) -> String:
	if b._immune(v, "displace"):
		return "immune"
	if not b.board.exists(nxt):
		return "edge"
	var o := b.unit_at(nxt)
	if o != null and o != v and o != u:
		return "unit"
	if b.board.step_cost(at, nxt) < 0 or not b.can_stand(v, nxt):
		return "rock"
	return ""


## BWKit2.turn_start: the charge goes off.
func run(b: BWBattle, u: BWUnit) -> void:
	var c: Dictionary = u.fx.get("lance_charge", {})
	u.fx.erase("lance_charge")
	if c.is_empty() or b.over or not u.alive():
		return
	var el := str(c.get("element", ""))
	var line: Array = c.get("line", [])
	if u.statuses.has("frozen") or u.statuses.has("becalmed"):
		b._emit({ "type": "lance_charge_run", "unit": u.id, "element": el, "path": [u.pos], "fizzled": true })
		return
	var r := simulate_run(b, u, line)
	var walk: Array = r.walk
	var path: Array = [u.pos] + walk
	b._emit({ "type": "lance_charge_run", "unit": u.id, "element": el, "path": path, "struck": (r.struck as Array).map(func(o): return o.id) })
	if not walk.is_empty():
		b.skill_relocate(u, { "dest": walk[-1], "shove": {} }, path, "charge")
		for h in walk:
			var pct := b.tiles.crossing_pct(h)
			if pct > 0 and u.alive() and not BWEffects.has(u, "heat_rush"):
				b._tile_hurt(u, b._tile_dmg(u, pct, "fire"), "fire_cross", str(b.tiles.at(h).get("source", "")))
		b._lay_on_move(u, path)
	var hexes: Array = walk.duplicate()
	var p := { "victims": r.struck, "shares": {}, "notes": [] }
	for o in r.struck:
		var v: BWUnit = o
		if not v.alive() or b.over or not u.alive():
			continue
		if not v.pos in hexes:
			hexes.append(v.pos)
		b._face(u, v.pos)
		var fc := b._skill_forecast(u, data, el, v, p)
		var res := b.roll(fc)
		BWEnchant.land(b, u, v, res)
		var before := v.hp
		v.hp = maxi(0, v.hp - res.damage)
		b._emit({ "type": "attack", "unit": u.id, "target": v.id, "result": res, "forecast_hit": fc.hit.value,
			"odds": BWBattle.odds(fc), "ko": not v.alive(), "target_hp": v.hp, "skill": id, "pattern": "lance_charge",
			"tags": BWBattle._tags(fc) })
		b._after_blow(u, v, res, before, "")
		b._conduct(u, v, int(res.damage))
		b._answer(b._riposte_check(v, res))
	var sl: Dictionary = r.slam
	if not sl.is_empty() and u.alive() and not b.over and (sl.unit as BWUnit).alive():
		var cv: BWUnit = sl.unit
		var into: BWUnit = sl.get("into", null)
		b._emit({ "type": "slam", "unit": cv.id, "by": u.id, "into": sl.kind, "with": into.name if into != null else "", "skill": id })
		b._tile_hurt(cv, b._tile_dmg(cv, BWSkills.CHARGE_SLAM_PCT, ""), "slam", u.id)
		if into != null and into.alive():
			b._tile_hurt(into, b._tile_dmg(into, BWSkills.CHARGE_SLAM_PCT, ""), "slam", u.id)
	if el != "" and not hexes.is_empty() and not b.over and u.alive():
		b.paint(hexes, el, u)                              # the trail
	b._check_end()


# ---------------------------------------------------------------- AI

## A support cast (no damage now): the AI sets the line with the most foes
## on it as they stand (they may step off: half value), the longest such.
func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	if u.fx.has("lance_charge") or (row.get("elements", []) as Array).is_empty():
		return {}
	var el := str(row.elements[0])
	var best := {}
	for n in BWHex.neighbors(u.pos):
		var line := line_to(b, u, n, LEN)
		if line.size() < 2:
			continue
		var r := simulate_run(b, u, line)
		if (r.struck as Array).is_empty():
			continue
		var score := 0.0
		for o in r.struck:
			var fc := b._skill_forecast(u, data, el, o, { "victims": [o], "shares": {}, "notes": [] })
			score += 0.5 * float(fc.expected.value)
		if best.is_empty() or score > float(best.score) + 0.01:
			best = { "target": line[-1], "element": el, "score": score }
	return best

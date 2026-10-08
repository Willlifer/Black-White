class_name BWKsWind
extends RefCounted
## D293 wind's keystones (design/ELEMENTS-v3.md §1 "Keystones", ELEMENTS.md
## §16.1). Pure rules on top of BWWind (src/core/wind_modes.gd), which calls
## the hooks here. Who holds what is BWKeystones (Lane C1).
##
## Eye of the Vortex  your Vortex fields pull EVERYONE within 2, up to 2 hexes,
##                    toward the centre, both when they fire and at the tick.
##                    Each unit steps in one hex at a time and stops at the
##                    first blocked hex: no slam on an inward pull. Only ONE of
##                    your Vortex fields acts per tick: the newest.
## Wind Wall          the existing action (skill def wind_wall), now granted by
##                    the keystone (the D273 flag is gone).
## Jetstream          wind on a gale 2 makes a gale 3 (copies to radius 3);
##                    the copies of your gales (or that your paint makes) last
##                    2 cycles; your Gust fields push 2. Every field move stays
##                    inside BWWind's caps (2 hexes per cycle, once per turn).
## Glaze carry (D293, the D272 TODO; D398 dropped the "rink" name): a glazed
## hex never fires a gale (wind on glaze does nothing, ELEMENTS-v3 §2), so
## glaze can't be the origin. A gale that fires NEXT TO glaze (a glazed,
## standable hex beside the origin) carries it instead: its WATER copies glaze
## for GLAZE_CARRY cycle (a fire or light copy stays unglazed; Unsteady ground,
## never a pillar: pillars need a fresh ice cast).

const EYE := "eye_of_vortex"
const WALL := "wind_wall"
const JET := "jetstream"
const EYE_RADIUS := 2
const EYE_PULL := 2
const JET_GALE_MAX := 3
const JET_COPY_CYCLES := 2
const JET_GUST := 2
const GLAZE_CARRY := 1


static func eye(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, EYE)


static func jet(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, JET)


## How far a Gust FIELD laid by `owner` pushes.
static func gust_n(owner: BWUnit) -> int:
	return JET_GUST if jet(owner) else 1


## BWBattle.paint: a Jetstream painter's wind on a gale 2 makes a gale 3, and
## the copies its paint makes last JET_COPY_CYCLES.
static func paint_opts(by: BWUnit, o: Dictionary) -> void:
	if not jet(by):
		return
	o["gale_max"] = JET_GALE_MAX
	o["gale_timer_plus"] = maxi(int(o.get("gale_timer_plus", 0)), JET_COPY_CYCLES - 1)


## BWWind.after_paint, for each gale that fired: the copies of a Jetstream
## holder's gale last JET_COPY_CYCLES too.
static func after_gale(b: BWBattle, g: Dictionary, snap: Dictionary) -> void:
	if not snap.has(g.origin):
		return
	var owner := b._unit(str(snap[g.origin].get("source", "")))
	if not jet(owner):
		return
	for c in g.copies:
		var e: Dictionary = b.tiles.entries.get(c, {})
		if not e.is_empty():
			e.timer = maxi(int(e.timer), JET_COPY_CYCLES)


## Glaze carry (BWWind.carry): a gale that fired beside glaze glazes its water copies.
static func carry_glaze(b: BWBattle, origin: Vector2i, copies: Array) -> void:
	var near := false
	var src := ""
	for n in b.board.neighbors(origin):
		if BWUnsteady.on_glaze(b.tiles, n) and not n in copies:
			near = true
			src = str(b.tiles.at(n).get("glaze_source", ""))
			break
	if not near:
		return
	for c in copies:
		var e: Dictionary = b.tiles.entries.get(c, {})
		if e.is_empty() or b.tiles.pillars.has(c) or str(e.get("marker", "")) != "" or int(e.h) >= 0:
			continue
		if int(e.glaze) <= 0:
			e.glaze = GLAZE_CARRY
			e["glaze_source"] = src
			e["glaze_carry"] = true


# ---------------------------------------------------------------- Eye of the Vortex

## The newest Vortex field of every Eye holder: owner id -> hex.
static func eye_fields(b: BWBattle) -> Dictionary:
	var best := {}
	var born := {}
	for h in BWWind.field_hexes(b):
		var f := BWWind.field_at(b, h)
		if str(f.mode) != BWWind.VORTEX:
			continue
		var o := b._unit(str(f.get("source", "")))
		if not eye(o):
			continue
		var n := int(f.get("born", 0))
		if not best.has(o.id) or n > int(born[o.id]) or (n == int(born[o.id]) and h > best[o.id]):
			best[o.id] = h
			born[o.id] = n
	return best


## Everyone within `radius` of `centre` is pulled in up to EYE_PULL hexes,
## closest first (ties in setup order), a field move under BWWind's caps.
static func eye_pull(b: BWBattle, owner: BWUnit, centre: Vector2i, radius: int = EYE_RADIUS) -> Array:
	var rows: Array = []
	for v in b.units:
		if not v.alive() or BWObelisk.is_objective(v) or maxi(v.size, 1) > 1 or v.pos == centre:
			continue
		var d := BWHex.distance(centre, v.pos)
		if d <= radius:
			rows.append([d, b.units.find(v), v])
	rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
	var moved: Array = []
	for r in rows:
		if b.over:
			break
		if pull_in(b, r[2], centre, EYE_PULL, owner):
			moved.append((r[2] as BWUnit).id)
	if not moved.is_empty() or not rows.is_empty():
		b._emit({ "type": "eye_pull", "hex": centre, "unit": owner.id if owner != null else "", "units": moved })
	return moved


## Step `v` toward `centre` one hex at a time, up to `n`, stopping before the
## first blocked hex (no slam). A field move (once per turn, the cycle budget).
## True when it moved.
static func pull_in(b: BWBattle, v: BWUnit, centre: Vector2i, n: int, by: BWUnit) -> bool:
	if not BWWind.field_ready(b, v):
		return false
	if b._immune(v, "displace"):
		b._emit({ "type": "displace_resisted", "unit": v.id, "kind": "pull" })
		return false
	var m := mini(n, BWWind.budget(b, v))
	var path: Array = [v.pos]
	var cur := v.pos
	for i in m:
		var d := BWBattle.pulse_heading(centre, cur, false)
		if d < 0:
			break
		var nxt: Vector2i = BWHex.neighbors(cur)[d]
		if b.board.step_cost(cur, nxt) < 0 or not b.can_stand(v, nxt):
			break
		cur = nxt
		path.append(cur)
	BWWind._spend(b, v, true, path.size() - 1)
	if path.size() < 2:
		return false
	v.pos = cur
	b._emit({ "type": "move", "unit": v.id, "path": path, "kind": "pull", "wind": true, "eye": true })
	return true


# ---------------------------------------------------------------- AI: Wind Wall

## D304: a cheap Wind Wall for the AI. Every legal wall (first hex within 3,
## each heading) is scored against two threats, and the best one is raised:
##  - a RANGED foe (reach 3+) whose straight lines to 2+ of our units (within
##    its move + reach) cross the wall: 8% of each screened unit's max HP;
##  - a MELEE foe within its move + reach of a HURT ally (under 50%) whose
##    straight approach crosses the wall: (10% + 20% x its missing share) of
##    the ally's max HP.
## Scores are in HP, like an attack's expected damage, so they compete.
## Lines are BWHex.line (a stand-in for the path; cheap, not exact). The wall
## isn't raised with a foe in the caster's face (hit it instead), nor while its
## own wall stands. {target, element, score, choice} or {}.
static func ai_wall(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	if not BWWind.walls(b).get(u.id, {}).is_empty():
		return {}
	var foes: Array = b.foes_of(u).filter(func(f): return not BWObelisk.is_objective(f) and f.hp > 0)
	for f in foes:
		if b.gap(u, f) <= 1:
			return {}                                  # a foe in its face: hit it instead
	var mine: Array = b.units.filter(func(o): return o.hp > 0 and o.team == u.team and not BWObelisk.is_objective(o))
	var lanes: Array = []                              # [{hexes, kind, w}]
	for f in foes:
		var reach: int = b.weapon_range(f)
		var span: int = reach + f.move_range()
		if reach >= 3:
			for a in mine:
				var d := b.gap(a, f)
				if d >= 2 and d <= span:
					lanes.append({ "foe": f.id, "line": BWHex.line(f.pos, a.pos).slice(1, -1), "kind": "ranged", "w": 0.08 * a.max_hp() })
		else:
			for a in mine:
				var hurt := float(a.hp) / float(maxi(1, a.max_hp()))
				var d2 := b.gap(a, f)
				if hurt < 0.5 and d2 >= 2 and d2 <= span:
					lanes.append({ "foe": f.id, "line": BWHex.line(f.pos, a.pos).slice(1, -1), "kind": "melee", "w": (0.1 + 0.2 * (1.0 - hurt)) * a.max_hp() })
	if lanes.is_empty():
		return {}
	var best := {}
	for h in b.skill_targets(u, str(row.key), ""):
		for dir in BWWind.wall_dirs(b, h):
			var wall: Array = BWWind.wall_line(b, h, dir)
			if wall.is_empty():
				continue
			var per_foe := {}                          # foe -> [screened ranged lanes, HP]
			var melee := 0.0
			for ln in lanes:
				if not (ln.line as Array).any(func(x): return x in wall):
					continue
				if ln.kind == "ranged":
					var pf: Array = per_foe.get(ln.foe, [0, 0.0])
					per_foe[ln.foe] = [int(pf[0]) + 1, float(pf[1]) + float(ln.w)]
				else:
					melee = maxf(melee, float(ln.w))
			var score := 0.0
			for k in per_foe:
				if int(per_foe[k][0]) >= 2:
					score = maxf(score, float(per_foe[k][1]))
			score = maxf(score, melee)
			if score > 0.0 and (best.is_empty() or score > float(best.score)):
				best = { "target": h, "element": "", "score": score, "choice": BWHex.neighbors(h)[dir] }
	return best

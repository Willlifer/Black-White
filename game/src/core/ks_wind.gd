class_name BWKsWind
extends RefCounted
## D293 wind's keystones (design/ELEMENTS-v3.md §1 "Keystones", ELEMENTS.md
## §16.1). Pure rules on top of BWWind (src/core/wind_modes.gd), which calls
## the hooks here. Who holds what is BWKeystones (Lane C1).
##
## Eye of the Vortex  (D408, reworked: the Vortex fields are gone, D406, and a
##                    gale only spreads) your wind skills' DRAW IN reaches
##                    foes within 2 of the area (not 1) and pulls each up to 2
##                    hexes toward its centre, one hex at a time, stopping at
##                    the first blocked hex: no slam on an inward pull. Still
##                    a direct wind move (once per action, 2 hexes a cycle).
## Wind Wall          the existing action (skill def wind_wall), now granted by
##                    the keystone (the D273 flag is gone).
## Jetstream          wind on a gale 2 makes a gale 3 (copies to radius 3);
##                    the copies of your gales (or that your paint makes) last
##                    2 cycles. (D406: the "Gust fields push 2" rider is gone
##                    with the fields.)
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
const GLAZE_CARRY := 1


static func eye(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, EYE)


static func jet(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, JET)


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


# ---------------------------------------------------------------- Eye of the Vortex (D408)

## Draw in for an Eye holder (BWWind.pre_mode): each candidate (foes within
## EYE_RADIUS of the area) is pulled up to EYE_PULL hexes toward `centre`,
## closest first (ties in setup order). `dry`: positions only (the preview
## restores them). Returns { moves, becalm } like BWWind.apply_mode.
static func eye_draw(b: BWBattle, by: BWUnit, cand: Array, centre: Vector2i, reserved: Array = [], dry: bool = false) -> Dictionary:
	var out := { "moves": [], "becalm": [] }
	var rows: Array = []
	for v in cand:
		if v == null or not v.alive() or BWObelisk.is_objective(v) or maxi(v.size, 1) > 1 or v.pos == centre:
			continue
		rows.append([BWHex.distance(centre, v.pos), b.units.find(v), v])
	rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
	for r in rows:
		if b.over:
			break
		var path := pull_in(b, r[2], centre, EYE_PULL, by, reserved, dry)
		if path.size() > 1:
			out.moves.append({ "unit": (r[2] as BWUnit).id, "path": path, "kind": "pull" })
	return out


## Step `v` toward `centre` one hex at a time, up to `n`, stopping before the
## first blocked or reserved hex (no slam). A direct wind move (once per
## action, the cycle budget). Returns the path walked ([start] = no move).
static func pull_in(b: BWBattle, v: BWUnit, centre: Vector2i, n: int, by: BWUnit, reserved: Array = [], dry: bool = false) -> Array:
	if not BWWind.direct_ready(b, v, dry):
		return [v.pos]
	if b._immune(v, "displace"):
		if not dry:
			b._emit({ "type": "displace_resisted", "unit": v.id, "kind": "pull" })
		return [v.pos]
	if not dry and b._negate(v, "displacement"):
		return [v.pos]
	var m := mini(n, BWWind.budget(b, v))
	var path: Array = [v.pos]
	var cur := v.pos
	for i in m:
		var d := BWBattle.pulse_heading(centre, cur, false)
		if d < 0:
			break
		var nxt: Vector2i = BWHex.neighbors(cur)[d]
		if nxt in reserved or b.board.step_cost(cur, nxt) < 0 or not b.can_stand(v, nxt):
			break
		cur = nxt
		path.append(cur)
	if not dry:
		BWWind._spend(b, v, false, path.size() - 1)
	if path.size() < 2:
		return path
	v.pos = cur
	if not dry:
		b._emit({ "type": "move", "unit": v.id, "path": path, "kind": "pull", "wind": true, "eye": true })
	return path


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

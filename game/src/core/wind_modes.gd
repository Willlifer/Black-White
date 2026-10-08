class_name BWWind
extends RefCounted
## D269-D274 Wind: crowd control (design/ELEMENTS-v3.md §1 with the author's
## rulings of 2026-10-07), simplified by D406-D408 (2026-10-08, the author: "I
## don't really get how wind works. Simplify wind to just one hex type").
## Pure rules; the battle calls the hooks marked "D269" in battle.gd. State
## lives on the units (fx caps) and on BWBattle.wind (walls, squalls), ids and
## numbers only, so clone() copies it.
##
## There is ONE wind tile: the gale marker (BWTiles). It only spreads: when a
## charge lands on it, the charge is copied to its neighbours (gale 2: radius
## 2, Jetstream's gale 3: radius 3), carrying electrified / glaze (D421: no steam)
## (carry). No stored mode, no heading, no field effects (D406).
##
## Wind MOVES units only from actions:
##   * a wind SKILL: its SHAPING (BWWindShape, D365-D370): Part / Blast out /
##     Draw in / Burst out / Push / Hold. Draw in acts before the hits
##     (pre_hit -> pre_mode), the rest after them (BWWindShape.post).
##   * a wind BASIC attack: after a landed, unresisted blow, the target is
##     pushed 1 away from the attacker (after_basic, D407).
## The three moves apply_mode knows (internal kinds, not a unit setting):
##   gust    push 1 away from the origin
##   vortex  pull 1 toward the origin
##   becalm  Becalmed: move 0 until the end of its next turn (it can still
##           act and be displaced); then Restless for 2 turns (immune)
##
## Caps (no loops): wind moves a unit at most CYCLE_HEXES hexes per cycle in
## all; an ambient move (`field`: a squall front, Riptide, Event Horizon) at
## most once per turn (the tick is its own turn); a direct application (skill
## or basic) at most once per action. A push onto glaze stops there (no slides
## since D397). Dark 3 gravity (BWCurse) adds or takes 1 within these caps.
## Weather Gale (BWWeather) moves outside these caps.

const GUST := "gust"
const VORTEX := "vortex"
const BECALM := "becalm"
const CYCLE_HEXES := 2          # wind moves a unit at most this far per cycle
const SLAM_PCT := 8.0           # D143 / v3 §1: a push stopped by rock, a unit, a pillar or a wall
const RESTLESS_TURNS := 2       # the ruling: immune to Becalm for 2 turns after it ends

## D273 Wind Wall (a keystone action; D293: granted by the wind_wall keystone).
const WALL_KEY := "wind_wall"
const WALL_LEN := 3
const WALL_RANGE := 3
const WALL_TICKS := 2
## Lane A hook: extra carriers for gale copies, Callable(b, origin, copies).
static var carry_hooks: Array = []


## Does `u`'s action carry wind? skill element, or the basic's element.
static func is_wind(b: BWBattle, u: BWUnit, skill_el: String = "?") -> bool:
	if skill_el != "?":
		return skill_el == "wind"
	return b.basic_element(u) == "wind"


# ---------------------------------------------------------------- caps

static func _slot(b: BWBattle) -> String:
	return "c%d" % b.cycle if bool(b.wind.get("in_tick", false)) else "t%d" % b._turn_serial


## Hexes of wind movement left to `v` this cycle.
static func budget(b: BWBattle, v: BWUnit) -> int:
	if int(v.fx.get("wind_cycle", -1)) != b.cycle:
		return CYCLE_HEXES
	return maxi(0, CYCLE_HEXES - int(v.fx.get("wind_hexes", 0)))


static func field_ready(b: BWBattle, v: BWUnit) -> bool:
	return str(v.fx.get("wind_slot", "")) != _slot(b) and budget(b, v) > 0


static func direct_ready(b: BWBattle, v: BWUnit, dry: bool = false) -> bool:
	if budget(b, v) <= 0:
		return false
	return dry or int(v.fx.get("wind_act", -1)) != b._action_serial


## v2/D93 Gust and the like: was `v` already moved by wind this action?
static func moved_this_action(b: BWBattle, v: BWUnit) -> bool:
	return int(v.fx.get("wind_act", -1)) == b._action_serial


static func _spend(b: BWBattle, v: BWUnit, field: bool, hexes: int) -> void:
	if field:
		v.fx["wind_slot"] = _slot(b)
	else:
		v.fx["wind_act"] = b._action_serial
	if int(v.fx.get("wind_cycle", -1)) != b.cycle:
		v.fx["wind_cycle"] = b.cycle
		v.fx["wind_hexes"] = 0
	v.fx["wind_hexes"] = int(v.fx.get("wind_hexes", 0)) + hexes


# ---------------------------------------------------------------- moving

## One wind displacement of `v`, `n` hexes along `dir`, under the caps and
## dark 3 gravity. `field` (a field) or direct (a skill / basic). `slam`: a
## push stopped by rock, a unit, a pillar or a wall slams both for SLAM_PCT.
## `reserved`: hexes it may not end on (a leap's landing, a charge's walk).
## `dry`: positions only (the preview restores them), no events, no caps.
## Returns { moved, path, stop, gravity }.
static func push(b: BWBattle, v: BWUnit, dir: int, n: int, kind: String, by: BWUnit, field: bool,
		slam: bool, reserved: Array = [], dry: bool = false, no_gravity: bool = false) -> Dictionary:
	var out := { "moved": false, "path": [v.pos] if v != null else [], "stop": "", "gravity": 0 }
	if v == null or dir < 0 or n <= 0 or not v.alive() or b.over or BWObelisk.is_objective(v):
		return out
	if field and not field_ready(b, v):
		return out
	if not field and not direct_ready(b, v, dry):
		return out
	if b._immune(v, "displace"):
		if not dry:
			b._emit({ "type": "displace_resisted", "unit": v.id, "kind": kind })
		return out
	if not dry and b._negate(v, "displacement"):
		return out
	var g := n if no_gravity else BWCurse.gravity_step(b, v, dir, n)   # D296: Event Horizon pulls exactly 1
	out.gravity = g - n
	var m := mini(g, budget(b, v))
	if not dry:
		_spend(b, v, field, 0)
	if m <= 0:
		return out
	var pp := b.push_path(v, dir, m)
	var path: Array = pp.path
	var stop := str(pp.stop)
	for i in range(1, path.size()):
		if path[i] in reserved:
			path = path.slice(0, i)
			stop = "reserved"
			break
	out.stop = stop
	out.path = path
	if path.size() < 2:
		if slam and not dry and stop in ["rock", "unit"]:
			_slam(b, v, dir, by)
		return out
	v.pos = path[-1]
	out.moved = true
	if dry:
		return out
	_spend(b, v, field, path.size() - 1)
	var e := { "type": "move", "unit": v.id, "path": path, "kind": kind, "wind": true }
	if out.gravity != 0:
		e["gravity"] = out.gravity
	b._emit(e)
	if kind == "push" and not field and by != null and by.team != v.team and BWDuo.has(by, "blizzard"):
		blizzard(b, by, v.pos)                     # D463 Blizzard: the landing hex glazes
	if slam and stop in ["rock", "unit"] and v.alive() and not b.over:
		_slam(b, v, dir, by)
	return out


## D463 Blizzard (wind + ice duo): glaze the hex a pushed foe landed on (an
## empty hex gets a thin glazed sheet of water 1, like Overfreeze's).
static func blizzard(b: BWBattle, by: BWUnit, h: Vector2i) -> void:
	if not b.tiles.can_hold(h) or b.tiles.is_pillar(h) or b.tiles.is_lava(h):
		return
	var e := b.tiles.at(h)
	if not e.is_empty() and str(e.get("marker", "")) != "":
		return
	if e.is_empty():
		e = b.tiles._entry(-1, 0, "", by.id, "spread")
		b.tiles.entries[h] = e
	e.glaze = maxi(int(e.glaze), BWTiles.GLAZE_CYCLES)
	e["glaze_source"] = by.id
	e.permanent = false
	e.erase("seeded")
	b._emit({ "type": "blizzard", "unit": by.id, "hex": h })
	b._emit({ "type": "paint", "unit": by.id, "element": "ice", "hexes": [h], "kind": "lay_on" })


## A wind push stopped short: SLAM_PCT to it and to the unit it hit.
static func _slam(b: BWBattle, v: BWUnit, dir: int, by: BWUnit) -> void:
	var nxt: Vector2i = BWHex.neighbors(v.pos)[dir]
	var o := b.unit_at(nxt)
	var src := by.id if by != null else ""
	b._emit({ "type": "slam", "unit": v.id, "by": src, "into": "unit" if o != null else "rock",
		"name": "Gust", "target": o.id if o != null else "", "hex": v.pos })
	var pv := BWPerkRules.slam_pct(b, v, src, SLAM_PCT, true)      # D281: Crosswind
	if pv > 0.0:
		b._tile_hurt(v, b._tile_dmg(v, pv, ""), "slam", src)
	if o != null and o != v and o.alive() and not b.over:
		var po := BWPerkRules.slam_pct(b, o, src, SLAM_PCT, true)
		if po > 0.0:
			b._tile_hurt(o, b._tile_dmg(o, po, ""), "slam", src)
	BWPerkRules.after_slam(b, v, src, true)       # D281: Crosswind Becalms


## Becalm `v` (a foe of `by`): Restless refuses it. `dry`: would it land?
static func becalm(b: BWBattle, v: BWUnit, by: BWUnit, dry: bool = false) -> bool:
	if v == null or not v.alive() or BWObelisk.is_objective(v):
		return false
	if v.statuses.has("restless"):
		if not dry:
			b._emit({ "type": "status_resisted", "unit": v.id, "status": "becalmed", "reason": "Restless: immune to Becalm" })
		return false
	if dry:
		return true
	b._add_status(v, "becalmed", by, 1)
	if v.statuses.has("becalmed"):
		b._emit({ "type": "becalm", "unit": v.id, "hex": v.pos, "by": by.id if by != null else "" })
		return true
	return false


## Apply mode `m` once to `units` about `origin`. Gust: farthest first, Vortex:
## closest first, ties in setup order (D143). Returns [{unit, path, kind}] of
## the moves made, plus { becalm: [ids] } as the last element's sibling key.
static func apply_mode(b: BWBattle, by: BWUnit, m: String, units: Array, origin: Vector2i, field: bool,
		heading: int = -1, reserved: Array = [], dry: bool = false) -> Dictionary:
	var out := { "moves": [], "becalm": [] }
	var rows: Array = []
	for v in units:
		if v != null and v.alive() and not BWObelisk.is_objective(v):
			rows.append([BWHex.distance(origin, v.pos), b.units.find(v), v])
	rows.sort_custom(func(a, c) -> bool:
		if a[0] != c[0]:
			return a[0] > c[0] if m == GUST else a[0] < c[0]
		return a[1] < c[1])
	for r in rows:
		var v: BWUnit = r[2]
		if b.over or not v.alive():
			continue
		match m:
			BECALM:
				if becalm(b, v, by, dry):
					out.becalm.append(v.id)
			GUST:
				var dir := heading if v.pos == origin else BWBattle.pulse_heading(origin, v.pos, true)
				if v.pos != origin and dir < 0:
					dir = BWHex.direction_index(origin, v.pos)
				if v.pos == origin and dir < 0 and by != null:
					dir = BWHex.direction_index(by.pos, v.pos)
				var res := push(b, v, dir, 1, "push", by, field, true, reserved, dry)
				if res.moved:
					out.moves.append({ "unit": v.id, "path": res.path, "kind": "push" })
			VORTEX:
				if v.pos == origin:
					continue
				var res2 := push(b, v, BWBattle.pulse_heading(origin, v.pos, false), 1, "pull", by, field, false, reserved, dry)
				if res2.moved:
					out.moves.append({ "unit": v.id, "path": res2.path, "kind": "pull" })
	return out


# ---------------------------------------------------------------- wind on every weapon (the ruling)

## The origin of a skill's mode: the shape's centre for ground-aimed and
## leap skills, else the caster.
static func skill_origin(u: BWUnit, s: Dictionary, target_hex: Vector2i) -> Vector2i:
	return target_hex if str(s.get("targeting", "")) in ["hex", "leap"] else u.pos


## D365: a wind skill's SHAPING (BWWindShape, src/core/wind_shape.gd) picks
## what its wind does; only Draw in acts here, before the hits (pre_mode with
## Vortex); the rest land after them (BWWindShape.post). Returns {} or
## { moves, becalm, restore: [[unit, pos]], origin, mode, shaping }.
static func pre_hit(b: BWBattle, u: BWUnit, s: Dictionary, p: Dictionary, target_hex: Vector2i, dry: bool = false) -> Dictionary:
	if str(p.get("element", "")) != "wind" or not u.alive():
		return {}
	return BWWindShape.pre(b, u, s, p, target_hex, dry)


## Mode `m` BEFORE a skill's hits: once, on the foes in or beside its
## shape. Foes that end in the shape join the victims. `dry` (skill_preview):
## positions only; the caller restores them with restore(). (D271; since D365
## only Draw in, with Vortex.)
static func pre_mode(b: BWBattle, u: BWUnit, s: Dictionary, p: Dictionary, target_hex: Vector2i, m: String, dry: bool = false) -> Dictionary:
	var origin := skill_origin(u, s, target_hex)
	var shape: Array = (p.hexes as Array) + (p.get("ring", []) as Array)
	for v in p.victims:
		shape.append_array(v.footprint())
	if shape.is_empty():
		shape = [target_hex]
	var eye := m == VORTEX and BWKsWind.eye(u)        # D408 Eye of the Vortex: Draw in reaches 2, pulls up to 2
	var zone := {}
	for h in BWHex.fringe(shape, BWKsWind.EYE_RADIUS if eye else 1):
		zone[h] = true
	var reserved: Array = (p.get("walk", []) as Array).duplicate()
	if p.dest != u.pos:
		reserved.append(p.dest)
	var shoved: BWUnit = null
	if not (p.shove as Dictionary).is_empty():
		shoved = p.shove.unit
		reserved.append(p.shove.to)
	var cand: Array = []
	for f in b.foes_of(u):
		if f == shoved or not b.can_harm(u, f) or maxi(f.size, 1) > 1:
			continue
		if zone.has(f.pos):
			cand.append(f)
	var restore: Array = []
	for f in cand:
		restore.append([f, f.pos])
	var res := BWKsWind.eye_draw(b, u, cand, origin, reserved, dry) if eye else apply_mode(b, u, m, cand, origin, false, -1, reserved, dry)
	res["restore"] = restore
	res["origin"] = origin
	res["mode"] = m
	# whoever now stands in the shape is hit; whoever was hit still is
	var hit_hexes := {}
	for h in (p.hexes as Array) + (p.get("ring", []) as Array):
		hit_hexes[h] = true
	for f in cand:
		if f in p.victims or not f.alive():
			continue
		if hit_hexes.has(f.pos):
			p.victims.append(f)
	if not res.moves.is_empty() or not res.becalm.is_empty():
		var nm := ("Eye of the Vortex" if eye else "Draw in") if m == VORTEX else m.capitalize()   # D365: only Draw in comes here
		(p.notes as Array).append("%s first: %s" % [nm, _summary(res)])
	return res


static func restore(pre: Dictionary) -> void:
	var rows: Array = pre.get("restore", [])
	rows.reverse()
	for r in rows:
		(r[0] as BWUnit).pos = r[1]
	pre.erase("restore")


static func _summary(res: Dictionary) -> String:
	var bits: PackedStringArray = []
	var pushed := (res.moves as Array).filter(func(x): return x.kind == "push").size()
	var pulled := (res.moves as Array).filter(func(x): return x.kind == "pull").size()
	if pushed > 0:
		bits.append("%d pushed 1" % pushed)
	if pulled > 0:
		bits.append("%d pulled in" % pulled)
	if not (res.becalm as Array).is_empty():
		bits.append("%d Becalmed" % (res.becalm as Array).size())
	return ", ".join(bits)


## D407: a wind basic attack pushes its target 1 away from the attacker
## after a landed, unresisted blow (v3 §1 direct hits; a Blank takes no
## element). No mode: the push is the only thing a wind basic does.
static func after_basic(b: BWBattle, u: BWUnit, target: BWUnit, first: Dictionary) -> void:
	if b.over or not u.alive() or target == null or not target.alive() or first.is_empty():
		return
	if b.basic_element(u) != "wind" or not first.get("hit", false) or not first.get("secondary", false):
		return
	if BWFormulas.strips_element(target):
		return
	apply_mode(b, u, GUST, [target], u.pos, false)


# ---------------------------------------------------------------- gales (D406: spread only)

## Before a paint: the gale markers on the painted hexes (their owner is
## gone once they fire; Jetstream and the squall read it).
static func before_paint(b: BWBattle, hexes: Array) -> Dictionary:
	var snap := {}
	for h in hexes:
		var e := b.tiles.at(h)
		if str(e.get("marker", "")) == "gale":
			snap[h] = e.duplicate()
	return snap


## After a paint: the copies of every gale that fired carry the origin's
## reaction states (electrified, glaze; D421: no steam); Jetstream's copies last 2.
static func after_paint(b: BWBattle, _by: BWUnit, _element: String, r: Dictionary, snap: Dictionary) -> void:
	for g in r.get("gales", []):
		carry(b, g.origin, g.copies)


## Gale copies carry the origin's reaction state (v3 §1 "Spreading,
## extended"): electrified (joins the origin's field) from BWTiles.shock /
## fields when they exist (D421: steam is gone); glaze is a
## D293/D398 glaze carry (a gale beside glaze, BWKsWind.carry_glaze). Plus any
## `carry_hooks` Lane A registers.
static func carry(b: BWBattle, origin: Vector2i, copies: Array) -> void:
	if copies.is_empty():
		return
	var t := b.tiles
	var shock = t.get("shock")
	var fields = t.get("fields")
	if shock is Dictionary and fields is Dictionary and (shock as Dictionary).has(origin):
		var fid = shock[origin]
		if (fields as Dictionary).has(fid):
			var fr: Dictionary = fields[fid]
			for c in copies:
				if not shock.has(c):
					shock[c] = fid
					if fr.has("hexes") and not c in fr.hexes:
						(fr.hexes as Array).append(c)
	BWKsWind.carry_glaze(b, origin, copies)      # D293/D398: a gale beside glaze glazes its water copies (1 cycle)
	for hook in carry_hooks:
		if (hook as Callable).is_valid():
			(hook as Callable).call(b, origin, copies)


## The cycle tick (v3 "the new tick", step 2), before the tiles decay: the
## squall fronts advance, then Lane C's Event Horizon (BWCurse.tick), the
## keystone ticks, then the walls count down. (D406: no vortex fields.)
static func tick(b: BWBattle) -> void:
	b.wind["in_tick"] = true
	if not b.over:
		BWSquall.tick(b)                              # D309: every squall front advances one ring
	if not b.over:
		BWCurse.tick(b)
	if not b.over:
		BWKeystoneFx.tick(b)                          # D294/D295: Wellspring heals, Frozen thaws
	b.wind["in_tick"] = false
	var walls: Dictionary = b.wind.get("walls", {})
	for k in walls.keys():
		walls[k].ticks = int(walls[k].ticks) - 1
		if int(walls[k].ticks) <= 0:
			walls.erase(k)
			b._emit({ "type": "wind_wall_end", "unit": k })


# ---------------------------------------------------------------- Becalmed / Restless

## At `u`'s turn end, before the D87 status sweep: Restless counts down; an
## armed Becalmed ends and leaves Restless for RESTLESS_TURNS turns.
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	var rs: Dictionary = u.statuses.get("restless", {})
	if not rs.is_empty() and rs.armed:
		rs.turns = int(rs.turns) - 1
		if int(rs.turns) <= 0:
			u.statuses.erase("restless")
			b._emit({ "type": "status_end", "unit": u.id, "status": "restless" })
	var bc: Dictionary = u.statuses.get("becalmed", {})
	if not bc.is_empty() and bc.armed:
		u.statuses.erase("becalmed")
		b._emit({ "type": "status_end", "unit": u.id, "status": "becalmed" })
		u.statuses["restless"] = { "armed": false, "keep": true, "turns": RESTLESS_TURNS, "source": "" }
		b._emit({ "type": "status", "unit": u.id, "status": "restless", "label": BWSkills.STATUS.restless[0],
			"rule": BWSkills.STATUS.restless[1], "by": "" })


# ---------------------------------------------------------------- D273 Wind Wall

static func has_wind_wall(_u: BWUnit) -> bool:
	return false                                   # D443: Wind Wall was removed with its keystone (the wall rules stay, unused)


## Keystone actions `u` fights with (BWBattle.skills_for adds them). D443:
## the v3 keystones' menu rows (BWKeystones.skills: Pitch Black, Solar Flare,
## Superconductor's Self-detonate).
static func keystone_actions(u: BWUnit) -> Array:
	if u == null:
		return []
	return BWKeystones.skills(u)


static func walls(b: BWBattle) -> Dictionary:
	return b.wind.get("walls", {})


static func walled(b: BWBattle, h: Vector2i) -> bool:
	for k in walls(b):
		if h in walls(b)[k].hexes:
			return true
	return false


static func wall_hexes(b: BWBattle) -> Array:
	var out: Array = []
	for k in walls(b):
		out.append_array(walls(b)[k].hexes)
	return out


## The 3-hex line from `start` heading `dir`, if every hex is empty ground
## (on the map, passable, no unit, no pillar or wall); else [].
static func wall_line(b: BWBattle, start: Vector2i, dir: int) -> Array:
	var out: Array = []
	var cur := start
	for i in WALL_LEN:
		if i > 0:
			cur = BWHex.neighbors(cur)[dir]
		if not b.board.is_passable(cur) or b.board.blocked(cur) or b.unit_at(cur) != null:
			return []
		out.append(cur)
	return out


## Headings from `start` that make a legal wall.
static func wall_dirs(b: BWBattle, start: Vector2i) -> Array:
	var out: Array = []
	for d in 6:
		if not wall_line(b, start, d).is_empty():
			out.append(d)
	return out


## Raise `u`'s wall (its old one comes down: one per unit).
static func raise_wall(b: BWBattle, u: BWUnit, hexes: Array) -> void:
	if not b.wind.has("walls"):
		b.wind["walls"] = {}
	if b.wind.walls.has(u.id):
		b.wind.walls.erase(u.id)
		b._emit({ "type": "wind_wall_end", "unit": u.id })
	b.wind.walls[u.id] = { "hexes": hexes.duplicate(), "ticks": WALL_TICKS }
	b._emit({ "type": "wind_wall", "unit": u.id, "hexes": hexes.duplicate(), "ticks": WALL_TICKS })


## Walls block skills both ways: no target on a wall or past one (the
## straight line from the caster crosses it). Basic attacks pierce (they never
## come here: in_range is untouched).
static func filter_targets(b: BWBattle, u: BWUnit, out: Array[Vector2i], s: Dictionary) -> Array[Vector2i]:
	if walls(b).is_empty() or str(s.get("targeting", "")) == "self":
		return out
	var wh := {}
	for h in wall_hexes(b):
		wh[h] = true
	var keep: Array[Vector2i] = []
	for h in out:
		if wh.has(h):
			continue
		var crossed := false
		var line := BWHex.line(u.pos, h)
		for i in range(1, line.size() - 1):
			if wh.has(line[i]):
				crossed = true
				break
		if not crossed:
			keep.append(h)
	return keep


## The board's dynamic blocker gains the walls (composed with Lane A's
## pillars). Idempotent; re-composes if someone replaced the blocker since.
static func hook_board(b: BWBattle) -> void:
	var bd := b.board
	if bd.has_meta("bw_wind_blocker") and bd.blocker == bd.get_meta("bw_wind_blocker"):
		return
	var prev: Callable = bd.blocker
	var wr: WeakRef = weakref(b)                       # the board must not keep its battle alive
	var f := func(h: Vector2i) -> bool:
		if prev.is_valid() and bool(prev.call(h)):
			return true
		var bb = wr.get_ref()
		return bb != null and walled(bb, h)
	bd.blocker = f
	bd.set_meta("bw_wind_blocker", f)


## The tile card's lines for `h` (plain text; the view colours them).
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var ge := b.tiles.at(h)                        # D377: a Tailwind holder's gale lifts its team (the perk's rider, not the tile)
	if str(ge.get("marker", "")) == "gale":
		var o := b._unit(str(ge.get("source", "")))
		if o != null and BWWeaponMove.has_updraft(o):
			out.append("Updraft (%s's Tailwind): %s's side starting a turn here gets +1 jump" % [o.name, o.name])
	if walled(b, h):
		for k in walls(b):
			if h in walls(b)[k].hexes:
				out.append("Wind Wall: blocks moves and skills both ways (basic attacks pierce); %d tick%s left" % [
					int(walls(b)[k].ticks), "" if int(walls(b)[k].ticks) == 1 else "s"])
	return out

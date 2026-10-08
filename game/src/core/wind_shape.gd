class_name BWWindShape
extends RefCounted
## D365-D370 Wind shaping: a wind-tagged SKILL no longer carries the abstract
## Gust / Vortex / Becalm mode. Once its target is picked, the confirm step
## offers options that follow the skill's SHAPE (design/ELEMENTS.md §18):
##
##   line    (Ley Line, Tridentpierce, Energized Shot, Earthsplitter,
##            Shockwave Palm, Lunge)
##             part_left / part_right  the foes ON the line are pushed 1 to
##                                     that side of it (the caster's left /
##                                     right, looking down the line)
##             blast                   the foes on or beside the line are
##                                     pushed 1 away from it
##   area    (Surge, Tempest, Rain of Arrows, Arcing Shot, Whirlwind Blade,
##            Fan of Knives, Cleave, Sweep, the leaps; any "hex" skill)
##             draw   BEFORE the hits: the foes in or beside the area are
##                    pulled 1 toward its centre (more of them are caught)
##             burst  AFTER the hits: the foes in the area are pushed 1 away
##                    from its centre
##   single  (everything aimed at one unit, and Charge)
##             push   the target is pushed 1 along a chosen heading (0-5,
##                    stored relative to "straight away from the caster")
##   every shape
##             hold   the foes it touches are Becalmed (move 0; Restless after)
##
## Everything but Draw in lands after the hits and the paint (§7.3: hit,
## paint, pushes, slams), through BWWind.push: the D272 caps (once per
## action, 2 hexes a cycle), dark 3 gravity and 8% slams
## all apply unchanged. Only foes are moved (the D271 ruling).
##
## The choice is remembered per unit and skill (`BWUnit.wind_shapes[key] =
## {opt, rel}`); with nothing stored it follows the unit's basic wind mode
## (gust → blast / push away, vortex → blast / pull in, becalm → hold;
## an area draws in under gust and vortex alike, D383). A gale the skill lays takes the shaping's equivalent mode
## (field_mode). Basic attacks keep the three modes (BWWind).

const LINE := "line"
const AREA := "area"
const SINGLE := "single"

const PART_LEFT := "part_left"
const PART_RIGHT := "part_right"
const BLAST := "blast"
const DRAW := "draw"
const BURST := "burst"
const PUSH := "push"
const HOLD := "hold"

const OPTIONS := {
	"line": ["part_left", "part_right", "blast", "hold"],
	"area": ["draw", "burst", "hold"],
	"single": ["push", "hold"],
}
const NAMES := {
	"part_left": "Part left", "part_right": "Part right", "blast": "Blast out",
	"draw": "Draw in", "burst": "Burst out", "push": "Push", "hold": "Hold",
}
const RULES := {
	"part_left": "foes on the line are pushed 1 to its left",
	"part_right": "foes on the line are pushed 1 to its right",
	"blast": "foes on or beside the line are pushed 1 away from it",
	"draw": "before the hit, foes in or beside the area are pulled 1 toward its centre",
	"burst": "after the hit, foes in the area are pushed 1 away from its centre",
	"push": "after the hit, the target is pushed 1 the way the arrow points",
	"hold": "the foes it touches are Becalmed: move 0 until their next turn ends",
}
## The line skills, by key (every other shape is read from the row).
const LINE_KEYS := ["ley_line", "tridentpierce", "energized_shot", "earthsplitter", "shockwave_palm", "lunge"]
## Push headings tried first, as offsets from "straight away" (ties).
const REL_ORDER := [0, 1, 5, 2, 4, 3]
const AI_MAX := 4                     # simulated options per skill (v3 §11)
const HOLD_AI := 3.0                  # the AI's worth of one Becalm (HP-ish units)


# ---------------------------------------------------------------- shapes and choices

## "line", "area", "single", or "" (a skill that can't carry wind, or has no shape).
static func kind_of(key: String) -> String:
	var s := BWSkills.get_skill(key)
	if s.is_empty() or not bool(s.get("needs_element", false)):
		return ""
	if key in LINE_KEYS:
		return LINE
	var aoe := bool(s.get("aoe", false)) or int(s.get("radius", 0)) > 0
	match str(s.get("targeting", "")):
		"hex", "leap":
			return AREA
		"self":
			return AREA if aoe else ""
		"dir":
			return AREA if aoe else SINGLE
		"unit", "adjacent_unit":
			return SINGLE
	return ""


static func options(kind: String) -> Array:
	return OPTIONS.get(kind, [])


## The option list as the UI cycles it (single: one Push per heading is too
## many to cycle; the push heading is its own control).
static func default_choice(u: BWUnit, kind: String) -> Dictionary:
	var m := BWWind.mode(u)
	if m == BWWind.BECALM:
		return { "opt": HOLD, "rel": 0 }
	match kind:
		AREA:
			return { "opt": DRAW, "rel": 0 }                # D383: areas default to Draw in (was Burst out under Gust, D365)
		LINE:
			return { "opt": BLAST, "rel": 0 }
		SINGLE:
			return { "opt": PUSH, "rel": 3 if m == BWWind.VORTEX else 0 }
	return { "opt": HOLD, "rel": 0 }


## `u`'s shaping for skill `key` (stored, else its default).
static func choice(u: BWUnit, key: String) -> Dictionary:
	var k := kind_of(key)
	if u == null or k == "":
		return {}
	var c: Dictionary = u.wind_shapes.get(key, {})
	if c.is_empty() or not str(c.get("opt", "")) in options(k):
		return default_choice(u, k)
	return { "opt": str(c.opt), "rel": posmod(int(c.get("rel", 0)), 6) }


static func set_choice(u: BWUnit, key: String, opt: String, rel: int = 0) -> void:
	if u == null or not opt in options(kind_of(key)):
		return
	u.wind_shapes[key] = { "opt": opt, "rel": posmod(rel, 6) }


## Re-simulation key for the readability cache (mode + every stored shaping).
static func sig(u: BWUnit) -> String:
	if u == null:
		return ""
	return BWWind.mode(u) + "|" + var_to_str(u.wind_shapes)


# ---------------------------------------------------------------- geometry

static func _w(h: Vector2i) -> Vector2:
	return BWHex.to_world(h)


## The centre of an area skill: the aimed hex for ground-aimed and leap
## skills, else the caster (self rings, Cleave and Sweep arcs).
static func centre(u_pos: Vector2i, s: Dictionary, target: Vector2i) -> Vector2i:
	return target if str(s.get("targeting", "")) in ["hex", "leap"] else u_pos


## A line skill's spine: the hexes on its axis (Tridentpierce: the 3-hex
## spine, not its fringe; Lunge: the dash and the struck hex).
static func spine(b: BWBattle, u_pos: Vector2i, key: String, target: Vector2i, p: Dictionary) -> Array:
	var out: Array = []
	if key == "tridentpierce":
		out = Array(b.board.ray(u_pos, target, BWSkills.TRIDENT_LEN))
	else:
		for h in (p.get("walk", []) as Array) + (p.get("hexes", []) as Array):
			if not h in out:
				out.append(h)
		for v in p.get("victims", []):
			if not v.pos in out and BWHex.distance(u_pos, v.pos) > 0:
				out.append(v.pos)
	out.erase(u_pos)
	return out


## The line's forward heading (world XZ, unit length): caster → aimed hex.
static func forward(u_pos: Vector2i, target: Vector2i) -> Vector2:
	var f := _w(target) - _w(u_pos)
	return f.normalized() if f.length() > 0.001 else Vector2(1, 0)


## The caster's left, looking down the line (world XZ; Y up).
static func left_of(fwd: Vector2) -> Vector2:
	return Vector2(fwd.y, -fwd.x)


## Which side of the line `h` stands: +1 left, -1 right, 0 on its axis.
static func side_of(u_pos: Vector2i, fwd: Vector2, h: Vector2i) -> int:
	var d := (_w(h) - _w(u_pos)).dot(left_of(fwd))
	if d > 0.25:
		return 1
	if d < -0.25:
		return -1
	return 0


## The neighbour heading that best leaves the line toward `side` (+1 left,
## -1 right); of the two 30°-off headings, the one leaning forward.
static func side_dir(fwd: Vector2, side: int) -> int:
	var want := left_of(fwd) * float(side)
	var best := 0
	var best_s := -INF
	for i in 6:
		var v := _dir_vec(i)
		var s := v.dot(want) + 0.01 * v.dot(fwd)
		if s > best_s + 1e-6:
			best_s = s
			best = i
	return best


## The world vector of heading `i` (the same from every hex in odd-r).
static func _dir_vec(i: int) -> Vector2:
	var h := Vector2i(0, 0)
	return (_w(BWHex.neighbors(h)[i]) - _w(h)).normalized()


## The heading closest to world vector `v`.
static func dir_toward(v: Vector2) -> int:
	var best := 0
	var best_s := -INF
	for i in 6:
		var s := _dir_vec(i).dot(v)
		if s > best_s + 1e-6:
			best_s = s
			best = i
	return best


## "Straight away from the caster" for a single target (the rel-0 heading).
static func away_dir(u_pos: Vector2i, at: Vector2i) -> int:
	var d := BWBattle.pulse_heading(u_pos, at, true)
	if d < 0:
		d = BWHex.direction_index(u_pos, at)
	return maxi(d, 0)


## A single target's push heading for `rel`.
static func push_dir(u_pos: Vector2i, at: Vector2i, rel: int) -> int:
	return posmod(away_dir(u_pos, at) + rel, 6)


# ---------------------------------------------------------------- the skill (battle hooks)

## BWWind.pre_hit: record the action's shaping (not dry) and, for Draw in,
## pull before the hits. Returns {} or the pre_hit dictionary (moves, becalm,
## restore, origin, mode, shaping).
static func pre(b: BWBattle, u: BWUnit, s: Dictionary, p: Dictionary, target_hex: Vector2i, dry: bool) -> Dictionary:
	var key := str(s.get("key", ""))
	var k := kind_of(key)
	if k == "":
		return {}
	var ch := choice(u, key)
	var opt := str(ch.opt)
	if not dry:
		var ctx := { "unit": u.id, "key": key, "kind": k, "opt": opt, "rel": int(ch.rel), "act": b._action_serial,
			"from": u.pos, "target": target_hex, "centre": centre(u.pos, s, target_hex) }
		if k == LINE:
			ctx["spine"] = spine(b, u.pos, key, target_hex, p)
		elif k == SINGLE:
			var at: Vector2i = (p.victims[0] as BWUnit).pos if not (p.victims as Array).is_empty() else target_hex
			ctx["dir"] = push_dir(u.pos, at, int(ch.rel))
		b.wind["shape"] = ctx
	if opt == DRAW:
		var res := BWWind.pre_mode(b, u, s, p, target_hex, BWWind.VORTEX, dry)
		res["shaping"] = opt
		return res
	return { "moves": [], "becalm": [], "restore": [], "origin": centre(u.pos, s, target_hex), "mode": field_equiv(opt), "shaping": opt }


## The live shaping of `by`'s action now ({} outside it).
static func active(b: BWBattle, by: BWUnit) -> Dictionary:
	var ctx: Dictionary = b.wind.get("shape", {})
	if ctx.is_empty() or by == null or str(ctx.get("unit", "")) != by.id or int(ctx.get("act", -1)) != b._action_serial:
		return {}
	return ctx


## The field mode a shaping lays (gales the skill paints keep it).
static func field_equiv(opt: String) -> String:
	match opt:
		DRAW: return BWWind.VORTEX
		HOLD: return BWWind.BECALM
	return BWWind.GUST


## BWWind.after_paint: the mode a gale laid by `by` now stores.
static func field_mode(b: BWBattle, by: BWUnit) -> String:
	var ctx := active(b, by)
	return field_equiv(str(ctx.opt)) if not ctx.is_empty() else BWWind.mode(by)


## The heading of a gust gale laid on `h` (-1 = BWWind's default: away from
## the caster). Part: the parting side; Push: the push heading.
static func field_heading(b: BWBattle, by: BWUnit, _h: Vector2i) -> int:
	var ctx := active(b, by)
	if ctx.is_empty():
		return -1
	match str(ctx.opt):
		PART_LEFT, PART_RIGHT:
			return side_dir(forward(ctx.from, ctx.target), 1 if str(ctx.opt) == PART_LEFT else -1)
		PUSH:
			return int(ctx.get("dir", -1))
	return -1


## After the hits and the paint (battle.use_skill): every option but Draw in
## lands here, once. Emits "wind_shape" { unit, opt, moves: [{unit, from, to,
## hazard: [[label, pct]]}], becalm: [ids] } for the preview and the log.
static func post(b: BWBattle, u: BWUnit, s: Dictionary, p: Dictionary) -> void:
	var ctx := active(b, u)
	b.wind.erase("shape")
	if ctx.is_empty() or b.over or not u.alive():
		return
	var opt := str(ctx.opt)
	if opt == DRAW:
		return
	var moves: Array = []
	var becalm: Array = []
	match str(ctx.kind):
		AREA:
			var area := {}
			for h in (p.hexes as Array) + (p.get("ring", []) as Array):
				area[h] = true
			var who := _foes(b, u, func(f): return area.has(f.pos))
			if opt == HOLD:
				becalm = _hold(b, u, who)
			else:
				var r := BWWind.apply_mode(b, u, BWWind.GUST, who, ctx.centre, false)
				moves = r.moves
		LINE:
			var sp: Array = ctx.get("spine", [])
			var on := {}
			for h in sp:
				on[h] = true
			var near := {}
			for h in BWHex.fringe(sp, 1):
				if h != ctx.from:
					near[h] = true
			var fwd := forward(ctx.from, ctx.target)
			match opt:
				HOLD:
					becalm = _hold(b, u, _foes(b, u, func(f): return on.has(f.pos)))
				PART_LEFT, PART_RIGHT:
					var d := side_dir(fwd, 1 if opt == PART_LEFT else -1)
					for f in _by_reach(_foes(b, u, func(f): return on.has(f.pos)), ctx.from):
						_one(b, u, f, d, moves)
				BLAST:
					var who := _foes(b, u, func(f): return near.has(f.pos))
					who.sort_custom(func(a, c) -> bool:      # the outer ring first, so the inner has room
						var da := 0 if on.has(a.pos) else 1
						var dc := 0 if on.has(c.pos) else 1
						if da != dc:
							return da > dc
						var ra := BWHex.distance(ctx.from, a.pos)
						var rc := BWHex.distance(ctx.from, c.pos)
						if ra != rc:
							return ra > rc
						return b.units.find(a) < b.units.find(c))
					for f in who:
						_one(b, u, f, blast_dir(b, f, ctx.from, fwd, on), moves)
		SINGLE:
			var who: Array = (p.victims as Array).filter(func(v): return v.alive() and v.team != u.team and maxi(v.size, 1) <= 1)
			if opt == HOLD:
				becalm = _hold(b, u, who)
			else:
				for f in who:
					_one(b, u, f, int(ctx.get("dir", 0)), moves)
	var rows: Array = []
	for m in moves:
		var v := b._unit(str(m.unit))
		if v == null:
			continue
		var path: Array = m.path
		rows.append({ "unit": v.id, "from": path[0], "to": v.pos, "hazard": hazard(b, v, v.pos) })
	b._emit({ "type": "wind_shape", "unit": u.id, "skill": str(s.get("key", "")), "opt": opt, "moves": rows, "becalm": becalm })


## Where one foe on or beside the line goes under Blast out: beside it,
## straight out on its side; past an end, on along the line; on it, to the
## open side (left first; neither open: left, and it slams).
static func blast_dir(b: BWBattle, f: BWUnit, from: Vector2i, fwd: Vector2, on: Dictionary) -> int:
	var sd := side_of(from, fwd, f.pos)
	if not on.has(f.pos):
		if sd != 0:
			return side_dir(fwd, sd)
		return dir_toward(fwd if (_w(f.pos) - _w(from)).dot(fwd) >= 0.0 else -fwd)
	for side in [1, -1]:
		var d := side_dir(fwd, side)
		if (b.push_path(f, d, 1).path as Array).size() > 1:
			return d
	return side_dir(fwd, 1)


static func _foes(b: BWBattle, u: BWUnit, keep: Callable) -> Array:
	var out: Array = []
	for f in b.foes_of(u):
		if f.alive() and b.can_harm(u, f) and maxi(f.size, 1) <= 1 and not BWObelisk.is_objective(f) and keep.call(f):
			out.append(f)
	return out


static func _by_reach(who: Array, from: Vector2i) -> Array:
	var rows := who.duplicate()
	rows.sort_custom(func(a, c) -> bool:
		var ra := BWHex.distance(from, a.pos)
		var rc := BWHex.distance(from, c.pos)
		return ra > rc if ra != rc else str(a.id) < str(c.id))
	return rows


static func _one(b: BWBattle, u: BWUnit, f: BWUnit, d: int, moves: Array) -> void:
	if b.over or not f.alive():
		return
	var r := BWWind.push(b, f, d, 1, "push", u, false, true)
	if r.moved:
		moves.append({ "unit": f.id, "path": r.path, "kind": "push" })


static func _hold(b: BWBattle, u: BWUnit, who: Array) -> Array:
	var out: Array = []
	for f in who:
		if BWWind.becalm(b, f, u):
			out.append(f.id)
	return out


## What landing on `h` costs `v` by its next turn (the preview's warning):
## [[label, pct]]: fire, dark 3, an electrified field, a gust field.
static func hazard(b: BWBattle, v: BWUnit, h: Vector2i) -> Array:
	var out: Array = []
	var st := b.tiles.standing(h)
	if float(st.fire) > 0.0:
		out.append(["FIRE", float(st.fire)])
	if float(st.drain) > 0.0:
		out.append(["DARK", float(st.drain)])
	var sh := BWPools.hazard_pct(b, v, h) * 0.5
	if sh > 0.0:
		out.append(["SHOCK", sh])
	var f := BWWind.field_at(b, h)
	if not f.is_empty() and str(f.mode) == BWWind.GUST:
		out.append(["GUST FIELD", 0.0])
	return out


# ---------------------------------------------------------------- AI (D368)

## The options worth simulating for `u`'s skill at `target`, at most AI_MAX:
## [{opt, rel}]. Single targets: the three cheapest-best push headings
## (a slam, a hazard; else straight away and its neighbours), then Hold.
static func ai_options(b: BWBattle, u: BWUnit, key: String, target: Vector2i) -> Array:
	var k := kind_of(key)
	var out: Array = []
	match k:
		LINE, AREA:
			for o in options(k):
				out.append({ "opt": o, "rel": 0 })
		SINGLE:
			var v := b.unit_at(target)
			if v != null and v.team != u.team:
				var rows: Array = []
				for i in REL_ORDER.size():
					var rel: int = REL_ORDER[i]
					var d := push_dir(u.pos, v.pos, rel)
					var pp := b.push_path(v, d, 1)
					var sc := 0.0
					if str(pp.stop) in ["rock", "unit"]:
						sc += BWWind.SLAM_PCT
					elif (pp.path as Array).size() > 1:
						for hz in hazard(b, v, pp.path[-1]):
							sc += float(hz[1])
					rows.append([sc, i, rel])
				rows.sort_custom(func(a, c) -> bool: return a[0] > c[0] if a[0] != c[0] else a[1] < c[1])
				for r in rows.slice(0, AI_MAX - 1):
					out.append({ "opt": PUSH, "rel": int(r[2]) })
			out.append({ "opt": HOLD, "rel": 0 })
	return out.slice(0, AI_MAX)


## Simulate each option once and keep the best (damage to foes minus damage
## to its own side, plus foes left on hazards and Becalms; ties keep the
## first, the unit's stored choice). Stores the pick on the unit.
static func ai_refine(b: BWBattle, u: BWUnit, key: String, el: String, target: Vector2i) -> void:
	if el != "wind" or kind_of(key) == "":
		return
	var first := choice(u, key)
	var opts: Array = [first]
	for o in ai_options(b, u, key, target):
		if not (str(o.opt) == str(first.opt) and int(o.rel) == int(first.rel)):
			opts.append(o)
	opts = opts.slice(0, AI_MAX)
	var best := first
	var best_s := -INF
	for o in opts:
		set_choice(u, key, str(o.opt), int(o.rel))
		var sim := b.simulate(u, { "kind": "skill", "key": key, "element": el, "hex": target })
		if sim.is_empty():
			continue
		var sc := ai_value(b, sim)
		if sc > best_s + 0.5:
			best_s = sc
			best = o
	set_choice(u, key, str(best.opt), int(best.rel))


## One simulation's worth to the actor's side.
static func ai_value(b: BWBattle, sim: Dictionary) -> float:
	var sc := 0.0
	for id in sim.units:
		var rec: Dictionary = sim.units[id]
		var d := float(rec.get("damage", 0))
		sc += -d if bool(rec.get("friendly", false)) else d
	for e in sim.get("events", []):
		if str(e.get("type", "")) != "wind_shape":
			continue
		for m in e.moves:
			var v := b._unit(str(m.unit))
			if v == null:
				continue
			for hz in m.hazard:
				sc += float(hz[1]) * v.max_hp() / 100.0 * (1.0 if v.team != str(sim.team) else -1.0)
		sc += HOLD_AI * (e.becalm as Array).size()
	return sc


# ---------------------------------------------------------------- words

## The confirm strip's one-line rule for an option.
static func rule(opt: String) -> String:
	return str(RULES.get(opt, ""))


static func label(opt: String) -> String:
	return str(NAMES.get(opt, opt))

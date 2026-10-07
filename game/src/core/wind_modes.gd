class_name BWWind
extends RefCounted
## D269-D274 Wind: crowd control (design/ELEMENTS-v3.md §1 with the author's
## rulings of 2026-10-07). Pure rules; the battle calls the hooks marked
## "D269" in battle.gd. State lives on the units (`wind_mode`, fx caps) and on
## BWBattle.wind (walls), ids and numbers only, so clone() copies it.
##
## Modes (`BWUnit.wind_mode`, chosen on the forecast, default Gust):
##   gust    push 1 away from the origin
##   vortex  pull 1 toward the origin
##   becalm  Becalmed: move 0 until the end of its next turn (it can still
##           act and be displaced); then Restless for 2 turns (immune)
##
## Where a mode applies:
##   * a wind SKILL (any weapon): BEFORE its hits, to the foes in or beside
##     its shape (pre_hit). The origin is the shape's centre for ground-aimed
##     and leap skills, else the caster. Foes pulled into the shape are hit;
##     foes blown out of it are still hit (the gust carries the blow).
##   * a wind BASIC attack (an imbue, a staff attuned to wind): on the target
##     after a landed, unresisted blow (after_basic).
##   * a gale MARKER laid by wind stores the caster's mode: it is a FIELD.
##       gust field    a heading (away from the caster); a unit that enters it
##                     or starts its turn on it is pushed 1 along the heading
##       vortex field  at the tick, units within 1 are pulled onto it
##       becalm field  a foe of its owner entering it stops there
##     When the marker fires (a fresh charge lands), it copies the charge as
##     ever and applies its mode once to the units in the copy area.
##
## Caps (no loops): wind moves a unit at most CYCLE_HEXES hexes per cycle in
## all; a field moves it at most once per turn (the tick is its own turn);
## a direct application (skill or basic) at most once per action; fields only
## read voluntary entry, turn start, the tick and a gale firing, never a
## displacement. Slides onto glaze are Lane A's BWSlides.after_push (their own
## cap of 6). Dark 3 gravity (BWCurse) adds or takes 1 within these caps.
## Weather Gale (BWWeather) is not a field: it moves outside these caps and
## never triggers a field.

const GUST := "gust"
const VORTEX := "vortex"
const BECALM := "becalm"
const MODES := [GUST, VORTEX, BECALM]
const NAMES := { "gust": "Gust", "vortex": "Vortex", "becalm": "Becalm" }
const RULES := {
	"gust": "push 1 away",
	"vortex": "pull 1 in",
	"becalm": "move 0 until its next turn ends",
}
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


# ---------------------------------------------------------------- modes

static func mode(u: BWUnit) -> String:
	if u == null:
		return GUST
	var m := str(u.wind_mode)
	return m if m in MODES else GUST


static func set_mode(u: BWUnit, m: String) -> void:
	if u != null and m in MODES:
		u.wind_mode = m


static func next_mode(m: String) -> String:
	var i := MODES.find(m)
	return MODES[(i + 1) % MODES.size()]


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
	var slid := _slide(b, v, dir, by)
	if slam and not slid and stop in ["rock", "unit"] and v.alive() and not b.over:
		_slam(b, v, dir, by)
	return out


## Lane A's slide (BWSlides.after_push: onto glaze it slides on, cap 6,
## then slams). True when it slid.
static func _slide(b: BWBattle, v: BWUnit, dir: int, by: BWUnit) -> bool:
	var sp: Dictionary = BWSlides.after_push(b, v, dir, by.id if by != null else "")
	return (sp.get("path", []) as Array).size() > 1


## A wind push stopped short: SLAM_PCT to it and to the unit it hit.
static func _slam(b: BWBattle, v: BWUnit, dir: int, by: BWUnit) -> void:
	var nxt: Vector2i = BWHex.neighbors(v.pos)[dir]
	var o := b.unit_at(nxt)
	var src := by.id if by != null else ""
	b._emit({ "type": "slam", "unit": v.id, "by": src, "into": "unit" if o != null else "rock",
		"name": "Gust", "target": o.id if o != null else "", "hex": v.pos })
	var pv := BWPerkRules.slam_pct(b, v, src, SLAM_PCT, true)      # D281: Crosswind, Fault Lines, Rime Armour
	if pv > 0.0:
		b._tile_hurt(v, b._tile_dmg(v, pv, ""), "slam", src)
	if o != null and o != v and o.alive() and not b.over:
		var po := BWPerkRules.slam_pct(b, o, src, SLAM_PCT, true)
		if po > 0.0:
			b._tile_hurt(o, b._tile_dmg(o, po, ""), "slam", src)
	BWPerkRules.after_slam(b, v, src, true, nxt if b.tiles.pillars.has(nxt) else Vector2i(-9999, -9999))   # D281: Crosswind Becalms


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
				var res := push(b, v, dir, BWKsWind.gust_n(by) if field else 1, "push", by, field, true, reserved, dry)   # D293 Jetstream
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


## A wind skill's mode, BEFORE its hits: once, on the foes in or beside its
## shape. Foes that end in the shape join the victims. `dry` (skill_preview):
## positions only; the caller restores them with restore(). Returns
## { moves, becalm, restore: [[unit, pos]], origin, mode }.
static func pre_hit(b: BWBattle, u: BWUnit, s: Dictionary, p: Dictionary, target_hex: Vector2i, dry: bool = false) -> Dictionary:
	if str(p.get("element", "")) != "wind" or not u.alive():
		return {}
	var origin := skill_origin(u, s, target_hex)
	var shape: Array = (p.hexes as Array) + (p.get("ring", []) as Array)
	for v in p.victims:
		shape.append_array(v.footprint())
	if shape.is_empty():
		shape = [target_hex]
	var zone := {}
	for h in BWHex.fringe(shape, 1):
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
	var m := mode(u)
	var res := apply_mode(b, u, m, cand, origin, false, -1, reserved, dry)
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
		var nm := str(NAMES[m])
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


## A wind basic attack: the mode on its target after a landed, unresisted
## blow (v3 §1 direct hits; a Blank takes no element).
static func after_basic(b: BWBattle, u: BWUnit, target: BWUnit, first: Dictionary) -> void:
	if b.over or not u.alive() or target == null or not target.alive() or first.is_empty():
		return
	if b.basic_element(u) != "wind" or not first.get("hit", false) or not first.get("secondary", false):
		return
	if BWFormulas.strips_element(target):
		return
	apply_mode(b, u, mode(u), [target], u.pos, false)


# ---------------------------------------------------------------- fields (gale markers with a mode)

## The field on `h`: its tile entry (marker gale with a `mode`), else {}.
static func field_at(b: BWBattle, h: Vector2i) -> Dictionary:
	var e := b.tiles.at(h)
	if str(e.get("marker", "")) != "gale" or not e.has("mode"):
		return {}
	return e


## Every field hex, sorted (deterministic).
static func field_hexes(b: BWBattle) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		if not field_at(b, h).is_empty():
			out.append(h)
	out.sort()
	return out


static func _owner(b: BWBattle, e: Dictionary) -> BWUnit:
	return b._unit(str(e.get("source", "")))


## Before a paint: the fields on the painted hexes (their mode is gone once
## they fire).
static func before_paint(b: BWBattle, hexes: Array) -> Dictionary:
	var snap := {}
	for h in hexes:
		var f := field_at(b, h)
		if not f.is_empty():
			snap[h] = f.duplicate()
	return snap


## After a paint: stamp the caster's mode on every gale it laid; each field
## that fired applies its mode once to the copy area; copies carry the
## origin's reaction states (steam, electrified; Lane A).
static func after_paint(b: BWBattle, by: BWUnit, element: String, r: Dictionary, snap: Dictionary) -> void:
	if element == "wind" and by != null:
		for h in r.get("changed", []):
			var e: Dictionary = b.tiles.entries.get(h, {})
			if str(e.get("marker", "")) == "gale" and str(e.get("source", "")) == by.id:
				e["mode"] = mode(by)
				b.wind["serial"] = int(b.wind.get("serial", 0)) + 1
				e["born"] = b.wind.serial                  # D293: Eye of the Vortex acts with the newest
				if e.mode == GUST:
					var dir := BWBattle.pulse_heading(by.pos, h, true) if by.pos != h else by.facing
					if dir < 0:
						dir = BWHex.direction_index(by.pos, h)
					e["heading"] = maxi(dir, 0)
				else:
					e.erase("heading")
	for g in r.get("gales", []):
		carry(b, g.origin, g.copies)
		BWKsWind.after_gale(b, g, snap)                # D293 Jetstream: your gales' copies last 2
		if snap.has(g.origin) and not b.over:
			var f: Dictionary = snap[g.origin]
			var radius := maxi(1, int(g.get("level", 1)))
			for c in g.copies:
				radius = maxi(radius, BWHex.distance(g.origin, c))
			fire_field(b, f, g.origin, radius)


## A field fired: its mode once on every unit in the copy area (a field
## application: once per turn, the cycle budget). Becalm takes only its
## owner's foes; Gust and Vortex are the air itself and move everyone.
static func fire_field(b: BWBattle, f: Dictionary, origin: Vector2i, radius: int) -> void:
	var owner := _owner(b, f)
	var m := str(f.mode)
	var who: Array = []
	for v in b.units:
		if not v.alive() or BWObelisk.is_objective(v) or BWHex.distance(origin, v.pos) > radius:
			continue
		if m == BECALM and owner != null and v.team == owner.team:
			continue
		if BWSets.spares_allies(owner, v):         # D282: the Wind set's fields skip allies
			continue
		who.append(v)
	b._emit({ "type": "field_fire", "hex": origin, "mode": m, "radius": radius })
	if m == VORTEX and BWKsWind.eye(owner):
		BWKsWind.eye_pull(b, owner, origin, maxi(radius, BWKsWind.EYE_RADIUS))   # D293 Eye of the Vortex
		return
	apply_mode(b, owner, m, who, origin, true, int(f.get("heading", -1)))


## Gale copies carry the origin's reaction state (v3 §1 "Spreading,
## extended"): steam (1 tick) and electrified (joins the origin's field) from
## Lane A's BWTiles.steam / shock / fields when they exist; rink glaze is a
## D293: rink glaze (a gale beside a rink, BWKsWind.carry_rink). Plus any
## `carry_hooks` Lane A registers.
static func carry(b: BWBattle, origin: Vector2i, copies: Array) -> void:
	if copies.is_empty():
		return
	var t := b.tiles
	var steam = t.get("steam")
	if steam is Dictionary and (steam as Dictionary).has(origin):
		for c in copies:
			if not steam.has(c):
				steam[c] = 1
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
	BWKsWind.carry_rink(b, origin, copies)       # D293: a gale beside a rink glazes its copies (1 cycle)
	for hook in carry_hooks:
		if (hook as Callable).is_valid():
			(hook as Callable).call(b, origin, copies)


## A voluntary walk stopped on `path[-1]`: a gust field pushes it along its
## heading; a becalm field (its owner's foe) has stopped it there.
static func after_move(b: BWBattle, u: BWUnit, path: Array) -> void:
	if b.over or not u.alive() or path.size() < 2:
		return
	var h: Vector2i = path[-1]
	var f := field_at(b, h)
	if f.is_empty():
		return
	if BWSets.spares_allies(_owner(b, f), u):      # D282: the Wind set's fields skip allies
		return
	match str(f.mode):
		GUST:
			var res := push(b, u, int(f.get("heading", 0)), BWKsWind.gust_n(_owner(b, f)), "push", _owner(b, f), true, true)
			if res.moved or str(res.stop) in ["rock", "unit"]:
				b._undo = {}                  # the field acted: the walk can't be taken back
		BECALM:
			var o := _owner(b, f)
			if o == null or o.team != u.team:
				b._emit({ "type": "field_stop", "unit": u.id, "hex": h, "mode": BECALM })


## Turn start on a gust field: pushed 1 along its heading.
static func turn_start(b: BWBattle, u: BWUnit) -> void:
	if b.over or not u.alive():
		return
	var f := field_at(b, u.pos)
	if not f.is_empty() and str(f.mode) == GUST and not BWSets.spares_allies(_owner(b, f), u):   # D282
		push(b, u, int(f.get("heading", 0)), BWKsWind.gust_n(_owner(b, f)), "push", _owner(b, f), true, true)


## Walk-stop hexes for BWBattle.reachable (merged into the D97 zone rule):
## every gust field (entering one ends the walk, then it pushes), and the
## becalm fields of `u`'s foes.
static func stop_rules(b: BWBattle, u: BWUnit, r: Dictionary) -> void:
	var z: Dictionary = r.get("zone", {})
	var any := false
	for h in field_hexes(b):
		var f := field_at(b, h)
		if str(f.mode) == GUST:
			z[h] = true
			any = true
		elif str(f.mode) == BECALM:
			var o := _owner(b, f)
			if o == null or o.team != u.team:
				z[h] = true
				any = true
	if any:
		r["zone"] = z


## The cycle tick (v3 "the new tick", step 2), before the tiles decay:
## vortex fields pull the units beside them onto them (closest first, a free
## hex only, no slam), then Lane C's Event Horizon (BWCurse.tick), then the
## walls count down.
static func tick(b: BWBattle) -> void:
	b.wind["in_tick"] = true
	var eyes := BWKsWind.eye_fields(b)                 # D293: one Eye field per holder (the newest)
	for h in field_hexes(b):
		var f := field_at(b, h)
		if str(f.mode) != VORTEX or b.over:
			continue
		var fo := _owner(b, f)
		if BWKsWind.eye(fo):
			if eyes.get(fo.id, BWBattle.NOWHERE) == h:
				BWKsWind.eye_pull(b, fo, h)
			continue
		var near: Array = []
		for v in b.units:
			if v.alive() and not BWObelisk.is_objective(v) and BWHex.distance(v.pos, h) == 1:
				near.append(v)
		if not near.is_empty():
			apply_mode(b, _owner(b, f), VORTEX, near, h, true)
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

static func has_wind_wall(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, WALL_KEY)            # D293: the keystone, not a flag


## Keystone actions `u` fights with (BWBattle.skills_for adds them): every
## action keystone it holds that has a skill def (D293: Wind Wall, Flash
## Freeze, Tidal Release), plus Glacier Wall's Shatter while it has a pillar.
static func keystone_actions(u: BWUnit) -> Array:
	var out: Array = []
	if u == null:
		return out
	for id in BWKeystones.actions(u):
		if BWSkillRegistry.has(str(id)) and not str(id) in out and BWKsIce.action_open(u, str(id)):
			out.append(str(id))
	if BWKeystones.has(u, BWKsIce.GLACIER) and BWSkillRegistry.has(BWKsIce.SHATTER_KEY):
		out.append(BWKsIce.SHATTER_KEY)
	if BWKeystones.has(u, "blast_rider") and BWSkillRegistry.has(BWThunderKeys.SELF_DET):
		out.append(BWThunderKeys.SELF_DET)        # D306: listed for every holder; open only on a charge or its fuse
	return out


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


# ---------------------------------------------------------------- AI (D274)

## A cheap mode for an action on `focus` from `origin`: Gust when the push
## slams it into rock, a unit, a pillar or a wall; Vortex when it stands
## within 2 of its own side's fire or water 3; Becalm on the fastest foe
## (not Restless); else Gust.
static func ai_choose(b: BWBattle, u: BWUnit, focus: BWUnit, origin: Vector2i) -> String:
	if focus == null:
		return GUST
	var dir := BWBattle.pulse_heading(origin, focus.pos, true) if origin != focus.pos else -1
	if dir >= 0 and not b._immune(focus, "displace"):
		var pp := b.push_path(focus, dir, 1)
		if str(pp.stop) in ["rock", "unit"]:
			return GUST
	for h in b.tiles.entries:
		if BWHex.distance(h, focus.pos) > 2:
			continue
		if b.tiles.intensity(h, "fire") >= 3 or b.tiles.intensity(h, "water") >= 3:
			var src := b._unit(str(b.tiles.at(h).get("source", "")))
			if src != null and src.team == u.team:
				return VORTEX
	var fastest: BWUnit = null
	for f in b.foes_of(u):
		if BWObelisk.is_objective(f):
			continue
		if fastest == null or f.move_range() > fastest.move_range():
			fastest = f
	if focus == fastest and not focus.statuses.has("restless") and not focus.statuses.has("becalmed"):
		return BECALM
	return GUST


## The ≤ 3-combo limit (v3 §11): for the chosen wind skill, simulate each of
## the three modes once and keep the best (damage to foes minus damage to
## its own side; ties keep the cheap pick). Sets u.wind_mode.
static func ai_refine(b: BWBattle, u: BWUnit, key: String, el: String, target: Vector2i) -> void:
	if el != "wind":
		return
	var first := mode(u)
	var best_m := first
	var best := -INF
	var order: Array = [first]
	for m in MODES:
		if not m in order:
			order.append(m)
	for m in order.slice(0, 3):
		u.wind_mode = m
		var sim := b.simulate(u, { "kind": "skill", "key": key, "element": el, "hex": target })
		if sim.is_empty():
			continue
		var sc := 0.0
		for id in sim.units:
			var rec: Dictionary = sim.units[id]
			var d := float(rec.get("damage", 0))
			sc += -d if bool(rec.get("friendly", false)) else d
		if sc > best + 0.5:
			best = sc
			best_m = m
	u.wind_mode = best_m


## The tile card's lines for `h` (plain text; the view colours them).
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var f := field_at(b, h)
	if not f.is_empty():
		match str(f.mode):
			GUST:
				out.append("Gust field: entering or starting a turn here pushes 1 along its arrow")
			VORTEX:
				out.append("Vortex field: pulls units beside it onto it at the tick")
			BECALM:
				out.append("Becalm field: a foe of its owner entering it stops here")
	if walled(b, h):
		for k in walls(b):
			if h in walls(b)[k].hexes:
				out.append("Wind Wall: blocks moves and skills both ways (basic attacks pierce); %d tick%s left" % [
					int(walls(b)[k].ticks), "" if int(walls(b)[k].ticks) == 1 else "s"])
	return out

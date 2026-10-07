class_name BWTiles
extends RefCounted
## Elements on the ground: the charge grid from design/ELEMENTS.md (§2-§6).
## Pure state + rules. It reports what happened (detonations, seeds) and the
## battle turns those into damage, because only the battle knows the units.
##
## A hex with nothing on it has no entry ("neutral is absence"). An entry:
##   { h, v, marker, timer, glaze, source, origin, permanent }
## h: water(-3)..fire(+3), v: dark(-3)..light(+3). `source` is a unit id
## ("" = authored). Section numbers below refer to ELEMENTS.md.

const AXIS_MAX := 3
const STEP_CYCLES := 2
const MARK_CYCLES := 3
const GLAZE_CYCLES := 2
const FIRE_STAND_PCT := 4
const FIRE_CROSS_PCT := 2
const LIGHT_HEAL_PCT := 3
const HIT_PER_POINT := 7
const DARK3_DRAIN_PCT := 3
const WATER_MOVE := [0, 0, 1, 2]
const DETONATE_BASE_PCT := 5
const DETONATE_PER_POINT_PCT := 4
const CONDUCT_DET_PCT := 2
const CONDUCT_HIT_MULT := 0.10
const SHATTER_MULT := 1.5
const ELEM_RESIST_CAP := 75.0
const GRASS_IGNITE_MIN := 2
## D86 (author-approved element rules, ELEMENTS §8.5).
const CHAIN_FRACTION := 0.5      # a conductive unit arcs half its damage to its nearest teammate
const SPARK_PCT := 10            # thunder hit on a target whose hex holds no charge
const SHATTER_HIT_PCT := 15      # any attack on a target standing on a glazed hex

const AXIS := ["fire", "water", "light", "dark"]
const OPERATORS := { "thunder": "fuse", "ice": "stasis", "wind": "gale" }
const MARKER_ELEMENT := { "fuse": "thunder", "stasis": "ice", "gale": "wind" }

var board: BWBoard
var entries := {}        # Vector2i -> entry Dictionary
## FX hook (tile_potency_pct): Callable(source_id, element) -> multiplier for
## the per-point effect of tiles that unit laid. Unset = 1 (pure tile tests).
var potency: Callable
## FX hook (tile_erupt): eruptions that went off in the last tick(), for the
## battle to resolve. [{hex, element, points, owner, dmg_pct, heal_pct,
## radius, push, consume, name}]. An entry may carry `erupt` (a countdown).
var eruptions: Array = []
## D115 static charge: the map's permanent floor state per hex (from
## BWBoard.statics), Vector2i(h, v). It never decays and re-forms at every
## tick; painting on it lasts until then. `scars`: hexes whose static was
## spent (a detonation, Consume) and stays off for STATIC_SCAR_TICKS ticks.
const STATIC_SCAR_TICKS := 1
var statics := {}
var scars := {}
## D261-D266 the ice/water spine (ELEMENTS-v3 §2, §4; src/core/pools.gd,
## slides.gd). pillars: hex -> {owner, ticks, born}; steam: hex -> ticks;
## fields (electrified): id -> {hexes, ticks, source, ramp {unit id: n}};
## shock: hex -> field id. `occupant` (hex -> BWUnit or null) is the battle's
## unit_at (unset = nobody). spine_tick: what the last tick thawed/discharged.
var pillars := {}
var steam := {}
var fields := {}
var shock := {}
var spine_serial := 0
var spine_tick := {}
var pool_cache := {}
var occupant: Callable


func _init(p_board: BWBoard) -> void:
	board = p_board
	for hex in board.statics:
		var s: Vector2i = board.statics[hex]
		set_static(hex, s.x, s.y)
	for hex in board.seeds:
		var s: Vector2i = board.seeds[hex]
		seed_hex(hex, s.x, s.y)


# ------------------------------------------------------------------ reading

func at(hex: Vector2i) -> Dictionary:
	return entries.get(hex, {})


func intensity(hex: Vector2i, element: String) -> int:
	var e := at(hex)
	if e.is_empty():
		return 0
	match element:
		"fire": return maxi(e.h, 0)
		"water": return maxi(-e.h, 0)
		"light": return maxi(e.v, 0)
		"dark": return maxi(-e.v, 0)
	return 0


func is_glazed(hex: Vector2i) -> bool:
	return int(at(hex).get("glaze", 0)) > 0


## §7.4 "carries the element".
func carries(hex: Vector2i, element: String) -> bool:
	var e := at(hex)
	if e.is_empty():
		return false
	match element:
		"fire": return e.h > 0
		"water": return e.h < 0
		"light": return e.v > 0
		"dark": return e.v < 0
		"thunder": return e.marker == "fuse"
		"wind": return e.marker == "gale"
		"ice": return e.marker == "stasis" or e.glaze > 0
	return false


## §7.5: dominant element and points, for Consume.
func dominant(hex: Vector2i) -> Dictionary:
	var e := at(hex)
	if e.is_empty():
		return {}
	if e.marker != "":
		return { "element": MARKER_ELEMENT[e.marker], "points": 1 }
	var points: int = absi(e.h) + absi(e.v)
	if absi(e.h) >= absi(e.v):
		return { "element": "fire" if e.h > 0 else "water", "points": points }
	return { "element": "light" if e.v > 0 else "dark", "points": points }


## FX hook (tile_potency_pct): how much stronger this hex's `element` is,
## from the unit that laid it (Brimming, Radiant, Gloaming, Shattering).
func pot(hex: Vector2i, element: String, src: String = "?") -> float:
	if not potency.is_valid():
		return 1.0
	return float(potency.call(str(at(hex).get("source", "")) if src == "?" else src, element))


## Extra move cost to enter (§6.5). Glazed water is walkable ice (E7).
## Brimming water costs more (rounded up).
func move_penalty(hex: Vector2i) -> int:
	if is_glazed(hex):
		return 0
	var base: int = WATER_MOVE[intensity(hex, "water")]
	return ceili(base * pot(hex, "water")) if base > 0 else 0


## Hit-chance points against whoever stands here (§2.2). Radiant exposes and
## Gloaming hides harder (tile_potency_pct), so this can be fractional.
func hit_mod(hex: Vector2i) -> float:
	var light := intensity(hex, "light")
	var dark := intensity(hex, "dark")
	var v := 0.0
	if light > 0:
		v += HIT_PER_POINT * light * pot(hex, "light")
	if dark > 0:
		v -= HIT_PER_POINT * dark * pot(hex, "dark")
	return v


## Start-of-turn effects in % HP (§2.2). Damage applies before healing.
## FX hook: Radiant heals more, a stronger fire burns more (tile_potency_pct).
func standing(hex: Vector2i) -> Dictionary:
	var fire := intensity(hex, "fire")
	var light := intensity(hex, "light")
	return {
		"fire": FIRE_STAND_PCT * fire * (pot(hex, "fire") if fire > 0 else 1.0),
		"drain": DARK3_DRAIN_PCT if intensity(hex, "dark") >= 3 else 0,
		"heal": LIGHT_HEAL_PCT * light * (pot(hex, "light") if light > 0 else 1.0),
		"source": str(at(hex).get("source", "")),
	}


func crossing_pct(hex: Vector2i) -> float:
	var fire := intensity(hex, "fire")
	return FIRE_CROSS_PCT * fire * (pot(hex, "fire") if fire > 0 else 1.0)


## D86: a unit standing on a fuse is conductive (§8.5). D264: so is one in an
## electrified pool.
func conductive(hex: Vector2i) -> bool:
	return str(at(hex).get("marker", "")) == "fuse" or shock.has(hex)


## D262: an ice pillar stands here (impassable, blocks sight, slams).
func is_pillar(hex: Vector2i) -> bool:
	return pillars.has(hex) and is_glazed(hex)


## D262/D264: the board's dynamic blockers (BWBoard.blocker / sight_blocker).
func blocks_move(hex: Vector2i) -> bool:
	return is_pillar(hex)


## Steam blocks a line through it, except between hexes within
## BWPools.STEAM_RANGE (a unit in steam can be targeted from that close).
func blocks_sight(hex: Vector2i, from: Vector2i = hex, to: Vector2i = hex) -> bool:
	return is_pillar(hex) or (steam.has(hex) and BWHex.distance(from, to) > BWPools.STEAM_RANGE)


## D86: does the hex hold axis charge (Spark needs it not to)?
func charged(hex: Vector2i) -> bool:
	var e := at(hex)
	return not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0)


## Thunder hits on a unit standing in water get +10% per water intensity (§8.3).
func conduct_mult(hex: Vector2i, element: String) -> float:
	if element != "thunder":
		return 1.0
	return 1.0 + CONDUCT_HIT_MULT * intensity(hex, "water")


## Tile damage after the victim's affinity resistance (§8.2).
static func tile_damage(u: BWUnit, pct: float, element: String, mult: float = 1.0) -> int:
	if pct <= 0.0:
		return 0
	var res := minf(BWFormulas.elemental_resist(u, element), ELEM_RESIST_CAP)
	return maxi(1, roundi(u.max_hp() * pct / 100.0 * mult * (1.0 - res / 100.0)))


# ------------------------------------------------------------------ writing

func can_hold(hex: Vector2i) -> bool:
	return board.exists(hex) and board.terrain(hex) != BWBoard.JAGGED


## D115: make `hex` a static (h, v) hex and lay its floor state now.
## (0, 0) removes the static (the current charge is left to decay).
func set_static(hex: Vector2i, h: int, v: int) -> void:
	h = clampi(h, -AXIS_MAX, AXIS_MAX)
	v = clampi(v, -AXIS_MAX, AXIS_MAX)
	if not can_hold(hex) or (h == 0 and v == 0):
		statics.erase(hex)
		scars.erase(hex)
		return
	statics[hex] = Vector2i(h, v)
	scars.erase(hex)
	entries[hex] = _static_entry(hex)


func is_static(hex: Vector2i) -> bool:
	return statics.has(hex)


## D115: the static's floor (h, v), or (0, 0).
func static_at(hex: Vector2i) -> Vector2i:
	return statics.get(hex, Vector2i.ZERO)


## D115: a static hex whose floor is spent until a later tick.
func is_scarred(hex: Vector2i) -> bool:
	return scars.has(hex)


## D134 seeded charge (§5.6): the hex starts with (h, v) and holds it with no
## decay (an authored, permanent entry flagged `seeded`). The first change by
## play makes it ordinary charge (a fresh entry, or `permanent` cleared and
## the flag dropped), so it decays from then on and never comes back.
func seed_hex(hex: Vector2i, h: int, v: int) -> void:
	author(hex, clampi(h, -AXIS_MAX, AXIS_MAX), clampi(v, -AXIS_MAX, AXIS_MAX))
	if entries.has(hex):
		entries[hex]["seeded"] = true


## D134: does the hex still hold its untouched seed?
func is_seeded(hex: Vector2i) -> bool:
	var e := at(hex)
	return bool(e.get("seeded", false)) and bool(e.get("permanent", false))


## Authored starting state (§5.4).
func author(hex: Vector2i, h: int, v: int, marker: String = "") -> void:
	if not can_hold(hex):
		return
	entries[hex] = _entry(h, v, marker, "", "cast")
	entries[hex].permanent = true


## Apply one action's element to a shape, simultaneously (§3.5).
## Returns { detonations: [{hex, pct, source}], changed: [hex], marker_fired: [hex],
##           gales: [{origin, copies}] }.
## FX hook `opts` (BWEffects.paint_opts): timer_plus / glaze_plus /
## gale_timer_plus (tile_duration_plus), ring {hex: steps} (element_area_plus,
## resolved in the same simultaneous pass), gale_radius (Gusting), erupt (a
## tile_erupt countdown stamped on every hex this cast leaves carrying it).
func apply(hexes: Array, element: String, caster: String, steps: int = 1, opts: Dictionary = {}) -> Dictionary:
	var out := { "detonations": [], "changed": [], "marker_fired": [], "gales": [] }
	var plans := {}
	# D199: `propagated` = the charge arrives as spread (on-kill paint, ENCHANTMENTS
	# §5.3): it never fires a marker and skips glazed hexes.
	var fresh: bool = not opts.get("propagated", false)
	var spine := BWPools.begin(self, hexes, element, fresh, steps, caster, opts)   # D264: pool reactions, pre-action
	var hot := BWOverheat.begin(self, hexes, element, fresh, opts)   # D285: fresh fire on fire 3 erupts
	var guard: Array = opts.get("fuse_guard", [])   # D307 Static Field: an ally's fuse ignores this paint
	for hex in hexes:
		if can_hold(hex) and not plans.has(hex):
			if not fresh and is_glazed(hex):
				continue
			if fuse_guarded(hex, guard):
				continue
			plans[hex] = spine.plans[hex] if spine.plans.has(hex) else _route(at(hex), element, fresh, steps, caster, opts)
	var ring: Dictionary = opts.get("ring", {})
	for hex in ring:
		if can_hold(hex) and not plans.has(hex) and not fuse_guarded(hex, guard):
			plans[hex] = _route(at(hex), element, true, int(ring[hex]), caster, opts)
	var gales: Array = []
	for hex in plans:
		var p: Dictionary = plans[hex]
		if p.op == "none":
			continue
		if p.op == "erase":
			entries.erase(hex)
		else:
			entries[hex] = p.entry
			p.entry.erase("seeded")              # D134: a changed seed is ordinary charge
		out.changed.append(hex)
		if p.has("detonate"):
			if statics.has(hex):
				scars[hex] = STATIC_SCAR_TICKS          # D115: a blown static stays spent a cycle
			out.detonations.append({ "hex": hex, "pct": p.detonate, "source": p.get("det_source", caster),
				"points": int(p.get("det_points", 0)) })   # v2 Overload reads the points blown
		if p.has("gale"):
			gales.append([hex, p.gale, int(p.get("gale_level", 1))])
		if p.get("fired", false):
			out.marker_fired.append(hex)
	BWPools.finish(self, spine, element, caster, fresh, out, int(opts.get("glaze_plus", 0)))   # D262/D264
	if opts.has("erupt"):
		for hex in out.changed:
			if carries(hex, element) and entries.has(hex) and str(entries[hex].source) == caster:
				entries[hex]["erupt"] = (opts.erupt as Dictionary).duplicate()
	# D93 Wildfire: fresh fire at `wild`+ from this caster may seed off grass.
	if opts.has("wild"):
		for hex in out.changed:
			var en: Dictionary = entries.get(hex, {})
			if not en.is_empty() and int(en.h) >= int(opts.wild) and str(en.source) == caster 					and en.origin == "cast" and int(en.glaze) == 0:
				en["wild"] = true
	BWOverheat.finish(self, hot, caster, out, opts)   # D285: the eruptions (ring +2, vent to 2), out.overheat
	for g in gales:
		# D95: a gale 2 copies one ring further (rings 1 and 2, same skip rules)
		var copies := _gale_copy(g[0], g[1], caster, out.changed,
			int(opts.get("gale_radius", 1)) + int(g[2]) - 1, int(opts.get("gale_timer_plus", 0)))
		out.gales.append({ "origin": g[0], "copies": copies, "level": int(g[2]) })
	return out


## D307 Static Field: a fuse whose owner is in `guard` (allies of the painter
## holding Static Field) can't be set off, re-armed or washed by that paint.
func fuse_guarded(hex: Vector2i, guard: Array) -> bool:
	if guard.is_empty():
		return false
	var e := at(hex)
	return str(e.get("marker", "")) == "fuse" and str(e.get("source", "")) in guard


## D93 Fault Lines: a Shatter hit breaks the glaze (the charge stays).
func break_glaze(hex: Vector2i) -> bool:
	var e := at(hex)
	if e.is_empty() or int(e.get("glaze", 0)) <= 0:
		return false
	e.glaze = 0
	e.erase("seeded")
	return true


## Consume (§7.2): the hex is eaten back to bare ground. A static hex is
## spent like a detonated one (D115).
func clear(hex: Vector2i) -> void:
	entries.erase(hex)
	if statics.has(hex):
		scars[hex] = STATIC_SCAR_TICKS


## Siphon (§9.3): both axes 2 steps toward 0, strip marker and glaze.
func siphon(hex: Vector2i) -> void:
	var e := at(hex)
	if e.is_empty():
		return
	var h: int = e.h - signi(e.h) * mini(2, absi(e.h))
	var v: int = e.v - signi(e.v) * mini(2, absi(e.v))
	if h == 0 and v == 0:
		entries.erase(hex)
		return
	entries[hex] = _entry(h, v, "", e.source, e.origin)


## The per-cycle tick (§5.1): eruptions, decay, grass spread, then the
## statics re-form (D115). Returns
## seeded hexes; eruptions that went off are left in `eruptions`.
func tick() -> Array:
	_erupt_phase()
	for hex in entries.keys():
		var e: Dictionary = entries[hex]
		if e.permanent or (statics.has(hex) and not scars.has(hex)):
			continue                           # statics decay in _static_phase
		if pillars.has(hex) or shock.has(hex):
			continue                           # D262/D264: a pillar or a live field freezes decay
		if e.glaze > 0:
			e.glaze -= 1
			continue
		e.timer -= 1
		if e.timer > 0:
			continue
		if e.marker != "":
			entries.erase(hex)
			continue
		var ah := absi(e.h)
		var av := absi(e.v)
		if ah >= av:
			e.h -= signi(e.h)
		if av >= ah:
			e.v -= signi(e.v)
		if e.h == 0 and e.v == 0:
			entries.erase(hex)
		else:
			e.timer = STEP_CYCLES
	BWPools.tick(self)                         # D262/D264: pillars, steam and fields count down
	var seeded := _grass_spread()
	_static_phase()
	return seeded


## D115, the static half of the tick, last (after decay and grass spread, so
## a real fire cast on static fire still gets its once-per-cast ignition).
## A scarred static counts its scar down and stays off. Otherwise the floor
## re-forms: an empty hex gets it back; a glazed one is frozen (glaze counts
## down, nothing else); a marker armed while it was spent fades on its own
## timer, then the floor returns; on charge, every axis the static declares
## snaps back to its value and a free axis (painted on top) decays on the
## entry's timer, one step per STEP_CYCLES. Restored entries are
## origin "spread", source "" (no one's), so they never ignite grass.
func _static_phase() -> void:
	var keys := statics.keys()
	keys.sort()
	for hex in keys:
		if scars.has(hex):
			scars[hex] = int(scars[hex]) - 1
			if int(scars[hex]) <= 0:
				scars.erase(hex)
			continue
		var s: Vector2i = statics[hex]
		var e := at(hex)
		if pillars.has(hex) or shock.has(hex):
			continue                           # D262/D264: frozen while the pillar or field stands
		if e.is_empty():
			entries[hex] = _static_entry(hex)
			continue
		if int(e.glaze) > 0:
			e.glaze -= 1
			continue
		if str(e.marker) != "":
			e.timer -= 1
			if e.timer <= 0:
				entries[hex] = _static_entry(hex)
			continue
		var h: int = s.x if s.x != 0 else int(e.h)
		var v: int = s.y if s.y != 0 else int(e.v)
		var excess := (s.x == 0 and h != 0) or (s.y == 0 and v != 0)
		if excess:
			e.timer -= 1
			if e.timer <= 0:
				if s.x == 0:
					h -= signi(h)
				if s.y == 0:
					v -= signi(v)
				e.timer = STEP_CYCLES
		if h == s.x and v == s.y:
			entries[hex] = _static_entry(hex)
		else:
			e.h = h
			e.v = v


func _static_entry(hex: Vector2i) -> Dictionary:
	var s: Vector2i = statics[hex]
	var e := _entry(s.x, s.y, "", "", "spread")
	e["static"] = true
	return e


# ------------------------------------------------------------------ internals

## FX hook (tile_erupt): count every armed tile down; at 0 it goes off with
## its element's current intensity (gone = fizzles). The eruption is reported,
## never painted: it lays nothing, fires no marker, and is spent whether or
## not it found anyone, so an eruption can never chain (§5.3).
func _erupt_phase() -> void:
	eruptions = []
	var keys := entries.keys()
	keys.sort()
	for hex in keys:
		var e: Dictionary = entries[hex]
		if not e.has("erupt"):
			continue
		var er: Dictionary = e.erupt
		er.left = int(er.left) - 1
		if er.left > 0:
			continue
		e.erase("erupt")
		var pts := intensity(hex, str(er.element))
		if pts <= 0:
			continue
		var rec := er.duplicate()
		rec.erase("left")
		rec["hex"] = hex
		rec["points"] = pts
		eruptions.append(rec)
		if er.consume:
			entries.erase(hex)

func _entry(h: int, v: int, marker: String, source: String, origin: String, timer_plus: int = 0) -> Dictionary:
	return { "h": h, "v": v, "marker": marker, "glaze": 0,
		"timer": MARK_CYCLES if marker != "" else STEP_CYCLES + timer_plus,
		"source": source, "origin": origin, "permanent": false }


## Pure: what would `element` arriving do to entry `e`? (§3.1-§3.3)
## FX hook: `opts` carries the caster's tile_duration_plus (timer_plus, glaze_plus).
func _route(e: Dictionary, element: String, fresh: bool, steps: int, caster: String, opts: Dictionary = {}) -> Dictionary:
	var h: int = e.get("h", 0)
	var v: int = e.get("v", 0)
	var marker: String = e.get("marker", "")
	var glaze: int = e.get("glaze", 0)
	var charged := h != 0 or v != 0

	if element in AXIS:
		if glaze > 0:
			if element == "fire":           # fire melts the glaze, and is spent
				var melted := e.duplicate()
				melted.glaze = 0
				melted.permanent = false
				return { "op": "set", "entry": melted }
			return { "op": "none" }          # everything else washes off
		var nh := h
		var nv := v
		match element:
			"fire": nh += steps
			"water": nh -= steps
			"light": nv += steps
			"dark": nv -= steps
		nh = clampi(nh, -AXIS_MAX, AXIS_MAX)
		nv = clampi(nv, -AXIS_MAX, AXIS_MAX)
		if marker != "":
			if not fresh:
				return { "op": "none" }      # containment rule 1
			var arrived := _entry(nh, nv, "", caster, "cast", int(opts.get("timer_plus", 0)))
			if marker == "gale":
				arrived["gale_level"] = int(e.get("gale_level", 1))
			var p := _operate(arrived, marker, str(e.get("source", caster)))
			p["fired"] = true
			return p
		if nh == 0 and nv == 0:
			return { "op": "erase" }
		return { "op": "set", "entry": _entry(nh, nv, "", caster, "cast" if fresh else "spread",
			int(opts.get("timer_plus", 0)) if fresh else 0) }

	# operator element
	var mk: String = OPERATORS.get(element, "")
	if mk == "":
		return { "op": "none" }
	if not charged:
		var armed := _entry(0, 0, mk, caster, "cast")                    # arm or replace
		if mk == "gale" and marker == "gale":
			armed["gale_level"] = mini(int(e.get("gale_level", 1)) + 1, int(opts.get("gale_max", 2)))   # D95: gale 2; D293 Jetstream: gale 3
		if mk == "fuse":
			armed.timer += int(opts.get("fuse_plus", 0))                 # D93 Static Field
		return { "op": "set", "entry": armed }
	if glaze > 0 and element == "wind":
		return { "op": "none" }
	return _operate(e.duplicate(), mk, caster, int(opts.get("glaze_plus", 0)))


## An operator acting on a charged entry. `src` is credited for a blast.
## FX hooks: Brimming boosts the water bonus by the water's layer; Shattering
## boosts the shatter by whoever glazed it; Frozen lengthens the glaze.
func _operate(e: Dictionary, mk: String, src: String, glaze_plus: int = 0) -> Dictionary:
	match mk:
		"fuse":
			var water := maxi(-int(e.h), 0)
			var wet := CONDUCT_DET_PCT * water * (pot(Vector2i.ZERO, "water", str(e.get("source", ""))) if water > 0 else 1.0)
			var pct := float(DETONATE_BASE_PCT + DETONATE_PER_POINT_PCT * (absi(e.h) + absi(e.v))) + wet
			if int(e.get("glaze", 0)) > 0:
				pct *= SHATTER_MULT * pot(Vector2i.ZERO, "ice", str(e.get("glaze_source", "")))
			return { "op": "erase", "detonate": pct, "det_source": src, "det_points": absi(e.h) + absi(e.v) }
		"stasis":
			e.glaze = GLAZE_CYCLES + glaze_plus
			e["glaze_source"] = src
			e.permanent = false
			return { "op": "set", "entry": e }
		"gale":
			e.permanent = false
			var lvl := int(e.get("gale_level", 1))
			e.erase("gale_level")
			return { "op": "set", "entry": e, "gale": [e.h, e.v], "gale_level": lvl }
	return { "op": "none" }


## FX hooks: `radius` 2 for Gusting, `timer_plus` for Lingering.
func _gale_copy(origin: Vector2i, hv: Array, caster: String, changed: Array, radius: int = 1, timer_plus: int = 0) -> Array:
	var copies: Array = []
	for n in board.area(origin, radius):
		if n == origin or not can_hold(n) or n in changed:
			continue
		var cur := at(n)
		if not cur.is_empty() and (cur.marker != "" or cur.glaze > 0):
			continue
		var copy := _entry(hv[0], hv[1], "", caster, "spread")
		copy.timer = 1 + timer_plus
		entries[n] = copy
		changed.append(n)
		copies.append(n)
	return copies


## Grass spread (§6.2), plus D93 Wildfire: a `wild` fire (fresh, 2+, laid by
## a Wildfire holder) also seeds fire 1 onto any neighbour whose fire axis is
## neutral, whatever its terrain, under the same once-per-cast flag. Only the
## grass rule dries wet ground; a wild seed skips anything charged.
func _grass_spread() -> Array:
	var seeds := {}                            # hex -> [source, grass?]
	var spent: Array = []
	for hex in entries:
		var e: Dictionary = entries[hex]
		var grass := board.terrain(hex) == BWBoard.GRASSY
		var wild: bool = e.get("wild", false)
		if not (grass or wild) or e.h < GRASS_IGNITE_MIN or (e.origin != "cast" and not wild) or e.glaze > 0:   # D307: a wild eruption ring is spread
			continue
		spent.append(hex)
		for n in board.neighbors(hex):
			var by_grass := grass and board.terrain(n) == BWBoard.GRASSY
			if not (by_grass or (wild and can_hold(n))):
				continue
			if not seeds.has(n) or (by_grass and not seeds[n][1]):
				seeds[n] = [e.source, by_grass]
	for hex in spent:
		entries[hex].origin = "spread"
		entries[hex].erase("wild")
	var seeded: Array = []
	for n in seeds:
		var cur := at(n)
		if not cur.is_empty() and (cur.marker != "" or cur.glaze > 0):
			continue
		var h: int = cur.get("h", 0)
		if h >= 1:
			continue                           # seeds never stack
		if h < 0:                              # wet grass dries instead
			if not seeds[n][1]:
				continue                       # a wild seed doesn't dry anything
			cur.h += 1
			cur.permanent = false                 # a dried authored / seeded hex is ordinary now
			cur.erase("seeded")
			if cur.h == 0 and cur.v == 0:
				entries.erase(n)
			continue
		var seed := _entry(1, int(cur.get("v", 0)), "", seeds[n][0], "spread")
		entries[n] = seed
		seeded.append(n)
	return seeded

class_name BWVfxCasts
extends Node3D
## D167-D169: the cast and spectacle VFX of a BWCombatScreen. A child of the
## screen (not the board, so the cutscene dim never touches it). The screen
## calls in at a few marked points of its playback and awaits the seconds it
## is told; everything here is fire-and-forget after that, run on _process.
##
##   begin(e, tc)          every blow event (from the screen's _tier): remembers
##                         the skill, element, hexes and the D122 tier
##   windup(a)             cast branch, before "cast": the casting circle under
##                         the caster and (FULL) particles converging on the
##                         staff head -> seconds the channel should hold
##   release(a, d, hit)    cast branch, on "release": the element-shaped
##                         release (or the skill's own: Surge, Saturate, Bolt,
##                         Tempest) -> seconds to impact, or -1 = the default
##                         projectile
##   strike_windup(a)      strike branch, on "windup" (Triumph's held gleam)
##   on_strike(a, ts)      strike branch, on "strike" (the spin trail ring)
##   at_release(a, ts)     strike branch, on "release" (Empty the Chamber's fan)
##   impact(a, ts, rs)     every blow's impact frame (Elemental Truth's double
##                         burst, Hundred Fists' afterimages and flashes)
##   setup(a)              a setup beat (no blows): Ley Line, War Cry, Siphon
##   dives(e, queue) / dive(v, path)   Dragoon Dive's leap, fall and crash
##
## Weight (how much plays): NONE under a MINIMAL tier; SHORT = the circle
## flash and the release, no converge; FULL = everything. FULL tier casts,
## and every staff skill above MINIMAL (the author singled out Surge and Ley
## Line; staff skills are cd 2 = SHORT under D122), play FULL. The tier
## already carries the player's cutscene mode (Fast drops one, Minimal
## drops all), so the mode is honoured here for free; setup beats, which are
## always MINIMAL by tier, read the mode directly (Minimal = none).
##
## Pooling: one MultiMesh of POOL particles (one draw call, buffer written
## once a frame) and free lists of quad / disc / ribbon nodes per shader.
## Shaders are flat, alpha-blended, a handful of ALU each (design/art/VFX.md).

enum { NONE, SHORT, FULL }

const POOL := 768
const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "light", "dark"]
const REL_MODE := { "fire": 0, "water": 1, "ice": 2, "thunder": 3, "wind": 4, "light": 5, "dark": 6 }
const SPHERE_MODES := [6, 7, 8, 9]
## Seconds from a release's start to the moment it "hits" (what reactions meet).
const REL_IMPACT := { "fire": 0.12, "water": 0.14, "ice": 0.1, "thunder": 0.06, "wind": 0.2, "light": 0.1, "dark": 0.7 }

var screen: Node                    # BWCombatScreen (untyped: no cyclic class refs)
var ctx := {}                       # the blow event being played: { e, tc, key, row, el, weight }
var stats := { "peak_particles": 0, "peak_nodes": 0 }

# particles: parallel packed arrays, live ones packed at the front
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _n := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _home := PackedVector3Array()
var _pk := PackedFloat32Array()     # homing pull (0 = ballistic)
var _pg := PackedFloat32Array()     # gravity
var _pdrag := PackedFloat32Array()
var _page := PackedFloat32Array()
var _plife := PackedFloat32Array()
var _ps0 := PackedFloat32Array()
var _ps1 := PackedFloat32Array()
var _pcol := PackedColorArray()
var _pshape := PackedFloat32Array()
var _pcore := PackedFloat32Array()
var _prot := PackedFloat32Array()
var _pspin := PackedFloat32Array()
var _pstr := PackedFloat32Array()   # stretch (sparks)
var _ptrack := PackedByteArray()    # 1 = home follows the tracked staff head
var _buf := PackedFloat32Array()
var _track: Node3D = null           # the caster whose weapon tip converging motes chase
var _track_tip := Vector3.ZERO

var _free := {}                     # "quad" / "disc" / "ribbon" -> [MeshInstance3D]
var _recs: Array = []               # live one-shots { node, kind, t, dur, delay, fn }
var _live_nodes := 0

static var _mats := {}
static var _quad_m: QuadMesh
static var _disc_m: PlaneMesh


func _ready() -> void:
	top_level = true                    # positions below are world positions
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	_mm.mesh = qm
	_mm.instance_count = POOL
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vfx_particle.gdshader")
	_mmi.material_override = m
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	_mmi.sorting_offset = 6.0
	add_child(_mmi)
	for arr in [_pos, _vel, _home]:
		arr.resize(POOL)
	for arr in [_pk, _pg, _pdrag, _page, _plife, _ps0, _ps1, _pshape, _pcore, _prot, _pspin, _pstr]:
		arr.resize(POOL)
	_pcol.resize(POOL)
	_ptrack.resize(POOL)
	_buf.resize(POOL * 20)


# ------------------------------------------------------------------ context

## Every blow event: what is playing and how much of it to show.
func begin(e: Dictionary, tc: Dictionary) -> void:
	var key := str(e.get("skill", e.get("pattern", "")))
	var row: Dictionary = BWSkills.get_skill(key) if key != "" else {}
	var el := str(e.get("element", ""))
	ctx = { "e": e, "tc": tc, "key": key, "row": row, "el": el, "weight": weight_for(e, tc, row) }


## Pure: the VFX weight for a blow event under its tier (see the header).
static func weight_for(e: Dictionary, tc: Dictionary, row: Dictionary = {}) -> int:
	if str(e.get("type", "")) != "skill":
		return NONE
	var t := int(tc.get("tier", BWCutsceneTier.MINIMAL))
	if t == BWCutsceneTier.MINIMAL:
		return NONE
	if t == BWCutsceneTier.FULL or str(row.get("weapon", "")) == "staff":
		return FULL
	return SHORT


## Setup beats are MINIMAL by tier; their spectacle follows the mode instead.
static func setup_weight(mode: String) -> int:
	match mode:
		"minimal": return NONE
		"fast": return SHORT
	return FULL


func _el(a: Node = null) -> String:
	var el := str(ctx.get("el", ""))
	if el == "" and a != null and a.get("unit") != null:
		el = str(a.unit.attuned) if str(a.unit.attuned) != "" else str(a.unit.element)
	return el


func _skipping() -> bool:
	return screen != null and bool(screen.get("skipping"))


# ------------------------------------------------------------------ cast hooks

## Before the cast pose: the circle (always, above NONE), the converge (FULL).
## Returns how long the channel should hold for it (0 = keep the default).
func windup(a: Node3D) -> float:
	var w := int(ctx.get("weight", NONE))
	if w == NONE:
		return 0.0
	var el := _el(a)
	var feet: Vector3 = a.global_position + Vector3(0, 0.05, 0)
	var dur := 1.0 if w == FULL else 0.5
	var c := _disc(0, el, feet, 1.45, dur + 0.75)
	c.set_instance_shader_parameter("tier", 1.0 if w == FULL else 0.0)
	if w == SHORT:
		return 0.0
	_track = a
	_track_tip = _tip(a)
	var n := 34
	for i in n:
		var d := float(i) / n * dur * 0.8
		_later(d, func(): _converge_mote(el))
	_later(dur * 0.85, func(): _quad(7, el, _tip(a), Vector2(1.1, 1.1), 0.4))
	if str(ctx.key) == "tempest":
		_clouds(el, dur + 2.4)
	return dur


## Tempest's storm: an inked cloud annulus overhead (the board view sees it
## from above) and a ring of cloud puffs orbiting the area at head height
## (what the low cutscene camera sees), with element flickers inside.
func _clouds(el: String, life: float) -> void:
	var at := _hex(ctx.e.get("target", Vector2i(-1, -1)))
	_disc(3, el, at + Vector3(0, 4.6, 0), 4.9, life)
	var w := 1.25                                      # rad/s; a harmonic pull k = w^2 keeps a circle
	for i in 26:
		var dl := 0.03 * i
		_later(dl, func():
			var ang := randf() * TAU
			var r := randf_range(2.6, 4.2)
			var c := at + Vector3(0, 3.3 + randf_range(-0.3, 0.4), 0)
			var p := c + Vector3(cos(ang), 0, sin(ang)) * r
			var v := Vector3(-sin(ang), 0, cos(ang)) * r * w
			var g: Color = [Color(0.24, 0.24, 0.27), Color(0.4, 0.4, 0.44), Color(0.62, 0.62, 0.66)][i % 3]
			_spawn(p, v, { "home": c, "k": w * w, "life": life - dl, "s0": randf_range(1.1, 1.7), "s1": 1.0, "col": g, "shape": 3, "core": 0.0 }))
	for i in 14:
		_later(0.25 + 0.17 * i, func():
			var ang := randf() * TAU
			var p := at + Vector3(cos(ang) * randf_range(1.5, 4.0), 3.2, sin(ang) * randf_range(1.5, 4.0))
			_quad(8, el, p, Vector2(0.9, 0.9), 0.15))


func _converge_mote(el: String) -> void:
	if _track == null or not is_instance_valid(_track):
		return
	var tip := _tip(_track)
	var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
	var from := tip + dir * randf_range(1.3, 2.0)
	var tangent := dir.cross(Vector3.UP).normalized() * randf_range(2.0, 3.2)
	_spawn(from, tangent, { "home": tip, "k": 26.0, "drag": 2.5, "life": 0.42, "s0": 0.26, "s1": 0.08,
		"col": _col(el), "shape": 0, "core": 0.6, "track": true })


## On the cast's release frame. -1 = no VFX here (the screen's projectile).
func release(a: Node3D, d: Node3D, hit: bool) -> float:
	var w := int(ctx.get("weight", NONE))
	if w == NONE:
		return -1.0
	var el := _el(a)
	_track = null
	_quad(8, el, _tip(a), Vector2(0.9, 0.9), 0.28)
	match str(ctx.key):
		"bolt": return _bolt(el, a, d, hit)
		"surge": return _surge(el, w)
		"saturate": return _pour(el, _hex(ctx.e.get("target", Vector2i(-1, -1))), w)
		"tempest": return _storm(el, w)
	var at: Vector3 = d.global_position if hit else d.global_position + (d.global_position - a.global_position).normalized() * 0.6
	return release_at(el, at, 1.0 if w == FULL else 0.8)


## One element's release at a ground point; returns the seconds to its hit.
func release_at(el: String, at: Vector3, s: float = 1.0, delay: float = 0.0) -> float:
	if not REL_MODE.has(el):
		el = "light" if el == "" else el
	if not REL_MODE.has(el):
		_quad(8, el, at + Vector3(0, 1.0, 0), Vector2(2, 2) * s, 0.4, delay)
		return 0.06 + delay
	var ring := func(r: float, dur: float, dl: float): _disc(1, el, at + Vector3(0, 0.06, 0), r * s, dur, delay + dl)
	match el:
		"fire":
			_quad(0, el, at, Vector2(1.9, 3.6) * s, 1.0, delay)
			ring.call(1.9, 0.6, 0.08)
			_burst_parts(at + Vector3(0, 0.6, 0), el, int(14 * s), delay + 0.1, { "up": 4.5, "spread": 1.4, "g": -2.0, "shape": 2, "life": 0.9, "s0": 0.14 })
		"water":
			_quad(1, el, at, Vector2(1.9, 3.8) * s, 1.1, delay)
			ring.call(2.0, 0.7, 0.1)
			_burst_parts(at + Vector3(0, 3.2 * s, 0), el, int(18 * s), delay + 0.3, { "up": 2.0, "spread": 2.6, "g": 9.0, "shape": 0, "life": 0.9, "s0": 0.16, "core": 0.5 })
		"ice":
			_quad(2, el, at, Vector2(3.0, 3.0) * s, 1.0, delay)
			ring.call(1.8, 0.5, 0.0)
			_burst_parts(at + Vector3(0, 1.0, 0), el, int(16 * s), delay + 0.72, { "up": 2.5, "spread": 3.0, "g": 9.0, "shape": 1, "life": 0.7, "s0": 0.2, "spin": 9.0 })
		"thunder":
			_quad(3, el, at, Vector2(1.6, 10.0) * s, 0.6, delay)
			_quad(8, el, at + Vector3(0, 0.6, 0), Vector2(2.2, 2.2) * s, 0.4, delay + 0.06)
			ring.call(2.1, 0.5, 0.06)
			_burst_parts(at + Vector3(0, 0.4, 0), el, int(14 * s), delay + 0.06, { "up": 3.0, "spread": 4.0, "g": 6.0, "shape": 2, "life": 0.45, "s0": 0.12 })
		"wind":
			_quad(4, el, at, Vector2(2.6, 3.4) * s, 1.1, delay)
			_disc(5, el, at + Vector3(0, 0.15, 0), 1.6 * s, 0.8, delay)
			for i in int(12 * s):
				var dl := delay + 0.05 * i
				_later(dl, func(): _swirl_mote(at, el, s))
		"light":
			_quad(5, el, at, Vector2(1.7, 8.0) * s, 1.1, delay)
			ring.call(1.8, 0.6, 0.05)
			_burst_parts(at + Vector3(0, 0.3, 0), el, int(14 * s), delay + 0.1, { "up": 3.2, "spread": 0.8, "g": -0.5, "shape": 0, "life": 1.0, "s0": 0.13, "core": 0.8 })
		"dark":
			var c := at + Vector3(0, 1.1, 0)
			_quad(6, el, c, Vector2(2.8, 2.8) * s, 1.0, delay)
			for i in int(16 * s):
				var dl := delay + 0.02 * i
				_later(dl, func():
					var dir := Vector3(randf_range(-1, 1), randf_range(-0.7, 1), randf_range(-1, 1)).normalized()
					_spawn(c + dir * 2.0 * s, Vector3.ZERO, { "home": c, "k": 14.0, "drag": 1.5, "life": 0.5, "s0": 0.16, "s1": 0.04, "col": _col(el), "shape": 0, "core": 0.2 }))
			ring.call(2.3, 0.6, 0.72)
	return float(REL_IMPACT[el]) + delay


func _swirl_mote(at: Vector3, el: String, s: float) -> void:
	var a := randf() * TAU
	var r := randf_range(0.5, 1.1) * s
	var p := at + Vector3(cos(a) * r, randf_range(0.2, 0.8), sin(a) * r)
	var tang := Vector3(-sin(a), 0, cos(a)) * 5.0 * s + Vector3(0, 3.5, 0)
	_spawn(p, tang, { "home": at + Vector3(0, 3.0 * s, 0), "k": 6.0, "drag": 0.5, "life": 0.7, "s0": 0.14, "s1": 0.06,
		"col": _col(el), "shape": 2 if randf() < 0.5 else 0, "core": 0.4 })


## Bolt: a quick orb of the element with a trail, a small burst on arrival.
func _bolt(el: String, a: Node3D, d: Node3D, hit: bool) -> float:
	var from := _tip(a)
	var to: Vector3 = d.global_position + Vector3(0, 1.2 * d.scale.y, 0)
	if not hit:
		to += (to - from).normalized() * 1.5 + Vector3(0, 0.4, 0)
	var flight := clampf(from.distance_to(to) / 26.0, 0.12, 0.3)
	var steps := 14
	for i in steps + 1:
		var k := float(i) / steps
		_later(flight * k, func():
			var p := from.lerp(to, k) + Vector3(0, sin(k * PI) * 0.35, 0)
			_spawn(p, Vector3.ZERO, { "life": 0.16, "s0": 0.5, "s1": 0.32, "col": _col(el), "shape": 0, "core": 0.85 })
			_spawn(p + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0), Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)),
				{ "life": 0.32, "s0": 0.18, "s1": 0.02, "col": _col(el), "shape": 0, "core": 0.3 }))
	if hit:
		_quad(8, el, to, Vector2(1.6, 1.6), 0.35, flight)
		_burst_parts(to, el, 10, flight, { "up": 1.0, "spread": 3.0, "g": 4.0, "shape": 2, "life": 0.4, "s0": 0.12 })
	return flight


## Surge: the ring of hexes flares, its charge rushes in, a bigger release
## lands on the centre hex.
func _surge(el: String, w: int) -> float:
	var centre_h: Vector2i = ctx.e.get("target", Vector2i(-1, -1))
	var c := _hex(centre_h)
	var rush := 0.3 if w == FULL else 0.18
	for h in ctx.e.get("hexes", []):
		if h == centre_h:
			continue
		var p := _hex(h)
		_disc(4, el, p + Vector3(0, 0.04, 0), 1.0, 0.6)
		_quad(8, el, p + Vector3(0, 0.5, 0), Vector2(1.0, 1.0), 0.3)
		for i in 5:
			var dl := 0.03 * i
			_later(dl, func():
				_spawn(p + Vector3(randf_range(-0.3, 0.3), 0.4 + randf() * 0.5, randf_range(-0.3, 0.3)), (p - c).normalized() * -2.0 + Vector3(0, 2.0, 0),
					{ "home": c + Vector3(0, 0.9, 0), "k": 40.0, "drag": 3.0, "life": rush + 0.05, "s0": 0.2, "s1": 0.08, "col": _col(el), "shape": 2, "core": 0.5 }))
	_disc(1, el, c + Vector3(0, 0.06, 0), 3.0, 0.8, rush + 0.05)
	_quad(8, el, c + Vector3(0, 1.0, 0), Vector2(3.0, 3.0), 0.45, rush)
	return release_at(el, c, 1.4 if w == FULL else 1.1, rush)


## Saturate: the element pours from above onto the hex and splashes out.
func _pour(el: String, at: Vector3, w: int) -> float:
	var h := 6.5
	_quad(10, el, at, Vector2(0.9, h), 0.95)
	var fall := 0.22
	for i in 22:
		var dl := 0.02 * i
		_later(dl, func():
			_spawn(at + Vector3(randf_range(-0.25, 0.25), h, randf_range(-0.25, 0.25)), Vector3(0, -24, 0),
				{ "g": 10.0, "life": 0.3, "s0": 0.16, "s1": 0.1, "col": _col(el), "shape": 0 if el != "ice" else 1, "core": 0.4 }))
	_disc(4, el, at + Vector3(0, 0.04, 0), 1.0, 0.9, fall)
	_disc(1, el, at + Vector3(0, 0.06, 0), 2.2 if w == FULL else 1.7, 0.7, fall)
	_quad(8, el, at + Vector3(0, 0.4, 0), Vector2(1.8, 1.8), 0.35, fall)
	_burst_parts(at + Vector3(0, 0.2, 0), el, 18, fall, { "up": 4.0, "spread": 3.2, "g": 11.0, "shape": 0, "life": 0.7, "s0": 0.15, "core": 0.5 })
	return fall


## Tempest: the clouds (laid in the windup) throw the element down across
## the 19 hexes, staggered; the victims' hexes land together on the impact.
func _storm(el: String, w: int) -> float:
	var hexes: Array = ctx.e.get("hexes", [])
	var victims := {}
	for r in ctx.e.get("results", []):
		var v: Node3D = (screen.get("_views") as Dictionary).get(str(r.target)) if screen else null
		if v:
			victims[v.unit.pos] = true
	var centre := _hex(ctx.e.get("target", Vector2i(-1, -1)))
	if w != FULL:
		_clouds(el, 2.2)
	var land := 0.75
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ctx.e.get("target", Vector2i.ZERO))
	var hit_at := 0.0
	for h in hexes:
		var p := _hex(h)
		var off := 0.0
		if victims.has(h):
			off = land - float(REL_IMPACT.get(el, 0.1))
		else:
			off = rng.randf_range(0.05, 1.35)
		release_at(el, p, 0.55, maxf(off, 0.0))
		_disc(4, el, p + Vector3(0, 0.04, 0), 1.0, 0.8, maxf(off, 0.0))
	hit_at = land
	_disc(1, el, centre + Vector3(0, 0.07, 0), 5.0, 1.0, land)
	return hit_at


# ------------------------------------------------------------------ strike hooks

## The strike's windup: Triumph holds it heavy with a gleam on the blade.
func strike_windup(a: Node3D) -> float:
	if int(ctx.get("weight", NONE)) == NONE:
		return 0.0
	if str(ctx.key) == "triumph":
		var el := _el(a)
		_later(0.12, func(): _quad(7, el, _tip(a), Vector2(1.6, 1.6), 0.55))
		_disc(1, el, a.global_position + Vector3(0, 0.06, 0), 1.4, 0.6, 0.0)
		_burst_parts(a.global_position + Vector3(0, 0.1, 0), "", 10, 0.0, { "up": 0.8, "spread": 2.2, "g": 2.0, "shape": 3, "life": 0.6, "s0": 0.3 })
		return 0.4
	return 0.0


## The strike begins (clip branch): Whirlwind Blade / Fan of Knives draw
## their spin trail ring for the turn.
func on_strike(a: Node3D, targets: Array) -> void:
	if int(ctx.get("weight", NONE)) == NONE:
		return
	var el := _el(a)
	match str(ctx.key):
		"whirlwind_blade", "fan_of_knives":
			var hit: float = maxf(float(a.call("time_to_marker", "hit")), 0.2)
			var at: Vector3 = a.global_position
			var dur := hit + 0.3
			var r1 := _disc(5, el, at + Vector3(0, 1.0, 0), 1.75, dur)
			r1.set_instance_shader_parameter("seed", 0.2)
			var r2 := _disc(5, el, at + Vector3(0, 0.45, 0), 1.45, dur, 0.05)
			r2.set_instance_shader_parameter("seed", 0.2)
			if str(ctx.key) == "fan_of_knives":
				_later(hit, func():
					for i in 12:
						var ang := TAU * i / 12.0
						var dir := Vector3(cos(ang), 0.05, sin(ang))
						_spawn(at + Vector3(0, 1.0, 0) + dir * 0.5, dir * 12.0, { "life": 0.22, "s0": 0.22, "s1": 0.16, "col": _col(el), "shape": 2, "core": 0.6, "stretch": 2.2, "rot": -ang }))


## On the strike's release frame: Empty the Chamber sweeps a fan of muzzle
## flashes and tracers across its targets, in angle order.
func at_release(a: Node3D, targets: Array) -> void:
	if int(ctx.get("weight", NONE)) == NONE or str(ctx.key) != "empty_the_chamber":
		return
	var el := _el(a)
	var c: Vector3 = a.global_position
	var fwd := -a.global_basis.z
	var order := targets.duplicate()
	order.sort_custom(func(x, y): return _bearing(c, fwd, x.global_position) < _bearing(c, fwd, y.global_position))
	var shots: Array = []
	for i in order.size():
		shots.append(order[i])
		if i < order.size() - 1:
			shots.append(null)           # a stray between targets: the fan reads as a sweep
	for i in shots.size():
		var tv: Node3D = shots[i]
		var dl := 0.065 * i
		_later(dl, func():
			var from := _tip(a)
			var to: Vector3
			if tv != null and is_instance_valid(tv):
				to = tv.global_position + Vector3(0, 1.2, 0)
			else:
				var p0: Vector3 = shots[maxi(i - 1, 0)].global_position if shots[maxi(i - 1, 0)] != null else c + fwd * 3.0
				var p1: Vector3 = shots[mini(i + 1, shots.size() - 1)].global_position if shots[mini(i + 1, shots.size() - 1)] != null else c + fwd * 3.0
				to = (p0 + p1) * 0.5 + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6))
			_quad(8, el, from, Vector2(0.85, 0.85), 0.16)
			_tracer(from, to, el)
			if tv != null:
				_quad(8, el, to, Vector2(0.9, 0.9), 0.22, 0.04)
				_burst_parts(to, el, 5, 0.04, { "up": 1.0, "spread": 2.5, "g": 6.0, "shape": 2, "life": 0.3, "s0": 0.1 }))


static func _bearing(c: Vector3, fwd: Vector3, p: Vector3) -> float:
	var d := p - c
	return atan2(fwd.cross(d).y, fwd.dot(d))


## Every blow's impact frame (quick hits too).
func impact(a: Node3D, targets: Array, results: Array) -> void:
	if targets.is_empty() or a == null:
		return
	var key := str(ctx.get("key", ""))
	var d: Node3D = targets[0]
	if key == "hundred_fists" and BWSettings.value("cutscenes") != "minimal":
		var el := _el(a)
		var back: Vector3 = a.global_position - d.global_position
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3.ZERO
		for k in 4:
			_later(0.03 * k, func(): _ghost(a, el, 0.8 - 0.16 * k, back * (0.16 + 0.14 * k)))
		for k in 3:
			var off := Vector3(randf_range(-0.35, 0.35), 0.9 + randf_range(0.0, 0.7), randf_range(-0.35, 0.35))
			_quad(8, el, d.global_position + off, Vector2(0.75, 0.75), 0.18, 0.03 * k)
		return
	if int(ctx.get("weight", NONE)) == NONE:
		return
	match key:
		"elemental_truth":
			var el := _el(a)
			release_at(el, d.global_position, 0.65, 0.0)
			release_at(el, d.global_position, 1.0, 0.17)
			_quad(8, el, d.global_position + Vector3(0, 1.1, 0), Vector2(2.2, 2.2), 0.4, 0.17)


# ------------------------------------------------------------------ setup beats

## A setup skill in place (no blows). Seconds to hold, or 0 when nothing.
func setup(a: Node3D) -> float:
	var w := setup_weight(str(BWSettings.value("cutscenes")))
	if w == NONE or ctx.is_empty():
		return 0.0
	match str(ctx.key):
		"ley_line": return _ley_line(a, w)
		"war_cry": return _war_cry(a, w)
		"siphon": return _siphon(a, w)
	return 0.0


## Ley Line: the circle flashes, a glowing line races out hex by hex laying
## the element with a travelling wave, allies on it flash "+1 move".
func _ley_line(a: Node3D, w: int) -> float:
	var el := _el(a)
	var hexes: Array = ctx.e.get("hexes", [])
	var step := 0.1 if w == FULL else 0.06
	_disc(0, el, a.global_position + Vector3(0, 0.05, 0), 1.45, 0.55 + hexes.size() * step)
	_quad(8, el, _tip(a), Vector2(1.0, 1.0), 0.3)
	var prev: Vector3 = a.global_position + Vector3(0, 0.12, 0)
	var swift := {}
	var team := str(a.unit.team)
	if screen and screen.get("battle"):
		for u in screen.battle.units:
			if u.alive() and u.team == team and u.id != a.unit.id and u.pos in hexes:
				swift[u.pos] = u.id
	for i in hexes.size():
		var h: Vector2i = hexes[i]
		var p := _hex(h) + Vector3(0, 0.12, 0)
		var from := prev
		var dl := 0.12 + i * step
		_later(dl, func():
			_line_seg(from, p, el, 0.9 + (hexes.size() - i) * step)
			_disc(4, el, p + Vector3(0, -0.07, 0), 1.0, 1.1)
			_quad(8, el, p + Vector3(0, 0.25, 0), Vector2(0.7, 0.7), 0.22)
			for k in 3:
				_spawn(p + Vector3(randf_range(-0.4, 0.4), 0.05, randf_range(-0.4, 0.4)), Vector3(0, randf_range(1.5, 3.0), 0),
					{ "life": 0.6, "s0": 0.13, "s1": 0.03, "col": _col(el), "shape": 0, "core": 0.6 }))
		# the wave: a second, brighter pulse runs the line once it is laid
		_later(dl + 0.25 + hexes.size() * step * 0.4, func():
			_disc(1, el, p + Vector3(0, -0.06, 0), 1.0, 0.45))
		if swift.has(h):
			var uid: String = swift[h]
			_later(dl + 0.08, func(): _swift_glyph(uid, el))
		prev = p
	return 0.25 + hexes.size() * step + 0.45


func _line_seg(from: Vector3, to: Vector3, el: String, dur: float) -> void:
	var mi := _take("ribbon")
	mi.mesh = _strip([from, to], 0.36, _col(el), 1.0, true)
	mi.material_override = _mat("ribbon", 0, "")
	mi.set_instance_shader_parameter("tier", 1.0)
	_add_rec(mi, dur, 0.0)


func _swift_glyph(uid: String, el: String) -> void:
	var v: Node3D = (screen.get("_views") as Dictionary).get(uid) if screen else null
	if v == null:
		return
	_quad(8, el, v.global_position + Vector3(0, 1.1, 0), Vector2(2.0, 2.0), 0.35)
	_disc(1, el, v.global_position + Vector3(0, 0.08, 0), 1.3, 0.5)
	var l := Label3D.new()
	l.text = "▲ +1 MOVE"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 24
	l.outline_size = 10
	l.modulate = BWLook.element_color(el) if el != "dark" else Color.WHITE
	l.outline_modulate = Color.BLACK
	l.render_priority = 22
	l.outline_render_priority = 21
	add_child(l)
	l.global_position = v.global_position + Vector3(0, 2.6 * v.scale.y, 0)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).from(Vector3.ONE * 1.6)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.5, 0), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


## War Cry: a shout shockwave (ground rings, rings round the head) and an aura.
func _war_cry(a: Node3D, w: int) -> float:
	var el := str(a.unit.element)
	var at: Vector3 = a.global_position
	_disc(1, el, at + Vector3(0, 0.06, 0), 3.2, 0.7)
	_disc(1, el, at + Vector3(0, 0.06, 0), 2.2, 0.6, 0.12)
	_quad(9, el, at + Vector3(0, 2.0 * a.scale.y, 0), Vector2(3.4, 3.4), 0.6)
	if w == FULL:
		_disc(6, el, at + Vector3(0, 0.05, 0), 1.3, 1.6)
		for i in 14:
			_later(0.06 * i, func():
				var ang := randf() * TAU
				_spawn(at + Vector3(cos(ang) * 0.6, 0.1, sin(ang) * 0.6), Vector3(0, randf_range(1.8, 3.0), 0),
					{ "life": 0.7, "s0": 0.14, "s1": 0.04, "col": _col(el), "shape": 2, "core": 0.7 }))
	if screen and screen.has_method("_shake"):
		screen.call("_shake", 0.06)
	return 0.55


## Siphon: the hex's charge rises out of it in a stream into the caster.
func _siphon(a: Node3D, w: int) -> float:
	var h: Vector2i = ctx.e.get("target", Vector2i(-1, -1))
	var at := _hex(h)
	var els: Array = []
	if screen and screen.get("board_view"):
		var st: Dictionary = screen.board_view.fx_state(h)
		for k in ["h", "v"]:
			if not (st.get(k, {}) as Dictionary).is_empty():
				els.append(str(st[k].el))
	if els.is_empty():
		els = [_el(a) if _el(a) != "" else "light"]
	_disc(4, els[0], at + Vector3(0, 0.04, 0), 1.0, 0.9)
	_track = a
	var n := 30 if w == FULL else 16
	var dur := 0.75 if w == FULL else 0.45
	for i in n:
		var el: String = els[i % els.size()]
		_later(dur * float(i) / n, func():
			var p := at + Vector3(randf_range(-0.5, 0.5), 0.05, randf_range(-0.5, 0.5))
			_spawn(p, Vector3(0, randf_range(4.0, 6.0), 0), { "home": _tip(a), "k": 9.0, "drag": 1.2, "life": 0.6, "s0": 0.18, "s1": 0.06,
				"col": _col(el), "shape": 0, "core": 0.5, "track": true }))
	_later(dur, func():
		_quad(8, els[0], _tip(a), Vector2(1.3, 1.3), 0.35)
		_disc(1, els[0], a.global_position + Vector3(0, 0.06, 0), 1.6, 0.5))
	return dur + 0.35


# ------------------------------------------------------------------ Dragoon Dive

## True when this leap is Dragoon Dive's and its tier allows the spectacle.
func dives(e: Dictionary, queue: Array) -> bool:
	for q in queue:
		if str(q.get("type", "")) == "skill":
			if str(q.get("skill", "")) != "dragoon_dive" or str(q.get("unit", "")) != str(e.get("unit", "")):
				return false
			var tc := BWCutsceneTier.tier_for(q, str(BWSettings.value("cutscenes")))
			return int(tc.tier) != BWCutsceneTier.MINIMAL
	return false


## Leap up out of frame, a shadow grows on the landing hex, a crash with a
## shockwave ring and debris.
func dive(v: Node3D, path: Array) -> void:
	var el := str(v.unit.attuned) if str(v.unit.attuned) != "" else str(v.unit.element)
	for q in screen._queue:
		if str(q.get("type", "")) == "skill":
			el = str(q.get("element", el))
			break
	var from: Vector3 = screen._unit_pos(path[0])
	var to: Vector3 = screen._unit_pos(path[path.size() - 1])
	v.face(to)
	v.pose_named("windup")
	await get_tree().create_timer(0.18).timeout
	_disc(1, "", from + Vector3(0, 0.06, 0), 1.6, 0.5)
	_burst_parts(from + Vector3(0, 0.1, 0), "", 10, 0.0, { "up": 1.5, "spread": 2.5, "g": 3.0, "shape": 3, "life": 0.6, "s0": 0.3 })
	var d0: float = screen.rig.dist if screen.rig else 0.0
	if screen.rig:
		screen.rig.follow(to)
		var push := create_tween()
		push.tween_property(screen.rig, "dist", d0 * 0.72, 0.5).set_trans(Tween.TRANS_CUBIC)
	var up := create_tween()
	up.tween_property(v, "position", from.lerp(to, 0.35) + Vector3(0, 16, 0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await up.finished
	var sh := _disc(2, el, to + Vector3(0, 0.05, 0), 1.5, 1.2)
	var grow := create_tween()
	grow.tween_method(func(k: float):
		if is_instance_valid(sh):
			sh.set_instance_shader_parameter("tier", k), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.42).timeout
	v.position = to + Vector3(0, 16, 0)
	v.pose_named("strike")
	var down := create_tween()
	down.tween_property(v, "position", to, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await down.finished
	# the crash
	_disc(1, el, to + Vector3(0, 0.07, 0), 3.6, 0.75)
	_disc(1, "", to + Vector3(0, 0.07, 0), 2.4, 0.6, 0.08)
	_quad(8, el, to + Vector3(0, 0.6, 0), Vector2(2.6, 2.6), 0.4)
	_burst_parts(to + Vector3(0, 0.2, 0), "", 18, 0.0, { "up": 5.5, "spread": 4.5, "g": 14.0, "shape": 1, "life": 0.9, "s0": 0.22, "spin": 10.0, "grey": true })
	_burst_parts(to + Vector3(0, 0.2, 0), el, 10, 0.0, { "up": 4.5, "spread": 4.0, "g": 12.0, "shape": 1, "life": 0.8, "s0": 0.18, "spin": 10.0 })
	_burst_parts(to + Vector3(0, 0.15, 0), "", 12, 0.02, { "up": 0.8, "spread": 3.5, "g": 1.0, "shape": 3, "life": 0.8, "s0": 0.38 })
	if screen.feel:
		screen.feel.shake(0.14)
	v.pose_named("land" if v.has_clip("land") else "kneel")   # D221: the leap's landing, not the KO kneel
	await get_tree().create_timer(0.3).timeout
	if screen.rig:
		var back := create_tween()
		back.tween_property(screen.rig, "dist", d0, 0.45).set_trans(Tween.TRANS_SINE)
	v.idle()


# ------------------------------------------------------------------ afterimages

## A stick-figure ghost of the unit's pose right now: the limbs as inked
## white strips (the striking arm in the element), fading.
func _ghost(v: Node3D, el: String, opacity: float, shift: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(v) or v.get("character") == null:
		return
	var ch = v.character
	var sk: Skeleton3D = ch.rig.skeleton if ch.rig else null
	if sk == null:
		return
	var P := func(b: String) -> Vector3:
		var i := sk.find_bone(b)
		return (sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else v.global_position) + shift
	var col := _col(el)
	var chains := [
		["hips", "spine", "chest", "neck"],
		["chest", "upper_arm_r", "forearm_r", "hand_r"],
		["chest", "upper_arm_l", "forearm_l", "hand_l"],
		["hips", "thigh_r", "shin_r", "foot_r"],
		["hips", "thigh_l", "shin_l", "foot_l"],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3(0, 10, 10)
	for ci in chains.size():
		var pts: Array = []
		for b in chains[ci]:
			pts.append(P.call(b))
		var hand: Vector3 = pts[pts.size() - 1]
		pts[pts.size() - 1] = hand + (hand - pts[pts.size() - 2]).normalized() * 0.12
		var tint := 0.75 if ci == 1 else (0.35 if ci == 2 else 0.0)
		_strip_into(st, pts, 0.17, Color(col.r, col.g, col.b, tint), eye)
	var head := P.call("head") as Vector3
	_spawn(head + Vector3(0, 0.22, 0), Vector3.ZERO, { "life": 0.28, "s0": 0.5, "s1": 0.48, "col": Color(1, 1, 1, opacity), "shape": 0, "core": 1.0 })
	var mi := _take("ribbon")
	mi.mesh = st.commit()
	mi.material_override = _mat("ribbon", 0, "")
	mi.set_instance_shader_parameter("tier", opacity)
	_add_rec(mi, 0.28, 0.0)


func _tracer(from: Vector3, to: Vector3, el: String) -> void:
	var mi := _take("ribbon")
	mi.mesh = _strip([from, to], 0.07, _col(el), 0.5, false)
	mi.material_override = _mat("ribbon", 0, "")
	mi.set_instance_shader_parameter("tier", 1.0)
	_add_rec(mi, 0.2, 0.0)


# ------------------------------------------------------------------ primitives

func _tip(a: Node3D) -> Vector3:
	if a == null or not is_instance_valid(a):
		return Vector3.ZERO
	var t: Vector3 = a.call("weapon_tip") if a.has_method("weapon_tip") else a.global_position + Vector3(0, 1.3, 0)
	if t.distance_to(a.global_position) > 3.5 or t.y < a.global_position.y + 0.3:
		t = a.global_position + Vector3(0, 1.5, 0)
	return t


func _hex(h: Variant) -> Vector3:
	if screen and h is Vector2i and screen.get("board_view") and screen.board_view.board and screen.board_view.board.exists(h):
		return screen.board_view.top_center(h)
	return Vector3.ZERO


static func _col(el: String) -> Color:
	if el == "" or not el in ELEMENTS:
		return Color(0.86, 0.86, 0.88)
	return BWLook.element_color(el)


func _mat(kind: String, mode: int, el: String) -> ShaderMaterial:
	var key := "%s:%d:%s" % [kind, mode, el]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	match kind:
		"quad":
			m.shader = load("res://shaders/vfx_column.gdshader")
			m.set_shader_parameter("sphere", mode in SPHERE_MODES)
		"disc":
			m.shader = load("res://shaders/vfx_ground.gdshader")
		"ribbon":
			m.shader = load("res://shaders/vfx_ribbon.gdshader")
	if kind != "ribbon":
		m.set_shader_parameter("mode", mode)
		m.set_shader_parameter("glow", _col(el))
	_mats[key] = m
	return m


func _take(kind: String) -> MeshInstance3D:
	var list: Array = _free.get(kind, [])
	var mi: MeshInstance3D
	if not list.is_empty():
		mi = list.pop_back()
	else:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.sorting_offset = 5.0
		mi.set_meta("vfx_kind", kind)
		if kind == "quad":
			if _quad_m == null:
				_quad_m = QuadMesh.new()
				_quad_m.size = Vector2(1, 1)
			mi.mesh = _quad_m
			mi.custom_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		elif kind == "disc":
			if _disc_m == null:
				_disc_m = PlaneMesh.new()
				_disc_m.size = Vector2(2, 2)
			mi.mesh = _disc_m
		add_child(mi)
	mi.visible = false
	mi.scale = Vector3.ONE
	mi.set_instance_shader_parameter("age", 0.0)
	mi.set_instance_shader_parameter("seed", randf())
	return mi


func _give(mi: MeshInstance3D) -> void:
	mi.visible = false
	var kind := str(mi.get_meta("vfx_kind", "quad"))
	if kind == "ribbon":
		mi.mesh = null
	if not _free.has(kind):
		_free[kind] = []
	(_free[kind] as Array).append(mi)


func _add_rec(mi: MeshInstance3D, dur: float, delay: float) -> void:
	mi.visible = delay <= 0.0
	_recs.append({ "node": mi, "t": 0.0, "dur": maxf(dur, 0.01), "delay": delay })


## A release / flash quad: columns stand on `at`, sphere modes centre on it.
func _quad(mode: int, el: String, at: Vector3, size: Vector2, dur: float, delay: float = 0.0) -> MeshInstance3D:
	var mi := _take("quad")
	mi.material_override = _mat("quad", mode, el)
	mi.position = at
	mi.scale = Vector3(size.x, size.y, 1.0)
	_add_rec(mi, dur, delay)
	return mi


func _disc(mode: int, el: String, at: Vector3, radius: float, dur: float, delay: float = 0.0) -> MeshInstance3D:
	var mi := _take("disc")
	mi.material_override = _mat("disc", mode, el)
	mi.position = at
	mi.scale = Vector3(radius, 1.0, radius)
	mi.set_instance_shader_parameter("tier", 1.0)
	_add_rec(mi, dur, delay)
	return mi


## Run `f` after `delay` seconds of game time (skipping speeds it up too).
func _later(delay: float, f: Callable) -> void:
	if delay <= 0.0:
		f.call()
		return
	_recs.append({ "node": null, "t": 0.0, "dur": 0.0, "delay": delay, "fn": f })


## A camera-facing strip through `pts` (ribbon shader UVs).
func _strip(pts: Array, w: float, col: Color, tint: float, flat: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3(0, 10, 10)
	if flat:
		eye = Vector3.INF
	_strip_into(st, pts, w, Color(col.r, col.g, col.b, tint), eye)
	return st.commit()


func _strip_into(st: SurfaceTool, pts: Array, w: float, col: Color, eye: Vector3) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0)
		if d.length() < 0.001:
			continue
		var side: Vector3
		if eye == Vector3.INF:
			side = d.cross(Vector3.UP).normalized()          # lies on the ground
		else:
			side = d.cross(eye - (p0 + p1) * 0.5).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side *= w * 0.5
		# overlap the joints a little so a bent limb has no gap
		var ext := d.normalized() * w * 0.35
		var a0 := p0 - ext
		var a1 := p1 + ext
		var quad := [[a0 - side, Vector2(0, 0)], [a0 + side, Vector2(0, 1)], [a1 + side, Vector2(1, 1)],
			[a0 - side, Vector2(0, 0)], [a1 + side, Vector2(1, 1)], [a1 - side, Vector2(1, 0)]]
		for v in quad:
			st.set_color(col)
			st.set_uv(v[1])
			st.add_vertex(v[0])


# ------------------------------------------------------------------ particles

## One particle. opts: home, k, g, drag, life, s0, s1, col, shape, core,
## rot, spin, stretch, track.
func _spawn(p: Vector3, v: Vector3, o: Dictionary) -> void:
	if _n >= POOL:
		return
	var i := _n
	_n += 1
	_pos[i] = p
	_vel[i] = v
	_home[i] = o.get("home", p)
	_pk[i] = float(o.get("k", 0.0))
	_pg[i] = float(o.get("g", 0.0))
	_pdrag[i] = float(o.get("drag", 0.0))
	_page[i] = 0.0
	_plife[i] = maxf(float(o.get("life", 0.5)), 0.01)
	_ps0[i] = float(o.get("s0", 0.15))
	_ps1[i] = float(o.get("s1", o.get("s0", 0.15)))
	_pcol[i] = o.get("col", Color.WHITE)
	_pshape[i] = float(o.get("shape", 0))
	_pcore[i] = float(o.get("core", 0.0))
	_prot[i] = float(o.get("rot", randf() * TAU))
	_pspin[i] = float(o.get("spin", 0.0)) * (1.0 if randf() < 0.5 else -1.0)
	_pstr[i] = float(o.get("stretch", 1.0))
	_ptrack[i] = 1 if o.get("track", false) else 0
	stats.peak_particles = maxi(int(stats.peak_particles), _n)


## A burst of n particles from p. opts: up, spread, g, shape, life, s0, core, spin, grey.
func _burst_parts(p: Vector3, el: String, n: int, delay: float, o: Dictionary) -> void:
	var f := func():
		for i in n:
			var ang := randf() * TAU
			var sp := float(o.get("spread", 2.0)) * randf_range(0.4, 1.0)
			var v := Vector3(cos(ang) * sp, float(o.get("up", 2.0)) * randf_range(0.5, 1.0), sin(ang) * sp)
			var c := _col(el)
			if o.get("grey", false):
				c = [Color(0.95, 0.95, 0.95), Color(0.55, 0.55, 0.57), Color(0.2, 0.2, 0.22)][i % 3]
			_spawn(p, v, { "g": float(o.get("g", 4.0)), "drag": 0.6, "life": float(o.get("life", 0.6)) * randf_range(0.7, 1.0),
				"s0": float(o.get("s0", 0.14)), "s1": float(o.get("s0", 0.14)) * 0.3, "col": c, "shape": int(o.get("shape", 0)),
				"core": float(o.get("core", 0.3)), "spin": float(o.get("spin", 0.0)),
				"stretch": 2.0 if int(o.get("shape", 0)) == 2 else 1.0, "rot": randf() * TAU })
	_later(delay, f)


func _kill(i: int) -> void:
	var j := _n - 1
	if i != j:
		_pos[i] = _pos[j]; _vel[i] = _vel[j]; _home[i] = _home[j]; _pk[i] = _pk[j]; _pg[i] = _pg[j]
		_pdrag[i] = _pdrag[j]; _page[i] = _page[j]; _plife[i] = _plife[j]; _ps0[i] = _ps0[j]; _ps1[i] = _ps1[j]
		_pcol[i] = _pcol[j]; _pshape[i] = _pshape[j]; _pcore[i] = _pcore[j]; _prot[i] = _prot[j]
		_pspin[i] = _pspin[j]; _pstr[i] = _pstr[j]; _ptrack[i] = _ptrack[j]
	_n -= 1


func _process(dt: float) -> void:
	# one-shots and scheduled calls
	var i := 0
	var live := 0
	while i < _recs.size():
		var r: Dictionary = _recs[i]
		if float(r.delay) > 0.0:
			r.delay = float(r.delay) - dt
			if float(r.delay) > 0.0:
				i += 1
				continue
			if r.node == null:
				_recs.remove_at(i)
				(r.fn as Callable).call()
				continue
			(r.node as MeshInstance3D).visible = true
		if r.node == null:
			_recs.remove_at(i)
			continue
		var mi: MeshInstance3D = r.node
		if not is_instance_valid(mi):
			_recs.remove_at(i)
			continue
		r.t = float(r.t) + dt
		var k := float(r.t) / float(r.dur)
		mi.set_instance_shader_parameter("age", minf(k, 1.0))
		if k >= 1.0:
			_recs.remove_at(i)
			_give(mi)
			continue
		live += 1
		i += 1
	stats.peak_nodes = maxi(int(stats.peak_nodes), live)
	# particles
	if _track != null and is_instance_valid(_track):
		_track_tip = _tip(_track)
	var p := 0
	while p < _n:
		_page[p] += dt
		if _page[p] >= _plife[p]:
			_kill(p)
			continue
		var v := _vel[p]
		if _pk[p] > 0.0:
			var h := _track_tip if _ptrack[p] == 1 else _home[p]
			var to := h - _pos[p]
			v += to * _pk[p] * dt
			if to.length() < 0.12 and _ptrack[p] == 1:
				_page[p] = _plife[p]
		v.y -= _pg[p] * dt
		v *= maxf(0.0, 1.0 - _pdrag[p] * dt)
		_vel[p] = v
		_pos[p] += v * dt
		_prot[p] += _pspin[p] * dt
		p += 1
	_write()


func _write() -> void:
	var cam := get_viewport().get_camera_3d()
	for i in _n:
		var k := _page[i] / _plife[i]
		var s := lerpf(_ps0[i], _ps1[i], k)
		var rot := _prot[i]
		if _pshape[i] == 2.0 and cam:
			# sparks lie along their velocity on screen
			var a := cam.unproject_position(_pos[i])
			var b := cam.unproject_position(_pos[i] + _vel[i] * 0.05)
			if a.distance_to(b) > 0.5:
				rot = atan2(-(b.y - a.y), b.x - a.x) - PI * 0.5
		var o := i * 20
		_buf[o] = s; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = _pos[i].x
		_buf[o + 4] = 0.0; _buf[o + 5] = s; _buf[o + 6] = 0.0; _buf[o + 7] = _pos[i].y
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = s; _buf[o + 11] = _pos[i].z
		var c := _pcol[i]
		_buf[o + 12] = c.r; _buf[o + 13] = c.g; _buf[o + 14] = c.b
		_buf[o + 15] = c.a * (1.0 - smoothstep(0.6, 1.0, k))
		_buf[o + 16] = _pshape[i]; _buf[o + 17] = _pcore[i]; _buf[o + 18] = rot; _buf[o + 19] = _pstr[i]
	_mm.buffer = _buf
	_mm.visible_instance_count = _n


## Live counts (probes, the perf readout).
func live() -> Dictionary:
	var nodes := 0
	for r in _recs:
		if r.node != null and float(r.delay) <= 0.0:
			nodes += 1
	return { "particles": _n, "nodes": nodes, "pending": _recs.size() }

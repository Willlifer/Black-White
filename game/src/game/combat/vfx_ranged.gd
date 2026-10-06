class_name BWRangedVFX
extends Node3D
## D165: arrows (and thrown blades) for the combat screen. One node owns a
## POOL of arrow views and drives every flight, stuck arrow, pin and burst
## from a single _process: nothing is instanced mid-volley, so Rain of
## Arrows doesn't hitch (tools/ranged_shots.gd measures it).
##
## Flights (BWProjectileView "arrow": B/W, the vanes tinted by the shot's
## element when it carries one, plain white otherwise):
##   flat      nock -> chest, straight and fast (FLAT_SPEED) with a faint
##             trail; a hit sinks in and rides the chest bone, a miss flies
##             past and skitters along the ground behind the target
##   ballistic Arcing Shot: one arrow on a tall arc to the centre hex, then
##             the impact burst over the blast hexes (a white flash, the hexes
##             lit from the centre out, ink debris, a shake)
##   up / down Rain of Arrows: the volley leaves the bow skyward (one arrow
##             per release marker); a shadow sweeps over the 19 hexes; then
##             2-4 arrows per hex fall over ~1 s (hold-to-skip collapses it)
##   fan       Split Arrow: the three arrows on the string, one per foe (or
##             down the side headings into the ground when a lane is empty)
##   pierce    Energized Shot: through the first foe, on through the pierced
##             one, into the ground beyond
##   pin       Pinning Shot: into the ground at the target's feet; it stays
##             there while the target is Pinned
##   blade     Dualthrow: the dagger spins end over end into the target
## Stuck arrows fade (sink and shrink) STUCK_LIFE seconds after they land.
##
## The combat screen hooks in at three points (marked "D165"): it creates
## this node, sets `context` to the skill event it is playing, routes its
## projectiles through shoot(), and hands Arcing Shot / Rain to play_area().

const POOL := 96
const FLAT_SPEED := 34.0
const BLADE_SPEED := 20.0
const STUCK_LIFE := 1.5
const FADE := 0.3
const SINK_UNIT := 0.16
const SINK_GROUND := 0.2
const RAIN_STAGGER := 1.0          # seconds over which the rain lands
const RAIN_FALL := 0.24            # each falling arrow is seen this long
const SKY_RISE := 0.55             # a volley arrow climbing out of frame
const AREA_SKILLS := ["arcing_shot", "rain_of_arrows"]
const THROWN := ["dualthrow", "dualthrow_second"]

var screen: Node                   # BWCombatScreen
## The skill event being played ({} = a basic shot). Setting it loads the
## shooter's string: the nocked arrows' fletching takes the skill's element.
var context := {}:
	set(v):
		context = v
		_load_string(v)
var _nock_view: Node3D
var _pool: Array[BWProjectileView] = []
var _live: Array = []              # flight / stuck records (see _rec)
var _fx: Array = []                # [node, age, life, kind, data]
var _blades := {}                  # weapon id -> Array[BWWeaponView] (free ones)
var _trail_mesh: ArrayMesh
var _trail_mat: StandardMaterial3D
var _plate_mat: StandardMaterial3D
var _debris_mesh: BoxMesh
var _debris_mat: StandardMaterial3D
static var _flash_shader: Shader
static var _shadow_shader: Shader
var stats := { "created": 0, "max_live": 0 }   # tools: pool health


# ------------------------------------------------------------------ pool

func _ready() -> void:
	name = "ranged_vfx"
	_trail_mesh = _make_trail_mesh()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = false
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.07, 0.05, 0.11)
	_debris_mat = StandardMaterial3D.new()
	_debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debris_mat.albedo_color = Color(0.08, 0.08, 0.08)


## Instance n arrow views now (combat start: only when someone holds a bow).
func prewarm(n: int = POOL) -> void:
	while _pool.size() < n:
		var v := _new_arrow()
		if v == null:
			return
		_pool.append(v)


func _new_arrow() -> BWProjectileView:
	var v := BWProjectileView.create_projectile("arrow")
	if v == null:
		return null
	v.visible = false
	add_child(v)
	var tr := MeshInstance3D.new()
	tr.name = "trail"
	tr.mesh = _trail_mesh
	tr.material_override = _trail_mat
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tr.position = Vector3(0, 0, -v.length())
	tr.visible = false
	v.add_child(tr)
	stats.created += 1
	return v


func _take(element: String) -> BWProjectileView:
	var v: BWProjectileView = _pool.pop_back() if not _pool.is_empty() else _new_arrow()
	if v == null:
		return null
	v.scale = Vector3.ONE
	v.set_accent(element)
	v.visible = true
	(v.get_node("trail") as Node3D).visible = false
	return v


func _give(v: Node3D) -> void:
	if not is_instance_valid(v):
		return
	v.visible = false
	v.scale = Vector3.ONE
	if v is BWProjectileView:
		_pool.append(v)
	elif v.has_meta("blade_id"):
		var id := str(v.get_meta("blade_id"))
		if not _blades.has(id):
			_blades[id] = []
		_blades[id].append(v)


func _load_string(e: Dictionary) -> void:
	if is_instance_valid(_nock_view) and _nock_view.character:
		_nock_view.character.nock_element = null
	_nock_view = null
	if e.is_empty() or screen == null:
		return
	var v: Variant = screen._views.get(str(e.get("unit", "")))
	if v is BWUnitView and (v as BWUnitView).character:
		_nock_view = v
		(v as BWUnitView).character.nock_element = str(e.get("element", ""))


## Free arrows in the pool right now (tools).
func pool_free() -> int:
	return _pool.size()


func live_count() -> int:
	return _live.size()


# ------------------------------------------------------------ the hooks

## True when the attacker's projectile should come from here: every bow
## shot (elemental or not: an element-loaded arrow is still an arrow), and a
## dagger thrown by Dualthrow. `_spell` (the screen's "send a bolt" flag) is
## ignored: only the weapon decides.
func handles(a: Node3D, _spell: bool = false) -> bool:
	if a == null or not "unit" in a or a.unit == null:
		return false
	var cls := str(a.unit.weapon_class)
	if cls == "bow":
		return true
	return cls == "daggers" and str(context.get("skill", "")) in THROWN


## Skills this node plays whole (camera, clip, arrows, impacts).
func owns(e: Dictionary) -> bool:
	if str(e.get("type", "")) != "skill" or not str(e.get("skill", "")) in AREA_SKILLS:
		return false
	var v: Node3D = screen._views.get(str(e.get("unit", ""))) if screen else null
	return v != null and handles(v)


## The clip a shooter plays for the current context ("" = the class strike).
static func clip_for(skill_key: String) -> String:
	match skill_key:
		"aimed_shot": return "shot_aimed"
		"retreating_shot": return "shot_quick"
		"arcing_shot": return "shot_sky"
		"rain_of_arrows": return "shot_volley"
		"split_arrow": return "shot_fan"
	return ""


## Launch the current shot from attacker view `a` at defender view `d` and
## return the seconds to the (first) impact. `element` tints the fletching
## ("" = plain). Never awaits.
func shoot(a: BWUnitView, d: BWUnitView, element: String = "", hit: bool = true) -> float:
	var key := str(context.get("skill", ""))
	if str(a.unit.weapon_class) == "daggers":
		return _throw_blade(a, d, hit)
	var nocks: Array = []
	if a.character:
		nocks = a.character.nocked_arrows()
	var from: Transform3D = nocks[0] if not nocks.is_empty() else _fallback_from(a, d)
	match key:
		"split_arrow":
			return _shoot_fan(a, d, nocks, from, element)
		"energized_shot":
			return _shoot_pierce(a, d, from, element, hit)
		"pinning_shot":
			return _shoot_pin(a, d, from, element, hit)
	return _shoot_flat(from, d, element, hit)


func _fallback_from(a: BWUnitView, d: Node3D) -> Transform3D:
	var p: Vector3 = a.weapon_tip() if a.has_method("weapon_tip") else a.global_position + Vector3(0, 1.3, 0)
	if p.distance_to(a.global_position) > 3.5:
		p = a.global_position + Vector3(0, 1.3, 0)
	return Transform3D(_look(_chest(d) - p), p)


# ------------------------------------------------------------ the shots

func _shoot_flat(from: Transform3D, d: Node3D, element: String, hit: bool) -> float:
	var to := _chest(d)
	if hit:
		return _fly([from.origin, to], from.basis, element, { "stick": "unit", "target": d, "trail": true })
	return _fly(_miss_path(from.origin, to, d), from.basis, element, { "stick": "skitter", "trail": true }) * 0.8


## A miss: past the target (high and to one side), down into the ground
## 1.5-2.5 behind it.
func _miss_path(p0: Vector3, chest: Vector3, d: Node3D) -> Array:
	var dir := chest - p0
	dir.y = 0
	dir = dir.normalized() if dir.length() > 1e-3 else Vector3.BACK
	var side := dir.cross(Vector3.UP).normalized()
	var s := 1.0 if (hash(str(d.get_instance_id()) + str(Time.get_ticks_msec() / 997)) & 1) == 0 else -1.0
	var past := chest + side * 0.42 * s + Vector3(0, 0.22, 0)
	var land := chest + dir * 2.0 + side * 0.6 * s
	land.y = _ground_y(land)
	return [p0, past, land]


func _shoot_fan(a: BWUnitView, d: Node3D, nocks: Array, from: Transform3D, element: String) -> float:
	var results: Array = context.get("results", [])
	var first := 0.0
	var lanes: Array = []           # [target view or null, hit]
	for r in results:
		lanes.append([screen._views.get(str(r.target)), bool((r.result as Dictionary).get("hit", true))])
	# the centre arrow is the clicked foe's; the sides go to the other foes or
	# down the neighbouring headings into the ground
	var heading := _chest(d) - from.origin
	heading.y = 0
	var dist := heading.length()
	heading = heading.normalized() if dist > 1e-3 else Vector3.BACK
	var order := [1, 0, 2]          # the string's arrows: index 1 is the centre one
	var side_foes := lanes.slice(1)
	for k in 3:
		var src: Transform3D = nocks[order[k]] if order[k] < nocks.size() else from
		var t := 0.0
		if k == 0 and not lanes.is_empty():
			t = _fly_to_unit(src, lanes[0][0], element, lanes[0][1])
			first = t
		elif k > 0 and side_foes.size() >= k and side_foes[k - 1][0] != null:
			_fly_to_unit(src, side_foes[k - 1][0], element, side_foes[k - 1][1])
		else:
			var ang := (-1.0 if k == 1 else 1.0) * PI / 3.0
			var dirk := heading.rotated(Vector3.UP, ang)
			var land := src.origin + dirk * maxf(dist, 4.0)
			land.y = _ground_y(land)
			_fly([src.origin, land], src.basis, element, { "stick": "ground", "trail": true })
	return first


func _fly_to_unit(src: Transform3D, v: Node3D, element: String, hit: bool) -> float:
	if v == null:
		return 0.0
	if hit:
		return _fly([src.origin, _chest(v)], src.basis, element, { "stick": "unit", "target": v, "trail": true })
	return _fly(_miss_path(src.origin, _chest(v), v), src.basis, element, { "stick": "skitter", "trail": true }) * 0.8


## Energized Shot: it doesn't stop. Through the target's chest, on through
## the pierced foe (if any), into the ground beyond; a white flash at each
## body it passes. Returns the time to the first.
func _shoot_pierce(a: BWUnitView, d: Node3D, from: Transform3D, element: String, hit: bool) -> float:
	var pts := [from.origin, _chest(d)]
	var p2: Node3D = screen._views.get(str(context.get("pierce", ""))) if context.has("pierce") else null
	if p2 != null:
		pts.append(_chest(p2))
	var last: Vector3 = pts[pts.size() - 1]
	var dir: Vector3 = last - (pts[pts.size() - 2] as Vector3)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 1e-3 else Vector3.BACK
	var end: Vector3 = last + dir * 3.2
	end.y = _ground_y(end)
	pts.append(end)
	var t1: float = ((pts[1] as Vector3) - (pts[0] as Vector3)).length() / FLAT_SPEED
	var bodies: Array = [[t1, pts[1], d, hit]]
	if p2 != null:
		bodies.append([t1 + ((pts[2] as Vector3) - (pts[1] as Vector3)).length() / FLAT_SPEED, pts[2], p2, true])
	var r := _fly(pts, from.basis, element, { "stick": "ground", "trail": true, "speed": FLAT_SPEED })
	for b in bodies:
		var at: Vector3 = b[1]
		get_tree().create_timer(float(b[0])).timeout.connect(func():
			if bool(b[3]):
				_flash(at, 0.9, 0.12, element))
	return t1 if r >= 0.0 else t1


## Pinning Shot: a low shot into the ground at the target's feet. While the
## target is Pinned it stays there.
func _shoot_pin(a: BWUnitView, d: Node3D, from: Transform3D, element: String, hit: bool) -> float:
	if not hit:
		return _shoot_flat(from, d, element, false)
	var dir := d.global_position - a.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 1e-3 else Vector3.BACK
	var foot := d.global_position + dir.cross(Vector3.UP).normalized() * 0.16 - dir * 0.06
	foot.y = _ground_y(foot)
	var u: BWUnit = d.unit if "unit" in d else null
	return _fly([from.origin, foot + Vector3(0, 0.02, 0)], from.basis, element, { "stick": "pin", "unit": u, "trail": true })


## Dualthrow: the dagger leaves the hand spinning end over end; a hit
## sticks in the chest, a miss tumbles past into the ground.
func _throw_blade(a: BWUnitView, d: Node3D, hit: bool) -> float:
	var id := BWCharacter.weapon_id_for(a.unit, "dagger")
	var b: BWWeaponView = null
	if _blades.has(id) and not (_blades[id] as Array).is_empty():
		b = (_blades[id] as Array).pop_back()
	else:
		b = BWWeaponView.create(id)
		if b == null:
			return 0.2
		b.set_meta("blade_id", id)
		add_child(b)
	b.visible = true
	b.scale = Vector3.ONE
	var p0: Vector3 = a.global_position + Vector3(0, 1.45, 0) + (d.global_position - a.global_position).normalized() * 0.3
	var to := _chest(d)
	var pts := [p0, to] if hit else _miss_path(p0, to, d)
	var rec := _rec(b, pts, Basis(), { "stick": "unit" if hit else "skitter", "target": d, "speed": BLADE_SPEED, "blade": true,
		"arc": 0.25 })
	return float(rec.dur) * (1.0 if hit else 0.8)


# ------------------------------------------------------------ flights

## Fly an arrow along a polyline (or a ballistic arc: opts.arc = apex height
## over a 2-point line). Returns the seconds to arrival.
func _fly(pts: Array, b0: Basis, element: String, opts: Dictionary) -> float:
	var v := _take(element)
	if v == null:
		return 0.2
	return float(_rec(v, pts, b0, opts).dur)


func _rec(v: Node3D, pts: Array, b0: Basis, opts: Dictionary) -> Dictionary:
	var lens: Array = [0.0]
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i] - pts[i - 1]).length()
		lens.append(total)
	var speed := float(opts.get("speed", FLAT_SPEED))
	var dur := float(opts.get("dur", maxf(0.08, total / speed)))
	var r := { "v": v, "mode": "fly", "t": 0.0, "dur": dur, "pts": pts, "lens": lens, "total": maxf(total, 1e-3),
		"arc": float(opts.get("arc", 0.0)), "b0": b0, "stick": str(opts.get("stick", "ground")),
		"target": opts.get("target"), "unit": opts.get("unit"), "trail": bool(opts.get("trail", false)),
		"blade": bool(opts.get("blade", false)), "life": 0.0, "spin": 0.0, "anchor": Transform3D(),
		"on_land": opts.get("on_land"), "dir": Vector3.BACK, "vel": Vector3.ZERO, "hold": float(opts.get("hold", STUCK_LIFE)) }
	_live.append(r)
	stats.max_live = maxi(int(stats.max_live), _live.size())
	_place(r, 0.0)
	if r.trail and v is BWProjectileView:
		var tr := v.get_node("trail") as Node3D
		tr.visible = true
		tr.scale = Vector3(1, 1, 0.01)
	return r


func _point(r: Dictionary, u: float) -> Vector3:
	var pts: Array = r.pts
	if pts.size() == 2 and float(r.arc) > 0.0:
		return (pts[0] as Vector3).lerp(pts[1], u) + Vector3(0, 4.0 * float(r.arc) * u * (1.0 - u), 0)
	var s := u * float(r.total)
	var lens: Array = r.lens
	for i in range(1, pts.size()):
		if s <= float(lens[i]) or i == pts.size() - 1:
			var seg := maxf(float(lens[i]) - float(lens[i - 1]), 1e-4)
			return (pts[i - 1] as Vector3).lerp(pts[i], clampf((s - float(lens[i - 1])) / seg, 0.0, 1.0))
	return pts[pts.size() - 1]


func _place(r: Dictionary, u: float) -> void:
	var p := _point(r, u)
	var q := _point(r, minf(u + 0.02, 1.0)) if u < 0.98 else p + (p - _point(r, u - 0.02))
	var dir := q - p
	if dir.length() < 1e-5:
		dir = r.dir
	dir = dir.normalized()
	r.dir = dir
	var b := _look(dir)
	if bool(r.blade):
		b = b * Basis(Vector3.RIGHT, float(r.spin))
	elif u < 0.12 and float(r.arc) <= 0.0:
		# leave the string in the nocked arrow's own attitude
		b = Basis(r.b0.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), u / 0.12))
	var v: Node3D = r.v
	v.global_transform = Transform3D(b, p)


func _process(delta: float) -> void:
	_tick_fx(delta)
	for i in range(_live.size() - 1, -1, -1):
		var r: Dictionary = _live[i]
		var v: Node3D = r.v
		if not is_instance_valid(v):
			_live.remove_at(i)
			continue
		match str(r.mode):
			"fly":
				r.t = float(r.t) + delta
				var u := clampf(float(r.t) / float(r.dur), 0.0, 1.0)
				if str(r.stick) == "unit" and r.target != null and is_instance_valid(r.target):
					# home on the moving chest (the reaction is already playing)
					var pts: Array = r.pts
					pts[pts.size() - 1] = _chest(r.target)
				if bool(r.blade):
					r.spin = float(r.spin) + delta * 22.0
				_place(r, u)
				if r.trail and v is BWProjectileView:
					var tr := v.get_node("trail") as Node3D
					tr.scale = Vector3(1, 1, clampf(float(r.t) * 9.0, 0.01, 1.0))
				if u >= 1.0:
					_land(r)
			"stuck":
				r.life = float(r.life) + delta
				if str(r.stick) == "unit":
					if r.target == null or not is_instance_valid(r.target) or not (r.target as Node3D).is_visible_in_tree():
						r.life = maxf(float(r.life), float(r.hold))
					else:
						var c: Variant = _chest_xf(r.target)
						v.global_transform = ((c as Transform3D) if c != null else (r.target as Node3D).global_transform) * (r.anchor as Transform3D)
				if str(r.stick) == "pin":
					var u2: BWUnit = r.unit
					if u2 != null and u2.statuses.has("pinned") and u2.alive():
						r.life = minf(float(r.life), 0.5)
				if float(r.life) >= float(r.hold):
					r.mode = "fade"
					r.t = 0.0
					r.fade_from = v.global_transform
			"skitter":
				r.t = float(r.t) + delta
				var vel: Vector3 = r.vel
				vel *= exp(-delta * 7.0)
				r.vel = vel
				var p := v.global_position + vel * delta
				p.y = _ground_y(p) + 0.03
				var flat := Vector3(vel.x, 0, vel.z)
				var fd: Vector3 = flat.normalized() if flat.length() > 0.05 else Vector3(r.dir.x, 0, r.dir.z).normalized()
				if fd.length() < 0.5:
					fd = Vector3.BACK
				var wob := sin(float(r.t) * 30.0) * 0.4 * exp(-float(r.t) * 6.0)
				v.global_transform = Transform3D(_look(fd.rotated(Vector3.UP, wob)), p + fd * 0.0)
				if float(r.t) > 0.35:
					r.mode = "stuck"
					r.stick = "ground"
					r.life = 0.35
			"fade":
				r.t = float(r.t) + delta
				var k := clampf(float(r.t) / FADE, 0.0, 1.0)
				var f0: Transform3D = r.fade_from
				if str(r.stick) == "unit":
					v.scale = Vector3.ONE * maxf(1.0 - k, 0.01)
				else:
					v.global_transform = Transform3D(f0.basis.scaled(Vector3.ONE * maxf(1.0 - k * 0.7, 0.01)), f0.origin + (r.dir as Vector3) * 0.3 * k)
				if k >= 1.0:
					_give(v)
					_live.remove_at(i)


func _land(r: Dictionary) -> void:
	var v: Node3D = r.v
	if v is BWProjectileView:
		(v.get_node("trail") as Node3D).visible = false
	var dir: Vector3 = r.dir
	if r.on_land is Callable:
		(r.on_land as Callable).call(v.global_position)
	match str(r.stick):
		"unit":
			if bool(r.blade):
				v.global_transform = Transform3D(_look(dir) * Basis(Vector3.RIGHT, -PI / 2.0), v.global_position - dir * 0.05)
			else:
				v.global_position += dir * SINK_UNIT
			var t: Node3D = r.target
			if t != null and is_instance_valid(t):
				var c: Variant = _chest_xf(t)
				var base: Transform3D = (c as Transform3D) if c != null else t.global_transform
				r.anchor = base.affine_inverse() * v.global_transform
			r.mode = "stuck"
			r.life = 0.0
			r.hold = 0.9 if bool(r.blade) else STUCK_LIFE
		"ground", "pin":
			v.global_position += dir * SINK_GROUND
			_dust(v.global_position - dir * SINK_GROUND, 0.35)
			r.mode = "stuck"
			r.life = 0.0
			if str(r.stick) == "pin":
				r.hold = STUCK_LIFE
		"skitter":
			var h := Vector3(dir.x, 0, dir.z)
			r.vel = h.normalized() * 5.0 if h.length() > 1e-3 else Vector3.ZERO
			_dust(v.global_position, 0.28)
			r.mode = "skitter"
			r.t = 0.0
		"up":
			_give(v)
			_live.erase(r)
		_:
			r.mode = "stuck"


# ------------------------------------------------------------ area skills

## Arcing Shot and Rain of Arrows, played whole: the camera (by tier), the
## callout, the archer's clip, the arrows, the impacts, the numbers.
func play_area(e: Dictionary, tc: Dictionary, call: Dictionary) -> void:
	var s := screen
	var a: BWUnitView = s._views[str(e.unit)]
	var key := str(e.skill)
	var element := str(e.get("element", ""))
	var results: Array = e.get("results", [])
	var hexes: Array = e.get("hexes", [])
	var target: Vector2i = e.get("target", a.unit.pos)
	var centre: Vector3 = s.board_view.top_center(target)
	var tier := int(tc.get("tier", BWCutsceneTier.FULL))
	var full := tier == BWCutsceneTier.FULL
	var targets: Array = []
	for r in results:
		targets.append(s._views[str(r.target)])
	context = e
	# ---- the camera (SHORT / FULL): archer and the whole area in frame
	var cine := {}
	if tier != BWCutsceneTier.MINIMAL:
		cine = await _cine_in(a, targets, hexes, centre, full, key == "rain_of_arrows")
	else:
		s.ui.cinematic(true)
	if not call.is_empty():
		var hold := BWCombatUI.CALLOUT_HOLD if full else 0.14
		if s.skipping:
			hold = 0.05
		s.ui.callout(str(call.word), str(call.element), str(call.name), a.unit.name, hold)
		s.skill_called.emit(a.unit.id, str(call.text), str(call.element))
		await get_tree().create_timer(BWCombatUI.CALLOUT_IN + hold).timeout
	elif tier != BWCutsceneTier.MINIMAL:
		s.ui.banner(str(BWSkills.get_skill(key).get("name", key)), 0.7 if full else 0.4)
	a.face(centre)
	for t in targets:
		t.face(a.global_position)
	var reacts: Array = []
	for k in results.size():
		reacts.append(s._pick_reaction(targets[k], results[k], false, "%s|%s|%d" % [a.unit.id, key, k]))
	a.skill = clip_for(key)
	a.pose_named("windup")
	await get_tree().create_timer(maxf(a.time_to_marker("coil"), 0.0) + 0.1).timeout
	a.pose_named("strike")
	if key == "arcing_shot":
		await _arcing(a, e, targets, reacts, centre, hexes, element, tc)
	else:
		await _rain(a, e, targets, reacts, centre, hexes, element, tc)
	# ---- numbers already floated per hit; the feed, then home
	var lines: PackedStringArray = []
	for k in results.size():
		var res: Dictionary = results[k].result
		lines.append("%s %s" % [targets[k].unit.name, "miss" if not res.hit else str(res.damage)])
	s.ui.feed("%s (%s) → %s" % [a.unit.name, str(BWSkills.get_skill(key).get("name", key)),
		", ".join(lines) if not lines.is_empty() else "no one"])
	await s._hold(0.5 if full else 0.25)
	if not cine.is_empty():
		await _cine_out(cine)
	s.ui.cinematic(false)
	a.idle()
	for t in targets:
		if t.unit.alive():
			t.idle()
	context = {}


func _cine_in(a: BWUnitView, targets: Array, hexes: Array, centre: Vector3, full: bool, wide: bool) -> Dictionary:
	var s := screen
	var zoom_t := 0.45 if full else 0.3
	s.ui.cinematic(true)
	var keep: Array = [a]
	keep.append_array(targets)
	keep.append_array(s.board_view.hex_parts(a.unit.pos))
	for h in hexes:
		keep.append_array(s.board_view.hex_parts(h))
	var others: Array = []
	for c in s.board_view.get_children():
		if not c in keep:
			others.append(c)
	for id in s._views:
		if not s._views[id] in keep:
			others.append(s._views[id])
	var saved := { "pos": s.rig.pivot, "yaw": s.rig.yaw, "pitch": s.rig.pitch, "dist": s.rig.dist, "fov": s.cam.fov,
		"others": others, "zoom_t": zoom_t }
	s.rig.following = false
	s.rig.input_enabled = false
	var span := a.global_position.distance_to(centre)
	var mid: Vector3 = a.global_position.lerp(centre, 0.55 if wide else 0.5) + Vector3(0, 1.0 if wide else 1.6, 0)
	var side_yaw := atan2(centre.x - a.global_position.x, centre.z - a.global_position.z) + PI / 2.0 + (0.5 if wide else 0.25)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(s._dim_all.bind(others), 0.0, 1.0, zoom_t * 0.78)
	tw.tween_property(s.rig, "yaw", s._closest_angle(s.rig.yaw, side_yaw), zoom_t).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s.cam, "fov", 34.0 if wide else 30.0, zoom_t).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s.rig, "pivot", mid, zoom_t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s.rig, "dist", clampf(10.0 + span * (1.25 if wide else 1.1), 13.0, 27.0), zoom_t).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s.rig, "pitch", deg_to_rad(36.0 if wide else 26.0), zoom_t).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	saved["hidden"] = s._hide_occluders(keep, [a] + targets)
	return saved


func _cine_out(saved: Dictionary) -> void:
	var s := screen
	var zoom_t := float(saved.zoom_t)
	var t2 := create_tween().set_parallel(true)
	t2.tween_method(s._dim_all.bind(saved.others), 1.0, 0.0, zoom_t * 0.9)
	t2.tween_property(s.rig, "pivot", saved.pos, zoom_t).set_trans(Tween.TRANS_CUBIC)
	t2.tween_property(s.rig, "yaw", saved.yaw, zoom_t).set_trans(Tween.TRANS_CUBIC)
	t2.tween_property(s.cam, "fov", saved.fov, zoom_t)
	t2.tween_property(s.rig, "dist", saved.dist, zoom_t)
	t2.tween_property(s.rig, "pitch", saved.pitch, zoom_t).set_trans(Tween.TRANS_CUBIC)
	await t2.finished
	for n in saved.get("hidden", []):
		if is_instance_valid(n):
			n.visible = true
	s.rig.following = true
	s.rig.input_enabled = true


## ARCING SHOT: one arrow up a tall arc and down onto the centre hex; the
## blast lands on its impact.
func _arcing(a: BWUnitView, e: Dictionary, targets: Array, reacts: Array, centre: Vector3, hexes: Array, element: String, tc: Dictionary) -> void:
	var s := screen
	var rel := maxf(a.time_to_marker("release"), 0.0)
	await get_tree().create_timer(rel).timeout
	var nocks: Array = a.character.nocked_arrows() if a.character else []
	var from: Transform3D = nocks[0] if not nocks.is_empty() else Transform3D(Basis(), a.global_position + Vector3(0, 1.8, 0))
	var span := Vector2(centre.x - from.origin.x, centre.z - from.origin.z).length()
	var apex := clampf(span * 0.42, 2.6, 6.5) + maxf(0.0, from.origin.y - centre.y) * 0.3
	var dur := 0.55 + span * 0.045
	var land := centre + Vector3(0, 0.02, 0)
	var opts := { "arc": apex, "dur": dur, "stick": "ground", "hold": STUCK_LIFE + 0.4 }
	var results: Array = e.get("results", [])
	for k in results.size():
		if targets[k].unit.pos == e.get("target", Vector2i(-99, -99)) and bool((results[k].result as Dictionary).get("hit", true)):
			land = _chest(targets[k]) + Vector3(0, 0.2, 0)       # the foe on the centre hex takes it
			opts.merge({ "stick": "unit", "target": targets[k] }, true)
	var v := _take(element)
	if v != null:
		_rec(v, [from.origin, land], from.basis, opts)
	await s._react_at(a, targets, reacts, dur, e.get("results", []), str(tc.get("flash", "full")))
	burst(e.get("target", a.unit.pos), hexes, element)
	_numbers(e.get("results", []), targets, -1)


## RAIN OF ARROWS: the volley skyward (one per release), the shadow, then
## the rain over every hex, each target's number on its hex's first strike.
func _rain(a: BWUnitView, e: Dictionary, targets: Array, reacts: Array, centre: Vector3, hexes: Array, element: String, tc: Dictionary) -> void:
	var s := screen
	var results: Array = e.get("results", [])
	var meta: Dictionary = a.character.animator.clip_meta("shot_volley") if a.character and a.character.animator else {}
	var marks: Dictionary = meta.get("markers", {})
	var rels: Array = []
	for n in ["release", "release2", "release3", "release4", "release5"]:
		if marks.has(n):
			rels.append(float(marks[n]))
	var t0 := maxf(a.time_to_marker("release"), 0.0)
	var base: float = float(rels[0]) if not rels.is_empty() else 0.0
	var heading := centre - a.global_position
	heading.y = 0
	heading = heading.normalized() if heading.length() > 1e-3 else Vector3.BACK
	# the volley: each arrow off the string at its release, up out of frame
	var clock := 0.0
	for k in maxi(rels.size(), 1):
		var at: float = t0 + (float(rels[k]) - base if k < rels.size() else 0.0)
		if at > clock:
			await get_tree().create_timer(at - clock).timeout
			clock = at
		var nocks: Array = a.character.nocked_arrows() if a.character else []
		var from: Transform3D = nocks[0] if not nocks.is_empty() else Transform3D(Basis(), a.global_position + Vector3(0, 1.9, 0))
		var up := (heading * 0.62 + Vector3(0, 1, 0)).normalized()
		var vv := _take(element)
		if vv != null:
			_rec(vv, [from.origin, from.origin + up * 16.0], from.basis, { "dur": SKY_RISE, "stick": "up", "trail": true })
	# the shadow sweeps in while the arrows turn over at the top
	var stagger := RAIN_STAGGER * (0.3 if s.skipping else 1.0)
	var lead := 0.5 if not s.skipping else 0.15
	var radius := float(BWSkills.get_skill("rain_of_arrows").get("radius", 2))
	_shadow(centre, heading, (radius + 0.9) * sqrt(3.0), lead + stagger + 0.4, lead)
	await get_tree().create_timer(lead).timeout
	# the schedule: 2-4 arrows per hex, staggered along the volley's heading
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(e.get("target", Vector2i.ZERO)) + str(e.unit))
	var by_hex := {}
	for k in results.size():
		by_hex[targets[k].unit.pos] = k
	var plan: Array = []              # [time, hex, point, k or -1, first]
	var reach := (radius + 1.0) * sqrt(3.0)
	for h in hexes:
		var top: Vector3 = s.board_view.top_center(h)
		var along := clampf((heading.dot(top - centre) / reach + 1.0) * 0.5, 0.0, 1.0)
		var th := clampf(along * 0.75 + rng.randf_range(0.0, 0.25), 0.0, 1.0) * stagger
		var n := rng.randi_range(2, 4)
		var k: int = by_hex.get(h, -1)
		for j in n:
			var t := th + (0.0 if j == 0 else rng.randf_range(0.04, 0.32) * (stagger / RAIN_STAGGER))
			var ang := rng.randf() * TAU
			var rr := rng.randf_range(0.2, 0.72) if not (k >= 0 and j == 0) else 0.0
			var p := top + Vector3(cos(ang) * rr, 0, sin(ang) * rr)
			plan.append([t, h, p, k, j == 0])
	plan.sort_custom(func(x, y): return x[0] < y[0])
	# reactions start so their impact meets the hex's first arrow
	var first_t := {}
	for p in plan:
		if int(p[3]) >= 0 and bool(p[4]):
			first_t[int(p[3])] = float(p[0])
	var events: Array = []            # [time, kind, data]
	for p in plan:
		events.append([maxf(float(p[0]) - RAIN_FALL, 0.0), "drop", p])
	for k in first_t:
		var tv: BWUnitView = targets[k]
		events.append([maxf(float(first_t[k]) - tv.lead_to_impact(reacts[k]), 0.0), "react", k])
		events.append([float(first_t[k]), "strike", k])
	events.sort_custom(func(x, y): return x[0] < y[0])
	var now := 0.0
	var fall_dir := (heading + Vector3(0, -2.6, 0)).normalized()
	for ev in events:
		if float(ev[0]) > now + 0.004:
			await get_tree().create_timer(float(ev[0]) - now).timeout
			now = float(ev[0])
		match str(ev[1]):
			"drop":
				var p: Array = ev[2]
				var k := int(p[3])
				var hit_unit: bool = k >= 0 and bool(p[4]) and bool((results[k].result as Dictionary).get("hit", true))
				var land: Vector3 = _chest(targets[k]) + Vector3(0, 0.15, 0) if hit_unit else p[2]
				var jitter := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
				var fd := (fall_dir + jitter).normalized()
				var from: Vector3 = land - fd * (RAIN_FALL * 30.0)
				var vv := _take(element)
				if vv != null:
					var opts := { "dur": RAIN_FALL, "stick": "unit" if hit_unit else "ground", "target": targets[k] if hit_unit else null,
						"hold": STUCK_LIFE + (stagger - float(p[0])) * 0.6 }
					_rec(vv, [from, land], _look(fd), opts)
			"react":
				var k2 := int(ev[2])
				var tv: BWUnitView = targets[k2]
				tv.pose_named(reacts[k2])
				s.reaction_chosen.emit(tv.unit.id, reacts[k2], (results[k2] as Dictionary).get("pick", {}))
				if reacts[k2] == "dodge" and not tv is BWObeliskView:
					s._dodge_shift(a, tv)
			"strike":
				var k3 := int(ev[2])
				_numbers(results, targets, k3)
				var res: Dictionary = results[k3].result
				if bool(res.get("crit", false)) and bool(res.get("hit", true)) and str(tc.get("flash", "none")) != "none":
					s.crit_flashed.emit(a.unit.id)
					s.ui.crit_flash_tiny()
				s._shake(0.05)
	# let the last arrows land
	await get_tree().create_timer(RAIN_FALL + 0.05).timeout


## Float the number (and riders) for result k (-1: all of them).
func _numbers(results: Array, targets: Array, only: int) -> void:
	var s := screen
	for k in results.size():
		if only >= 0 and k != only:
			continue
		var r: Dictionary = results[k]
		var res: Dictionary = r.result
		var t: BWUnitView = targets[k]
		var label := "MISS" if not res.hit else str(res.damage)
		if res.get("crit", false) and res.hit:
			label += "  CRIT"
		if res.get("glance", false):
			label += "  glance"
		if res.get("resisted", false):
			label += "  resisted"
		if BWSettings.value("show_numbers"):
			s._float_text(t, label, Color.WHITE, 1.0)
		s._float_tags(t, r)
		t.refresh()
	if not results.is_empty():
		s.ui.odds_result(results[0].result)


# ------------------------------------------------------------ bursts

## The Arcing Shot's blast: a white star at the centre, every blast hex lit
## from the centre out (a flat hex plate in the element that pops and
## fades), ink debris thrown out, a shake.
func burst(at: Vector2i, hexes: Array, element: String) -> void:
	var s := screen
	var centre: Vector3 = s.board_view.top_center(at)
	_flash(centre + Vector3(0, 0.55, 0), 2.6, 0.32, element)
	var col := BWLook.element_color(element) if element != "" else Color(1, 1, 1)
	for h in hexes:
		var dist := BWHex.distance(at, h)
		var top: Vector3 = s.board_view.top_center(h) + Vector3(0, 0.045, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = BWTileFX.hex_mesh()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(col.r, col.g, col.b, 0.0)
		m.render_priority = 2
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.sorting_offset = 3.0
		add_child(mi)
		mi.global_position = top
		mi.scale = Vector3.ONE * 0.2
		_fx.append([mi, -float(dist) * 0.075, 0.55, "plate", m])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(at))
	for i in 18:
		var d := MeshInstance3D.new()
		d.mesh = _debris_mesh
		d.material_override = _debris_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		d.global_position = centre + Vector3(0, 0.1, 0)
		var ang := rng.randf() * TAU
		var sp := rng.randf_range(2.0, 4.6)
		var vel := Vector3(cos(ang) * sp, rng.randf_range(3.0, 6.0), sin(ang) * sp)
		_fx.append([d, 0.0, rng.randf_range(0.5, 0.8), "debris", [vel, Vector3(rng.randf(), rng.randf(), rng.randf()) * 14.0]])
	_dust(centre, 0.9)
	s._shake(0.16)


## A little ink-and-paper puff where an arrow lands.
func _dust(at: Vector3, size: float) -> void:
	_flash(at + Vector3(0, size * 0.25, 0), size, 0.16, "")


## The volley's shadow: slides in along the heading over `lead` seconds,
## holds dark while the rain falls, lifts at the end.
func _shadow(centre: Vector3, heading: Vector3, r: float, life: float, lead: float) -> void:
	if _shadow_shader == null:
		_shadow_shader = load("res://shaders/volley_shadow.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.2, r * 2.2)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _shadow_shader
	m.set_shader_parameter("heading", Vector2(heading.x, heading.z))
	m.set_shader_parameter("seed", randf())
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 2.5
	add_child(mi)
	var at := centre + Vector3(0, 0.06, 0)
	mi.global_position = at - heading * r * 1.3
	_fx.append([mi, 0.0, life, "shadow", [m, at, heading * r * 1.3, lead]])


# ------------------------------------------------------------ flashes / fx

func _flash(at: Vector3, size: float, life: float, element: String) -> void:
	if _flash_shader == null:
		_flash_shader = load("res://shaders/muzzle_flash.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = _flash_shader
	m.set_shader_parameter("ring", BWLook.element_color(element) if element != "" else Color(1, 1, 1))
	m.set_shader_parameter("seed", randf())
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	_fx.append([mi, 0.0, life, "flash", m])


func _tick_fx(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var e: Array = _fx[i]
		var n: Node3D = e[0]
		e[1] = float(e[1]) + delta
		var age := float(e[1])
		var life := float(e[2])
		if not is_instance_valid(n) or age >= life:
			if is_instance_valid(n):
				n.queue_free()
			_fx.remove_at(i)
			continue
		if age < 0.0:
			continue
		var u := age / life
		match str(e[3]):
			"flash":
				var sc := u / 0.3 if u < 0.3 else 1.0 - (u - 0.3) / 0.7 * 0.6
				n.scale = Vector3.ONE * maxf(sc, 0.05)
				(e[4] as ShaderMaterial).set_shader_parameter("age", u)
			"plate":
				var grow := minf(age / 0.12, 1.0)
				n.scale = Vector3.ONE * lerpf(0.2, 0.93, 1.0 - pow(1.0 - grow, 3.0))
				var m: StandardMaterial3D = e[4]
				m.albedo_color.a = (0.85 if u < 0.25 else 0.85 * (1.0 - (u - 0.25) / 0.75))
			"debris":
				var d: Array = e[4]
				var vel: Vector3 = d[0]
				vel.y -= 16.0 * delta
				d[0] = vel
				n.global_position += vel * delta
				n.rotation += (d[1] as Vector3) * delta
				if n.global_position.y < _ground_y(n.global_position) - 0.05:
					d[0] = Vector3.ZERO
			"shadow":
				var d2: Array = e[4]
				var m2: ShaderMaterial = d2[0]
				var lead := float(d2[3])
				var k := clampf(age / maxf(lead, 0.01), 0.0, 1.0)
				var ease := 1.0 - pow(1.0 - k, 3.0)
				n.global_position = (d2[1] as Vector3) - (d2[2] as Vector3) * (1.0 - ease)
				var tail := clampf((life - age) / 0.35, 0.0, 1.0)
				m2.set_shader_parameter("fade", minf(ease, tail) * (0.75 + 0.25 * minf(age / (lead + 0.4), 1.0)))
				m2.set_shader_parameter("scroll", age)


# ------------------------------------------------------------ helpers

static func _look(dir: Vector3) -> Basis:
	if dir.length() < 1e-5:
		dir = Vector3.BACK
	dir = dir.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	return Basis.looking_at(dir, up, true)


## The target's chest point (world): the chest bone, else 1.15 up.
func _chest(t: Node3D) -> Vector3:
	if t == null or not is_instance_valid(t):
		return Vector3.ZERO
	var c: Variant = _chest_xf(t)
	if c != null:
		return (c as Transform3D).origin + Vector3(0, 0.05, 0)
	return t.global_position + Vector3(0, 1.15 * t.scale.y, 0)


func _chest_xf(t: Node3D) -> Variant:
	if t == null or not is_instance_valid(t):
		return null
	var ch: Variant = t if t is BWCharacter else t.get("character")
	if ch == null or not (ch is BWCharacter) or (ch as BWCharacter).rig == null:
		return null
	var sk := (ch as BWCharacter).rig.skeleton
	if sk == null or not sk.is_inside_tree():
		return null
	var i := sk.find_bone("chest")
	if i < 0:
		return null
	return sk.global_transform * sk.get_bone_global_pose(i)


## The ground height under a world point (the tile top), or the floor.
func _ground_y(p: Vector3) -> float:
	if screen == null or screen.board_view == null or screen.board_view.board == null:
		return 0.0
	var h := BWHex.from_world(Vector2(p.x, p.z), BWLook.HEX_SIZE)
	if not screen.board_view.board.exists(h):
		return BWBoardView.FLOOR_Y
	return screen.board_view.top_center(h).y


## A crossed pair of thin quads running back from the arrow's tail, grey
## fading to nothing (the faint trail of a flat shot).
static func _make_trail_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 1.6
	var w := 0.035
	var c0 := Color(0.7, 0.7, 0.7, 0.55)
	var c1 := Color(0.7, 0.7, 0.7, 0.0)
	for axis in [Vector3(w, 0, 0), Vector3(0, w, 0)]:
		var a0: Vector3 = -axis
		var a1: Vector3 = axis
		var b0: Vector3 = -axis * 0.2 + Vector3(0, 0, -L)
		var b1: Vector3 = axis * 0.2 + Vector3(0, 0, -L)
		for v in [[a0, c0], [a1, c0], [b1, c1], [a0, c0], [b1, c1], [b0, c1]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _exit_tree() -> void:
	for e in _fx:
		if is_instance_valid(e[0]):
			(e[0] as Node).queue_free()
	_fx.clear()
	_live.clear()

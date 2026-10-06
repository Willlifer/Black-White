class_name BWProjectileFlight
extends Node3D
## One projectile in flight, in the weapon look (BWProjectileView models):
##
##   arrow   a ballistic arc, oriented along its velocity; on a hit it sinks
##           0.12 into the target, STICKS there (riding the target's chest
##           bone through its reaction) for a beat, then shrinks away; a
##           miss flies on past and drops out
##   bullet  straight and fast (38 u/s) with its tracer; a muzzle flash
##           (an ink-rimmed star, the element in its ring) pops at the
##           muzzle on launch and a small one at the hit
##   bolt    a faceted shard that spins about its flight line on a shallow
##           arc, wrapped in the element aura (shell + particles: the
##           particles' world-space wake is its trail); bursts at the end
##
##   var f := BWProjectileFlight.launch(parent, "arrow", from_xf, target_view, "fire", true)
##   f.duration            # seconds to arrival (the impact)
##   f.manual = true       # tools: step with f.advance(dt) instead of _process
##
## Every flight frees itself; nothing waits on it (callers use a timer of
## `duration`), so a freed target or a missing model can't hang the combat.

const ARROW_SPEED := 22.0
const BULLET_SPEED := 38.0
const BOLT_SPEED := 18.0
const STICK_TIME := 0.7
const SHRINK_TIME := 0.18
const SINK := 0.12

var kind := ""
var element := ""
var hit := true
var duration := 0.3
var manual := false
var model: BWProjectileView
var t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 0.0
var _phase := "fly"
var _phase_t := 0.0
var _target: Node3D
var _anchor_local := Transform3D()
var _spin := 0.0
var _flashes: Array = []        # [node, age, life]
static var _flash_shader: Shader


## Start a flight. `from` is a Vector3 (the muzzle, the staff head) or a
## Transform3D (a nocked arrow: it leaves exactly from the string); `target`
## is the defender's view (BWUnitView or any Node3D). Returns the flight.
static func launch(parent: Node, p_kind: String, from: Variant, target: Node3D, p_element: String = "", p_hit: bool = true) -> BWProjectileFlight:
	var f := BWProjectileFlight.new()
	f.name = "flight_" + p_kind
	f.kind = p_kind
	f.element = p_element
	f.hit = p_hit
	f._target = target
	parent.add_child(f)
	f._begin(from)
	return f


## The projectile a weapon class shoots ("arrow", "bullet", "bolt").
static func kind_for(weapon_class: String, spell: bool) -> String:
	if spell:
		return "bolt"
	return str(BWProjectileView.FOR_CLASS.get(weapon_class, "bolt"))


func _begin(from: Variant) -> void:
	model = BWProjectileView.create_projectile(kind)
	if model:
		add_child(model)
		if kind == "bolt" and element != "":
			model.set_aura(element, 1.3)
		else:
			model.set_accent(element)
	var start_basis := Basis()
	if from is Transform3D:
		_from = (from as Transform3D).origin
		start_basis = (from as Transform3D).basis
	else:
		_from = from
	_to = _aim_point()
	var dist := _from.distance_to(_to)
	match kind:
		"arrow":
			_arc = 0.18 + dist * 0.05
			duration = 0.1 + dist / ARROW_SPEED
		"bullet":
			_arc = 0.0
			duration = maxf(0.05, dist / BULLET_SPEED)
			_flash(_from, 0.85, 0.09)
		_:
			_arc = 0.1 + dist * 0.03
			duration = 0.12 + dist / BOLT_SPEED
	global_position = _from
	global_basis = start_basis if from is Transform3D else _flight_basis(0.0)
	if not hit:
		# a miss: aim past the target, a little high and to the side
		var d := (_to - _from).normalized()
		_to += d * 1.6 + d.cross(Vector3.UP).normalized() * 0.35 + Vector3(0, 0.25, 0)
		duration *= 1.35


func _aim_point() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return _from + Vector3(0, 0, 3)
	var c: Variant = _chest_xf()
	if c != null:
		return (c as Transform3D).origin + Vector3(0, 0.05, 0)
	return _target.global_position + Vector3(0, 1.1 * _target.scale.y, 0)


## The target's chest bone (world), or null (no rig).
func _chest_xf() -> Variant:
	if _target == null or not is_instance_valid(_target):
		return null
	var ch: Variant = _target if _target is BWCharacter else _target.get("character")
	if ch == null or not (ch is BWCharacter) or (ch as BWCharacter).rig == null:
		return null
	var sk := (ch as BWCharacter).rig.skeleton
	if sk == null or not sk.is_inside_tree():
		return null
	var i := sk.find_bone("chest")
	if i < 0:
		return null
	return sk.global_transform * sk.get_bone_global_pose(i)


func _pos(u: float) -> Vector3:
	return _from.lerp(_to, u) + Vector3(0, sin(u * PI) * _arc, 0)


func _flight_basis(u: float) -> Basis:
	var v := (_to - _from) + Vector3(0, PI * cos(u * PI) * _arc, 0)
	if v.length() < 1e-4:
		v = Vector3.BACK
	var up := Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.BACK
	return Basis.looking_at(v.normalized(), up, true)


func _process(delta: float) -> void:
	if not manual:
		advance(delta)


func advance(delta: float) -> void:
	_tick_flashes(delta)
	if _phase == "done":
		if _flashes.is_empty():
			queue_free()
		return
	_phase_t += delta
	match _phase:
		"fly":
			t = minf(t + delta / maxf(duration, 0.01), 1.0)
			var b := _flight_basis(t)
			if kind == "bolt":
				_spin += delta * 14.0
				b = b * Basis(Vector3.BACK, _spin)
			global_transform = Transform3D(b, _pos(t))
			if t >= 1.0:
				_arrive()
		"stick":
			if _target and is_instance_valid(_target):
				var c: Variant = _chest_xf()
				if c != null:
					global_transform = (c as Transform3D) * _anchor_local
			if _phase_t >= STICK_TIME:
				_phase = "shrink"
				_phase_t = 0.0
		"shrink":
			var k := 1.0 - clampf(_phase_t / SHRINK_TIME, 0.0, 1.0)
			if model:
				model.scale = Vector3.ONE * maxf(k, 0.001)
			if k <= 0.0:
				_finish()


func _arrive() -> void:
	if kind == "arrow" and hit:
		# sink in along the flight line, then ride the chest
		global_position += global_basis.z * SINK
		var c: Variant = _chest_xf()
		if c != null:
			_anchor_local = (c as Transform3D).affine_inverse() * global_transform
		_phase = "stick"
		_phase_t = 0.0
		return
	if kind == "bullet" and hit:
		_flash(global_position, 0.45, 0.08)
	if kind == "bolt" and hit:
		_flash(global_position, 0.6, 0.1)
	_phase = "shrink"
	_phase_t = 0.0


func _finish() -> void:
	if model:
		model.visible = false
		model.clear_aura()
	_phase = "done"


# ------------------------------------------------------------------ flashes

## A muzzle (or impact) flash: a camera-facing star, white with an ink rim
## and the element in its ring, popping up and gone in `life` seconds.
func _flash(at: Vector3, size: float, life: float) -> void:
	if _flash_shader == null:
		_flash_shader = load("res://shaders/muzzle_flash.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = _flash_shader
	var col := BWLook.element_color(element) if element != "" else Color(1, 1, 1)
	m.set_shader_parameter("ring", col)
	m.set_shader_parameter("seed", float(absi(hash(str(at))) % 97) / 97.0)
	var mi := MeshInstance3D.new()
	mi.name = "flash"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var host := get_parent() if get_parent() else self
	host.add_child(mi)
	mi.global_position = at
	_flashes.append([mi, 0.0, life])


func _tick_flashes(delta: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		var e: Array = _flashes[i]
		var mi: MeshInstance3D = e[0]
		e[1] = float(e[1]) + delta
		var u := float(e[1]) / float(e[2])
		if u >= 1.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_flashes.remove_at(i)
			continue
		# pop to full on the first third, then shrink
		var s := u / 0.3 if u < 0.3 else 1.0 - (u - 0.3) / 0.7 * 0.6
		mi.scale = Vector3.ONE * maxf(s, 0.05)
		(mi.material_override as ShaderMaterial).set_shader_parameter("age", u)


func _exit_tree() -> void:
	for e in _flashes:
		if is_instance_valid(e[0]):
			(e[0] as Node).queue_free()
	_flashes.clear()

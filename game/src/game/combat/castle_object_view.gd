class_name BWCastleObjectView
extends BWObeliskView
## D340: the castle's objective objects on the board (BWCastle): the GATE
## (iron in Defend, wood in Storm) and the THRONE (Storm). Procedural, in the
## board's look: white stone with ink contours, black iron, white planks with
## ink seams; built from boxes so it reads at the big-board camera distance.
## The same floating HP bar and name as a stone (BWObeliskView), wider.
##   gate    an arch (two jambs and a crenellated lintel standing proud of the
##           wall walk) across the wall line, the door inside it: a black
##           portcullis grid (iron) or a plank door with two iron bands (wood).
##           Hit: it rocks. Broken: the door falls in and its pieces scatter.
##   throne  a black seat with a tall back and a white crown on a dais; while
##           SEALED (the gate stands) a white cage of ink bars rings it, gone
##           when the gate falls. Broken: it splits and sinks.

const INK := Color(0.03, 0.03, 0.035)
const STONE := Color(0.93, 0.93, 0.93)
const PLANK := Color(0.86, 0.85, 0.82)

var _door: Node3D
var _cage: Node3D
var _debris: Array = []


func obj() -> BWObjective:
	return unit as BWObjective


func is_gate() -> bool:
	return obj() != null and obj().tag == "gate"


func setup(u: BWUnit) -> void:
	unit = u
	name = "castle_" + u.id
	register(self)
	_build()
	refresh()


func _build() -> void:
	model = Node3D.new()
	model.name = "model"
	add_child(model)
	if is_gate():
		_height = 2.0
		_build_gate(obj().kind == "wood_gate")
	else:
		_height = 2.3
		_build_throne()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.outline_size = 7
	_label.modulate = Color.WHITE
	_label.outline_modulate = Color.BLACK
	_label.font_size = 14
	add_child(_label)
	_build_bar(BAR_W * 2.0)
	_place_bar()


## One box (centre `at`, `size`), white or black with the matching contour.
func _box(parent: Node3D, at: Vector3, size: Vector3, col: Color, outline := 0.022) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	var m := BWLook.flat().duplicate() as ShaderMaterial
	var dark := col.get_luminance() < 0.5
	if outline > 0.0:
		m.next_pass = BWLook.outline(outline, Color(0.92, 0.92, 0.95) if dark else Color.BLACK)
	mi.material_override = m
	mi.set_instance_shader_parameter("tint", col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_gate(wood: bool) -> void:
	# the arch: the wall line runs along world X; the gate faces +-Z
	var jx := 0.78
	_box(model, Vector3(-jx, 0.85, 0), Vector3(0.3, 1.7, 0.62), STONE)
	_box(model, Vector3(jx, 0.85, 0), Vector3(0.3, 1.7, 0.62), STONE)
	_box(model, Vector3(0, 1.82, 0), Vector3(1.9, 0.34, 0.66), STONE)
	for k in 4:
		_box(model, Vector3(-0.72 + 0.48 * k, 2.1, 0), Vector3(0.26, 0.24, 0.62), STONE)
	# a keystone wedge of ink over the opening
	_box(model, Vector3(0, 1.62, 0.34), Vector3(0.22, 0.2, 0.02), INK, 0.0)
	_door = Node3D.new()
	_door.name = "door"
	model.add_child(_door)
	if wood:
		_box(_door, Vector3(0, 0.75, 0), Vector3(1.26, 1.5, 0.16), PLANK)
		for k in 5:                              # plank seams
			var x := -0.5 + 0.25 * k
			for z in [0.085, -0.085]:
				_box(_door, Vector3(x, 0.75, z), Vector3(0.025, 1.46, 0.01), INK, 0.0)
		for y in [0.38, 1.12]:                   # iron bands with rivets
			_box(_door, Vector3(0, y, 0), Vector3(1.3, 0.12, 0.2), INK, 0.0)
			for k in 4:
				_box(_door, Vector3(-0.45 + 0.3 * k, y, 0.11), Vector3(0.05, 0.05, 0.02), Color(0.8, 0.8, 0.8), 0.0)
		_box(_door, Vector3(0.36, 0.75, 0.11), Vector3(0.08, 0.08, 0.04), INK, 0.0)   # the ring pull
	else:
		for k in 6:                              # portcullis: vertical bars
			_box(_door, Vector3(-0.55 + 0.22 * k, 0.78, 0), Vector3(0.07, 1.56, 0.07), INK, 0.012)
		for k in 5:                              # cross bars
			_box(_door, Vector3(0, 0.12 + 0.34 * k, 0), Vector3(1.26, 0.06, 0.06), INK, 0.012)
		for k in 6:                              # spikes at the foot
			_box(_door, Vector3(-0.55 + 0.22 * k, 0.0, 0), Vector3(0.05, 0.12, 0.05), INK, 0.0)


func _build_throne() -> void:
	_box(model, Vector3(0, 0.08, 0), Vector3(1.3, 0.16, 1.1), INK)          # dais
	_box(model, Vector3(0, 0.22, 0), Vector3(1.05, 0.12, 0.85), STONE)      # a white step
	_box(model, Vector3(0, 0.5, 0.05), Vector3(0.78, 0.42, 0.62), INK)      # the seat
	_box(model, Vector3(0, 1.25, -0.24), Vector3(0.82, 1.5, 0.16), INK)     # the tall back
	_box(model, Vector3(-0.42, 0.78, 0.05), Vector3(0.12, 0.16, 0.6), INK)  # arms
	_box(model, Vector3(0.42, 0.78, 0.05), Vector3(0.12, 0.16, 0.6), INK)
	var crown := Node3D.new()
	crown.position = Vector3(0, 2.08, -0.24)
	model.add_child(crown)
	_box(crown, Vector3(0, 0, 0), Vector3(0.62, 0.12, 0.2), STONE)
	for k in 3:
		_box(crown, Vector3(-0.22 + 0.22 * k, 0.15, 0), Vector3(0.1, 0.2 if k != 1 else 0.3, 0.12), STONE)
	_cage = Node3D.new()
	_cage.name = "cage"
	model.add_child(_cage)
	for k in 10:                                 # the seal: a ring of white bars
		var a := TAU * k / 10.0
		_box(_cage, Vector3(cos(a) * 0.82, 1.15, sin(a) * 0.82), Vector3(0.06, 2.3, 0.06), STONE, 0.012)
	for y in [0.3, 2.25]:
		for k in 10:
			var a := TAU * (k + 0.5) / 10.0
			var bar := _box(_cage, Vector3(cos(a) * 0.8, y, sin(a) * 0.8), Vector3(0.5, 0.05, 0.05), STONE, 0.012)
			bar.rotation.y = -a + PI / 2


func _base_ring() -> void:
	pass                        # the gate sits in the wall; the throne has its dais


func glow_color() -> Color:
	return Color.WHITE


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 1.4)
	if model and not _crack:
		_rock = lerpf(_rock, 0.0, minf(1.0, delta * 6.0))
		model.rotation.z = _rock * 0.04 * sin(_t * 31.0)
	if _cage:
		var sealed: bool = obj() != null and obj().hittable.is_empty() and obj().alive()
		if _cage.visible != sealed:
			_cage.visible = sealed
			if not sealed:
				_unseal_flash()
	for d in _debris:
		if is_instance_valid(d.node):
			d.v.y -= 9.0 * delta
			d.node.position += d.v * delta
			d.node.rotation += d.spin * delta
			if d.node.position.y < 0.05:
				d.node.position.y = 0.05
				d.v = Vector3.ZERO
				d.spin = Vector3.ZERO


## The seal breaks: the cage bars fly outward for a moment (the view's only
## flourish for the phase change; the screen adds the banner).
func _unseal_flash() -> void:
	_flare = 1.0
	for i in 8:
		var a := TAU * i / 8.0
		var p := _box(self, Vector3(cos(a) * 0.8, 1.2, sin(a) * 0.8), Vector3(0.06, 0.9, 0.06), STONE, 0.012)
		_debris.append({ "node": p, "v": Vector3(cos(a) * 2.6, 3.0, sin(a) * 2.6), "spin": Vector3(4, 0, 3) })
		_fade_later(p, 1.6)


func _fade_later(n: Node3D, t: float) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(n.queue_free)


func _crumble() -> void:
	if _crack:
		return
	_crack = true
	_flare = 1.0
	if is_gate() and _door:
		# the door gives: it falls in, then its pieces scatter across the gateway
		var tw := create_tween()
		tw.tween_property(_door, "rotation:x", -1.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_door, "position:y", -0.1, 0.45)
		tw.tween_callback(_scatter)
		return
	if model:
		var tw := create_tween()
		tw.tween_property(model, "rotation:z", 0.25, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(model, "position:y", -0.5, 0.6).set_ease(Tween.EASE_IN)
		tw.tween_callback(_scatter)


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(unit.id)
	var col := PLANK if obj().kind == "wood_gate" else INK
	for i in 14:
		var p := _box(self, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.3, 1.2), rng.randf_range(-0.2, 0.2)),
			Vector3(rng.randf_range(0.08, 0.3), rng.randf_range(0.05, 0.12), rng.randf_range(0.05, 0.2)), col, 0.01)
		_debris.append({ "node": p, "v": Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(1.5, 4.0), rng.randf_range(-2.5, 2.5)),
			"spin": Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6)) })
	if _door:
		_door.visible = false

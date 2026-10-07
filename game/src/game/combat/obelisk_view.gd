class_name BWObeliskView
extends BWUnitView
## D145: an obelisk on the board (BWObelisk). The Blender model
## (art/obelisks/<kind>.glb, tools/blender/build_obelisks.py): a white
## Lantern and a black Well, with carved glyphs on an `accent` surface that
## glow and breathe slowly; the same floating HP bar and name as a unit.
##
## Additive API on top of BWUnitView's (combat calls these):
##   pulse(kind)          the turn's shockwave: the glyphs flare, the stone
##                        rocks, and a ring runs across the board, outward for
##                        the Lantern's push, inward for the Well's pull
##   pose_named(p)        hit / stricken_*: a jolt; dodge: the stone flickers
##                        (it doesn't step aside); fall: it cracks and sinks
## A stone never walks, faces or idles like a figure: those are no-ops.

const META_PATH := "res://art/obelisks/obelisks.json"
const RING_REACH := 30.0         # world units the push ring runs out to (the whole map)
const PULSE_TIME := 0.95
const PULL_FROM := 15.0         # world units the pull ring starts from (most of the map, on screen)

static var _meta := {}
static var _glyph_mat: ShaderMaterial
static var _ring_mat: ShaderMaterial

var model: Node3D
var _glow_meshes: Array[MeshInstance3D] = []
var _flare := 0.0                # 0..1, added to the idle glow by pulse() / hits
var _height := 3.2
var _rock := 0.0
var _crack := false


static func load_meta() -> Dictionary:
	if not _meta.is_empty():
		return _meta
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		push_error("BWObeliskView: cannot open %s (run build_obelisks.py)" % META_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_meta = parsed.get("obelisks", {}) if parsed is Dictionary else {}
	return _meta


func ob() -> BWObelisk:
	return unit as BWObelisk


func setup(u: BWUnit) -> void:
	unit = u
	name = "obelisk_" + u.id
	register(self)
	_build()
	refresh()


func _build() -> void:
	var o := ob()
	var m: Dictionary = load_meta().get(o.kind, {})
	_height = float(m.get("height", (o as BWObjective).view_height if o is BWObjective else 3.2))   # D327: an objective object's own height
	var scene := load(str(m.get("glb", ""))) as PackedScene if not m.is_empty() else null
	if scene:
		model = scene.instantiate() as Node3D
		model.name = "model"
		add_child(model)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			_apply(mi as MeshInstance3D)
	else:
		_build_fallback()          # no glb: a plain prism, so a fight still shows a stone
	_base_ring()
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
	_build_bar(BAR_W * 1.6)         # D215: the same bar rule, wider (the shared pool, D378)
	_place_bar()


func _place_bar() -> void:
	_hp_bar.place(_height + 0.35)
	_label.position.y = 0.42


func head_height() -> float:
	return _height - 0.6


func _apply(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bright := ob().look() == "bright"
	for i in mi.mesh.get_surface_count():
		if BWWeaponView.surface_role(mi.mesh, i) == "accent":
			mi.set_surface_override_material(i, glyph_material())
			if not mi in _glow_meshes:
				_glow_meshes.append(mi)
		else:
			var m := BWLook.flat().duplicate() as ShaderMaterial
			# the Lantern keeps the ink contour; the Well gets a white one so
			# it reads against the black sky (D42's rule for black limbs)
			m.next_pass = BWLook.outline(0.03, Color.BLACK if bright else Color(0.92, 0.92, 0.95))
			mi.set_surface_override_material(i, m)
	mi.set_instance_shader_parameter("glow", glow_color())
	mi.set_instance_shader_parameter("power", 0.6)


## Lantern: the warm white of light's glow; Well: a cold violet-white (dark's
## colour lifted so it reads on black).
func glow_color() -> Color:
	if ob().look() == "bright":
		return BWLook.glow_color("light").lerp(Color.WHITE, 0.35)
	return BWLook.element_color("dark").lerp(Color(0.85, 0.8, 1.0), 0.72)


func _build_fallback() -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, _height, 0.7)
	mi.mesh = pm
	mi.position.y = _height * 0.5
	mi.material_override = BWLook.flat()
	var lk := ob().look()
	var tint := Color.WHITE if lk == "bright" else Color(0.08, 0.08, 0.09)
	if ob() is BWObjective and not lk in ["bright", "dark"]:
		tint = BWLook.element_color(lk).lerp(Color.WHITE, 0.25)   # D327: an object in an element's colour (a wind wall)
	mi.set_instance_shader_parameter("tint", tint)
	add_child(mi)


## A carved ring on the tile under the stone: it marks the objective hex.
func _base_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var r0 := 0.9
		var r1 := 0.98
		var p := [Vector3(cos(a0) * r0, 0.02, sin(a0) * r0), Vector3(cos(a0) * r1, 0.02, sin(a0) * r1),
			Vector3(cos(a1) * r1, 0.02, sin(a1) * r1), Vector3(cos(a1) * r0, 0.02, sin(a1) * r0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.add_vertex(p[idx])
	var ring := MeshInstance3D.new()
	ring.name = "base_ring"
	ring.mesh = st.commit()
	ring.material_override = glyph_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_instance_shader_parameter("glow", glow_color())
	ring.set_instance_shader_parameter("power", 0.5)
	add_child(ring)
	_glow_meshes.append(ring)


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 1.4)
	# the slow idle pulse: the glyphs breathe on a 2.6 s cycle (each stone its own phase)
	var phase := 0.0 if ob() == null or ob().look() == "bright" else PI
	var breathe := 0.55 + 0.3 * (0.5 + 0.5 * sin(_t * TAU / 2.6 + phase))
	for mi in _glow_meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter("power", (breathe + _flare * 1.6) if unit and unit.alive() else 0.0)
	if model:
		_rock = lerpf(_rock, 0.0, minf(1.0, delta * 6.0))
		model.rotation.z = _rock * 0.06 * sin(_t * 31.0)
		if ob() and ob().look() == "dark":
			model.rotation.y += delta * 0.12       # the Well turns, very slowly


# ---------------------------------------------------------------- poses

func idle() -> void:
	pass


func face(_world_target: Vector3) -> void:
	pass                     # a stone faces nowhere (the Well turns on its own)


func pose_named(p: String) -> void:
	match p:
		"hit", "kneel", "block", "fumble":
			_rock = 1.0
			_flare = maxf(_flare, 0.5)
		"dodge":
			_flicker()
		"fall":
			_crumble()
		_:
			if p.begins_with("stricken"):
				_rock = 1.0
				_flare = maxf(_flare, 0.5)


## The dodge: the stone goes thin (a ghost of itself) for a beat; the blow
## passes through the glare / the hollow.
func _flicker() -> void:
	_flare = 1.0
	if model == null:
		return
	var tw := create_tween()
	for k in 3:
		tw.tween_callback(func(): BWLook.set_dim(model, 0.75))
		tw.tween_interval(0.05)
		tw.tween_callback(func(): BWLook.set_dim(model, 0.0))
		tw.tween_interval(0.05)


func _crumble() -> void:
	if _crack:
		return
	_crack = true
	_flare = 1.0
	if model:
		var tw := create_tween()
		tw.tween_property(model, "rotation:z", 0.22, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(model, "position:y", -0.6, 0.6).set_ease(Tween.EASE_IN)


func time_to_marker(_marker_name: String) -> float:
	return -1.0


func lead_to_impact(_p: String) -> float:
	return 0.0


# ---------------------------------------------------------------- the pulse

## The turn's shockwave. `kind` "push" (the Lantern): a ring bursts out from
## the stone across the whole board; "pull" (the Well): a ring rushes in from
## the board's edge and collapses into the heart. Returns its length in s.
func pulse(kind: String) -> float:
	_flare = 1.0
	_rock = 0.6
	var ring := MeshInstance3D.new()
	ring.name = "pulse_ring"
	ring.mesh = _ring_mesh()
	ring.material_override = ring_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_instance_shader_parameter("glow", glow_color())
	ring.set_instance_shader_parameter("ink", 1.0 if ob().look() == "bright" else 0.0)
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.3, 0)
	var echo := ring.duplicate() as MeshInstance3D
	get_parent().add_child(echo)
	echo.global_position = ring.global_position + Vector3(0, 0.05, 0)
	var push := kind == "push"
	var from := 0.4 if push else PULL_FROM
	var to := RING_REACH if push else 0.5
	for r in [ring, echo]:
		r.scale = Vector3(from, 1, from)
		r.set_instance_shader_parameter("fade", 0.0 if push else 0.6)
	var tw := create_tween().set_parallel(true)
	var trans := Tween.TRANS_CUBIC if push else Tween.TRANS_SINE
	var ease := Tween.EASE_OUT if push else Tween.EASE_IN_OUT
	tw.tween_property(ring, "scale", Vector3(to, 1, to), PULSE_TIME).set_trans(trans).set_ease(ease)
	tw.tween_property(echo, "scale", Vector3(to, 1, to), PULSE_TIME).set_trans(trans).set_ease(ease).set_delay(0.14)
	for r in [ring, echo]:
		var rr: MeshInstance3D = r
		var f0 := 0.0 if push else 0.6
		var f1 := 1.0 if push else 0.0
		tw.tween_method(func(x: float):
			if is_instance_valid(rr):
				rr.set_instance_shader_parameter("fade", x), f0, f1, PULSE_TIME * (1.0 if push else 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if not push:                       # the pull's ring flares in, then vanishes into the heart
			tw.tween_method(func(x: float):
				if is_instance_valid(rr):
					rr.set_instance_shader_parameter("fade", x), 0.0, 1.0, 0.15).set_delay(PULSE_TIME - 0.05)
	var done := create_tween()
	done.tween_interval(PULSE_TIME + 0.35)
	done.tween_callback(ring.queue_free)
	done.tween_callback(echo.queue_free)
	return PULSE_TIME


## A thin flat band of radius 1 (scaled by the tween), a little height so it
## reads from the gameplay camera's pitch.
static func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 96
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var c0 := Vector3(cos(a0), 0, sin(a0))
		var c1 := Vector3(cos(a1), 0, sin(a1))
		# a wall (uv.y 0..1 up) and a floor band (uv.y 0, uv.x across)
		var quads := [
			[c0 * 0.94, c1 * 0.94, c1 * 1.0, c0 * 1.0, 0.0],
			[c0, c1, c1 + Vector3(0, 0.55, 0), c0 + Vector3(0, 0.55, 0), 1.0],
		]
		for q in quads:
			var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(float(q[4]), uvs[idx].y))
				st.add_vertex(q[idx])
	return st.commit()


static func glyph_material() -> ShaderMaterial:
	if _glyph_mat == null:
		var sh := Shader.new()
		sh.code = GLYPH_SHADER
		_glyph_mat = ShaderMaterial.new()
		_glyph_mat.shader = sh
	return _glyph_mat


static func ring_material() -> ShaderMaterial:
	if _ring_mat == null:
		var sh := Shader.new()
		sh.code = RING_SHADER
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = sh
	return _ring_mat


const GLYPH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
instance uniform float dim : hint_range(0.0, 1.0), instance_index(0) = 0.0;
instance uniform vec4 glow : source_color, instance_index(2) = vec4(1.0);
instance uniform float power : instance_index(3) = 0.6;
void fragment() {
	// carved glyphs: the cut is ink at rest and fills with the stone's light as it breathes
	vec3 ink = vec3(0.02);
	vec3 lit = glow.rgb * (0.55 + 0.9 * power);
	vec3 c = mix(ink, lit, clamp(power * 1.15, 0.0, 1.0));
	ALBEDO = mix(c, c * 0.012, dim);
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
instance uniform vec4 glow : source_color = vec4(1.0);
instance uniform float ink = 1.0;
instance uniform float fade = 0.0;
instance uniform float dim = 0.0;
void fragment() {
	// UV.x 0 = the floor band, 1 = the wall; UV.y up the wall
	float wall = UV.x;
	float a = mix(0.85, 0.75 * (1.0 - UV.y), wall);
	// an ink under-stroke so the band reads on the white tiles, the glow over the black sky
	vec3 c = mix(glow.rgb, vec3(0.02), ink * (1.0 - wall) * 0.6);
	a *= (1.0 - fade) * (1.0 - dim);
	if (a < 0.004) { discard; }
	ALBEDO = c;
	ALPHA = a;
}
"""

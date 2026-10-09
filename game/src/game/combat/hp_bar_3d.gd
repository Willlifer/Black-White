class_name BWHPBar3D
extends Node3D
## D215: the floating HP bar over a unit, a Giant, the Colossus or a stone
## (BWUnitView, BWObeliskView). One billboarded quad (shaders/hp_bar.gdshader):
## D495: by team (it was by HP, D215): the player's side black with white
## pips on a dark-grey well, everyone else white with black pips on a
## light-grey well; pips every 10% of max HP, a grey ghost for the chunk
## just lost, and a two-ring outline. No colour flip at 50% any more.
##
## The "hp / max" label shows only while the unit is hovered (combat sets
## `hover_unit` from the hex under the mouse) or the mouse is on the bar.
## D217: the bar and the name label (`carry`) stay below the turn-order bar:
## combat publishes its screen rect as `hud_rect`, and a bar that would
## project above its bottom edge slides down the screen until it clears.

static var hover_unit: BWUnit = null
static var hud_rect := Rect2()
## D230 (L-21): screen rects of the HUD plates (combat_ui.cover_rects). A bar
## whose rect (with the name label above it) touches one is culled: its quad
## and labels drop out of every camera's layers, so nothing shows through a
## translucent panel. Restored the frame it clears.
static var covers: Callable = Callable()
var covered := false
static var _shader: Shader

const PAD := 0.06
const LABEL_RISE := 0.18          # the name label sits this far above the bar (local)

var unit: BWUnit
var quad: MeshInstance3D
var label: Label3D
var width := 1.25
var height := 0.13
var shown := true                 # show_label(false) hides the whole bar
var _f := 1.0
var _ghost := 1.0
var _tween: Tween
var _pulse: Tween
var _base := Vector3.ZERO         # the local position the view placed it at


func _init(u: BWUnit = null, w: float = 1.25, h: float = 0.13) -> void:
	unit = u
	width = w
	height = h
	name = "hp_bar"
	if _shader == null:
		_shader = load("res://shaders/hp_bar.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(w + 2.0 * PAD, h + 2.0 * PAD)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.render_priority = 11
	m.set_shader_parameter("bar_size", Vector2(w, h))
	m.set_shader_parameter("pad", PAD)
	m.set_shader_parameter("ally", ally_side(u))      # D495
	quad = MeshInstance3D.new()
	quad.name = "bar"
	quad.mesh = q
	quad.material_override = m
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	label = Label3D.new()
	label.name = "hp_label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 17
	label.outline_size = 9
	label.modulate = Color.BLACK
	label.outline_modulate = Color.WHITE
	label.render_priority = 14
	label.outline_render_priority = 13
	label.visible = false
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP      # hangs just under the bar, the pips stay readable
	label.position.y = -(h * 0.5 + PAD)
	add_child(label)


## Where the view wants the bar (local to the view). The clamp moves it from here.
func place(y: float) -> void:
	_base = Vector3(0, y, 0)
	position = _base


## Set the fill. A drop leaves a grey ghost that drains after a beat; a
## crossing of 50% (either way) pulses the bar once.
func set_hp(hp: int, max_hp: int, animate: bool = true) -> void:
	var f := clampf(float(hp) / maxf(max_hp, 1), 0.0, 1.0)
	label.text = "%d / %d" % [hp, max_hp]
	if f < _f - 0.001 and animate and is_inside_tree():
		if _tween and _tween.is_valid():
			_tween.kill()
		_ghost = maxf(_ghost, _f)
		_tween = create_tween()
		_tween.tween_interval(0.35)
		_tween.tween_method(_set_ghost, _ghost, f, 0.45).set_trans(Tween.TRANS_SINE)
	else:
		if _tween and _tween.is_valid():
			_tween.kill()
		_set_ghost(f)
	_f = f
	_mat().set_shader_parameter("fill", f)
	_mat().set_shader_parameter("ally", ally_side(unit))   # D495: by team


func fraction() -> float:
	return _f


## D495: "black" (black fill, white pips: the player's side) or "white".
func mode() -> String:
	return "black" if ally_side(unit) else "white"


## D495: does `u`'s bar wear the ally colours? The player's team, and an
## objective that belongs to the player (the Lil Fella, a Defend gate).
## Enemies, the Giant, the Twins and the neutral stones read as enemies.
static func ally_side(u: BWUnit) -> bool:
	if u == null:
		return true
	if u.team == "player":
		return true
	return u is BWObjective and str((u as BWObjective).allegiance) == "player"


## The tiny pulse at the 50% flip: a quick swell and settle.
func pulse() -> void:
	if _pulse and _pulse.is_valid():
		_pulse.kill()
	quad.scale = Vector3.ONE
	_pulse = create_tween()
	_pulse.tween_property(quad, "scale", Vector3(1.12, 1.6, 1.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse.tween_property(quad, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_ghost(x: float) -> void:
	_ghost = x
	_mat().set_shader_parameter("ghost", x)


func _mat() -> ShaderMaterial:
	return quad.material_override as ShaderMaterial


func set_shown(v: bool) -> void:
	shown = v
	quad.visible = v
	if not v:
		label.visible = false


func hovered() -> bool:
	if unit != null and hover_unit == unit:
		return true
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.is_position_behind(quad.global_position):
		return false
	var r := screen_rect(cam)
	return r.grow_individual(4, 6, 4, 6).has_point(get_viewport().get_mouse_position())


## The bar's rectangle on screen (readability keeps blast tags off it).
func screen_rect(cam: Camera3D) -> Rect2:
	var c := quad.global_position
	var s := global_transform.basis.get_scale().x
	var half := cam.global_basis.x * ((width * 0.5 + PAD) * s)
	var up := cam.global_basis.y * ((height * 0.5 + PAD) * s)
	var a := cam.unproject_position(c - half - up)
	var b := cam.unproject_position(c + half + up)
	return Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y))


func _process(_delta: float) -> void:
	if not shown or not is_visible_in_tree():
		return
	label.visible = hovered()
	_clamp_below_hud()
	_cull_under_hud()


func _cull_under_hud() -> void:
	var hide := false
	if covers.is_valid():
		var cam := get_viewport().get_camera_3d()
		if cam != null and not cam.is_position_behind(quad.global_position):
			var r := screen_rect(cam).grow_individual(2, 30, 2, 18)   # the name label above, "hp / max" below
			for c in covers.call():
				if (c as Rect2).intersects(r):
					hide = true
					break
	if hide != covered:
		set_covered(hide)


func set_covered(v: bool) -> void:
	covered = v
	for n in [quad] + find_children("*", "Label3D", true, false):
		var vi := n as VisualInstance3D
		if v:
			if not vi.has_meta("hud_layers"):
				vi.set_meta("hud_layers", vi.layers)
			vi.layers = 0
		elif vi.has_meta("hud_layers"):
			vi.layers = int(vi.get_meta("hud_layers"))
			vi.remove_meta("hud_layers")


func _clamp_below_hud() -> void:
	position = _base
	if not hud_rect.has_area():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return
	var s := global_transform.basis.get_scale().y
	var top := global_position + cam.global_basis.y * (LABEL_RISE * s)
	if cam.is_position_behind(top):
		return
	var sy := cam.unproject_position(top).y - 12.0      # the name label's top edge
	var limit := hud_rect.end.y + 6.0
	if sy >= limit:
		return
	var depth := (global_position - cam.global_position).dot(-cam.global_basis.z)
	var vh := get_viewport().get_visible_rect().size.y
	if depth <= 0.01 or vh <= 0.0:
		return
	var wpp := 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / vh
	global_position -= cam.global_basis.y * ((limit - sy) * wpp)

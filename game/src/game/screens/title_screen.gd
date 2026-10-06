class_name BWTitleScreen
extends Node3D
## Brief: all black and white; fades in, circling the arena map with no
## characters; big lettering "Black | White"; press any button. (D83)
##
## Up from black over ~2 s; the camera orbits the arena's true middle
## (BWLoadingScreen's framing: the mean of the tiles, back far enough for its
## widest extent) with a slow breathing bob in height, pitch and distance;
## a near shell of stars in front of the sky's, so the orbit has parallax.
## The mark: a white bar, then two plates wiping out from it — "Black" in
## white on black, "White" in black on white — then "press any button"
## pulsing, and "C  continue your run" when a save exists. The UI is drawn in
## the 1600×900 design space and scales with the window (4K included).

signal done(choice: String)     # "new" | "continue" | "tutorial" (D223)

const ORBIT := 0.085            # rad/s
const FADE_IN := 2.2

var has_save := false
## D150: the save is from before the roster rename (BWRun.can_load false):
## say so instead of offering to continue; any key starts fresh.
var old_save := false
var _rig: Node3D
var _arm: Node3D
var _cam: Camera3D
var _base_y := 0.0
var _dist := 22.0
var _mark: TitleMark
var _prompt: Label
var _cont: Label
var _set_line: Button               # D124: "S  settings"
var _tut_line: Button               # D223: "T  tutorial"
var settings: BWSettingsPanel
var _black: ColorRect
var _ready_for_input := false
var _t := 0.0


func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	add_child(we)
	var board := BWBoard.load_file("res://maps/arena.json")
	var bv := BWBoardView.new()
	add_child(bv)
	bv.build(board)
	# orbit the board's true middle, far enough back for its widest extent
	var mid := Vector3.ZERO
	var cells: Array = board.cells()
	for h in cells:
		mid += BWLook.world(h, board.elevation(h))
	mid /= maxf(1.0, cells.size())
	var radius := 0.0
	for h in cells:
		var p := BWLook.world(h)
		radius = maxf(radius, Vector2(p.x - mid.x, p.z - mid.z).length())
	_rig = Node3D.new()
	# aim above the board: it sits in the lower half, the mark over the sky
	_rig.position = mid + Vector3(0, 3.2, 0)
	_base_y = _rig.position.y
	_rig.rotation.y = 0.6
	add_child(_rig)
	_arm = Node3D.new()
	_arm.rotation_degrees.x = -30.0
	_rig.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_dist = clampf(radius * 3.3, 20.0, 52.0)
	_cam.position = Vector3(0, 0, _dist)
	_arm.add_child(_cam)
	_cam.make_current()
	_build_near_stars(mid)

	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWStyle.theme()
	ui.add_child(root)
	# a soft vignette so the mark sits on dark
	var vig := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 1.0)
	gt.width = 128
	gt.height = 128
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	_mark = TitleMark.new()
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_mark)
	_prompt = Label.new()
	_prompt.text = "PRESS ANY BUTTON"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 21)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	var plate := PanelContainer.new()
	var ps := BWStyle.hud_style()
	ps.bg_color = Color(0, 0, 0, 0.72)
	ps.set_content_margin_all(10)
	ps.content_margin_left = 26
	ps.content_margin_right = 26
	plate.add_theme_stylebox_override("panel", ps)
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -170
	plate.offset_right = 170
	plate.offset_top = 452
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(lines)
	lines.add_child(_prompt)
	plate.modulate.a = 0.0
	root.add_child(plate)
	set_meta("plate", plate)
	_cont = Label.new()
	_cont.text = "This save is from an older version  ·  a new run starts fresh" if old_save else "C    continue your run"
	_cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cont.add_theme_font_size_override("font_size", 19)
	_cont.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_cont.add_theme_color_override("font_outline_color", Color.BLACK)
	_cont.add_theme_constant_override("outline_size", 8)
	_cont.modulate.a = 0.0
	_cont.visible = has_save
	lines.add_child(_cont)
	# ---- D124: the settings entry (S, or click it)
	_set_line = Button.new()
	_set_line.text = "S    settings"
	_set_line.flat = true
	_set_line.focus_mode = Control.FOCUS_NONE
	_set_line.add_theme_font_size_override("font_size", 19)
	_set_line.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_set_line.add_theme_color_override("font_hover_color", Color.WHITE)
	_set_line.add_theme_color_override("font_outline_color", Color.BLACK)
	_set_line.add_theme_constant_override("outline_size", 8)
	_set_line.modulate.a = 0.0
	_set_line.pressed.connect(open_settings)
	# ---- D223: the tutorial entry, next to settings (T, or click it)
	var opts := HBoxContainer.new()
	opts.alignment = BoxContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("separation", 28)
	lines.add_child(opts)
	opts.add_child(_set_line)
	_tut_line = Button.new()
	_tut_line.name = "tutorial_entry"
	_tut_line.text = "T    tutorial"
	for k in ["flat", "focus_mode", "modulate"]:
		_tut_line.set(k, _set_line.get(k))
	for c in ["font_color", "font_hover_color", "font_outline_color"]:
		_tut_line.add_theme_color_override(c, _set_line.get_theme_color(c))
	_tut_line.add_theme_font_size_override("font_size", 19)
	_tut_line.add_theme_constant_override("outline_size", 8)
	_tut_line.pressed.connect(open_tutorial)
	opts.add_child(_tut_line)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)
	# the sequence: up from black, the bar, the plates, the words, the prompt
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_black, "color:a", 0.0, FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var mk := create_tween()
	mk.tween_interval(1.0)
	mk.tween_property(_mark, "bar", 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	mk.tween_property(_mark, "wipe", 1.0, 0.85).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	mk.parallel().tween_property(_mark, "words", 1.0, 0.7).set_delay(0.35).set_trans(Tween.TRANS_SINE)
	mk.tween_callback(func(): _ready_for_input = true)
	mk.tween_property(get_meta("plate"), "modulate:a", 1.0, 0.4)
	mk.tween_property(_cont, "modulate:a", 1.0, 0.6)
	mk.parallel().tween_property(_set_line, "modulate:a", 1.0, 0.6)
	mk.parallel().tween_property(_tut_line, "modulate:a", 1.0, 0.6)


## A shell of nearer stars around the arena, in front of the sky's: as the
## camera circles, they slide against the far field (parallax).
func _build_near_stars(mid: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	mm.mesh = q
	mm.instance_count = 520
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.75, 1), rng.randf_range(-1, 1)).normalized()
		var r := rng.randf_range(48.0, 95.0)
		var s := rng.randf_range(0.5, 1.6) * r / 60.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), mid + d * r))
		var b := rng.randf_range(0.35, 1.0)
		mm.set_instance_color(i, Color(b, b, b, 1.0))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _dot_texture()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt


func _process(delta: float) -> void:
	_t += delta
	# the orbit, with a slow bob: height, pitch and distance on unrelated periods
	_rig.rotation.y += delta * ORBIT
	_rig.position.y = _base_y + 0.35 * sin(_t * 0.29)
	_arm.rotation_degrees.x = -30.0 + 3.2 * sin(_t * 0.21 + 0.7)
	_cam.position.z = _dist + 1.4 * sin(_t * 0.17)
	if _ready_for_input:
		_prompt.modulate.a = 0.68 + 0.32 * sin(_t * 2.2)


## D124: the settings overlay over the orbit; the title waits for it.
func open_settings() -> void:
	if settings and is_instance_valid(settings):
		return
	settings = BWSettingsPanel.summon(self)


## D223: the guided practice fight; the title waits for nothing else.
func open_tutorial() -> void:
	if not _ready_for_input or (settings and is_instance_valid(settings)):
		return
	_ready_for_input = false
	done.emit("tutorial")


func _unhandled_input(ev: InputEvent) -> void:
	if not _ready_for_input or (settings and is_instance_valid(settings)):
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_S:
		open_settings()
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_T:   # ---- D223
		open_tutorial()
		get_viewport().set_input_as_handled()
		return
	var pressed: bool = (ev is InputEventKey and ev.pressed and not ev.echo) \
		or (ev is InputEventMouseButton and ev.pressed) \
		or (ev is InputEventJoypadButton and ev.pressed)
	if not pressed:
		return
	_ready_for_input = false
	var choice := "continue" if has_save and not old_save and ev is InputEventKey and ev.keycode == KEY_C else "new"
	done.emit(choice)


## The lettering. A white bar grows from the middle; two plates wipe out from
## it, "Black" in white on a black plate, "White" in black on a white plate,
## each with the other colour's rule round it and a drop shadow.
class TitleMark:
	extends Control
	var bar := 0.0:
		set(v):
			bar = v
			queue_redraw()
	var wipe := 0.0:
		set(v):
			wipe = v
			queue_redraw()
	var words := 0.0:
		set(v):
			words = v
			queue_redraw()
	var _font: FontVariation

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.85
		_font.spacing_glyph = 3

	func _draw() -> void:
		var c := size * Vector2(0.5, 0.33)
		var fs := 118
		var half_w := 452.0
		var h := 176.0
		var gap := 13.0
		var top := c.y - h * 0.5
		# the bar: from the middle out, past the plates above and below
		var bl := (h + 96.0) * bar
		if bar > 0.0:
			draw_rect(Rect2(c.x - 3.5, c.y - bl * 0.5, 7.0, bl), Color.WHITE)
		if wipe <= 0.0:
			return
		var w := half_w * wipe
		var lp := Rect2(c.x - gap - w, top, w, h)
		var rp := Rect2(c.x + gap, top, w, h)
		# shadows
		draw_rect(Rect2(lp.position + Vector2(10, 12), lp.size), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(rp.position + Vector2(10, 12), rp.size), Color(0, 0, 0, 0.55))
		# plates and their rules
		draw_rect(lp.grow(3), Color.WHITE)
		draw_rect(lp, Color(0.015, 0.015, 0.015))
		draw_rect(lp.grow(-9), Color.WHITE, false, 2.0)
		draw_rect(rp.grow(3), Color.BLACK)
		draw_rect(rp, Color(0.97, 0.97, 0.97))
		draw_rect(rp.grow(-9), Color.BLACK, false, 2.0)
		if words <= 0.0:
			return
		var a := clampf(words, 0.0, 1.0)
		var by := c.y + fs * 0.34
		var lw := _font.get_string_size("Black", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rw := _font.get_string_size("White", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rise := (1.0 - a) * 14.0
		draw_string(_font, Vector2(c.x - gap - half_w * 0.5 - lw * 0.5, by + rise), "Black", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
		draw_string(_font, Vector2(c.x + gap + half_w * 0.5 - rw * 0.5, by + rise), "White", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, a))

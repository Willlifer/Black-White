class_name BWBootScreen
extends CanvasLayer
## D381 (L-15): the boot screen. Shown over the game while the D232 shader
## pre-warm pass (BWShaderWarm) draws offscreen, then it fades away onto the
## title, which builds underneath it from the first frame. Black ground, the
## mark's white bar with "Black" and "White" either side, a thin progress
## line fed by BWShaderWarm.progress and a one-line hint. It never waits on
## anything but the warm pass (MAX_WAIT caps it), so boot is no slower: the
## title was already building under the warm pass before.
## (Replaces BWLoadingScreen, the map montage unused since D84.)

signal finished

const MIN_SHOW := 0.25        # s, so it never flickers
const MAX_WAIT := 4.0         # s, a warm pass that never reports done
const FADE := 0.35

var _root: Control
var _bar_fill: ColorRect
var _hint: Label
var _t := 0.0
var _leaving := false
## Review renders: hold at this progress (0-1) and never leave (-1 = live).
var freeze_at := -1.0


func _ready() -> void:
	layer = 120
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_fit()
	get_viewport().size_changed.connect(_fit)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 22)
	mark.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(mark)
	var left := Label.new()
	left.text = "Black"
	left.add_theme_font_size_override("font_size", 44)
	left.add_theme_color_override("font_color", Color.WHITE)
	mark.add_child(left)
	var bar := ColorRect.new()
	bar.color = Color.WHITE
	bar.custom_minimum_size = Vector2(6, 58)
	mark.add_child(bar)
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	plate.add_theme_stylebox_override("panel", sb)
	mark.add_child(plate)
	var right := Label.new()
	right.text = "White"
	right.add_theme_font_size_override("font_size", 44)
	right.add_theme_color_override("font_color", Color.BLACK)
	plate.add_child(right)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.16)
	track.custom_minimum_size = Vector2(300, 3)
	var tc := CenterContainer.new()
	tc.add_child(track)
	v.add_child(tc)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color.WHITE
	_bar_fill.size = Vector2(0, 3)
	track.add_child(_bar_fill)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_hint.add_theme_color_override("font_color", BWStyle.FAINT)
	v.add_child(_hint)
	_update(0.0)


func _process(delta: float) -> void:
	_t += delta
	if freeze_at >= 0.0:
		_update(freeze_at)
		return
	var p := 1.0 if not BWShaderWarm.pending else BWShaderWarm.progress
	_update(p)
	if not _leaving and _t >= MIN_SHOW and (not BWShaderWarm.pending or _t >= MAX_WAIT):
		_leave()


func _update(p: float) -> void:
	_bar_fill.size.x = 300.0 * clampf(p, 0.0, 1.0)
	_hint.text = "ready" if p >= 1.0 else "warming up the effects  ·  %d%%" % int(round(p * 100.0))


func _leave() -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


## Controls under a CanvasLayer have no parent rect: size to the viewport.
func _fit() -> void:
	_root.position = Vector2.ZERO
	_root.size = get_viewport().get_visible_rect().size

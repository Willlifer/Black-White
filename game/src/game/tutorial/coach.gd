class_name BWCoach
extends CanvasLayer
## D224: the tutorial's coach. A small BWStyle panel top left (the lesson,
## one prompt of at most two short sentences, its glossary terms hoverable,
## Next on read-only steps), a highlight layer that pulses an outline round a
## piece of UI or a ring and arrow over a hex or a unit, and the Esc dialog
## (skip this lesson / exit the tutorial / keep going).
##
## The tutorial feeds it: show(step, ...) for the words, `targets` (a
## Callable returning [{rect} | {point, ring}]) for the highlight each frame.

signal next_pressed
signal skip_pressed
signal exit_pressed

const W := 470.0
const ARROW := 34.0

var targets: Callable                  # () -> Array of { rect: Rect2 } | { point: Vector2, ring: float }
var esc_passes: Callable               # () -> bool: let this Esc through to the game (undo, back out)
var _panel: PanelContainer
var _kicker: Label
var _count: Label
var _body: BWGlossary.Rich
var _next: Button
var _esc_hint: Label
var _layer: HighlightLayer
var _dialog: PanelContainer
var _dim: ColorRect
var _t := 0.0
var shown_text := ""                   # the prompt now (probes)


func _ready() -> void:
	layer = 40
	_layer = HighlightLayer.new()
	_layer.coach = self
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWStyle.theme()
	add_child(root)
	_panel = PanelContainer.new()
	var sb := BWStyle.box_style()
	sb.border_color = Color.WHITE
	sb.border_width_left = 5
	sb.set_content_margin_all(14)
	sb.content_margin_left = 18
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(W, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_kicker = BWStyle.section_label("")
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", BWStyle.FAINT)
	head.add_child(_count)
	_body = BWGlossary.Rich.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(W - 32, 0)
	_body.add_theme_font_size_override("normal_font_size", BWStyle.F_BODY)
	_body.add_theme_font_size_override("bold_font_size", BWStyle.F_BODY)
	_body.add_theme_color_override("default_color", BWStyle.TEXT)
	v.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	_esc_hint = Label.new()
	_esc_hint.text = "Esc  skip or exit"
	_esc_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_esc_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_esc_hint.add_theme_font_size_override("font_size", 14)
	_esc_hint.add_theme_color_override("font_color", BWStyle.FAINT)
	foot.add_child(_esc_hint)
	_next = Button.new()
	_next.name = "coach_next"
	_next.text = "Next  ▸"
	_next.focus_mode = Control.FOCUS_NONE
	_next.custom_minimum_size = Vector2(120, 36)
	_next.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_next.pressed.connect(func(): next_pressed.emit())
	foot.add_child(_next)
	_build_dialog(root)


func _build_dialog(root: Control) -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)
	_dialog = PanelContainer.new()
	var sb := BWStyle.box_style()
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	_dialog.add_theme_stylebox_override("panel", sb)
	_dialog.anchor_left = 0.5
	_dialog.anchor_right = 0.5
	_dialog.anchor_top = 0.5
	_dialog.anchor_bottom = 0.5
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dialog.visible = false
	root.add_child(_dialog)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_dialog.add_child(v)
	var t := Label.new()
	t.text = "Tutorial"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	v.add_child(t)
	for b in [["Skip this lesson", "dialog_skip", func(): close_dialog(); skip_pressed.emit()],
			["Exit to the title", "dialog_exit", func(): close_dialog(); exit_pressed.emit()],
			["Keep going  [Esc]", "dialog_back", close_dialog]]:
		var btn := Button.new()
		btn.name = str(b[1])
		btn.text = str(b[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(300, 42)
		btn.add_theme_font_size_override("font_size", BWStyle.F_BODY)
		btn.pressed.connect(b[2])
		v.add_child(btn)


## The words for one step: the lesson, the prompt, Next when it's read-only.
func show_step(lesson: int, lesson_count: int, lesson_name: String, text: String, index: int, total: int, can_next: bool) -> void:
	_kicker.text = ("Tutorial" if lesson == 0 else "Lesson %d of %d  ·  %s" % [lesson, lesson_count, lesson_name]).to_upper()
	_count.text = "%d / %d" % [index + 1, total]
	shown_text = text
	_body.set_glossed(text)
	_next.visible = can_next
	_place.call_deferred()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.18)


## Top left in the fight; bottom left over the summary, the picks and the
## closing card, which fill the middle.
func dock_low(low: bool) -> void:
	_panel.set_meta("low", low)
	_place()


func _place() -> void:
	var vp := _panel.get_viewport_rect().size
	_panel.reset_size()
	_panel.position = Vector2(16, vp.y - _panel.size.y - 16) if _panel.get_meta("low", false) else Vector2(16, 16)


func set_next_visible(on: bool) -> void:
	_next.visible = on


func next_button() -> Button:
	return _next


func panel_visible(on: bool) -> void:
	_panel.visible = on


func dialog_open() -> bool:
	return _dialog.visible


func open_dialog() -> void:
	_dim.visible = true
	_dialog.visible = true
	_dialog.reset_size()


func close_dialog() -> void:
	_dim.visible = false
	_dialog.visible = false


func dialog_button(which: String) -> Button:
	return _dialog.find_child("dialog_" + which, true, false) as Button


## Esc belongs to the coach first: it closes the dialog, or opens it, unless
## the step wants Esc itself (undo the move, back out of an aim) or a window
## that Esc should close (a tooltip, the codex, settings) is on top.
## Enter is Next on a read-only step.
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if ev.keycode == KEY_ESCAPE:
		if _dialog.visible:
			close_dialog()
		elif esc_passes.is_valid() and esc_passes.call():
			return
		elif not BWEsc.top_name() in ["", "confirm", "picker"]:
			return
		else:
			open_dialog()
		get_viewport().set_input_as_handled()
	elif _dialog.visible:
		match ev.keycode:
			KEY_S: close_dialog(); skip_pressed.emit()
			KEY_X: close_dialog(); exit_pressed.emit()
		get_viewport().set_input_as_handled()
	elif ev.keycode in [KEY_ENTER, KEY_KP_ENTER] and _next.visible and _panel.visible:
		next_pressed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	if _panel.get_meta("low", false):
		_place()
	_layer.queue_redraw()


## Pulsing outlines round UI rects, a ring and a bobbing arrow over board
## points. Never takes the mouse.
class HighlightLayer:
	extends Control
	var coach: BWCoach

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if coach == null or not coach.targets.is_valid() or coach._dialog.visible:
			return
		var p := 0.5 + 0.5 * sin(coach._t * 5.0)
		for t in coach.targets.call():
			if t.has("rect"):
				var r: Rect2 = t.rect
				if r.size.x <= 0.0:
					continue
				var g := (6.0 + 4.0 * p) if r.size.y > 48.0 else (2.0 + 2.0 * p)   # small labels: hug them
				draw_rect(r.grow(g + 3.0), Color(0, 0, 0, 0.8), false, 6.0)
				draw_rect(r.grow(g), Color(1, 1, 1, 0.55 + 0.45 * p), false, 3.0)
			elif t.has("point"):
				var c: Vector2 = t.point
				var rad: float = float(t.get("ring", 26.0)) * (1.0 + 0.12 * p)
				draw_arc(c, rad + 3.0, 0, TAU, 40, Color(0, 0, 0, 0.8), 6.0)
				draw_arc(c, rad, 0, TAU, 40, Color(1, 1, 1, 0.6 + 0.4 * p), 3.0)
				var tip: Vector2 = t.get("arrow", c - Vector2(0, rad + 8.0))
				tip.y -= 8.0 * p
				var pts := PackedVector2Array([tip, tip + Vector2(-ARROW * 0.5, -ARROW * 0.8), tip + Vector2(-ARROW * 0.18, -ARROW * 0.8),
					tip + Vector2(-ARROW * 0.18, -ARROW * 1.6), tip + Vector2(ARROW * 0.18, -ARROW * 1.6), tip + Vector2(ARROW * 0.18, -ARROW * 0.8),
					tip + Vector2(ARROW * 0.5, -ARROW * 0.8)])
				draw_colored_polygon(pts, Color.WHITE)
				var ring := pts.duplicate()
				ring.append(pts[0])
				draw_polyline(ring, Color.BLACK, 2.5, true)

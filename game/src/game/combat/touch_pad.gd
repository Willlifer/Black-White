class_name BWTouchPad
extends Control
## D574 (author, 2026-10-11, "make it mobile browser friendly"): the mobile
## layout's on-screen controller, laid over the combat HUD.
##   top-left      ◀ ▶ turn the camera 60° around the acting unit, II pauses
##   bottom-left   an 8-way stick: steps the board cursor (or the menu
##                 highlight), repeating while held
##   bottom-right  three face buttons: A right (confirm / open your unit's
##                 commands), B bottom (back), X left (more information).
##                 No Y (author: the commands open on your turn, or on A over
##                 your own unit, as in Fire Emblem / FFT)
## A held through playback fast-forwards it (hold Space on desktop).
## Fingers and the mouse both work: a screen touch is taken per finger (so a
## thumb resting on the stick doesn't block a tap on A); once a touch has been
## seen, the emulated mouse copies of it are ignored.

signal step(dir: int)                 # 0 right, 1 down-right, 2 down … 7 up-right (screen space, 45° apart)
signal pressed(id: String)            # "a", "b", "x", "turn_left", "turn_right", "pause"
signal released(id: String)

const BTN := 84.0                     # face button diameter
const GAP := 92.0                     # centre to centre, diamond arm
const STICK := 220.0                  # stick diameter
const REPEAT_FIRST := 0.32
const REPEAT := 0.13
const MARGIN := 28.0

static var touch_seen := false

var held := {}                        # id -> true while down
var _stick: Stick
var _buttons := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick = Stick.new()
	_stick.pad = self
	_stick.anchor_top = 1.0
	_stick.anchor_bottom = 1.0
	_stick.offset_left = MARGIN
	_stick.offset_right = MARGIN + STICK
	_stick.offset_top = -STICK - MARGIN
	_stick.offset_bottom = -MARGIN
	add_child(_stick)
	var c := Vector2(-MARGIN - BTN / 2.0 - GAP, -MARGIN - BTN / 2.0 - GAP)     # diamond centre, from the bottom-right
	_face("x", "X", c + Vector2(-GAP, 0))
	_face("a", "A", c + Vector2(GAP, 0))
	_face("b", "B", c + Vector2(0, GAP))
	_corner("turn_left", "◀", Vector2(MARGIN, MARGIN))
	_corner("turn_right", "▶", Vector2(MARGIN + 76, MARGIN))
	_corner("pause", "II", Vector2(MARGIN + 168, MARGIN))


func _face(id: String, label: String, centre: Vector2) -> void:
	var b := PadButton.new()
	b.pad = self
	b.id = id
	b.label = label
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = centre.x - BTN / 2.0
	b.offset_right = centre.x + BTN / 2.0
	b.offset_top = centre.y - BTN / 2.0
	b.offset_bottom = centre.y + BTN / 2.0
	b.name = "pad_" + id
	add_child(b)
	_buttons[id] = b


func _corner(id: String, label: String, at: Vector2) -> void:
	var b := PadButton.new()
	b.pad = self
	b.id = id
	b.label = label
	b.small = true
	b.offset_left = at.x
	b.offset_top = at.y
	b.offset_right = at.x + 64
	b.offset_bottom = at.y + 64
	b.name = "pad_" + id
	add_child(b)
	_buttons[id] = b


func button(id: String) -> Control:
	return _buttons.get(id)


func stick() -> Control:
	return _stick


## Rects the pad covers (the HUD keeps its panels out of them).
func cover_rects() -> Array:
	var out: Array = [_stick.get_global_rect()]
	for id in _buttons:
		out.append((_buttons[id] as Control).get_global_rect())
	return out


func _press(id: String) -> void:
	held[id] = true
	pressed.emit(id)


func _release(id: String) -> void:
	if held.erase(id):
		released.emit(id)


## The 8-way index for a vector in screen space (y down), or -1 inside the dead zone.
static func dir_of(v: Vector2, dead: float = 0.0) -> int:
	if v.length() <= dead:
		return -1
	return posmod(roundi(v.angle() / (PI / 4.0)), 8)


static func dir_vec(d: int) -> Vector2:
	return Vector2.RIGHT.rotated(d * PI / 4.0)


# ---------------------------------------------------------------- parts

class PadButton:
	extends Control
	var pad: BWTouchPad
	var id := ""
	var label := ""
	var small := false
	var _down := false
	var _finger := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			BWTouchPad.touch_seen = true
			if ev.pressed and not _down:
				_finger = ev.index
				_set_down(true)
			elif not ev.pressed and ev.index == _finger:
				_set_down(false)
			accept_event()
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if BWTouchPad.touch_seen:
				return
			_set_down(ev.pressed)

	func _set_down(v: bool) -> void:
		if v == _down:
			return
		_down = v
		queue_redraw()
		if v:
			pad._press(id)
		else:
			pad._release(id)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _down and not BWTouchPad.touch_seen:
			_set_down(false)

	func _draw() -> void:
		var r := size.x / 2.0
		var c := size / 2.0
		draw_circle(c, r, Color(1, 1, 1, 0.92) if _down else Color(0, 0, 0, 0.55))
		draw_arc(c, r - 1.5, 0, TAU, 48, Color(1, 1, 1, 0.9), 3.0, true)
		var f := get_theme_default_font()
		var fs := 26 if small else 38
		var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, c + Vector2(-ts.x / 2.0, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color.BLACK if _down else Color.WHITE)


class Stick:
	extends Control
	var pad: BWTouchPad
	var _down := false
	var _finger := -1
	var _knob := Vector2.ZERO
	var _dir := -1
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			BWTouchPad.touch_seen = true
			accept_event()
			if ev.pressed and not _down:
				_finger = ev.index
				_down = true
				_move(ev.position)
			elif not ev.pressed and ev.index == _finger:
				_end()
		elif ev is InputEventScreenDrag:
			accept_event()
			if _down and ev.index == _finger:
				_move(ev.position)
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if BWTouchPad.touch_seen:
				return
			if ev.pressed:
				_down = true
				_move(ev.position)
			else:
				_end()
		elif ev is InputEventMouseMotion:
			accept_event()
			if _down and not BWTouchPad.touch_seen:
				_move(ev.position)

	func _move(p: Vector2) -> void:
		var c := size / 2.0
		var v := p - c
		var r := size.x / 2.0 - 30.0
		_knob = v.limit_length(r)
		var d := BWTouchPad.dir_of(v, 22.0)
		if d != _dir:
			_dir = d
			_t = BWTouchPad.REPEAT_FIRST
			if d >= 0:
				pad.step.emit(d)
		queue_redraw()

	func _end() -> void:
		_down = false
		_dir = -1
		_knob = Vector2.ZERO
		queue_redraw()

	func _process(delta: float) -> void:
		if not _down or _dir < 0:
			return
		_t -= delta
		if _t <= 0.0:
			_t = BWTouchPad.REPEAT
			pad.step.emit(_dir)

	func _draw() -> void:
		var c := size / 2.0
		var r := size.x / 2.0
		draw_circle(c, r, Color(0, 0, 0, 0.45))
		draw_arc(c, r - 1.5, 0, TAU, 64, Color(1, 1, 1, 0.85), 3.0, true)
		for k in 8:
			var d := BWTouchPad.dir_vec(k)
			var lit := _down and k == _dir
			draw_line(c + d * (r - 34), c + d * (r - 12), Color(1, 1, 1, 1.0 if lit else 0.5), 6.0 if lit else 3.0, true)
		draw_circle(c + _knob, 40.0, Color(1, 1, 1, 0.9) if _down else Color(1, 1, 1, 0.35))
		draw_arc(c + _knob, 40.0, 0, TAU, 40, Color.WHITE, 2.0, true)

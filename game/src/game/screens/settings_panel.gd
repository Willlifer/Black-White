class_name BWSettingsPanel
extends CanvasLayer
## D124: the settings overlay, in BWStyle. Opened from the title (S) and the
## pause menu; works while the tree is paused. Every change applies and
## saves at once (BWSettings.put). Esc or Done closes it and emits `closed`.
##     BWSettingsPanel.summon(self)

signal closed

const LAYER := 96
const W := 760.0

var _seg := {}           # setting key -> { value -> Button }
var _sliders := {}       # setting key -> HSlider
var _note: Label


static func summon(host: Node) -> BWSettingsPanel:
	var p := BWSettingsPanel.new()
	host.add_child(p)
	return p


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	BWEsc.push(self, close, { "name": "settings" })           # ---- D171


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			if BWEsc.routed():
				return                            # ---- D171: BWEsc closes it (the newest window)
			close()
		if ev.keycode != KEY_F11:
			get_viewport().set_input_as_handled()


## Press one choice of a segmented setting (the probes use it too).
func choose(key: String, value: Variant) -> void:
	var b: Button = _seg.get(key, {}).get(str(value))
	if b:
		b.button_pressed = true
		b.pressed.emit()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = BWStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BWStyle.box_style())
	panel.custom_minimum_size = Vector2(W, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)       # D231: 8 -> 4, room for Accessibility at 16:9
	panel.add_child(v)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	v.add_child(title)
	v.add_child(HSeparator.new())

	v.add_child(BWStyle.section_label("Sound"))
	for k in ["vol_master", "vol_music", "vol_sfx", "vol_voice", "vol_ui"]:
		_slider(v, k, { "vol_master": "Master", "vol_music": "Music", "vol_sfx": "Effects", "vol_voice": "Voices", "vol_ui": "Interface" }[k])

	v.add_child(BWStyle.section_label("Display"))
	_segmented(v, "fullscreen", "Fullscreen", [[false, "Off"], [true, "On"]])
	var wins: Array = []
	for w in BWSettings.WINDOW_PRESETS:
		wins.append([w, "Maximized" if w == "" else str(w).replace("x", "×")])
	_segmented(v, "window", "Window", wins)
	var scales: Array = []
	for s in BWSettings.UI_SCALES:
		scales.append([s, "%d%%" % roundi(s * 100.0)])
	_segmented(v, "scale_ui", "Interface size", scales)

	v.add_child(BWStyle.section_label("Cutscenes"))
	var modes: Array = []
	for m in BWCutsceneTier.MODES:
		modes.append([m, BWCutsceneTier.MODE_LABELS[m]])
	_segmented(v, "cutscenes", "Mode  [F in battle]", modes)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_note.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = W - 40
	v.add_child(_note)
	_segmented(v, "skip_hold", "Hold Space to skip", [[false, "Off"], [true, "On"]])

	v.add_child(BWStyle.section_label("Combat"))
	_segmented(v, "show_odds", "Odds strip", [[false, "Off"], [true, "On"]])
	_segmented(v, "show_numbers", "Damage numbers", [[false, "Off"], [true, "On"]])
	_segmented(v, "screen_shake", "Screen shake", [[false, "Off"], [true, "On"]])   # ---- D170

	v.add_child(BWStyle.section_label("Accessibility"))                              # ---- D231
	_segmented(v, "element_kanji", "Element kanji  火 水 氷", [[false, "Off"], [true, "On"]])
	BWKanji.fallback(v.get_child(v.get_child_count() - 1).get_child(0))   # the row label shows the glyphs

	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		BWSettings.reset()
		_sync())
	foot.add_child(reset)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var done := Button.new()
	done.text = "Done  [Esc]"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(160, 42)
	done.pressed.connect(close)
	foot.add_child(done)
	_sync()


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 210
	l.add_theme_color_override("font_color", BWStyle.LABEL)
	l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	h.add_child(l)
	return h


func _slider(parent: Control, key: String, label: String) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size.y = 26
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.18)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.94, 0.94, 0.95)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _knob(false))
	s.add_theme_icon_override("grabber_highlight", _knob(true))
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	h.add_child(val)
	s.value_changed.connect(func(x: float):
		val.text = "%d%%" % roundi(x)
		if not is_equal_approx(float(BWSettings.value(key)) * 100.0, x):
			BWSettings.put(key, x / 100.0))
	_sliders[key] = s


static var _knobs := {}

func _knob(hi: bool) -> Texture2D:
	if _knobs.has(hi):
		return _knobs[hi]
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
			if d <= 6.5:
				img.set_pixel(x, y, Color.WHITE)
			elif d <= 8.5:
				img.set_pixel(x, y, Color(0, 0, 0, 1) if not hi else Color(1, 1, 1, 0.55))
	var t := ImageTexture.create_from_image(img)
	_knobs[hi] = t
	return t


func _segmented(parent: Control, key: String, label: String, options: Array) -> void:
	var h := _row(parent, label)
	var group := ButtonGroup.new()
	_seg[key] = {}
	var on := BWStyle.button_style("hover")
	on.bg_color = Color(0.94, 0.94, 0.95)
	for o in options:
		var b := Button.new()
		b.text = str(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_color_override("font_pressed_color", Color.BLACK)
		b.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
		var value: Variant = o[0]
		b.pressed.connect(func():
			if str(BWSettings.value(key)) != str(value):
				BWSettings.put(key, value)
			if key == "fullscreen" or key == "window":
				_sync()
			_explain())
		h.add_child(b)
		_seg[key][str(value)] = b


## Show the stored values (after open or a reset).
func _sync() -> void:
	for k in _sliders:
		(_sliders[k] as HSlider).set_value_no_signal(float(BWSettings.value(k)) * 100.0)
		(_sliders[k] as HSlider).value_changed.emit((_sliders[k] as HSlider).value)
	for k in _seg:
		var cur := str(BWSettings.value(k))
		for val in _seg[k]:
			(_seg[k][val] as Button).set_pressed_no_signal(val == cur)
	_explain()


func _explain() -> void:
	if _note == null:
		return
	match str(BWSettings.value("cutscenes")):
		"fast": _note.text = "Everything one step shorter: big moments get the short zoom, the rest plays in place."
		"minimal": _note.text = "Every action plays in place, no zoom. Crits keep a small flash."
		_: _note.text = "Basic attacks and setup skills play in place; quick skills zoom briefly; long-cooldown and once-per-battle skills, crits and knockouts get the full cutscene."

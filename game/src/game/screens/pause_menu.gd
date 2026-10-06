class_name BWPauseMenu
extends CanvasLayer
## D124: the pause menu for combat, the hall (prep, downtime) and the
## pre-battle screen. Pauses the tree while open. Esc opens it from a screen
## only when that screen has nothing left to back out of (combat: no
## forecast, aim or move to undo); Esc again resumes.
##     BWPauseMenu.open(self, "combat")
## Resume · Settings · Codex · Quit to title (the run is saved at the last
## screen change; a fight in progress restarts from pre-battle) · Quit game.

signal resumed

const LAYER := 94

var where := ""
var settings: BWSettingsPanel
var codex: BWCodex
var _buttons := {}
var _armed := false      # not the Esc that opened it


static func open(host: Node, p_where: String = "") -> BWPauseMenu:
	var m := BWPauseMenu.new()
	m.where = p_where
	host.add_child(m)
	return m


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_build()
	BWEsc.push(self, resume, { "name": "pause" })             # ---- D171
	await get_tree().process_frame
	_armed = true


func resume() -> void:
	if is_queued_for_deletion():
		return
	get_tree().paused = false
	resumed.emit()
	queue_free()


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if _sub_open() or not _armed:
			return
		match ev.keycode:
			KEY_ESCAPE: resume()                  # only without the D171 router (it closes the pause menu first)
			KEY_S: open_settings()
			KEY_I: open_codex()
		if ev.keycode != KEY_F11:
			get_viewport().set_input_as_handled()


func _sub_open() -> bool:
	return (settings and is_instance_valid(settings)) or (codex and is_instance_valid(codex))


func open_settings() -> void:
	if _sub_open():
		return
	settings = BWSettingsPanel.summon(self)


func open_codex() -> void:
	if _sub_open():
		return
	codex = BWCodex.summon(self, "glossary")
	codex.process_mode = Node.PROCESS_MODE_ALWAYS


func _game() -> BWGame:
	var n: Node = get_parent()
	while n:
		if n is BWGame:
			return n
		n = n.get_parent()
	return null


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = BWStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BWStyle.box_style())
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	v.add_child(title)
	var sub := Label.new()
	sub.text = { "combat": "Battle", "hall": "The hall", "prebattle": "Before the battle" }.get(where, "")
	sub.visible = sub.text != ""
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	v.add_child(sub)
	v.add_child(HSeparator.new())
	_button(v, "resume", "Resume  [Esc]", resume)
	_button(v, "settings", "Settings  [S]", open_settings)
	_button(v, "codex", "Codex & glossary  [I]", open_codex)
	v.add_child(HSeparator.new())
	var g := _game()
	var qt := _button(v, "title", "Quit to title", func():
		var game := _game()
		resume()
		if game:
			game.go_title())
	qt.disabled = g == null
	qt.tooltip_text = "The run is saved; a fight in progress starts again from pre-battle." if g else "Only in a run"
	_button(v, "quit", "Quit game", func(): get_tree().quit())


func _button(parent: Control, id: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(340, 46)
	b.add_theme_font_size_override("font_size", BWStyle.F_MENU)
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons[id] = b
	return b

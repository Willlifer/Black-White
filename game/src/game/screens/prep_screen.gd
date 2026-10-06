class_name BWPrepScreen
extends BWDowntimeScreen
## The hall before the first fight (D84, kit from D81; replaces the map-orbit intro there).
## Author: "replace it with the marble hall scene that allows you to move
## around equipment between units before continuing to the first map."
##
## The same hall and lineup as downtime (BWHall, a spotlight each, poses from
## personality), with no day actions: click a unit (or ←/→) and its light comes
## up, the camera moves in on it and the equipment panel opens beside it —
## BWGearPanel, the pre-battle's paperdoll / inventory / item card, with
## `give_enabled` so a picked item can go straight onto someone else
## ("Equip on …", "Give to …"). Under each spotlight, four squares show what
## that unit wears. Continue (the arrow, or Enter) goes on to fight 1's
## pre-battle; Info (I) opens the codex.

var _panel: BWGearPanel
var _cont: BWDowntimeWidgets.ProgressArrow
var _open := false
var _left := false


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = BWStyle.theme()
	ui.add_child(_ui_root)
	_ui_root.add_child(_top_scrim())
	_tag_layer = Control.new()
	_tag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_tag_layer)
	for i in _views.size():
		_tags.append(_make_tag(i))
	_plan_ui = Control.new()
	_plan_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plan_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_plan_ui)
	# header
	var top := VBoxContainer.new()
	top.position = Vector2(30, 18)
	top.add_theme_constant_override("separation", -2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan_ui.add_child(top)
	top.add_child(BWStyle.section_label("Before the first fight  ·  the hall"))
	var big := Label.new()
	big.text = "Share out the gear"
	big.add_theme_font_size_override("font_size", 40)
	big.add_theme_color_override("font_outline_color", Color.BLACK)
	big.add_theme_constant_override("outline_size", 10)
	top.add_child(big)
	var sub := Label.new()
	sub.text = "click a unit to open their gear   ·   %d loose piece%s in the inventory" % [run.inventory.size(), "" if run.inventory.size() == 1 else "s"]
	sub.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 6)
	top.add_child(sub)
	set_meta("sub", sub)
	var info := Button.new()
	info.text = "Info  [I]"
	info.focus_mode = Control.FOCUS_NONE
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -24 - 150
	info.offset_right = -24
	info.offset_top = 24
	info.offset_bottom = 24 + 46
	info.pressed.connect(open_codex)
	_plan_ui.add_child(info)
	# the equipment panel, right of the chosen unit
	_panel = BWGearPanel.new(run)
	_panel.give_enabled = true
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -24 - 1050
	_panel.offset_right = -24
	_panel.offset_top = 86
	_panel.offset_bottom = -24 - 150
	_panel.visible = false
	_panel.closed.connect(_close_panel)
	BWEsc.track(_panel, _close_panel, { "name": "gear" })          # ---- D171: the hall's gear panel
	_panel.changed.connect(_on_changed)
	_plan_ui.add_child(_panel)
	var step := HBoxContainer.new()
	step.add_theme_constant_override("separation", 4)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if d < 0 else "▶"
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Previous unit  [←]" if d < 0 else "Next unit  [→]"
		b.pressed.connect(func(): _select(_sel + d))
		step.add_child(b)
	_panel.add_header(step)
	# on to the first fight
	_cont = BWDowntimeWidgets.ProgressArrow.new()
	_cont.lines = ["CONTINUE", "TO FIGHT %d" % run.fight]
	_cont.sub_text = "%s  ·  Enter" % str(BWBoard.load_file("res://maps/%s.json" % run.map_for(run.fight)).name)
	_cont.set_count(_views.size(), _views.size())
	_cont.anchor_left = 1.0
	_cont.anchor_right = 1.0
	_cont.anchor_top = 1.0
	_cont.anchor_bottom = 1.0
	_cont.offset_left = -24 - 300
	_cont.offset_right = -24
	_cont.offset_top = -24 - 132
	_cont.offset_bottom = -24
	_cont.tooltip_text = "Continue to fight %d (Enter)" % run.fight
	_cont.pressed.connect(_continue)
	_plan_ui.add_child(_cont)
	var hint := Label.new()
	hint.text = "←/→ or click a unit   ·   pick an item, then Equip on / Give to   ·   Esc closes   ·   Enter continues"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 30
	hint.offset_top = -52
	hint.offset_bottom = -24
	hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	hint.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	_plan_ui.add_child(hint)
	set_meta("hint", hint)


func _make_tag(i: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_tag_layer.add_child(box)
	var nm := Label.new()
	nm.text = (run.squad[i] as BWUnit).name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	nm.add_theme_color_override("font_outline_color", Color.BLACK)
	nm.add_theme_constant_override("outline_size", 7)
	box.add_child(nm)
	var pips := BWDowntimeWidgets.GearPips.new()
	pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pips.set_unit(run.squad[i])
	box.add_child(pips)
	return { "box": box, "name": nm, "chips": [], "pips": pips }


func _refresh_tags() -> void:
	for i in _tags.size():
		var tag: Dictionary = _tags[i]
		var sel := i == _sel and _open
		(tag.name as Label).add_theme_color_override("font_color", Color.WHITE if sel or not _open else BWStyle.TEXT_DIM)
		(tag.name as Label).text = ("▸ " if sel else "") + (run.squad[i] as BWUnit).name
		(tag.pips as Control).queue_redraw()
		# with the panel open, only the chosen unit's tag shows (the rest are under the panel)
		tag.box.modulate.a = 1.0 if (not _open or i == _sel) else 0.0


func _refresh_go() -> void:
	pass


func _select(i: int) -> void:
	_focus(i)
	if not _started():
		_wide()
		return
	_open = true
	_panel.visible = true
	_panel.set_unit(run.squad[_sel])
	var at: Vector3 = _home[_sel].pos
	# the chosen unit in the left third, beside the panel, under its light
	_cam_pos = at + Vector3(3.0, 2.3, 8.4)
	_cam_look = at + Vector3(2.6, 0.62, 0)
	_place_continue(true)
	_refresh_tags()


func _started() -> bool:
	return _panel != null and is_inside_tree() and _cam != null and has_meta("started")


func _wide() -> void:
	_cam_pos = Vector3(0, 3.7, 16.4)
	_cam_look = Vector3(0, 1.15, 0)
	for k in _views.size():
		_hall.set_spot_level(_spot_ids[k], 1.0 if not _open else (1.0 if k == _sel else 0.42))
	_refresh_tags()


func _ready() -> void:
	super._ready()
	# every light up while nobody is chosen
	_open = false
	for k in _views.size():
		_hall.set_spot_level(_spot_ids[k], 1.0, true)
		_views[k].set_meta("dim", 0.0)
		BWLook.set_dim(_views[k], 0.0)
	_wide()
	_cam.position = _cam_pos
	_cam_look_now = _cam_look
	_cam.look_at(_cam_look_now)
	set_meta("started", true)


## The arrow sits bottom-right over the hall, and moves under the chosen
## unit (bottom-left) while the panel fills the right.
func _place_continue(open: bool) -> void:
	_cont.anchor_left = 0.0 if open else 1.0
	_cont.anchor_right = 0.0 if open else 1.0
	_cont.offset_left = 24.0 if open else -24.0 - 300.0
	_cont.offset_right = 324.0 if open else -24.0
	(get_meta("hint") as Control).visible = not open


func _close_panel() -> void:
	_open = false
	_panel.visible = false
	_place_continue(false)
	for k in _views.size():
		_hall.set_spot_level(_spot_ids[k], 1.0)
		var v: BWUnitView = _views[k]
		var from := float(v.get_meta("dim", 0.0))
		if from > 0.0:
			create_tween().tween_method(func(x: float): v.set_meta("dim", x); BWLook.set_dim(v, x), from, 0.0, 0.3)
	_wide()


func _on_changed() -> void:
	for v in _views:
		(v as BWUnitView).refresh_equipment()
	if has_meta("sub"):
		(get_meta("sub") as Label).text = "click a unit to open their gear   ·   %d loose piece%s in the inventory" % [run.inventory.size(), "" if run.inventory.size() == 1 else "s"]
	_refresh_tags()


func _continue() -> void:
	if _left:
		return
	_left = true
	done.emit()


func _unhandled_input(ev: InputEvent) -> void:
	if _left:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_LEFT: _select(_sel - 1)
			KEY_RIGHT: _select(_sel + 1)
			KEY_I: open_codex()
			KEY_ESCAPE:
				if _open:
					_close_panel()
				else:
					BWPauseMenu.open(self, "hall")          # ---- D124
			KEY_ENTER, KEY_KP_ENTER: _continue()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var best := _unit_at(ev.position)
		if best >= 0:
			_select(best)
		elif _open:
			_close_panel()


func _top_scrim() -> TextureRect:
	return BWDowntimeScreen.top_scrim()

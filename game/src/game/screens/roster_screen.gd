class_name BWRosterScreen
extends Node3D
## Brief: the roster sits on a semicircle facing the camera on the centre
## stage. Arrow keys or mouse-over highlights a character: face + name bottom
## right, stats/element/weapon bottom left. Pick 6.
## Picks fly into six portrait slots across the top (empty slots show a
## dimmed placeholder head); clicking a filled slot unpicks it (D75).
## Info (I) opens the codex (BWCodex) over the stage.
## D150: the 20 are rolled (BWRosterGen) when the screen opens; Randomize (R)
## re-rolls weapon, element and clothes with a new seed, clears the picks and
## re-dresses the seats with a quick spin. BWGame starts the run with `rows`
## and `roster_seed` (stored in the run, shown nowhere).

signal done(chosen_ids: Array)
signal rerolled                 ## a Randomize finished re-dressing the seats

const PICKS := 6
const PER_ROW := 10
const SLOT_W := 104             # portrait slot, design px

var _units: Array = []          # BWUnit
var _views: Array = []          # BWUnitView
var _sel := 0
var _chosen: Array = []         # indices
var _cam: Camera3D
var _stats: RichTextLabel
var _name: Label
var _count: Label
var _begin: Button
var _face_vp: SubViewport
var _face_view: BWUnitView
var _ui_root: Control
var _slots: Array = []          # PortraitSlot, left to right
var _codex: BWCodex
var rows: Array = []            ## D150: the current roll (BWRosterGen.roll)
var roster_seed := -1
var _shuffling := false
var _roll_gen := 0              ## bumps on every roll; stale portrait renders are dropped


func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	add_child(we)
	_build_stage()
	roster_seed = BWRosterGen.first_seed()
	rows = BWRosterGen.roll(BWData.identities(), roster_seed, BWData.pool_identities())   # D379: the pool rotates into the back row
	for row in rows:
		_units.append(BWUnit.from_roster(row))
	for i in _units.size():
		_views.append(_make_view(i))
	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.position = Vector3(0, 4.2, 11.5)
	add_child(_cam)
	_cam.look_at(Vector3(0, 1.2, -1.5))
	_cam.make_current()
	_build_ui()
	_select(0)


func _make_view(i: int) -> BWUnitView:
	var v := BWUnitView.new()
	add_child(v)
	v.setup(_units[i])
	v.showcase = true          # animation lane (D80): more weapon handling on the roster stage
	v.show_label(false)
	v.position = _seat(i)
	v.face(Vector3(0, v.position.y, 9.0))
	return v


## D150: a new roll. The picks clear; each seat spins out and its newly
## dressed character spins back in, left to right (~0.8 s in all).
func randomize_roster() -> void:
	if _shuffling:
		return
	_shuffling = true
	_roll_gen += 1
	for i in _chosen.duplicate():
		var pv: BWUnitView = _views[i]
		pv.position = _seat(i)
	_chosen.clear()
	roster_seed = BWRosterGen.next_seed(roster_seed)
	rows = BWRosterGen.roll(BWData.identities(), roster_seed, BWData.pool_identities())   # D379: the pool rotates into the back row
	_units.clear()
	for row in rows:
		_units.append(BWUnit.from_roster(row))
	_refresh_count()
	var last: Tween
	for i in _views.size():
		var old: BWUnitView = _views[i]
		var tw := create_tween()
		tw.tween_interval(0.022 * i)
		tw.tween_property(old, "scale", Vector3.ONE * 0.05, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(old, "rotation:y", old.rotation.y + PI, 0.14)
		tw.tween_callback(func():
			old.queue_free()
			var v := _make_view(i)
			_views[i] = v
			var face_y := v.rotation.y
			v.rotation.y = face_y - PI
			v.scale = Vector3.ONE * 0.05
			var t2 := create_tween().set_parallel(true)
			t2.tween_property(v, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t2.tween_property(v, "rotation:y", face_y, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
		last = tw
	if last:
		await last.finished
	await get_tree().create_timer(0.24).timeout
	_shuffling = false
	_select(_sel)
	rerolled.emit()


## Two tiers of ten on a 150° arc; the back tier is raised like stadium seating.
func _seat(i: int) -> Vector3:
	var row := i / PER_ROW
	var k := i % PER_ROW
	var radius := 6.0 + row * 2.0
	var a := deg_to_rad(lerpf(-75.0, 75.0, float(k) / (PER_ROW - 1)))
	return Vector3(sin(a) * radius, row * 0.9 + 0.35, -cos(a) * radius + 2.0)


func _build_stage() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# centre stage disc and the two seating tiers, as flat white bands with ink edges
	_band(st, 0.0, 4.6, 0.0, BWLook.WHITE)
	_band(st, 4.6, 4.75, 0.005, BWLook.INK)
	_band(st, 5.2, 6.9, 0.35, BWLook.PAPER)
	_band(st, 6.9, 7.0, 0.355, BWLook.INK)
	_band(st, 7.2, 8.9, 1.25, BWLook.GREY_LIGHT)
	_band(st, 8.9, 9.0, 1.255, BWLook.INK)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	mi.position.z = 2.0
	add_child(mi)


func _band(st: SurfaceTool, r0: float, r1: float, y: float, col: Color) -> void:
	var n := 48
	for i in n:
		var a0 := deg_to_rad(lerpf(-100.0, 100.0, float(i) / n))
		var a1 := deg_to_rad(lerpf(-100.0, 100.0, float(i + 1) / n))
		var p := [Vector3(sin(a0) * r0, y, -cos(a0) * r0), Vector3(sin(a1) * r0, y, -cos(a1) * r0),
			Vector3(sin(a1) * r1, y, -cos(a1) * r1), Vector3(sin(a0) * r1, y, -cos(a0) * r1)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(p[idx])


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWCombatUI.theme_bw()
	ui.add_child(root)

	_ui_root = root
	var head := Label.new()
	head.text = "Select your Six Contestants"
	head.anchor_right = 1.0
	head.offset_top = 14
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_theme_constant_override("outline_size", 10)
	root.add_child(head)
	var strip := HBoxContainer.new()
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.offset_left = -(SLOT_W * PICKS + 10 * (PICKS - 1)) / 2.0
	strip.offset_right = -strip.offset_left
	strip.offset_top = 64
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 10)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	for k in PICKS:
		var slot := PortraitSlot.new()
		slot.clicked.connect(_on_slot_clicked.bind(k))
		slot.hovered.connect(_on_slot_hovered.bind(k))
		strip.add_child(slot)
		_slots.append(slot)
	_count = Label.new()
	_count.anchor_left = 0.5
	_count.anchor_right = 0.5
	_count.offset_left = -strip.offset_left + 20
	_count.offset_right = _count.offset_left + 120
	_count.offset_top = 64 + SLOT_W / 2.0 - 16
	_count.add_theme_font_size_override("font_size", BWStyle.F_SUB + 3)
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.add_theme_constant_override("outline_size", 8)
	root.add_child(_count)
	var help := Label.new()
	help.text = "Arrows / mouse to look  ·  Enter / click to pick  ·  click a portrait to unpick  ·  R to randomize  ·  I for info  ·  Space to begin"
	help.anchor_right = 1.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -112
	help.offset_bottom = -88
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	help.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	root.add_child(help)

	var left := PanelContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 24
	left.offset_right = 420
	left.offset_top = -250
	left.offset_bottom = -24
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN     # the full stat spread always fits
	root.add_child(left)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.custom_minimum_size = Vector2(370, 200)
	left.add_child(_stats)

	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -300
	right.offset_right = -24
	right.offset_top = -330
	right.offset_bottom = -24
	root.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(252, 230)
	svc.stretch = true
	rv.add_child(svc)
	_face_vp = SubViewport.new()
	_face_vp.own_world_3d = true
	_face_vp.transparent_bg = false
	svc.add_child(_face_vp)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 28)
	rv.add_child(_name)

	_begin = Button.new()
	_begin.text = "Begin  [Space]"
	_begin.anchor_left = 0.5
	_begin.anchor_right = 0.5
	_begin.anchor_top = 1.0
	_begin.anchor_bottom = 1.0
	_begin.offset_left = -90
	_begin.offset_right = 90
	_begin.offset_top = -80
	_begin.offset_bottom = -30
	_begin.focus_mode = Control.FOCUS_NONE
	_begin.pressed.connect(_try_begin)
	root.add_child(_begin)
	var info := Button.new()
	info.text = "Info  [I]"
	info.anchor_left = 0.5
	info.anchor_right = 0.5
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.offset_left = -246
	info.offset_right = -102
	info.offset_top = -80
	info.offset_bottom = -30
	info.focus_mode = Control.FOCUS_NONE
	info.pressed.connect(open_codex)
	root.add_child(info)
	var reroll := Button.new()                   # D150
	reroll.text = "Randomize  [R]"
	reroll.anchor_left = 0.5
	reroll.anchor_right = 0.5
	reroll.anchor_top = 1.0
	reroll.anchor_bottom = 1.0
	reroll.offset_left = 102
	reroll.offset_right = 282
	reroll.offset_top = -80
	reroll.offset_bottom = -30
	reroll.focus_mode = Control.FOCUS_NONE
	reroll.tooltip_text = "Re-roll everyone's weapon, element and clothes (clears your picks)"
	reroll.pressed.connect(randomize_roster)
	root.add_child(reroll)
	_refresh_count()


func _set_face(u: BWUnit) -> void:
	if _face_view:
		_face_view.queue_free()
	for c in _face_vp.get_children():
		c.queue_free()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.93, 0.93)
	env.environment = e
	_face_vp.add_child(env)
	_face_view = BWUnitView.new()
	_face_vp.add_child(_face_view)
	_face_view.setup(u)
	_face_view.show_label(false)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_face_vp.add_child(cam)
	# frame the head (rig head centre 1.92; the primitive's ~1.5)
	var hy := _face_view.head_height()
	cam.position = Vector3(0.0, hy + 0.18, 3.2)
	cam.look_at(Vector3(0, hy + 0.02, 0))
	cam.make_current()


func _select(i: int) -> void:
	_sel = clampi(i, 0, _units.size() - 1)
	var u: BWUnit = _units[_sel]
	for k in _views.size():
		var v: BWUnitView = _views[k]
		var target := 1.25 if k == _sel else 1.0
		create_tween().tween_property(v, "scale", Vector3.ONE * target, 0.12)
	_name.text = u.name
	_set_face(u)
	BWPortraits.portrait(u)         # D156: render on hover, so a pick's slot is ready when it lands
	var el := BWLook.element_color(u.element).to_html(false)
	# "Flamberge (Sword)", but just "Axe" when the model is the class itself (D218: BWText).
	var wname := BWText.model_name(u.weapon_model, u.weapon_class)
	var wtext := BWText.weapon(u.weapon_class) if wname == "" else "%s (%s)" % [wname, BWText.weapon(u.weapon_class)]
	_stats.text = "[font_size=24][b]%s[/b][/font_size]   [color=#999999]%s[/color]\n" % [u.name, BWText.label(u.friendliness)] \
		+ "[color=#%s]■[/color] %s      %s\n" % [el, u.element.capitalize(), wtext] \
		+ "\n" + _bars(u)


func _bars(u: BWUnit) -> String:
	var lines: PackedStringArray = []
	for s in BWUnit.STATS:
		var v := u.stat(s)
		lines.append("%s  %s%s  %d" % [s.to_upper(), "█".repeat(v), "[color=#444444]%s[/color]" % "█".repeat(6 - v), v])
	return "\n".join(lines)


func _toggle(i: int) -> void:
	if _shuffling:
		return
	var v: BWUnitView = _views[i]
	if i in _chosen:
		_chosen.erase(i)
		v.idle()
		create_tween().tween_property(v, "position", _seat(i), 0.2)
	elif _chosen.size() < PICKS:
		_chosen.append(i)
		v.pose_named("cheer")
		create_tween().tween_property(v, "position", _seat(i) + Vector3(0, 0.25, 0), 0.2).set_trans(Tween.TRANS_BACK)
		_fly_in(i, _chosen.size() - 1)
	_refresh_count()


func _refresh_count() -> void:
	if _count:
		_count.text = "%d / %d" % [_chosen.size(), PICKS]
		_count.add_theme_color_override("font_color", Color.WHITE if _chosen.size() == PICKS else BWStyle.TEXT_DIM)
		_begin.disabled = _chosen.size() != PICKS
	_refresh_slots()


func _refresh_slots() -> void:
	for k in _slots.size():
		var slot: PortraitSlot = _slots[k]
		if k < _chosen.size():
			var i: int = _chosen[k]
			var u: BWUnit = _units[i]
			slot.fill(u)
		else:
			slot.clear()


func _on_slot_clicked(k: int) -> void:
	if k < _chosen.size():
		var i: int = _chosen[k]
		_select(i)
		_toggle(i)


func _on_slot_hovered(k: int) -> void:
	if k < _chosen.size() and _chosen[k] != _sel:
		_select(_chosen[k])


## The pick flies from the character's head on the stage into its slot.
func _fly_in(i: int, k: int) -> void:
	if k >= _slots.size() or _cam == null or _ui_root == null:
		return
	var slot: PortraitSlot = _slots[k]
	slot.arriving = true
	var head: Vector3 = _views[i].global_position + Vector3(0, 1.6, 0)
	var half := Vector2(SLOT_W, SLOT_W) * 0.5
	var fly := BWWidgets.Portrait.new(_units[i], SLOT_W, false)
	fly.size = Vector2(SLOT_W, SLOT_W)
	fly.pivot_offset = half
	fly.position = _cam.unproject_position(head) - half
	fly.scale = Vector2.ONE * 0.45
	_ui_root.add_child(fly)
	var to := slot.frame_global_position() - _ui_root.global_position
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fly, "position", to, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(fly, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		fly.queue_free()
		if is_instance_valid(slot):
			slot.arriving = false
			_refresh_slots()
			slot.pop())


# ---------------------------------------------------------------- codex

## The rules reference over the stage. Other screens open it the same way:
## BWCodex.summon(self, "elements" | "weapons" | "stats" | "terrain").
func open_codex(tab: String = "elements") -> void:
	if is_instance_valid(_codex):
		return
	_codex = BWCodex.summon(self, tab)


func _try_begin() -> void:
	if _chosen.size() == PICKS and not _shuffling:
		set_process_unhandled_input(false)
		done.emit(_chosen.map(func(i): return _units[i].id))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var best := -1
		var best_d := 70.0
		for i in _views.size():
			var head: Vector3 = _views[i].global_position + Vector3(0, 1.5, 0)
			if _cam.is_position_behind(head):
				continue
			var d := _cam.unproject_position(head).distance_to(ev.position)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0 and best != _sel:
			_select(best)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var head: Vector3 = _views[_sel].global_position + Vector3(0, 1.5, 0)
		if _cam.unproject_position(head).distance_to(ev.position) < 70.0:
			_toggle(_sel)
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_LEFT: _select(_sel - 1)
			KEY_RIGHT: _select(_sel + 1)
			KEY_UP: _select(_sel + PER_ROW if _sel < PER_ROW else _sel)
			KEY_DOWN: _select(_sel - PER_ROW if _sel >= PER_ROW else _sel)
			KEY_ENTER, KEY_KP_ENTER: _toggle(_sel)
			KEY_SPACE: _try_begin()
			KEY_I: open_codex()
			KEY_R: randomize_roster()


## One of the six slots across the top. Empty: an outlined, dimmed
## placeholder head. Filled: the character's portrait (BWWidgets.Portrait,
## D156: BWPortraits, the placeholder until the render lands), with the name.
class PortraitSlot:
	extends VBoxContainer
	signal clicked
	signal hovered
	var arriving := false
	var _frame: Control
	var _icon: BWWidgets.Portrait
	var _name: Label
	var _element := ""
	var _filled := false

	func _init() -> void:
		add_theme_constant_override("separation", 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame = Control.new()
		_frame.custom_minimum_size = Vector2(SLOT_W, SLOT_W)
		_frame.mouse_filter = Control.MOUSE_FILTER_STOP
		_frame.draw.connect(_draw_frame)
		_frame.gui_input.connect(_on_input)
		_frame.mouse_entered.connect(_on_enter)
		_frame.mouse_exited.connect(_frame.queue_redraw)
		add_child(_frame)
		_icon = BWWidgets.Portrait.new(null, SLOT_W, false)
		_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_icon.visible = false
		_frame.add_child(_icon)
		_name = Label.new()
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.custom_minimum_size = Vector2(SLOT_W, 0)
		_name.clip_text = true
		_name.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		_name.add_theme_color_override("font_outline_color", Color.BLACK)
		_name.add_theme_constant_override("outline_size", 6)
		add_child(_name)
		clear()

	func frame_global_position() -> Vector2:
		return _frame.global_position

	func fill(u: BWUnit) -> void:
		var n := u.name
		_filled = not arriving
		_element = u.element
		_name.text = n if not arriving else ""
		_name.add_theme_font_size_override("font_size", BWStyle.F_SMALL if n.length() <= 9 else BWStyle.F_SMALL - 3)
		_name.add_theme_color_override("font_color", BWStyle.TEXT)
		_frame.tooltip_text = "%s: click to unpick" % n
		_frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_icon.set_unit(u, false)
		_icon.visible = not arriving
		_frame.queue_redraw()

	func clear() -> void:
		_filled = false
		_element = ""
		_name.text = "—"
		_name.add_theme_color_override("font_color", BWStyle.FAINT)
		_frame.tooltip_text = ""
		_frame.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_icon.set_unit(null)
		_icon.visible = false
		_frame.queue_redraw()

	func is_filled() -> bool:
		return _filled

	func pop() -> void:
		_frame.pivot_offset = _frame.size * 0.5
		_frame.scale = Vector2.ONE * 1.12
		_frame.create_tween().tween_property(_frame, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)

	func _on_enter() -> void:
		if _filled:
			hovered.emit()
		_frame.queue_redraw()

	func _on_input(ev: InputEvent) -> void:
		if _filled and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_frame.accept_event()
			clicked.emit()

	func _draw_frame() -> void:
		var s := _frame.size
		if not _filled:
			# The empty seat: a dark plate, an outlined dim head and shoulders.
			_frame.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.03, 0.035, 0.8))
			_frame.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.3), false, 1.5)
			var dim := Color(1, 1, 1, 0.24)
			_frame.draw_arc(Vector2(s.x * 0.5, s.y * 0.42), s.x * 0.19, 0, TAU, 40, dim, 2.0, true)
			_frame.draw_arc(Vector2(s.x * 0.5, s.y * 1.06), s.x * 0.36, PI * 1.1, PI * 1.9, 32, dim, 2.0, true)
			return
		var hover := _frame.get_global_rect().has_point(_frame.get_global_mouse_position())
		_frame.draw_rect(Rect2(Vector2.ZERO, s), Color(0.93, 0.93, 0.93))
		_frame.draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), BWLook.element_color(_element), false, 4.0)
		_frame.draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK, false, 1.0)
		if hover:
			_frame.draw_rect(Rect2(Vector2(-4, -4), s + Vector2(8, 8)), Color.WHITE, false, 2.0)

class_name BWLoadingScreen
extends Control
## The run's opening (replaces the "Six of you…" card, D75): a slow orbit
## over each of the five maps, crossfading from one to the next, with the map
## name small in the corner. It ends on the next fight's map with "Ready to
## fight"; any key continues. A key during the montage skips to the end.
## Doubles as the loading screen: the next fight's board is built first and
## kept, so its meshes and shaders are warm before pre-battle.

signal done

const HOLD := 2.6             # seconds on each map
const FADE := 1.1             # crossfade between maps
const MIN_READY := 0.6        # "Ready" ignores keys this long (no accidental skip)
const ORBIT := 0.16           # rad/s

var maps: Array = BWRun.MAPS.duplicate()
var next_map := "arena"       # shown last; the "Ready to fight" backdrop

var _order: Array = []
var _slots: Array = []        # [{ vp, rect, rig, name }]
var _cur := 0                 # which slot is in front
var _idx := -1
var _name: Label
var _ready_lbl: Label
var _prompt: Label
var _is_ready := false
var _ready_t := 0.0
var _sent := false
var _t := 0.0
var _seq: Tween
var _scrim: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	theme = BWStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_order = maps.filter(func(m): return m != next_map)
	_order.append(next_map)
	for i in 2:
		_slots.append(_make_slot())
	_build_text()
	# Warm the fight's map first (the loading half of the job), then start.
	_load_into(_slots[1], next_map)
	_slots[1].vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_advance()


func _make_slot() -> Dictionary:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.modulate.a = 0.0
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	vp.add_child(we)
	var rig := Node3D.new()
	vp.add_child(rig)
	var arm := Node3D.new()
	arm.name = "arm"
	rig.add_child(arm)
	var cam := Camera3D.new()
	cam.fov = 40.0
	arm.add_child(cam)
	cam.current = true
	return { "svc": svc, "vp": vp, "rig": rig, "arm": arm, "cam": cam, "map": "", "board": null }


## Build a map into a slot (reusing it if it already holds that map).
func _load_into(slot: Dictionary, map_id: String) -> void:
	if slot.map == map_id:
		return
	if slot.board:
		slot.board.queue_free()
	var board := BWBoard.load_file("res://maps/%s.json" % map_id)
	var bv := BWBoardView.new()
	slot.vp.add_child(bv)
	bv.build(board, BWTileFX.authored(board, "res://maps/%s.json" % map_id))   # tile FX (D82)
	slot.board = bv
	slot.map = map_id
	slot.title = board.name
	# Frame the whole board: distance from its extent.
	# Orbit the board's true middle (the mean of its tiles), far enough back
	# that its widest extent stays in frame all the way round.
	var mid := Vector3.ZERO
	var cells: Array = board.cells()
	for h in cells:
		mid += BWLook.world(h, board.elevation(h))
	mid /= maxf(1.0, cells.size())
	var radius := 0.0
	for h in cells:
		var p := BWLook.world(h)
		radius = maxf(radius, Vector2(p.x - mid.x, p.z - mid.z).length())
	slot.rig.position = mid
	slot.arm.rotation_degrees.x = -36.0
	slot.cam.position = Vector3(0, 0, clampf(radius * 3.0, 18.0, 52.0))
	slot.rig.rotation.y = randf() * TAU


func _build_text() -> void:
	# Dims the board under "Ready to fight" so the words read on white tiles.
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.5)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.modulate.a = 0.0
	add_child(_scrim)
	_name = Label.new()
	_name.anchor_top = 1.0
	_name.anchor_bottom = 1.0
	_name.offset_left = 48
	_name.offset_top = -86
	_name.offset_bottom = -48
	_name.offset_right = 600
	_name.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 8)
	_name.modulate.a = 0.0
	add_child(_name)
	_ready_lbl = Label.new()
	_ready_lbl.text = "Ready to fight"
	_ready_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ready_lbl.offset_bottom = -40
	_ready_lbl.add_theme_font_size_override("font_size", 76)
	_ready_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_ready_lbl.add_theme_constant_override("outline_size", 24)
	_ready_lbl.modulate.a = 0.0
	add_child(_ready_lbl)
	_prompt = Label.new()
	_prompt.text = "press any key"
	_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.offset_top = 110
	_prompt.add_theme_font_size_override("font_size", BWStyle.F_SMALL + 1)
	_prompt.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.modulate.a = 0.0
	add_child(_prompt)


## Next map: build it into the back slot, crossfade it to the front.
func _advance() -> void:
	_idx += 1
	if _idx >= _order.size():
		_show_ready()
		return
	var back: Dictionary = _slots[1 - _cur]
	var front: Dictionary = _slots[_cur]
	_load_into(back, _order[_idx])
	back.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	move_child(back.svc, front.svc.get_index() + 1)     # draw over the old one
	back.svc.modulate.a = 0.0
	_seq = create_tween()
	_seq.set_parallel(true)
	_seq.tween_property(back.svc, "modulate:a", 1.0, FADE if _idx > 0 else 0.8).set_trans(Tween.TRANS_SINE)
	_seq.tween_property(_name, "modulate:a", 0.0, FADE * 0.4)
	_seq.chain().tween_callback(func():
		front.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		front.svc.modulate.a = 0.0
		_name.text = str(back.title).to_upper()
		_cur = 1 - _cur)
	_seq.chain().tween_property(_name, "modulate:a", 1.0, 0.5)
	_seq.chain().tween_interval(HOLD if _idx < _order.size() - 1 else 0.6)
	_seq.chain().tween_callback(_advance)


func _show_ready() -> void:
	if _is_ready:
		return
	_is_ready = true
	if _seq and _seq.is_valid():
		_seq.kill()
	# Land on the fight's map, whichever slot it is in.
	var tgt: Dictionary = _slots[_cur]
	if tgt.map != next_map:
		var other: Dictionary = _slots[1 - _cur]
		_load_into(other, next_map)
		other.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		move_child(other.svc, tgt.svc.get_index() + 1)
		var tw0 := create_tween()
		tw0.tween_property(other.svc, "modulate:a", 1.0, 0.5)
		tw0.tween_callback(func(): tgt.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED)
		_cur = 1 - _cur
		_name.text = str(other.title).to_upper()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_ready_lbl, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_scrim, "modulate:a", 1.0, 0.7)
	tw.tween_property(_name, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	_t += delta
	for s in _slots:
		if s.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			s.rig.rotation.y += delta * ORBIT
	if _is_ready:
		_ready_t += delta
		if _ready_t >= MIN_READY:
			_prompt.modulate.a = 0.45 + 0.3 * sin(_t * 2.4)


func is_ready_to_fight() -> bool:
	return _is_ready


func _unhandled_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventKey and ev.pressed and not ev.echo) \
		or (ev is InputEventMouseButton and ev.pressed) \
		or (ev is InputEventJoypadButton and ev.pressed)
	if not pressed:
		return
	if not _is_ready:
		_show_ready()
	elif _ready_t >= MIN_READY and not _sent:
		_sent = true
		done.emit()


## These screens are Controls under a plain Node (BWGame), so anchors have
## no parent rect to follow: size to the viewport ourselves, and keep it.
func _fit() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

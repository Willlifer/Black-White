class_name BWPicksScreen
extends Control
## Run start (D90): right after the roster, before the hall. Each of the six
## owes the first perk of their own element (affinity rank 1); one picker per
## unit, in squad order. The squad strip along the top shows who has chosen.
## Also used after loading a save that owes picks. Emits `done` when nothing
## is owed. `current` is the open BWPicker (the flow probe answers it).

signal done

var run: BWRun
var title_text := "Before the hall"
var current: BWPicker
var _strip: HBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BWStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 26
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)
	var t := Label.new()
	t.text = title_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	top.add_child(t)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	_status.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	top.add_child(_status)
	var cc := CenterContainer.new()
	top.add_child(cc)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 12)
	cc.add_child(_strip)
	_run_picks.call_deferred()


func _refresh_strip(active: BWUnit) -> void:
	for c in _strip.get_children():
		c.queue_free()
	for u in run.squad:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var ic := BWWidgets.Portrait.new(u, 48.0, false)
		ic.selected = u == active
		ic.modulate.a = 1.0 if u == active or BWPicks.pending(u).is_empty() else 0.45
		col.add_child(ic)
		var l := Label.new()
		var done_mark := BWPicks.pending(u).is_empty()
		l.text = ("✓ " if done_mark else "") + u.name
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 3)
		l.add_theme_color_override("font_color", BWStyle.TEXT if u == active else BWStyle.FAINT)
		l.custom_minimum_size = Vector2(70, 0)
		col.add_child(l)
		_strip.add_child(col)


func _run_picks() -> void:
	while true:
		var pend := run.pending_picks()
		if pend.is_empty():
			break
		var u: BWUnit = pend[0][0]
		var req: Dictionary = pend[0][1]
		var left := pend.size()
		_status.text = "Each of your squad takes their first %s. %d to go." % ["perk" if req.kind == "perk" else "pick", left]
		_refresh_strip(u)
		current = BWPicker.new(u, req)
		current.offset_top = 236          # below the strip
		add_child(current)
		var id: String = await current.chosen
		BWPicks.apply(u, req, id)
		current.queue_free()
		current = null
		await get_tree().process_frame
	_refresh_strip(null)
	_status.text = "Done."
	await get_tree().create_timer(0.3).timeout
	done.emit()

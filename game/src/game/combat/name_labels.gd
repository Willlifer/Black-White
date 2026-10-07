class_name BWNameLabels
extends Node
## D344 name labels in a crowd (polish pass 3). With 12 units on Commons the
## names over the HP bars printed on top of each other and on the bars. Now,
## each frame (after the bars' clamp):
##   * FOCUS (full size): the acting unit, the hovered unit and every unit
##     the aimed action's preview touches (BWBlastPreview.last.units);
##   * everyone else: the name at REDUCED size, only if it overlaps no HP bar
##     and no name already placed (focus names first, then front to back);
##     otherwise hidden. A 3v3 rarely overlaps, so it keeps most names;
##   * the HP bars are untouched (always shown, D215).
## The bar's own visibility (show_label(false), the HUD cull) still wins.

const REDUCED := 0.8               # the unfocused name's size (of the focus size)
const PAD := 2.0                   # screen px around each rect

var screen: BWCombatScreen
var shown := {}                    # unit id -> "focus" | "small" | "hidden" (probes, review)


func setup(s: BWCombatScreen) -> void:
	screen = s
	process_priority = 100         # after the bars' _process (their clamp moves the labels)


func focus_ids() -> Dictionary:
	var out := {}
	if screen == null or screen.battle == null:
		return out
	var cur := screen.battle.current()
	if cur != null:
		out[cur.id] = true
	if BWHPBar3D.hover_unit != null:
		out[BWHPBar3D.hover_unit.id] = true
	var pv: BWBlastPreview = screen.readability.preview if screen.readability else null
	if pv != null and pv.shown():
		for id in (pv.last.get("units", {}) as Dictionary):
			out[str(id)] = true
	return out


static func _rect(cam: Camera3D, l: Label3D, pixel: float) -> Rect2:
	if l.text == "" or cam.is_position_behind(l.global_position):
		return Rect2()
	var k := BWBlastPreview.px_scale(cam, pixel)
	var sz := Vector2(ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x + l.outline_size,
		l.font_size * 1.2) * k
	var c := cam.unproject_position(l.global_position) + Vector2(l.offset.x, -l.offset.y) * k
	return Rect2(c - sz * 0.5, sz).grow(PAD)


## Seat the name just above its own bar in SCREEN pixels: the bar's world
## rise (LABEL_RISE) shrinks to a few pixels on the zoomed-out 6v6 camera and
## the name sank behind its own bar.
static func _seat(cam: Camera3D, l: Label3D, bar: Rect2) -> void:
	l.offset = Vector2.ZERO
	if cam.is_position_behind(l.global_position) or not bar.has_area():
		return
	var k := BWBlastPreview.px_scale(cam, l.pixel_size)
	if k <= 0.0:
		return
	var anchor := cam.unproject_position(l.global_position).y
	var want := bar.position.y + PAD - 1.0 - l.font_size * 0.62 * k
	l.offset.y = maxf(0.0, (anchor - want) / k)


func _process(_d: float) -> void:
	if screen == null or screen.battle == null:
		return
	var cam: Camera3D = screen.cam
	if cam == null:
		return
	var focus := focus_ids()
	var items: Array = []
	var bars: Array = []
	for id in screen._views:
		var v = screen._views[id]
		if not (v is BWUnitView) or not is_instance_valid(v):
			continue
		var uv := v as BWUnitView
		if uv._label == null or uv._hp_bar == null:
			continue
		if not uv.is_visible_in_tree() or not uv._hp_bar.shown or not uv.unit.alive():
			continue
		var l := uv._label
		if not l.has_meta("full_pixel"):
			l.set_meta("full_pixel", l.pixel_size)
		var br := uv._hp_bar.screen_rect(cam).grow(PAD)
		bars.append(br)
		for t in uv._hp_bar.get_children():        # the bar's marks (ROT, DOOM, FROZEN: BWKeystoneView.bar_mark)
			if t is Label3D and t != l and t != uv._hp_label and (t as Label3D).visible:
				var tr := BWBlastPreview.label_rect(cam, t)
				if tr.has_area():
					bars.append(tr)
		items.append({ "id": str(id), "l": l, "focus": focus.has(str(id)), "bar": br,
			"y": cam.unproject_position(uv._hp_bar.quad.global_position).y })
	# focus first, then front (lower on screen) to back
	items.sort_custom(func(a, b):
		if a.focus != b.focus:
			return a.focus
		return a.y > b.y)
	var placed: Array = []
	shown = {}
	for it in items:
		var l: Label3D = it.l
		var full := float(l.get_meta("full_pixel"))
		if it.focus:
			l.pixel_size = full
			_seat(cam, l, it.bar)
			l.visible = true
			l.render_priority = 18             # over the bars and their marks
			l.outline_render_priority = 17
			placed.append(_rect(cam, l, full))
			shown[it.id] = "focus"
			continue
		var px := full * REDUCED
		l.pixel_size = px
		_seat(cam, l, it.bar)
		l.render_priority = 13             # over the figures (never over a bar: it skips those)
		l.outline_render_priority = 12
		var r := _rect(cam, l, px)
		var free := r.has_area()
		if free:
			for q in placed + bars:
				if (q as Rect2).has_area() and q != it.bar and r.intersects(q):
					free = false
					break
		l.pixel_size = px
		l.visible = free
		if free:
			placed.append(r)
		shown[it.id] = "small" if free else "hidden"

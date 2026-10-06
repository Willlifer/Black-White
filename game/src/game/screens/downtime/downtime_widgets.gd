class_name BWDowntimeWidgets
## Drawn pieces of the downtime screen (D83, D127), in BWStyle's language: the
## three choices' glyphs, the big choice tile, the chosen chip under a
## spotlight, the Progress Day arrow, and the dawn-to-dusk track.

## Choice -> [tile title, chip word]. Names only: the author wants no hint
## of what a choice does (no effect text, no tooltip).
static func info(choice: String) -> Array:
	var n := str(BWRun.CHOICE_NAMES.get(choice, choice))
	return [n, n]


## The choice's glyph, drawn into `r` in `col` (ink on white chips, white on
## the dark tiles). Specialize: a target. Branch out: a fork. Wander: a
## winding path of footsteps.
static func draw_icon(ci: CanvasItem, choice: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var w := maxf(1.6, s * 0.15)
	match choice:
		"specialize":
			ci.draw_arc(c, s * 0.9, 0, TAU, 40, col, w)
			ci.draw_arc(c, s * 0.55, 0, TAU, 32, col, w)
			ci.draw_circle(c, s * 0.2, col)
		"branch_out":
			var root := c + Vector2(0, s * 0.9)
			var fork := c + Vector2(0, s * 0.05)
			ci.draw_line(root, fork, col, w * 1.3)
			for tip in [c + Vector2(-s * 0.75, -s * 0.8), c + Vector2(0, -s * 0.95), c + Vector2(s * 0.75, -s * 0.8)]:
				ci.draw_line(fork, tip, col, w * 1.1)
				ci.draw_circle(tip, w * 1.1, col)
		"wander":
			var pts := PackedVector2Array()
			for i in 25:
				var t := float(i) / 24.0
				pts.append(c + Vector2(sin(t * TAU * 1.1) * s * 0.55, s * 0.9 - t * s * 1.8))
			for i in range(0, pts.size() - 1, 3):
				ci.draw_line(pts[i], pts[i + 1], col, w)
			ci.draw_circle(pts[pts.size() - 1], w * 1.4, col)
		_:
			ci.draw_circle(c, s * 0.5, col)


## A choice as a big tile: the glyph, the name, the hotkey. Nothing else.
class ChoiceTile:
	extends Button
	var choice := ""
	var key := ""
	var chosen := false

	func _init(p_choice: String, p_key: String) -> void:
		choice = p_choice
		key = p_key
		custom_minimum_size = Vector2(220, 128)
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hover := is_hovered() and not disabled
		var lit := hover or chosen
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.97, 0.97) if chosen else (Color(0.16, 0.16, 0.18, 0.96) if hover else Color(0.07, 0.07, 0.08, 0.94))
		sb.set_corner_radius_all(8)
		sb.border_color = Color.WHITE if lit else Color(1, 1, 1, 0.55)
		sb.set_border_width_all(3 if lit else 1)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var ink := Color.BLACK if chosen else Color.WHITE
		var g := minf(size.y * 0.42, 58.0)
		BWDowntimeWidgets.draw_icon(self, choice, Rect2(Vector2((size.x - g) * 0.5, 16), Vector2(g, g)), ink)
		var f := get_theme_font("font", "Label")
		var fs := BWStyle.F_BODY + 2
		draw_string(f, Vector2(0, size.y - 22), str(BWDowntimeWidgets.info(choice)[0]), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, ink)
		draw_string(f, Vector2(size.x - 20, 22), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(ink.r, ink.g, ink.b, 0.4))


## A locked-in action under a unit's spotlight: a white chip with the glyph
## and a word (the element's name in its colour), or an empty dashed slot.
class Chip:
	extends Control
	var action := ""
	var word := ""
	var accent := Color.TRANSPARENT
	var active := false          # the day scene: this one is happening now

	func _init() -> void:
		custom_minimum_size = Vector2(122, 28)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_action(a: String, w: String, col: Color = Color.TRANSPARENT) -> void:
		action = a
		word = w
		accent = col
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var f := get_theme_font("font", "Label")
		if action == "":
			# an open slot: a faint plate and a plus
			var e := StyleBoxFlat.new()
			e.bg_color = Color(0, 0, 0, 0.35)
			e.set_corner_radius_all(5)
			e.border_color = Color(1, 1, 1, 0.3)
			e.set_border_width_all(1)
			e.anti_aliasing = true
			draw_style_box(e, r)
			var c := r.get_center()
			draw_line(c - Vector2(5, 0), c + Vector2(5, 0), Color(1, 1, 1, 0.4), 1.5)
			draw_line(c - Vector2(0, 5), c + Vector2(0, 5), Color(1, 1, 1, 0.4), 1.5)
			return
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.97, 0.97) if not active else Color.WHITE
		sb.set_corner_radius_all(5)
		sb.border_color = Color.BLACK
		sb.set_border_width_all(2 if active else 1)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 3
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		if accent.a > 0.0:
			draw_rect(Rect2(Vector2(2, 2), Vector2(5, size.y - 4)), accent)
		BWDowntimeWidgets.draw_icon(self, action, Rect2(Vector2(10, 5), Vector2(size.y - 10, size.y - 10)), Color.BLACK)
		draw_string(f, Vector2(size.y + 6, size.y * 0.5 + 5.5), word, HORIZONTAL_ALIGNMENT_LEFT, size.x - size.y - 8, 14, Color.BLACK)


## The Progress Day arrow: an arrow-shaped plate pointing on to tomorrow,
## outlined and dim until every unit is set, then solid white with a slow
## shimmer. Shows the count ("4 of 6 ready").
class ProgressArrow:
	extends Button
	var ready_n := 0
	var total := 6
	## Other screens' arrows (the hall's prep: "CONTINUE" / "TO FIGHT 1").
	var lines: PackedStringArray = ["PROGRESS", "DAY"]
	var sub_text := ""                 # replaces the ready count when set
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(250, 120)
		focus_mode = Control.FOCUS_NONE
		text = ""
		tooltip_text = "Progress the day (Enter)"
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func set_count(n: int, of: int) -> void:
		ready_n = n
		total = of
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if not disabled:
			queue_redraw()

	func _shape(inset: float, nudge: float) -> PackedVector2Array:
		var w := size.x
		var h := size.y
		var head := h * 0.42
		var y0 := h * 0.14 + inset
		var y1 := h * 0.86 - inset
		return PackedVector2Array([Vector2(inset + nudge, y0), Vector2(w - head - inset * 0.4 + nudge, y0),
			Vector2(w - head - inset * 0.4 + nudge, inset), Vector2(w - inset * 1.6 + nudge, h * 0.5),
			Vector2(w - head - inset * 0.4 + nudge, h - inset), Vector2(w - head - inset * 0.4 + nudge, y1),
			Vector2(inset + nudge, y1)])

	func _draw() -> void:
		var f := get_theme_font("font", "Label")
		var hover := is_hovered() and not disabled
		var nudge := (3.0 if hover else 0.0) + (0.0 if disabled else 2.0 * sin(_t * 2.2))
		var outer := _shape(0.0, nudge)
		if disabled:
			draw_colored_polygon(outer, Color(0.04, 0.04, 0.05, 0.85))
			var loop := outer.duplicate()
			loop.append(outer[0])
			draw_polyline(loop, Color(1, 1, 1, 0.4), 2.0, true)
		else:
			# shadow, ink rim, white body
			var sh := PackedVector2Array()
			for p in outer:
				sh.append(p + Vector2(4, 5))
			draw_colored_polygon(sh, Color(0, 0, 0, 0.55))
			draw_colored_polygon(outer, Color.BLACK)
			var inner := _shape(3.0, nudge)
			draw_colored_polygon(inner, Color(0.97, 0.97, 0.97))
			var glow := 0.5 + 0.5 * sin(_t * 2.2)
			var loop := inner.duplicate()
			loop.append(inner[0])
			draw_polyline(loop, Color(0, 0, 0, 0.25 + 0.25 * glow), 2.0, true)
		var ink := Color.BLACK if not disabled else BWStyle.TEXT_DIM
		var bx := 22.0 + nudge
		draw_string(f, Vector2(bx, size.y * 0.5 - 22), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		draw_string(f, Vector2(bx, size.y * 0.5 + 6), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		if sub_text != "":
			draw_string(f, Vector2(bx, size.y * 0.5 + 34), sub_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, 16, ink)
			return
		var sub := "%d of %d ready" % [ready_n, total]
		if not disabled:
			sub = "all %d ready  ·  Enter" % total
		draw_string(f, Vector2(bx, size.y * 0.5 + 34), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, 16, ink if not disabled else BWStyle.FAINT)
		# the ready count as pips
		for i in total:
			var p := Vector2(bx + 6 + i * 15, size.y * 0.5 + 50)
			if i < ready_n:
				draw_circle(p, 4.5, ink)
			else:
				draw_arc(p, 4.5, 0, TAU, 14, Color(ink.r, ink.g, ink.b, 0.5), 1.2, true)


## Dawn → dusk across the top while the day runs: a rule with ticks, the sun
## travelling along an arc, "Day N" above.
class SunTrack:
	extends Control
	var f := 0.0
	var title := ""

	func _init() -> void:
		custom_minimum_size = Vector2(560, 92)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var w := size.x
		var base := size.y - 18.0
		draw_string(font, Vector2(0, 30), title, HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color.WHITE)
		var x0 := 60.0
		var x1 := w - 60.0
		draw_line(Vector2(x0, base), Vector2(x1, base), Color(1, 1, 1, 0.5), 1.5, true)
		for i in 9:
			var x := lerpf(x0, x1, i / 8.0)
			draw_line(Vector2(x, base - (6 if i % 4 == 0 else 3)), Vector2(x, base), Color(1, 1, 1, 0.5), 1.2)
		draw_string(font, Vector2(0, base + 5), "DAWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BWStyle.TEXT_DIM)
		draw_string(font, Vector2(x1 + 12, base + 5), "DUSK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BWStyle.TEXT_DIM)
		# the sun's arc, travelled part solid
		var prev := Vector2.ZERO
		for i in 41:
			var t := i / 40.0
			var p := Vector2(lerpf(x0, x1, t), base - sin(PI * t) * 34.0)
			if i > 0:
				draw_line(prev, p, Color(1, 1, 1, 0.9 if t <= f else 0.18), 1.5 if t <= f else 1.0, true)
			prev = p
		var sp := Vector2(lerpf(x0, x1, f), base - sin(PI * f) * 34.0)
		draw_circle(sp, 9.0, Color.BLACK)
		draw_circle(sp, 7.0, Color.WHITE)


## The hall's prep (D84): what a unit wears, as four small slot squares
## (head, chest, legs, weapon): filled when worn, with the element stripe of
## an enchanted piece.
class GearPips:
	extends Control
	var unit: BWUnit

	func _init() -> void:
		custom_minimum_size = Vector2(4 * 22 + 3 * 5, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_unit(u: BWUnit) -> void:
		unit = u
		queue_redraw()

	func _draw() -> void:
		if unit == null:
			return
		var f := get_theme_font("font", "Label")
		var letters := { "head": "H", "chest": "C", "legs": "L", "main_hand": "W" }
		var x := 0.0
		for slot in BWRun.SLOTS:
			var r := Rect2(Vector2(x, 0), Vector2(22, 22))
			var it: Dictionary = unit.equipment.get(slot, {})
			if it.is_empty():
				draw_rect(r, Color(0, 0, 0, 0.45))
				draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
				draw_string(f, r.position + Vector2(0, 16), letters[slot], HORIZONTAL_ALIGNMENT_CENTER, 22, 12, Color(1, 1, 1, 0.45))
			else:
				draw_rect(r, Color(0.97, 0.97, 0.97))
				draw_rect(r, Color.BLACK, false, 1.0)
				var el := BWRun.item_element(it)
				if el != "":
					draw_rect(Rect2(r.position + Vector2(0, 18), Vector2(22, 4)), BWLook.element_color(el))
				draw_string(f, r.position + Vector2(0, 16), letters[slot], HORIZONTAL_ALIGNMENT_CENTER, 22, 13, Color.BLACK)
			x += 27.0

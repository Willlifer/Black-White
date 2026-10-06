class_name BWStatPanel
extends VBoxContainer
## The unit sheet, top right of the pre-battle screen:
##   header       head icon, name, level, element, weapon (D179: no XP bar)
##   attributes   one row per stat: glyph, full name, a bar on a shared scale
##                (base in white, equipment as a hatched extension), the BASE
##                value large and the equipment modifier as "(+x)"
##   derived      HP, Move, Speed tiles; hover for the BWFormulas calc
##   affinity     element-coloured pips by rank (10 points per rank)
##   expertise    a letter grade per weapon class, the wielded one framed
## Everything is read from the unit at set_unit() / refresh(); nothing here
## writes to it.

const W := 438.0

var unit: BWUnit
var scale_max := 20               ## bar scale, shared by the squad (set by the screen)
var _rows: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(W, 0)


func set_unit(u: BWUnit) -> void:
	unit = u
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	if unit == null:
		return
	var u := unit
	# ---- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	var icon := BWWidgets.LivePortrait.new(u, 78.0)   # D156: live once placed on the map, else the snapshot
	head.add_child(icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nm := Label.new()
	nm.text = u.name
	nm.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	hv.add_child(nm)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 7)
	hv.add_child(sub)
	sub.add_child(_label("Lv %d" % u.level, BWStyle.F_SUB - 2, BWStyle.TEXT))
	sub.add_child(_label("·", BWStyle.F_SMALL, BWStyle.FAINT))
	sub.add_child(BWGearText.Swatch.new(u.element, 15.0))
	sub.add_child(_label(u.element.capitalize(), BWStyle.F_SMALL, BWGearText.readable(BWLook.element_color(u.element))))
	sub.add_child(_label("·", BWStyle.F_SMALL, BWStyle.FAINT))
	sub.add_child(_label(str(BWData.row("weapons", u.weapon_class).get("name", u.weapon_class)), BWStyle.F_SMALL, BWStyle.LABEL))
	hv.add_child(_label("+1 level for every fight", BWStyle.F_SMALL - 3, BWStyle.FAINT))   # D179: no XP
	# ---- attributes
	add_child(_section("Attributes", "base  (+equipment)"))
	for s in BWUnit.STATS:
		var r := _StatRow.new(u, s, scale_max)
		add_child(r)
		_rows.append(r)
	# ---- derived
	var der := HBoxContainer.new()
	der.add_theme_constant_override("separation", 8)
	add_child(der)
	var mv := BWFormulas.move(u)
	var sp := BWFormulas.speed(u)
	der.add_child(_Derived.new("hp", "HP", BWFormulas.hp(u), BWFormulas.HP_TEXT))
	der.add_child(_Derived.new("move", "Move", mv, "hexes per turn"))
	der.add_child(_Derived.new("speed", "Speed", sp, "turn order"))
	# ---- affinity
	add_child(_section("Affinity", "rank · 10 points each"))
	var aff := VBoxContainer.new()
	aff.add_theme_constant_override("separation", 1)
	add_child(aff)
	for el in BWFormulas.ELEMENTS:
		aff.add_child(_AffRow.new(u, el))
	# ---- expertise
	add_child(_section("Expertise", "E → A"))
	var ex := HBoxContainer.new()
	ex.add_theme_constant_override("separation", 4)
	add_child(ex)
	for wc in BWGearText.weapon_classes():
		ex.add_child(_ExTile.new(u, wc))


func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _section(title: String, note: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var t := BWStyle.section_label(title)
	h.add_child(t)
	var line := _Rule.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(line)
	h.add_child(_label(note, BWStyle.F_MENU_TITLE - 2, BWStyle.FAINT))
	h.custom_minimum_size = Vector2(0, 26)
	return h


## A thin rule that fills the space between a section title and its note.
class _Rule:
	extends Control
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_line(Vector2(0, size.y / 2.0 + 1), Vector2(size.x, size.y / 2.0 + 1), Color(1, 1, 1, 0.18), 1.0)


class _Meter:
	extends Control
	var f := 0.0
	var col := Color.WHITE
	func _init(p: float, c: Color) -> void:
		f = clampf(p, 0.0, 1.0)
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.10))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * f, size.y)), col)


## glyph · name · bar · BASE (+gear)
class _StatRow:
	extends Control
	var u: BWUnit
	var s := ""
	var scale_max := 20
	var base := 0
	var gear := 0
	var other := 0
	var _font: Font

	func _init(p_u: BWUnit, p_s: String, p_scale: int) -> void:
		u = p_u
		s = p_s
		scale_max = maxi(p_scale, 10)
		base = int(u.stats.get(s, 0))
		gear = BWGearText.gear_bonus(u, s)
		other = BWGearText.other_bonus(u, s)
		custom_minimum_size = Vector2(0, 36)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var lines: PackedStringArray = ["%s %d" % [BWGearText.STAT_NAMES[s], u.stat(s)], "  base %d" % base]
		for slot in BWRun.SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			var v := int(it.get("stats", {}).get(s, 0))
			if v != 0:
				lines.append("  %+d  %s" % [v, BWGearText.plain_name(it)])
		if other != 0:
			lines.append("  %+d  passives" % other)
		tooltip_text = "\n".join(lines)

	func _ready() -> void:
		_font = get_theme_default_font()

	func _draw() -> void:
		var h := size.y
		BWGearText.draw_glyph(self, s, Rect2(Vector2(2, h / 2.0 - 11), Vector2(22, 22)), Color(1, 1, 1, 0.9))
		var fs := BWStyle.F_BODY
		draw_string(_font, Vector2(36, h / 2.0 + fs * 0.36), BWGearText.STAT_NAMES[s], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BWStyle.TEXT)
		draw_string(_font, Vector2(36 + _font.get_string_size(BWGearText.STAT_NAMES[s], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 7,
			h / 2.0 + fs * 0.36), s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, BWStyle.F_SMALL - 4, BWStyle.FAINT)
		# bar on the shared scale
		var bx := 222.0
		var bw := size.x - bx - 104.0
		var by := h / 2.0 - 4.0
		var bh := 8.0
		draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.08))
		var fb := bw * clampf(float(base) / scale_max, 0.0, 1.0)
		draw_rect(Rect2(bx, by, fb, bh), Color(0.96, 0.96, 0.96))
		var extra := gear + other
		if extra > 0:
			var fg := bw * clampf(float(base + extra) / scale_max, 0.0, 1.0) - fb
			draw_rect(Rect2(bx + fb, by, fg, bh), Color(1, 1, 1, 0.28))
			var k := 0.0
			while k < fg:
				draw_line(Vector2(bx + fb + k, by + bh), Vector2(bx + fb + minf(k + bh, fg), by), Color(1, 1, 1, 0.75), 1.0)
				k += 4.0
		var step := 5 if scale_max <= 30 else 10
		var t := step
		while t < scale_max:
			var x := bx + bw * float(t) / scale_max
			draw_line(Vector2(x, by - 2), Vector2(x, by + bh + 2), Color(0, 0, 0, 0.7), 1.0)
			t += step
		# BASE large, (+x) small
		var vfs := BWStyle.F_SUB + 5
		var vs := str(base)
		var vx := size.x - 62.0
		var vw := _font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs).x
		draw_string(_font, Vector2(vx - vw, h / 2.0 + vfs * 0.36), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs, Color.WHITE)
		if extra != 0:
			draw_string(_font, Vector2(vx + 6, h / 2.0 + vfs * 0.36), "(%+d)" % extra, HORIZONTAL_ALIGNMENT_LEFT, -1,
				BWStyle.F_SMALL, BWStyle.TEXT_DIM)


## A derived number: glyph, big value, caption; the calc on hover.
class _Derived:
	extends PanelContainer
	func _init(glyph: String, label: String, c: Dictionary, caption: String) -> void:
		add_theme_stylebox_override("panel", BWStyle.column_style())
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "%s = %s\n    = %s\n    = %d" % [label, c.formula, c.values, int(c.value)]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		var g := _Glyph.new(glyph)
		h.add_child(g)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var n := Label.new()
		n.text = "%d" % int(c.value)
		n.add_theme_font_size_override("font_size", BWStyle.F_NAME - 2)
		v.add_child(n)
		var l := Label.new()
		l.text = label.to_upper()
		l.add_theme_font_size_override("font_size", BWStyle.F_MENU_TITLE - 2)
		l.add_theme_color_override("font_color", BWStyle.LABEL)
		v.add_child(l)
		var cl := Label.new()
		cl.text = caption
		cl.add_theme_font_size_override("font_size", BWStyle.F_MENU_TITLE - 4)
		cl.add_theme_color_override("font_color", BWStyle.FAINT)
		v.add_child(cl)


class _Glyph:
	extends Control
	var g := ""
	func _init(p: String) -> void:
		g = p
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		BWGearText.draw_glyph(self, g, Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.9))


## swatch · element · 10 pips (filled to rank; the next one shows progress)
class _AffRow:
	extends Control
	var u: BWUnit
	var el := ""
	var _font: Font
	func _init(p_u: BWUnit, p_el: String) -> void:
		u = p_u
		el = p_el
		custom_minimum_size = Vector2(0, 22)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var pts := int(u.affinity.get(el, 0))
		var r := u.affinity_rank(el)
		tooltip_text = "%s rank %d  (%d points)\n+%d%% %s damage, +%d%% %s resistance" % [el.capitalize(), r, pts,
			int(r * BWFormulas.AFFINITY_DMG_PER_RANK * 100), el, int(r * BWFormulas.AFFINITY_RES_PER_RANK), el]
	func _ready() -> void:
		_font = get_theme_default_font()
	func _draw() -> void:
		var h := size.y
		var col := BWLook.element_color(el)
		var pts := int(u.affinity.get(el, 0))
		var r := u.affinity_rank(el)
		var on := pts > 0
		var c := Vector2(9, h / 2.0)
		var d := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
		draw_colored_polygon(d, col if on else Color(col, 0.35))
		var fs := BWStyle.F_SMALL
		draw_string(_font, Vector2(26, h / 2.0 + fs * 0.36), el.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			BWGearText.readable(col) if on else BWStyle.FAINT)
		var x0 := 120.0
		var pw := (size.x - x0 - 40.0) / 10.0
		for i in BWUnit.MAX_AFFINITY_RANK:
			var pr := Rect2(x0 + i * pw + 1, h / 2.0 - 5, pw - 3, 10)
			draw_rect(pr, Color(1, 1, 1, 0.07))
			if i < r:
				draw_rect(pr, col)
			elif i == r and pts % BWUnit.POINTS_PER_RANK > 0:
				var f := float(pts % BWUnit.POINTS_PER_RANK) / BWUnit.POINTS_PER_RANK
				draw_rect(Rect2(pr.position, Vector2(pr.size.x * f, pr.size.y)), Color(col, 0.5))
		var rs := str(r)
		draw_string(_font, Vector2(size.x - 24, h / 2.0 + fs * 0.4), rs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1,
			Color.WHITE if on else BWStyle.FAINT)


## weapon name over its letter grade; progress to the next grade underneath
class _ExTile:
	extends Control
	var u: BWUnit
	var wc := ""
	var _font: Font
	func _init(p_u: BWUnit, p_wc: String) -> void:
		u = p_u
		wc = p_wc
		custom_minimum_size = Vector2(0, 64)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS
		var pts := int(u.expertise.get(wc, 0))
		tooltip_text = "%s expertise %s  (%d points)\n+5 hit and a skill pick per letter. Anyone can wield any weapon." % [
			BWText.weapon(wc), u.expertise_letter(wc), pts]
	func _ready() -> void:
		_font = get_theme_default_font()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var wielded := wc == u.weapon_class
		var pts := int(u.expertise.get(wc, 0))
		draw_rect(r, Color(1, 1, 1, 0.06 if not wielded else 0.12))
		if wielded:
			draw_rect(r.grow(-1), Color.WHITE, false, 2.0)
		var name := str(BWData.row("weapons", wc).get("name", wc))
		var fs := BWStyle.F_SMALL - 5
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, Vector2((size.x - tw) / 2.0, fs + 4), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			BWStyle.LABEL if wielded or pts > 0 else BWStyle.FAINT)
		var letter := u.expertise_letter(wc)
		var lfs := BWStyle.F_NAME - 4
		var lw := _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(_font, Vector2((size.x - lw) / 2.0, size.y - 14), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs,
			Color.WHITE if wielded or pts > 0 else BWStyle.FAINT)
		var f := float(pts % BWUnit.POINTS_PER_RANK) / BWUnit.POINTS_PER_RANK
		if u.expertise_rank(wc) >= BWUnit.EXPERTISE_RANKS.size() - 1:
			f = 1.0
		draw_rect(Rect2(6, size.y - 7, size.x - 12, 3), Color(1, 1, 1, 0.10))
		draw_rect(Rect2(6, size.y - 7, (size.x - 12) * f, 3), Color(1, 1, 1, 0.8))

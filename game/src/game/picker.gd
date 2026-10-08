class_name BWPicker
extends Control
## The pick panel (D90/D91): a centred box of cards over a dim scrim, one
## card per option of a BWPicks request. D174: two cards, drawn at random
## (BWPicks.options): two element perks the unit doesn't own, or two of
## "Improve" a known skill / "Learn" a new one.
##
##   var p := BWPicker.new(unit, request, "Rank up")
##   add_child(p)                    # anywhere: it fills its parent's rect
##   var id: String = await p.chosen
##
## Click a card to select it, then Take it (or double-click, or Enter).
## Keys 1-9 select. There is no cancel: the pick is owed now (no banking).
## Plain B/W panel; the only hue is the element accent (the perk's element,
## or the unit's own for skill picks).

signal chosen(id: String)

const CARD := Vector2(232, 316)
## D278: the keystone rule (ELEMENTS-v3 §9: "the pick card is gold-ruled, with
## KEYSTONE over the name"). The one non-element hue, kept to thin rules.
const GOLD := Color(0.86, 0.71, 0.36)

var unit: BWUnit
var request: Dictionary = {}
var context := ""
var options: Array = []
var accent := Color.WHITE
var _cards: Array = []
var _sel := -1
var _take: Button
var _hint: Label
var _sent := false
var _scrim: ColorRect


func _init(u: BWUnit, req: Dictionary, ctx: String = "") -> void:
	unit = u
	request = req
	context = ctx
	options = BWPicks.options(u, req)
	var el := str(req.get("element", "")) if req.get("kind", "") in ["perk", "keystone"] else u.element
	accent = BWLook.element_color(el) if el != "" else Color.WHITE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = BWStyle.theme()
	_build()
	ready.connect(func(): BWEsc.push(self, Callable(), { "name": "picker", "mandatory": true, "nudge": nudge }))   # ---- D171


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.62)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := PanelContainer.new()
	var sb := BWStyle.box_style()
	sb.set_content_margin_all(22)
	sb.border_color = Color.WHITE
	sb.border_width_top = 6
	sb.border_color = accent if request.get("kind", "") == "perk" else Color.WHITE
	if request.get("kind", "") == "keystone":
		sb.border_color = GOLD                      # D278: a keystone pick is gold-ruled
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	# header: the unit, what this pick is
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var icon := BWWidgets.Portrait.new(unit, 64.0, unit.team != "player")
	head.add_child(icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var kicker := BWStyle.section_label(_kicker())
	kicker.add_theme_color_override("font_color", Color(accent, 0.95) if accent != Color.WHITE else Color(1, 1, 1, 0.6))
	hv.add_child(kicker)
	var title := Label.new()
	title.text = "%s — choose one" % BWKeystones.titled(unit)   # D445: the title shows
	title.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	hv.add_child(title)
	var sub := Label.new()
	sub.text = _subtitle()
	sub.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	hv.add_child(sub)
	# the cards
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 16)
	row.custom_minimum_size = Vector2(mini(maxi(options.size(), 3), 5) * (CARD.x + 16) - 16, 0)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for i in options.size():
		var c := Card.new(options[i], i, self)
		_cards.append(c)
		row.add_child(c)
	# footer: hint + Take it
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_hint = Label.new()
	_hint.text = "Click a card, then Take it  ·  double-click or Enter  ·  1–%d" % mini(options.size(), 9)
	_hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_hint.add_theme_color_override("font_color", BWStyle.FAINT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_hint)
	_take = Button.new()
	_take.text = "Take it  [Enter]"
	_take.focus_mode = Control.FOCUS_NONE
	_take.disabled = true
	_take.custom_minimum_size = Vector2(200, 44)
	for st in ["normal", "hover", "pressed"]:
		var bs := BWStyle.button_style(st)
		bs.border_color = accent
		bs.border_width_left = 5
		_take.add_theme_stylebox_override(st, bs)
	_take.pressed.connect(_confirm)
	foot.add_child(_take)
	# preselect the first free card so Enter always works
	for i in options.size():
		if not options[i].owned:
			select(i)
			break


func _kicker() -> String:
	if request.get("kind", "") == "leviathan":         # D451: the Leviathan's prompts
		return "LEVIATHAN  ·  %s%s" % ["submerge?" if str(request.get("step", "")) == "submerge" else "choose your form",
			("  ·  " + context) if context != "" else ""]
	if request.get("kind", "") == "keystone":
		var kel := str(request.element)
		if kel == BWKeystones.ANY:                     # D444: the rank-6 wildcard
			return "KEYSTONE  ·  second slot  ·  rank 6%s" % [("  ·  " + context) if context != "" else ""]
		return "KEYSTONE  ·  %s  ·  rank %d%s" % [kel.capitalize(), unit.affinity_rank(kel),
			("  ·  " + context) if context != "" else ""]
	if request.get("kind", "") == "perk":
		var el := str(request.element)
		return "%s perk  ·  rank %d%s" % [el.capitalize(), unit.affinity_rank(el),
			("  ·  " + context) if context != "" else ""]
	var wc := str(request.get("weapon", ""))
	return "%s skill  ·  expertise %s%s" % [BWText.weapon(wc), unit.expertise_letter(wc),
		("  ·  " + context) if context != "" else ""]


func _subtitle() -> String:
	if request.get("kind", "") == "perk":
		var el := str(request.element)
		var n := BWPicks.perks_of(el).size()
		return "Affinity rank %d in %s: perk %d of %d, one of two drawn for you. Rank 3 brings a keystone and a title, rank 6 a second." % [
			unit.affinity_rank(el), el, BWPicks.owned(unit, el).size() + 1, n]
	if request.get("kind", "") == "leviathan":
		if str(request.get("step", "")) == "submerge":
			return "%s ended its walk on water 3. Once a battle it may sink: its turn ends now." % unit.name
		return "%s rises from the water. The form it takes holds for the rest of the battle." % unit.name
	if request.get("kind", "") == "keystone":
		var kel := str(request.element)
		if kel == BWKeystones.ANY:
			return "Rank 6: a second keystone, from another element you know (one per element, %d at most). It names you anew." % BWKeystones.MAX_PER_UNIT
		return ("A keystone breaks one of %s's rules and gives a title. One per element, %d at most; rank 6 opens the second." % [kel,
			BWKeystones.MAX_PER_UNIT])
	var tail := " A passive takes no slot." if not BWWeaponMove.passives_of(str(request.get("weapon", ""))).is_empty() else ""   # D372
	return "A new expertise letter: two ways to grow, drawn for you. You equip up to %d.%s" % [BWUnit.loadout_cap(str(request.get("weapon", ""))), tail]


## Mid-fight: keep the top of the screen (the unit, its marked tile) clear.
## `top` is in design pixels (1600×900); the scrim covers only the panel's band.
func dock_low(top: float = 330.0, scrim_alpha: float = 0.35) -> void:
	offset_top = top
	_scrim.color.a = scrim_alpha


## D171: Esc on an owed pick: it can't be dismissed, so a small "choose one".
var nudges := 0
var _nudge_tw: Tween


func nudge() -> void:
	nudges += 1
	_hint.text = "Choose one: this pick can't be skipped"
	_hint.add_theme_color_override("font_color", Color.WHITE)
	if _nudge_tw:
		_nudge_tw.kill()
	_nudge_tw = create_tween().set_ignore_time_scale(true)
	_nudge_tw.tween_property(_hint, "modulate:a", 0.35, 0.09)
	_nudge_tw.tween_property(_hint, "modulate:a", 1.0, 0.09)
	_nudge_tw.tween_property(_hint, "modulate:a", 0.35, 0.09)
	_nudge_tw.tween_property(_hint, "modulate:a", 1.0, 0.09)


func select(i: int) -> void:
	if i < 0 or i >= options.size() or options[i].owned:
		return
	_sel = i
	for c in _cards:
		c.queue_redraw()
	_take.disabled = false
	_take.text = "Take %s  [Enter]" % str(options[i].name)


func _confirm() -> void:
	if _sent or _sel < 0:
		return
	_sent = true
	chosen.emit(str(options[_sel].id))


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k: int = ev.keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		_confirm()
	elif k >= KEY_1 and k <= KEY_9:
		select(k - KEY_1)
	elif k == KEY_LEFT or k == KEY_RIGHT:
		var step := -1 if k == KEY_LEFT else 1
		var i := _sel
		for n in options.size():
			i = wrapi(i + step, 0, options.size())
			if not options[i].owned:
				select(i)
				break
	get_viewport().set_input_as_handled()


## One option: glyph, name, effect text; greyed when owned.
class Card:
	extends Control
	var opt: Dictionary
	var index := 0
	var picker: BWPicker
	var _hover := false

	func _init(o: Dictionary, i: int, p: BWPicker) -> void:
		opt = o
		index = i
		picker = p
		custom_minimum_size = BWPicker.CARD
		if str(o.get("kind", "")) in ["keystone", "leviathan"]:
			custom_minimum_size = BWPicker.CARD + Vector2(36, 84)   # D278: a keystone's rule is longer
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_ARROW if o.owned else Control.CURSOR_POINTING_HAND
		tooltip_text = "%s\n%s" % [o.name, o.text]
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	## D125: the rule, then the definitions of the terms it uses.
	func _make_custom_tooltip(for_text: String) -> Object:
		return BWGlossary.tooltip_panel(for_text)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			picker.select(index)
			if ev.double_click:
				picker._confirm()
			accept_event()

	func _draw() -> void:
		var s := size
		var owned: bool = opt.owned
		var sel := picker._sel == index
		var acc: Color = picker.accent
		var el := str(opt.get("element", ""))
		var ks := str(opt.get("kind", "")) in ["keystone", "leviathan"]
		var duo := str(opt.get("duo", ""))             # D455: a duo perk's second element
		var glyph_col := BWLook.element_color(el) if el != "" else acc
		var fade := 0.32 if owned else 1.0
		# plate
		var bg := Color(0.11, 0.11, 0.12, 0.96) if (sel or _hover) and not owned else Color(0.06, 0.06, 0.07, 0.94)
		draw_rect(Rect2(Vector2.ZERO, s), bg)
		var rim := Color(1, 1, 1, 0.95) if sel else Color(1, 1, 1, 0.55 if _hover and not owned else 0.28)
		if ks:                                     # D278: gold-ruled, a double rule inside the rim
			rim = Color(BWPicker.GOLD, (1.0 if sel else (0.85 if _hover else 0.7)) * fade)
		draw_rect(Rect2(Vector2.ZERO, s), rim, false, 3.0 if sel else 1.5)
		if ks:
			draw_rect(Rect2(Vector2(6, 6), s - Vector2(12, 12)), Color(BWPicker.GOLD, 0.45 * fade), false, 1.0)
		# the element band across the top (thicker when chosen)
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 8.0 if sel else 5.0)), Color(glyph_col, fade))
		# hotkey
		var font := get_theme_default_font()
		draw_string(font, Vector2(12, 30), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, BWStyle.F_SMALL,
			Color(1, 1, 1, 0.35 * fade))
		if el != "" and BWKanji.enabled():           # D231: the element kanji, top right
			draw_string(BWKanji.font(2), Vector2(12, 40), BWKanji.glyph(el), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 24, BWStyle.F_BODY + 8,
				Color(glyph_col.lightened(0.15), fade))
		# glyph in a ring
		var c := Vector2(s.x / 2.0, 82)
		draw_circle(c, 46, Color(1, 1, 1, 0.06 * fade))
		draw_arc(c, 46, 0, TAU, 64, Color(glyph_col, 0.85 * fade), 2.5, true)
		var g := Rect2(c - Vector2(28, 28), Vector2(56, 56))
		var kind := str(opt.get("kind", "perk"))
		if kind in ["keystone", "leviathan"]:
			BWPicker.draw_keystone_sigil(self, c, 40.0, Color(BWPicker.GOLD, fade))
			BWPicker.draw_element_glyph(self, el, Rect2(c - Vector2(20, 20), Vector2(40, 40)), Color(glyph_col, fade))
		elif kind == "perk" and duo != "":           # D455: two glyphs, side by side, the two colours
			var c2 := BWLook.element_color(duo)
			draw_arc(c, 46, PI * 0.5, PI * 1.5, 32, Color(glyph_col, 0.95 * fade), 3.0, true)
			draw_arc(c, 46, -PI * 0.5, PI * 0.5, 32, Color(c2, 0.95 * fade), 3.0, true)
			BWPicker.draw_element_glyph(self, el, Rect2(c + Vector2(-38, -17), Vector2(34, 34)), Color(glyph_col, fade))
			BWPicker.draw_element_glyph(self, duo, Rect2(c + Vector2(4, -17), Vector2(34, 34)), Color(c2, fade))
		elif kind == "perk":
			BWPicker.draw_element_glyph(self, el, g, Color(glyph_col, fade))
		else:
			BWPicker.draw_skill_glyph(self, kind, g, Color(Color.WHITE, fade))
		# name
		var nfs := BWStyle.F_BODY + 2           # shrink a long name to fit, never clip it
		while nfs > BWStyle.F_SMALL - 2 and font.get_string_size(str(opt.name), HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > s.x - 24:
			nfs -= 1
		if ks:                                     # D278: "KEYSTONE" over the name
			var kick := "KEYSTONE" + ("  ·  ACTION" if opt.get("action", false) else "")
			if kind == "leviathan":
				kick = "LEVIATHAN"
			draw_string(font, Vector2(12, 146), kick, HORIZONTAL_ALIGNMENT_CENTER, s.x - 24, BWStyle.F_SMALL - 2, Color(BWPicker.GOLD, fade))
		elif duo != "":                            # D455: "DUO · Fire + Wind" over the name
			draw_string(font, Vector2(12, 148), "DUO  ·  %s + %s" % [el.capitalize(), duo.capitalize()],
				HORIZONTAL_ALIGNMENT_CENTER, s.x - 24, BWStyle.F_SMALL - 2, Color(BWLook.element_color(duo).lightened(0.2), fade))
		draw_string(font, Vector2(12, 168 if ks or duo != "" else 160), str(opt.name), HORIZONTAL_ALIGNMENT_CENTER, s.x - 24, nfs,
			Color(BWStyle.TEXT, fade))
		var y := 196.0 if ks or duo != "" else 192.0
		var ttl := str(opt.get("title", ""))
		if ttl != "" and picker.unit != null:      # D445: the title it gives ("Will, the Lava Walker")
			draw_string(font, Vector2(12, 190), "%s, %s" % [picker.unit.name, ttl], HORIZONTAL_ALIGNMENT_CENTER, s.x - 24,
				BWStyle.F_SMALL - 1, Color(BWPicker.GOLD.lightened(0.15), 0.95 * fade))
			y = 216.0
		# effect text, wrapped; the last line that fits ends in an ellipsis (the tooltip has it all)
		var fs := BWStyle.F_SMALL - 1
		var lines := _wrap(font, str(opt.text), s.x - 28, fs)
		var room := int((s.y - 44.0 - y) / (BWStyle.F_SMALL + 3)) + 1
		for i in mini(lines.size(), room):
			var line := lines[i]
			if i == room - 1 and lines.size() > room:
				line = line.trim_suffix(".") + "…"
			draw_string(font, Vector2(14, y), line, HORIZONTAL_ALIGNMENT_CENTER, s.x - 28, fs,
				Color(BWStyle.TEXT_DIM, fade))
			y += BWStyle.F_SMALL + 3
		if owned:
			var tag := "OWNED" if kind in ["perk", "keystone", "passive"] else "IMPROVED"
			if opt.get("locked", false):
				tag = "NOT YET"                    # D451: Leviathos isn't built
			draw_string(font, Vector2(14, s.y - 14), tag, HORIZONTAL_ALIGNMENT_CENTER, s.x - 28, BWStyle.F_MENU_TITLE,
				Color(1, 1, 1, 0.55))
		elif sel:
			draw_string(font, Vector2(14, s.y - 14), "CHOSEN", HORIZONTAL_ALIGNMENT_CENTER, s.x - 28, BWStyle.F_MENU_TITLE,
				Color(glyph_col.lightened(0.2), 1.0))

	func _wrap(font: Font, text: String, w: float, fs: int) -> PackedStringArray:
		var out := PackedStringArray()
		var line := ""
		for word in text.split(" ", false):
			var t := word if line == "" else line + " " + word
			if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w and line != "":
				out.append(line)
				line = word
			else:
				line = t
		if line != "":
			out.append(line)
		return out


# ---------------------------------------------------------------- keystone text (D278)

## The sigil after a unit's element on its cards: a gold diamond-in-a-diamond
## per keystone held ("" for none).
static func sigil_bb(u: BWUnit) -> String:
	if u == null or u.keystones.is_empty():
		return ""
	return " [color=#%s]%s[/color]" % [GOLD.to_html(false), "◈".repeat(u.keystones.size())]


## One card line naming the keystones, each with its rule on hover:
## "◈ Keystone  Prism · Doom" ("" for none).
static func keystone_bb(u: BWUnit, fs: int) -> String:
	if u == null or u.keystones.is_empty():
		return ""
	var names: PackedStringArray = []
	for id in u.keystones:
		var r := BWKeystones.row(str(id))
		names.append("[hint=%s][color=#%s]%s[/color][/hint]" % [BWPicker.hint_safe("%s (%s): %s" % [str(r.get("name", id)), str(r.get("title", "")), str(r.get("text", ""))]),
			BWGearText.hex(BWGearText.readable(BWLook.element_color(str(r.get("element", ""))))), str(r.get("name", id))])
	return "[font_size=%d][color=#%s]◈ %s[/color]  %s[/font_size]" % [fs, GOLD.to_html(false),
		"Keystones" if u.keystones.size() > 1 else "Keystone", " · ".join(names)]


## A rule as a [hint=] value: no brackets, no "=" (the BBCode parser reads a
## second "=" as a new tag argument and the whole tag leaks as text, D301), and
## typographic quotes (a straight quote starts a quoted string in the parser;
## see BWGlossary.hint_text).
static func hint_safe(t: String) -> String:
	return t.replace("[", "(").replace("]", ")").replace(" = ", " is ").replace("=", ":").replace("'", "’").replace("\"", "”")


# ---------------------------------------------------------------- glyphs

## D278: the keystone sigil, a diamond in a diamond (the picker card's ring,
## the unit card beside the element dot, the hall). `r` = the outer half-size.
static func draw_keystone_sigil(ci: CanvasItem, c: Vector2, r: float, col: Color, filled: bool = false) -> void:
	var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
	if filled:
		ci.draw_colored_polygon(outer.slice(0, 4), Color(col, col.a * 0.25))
	ci.draw_polyline(outer, col, maxf(1.5, r * 0.07), true)
	var k := r * 0.62
	ci.draw_polyline(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, 0), c + Vector2(0, k), c + Vector2(-k, 0), c + Vector2(0, -k)]),
		Color(col, col.a * 0.7), maxf(1.0, r * 0.04), true)

## A small vector mark per element, drawn into `r` in `col`.
static func draw_element_glyph(ci: CanvasItem, el: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var h := r.size.y / 2.0
	match el:
		"fire":
			ci.draw_colored_polygon(_flame(c + Vector2(0, h * 0.12), h * 0.9, h * 0.6, 0.18), col)
			ci.draw_colored_polygon(_flame(c + Vector2(-h * 0.42, h * 0.38), h * 0.42, h * 0.26, -0.3), col)
			ci.draw_colored_polygon(_flame(c + Vector2(0, h * 0.42), h * 0.46, h * 0.3, -0.1), Color(0.06, 0.06, 0.07, col.a))
		"water":
			var pts := PackedVector2Array([c + Vector2(0, -h)])
			var cc := c + Vector2(0, h * 0.32)
			for i in 25:
				var a := -PI / 6.0 + (PI + PI / 3.0) * float(i) / 24.0
				pts.append(cc + Vector2(cos(a), sin(a)) * h * 0.62)
			ci.draw_colored_polygon(pts, col)
			ci.draw_arc(cc, h * 0.38, PI * 0.15, PI * 0.55, 10, Color(1, 1, 1, 0.55 * col.a), 3.0, true)
		"ice":
			for i in 6:
				var a := PI / 3.0 * i
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c, c + d * h, col, 3.5, true)
				var m := c + d * h * 0.58
				ci.draw_line(m, m + d.rotated(0.75) * h * 0.3, col, 2.5, true)
				ci.draw_line(m, m + d.rotated(-0.75) * h * 0.3, col, 2.5, true)
		"thunder":
			var pts := PackedVector2Array([c + Vector2(h * 0.25, -h), c + Vector2(-h * 0.5, h * 0.12),
				c + Vector2(-h * 0.02, h * 0.12), c + Vector2(-h * 0.3, h), c + Vector2(h * 0.55, -h * 0.18),
				c + Vector2(h * 0.06, -h * 0.18)])
			ci.draw_colored_polygon(pts, col)
		"wind":
			for k in 3:
				var y := (k - 1) * h * 0.55
				var w := h * (1.0 - 0.18 * absf(k - 1))
				ci.draw_line(c + Vector2(-w, y), c + Vector2(w * 0.45, y), col, 4.0, true)
				ci.draw_arc(c + Vector2(w * 0.45, y - h * 0.18), h * 0.18, PI * 0.5, PI * 2.1, 12, col, 4.0, true)
		"dark":
			ci.draw_circle(c, h * 0.82, col)
			ci.draw_circle(c + Vector2(h * 0.38, -h * 0.22), h * 0.7, Color(0.06, 0.06, 0.07))
			ci.draw_arc(c, h * 0.82, 0, TAU, 48, Color(col, 0.6), 1.5, true)
		"light":
			ci.draw_circle(c, h * 0.42, col)
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				ci.draw_line(c + d * h * 0.58, c + d * h * 0.98, col, 4.0, true)
		_:
			ci.draw_circle(c, h * 0.5, col)


## A flame tongue: round base of radius `w` centred at `base`, a tip `tall`
## above it, leaning `lean` (fraction of w) sideways. Clockwise, simple.
static func _flame(base: Vector2, tall: float, w: float, lean: float) -> PackedVector2Array:
	var pts := PackedVector2Array([base + Vector2(w * lean * 2.0, -tall)])
	for i in 21:
		var a := -PI * 0.12 + PI * 1.24 * float(i) / 20.0
		pts.append(base + Vector2(cos(a), sin(a)) * w)
	return pts


## Improve: a double chevron up. Learn: a four-point star. Passive (D372):
## a climber's stair, three rising steps under an up arrow.
static func draw_skill_glyph(ci: CanvasItem, kind: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var h := r.size.y / 2.0
	if kind == "passive":
		var st := PackedVector2Array([c + Vector2(-h * 0.85, h * 0.8)])
		for i in 3:
			var x := -h * 0.85 + h * 0.57 * i
			var y := h * 0.8 - h * 0.45 * (i + 1)
			st.append(c + Vector2(x, y))
			st.append(c + Vector2(x + h * 0.57, y))
		st.append(c + Vector2(h * 0.86, h * 0.8))
		ci.draw_colored_polygon(st, col)
		ci.draw_line(c + Vector2(-h * 0.5, -h * 0.2), c + Vector2(-h * 0.5, -h * 0.95), col, 5.0, true)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.5, -h * 1.15), c + Vector2(-h * 0.78, -h * 0.78),
			c + Vector2(-h * 0.22, -h * 0.78)]), col)
		return
	if kind == "learn":
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI / 2.0
			pts.append(c + Vector2.from_angle(a) * (h if i % 2 == 0 else h * 0.3))
		ci.draw_colored_polygon(pts, col)
	else:
		for k in 2:
			var y := (k * 0.62 - 0.1) * h
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, y + h * 0.35), c + Vector2(0, y - h * 0.35),
				c + Vector2(h * 0.7, y + h * 0.35)]), col, 7.0, true)

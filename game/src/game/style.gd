class_name BWStyle
## The HUD's one visual language, ported from Temporal Sea V8
## (fe_dialogue_box.gd box/frame/hud/prompt styles, ADR-0023 "one HUD visual
## language") and translated to black and white: V8's gold borders become
## white, its faction colours become fills (player = white, enemy = grey), and
## element colour is the only hue on screen.
## Weight order (ADR-0023): hud plate < frame < prompt < box.

const PANEL_BG := Color(0.035, 0.035, 0.04, 0.92)
const PANEL_BG_LIGHT := Color(0.085, 0.085, 0.095, 0.92)
const HUD_BG := Color(0.03, 0.03, 0.035, 0.72)
const BORDER := Color(1, 1, 1)
const BORDER_SOFT := Color(1, 1, 1, 0.55)
const TEXT := Color(0.94, 0.94, 0.95)
const TEXT_DIM := Color(0.70, 0.70, 0.74)
const LABEL := Color(0.78, 0.78, 0.82)
const FAINT := Color(0.42, 0.42, 0.46)
const PLAYER_FILL := Color(0.96, 0.96, 0.96)
const ENEMY_FILL := Color(0.45, 0.45, 0.47)

## V8 sizes were set at 1280×720; ours are ×1.25 for the 1600×900 design size.
const F_NAME := 32
const F_SUB := 21
const F_BODY := 20
const F_SMALL := 17
const F_MENU := 23
const F_MENU_TITLE := 16
const F_FEED := 18


static func _box(bg: Color, border: Color, bw: int, radius: int, shadow_a: float, shadow: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, shadow_a)
	sb.shadow_size = shadow
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## Dialogue-weight box: forecast, sheets, results.
static func box_style() -> StyleBoxFlat:
	return _box(PANEL_BG, BORDER, 3, 10, 0.5, 10, 14)


## Framed group: turn order, unit cards, menus.
static func frame_style() -> StyleBoxFlat:
	return _box(PANEL_BG_LIGHT, BORDER, 2, 6, 0.4, 6, 8)


## Quiet persistent plate: feed, hints.
static func hud_style() -> StyleBoxFlat:
	return _box(HUD_BG, BORDER_SOFT, 1, 6, 0.35, 4, 8)


## A prompt asking for input: banners, confirm.
static func prompt_style() -> StyleBoxFlat:
	return _box(Color(0.04, 0.04, 0.05, 0.88), Color(1, 1, 1, 0.85), 2, 8, 0.45, 8, 10)


static func column_style() -> StyleBoxFlat:
	return _box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 6, 0.0, 0, 8)


static func button_style(state: String) -> StyleBoxFlat:
	var sb: StyleBoxFlat
	match state:
		"hover": sb = _box(Color(0.16, 0.16, 0.18, 0.95), BORDER, 1, 5, 0.0, 0, 6)
		"pressed": sb = _box(Color(0.0, 0.0, 0.0, 0.98), BORDER, 1, 5, 0.0, 0, 6)
		"disabled": sb = _box(Color(0.05, 0.05, 0.06, 0.7), Color(1, 1, 1, 0.2), 1, 5, 0.0, 0, 6)
		_: sb = _box(Color(0.07, 0.07, 0.08, 0.90), Color(1, 1, 1, 0.75), 1, 5, 0.0, 0, 6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


## An element-accented button: the same plate with an element-coloured edge.
static func element_button_style(element: String, state: String = "normal") -> StyleBoxFlat:
	var sb := button_style(state)
	sb.border_color = BWLook.element_color(element)
	sb.border_width_left = 5
	return sb


static func theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("panel", "PanelContainer", frame_style())
	t.set_stylebox("panel", "Panel", frame_style())
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "Button", button_style(st))
		t.set_stylebox(st, "OptionButton", button_style(st))
	t.set_stylebox("focus", "Button", button_style("hover"))
	t.set_stylebox("focus", "OptionButton", button_style("hover"))
	for cls in ["Button", "OptionButton", "CheckBox"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, FAINT)
		t.set_font_size("font_size", cls, F_BODY)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", F_BODY)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", F_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", F_BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", F_BODY)
	var tip := _box(Color(0.97, 0.97, 0.97, 0.98), Color.BLACK, 2, 6, 0.4, 6, 10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color.BLACK)
	t.set_font_size("font_size", "TooltipLabel", F_SMALL)
	t.set_stylebox("panel", "ItemList", column_style())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_stylebox("selected", "ItemList", button_style("hover"))
	t.set_stylebox("selected_focus", "ItemList", button_style("hover"))
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.25)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 8)
	return t


## A title label in the V8 menu-section manner: small caps-ish, faded.
static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", F_MENU_TITLE)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return l

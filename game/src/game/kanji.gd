class_name BWKanji
extends RefCounted
## D231: the element kanji, an accessibility layer over hue and FX (the
## author: "Japanese kanji in varying boldness in addition to hue and effect").
## Off by default; Settings > Accessibility > Element kanji.
##
##   BWKanji.enabled()                 the setting
##   BWKanji.glyph("water")            "水" ("" for no element)
##   BWKanji.bb("water")               "[font=…]水[/font] " for RichTextLabel text, "" when off
##   BWKanji.prefix("water")           "水 " for a plain Label, "" when off
##   BWKanji.font(level)               the subset font at the weight a tile level reads at
##
## The font is a 7-glyph subset of Noto Sans JP (variable weight, OFL):
## art/fonts/bw_kanji.ttf, credits beside it. Never on hair: characters stay
## clean. Board placement is BWKanjiLayer (combat/kanji_layer.gd).

const FONT_PATH := "res://art/fonts/bw_kanji.ttf"
const GLYPHS := { "fire": "火", "water": "水", "ice": "氷", "thunder": "雷", "wind": "風", "dark": "闇", "light": "光" }
## Tile level -> wght: 1 thin, 2 regular, 3 heavy (0 = the UI weight).
const WEIGHTS := { 0: 500, 1: 250, 2: 500, 3: 900 }
## Tile level -> the white halo, in font pixels at Label3D font_size 96.
const OUTLINES := { 1: 14, 2: 18, 3: 24 }
const SETTING := "element_kanji"

static var _base: FontFile
static var _fonts := {}           # wght -> FontVariation
## Tests force it on/off without touching the settings file (null = the setting).
static var force: Variant = null


static func enabled() -> bool:
	if force != null:
		return bool(force)
	return bool(BWSettings.value(SETTING))


static func glyph(element: String) -> String:
	return str(GLYPHS.get(element.strip_edges().to_lower(), ""))


static func base_font() -> FontFile:
	if _base == null:
		_base = load(FONT_PATH) as FontFile
	return _base


## The subset font at the weight tile level `level` reads at (0 = UI text).
static func font(level: int = 0) -> Font:
	var w: int = WEIGHTS.get(clampi(level, 0, 3), 500)
	if not _fonts.has(w):
		var fv := FontVariation.new()
		fv.base_font = base_font()
		fv.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): w }
		_fonts[w] = fv
	return _fonts[w]


## RichTextLabel BBCode: the kanji in the subset font plus a space, or "" when
## the setting is off or the word names no element.
static func bb(element: String) -> String:
	var g := glyph(element)
	if g == "" or not enabled():
		return ""
	return "[font=%s]%s[/font] " % [FONT_PATH, g]


## The same for a plain Label (the label needs the subset as a fallback:
## `BWKanji.fallback(label)`).
static func prefix(element: String) -> String:
	var g := glyph(element)
	if g == "" or not enabled():
		return ""
	return g + " "


## Give a Control's default font the subset as a fallback, so a plain Label
## can show the kanji next to its own Latin text.
static func fallback(c: Control) -> void:
	var f := c.get_theme_default_font() if c.is_inside_tree() else ThemeDB.fallback_font
	if f == null:
		return
	var key := f.get_rid().get_id()
	if not _with_fallback.has(key):
		var fv := FontVariation.new()
		fv.base_font = f
		fv.fallbacks = [font(0)]
		_with_fallback[key] = fv
	c.add_theme_font_override("font", _with_fallback[key])

static var _with_fallback := {}


## Put the kanji in front of every element word in BBCode or plain text
## ("Light" -> "光 Light"). Whole words, case-insensitive, never inside a
## tag's own brackets (a [hint=…] value); idempotent.
static func tag_words(text: String, rich: bool = true) -> String:
	if not enabled() or text == "":
		return text
	if _word_re == null:
		_word_re = RegEx.new()
		_word_re.compile("(?i)(?<![A-Za-z0-9_])(" + "|".join(GLYPHS.keys()) + ")(?![A-Za-z0-9_])")
		_tag_re = RegEx.new()
		_tag_re.compile("\\[/?[A-Za-z_][^\\[\\]]*\\]")
	var out := ""
	var pos := 0
	for m in _tag_re.search_all(text):
		out += _tag_seg(text.substr(pos, m.get_start() - pos), rich, out) + m.get_string()
		pos = m.get_end()
	return out + _tag_seg(text.substr(pos), rich, out)


static var _word_re: RegEx
static var _tag_re: RegEx


static func _tag_seg(seg: String, rich: bool, before: String = "") -> String:
	var out := ""
	var pos := 0
	for m in _word_re.search_all(seg):
		var el := m.get_string(1).to_lower()
		var g := glyph(el)
		var head := (before + seg.substr(0, m.get_start())).strip_edges(false, true).trim_suffix("[/font]")
		out += seg.substr(pos, m.get_start() - pos)
		if not head.ends_with(g):
			out += bb(el) if rich else prefix(el)
		out += m.get_string(1)
		pos = m.get_end()
	return out + seg.substr(pos)

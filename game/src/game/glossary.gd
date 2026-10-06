class_name BWGlossary
extends RefCounted
## D125: hover definitions. data/glossary.csv is the lexicon
## (id, term, aliases, category, definition, see); markup() turns every known
## term in a BBCode string into a [hint] (RichTextLabel draws it with a dotted
## underline and shows the definition on hover).
##
##   rt.text = BWGlossary.markup("Glaze stops the tile's decay")
##   var rt := BWGlossary.Rich.new()        # a RichTextLabel whose hint tooltips are BWStyle cards
##   var b := BWGlossary.TipButton.new()   # a Button whose tooltip lists the terms it mentions
##
## Matching: whole words, case-insensitive, the longest surface wins ("gale 2"
## over "gale"), text inside tags, [hint] and [url] is left alone, so running
## it twice changes nothing. One precompiled regex for the whole lexicon.

const TABLE := "glossary"
const CATEGORY_ORDER := ["element", "tile", "operator", "rider", "status", "roll", "facing", "rule", "progression"]
const CATEGORY_NAMES := {
	"element": "Elements", "tile": "Tiles", "operator": "Operators", "rider": "Riders",
	"status": "Statuses", "roll": "The rolls", "facing": "Facing", "rule": "Rules", "progression": "Growth",
}
const HINT_SEP := ": "

static var _entries := {}          # id -> row
static var _order: Array = []      # ids, in file order
static var _by_word := {}          # lower-case surface -> id
static var _by_term := {}          # term -> id (for hint lookups)
static var _re: RegEx
static var _tag_re: RegEx
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	build(BWData.table(TABLE) if BWData.has_table(TABLE) else [])


## (Re)build the lexicon from rows (the CSV, or a test's own rows).
static func build(rows: Array) -> void:
	_loaded = true
	_entries.clear()
	_order.clear()
	_by_word.clear()
	_by_term.clear()
	var words: Array = []
	for r in rows:
		var id := str(r.get("id", ""))
		if id == "" or _entries.has(id):
			continue
		var row := {
			"id": id, "term": str(r.get("term", id)), "category": str(r.get("category", "rule")),
			"definition": _safe(str(r.get("definition", ""))), "see": str(r.get("see", "")),
			"aliases": Array(BWData.list(r.get("aliases", ""))),
		}
		_entries[id] = row
		_order.append(id)
		_by_term[row.term] = id
		for w in [row.term] + row.aliases:
			var k := str(w).strip_edges().to_lower()
			if k != "" and not _by_word.has(k):
				_by_word[k] = id
				words.append(k)
	words.sort_custom(func(a, b): return a.length() > b.length() if a.length() != b.length() else a < b)
	_re = null
	if not words.is_empty():
		var alt := "|".join(words.map(func(w): return _escape(w).replace(" ", "\\s+")))
		_re = RegEx.new()
		_re.compile("(?i)(?<![A-Za-z0-9_])(" + alt + ")(?![A-Za-z0-9_])")
	_tag_re = RegEx.new()
	_tag_re.compile("\\[/?[A-Za-z_][^\\[\\]]*\\]")


## Back to the CSV on the next call (tests that built their own rows).
static func reset() -> void:
	_loaded = false


static func entries() -> Array:
	_ensure()
	return _order.map(func(id): return _entries[id])


static func entry(id: String) -> Dictionary:
	_ensure()
	return _entries.get(id, {})


## The entry a word or phrase names ({} if none).
static func lookup(word: String) -> Dictionary:
	_ensure()
	var k := word.strip_edges().to_lower()
	var re := RegEx.new()
	re.compile("\\s+")
	k = re.sub(k, " ", true)
	return _entries.get(_by_word.get(k, ""), {})


## Every known term in `text`, linked. BBCode in, BBCode out.
static func markup(text: String) -> String:
	_ensure()
	if _re == null or text == "":
		return text
	var out := ""
	var pos := 0
	var skip := 0                    # inside [hint] / [url]: never link twice
	for m in _tag_re.search_all(text):
		var seg := text.substr(pos, m.get_start() - pos)
		out += seg if skip > 0 else _link(seg)
		var tag := m.get_string().to_lower()
		if tag.begins_with("[hint") or tag.begins_with("[url"):
			skip += 1
		elif tag.begins_with("[/hint") or tag.begins_with("[/url"):
			skip = maxi(0, skip - 1)
		out += m.get_string()
		pos = m.get_end()
	var rest := text.substr(pos)
	out += rest if skip > 0 else _link(rest)
	return out


## The ids of every term mentioned in plain or BBCode text (first-seen order).
static func terms_in(text: String) -> Array:
	_ensure()
	var ids: Array = []
	if _re == null:
		return ids
	var plain := _tag_re.sub(text, "", true) if _tag_re else text
	for m in _re.search_all(plain):
		var id := str(_by_word.get(_norm(m.get_string(1)), ""))
		if id != "" and not id in ids:
			ids.append(id)
	return ids


static func _link(seg: String) -> String:
	if seg == "":
		return seg
	var out := ""
	var pos := 0
	for m in _re.search_all(seg):
		var surface := m.get_string(1)
		var id := str(_by_word.get(_norm(surface), ""))
		out += seg.substr(pos, m.get_start(1) - pos)
		if id == "":
			out += surface
		else:
			out += "[hint=%s]%s[/hint]" % [hint_text(id), surface]
		pos = m.get_end(1)
	return out + seg.substr(pos)


## The hint string RichTextLabel shows (and Rich parses back): "Term: definition".
static func hint_text(id: String) -> String:
	var e: Dictionary = _entries.get(id, {})
	# a straight quote inside a tag value starts a quoted string in the BBCode
	# parser and swallows the rest of the line: use the typographic ones
	return ("%s%s%s" % [e.get("term", id), HINT_SEP, e.get("definition", "")]).replace("'", "’").replace("\"", "”")


static func _norm(s: String) -> String:
	var parts := s.to_lower().split(" ", false)
	var clean: PackedStringArray = []
	for p in parts:
		var q := p.strip_edges()
		if q != "":
			clean.append(q)
	return " ".join(clean)


static func _safe(s: String) -> String:
	return s.replace("[", "(").replace("]", ")").replace("\n", " ")


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in ".^$*+?()[]{}|\\/-":
			out += "\\" + ch
		else:
			out += ch
	return out


# ---------------------------------------------------------------- tooltips

const TIP_W := 360.0
const INK := Color(0.06, 0.06, 0.07)
const INK_DIM := Color(0.32, 0.32, 0.35)


## A tooltip card for hover text. For a glossary hint ("Term: definition")
## it is the term and its definition; for any other text (a button's
## tooltip, a pick card's rule) it is that text, then the definitions of the
## terms it mentions (up to `max_terms`). Dark ink on BWStyle's paper
## tooltip plate.
static func tooltip_panel(for_text: String, max_terms: int = 4) -> Control:
	_ensure()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	# D171: on the Esc stack once the viewport shows it (its popup is the parent)
	v.ready.connect(func(): BWEsc.push(v, BWEsc.close_tooltip_of.bind(v), { "name": "tooltip", "hover": true }))
	var id := ""
	var cut := for_text.find(HINT_SEP)
	if cut > 0:
		id = str(_by_term.get(for_text.substr(0, cut).replace("’", "'"), ""))
	if id != "":
		_entry_block(v, _entries[id], true)
		return v
	if for_text.strip_edges() != "":
		var body := Label.new()
		body.text = for_text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = TIP_W
		body.add_theme_color_override("font_color", INK)
		body.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		v.add_child(body)
	var ids := terms_in(for_text).slice(0, max_terms)
	if not ids.is_empty():
		var sep := ColorRect.new()
		sep.color = Color(0, 0, 0, 0.25)
		sep.custom_minimum_size = Vector2(TIP_W, 1)
		v.add_child(sep)
		for t in ids:
			_entry_block(v, _entries[t], false)
	return v


static func _entry_block(v: VBoxContainer, e: Dictionary, full: bool) -> void:
	var head := Label.new()
	head.text = str(e.term) if full else str(e.term).to_upper()
	head.add_theme_color_override("font_color", INK)
	head.add_theme_font_size_override("font_size", BWStyle.F_SMALL + (1 if full else -3))
	v.add_child(head)
	var d := Label.new()
	d.text = str(e.definition)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = TIP_W
	d.add_theme_color_override("font_color", INK_DIM if not full else INK)
	d.add_theme_font_size_override("font_size", BWStyle.F_SMALL - (0 if full else 2))
	v.add_child(d)
	if full and str(e.see) != "" and _entries.has(str(e.see)):
		var s := Label.new()
		s.text = "See also: " + str(_entries[str(e.see)].term)
		s.add_theme_color_override("font_color", INK_DIM)
		s.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 3)
		v.add_child(s)


## A RichTextLabel whose glossary hints show as tooltip cards.
class Rich:
	extends RichTextLabel

	func _init() -> void:
		bbcode_enabled = true
		mouse_filter = Control.MOUSE_FILTER_PASS

	## Set BBCode with every glossary term linked.
	func set_glossed(bb: String) -> void:
		text = BWGlossary.markup(bb)

	func _make_custom_tooltip(for_text: String) -> Object:
		return BWGlossary.tooltip_panel(for_text)


## A Button whose tooltip adds the definitions of the terms it mentions.
class TipButton:
	extends Button

	func _make_custom_tooltip(for_text: String) -> Object:
		return BWGlossary.tooltip_panel(for_text)

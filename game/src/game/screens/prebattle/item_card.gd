class_name BWItemCard
extends PanelContainer
## The item detail card, read BEFORE committing (equipment, shop, re-imbue):
##   name in the element colour, tier badge, kind and infusion
##   stat lines with the delta against what the unit wears in that slot now
##     (+2 in white, −1 dimmed, ±0 faint)
##   the enchantment's passive (its effect_text) or "No passive"
##   the ability it teaches after BWRun.LEARN_BATTLES battles worn
##   whether this unit can equip it (weapon tier vs expertise)
## Frame weight (BWStyle.frame_style), the same as the combat unit cards.

const W := 420.0

var _icon: BWItemTile
var _name: RichTextLabel
var _kind: Label
var _infusion: HBoxContainer
var _vs: Label
var _stats: GridContainer
var _passive: RichTextLabel
var _teach: RichTextLabel
var _check: RichTextLabel
var _hint: Label
var _empty: Label
var _body: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", BWStyle.frame_style())
	custom_minimum_size = Vector2(W, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	_empty = Label.new()
	_empty.text = EMPTY_TEXT
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty.add_theme_color_override("font_color", BWStyle.FAINT)
	_empty.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	v.add_child(_empty)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	v.add_child(_body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_body.add_child(head)
	_icon = BWItemTile.new({}, 68.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draggable = false
	head.add_child(_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_name = _rich(BWStyle.F_SUB)
	hv.add_child(_name)
	_kind = Label.new()
	_kind.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_kind.add_theme_color_override("font_color", BWStyle.LABEL)
	hv.add_child(_kind)
	_infusion = HBoxContainer.new()
	_infusion.add_theme_constant_override("separation", 6)
	hv.add_child(_infusion)
	_body.add_child(HSeparator.new())
	_vs = Label.new()
	_vs.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_vs.add_theme_color_override("font_color", BWStyle.FAINT)
	_vs.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(_vs)
	_stats = GridContainer.new()
	_stats.columns = 3
	_stats.add_theme_constant_override("h_separation", 18)
	_stats.add_theme_constant_override("v_separation", 2)
	_body.add_child(_stats)
	_body.add_child(BWStyle.section_label("Passive"))
	_passive = _rich(BWStyle.F_SMALL - 2)
	_body.add_child(_passive)
	_body.add_child(BWStyle.section_label("Teaches after %d battles worn" % BWRun.LEARN_BATTLES))
	_teach = _rich(BWStyle.F_SMALL - 2)
	_body.add_child(_teach)
	_body.add_child(HSeparator.new())
	_check = _rich(BWStyle.F_SMALL - 2)
	_body.add_child(_check)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_hint.add_theme_color_override("font_color", BWStyle.FAINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(_hint)
	clear()


func _rich(fs: int) -> RichTextLabel:
	var t := BWGlossary.Rich.new()               # D125: terms in the card hover
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.add_theme_font_size_override("normal_font_size", fs)
	t.add_theme_font_size_override("bold_font_size", fs)
	t.add_theme_font_size_override("italics_font_size", fs)
	return t


const EMPTY_TEXT := "Hover or select an item to read it before you equip it."


## The resting state; `text` for this once ("Head: empty ..."), else the default.
func clear(text: String = "") -> void:
	_body.visible = false
	_empty.visible = true
	_empty.text = text if text != "" else EMPTY_TEXT


func showing() -> bool:
	return _body.visible


## Show `item` for `u`. `compare` is what it would replace ({} = an empty
## slot; pass the item itself to show it as worn, without deltas).
## opts: hint (footer line), vs (override the comparison caption),
##       no_check (skip the can-equip line, e.g. a shop item for nobody).
func show_item(item: Dictionary, u: BWUnit, run: BWRun, compare: Dictionary = {}, opts: Dictionary = {}) -> void:
	if item.is_empty():
		clear()
		return
	_body.visible = true
	_empty.visible = false
	_icon.set_item(item)
	var col := BWGearText.readable(BWGearText.item_color(item))
	_name.text = "[b][color=#%s]%s[/color][/b]" % [BWGearText.hex(col), BWGearText.plain_name(item)]
	_kind.text = "%s   ·   Tier %s" % [BWGearText.kind(item), str(item.tier)]
	for c in _infusion.get_children():
		c.queue_free()
	var el := BWGearText.item_element(item)
	_infusion.add_child(BWGearText.Swatch.new(el, 14.0))
	var il := Label.new()
	il.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	il.text = ("%s infusion" % el.capitalize()) if el != "" else "No infusion"
	il.add_theme_color_override("font_color", BWGearText.readable(BWLook.element_color(el)) if el != "" else BWStyle.FAINT)
	_infusion.add_child(il)
	# stats with deltas
	var worn := compare == item
	if opts.has("vs"):
		_vs.text = str(opts.vs)
	elif worn:
		_vs.text = "Worn by %s" % u.name if u else "Worn"
	elif compare.is_empty():
		_vs.text = ("Compared with %s's empty %s slot" % [u.name, BWGearText.SLOT_NAMES.get(str(item.slot), "")]) if u else ""
	else:
		_vs.text = "Compared with %s's %s" % [u.name if u else "the", BWGearText.plain_name(compare)]
	_vs.visible = _vs.text != ""
	for c in _stats.get_children():
		c.queue_free()
	var keys: Array = []
	for s in BWUnit.STATS:
		if item.stats.has(s) or (not worn and compare.get("stats", {}).has(s)):
			keys.append(s)
	for s in keys:
		var v := int(item.stats.get(s, 0))
		var name_l := Label.new()
		name_l.text = BWGearText.STAT_NAMES[s]
		name_l.add_theme_color_override("font_color", BWStyle.LABEL if item.stats.has(s) else BWStyle.FAINT)
		name_l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		_stats.add_child(name_l)
		var val := Label.new()
		val.text = "+%d" % v if item.stats.has(s) else "—"
		val.add_theme_font_size_override("font_size", BWStyle.F_SMALL + 1)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size = Vector2(44, 0)
		_stats.add_child(val)
		var dl := Label.new()
		dl.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
		if worn:
			dl.text = ""
		else:
			var d := v - int(compare.get("stats", {}).get(s, 0))
			if d > 0:
				dl.text = "+%d %s" % [d, s.to_upper()]
				dl.add_theme_color_override("font_color", Color.WHITE)
			elif d < 0:
				dl.text = "%s%d %s" % [BWGearText.MINUS, -d, s.to_upper()]
				dl.add_theme_color_override("font_color", BWStyle.FAINT)
			else:
				dl.text = "±0"
				dl.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		_stats.add_child(dl)
	# passive
	var p := BWGearText.passive_text(item)
	if p == "":
		_passive.text = "[color=#%s]No passive[/color]" % BWGearText.hex(BWStyle.FAINT)
	else:
		_passive.text = "[color=#%s]■[/color] %s" % [BWGearText.hex(col), BWGlossary.markup(p)]
	# teaches
	var t := BWGearText.teaches(item)
	if t.is_empty():
		_teach.text = "[color=#%s]Nothing — weapons teach skills by expertise, not by wearing.[/color]" % BWGearText.hex(BWStyle.FAINT) \
			if str(item.slot) == "main_hand" else "[color=#%s]Nothing[/color]" % BWGearText.hex(BWStyle.FAINT)
	else:
		var lines: PackedStringArray = []
		for a in t:
			var known: bool = u != null and run != null and str(a.id) in run.learned.get(u.id, [])
			var worn_n := int(item.get("worn", {}).get(u.id if u else "", 0))
			var state := " [color=#%s](known)[/color]" % BWGearText.hex(BWStyle.FAINT) if known else \
				(" [color=#%s](%d/%d worn)[/color]" % [BWGearText.hex(BWStyle.FAINT), worn_n, BWRun.LEARN_BATTLES] if worn_n > 0 else "")
			lines.append("[b]%s[/b] [color=#%s]%s[/color]%s — %s" % [a.name, BWGearText.hex(BWStyle.LABEL), str(a.type), state, a.effect_text])
		_teach.text = BWGlossary.markup("\n".join(lines))
	# can equip
	if opts.get("no_check", false) or u == null or run == null:
		_check.visible = false
	else:
		_check.visible = true
		var ck := BWGearText.equip_check(run, u, item)
		_check.text = ("[b]✓[/b]  %s" % ck[1]) if ck[0] else "[color=#%s][b]✕[/b]  %s[/color]" % [BWGearText.hex(BWStyle.TEXT_DIM), ck[1]]
	_hint.text = str(opts.get("hint", ""))
	_hint.visible = _hint.text != ""

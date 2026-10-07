class_name BWItemCard
extends PanelContainer
## The item detail card, read BEFORE committing (equipment, shop, scrolls):
##   name in the element colour, tier badge, kind and infusion
##   stat lines with the delta against what the unit wears in that slot now
##     (+2 in white, −1 dimmed, ±0 faint)
##   the enchantment's passive (its effect_text) or "No passive"; a cursed
##     row (D201) carries the curse mark and spells out its cost
##   the ability it teaches after BWRun.LEARN_BATTLES battles worn
##   for a weapon, its expertise line (anyone can wield it, D180)
## Frame weight (BWStyle.frame_style), the same as the combat unit cards.
## D216: compact, so a C+ weapon (three enchantment lines) or a cursed card
## with its cost fits without scrolling at 1600×900 and 1920×1080: a 52 px
## icon, the imbue on the kind line, the stat deltas on one line, no section
## titles, and the "teaches" block only when the item teaches something.

const W := 420.0
const W_WIDE := 470.0           # the shop's two cards side by side (D216)

var _icon: BWItemTile
var _name: RichTextLabel
var _kind: Label
var _infusion: HBoxContainer
var _vs: Label
var _stats: RichTextLabel       # D216: one line, "STR +5 (+5)   DEX — (−2)"
var _passive: RichTextLabel
var _teach: RichTextLabel
var _teach_title: Label
var _passive_title: Label
var _check: RichTextLabel
var _hint: Label
var _empty: Label
var _body: VBoxContainer


func _init(w: float = W) -> void:
	var sb := BWStyle.frame_style()
	sb.content_margin_top = mini(int(sb.content_margin_top), 8)
	sb.content_margin_bottom = mini(int(sb.content_margin_bottom), 8)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(w, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_empty = Label.new()
	_empty.text = EMPTY_TEXT
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty.add_theme_color_override("font_color", BWStyle.FAINT)
	_empty.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	v.add_child(_empty)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	v.add_child(_body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_body.add_child(head)
	_icon = BWItemTile.new({}, 52.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draggable = false
	head.add_child(_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_name = _rich(BWStyle.F_SUB)
	hv.add_child(_name)
	_kind = Label.new()
	_kind.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_kind.add_theme_color_override("font_color", BWStyle.LABEL)
	var kr := HBoxContainer.new()                # D216: kind and imbue share a line
	kr.add_theme_constant_override("separation", 14)
	hv.add_child(kr)
	kr.add_child(_kind)
	_infusion = HBoxContainer.new()
	_infusion.add_theme_constant_override("separation", 5)
	kr.add_child(_infusion)
	_vs = Label.new()
	_vs.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_vs.add_theme_color_override("font_color", BWStyle.FAINT)
	_vs.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(_vs)
	_stats = _rich(BWStyle.F_SMALL - 1)
	_body.add_child(_stats)
	_passive_title = BWStyle.section_label("Passive")
	_body.add_child(_passive_title)
	_passive = _rich(BWStyle.F_SMALL - 2)
	_body.add_child(_passive)
	_teach_title = BWStyle.section_label(TEACH_TITLE)
	_body.add_child(_teach_title)
	_teach = _rich(BWStyle.F_SMALL - 2)
	_body.add_child(_teach)
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
const TEACH_TITLE := "Teaches after %d battles worn" % BWRun.LEARN_BATTLES


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
	_stats.visible = true
	_passive_title.visible = false               # D216: no section titles; the ■ lines speak
	_teach_title.visible = true
	_icon.set_item(item)
	var col := BWGearText.readable(BWGearText.item_color(item))
	_name.text = "[b][color=#%s]%s[/color][/b]" % [BWGearText.hex(col), BWGearText.plain_name(item)]
	_kind.text = "%s   ·   Tier %s" % [BWGearText.kind(item), str(item.tier)]
	if BWEffects.cursed(BWGearText.enchant(item)):
		_kind.text += "   ·   %s cursed" % BWRun.CURSE_MARK       # D201: the cost is spelled out under Passive
	for c in _infusion.get_children():
		c.queue_free()
	var el := BWGearText.item_element(item)
	_infusion.add_child(BWGearText.Swatch.new(el, 14.0))
	var il := Label.new()
	il.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	var weapon := str(item.slot) == "main_hand"
	if weapon:                                   # D182: a weapon's element is its imbue
		il.text = ("Imbued with %s" % el.capitalize()) if el != "" else "No imbue (tiers C and up carry one)"
	else:
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
	var keys: Array = []
	for s in BWUnit.STATS:
		if item.stats.has(s) or (not worn and compare.get("stats", {}).has(s)):
			keys.append(s)
	var segs: PackedStringArray = []                # D216: the deltas on one line
	for s in keys:
		var v := int(item.stats.get(s, 0))
		var has: bool = item.stats.has(s)
		var seg := "[color=#%s]%s[/color] [b]%s[/b]" % [BWGearText.hex(BWStyle.LABEL if has else BWStyle.FAINT), s.to_upper(),
			("+%d" % v) if has else "—"]
		if not worn:
			var d := v - int(compare.get("stats", {}).get(s, 0))
			if d > 0:
				seg += " [color=#ffffff](+%d)[/color]" % d
			elif d < 0:
				seg += " [color=#%s](%s%d)[/color]" % [BWGearText.hex(BWStyle.FAINT), BWGearText.MINUS, -d]
			else:
				seg += " [color=#ffffff4d](±0)[/color]"
		segs.append(seg)
	_stats.text = "   ".join(segs)
	_stats.visible = not segs.is_empty()
	# passive
	var p := BWGearText.passive_text(item)
	if p == "":
		_passive.text = "[color=#%s]No passive[/color]" % BWGearText.hex(BWStyle.FAINT)
	else:
		_passive.text = "[color=#%s]■[/color] %s" % [BWGearText.hex(col if not weapon else BWStyle.TEXT), BWGlossary.markup(p)]
	_passive.text += curse_line(BWGearText.enchant(item))       # D201
	if weapon and el != "":                      # D182: the imbue is the weapon's second enchantment
		var ec := BWGearText.hex(BWGearText.readable(BWLook.element_color(el)))
		_passive.text += "\n[color=#%s]■ Imbued with %s:[/color] basic attacks carry %s and paint it on the target's hex, hit or miss." % [ec, el.capitalize(), el]
		var ie := BWData.row("enchantments", str(item.get("imbue_enchant", "")))
		if not ie.is_empty():                    # D206: the imbue's own element enchantment (while drawn)
			_passive.text += "\n[color=#%s]■ %s imbue · %s:[/color] %s%s" % [ec, el.capitalize(), BWGearText.row_name(ie),
				BWGlossary.markup(str(ie.get("effect_text", ""))), curse_line(ie)]
	# D282: one dim set line ("Set: Fire 2/3 · next: Flashpoint"); a loose or
	# shop piece counts as if equipped ("Fire → 2/3"); the carried weapon counts
	# only once drawn.
	var setl := ""
	if u != null and weapon and u.equipment.get(BWUnit.SECOND, {}).get("uid", "-") == item.get("uid", "?"):
		setl = ("Set: %s · counts when drawn" % el.capitalize()) if el != "" else ""
	else:
		setl = BWSets.card_line(item, u, u != null and not worn)
	if setl != "":
		_passive.text += "\n[color=#%s]%s[/color]" % [BWGearText.hex(BWStyle.FAINT), setl]
	# teaches (D216: collapsed when there's nothing to teach)
	var t := BWGearText.teaches(item)
	_teach_title.visible = not t.is_empty()
	_teach.visible = not t.is_empty()
	if not t.is_empty():
		var lines: PackedStringArray = []
		for a in t:
			var known: bool = u != null and run != null and str(a.id) in run.learned.get(u.id, [])
			var worn_n := int(item.get("worn", {}).get(u.id if u else "", 0))
			var state := " [color=#%s](known)[/color]" % BWGearText.hex(BWStyle.FAINT) if known else (" [color=#%s](%d/%d worn)[/color]" % [BWGearText.hex(BWStyle.FAINT), worn_n, BWRun.LEARN_BATTLES] if worn_n > 0 else "")
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


## D201: a cursed row's cost, spelled out under its passive ("" when not cursed).
static func curse_line(row: Dictionary) -> String:
	if row.is_empty() or not BWEffects.cursed(row):
		return ""
	return "\n[b]%s Cursed:[/b] %s" % [BWRun.CURSE_MARK, BWGlossary.markup(str(row.get("cost_text", "")))]


## D203: an imbuement scroll (BWRun.scrolls): its element, the row it holds,
## what it does to armour and to a weapon, and its price. opts: hint, pay
## (the loose items picked so far).
func show_scroll(s: Dictionary, opts: Dictionary = {}) -> void:
	if s.is_empty():
		clear()
		return
	_body.visible = true
	_empty.visible = false
	_icon.set_item(s)
	var el := str(s.get("element", ""))
	var row := BWData.row("enchantments", str(s.get("enchant", "")))
	var col := BWGearText.readable(BWLook.element_color(el))
	var cursed := BWEffects.cursed(row)
	_name.text = "[b][color=#%s]Scroll of %s%s[/color][/b]" % [BWGearText.hex(col), el.capitalize(), (" " + BWRun.CURSE_MARK) if cursed else ""]
	_kind.text = "Imbuement scroll   ·   Tier %s" % str(s.get("tier", "E"))
	for c in _infusion.get_children():
		c.queue_free()
	_infusion.add_child(BWGearText.Swatch.new(el, 14.0))
	var il := Label.new()
	il.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	il.text = "%s · %s" % [el.capitalize(), BWGearText.row_name(row)]
	il.add_theme_color_override("font_color", col)
	_infusion.add_child(il)
	var pay: Array = opts.get("pay", [])
	_vs.text = "" if pay.is_empty() else "Paying with: %s" % ", ".join(pay.map(func(it): return BWGearText.plain_name(it)))
	_vs.visible = _vs.text != ""
	_stats.visible = false
	_passive_title.visible = false               # the scroll card is tighter: no section titles
	_passive.text = "[color=#%s]■[/color] [b]%s[/b]: %s%s" % [BWGearText.hex(col), BWGearText.row_name(row),
		BWGlossary.markup(str(row.get("effect_text", ""))), curse_line(row)]
	_teach_title.visible = false
	_teach.visible = true
	_teach.text = BWGlossary.markup("[b]Armour:[/b] replaces its enchantment.  [b]Weapon:[/b] imbues it with %s and this enchantment (its own enchantment stays)." % el.capitalize())
	_check.visible = false
	_hint.text = str(opts.get("hint", ""))
	_hint.visible = _hint.text != ""

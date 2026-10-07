class_name BWShopPanel
extends PanelContainer
## The shop (D203), Baldur's Gate style, in one frame:
##   FEATURED   seven imbuement scrolls, one per element (BWRun.scrolls),
##              re-rolled after every battle. Each holds one element row.
##   Trade      pick yours → pick theirs (1 head, 1 chest, 1 legs, 2 weapons
##              at the current tier) → the comparison → Confirm trade
##              (BWRun.trade: 1-for-1, loose items only)
##   Scroll     click a scroll → pick the item it goes on (worn on the left,
##              loose on the right) → the scroll and the item after →
##              Use scroll (BWRun.use_scroll). Free since D236 (author,
##              playtest 1); it's spent until the next battle. Armour: the enchantment is
##              overwritten. A weapon: it takes the scroll's element and row as
##              its imbue (D206); its own enchantment stays.
## Re-imbue (D38/D183) is gone (D202). Hover any tile for its card.
## `unit` (the screen's selected unit) is who the cards compare against.
## D235: the grids sort by BWInvSort (Newest / Element / Slot / Tier, the
## header's buttons, shared with the gear panel for the session). D234: items
## set aside to throw away (BWRun.trash) aren't loose, so never offered here.

signal changed
signal closed

var run: BWRun
var unit: BWUnit
var mode := "trade"               # trade | scroll
var mine: Dictionary = {}         # trade: yours
var theirs: Dictionary = {}       # trade: theirs / scroll: the item it goes on
var scroll: Dictionary = {}       # scroll: the chosen scroll
var _sort_btns := {}              # D235
var _title: Label
var _scroll_row: HBoxContainer
var _feat_reason: Label            ## D380: "Featured: completes Will's Wind set"
var _left_title: Label
var _right_title: Label
var _left: GridContainer
var _right: GridContainer
var _card_a: BWItemCard
var _card_b: BWItemCard
var _arrow: Label
var _status: Label
var _confirm: Button
var _back: Button


func _init(p_run: BWRun) -> void:
	run = p_run
	add_theme_stylebox_override("panel", BWStyle.box_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", BWStyle.F_NAME - 6)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_title)
	var sl := Label.new()                       # ---- D235: sort
	sl.text = "Sort"
	sl.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	sl.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	hb.add_child(sl)
	for m in BWInvSort.MODES:
		var sb := Button.new()
		sb.text = BWInvSort.LABELS[m]
		sb.name = "sort_" + m
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
		sb.pressed.connect(func(): set_sort(m))
		hb.add_child(sb)
		_sort_btns[m] = sb
	_back = Button.new()
	_back.text = "Back to trading"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func(): set_mode("trade"))
	hb.add_child(_back)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): closed.emit())
	hb.add_child(close)
	# featured: the seven scrolls
	var feat := HBoxContainer.new()
	feat.add_theme_constant_override("separation", 14)
	v.add_child(feat)
	var fl := BWStyle.section_label("Featured
imbuement scrolls")
	fl.tooltip_text = "One per element, free, new ones after every battle."
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	feat.add_child(fl)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	feat.add_child(mid)
	_scroll_row = HBoxContainer.new()
	_scroll_row.add_theme_constant_override("separation", 8)
	mid.add_child(_scroll_row)
	_feat_reason = Label.new()                       # D380: why the featured one
	_feat_reason.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_feat_reason.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	mid.add_child(_feat_reason)
	var fn := Label.new()
	fn.text = "one per element · free
new scrolls after every battle"
	fn.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	fn.add_theme_color_override("font_color", BWStyle.FAINT)
	fn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	feat.add_child(fn)
	# two grids
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 40)
	v.add_child(grids)
	var lv := VBoxContainer.new()
	grids.add_child(lv)
	_left_title = BWStyle.section_label("")
	lv.add_child(_left_title)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size = Vector2(BWItemCard.W + 20, 148)      # D216: two rows of tiles, no spare
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(ls)
	_left = _grid()
	ls.add_child(_left)
	var rv := VBoxContainer.new()
	grids.add_child(rv)
	_right_title = BWStyle.section_label("")
	rv.add_child(_right_title)
	var rsc := ScrollContainer.new()
	rsc.custom_minimum_size = Vector2(BWItemCard.W + 20, 148)
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(rsc)
	_right = _grid()
	rsc.add_child(_right)
	v.add_child(HSeparator.new())
	# comparison
	var cs := ScrollContainer.new()
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cs)
	var cmp := HBoxContainer.new()
	cmp.add_theme_constant_override("separation", 10)
	cs.add_child(cmp)
	_card_a = BWItemCard.new(BWItemCard.W_WIDE)        # D216: wide, so a full card fits unscrolled
	cmp.add_child(_card_a)
	_arrow = Label.new()
	_arrow.text = "⇄"
	_arrow.add_theme_font_size_override("font_size", 40)
	_arrow.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arrow.custom_minimum_size = Vector2(46, 0)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cmp.add_child(_arrow)
	_card_b = BWItemCard.new(BWItemCard.W_WIDE)
	cmp.add_child(_card_b)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	foot.add_child(_status)
	_confirm = Button.new()
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.custom_minimum_size = Vector2(220, 46)
	_confirm.pressed.connect(_on_confirm)
	foot.add_child(_confirm)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g


func open(u: BWUnit) -> void:
	unit = u
	mine = {}
	theirs = {}
	if mode == "scroll" and (scroll.is_empty() or scroll.get("sold", false)):
		mode = "trade"
	refresh()


## D235: the grids' order (shared with the gear panel for the session).
func set_sort(m: String) -> void:
	BWInvSort.set_mode(m)
	refresh()


func set_mode(m: String) -> void:
	mode = m
	mine = {}
	theirs = {}
	if m == "trade":
		scroll = {}
	refresh()


## Click a scroll: buy-and-use flow for it (click it again to go back).
func pick_scroll(s: Dictionary) -> void:
	if s.get("sold", false):
		return
	if scroll == s and mode == "scroll":
		set_mode("trade")
		return
	scroll = s
	set_mode("scroll")


func refresh() -> void:
	_fill_scrolls()
	_back.visible = mode == "scroll"
	if not mine.is_empty() and not (mine in run.inventory):
		mine = {}
	for m in _sort_btns:
		_sort_btns[m].button_pressed = m == BWInvSort.mode
	if mode == "trade":
		_title.text = "Shop — tier %s stock" % run.tier_for(run.fight)
		if not theirs.is_empty() and not theirs in run.shop:
			theirs = {}
		_left_title.text = "1 · YOURS — loose items (%d)" % run.inventory.size()
		_right_title.text = "2 · THEIRS — 1 head, 1 chest, 1 legs, 2 weapons"
		_fill(_left, BWInvSort.sorted(run.inventory), func(it): return it == mine, func(it): _pick_mine(it), "Nothing loose to trade. Unequip something first (Equipment).")
		_fill(_right, BWInvSort.sorted(run.shop), func(it): return it == theirs, func(it): _on_shop_item_selected(it), "The shop is empty.")
		_arrow.text = "⇄"
		_confirm.text = "Confirm trade"
	else:
		_title.text = "Scroll of %s — free, imbue 1" % str(scroll.element).capitalize()
		var worn := _worn_items()
		if not theirs.is_empty() and not theirs in worn and not theirs in run.inventory:
			theirs = {}
		_left_title.text = "USE IT ON — worn by the squad (%d)" % worn.size()
		_right_title.text = "OR — loose (%d)" % run.inventory.size()
		_fill(_left, BWInvSort.sorted(worn), func(it): return it == theirs, _pick_target, "Nobody wears anything.")
		_fill(_right, BWInvSort.sorted(run.inventory), func(it): return it == theirs, _pick_target, "Nothing loose.")
		_arrow.text = "→"
		_confirm.text = "Use scroll"
	_cards()


func _fill_scrolls() -> void:
	for c in _scroll_row.get_children():
		c.queue_free()
	var feat := run.featured_scroll()            # D380: one scroll marked for this squad
	_feat_reason.text = str(feat.get("reason", ""))
	for s in run.scrolls:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var tag := Label.new()
		tag.text = "FEATURED" if not feat.is_empty() and feat.scroll == s else " "
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 4)
		tag.add_theme_color_override("font_color", BWStyle.TEXT)
		box.add_child(tag)
		var t := BWItemTile.new(s, 60.0)
		t.draggable = false
		t.source = "shop"
		t.selected = mode == "scroll" and s == scroll
		t.blocked = s.get("sold", false)
		t.picked.connect(func(tile): pick_scroll(tile.item))
		t.hovered.connect(func(tile): _hover_scroll(tile.item))
		t.unhovered.connect(func(_tile): _cards())
		box.add_child(t)
		_scroll_row.add_child(box)


## Every item the squad wears or carries (D180: the second weapon too).
func _worn_items() -> Array:
	var out: Array = []
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			if u.equipment.has(slot):
				out.append(u.equipment[slot])
	return out


## Scroll mode: the item the scroll goes on (click again to clear).
func _pick_target(it: Dictionary) -> void:
	theirs = it if theirs != it else {}
	refresh()


func _fill(g: GridContainer, items: Array, is_sel: Callable, on_pick: Callable, empty_text: String) -> void:
	for c in g.get_children():
		c.queue_free()
	if items.is_empty():
		var l := Label.new()
		l.text = empty_text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(BWItemCard.W, 0)
		l.add_theme_color_override("font_color", BWStyle.FAINT)
		l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		g.add_child(l)
		return
	for it in items:
		var t := BWItemTile.new(it, 70.0)
		t.draggable = false
		t.selected = is_sel.call(it)
		t.picked.connect(func(tile): on_pick.call(tile.item))
		t.hovered.connect(func(tile): _hover(tile.item, g == _left))
		t.unhovered.connect(func(_tile): _cards())
		g.add_child(t)


func _pick_mine(it: Dictionary) -> void:
	mine = it if mine != it else {}
	refresh()


## Hover is the read (the author's 10/4 note): any tile shows its full card at
## once; click is the pick. Selecting a shop item makes it "theirs"; once both
## sides are picked the cards show the give/get comparison and Confirm unlocks.
func _on_shop_item_selected(it: Dictionary) -> void:
	theirs = it if theirs != it else {}
	refresh()


## Hover reads an item the way the equipment view does: against what the
## selected unit wears in that slot, with the can-equip line.
func _hover(it: Dictionary, left: bool) -> void:
	var c := _card_a if left else _card_b
	var hint := "Click to pick it for the trade."
	if mode == "scroll":
		hint = "Click to put the scroll on it."
	c.show_item(it, unit, run, _worn_cmp(it), { "vs": _vs_line(it), "no_check": mode == "scroll", "hint": hint })


func _hover_scroll(s: Dictionary) -> void:
	_card_b.show_scroll(s)
	if s.get("sold", false):
		_status.text = "Sold — a new scroll comes after the next battle."
	else:
		_status.text = "Scroll of %s: free. Click it, then the item it goes on." % str(s.element).capitalize()


func _worn_cmp(it: Dictionary) -> Dictionary:
	if unit == null:
		return {}
	return unit.equipment.get(str(it.slot), {})


func _vs_line(it: Dictionary) -> String:
	var who := run.owner_of(it)
	if who != null and unit != null and who != unit:
		return "Worn by %s" % who.name
	if unit == null:
		return ""
	var w: Dictionary = unit.equipment.get(str(it.slot), {})
	if w == it:
		return "Worn by %s" % unit.name
	return ("Compared with %s's %s" % [unit.name, BWGearText.plain_name(w)]) if not w.is_empty() else \
		"Compared with %s's empty %s slot" % [unit.name, BWGearText.SLOT_NAMES[str(it.slot)].to_lower()]


func _cards() -> void:
	if mode == "trade":
		if mine.is_empty():
			_card_a.clear("1 · Pick one of your loose items to give. Or click a scroll above to buy it.")
		else:
			_card_a.show_item(mine, unit, run, mine, { "vs": "You give", "no_check": true })
		if theirs.is_empty():
			_card_b.clear("2 · Pick an item from their stock.")
		elif mine.is_empty():
			_card_b.show_item(theirs, unit, run, _worn_cmp(theirs), { "vs": _vs_line(theirs) })
		elif str(mine.slot) == str(theirs.slot):
			_card_b.show_item(theirs, unit, run, mine, { "vs": "You get — compared with what you give" })
		else:
			_card_b.show_item(theirs, unit, run, _worn_cmp(theirs), { "vs": "You get (another slot). " + _vs_line(theirs) })
		var both := not mine.is_empty() and not theirs.is_empty()
		_confirm.disabled = not both
		_status.text = ("Trade %s for %s. One for one; it lands in your inventory." % [BWGearText.plain_name(mine), BWGearText.plain_name(theirs)]) \
			if both else "Pick yours, then theirs, then confirm."
		return
	_card_a.show_scroll(scroll)
	if theirs.is_empty():
		_card_b.clear("2 · Pick the item the scroll goes on. Armour: its enchantment is replaced. A weapon: it takes the scroll's element and enchantment as its imbue.")
	else:
		var after := theirs.duplicate(true)
		BWRun.apply_scroll(scroll, after)
		var who := run.owner_of(theirs)
		_card_b.show_item(after, unit, run, after, { "no_check": true, "vs": "After the scroll%s — was %s" % [
			" (worn by %s)" % who.name if who else "", BWGearText.plain_name(theirs)] })
	var ok := run.can_use_scroll(scroll, theirs)
	_confirm.disabled = not ok
	if ok:
		_status.text = "Use the Scroll of %s on %s. Free; the scroll is gone until the next battle." % [
			str(scroll.element).capitalize(), BWGearText.plain_name(theirs)]
	else:
		_status.text = "Pick the item the scroll goes on, worn or loose. It's free."


func _on_confirm() -> void:
	var ok := false
	if mode == "trade":
		ok = run.trade(mine, theirs)
		if ok:
			_status.text = "Traded."
	else:
		ok = run.use_scroll(scroll, theirs)
		if ok:
			mode = "trade"
			scroll = {}
	if ok:
		mine = {}
		theirs = {}
		refresh()
		changed.emit()

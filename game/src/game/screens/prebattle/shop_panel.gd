class_name BWShopPanel
extends PanelContainer
## The shop, Baldur's Gate style: the stock as a grid of item tiles (icon,
## element border, tier), the same BWItemCard as the equipment view, and
## two flows in the same frame:
##   Trade      pick yours → pick theirs → the comparison (what you give,
##              what you get, deltas between them) → Confirm trade
##              (BWRun.trade: 1-for-1, loose items only)
##   Re-imbue   pick the item that gives up its enchantment → pick where it
##              goes (BWRun.can_reimbue) → before/after cards → Confirm
## `unit` (the screen's selected unit) is who the cards compare against
## until both sides of a trade are picked.

signal changed
signal closed

var run: BWRun
var unit: BWUnit
var mode := "trade"
var mine: Dictionary = {}         # trade: yours / re-imbue: the source
var theirs: Dictionary = {}       # trade: theirs / re-imbue: the target
var _title: Label
var _mode_btns := {}
var _left_title: Label
var _right_title: Label
var _left: GridContainer
var _right: GridContainer
var _card_a: BWItemCard
var _card_b: BWItemCard
var _arrow: Label
var _status: Label
var _confirm: Button


func _init(p_run: BWRun) -> void:
	run = p_run
	add_theme_stylebox_override("panel", BWStyle.box_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", BWStyle.F_NAME - 6)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_title)
	for m in [["trade", "Trade"], ["reimbue", "Re-imbue"]]:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_mode(m[0]))
		hb.add_child(b)
		_mode_btns[m[0]] = b
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): closed.emit())
	hb.add_child(close)
	# two grids
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 40)
	v.add_child(grids)
	var lv := VBoxContainer.new()
	grids.add_child(lv)
	_left_title = BWStyle.section_label("")
	lv.add_child(_left_title)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size = Vector2(BWItemCard.W + 20, 176)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(ls)
	_left = _grid()
	ls.add_child(_left)
	var rv := VBoxContainer.new()
	grids.add_child(rv)
	_right_title = BWStyle.section_label("")
	rv.add_child(_right_title)
	var rsc := ScrollContainer.new()
	rsc.custom_minimum_size = Vector2(BWItemCard.W + 20, 176)
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
	_card_a = BWItemCard.new()
	cmp.add_child(_card_a)
	_arrow = Label.new()
	_arrow.text = "⇄"
	_arrow.add_theme_font_size_override("font_size", 40)
	_arrow.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arrow.custom_minimum_size = Vector2(46, 0)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cmp.add_child(_arrow)
	_card_b = BWItemCard.new()
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
	refresh()


func set_mode(m: String) -> void:
	mode = m
	mine = {}
	theirs = {}
	refresh()


func refresh() -> void:
	for k in _mode_btns:
		_mode_btns[k].button_pressed = k == mode
	if not mine.is_empty() and not (mine in run.inventory):
		mine = {}
	if mode == "trade":
		_title.text = "Shop — tier %s stock" % run.tier_for(run.fight)
		if not theirs.is_empty() and not theirs in run.shop:
			theirs = {}
		_left_title.text = "1 · YOURS — loose items (%d)" % run.inventory.size()
		_right_title.text = "2 · THEIRS — %d in stock" % run.shop.size()
		_fill(_left, run.inventory, mine, func(it): _pick_mine(it), "Nothing loose to trade. Unequip something first (Equipment).")
		_fill(_right, run.shop, theirs, func(it): _on_shop_item_selected(it), "The shop is empty.")
		_arrow.text = "⇄"
		_confirm.text = "Confirm trade"
	else:
		_title.text = "Re-imbue — move an enchantment"
		var sources := run.inventory.filter(func(it): return str(it.get("enchant", "")) != "")
		var targets: Array = _all_items().filter(func(it): return mine.is_empty() or BWRun.can_reimbue(mine, it))
		if not theirs.is_empty() and not theirs in targets:
			theirs = {}
		_left_title.text = "1 · TAKE THE ENCHANTMENT FROM… (loose, enchanted)"
		_right_title.text = "2 · …AND PUT IT ON" + ("" if not mine.is_empty() else " (pick a source first)")
		_fill(_left, sources, mine, func(it): _pick_mine(it), "No loose enchanted items. Unequip one to use its enchantment.")
		_fill(_right, targets, theirs, func(it): theirs = it if theirs != it else {}; refresh(),
			"Nothing can take that enchantment (weapon enchantments only fit the weapons they list).")
		_arrow.text = "→"
		_confirm.text = "Confirm re-imbue"
	_cards()


## Every item the run holds: worn by the squad, then loose.
func _all_items() -> Array:
	var out: Array = []
	for u in run.squad:
		for slot in BWRun.SLOTS:
			if u.equipment.has(slot):
				out.append(u.equipment[slot])
	out.append_array(run.inventory)
	return out


func _owner_of(it: Dictionary) -> BWUnit:
	for u in run.squad:
		for slot in BWRun.SLOTS:
			if u.equipment.get(slot, {}) == it:
				return u
	return null


func _fill(g: GridContainer, items: Array, sel: Dictionary, on_pick: Callable, empty_text: String) -> void:
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
		var t := BWItemTile.new(it, 80.0)
		t.draggable = false
		t.selected = it == sel
		t.picked.connect(func(tile): on_pick.call(tile.item))
		t.hovered.connect(func(tile): _hover(tile.item, g == _left))
		t.unhovered.connect(func(_tile): _cards())
		g.add_child(t)


func _pick_mine(it: Dictionary) -> void:
	mine = it if mine != it else {}
	if mode == "reimbue":
		theirs = {}
	refresh()


## ── HOOK: "upon selection…" (filled 10/4) ──────────────────────────────
## The author's shop note stopped at "…then upon selection". Clarified:
## "previously when hovering over an equipped item it would show me the item
## details, do that for the shoppe." So HOVER is the read: hovering any shop
## tile, or any of your own tiles, shows the full item card at once (name in
## its element colour, stat deltas against what the selected unit wears in
## that slot, the passive or "No passive", what it teaches, whether the
## selected unit can equip it) — see _hover(). CLICK is the trade pick:
## selecting a shop item makes it the "theirs" side; once both sides are
## picked the cards show the give/get comparison and Confirm unlocks.
func _on_shop_item_selected(it: Dictionary) -> void:
	theirs = it if theirs != it else {}
	refresh()


## Hover reads an item the way the equipment view does: against what the
## selected unit wears in that slot, with the can-equip line.
func _hover(it: Dictionary, left: bool) -> void:
	var c := _card_a if left else _card_b
	c.show_item(it, unit, run, _worn_cmp(it), { "vs": _vs_line(it), "no_check": mode == "reimbue",
		"hint": "Click to pick it for the trade." if mode == "trade" else "Click to pick it." })


func _worn_cmp(it: Dictionary) -> Dictionary:
	if unit == null:
		return {}
	return unit.equipment.get(str(it.slot), {})


func _vs_line(it: Dictionary) -> String:
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
			_card_a.clear("1 · Pick one of your loose items to give.")
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
	else:
		if mine.is_empty():
			_card_a.clear("1 · Pick a loose item whose enchantment you want to move. It becomes plain.")
		else:
			var after := mine.duplicate(true)
			after.enchant = ""
			_card_a.show_item(after, unit, run, after, { "vs": "Source after — %s gives up its enchantment" % BWGearText.plain_name(mine), "no_check": true })
		if theirs.is_empty():
			_card_b.clear("2 · Pick the item that takes it (any of the squad's gear, worn or loose).")
		else:
			var after2 := theirs.duplicate(true)
			after2.enchant = mine.enchant
			var who := _owner_of(theirs)
			_card_b.show_item(after2, unit, run, after2, { "vs": "Target after%s — was %s" % [
				" (worn by %s)" % who.name if who else "", BWGearText.plain_name(theirs)], "no_check": true })
		var both := not mine.is_empty() and not theirs.is_empty()
		_confirm.disabled = not both
		_status.text = "Moves the enchantment; the source keeps its stats. Armour enchantments move between armour; weapon ones only to the weapons they list." \
			if not both else "Move %s's enchantment onto %s." % [BWGearText.plain_name(mine), BWGearText.plain_name(theirs)]


func _on_confirm() -> void:
	var ok := false
	if mode == "trade":
		ok = run.trade(mine, theirs)
		if ok:
			_status.text = "Traded."
	else:
		ok = run.reimbue(mine, theirs)
	if ok:
		mine = {}
		theirs = {}
		refresh()
		changed.emit()

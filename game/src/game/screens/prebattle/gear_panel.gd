class_name BWGearPanel
extends PanelContainer
## The equipment view: a paperdoll (the unit's live 3D model with Head,
## Chest, Legs, Main hand and Second weapon slot boxes around it, D180), the inventory as a grid
## of item tiles, and the item card that reads an item BEFORE you equip it.
##
##   hover a tile / slot     its card (deltas against what's worn there)
##   click a tile            select it; the model tries it on (preview only)
##   double-click a tile     equip it          drag a tile onto a slot: equip
##   double-click a slot     take it off       drag a slot onto the grid: take off
## Abilities (one per type) are chosen under the model.
## Emits `changed` after any real change, so the screen re-reads the unit.
## Used by the pre-battle screen and by the hall's prep (BWPrepScreen, D84).
##   add_header(control)     a screen's own controls in the header (unit steppers)
##   give_enabled = true     moving gear between units: a picked inventory item
##                           shows "Equip on: <unit> …"; a picked worn piece shows
##                           "Give to: <unit> …" (it comes off and onto them)
## D234 the discard pile under the grid (BWRun.trash): drag a loose (or worn)
## piece onto it, or pick one and press Discard; drag it back to the grid or
## double-click it to keep it. Everything there is thrown away when the battle
## starts (BWGame.go_combat -> BWRun.empty_trash).
## D235 the grid sorts by BWInvSort (Newest / Element / Slot / Tier), the
## filters stay; the order is shared with the shop for the session.

signal changed
signal closed

var run: BWRun
var unit: BWUnit
var doll: BWPaperdoll
var card: BWItemCard
var _slots := {}                  # slot -> BWItemTile
var _grid: GridContainer
var _filter := ""
var _filter_btns := {}
var _sel: Dictionary = {}
var _title: Label
var _inv_title: Label
var _msg: Label
var _abil: VBoxContainer
var _skills: HFlowContainer          # D89: the weapon-skill loadout
var _skills_title: Label
var _header: HBoxContainer
var _give_box: HBoxContainer
var _give_flow: HFlowContainer
var _give_label: Label
var _swap_btn: Button              # D180
var _sort_btns := {}               # D235
var _trash_box: PanelContainer     # D234
var _trash_row: HBoxContainer
var _trash_title: Label
var _trash_btn: Button
## The hall's prep (D84): hand gear between units in one click.
var give_enabled := false


func _init(p_run: BWRun) -> void:
	run = p_run
	add_theme_stylebox_override("panel", BWStyle.box_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	# header
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)
	_header = hb
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", BWStyle.F_NAME - 6)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_title)
	for f in [["", "All"], ["head", "Head"], ["chest", "Chest"], ["legs", "Legs"], ["main_hand", "Weapons"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		b.pressed.connect(func(): _filter = f[0]; _fill_grid())
		hb.add_child(b)
		_filter_btns[f[0]] = b
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): closed.emit())
	hb.add_child(close)
	# body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	v.add_child(body)
	# -- doll column
	var dc := VBoxContainer.new()
	dc.add_theme_constant_override("separation", 8)
	body.add_child(dc)
	var dollrow := HBoxContainer.new()
	dollrow.add_theme_constant_override("separation", 10)
	dc.add_child(dollrow)
	var ls := VBoxContainer.new()
	ls.add_theme_constant_override("separation", 16)   # D229 (L-22): was 34; the doll is shorter
	ls.alignment = BoxContainer.ALIGNMENT_CENTER
	dollrow.add_child(ls)
	var frame := PanelContainer.new()
	var fs := BWStyle.column_style()
	fs.bg_color = Color(1, 1, 1, 0.045)
	fs.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", fs)
	dollrow.add_child(frame)
	doll = BWPaperdoll.new()
	doll.custom_minimum_size = Vector2(330, 372)       # D229 (L-22): 440 ran the skill rows off a 16:9 screen
	frame.add_child(doll)
	var rs := VBoxContainer.new()
	rs.add_theme_constant_override("separation", 34)
	rs.alignment = BoxContainer.ALIGNMENT_CENTER
	dollrow.add_child(rs)
	rs.add_theme_constant_override("separation", 10)
	for slot in BWRun.GEAR_SLOTS:
		var t := BWItemTile.new({}, 88.0)
		t.custom_minimum_size = Vector2(88, 88 + 24)
		t.slot = slot
		t.source = "slot"
		t.caption = BWGearText.SLOT_NAMES[slot]
		t.accept = _accepts_for(slot)
		t.on_drop = func(it: Dictionary): _equip(it, slot)
		t.hovered.connect(_hover_slot)
		t.unhovered.connect(_unhover)
		t.picked.connect(func(tile): _hover_slot(tile); _show_give(tile.item, tile.slot))
		t.activated.connect(func(tile): _unequip(tile.slot))
		t.name = "slot_" + slot
		_slots[slot] = t
		(rs if slot in ["main_hand", "second"] else ls).add_child(t)
		if slot == "main_hand":
			# D180: trade the two weapons (the same free swap combat offers)
			_swap_btn = Button.new()
			_swap_btn.name = "swap_weapons"
			_swap_btn.text = "Swap"
			_swap_btn.focus_mode = Control.FOCUS_NONE
			_swap_btn.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
			_swap_btn.tooltip_text = "Draw the second weapon and carry the one in hand.\nIn battle: Swap weapon, under Attack (free, as often as you like)."
			_swap_btn.pressed.connect(_swap)
			rs.add_child(_swap_btn)
	doll.tooltip_text = "Drag to turn the model. Double-click a slot to take it off."
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_msg.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	_msg.custom_minimum_size = Vector2(500, 0)
	dc.add_child(_msg)
	_give_box = HBoxContainer.new()
	_give_box.add_theme_constant_override("separation", 8)
	_give_box.visible = false
	dc.add_child(_give_box)
	_give_label = BWStyle.section_label("Give to")
	_give_box.add_child(_give_label)
	_give_flow = HFlowContainer.new()
	_give_flow.custom_minimum_size = Vector2(420, 0)
	_give_flow.add_theme_constant_override("h_separation", 6)
	_give_flow.add_theme_constant_override("v_separation", 6)
	_give_box.add_child(_give_flow)
	dc.add_child(BWStyle.section_label("Abilities — one of each type"))
	_abil = VBoxContainer.new()
	_abil.add_theme_constant_override("separation", 4)
	_abil.custom_minimum_size = Vector2(500, 0)
	dc.add_child(_abil)
	_skills_title = BWStyle.section_label("Skills")
	dc.add_child(_skills_title)
	_skills = HFlowContainer.new()
	_skills.add_theme_constant_override("h_separation", 6)
	_skills.add_theme_constant_override("v_separation", 6)
	_skills.custom_minimum_size = Vector2(500, 0)
	dc.add_child(_skills)
	# -- inventory column
	var ic := VBoxContainer.new()
	ic.add_theme_constant_override("separation", 8)
	body.add_child(ic)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 4)
	ic.add_child(ih)
	_inv_title = BWStyle.section_label("Inventory")
	_inv_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(_inv_title)
	for m in BWInvSort.MODES:                          # ---- D235: sort
		var sb := Button.new()
		sb.text = BWInvSort.LABELS[m]
		sb.name = "sort_" + m
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.tooltip_text = "Sort the inventory by %s" % BWInvSort.LABELS[m].to_lower()
		sb.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 4)
		sb.custom_minimum_size = Vector2(0, 26)
		sb.pressed.connect(func(): set_sort(m))
		ih.add_child(sb)
		_sort_btns[m] = sb
	var sc := _GridDrop.new()
	sc.panel = self
	sc.custom_minimum_size = Vector2(BWItemCard.W + 8, 178)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ic.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(_grid)
	ic.add_child(_build_trash())                       # ---- D234
	ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cs := ScrollContainer.new()
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ic.add_child(cs)
	card = BWItemCard.new()
	cs.add_child(card)


## Put a screen's own control in the header, after the title (index 1).
## The panel owns its icon dependency: whichever screen hosts it (pre-battle,
## the hall's prep), the shared renderer must exist, or every tile falls back
## to its slot glyph (seen in the hall prep, 2026-10-05).
func _enter_tree() -> void:
	BWItemIcons.ensure(self)


func add_header(c: Control, at: int = 1) -> void:
	_header.add_child(c)
	_header.move_child(c, at)


func set_unit(u: BWUnit) -> void:
	unit = u
	_sel = {}
	_show_give({}, "")
	_msg.text = "Drag an item onto a slot, or double-click it, to equip."
	doll.set_unit(u)
	refresh()


func refresh() -> void:
	if unit == null:
		return
	_title.text = "Equipment — %s" % unit.name
	for slot in _slots:
		var t: BWItemTile = _slots[slot]
		t.set_item(unit.equipment.get(slot, {}))
		t.draggable = slot != "main_hand"
	_swap_btn.disabled = unit.second_weapon().is_empty()
	for f in _filter_btns:
		_filter_btns[f].button_pressed = f == _filter
	_fill_grid()
	_fill_abilities()
	_fill_skills()
	if _sel.is_empty():
		card.clear()
	elif not _sel in run.inventory:
		_sel = {}
		card.clear()
	_fill_trash()


func _fill_grid() -> void:
	for f in _filter_btns:
		_filter_btns[f].button_pressed = f == _filter
	for m in _sort_btns:
		_sort_btns[m].button_pressed = m == BWInvSort.mode
	for c in _grid.get_children():
		c.queue_free()
	_fill_trash()
	var items := BWInvSort.sorted(run.inventory.filter(func(it): return _filter == "" or str(it.slot) == _filter))
	_inv_title.text = ("Inventory · %d item%s" % [items.size(), "" if items.size() == 1 else "s"]).to_upper()
	if items.is_empty():
		var l := Label.new()
		l.text = "Nothing loose%s. Loot drops after each win; the shop trades 1-for-1." % ("" if _filter == "" else " for that slot")
		l.add_theme_color_override("font_color", BWStyle.FAINT)
		l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(BWItemCard.W, 0)
		_grid.add_child(l)
		return
	for it in items:
		var t := BWItemTile.new(it, 78.0)
		t.blocked = not run.can_equip(unit, it)
		t.selected = it == _sel
		t.hovered.connect(_hover_tile)
		t.unhovered.connect(_unhover)
		t.picked.connect(_pick_tile)
		t.activated.connect(func(tile): _equip(tile.item))
		# a worn piece dropped on any tile comes off, like a drop on the grid;
		# a discarded one comes back (D234)
		t.accept = func(x: Dictionary) -> bool: return x in run.trash or (not x in run.inventory and str(x.get("slot", "")) != "main_hand")
		t.on_drop = func(x: Dictionary): _back_to_grid(x)
		_grid.add_child(t)


## D235: the grid's order (shared with the shop for the session).
func set_sort(m: String) -> void:
	BWInvSort.set_mode(m)
	_fill_grid()


## A drop on the grid: a discarded piece comes back, a worn one comes off.
func _back_to_grid(x: Dictionary) -> void:
	if x in run.trash:
		restore(x)
	elif str(x.get("slot", "")) != "main_hand":
		_unequip(_worn_slot(x))


## The slot `x` is worn in on this unit, or "".
func _worn_slot(x: Dictionary) -> String:
	for slot in BWRun.GEAR_SLOTS:
		if unit != null and unit.equipment.get(slot, {}) == x:
			return slot
	return ""


# ---------------------------------------------------------------- discard (D234)

func _build_trash() -> Control:
	_trash_box = _TrashDrop.new()
	_trash_box.panel = self
	_trash_box.name = "trash"
	var st := BWStyle.column_style()
	st.bg_color = Color(0, 0, 0, 0.35)
	st.border_color = Color(1, 1, 1, 0.22)
	st.set_border_width_all(1)
	st.set_content_margin_all(4)
	st.content_margin_left = 8
	_trash_box.add_theme_stylebox_override("panel", st)
	_trash_box.custom_minimum_size = Vector2(BWItemCard.W + 8, 0)
	_trash_box.tooltip_text = "Drag a loose item here to throw it away when the battle starts.\nDrag it back, or double-click it, to keep it."
	# one compact row: the title and its rule | the pile | Discard picked
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash_box.add_child(h)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	_trash_title = BWStyle.section_label("Discard")
	tv.add_child(_trash_title)
	for line in ["Discarded when", "the battle starts"]:      # two Labels: the theme spaces lines wide
		var note := Label.new()
		note.text = line
		note.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 5)
		note.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
		tv.add_child(note)
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 44)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(sc)
	_trash_row = HBoxContainer.new()
	_trash_row.add_theme_constant_override("separation", 5)
	_trash_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_trash_row.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(_trash_row)
	_trash_btn = Button.new()
	_trash_btn.name = "discard_picked"
	_trash_btn.text = "Discard
picked"
	_trash_btn.focus_mode = Control.FOCUS_NONE
	_trash_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trash_btn.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 5)
	_trash_btn.tooltip_text = "Throw away the picked loose item when the battle starts"
	_trash_btn.pressed.connect(func(): discard(_sel))
	h.add_child(_trash_btn)
	return _trash_box


func _fill_trash() -> void:
	if _trash_row == null:
		return
	for c in _trash_row.get_children():
		c.queue_free()
	var n := run.trash.size()
	_trash_title.text = ("Discard · %d" % n).to_upper() if n > 0 else "DISCARD"
	_trash_btn.disabled = _sel.is_empty() or not _sel in run.inventory
	if n == 0:
		var l := Label.new()
		l.text = "Drag loose items here"
		l.add_theme_color_override("font_color", BWStyle.FAINT)
		l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 3)
		l.custom_minimum_size = Vector2(0, 42)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_trash_row.add_child(l)
		return
	for it in run.trash:
		var t := BWItemTile.new(it, 42.0)
		t.source = "trash"
		t.modulate = Color(1, 1, 1, 0.6)
		t.hovered.connect(_hover_trash)
		t.unhovered.connect(_unhover)
		t.activated.connect(func(tile): restore(tile.item))
		_trash_row.add_child(t)


func _hover_trash(t: BWItemTile) -> void:
	_peek = false
	card.show_item(t.item, unit, run, unit.equipment.get(str(t.item.slot), {}),
		{ "hint": "Discarded when the battle starts. Drag it back or double-click to keep it." })


## Put a loose piece (or, from a slot, a worn one) on the discard pile.
func discard(it: Dictionary) -> bool:
	if it.is_empty():
		return false
	if not it in run.inventory:
		var slot := _worn_slot(it)
		if slot == "" or slot == "main_hand":
			return false
		run.unequip(unit, slot)
		doll.refresh()
	if not run.trash_item(it):
		return false
	if _sel == it:
		_sel = {}
		_show_give({}, "")
		doll.refresh()
	_msg.text = "%s goes in the discard pile: thrown away when the battle starts." % BWGearText.plain_name(it)
	refresh()
	changed.emit()
	return true


## Take a piece back off the discard pile.
func restore(it: Dictionary) -> bool:
	if not run.untrash_item(it):
		return false
	_msg.text = "Kept %s." % BWGearText.plain_name(it)
	refresh()
	changed.emit()
	return true


## The discard pile as a drop target: loose pieces, or worn ones (not the main hand).
class _TrashDrop:
	extends PanelContainer
	var panel: BWGearPanel
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary and data.has("bw_item")):
			return false
		var it: Dictionary = data.bw_item
		return it in panel.run.inventory or (str(data.get("from", "")) == "slot" and str(data.get("slot", "")) != "main_hand")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.discard(data.bw_item)


## (item) -> bool for a slot box: the right slot and allowed for this unit.
func _accepts_for(slot: String) -> Callable:
	return func(it: Dictionary) -> bool:
		var kind := "main_hand" if slot == BWUnit.SECOND else slot      # D180: the second slot takes weapons
		return unit != null and str(it.get("slot", "")) == kind and it in run.inventory and run.can_equip(unit, it)


func _hover_tile(t: BWItemTile) -> void:
	_peek = false
	_show(t.item)


func _pick_tile(t: BWItemTile) -> void:
	_sel = t.item if _sel != t.item else {}
	for c in _grid.get_children():
		if c is BWItemTile:
			c.selected = c.item == _sel
			c.queue_redraw()
	_trash_btn.disabled = _sel.is_empty()
	if _sel.is_empty():
		doll.refresh()
		card.clear()
		_show_give({}, "")
		return
	_show(_sel)
	_show_give(_sel, "")
	doll.preview(str(_sel.slot), _sel)
	_msg.text = "Trying on %s — double-click or drag it onto %s to keep it." % [BWGearText.plain_name(_sel),
		BWGearText.SLOT_NAMES[str(_sel.slot)]]


func _hover_slot(t: BWItemTile) -> void:
	_peek = false
	if t.item.is_empty():
		if t.slot == BWUnit.SECOND:
			card.clear("Second weapon: empty. Drag a weapon here to carry it; in battle, Swap weapon draws it (free).")
		else:
			card.clear("%s: empty. Drag a %s item here." % [BWGearText.SLOT_NAMES[t.slot], BWGearText.SLOT_NAMES[t.slot].to_lower()])
		return
	var hint := "Double-click to take it off."
	if t.slot == "main_hand":
		hint = "Never empty-handed: swap weapons by equipping another."
	elif t.slot == BWUnit.SECOND:
		hint = "Carried, not in hand: no stats or passive until drawn. In battle, Swap weapon draws it (free). Double-click to take it off."
	card.show_item(t.item, unit, run, t.item, { "hint": hint })


## Off a tile: back to the selection, or an empty card. D171 (author): with
## nothing selected the card kept the last hovered item ("the tooltip stays
## up when I mouse off the piece"). The cursor may travel onto the card to
## hover its terms; anywhere else, the hovered read goes (_process).
var _peek := false                   # the card shows a hovered piece, not the selection


func _unhover(_t: BWItemTile) -> void:
	_peek = true


func _process(_d: float) -> void:
	if not _peek or not is_visible_in_tree():
		return
	var over: Control = get_viewport().gui_get_hovered_control()
	if over != null and (over is BWItemTile or card.is_ancestor_of(over) or over == card):
		return
	_peek = false
	if not _sel.is_empty():
		_show(_sel)
	else:
		card.clear()


func _show(it: Dictionary) -> void:
	var cur: Dictionary = unit.equipment.get(str(it.slot), {})
	card.show_item(it, unit, run, cur, { "hint": "Double-click or drag onto %s to equip." % BWGearText.SLOT_NAMES[str(it.slot)] })


func _equip(it: Dictionary, slot: String = "") -> void:
	if not it in run.inventory:
		return
	if not run.can_equip(unit, it):
		_msg.text = "✕ " + str(BWGearText.equip_check(run, unit, it)[1])
		return
	if slot != BWUnit.SECOND:
		slot = ""
	if not run.equip(unit, it, slot):
		return
	_sel = {}
	_msg.text = "Equipped %s." % BWGearText.plain_name(it)
	doll.refresh()
	refresh()
	card.show_item(it, unit, run, it)
	changed.emit()


func _unequip(slot: String) -> void:
	if slot == "main_hand" or not unit.equipment.has(slot):
		return
	var it: Dictionary = unit.equipment[slot]
	run.unequip(unit, slot)
	_msg.text = "Took off %s." % BWGearText.plain_name(it)
	doll.refresh()
	refresh()
	changed.emit()


func _fill_abilities() -> void:
	for c in _abil.get_children():
		c.queue_free()
	_abil.add_child(_focus_row())
	var known: Array = run.learned.get(unit.id, [])
	if known.is_empty():
		var n := Label.new()
		n.text = "None yet — wear a piece of armour for %d battles to learn what it teaches." % BWRun.LEARN_BATTLES
		n.autowrap_mode = TextServer.AUTOWRAP_WORD
		n.add_theme_color_override("font_color", BWStyle.FAINT)
		n.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		n.custom_minimum_size = Vector2(500, 0)
		_abil.add_child(n)
		return
	for type in BWEffects.TYPES:
		var mine := known.filter(func(a): return BWRun.ability_type(a) == type)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		ob.add_item("%s: none" % str(type).capitalize())
		ob.disabled = mine.is_empty()
		var cur := str(run.equipped_ability.get(unit.id, {}).get(type, ""))
		for a in mine:
			var row := BWData.row("abilities", a)
			ob.add_item("%s: %s (rank %d)" % [str(type).capitalize(), row.name, int(run.ability_ranks[unit.id].get(a, 1))])
			if a == cur:
				ob.select(ob.item_count - 1)
		ob.tooltip_text = "\n".join(mine.map(func(a): return "%s — %s" % [BWData.row("abilities", a).name, BWData.row("abilities", a).effect_text])) \
			if not mine.is_empty() else "No %s ability learned yet." % type
		ob.item_selected.connect(func(i: int):
			if i == 0:
				run.equipped_ability[unit.id].erase(type)
			else:
				run.equip_ability(unit, mine[i - 1])
			changed.emit())
		_abil.add_child(ob)


## D132: the focus element (what Specialize trains), a small toggle of the
## elements the unit has affinity in; the native one first.
func _focus_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = "Focus"
	l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	l.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	row.add_child(l)
	for el in unit.focus_options():
		var b := Button.new()
		b.text = str(el).capitalize()
		b.toggle_mode = true
		b.button_pressed = el == unit.focus()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
		b.custom_minimum_size = Vector2(0, 30)
		var on: bool = el == unit.focus()
		var ec := BWLook.element_color(el)
		for st in ["normal", "hover", "pressed"]:
			var sb := BWStyle.element_button_style(el, st)
			if on:
				sb.bg_color = ec                # the focus: filled in its colour
				sb.border_color = Color.WHITE
				sb.set_border_width_all(2)
			b.add_theme_stylebox_override(st, sb)
		var ink := (Color.BLACK if ec.get_luminance() > 0.5 else Color.WHITE) if on else BWGearText.readable(ec)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, ink)
		b.name = "focus_" + str(el)
		b.pressed.connect(func():
			unit.focus_element = "" if el == unit.element else str(el)
			refresh()
			changed.emit())
		row.add_child(b)
	return row


## D180: trade the weapon in hand and the carried one.
func _swap() -> void:
	if unit == null or not run.swap_weapons(unit):
		return
	_msg.text = "Now holding %s; carrying %s." % [BWGearText.plain_name(unit.equipment.get("main_hand", {})),
		BWGearText.plain_name(unit.second_weapon())]
	doll.refresh()
	refresh()
	changed.emit()


## D89: the skills this unit knows for the weapon it holds, as toggles; up
## to BWUnit.loadout_cap equipped (3; the staff keeps its starting 4). An
## improved skill (an expertise pick) is marked "+". D181: a carried weapon of
## another class gets its own row (each class keeps its own loadout).
func _fill_skills() -> void:
	for c in _skills.get_children():
		c.queue_free()
	var classes: Array = [unit.weapon_class]
	var sec := str(unit.second_weapon().get("weight", ""))
	if sec != "" and not sec in classes:
		classes.append(sec)
	var titles: PackedStringArray = []
	for wc in classes:
		titles.append("%s %d/%d" % [BWText.weapon(wc), unit.loadout(wc).size(), BWUnit.loadout_cap(wc)])
		if classes.size() > 1:
			var l := Label.new()
			l.text = BWText.weapon(wc) + ("" if wc == unit.weapon_class else " (carried)")
			l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
			l.add_theme_color_override("font_color", BWStyle.LABEL)
			l.custom_minimum_size = Vector2(0, 30)
			_skills.add_child(l)
		_fill_skill_row(wc)
		if classes.size() > 1 and wc == classes[0]:
			var br := Control.new()                 # a line break in the flow
			br.custom_minimum_size = Vector2(480, 0)
			_skills.add_child(br)
	_skills_title.text = ("Skills — up to 3 per weapon, staff 4 · " + " · ".join(titles)).to_upper()


func _fill_skill_row(wc: String) -> void:
	var cap := BWUnit.loadout_cap(wc)
	var on: Array = unit.loadout(wc)
	for k in unit.known(wc):
		var row := BWSkills.get_skill(k)
		var b := BWGlossary.TipButton.new()          # D125: the tooltip defines its terms
		b.toggle_mode = true
		b.button_pressed = k in on
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(row.get("name", k)) + ("  +" if unit.skill_upgraded(k) else "")
		b.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		for st in ["normal", "hover"]:
			b.add_theme_stylebox_override(st, BWStyle.button_style(st))
		b.add_theme_stylebox_override("pressed", BWStyle.element_button_style(unit.element, "pressed"))
		b.tooltip_text = "%s%s
%s
Range %s · cooldown %s" % [row.get("name", k),
			" (improved)" if unit.skill_upgraded(k) else "", row.get("desc", ""), row.get("range", 0), row.get("cd", 0)]
		b.toggled.connect(func(pressed: bool):
			if not unit.set_equipped(wc, k, pressed):
				_msg.text = "✕ " + ("Loadout full (%d): take one off first." % cap if pressed else "Keep at least one skill.")
			_fill_skills()
			changed.emit())
		_skills.add_child(b)


## Drop a slot's item anywhere on the inventory area to take it off.
class _GridDrop:
	extends ScrollContainer
	var panel: BWGearPanel
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.get("from", "") == "trash":
			return true                                  # D234: back off the discard pile
		return data is Dictionary and data.get("from", "") == "slot" and str(data.get("slot", "")) != "main_hand"
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.get("from", "") == "trash":
			panel.restore(data.bw_item)
			return
		panel._unequip(str(data.slot))


# ---------------------------------------------------------------- give (D84)

## The "Give to" / "Equip on" row for a picked item: from a worn slot
## (`from_slot`) or loose in the inventory (""). Hidden unless give_enabled.
func _show_give(it: Dictionary, from_slot: String) -> void:
	if _give_box == null:
		return
	for c in _give_flow.get_children():
		c.queue_free()
	_give_box.visible = give_enabled and not it.is_empty() and from_slot != "main_hand"
	if not _give_box.visible:
		return
	_give_label.text = ("Give to" if from_slot != "" else "Equip on").to_upper()
	for o in run.squad:
		if o == unit and from_slot != "":
			continue
		var b := Button.new()
		b.text = o.name
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, BWStyle.element_button_style(o.element, st))
		b.disabled = not run.can_equip(o, it)
		var worn: Dictionary = o.equipment.get(str(it.slot), {})
		b.tooltip_text = ("Swaps out %s" % BWGearText.plain_name(worn)) if not worn.is_empty() else "Nothing worn there"
		b.pressed.connect(give.bind(o, it, from_slot))
		_give_flow.add_child(b)


## Move `it` onto `to`: off this unit first when it's worn (`from_slot`),
## whatever `to` wore there goes to the inventory. Returns true when it moved.
func give(to: BWUnit, it: Dictionary, from_slot: String = "") -> bool:
	if from_slot != "":
		if from_slot == "main_hand" or unit.equipment.get(from_slot, {}) != it:
			return false
		run.unequip(unit, from_slot)
	if not run.equip(to, it):
		_msg.text = "✕ %s can't use %s." % [to.name, BWGearText.plain_name(it)]
		refresh()
		changed.emit()
		return false
	_sel = {}
	_msg.text = "%s now wears %s." % [to.name, BWGearText.plain_name(it)]
	_show_give({}, "")
	doll.refresh()
	refresh()
	changed.emit()
	return true

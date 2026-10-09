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
## D315-D318 auto-equip (BWAutoEquip): "Optimize all [O]" in the header hands
## the squad's gear out, most-used unit first (it may take from units below
## it); "Optimize" under the sets line fills this unit from the loose
## inventory only. Both show the changes first (Apply / Cancel, Esc cancels);
## after Apply, "Undo optimize" puts everything back (one step, until the
## gear is changed by hand).
## D403: Optimize ranks a unit's focus element first, then its other learned
## elements; the preview notes why ("Fire set 3/3", "Water (2nd)").
## D404: "Unequip all [U]" beside it takes every squad unit's armour and
## second weapon off (the main hand stays); "Unequip" under the sets line
## does this unit. Both confirm in the same box and share the one-step Undo.

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
var _sets: RichTextLabel           # D282
var _trash_box: PanelContainer     # D234
var _trash_row: HBoxContainer
var _trash_title: Label
var _trash_btn: Button
var _opt_all: Button               # D315-D318
var _opt_unit: Button
var _undo_btn: Button
var _unequip_all: Button           # D404
var _unequip_unit: Button
var _plan_kind := "optimize"       # the plan on preview: "optimize" / "unequip"
var _undo_kind := "optimize"
var _preview: PanelContainer
var _preview_text: RichTextLabel
var _preview_title: Label
var _plan := {}                    # the plan on preview
var _undo_snap := {}               # BWAutoEquip.apply's snapshot (one step)
var _applying := false
## D404: the header's filter and action buttons (with Unequip all the row
## outgrew the hall's panel at F_SMALL).
const HEADER_FONT := BWStyle.F_SMALL - 3
## D532: the doll column's scrolled lower part (skills, sets, abilities) and
## the inventory grid's share of its column (at least 3 rows; it splits the
## free height with the item card, which keeps CARD_MIN_H).
const LOWER_W := 500.0
const GRID_MIN_H := 360.0               # D534 (author: "try 4 rows of shown gear"): was 278 (3 rows)
const GRID_RATIO := 1.6
const CARD_MIN_H := 150.0
## The hall's prep (D84): hand gear between units in one click.
var give_enabled := false


func _init(p_run: BWRun) -> void:
	run = p_run
	add_theme_stylebox_override("panel", BWStyle.box_style())
	# D404: a host that anchors the panel to the right edge (the hall's prep)
	# has it widen leftward when the header outgrows it, never off screen
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	# header
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)                # D404: a 4th action fits the hall's header
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
		b.add_theme_font_size_override("font_size", HEADER_FONT)
		b.pressed.connect(func(): _filter = f[0]; _fill_grid())
		hb.add_child(b)
		_filter_btns[f[0]] = b
	_opt_all = Button.new()                            # ---- D318
	_opt_all.name = "optimize_all"
	_opt_all.text = "Optimize all [O]"
	_opt_all.focus_mode = Control.FOCUS_NONE
	_opt_all.add_theme_font_size_override("font_size", HEADER_FONT)   # the hall's 1050 px header fits
	_opt_all.tooltip_text = "Hand out the whole squad's gear, most-used unit first:\nits element and weapon first, then the higher tier. It may take\npieces from units used less. You see the changes before they apply."
	var sc_ev := InputEventKey.new()
	sc_ev.keycode = KEY_O
	var o_sc := Shortcut.new()
	o_sc.events = [sc_ev]
	_opt_all.shortcut = o_sc
	_opt_all.shortcut_in_tooltip = false
	_opt_all.pressed.connect(optimize_all)
	hb.add_child(_opt_all)
	_unequip_all = Button.new()                        # ---- D404
	_unequip_all.name = "unequip_all"
	_unequip_all.text = "Unequip all [U]"
	_unequip_all.focus_mode = Control.FOCUS_NONE
	_unequip_all.add_theme_font_size_override("font_size", HEADER_FONT)
	_unequip_all.tooltip_text = "Take the whole squad's armour and second weapons off, into the\ninventory (cursed pieces too). Main-hand weapons stay, so nobody\nis left without one. You confirm first; Undo puts it back."
	var u_ev := InputEventKey.new()
	u_ev.keycode = KEY_U
	var u_sc := Shortcut.new()
	u_sc.events = [u_ev]
	_unequip_all.shortcut = u_sc
	_unequip_all.shortcut_in_tooltip = false
	_unequip_all.pressed.connect(unequip_all)
	hb.add_child(_unequip_all)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", HEADER_FONT)
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
	dc.size_flags_vertical = Control.SIZE_EXPAND_FILL      # ---- D532
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
	# ---- D532 (author: "Sometimes I can't see secondary weapon skill options"): everything
	# under the doll scrolls inside the panel instead of running off the screen's
	# bottom, and the skills (both weapons' rows) come first, right under the doll
	var lower_sc := ScrollContainer.new()
	lower_sc.name = "lower_scroll"
	lower_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lower_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower_sc.custom_minimum_size = Vector2(LOWER_W + 14, 120)
	dc.add_child(lower_sc)
	var lower := VBoxContainer.new()
	lower.add_theme_constant_override("separation", 8)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower_sc.add_child(lower)
	dc = lower
	_skills_title = BWStyle.section_label("Skills")
	dc.add_child(_skills_title)
	_skills = HFlowContainer.new()
	_skills.name = "skill_rows"
	_skills.add_theme_constant_override("h_separation", 6)
	_skills.add_theme_constant_override("v_separation", 6)
	_skills.custom_minimum_size = Vector2(LOWER_W, 0)
	dc.add_child(_skills)
	# ---- end D532
	_sets = RichTextLabel.new()                         # D282: the active element sets, one line
	_sets.name = "active_sets"
	_sets.bbcode_enabled = true
	_sets.fit_content = true
	_sets.scroll_active = false
	_sets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # D318: an unwrapped hint widened the panel off screen
	_sets.custom_minimum_size = Vector2(500, 0)
	_sets.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL - 1)
	_sets.add_theme_font_size_override("bold_font_size", BWStyle.F_SMALL - 1)
	dc.add_child(_sets)
	var orow := HBoxContainer.new()                    # ---- D317: this unit, from the inventory
	orow.add_theme_constant_override("separation", 8)
	dc.add_child(orow)
	_opt_unit = Button.new()
	_opt_unit.name = "optimize_unit"
	_opt_unit.text = "Optimize"
	_opt_unit.focus_mode = Control.FOCUS_NONE
	_opt_unit.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_opt_unit.tooltip_text = "Fill this unit's slots from the loose inventory (never from another unit):\nits element and weapon first, then the higher tier."
	_opt_unit.pressed.connect(optimize_unit)
	orow.add_child(_opt_unit)
	_unequip_unit = Button.new()                       # ---- D404: this unit
	_unequip_unit.name = "unequip_unit"
	_unequip_unit.text = "Unequip"
	_unequip_unit.focus_mode = Control.FOCUS_NONE
	_unequip_unit.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_unequip_unit.tooltip_text = "Take this unit's armour and second weapon off, into the inventory.\nThe main-hand weapon stays."
	_unequip_unit.pressed.connect(unequip_unit)
	orow.add_child(_unequip_unit)
	_undo_btn = Button.new()
	_undo_btn.name = "undo_optimize"
	_undo_btn.text = "Undo optimize"
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_undo_btn.tooltip_text = "Put everyone's gear back as it was before the last Optimize or Unequip"
	_undo_btn.visible = false
	_undo_btn.pressed.connect(undo_optimize)
	orow.add_child(_undo_btn)
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
	sc.custom_minimum_size = Vector2(BWItemCard.W + 8, GRID_MIN_H)      # ---- D532: was 178 (2 rows)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = GRID_RATIO
	sc.name = "inventory_scroll"
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
	cs.custom_minimum_size = Vector2(0, CARD_MIN_H)                    # ---- D532
	ic.add_child(cs)
	card = BWItemCard.new()
	cs.add_child(card)
	_build_preview()
	changed.connect(func():
		if not _applying:
			_set_undo({}))                             # a change by hand ends the one-step undo


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
	_fill_sets()
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


## D282: "Sets: Fire 2/3 · Water 3/3 (Breakwater)", each in its colour; hover
## for what the tiers do. Empty sets: a faint hint of how they're made.
func _fill_sets() -> void:
	var act := BWSets.active(unit)
	var faint := BWGearText.hex(BWStyle.FAINT)
	if act.is_empty():
		_sets.text = "[color=#%s]Sets: none. Head, chest, legs and the drawn weapon's imbue count toward their element.[/color]" % faint
		_sets.tooltip_text = ""
		return
	var parts: PackedStringArray = []
	var tips: PackedStringArray = []
	for a in act:
		var ec := BWGearText.hex(BWGearText.readable(BWLook.element_color(str(a.element))))
		parts.append("[color=#%s][b]%s %d/3[/b][/color]%s" % [ec, str(a.element).capitalize(), int(a.pieces),
			(" [color=#%s](%s)[/color]" % [ec, a.three]) if int(a.tier) >= 3 else ""])
		tips.append("%s 2: %s" % [str(a.element).capitalize(), a.two_text])
		if int(a.tier) >= 3:
			tips.append("%s 3, %s: %s" % [str(a.element).capitalize(), a.three, a.three_text])
	_sets.text = "[color=#%s]Sets[/color]  %s" % [faint, "  ·  ".join(parts)]
	_sets.tooltip_text = "
".join(tips)


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
	# ---- D534 (author): a drop-down to discard by tier ("drop all D tier and under")
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 3)
	bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bv)
	_trash_btn.size_flags_vertical = Control.SIZE_FILL
	bv.add_child(_trash_btn)
	_bulk_btn = MenuButton.new()
	_bulk_btn.name = "discard_bulk"
	_bulk_btn.text = "By tier ▾"
	_bulk_btn.flat = false
	_bulk_btn.focus_mode = Control.FOCUS_NONE
	_bulk_btn.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 5)
	_bulk_btn.tooltip_text = "Discard every loose item of a tier and below (worn gear is never touched)"
	var pm := _bulk_btn.get_popup()
	for i in BULK.size():
		pm.add_item(str(BULK[i][1]), i)
	pm.add_separator()
	pm.add_item("Keep all (empty the pile)", BULK.size())
	pm.id_pressed.connect(_bulk)
	bv.add_child(_bulk_btn)
	# ---- end D534
	return _trash_box


## D534: the tier drop-down's rows: [tier, label].
const BULK := [["E", "Discard all E"], ["D", "Discard D and under"], ["C", "Discard C and under"], ["B", "Discard B and under"]]
var _bulk_btn: MenuButton


func _bulk(id: int) -> void:
	if id >= BULK.size():
		var k := run.untrash_all()
		_msg.text = "Kept all %d discarded item%s." % [k, "" if k == 1 else "s"]
	else:
		var n := run.trash_tier_and_under(str(BULK[id][0]))
		_msg.text = "%d loose item%s %s in the discard pile: thrown away when the battle starts." % [
			n, "" if n == 1 else "s", "goes" if n == 1 else "go"] if n > 0 else "No loose items of %s." % str(BULK[id][1]).trim_prefix("Discard ").to_lower()
	if not _sel.is_empty() and not _sel in run.inventory and _worn_slot(_sel) == "":
		_sel = {}
		_show_give({}, "")
	refresh()
	changed.emit()


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


# ---------------------------------------------------------------- auto-equip (D315-D318)

func _build_preview() -> void:
	_preview = PanelContainer.new()
	_preview.name = "optimize_preview"
	_preview.top_level = true                          # floats over the panel, not in its layout
	_preview.z_index = 20
	_preview.visible = false
	var ps := BWStyle.prompt_style()
	ps.bg_color.a = 0.98                               # opaque: the gear panel mustn't read through
	ps.set_content_margin_all(18)
	_preview.add_theme_stylebox_override("panel", ps)
	add_child(_preview)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_preview.add_child(v)
	_preview_title = Label.new()
	_preview_title.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	v.add_child(_preview_title)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(720, 0)
	sc.name = "preview_scroll"
	v.add_child(sc)
	_preview_text = RichTextLabel.new()
	_preview_text.bbcode_enabled = true
	_preview_text.fit_content = true
	_preview_text.scroll_active = false
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_text.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL)
	_preview_text.add_theme_font_size_override("bold_font_size", BWStyle.F_SMALL)
	_preview_text.add_theme_constant_override("line_separation", 6)
	sc.add_child(_preview_text)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bh.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bh)
	var cancel := Button.new()
	cancel.name = "preview_cancel"
	cancel.text = "Cancel  [Esc]"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(cancel_preview)
	bh.add_child(cancel)
	var ok := Button.new()
	ok.name = "preview_apply"
	ok.text = "Apply"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(140, 0)
	ok.pressed.connect(apply_preview)
	bh.add_child(ok)


## Optimize all [O]: plan the whole squad, show the changes.
func optimize_all() -> void:
	if preview_open():
		return
	_plan_kind = "optimize"
	_show_plan(BWAutoEquip.plan_all(run), "Optimize all")


## Optimize: this unit, from the loose inventory.
func optimize_unit() -> void:
	if unit == null or preview_open():
		return
	_plan_kind = "optimize"
	_show_plan(BWAutoEquip.plan_unit(run, unit), "Optimize %s" % unit.name)


## D404 Unequip all [U]: every squad unit's armour and second weapon to the
## inventory (the main hand stays). One line to confirm, Apply / Cancel.
func unequip_all() -> void:
	if preview_open():
		return
	_plan_kind = "unequip"
	_show_plan(BWAutoEquip.plan_unequip(run), "Unequip all")


## D404 Unequip: this unit only.
func unequip_unit() -> void:
	if unit == null or preview_open():
		return
	_plan_kind = "unequip"
	_show_plan(BWAutoEquip.plan_unequip(run, [unit]), "Unequip %s" % unit.name)


func preview_open() -> bool:
	return _preview != null and _preview.visible


func _show_plan(plan: Dictionary, title: String) -> void:
	if BWAutoEquip.empty(plan):
		_msg.text = "Nothing to take off: only main-hand weapons are on." if _plan_kind == "unequip" \
			else "Nothing to change: the best pieces are already on."
		return
	_plan = plan
	var n: int = plan.changes.size()
	if _plan_kind == "unequip":
		_preview_title.text = title
		_preview_text.text = unequip_line(run, plan)
	else:
		_preview_title.text = "%s · %d change%s" % [title, n, "" if n == 1 else "s"]
		_preview_text.text = preview_bbcode(run, plan)
	_preview.visible = true
	_fit_preview()
	_fit_preview.call_deferred()                       # again once the text has wrapped at its width
	_set_buttons_disabled(true)
	BWEsc.push(_preview, cancel_preview, { "name": "unequip confirm" if _plan_kind == "unequip" else "optimize preview" })


## Size the scroll to the wrapped text (up to 440 px) and centre the box on the panel.
func _fit_preview() -> void:
	var sc: ScrollContainer = _preview.find_child("preview_scroll", true, false)
	_preview_text.size.x = sc.custom_minimum_size.x
	sc.custom_minimum_size.y = minf(_preview_text.get_content_height() + 6, 440.0)
	_preview.reset_size()
	var r := get_global_rect()
	_preview.global_position = (r.position + (r.size - _preview.get_combined_minimum_size()) * 0.5).round()


func cancel_preview() -> void:
	_preview.visible = false
	_plan = {}
	BWEsc.remove(_preview)
	_set_buttons_disabled(false)


func _set_buttons_disabled(on: bool) -> void:
	for b in [_opt_all, _opt_unit, _unequip_all, _unequip_unit]:
		b.disabled = on


func apply_preview() -> void:
	if _plan.is_empty():
		return
	var plan := _plan
	var kind := _plan_kind
	cancel_preview()
	var snap := BWAutoEquip.apply(run, plan)
	_sel = {}
	_show_give({}, "")
	var n: int = plan.changes.size()
	if kind == "unequip":
		var k: int = plan.get("freed", []).size()
		_msg.text = "Took off %d piece%s (main hands stay). Undo unequip puts them back." % [k, "" if k == 1 else "s"]
	else:
		_msg.text = "Optimized: %d change%s. Undo optimize puts it all back." % [n, "" if n == 1 else "s"]
	doll.refresh()
	refresh()
	_applying = true
	changed.emit()
	_applying = false
	_undo_kind = kind
	_set_undo(snap)


func undo_optimize() -> void:
	if _undo_snap.is_empty():
		return
	if not BWAutoEquip.undo(run, _undo_snap):
		_msg.text = "✕ The gear changed since (a trade or a discard): can't undo."
		_set_undo({})
		return
	_msg.text = "Undone: everyone's gear is back as it was."
	_sel = {}
	doll.refresh()
	refresh()
	_applying = true
	changed.emit()
	_applying = false
	_set_undo({})


func _set_undo(snap: Dictionary) -> void:
	_undo_snap = snap
	if _undo_btn != null:
		_undo_btn.visible = not snap.is_empty()
		_undo_btn.text = "Undo unequip" if _undo_kind == "unequip" else "Undo optimize"


func can_undo() -> bool:
	return not _undo_snap.is_empty()


## The diff, one line per unit that changes (priority order):
## "Della: +Fire Chain Mail [C] (from Bob) · +Iron Helm [D]", a slot left
## empty as "−Old Cap (to inventory)", then how many pieces go back.
static func preview_bbcode(p_run: BWRun, plan: Dictionary) -> String:
	var names := {}
	for u in p_run.squad:
		names[u.id] = u.name
	var dest := {}                                     # item uid -> who wears it after
	for id in plan.get("loadouts", {}):
		for slot in plan.loadouts[id]:
			if not plan.loadouts[id][slot].is_empty():
				dest[str(plan.loadouts[id][slot].uid)] = str(id)
	var by := {}
	for c in plan.changes:
		if not by.has(c.unit):
			by[c.unit] = []
		by[c.unit].append(c)
	var dim := BWGearText.hex(BWStyle.TEXT_DIM)
	var lines: PackedStringArray = []
	for u in BWAutoEquip.priority(p_run):
		if not by.has(u.id):
			continue
		var parts: PackedStringArray = []
		for c in by[u.id]:
			if c.item.is_empty():
				var to := str(dest.get(str(c.out.get("uid", "")), ""))
				parts.append("[color=#%s]−%s (to %s)[/color]" % [dim, BWGearText.plain_name(c.out),
					names.get(to, to) if to != "" else "inventory"])
				continue
			var col := BWGearText.hex(BWGearText.readable(BWGearText.item_color(c.item)))
			var notes: PackedStringArray = []
			if str(c.from) != "" and str(c.from) != u.id:
				notes.append("from %s" % names.get(str(c.from), str(c.from)))
			elif str(c.slot) == "main_hand" and str(c.from) == u.id:
				notes.append("drawn")
			elif str(c.slot) == BWUnit.SECOND:
				notes.append("carried")
			var note := "" if notes.is_empty() else " (%s)" % ", ".join(notes)
			if str(c.get("reason", "")) != "":                # D403: why
				note += " – %s" % str(c.reason)
			parts.append("[color=#%s]+%s[/color] [color=#%s][lb]%s[rb]%s[/color]" % [col,
				BWGearText.plain_name(c.item), dim, str(c.item.get("tier", "E")), note])
		lines.append("[b]%s[/b]:  %s" % [u.name, "  ·  ".join(parts)])
	var freed: int = plan.get("freed", []).size()
	if freed > 0:
		lines.append("[color=#%s]%d piece%s back to the inventory.[/color]" % [dim, freed, "" if freed == 1 else "s"])
	return "\n".join(lines)


## D404: the unequip confirm's one line: "9 pieces from 5 units go to the
## inventory (2 cursed). Main-hand weapons stay."
static func unequip_line(p_run: BWRun, plan: Dictionary) -> String:
	var freed: Array = plan.get("freed", [])
	var who := {}
	for c in plan.get("changes", []):
		who[c.unit] = true
	var cur := freed.filter(func(it): return BWAutoEquip.cursed(it)).size()
	var units := " from %d units" % who.size()
	if who.size() == 1:
		for u in p_run.squad:
			if who.has(u.id):
				units = " from %s" % u.name
	return "%d piece%s%s go%s to the inventory%s. Main-hand weapons stay." % [freed.size(),
		"" if freed.size() == 1 else "s", units, "es" if freed.size() == 1 else "",
		" (%d cursed)" % cur if cur > 0 else ""]

class_name BWCombatUI
extends CanvasLayer
## Combat HUD, laid out after Temporal Sea V8's combat_ui.gd in BWStyle's
## black-and-white language:
##   top centre    turn order: head icons, 58 px for the actor, 42 px otherwise
##   bottom left   the acting unit's card (portrait, ticked HP bar, stats)
##   bottom right  the hovered unit's card, above the feed
##   by the unit   the action menu: a vertical list, skills that take an
##                 element open as an accordion (V8 menu_group), Wait last
##   right         the forecast box; every number explains itself on hover

signal action_pressed(id: String)     # "wait", "confirm", "cancel", "attack"
signal skill_chosen(key: String, element: String)

const CARD_W := 520
const MENU_W := 300

var _root: Control
var _order_panel: PanelContainer
var _order: HBoxContainer
var _acting: Dictionary = {}
var _hovered: Dictionary = {}
var _menu: PanelContainer
var _menu_list: VBoxContainer
var _menu_anchor := Vector2(800, 450)
var _open_group := ""
var _forecast: PanelContainer
var _fc_title: Label
var _fc_rows: VBoxContainer
var _fc_bar: BWWidgets.HPBar
var _feed: RichTextLabel
var _banner: PanelContainer
var _banner_label: Label
var _hint: Label
var _last_menu := {}


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = BWStyle.theme()
	add_child(_root)

	# turn order, top centre
	_order_panel = PanelContainer.new()
	_order_panel.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_order_panel.anchor_left = 0.5
	_order_panel.anchor_right = 0.5
	_order_panel.offset_top = 10
	_order_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_order_panel)
	# D217: the over-unit bars and labels keep below the turn-order bar
	_order_panel.item_rect_changed.connect(func(): BWHPBar3D.hud_rect = _order_panel.get_global_rect())
	tree_exiting.connect(func(): BWHPBar3D.hud_rect = Rect2(); BWHPBar3D.hover_unit = null; BWHPBar3D.covers = Callable())
	BWHPBar3D.covers = cover_rects                # D230 (L-21): bars hide behind HUD panels
	_order = HBoxContainer.new()
	_order.add_theme_constant_override("separation", 6)
	_order.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_panel.add_child(_order)

	_acting = _card(Control.PRESET_BOTTOM_LEFT)
	_hovered = _card(Control.PRESET_BOTTOM_RIGHT)
	_hovered.panel.offset_bottom = -200
	_hovered.panel.visible = false

	# feed, bottom right, a quiet plate
	var fp := PanelContainer.new()
	fp.add_theme_stylebox_override("panel", BWStyle.hud_style())
	fp.anchor_left = 1.0
	fp.anchor_right = 1.0
	fp.anchor_top = 1.0
	fp.anchor_bottom = 1.0
	fp.offset_left = -CARD_W - 16
	fp.offset_right = -16
	fp.offset_top = -186
	fp.offset_bottom = -16
	_root.add_child(fp)
	_feed = BWGlossary.Rich.new()                 # D125: terms in the feed hover too
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	_feed.add_theme_font_size_override("normal_font_size", BWStyle.F_FEED)
	_feed.add_theme_font_size_override("italics_font_size", BWStyle.F_FEED)
	_feed.add_theme_font_size_override("bold_font_size", BWStyle.F_FEED)
	fp.add_child(_feed)

	# action menu, floats by the acting unit
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_menu.custom_minimum_size = Vector2(MENU_W, 0)
	_root.add_child(_menu)
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 3)
	_menu.add_child(_menu_list)
	_menu.visible = false

	# hint line above the acting card
	var hint_plate := PanelContainer.new()
	hint_plate.add_theme_stylebox_override("panel", BWStyle.hud_style())
	hint_plate.anchor_top = 1.0
	hint_plate.anchor_bottom = 1.0
	hint_plate.offset_left = 16
	hint_plate.offset_top = -262
	hint_plate.offset_bottom = -228
	hint_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint_plate)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_hint.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	hint_plate.add_child(_hint)

	# forecast box, right
	_forecast = PanelContainer.new()
	_forecast.add_theme_stylebox_override("panel", BWStyle.box_style())
	_forecast.anchor_left = 1.0
	_forecast.anchor_right = 1.0
	_forecast.offset_left = -MENU_W - 16 - 100
	_forecast.offset_right = -16
	_forecast.offset_top = 96
	_root.add_child(_forecast)
	BWEsc.track(_forecast, func(): action_pressed.emit("cancel"), { "name": "confirm" })   # ---- D171
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 6)
	_forecast.add_child(fv)
	_fc_title = Label.new()
	_fc_title.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	_fc_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_fc_title.custom_minimum_size = Vector2(360, 0)
	fv.add_child(_fc_title)
	_fc_bar = BWWidgets.HPBar.new(Vector2(360, 12))
	_fc_bar.enemy = true
	fv.add_child(_fc_bar)
	fv.add_child(HSeparator.new())
	_fc_rows = VBoxContainer.new()
	fv.add_child(_fc_rows)
	fv.add_child(HSeparator.new())
	var fb := HBoxContainer.new()
	fb.alignment = BoxContainer.ALIGNMENT_CENTER
	fb.add_theme_constant_override("separation", 10)
	fv.add_child(fb)
	_button(fb, "Confirm  [Enter]", "confirm")
	_button(fb, "Back  [Esc]", "cancel")
	_forecast.visible = false

	# banner: a prompt-weight plaque, top centre under the turn order
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", BWStyle.prompt_style())
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_top = 92
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 34)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	_banner.visible = false
	_root.add_child(_banner)


## Old name kept for the other screens: they share the HUD theme.
static func theme_bw() -> Theme:
	return BWStyle.theme()


func _button(parent: Control, text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): action_pressed.emit(id))
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- unit cards

func _card(preset: int) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", BWStyle.frame_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preset == Control.PRESET_BOTTOM_LEFT:
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		p.offset_left = 16
		p.offset_right = 16 + CARD_W
		p.offset_bottom = -16
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		p.offset_left = -CARD_W - 16
		p.offset_right = -16
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	h.add_child(left)
	var icon := BWWidgets.LivePortrait.new(null, 104.0)     # D156: the unit's face, live
	left.add_child(icon)
	var bar := BWWidgets.HPBar.new(Vector2(104, 11))
	left.add_child(bar)
	var right := BWGlossary.Rich.new()            # D125: hover a term on the card for its definition
	right.bbcode_enabled = true
	right.fit_content = true
	right.scroll_active = false
	right.custom_minimum_size = Vector2(CARD_W - 150, 0)
	right.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(right)
	return { "panel": p, "icon": icon, "bar": bar, "text": right }


func _fill_card(c: Dictionary, u: BWUnit, tiles: BWTiles) -> void:
	if u == null:
		c.panel.visible = false
		return
	c.panel.visible = true
	if BWObelisk.is_objective(u):
		_fill_obelisk_card(c, u as BWObelisk)       # D145
		return
	c.icon.set_unit(u)
	c.bar.enemy = u.team == "enemy"
	c.bar.set_hp(u.hp, u.max_hp())
	var el := BWLook.element_color(u.element).to_html(false)
	var lines: PackedStringArray = []
	lines.append("[font_size=%d][b]%s[/b][/font_size]  [color=#%s]%s[/color]" % [BWStyle.F_NAME, u.name,
		BWStyle.TEXT_DIM.to_html(false), "enemy" if u.team == "enemy" else "Lv %d" % u.level])
	var model := BWText.model_name(u.weapon_model, u.weapon_class)      # D218: no "Sword · Sword"
	lines.append("[font_size=%d][color=#%s]%s%s ([hint=%s]%s[/hint])  [/color][color=#%s]■[/color] [color=#%s]%s[/color][/font_size]" % [
		BWStyle.F_SUB, BWStyle.LABEL.to_html(false), (model + " · ") if model != "" else "",
		BWText.weapon(u.weapon_class), BWGlossary.hint_text("expertise"), u.expertise_letter(u.weapon_class), el, BWStyle.LABEL.to_html(false),
		BWKanji.bb(u.element) + BWGlossary.markup(u.element.capitalize()) + BWPicker.sigil_bb(u)])     # D231: the kanji, when on; D278: the keystone sigil
	lines.append_array(badge_lines(u, BWStyle.F_SMALL))      # D129/D130
	lines.append("[font_size=%d]HP %d / %d    %s    Speed %d[/font_size]" % [BWStyle.F_BODY, u.hp, u.max_hp(), BWWeaponMove.card_bb(u), u.speed()])   # D359/D360
	lines.append_array(BWCombatUI.trait_lines(u, BWStyle.F_SMALL))           # D360/D361/D372: Jump 4, Rough-Footed, HighGrounder
	lines.append("[font_size=%d][color=#%s]CON %d   STR %d   DEX %d   WIL %d
DEF %d   RES %d   SPD %d[/color][/font_size]" % [
		BWStyle.F_SMALL, BWStyle.TEXT_DIM.to_html(false), u.stat("con"), u.stat("str"), u.stat("dex"),
		u.stat("wil"), u.stat("def"), u.stat("res"), u.stat("spd")])
	if tiles:
		var e := tiles.at(u.pos)
		if not e.is_empty():
			lines.append("[font_size=%d][i]Standing on %s[/i][/font_size]" % [BWStyle.F_SMALL, BWGlossary.markup(_ground_text(e))])
	for k in u.statuses:                          # D87 short statuses; D102 glyphs + the author's short rules
		var st: Array = status_info(str(k))
		var img := ""
		if status_glyph(str(k)) != null:
			img = GLYPH_MARK + str(k) + GLYPH_MARK + " "     # D102: a glyph slot, filled by _set_rich
		var until := " · until its turn ends" if not str(k) in WARD_KEYS and not u.statuses[k].get("keep", false) else ""   # D270: Restless / Steadied count turns
		lines.append("[font_size=%d]%s[b]%s[/b] [color=#%s]%s%s[/color][/font_size]" % [
			BWStyle.F_SMALL, img, BWGlossary.markup(str(st[0])), BWStyle.TEXT_DIM.to_html(false), BWGlossary.markup(str(st[1])), until])
	if not u.statuses.has("frost_ward") and not u.statuses.has("ward") and BWUnitView.has_ward(u):
		var wi := status_info("frost_ward")
		lines.append("[font_size=%d]%s[b]%s[/b] [color=#%s]%s[/color][/font_size]" % [
			BWStyle.F_SMALL, GLYPH_MARK + "frost_ward" + GLYPH_MARK + " ", BWGlossary.markup(str(wi[0])), BWStyle.TEXT_DIM.to_html(false), BWGlossary.markup(str(wi[1]))])
	lines.append_array(BWWindView.card_lines(u, BWStyle.F_SMALL))      # D275: Rot marks
	lines.append_array(BWElementsView.card_lines(u, BWStyle.F_SMALL))  # D287/D288: Empowered, Ward of Light
	_set_rich(c.text, "\n".join(lines))          # D153: no personality line          # D102: glyph slots become images


## D360/D361/D372: the class jump above 2 (Jump 4), movement traits (Rough-Footed) and owned passives (HighGrounder),
## one dim line, like a weapon passive.
static func trait_lines(u: BWUnit, fs: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for l in BWWeaponMove.card_lines(u):
		out.append("[font_size=%d][color=#%s]■ [b]%s[/b] %s[/color][/font_size]" % [fs, BWStyle.TEXT_DIM.to_html(false),
			BWGlossary.markup(str(l[0])), l[1]])
	return out


## D130: what Wander left on a unit, for every card that shows one:
## immunities, the next battle's buff (D177 removed the Disobedient badge).
static func badge_lines(u: BWUnit, fs: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var dim := BWStyle.TEXT_DIM.to_html(false)
	var ksl := BWPicker.keystone_bb(u, fs)               # D278: the keystones it holds, by name
	if ksl != "":
		out.append(ksl)
	var imm: PackedStringArray = []
	for st in u.immune_statuses:
		imm.append(str(BWSkills.STATUS.get(st, [st])[0]))
	if not imm.is_empty():
		out.append("[font_size=%d][color=#%s]Immune this battle:[/color] %s[/font_size]" % [fs, dim, ", ".join(imm)])
	var col := func(el: String) -> String:
		return "[color=#%s]%s[/color]" % [BWGearText.readable(BWLook.element_color(el)).to_html(false), el.capitalize()]
	if not u.braced.is_empty():
		out.append("[font_size=%d][color=#%s]Braced this battle:[/color] %s[/font_size]" % [fs, dim, ", ".join(u.braced.map(col))])
	var nb: PackedStringArray = []
	for k in u.fight_buff:
		nb.append("+%d %s" % [int(u.fight_buff[k]), str(k).to_upper()])
	for el in u.next_brace:
		nb.append("braced vs " + col.call(el))
	for st in u.next_immune:
		nb.append("immune to " + str(BWSkills.STATUS.get(st, [st])[0]))
	if not nb.is_empty():
		out.append("[font_size=%d][color=#%s]Next battle:[/color] %s[/font_size]" % [fs, dim, ", ".join(nb)])
	return out


func set_acting(u: BWUnit, tiles: BWTiles = null) -> void:
	_fill_card(_acting, u, tiles)


## The hovered unit (hidden when it's the acting unit or nobody).
func set_card(u: BWUnit, tiles: BWTiles = null, acting: BWUnit = null) -> void:
	if u == null or u == acting:
		_hovered.panel.visible = false
		return
	_fill_card(_hovered, u, tiles)


func _ground_text(e: Dictionary) -> String:
	var parts: PackedStringArray = []
	if e.h > 0: parts.append("Fire %d" % e.h)
	if e.h < 0: parts.append("Water %d" % -e.h)
	if e.v > 0: parts.append("Light %d" % e.v)
	if e.v < 0: parts.append("Dark %d" % -e.v)
	if e.marker != "": parts.append(BWTiles.MARKER_ELEMENT[e.marker].capitalize() + " mark")
	if e.marker == "fuse": parts.append("conductive: half its damage arcs to its nearest ally")    # D86
	if e.glaze > 0: parts.append("glazed")
	return ", ".join(parts)


# ---------------------------------------------------------------- turn order

## Turn order, predicted (author 10/4: "in the top I want to see the predicted
## turn order"): who is still to act this round, then — after a NEXT divider —
## next round's order (BWTurnQueue on the living units, so deaths and speed
## changes show up as soon as they happen). Every icon carries a mini HP bar.
var group_shown := {}          # D347: probes / review: group key -> members shown in its slot


func set_order(queue: Array, current: BWUnit, upcoming: Array = []) -> void:
	group_shown.clear()
	for c in _order.get_children():
		_order.remove_child(c)
		c.queue_free()
	var now: Array = BWTurnQueue.slots(queue.filter(func(u): return u.alive()))      # D347: a group is one slot
	var nxt: Array = BWTurnQueue.slots(upcoming.filter(func(u): return u.alive()))
	var fit := order_fit(_root.get_viewport_rect().size.x if _root else 1600.0, now.size(), nxt.size())   # D324
	var shown := 0
	for u in now:
		if shown >= fit.now:
			break
		shown += 1
		_order.add_child(_slot_icon(u, current, false))
	# D211/D324: past what fits, say how many more act this round
	var left: int = now.size() - shown
	if left > 0:
		var more := Label.new()
		more.text = "+%d" % left
		more.tooltip_text = "%d more act this round" % left
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		more.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		more.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_order.add_child(more)
	if fit.next > 0:
		var sep := VBoxContainer.new()
		sep.alignment = BoxContainer.ALIGNMENT_CENTER
		var line := ColorRect.new()
		line.color = BWStyle.BORDER_SOFT
		line.custom_minimum_size = Vector2(2, 30)
		line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sep.add_child(line)
		var nl := Label.new()
		nl.text = "NEXT"
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
		sep.add_child(nl)
		_order.add_child(sep)
		for i in mini(fit.next, nxt.size()):
			_order.add_child(_slot_icon(nxt[i], null, true))


## D324: how many turn-order icons fit in ORDER_FRAC of the HUD width (the
## design width is 1600, so the same count at 1080p): this round first (the
## current unit's 58 px, then 42 px icons, a "+N" past the fit), then next
## round's 34 px icons after the NEXT divider, at most ORDER_NEXT_MAX of them.
## The old fixed caps (8 this round, 13 in all) are the floor, so 3v3 reads
## as before. { now, next }.
const ORDER_FRAC := 0.56
const ORDER_NEXT_MAX := 8


static func order_fit(width: float, n_now: int, n_next: int) -> Dictionary:
	var budget := width * ORDER_FRAC
	var gap := 6.0
	var reserve := (36.0 + gap + mini(n_next, 4) * (34.0 + gap)) if n_next > 0 else 0.0
	var now := 1
	var used := 58.0
	while now < n_now and used + 42.0 + gap + (30.0 if now + 1 < n_now else 0.0) + reserve <= budget:
		used += 42.0 + gap
		now += 1
	now = mini(n_now, maxi(now, 8))
	if now < n_now:
		used += 30.0 + gap                                 # the "+N"
	var nxt := 0
	if n_next > 0:
		used += 36.0 + gap
		while nxt < mini(n_next, ORDER_NEXT_MAX) and used + 34.0 + gap <= budget:
			used += 34.0 + gap
			nxt += 1
		nxt = mini(n_next, maxi(nxt, 13 - now)) if now < 13 else nxt
	return { "now": now, "next": nxt }


## D347: one turn-order slot: a unit, or a group block ({ group, units })
## shown as its first member's portrait with a "×N" badge ("Horde ×6").
func _slot_icon(slot: Variant, current: BWUnit, next_round: bool) -> Control:
	if not slot is Dictionary:
		return _order_icon(slot, slot == current, next_round)
	var us: Array = slot.units
	var cur: bool = current != null and current in us
	var box := _order_icon(us[0], cur, next_round)
	var label := "%s ×%d" % [str(slot.group).capitalize(), us.size()]
	var icon: Control = box.get_child(0)
	icon.tooltip_text = "%s: they all move at once, one group turn
%s" % [label,
		", ".join(us.map(func(x): return "%s %d/%d" % [x.name, x.hp, x.max_hp()]))]
	var badge := Label.new()                         # the count, on the portrait's corner
	badge.text = "×%d" % us.size()
	badge.add_theme_font_size_override("font_size", 16 if not next_round else 13)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 7)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = 0
	badge.offset_top = 0
	badge.offset_right = -2
	badge.offset_bottom = 3
	icon.add_child(badge)
	var bar: Control = box.get_child(1)
	if bar.has_method("set_hp"):
		var hp := 0
		var mx := 0
		for x in us:
			hp += x.hp
			mx += x.max_hp()
		bar.set_hp(hp, mx)
	group_shown[str(slot.group)] = us.size()
	if cur and box.get_child_count() > 2:
		(box.get_child(2) as Label).text = label
	return box


func _order_icon(u: BWUnit, current: bool, next_round: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var px := 58.0 if current else (34.0 if next_round else 42.0)
	var icon := BWWidgets.Portrait.new(u, px)       # D156 (D145: the stones take turns too; they get their stone)
	icon.selected = current
	icon.tooltip_text = "%s  ·  HP %d/%d  ·  speed %d" % [u.name, u.hp, u.max_hp(), u.speed()]
	if BWObelisk.is_objective(u):
		icon.tooltip_text += "\n" + (u as BWObelisk).rule_text()
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	if next_round:
		icon.modulate = Color(1, 1, 1, 0.7)
	box.add_child(icon)
	var bar := BWWidgets.HPBar.new(Vector2(px, 5))
	bar.enemy = u.team == "enemy"
	bar.set_hp(u.hp, u.max_hp())
	box.add_child(bar)
	if current:
		var n := Label.new()
		n.text = u.name
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_font_size_override("font_size", 13)
		box.add_child(n)
	return box


# ---------------------------------------------------------------- action menu

## Kept for callers; placement no longer follows the unit (see _place_menu).
func set_menu_anchor(p: Vector2) -> void:
	_menu_anchor = p


## Locked placement (author, 2026-10-04: "the UI stays on the right side of
## the screen and doesn't flutter"): the action menu owns a fixed slot on
## the right, the same slot the forecast box takes when an attack is aimed,
## so choosing an action never moves the panel.
func _place_menu() -> void:
	if not _menu.visible:
		return
	var vp := _root.get_viewport_rect().size
	_menu.position = Vector2(vp.x - MENU_W - 16, 96)


## V8's action menu: ATTACK — weapon, then the basic attack, then each skill;
## a skill that needs an element is an accordion group whose rows are the
## elements; then Wait. During a follow-up only what's allowed is listed.
func set_skills(u: BWUnit, rows: Array, mode_key: String, can_swap: Variant = null) -> void:
	if can_swap == null:
		can_swap = _last_menu.get("swap", false) if _last_menu.get("u") == u else false
	_last_menu = { "u": u, "rows": rows, "mode": mode_key, "swap": can_swap }
	for c in _menu_list.get_children():
		_menu_list.remove_child(c)      # out of the layout now, not at frame end
		c.queue_free()
	var fu: Array = u.follow_up
	_menu_list.add_child(BWStyle.section_label("Follow-up" if not fu.is_empty() else "Attack — " + BWText.weapon(u.weapon_class)))
	if not u.acted or "basic" in fu:
		_menu_item("Attack", "Basic %s strike" % u.weapon_class, mode_key == "", func(): action_pressed.emit("attack"))
	if can_swap:                                     # D181/D195: free, any number of times, right under Attack
		var other: Dictionary = u.second_weapon()
		var b := _menu_item("Swap weapon  ·  %s" % BWText.weapon(str(other.get("weight", ""))),
			"Swap weapon (free)\nDraw %s and sheathe the one in hand: the attack, range and skills change with it. Doesn't use the action or the move." % BWRun.item_name(other),
			false, func(): action_pressed.emit("swap"))
		b.name = "swap_weapon"
	for row in rows:
		var els: Array = row.elements
		if row.get("upgraded", false):
			row = row.duplicate()
			row["name"] = str(row.name) + " +"     # D89: improved by an expertise pick
		if els.size() == 1:
			var el: String = els[0]
			var label := str(row.name) + ("" if el == "" else "  ·  " + el.capitalize())
			var b := _menu_item(label, _tip(row), mode_key == "%s|%s" % [row.key, el],
				func(): skill_chosen.emit(str(row.key), el))
			if el != "":
				b.add_theme_stylebox_override("normal", BWStyle.element_button_style(el))
			continue
		var open := _open_group == str(row.key)
		_menu_item(("▾ " if open else "▸ ") + str(row.name), _tip(row), false, func():
			_open_group = "" if _open_group == str(row.key) else str(row.key)
			set_skills(_last_menu.u, _last_menu.rows, _last_menu.mode))
		if open:
			for el in els:
				var b := _menu_item("      " + str(el).capitalize(), _tip(row), mode_key == "%s|%s" % [row.key, el],
					func(): skill_chosen.emit(str(row.key), str(el)))
				b.add_theme_stylebox_override("normal", BWStyle.element_button_style(str(el)))
				b.add_theme_stylebox_override("hover", BWStyle.element_button_style(str(el), "hover"))
	_menu_list.add_child(HSeparator.new())
	_menu_item("Wait  [T]" if fu.is_empty() else "Skip follow-up  [T]", "End this unit's turn", false,
		func(): action_pressed.emit("wait"))
	if _cine:
		_menu_want = true                   # D111: not over a cutscene
		return
	_menu_show(true)
	_menu.size = Vector2.ZERO
	_menu.reset_size()
	_place_menu.call_deferred()


func _tip(row: Dictionary) -> String:
	return "%s\n%s\nRange %s · cooldown %s" % [row.name, row.desc, row.range, row.cd]


func _menu_item(text: String, tip: String, active: bool, cb: Callable) -> Button:
	var b := BWGlossary.TipButton.new()           # D125: the tooltip adds the terms' definitions
	b.text = text
	b.tooltip_text = tip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(MENU_W - 16, 40)
	b.add_theme_font_size_override("font_size", BWStyle.F_MENU)
	if active:
		var sb := BWStyle.button_style("hover")
		sb.border_width_left = 5
		b.add_theme_stylebox_override("normal", sb)
	b.pressed.connect(cb)
	_menu_list.add_child(b)
	return b


## Screen rects the HUD covers, for anything that needs to click around it.
func blocking_rects() -> Array:
	var out: Array = []
	for c in [_menu, _forecast, _acting.panel, _hovered.panel]:
		if c.visible:
			out.append(c.get_global_rect())
	return out


## D230 (L-21): every visible HUD plate (the log, the cards, the menu, the
## forecast, toasts): an over-unit bar or label touching one is culled.
func cover_rects() -> Array:
	var out: Array = []
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	for c in _root.get_children():
		if c is PanelContainer and c != _order_panel and (c as Control).is_visible_in_tree():   # D217 clamps under the turn order
			var r: Rect2 = (c as Control).get_global_rect()
			if r.has_area() and r.size.x < screen.x * 0.9:
				out.append(r)
	for d in [_acting, _hovered]:
		if not d.is_empty() and d.panel.is_visible_in_tree() and not d.panel.get_parent() == _root:
			out.append(d.panel.get_global_rect())
	return out


func set_actions_visible(v: bool) -> void:
	var want := v and _menu_list.get_child_count() > 0
	if _cine:
		_menu_want = want                   # D111: shown again when the cutscene ends
		return
	_menu_show(want)


# ---- D111 cutscene HUD (marked edit) ----
## The action menu (and the hint line) fade out while a cutscene plays (the
## menu sat behind the callout band) and back in after, if it was up. While a cutscene runs,
## anything that would show the menu only records that it wants to.
var _cine := false
var _menu_want := false
var _menu_tw: Tween


func cinematic(on: bool) -> void:
	if on == _cine:
		return
	if _menu_tw:
		_menu_tw.kill()
	var plate := _hint.get_parent() as Control      # the hint line goes quiet with the menu
	create_tween().tween_property(plate, "modulate:a", 0.0 if on else 1.0, 0.15 if on else 0.2)
	if on:
		_menu_want = _menu.visible
		_cine = true
		if _menu.visible:
			_menu_tw = create_tween()
			_menu_tw.tween_property(_menu, "modulate:a", 0.0, 0.15)
			_menu_tw.tween_callback(func(): _menu.visible = false)
		return
	_cine = false
	if _menu_want and not _forecast.visible:
		_menu.visible = true
		_menu.modulate.a = 0.0
		_menu_tw = create_tween()
		_menu_tw.tween_property(_menu, "modulate:a", 1.0, 0.2)
	else:
		_menu.modulate.a = 1.0


func menu_shown() -> bool:
	return _menu.visible and _menu.modulate.a > 0.5


func _menu_show(v: bool) -> void:
	if _menu_tw:
		_menu_tw.kill()
	_menu.modulate.a = 1.0
	_menu.visible = v
# ---- end D111 ----


# ---------------------------------------------------------------- forecast

func show_forecast(att: BWUnit, dfn: BWUnit, fc: Dictionary, what: String = "", extra: int = 0) -> void:
	_fc_title.text = "%s  →  %s" % [att.name, dfn.name]
	if what != "":
		_fc_title.text = "%s: %s → %s%s" % [att.name, what, dfn.name, "  (+%d more)" % extra if extra > 0 else ""]
	_fc_bar.visible = true
	_fc_bar.enemy = dfn.team == "enemy"
	_fc_bar.set_hp(dfn.hp, dfn.max_hp(), maxi(0, dfn.hp - int(fc.damage.value)))
	for c in _fc_rows.get_children():
		c.queue_free()
	var rows := [["hit", "Hit chance", "%"], ["dodge", str(fc.get("dodge", {}).get("label", "Dodge")), "%"], ["avoid", "Avoid (in hit)", "%"], ["glance", "Glance chance", "%"],
		["crit", "Crit chance", "%"], ["resist", "Resist chance", "%"], ["damage", "Damage per hit", ""],
		["expected", "Expected", ""]]
	for r in rows:
		if not fc.has(r[0]):
			continue
		var c: Dictionary = fc[r[0]]
		var row := HBoxContainer.new()
		if r[0] == "dodge":
			row.modulate = Color(1, 1, 1)            # D142: the obelisk's flat dodge, its own named line
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = "%s\n= %s\n= %s\n= %s%s" % [c.label, c.formula, c.values, _num(c.value), r[2]]
		var name_l := Label.new()
		name_l.text = r[1]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.add_theme_color_override("font_color", BWStyle.LABEL)
		var val := Label.new()
		val.text = _num(c.value) + r[2]
		val.add_theme_font_size_override("font_size", 24 if r[0] in ["hit", "damage"] else BWStyle.F_BODY)
		val.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		row.add_child(val)
		_fc_rows.add_child(row)
	for n in fc.get("notes", []):                # D86/D87 riders, named; D125 terms hover
		_fc_rows.add_child(_note_line(str(n)))
	_forceful_toggle(att, what)                  # D244
	_wind_toggle(att)                            # D269
	var after := Label.new()
	after.text = "HP %d → %d on a clean hit" % [dfn.hp, maxi(0, dfn.hp - int(fc.damage.value))]
	after.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	after.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_fc_rows.add_child(after)
	var tip := Label.new()
	tip.text = "Hover a number for its formula."
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", BWStyle.FAINT)
	_fc_rows.add_child(tip)
	_forecast.visible = true
	_menu.visible = false
	_hovered.panel.visible = false


## D269: a wind action's three-way mode toggle (Gust / Vortex / Becalm),
## when the screen set `wind_action` for this forecast. `wind_changed` re-opens
## it with the new mode. Consumed once (the next forecast must set it again).
var wind_action := false
var wind_changed: Callable
var wind_strip: Callable           # D365: BWWindShapeView.strip, the WIND SHAPING strip of a wind skill


func _wind_toggle(att: BWUnit) -> void:
	if not wind_action:
		return
	wind_action = false
	if att == null or att.team != "player":
		return
	var shaping: Control = wind_strip.call() if wind_strip.is_valid() else null
	if shaping != null:
		_fc_rows.add_child(shaping)              # D365: a skill shapes its wind; the mode toggle is for basics
		return
	_fc_rows.add_child(BWWindView.toggle_row(att, wind_changed))


## D244 Forceful: a basic attack's knock is the player's call, push or pull,
## a toggle in the forecast (BWBattle._knockback_hit reads fx.force_pull).
func _forceful_toggle(att: BWUnit, what: String) -> void:
	if what != "" or att.team != "player":
		return
	var row: Dictionary = {}
	for e in BWEffects.list(att, "knockback"):
		if int(BWEffects.p(e, "choice", 0)) == 1:
			row = e
			break
	if row.is_empty():
		return
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	var label := func() -> String:
		return "%s: %s 1 (click to %s)" % [row.name, "pull" if att.fx.get("force_pull", false) else "push",
			"push" if att.fx.get("force_pull", false) else "pull"]
	b.text = label.call()
	b.pressed.connect(func():
		att.fx["force_pull"] = not att.fx.get("force_pull", false)
		b.text = label.call())
	_fc_rows.add_child(b)


## D125: one forecast note ("◆ Shatter: +15% ..."), its terms hoverable.
func _note_line(n: String) -> RichTextLabel:
	var nl := BWGlossary.Rich.new()
	nl.fit_content = true
	nl.scroll_active = false
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(360, 0)
	nl.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL)
	nl.add_theme_font_size_override("bold_font_size", BWStyle.F_SMALL)
	nl.add_theme_color_override("default_color", BWStyle.LABEL)
	nl.set_glossed("◆ " + n.replace("[", "(").replace("]", ")"))
	return nl


func hide_forecast() -> void:
	_forecast.visible = false


# ---- D160 blast preview in the confirm box (readability lane, marked edit) ----
var _fc_extra: Control


## The action's ground consequences in words under the numbers (BWReadability):
## [{ text, warn }]; a warn line (a friendly hurt) is red. Replaces the last set.
func forecast_extra(lines: Array) -> void:
	if _fc_extra and is_instance_valid(_fc_extra):
		_fc_extra.queue_free()
	_fc_extra = null
	if lines.is_empty() or not _forecast.visible:
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	for l in lines:
		var nl := _note_line(str(l.text))
		nl.set_glossed(("▲ " if l.warn else "◆ ") + str(l.text).replace("[", "(").replace("]", ")"))
		if l.warn:
			nl.add_theme_color_override("default_color", Color(1.0, 0.36, 0.36))
		v.add_child(nl)
	_fc_rows.add_child(v)
	_fc_rows.move_child(v, mini(_fc_rows.get_child_count() - 1, maxi(0, _fc_rows.get_child_count() - 3)))
	_fc_extra = v
# ---- end D160 ----


## D109/D110: the confirm box for an action with nothing to roll (Transfer,
## a self-centred skill with no one in reach): the title, the skill's notes
## in words, then Confirm / Back.
func show_plan(att: BWUnit, what: String, notes: Array) -> void:
	_fc_title.text = "%s: %s" % [att.name, what]
	_fc_bar.visible = false
	for c in _fc_rows.get_children():
		c.queue_free()
	for n in notes:
		_fc_rows.add_child(_note_line(str(n)))
	_wind_toggle(att)                            # D269: a gale laid on empty ground keeps the mode
	var tip := Label.new()
	tip.text = "Nothing to roll. Click again or press Enter to confirm."
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", BWStyle.FAINT)
	_fc_rows.add_child(tip)
	_forecast.visible = true
	_menu.visible = false
	_hovered.panel.visible = false


func forecast_open() -> bool:
	return _forecast.visible


func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# ---------------------------------------------------------------- feed etc.

func feed(text: String) -> void:
	_sums.clear()
	_feed_line(text)


func _feed_line(text: String) -> void:
	_lines.append(text)
	if _lines.size() > 60:
		_lines.pop_front()
		_sums.clear()                    # indices shifted: start summing afresh
	_feed.append_text(BWGlossary.markup(text) + "\n")
	if _feed.get_paragraph_count() > 60:
		_feed.remove_paragraph(0)


## D301: ground damage of one cause on one unit inside one action is ONE line,
## summed ("Demeter takes 32 from slam (x2)"); any plain feed() ends the action.
var _lines: Array = []
var _sums := {}

func feed_damage(who: String, amount: int, cause: String) -> void:
	var key := who + "|" + cause
	if not _sums.has(key):
		_feed_line("%s takes %d from %s" % [who, amount, cause])
		_sums[key] = { "amount": amount, "n": 1, "idx": _lines.size() - 1 }
		return
	var sm: Dictionary = _sums[key]
	sm.amount = int(sm.amount) + amount
	sm.n = int(sm.n) + 1
	var idx := int(sm.idx)
	if idx < 0 or idx >= _lines.size():
		_sums.erase(key)
		feed_damage(who, amount, cause)
		return
	_lines[idx] = "%s takes %d from %s (x%d)" % [who, int(sm.amount), cause, int(sm.n)]
	_feed.clear()
	for t in _lines:
		_feed.append_text(BWGlossary.markup(str(t)) + "\n")


func hint(text: String) -> void:
	_hint.text = text


func banner(text: String, seconds: float = 1.4) -> void:
	_banner_label.text = "  %s  " % text
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.reset_size()
	# D301: one banner tween at a time (an older tween's fade no longer fights
	# the new one), on real time and through pauses / slow beats, so the banner
	# always clears; a hard deadline hides it even if the tween never finishes.
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_banner_tw = tw
	_banner_until = Time.get_ticks_msec() + int((seconds + 0.6) * 1000.0)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.12)
	tw.tween_interval(seconds)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _banner.visible = false)


var _banner_tw: Tween
var _banner_until := 0


## D301: is a banner on screen? (A stuck one past its deadline is hidden here.)
func banner_up() -> bool:
	if _banner == null or not _banner.visible:
		return false
	if Time.get_ticks_msec() > _banner_until + 500:
		_banner.visible = false
		return false
	return true


## D301: review tools await this before a frame so no banner hides the tags.
func banner_gone() -> void:
	var t0 := Time.get_ticks_msec()
	while banner_up() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


# ---- D100 skill callout (marked edit) ----

## The skill's name as a cinematic beat before the cast (author: "it should
## pause before action in the cutscene, say something like 'Fire Tempest'
## then cast"): a black band wipes in from the left across the upper third,
## the name slides in on it (the element word in its hair colour, the rest
## white), holds, then slides on and wipes out to the right. D111: a slim
## band high on screen under the turn order, the caster's name small beside. Sizes are in the
## 1600x900 design space (canvas_items stretch), so it reads the same at
## 1080p and 4K. Returns at once; `CALLOUT_HOLD` is the beat the screen waits.
const CALLOUT_IN := 0.16
const CALLOUT_HOLD := 0.6
const CALLOUT_OUT := 0.18
const CALLOUT_SIZE := 32          # D111: ~38 px at 1080p (was 88)
const CALLOUT_NAME_SIZE := 29     # D173: the name over its element word, both inside the band
const CALLOUT_WORD_SIZE := 15
const CALLOUT_BAND := 60.0        # D111: ~66 px at 1080p (was 156); D173 60: the name over its element word
const CALLOUT_PAD := 56.0         # D173: the plate is the words plus this each side ...
const CALLOUT_MIN_W := 380.0      # ... never narrower ...
const CALLOUT_MAX_FRAC := 0.7     # ... nor wider than this share of the screen
const CALLOUT_Y := 122.0          # D111: high, just under the turn order bar
var _callout: Control


func callout(element_word: String, element: String, skill_name: String, who: String = "", hold: float = CALLOUT_HOLD) -> void:
	if _callout and is_instance_valid(_callout):
		_callout.queue_free()
	var vp := _root.get_viewport_rect().size
	var band_h := CALLOUT_BAND
	var y := CALLOUT_Y
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(host)
	_callout = host
	var col := BWLook.element_color(element) if element != "" else Color.WHITE
	# the words first: the plate is sized to them (D173: a centred plate, not full width)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	font.spacing_glyph = 3
	if who != "":                                  # D111: the caster, small, beside the name
		var wl := Label.new()
		wl.text = who.to_upper()
		wl.add_theme_font_override("font", font)
		wl.add_theme_font_size_override("font_size", 14)
		wl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(wl)
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.35)
		bar.custom_minimum_size = Vector2(2, 24)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
	# D173 (author): the skill's NAME is the line ("Fan of Knives", large),
	# the element word small under it in the element colour ("Light").
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -8)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := _callout_word(skill_name, Color.WHITE, font, Color(0, 0, 0, 0.9), 6)
	nm.add_theme_font_size_override("font_size", CALLOUT_NAME_SIZE if element_word != "" else CALLOUT_SIZE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(nm)
	if element_word != "":
		var dark := col.get_luminance() < 0.3
		var ew := _callout_word(BWText.label(element_word.to_lower()), BWGearText.readable(col) if dark else col, font,
			Color.WHITE if dark else Color(0, 0, 0, 0.9), 3 if dark else 4)
		ew.add_theme_font_size_override("font_size", CALLOUT_WORD_SIZE)
		ew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(ew)
	row.add_child(stack)
	# measured in the tree (a label's minimum size needs its theme and font)
	host.add_child(row)
	var rs := row.get_combined_minimum_size()
	host.remove_child(row)
	var plate_w := clampf(rs.x + 2.0 * CALLOUT_PAD, CALLOUT_MIN_W, vp.x * CALLOUT_MAX_FRAC)
	var x0 := roundf((vp.x - plate_w) * 0.5)
	# the plate: clipped, so widening it is the wipe
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(x0, y)
	clip.size = Vector2(0, band_h)
	host.add_child(clip)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025, 0.86)
	bg.size = Vector2(plate_w, band_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(bg)
	for ry in [0.0, band_h - 2.0]:
		var rule := ColorRect.new()
		rule.color = Color(1, 1, 1, 0.9)
		rule.position = Vector2(0, ry)
		rule.size = Vector2(plate_w, 2)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(rule)
	var accent := ColorRect.new()                  # a slim element-coloured edge at the left
	accent.color = col if element != "" else Color(1, 1, 1, 0.9)
	accent.position = Vector2(0, 2)
	accent.size = Vector2(8, band_h - 4)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(accent)
	clip.add_child(row)
	row.reset_size()
	var rx := roundf((plate_w - rs.x) * 0.5)
	row.position = Vector2(rx - 40.0, roundf((band_h - rs.y) * 0.5))
	row.modulate.a = 0.0
	var tw := create_tween()
	# in: wipe the plate left to right while the words slide in after it
	tw.tween_property(clip, "size:x", plate_w, CALLOUT_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(row, "position:x", rx, CALLOUT_IN + 0.08).set_delay(0.03).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(row, "modulate:a", 1.0, 0.1).set_delay(0.03)
	# hold: a slow drift so it isn't dead still
	tw.tween_property(row, "position:x", rx + 6.0, hold)
	# out: the words slide on and fade, the plate wipes off to the right
	tw.tween_property(row, "position:x", rx + 40.0, CALLOUT_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(row, "modulate:a", 0.0, CALLOUT_OUT * 0.8)
	tw.parallel().tween_property(clip, "position:x", x0 + plate_w, CALLOUT_OUT).set_delay(0.04).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bg, "position:x", -plate_w, CALLOUT_OUT).set_delay(0.04).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(host.queue_free)


func _callout_word(text: String, col: Color, font: Font, outline: Color, outline_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", CALLOUT_SIZE)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---- end D100 ----


# ---- D113 odds strip (marked edit) ----

## The confirmed blow's odds through the cutscene (author: "I want to see
## the chances of my miss when I see the miss"): a slim plate low centre,
## between the unit cards, listing Hit, Miss, Glance, Crit, Resist (magic
## only) and the expected damage; when the blow lands the outcome that
## happened lights up (white, or the element's colour) and the rest dim.
## Multi-target: the primary target's odds, plus "+N targets".
var _odds: PanelContainer
var _odds_cells := {}            # outcome key -> cell (Control)
var _odds_tw: Tween


func odds_show(o: Dictionary, target_name: String = "", extra: int = 0, element: String = "") -> void:
	if o.is_empty():
		odds_hide(true)
		return
	if _odds == null or not is_instance_valid(_odds):
		_odds = PanelContainer.new()
		_odds.add_theme_stylebox_override("panel", BWStyle.hud_style())
		_odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_odds)
	for c in _odds.get_children():
		_odds.remove_child(c)
		c.queue_free()
	_odds_cells.clear()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_odds.add_child(v)
	var head := Label.new()
	head.text = ("vs %s" % target_name if target_name != "" else "") + ("   +%d targets" % extra if extra > 0 else "")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	head.visible = head.text != ""
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var hit := float(o.get("hit", 0.0))
	var cells := [["hit", "HIT", "%d%%" % roundi(hit)], ["miss", "MISS", "%d%%" % roundi(100.0 - hit)],
		["glance", "GLANCE", "%d%%" % roundi(float(o.get("glance", 0.0)))],
		["crit", "CRIT", "%d%%" % roundi(float(o.get("crit", 0.0)))]]
	if o.has("resist"):
		cells.append(["resist", "RESIST", "%d%%" % roundi(float(o.resist))])
	cells.append(["exp", "EXPECTED", _num(float(o.get("expected", 0.0)))])
	for c in cells:
		var cell := _odds_cell(str(c[1]), str(c[2]), element)
		row.add_child(cell)
		_odds_cells[c[0]] = cell
	_odds.visible = true
	_odds.size = Vector2.ZERO
	_odds.reset_size()
	_place_odds.call_deferred()
	if _odds_tw:
		_odds_tw.kill()
	_odds.modulate.a = 0.0
	_odds_tw = create_tween()
	_odds_tw.tween_property(_odds, "modulate:a", 1.0, 0.25)


func _odds_cell(label: String, value: String, element: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1, 1, 1, 0)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("element", element)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", BWStyle.LABEL)
	v.add_child(l)
	var n := Label.new()
	n.text = value
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 20)
	n.add_theme_color_override("font_color", BWStyle.TEXT)
	v.add_child(n)
	return p


## Low centre, between the unit cards (the design space is 1600 wide; the
## cards take 536 px a side, so the strip keeps under ~500).
func _place_odds() -> void:
	if _odds == null or not is_instance_valid(_odds):
		return
	var vp := _root.get_viewport_rect().size
	var sz := _odds.get_combined_minimum_size()
	_odds.size = sz
	_odds.position = Vector2(roundf((vp.x - sz.x) * 0.5), vp.y - sz.y - 20.0)


## Light what happened: miss, else glance / crit / hit, plus resist.
func odds_result(res: Dictionary) -> void:
	if _odds == null or not is_instance_valid(_odds) or not _odds.visible:
		return
	var lit: Array = []
	if not bool(res.get("hit", false)):
		lit.append("miss")
	else:
		lit.append("glance" if res.get("glance", false) else ("crit" if res.get("crit", false) else "hit"))
		if res.get("resisted", false):
			lit.append("resist")
	for k in _odds_cells:
		var cell: PanelContainer = _odds_cells[k]
		var on: bool = k in lit
		var sb: StyleBoxFlat = cell.get_theme_stylebox("panel")
		var el := str(cell.get_meta("element", ""))
		var col := BWLook.element_color(el) if el != "" and k != "miss" else Color.WHITE
		if col.get_luminance() < 0.35:
			col = Color.WHITE                  # dark's ink would vanish on the plate
		sb.border_color = col if on else Color(1, 1, 1, 0)
		sb.bg_color = Color(1, 1, 1, 0.1) if on else Color(0, 0, 0, 0)
		var tw := create_tween()
		tw.tween_property(cell, "modulate:a", 1.0 if on else (0.6 if k == "exp" else 0.3), 0.12)
		if on:
			cell.pivot_offset = cell.size * 0.5
			tw.parallel().tween_property(cell, "scale", Vector2.ONE * 1.12, 0.08).from(Vector2.ONE)
			tw.tween_property(cell, "scale", Vector2.ONE, 0.12)
			var n: Label = cell.get_child(0).get_child(1)
			n.add_theme_color_override("font_color", col)
			if k == "miss" or k == "glance" or k == "crit" or k == "resist" or k == "hit":
				(cell.get_child(0).get_child(0) as Label).add_theme_color_override("font_color", col)


func odds_hide(now: bool = false) -> void:
	if _odds == null or not is_instance_valid(_odds):
		return
	if _odds_tw:
		_odds_tw.kill()
	if now:
		_odds.visible = false
		return
	_odds_tw = create_tween()
	_odds_tw.tween_property(_odds, "modulate:a", 0.0, 0.3)
	_odds_tw.tween_callback(func(): _odds.visible = false)

# ---- end D113 ----


# ---- D101 crit flash (marked edit) ----

## A crit's hit-stop beat (author: "screen goes white for a split second,
## then collapses into a thin horizontal line. Then the line disappears"):
## a CanvasLayer above everything (the HUD is layer 10), full white for
## FLASH_WHITE, collapsing vertically to a line across the centre over
## FLASH_COLLAPSE, the line thinning out over FLASH_LINE. Its tweens ignore
## Engine.time_scale, so the screen can freeze the world (time_scale 0)
## while it plays. Returns the total seconds.
const FLASH_WHITE := 0.08
const FLASH_COLLAPSE := 0.12
const FLASH_LINE := 0.08
var _flash_layer: CanvasLayer
## Review renders only (tools/present_shots.gd): stretch the flash so frame
## capture can see every stage. 1 in the game.
static var flash_slow := 1.0


func crit_flash() -> float:
	if _flash_layer == null or not is_instance_valid(_flash_layer):
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 120
		add_child(_flash_layer)
	for c in _flash_layer.get_children():
		c.queue_free()
	var vp := _root.get_viewport_rect().size
	var r := ColorRect.new()
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2.ZERO
	r.size = vp
	_flash_layer.add_child(r)
	var line_h := maxf(4.0, vp.y * 0.009)
	var cy := vp.y * 0.5
	var shape := func(h: float) -> void:
		r.size = Vector2(vp.x, h)
		r.position = Vector2(0, cy - h * 0.5)
	var slow := maxf(flash_slow, 0.01)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(FLASH_WHITE * slow)
	tw.tween_method(shape, vp.y, line_h, FLASH_COLLAPSE * slow).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# the line: thins to a hair and fades, pulled in a touch from the sides
	tw.tween_method(func(k: float):
		var h := lerpf(line_h, 1.0, k)
		var inset := vp.x * 0.18 * k
		r.size = Vector2(vp.x - inset * 2.0, h)
		r.position = Vector2(inset, cy - h * 0.5)
		r.color.a = 1.0 - k * k, 0.0, 1.0, FLASH_LINE * slow)
	tw.tween_callback(r.queue_free)
	return (FLASH_WHITE + FLASH_COLLAPSE + FLASH_LINE) * slow

# ---- end D101 ----


# ---- D102 status words and glyphs (marked edit) ----

## The author's short rules for the statuses the rules lane is adding or
## reworking; they win over BWSkills.STATUS (which may still carry the old
## text while that lane lands). Anything else reads BWSkills.STATUS, then the
## event's own label / rule, then the key.
const STATUS_VIEW := {
	"pinned": ["Pinned", "-2 move"],
	"staggered": ["Staggered", "no skills"],
	"blinded": ["Blinded", "no crit, reach 2"],
	"ward": ["Frost Ward", "negates the next elemental effect on it, then breaks"],
}
const WARD_KEYS := ["frost_ward", "ward"]
static var _glyphs := {}


## [name, rule] for a status key.
static func status_info(key: String, label: String = "", rule: String = "") -> Array:
	if STATUS_VIEW.has(key):
		var v: Array = STATUS_VIEW[key]
		if key == "pinned" and BWSkills.STATUS.has("pinned"):
			return [v[0], str(BWSkills.STATUS.pinned[1])]   # Pinned's exact rule is the rules lane's
		return v
	var st: Variant = BWSkills.STATUS.get(key)
	if st is Array and (st as Array).size() >= 2:
		return [str(st[0]), str(st[1])]
	return [label if label != "" else key.replace("_", " ").capitalize(), rule]


## A small glyph texture for a status (null = none): Pinned is a nail
## driven point-down; Frost Ward a hex shield. Drawn once, white with an ink
## edge, so it reads on the dark HUD and over the board.
static func status_glyph(key: String) -> Texture2D:
	var kind := "nail" if key == "pinned" else ("ward" if key in WARD_KEYS else "")
	if kind == "":
		return null
	if _glyphs.has(kind):
		return _glyphs[kind]
	var n := 64
	var inside := func(x: float, y: float) -> bool:
		if kind == "nail":
			if y >= 5.0 and y <= 17.0 and x >= 10.0 and x <= 54.0:
				return true                        # the head
			if y > 17.0 and y <= 44.0 and absf(x - 32.0) <= 7.0:
				return true                        # the shaft
			if y > 44.0 and y <= 61.0:
				return absf(x - 32.0) <= 7.0 * (61.0 - y) / 17.0   # the point
			return false
		# a hexagon outline (pointy-top), 7 px thick
		var p := Vector2(x - 32.0, y - 32.0)
		var hexd := maxf(absf(p.x) * 0.866 + absf(p.y) * 0.5, absf(p.y))
		return hexd <= 27.0 and hexd >= 18.0
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			if inside.call(x + 0.5, y + 0.5):
				img.set_pixel(x, y, Color.WHITE)
				continue
			# ink edge: within 3 px of the shape
			var near := false
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if dx * dx + dy * dy <= 10 and inside.call(x + dx + 0.5, y + dy + 0.5):
						near = true
						break
				if near:
					break
			if near:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.03, 1))
	var tex := ImageTexture.create_from_image(img)
	_glyphs[kind] = tex
	return tex


## BBCode text whose GLYPH_MARK key GLYPH_MARK slots are status glyphs,
## added as images sized to the small font.
const GLYPH_MARK := "§§"

func _set_rich(rt: RichTextLabel, text: String) -> void:
	if not text.contains(GLYPH_MARK):
		rt.text = text
		return
	rt.clear()
	var parts := text.split(GLYPH_MARK)
	for i in parts.size():
		if i % 2 == 0:
			rt.append_text(parts[i])
		else:
			var tex := status_glyph(parts[i])
			if tex:
				rt.add_image(tex, BWStyle.F_SMALL + 6, BWStyle.F_SMALL + 6)

# ---- end D102 ----


# ---- D122 / D123 cutscene tiers and skipping (marked edit) ----

var _toast: PanelContainer
var _toast_tw: Tween
var _skip_hint: Label
var _skip_tw: Tween


## A small notice under the turn order ("Cutscenes: Fast"), gone in ~1.4 s.
func toast(text: String) -> void:
	if _toast == null or not is_instance_valid(_toast):
		_toast = PanelContainer.new()
		_toast.add_theme_stylebox_override("panel", BWStyle.hud_style())
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_child(l)
		_root.add_child(_toast)
	(_toast.get_child(0) as Label).text = text
	_toast.visible = true
	_toast.size = Vector2.ZERO
	_toast.reset_size()
	var vp := _root.get_viewport_rect().size
	_toast.position = Vector2(roundf((vp.x - _toast.get_combined_minimum_size().x) * 0.5), 186.0)
	if _toast_tw:
		_toast_tw.kill()
	_toast.modulate.a = 0.0
	_toast_tw = create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tw.tween_interval(1.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tw.tween_callback(func(): _toast.visible = false)


func toast_text() -> String:
	return (_toast.get_child(0) as Label).text if _toast and is_instance_valid(_toast) and _toast.visible else ""


## The faint "hold Space to skip" line low on screen, for the first few FULL
## cutscenes (BWSettings counts them).
func skip_hint(on: bool) -> void:
	if _skip_hint == null or not is_instance_valid(_skip_hint):
		_skip_hint = Label.new()
		_skip_hint.text = "hold Space to skip"
		_skip_hint.add_theme_font_size_override("font_size", 14)
		_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_skip_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_skip_hint.add_theme_constant_override("outline_size", 5)
		_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skip_hint.anchor_left = 0.5                  # low centre, just above the odds strip
		_skip_hint.anchor_right = 0.5
		_skip_hint.anchor_top = 1.0
		_skip_hint.anchor_bottom = 1.0
		_skip_hint.offset_left = -200
		_skip_hint.offset_right = 200
		_skip_hint.offset_top = -152
		_skip_hint.offset_bottom = -132
		_root.add_child(_skip_hint)
		_skip_hint.modulate.a = 0.0
	if _skip_tw:
		_skip_tw.kill()
	_skip_tw = create_tween()
	_skip_tw.tween_property(_skip_hint, "modulate:a", 1.0 if on else 0.0, 0.3 if on else 0.2)


func skip_hint_shown() -> bool:
	return _skip_hint != null and is_instance_valid(_skip_hint) and _skip_hint.modulate.a > 0.05


## A crit outside a FULL cutscene (Fast / Minimal modes, or while skipping):
## a quick white pulse with no freeze. Returns at once.
func crit_flash_tiny() -> void:
	if _flash_layer == null or not is_instance_valid(_flash_layer):
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 120
		add_child(_flash_layer)
	var vp := _root.get_viewport_rect().size
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.38)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = vp
	_flash_layer.add_child(r)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(r, "color:a", 0.0, 0.14).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)

# ---- end D122 / D123 ----


# ---- D140/D145 obelisks (marked edit) ----

var _obj_panel: PanelContainer
var _obj_rows := {}              # D378: "stones" -> { bar, label, row } (one shared row)


## The objective plate, top left. D378: the stones share ONE life, so the
## plate shows one row: both stones' portraits, "The Stones   150 / 220" and
## one bar (each stone's own bar on the board mirrors it). BROKEN when it's
## gone. Built on first call, then updated.
func set_objectives(stones: Array) -> void:
	if stones.is_empty():
		return
	if _obj_panel == null:
		_obj_panel = PanelContainer.new()
		_obj_panel.add_theme_stylebox_override("panel", BWStyle.frame_style())
		_obj_panel.offset_left = 16
		_obj_panel.offset_top = 10
		_obj_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		_root.add_child(_obj_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		_obj_panel.add_child(v)
		var t := Label.new()
		t.text = "BREAK THE STONES"
		t.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		t.add_theme_color_override("font_color", BWStyle.LABEL)
		v.add_child(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var tips: PackedStringArray = []
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 2)
		for o in stones:
			icons.add_child(BWWidgets.Portrait.new(o, 30.0))     # D156: each stone, rendered
			tips.append("%s
%s
%s" % [o.name, (o as BWObelisk).rule_text(), (o as BWObelisk).codex_line()])
		row.tooltip_text = "

".join(tips)
		row.add_child(icons)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		col.add_child(nm)
		var bar := BWWidgets.HPBar.new(Vector2(220, 10))
		bar.enemy = false
		bar.track = true
		col.add_child(bar)
		row.add_child(col)
		v.add_child(row)
		_obj_rows["stones"] = { "bar": bar, "label": nm, "row": row }
	var r: Dictionary = _obj_rows.get("stones", {})
	if r.is_empty():
		return
	var o: BWUnit = stones[0]                      # D378: every stone mirrors the pool
	var alive := stones.all(func(x: BWUnit): return x.alive())
	r.bar.set_hp(o.hp, o.max_hp())
	r.label.text = "The Stones   %d / %d" % [o.hp, o.max_hp()] if alive else "The Stones   BROKEN"
	r.row.modulate = Color.WHITE if alive else Color(1, 1, 1, 0.45)


## The texts of the objective plate (probes and review tools).
func objective_texts() -> Array:
	var out: Array = []
	for id in _obj_rows:
		out.append(str(_obj_rows[id].label.text))
	return out


## D145: an obelisk's hover card: name, what it is, HP, speed, its rule and
## the pulse in numbers, the codex line.
func _fill_obelisk_card(c: Dictionary, o: BWObelisk) -> void:
	c.icon.set_unit(o)                              # D156: the stone's own portrait, not a head
	c.bar.enemy = o.look() != "bright"
	c.bar.set_hp(o.hp, o.max_hp())
	var dim := BWStyle.TEXT_DIM.to_html(false)
	var lines: PackedStringArray = []
	if o is BWLilFella:                             # ---- D348: the little one's own card
		c.bar.enemy = false
		lines.append("[font_size=%d][b]%s[/b][/font_size]  [color=#%s]keep it alive[/color]" % [BWStyle.F_NAME, o.name, dim])
		lines.append("[font_size=%d]HP %d / %d    Move %d    Speed %d[/font_size]" % [BWStyle.F_BODY, o.hp, o.max_hp(), o.move_range(), o.speed()])
		lines.append("[font_size=%d]%s[/font_size]" % [BWStyle.F_SMALL, o.rule_text()])
		lines.append("[font_size=%d][color=#%s]Not yours to command: on its turn it runs from the horde, toward your squad, never onto fire, dark or a shock. Nothing of yours can hurt, move or status it. If it falls, the fight is lost.[/color][/font_size]" % [BWStyle.F_SMALL, dim])
		lines.append("[font_size=%d][color=#%s][i]“%s”[/i][/color][/font_size]" % [BWStyle.F_SMALL, BWStyle.FAINT.to_html(false), o.codex_line()])
		_set_rich(c.text, "\n".join(lines))
		return
	lines.append("[font_size=%d][b]%s[/b][/font_size]  [color=#%s]obelisk · objective[/color]" % [BWStyle.F_NAME, o.name, dim])
	lines.append("[font_size=%d]HP %d / %d (shared)    Speed %d    never moves[/font_size]" % [BWStyle.F_BODY, o.hp, o.max_hp(), o.speed()])
	lines.append("[font_size=%d]%s[/font_size]" % [BWStyle.F_SMALL, o.rule_text()])
	lines.append("[font_size=%d][color=#%s]Pulse: flat %d to every unit on the map, both sides; no hit roll, ignores DEF, RES and wards. Takes no ground damage and no statuses; can't be moved. The enemy never strikes it.[/color][/font_size]" % [
		BWStyle.F_SMALL, dim, o.pulse_damage])
	lines.append("[font_size=%d][color=#%s]DEF %d   RES %d   DEX %d[/color][/font_size]" % [BWStyle.F_SMALL, dim, o.stat("def"), o.stat("res"), o.stat("dex")])
	lines.append("[font_size=%d][color=#%s][i]“%s”[/i][/color][/font_size]" % [BWStyle.F_SMALL, BWStyle.FAINT.to_html(false), o.codex_line()])
	_set_rich(c.text, "\n".join(lines))


## A turn-order / plate icon for a stone: a monolith on a plinth, white with
## ink glyphs (the Lantern) or black with pale glyphs (the Well).
class ObeliskIcon:
	extends Control
	var bright := true
	var selected := false

	func _init(is_bright: bool = true, px: float = 42.0) -> void:
		bright = is_bright
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var s := size
		var bg := Color(0.20, 0.20, 0.22, 0.95) if bright else BWStyle.PANEL_BG_LIGHT
		draw_rect(Rect2(Vector2.ZERO, s), bg)
		draw_rect(Rect2(Vector2.ZERO, s), Color.WHITE if selected else BWStyle.BORDER_SOFT, false, 3.0 if selected else 1.0)
		var body := Color.WHITE if bright else Color(0.06, 0.06, 0.07)
		var line := Color.BLACK if bright else Color(0.85, 0.8, 1.0)
		var cx := s.x * 0.5
		var shaft := PackedVector2Array([Vector2(cx - s.x * 0.16, s.y * 0.84), Vector2(cx + s.x * 0.16, s.y * 0.84),
			Vector2(cx + s.x * 0.11, s.y * 0.26), Vector2(cx, s.y * 0.1), Vector2(cx - s.x * 0.11, s.y * 0.26)])
		draw_colored_polygon(shaft, body)
		var closed := shaft.duplicate()
		closed.append(shaft[0])
		draw_polyline(closed, Color.BLACK if bright else Color(0.85, 0.85, 0.9), 1.5)
		draw_rect(Rect2(Vector2(s.x * 0.22, s.y * 0.84), Vector2(s.x * 0.56, s.y * 0.08)), body)
		for k in 3:                                   # glyph marks
			var y := s.y * (0.36 + 0.15 * k)
			draw_line(Vector2(cx - s.x * 0.06, y), Vector2(cx + s.x * 0.06, y), line, 1.5)
		if not bright:                                # the Well's hole for a heart
			draw_arc(Vector2(cx, s.y * 0.5), s.x * 0.08, 0.0, TAU, 12, line, 1.5)

# ---- end D140/D145 ----

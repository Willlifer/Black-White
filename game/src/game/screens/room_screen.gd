class_name BWRoomScreen
extends Control
## D190: the room select. After the day (or the hall, before fight 1) and
## before the pre-battle, the run offers two rooms (BWRooms, D186-D188): two
## big cards side by side, each with
##   the difficulty tag (Standard / Hard) and the map's name
##   a thumbnail of the map (BWMapThumbs: top-down, your deploy hexes ringed
##     grey, the enemy start in black)
##   the three enemies: portrait, name, element, weapon (letter) and level
##   the reward line
## Hovering a card lifts it and opens its detail (each enemy's HP, Move and
## Speed); hovering an enemy shows its full unit card (BWUnitCard). Click a
## card, or 1 / 2, to take it (Left / Right + Enter also work). Esc goes back
## when the flow allows (before fight 1: to the hall); after a day it can't.
## Emits done(index) with 0 = Standard, 1 = Hard, or -1 = back.

signal done(choice: int)

const CARD_W := 700.0
const THUMB_H := 330.0
const PORTRAIT := 92.0

var run: BWRun
var can_back := false
var rooms: Array = []
var enemies: Array = []          # per room: [BWUnit]
var cards: Array = []            # PanelContainer per room
var hover := -1                  # the card under the cursor (or the keyboard's)
var chosen := -1
var unit_card: BWUnitCard
var _thumbs: Array = []          # TextureRect per room
var _details: Array = []         # per room: [Label] (shown on hover)
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BWStyle.theme()
	rooms = BWRooms.offer(run)
	for r in rooms:
		var es := run.enemies_for(run.fight, r)
		for e in es:
			e.team = "enemy"
		enemies.append(es)
	var warm: Array = []
	for es in enemies:
		warm.append_array(es.slice(0, 3))
	BWPortraits.prewarm(warm)
	var mt := BWMapThumbs.ensure(self)
	mt.thumb_ready.connect(_on_thumb)
	_build()
	for i in rooms.size():
		_set_thumb(i)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 22
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var t := Label.new()
	t.text = "Choose your fight"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	top.add_child(t)
	var sub := Label.new()
	sub.text = "Fight %d of %d  ·  two rooms, one door" % [run.fight, BWRun.FIGHTS]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	top.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 44)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 128
	row.offset_bottom = -64
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for i in rooms.size():
		var c := _card(i)
		row.add_child(c)
		cards.append(c)
	_hint = Label.new()
	_hint.text = "Click a room, or press 1 / 2" + ("   ·   Esc: back to the hall" if can_back else "")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -48
	_hint.offset_bottom = -18
	_hint.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	_hint.add_theme_color_override("font_color", BWStyle.FAINT)
	add_child(_hint)
	unit_card = BWUnitCard.new()
	unit_card.visible = false
	unit_card.top_level = true
	unit_card.z_index = 10
	add_child(unit_card)
	_restyle()


func _card(i: int) -> PanelContainer:
	var room: Dictionary = rooms[i]
	var hard: bool = room.kind == BWRooms.HARD
	var enc := str(room.get("encounter", ""))      # D208: a special encounter in the Hard room's place
	var c := PanelContainer.new()
	c.custom_minimum_size = Vector2(CARD_W, 0)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.resized.connect(func(): c.pivot_offset = c.size / 2.0)
	c.mouse_entered.connect(func(): _hover(i))
	c.mouse_exited.connect(func(): _unhover(i))
	c.gui_input.connect(func(ev): _card_input(i, ev))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	# tag, name, key
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(_tag(BWRooms.NAMES[room.kind], hard))
	var title := Label.new()
	var map_name := str(BWBoard.load_file("res://maps/%s.json" % room.map).name)
	title.text = BWEncounters.NAMES[enc] if enc != "" else map_name
	title.add_theme_font_size_override("font_size", BWStyle.F_NAME)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if enc != "":
		var on := Label.new()
		on.text = "on " + map_name
		on.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		on.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
		on.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(on)
		head.move_child(on, 2)
	var key := Label.new()
	key.text = "[%d]" % (i + 1)
	key.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	key.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	head.add_child(key)
	if str(room.get("weather", "")) != "":         # D252: the weather tag
		v.add_child(BWWeatherIcon.strip(str(room.weather)))
	# the map
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = BWMapThumbs.BG
	fsb.border_color = Color(1, 1, 1, 0.35)
	fsb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(frame)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(CARD_W - 30, THUMB_H - (60.0 if str(room.get("weather", "")) != "" else 0.0))   # D252: room for the weather line
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tr)
	_thumbs.append(tr)
	# the enemies
	v.add_child(BWStyle.section_label("You face"))
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 12)
	er.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(er)
	var det: Array = []
	var shown: Array = enemies[i]
	if shown.size() > BWRun.DEPLOY:                # D208: a crowd shows one of its kind, counted
		shown = [shown[0]]
	for e in shown:
		var col := _enemy(e, i, det, enemies[i].size() if shown.size() < enemies[i].size() else 1)
		er.add_child(col)
	if shown.size() == 1:
		er.alignment = BoxContainer.ALIGNMENT_CENTER
	_details.append(det)
	v.add_child(HSeparator.new())
	# the reward
	var rw := Label.new()
	rw.text = BWRooms.reward_text(run, room)
	rw.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	rw.add_theme_color_override("font_color", BWStyle.TEXT if hard else BWStyle.TEXT_DIM)
	v.add_child(rw)
	var note := Label.new()
	note.text = BWRooms.hard_note() if hard else "The usual squad for this fight"
	if enc != "":
		note.text = BWEncounters.HINTS[enc]          # D208: the counter hint
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(CARD_W - 40, 0)
	note.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	note.add_theme_color_override("font_color", BWStyle.TEXT if enc != "" else BWStyle.FAINT)
	v.add_child(note)
	return c


## The difficulty tag: Standard an outline, Hard solid white with black text.
func _tag(text: String, hard: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE if hard else Color(0, 0, 0, 0)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	l.add_theme_color_override("font_color", Color.BLACK if hard else Color.WHITE)
	p.add_child(l)
	return p


func _enemy(e: BWUnit, i: int, det: Array, count: int = 1) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2((CARD_W - 60) / 3.0, 0)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.mouse_entered.connect(func(): _show_unit(e, col, i))
	col.mouse_exited.connect(func(): _hide_unit(e))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cc)
	var p := BWWidgets.Portrait.new(e, PORTRAIT, true)
	cc.add_child(p)
	var n := _small(e.name if count <= 1 else "%s  ×%d" % [e.name.rstrip("0123456789 "), count], BWStyle.F_BODY, BWStyle.TEXT)
	col.add_child(n)
	var ec := BWGearText.readable(BWLook.element_color(e.element))
	var el := _small("◆ " + BWKanji.prefix(e.element) + BWText.label(e.element) if e.element != "" else "No element", BWStyle.F_SMALL, ec)
	BWKanji.fallback(el)                                   # D231: the kanji, when on
	col.add_child(el)
	col.add_child(_small(("Melee weapons" if count > 1 else "%s (%s)" % [BWText.weapon(e.weapon_class), e.expertise_letter(e.weapon_class)]) + "  ·  Lv %d" % e.level,
		BWStyle.F_SMALL, BWStyle.LABEL))
	var d := _small("HP %d  ·  Move %d  ·  Spd %d" % [e.max_hp(), e.move_range(), e.speed()], BWStyle.F_SMALL - 1, BWStyle.TEXT_DIM)
	d.visible = false
	col.add_child(d)
	det.append(d)
	return col


func _small(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	return l


# ---------------------------------------------------------------- thumbnails

func _set_thumb(i: int) -> void:
	var tex := BWMapThumbs.thumb(str(rooms[i].map))
	if tex:
		_thumbs[i].texture = tex


func _on_thumb(map: String) -> void:
	for i in rooms.size():
		if str(rooms[i].map) == map:
			_set_thumb(i)


## Every thumbnail on the cards has landed (tools wait on it).
func thumbs_ready() -> bool:
	return _thumbs.all(func(tr): return tr.texture != null)


# ---------------------------------------------------------------- hover

func _hover(i: int) -> void:
	hover = i
	_restyle()


func _unhover(i: int) -> void:
	# leaving the card for one of its own children keeps the hover
	if hover == i and not cards[i].get_global_rect().has_point(get_global_mouse_position()):
		hover = -1
		_restyle()


## Cards: the hovered one lifts (scale, a heavier border, its detail lines
## open); the other dims a little. Hard always carries the heavier edge.
func _restyle() -> void:
	for i in cards.size():
		var hard: bool = rooms[i].kind == BWRooms.HARD
		var on := i == hover
		var sb := BWStyle.box_style()
		sb.border_color = Color.WHITE if on else Color(1, 1, 1, 0.85 if hard else 0.5)
		sb.set_border_width_all(4 if on else (3 if hard else 2))
		sb.bg_color = Color(0.07, 0.07, 0.08, 0.97) if on else BWStyle.PANEL_BG
		sb.set_content_margin_all(16)
		cards[i].add_theme_stylebox_override("panel", sb)
		var tw: Tween = cards[i].create_tween()
		tw.tween_property(cards[i], "scale", Vector2.ONE * (1.025 if on else 1.0), 0.12)
		cards[i].modulate = Color(1, 1, 1, 1) if on or hover < 0 else Color(0.78, 0.78, 0.8, 1)
		for d in _details[i]:
			d.visible = on


func _show_unit(e: BWUnit, col: Control, i: int) -> void:
	_hover(i)
	unit_card.show_unit(e)
	unit_card.visible = true
	var r := col.get_global_rect()
	var vr := get_viewport_rect()
	var w := unit_card.size.x
	var x := r.end.x + 12 if r.end.x + 12 + w < vr.size.x - 8 else r.position.x - 12 - w
	var y := clampf(r.position.y - 60, 8, vr.size.y - unit_card.size.y - 8)
	unit_card.global_position = Vector2(clampf(x, 8, vr.size.x - w - 8), y)
	BWEsc.push(unit_card, func(): _hide_unit(null), { "name": "room unit card", "hover": true })


func _hide_unit(e: BWUnit) -> void:
	if e != null and unit_card.unit != e:
		return
	unit_card.visible = false
	BWEsc.remove(unit_card)


# ---------------------------------------------------------------- choosing

func _card_input(i: int, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		choose(i)


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo) or chosen >= 0:
		return
	match ev.keycode:
		KEY_1, KEY_KP_1: choose(0)
		KEY_2, KEY_KP_2: choose(1)
		KEY_LEFT: _hover(0)
		KEY_RIGHT: _hover(mini(1, rooms.size() - 1))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if hover >= 0:
				choose(hover)
		KEY_ESCAPE:
			if can_back:
				chosen = 99
				done.emit(-1)
			else:
				_hint.text = "Choose one: the day is done, there's no going back"
		_: return
	get_viewport().set_input_as_handled()


## Take room i: a short flash on the card, then done(i).
func choose(i: int) -> void:
	if chosen >= 0 or i < 0 or i >= rooms.size():
		return
	chosen = i
	_hide_unit(null)
	hover = i
	_restyle()
	for k in cards.size():
		if k != i:
			cards[k].modulate = Color(0.4, 0.4, 0.42, 1)
	var tw := create_tween()
	tw.tween_property(cards[i], "scale", Vector2.ONE * 1.05, 0.12)
	tw.tween_property(cards[i], "scale", Vector2.ONE, 0.18)
	await tw.finished
	done.emit(i)

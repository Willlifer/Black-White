class_name BWItemTile
extends Control
## One item as a square tile: its rendered icon (BWItemIcons), a tier badge,
## an element-coloured border (grey when plain). Used for inventory and shop
## grids and, with `slot` set, as a paperdoll slot box.
##
## Input: hover -> `hovered`, click -> `picked`, double-click -> `activated`,
## left-drag -> Godot GUI drag-and-drop with { bw_item, from } as the data.
## A tile is also a drop target when `accept` (Callable(item) -> bool) is set:
## a drop calls `on_drop(item)`.

signal hovered(tile: BWItemTile)
signal unhovered(tile: BWItemTile)
signal picked(tile: BWItemTile)
signal activated(tile: BWItemTile)

var item: Dictionary = {}
var slot := ""                    ## paperdoll slot box when set ("head", ...)
var source := "inventory"         ## drag data "from": inventory | slot | shop
var selected := false
var marked := false               ## a second selection state (trade: "yours")
var blocked := false              ## this unit can't equip it: hatched
var draggable := true
var accept: Callable              ## (item) -> bool; unset = not a drop target
var on_drop: Callable             ## (item) -> void
var caption := ""                 ## drawn under the tile (slot boxes)
var _hover := false
var _drop_hint := false
var _font: Font


func _init(p_item: Dictionary = {}, px: float = 84.0) -> void:
	item = p_item
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_font = get_theme_default_font()
	mouse_entered.connect(func(): _hover = true; queue_redraw(); hovered.emit(self))
	mouse_exited.connect(func(): _hover = false; queue_redraw(); unhovered.emit(self))
	var r := BWItemIcons.instance()
	if r:
		r.icon_ready.connect(_on_icon)


func set_item(p_item: Dictionary) -> void:
	item = p_item
	tooltip_text = ""
	queue_redraw()


func _on_icon(_key: String) -> void:
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		if ev.double_click:
			activated.emit(self)
		else:
			picked.emit(self)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	var ghost := BWItemTile.new(item, size.x)
	ghost.modulate.a = 0.85
	ghost.draggable = false
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -size / 2.0
	set_drag_preview(holder)
	return { "bw_item": item, "from": source, "slot": slot }


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = accept.is_valid() and data is Dictionary and data.has("bw_item") and accept.call(data.bw_item)
	if ok != _drop_hint:
		_drop_hint = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_drop_hint = false
	queue_redraw()
	if on_drop.is_valid():
		on_drop.call(data.bw_item)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drop_hint:
		_drop_hint = false
		queue_redraw()


func _draw() -> void:
	var s := Vector2(size.x, size.x)          # square; a caption may sit below
	var r := Rect2(Vector2.ZERO, s)
	var el := BWGearText.item_element(item)
	var edge := BWLook.element_color(el) if el != "" else Color(1, 1, 1, 0.35)
	var bg := BWStyle.PANEL_BG_LIGHT if not _hover else Color(0.16, 0.16, 0.18, 0.95)
	if selected:
		bg = Color(0.20, 0.20, 0.23, 0.98)
	draw_rect(r, Color(0, 0, 0, 0.5))
	draw_rect(r.grow(-1), bg)
	if item.is_empty():
		_draw_empty(r)
	else:
		var tex: Texture2D = null if str(item.get("kind", "")) == "scroll" else BWItemIcons.for_item(item)
		if str(item.get("kind", "")) == "scroll":           # D203: drawn, not rendered
			BWItemIcons.draw_scroll(self, r.grow(-s.x * 0.08), str(item.get("element", "")))
		elif tex:
			draw_texture_rect(tex, r.grow(-6), false)
		else:
			# not rendered yet: the slot glyph as a placeholder
			_slot_glyph(str(item.get("slot", "")), r.grow(-s.x * 0.28), Color(1, 1, 1, 0.25))
		if BWEffects.cursed(str(item.get("enchant", ""))):    # D201: the curse mark
			var cp := maxf(16.0, s.x * 0.22)
			BWItemIcons.draw_curse(self, Vector2(s.x - cp - 4, 4), cp)
		if blocked:
			draw_rect(r.grow(-1), Color(0, 0, 0, 0.55))
			for k in range(-int(s.x), int(s.x), 10):
				draw_line(Vector2(k, s.y), Vector2(k + s.y, 0), Color(1, 1, 1, 0.10), 2.0)
		BWGearText.draw_tier(self, str(item.get("tier", "E")), Vector2(4, 4), 20.0, _font)
	# element border: colour carries the infusion; weight carries selection
	var bw := 2.0
	if selected or _drop_hint:
		bw = 4.0
	draw_rect(r.grow(-bw / 2.0), edge if not item.is_empty() else Color(1, 1, 1, 0.3), false, bw)
	if selected:
		draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
	if marked:
		draw_rect(r.grow(5.0), Color(1, 1, 1, 0.65), false, 1.5)
	if _drop_hint:
		draw_rect(r.grow(3.0), Color.WHITE, false, 2.0)
	if caption != "":
		var fs := BWStyle.F_SMALL - 2
		var tw := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font, Vector2((s.x - tw.x) / 2.0, s.y + fs + 3), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BWStyle.LABEL)


func _draw_empty(r: Rect2) -> void:
	for k in range(int(r.position.x) + 6, int(r.end.x) - 6, 8):
		draw_line(Vector2(k, r.position.y + 6), Vector2(k + 4, r.position.y + 6), Color(1, 1, 1, 0.18), 1.0)
		draw_line(Vector2(k, r.end.y - 6), Vector2(k + 4, r.end.y - 6), Color(1, 1, 1, 0.18), 1.0)
	if slot != "":
		_slot_glyph(slot, r.grow(-r.size.x * 0.26), Color(1, 1, 1, 0.22))


## Silhouette of a slot: helm, torso, legs, blade.
func _slot_glyph(which: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := r.size.x / 2.0
	match which:
		"head":
			draw_arc(c + Vector2(0, s * 0.15), s * 0.7, PI, TAU, 20, col, 3.0)
			draw_line(c + Vector2(-s * 0.9, s * 0.15), c + Vector2(s * 0.9, s * 0.15), col, 3.0)
		"chest":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, -s * 0.7), c + Vector2(s * 0.9, -s * 0.7),
				c + Vector2(s * 0.6, s * 0.9), c + Vector2(-s * 0.6, s * 0.9)]), col)
		"legs":
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.9), Vector2(s * 1.4, s * 0.4)), col)
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.5), Vector2(s * 0.55, s * 1.4)), col)
			draw_rect(Rect2(c + Vector2(s * 0.15, -s * 0.5), Vector2(s * 0.55, s * 1.4)), col)
		_:
			draw_line(c + Vector2(-s * 0.8, s * 0.8), c + Vector2(s * 0.8, -s * 0.8), col, 4.0)
			draw_line(c + Vector2(-s * 0.75, s * 0.25), c + Vector2(-s * 0.25, s * 0.75), col, 4.0)

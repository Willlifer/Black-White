class_name BWGearText
## Shared words, colours and glyphs for the pre-battle screen's gear and
## stat views (BWItemCard, BWStatPanel, BWUnitCard, tiles, slots). Read-only
## over the run and the data tables; draws nothing on its own except the
## stat glyphs and the element swatch.

const STAT_NAMES := {
	"con": "Constitution", "str": "Strength", "dex": "Dexterity", "wil": "Willpower",
	"def": "Defense", "res": "Resistance", "spd": "Speed",
}
const SLOT_NAMES := { "head": "Head", "chest": "Chest", "legs": "Legs", "main_hand": "Main hand" }
const WEIGHT_NAMES := { "heavy": "Heavy armour", "ranger": "Ranger gear", "wizard": "Wizard garb" }
const MINUS := "−"


static func hex(c: Color) -> String:
	return c.to_html(false)


## Element colour of an item (its enchantment), or "" when plain.
static func item_element(item: Dictionary) -> String:
	return BWRun.item_element(item) if not item.is_empty() else ""


static func item_color(item: Dictionary) -> Color:
	var el := item_element(item)
	return BWLook.element_color(el) if el != "" else BWStyle.TEXT


## Element colour, lifted for text on the near-black panels: dark's deep
## violet is unreadable at body size, so it is lightened (the hue stays).
static func readable(c: Color) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color.WHITE, clampf(0.42 - l, 0.0, 0.42) * 1.2) if l < 0.42 else c


## Name without the trailing " [T]" tier tag (the tier gets its own badge).
static func plain_name(item: Dictionary) -> String:
	var n := BWRun.item_name(item)
	var i := n.rfind(" [")
	return n.substr(0, i) if i > 0 else n


## "Chest · Heavy armour" / "Weapon · Axe".
static func kind(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	if str(item.slot) == "main_hand":
		return "Weapon · %s" % str(BWData.row("weapons", str(item.weight)).get("name", str(item.weight).capitalize()))
	return "%s · %s" % [SLOT_NAMES.get(str(item.slot), str(item.slot)), WEIGHT_NAMES.get(str(item.weight), str(item.weight))]


static func enchant(item: Dictionary) -> Dictionary:
	return BWData.row("enchantments", str(item.get("enchant", "")))


static func passive_text(item: Dictionary) -> String:
	var e := enchant(item)
	return str(e.get("effect_text", "")) if not e.is_empty() else ""


## Abilities the base item teaches after LEARN_BATTLES battles worn.
static func teaches(item: Dictionary) -> Array:
	var out: Array = []
	for a in BWData.list(BWData.row("equipment", str(item.get("base", ""))).get("ability_id", "")):
		var row := BWData.row("abilities", a)
		if not row.is_empty():
			out.append(row)
	return out


## Stat bonus from worn equipment alone.
static func gear_bonus(u: BWUnit, stat: String) -> int:
	var v := 0
	for item in u.equipment.values():
		v += int(item.get("stats", {}).get(stat, 0))
	return v


## Whatever else u.stat() adds outside a battle (own passives, stat shares).
static func other_bonus(u: BWUnit, stat: String) -> int:
	return u.stat(stat) - int(u.stats.get(stat, 0)) - gear_bonus(u, stat)


## [ok, line] for "can this unit equip it?" (brief: a weapon needs that
## class's expertise at the item's tier or better; armour has no rule).
static func equip_check(run: BWRun, u: BWUnit, item: Dictionary) -> Array:
	if item.is_empty() or u == null:
		return [true, ""]
	if str(item.slot) != "main_hand":
		return [true, "Armour — anyone can wear it."]
	var wc := str(item.weight)
	var need := str(item.tier)
	var have := u.expertise_letter(wc)
	var wname := BWText.weapon(wc)
	if run.can_equip(u, item):
		return [true, "%s's %s expertise %s meets tier %s." % [u.name, wname, have, need]]
	return [false, "Needs %s expertise %s — %s has %s." % [wname, need, u.name, have]]


## Weapon classes in data order.
static func weapon_classes() -> Array:
	return BWData.table("weapons").map(func(r): return str(r.id))


# ------------------------------------------------------------------ glyphs

## A small white pictogram per stat, drawn into `r` (square). Plain shapes
## in the HUD's line weight: heart, fist-wedge, crosshair, star, shield,
## warded ring, chevrons.
static func draw_glyph(ci: CanvasItem, stat: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var w := maxf(1.5, s * 0.16)
	match stat:
		"con":
			var pts := PackedVector2Array()
			for i in 33:
				var t := TAU * float(i) / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
				pts.append(c + Vector2(x, y) * s / 17.5 + Vector2(0, s * 0.05))
			ci.draw_colored_polygon(pts, col)
		"str":
			# a blade: point up, cross-guard, grip
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.95), c + Vector2(s * 0.2, -s * 0.6),
				c + Vector2(s * 0.2, s * 0.25), c + Vector2(-s * 0.2, s * 0.25), c + Vector2(-s * 0.2, -s * 0.6)]), col)
			ci.draw_line(c + Vector2(-s * 0.6, s * 0.35), c + Vector2(s * 0.6, s * 0.35), col, w * 1.2)
			ci.draw_line(c + Vector2(0, s * 0.4), c + Vector2(0, s * 0.95), col, w * 1.2)
		"dex":
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, col, w)
			ci.draw_circle(c, s * 0.16, col)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * s * 0.38, c + d * s * 0.98, col, w)
		"wil":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + PI * float(i) / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * (0.95 if i % 2 == 0 else 0.42))
			ci.draw_colored_polygon(pts, col)
		"def":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.78, -s * 0.8), c + Vector2(s * 0.78, -s * 0.8),
				c + Vector2(s * 0.74, s * 0.05), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.74, s * 0.05)]), col)
			ci.draw_line(c + Vector2(0, -s * 0.62), c + Vector2(0, s * 0.62), Color(0, 0, 0, 0.75), w)
		"res":
			ci.draw_arc(c, s * 0.86, 0, TAU, 32, col, w)
			ci.draw_arc(c, s * 0.52, 0, TAU, 28, col, w)
			ci.draw_circle(c, s * 0.2, col)
		"spd":
			for k in 2:
				var x0 := -s * 0.75 + k * s * 0.7
				ci.draw_polyline(PackedVector2Array([c + Vector2(x0, -s * 0.7), c + Vector2(x0 + s * 0.6, 0),
					c + Vector2(x0, s * 0.7)]), col, w * 1.4)
		"hp":
			ci.draw_rect(Rect2(c - Vector2(s * 0.22, s * 0.8), Vector2(s * 0.44, s * 1.6)), col)
			ci.draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.22), Vector2(s * 1.6, s * 0.44)), col)
		"move":
			for k in 3:
				var p := c + Vector2(-s * 0.55 + k * s * 0.55, s * (0.45 - 0.45 * k))
				ci.draw_circle(p, s * 0.2, col)
		"speed":
			ci.draw_arc(c, s * 0.82, -PI * 1.25, PI * 0.25, 24, col, w)
			ci.draw_line(c, c + Vector2(cos(-PI / 4), sin(-PI / 4)) * s * 0.66, col, w * 1.3)
			ci.draw_circle(c, s * 0.14, col)


## An element swatch: a filled diamond in the element colour with an ink rim
## (a hollow one for "no element").
class Swatch:
	extends Control
	var element := ""

	func _init(el: String = "", px: float = 16.0) -> void:
		element = el
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.48
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		if element == "":
			pts.append(pts[0])
			draw_polyline(pts, BWStyle.FAINT, 1.5)
			return
		draw_colored_polygon(pts, BWLook.element_color(element))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 1.2)


## A tier badge: the letter in a small ink plate with a white rim.
static func draw_tier(ci: CanvasItem, tier: String, at: Vector2, px: float, font: Font) -> void:
	var r := Rect2(at, Vector2(px, px))
	ci.draw_rect(r, Color(0, 0, 0, 0.9))
	ci.draw_rect(r, Color(1, 1, 1, 0.9), false, 1.5)
	var fs := int(px * 0.72)
	var tw := font.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(font, at + Vector2((px - tw.x) / 2.0, px * 0.5 + fs * 0.36), tier, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

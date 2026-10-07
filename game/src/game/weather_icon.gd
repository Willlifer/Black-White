class_name BWWeatherIcon
extends Control
## D252: a weather's icon, drawn (no texture): white ink on the dark HUD,
## the element colour only where the weather carries an element (rain's
## water, ashfall's embers, eclipse's dark, blizzard's ice, gale's wind).
##   rain      a cloud over three slanted streaks
##   ashfall   a cloud dropping grey flakes and one ember
##   eclipse   a black disc inside a white corona ring
##   blizzard  a six-armed snowflake
##   gale      three wind lines curling at their ends
## `heading_angle` (radians, screen space; NAN = none) adds Gale's arrow.

var kind := ""
var heading_angle := NAN


func _init(p_kind: String = "", px: float = 40.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func _draw() -> void:
	var s := size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5
	var ink := Color(0.96, 0.96, 0.97)
	var w := maxf(1.5, r * 0.09)
	draw_circle(c, r * 0.98, Color(0.03, 0.03, 0.035, 0.9))
	draw_arc(c, r * 0.98, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 1.0, true)
	match kind:
		BWWeather.RAIN:
			_cloud(c + Vector2(0, -r * 0.22), r * 0.5, ink, w)
			var wc := BWLook.glow_color("water")
			for i in 3:
				var x := c.x + (i - 1) * r * 0.3
				draw_line(Vector2(x + r * 0.08, c.y + r * 0.12), Vector2(x - r * 0.06, c.y + r * 0.6), wc, w * 1.2, true)
		BWWeather.ASHFALL:
			_cloud(c + Vector2(0, -r * 0.25), r * 0.5, Color(0.6, 0.6, 0.62), w)
			for p in [Vector2(-0.3, 0.2), Vector2(0.05, 0.42), Vector2(0.32, 0.22), Vector2(-0.12, 0.62)]:
				draw_circle(c + p * r, r * 0.07, Color(0.55, 0.55, 0.58))
			draw_circle(c + Vector2(0.28, 0.58) * r, r * 0.08, BWLook.glow_color("fire"))
		BWWeather.ECLIPSE:
			draw_circle(c, r * 0.62, ink)
			draw_circle(c + Vector2(r * 0.08, -r * 0.04), r * 0.52, Color(0.01, 0.01, 0.015))
			draw_arc(c, r * 0.74, 0.0, TAU, 40, BWLook.glow_color("dark"), w, true)
		BWWeather.BLIZZARD:
			var ic := BWLook.glow_color("ice")
			for k in 6:
				var a := TAU * k / 6.0 - PI / 2.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c, c + d * r * 0.66, ink, w, true)
				var m := c + d * r * 0.4
				for sgn in [-1.0, 1.0]:
					var b := Vector2(cos(a + sgn * 0.7), sin(a + sgn * 0.7))
					draw_line(m, m + b * r * 0.2, ink, w * 0.8, true)
			draw_circle(c, r * 0.12, ic)
		BWWeather.GALE:
			var gc := BWLook.glow_color("wind")
			for i in 3:
				var y := c.y + (i - 1) * r * 0.32
				var x0 := c.x - r * 0.62 + i * r * 0.08
				var x1 := c.x + r * (0.35 - i * 0.12)
				draw_line(Vector2(x0, y), Vector2(x1, y), ink if i != 1 else gc, w, true)
				draw_arc(Vector2(x1, y - r * 0.12), r * 0.12, PI / 2.0, PI * 2.0, 10, ink if i != 1 else gc, w, true)
	if not is_nan(heading_angle):
		_arrow(c, r * 0.9, heading_angle)


func _cloud(at: Vector2, r: float, col: Color, w: float) -> void:
	for p in [[Vector2(-0.45, 0.1), 0.42], [Vector2(0.05, -0.18), 0.55], [Vector2(0.5, 0.1), 0.4]]:
		draw_circle(at + p[0] * r, p[1] * r, col)
	draw_rect(Rect2(at + Vector2(-0.85, 0.05) * r, Vector2(1.7, 0.42) * r), col)


## An arrow along `ang` (screen radians), drawn over the icon's lower right.
func _arrow(c: Vector2, len: float, ang: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var a := c - d * len * 0.55
	var b := c + d * len * 0.55
	var n := Vector2(-d.y, d.x)
	draw_line(a, b, Color.BLACK, 6.0, true)
	draw_line(a, b, Color.WHITE, 3.0, true)
	var head := PackedVector2Array([b + d * 6.0, b - d * 7.0 + n * 7.0, b - d * 7.0 - n * 7.0])
	draw_colored_polygon(head, Color.WHITE)
	draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), Color.BLACK, 1.5, true)


## The room card's weather line: icon, WEATHER tag + name, the one-line rule.
static func strip(k: String, px: float = 40.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(BWWeatherIcon.new(k, px))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var n := Label.new()
	n.text = "WEATHER  ·  %s" % BWWeather.label(k)
	n.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	n.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(n)
	var rl := Label.new()
	rl.text = str(BWWeather.RULES.get(k, ""))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	rl.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	col.add_child(rl)
	return row

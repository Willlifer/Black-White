class_name BWWindView
extends Node3D
## D269-D276 readability for wind and dark (rules: BWWind, BWCurse;
## design/ELEMENTS-v3.md §11 "Readability" and the author's rulings).
## Everything is read from the battle when it changes (a signature per
## frame), drawn in ink on the board in one unshaded mesh:
##   gust field    two heavy ink chevrons along its heading
##   vortex field  a two-armed ink spiral winding in, arrow heads inward
##   becalm field  the author asked for "strong, unmistakable": a pale calm
##                 fill, three still concentric ink rings, a white calm-zone
##                 band inside the rim and a dashed ink border outside it
##   Wind Wall     a vertical sheet along the line (pale, ink-edged, with
##                 horizontal wind streaks), one per wall hex
##   gravity       a subtle inward swirl (light ink on the dark) on every dark
##                 3 hex a unit laid
##   Rot           "ROT" and one ink slash per stack, white-rimmed, on the unit's
##                 HP bar (D299: follows its clamp below the turn order)
## Plus the forecast's three-way mode toggle (toggle_row) and the unit card's
## Rot line (card_lines), used by BWCombatUI.

const LIFT := 0.05
const INK := Color(0.02, 0.02, 0.03)
const CALM := Color(0.97, 0.97, 0.99)
const WALL_H := 1.9

var screen: BWCombatScreen
var _mesh: MeshInstance3D
var _sig := ""
var _rot_labels := {}          # unit id -> [word Label3D, marks Label3D] (D346)
var shown := {}                # what is drawn (probes, review): { fields, walls, gravity, rot }


func setup(s: BWCombatScreen) -> void:
	screen = s
	_mesh = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(_delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	var b := screen.battle
	var sig := _signature(b)
	if sig != _sig and not screen._busy:          # the rules run ahead of the replay: redraw once it caught up
		_sig = sig
		rebuild()
	_place_rot(b)


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	for h in BWWind.field_hexes(b):
		var f := BWWind.field_at(b, h)
		parts.append("%s%s%d" % [h, f.mode, int(f.get("heading", -1))])
	parts.append(var_to_str(BWWind.wall_hexes(b)))
	for h in _gravity(b):
		parts.append("g%s" % h)
	for u in b.units:
		if u.alive() and BWCurse.rot(u) > 0:
			parts.append("r%s%d" % [u.id, BWCurse.rot(u)])
	return "|".join(parts)


## Dark 3 laid by a unit (whoever it pulls: either side's foes).
func _gravity(b: BWBattle) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		if b.tiles.intensity(h, "dark") >= BWCurse.GRAVITY_LEVEL and b._unit(str(b.tiles.at(h).get("source", ""))) != null:
			out.append(h)
	out.sort()
	return out


func rebuild() -> void:
	var b := screen.battle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	shown = { "fields": {}, "walls": BWWind.wall_hexes(b), "gravity": _gravity(b), "rot": {} }
	for h in shown.gravity:
		_swirl(st, h)
		n += 1
	for h in BWWind.field_hexes(b):
		var f := BWWind.field_at(b, h)
		shown.fields[h] = str(f.mode)
		match str(f.mode):
			BWWind.GUST: _gust(st, h, int(f.get("heading", 0)))
			BWWind.VORTEX: _vortex(st, h)
			BWWind.BECALM: _becalm(st, h)
		n += 1
	for k in BWWind.walls(b):
		var hexes: Array = BWWind.walls(b)[k].hexes
		for i in hexes.size():
			_wall(st, hexes, i)
			n += 1
	_mesh.mesh = st.commit() if n > 0 else null
	for u in b.units:
		if u.alive() and BWCurse.rot(u) > 0:
			shown.rot[u.id] = BWCurse.rot(u)


# ---------------------------------------------------------------- the marks

func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


func _dir3(d: int) -> Vector3:
	var v := BWWeather.heading_vector(d)
	return Vector3(v.x, 0, v.y)


func _gust(st: SurfaceTool, h: Vector2i, heading: int) -> void:
	var c := _top(h)
	var f := _dir3(heading)
	var s := Vector3(-f.z, 0, f.x)
	for k in 2:
		var tip := c + f * (0.18 + 0.42 * k - 0.2)
		var back := tip - f * 0.36
		_ribbon(st, back + s * 0.42, tip, 0.11, INK)
		_ribbon(st, back - s * 0.42, tip, 0.11, INK)
	# a thin streak behind, so it reads as moving air
	_ribbon(st, c - f * 0.75, c - f * 0.25, 0.04, Color(INK, 0.6))


func _vortex(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h)
	for arm in 2:
		var pts: Array = []
		for i in 25:
			var t := float(i) / 24.0
			var a := arm * PI + t * 2.6 * PI
			var r := 0.78 * (1.0 - t) + 0.08
			pts.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
		for i in pts.size() - 1:
			_ribbon(st, pts[i], pts[i + 1], 0.075 * (1.0 - float(i) / 30.0) + 0.02, INK)
		# an arrow head at the inner end, pointing in
		var p1: Vector3 = pts[pts.size() - 1]
		var p0: Vector3 = pts[pts.size() - 3]
		var d := (p1 - p0).normalized()
		var sd := Vector3(-d.z, 0, d.x)
		_tri(st, p1 + d * 0.14, p0 + sd * 0.12, p0 - sd * 0.12, INK)


func _becalm(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h)
	var r := BWLook.HEX_SIZE * 0.93
	# the calm fill
	var outer := BWLook.hex_corners(c + Vector3(0, -0.004, 0), r)
	for e in 6:
		_tri(st, c + Vector3(0, -0.004, 0), outer[e], outer[(e + 1) % 6], Color(CALM, 0.8))
	# still concentric rings
	for k in 3:
		_ring(st, c, 0.18 + 0.2 * k, 0.05, INK)
	# the calm-zone border: a white band inside the rim, a dashed ink edge outside it
	_hexband(st, c, r - 0.02, 0.1, Color(1, 1, 1, 0.95), false)
	_hexband(st, c, r + 0.06, 0.07, INK, true)


func _swirl(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h) + Vector3(0, 0.004, 0)
	var col := Color(0.82, 0.8, 0.9, 0.42)
	for arm in 3:
		var prev := Vector3.ZERO
		for i in 15:
			var t := float(i) / 14.0
			var a := arm * TAU / 3.0 + t * 1.4 * PI
			var r := 0.72 * (1.0 - t) + 0.1
			var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
			if i > 0:
				_ribbon(st, prev, p, 0.035 * (1.0 - t) + 0.012, col)
			prev = p


func _wall(st: SurfaceTool, hexes: Array, i: int) -> void:
	var h: Vector2i = hexes[i]
	var c := _top(h)
	var a: Vector2i = hexes[0]
	var z: Vector2i = hexes[hexes.size() - 1]
	var along := (_top(z) - _top(a))
	along.y = 0
	along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
	var half := along * BWLook.HEX_SIZE * 0.87
	var p0 := c - half
	var p1 := c + half
	var up := Vector3(0, WALL_H, 0)
	_quad(st, p0, p1, p1 + up, p0 + up, Color(0.93, 0.95, 1.0, 0.55))
	var n := Vector3(-along.z, 0, along.x) * 0.012
	# ink top and bottom edges, end posts on the line's ends
	_quad(st, p0 + up * 0.97 + n, p1 + up * 0.97 + n, p1 + up + n, p0 + up + n, INK)
	_quad(st, p0 + n, p1 + n, p1 + up * 0.03 + n, p0 + up * 0.03 + n, INK)
	if i == 0:
		_quad(st, p0 - along * 0.03, p0 + along * 0.03, p0 + along * 0.03 + up, p0 - along * 0.03 + up, INK)
	if i == hexes.size() - 1:
		_quad(st, p1 - along * 0.03, p1 + along * 0.03, p1 + along * 0.03 + up, p1 - along * 0.03 + up, INK)
	# horizontal wind streaks, staggered per hex
	for k in 4:
		var y := 0.3 + 0.38 * k + 0.08 * (i % 2)
		var s0 := 0.1 + 0.25 * ((k + i) % 3)
		var q0 := p0.lerp(p1, s0) + Vector3(0, y, 0) + n * 2.0
		var q1 := p0.lerp(p1, minf(s0 + 0.55, 0.98)) + Vector3(0, y, 0) + n * 2.0
		_quad(st, q0, q1, q1 + Vector3(0, 0.035, 0), q0 + Vector3(0, 0.035, 0), Color(INK, 0.75))


# ---------------------------------------------------------------- Rot marks

## D346: the word is small ink ("ROT", ROT_WORD, the names' size) and the
## stacks are their own label of fat ink slashes (ROT_MARK, a thick white
## rim), so ONE stack reads at game distance and 3 reads as three. The pair
## sits beside the HP bar's right end, in screen pixels (it used to hang
## under the bar at 30 px and covered the next unit in a crowd).
const ROT_WORD := 13
const ROT_MARK := 24

func _place_rot(b: BWBattle) -> void:
	for id in _rot_labels.keys():
		var u := b._unit(str(id))
		if u == null or not u.alive() or BWCurse.rot(u) <= 0:
			for l in _rot_labels[id]:
				if is_instance_valid(l):
					(l as Label3D).queue_free()
			_rot_labels.erase(id)
	for u in b.units:
		if not u.alive() or BWCurse.rot(u) <= 0 or not screen._views.has(u.id):
			continue
		var pair: Array = _rot_labels.get(u.id, [])
		if pair.size() != 2 or not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
			var w := BWKeystoneView.make_tag(ROT_WORD)
			var m := BWKeystoneView.make_tag(ROT_MARK)
			m.outline_size = 10
			pair = [w, m]
			_rot_labels[u.id] = pair
		var word: Label3D = pair[0]
		var marks: Label3D = pair[1]
		word.text = "ROT"
		marks.text = "/".repeat(BWCurse.rot(u))
		var v: Node3D = screen._views[u.id]
		BWKeystoneView.bar_mark(v, word, 0)
		BWKeystoneView.bar_mark(v, marks, 0)
		# beside the bar's right end (offsets in label pixels, from the screen)
		var f := ThemeDB.fallback_font
		var ww := f.get_string_size("ROT", HORIZONTAL_ALIGNMENT_LEFT, -1, ROT_WORD).x
		var mw := f.get_string_size(marks.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROT_MARK).x
		var half := 40.0
		var cam: Camera3D = screen.cam
		var bar: BWHPBar3D = v.get("_hp_bar") if "_hp_bar" in v else null
		if cam != null and bar != null and word.is_inside_tree() and not cam.is_position_behind(bar.global_position):
			half = bar.screen_rect(cam).size.x * 0.5 / maxf(BWBlastPreview.px_scale(cam, word.pixel_size), 0.001)
		word.offset = Vector2(half + 5.0 + ww * 0.5, 0.0)
		marks.offset = Vector2(half + 5.0 + ww + 3.0 + mw * 0.5, 1.0)


## Rot labels by unit id (probes, review): "ROT /", "ROT ///".
func rot_text(id: String) -> String:
	var pair: Array = _rot_labels.get(id, [])
	if pair.size() != 2 or not is_instance_valid(pair[0]):
		return ""
	return "%s %s" % [(pair[0] as Label3D).text, (pair[1] as Label3D).text]


## The Rot labels of a unit (review / probes).
func rot_labels(id: String) -> Array:
	return _rot_labels.get(id, [])


# ---------------------------------------------------------------- UI helpers (BWCombatUI)

## The forecast's three-way mode toggle for a wind action. `changed` is
## called after a pick (the screen re-opens the forecast with it).
static func toggle_row(att: BWUnit, changed: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = "Wind mode"
	l.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	l.add_theme_color_override("font_color", BWStyle.LABEL)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var group := ButtonGroup.new()
	for m in BWWind.MODES:
		var bt := Button.new()
		bt.toggle_mode = true
		bt.button_group = group
		bt.focus_mode = Control.FOCUS_NONE
		bt.text = ("● " if BWWind.mode(att) == m else "") + str(BWWind.NAMES[m])
		bt.tooltip_text = "%s: %s. Fields laid in this mode keep it." % [BWWind.NAMES[m], BWWind.RULES[m]]
		bt.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		bt.button_pressed = BWWind.mode(att) == m
		bt.name = "Mode_" + str(m)
		var mm: String = m
		bt.pressed.connect(func():
			if BWWind.mode(att) == mm:
				return
			BWWind.set_mode(att, mm)
			if changed.is_valid():
				changed.call())
		row.add_child(bt)
	return row


## The unit card's Rot line (BBCode), or nothing.
static func card_lines(u: BWUnit, fs: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var r := BWCurse.rot(u)
	if r > 0:
		out.append("[font_size=%d][b]%s[/b] [b]%s[/b] [color=#%s]%d of %d: takes +%d%% damage; a light heal cleans 1[/color][/font_size]" % [
			fs, "/".repeat(r), BWGlossary.markup("Rot"), BWStyle.TEXT_DIM.to_html(false), r, BWCurse.ROT_MAX, BWCurse.ROT_PCT * r])
	return out


# ---------------------------------------------------------------- geometry

func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0
	if d.length() < 0.0001:
		return
	var s := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	_quad(st, a - s, a + s, b + s, b - s, col)


func _ring(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color) -> void:
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := c + Vector3(cos(a0), 0, sin(a0)) * (r + w * 0.5)
		var o1 := c + Vector3(cos(a1), 0, sin(a1)) * (r + w * 0.5)
		var i0 := c + Vector3(cos(a0), 0, sin(a0)) * (r - w * 0.5)
		var i1 := c + Vector3(cos(a1), 0, sin(a1)) * (r - w * 0.5)
		_quad(st, i0, o0, o1, i1, col)


func _hexband(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color, dashed: bool) -> void:
	var outer := BWLook.hex_corners(c, r)
	var inner := BWLook.hex_corners(c, r - w)
	for e in 6:
		var n := (e + 1) % 6
		if dashed:
			for s in 4:
				if s % 2 == 1:
					continue
				var t0 := s / 4.0
				var t1 := (s + 1) / 4.0
				_quad(st, outer[e].lerp(outer[n], t0), outer[e].lerp(outer[n], t1), inner[e].lerp(inner[n], t1), inner[e].lerp(inner[n], t0), col)
		else:
			_quad(st, outer[e], outer[n], inner[n], inner[e], col)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)

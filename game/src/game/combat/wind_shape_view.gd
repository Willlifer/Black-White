class_name BWWindShapeView
extends Node3D
## D365-D370 the WIND SHAPING step (rules: BWWindShape, src/core/wind_shape.gd;
## design/ELEMENTS.md §18). While a wind skill's confirm box is up:
##   * the box shows a WIND SHAPING strip (strip()): the shape's options, the
##     chosen one marked, its rule and the keys;
##   * the mouse and keys pick the option with no extra click (Enter or a
##     click on the target still fires):
##       line    the mouse on either side of the line parts to that side; an
##               arrow key pointing at a side picks it; Tab / the wheel /
##               the other arrows cycle (Blast out, Hold)
##       area    Tab, the wheel or any arrow toggles Draw in / Burst out / Hold
##       single  the mouse around the target aims the push; ← / → turn it;
##               Tab, ↑ / ↓ toggle Hold; the wheel turns it
##   * the board shows it at a glance, over the blast preview (which already
##     draws every unit's move, slide ghost and damage): wind arrows on the
##     line's side / the area's rim / the target, a tag naming the option,
##     a dashed ghost ring where each pushed foe lands, "SLAM 8%" on every
##     blocked push and "INTO FIRE 12%" (shock, dark, a gust field) where a
##     foe would land in a hazard.
## A change stores the choice on the unit (BWWindShape.set_choice) and asks
## the screen to re-open the confirm (BWCombatScreen._wind_mode_changed),
## which re-simulates the preview.

const LIFT := 0.075
const INK := Color(0.02, 0.02, 0.03)
const WARN := Color(1.0, 0.42, 0.30)
const DEAD_PX := 16.0               # line: the band around the line where the mouse picks nothing
const AIM_PX := 26.0                # single: the radius around the target where the mouse picks nothing
const ARROW_GLYPHS := ["→", "↗", "↑", "↖", "←", "↙", "↓", "↘"]

var screen: BWCombatScreen
var ctx := {}                       # { unit, key, kind, hex, from, at, spine, area, centre }
var shown := {}                     # what is drawn (probes, review): { opt, rel, arrows, tags: [..] }
var _region := ""                   # the mouse's last region (line "L"/"R", single "0".."5")
var _mesh: MeshInstance3D
var _tags: Array = []
var _sig := ""


func setup(s: BWCombatScreen) -> void:
	screen = s
	_mesh = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 3
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


# ---------------------------------------------------------------- state

## The confirm box opens for skill `sk` ({key, element, row}) aimed at `h`
## (preview `pv`): shaping starts if it is a wind skill with a shape.
func begin(u: BWUnit, sk: Dictionary, h: Vector2i, pv: Dictionary) -> void:
	var key := str(sk.get("key", ""))
	var k := BWWindShape.kind_of(key)
	if u == null or u.team != "player" or str(sk.get("element", "")) != "wind" or k == "":
		ctx = {}
		return
	var b := screen.battle
	var same: bool = str(ctx.get("key", "")) == key and ctx.get("hex", null) == h
	var at := h
	var ids: Array = pv.get("units", [])
	if not ids.is_empty() and b._unit(str(ids[0])) != null:
		at = b._unit(str(ids[0])).pos
	var area: Array = (pv.get("hexes", []) as Array) + (pv.get("ring", []) as Array)
	ctx = { "unit": u.id, "key": key, "kind": k, "hex": h, "from": u.pos, "at": at, "area": area,
		"centre": BWWindShape.centre(u.pos, BWSkills.get_skill(key), h),
		"spine": BWWindShape.spine(b, u.pos, key, h, { "hexes": pv.get("hexes", []), "walk": [], "victims": [] }) }
	if not same:
		_region = _mouse_region(get_viewport().get_mouse_position()) if is_inside_tree() else ""
	_sig = ""


func active() -> bool:
	if ctx.is_empty() or screen == null or screen.battle == null or not screen.ui.forecast_open():
		return false
	var ps: Dictionary = screen._pending_skill
	var u := screen.battle.current()
	return not ps.is_empty() and str(ps.get("key", "")) == str(ctx.key) and ps.get("hex", null) == ctx.hex \
		and u != null and u.id == str(ctx.unit) and screen._player_turn()


func choice() -> Dictionary:
	return BWWindShape.choice(screen.battle.current(), str(ctx.key)) if not ctx.is_empty() else {}


## Pick an option (a push heading for Push); re-opens the confirm.
func pick(opt: String, rel: int = -99) -> void:
	if not active():
		return
	var u := screen.battle.current()
	var cur := choice()
	if rel == -99:
		rel = int(cur.get("rel", 0))
	if str(cur.get("opt", "")) == opt and int(cur.get("rel", 0)) == posmod(rel, 6):
		return
	BWWindShape.set_choice(u, str(ctx.key), opt, rel)
	_sig = ""
	screen._wind_mode_changed()


func cycle(step: int) -> void:
	var opts := BWWindShape.options(str(ctx.kind))
	var i := opts.find(str(choice().get("opt", "")))
	pick(str(opts[posmod(i + step, opts.size())]))


## Single: turn the push heading by `step` (+1 counter-clockwise on the map).
func turn(step: int) -> void:
	var c := choice()
	pick(BWWindShape.PUSH, int(c.get("rel", 0)) + (step if str(c.opt) == BWWindShape.PUSH else 0))


# ---------------------------------------------------------------- input

func _input(ev: InputEvent) -> void:
	if not active():
		return
	if ev is InputEventMouseMotion:
		var r := _mouse_region(ev.position)
		if r != _region:
			_region = r
			if r != "":
				_apply_region(r)
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var st := 1 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		if str(ctx.kind) == BWWindShape.SINGLE:
			turn(-st)
		else:
			cycle(st)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var kc: int = ev.keycode
		if not kc in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_TAB]:
			return
		key(kc, ev.shift_pressed)
		get_viewport().set_input_as_handled()


## One shaping key (arrows, Tab; `back` = Shift).
func key(kc: int, back: bool = false) -> void:
	match str(ctx.kind):
		BWWindShape.LINE:
			if kc == KEY_TAB:
				cycle(-1 if back else 1)
				return
			var side := side_for_key(kc)
			if side != 0:
				pick(BWWindShape.PART_LEFT if side > 0 else BWWindShape.PART_RIGHT)
			else:
				cycle(1 if kc in [KEY_DOWN, KEY_RIGHT] else -1)
		BWWindShape.AREA:
			cycle(-1 if (kc in [KEY_LEFT, KEY_UP] or (kc == KEY_TAB and back)) else 1)
		BWWindShape.SINGLE:
			match kc:
				KEY_LEFT: turn(1)
				KEY_RIGHT: turn(-1)
				_: pick(BWWindShape.PUSH if str(choice().opt) == BWWindShape.HOLD else BWWindShape.HOLD)


## The line side (+1 the caster's left, -1 its right) an arrow key points
## at on screen, or 0 when that arrow runs along the line.
func side_for_key(kc: int) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null or ctx.is_empty():
		return 0
	var want: Vector2 = { KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, -1), KEY_DOWN: Vector2(0, 1) }.get(kc, Vector2.ZERO)
	if want == Vector2.ZERO:
		return 0
	var v := _left_screen(cam)
	if v.length() < 0.5:
		return 0
	var d := v.normalized().dot(want)
	if d > 0.38:
		return 1
	if d < -0.38:
		return -1
	return 0


## The arrow key that points at `side` (probes): the first that does.
func key_for_side(side: int) -> int:
	for kc in [KEY_RIGHT, KEY_LEFT, KEY_UP, KEY_DOWN]:
		if side_for_key(kc) == side:
			return kc
	return KEY_NONE


## Screen vector from the line's start toward the caster's left.
func _left_screen(cam: Camera3D) -> Vector2:
	var fwd := BWWindShape.forward(ctx.from, ctx.hex)
	var a := _top(ctx.from)
	var l := BWWindShape.left_of(fwd)
	return cam.unproject_position(a + Vector3(l.x, 0, l.y)) - cam.unproject_position(a)


func _mouse_region(pos: Vector2) -> String:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or ctx.is_empty():
		return ""
	match str(ctx.kind):
		BWWindShape.LINE:
			var fwd := BWWindShape.forward(ctx.from, ctx.hex)
			var a3 := _top(ctx.from)
			var a := cam.unproject_position(a3)
			var d := cam.unproject_position(a3 + Vector3(fwd.x, 0, fwd.y) * 3.0) - a
			if d.length() < 1.0:
				return ""
			var m := pos - a
			var cr := d.x * m.y - d.y * m.x
			if absf(cr) / d.length() < DEAD_PX:
				return ""
			var lv := _left_screen(cam)
			var lc := d.x * lv.y - d.y * lv.x
			return "L" if signf(cr) == signf(lc) else "R"
		BWWindShape.SINGLE:
			var t := cam.unproject_position(_top(ctx.at))
			var m2 := pos - t
			if m2.length() < AIM_PX:
				return ""
			var best := -1
			var best_d := -INF
			for i in 6:
				var sv := cam.unproject_position(_top(BWHex.neighbors(ctx.at)[i])) - t
				if sv.length() < 0.5:
					continue
				var dd := sv.normalized().dot(m2.normalized())
				if dd > best_d:
					best_d = dd
					best = i
			return str(best) if best >= 0 else ""
	return ""


func _apply_region(r: String) -> void:
	match str(ctx.kind):
		BWWindShape.LINE:
			pick(BWWindShape.PART_LEFT if r == "L" else BWWindShape.PART_RIGHT)
		BWWindShape.SINGLE:
			var u := screen.battle.current()
			pick(BWWindShape.PUSH, int(r) - BWWindShape.away_dir(u.pos, ctx.at))


## Probes: move the "mouse" to screen point `pos` as a motion would.
func hover(pos: Vector2) -> void:
	var r := _mouse_region(pos)
	if r != _region:
		_region = r
		if r != "":
			_apply_region(r)


# ---------------------------------------------------------------- the strip in the confirm box

## The WIND SHAPING strip for BWCombatUI's confirm box, or null.
func strip() -> Control:
	if ctx.is_empty() or screen == null or screen._skill.is_empty() or str(screen._skill.get("key", "")) != str(ctx.key):
		return null
	var u := screen.battle.current()
	if u == null or u.id != str(ctx.unit):
		return null
	var c := choice()
	var box := VBoxContainer.new()
	box.name = "WindShaping"
	box.add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = "WIND SHAPING"
	head.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	head.add_theme_color_override("font_color", BWLook.glow_color("wind").lightened(0.25))
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for o in BWWindShape.options(str(ctx.kind)):
		var bt := Button.new()
		bt.toggle_mode = true
		bt.button_group = group
		bt.focus_mode = Control.FOCUS_NONE
		bt.name = "Shape_" + str(o)
		var txt := BWWindShape.label(str(o))
		if str(o) == BWWindShape.PUSH:
			txt += " " + _glyph(int(c.get("rel", 0)))
		bt.text = ("● " if str(c.opt) == str(o) else "") + txt
		bt.button_pressed = str(c.opt) == str(o)
		bt.tooltip_text = "%s: %s" % [BWWindShape.label(str(o)), BWWindShape.rule(str(o))]
		bt.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		var oo: String = o
		bt.pressed.connect(func(): pick(oo))
		row.add_child(bt)
	box.add_child(row)
	var rule := BWGlossary.Rich.new()
	rule.fit_content = true
	rule.scroll_active = false
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size = Vector2(360, 0)
	rule.add_theme_font_size_override("normal_font_size", BWStyle.F_SMALL)
	rule.add_theme_color_override("default_color", BWStyle.TEXT)
	rule.set_glossed("%s: %s." % [BWWindShape.label(str(c.opt)), BWWindShape.rule(str(c.opt))])
	box.add_child(rule)
	var keys := Label.new()
	keys.text = {
		"line": "Mouse to a side of the line, or the arrow toward it · Tab: Blast out, Hold · Enter fires",
		"area": "Wheel, Tab or arrows: Draw in / Burst out / Hold · Enter fires",
		"single": "Mouse around the target or ←/→ aims the push · Tab: Hold · Enter fires",
	}.get(str(ctx.kind), "")
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size = Vector2(360, 0)
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_color_override("font_color", BWStyle.FAINT)
	box.add_child(keys)
	return box


## The push heading as a screen arrow glyph (8-way, the camera's view).
func _glyph(rel: int) -> String:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or ctx.is_empty():
		return ""
	var u := screen.battle.current()
	var d := BWWindShape.push_dir(u.pos, ctx.at, rel)
	var t := cam.unproject_position(_top(ctx.at))
	var v := cam.unproject_position(_top(BWHex.neighbors(ctx.at)[d])) - t
	if v.length() < 0.5:
		return ""
	var ang := atan2(-v.y, v.x)
	return ARROW_GLYPHS[posmod(roundi(ang / (PI / 4.0)), 8)]


# ---------------------------------------------------------------- the board

func _process(_delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	if not active():
		ctx = {} if not screen.ui.forecast_open() else ctx
		if _mesh.mesh != null or not _tags.is_empty():
			_clear()
			_sig = ""
		return
	var rd := screen.readability
	var sig := var_to_str(ctx) + var_to_str(choice()) + (rd._sig if rd else "") + str(rd.preview.last.size() if rd else 0)
	if sig == _sig:
		return
	_sig = sig
	_draw(rd.preview.last if rd else {})


func _clear() -> void:
	_mesh.mesh = null
	for t in _tags:
		if is_instance_valid(t):
			t.queue_free()
	_tags.clear()
	shown = {}


func _draw(sim: Dictionary) -> void:
	_clear()
	var b := screen.battle
	var u := b.current()
	var c := choice()
	var opt := str(c.opt)
	var wind := BWLook.glow_color("wind")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrows := 0
	var tags: Array = []
	match str(ctx.kind):
		BWWindShape.LINE:
			var sp: Array = ctx.spine
			var fwd := BWWindShape.forward(ctx.from, ctx.hex)
			var on := {}
			for h in sp:
				on[h] = true
			match opt:
				BWWindShape.PART_LEFT, BWWindShape.PART_RIGHT:
					var side := 1 if opt == BWWindShape.PART_LEFT else -1
					var d := BWWindShape.side_dir(fwd, side)
					for h in sp:
						_arrow(st, h, BWHex.neighbors(h)[d], wind, 0.17, 0.95)
						arrows += 1
					if not sp.is_empty():
						var far: Vector2i = sp[sp.size() - 1]
						tags.append(_tag(BWHex.neighbors(far)[d], "PART %s" % ("LEFT" if side > 0 else "RIGHT"), wind, 0.55))
				BWWindShape.BLAST:
					for h in BWHex.fringe(sp, 1):
						if h == ctx.from or not b.board.exists(h):
							continue
						var f := b.unit_at(h)
						var dd := -1
						if f != null and f.team != u.team:
							dd = BWWindShape.blast_dir(b, f, ctx.from, fwd, on)
						elif on.has(h):
							continue
						else:
							var sd := BWWindShape.side_of(ctx.from, fwd, h)
							dd = BWWindShape.side_dir(fwd, sd) if sd != 0 else BWWindShape.dir_toward(fwd)
						_arrow(st, h, BWHex.neighbors(h)[dd], wind, 0.12 if f == null else 0.17, 0.8)
						arrows += 1
					if not sp.is_empty():
						tags.append(_tag(sp[sp.size() - 1], "BLAST OUT", wind, 0.75))
				BWWindShape.HOLD:
					for h in sp:
						_rings(st, h)
					if not sp.is_empty():
						tags.append(_tag(sp[sp.size() - 1], "HOLD", wind, 0.75))
		BWWindShape.AREA:
			var area := {}
			for h in ctx.area:
				area[h] = true
			var cen: Vector2i = ctx.centre
			match opt:
				BWWindShape.DRAW:
					for h in BWHex.fringe(ctx.area, 1):
						if area.has(h) or h == ctx.from or not b.board.exists(h):
							continue
						var dn := BWBattle.pulse_heading(cen, h, false)
						if dn >= 0:
							_arrow(st, h, BWHex.neighbors(h)[dn], wind, 0.13, 0.85)
							arrows += 1
					tags.append(_tag(cen, "DRAW IN", wind, 0.95))
				BWWindShape.BURST:
					var rmax := 0
					for h in ctx.area:
						rmax = maxi(rmax, BWHex.distance(cen, h))
					for h in ctx.area:
						if h == cen or BWHex.distance(cen, h) < rmax:
							continue
						var du := BWBattle.pulse_heading(cen, h, true)
						if du >= 0:
							_arrow(st, h, BWHex.neighbors(h)[du], wind, 0.13, 0.85)
							arrows += 1
					tags.append(_tag(cen, "BURST OUT", wind, 0.95))
				BWWindShape.HOLD:
					for h in ctx.area:
						if b.unit_at(h) != null and b.unit_at(h).team != u.team:
							_rings(st, h)
					tags.append(_tag(cen, "HOLD", wind, 0.95))
		BWWindShape.SINGLE:
			if opt == BWWindShape.HOLD:
				_rings(st, ctx.at)
				tags.append(_tag(ctx.at, "HOLD", wind, 1.25))
			else:
				var d2 := BWWindShape.push_dir(u.pos, ctx.at, int(c.rel))
				var nx: Vector2i = BWHex.neighbors(ctx.at)[d2]
				_arrow(st, ctx.at, nx, wind, 0.26, 1.15)
				arrows += 1
				tags.append(_tag(nx, "PUSH", wind, 0.55))
	# what the simulation says will happen: ghosts, slams, hazards
	for e in sim.get("events", []):
		if str(e.get("type", "")) != "wind_shape":
			continue
		for m in e.moves:
			_ghost(st, m.to)
			for hz in m.hazard:
				var txt := "INTO %s" % str(hz[0]) + (" %d%%" % roundi(float(hz[1])) if float(hz[1]) > 0.0 else "")
				tags.append(_tag(m.to, txt, WARN, 0.95))
	for sl in sim.get("slams", []):
		if str(sl.get("name", "")) == "Gust":
			var who := b._unit(str(sl.unit))
			if who != null:
				tags.append(_tag(who.pos, "SLAM %d%%" % int(BWWind.SLAM_PCT), WARN, 1.3))
	_mesh.mesh = st.commit()
	shown = { "opt": opt, "rel": int(c.get("rel", 0)), "arrows": arrows, "tags": tags.map(func(l): return (l as Label3D).text) }


# ---------------------------------------------------------------- geometry

func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


## A fat wind arrow from hex `a` toward hex `b` (`len` of the way), ink-edged.
func _arrow(st: SurfaceTool, a: Vector2i, b: Vector2i, col: Color, w: float, frac: float) -> void:
	var pa := _top(a)
	var pb := _top(b)
	var d := pb - pa
	d.y = 0
	if d.length() < 0.01:
		return
	var dn := d.normalized()
	var s := Vector3(-dn.z, 0, dn.x)
	var start := pa + dn * 0.30                      # clear of the unit standing there
	var tip := pa + dn * (d.length() * frac * 0.78)
	var neck := tip - dn * 0.34
	for layer in 2:
		var o := 0.045 if layer == 0 else 0.0
		var cc := INK if layer == 0 else Color(col, 0.97)
		var y := Vector3(0, 0.004 * layer, 0)
		_quad(st, start - s * (w * 0.5 + o) + y, start + s * (w * 0.5 + o) + y, neck + s * (w * 0.5 + o) + y, neck - s * (w * 0.5 + o) + y, cc)
		_tri(st, tip + dn * o * 1.6 + y, neck + s * (w * 1.35 + o * 1.5) + y, neck - s * (w * 1.35 + o * 1.5) + y, cc)


## A dashed ink ring: where a pushed foe will stand (its ghost).
func _ghost(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h) + Vector3(0, 0.006, 0)
	var seg := 20
	for i in seg:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * 0.50, c + d0 * 0.60, c + d1 * 0.60, c + d1 * 0.50, INK)
		_quad(st, c + d0 * 0.60, c + d0 * 0.64, c + d1 * 0.64, c + d1 * 0.60, Color(1, 1, 1, 0.9))


## Hold: two still ink rings (the Becalm mark).
func _rings(st: SurfaceTool, h: Vector2i) -> void:
	var c := _top(h) + Vector3(0, 0.006, 0)
	var seg := 24
	for k in 2:
		var r := 0.36 + 0.2 * k
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			_quad(st, c + d0 * (r - 0.035), c + d0 * (r + 0.035), c + d1 * (r + 0.035), c + d1 * (r - 0.035), INK)


func _tag(h: Vector2i, text: String, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 24
	l.outline_size = 12
	l.modulate = Color.WHITE
	l.outline_modulate = col.darkened(0.45)
	l.render_priority = 19
	l.outline_render_priority = 18
	l.position = _top(h) + Vector3(0, y, 0)
	add_child(l)
	_tags.append(l)
	return l


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)

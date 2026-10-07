class_name BWWeatherView
extends Node3D
## D252: the weather on the combat screen (rules: BWWeather, design/WEATHER.md).
##   particles   one pooled MultiMesh (POOL quads, one draw call) on the cast
##               VFX's own particle shader (vfx_particle.gdshader, already in
##               the D232 pre-warm): ink-rimmed rain streaks, ash flakes with a
##               few embers, snow motes and shards, wind streaks along the
##               heading, rising dark motes for an eclipse. CPU-stepped, the
##               buffer written once a frame.
##   vignette    Eclipse darkens the screen's edges (a radial gradient, no shader).
##   telegraph   the next tick on the board, in the blast preview's hatching
##               (D160): Blizzard's four marks (ice hatch, dashed rim),
##               Ashfall's hexes about to catch (fire hatch), Gale's push per
##               unit (an ink arrow; a slam ends in a bar).
##   plate       top left (where the Obelisks' plate goes; weather never
##               shares a fight with them): icon, name, the rule, the next
##               tick and when; Gale's heading arrow (turned with the camera),
##               the ticks until it turns and an arrow for the next heading.
## combat_screen feeds it the battle's `weather` events (on_event) and
## nothing else; everything else it reads from the battle when idle.

const POOL := 240
const COUNTS := { "rain": 220, "ashfall": 150, "eclipse": 70, "blizzard": 170, "gale": 120 }
const TOP := 7.0
const PAD := 3.0

var screen: BWCombatScreen
var kind := ""
var state := {}                 # the last snapshot shown (BWWeather.snapshot)
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _pos := PackedVector3Array()
var _seed := PackedFloat32Array()      # per particle phase
var _sub := PackedInt32Array()         # per particle variant (ember / shard)
var _n := 0
var _box := AABB()
var _gust := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _tele: MeshInstance3D
var _tele_mat: StandardMaterial3D
var _geo: BWBlastPreview
var _dirty := true
var _vignette: CanvasLayer
var plate: PanelContainer
var _icon: BWWeatherIcon
var _next_icon: BWWeatherIcon
var _next_l: Label
var _rule_l: Label
var tele_hexes: Array = []      # what the telegraph draws now (probes, review)
var _tags: Array = []           # Label3D per telegraphed hex (pooled)


func setup(s: BWCombatScreen) -> void:
	screen = s
	kind = str(s.battle.weather.get("kind", ""))
	if kind == "":
		return
	state = BWWeather.snapshot(s.battle.weather)
	_rng.seed = int(s.battle.weather.get("seed", 1))
	_bounds()
	_build_particles()
	_build_telegraph()
	_build_plate()
	if kind == BWWeather.ECLIPSE:
		_build_vignette()
	s.ui.feed("[b]Weather: %s[/b]. %s" % [BWWeather.label(kind), BWWeather.RULES[kind]])


func _exit_tree() -> void:
	if _geo:
		_geo.free()
		_geo = null


# ---------------------------------------------------------------- events

## A battle event in replay order. "weather": the tick just happened.
func on_event(e: Dictionary) -> void:
	if kind == "":
		return
	match str(e.get("type", "")):
		"weather":
			state = { "marks": e.get("marks", []), "heading": int(e.get("heading", -1)),
				"next_heading": int(e.get("next_heading", -1)), "turn_in": int(e.get("turn_in", 0)) }
			if kind == BWWeather.ASHFALL:
				screen.board_view.on_tile_event({ "type": "tiles_tick", "seeded": e.get("ignited", []) })
			else:
				screen.board_view.refresh_tiles()
			screen.ui.feed(_feed_line(e))
			_rebuild_telegraph()                    # the post-tick telegraph, in replay order
			if kind == BWWeather.GALE:
				_gust = 1.0
				await get_tree().create_timer(0.3 * (0.15 if screen.skipping else 1.0)).timeout
		_:
			_dirty = true


func _feed_line(e: Dictionary) -> String:
	var n := "[b]%s[/b]" % BWWeather.label(kind)
	match kind:
		BWWeather.RAIN: return "%s: water on every hex, fire steps down" % n
		BWWeather.ASHFALL: return "%s: %d hex%s catch fire" % [n, (e.get("ignited", []) as Array).size(), "" if (e.get("ignited", []) as Array).size() == 1 else "es"]
		BWWeather.ECLIPSE: return "%s: every hex is pulled toward dark 1" % n
		BWWeather.BLIZZARD: return "%s: %d hexes glaze; 4 more are marked" % [n, (e.get("glazed", []) as Array).size()]
		BWWeather.GALE: return "%s: everyone is pushed %s" % [n, BWWeather.HEADING_NAMES[maxi(int(e.get("push", 0)), 0)]]
	return n


# ---------------------------------------------------------------- frame

func _process(dt: float) -> void:
	if kind == "" or screen == null or screen.cam == null:
		return
	_t += dt
	_gust = maxf(0.0, _gust - dt * 0.8)
	_step_particles(dt)
	if _tele_mat:
		_tele_mat.albedo_color = Color(1, 1, 1, 0.72 + 0.22 * sin(_t * 3.2))
	if screen._busy:
		_dirty = true                               # anything may move while events replay
	elif _dirty:
		_dirty = false
		_rebuild_telegraph()
	if kind == BWWeather.GALE and screen._busy and _tele.visible:
		_tele.visible = false                       # gale arrows are for planning: hidden while things move
	elif not screen._busy and not _tele.visible:
		_tele.visible = true
	_update_plate()


# ---------------------------------------------------------------- particles

func _bounds() -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for h in screen.battle.board.cells():
		var p := BWLook.world(h)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	lo -= Vector3(PAD, 0, PAD)
	hi += Vector3(PAD, 0, PAD)
	_box = AABB(Vector3(lo.x, -0.3, lo.z), Vector3(hi.x - lo.x, TOP + 0.3, hi.z - lo.z))


func _build_particles() -> void:
	_n = mini(int(COUNTS.get(kind, 120)), POOL)
	_mmi = particle_node(POOL)
	_mm = _mmi.multimesh
	_mm.visible_instance_count = _n
	_mmi.custom_aabb = AABB(_box.position - Vector3(2, 2, 2), _box.size + Vector3(4, 4, 4))
	add_child(_mmi)
	_buf.resize(POOL * 20)
	_pos.resize(_n)
	_seed.resize(_n)
	_sub.resize(_n)
	for i in _n:
		_pos[i] = _spawn(true)
		_seed[i] = _rng.randf() * TAU
		var r := _rng.randf()
		_sub[i] = 1 if (kind == BWWeather.ASHFALL and r < 0.12) or (kind == BWWeather.BLIZZARD and r < 0.25) else 0


## The pooled particle node (also the pre-warm's copy): the cast VFX's
## particle shader on a quad MultiMesh with colours and custom data.
static func particle_node(count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mm.mesh = qm
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vfx_particle.gdshader")
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	return mmi


func _spawn(anywhere: bool) -> Vector3:
	var x := _box.position.x + _rng.randf() * _box.size.x
	var z := _box.position.z + _rng.randf() * _box.size.z
	match kind:
		BWWeather.ECLIPSE:
			return Vector3(x, _rng.randf() * 4.0 if anywhere else 0.0, z)
		BWWeather.GALE:
			return Vector3(x, 0.25 + _rng.randf() * 2.6, z)
	return Vector3(x, _rng.randf() * TOP if anywhere else TOP, z)


## The screen-space roll (the shader's custom z) that lays a streak along
## world direction `d` seen from the camera at `at`.
func _roll(at: Vector3, d: Vector3) -> float:
	var cam := screen.cam
	if cam.is_position_behind(at) or cam.is_position_behind(at + d):
		return 0.0
	var s := cam.unproject_position(at + d) - cam.unproject_position(at)
	if s.length() < 0.001:
		return 0.0
	return -s.angle() - PI / 2.0


func _step_particles(dt: float) -> void:
	var focus := _box.get_center()
	var wind := Vector3.ZERO
	var hd := int(state.get("heading", -1))
	if kind == BWWeather.GALE and hd >= 0:
		var v2 := BWWeather.heading_vector(hd)
		wind = Vector3(v2.x, 0, v2.y)
	var fall_roll := _roll(focus, Vector3(0.12, -1.0, 0.0))
	var wind_roll := _roll(focus + Vector3(0, 1, 0), wind) if wind != Vector3.ZERO else 0.0
	var lo := _box.position
	var hi := _box.end
	for i in _n:
		var p := _pos[i]
		var ph := _seed[i]
		var size := 0.1
		var col := Color.WHITE
		var shape := 0.0
		var core := 0.0
		var roll := 0.0
		var stretch := 1.0
		match kind:
			BWWeather.RAIN:
				p += Vector3(0.12, -1.0, 0.0) * 15.0 * dt
				if p.y < 0.0:
					p = _spawn(false)
				size = 0.085
				shape = 2.0
				stretch = 8.0
				roll = fall_roll
				col = Color(0.62, 0.68, 0.78, 0.85)      # mid grey-blue: reads on the white board and the black sky
			BWWeather.ASHFALL:
				p += Vector3(sin(_t * 0.7 + ph) * 0.35, -0.75, cos(_t * 0.5 + ph) * 0.25) * dt
				if p.y < 0.0:
					p = _spawn(false)
				if _sub[i] == 1:
					size = 0.07
					col = BWLook.glow_color("fire")
					core = 0.6
				else:
					size = 0.1 + 0.05 * sin(ph * 3.0)
					shape = 3.0
					col = Color(0.5, 0.5, 0.53, 0.9)
				roll = _t * 0.8 + ph
			BWWeather.ECLIPSE:
				p += Vector3(sin(_t + ph) * 0.15, 0.45, 0.0) * dt
				if p.y > 4.2:
					p = _spawn(false)
				size = 0.07 + 0.03 * sin(ph * 2.0)
				col = BWLook.glow_color("dark")
				col.a = clampf(p.y, 0.0, 1.0) * clampf(4.2 - p.y, 0.0, 1.0) * 0.85
			BWWeather.BLIZZARD:
				p += Vector3(sin(_t * 1.3 + ph) * 0.5 + 0.4, -1.5, cos(_t * 0.9 + ph) * 0.3) * dt
				if p.y < 0.0:
					p = _spawn(false)
				if _sub[i] == 1:
					size = 0.13
					shape = 1.0
					col = BWLook.glow_color("ice")
					roll = _t * 1.5 + ph
				else:
					size = 0.08 + 0.03 * sin(ph * 5.0)
					col = Color(1, 1, 1, 1)
					core = 0.4
			BWWeather.GALE:
				p += wind * (8.0 + 14.0 * _gust) * dt + Vector3(0, sin(_t * 2.0 + ph) * 0.15 * dt, 0)
				size = 0.06
				shape = 2.0
				stretch = 10.0 + 8.0 * _gust
				roll = wind_roll
				col = Color(0.97, 0.97, 0.98, 0.55 + 0.35 * _gust)
		# wrap around the board's box (the wind blows streaks out one side, in the other)
		if p.x < lo.x: p.x = hi.x
		elif p.x > hi.x: p.x = lo.x
		if p.z < lo.z: p.z = hi.z
		elif p.z > hi.z: p.z = lo.z
		if kind != BWWeather.ECLIPSE and kind != BWWeather.GALE:
			col.a *= clampf((TOP - p.y) / 1.2, 0.0, 1.0)
		_pos[i] = p
		var o := i * 20
		_buf[o] = size; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = p.x
		_buf[o + 4] = 0.0; _buf[o + 5] = size; _buf[o + 6] = 0.0; _buf[o + 7] = p.y
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = size; _buf[o + 11] = p.z
		_buf[o + 12] = col.r; _buf[o + 13] = col.g; _buf[o + 14] = col.b; _buf[o + 15] = col.a
		_buf[o + 16] = shape; _buf[o + 17] = core; _buf[o + 18] = roll; _buf[o + 19] = stretch
	_mm.buffer = _buf


# ---------------------------------------------------------------- telegraph

func _build_telegraph() -> void:
	_tele = telegraph_node()
	_tele_mat = _tele.material_override
	add_child(_tele)
	_geo = BWBlastPreview.new(screen.board_view)


## The telegraph's mesh node (also the pre-warm's copy): the blast
## preview's flat vertex-colour material (D160).
static func telegraph_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _rebuild_telegraph() -> void:
	var b := screen.battle
	var fc := BWWeather.forecast(b)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	tele_hexes = []
	match kind:
		BWWeather.BLIZZARD:
			var ice := BWLook.glow_color("ice")
			for h in state.get("marks", []):
				_geo._hatch(st, h, ice.darkened(0.35), "dense", 0.85)
				_geo._rim(st, h, BWBlastPreview.INK, 0.13, false)
				_geo._rim(st, h, ice, 0.07, true)
				tele_hexes.append(h)
				any = true
		BWWeather.ASHFALL:
			var fire := BWLook.glow_color("fire")
			for h in fc.get("ignite", []):
				_geo._hatch(st, h, fire, "sparse", 0.55)
				_geo._rim(st, h, fire, 0.05, true)
				tele_hexes.append(h)
				any = true
		BWWeather.GALE:
			var dir := int(state.get("heading", -1))
			for u in b.units:
				if not u.alive() or BWObelisk.is_objective(u) or b._immune(u, "displace") or dir < 0:
					continue
				var pp := b.push_path(u, dir, 1)
				var path: Array = pp.path
				if path.size() > 1:
					_geo._shove(st, path[0], path[-1])
					tele_hexes.append(path[-1])
					any = true
				elif str(pp.stop) in ["rock", "unit"]:
					_slam_mark(st, u.pos, dir)
					tele_hexes.append(u.pos)
					any = true
	_tele.mesh = st.commit() if any else null
	_place_tags("GLAZE" if kind == BWWeather.BLIZZARD else "")      # Ashfall lights too many hexes to tag: hatching only


## Small billboard tags over the telegraphed hexes (Blizzard, Ashfall).
func _place_tags(text: String) -> void:
	var want := tele_hexes.size() if text != "" else 0
	while _tags.size() < want:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0009                    # the blast preview's tag size (D160)
		l.font_size = 22
		l.outline_size = 12
		l.modulate = Color.WHITE
		l.outline_modulate = Color.BLACK
		l.render_priority = 18
		l.outline_render_priority = 17
		add_child(l)
		_tags.append(l)
	for i in _tags.size():
		var l: Label3D = _tags[i]
		l.visible = i < want
		if i < want:
			l.text = text
			l.position = screen.board_view.top_center(tele_hexes[i]) + Vector3(0, 0.25, 0)


## A push that slams: a short ink arrow to the hex edge and a bar across it.
func _slam_mark(st: SurfaceTool, h: Vector2i, dir: int) -> void:
	var a := _geo._top(h) + Vector3(0, 0.02, 0)
	var v2 := BWWeather.heading_vector(dir)
	var d := Vector3(v2.x, 0, v2.y)
	var side := Vector3(-d.z, 0, d.x)
	var edge := a + d * BWLook.HEX_SIZE * 0.78
	var ink := BWBlastPreview.INK
	_geo._quad(st, a - side * 0.07, a + side * 0.07, edge - d * 0.25 + side * 0.07, edge - d * 0.25 - side * 0.07, ink)
	for p in [edge - d * 0.02, edge - d * 0.3 + side * 0.24, edge - d * 0.3 - side * 0.24]:
		st.set_color(ink)
		st.add_vertex(p)
	_geo._quad(st, edge - side * 0.42, edge + side * 0.42, edge + side * 0.42 + d * 0.1, edge - side * 0.42 + d * 0.1, ink)


# ---------------------------------------------------------------- vignette

func _build_vignette() -> void:
	_vignette = CanvasLayer.new()
	_vignette.layer = 5
	add_child(_vignette)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.02, 0.0, 0.05, 0.12), Color(0.0, 0.0, 0.0, 0.72)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.add_child(tr)


# ---------------------------------------------------------------- plate

func _build_plate() -> void:
	plate = PanelContainer.new()
	plate.add_theme_stylebox_override("panel", BWStyle.frame_style())
	plate.offset_left = 16
	plate.offset_top = 10
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.tooltip_text = "%s\n%s" % [BWWeather.label(kind), BWWeather.RULES[kind]]
	screen.ui._root.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	plate.add_child(row)
	_icon = BWWeatherIcon.new(kind, 52.0)
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	var t := Label.new()
	t.text = "WEATHER  ·  %s" % BWWeather.label(kind).to_upper()
	t.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	t.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(t)
	_rule_l = Label.new()
	_rule_l.text = BWWeather.RULES[kind]
	_rule_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule_l.custom_minimum_size = Vector2(300, 0)
	_rule_l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_rule_l.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	col.add_child(_rule_l)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 6)
	col.add_child(nr)
	_next_l = Label.new()
	_next_l.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 1)
	_next_l.add_theme_color_override("font_color", BWStyle.TEXT)
	nr.add_child(_next_l)
	if kind == BWWeather.GALE:
		_next_icon = BWWeatherIcon.new("", 26.0)
		_next_icon.modulate = Color(1, 1, 1, 0.7)
		nr.add_child(_next_icon)


## Ticks left in this cycle (the acting unit's turn included).
func _turns_left() -> int:
	var b := screen.battle
	var n := 0
	for i in range(maxi(b.turn_index, 0), b.queue.size()):
		if b.queue[i].alive():
			n += 1
	return n


func _update_plate() -> void:
	if plate == null:
		return
	var when := _turns_left()
	var w := "after %d more turn%s" % [when, "" if when == 1 else "s"] if when > 1 else "after this turn"
	var txt := ""
	match kind:
		BWWeather.RAIN: txt = "Next tick %s: water 1 everywhere, fire −1" % w
		BWWeather.ASHFALL: txt = "Next tick %s: %d hatched hex%s catch" % [w, tele_hexes.size(), "" if tele_hexes.size() == 1 else "es"]
		BWWeather.ECLIPSE: txt = "Next tick %s: every hex toward dark 1" % w
		BWWeather.BLIZZARD: txt = "Next tick %s: the %d hatched hexes glaze" % [w, (state.get("marks", []) as Array).size()]
		BWWeather.GALE:
			var ti := int(state.get("turn_in", 0))
			txt = "Push %s · the wind turns in %d tick%s, to" % [w, ti, "" if ti == 1 else "s"]
	if _next_l.text != txt:
		_next_l.text = txt
	if kind == BWWeather.GALE:
		var a := _screen_angle(int(state.get("heading", -1)))
		if absf(a - (_icon.heading_angle if not is_nan(_icon.heading_angle) else 99.0)) > 0.01:
			_icon.heading_angle = a
			_icon.queue_redraw()
		var na := _screen_angle(int(state.get("next_heading", -1)))
		if absf(na - (_next_icon.heading_angle if not is_nan(_next_icon.heading_angle) else 99.0)) > 0.01:
			_next_icon.heading_angle = na
			_next_icon.queue_redraw()


## Heading `dir` as a screen angle (radians, y down) from the camera now.
func _screen_angle(dir: int) -> float:
	if dir < 0:
		return NAN
	var c := _box.get_center()
	var v2 := BWWeather.heading_vector(dir)
	var s := screen.cam.unproject_position(c + Vector3(v2.x, 0, v2.y)) - screen.cam.unproject_position(c)
	return s.angle()


## Probe / review readout: the plate's lines.
func plate_texts() -> Array:
	return [] if plate == null else [BWWeather.label(kind), _rule_l.text, _next_l.text]


## D232 pre-warm: one of each node the weather draws.
static func warm_catalog() -> Array:
	var p := particle_node(4)
	for i in 4:
		p.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.2), Vector3(i * 0.3, 0, 0)))
		p.multimesh.set_instance_color(i, Color.WHITE)
		p.multimesh.set_instance_custom_data(i, Color(2.0, 0.0, 0.0, 8.0))
	var t := telegraph_node()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		st.set_color(Color(1, 1, 1, 0.5))
		st.add_vertex(v)
	t.mesh = st.commit()
	return [["weather_particles", p], ["weather_telegraph", t]]

class_name BWTwinsFX
extends Node3D
## D260: the Twins' presentation on the combat screen (BWCombatScreen makes
## one when the battle's boss is the Twins, BWPhases.kind == "twins").
##   intro()       the title card "The Twins: Noon and Dusk" (awaited before play)
##   on_event(e)   beam / beam_hit / beam_break / phase / phase_pending / phase_cancel
##   the beam      a ribbon on the ground from Noon to Dusk, each half in its
##                 colour (light: a warm white-gold core; dark: an ink core
##                 with a violet rim), a flowing pulse along it and a soft glow
##   the swap      a colour-inversion flash of the whole screen (twice, like a
##                 blink), the ring heads' glows trade colours, a banner
##   the rage      a column of the survivor's colour round its feet, a ring on
##                 the ground, "RAGE" over it; before it, "RAGE IN n" over it
##   the plate     top centre under the turn order: both Twins' HP bars (D215
##                 style), the phase line and the rage countdown
## Light and dark are the only accents (B/W).

const BEAM_W := 0.62
const GLOW_W := 1.7
const LIFT := 0.06

var screen: BWCombatScreen
var battle: BWBattle
var _beam_root: Node3D
var _beam_mats: Array = []
var _beam_alpha := 1.0
var _ui: CanvasLayer
var _plate: PanelContainer
var _rows := {}               # role -> { bar, name, chip }
var _phase_label: Label
var _invert: ColorRect
var _rage_nodes := {}         # unit id -> Node3D (aura)
var _count_labels := {}       # unit id -> Label3D
var _t := 0.0
var _flare := 0.0
var _swapped := false

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform float alpha = 1.0;
uniform float glow = 0.0;
varying vec3 rim_col;
void vertex() {
	rim_col = CUSTOM0.rgb;
}
void fragment() {
	// UV.x along the beam (world units), UV.y across (0..1)
	float across = abs(UV.y - 0.5) * 2.0;
	float flow = 0.72 + 0.28 * sin(UV.x * 5.0 - TIME * 5.0);
	float a;
	vec3 c = COLOR.rgb;
	if (glow > 0.5) {
		a = (1.0 - smoothstep(0.0, 1.0, across)) * 0.55 * flow;
	} else {
		a = 1.0 - smoothstep(0.82, 1.0, across);
		// an ink rim so a light core reads on white tiles; a pale rim on a dark one
		float rim = smoothstep(0.62, 0.8, across);
		c = mix(c * (0.85 + 0.25 * flow), rim_col, rim);
	}
	ALBEDO = c;
	ALPHA = a * alpha * COLOR.a;
}
"""

const INVERT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// a B/W negative (luminance only): light and dark trade places, no off-palette hues
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(1.0 - l), amount), 1.0);
}
"""

const AURA_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float power = 1.0;
void fragment() {
	// UV.y 0 at the top of the column; fades up, flickers in vertical tongues
	float up = 1.0 - UV.y;
	float tongues = 0.55 + 0.45 * sin(UV.x * 37.7 + TIME * 6.0 + sin(TIME * 2.3 + UV.x * 12.0) * 2.0);
	float a = pow(1.0 - up, 1.6) * tongues * power;
	ALBEDO = col.rgb * a;
}
"""


func setup(s: BWCombatScreen) -> void:
	screen = s
	battle = s.battle
	name = "twins_fx"
	_beam_root = Node3D.new()
	_beam_root.name = "beam"
	add_child(_beam_root)
	_build_ui()
	_build_beam()
	refresh()


static func colour_of(element: String) -> Color:
	if element == "light":
		return Color(1.0, 0.93, 0.6)
	return Color(0.05, 0.03, 0.08)


static func glow_of(element: String) -> Color:
	if element == "light":
		return BWLook.glow_color("light").lerp(Color.WHITE, 0.25)
	return BWLook.element_color("dark").lerp(Color(0.8, 0.7, 1.0), 0.35)


static func rim_of(element: String) -> Color:
	return Color(0.08, 0.06, 0.02) if element == "light" else Color(0.72, 0.62, 0.95)


# ---------------------------------------------------------------- the beam

func _hex_top(h: Vector2i) -> Vector3:
	return BWLook.world(h, battle.board.elevation(h)) + Vector3(0, LIFT, 0)


## Rebuild the ribbon from a beam event (or the battle's beam at setup):
## the hexes between, each its colour, joined to the Twins' hexes at the ends.
var _last: Dictionary = {}


func _build_beam(e: Dictionary = {}, draw_in: bool = false) -> void:
	for c in _beam_root.get_children():
		c.queue_free()
	_beam_mats.clear()
	if e.is_empty():
		var bm: Array = battle.boss.get("beam", [])
		var n0 := BWTwins.twin(battle, BWTwins.NOON)
		var d0 := BWTwins.twin(battle, BWTwins.DUSK)
		e = { "hexes": bm.map(func(x): return x[0]), "colours": bm.map(func(x): return x[1]),
			"ends": [n0.pos if n0 else Vector2i.ZERO, d0.pos if d0 else Vector2i.ZERO] }
	_last = e
	var hexes: Array = e.get("hexes", [])
	var cols: Array = e.get("colours", [])
	if hexes.is_empty():
		return
	var pts: Array = [[e.ends[0], str(cols[0])]]
	for i in hexes.size():
		pts.append([hexes[i], str(cols[i])])
	pts.append([e.ends[1], str(cols[-1])])
	for glow in [true, false]:
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(pts, GLOW_W if glow else BEAM_W, glow)
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = BEAM_SHADER
		m.shader = sh
		m.set_shader_parameter("glow", 1.0 if glow else 0.0)
		m.render_priority = 1 if not glow else 0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.01 if glow else 0.02
		_beam_root.add_child(mi)
		_beam_mats.append(m)
	if draw_in:
		_beam_alpha = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_beam_alpha", 1.0, 0.35)


## A flat strip along the hex centres (each point's half coloured by its
## segment), UV.x = distance along, UV.y across. CUSTOM0 = the rim colour.
func _ribbon(pts: Array, w: float, glow: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var along := 0.0
	for i in pts.size() - 1:
		var a := _hex_top(pts[i][0])
		var b := _hex_top(pts[i + 1][0])
		var d := b - a
		var len := Vector2(d.x, d.z).length()
		if len < 0.001:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
		# split the step at its middle so each half takes its hex's colour
		var mid := (a + b) * 0.5
		for half in 2:
			var p0 := a if half == 0 else mid
			var p1 := mid if half == 0 else b
			var el: String = str(pts[i][1]) if half == 0 else str(pts[i + 1][1])
			var col := glow_of(el) if glow else colour_of(el)
			var rim := rim_of(el)
			var u0 := along + (0.0 if half == 0 else len * 0.5)
			var u1 := u0 + len * 0.5
			var quad := [[p0 - side, Vector2(u0, 0)], [p0 + side, Vector2(u0, 1)], [p1 + side, Vector2(u1, 1)],
				[p0 - side, Vector2(u0, 0)], [p1 + side, Vector2(u1, 1)], [p1 - side, Vector2(u1, 0)]]
			for q in quad:
				st.set_color(col)
				st.set_custom(0, rim)
				st.set_uv(q[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
		along += len
	return st.commit()


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 1.2)
	for m in _beam_mats:
		(m as ShaderMaterial).set_shader_parameter("alpha", _beam_alpha)
	# the ring heads breathe (Noon and Dusk out of step), flaring on the swap
	for u in battle.units:
		if not BWTwins.is_twin(u):
			continue
		var v: BWUnitView = screen._views.get(u.id)
		if v == null or v.character == null:
			continue
		var ph := 0.0 if BWTwins.role(u) == BWTwins.NOON else PI
		var p := (0.6 + 0.25 * sin(_t * TAU / 2.4 + ph) + _flare * 1.5) if u.alive() else 0.0
		for g in BWTwinsLook.glow_parts(v.character):
			(g as GeometryInstance3D).set_instance_shader_parameter("power", p)
	refresh()


# ---------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	match str(e.type):
		"beam":
			_build_beam(e, true)
		"beam_hit":
			var v: BWUnitView = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "Beam: %s" % ("Blinded" if e.colour == "light" else "Shrouded"),
					glow_of(str(e.colour)).lerp(Color.WHITE, 0.3), 0.7)
			_beam_alpha = 1.6
			create_tween().tween_property(self, "_beam_alpha", 1.0, 0.4)
			BWSfx.play("elem_light" if e.colour == "light" else "elem_dark", v, { "gain_db": -4.0, "tag": "beam" })
			await get_tree().create_timer(0.25).timeout
		"beam_break":
			screen.ui.banner("Thunder breaks the beam", 1.2)
			var tw := create_tween()
			for k in 3:
				tw.tween_property(self, "_beam_alpha", 0.15, 0.06)
				tw.tween_property(self, "_beam_alpha", 1.0, 0.06)
			tw.tween_property(self, "_beam_alpha", 0.0, 0.25)
			BWSfx.play("tile_detonate", null, { "gain_db": -3.0, "tag": "beam" })
			await tw.finished
			_build_beam({ "hexes": [], "colours": [] })
		"phase":
			if str(e.phase) == "swap":
				await swap_beat()
			elif str(e.phase) == "rage":
				await rage_beat(e.units)
		"phase_pending":
			for id in e.units:
				var v: BWUnitView = screen._views.get(str(id))
				screen.ui.banner("%s will rage in %d cycles. Down it first." % [screen._name(str(id)), int(e["in"])], 2.0)
				if v:
					screen.rig.follow(v.global_position)
			await get_tree().create_timer(1.2).timeout
		"phase_cancel":
			screen.ui.banner("Both down together: the rage never comes", 2.0)


## The swap: the whole screen inverts (a blink, twice), the ring heads trade
## glows, both Twins flare, a banner says what changed.
func swap_beat() -> void:
	_swapped = true
	var noon := BWTwins.twin(battle, BWTwins.NOON)
	var dusk := BWTwins.twin(battle, BWTwins.DUSK)
	if noon and dusk:
		screen.rig.follow((_hex_top(noon.pos) + _hex_top(dusk.pos)) * 0.5)
	BWSfx.play("cast_whoom", null, { "pitch": 0.5, "gain_db": -2.0, "tag": "swap" })
	var m := _invert.material as ShaderMaterial
	_invert.visible = true
	var tw := create_tween()
	tw.tween_method(func(x): m.set_shader_parameter("amount", x), 0.0, 1.0, 0.08)
	tw.tween_interval(0.12)
	tw.tween_method(func(x): m.set_shader_parameter("amount", x), 1.0, 0.0, 0.1)
	tw.tween_interval(0.08)
	tw.tween_callback(_trade_glows)
	tw.tween_method(func(x): m.set_shader_parameter("amount", x), 0.0, 1.0, 0.06)
	tw.tween_interval(0.3)
	tw.tween_method(func(x): m.set_shader_parameter("amount", x), 1.0, 0.0, 0.3)
	await tw.finished
	_invert.visible = false
	_flare = 1.0
	screen.ui.banner("The colours swap: Noon paints dark, Dusk paints light", 2.2)
	screen.ui.feed("[b]The Twins swap.[/b] Noon now paints dark and Dusk light; each heals ×2 on its own colour.")
	await get_tree().create_timer(1.0).timeout


func _trade_glows() -> void:
	for u in battle.units:
		if not BWTwins.is_twin(u):
			continue
		var v: BWUnitView = screen._views.get(u.id)
		if v == null or v.character == null:
			continue
		var el := BWTwins.colour(battle, u)
		for g in BWTwinsLook.glow_parts(v.character):
			(g as GeometryInstance3D).set_instance_shader_parameter("glow", glow_of(el).lerp(Color.WHITE, 0.15 if el == "light" else 0.0))


## The rage: the survivor's column, its ground ring, the banner.
func rage_beat(ids: Array) -> void:
	for id in ids:
		var u := battle._unit(str(id))
		var v: BWUnitView = screen._views.get(str(id))
		if u == null or v == null or _rage_nodes.has(u.id):
			continue
		screen.rig.follow(v.global_position)
		var el := BWTwins.colour(battle, u)
		var aura := Node3D.new()
		aura.name = "rage_aura"
		v.add_child(aura)
		var col := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 0.55
		cyl.height = 3.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 24
		col.mesh = cyl
		col.position.y = 1.5
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = AURA_SHADER
		m.shader = sh
		var c := glow_of(el)
		m.set_shader_parameter("col", c if el == "light" else c.lerp(Color(0.6, 0.4, 1.0), 0.4))
		m.set_shader_parameter("power", 1.8)
		col.material_override = m
		col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aura.add_child(col)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.62
		tm.outer_radius = 0.72
		tm.rings = 40
		tm.ring_segments = 4
		ring.mesh = tm
		ring.scale.y = 0.15
		ring.position.y = 0.05
		ring.material_override = BWObeliskView.glyph_material()
		ring.set_instance_shader_parameter("glow", glow_of(el))
		ring.set_instance_shader_parameter("power", 1.0)
		aura.add_child(ring)
		_rage_nodes[u.id] = aura
		var tw := create_tween()
		aura.scale = Vector3(0.2, 0.2, 0.2)
		tw.tween_property(aura, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		BWSfx.play("cast_whoom", v, { "pitch": 0.4, "gain_db": -1.0, "tag": "rage" })
		screen._float_text(v, "RAGE", Color.WHITE, 1.2)
		screen.ui.banner("%s rages: +1 move, paints twice as far" % u.name, 2.2)
		screen.ui.feed("[b]%s rages.[/b] +1 move; its paint reaches 2 hexes." % u.name)
		await get_tree().create_timer(1.1).timeout


# ---------------------------------------------------------------- the plate

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_invert = ColorRect.new()
	_invert.set_anchors_preset(Control.PRESET_FULL_RECT)
	_invert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var im := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = INVERT_SHADER
	im.shader = sh
	_invert.material = im
	_invert.visible = false
	_ui.add_child(_invert)
	_plate = PanelContainer.new()
	_plate.add_theme_stylebox_override("panel", BWStyle.frame_style())
	_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	_ui.add_child(_plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_plate.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(top)
	for r in BWTwins.ROLES:
		var u := BWTwins.twin(battle, r)
		if u == null:
			continue
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		col.tooltip_text = BWTwins.beam_text()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(12, 12)
		head.add_child(chip)
		var nm := Label.new()
		nm.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
		nm.add_theme_color_override("font_color", BWStyle.TEXT)
		head.add_child(nm)
		col.add_child(head)
		var bar := BWWidgets.HPBar.new(Vector2(250, 12))
		bar.enemy = true
		bar.track = true
		col.add_child(bar)
		top.add_child(col)
		_rows[r] = { "bar": bar, "name": nm, "chip": chip, "unit": u, "box": col }
	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", BWStyle.F_SMALL - 2)
	_phase_label.add_theme_color_override("font_color", BWStyle.LABEL)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_phase_label)


func refresh() -> void:
	if _plate == null:
		return
	for r in _rows:
		var row: Dictionary = _rows[r]
		var u: BWUnit = row.unit
		row.bar.set_hp(u.hp, u.max_hp())
		var el := BWTwins.colour(battle, u)
		row.chip.color = glow_of(el) if el == "light" else Color(0.45, 0.32, 0.75)
		var tag := ""
		if not u.alive():
			tag = "   DOWN"
		elif BWTwins.raging(battle, u):
			tag = "   RAGING"
		elif BWPhases.countdown(battle, "rage") >= 0:
			tag = "   rage in %d" % BWPhases.countdown(battle, "rage")
		row.name.text = "%s  · %s%s" % [u.name, el, tag]
		row.box.modulate = Color(1, 1, 1, 0.45) if not u.alive() else Color.WHITE
	var line := "Phase 1 · each heals on its own colour · apart, a beam joins them"
	if BWPhases.fired(battle, "rage"):
		line = "Rage · +1 move, paint radius 2"
	elif BWPhases.countdown(battle, "rage") >= 0:
		line = "One down · the other rages in %d cycle%s" % [BWPhases.countdown(battle, "rage"), "" if BWPhases.countdown(battle, "rage") == 1 else "s"]
	elif BWPhases.fired(battle, "swap"):
		line = "Phase 2 · colours swapped · heals ×2"
	_phase_label.text = line
	# under the turn order, centred
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)
	var y := (BWHPBar3D.hud_rect.end.y + 6.0) if BWHPBar3D.hud_rect.has_area() else 130.0
	_plate.reset_size()
	_plate.position = Vector2((vp.x - _plate.size.x) * 0.5, y)
	_counters()


## "RAGE IN n" over a survivor while the rage is pending.
func _counters() -> void:
	var n := BWPhases.countdown(battle, "rage")
	for u in battle.units:
		if not BWTwins.is_twin(u):
			continue
		var want: bool = u.alive() and n >= 0
		var lab: Label3D = _count_labels.get(u.id)
		if want and lab == null:
			var v: BWUnitView = screen._views.get(u.id)
			if v == null:
				continue
			lab = Label3D.new()
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.no_depth_test = true
			lab.fixed_size = true
			lab.pixel_size = 0.0013
			lab.font_size = 26
			lab.outline_size = 10
			lab.modulate = Color.WHITE
			lab.outline_modulate = Color.BLACK
			lab.render_priority = 16              # over the board's transparent tiles
			lab.outline_render_priority = 15
			BWKeystoneView.bar_mark(v, lab, 2)    # D299: on its HP bar, clamped below the turn order
			_count_labels[u.id] = lab
		if lab:
			lab.visible = want
			if want:
				lab.text = "RAGE IN %d" % n


# ---------------------------------------------------------------- intro

## The title card: a black band across the middle, the name large, the two
## Twins' colours as chips, the rule in one line. ~2.8 s, then play.
func intro() -> void:
	var band := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.9)
	sb.border_color = Color.WHITE
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	band.add_theme_stylebox_override("panel", sb)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(band)
	var vp := get_viewport().get_visible_rect().size
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	band.add_child(v)
	var kick := Label.new()
	kick.text = "FIGHT 7"
	kick.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	kick.add_theme_color_override("font_color", BWStyle.LABEL)
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kick)
	var title := Label.new()
	title.text = BWTwins.TITLE
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 14)
	for el in ["light", "dark"]:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(120, 4)
		c.color = glow_of(el) if el == "light" else Color(0.5, 0.36, 0.85)
		chips.add_child(c)
	v.add_child(chips)
	var sub := Label.new()
	sub.text = "Noon paints light, Dusk paints dark. Apart, a beam joins them. Paint over their ground, thunder the beam, down both together."
	sub.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	sub.add_theme_color_override("font_color", BWStyle.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	band.size = Vector2(vp.x, 0)
	band.reset_size()
	band.size.x = vp.x
	band.position = Vector2(0, vp.y * 0.36)
	band.modulate.a = 0.0
	var noon := BWTwins.twin(battle, BWTwins.NOON)
	var dusk := BWTwins.twin(battle, BWTwins.DUSK)
	if noon and dusk:
		screen.rig.follow((_hex_top(noon.pos) + _hex_top(dusk.pos)) * 0.5)
	_flare = 1.0
	var tw := create_tween()
	tw.tween_property(band, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.3)
	tw.tween_property(band, "modulate:a", 0.0, 0.35)
	await tw.finished
	band.queue_free()

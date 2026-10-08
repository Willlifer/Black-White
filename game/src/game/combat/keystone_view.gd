class_name BWKeystoneView
extends Node3D
## D293-D299 readability for the wind, ice, water and dark keystones (rules:
## BWKsWind, BWKsIce, BWKsWater, BWKsDark). Two halves:
##
## Standing marks, read from the battle when it changes (a signature):
##   Frozen       the unit encased in an inked ice prism (translucent ice
##                faces, black contours, a frosted foot ring) and a "x2" tag
##   Doomed       an ink ring of thorns on the ground under it, and a "DOOM n"
##                countdown tag (n = turns of its own until the burst)
##   (gale 3      D406: no own mark any more; every gale is the tile shader's
##                one swirl, gale 2+ the bigger one)
##   Unsteady     (D397, any unit on glaze or holding the status) a thin
##                ice-blue ring at its feet, broken by short ink cracks, that
##                rocks gently: bad footing, read at a glance
## Unit tags sit on the unit's HP bar (bar_mark), so they follow its clamp
## below the turn order (D217) and its cull behind HUD panels (D230).
##
## One-shots (on_event, from BWCombatScreen._play):
##   tidal        a water wave crest that runs the line, the drained pool
##                flashes
##   wellspring   water droplets rising round the healed unit
##   contagion    ink jump lines arcing from the fallen to each new host
##   doomed/doom  "DOOMED" over it; the burst: a dark ink ring blast, a shake
##   frozen/thaw  an ice flash; shards on the thaw; "FROZEN: skips" on a skip
##   pillar_shatter  ice shards flung out to the six neighbours
##   riptide / event_horizon  a quick ring at the centre, a feed line

const INK := Color(0.02, 0.02, 0.03)
const LIFT := 0.05

var screen: BWCombatScreen
var _mesh: MeshInstance3D
var _sig := ""
var _tags := {}            # unit id -> Label3D
var _shells := {}          # unit id -> MeshInstance3D (the ice)
var shown := {}            # probes / review: { frozen: [ids], doomed: {id: n}, gale3: [hexes], unsteady: [ids] }
var _rings := {}           # D397: unit id -> MeshInstance3D, the Unsteady crack ring (rocked in _process)
var _t := 0.0
static var _crack_mesh: ArrayMesh
static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.render_priority = 1
	return _mat


func setup(s: BWCombatScreen) -> void:
	screen = s
	_mesh = MeshInstance3D.new()
	_mesh.material_override = material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## A tag Label3D on a unit's HP bar: under the bar, `slot` rows down (0 is
## the first row). It moves with the bar's clamp and hides with its cull.
static func bar_mark(v: Node3D, l: Label3D, slot: int) -> void:
	var bar: Node3D = v.get("_hp_bar") if v != null and "_hp_bar" in v else null
	var parent: Node3D = bar if bar != null else v
	if l.get_parent() != parent:
		if l.get_parent() != null:
			l.get_parent().remove_child(l)
		parent.add_child(l)
	l.position = Vector3.ZERO if bar != null else Vector3(0, 2.6, 0)
	var sc := parent.global_transform.basis.get_scale().y if parent.is_inside_tree() else 1.0
	l.scale = Vector3.ONE / maxf(sc, 0.01)          # the same size over a scaled figure (the Twins, a boss)
	l.offset = Vector2(0, -30.0 - 34.0 * slot) / (l.pixel_size / 0.0011) if bar != null else Vector2.ZERO


static func make_tag(size: int = 24) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 9
	l.modulate = INK
	l.outline_modulate = Color(1, 1, 1)
	l.render_priority = 16
	l.outline_render_priority = 15
	return l


func _process(delta: float) -> void:
	if screen == null or screen.battle == null:
		return
	_t += delta
	var k := 0
	for id in _rings:                                       # D397: the cracked ice rocks a little
		(_rings[id] as Node3D).rotation = Vector3(0.06 * sin(_t * 2.6 + k), 0.0, 0.06 * sin(_t * 2.1 + 1.3 + k))
		k += 1
	var b := screen.battle
	var sig := _signature(b)
	if sig != _sig and not screen._busy:
		_sig = sig
		rebuild()
	_follow(b)


func _signature(b: BWBattle) -> String:
	var parts: PackedStringArray = []
	for u in b.units:
		if not u.alive():
			continue
		if BWKsIce.frozen(u):
			parts.append("f%s%s" % [u.id, u.pos])
		if BWKsDark.doomed(u):
			parts.append("d%s%s%d" % [u.id, u.pos, doom_left(b, u)])
		if BWUnsteady.unsteady(b, u):
			parts.append("u%s%s" % [u.id, u.pos])
	return "|".join(parts)


## Turns of its own left before a doomed unit's burst (1 = at the end of its
## next turn; 0 = at the end of this one).
static func doom_left(b: BWBattle, u: BWUnit) -> int:
	var d: Dictionary = u.fx.get("doom", {})
	if d.is_empty():
		return -1
	return 0 if b.current() == u and int(d.at) < b._turn_serial else 1


func _gale3(b: BWBattle) -> Array:
	var out: Array = []
	for h in b.tiles.entries:
		var e: Dictionary = b.tiles.entries[h]
		if str(e.get("marker", "")) == "gale" and int(e.get("gale_level", 1)) >= 3:
			out.append(h)
	out.sort()
	return out


func rebuild() -> void:
	var b := screen.battle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	# D406: a gale 3 no longer gets its own ringed swirl (one gale look: the
	# tile shader's swirl), and the Eye of the Vortex has no field to ring.
	shown = { "frozen": [], "doomed": {}, "gale3": _gale3(b), "unsteady": [] }
	for u in b.units:
		if u.alive() and BWKsDark.doomed(u):
			shown.doomed[u.id] = doom_left(b, u)
			_thorns(st, _top(u.pos))
			n += 1
		if u.alive() and BWKsIce.frozen(u):
			shown.frozen.append(u.id)
		if BWUnsteady.unsteady(b, u):
			shown.unsteady.append(u.id)
	_mesh.mesh = st.commit() if n > 0 else null
	for id in _rings.keys():                                # D397: the Unsteady crack rings
		if not id in shown.unsteady:
			(_rings[id] as Node).queue_free()
			_rings.erase(id)
	for u in b.units:
		if u.id in shown.unsteady:
			if not _rings.has(u.id):
				var mi := MeshInstance3D.new()
				mi.mesh = crack_mesh()
				mi.material_override = material()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				_rings[u.id] = mi
			(_rings[u.id] as Node3D).position = _top(u.pos)
	# the ice shells
	for id in _shells.keys():
		if not id in shown.frozen:
			(_shells[id] as Node).queue_free()
			_shells.erase(id)
	for id in shown.frozen:
		if not _shells.has(id) and screen._views.has(id):
			var sh := _shell(screen._views[id])
			add_child(sh)
			_shells[id] = sh
	# the tags
	for id in _tags.keys():
		if not id in shown.frozen and not shown.doomed.has(id):
			(_tags[id] as Node).queue_free()
			_tags.erase(id)
	for u in b.units:
		var bits: PackedStringArray = []
		if u.id in shown.frozen:
			bits.append("FROZEN x2")
		if shown.doomed.has(u.id):
			bits.append("DOOM %s" % ("NOW" if int(shown.doomed[u.id]) == 0 else str(shown.doomed[u.id])))
		if bits.is_empty() or not screen._views.has(u.id):
			continue
		var l: Label3D = _tags.get(u.id)
		if l == null or not is_instance_valid(l):
			l = make_tag(22)
			_tags[u.id] = l
		l.text = "  ·  ".join(bits)
		l.modulate = INK
		bar_mark(screen._views[u.id], l, 1)


func _follow(b: BWBattle) -> void:
	for id in _shells:
		var v: Node3D = screen._views.get(id)
		if v != null:
			(_shells[id] as Node3D).global_position = v.global_position
			(_shells[id] as Node3D).visible = v.visible


## Tag text by unit id (probes, review).
func tag_text(id: String) -> String:
	var l: Label3D = _tags.get(id)
	return l.text if l != null and is_instance_valid(l) else ""


# ---------------------------------------------------------------- the marks

func _top(h: Vector2i) -> Vector3:
	return screen.board_view.top_center(h) + Vector3(0, LIFT, 0)


## The ice encasing a Frozen unit: a six-sided prism to above its head.
func _shell(v: Node3D) -> MeshInstance3D:
	var hh: float = (v as BWUnitView).head_height() + 0.35 if v is BWUnitView else 2.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ice := BWLook.element_color("ice")
	var c := Vector3.ZERO
	var r0 := 0.5
	var bot := BWLook.hex_corners(c + Vector3(0, 0.02, 0), r0)
	var top := BWLook.hex_corners(c + Vector3(0, hh, 0), r0 * 0.82)
	var tip := c + Vector3(0.05, hh + 0.3, -0.03)
	for i in 6:
		var k := (i + 1) % 6
		var shade := 0.5 + 0.5 * absf(sin(i * 1.1 + 0.3))
		_quad(st, bot[i], bot[k], top[k], top[i], Color(Color.WHITE.lerp(ice, 0.5 * shade), 0.32))
		_tri(st, top[i], top[k], tip, Color(Color.WHITE.lerp(ice, 0.3), 0.45))
		_edge(st, bot[i], top[i], 0.05)
		_edge(st, top[i], tip, 0.035)
		_edge(st, bot[i], bot[k], 0.05)
		_edge(st, top[i], top[k], 0.035)
		# frost cracks
		if i % 2 == 1:
			var m0 := bot[i].lerp(bot[k], 0.3).lerp(top[i].lerp(top[k], 0.6), 0.25)
			var m1 := bot[i].lerp(bot[k], 0.7).lerp(top[i].lerp(top[k], 0.4), 0.7)
			_edge(st, m0, m1, 0.025)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.sorting_offset = 3.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _thorns(st: SurfaceTool, c: Vector3) -> void:
	var col := Color(0.24, 0.1, 0.36, 0.95)
	_ring(st, c, 0.62, 0.07, INK)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		_tri(st, c + d * 0.62 + s * 0.07, c + d * 0.62 - s * 0.07, c + d * 0.86, INK)
	_ring(st, c, 0.48, 0.035, col)


## D397 Unsteady: a thin ice ring at the feet, broken by short ink cracks
## that run out across it (a cracked ice sheet), with ink rims.
static func crack_mesh() -> ArrayMesh:
	if _crack_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cracks(st, Vector3.ZERO)
		_crack_mesh = st.commit()
	return _crack_mesh


static func _cracks(st: SurfaceTool, c: Vector3) -> void:
	var ice := Color(BWLook.element_color("ice"), 0.9)
	var r := 0.5
	var seg := 30
	for i in seg:
		if i % 6 == 5:
			continue                                   # gaps where it's cracked through
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * (r - 0.05), c + d0 * (r + 0.05), c + d1 * (r + 0.05), c + d1 * (r - 0.05), ice)
		_quad(st, c + d0 * (r + 0.05), c + d0 * (r + 0.075), c + d1 * (r + 0.075), c + d1 * (r + 0.05), INK)
		_quad(st, c + d0 * (r - 0.075), c + d0 * (r - 0.05), c + d1 * (r - 0.05), c + d1 * (r - 0.075), INK)
	for k in 6:                                        # zig-zag cracks across the ring
		var a := TAU * (k + 0.37) / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		var p0 := c + d * (r - 0.16)
		var p1 := c + d * (r - 0.02) + s * 0.05
		var p2 := c + d * (r + 0.1) - s * 0.03
		var p3 := c + d * (r + 0.2) + s * 0.04
		_ribbon(st, p0, p1, 0.035, INK)
		_ribbon(st, p1, p2, 0.03, INK)
		_ribbon(st, p2, p3, 0.022, INK)


# ---------------------------------------------------------------- one-shots

func on_event(e: Dictionary) -> void:
	var b := screen.battle
	match str(e.type):
		"tidal":
			screen.ui.feed("[b]Tidal Release[/b]: the pool drains and a wave runs %d hexes" % (e.line as Array).size())
			await wave(e.line, int(e.dir))
			screen.board_view.refresh_tiles()
		"wellspring":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				droplets(v.global_position)
		"contagion":
			var from: Vector3 = screen.board_view.top_center(e.hex) + Vector3(0, 1.2, 0)
			for id in e.to:
				var v: Node3D = screen._views.get(str(id))
				if v:
					jump_line(from, v.global_position + Vector3(0, 1.4, 0))
			screen.ui.feed("[b]Contagion[/b]: the Rot jumps to %d" % (e.to as Array).size())
			await get_tree().create_timer(0.55).timeout
		"doomed":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "DOOMED", Color(0.75, 0.6, 1.0), 1.0)
			screen.ui.feed("[b]%s is Doomed[/b]: it bursts at the end of its next turn" % screen._name(str(e.unit)))
		"doom":
			var at: Vector3 = screen.board_view.top_center(e.hex)
			blast(at, Color(0.3, 0.12, 0.45), 1.9)
			screen._shake(0.14)
			screen.ui.banner("Doom", 0.8)
			screen.ui.feed("[b]Doom[/b]: %d%% to %s, half to its neighbours" % [int(e.pct), screen._name(str(e.unit))])
			if screen.readability:
				await screen.readability.beat(e.hex)
			await get_tree().create_timer(0.3).timeout
		"frozen":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				blast(v.global_position + Vector3(0, 0.05, 0), BWLook.element_color("ice"), 1.0)
				screen._float_text(v, "FROZEN", Color(0.85, 0.95, 1.0), 0.9)
			_sig = ""
			await get_tree().create_timer(0.35).timeout
		"thaw":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				shards(v.global_position + Vector3(0, 1.0, 0), 10, 1.0)
			_sig = ""
		"frozen_skip":
			var v: Node3D = screen._views.get(str(e.unit))
			if v:
				screen._float_text(v, "Frozen: skips", Color(0.85, 0.95, 1.0), 0.8)
			screen.ui.feed("%s is frozen and skips its turn" % screen._name(str(e.unit)))
			await get_tree().create_timer(0.45).timeout
		"pillar_shatter":
			var at: Vector3 = screen.board_view.top_center(e.hex)
			shards(at + Vector3(0, 0.9, 0), 18, 1.6)
			blast(at, BWLook.element_color("ice"), 1.6)
			screen._shake(0.1)
			screen.board_view.refresh_tiles()
			screen.ui.feed("[b]Break Pillar[/b]: the ice bursts, %d%% to the six around" % int(e.pct))
			await get_tree().create_timer(0.3).timeout
		"riptide":
			screen.ui.feed("[b]Riptide[/b]: %s drags %d through the water" % [screen._name(str(e.unit)), (e.units as Array).size()])
		"event_horizon":
			screen.ui.feed("[b]Event Horizon[/b] pulls %d toward the dark" % (e.units as Array).size())
	_sig = "" if str(e.type) in ["doomed", "doom", "frozen", "thaw"] else _sig


## A wave crest that runs the line: a curled blue ribbon with an ink rim,
## sweeping start to end in ~0.55 s, then sinking.
func wave(line: Array, dir: int) -> void:
	if line.is_empty():
		return
	var pts: Array = line.map(func(h): return screen.board_view.top_center(h))
	var fwd := BWWeather.heading_vector(dir)
	var f3 := Vector3(fwd.x, 0, fwd.y)
	var side := Vector3(-f3.z, 0, f3.x)
	var mi := MeshInstance3D.new()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 3.0
	mi.mesh = _crest(side, 1.0)
	add_child(mi)
	mi.global_position = pts[0] - f3 * 0.6
	var tw := create_tween()
	var dur := 0.12 * pts.size() + 0.2
	tw.tween_property(mi, "global_position", (pts[-1] as Vector3) + f3 * 0.3, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "scale", Vector3(1, 0.05, 1), 0.2)
	tw.tween_callback(mi.queue_free)
	# a wet trail
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dt := create_tween()
		dt.tween_interval(0.12 * i)
		dt.tween_callback(func():
			blast(p, BWLook.element_color("water"), 0.8))
	await tw.finished


## The crest: a curl profile (rising, then curling over) swept across `side`.
func _crest(side: Vector3, w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water := BWLook.element_color("water")
	var prof: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var a := t * PI * 1.25
		prof.append(Vector3(0, 0, 0) + Vector3(0, sin(a) * 0.95, 0) + side.cross(Vector3.UP) * (-0.55 * cos(a) + 0.2 * t))
	var half := side * w * 0.95
	for i in prof.size() - 1:
		var col := Color(water.lerp(Color.WHITE, 0.25 * i / 8.0), 0.85)
		_quad(st, prof[i] - half, prof[i] + half, prof[i + 1] + half, prof[i + 1] - half, col)
	for i in prof.size() - 1:
		var a: Vector3 = prof[i]
		var bb: Vector3 = prof[i + 1]
		var up := (bb - a).cross(side).normalized() * 0.04
		if i >= 5:
			_quad(st, a - half + up, a + half + up, bb + half + up, bb - half + up, INK)
	# white foam dashes on the lip
	for k in 5:
		var s0 := -half + half * 2.0 * (k + 0.2) / 5.0
		var s1 := -half + half * 2.0 * (k + 0.7) / 5.0
		var lip: Vector3 = prof[prof.size() - 2]
		_quad(st, lip + s0, lip + s1, lip + s1 + Vector3(0, 0.07, 0), lip + s0 + Vector3(0, 0.07, 0), Color.WHITE)
	return st.commit()


## Water droplets rising round a unit (Wellspring).
func droplets(at: Vector3) -> void:
	var water := BWLook.element_color("water")
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		var p := at + Vector3(cos(a) * 0.45, 0.15, sin(a) * 0.45)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.2
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = water.lerp(Color.WHITE, 0.15)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = p
		var tw := create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(mi, "global_position", p + Vector3(0, 1.3 + 0.2 * (i % 3), 0), 0.8).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.8).set_delay(0.3)
		tw.tween_callback(mi.queue_free)


## An ink arc from `a` to `b` that draws itself, then fades (Contagion).
func jump_line(a: Vector3, b: Vector3) -> void:
	var pts: Array = []
	for i in 17:
		var t := float(i) / 16.0
		pts.append(a.lerp(b, t) + Vector3(0, sin(t * PI) * 1.1, 0))
	var mi := MeshInstance3D.new()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 4.0
	add_child(mi)
	var col := Color(0.28, 0.12, 0.42)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := maxi(2, int(t * pts.size()))
		for i in n - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var cam := get_viewport().get_camera_3d()
			var view := (cam.global_position - p0).normalized() if cam else Vector3.UP
			var sd := (p1 - p0).cross(view).normalized()
			_quad(st, p0 - sd * 0.06, p0 + sd * 0.06, p1 + sd * 0.06, p1 - sd * 0.06, INK)
			_quad(st, p0 - sd * 0.03, p0 + sd * 0.03, p1 + sd * 0.03, p1 - sd * 0.03, col)
		mi.mesh = st.commit(), 0.0, 1.0, 0.35)
	tw.tween_interval(0.35)
	tw.tween_property(mi, "transparency", 1.0, 0.25)
	tw.tween_callback(mi.queue_free)


## A flat expanding ring blast at `at` (Doom, Frozen, the Eye).
func blast(at: Vector3, col: Color, radius: float, thin: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st, Vector3(0, 0.08, 0), 1.0, 0.06 if thin else 0.14, INK)
	_ring(st, Vector3(0, 0.085, 0), 0.9, 0.04 if thin else 0.12, Color(col, 0.9))
	mi.mesh = st.commit()
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mi, "transparency", 1.0, 0.4).set_delay(0.15)
	tw.tween_callback(mi.queue_free)


## Ice shards flung outward and down (a thaw, a shatter).
func shards(at: Vector3, n: int, reach: float) -> void:
	var ice := BWLook.element_color("ice")
	for i in n:
		var a := TAU * i / n + 0.2 * (i % 3)
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.09, 0.26, 0.06)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.WHITE.lerp(ice, 0.35 + 0.3 * (i % 2))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at
		mi.rotation = Vector3(0.6 * i, a, 0.4 * i)
		var to := at + Vector3(cos(a) * reach, -0.6 - 0.1 * (i % 4), sin(a) * reach)
		var tw := create_tween()
		tw.tween_property(mi, "global_position", to, 0.45).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation", mi.rotation + Vector3(3, 2, 1), 0.45)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.2)
		tw.tween_callback(mi.queue_free)


# ---------------------------------------------------------------- geometry

static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0
	if d.length() < 0.0001:
		return
	var s := Vector3(-d.z, 0, d.x).normalized() * w * 0.5
	_quad(st, a - s, a + s, b + s, b - s, col)


func _ring(st: SurfaceTool, c: Vector3, r: float, w: float, col: Color) -> void:
	var seg := 32
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, c + d0 * (r - w * 0.5), c + d0 * (r + w * 0.5), c + d1 * (r + w * 0.5), c + d1 * (r - w * 0.5), col)


## An ink edge strip between two points, facing roughly outward.
func _edge(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var mid := (a + b) * 0.5
	var out := Vector3(mid.x, 0, mid.z)
	out = out.normalized() if out.length() > 0.001 else Vector3.FORWARD
	var d := (b - a).normalized()
	var s := d.cross(out).normalized() * w * 0.5
	var o := out * 0.01
	_quad(st, a - s + o, b - s + o, b + s + o, a + s + o, INK)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)

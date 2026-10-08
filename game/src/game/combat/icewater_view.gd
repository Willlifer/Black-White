class_name BWIceWaterView
extends Node3D
## D266 the ice/water spine on the board (design/ELEMENTS-v3.md §11 "Board
## marks"), redrawn from BWTiles by BWBoardView.refresh_tiles:
##   * GLAZE SHEEN: every glazed hex a unit can stand on (Unsteady ground,
##     D397) gets glints and ink lines over its frost (shaders/icewater mode 0);
##   * PILLAR: an inked ice column, white facets with an ice-cyan band and
##     black contours, its ticks left floating over it;
##   (D421: the steam puffs are gone with steam; the shader's mode 1 is unused);
##   * ELECTRIFIED: each field's outer boundary as a crackling purple ribbon
##     (re-rolled ~13x/s like the chain bolts), and its timer as purple pips
##     over the field (one per tick left).

const PILLAR_R := 0.56
const PILLAR_H := 1.75
const INK := Color(0.02, 0.02, 0.03)
const REROLL := 0.075

var bv: BWBoardView
var _sheen := {}          # hex -> MeshInstance3D
var _pillar := {}         # hex -> [MeshInstance3D, Label3D]
var _shock_glow: MeshInstance3D
var _shock_core: MeshInstance3D
var _pips: Array = []     # MeshInstance3D
var _edges: Array = []    # [[Vector3, Vector3]]
var _t := 0.0
var _next := 0.0
static var _mats := {}


func setup(p_bv: BWBoardView) -> void:
	bv = p_bv
	_shock_glow = _bolt_node(Color(BWLook.glow_color("thunder"), 0.85))
	_shock_core = _bolt_node(Color(1.0, 0.95, 1.0, 1.0))


static func material(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"sheen":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/icewater.gdshader")
			sm.set_shader_parameter("mode", 0)
			sm.set_shader_parameter("glow", BWLook.element_color("ice"))
			m = sm
		"pillar":
			var pm := StandardMaterial3D.new()
			pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.vertex_color_use_as_albedo = true
			pm.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = pm
		"hull":
			var hm := StandardMaterial3D.new()
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hm.albedo_color = INK
			hm.cull_mode = BaseMaterial3D.CULL_FRONT
			m = hm
		"pip":
			var qm := StandardMaterial3D.new()
			qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			qm.vertex_color_use_as_albedo = true
			qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			qm.cull_mode = BaseMaterial3D.CULL_DISABLED
			qm.no_depth_test = true
			qm.render_priority = 3
			m = qm
	_mats[kind] = m
	return m


## The shaders and meshes BWShaderWarm compiles offscreen at boot (D232).
static func warm_catalog() -> Array:
	var out: Array = []
	for k in ["sheen", "pillar", "pip", "hull"]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		mi.mesh = BWTileFX.hex_mesh() if k == "sheen" else q
		mi.material_override = material(k)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(["icewater_" + k, mi])
	return out


## Sync every mark with the tiles.
func refresh() -> void:
	if bv == null or bv.tiles == null:
		return
	var t := bv.tiles
	var want_sheen := {}
	for h in t.entries:
		if bv.board.exists(h) and BWUnsteady.on_glaze(t, h):
			want_sheen[h] = true
	_sync(_sheen, want_sheen, _make_sheen)
	var want_p := {}
	for h in t.pillars:
		if t.is_pillar(h):
			want_p[h] = true
	_sync(_pillar, want_p, _make_pillar)
	for h in _pillar:
		(_pillar[h][1] as Label3D).text = "∞" if bool(t.pillars[h].get("glacier", false)) else str(int(t.pillars[h].ticks))   # D294 Glacier Wall
	_build_edges()
	_reroll()


func _sync(have: Dictionary, want: Dictionary, make: Callable) -> void:
	for h in have.keys():
		if not want.has(h):
			for n in (have[h] if have[h] is Array else [have[h]]):
				if is_instance_valid(n):
					n.queue_free()
			have.erase(h)
	for h in want:
		if not have.has(h) and bv.board.exists(h):
			have[h] = make.call(h)


func _make_sheen(h: Vector2i) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BWTileFX.hex_mesh()
	mi.material_override = material("sheen")
	mi.position = bv.top_center(h) + Vector3(0, 0.03, 0)
	mi.sorting_offset = BWTileFX.SORT_MARK + 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("seed", BWTileFX.seed_for(h, 31))
	add_child(mi)
	return mi


## An inked ice column: a hexagonal prism with a faceted crown, white faces
## shaded per facet toward ice cyan, an ice-cyan band at the foot, black
## contour strips on every vertical edge and round both rims.
func _make_pillar(h: Vector2i) -> Array:
	var c := bv.top_center(h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ice := BWLook.element_color("ice")
	var bot := BWLook.hex_corners(c + Vector3(0, -0.02, 0), PILLAR_R)
	var top := BWLook.hex_corners(c + Vector3(0, PILLAR_H, 0), PILLAR_R * 0.86)
	var tip := c + Vector3(0.06, PILLAR_H + 0.55, -0.04)
	for i in 6:
		var n := (i + 1) % 6
		var shade := 0.55 + 0.45 * absf(sin(i * 1.05 + 0.4))
		var face := Color.WHITE.lerp(ice, 0.22 * (1.0 - shade))
		_quad(st, bot[i], bot[n], top[n], top[i], face)
		# the ice-cyan band at the foot
		var b0 := bot[i].lerp(top[i], 0.07)
		var b1 := bot[n].lerp(top[n], 0.07)
		var b2 := bot[n].lerp(top[n], 0.16)
		var b3 := bot[i].lerp(top[i], 0.16)
		_quad(st, b0, b1, b2, b3, ice)
		# a crack line up one face in two
		if i % 2 == 0:
			var m0 := bot[i].lerp(bot[n], 0.4).lerp(top[i].lerp(top[n], 0.55), 0.2)
			var m1 := bot[i].lerp(bot[n], 0.6).lerp(top[i].lerp(top[n], 0.35), 0.75)
			_strip(st, m0, m1, 0.035, INK, c)
		# the crown facet
		_tri(st, top[i], top[n], tip, Color.WHITE.lerp(ice, 0.35 * (1.0 - shade)))
		# contours (D299: heavier side edges, so the column's sides read)
		_strip(st, bot[i], top[i], 0.11, INK, c)
		_strip(st, bot[i], bot[n], 0.05, INK, c)
		_strip(st, top[i], top[n], 0.04, INK, c)
		_strip(st, top[i], tip, 0.035, INK, c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material("pillar")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# D299: an inked silhouette: a slightly larger black hull drawn back faces
	# only, so the column's sides always carry an outline whatever the angle
	var hull := MeshInstance3D.new()
	hull.mesh = _hull(c, ice)
	hull.material_override = material("hull")
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(hull)
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 26
	l.outline_size = 10
	l.modulate = Color.WHITE
	l.outline_modulate = Color(ice.darkened(0.55))
	l.position = c + Vector3(0, PILLAR_H + 0.95, 0)
	l.render_priority = 12
	l.outline_render_priority = 11
	add_child(l)
	return [mi, l]


## D299: the pillar's ink hull (the prism and crown grown outward ~5 cm).
func _hull(c: Vector3, _ice: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := 0.055
	var bot := BWLook.hex_corners(c + Vector3(0, -0.02, 0), PILLAR_R + g)
	var top := BWLook.hex_corners(c + Vector3(0, PILLAR_H + g * 0.5, 0), PILLAR_R * 0.86 + g)
	var tip := c + Vector3(0.06, PILLAR_H + 0.55 + g * 1.6, -0.04)
	for i in 6:
		var n := (i + 1) % 6
		_quad(st, bot[i], bot[n], top[n], top[i], INK)
		_tri(st, top[i], top[n], tip, INK)
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


## A contour strip from a to b, pushed a hair outward from the column axis
## (so it sits on the face it outlines).
func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color, axis: Vector3) -> void:
	var mid := (a + b) * 0.5
	var out := Vector3(mid.x - axis.x, 0, mid.z - axis.z).normalized() * 0.012
	var d := (b - a).normalized()
	var side := d.cross(out.normalized() if out.length() > 0.001 else Vector3.UP).normalized() * w * 0.5
	_quad(st, a - side + out, b - side + out, b + side + out, a + side + out, col)


# ---------------------------------------------------------------- electrified fields

func _bolt_node(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 2.5
	add_child(mi)
	return mi


## Every field hex edge whose neighbour isn't in the same field: the pool's
## outline. Plus the timer pips (ticks left) over each field's middle hex.
func _build_edges() -> void:
	_edges.clear()
	for p in _pips:
		if is_instance_valid(p):
			p.queue_free()
	_pips.clear()
	var t := bv.tiles
	for id in t.fields:
		var f: Dictionary = t.fields[id]
		var hs: Array = (f.hexes as Array).filter(func(x): return int(t.shock.get(x, -1)) == int(id) and bv.board.exists(x))
		if hs.is_empty():
			continue
		var sum := Vector3.ZERO
		for h in hs:
			var c := bv.top_center(h) + Vector3(0, 0.06, 0)
			sum += c
			var corners := BWLook.hex_corners(c, BWLook.HEX_SIZE * 0.97)
			for n in BWHex.neighbors(h):
				if int(t.shock.get(n, -1)) == int(id):
					continue
				var mid := (c + bv.top_center(n) + Vector3(0, 0.06, 0)) * 0.5 if bv.board.exists(n) \
					else c + (BWLook.world(n) - BWLook.world(h)) * 0.5
				var pair := _nearest2(corners, mid)
				_edges.append(pair)
		var centre := sum / hs.size()
		var order := hs.duplicate()                   # the free hex nearest the field's middle
		order.sort_custom(func(x, y): return bv.top_center(x).distance_to(centre) < bv.top_center(y).distance_to(centre))
		var best: Vector2i = order[0]
		for h in order:
			if not (t.occupant.is_valid() and t.occupant.call(h) != null):
				best = h
				break
		var n_pips := int(f.ticks)
		for k in n_pips:
			var mi := MeshInstance3D.new()
			mi.mesh = _diamond_mesh()
			mi.material_override = material("pip")
			mi.position = bv.top_center(best) + Vector3((k - (n_pips - 1) * 0.5) * 0.5, 0.25, 0)
			mi.sorting_offset = 4.0
			add_child(mi)
			_pips.append(mi)


static func _nearest2(corners: PackedVector3Array, p: Vector3) -> Array:
	var idx: Array = range(corners.size())
	idx.sort_custom(func(a, b): return corners[a].distance_to(p) < corners[b].distance_to(p))
	return [corners[idx[0]], corners[idx[1]]]


static func _diamond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := BWLook.glow_color("thunder")
	for spec in [[0.24, INK], [0.17, glow], [0.07, Color.WHITE]]:
		var r: float = spec[0]
		var col: Color = spec[1]
		var pts := [Vector3(0, r, 0), Vector3(r * 0.7, 0, 0), Vector3(0, -r, 0), Vector3(-r * 0.7, 0, 0)]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for i in tri:
				st.set_color(col)
				st.add_vertex(pts[i] + Vector3(0, 0, -0.001 * (0.16 - r)))
	return st.commit()


## A fresh jagged ribbon along every outline edge: each edge kinked at two
## points, jittered sideways and up.
func _reroll() -> void:
	if _edges.is_empty():
		_shock_glow.mesh = null
		_shock_core.mesh = null
		return
	var sg := SurfaceTool.new()
	sg.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := SurfaceTool.new()
	sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in _edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var pts: Array = [a]
		for k in [1, 2]:
			var p := a.lerp(b, k / 3.0)
			pts.append(p + Vector3(randf_range(-0.09, 0.09), randf_range(0.0, 0.16), randf_range(-0.09, 0.09)))
		pts.append(b)
		for i in pts.size() - 1:
			_ribbon_seg(sg, pts[i], pts[i + 1], 0.07)
			_ribbon_seg(sc, pts[i], pts[i + 1], 0.022)
	_shock_glow.mesh = sg.commit()
	_shock_core.mesh = sc.commit()


func _ribbon_seg(st: SurfaceTool, p0: Vector3, p1: Vector3, w: float) -> void:
	var d := (p1 - p0).normalized()
	for off in [d.cross(Vector3.UP).normalized() * w, Vector3.UP * w]:
		for p in [p0 - off, p0 + off, p1 + off, p0 - off, p1 + off, p1 - off]:
			st.add_vertex(p)


func _process(delta: float) -> void:
	if _edges.is_empty():
		return
	_t += delta
	if _t >= _next:
		_next = _t + REROLL
		_reroll()
	var flick := 0.65 + 0.35 * absf(sin(_t * 23.0))
	(_shock_glow.material_override as StandardMaterial3D).albedo_color.a = 0.85 * flick

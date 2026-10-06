class_name BWRangeOverlay
extends MeshInstance3D
## Movement and attack radius display, ported from Temporal Sea V8
## (prologue_hill_combat_3d.gd _rebuild_overlay / _add_range_halo /
## path arrow, hex_terrain.gd add_flat_hex / add_edge_ribbon):
##   * a flat fill on every hex of a region,
##   * a vertical ribbon rising only from the region's OUTER edges, full
##     colour at the base fading to clear (the "range halo"),
##   * the path arrow: a flat ribbon through hex centres, last segment cut to
##     55 %, with a triangle head.
## Translated to black and white (D59): V8's blue/gold walk becomes a grey wash
## rimmed in the acting unit's ELEMENT colour; red/orange attack becomes ink;
## amber splash becomes the skill's element colour; the gold arrow becomes ink.

const TILE_INSET := 0.94          # V8 HEX*TILE_INSET
const FILL_LIFT := 0.03
const HALO_BASE := 0.04
const HALO_H := 0.30              # V8 used 0.22; taller reads better at our camera distance
const PATH_LIFT := 0.06
const PATH_HALF := 0.16           # ribbon half-width (V8)
const HEAD_BACK := 0.5
const HEAD_HALF := 0.34
const LAST_SEG := 0.55
## V8's EDGE_NEIGHBOR: edge e (corner e → e+1, corners at 60e−30°) faces this
## index of BWHex.neighbors() (E, NE, NW, W, SW, SE — same order as V8).
const EDGE_NEIGHBOR := [0, 5, 4, 3, 2, 1]

const MOVE_FILL := Color(0.55, 0.57, 0.63, 0.30)
const ATTACK_FILL := Color(0.0, 0.0, 0.0, 0.24)
const ATTACK_HALO := Color(0.0, 0.0, 0.0, 0.95)
const PATH_COL := Color(0.02, 0.02, 0.03, 0.92)

var board_view: BWBoardView


func _init(bv: BWBoardView = null) -> void:
	board_view = bv
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func clear() -> void:
	mesh = null


## Rebuild everything at once (V8 rebuilt its one overlay mesh per change).
##   move: hexes the unit can reach (their union is one region for the halo)
##   move_rim: the halo colour for the move region (the unit's element)
##   attack: hexes in attack radius; splash: hexes an aimed action will hit
##   path: hex chain for the arrow (start → hovered)
func display(move: Array, move_rim: Color, attack: Array = [], splash: Array = [],
		splash_col: Color = Color(0, 0, 0, 0), path: Array = []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var move_set := {}
	for h in move:
		move_set[h] = true
	var atk_set := {}
	for h in attack:
		atk_set[h] = true
	for h in move:
		_fill(st, h, MOVE_FILL)
		any = true
	for h in attack:
		_fill(st, h, ATTACK_FILL)
		any = true
	if splash_col.a > 0.0:
		for h in splash:
			_fill(st, h, Color(splash_col.r, splash_col.g, splash_col.b, 0.5))
			any = true
	if not move.is_empty():
		_halo(st, move_set, Color(move_rim.r, move_rim.g, move_rim.b, 1.0))
	if not attack.is_empty():
		_halo(st, atk_set, ATTACK_HALO)
	if path.size() >= 2:
		_arrow(st, path)
		any = true
	if not any:
		mesh = null
		return
	mesh = st.commit()


func _top(h: Vector2i) -> Vector3:
	return board_view.top_center(h)


func _fill(st: SurfaceTool, h: Vector2i, col: Color) -> void:
	var c := _top(h) + Vector3(0, FILL_LIFT, 0)
	var v := BWLook.hex_corners(c, BWLook.HEX_SIZE * TILE_INSET)
	for i in 6:
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(col)
		st.add_vertex(v[i])
		st.set_color(col)
		st.add_vertex(v[(i + 1) % 6])


## V8 _add_range_halo: a ribbon on every edge whose neighbour is outside the set.
func _halo(st: SurfaceTool, region: Dictionary, col: Color) -> void:
	var clear_col := Color(col.r, col.g, col.b, 0.0)
	for h in region:
		var nb := BWHex.neighbors(h)
		var c := _top(h)
		var corners := BWLook.hex_corners(c, BWLook.HEX_SIZE * TILE_INSET)
		for e in 6:
			if region.has(nb[EDGE_NEIGHBOR[e]]):
				continue
			var a := corners[e] + Vector3(0, HALO_BASE, 0)
			var b := corners[(e + 1) % 6] + Vector3(0, HALO_BASE, 0)
			var a2 := a + Vector3(0, HALO_H, 0)
			var b2 := b + Vector3(0, HALO_H, 0)
			for p in [[a, col], [b, col], [b2, clear_col], [a, col], [b2, clear_col], [a2, clear_col]]:
				st.set_color(p[1])
				st.add_vertex(p[0])


## V8 path arrow: flat ribbon between hex centres, last segment shortened,
## triangle head with its tip on the destination centre.
func _arrow(st: SurfaceTool, path: Array) -> void:
	var pts: Array = []
	for h in path:
		pts.append(_top(h) + Vector3(0, PATH_LIFT, 0))
	var n := pts.size()
	for i in n - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if i == n - 2:
			b = a.lerp(b, LAST_SEG)
		var d := b - a
		var side := Vector3(-d.z, 0, d.x).normalized() * PATH_HALF
		_quad(st, a - side, a + side, b + side, b - side, PATH_COL)
	var tip: Vector3 = pts[n - 1]
	var dir: Vector3 = (tip - (pts[n - 2] as Vector3))
	dir.y = 0
	dir = dir.normalized()
	var back := tip - dir * HEAD_BACK
	var side2 := Vector3(-dir.z, 0, dir.x) * HEAD_HALF
	for p in [tip, back + side2, back - side2]:
		st.set_color(PATH_COL)
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)

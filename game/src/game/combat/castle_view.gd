class_name BWCastleView
extends Node3D
## D340: the castle maps' look and the castle modes on the combat screen
## (BWCastle, BWCastleDefend, BWCastleStorm). Inert off a castle map.
##   dressing   the wall walk (every standable hex at elevation 2+ outside the
##              courtyard) gets ink masonry courses on its outer faces and white
##              merlons along its outer edge; the keep's rock block is capped
##              by a white crenellated tower with a black doorway; iron
##              braziers on the brazier hexes (their static fire is the board's
##              own FX); open arches on Storm's back doors.
##   objects    make_view(u): the gate and the throne (BWCastleObjectView).
##   events     castle_breach (Storm's phase change): a banner, the feed, a
##              beat on the throne; the gate's fall in Defend ends the fight
##              (the end banner says so).
## The HUD plate (gate HP, waves, rounds) is BWModeView's, fed by the modes'
## hud_lines.

const STONE := Color(0.93, 0.93, 0.93)
const INK := Color(0.03, 0.03, 0.035)

var screen: BWCombatScreen
var battle: BWBattle
var board: BWBoard
var _courtyard := {}
var breach_shown := false          # the review tool waits on it (tools/castle_shots.gd)


## The view for a castle object (the gate, the throne), else null.
static func make_view(u: BWUnit) -> BWUnitView:
	if u is BWObjective and (u as BWObjective).tag in ["gate", "throne"]:
		return BWCastleObjectView.new()
	return null


func setup(s: BWCombatScreen) -> void:
	screen = s
	battle = s.battle
	board = battle.board
	if not BWCastle.active(battle):
		return
	_courtyard = courtyard(board)
	_dress_walls()
	_keep_tower()
	for h in BWCastle.hexes(battle, "braziers"):
		_brazier(h)
	for h in board.cells():                     # Storm's back doors: gaps in the north wall
		if board.is_passable(h) and board.elevation(h) == 0 and h.y == 0 and _wall_neighbour(h):
			_arch(h)


## Hexes inside the walls at ground level (flood from the keep door / the
## throne over elevation <= 1, not crossing the gate).
static func courtyard(bd: BWBoard) -> Dictionary:
	var seedh: Array = []
	for key in ["keep", "throne"]:
		var v: Variant = bd.objective.get(key, [])
		if v is Array and not (v as Array).is_empty():
			if v[0] is Array:
				for p in v:
					seedh.append(Vector2i(int(p[0]), int(p[1])))
			else:
				seedh.append(Vector2i(int(v[0]), int(v[1])))
	var g: Array = bd.objective.get("gate", [])
	var gate := Vector2i(int(g[0]), int(g[1])) if g.size() == 2 else Vector2i(-99, -99)
	var out := {}
	var todo: Array = seedh.duplicate()
	while not todo.is_empty():
		var h: Vector2i = todo.pop_back()
		if out.has(h) or not bd.exists(h) or h == gate:
			continue
		if bd.terrain(h) != BWBoard.JAGGED and bd.elevation(h) > 1:
			continue
		out[h] = true
		for n in bd.neighbors(h):
			if not out.has(n):
				todo.append(n)
	return out


func _wall_neighbour(h: Vector2i) -> bool:
	for n in board.neighbors(h):
		if board.is_passable(n) and board.elevation(n) >= 3:
			return true
	return false


## The wall walk: masonry courses and merlons on the faces that look out.
func _dress_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var merlons: Array = []
	for h in board.cells():
		if not board.is_passable(h) or board.elevation(h) < 2:
			continue
		var e := board.elevation(h)
		var top := screen.board_view.top_center(h)
		var corners := BWLook.hex_corners(top, BWLook.HEX_SIZE)
		for i in 6:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 6]
			var mid := (a + b) * 0.5
			var n := _neighbour_across(h, mid - top)
			var ne := board.elevation(n) if board.exists(n) and board.terrain(n) != BWBoard.JAGGED else -1
			if board.exists(n) and board.terrain(n) == BWBoard.JAGGED and board.elevation(n) >= e:
				continue
			if ne >= e - 1:
				continue                               # level with the walk (or a step): no parapet
			var out := (mid - top)
			out.y = 0
			out = out.normalized()
			var low := maxf(BWBoardView.FLOOR_Y, (ne + 1) * BWLook.TILE_HEIGHT if ne >= 0 else BWBoardView.FLOOR_Y)
			_masonry(st, a, b, out, low, top.y, h, i)
			if not _courtyard.has(n):
				merlons.append([a, b, out])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "masonry"
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var ms := SurfaceTool.new()
	ms.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in merlons:
		var a: Vector3 = m[0]
		var b: Vector3 = m[1]
		var out: Vector3 = m[2]
		for t in [0.25, 0.75]:
			var p := a.lerp(b, t) - out * 0.12
			_block(ms, p + Vector3(0, 0.15, 0), Vector3(0.36, 0.3, 0.2), out, STONE)
	ms.generate_normals()
	var mm := MeshInstance3D.new()
	mm.name = "merlons"
	mm.mesh = ms.commit()
	var mat := BWLook.flat().duplicate() as ShaderMaterial
	mat.next_pass = BWLook.outline(0.02, Color.BLACK)
	mm.material_override = mat
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)


## The neighbour of h across the edge whose midpoint is at `dir` from its centre.
func _neighbour_across(h: Vector2i, dir: Vector3) -> Vector2i:
	var best := h
	var best_d := -INF
	var c := BWLook.world(h)
	for n in BWHex.neighbors(h):
		var d := BWLook.world(n) - c
		var k := Vector2(d.x, d.z).normalized().dot(Vector2(dir.x, dir.z).normalized())
		if k > best_d:
			best_d = k
			best = n
	return best


## Ink courses on one outer face (a..b along the top, down to `low`): two or
## three horizontal lines and staggered joints, set just proud of the face.
func _masonry(st: SurfaceTool, a: Vector3, b: Vector3, out: Vector3, low: float, top: float, h: Vector2i, side: int) -> void:
	var lift := out * 0.012
	var course := BWLook.TILE_HEIGHT
	var y := top - course
	var row := 0
	while y > low + 0.05:
		_quad(st, Vector3(a.x, y - 0.012, a.z) + lift, Vector3(b.x, y - 0.012, b.z) + lift,
			Vector3(b.x, y + 0.012, b.z) + lift, Vector3(a.x, y + 0.012, a.z) + lift, INK)
		var off := 0.25 if (row + side + h.x) % 2 == 0 else 0.6
		var p := a.lerp(b, off)
		var y1 := minf(top, y + course)
		_quad(st, Vector3(p.x - 0.012 * (b - a).normalized().x, y, p.z - 0.012 * (b - a).normalized().z) + lift,
			Vector3(p.x + 0.012 * (b - a).normalized().x, y, p.z + 0.012 * (b - a).normalized().z) + lift,
			Vector3(p.x + 0.012 * (b - a).normalized().x, y1, p.z + 0.012 * (b - a).normalized().z) + lift,
			Vector3(p.x - 0.012 * (b - a).normalized().x, y1, p.z - 0.012 * (b - a).normalized().z) + lift, INK)
		y -= course
		row += 1


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)
	for p in [a, c, b, a, d, c]:                     # both faces (no culling surprises)
		st.set_color(col)
		st.add_vertex(p)


## An axis box turned to face `out` (its depth along out).
func _block(st: SurfaceTool, c: Vector3, size: Vector3, out: Vector3, col: Color) -> void:
	var fwd := out.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var hx := right * size.x * 0.5
	var hy := Vector3.UP * size.y * 0.5
	var hz := fwd * size.z * 0.5
	var v := [c - hx - hy - hz, c + hx - hy - hz, c + hx + hy - hz, c - hx + hy - hz,
		c - hx - hy + hz, c + hx - hy + hz, c + hx + hy + hz, c - hx + hy + hz]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in faces:
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(v[f[idx]])


## The keep: the tall rock block (jagged, elevation 5+) capped by a white tower.
func _keep_tower() -> void:
	var block: Array = board.cells().filter(func(h): return board.terrain(h) == BWBoard.JAGGED and board.elevation(h) >= 5)
	if block.is_empty():
		return
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	var top_e := 0
	for h in block:
		var w := BWLook.world(h)
		lo = Vector3(minf(lo.x, w.x - 0.8), 0, minf(lo.z, w.z - 0.9))
		hi = Vector3(maxf(hi.x, w.x + 0.8), 0, maxf(hi.z, w.z + 0.9))
		top_e = maxi(top_e, board.elevation(h))
	var height := top_e * BWLook.TILE_HEIGHT + 0.7
	var c := (lo + hi) * 0.5
	var size := Vector3(hi.x - lo.x, height - BWBoardView.FLOOR_Y, hi.z - lo.z)
	var tower := Node3D.new()
	tower.name = "keep_tower"
	add_child(tower)
	_mesh_box(tower, Vector3(c.x, BWBoardView.FLOOR_Y + size.y * 0.5, c.z), size, STONE, 0.03)
	# crenellations round the top
	var n := int(size.x / 0.55)
	for k in n:
		var x := lo.x + 0.3 + (size.x - 0.6) * k / maxf(1.0, n - 1)
		for z in [lo.z + 0.12, hi.z - 0.12]:
			_mesh_box(tower, Vector3(x, height + 0.18, z), Vector3(0.3, 0.36, 0.24), STONE, 0.02)
	var m := int(size.z / 0.55)
	for k in m:
		var z := lo.z + 0.3 + (size.z - 0.6) * k / maxf(1.0, m - 1)
		for x in [lo.x + 0.12, hi.x - 0.12]:
			_mesh_box(tower, Vector3(x, height + 0.18, z), Vector3(0.24, 0.36, 0.3), STONE, 0.02)
	# ink courses on the long faces, a slit window or two
	for k in int(height / 0.7):
		var y := 0.35 + 0.7 * k
		for z in [lo.z - 0.005, hi.z + 0.005]:
			_mesh_box(tower, Vector3(c.x, y, z), Vector3(size.x, 0.03, 0.01), INK, 0.0)
	# the doorway on the face toward the keep door (Defend); in Storm the throne
	# stands there, so the face stays white behind its black seat
	var doors := BWCastle.hexes(battle, "keep")
	var face_z := hi.z + 0.01
	if not doors.is_empty():
		var door_at: Vector2i = doors[0]
		face_z = lo.z - 0.01 if BWLook.world(door_at).z < c.z else hi.z + 0.01
		_mesh_box(tower, Vector3(BWLook.world(door_at).x, 0.95, face_z), Vector3(0.75, 1.3, 0.04), INK, 0.0)
	else:
		var th: Array = board.objective.get("throne", [9, 2])
		face_z = lo.z - 0.01 if BWLook.world(Vector2i(int(th[0]), int(th[1]))).z < c.z else hi.z + 0.01
	for y in [height * 0.62, height * 0.82]:
		_mesh_box(tower, Vector3(c.x - size.x * 0.25, y, face_z), Vector3(0.1, 0.4, 0.04), INK, 0.0)
		_mesh_box(tower, Vector3(c.x + size.x * 0.25, y, face_z), Vector3(0.1, 0.4, 0.04), INK, 0.0)


func _mesh_box(parent: Node3D, at: Vector3, size: Vector3, col: Color, outline: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	var m := BWLook.flat().duplicate() as ShaderMaterial
	if outline > 0.0:
		m.next_pass = BWLook.outline(outline, Color(0.92, 0.92, 0.95) if col.get_luminance() < 0.5 else Color.BLACK)
	mi.material_override = m
	mi.set_instance_shader_parameter("tint", col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## An iron brazier: a bowl on three legs (the hex's static fire burns in it).
func _brazier(h: Vector2i) -> void:
	var n := Node3D.new()
	n.name = "brazier_%d_%d" % [h.x, h.y]
	n.position = screen.board_view.top_center(h)
	add_child(n)
	for k in 3:
		var a := TAU * k / 3.0
		var leg := _mesh_box(n, Vector3(cos(a) * 0.2, 0.25, sin(a) * 0.2), Vector3(0.05, 0.5, 0.05), INK, 0.012)
		leg.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.16
	cm.height = 0.2
	cm.radial_segments = 10
	bowl.mesh = cm
	bowl.position = Vector3(0, 0.56, 0)
	var m := BWLook.flat().duplicate() as ShaderMaterial
	m.next_pass = BWLook.outline(0.018, Color(0.92, 0.92, 0.95))
	bowl.material_override = m
	bowl.set_instance_shader_parameter("tint", INK)
	n.add_child(bowl)


## An open arch on a back door (Storm): white jambs and lintel, a black void.
func _arch(h: Vector2i) -> void:
	var n := Node3D.new()
	n.name = "arch_%d_%d" % [h.x, h.y]
	n.position = screen.board_view.top_center(h)
	add_child(n)
	_mesh_box(n, Vector3(-0.7, 0.75, 0), Vector3(0.26, 1.5, 0.5), STONE, 0.02)
	_mesh_box(n, Vector3(0.7, 0.75, 0), Vector3(0.26, 1.5, 0.5), STONE, 0.02)
	_mesh_box(n, Vector3(0, 1.6, 0), Vector3(1.7, 0.3, 0.54), STONE, 0.02)
	_mesh_box(n, Vector3(0, 0.72, -0.26), Vector3(1.14, 1.44, 0.04), INK, 0.0)


# ---------------------------------------------------------------- events

## The rules for the feed, after BWModeView's banner.
static func intro_lines(b: BWBattle) -> Array:
	match BWCastle.mode(b):
		"defend":
			return ["[b]Hold the iron gate[/b] for %d rounds, or down every raider once the waves are done. If the gate breaks, the keep falls." % BWCastleDefend.ROUNDS,
				"Raiders come in waves (rung a round ahead) and go for the gate. The walls are high ground: +%d%% damage per level above the target (up to +%d%%). The moat is water: thunder electrifies it." % [int(BWCastle.HEIGHT_PCT), int(BWCastle.HEIGHT_PCT * BWCastle.HEIGHT_MAX)]]
		"storm":
			return ["[b]Break the wooden gate[/b] (fire burns it x%.1f; thunder on a glazed gate shatters it x%.1f), then [b]break the throne[/b] or down the Warden." % [BWCastle.WOOD_FIRE, BWCastle.SHATTER_GATE],
				"Guards hold the walls with the high ground; more come through the back doors every %d rounds until the gate falls. The moat is water: thunder electrifies it." % BWCastleStorm.REINFORCE_EVERY]
	return []


static func end_text(b: BWBattle, winner: String) -> String:
	match BWCastle.mode(b):
		"defend":
			if winner == "player":
				return "Victory: the keep holds" if b.objective_state.get("held", false) else "Victory: the raiders are broken"
			var g := BWCastle.gate(b)
			if g != null and not g.alive():
				return "Defeat: the gate is broken"
		"storm":
			if winner == "player":
				var t := BWCastleStorm.throne(b)
				return "Victory: the throne is broken" if t != null and not t.alive() else "Victory: the Warden falls"
	return ""


func on_event(e: Dictionary) -> void:
	match str(e.type):
		"castle_breach":
			breach_shown = true
			screen.ui.banner("The gate falls  ·  break the throne", 2.6)
			screen.ui.feed("[b]The gate falls.[/b] The throne is open: break it, or down the Warden.%s" % (
				" The reinforcements stop." if int(e.get("cut", 0)) > 0 else ""))
			var t := battle._unit(str(e.get("throne", "")))
			if t != null and screen.readability:
				await screen.readability.beat(t.pos)

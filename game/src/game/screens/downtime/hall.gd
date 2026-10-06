class_name BWHall
extends Node3D
## The downtime room (brief: "an empty marble school hall"; D83). Built in
## code like the boards, in the board's graphic language: flat shading, ink
## contours, a controlled grey palette, element colour reserved for the units.
##
##   var hall := BWHall.new(); add_child(hall)       # builds on _ready
##   var i := hall.add_spot(Vector3(x, 0, z))         # a pool + a visible cone
##   hall.set_spot_level(i, 1.0)                      # 0..1, eased
##   hall.set_time(0.35)                              # 0 dawn .. 1 dusk: windows, shafts
##   hall.follow(camera)                              # every frame: the floor's reflection
##
## Pieces: a polished marble floor (marble_floor.gdshader: slabs, ink seams,
## veins, the light pools painted in, and a planar reflection from a mirrored
## camera in a half-size SubViewport sharing this world); a back wall with a
## dark wainscot and a rail; four tall arched windows; a crest banner (the
## split circle: half white, half black); white fluted columns carrying an
## entablature; dark rafters above. Spotlights are fake volumetric cones
## (light_cone.gdshader) over pools painted into the floor.

const FLOOR_X := 16.0
const FLOOR_Z0 := -10.0
const FLOOR_Z1 := 16.0
const WALL_Z := -10.0
const WALL_H := 13.0
const COL_Z := -8.6
const COL_H := 7.6
const COLUMNS := [-12.5, -7.5, -2.5, 2.5, 7.5, 12.5]
const WINDOWS := [-10.0, -5.0, 5.0, 10.0]
const WIN_W := 2.1
const WIN_Y0 := 2.5
const WIN_Y1 := 6.7                 # top of the arch
const SPOT_H := 7.2                 # the lamps hang this high
const SPOT_R := 1.05
const REFLECT_LAYER := 2            # the floor: hidden from the mirror camera
## Linear greys (the screen shows them brighter: 0.10 reads ~35%).
const WALL := 0.034
const WAINSCOT := 0.008
const MARBLE_WHITE := 0.62
const MARBLE_SHADE := 0.27
const RAFTER := 0.018

var time_of_day := 0.35
var _floor_mat: ShaderMaterial
var _spots: Array = []              # [{ at: Vector2, r, level, target, cone, lamp }]
var _glass: Array = []              # MeshInstance3D per window
var _shafts: MeshInstance3D
var _shaft_mesh: ImmediateMesh
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _light := Vector3(-0.55, 0.55, 0.62).normalized()      # the painted light on columns


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	_build_mirror()
	_build_floor()
	_build_wall()
	for x in WINDOWS:
		_build_window(x)
	_build_banner(0.0)
	for x in COLUMNS:
		_build_column(Vector3(x, 0, COL_Z))
	_build_entablature()
	_build_rafters()
	_build_shafts()
	set_time(time_of_day)


func _process(delta: float) -> void:
	var dirty := false
	for s in _spots:
		if absf(s.level - s.target) > 0.001:
			s.level = move_toward(s.level, s.target, delta * 3.0)
			(s.cone as GeometryInstance3D).set_instance_shader_parameter("strength", 0.35 + 0.65 * s.level)
			dirty = true
	if dirty:
		_push_spots()


# ---------------------------------------------------------------- API

## A spotlight standing at `at` (floor point): returns its index.
func add_spot(at: Vector3, level: float = 1.0) -> int:
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.10
	cm.bottom_radius = SPOT_R * 1.02
	cm.height = SPOT_H
	cm.radial_segments = 40
	cm.rings = 6
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/light_cone.gdshader")
	m.set_shader_parameter("height", SPOT_H)
	m.set_shader_parameter("top", SPOT_H * 0.5)
	m.set_shader_parameter("intensity", 0.20)
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(at.x, SPOT_H * 0.5, at.z)
	cone.set_instance_shader_parameter("strength", 0.35 + 0.65 * level)
	add_child(cone)
	# the lamp: a small black can with a white lens
	var lamp := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.16
	lm.bottom_radius = 0.22
	lm.height = 0.34
	lamp.mesh = lm
	lamp.material_override = BWLook.flat()
	lamp.set_instance_shader_parameter("tint", Color(0.02, 0.02, 0.02))
	lamp.position = Vector3(at.x, SPOT_H + 0.12, at.z)
	add_child(lamp)
	var lens := MeshInstance3D.new()
	var le := CylinderMesh.new()
	le.top_radius = 0.17
	le.bottom_radius = 0.17
	le.height = 0.02
	lens.mesh = le
	lens.material_override = BWLook.flat()
	lens.position = Vector3(0, -0.17, 0)
	lamp.add_child(lens)
	_spots.append({ "at": Vector2(at.x, at.z), "r": SPOT_R, "level": level, "target": level, "cone": cone, "lamp": lamp })
	_push_spots()
	return _spots.size() - 1


func spot_count() -> int:
	return _spots.size()


## Brightness of a spot, 0..1 (eased over ~0.3 s).
func set_spot_level(i: int, level: float, instant: bool = false) -> void:
	if i < 0 or i >= _spots.size():
		return
	_spots[i].target = clampf(level, 0.0, 1.0)
	if instant:
		_spots[i].level = _spots[i].target
		(_spots[i].cone as GeometryInstance3D).set_instance_shader_parameter("strength", 0.35 + 0.65 * _spots[i].level)
		_push_spots()


## Time of day across the windows, 0 = dawn, 0.5 = noon, 1 = dusk.
## Greyscale only: the glass brightens and darkens, the shafts swing across
## the floor (long and low from the left at dawn, short at noon, long from
## the right at dusk).
func set_time(f: float) -> void:
	time_of_day = clampf(f, 0.0, 1.0)
	var day := sin(PI * time_of_day)
	var g := lerpf(0.035, 0.62, pow(day, 0.8))
	for gl in _glass:
		(gl as GeometryInstance3D).set_instance_shader_parameter("tint", Color(g, g, g * 1.0))
	var sy := lerpf(0.30, 1.05, day)                # sun elevation (rise per unit of z)
	var sx := lerpf(1.05, -1.05, time_of_day)       # sideways per unit of z
	var foot_dz := WIN_Y0 / sy
	var head_dz := WIN_Y1 / sy
	var axis := Vector2(sx * (head_dz - foot_dz), head_dz - foot_dz)
	var patches := PackedVector4Array()
	for x in WINDOWS:
		patches.append(Vector4(x + sx * foot_dz, WALL_Z + foot_dz, 1.0, 0.0))
	var strength := 0.05 + 0.30 * pow(day, 0.6)
	if _floor_mat:
		_floor_mat.set_shader_parameter("patches", patches)
		_floor_mat.set_shader_parameter("patch_count", patches.size())
		_floor_mat.set_shader_parameter("patch_dir", Vector4(axis.x, axis.y, WIN_W * 0.92, strength))
		_floor_mat.set_shader_parameter("ambient", lerpf(0.045, 0.075, day))
	_rebuild_shafts(Vector3(sx, -sy, 1.0), 0.5 + 0.8 * day)


## Keep the reflection's mirrored camera in step with `cam`. Call every frame
## the camera moves (BWDowntimeScreen does).
func follow(cam: Camera3D) -> void:
	if _mirror_cam == null or cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(64, int(vs.x * 0.5)), maxi(64, int(vs.y * 0.5)))
	if _mirror_vp.size != want:
		_mirror_vp.size = want
	_mirror_cam.fov = cam.fov
	_mirror_cam.near = cam.near
	_mirror_cam.far = cam.far
	var p := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var mp := Vector3(p.x, -p.y, p.z)
	var mf := Vector3(fwd.x, -fwd.y, fwd.z)
	_mirror_cam.global_position = mp
	if absf(mf.normalized().dot(Vector3.UP)) < 0.999:
		_mirror_cam.look_at(mp + mf, Vector3.UP)


# ---------------------------------------------------------------- build

func _build_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(800, 450)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	_mirror_vp.transparent_bg = false
	add_child(_mirror_vp)          # no own world: it renders this hall
	_mirror_cam = Camera3D.new()
	_mirror_cam.cull_mask = 0xFFFFF & ~REFLECT_LAYER
	_mirror_vp.add_child(_mirror_cam)
	_mirror_cam.current = true


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(FLOOR_X * 2.0, FLOOR_Z1 - FLOOR_Z0)
	mi.mesh = pm
	mi.position = Vector3(0, 0, (FLOOR_Z0 + FLOOR_Z1) * 0.5)
	mi.layers = REFLECT_LAYER
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://shaders/marble_floor.gdshader")
	_floor_mat.set_shader_parameter("reflection", _mirror_vp.get_texture())
	mi.material_override = _floor_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_wall() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := WALL_Z
	var x0 := -FLOOR_X - 4.0
	var x1 := FLOOR_X + 4.0
	# wainscot (dark), the rail (light), the wall fading up into the dark
	_rect(st, Vector3(x0, 0, z), Vector3(x1, 1.25, z), Color(WAINSCOT, WAINSCOT, WAINSCOT), Color(WAINSCOT, WAINSCOT, WAINSCOT))
	_rect(st, Vector3(x0, 1.25, z + 0.01), Vector3(x1, 1.36, z + 0.01), Color(0.55, 0.55, 0.55), Color(0.55, 0.55, 0.55))
	_rect(st, Vector3(x0, 1.36, z), Vector3(x1, 7.0, z), Color(WALL, WALL, WALL), Color(WALL * 0.8, WALL * 0.8, WALL * 0.8))
	_rect(st, Vector3(x0, 7.0, z), Vector3(x1, WALL_H, z), Color(WALL * 0.8, WALL * 0.8, WALL * 0.8), Color(0.004, 0.004, 0.004))
	# skirting: an ink line where the floor meets the wall
	_rect(st, Vector3(x0, 0, z + 0.02), Vector3(x1, 0.14, z + 0.02), Color(0, 0, 0), Color(0, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	add_child(mi)


## A wall rectangle from corner a (low left) to b (high right), colour bottom → top.
func _rect(st: SurfaceTool, a: Vector3, b: Vector3, c0: Color, c1: Color) -> void:
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var c := [c0, c0, c1, c1]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(c[i])
		st.add_vertex(p[i])


## An arched outline (a rectangle with a half-circle top) as a fan.
func _arch(st: SurfaceTool, cx: float, y0: float, y1: float, w: float, z: float, col: Color) -> void:
	var r := w * 0.5
	var spring := y1 - r
	var pts: Array = [Vector3(cx - r, y0, z), Vector3(cx + r, y0, z)]
	for i in range(0, 21):
		var a := PI * float(i) / 20.0
		pts.append(Vector3(cx + cos(a) * r, spring + sin(a) * r, z))
	var c := Vector3(cx, (y0 + spring) * 0.5, z)
	for i in pts.size():
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % pts.size()]
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(col)
		st.add_vertex(p1)
		st.set_color(col)
		st.add_vertex(p0)


func _build_window(x: float) -> void:
	var z := WALL_Z + 0.02
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arch(frame, x, WIN_Y0 - 0.14, WIN_Y1 + 0.14, WIN_W + 0.28, z, Color(0, 0, 0))
	# the sill: a pale ledge
	_rect(frame, Vector3(x - WIN_W * 0.62, WIN_Y0 - 0.34, z + 0.02), Vector3(x + WIN_W * 0.62, WIN_Y0 - 0.14, z + 0.02), Color(0.5, 0.5, 0.5), Color(0.62, 0.62, 0.62))
	var fm := MeshInstance3D.new()
	fm.mesh = frame.commit()
	fm.material_override = BWLook.flat()
	fm.sorting_offset = 1.0           # the flat material sorts as transparent: draw over the wall
	add_child(fm)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arch(glass, x, WIN_Y0, WIN_Y1, WIN_W, z + 0.01, Color(1, 1, 1))
	var gm := MeshInstance3D.new()
	gm.mesh = glass.commit()
	gm.material_override = BWLook.flat()
	gm.sorting_offset = 2.0
	add_child(gm)
	_glass.append(gm)
	# mullions and transoms: ink bars over the glass
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := Color(0, 0, 0)
	var zb := z + 0.03
	_rect(bars, Vector3(x - 0.05, WIN_Y0, zb), Vector3(x + 0.05, WIN_Y1 - 0.02, zb), k, k)
	for yy in [WIN_Y0 + 1.35, WIN_Y0 + 2.75, WIN_Y1 - WIN_W * 0.5]:
		_rect(bars, Vector3(x - WIN_W * 0.5, yy - 0.045, zb), Vector3(x + WIN_W * 0.5, yy + 0.045, zb), k, k)
	var bm := MeshInstance3D.new()
	bm.mesh = bars.commit()
	bm.material_override = BWLook.flat()
	bm.sorting_offset = 3.0
	add_child(bm)


## The school crest on a long banner: a black field with a white border and a
## swallowtail, the split circle (half white, half black) inside a white ring.
func _build_banner(x: float) -> void:
	var z := WALL_Z + 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 2.1
	var top := COL_H - 0.35
	var bot := 2.7
	var white := Color(0.82, 0.82, 0.82)
	var field := Color(0.004, 0.004, 0.004)
	_banner_shape(st, x, w, top, bot, z, white)
	_banner_shape(st, x, w - 0.24, top - 0.12, bot + 0.16, z + 0.01, field)
	_banner_shape(st, x, w - 0.38, top - 0.19, bot + 0.27, z + 0.02, Color(0.6, 0.6, 0.6))   # a thin inner rule (the next shape covers its middle)
	_banner_shape(st, x, w - 0.46, top - 0.23, bot + 0.33, z + 0.03, field)
	# the crest
	var c := Vector3(x, 5.75, z + 0.04)
	var r := 0.6
	_disc(st, c, r + 0.10, white, 0.0, TAU)
	_disc(st, c + Vector3(0, 0, 0.01), r + 0.03, field, 0.0, TAU)
	_disc(st, c + Vector3(0, 0, 0.02), r - 0.04, white, PI * 0.5, PI * 1.5)     # left half white
	# the bar between the halves
	_rect(st, Vector3(x - 0.035, c.y - r - 0.22, z + 0.07), Vector3(x + 0.035, c.y + r + 0.22, z + 0.07), white, white)
	# three short rules under the crest (the school's motto, unreadable at range)
	for i in 3:
		var yy := 4.3 - i * 0.22
		var hw := 0.5 - i * 0.12
		_rect(st, Vector3(x - hw, yy, z + 0.05), Vector3(x + hw, yy + 0.06, z + 0.05), Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	add_child(mi)
	# the pole it hangs from
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = w + 0.7
	pole.mesh = pm
	pole.rotation_degrees.z = 90.0
	pole.position = Vector3(x, top + 0.05, z + 0.1)
	pole.material_override = BWLook.flat()
	pole.set_instance_shader_parameter("tint", Color(0.55, 0.55, 0.55))
	add_child(pole)


func _banner_shape(st: SurfaceTool, x: float, w: float, top: float, bot: float, z: float, col: Color) -> void:
	var notch := 0.55
	var pts := [Vector3(x - w * 0.5, top, z), Vector3(x + w * 0.5, top, z), Vector3(x + w * 0.5, bot, z),
		Vector3(x, bot + notch, z), Vector3(x - w * 0.5, bot, z)]
	var c := Vector3(x, (top + bot) * 0.5, z)
	for i in pts.size():
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(col)
		st.add_vertex(pts[i])
		st.set_color(col)
		st.add_vertex(pts[(i + 1) % pts.size()])


func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color, a0: float, a1: float) -> void:
	var n := 40
	for i in n:
		var t0 := lerpf(a0, a1, float(i) / n)
		var t1 := lerpf(a0, a1, float(i + 1) / n)
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(col)
		st.add_vertex(c + Vector3(cos(t1), sin(t1), 0) * r)
		st.set_color(col)
		st.add_vertex(c + Vector3(cos(t0), sin(t0), 0) * r)


## A fluted white column: a lathe with faceted (flat per face) two-tone
## shading from a painted light, a plinth and a capital, and an ink hull.
func _build_column(at: Vector3) -> void:
	var h := COL_H
	var prof := [[0.66, 0.0], [0.66, 0.34], [0.56, 0.42], [0.52, 0.62], [0.46, h - 0.95], [0.50, h - 0.78],
		[0.60, h - 0.62], [0.72, h - 0.5], [0.72, h - 0.5], [0.72, h]]
	var square := { 0: true, 1: true, 8: true, 9: true }
	var col := MeshInstance3D.new()
	col.mesh = _lathe(prof, 22, true, square)
	col.material_override = BWLook.flat()
	col.position = at
	add_child(col)
	var ol := MeshInstance3D.new()
	ol.mesh = _lathe(prof, 22, false, square)
	ol.material_override = BWLook.outline(0.035)
	col.add_child(ol)


## Surface of revolution. `faceted`: per-face colours from the painted light
## (lit / shade, crisp); otherwise smooth indexed normals for the outline hull.
## Profile rings listed in `square` are drawn as four-sided (plinth, abacus).
func _lathe(prof: Array, seg: int, faceted: bool, square: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := func(k: int, i: int) -> Vector3:
		var r: float = prof[k][0]
		var y: float = prof[k][1]
		var a := TAU * float(i) / seg + PI / seg
		if square.has(k):
			# a square block: push the circle out to a square of half-side r
			var d := Vector2(cos(a), sin(a))
			var m := maxf(absf(d.x), absf(d.y))
			return Vector3(d.x / m * r * 0.95, y, d.y / m * r * 0.95)
		return Vector3(cos(a) * r, y, sin(a) * r)
	for k in prof.size() - 1:
		for i in seg:
			var a: Vector3 = ring.call(k, i)
			var b: Vector3 = ring.call(k, (i + 1) % seg)
			var c: Vector3 = ring.call(k + 1, (i + 1) % seg)
			var d: Vector3 = ring.call(k + 1, i)
			if a.distance_to(d) < 0.0001 and b.distance_to(c) < 0.0001:
				continue
			var n := (d - a).cross(b - a).normalized()
			if n.length() < 0.5:
				n = Vector3(a.x, 0, a.z).normalized()
			var lit := n.dot(_light)
			var v := MARBLE_WHITE if lit > 0.05 else MARBLE_SHADE
			if not faceted:
				v = 1.0
			# every other flute a hair darker: the fluting reads up close
			if faceted and i % 2 == 1 and not square.has(k) and k >= 3 and k <= 4:
				v *= 0.88
			var cc := Color(v, v, v)
			for p in [a, c, d, a, b, c]:
				st.set_color(cc)
				if not faceted:
					st.set_normal(Vector3(p.x, 0, p.z).normalized())
				st.add_vertex(p)
	# caps (top, bottom)
	if faceted:
		st.generate_normals()
	else:
		st.index()
	return st.commit()


## The beam the columns carry, across the hall.
func _build_entablature() -> void:
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(FLOOR_X * 2.0 + 4.0, 0.9, 1.6)
	beam.mesh = bm
	beam.material_override = BWLook.flat()
	beam.set_instance_shader_parameter("tint", Color(0.55, 0.55, 0.55))
	beam.position = Vector3(0, COL_H + 0.45, COL_Z)
	add_child(beam)
	var ol := MeshInstance3D.new()
	ol.mesh = bm
	ol.material_override = BWLook.outline(0.035)
	beam.add_child(ol)
	# a lit band along the beam's face
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(FLOOR_X * 2.0 + 4.0, 0.16, 0.02)
	band.mesh = bb
	band.material_override = BWLook.flat()
	band.set_instance_shader_parameter("tint", Color(0.85, 0.85, 0.85))
	band.position = Vector3(0, COL_H + 0.12, COL_Z + 0.81)
	add_child(band)


## Dark rafters: beams running the hall's length overhead, crossed by ties.
func _build_rafters() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := COL_H + 1.3
	var k := Color(RAFTER, RAFTER, RAFTER)
	var k2 := Color(RAFTER * 2.2, RAFTER * 2.2, RAFTER * 2.2)
	var xi := -15.0
	while xi <= 15.01:
		_box(st, Vector3(xi, y, (WALL_Z + FLOOR_Z1) * 0.5), Vector3(0.32, 0.5, FLOOR_Z1 - WALL_Z), k, k2)
		xi += 3.0
	var zi := WALL_Z + 2.0
	while zi < FLOOR_Z1:
		_box(st, Vector3(0, y - 0.45, zi), Vector3(FLOOR_X * 2.0 + 4.0, 0.36, 0.36), k, k2)
		zi += 4.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.flat()
	add_child(mi)


func _box(st: SurfaceTool, c: Vector3, s: Vector3, side: Color, bottom: Color) -> void:
	var h := s * 0.5
	var v := func(x: float, y: float, z: float) -> Vector3: return c + Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1], side],       # front
		[[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1], side],   # back
		[[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1], bottom], # underside
		[[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1], side],
		[[1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1], side],
	]
	for f in faces:
		var p: Array = []
		for j in 4:
			p.append(v.call(f[j][0], f[j][1], f[j][2]))
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(f[4])
			st.add_vertex(p[i])


# ---------------------------------------------------------------- window light

func _build_shafts() -> void:
	_shaft_mesh = ImmediateMesh.new()
	_shafts = MeshInstance3D.new()
	_shafts.mesh = _shaft_mesh
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/light_cone.gdshader")
	m.set_shader_parameter("height", WIN_Y1)
	m.set_shader_parameter("top", WIN_Y1)
	m.set_shader_parameter("intensity", 0.05)
	m.set_shader_parameter("dust", 0.6)
	_shafts.material_override = m
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shafts)


## Each window's light as a slanted prism from the glass to its patch on the
## floor (the same fake-volumetric shader as the cones, faint).
func _rebuild_shafts(d: Vector3, strength: float) -> void:
	if _shaft_mesh == null:
		return
	_shaft_mesh.clear_surfaces()
	_shafts.set_instance_shader_parameter("strength", strength)
	_shaft_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := WIN_W * 0.46
	for x in WINDOWS:
		var w := [Vector3(x - hw, WIN_Y0, WALL_Z), Vector3(x + hw, WIN_Y0, WALL_Z),
			Vector3(x + hw, WIN_Y1 - 0.4, WALL_Z), Vector3(x - hw, WIN_Y1 - 0.4, WALL_Z)]
		var f: Array = []
		for p in w:
			var t: float = p.y / -d.y
			f.append(p + d * t)
		# four sides: bottom, top, left, right (each a quad from window edge to floor edge)
		for e in [[0, 1], [2, 3], [3, 0], [1, 2]]:
			var a: Vector3 = w[e[0]]
			var b: Vector3 = w[e[1]]
			var fa: Vector3 = f[e[0]]
			var fb: Vector3 = f[e[1]]
			var n := (b - a).cross(fa - a).normalized()
			for p in [a, b, fb, a, fb, fa]:
				_shaft_mesh.surface_set_normal(n)
				_shaft_mesh.surface_add_vertex(p)
			for p in [a, fb, b, a, fa, fb]:
				_shaft_mesh.surface_set_normal(-n)
				_shaft_mesh.surface_add_vertex(p)
	_shaft_mesh.surface_end()


func _push_spots() -> void:
	if _floor_mat == null:
		return
	var arr := PackedVector4Array()
	for s in _spots:
		arr.append(Vector4(s.at.x, s.at.y, s.r, s.level))
	_floor_mat.set_shader_parameter("spots", arr)
	_floor_mat.set_shader_parameter("spot_count", arr.size())

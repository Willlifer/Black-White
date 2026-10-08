class_name BWShaderWarm
extends RefCounted
## D232 (L-6): pre-warm the VFX shaders and materials so the first cast, the
## first Rain of Arrows / Tempest, the first tile FX and the first HP bar
## don't stall a frame while their shaders and pipelines compile.
##
##   BWShaderWarm.start(boot_node)        # boot: once, under the title, async
##   await BWShaderWarm.warm(host)        # the pass itself (tools/prewarm_probe.gd)
##
## The pass draws one object per (shader, mesh format) pair the combat VFX
## use, offscreen in a small SubViewport with the main viewport's MSAA, for a
## few frames, then frees it all. Uniform values don't matter (a pipeline is
## per shader, render state and vertex format); the mesh formats do, so each
## shader is drawn on the mesh its system really uses. Skipped headless and
## with BW_PREWARM=0 (the probe's "cold" run).

const FRAMES := 3
const SIZE := Vector2i(192, 192)

static var done := false
static var last_ms := 0.0
## D381: the boot screen (BWBootScreen) reads these: a pass is queued or
## running, and how far it is (0-1: built, then each frame drawn).
static var pending := false
static var progress := 0.0


static func start(host: Node) -> void:
	if done or DisplayServer.get_name() == "headless" or OS.get_environment("BW_PREWARM") == "0":
		return
	done = true
	pending = true
	progress = 0.0
	warm.call_deferred(host)


## Every (name, node) pair to draw. Fresh nodes each call (the probe reuses it
## to show each one cold on the main screen).
static func catalog() -> Array:
	var out: Array = []
	# tile FX (BWTileFX / BWBoardView): faces and markers on the hex, cards, bursts, flashes
	for k in ["tile_fire", "tile_water", "tile_light", "tile_dark", "fuse", "stasis", "gale", "glaze"]:
		out.append([k, _mi(BWTileFX.hex_mesh(), BWTileFX.material(k))])
	for k in ["tile_flame", "tile_beam", "tile_tendril"]:
		var mi := _mi(BWTileFX.card_mesh(), BWTileFX.material(k))
		mi.custom_aabb = BWTileFX.CARD_AABB
		out.append([k, mi])
	out.append(["burst", _mi(BWTileFX.disc_mesh(), BWTileFX.material("burst_detonate"))])
	out.append(["flash", _mi(BWTileFX.quad_mesh(), BWTileFX.material("flash_detonate"))])
	# casts (BWVfxCasts): columns / spheres on a quad, ground circles, ribbons, the particle pool
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var col := _mi(q, _shader_mat("res://shaders/vfx_column.gdshader"))
	col.custom_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	out.append(["vfx_column", col])
	var disc := PlaneMesh.new()
	disc.size = Vector2(2, 2)
	out.append(["vfx_ground", _mi(disc, _shader_mat("res://shaders/vfx_ground.gdshader"))])
	out.append(["vfx_ribbon", _mi(_strip(), _shader_mat("res://shaders/vfx_ribbon.gdshader"))])
	out.append(["vfx_particle", _particles()])
	# ranged (BWVfxRanged / BWProjectileFlight): volley shadow on the hex, muzzle flash on a quad
	out.append(["volley_shadow", _mi(BWTileFX.hex_mesh(), _shader_mat("res://shaders/volley_shadow.gdshader"))])
	out.append(["muzzle_flash", _mi(q, _shader_mat("res://shaders/muzzle_flash.gdshader"))])
	out.append(["smear", _mi(_strip(), _shader_mat("res://shaders/smear.gdshader"))])
	# the D215 HP bar and the label kinds (name / hp text, D231 kanji)
	var bar := BWHPBar3D.new(null)
	out.append(["hp_bar", bar])
	var tag := Label3D.new()
	tag.text = "Aa 12"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.004
	tag.outline_size = 9
	out.append(["label", tag])
	var kj := Label3D.new()
	kj.text = "".join(BWKanji.GLYPHS.values())
	kj.font = BWKanji.font(3)
	kj.font_size = 96
	kj.outline_size = 24
	kj.pixel_size = 0.004
	kj.shaded = false
	out.append(["kanji", kj])
	out.append_array(BWWeatherView.warm_catalog())      # D252: the weather's particles and telegraph
	out.append_array(BWIceWaterView.warm_catalog())     # D266: glaze sheen, pillars, field pips
	out.append_array(BWElementsView.warm_catalog())     # D292: beams, Overheat rims, bursts (one vertex-colour material)
	return out


static func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _sm := {}

static func _shader_mat(path: String) -> ShaderMaterial:
	if not _sm.has(path):
		var m := ShaderMaterial.new()
		m.shader = load(path)
		_sm[path] = m
	return _sm[path]


## A short ribbon in BWVfxCasts._strip's format (vertex, colour, uv).
static func _strip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [[Vector3(-0.5, 0, -0.1), Vector2(0, 0)], [Vector3(-0.5, 0, 0.1), Vector2(0, 1)], [Vector3(0.5, 0, 0.1), Vector2(1, 1)],
		[Vector3(-0.5, 0, -0.1), Vector2(0, 0)], [Vector3(0.5, 0, 0.1), Vector2(1, 1)], [Vector3(0.5, 0, -0.1), Vector2(1, 0)]]
	for p in pts:
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(p[1])
		st.add_vertex(p[0])
	return st.commit()


## BWVfxCasts' particle pool: a MultiMesh of quads with colours and custom data.
static func _particles() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mm.mesh = qm
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(i * 0.3, 0, 0)))
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(0.5, 0.5, 0.5, 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shader_mat("res://shaders/vfx_particle.gdshader")
	mmi.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	return mmi


## Draw the catalog offscreen for FRAMES frames, then free it. Returns the
## wall time spent (ms), also kept in last_ms.
static func warm(host: Node) -> float:
	if host == null or not host.is_inside_tree():
		pending = false
		return 0.0
	var t0 := Time.get_ticks_usec()
	var tree := host.get_tree()
	var vp := SubViewport.new()
	vp.name = "shader_warm"
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = tree.root.msaa_3d
	vp.use_hdr_2d = tree.root.use_hdr_2d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9, 9)
	cam.fov = 70
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	var items := catalog()
	var n := items.size()
	var cols := ceili(sqrt(float(n)))
	for i in n:
		var node: Node3D = items[i][1]
		node.position = Vector3((i % cols - cols * 0.5) * 2.2, 0, (i / cols - cols * 0.5) * 2.2)
		vp.add_child(node)
	host.add_child(vp)
	cam.current = true
	_instance_params(vp)
	progress = 0.25
	for f in FRAMES:
		await RenderingServer.frame_post_draw
		progress = 0.25 + 0.75 * float(f + 1) / FRAMES
	vp.queue_free()
	pending = false
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if OS.has_environment("BW_PREWARM_LOG"):
		print("shader warm: %d objects, %d frames, %.1f ms" % [n, FRAMES, last_ms])
	return last_ms


## The instance uniforms the tile shaders read, at a visible value (tier 0
## draws nothing). Unknown names are ignored by the server.
static func _instance_params(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var m := g.material_override as ShaderMaterial
		if m == null or m.shader == null:
			continue
		for p in [["tier", 2.0], ["age", 0.5], ["seed", 0.3]]:
			g.set_instance_shader_parameter(p[0], p[1])

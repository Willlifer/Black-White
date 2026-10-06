class_name BWMapThumbs
extends Node
## D190: map thumbnails for the room cards. A small top-down render of a hex
## map (the real BWBoardView with its authored tile FX, an orthographic camera
## from the player's side, steep, so the enemy start is at the top), once per
## map, then cached:
##   memory  a static dictionary, for the rest of the session
##   disk    user://map_thumbs/v<VERSION>/<map>.png, for later runs
## Bump VERSION when the maps or the framing change. The player's deploy hexes
## carry a grey ring, the enemy start a black hex, so the matchup reads.
##
##   BWMapThumbs.ensure(self)                  # one renderer in the tree
##   var tex := BWMapThumbs.thumb("lake")      # null until rendered
##   r.thumb_ready.connect(func(map): ...)     # a requested thumbnail landed

signal thumb_ready(map: String)

const VERSION := 1
const SIZE := Vector2i(640, 360)
const DIR := "user://map_thumbs/v%d/" % VERSION
const PITCH := 62.0
const BG := Color(0.035, 0.035, 0.04)

static var _cache := {}               # map -> Texture2D
static var _inst: BWMapThumbs
## Tools: skip the disk cache (re-render every map once this session).
static var fresh := false

var _queue: Array = []
var _busy := false
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


static func ensure(parent: Node) -> BWMapThumbs:
	if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	_inst = BWMapThumbs.new()
	_inst.name = "MapThumbs"
	parent.add_child(_inst)
	return _inst


static func instance() -> BWMapThumbs:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## The cached thumbnail, or null (and a render is queued) if not ready yet.
static func thumb(map: String) -> Texture2D:
	if _cache.has(map):
		return _cache[map]
	var path := DIR + map + ".png"
	if not fresh and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img and not img.is_empty():
			_cache[map] = ImageTexture.create_from_image(img)
			return _cache[map]
	var r := instance()
	if r:
		r._request(map)
	return null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.current = true
	_cam.far = 400.0
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func _request(map: String) -> void:
	if map in _queue:
		return
	_queue.append(map)
	if not _busy:
		_pump.call_deferred()


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty() and is_inside_tree():
		var m: String = _queue.pop_front()
		if _cache.has(m):
			thumb_ready.emit(m)
			continue
		var tex := await _render(m)
		if tex:
			_cache[m] = tex
		thumb_ready.emit(m)
	_busy = false


func _render(map: String) -> Texture2D:
	for c in _stage.get_children():
		c.free()
	var path := "res://maps/%s.json" % map
	var board := BWBoard.load_file(path)
	if board.cells().is_empty():
		return null
	var bv := BWBoardView.new()
	_stage.add_child(bv)
	bv.build(board, BWTileFX.authored(board, path))
	bv.set_process(false)
	for h in board.deploy.player:
		_mark(bv.top_center(h), 0.56, 0.84, Color(0.42, 0.42, 0.45, 1.0))
	for h in board.spawns.enemy:
		_mark(bv.top_center(h), 0.0, 0.70, Color(0.0, 0.0, 0.0, 1.0))
	# From the player's side (deploy centre away from the enemy start), steep.
	var pts: Array = []
	for h in board.cells():
		pts.append(bv.top_center(h))
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var dsum := Vector3.ZERO
	for h in board.deploy.player:
		dsum += bv.top_center(h)
	var esum := Vector3.ZERO
	for h in board.spawns.enemy:
		esum += bv.top_center(h)
	var away := Vector2.ZERO
	if not board.deploy.player.is_empty() and not board.spawns.enemy.is_empty():
		var dc: Vector3 = dsum / board.deploy.player.size()
		var ec: Vector3 = esum / board.spawns.enemy.size()
		away = Vector2(dc.x - ec.x, dc.z - ec.z)
	if away.length() < 0.1:
		away = Vector2(0, 1)
	away = away.normalized()
	var p := deg_to_rad(PITCH)
	_cam.position = c + Vector3(away.x * cos(p), sin(p), away.y * cos(p)) * 80.0
	_cam.look_at(c, Vector3.UP)
	var inv := _cam.global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		for dy in [-0.6, 0.0]:
			var v: Vector3 = inv * (q + Vector3(0, dy, 0))
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var ext := hi - lo
	var aspect := float(SIZE.x) / float(SIZE.y)
	_cam.size = maxf(ext.y, ext.x / aspect) * 1.08 + 1.0
	var mid := (lo + hi) / 2.0
	_cam.position += _cam.global_transform.basis.x * mid.x + _cam.global_transform.basis.y * mid.y
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return null
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	img.save_png(ProjectSettings.globalize_path(DIR + map + ".png"))
	return ImageTexture.create_from_image(img)


## A flat hex ring (r0 > 0) or disc (r0 = 0) just above a tile top.
func _mark(at: Vector3, r0: float, r1: float, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := BWLook.hex_corners(Vector3.ZERO, maxf(r0, 0.001))
	var outer := BWLook.hex_corners(Vector3.ZERO, r1)
	for i in 6:
		var j := (i + 1) % 6
		var tri := [outer[i], outer[j], inner[j], outer[i], inner[j], inner[i]]
		var both: Array = tri.duplicate()
		tri.reverse()
		both.append_array(tri)                    # both windings: never culled
		for q in both:
			st.set_color(Color.WHITE)
			st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = BWLook.alpha(false)     # the pre-battle deploy rings' material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 1.0                         # over the tile FX
	mi.position = at + Vector3(0, 0.06, 0)
	_stage.add_child(mi)
	mi.set_instance_shader_parameter("tint", col)

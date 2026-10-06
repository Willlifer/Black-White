class_name BWItemIcons
extends Node
## Item icons rendered from the real models (art/equipment/*.glb and
## art/weapons/*.glb), once per (base id, element), then cached:
##   memory  a static dictionary, for the rest of the session
##   disk    user://item_icons/v<VERSION>/<base>_<element>.png, for later runs
## Bump VERSION when the models or the framing change.
##
##   BWItemIcons.ensure(self)                       # one renderer in the tree
##   var tex := BWItemIcons.icon(base_id, element)  # null until rendered
##   BWItemIcons.ready.connect(func(key): ...)      # a requested icon landed
##
## The renderer is a SubViewport in its own World3D with a transparent
## background and an orthographic camera fitted to the model's bounds. Armour
## faces the camera three-quarter; weapons lie on the diagonal, profile on.
## Colour follows the models' own contract: the armour accent and the weapon
## accent take the element colour (grey / untinted when plain).

signal icon_ready(key: String)

const VERSION := 1
const SIZE := 128
const DIR := "user://item_icons/v%d/" % VERSION

static var _cache := {}               # key -> Texture2D
static var _inst: BWItemIcons

var _queue: Array = []                # [base, element]
var _busy := false
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


static func key_for(base_id: String, element: String) -> String:
	return "%s_%s" % [base_id, element if element != "" else "plain"]


## Make sure one renderer lives under `parent` (re-parented if the old one was freed).
static func ensure(parent: Node) -> BWItemIcons:
	if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	_inst = BWItemIcons.new()
	_inst.name = "ItemIcons"
	parent.add_child(_inst)
	return _inst


static func instance() -> BWItemIcons:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## The icon for an item Dictionary (base + its enchantment's element).
static func for_item(item: Dictionary) -> Texture2D:
	if item.is_empty():
		return null
	return icon(str(item.get("base", "")), BWRun.item_element(item))


## The cached icon, or null (and a render is queued) if it isn't ready yet.
static func icon(base_id: String, element: String = "") -> Texture2D:
	var key := key_for(base_id, element)
	if _cache.has(key):
		return _cache[key]
	var path := DIR + key + ".png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img and not img.is_empty():
			_cache[key] = ImageTexture.create_from_image(img)
			return _cache[key]
	var r := instance()
	if r:
		r._request(base_id, element)
	return null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.current = true
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func _request(base_id: String, element: String) -> void:
	for q in _queue:
		if q[0] == base_id and q[1] == element:
			return
	_queue.append([base_id, element])
	if not _busy:
		_pump.call_deferred()


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty() and is_inside_tree():
		var q: Array = _queue.pop_front()
		var key := key_for(q[0], q[1])
		if _cache.has(key):
			continue
		var tex := await _render(q[0], q[1])
		if tex:
			_cache[key] = tex
		icon_ready.emit(key)
	_busy = false


func _render(base_id: String, element: String) -> Texture2D:
	for c in _stage.get_children():
		c.free()
	var node := _build(base_id, element)
	if node == null:
		return null
	_stage.add_child(node)
	# Fit an orthographic camera to the model's bounds, seen along `view`.
	var aabb := _bounds(node)
	var view := Vector3(0.62, 0.30, 1.0).normalized()
	if _is_weapon(base_id):
		view = Vector3(1.0, 0.12, 0.10).normalized()
	var centre := aabb.get_center()
	_cam.position = centre + view * (aabb.size.length() * 2.0 + 2.0)
	_cam.look_at(centre, Vector3.UP)
	# Projected extent in the camera's own plane, so long weapons fill the tile.
	var inv := _cam.global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = inv * aabb.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var ext := hi - lo
	_cam.size = maxf(ext.x, ext.y) * 1.16
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
	img.save_png(ProjectSettings.globalize_path(DIR + key_for(base_id, element) + ".png"))
	return ImageTexture.create_from_image(img)


## D203: the imbuement scroll, drawn in the tile's own canvas: a rolled B/W
## scroll (paper, two rolls, inked lines) with a wax seal in the element colour.
static func draw_scroll(ci: CanvasItem, r: Rect2, element: String) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) / 2.0
	var ink := Color(0.04, 0.04, 0.05)
	var paper := Rect2(o + Vector2(0.27, 0.20) * s, Vector2(0.46, 0.56) * s)
	ci.draw_rect(paper, Color(0.93, 0.92, 0.89))
	ci.draw_rect(paper, ink, false, maxf(1.5, s * 0.02))
	for i in 4:
		var y := paper.position.y + s * (0.10 + 0.085 * i)
		var x1 := paper.end.x - s * (0.07 if i < 3 else 0.17)
		ci.draw_line(Vector2(paper.position.x + s * 0.06, y), Vector2(x1, y), Color(0.25, 0.25, 0.27), maxf(1.2, s * 0.018))
	for y in [0.13, 0.71]:
		var roll := Rect2(o + Vector2(0.19, y) * s, Vector2(0.62, 0.12) * s)
		ci.draw_rect(roll, Color(0.80, 0.79, 0.76))
		ci.draw_rect(Rect2(roll.position + Vector2(0, roll.size.y * 0.62), Vector2(roll.size.x, roll.size.y * 0.38)), Color(0.62, 0.61, 0.58))
		ci.draw_rect(roll, ink, false, maxf(1.5, s * 0.02))
		for x in [roll.position.x, roll.end.x]:
			ci.draw_circle(Vector2(x, roll.get_center().y), s * 0.045, Color(0.70, 0.69, 0.66))
			ci.draw_arc(Vector2(x, roll.get_center().y), s * 0.045, 0, TAU, 16, ink, maxf(1.2, s * 0.016))
	var col := BWLook.element_color(element) if element != "" else Color(0.6, 0.6, 0.6)
	var c := o + Vector2(0.5, 0.74) * s
	for side in [-1.0, 1.0]:
		var tail := PackedVector2Array([c + Vector2(side * 0.03, 0) * s, c + Vector2(side * 0.11, 0.20) * s,
			c + Vector2(side * 0.05, 0.16) * s, c + Vector2(side * 0.0, 0.21) * s])
		ci.draw_colored_polygon(tail, col.darkened(0.25))
		var line := tail.duplicate()
		line.append(tail[0])
		ci.draw_polyline(line, ink, maxf(1.0, s * 0.012))
	ci.draw_circle(c, s * 0.11, col.darkened(0.35))
	ci.draw_circle(c, s * 0.085, col)
	ci.draw_arc(c, s * 0.055, 0, TAU, 20, col.lightened(0.35), maxf(1.0, s * 0.014))
	ci.draw_arc(c, s * 0.11, 0, TAU, 24, ink, maxf(1.5, s * 0.02))


## D201: the curse mark, a small ink plate with a white dagger-cross, at `at`.
static func draw_curse(ci: CanvasItem, at: Vector2, px: float) -> void:
	var c := at + Vector2(px, px) / 2.0
	ci.draw_circle(c, px * 0.5, Color(0, 0, 0, 0.92))
	ci.draw_arc(c, px * 0.5, 0, TAU, 20, Color(1, 1, 1, 0.9), maxf(1.0, px * 0.08))
	var w := maxf(1.5, px * 0.12)
	ci.draw_line(c + Vector2(0, -px * 0.32), c + Vector2(0, px * 0.34), Color.WHITE, w)
	ci.draw_line(c + Vector2(-px * 0.2, -px * 0.1), c + Vector2(px * 0.2, -px * 0.1), Color.WHITE, w)


static func _is_weapon(base_id: String) -> bool:
	return str(BWData.row("equipment", base_id).get("slot", "")) == "main_hand"


func _build(base_id: String, element: String) -> Node3D:
	if _is_weapon(base_id):
		var w := BWWeaponView.create(base_id)
		if w == null:
			return null
		w.transform = Transform3D.IDENTITY
		# Lay the blade on the screen diagonal (tip to the upper right).
		w.rotation = Vector3(deg_to_rad(-42.0), 0, 0)
		if element != "":
			for mi in w.meshes():
				mi.set_instance_shader_parameter("accent", Color(BWLook.element_color(element), 0.9))
		return w
	if not BWEquipmentView.has_model(base_id):
		return null
	return BWEquipmentView.instantiate(base_id, element)


static func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh and (c as MeshInstance3D).visible:
			var mi := c as MeshInstance3D
			var b: AABB = (n as Node3D).global_transform.affine_inverse() * mi.global_transform * mi.get_aabb() \
				if n.is_inside_tree() else _local_xf(mi, n) * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
	if n is Node3D:
		out = (n as Node3D).transform * out
	return out


static func _local_xf(mi: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = mi
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

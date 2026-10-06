class_name BWWidgets
## Small drawn HUD pieces shared by every screen.


## A faceless head: white disc, ink rim, hair cap in the element colour.
## Stands in for V8's portraits until the rigged busts render (Phase 5).
class HeadIcon:
	extends Control
	var element := ""
	var enemy := false
	var selected := false

	func _init(el: String = "", is_enemy: bool = false, px: float = 42.0) -> void:
		element = el
		enemy = is_enemy
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var c := s / 2.0
		var r := minf(s.x, s.y) * 0.36
		var bg := BWStyle.PANEL_BG_LIGHT if not enemy else Color(0.20, 0.20, 0.22, 0.95)
		draw_rect(Rect2(Vector2.ZERO, s), bg)
		draw_rect(Rect2(Vector2.ZERO, s), Color.WHITE if selected else BWStyle.BORDER_SOFT, false, 3.0 if selected else 1.0)
		var head_c := c + Vector2(0, r * 0.15)
		draw_circle(head_c, r + 2.0, Color.BLACK)
		draw_circle(head_c, r, Color.WHITE)
		# hair: an arc band over the top of the head
		var col := BWLook.element_color(element) if element != "" else Color(0.5, 0.5, 0.5)
		var pts := PackedVector2Array()
		for i in 25:
			var a := PI + PI * float(i) / 24.0
			pts.append(head_c + Vector2(cos(a), sin(a) * 0.9) * (r + 3.0))
		for i in range(24, -1, -1):
			var a := PI + PI * float(i) / 24.0
			pts.append(head_c + Vector2(cos(a), sin(a) * 0.35 - 0.12) * (r - 1.0))
		draw_colored_polygon(pts, col)
		if enemy:
			# enemy mark: a small ink notch in the corner
			draw_colored_polygon(PackedVector2Array([Vector2(s.x - 12, 0), s * Vector2(1, 0), Vector2(s.x, 12)]), Color.WHITE)


## D156: a unit's real portrait (BWPortraits: its head, hair gradient, collar
## and headgear, rendered once per look). Draws the HeadIcon placeholder until
## the render lands, then swaps it in. Always keeps a thin element-colour
## frame and a corner tick so the element reads even when streaks or an
## ombre make the hair ambiguous; enemies keep the dark plate and the notch.
##
##   var p := BWWidgets.Portrait.new(unit, 42.0)   # same px as the HeadIcon it replaces
##   p.selected = true
##   p.set_unit(other)                             # cards that are refilled
## A unit-less portrait (the codex) passes `look_unit`, a stand-in built by
## Portrait.stand_in(element).
class Portrait:
	extends HeadIcon
	var unit: BWUnit
	var tex: Texture2D
	const PLATE := Color(0.15, 0.15, 0.165, 0.97)        ## a step above the panels, so dark hair still reads
	const PLATE_ENEMY := Color(0.27, 0.27, 0.29, 0.97)
	var _key := ""
	var _obelisk := false
	var _bright := true

	func _init(u: BWUnit = null, px: float = 42.0, is_enemy: Variant = null) -> void:
		super("", false, px)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		set_unit(u, is_enemy)

	func _ready() -> void:
		var r := BWPortraits.ensure(self)
		if r and not r.portrait_ready.is_connected(_on_ready):
			r.portrait_ready.connect(_on_ready)
		if unit and tex == null:
			_fetch()

	## Show `u` (null: the empty placeholder). `is_enemy` overrides the team read.
	func set_unit(u: BWUnit, is_enemy: Variant = null) -> void:
		unit = u
		element = u.element if u else ""
		enemy = bool(is_enemy) if is_enemy != null else (u != null and u.team == "enemy")
		_obelisk = u != null and BWObelisk.is_objective(u)
		if _obelisk:
			_bright = (u as BWObelisk).look() == "bright"
			element = ""
			enemy = not _bright
		var k := BWPortraits.key_for(u) if u else ""
		if k != _key:
			_key = k
			tex = null
			_fetch()
		queue_redraw()

	## Re-read the look (a rank-up, new headgear): a new key re-renders.
	func refresh() -> void:
		set_unit(unit, enemy)

	func _fetch() -> void:
		if unit == null:
			return
		var t := BWPortraits.portrait(unit)
		if t:
			tex = t
			queue_redraw()

	func _on_ready(k: String) -> void:
		if k == _key and unit:
			tex = BWPortraits.cached(k)
			queue_redraw()

	## A character with only an element (the codex's element cards): rank 3,
	## solid colour, neutral clothes.
	static func stand_in(el: String) -> BWUnit:
		var u := BWUnit.new()
		u.id = "codex_" + el
		u.element = el
		u.affinity = { el: 3 * BWUnit.POINTS_PER_RANK } if el != "" else {}
		u.cosmetics = { "hair_style": "bob", "hair_variant": 0, "top": "tshirt", "bottom": "sweatpants", "clothing_shade": "mid" }
		return u

	func _draw() -> void:
		if tex == null and not _obelisk:
			super()                                   # the placeholder until the render lands
			_draw_marks()
			return
		var s := size
		var bg := PLATE if not enemy else PLATE_ENEMY
		if _obelisk:
			bg = Color(0.20, 0.20, 0.22, 0.95) if _bright else Color(0.62, 0.62, 0.66, 0.95)   # the Well: black stone on a pale plate
		draw_rect(Rect2(Vector2.ZERO, s), bg)
		if tex:
			var side := minf(s.x, s.y)
			draw_texture_rect(tex, Rect2((s - Vector2(side, side)) / 2.0, Vector2(side, side)), false)
		elif _obelisk:
			BWWidgets.draw_stone(self, s, _bright)
		_draw_marks()

	## The frame: element colour (grey when unaligned), a corner tick, the
	## selection ring, the enemy notch.
	func _draw_marks() -> void:
		var s := size
		var side := minf(s.x, s.y)
		var col := BWLook.element_color(element) if element != "" else Color(0.55, 0.55, 0.58)
		if BWLook.luminance(col) < 0.06:              # dark's deep violet: lifted so the frame reads on the plate
			col = col.lerp(Color.WHITE, 0.3)
		if _obelisk:
			col = Color(0.85, 0.85, 0.88) if _bright else Color(0.62, 0.55, 0.85)
		var w := clampf(side * 0.035, 1.5, 3.5)
		draw_rect(Rect2(Vector2(w, w) * 0.5, s - Vector2(w, w)), col, false, w)
		var t := clampf(side * 0.2, 7.0, 20.0)       # the corner tick, bottom left
		draw_colored_polygon(PackedVector2Array([Vector2(0, s.y - t), Vector2(t, s.y), Vector2(0, s.y)]), col)
		draw_polyline(PackedVector2Array([Vector2(0, s.y - t), Vector2(t, s.y)]), Color(0, 0, 0, 0.8), 1.0, true)
		if selected:
			draw_rect(Rect2(Vector2.ZERO, s), Color.WHITE, false, 3.0)
		if enemy and not _obelisk:
			var n := clampf(side * 0.22, 8.0, 14.0)
			draw_colored_polygon(PackedVector2Array([Vector2(s.x - n, 0), Vector2(s.x, 0), Vector2(s.x, n)]), Color.WHITE)


## D156: a camera feed of the unit's face, for the big unit panels (the
## combat acting / hover cards, the hall card, the pre-battle stat panel and
## hover card). A small SubViewport sharing the unit view's World3D, with an
## orthographic camera that tracks the head bone in the snapshot's framing
## (3/4 front, BWPortraits.FRAME_*), so the face follows idles, strikes and
## hit reactions. Only this unit is drawn: each feed owns a render layer
## (LAYER_BASE + slot, 19 and 20); the unit's meshes get that bit added
## (re-tagged every ~0.5 s, so a new weapon, aura or armour joins) and the feed
## camera culls everything else. Every other camera keeps its all-layers mask,
## so nothing changes in the main view. The camera's own Environment paints the
## plate colour behind the head (no backdrop geometry in the shared world).
## Falls back to the cached snapshot (Portrait) when the unit has no view on
## stage (BWUnitView.view_for), or when MAX_LIVE feeds are already running.
## Renders every other frame (~30 fps at 60); hidden = not rendered.
class LivePortrait:
	extends Portrait
	const MAX_LIVE := 2
	const MAX_PX := 320
	const LAYER_BASE := 18                ## bit index: feeds use layers 19 and 20 (1-based)
	static var live := 0                  ## feeds running now
	static var _slots := [false, false]
	static var enabled := OS.get_environment("BW_LIVE") != "0"   ## false: always the snapshot (benchmarks: BW_LIVE=0)
	## Rolling GPU / CPU render time per feed update, ms (RenderingServer measure).
	static var stats := { "updates": 0, "gpu": 0.0, "cpu": 0.0 }
	var view: BWUnitView
	var _vp: SubViewport
	var _cam: Camera3D
	var _env: Environment
	var _tick := 0
	var _head_off := 0.0
	var _head_bone := -1
	var _slot := -1
	var _tagged: BWUnitView

	func set_unit(u: BWUnit, is_enemy: Variant = null) -> void:
		super(u, is_enemy)
		var v := BWUnitView.view_for(u) if u else null
		if v != view:
			_untag()
			view = v
			_head_bone = -1
			_tick = 0
			if view == null:
				_stop()
		if _env:
			_env.background_color = _plate()
		queue_redraw()

	func _plate() -> Color:
		var c := PLATE_ENEMY if enemy else PLATE
		if _obelisk:
			c = Color(0.20, 0.20, 0.22) if _bright else Color(0.62, 0.62, 0.66)
		return Color(c, 1.0)

	func is_live() -> bool:
		return _vp != null and view != null and is_instance_valid(view)

	func _start() -> bool:
		if _vp:
			return true
		if not enabled or live >= MAX_LIVE or view == null:
			return false
		live += 1
		_slot = _slots.find(false)
		_slots[_slot] = true
		_vp = SubViewport.new()
		_vp.own_world_3d = false
		_vp.world_3d = view.get_world_3d()
		_vp.transparent_bg = false
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp.size = Vector2i(128, 128)
		add_child(_vp)
		RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_env = Environment.new()
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = _plate()
		_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_cam.environment = _env
		_cam.cull_mask = 1 << (LAYER_BASE + _slot)
		_vp.add_child(_cam)
		_cam.current = true
		return true

	func _stop() -> void:
		if _vp == null:
			return
		_untag()
		live -= 1
		if _slot >= 0:
			_slots[_slot] = false
		_slot = -1
		_vp.queue_free()
		_vp = null
		_cam = null
		_env = null

	func _exit_tree() -> void:
		_stop()

	func _process(_delta: float) -> void:
		if view != null and not is_instance_valid(view):
			view = null
			_stop()
			queue_redraw()
		if view == null or not is_visible_in_tree():
			if _vp:
				_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		if _vp == null and not _start():          # a slot frees up: go live then
			return
		_tick += 1
		# GPU timings arrive a frame or two late: sample every frame, keep the non-zero ones
		var rid := _vp.get_viewport_rid()
		var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var c := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		if g > 0.0 or c > 0.0:
			stats.gpu = g if stats.updates == 0 else lerpf(stats.gpu, g, 0.05)
			stats.cpu = c if stats.updates == 0 else lerpf(stats.cpu, c, 0.05)
			stats.updates += 1
			if OS.has_environment("BW_LIVE_STATS") and stats.updates % 120 == 0:
				var root_rid := get_tree().root.get_viewport_rid()
				print("live portraits: %d feeds, %d px, per render gpu %.3f ms cpu %.3f ms; main view gpu %.2f ms; fps %d" % [live, _vp.size.x,
					stats.gpu, stats.cpu, RenderingServer.viewport_get_measured_render_time_gpu(root_rid), Engine.get_frames_per_second()])
		if _tick % 2 == 1:
			return
		if _tick % 30 == 2 or _tagged != view:
			_tag()
		if _vp.world_3d != view.get_world_3d():
			_vp.world_3d = view.get_world_3d()
		var scale_px := get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
		var px := clampi(int(ceil(minf(size.x, size.y) * scale_px)), 32, MAX_PX)
		if _vp.size.x != px:
			_vp.size = Vector2i(px, px)
		_place()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()

	## Add this feed's layer bit to every visual under the view (idempotent).
	func _tag() -> void:
		if _tagged != view:
			_untag()
		_tagged = view
		var bit := 1 << (LAYER_BASE + _slot)
		for n in _body(view).find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers |= bit

	## The figure only: the dressed character (or the stone's model), not the
	## name label, the HP bar over the head or the team disc.
	static func _body(v: BWUnitView) -> Node:
		if v.character:
			return v.character
		var m: Variant = v.get("model")
		return m if m is Node3D else v

	func _untag() -> void:
		if _tagged != null and is_instance_valid(_tagged) and _slot >= 0:
			var bit := 1 << (LAYER_BASE + _slot)
			for n in _body(_tagged).find_children("*", "VisualInstance3D", true, false):
				(n as VisualInstance3D).layers &= ~bit
		_tagged = null

	## Aim at the head, in the snapshot's framing, from the unit's own facing.
	func _place() -> void:
		var centre: Vector3
		var basis := view.global_transform.basis.orthonormalized()
		var s := view.global_transform.basis.get_scale().y
		var size_m := BWPortraits.FRAME_SIZE
		var yaw := BWPortraits.VIEW_YAW
		var c3 := view.character
		if _obelisk:
			var h := float(BWObeliskView.load_meta().get((unit as BWObelisk).kind, {}).get("height", 3.2)) * s
			centre = view.global_position + Vector3.UP * h * 0.66
			size_m = h * 0.72 / s
			yaw = 18.0
		elif c3 and c3.rig and c3.rig.skeleton:
			var sk := c3.rig.skeleton
			if _head_bone < 0:
				_head_bone = sk.find_bone("head")
				if _head_bone >= 0:
					var rig_from_sk := c3.global_transform.affine_inverse() * sk.global_transform
					_head_off = BWPortraits.FRAME_CENTRE.y - (rig_from_sk * sk.get_bone_global_rest(_head_bone).origin).y
			basis = c3.rig.global_transform.basis.orthonormalized()
			if _head_bone >= 0:
				centre = sk.global_transform * sk.get_bone_global_pose(_head_bone).origin + Vector3.UP * _head_off * s
			else:
				centre = view.global_position + Vector3.UP * BWPortraits.FRAME_CENTRE.y * s
			if unit.size > 1:                     # the Giant: the close framing of its snapshot
				centre += Vector3.UP * (1.70 - BWPortraits.FRAME_CENTRE.y) * s
				size_m = 0.98
				yaw = 32.0
		else:
			centre = view.global_position + Vector3.UP * (view.head_height() - 0.09 * s)
		var dir := basis * Vector3(sin(deg_to_rad(yaw)), sin(deg_to_rad(BWPortraits.VIEW_PITCH)), cos(deg_to_rad(yaw)))
		dir = dir.normalized()
		var d := 4.0 * s
		_cam.size = size_m * s
		_cam.global_position = centre + dir * d
		_cam.look_at(centre, Vector3.UP)
		# only this unit is on the feed's layer; the slab just keeps the far side tidy
		_cam.near = d - 1.6 * s * (2.0 if _obelisk else 1.0)
		_cam.far = d + 1.6 * s * (2.0 if _obelisk else 1.0)

	func _draw() -> void:
		if not is_live():
			super()
			return
		var s := size
		var side := minf(s.x, s.y)
		draw_rect(Rect2(Vector2.ZERO, s), _plate())
		draw_texture_rect(_vp.get_texture(), Rect2((s - Vector2(side, side)) / 2.0, Vector2(side, side)), false)
		_draw_marks()


## The carved stone, drawn: the obelisk portrait's placeholder (the same
## shapes as BWCombatUI.ObeliskIcon).
static func draw_stone(ci: CanvasItem, s: Vector2, bright: bool) -> void:
	var body := Color.WHITE if bright else Color(0.06, 0.06, 0.07)
	var line := Color.BLACK if bright else Color(0.85, 0.8, 1.0)
	var cx := s.x * 0.5
	var shaft := PackedVector2Array([Vector2(cx - s.x * 0.16, s.y * 0.84), Vector2(cx + s.x * 0.16, s.y * 0.84),
		Vector2(cx + s.x * 0.11, s.y * 0.26), Vector2(cx, s.y * 0.1), Vector2(cx - s.x * 0.11, s.y * 0.26)])
	ci.draw_colored_polygon(shaft, body)
	var closed := shaft.duplicate()
	closed.append(shaft[0])
	ci.draw_polyline(closed, Color.BLACK if bright else Color(0.85, 0.85, 0.9), 1.5)
	for k in 3:
		var y := s.y * (0.36 + 0.15 * k)
		ci.draw_line(Vector2(cx - s.x * 0.06, y), Vector2(cx + s.x * 0.06, y), line, 1.5)


## V8 hp_bar.gd, in black and white: outline, dark well, a white fill (grey
## for enemies), a sheen, and a tick every 10 HP (heavier every 100).
class HPBar:
	extends Control
	var hp := 100
	var max_hp := 100
	var preview := -1        # forecast: HP after the hit, drawn as a lighter cut
	var enemy := false

	func _init(px: Vector2 = Vector2(112, 11)) -> void:
		custom_minimum_size = px
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_hp(v: int, m: int, after: int = -1) -> void:
		hp = v
		max_hp = maxi(m, 1)
		preview = after
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2(-1, -1), s + Vector2(2, 2)), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.06, 0.07))
		var f := clampf(float(hp) / max_hp, 0.0, 1.0)
		var fill := BWStyle.ENEMY_FILL if enemy else BWStyle.PLAYER_FILL
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * f, s.y)), fill)
		if preview >= 0 and preview < hp:
			var pf := clampf(float(preview) / max_hp, 0.0, 1.0)
			draw_rect(Rect2(Vector2(s.x * pf, 0), Vector2(s.x * (f - pf), s.y)), Color(0.25, 0.25, 0.27))
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * f, s.y * 0.35)), Color(1, 1, 1, 0.28))
		var t := 10
		while t < max_hp:
			var x := s.x * float(t) / max_hp
			var heavy := t % 100 == 0
			draw_line(Vector2(x, 0), Vector2(x, s.y * (1.0 if heavy else 0.55)), Color(0, 0, 0, 0.75 if heavy else 0.45), 1.0)
			t += 10

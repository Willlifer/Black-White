class_name BWCameraRig
extends Node3D
## The Temporal Sea V8 combat camera (prologue_hill_combat_3d.gd §_update_cam,
## guide §5.1), ported: one Camera3D placed by spherical maths around a pivot.
##   left-drag   orbit (yaw + pitch, pitch 15–85°); a left click without a drag still picks
##   right/middle-drag   pan, speed scaled by distance
##   wheel       zoom ×0.9 per notch
##   arrows      pan
##   Space       recentre on the follow target (D322: the active unit, via recentre_fn)
##   Q / E       rotate 60° (B|W addition, tweened)
##   screen edge pan (D322, big boards: `edge_scroll`), clamped to `bounds`
## The follow lags (FOLLOW_LAG 4.0, "a follow camera lags, it does not snap");
## a player pan re-anchors the follow offset so the two don't fight.

signal clicked(screen_pos: Vector2)

const FOV := 34.0                # V8 SceneLook.FOV: the diorama lens (ADR-0018)
const PITCH_MIN := 15.0
const PITCH_MAX := 85.0
const DIST_MIN := 4.0
const DIST_MAX := 60.0
const FOLLOW_LAG := 4.0
const DRAG_THRESHOLD := 1.5
const YAW_PER_PX := 0.008
const PITCH_PER_PX := 0.006
const PAN_PER_PX := 0.0016
## D322: edge scroll: the cursor within EDGE_PX of the window edge pans at
## EDGE_SPEED screen px a second (scaled by distance like a drag).
const EDGE_PX := 14.0
const EDGE_SPEED := 900.0

var cam: Camera3D
var pivot := Vector3.ZERO: set = _set_pivot
var yaw := deg_to_rad(8.0): set = _set_yaw
var pitch := deg_to_rad(42.0): set = _set_pitch
var dist := 24.0: set = _set_dist
var following := true
var input_enabled := true
## D322: the zoom-out limit (big boards raise it, see fit_board).
var dist_max := DIST_MAX
## D322: pan with the cursor at the window edge (big boards).
var edge_scroll := false
## D322: the pivot stays inside this ground rectangle (x, z); empty = free.
var bounds := Rect2()
## D322: Space recentres on what this returns (the active unit's spot); unset = the follow target.
var recentre_fn: Callable

var _follow_target := Vector3.ZERO
var _follow_offset := Vector3.ZERO
var _press_pos := Vector2.ZERO
var _dragging := false
var _left_down := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = FOV
	add_child(cam)
	cam.make_current()
	_update()


func _set_pivot(v: Vector3) -> void:
	pivot = v
	_update()


func _set_yaw(v: float) -> void:
	yaw = v
	_update()


func _set_pitch(v: float) -> void:
	pitch = clampf(v, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	_update()


func _set_dist(v: float) -> void:
	dist = clampf(v, DIST_MIN, maxf(DIST_MAX, dist_max))
	_update()


## D322: a big board (a 6v6 map, deploy_count > 3): a wider zoom range
## (BIG_DIST_MAX), edge scroll and a pan clamp to the board's footprint
## (padded 2 m). True when it applied; 3v3 maps keep the V8 rig as is.
const BIG_DIST_MAX := 90.0


func fit_board(board: BWBoard) -> bool:
	if board.deploy_count <= BWRun.DEPLOY:
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for h in board.cells():
		var w := BWLook.world(h, 0)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	bounds = Rect2(lo, hi - lo).grow(2.0)
	dist_max = BIG_DIST_MAX
	edge_scroll = true
	return true


func _update() -> void:
	if cam == null:
		return
	if bounds.has_area() and not bounds.has_point(Vector2(pivot.x, pivot.z)):
		var c := Vector2(clampf(pivot.x, bounds.position.x, bounds.end.x), clampf(pivot.z, bounds.position.y, bounds.end.y))
		pivot = Vector3(c.x, pivot.y, c.y)        # D322: never pan off the board (re-enters through the setter once)
		return
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = pivot + dir * dist
	cam.look_at(pivot, Vector3.UP)


## Follow a point (the acting unit). The first call snaps; later ones lag.
func follow(p: Vector3, snap: bool = false) -> void:
	_follow_target = p
	_follow_offset = Vector3.ZERO
	following = true
	if snap:
		pivot = p


func recentre() -> void:
	if recentre_fn.is_valid():
		var p: Variant = recentre_fn.call()
		if p is Vector3:
			_follow_target = p                        # D322: the active unit, wherever the follow last went
	_follow_offset = Vector3.ZERO
	following = true


func _process(delta: float) -> void:
	if edge_scroll and input_enabled:
		_edge_pan(delta)
	if not following:
		return
	var target := _follow_target + _follow_offset
	if pivot.distance_to(target) < 0.005:
		return
	pivot = pivot.lerp(target, 1.0 - exp(-FOLLOW_LAG * delta))


## D322: the cursor at a window edge pans (only while the window has focus
## and the cursor is inside it, never during a drag).
func _edge_pan(delta: float) -> void:
	var vp := get_viewport()
	if vp == null or not DisplayServer.window_is_focused() or _left_down 			or Input.get_mouse_button_mask() & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		return
	var r := vp.get_visible_rect()
	var m := vp.get_mouse_position()
	if not r.has_point(m):
		return
	var d := Vector2.ZERO
	if m.x < r.position.x + EDGE_PX:
		d.x = 1.0
	elif m.x > r.end.x - EDGE_PX:
		d.x = -1.0
	if m.y < r.position.y + EDGE_PX:
		d.y = 1.0
	elif m.y > r.end.y - EDGE_PX:
		d.y = -1.0
	if d != Vector2.ZERO:
		pan(d * EDGE_SPEED * delta)


func pan(px: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var delta := (-right * px.x + fwd * px.y) * dist * PAN_PER_PX
	if bounds.has_area():                         # D322: the clamp eats the overshoot, so panning back is immediate
		var np := pivot + delta
		np = Vector3(clampf(np.x, bounds.position.x, bounds.end.x), np.y, clampf(np.z, bounds.position.y, bounds.end.y))
		delta = np - pivot
	pivot += delta
	_follow_offset += delta


func rotate_by(deg: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "yaw", yaw + deg_to_rad(deg), 0.3).set_trans(Tween.TRANS_SINE)


func _unhandled_input(ev: InputEvent) -> void:
	if not input_enabled:
		return
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if ev.pressed: dist *= 0.9
			MOUSE_BUTTON_WHEEL_DOWN:
				if ev.pressed: dist /= 0.9
			MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_left_down = true
					_dragging = false
					_press_pos = ev.position
				else:
					_left_down = false
					if not _dragging:
						clicked.emit(ev.position)
					_dragging = false
	elif ev is InputEventMouseMotion:
		if ev.button_mask & MOUSE_BUTTON_MASK_LEFT and _left_down:
			if _dragging or ev.position.distance_to(_press_pos) > DRAG_THRESHOLD * 4.0 or ev.relative.length() > DRAG_THRESHOLD:
				_dragging = true
				yaw -= ev.relative.x * YAW_PER_PX
				pitch += ev.relative.y * PITCH_PER_PX
		elif ev.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			pan(ev.relative)
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_LEFT: pan(Vector2(40, 0))
			KEY_RIGHT: pan(Vector2(-40, 0))
			KEY_UP: pan(Vector2(0, 40))
			KEY_DOWN: pan(Vector2(0, -40))
			KEY_SPACE: recentre()
			KEY_Q: rotate_by(-60.0)
			KEY_E: rotate_by(60.0)

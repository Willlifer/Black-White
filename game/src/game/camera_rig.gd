class_name BWCameraRig
extends Node3D
## The Temporal Sea V8 combat camera (prologue_hill_combat_3d.gd §_update_cam,
## guide §5.1), ported: one Camera3D placed by spherical maths around a pivot.
##   left-drag   orbit (yaw + pitch, pitch 15–85°); a left click without a drag still picks
##   right/middle-drag   pan, speed scaled by distance
##   wheel       zoom ×0.9 per notch
##   arrows      pan
##   Space       recentre on the follow target
##   Q / E       rotate 60° (B|W addition, tweened)
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

var cam: Camera3D
var pivot := Vector3.ZERO: set = _set_pivot
var yaw := deg_to_rad(8.0): set = _set_yaw
var pitch := deg_to_rad(42.0): set = _set_pitch
var dist := 24.0: set = _set_dist
var following := true
var input_enabled := true

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
	dist = clampf(v, DIST_MIN, DIST_MAX)
	_update()


func _update() -> void:
	if cam == null:
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
	_follow_offset = Vector3.ZERO
	following = true


func _process(delta: float) -> void:
	if not following:
		return
	var target := _follow_target + _follow_offset
	if pivot.distance_to(target) < 0.005:
		return
	pivot = pivot.lerp(target, 1.0 - exp(-FOLLOW_LAG * delta))


func pan(px: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var delta := (-right * px.x + fwd * px.y) * dist * PAN_PER_PX
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

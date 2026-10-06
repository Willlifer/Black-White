class_name BWPaperdoll
extends SubViewportContainer
## The selected unit's live, dressed 3D model (BWCharacter) in its own
## SubViewport and World3D, on a small plinth, slowly turning. Drag to turn
## it by hand (the auto-turn waits a few seconds after you let go).
##
##   set_unit(u)            show this unit (one character per unit, cached)
##   refresh()              re-dress from unit.equipment (after equip/unequip)
##   preview(slot, item)    dress a candidate item for a look, without
##                          changing the unit's real equipment ({} = clear)

const TURN_SPEED := 0.32          # rad/s auto-turn
const RESUME_AFTER := 2.5         # s after a manual turn

var unit: BWUnit
var character: BWCharacter
var yaw := -0.45
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _chars := {}                  # unit id -> BWCharacter
var _idle_t := 99.0
var _drag := false
var _previewing := false


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_vp.add_child(we)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_cam.transform = Transform3D(Basis(), Vector3(0, 1.3, 8.6)).looking_at(Vector3(0, 1.02, 0), Vector3.UP)
	_cam.current = true
	_vp.add_child(_cam)
	_vp.add_child(_plinth())


## A white disc with an ink rim and a soft ink shadow ring.
func _plinth() -> Node3D:
	var root := Node3D.new()
	var rim := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.78
	cm.bottom_radius = 0.80
	cm.height = 0.10
	rim.mesh = cm
	rim.material_override = BWLook.flat()
	rim.set_instance_shader_parameter("tint", Color(0.05, 0.05, 0.06))
	rim.position.y = -0.05
	root.add_child(rim)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.72
	tm.bottom_radius = 0.72
	tm.height = 0.02
	top.mesh = tm
	top.material_override = BWLook.flat()
	top.set_instance_shader_parameter("tint", Color(0.92, 0.92, 0.93))
	top.position.y = 0.0
	root.add_child(top)
	return root


func set_unit(u: BWUnit) -> void:
	if u == unit and character != null:
		return
	unit = u
	for id in _chars:
		_chars[id].visible = false
	if not _chars.has(u.id):
		var c := BWCharacter.create(u)
		_pivot.add_child(c)
		_chars[u.id] = c
	character = _chars[u.id]
	character.visible = true
	_previewing = false
	character.refresh_equipment()


func refresh() -> void:
	_previewing = false
	if character:
		character.refresh_equipment()


## Dress `item` in `slot` for a look. The unit's equipment is swapped only
## for the duration of the re-dress, then put back exactly as it was.
func preview(slot: String, item: Dictionary) -> void:
	if character == null or unit == null:
		return
	if item.is_empty():
		if _previewing:
			refresh()
		return
	var had := unit.equipment.has(slot)
	var old: Dictionary = unit.equipment.get(slot, {})
	unit.equipment[slot] = item
	character.refresh_equipment()
	if had:
		unit.equipment[slot] = old
	else:
		unit.equipment.erase(slot)
	_previewing = true


func is_previewing() -> bool:
	return _previewing


func _process(delta: float) -> void:
	_idle_t += delta
	if not _drag and _idle_t > RESUME_AFTER:
		yaw += TURN_SPEED * delta
	_pivot.rotation.y = yaw


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		_idle_t = 0.0
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		yaw += ev.relative.x * 0.012
		_idle_t = 0.0
		accept_event()

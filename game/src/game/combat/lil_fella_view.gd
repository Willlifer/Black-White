class_name BWLilFellaView
extends BWUnitView
## D348: the Lil Fella on the board (BWLilFella, Stop the Horde). The usual
## dressed character (BWCharacter: a pointed hat, a light hoodie, shorts) at
## SCALE of a squad figure, no weapon, a little LANTERN swinging from its
## left hand (an ink bail and frame, a white glass that breathes), and a
## white-and-ink tile ring under its feet (the tile marker) so it reads at
## 6v6 zoom. Same HP bar and name as a unit, at the normal on-screen size.

const SCALE := 0.62
const RING_R := 0.62             # world radius of the tile ring (after the scale)
const LANTERN_SCALE := 1.7       # the lantern reads at 6v6 zoom

var _lantern: Node3D
var _glass: MeshInstance3D
var _halo: MeshInstance3D
var _swing := 0.0


func setup(u: BWUnit) -> void:
	super.setup(u)
	name = "fella_" + u.id
	scale = Vector3.ONE * SCALE
	_label.pixel_size *= 1.0 / SCALE
	_hp_label.pixel_size *= 1.0 / SCALE
	if character and character.weapon:
		character.weapon.visible = false
	_build_ring()
	_build_lantern()


## The tile marker: a white ring with an ink rim on the hex under it.
func _build_ring() -> void:
	for spec in [[RING_R * 1.1, RING_R * 0.86, BWLook.INK, 0.03], [RING_R * 0.86, RING_R * 0.78, BWLook.WHITE, 0.034]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 40
		var ro: float = float(spec[0]) / SCALE
		var ri: float = float(spec[1]) / SCALE
		var y: float = float(spec[3]) / SCALE
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := Vector3(cos(a0), 0, sin(a0))
			var p1 := Vector3(cos(a1), 0, sin(a1))
			for p in [p0 * ro, p1 * ro, p1 * ri, p0 * ro, p1 * ri, p0 * ri]:
				st.add_vertex(p + Vector3(0, y, 0))
		var mi := MeshInstance3D.new()
		mi.name = "fella_ring"
		mi.mesh = st.commit()
		mi.material_override = BWLook.flat()
		mi.set_instance_shader_parameter("tint", spec[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_lantern() -> void:
	_lantern = Node3D.new()
	_lantern.name = "lantern"
	add_child(_lantern)
	_lantern.scale = Vector3.ONE * LANTERN_SCALE
	var ink := BWLook.flat()
	# the bail: a thin ink rod from the hand down to the cap
	var bail := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.012
	bm.bottom_radius = 0.012
	bm.height = 0.16
	bail.mesh = bm
	bail.position.y = -0.08
	bail.material_override = ink
	bail.set_instance_shader_parameter("tint", BWLook.INK)
	_lantern.add_child(bail)
	# the cap and the base: ink
	for yy in [-0.17, -0.37]:
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05 if yy > -0.2 else 0.085
		cm.bottom_radius = 0.085
		cm.height = 0.04
		cap.mesh = cm
		cap.position.y = yy
		cap.material_override = ink
		cap.set_instance_shader_parameter("tint", BWLook.INK)
		_lantern.add_child(cap)
	# the glass: white, unshaded, glowing a little
	_glass = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.07
	gm.bottom_radius = 0.07
	gm.height = 0.16
	gm.radial_segments = 6
	_glass.mesh = gm
	_glass.position.y = -0.27
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.98, 0.92)
	_glass.material_override = mat
	var ol := BWLook.outline(0.02, Color.BLACK)
	mat.next_pass = ol
	_lantern.add_child(_glass)
	# a soft halo (billboard) so the light reads on the dark board
	_halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 0.75)
	_halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = _halo_tex()
	hm.albedo_color = Color(1.0, 0.97, 0.88, 0.55)
	_halo.material_override = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = -0.27
	_lantern.add_child(_halo)


static var _tex: ImageTexture


static func _halo_tex() -> ImageTexture:
	if _tex:
		return _tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## The lantern hangs from the left hand wherever the clip puts it (the poser's
## hand transform), swinging a little with the walk; without a rig, at the hip.
func _process(delta: float) -> void:
	super._process(delta)
	if _lantern == null:
		return
	_swing += delta
	var at := global_position + Vector3(0.25, 0.75, 0.0) * SCALE
	if character and character.poser and character.poser.skeleton and character.poser.globals.has("hand_l"):
		var g: Transform3D = character.poser.skeleton.global_transform * (character.poser.globals["hand_l"] as Transform3D)
		at = g.origin
	_lantern.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.18 * sin(_swing * 2.6))).scaled(Vector3.ONE * SCALE * LANTERN_SCALE), at)
	if _glass and unit:
		var k := 0.92 + 0.08 * sin(_swing * 3.1)
		(_glass.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.98, 0.92) * k
	if _halo:
		_halo.visible = unit != null and unit.alive()

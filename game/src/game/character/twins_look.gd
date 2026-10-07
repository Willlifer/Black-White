class_name BWTwinsLook
extends RefCounted
## D260: the Twins' look, laid over a dressed BWCharacter (BWCharacter.
## _encounter_look, kind "twin"). Tall robed figures (BWUnitView scales them
## x1.6), every part one solid colour:
##   Noon  white with the ink contour; its head is a white RING standing
##         upright, a halo, with a disc of light's glow inside it
##   Dusk  black with a white contour (D42); its head is a HOLLOW octagonal
##         ring (the Black Well's motif) with a cold violet inner rim
## The rig's own head is hidden (its surface discards); the ring rides the
## head socket. Dusk's figure is mirrored (the rig's x scale -1), so the two
## hold their glaives in opposite hands and mirror each other's pose.

const NOON_BODY := Color(0.97, 0.97, 0.97)
const DUSK_BODY := Color(0.035, 0.035, 0.045)
const DUSK_LINE := Color(0.92, 0.92, 0.95)

static var _mats := {}
static var _discard: ShaderMaterial


static func is_noon(c: BWCharacter) -> bool:
	return c.unit != null and BWTwins.role(c.unit) == BWTwins.NOON


static func body_material(noon: bool) -> ShaderMaterial:
	var key := "noon" if noon else "dusk"
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/twin_body.gdshader")
	m.set_shader_parameter("body", NOON_BODY if noon else DUSK_BODY)
	m.next_pass = BWLook.outline(0.03, Color.BLACK if noon else DUSK_LINE)
	_mats[key] = m
	return m


static func discard_material() -> ShaderMaterial:
	if _discard == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
		_discard = ShaderMaterial.new()
		_discard.shader = sh
	return _discard


static func glow_color(noon: bool) -> Color:
	if noon:
		return BWLook.glow_color("light").lerp(Color.WHITE, 0.35)
	return BWLook.element_color("dark").lerp(Color(0.85, 0.8, 1.0), 0.6)


static func apply(c: BWCharacter) -> void:
	var noon := is_noon(c)
	# the robe over everything (visual only), the plain clothes under it hidden
	if c.equipment:
		c.equipment.equip_model("silken_robe", "")
		c.equipment.equip_model("robe_bottoms", "")
	for slot in ["top", "bottom"]:
		var g := BWClothing.garment(c.rig, slot)
		if g:
			g.visible = false
	var body := body_material(noon)
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("twin_head"):
			continue
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var skip := false
		for i in m.mesh.get_surface_count():
			var am := m.get_active_material(i)
			if am is ShaderMaterial and (am as ShaderMaterial).shader and str((am as ShaderMaterial).shader.resource_path).contains("aura"):
				skip = true
		if skip:
			continue
		for i in m.mesh.get_surface_count():
			var head_surface := m == c.rig.body and BWCharacterRig._role(m.mesh, i) == "skin"
			m.set_surface_override_material(i, discard_material() if head_surface else body)
	_ring_head(c, noon)
	if not noon and c.rig:
		c.rig.scale.x = -absf(c.rig.scale.x)   # mirrored: the glaive in the other hand


static func _ring_head(c: BWCharacter, noon: bool) -> void:
	var sock := c.rig.socket("hair")
	if sock == null or sock.has_node("twin_head"):
		return
	var root := Node3D.new()
	root.name = "twin_head"
	sock.add_child(root)
	var ring := MeshInstance3D.new()
	ring.set_meta("twin_head", true)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22 if noon else 0.2
	tm.outer_radius = 0.34 if noon else 0.35
	tm.rings = 40 if noon else 8          # round sun / the Well's octagon
	tm.ring_segments = 10 if noon else 4
	ring.mesh = tm
	ring.rotation.x = PI * 0.5             # stands upright, facing forward
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/twin_body.gdshader")
	m.set_shader_parameter("body", NOON_BODY if noon else DUSK_BODY)
	m.next_pass = BWLook.outline(0.022, Color.BLACK if noon else DUSK_LINE)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# the inside: Noon a disc of light, Dusk an inner rim of violet (hollow)
	var inner := MeshInstance3D.new()
	inner.set_meta("twin_head", true)
	inner.name = "twin_glow"
	if noon:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.2
		cyl.height = 0.02
		cyl.radial_segments = 32
		inner.mesh = cyl
		inner.rotation.x = PI * 0.5
	else:
		var t2 := TorusMesh.new()
		t2.inner_radius = 0.185
		t2.outer_radius = 0.215
		t2.rings = 8
		t2.ring_segments = 4
		inner.mesh = t2
		inner.rotation.x = PI * 0.5
	inner.material_override = BWObeliskView.glyph_material()
	inner.set_instance_shader_parameter("glow", glow_color(noon))
	inner.set_instance_shader_parameter("power", 0.8)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner)
	# Noon's halo proper: a thin glowing ring floating just behind the head
	if noon:
		var halo := MeshInstance3D.new()
		halo.set_meta("twin_head", true)
		halo.name = "twin_halo"
		var th := TorusMesh.new()
		th.inner_radius = 0.43
		th.outer_radius = 0.46
		th.rings = 48
		th.ring_segments = 6
		halo.mesh = th
		halo.rotation.x = PI * 0.5
		halo.position.z = -0.08
		halo.material_override = BWObeliskView.glyph_material()
		halo.set_instance_shader_parameter("glow", glow_color(true))
		halo.set_instance_shader_parameter("power", 0.7)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(halo)


## The glow parts (BWTwinsFX breathes them, flares them on the swap).
static func glow_parts(c: BWCharacter) -> Array:
	var out: Array = []
	for n in c.find_children("twin_*", "MeshInstance3D", true, false):
		out.append(n)
	return out

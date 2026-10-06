extends RefCounted
## The base character rig: art/characters/base_rig.glb through BWCharacterRig.
## Bone names, sockets, height, facing, materials, budget, test actions.


func _rig() -> BWCharacterRig:
	var r := BWCharacterRig.new()
	r.build()
	return r


func test_loads(t) -> void:
	var r := _rig()
	t.ok(r.model != null, "glb instanced")
	t.ok(r.skeleton != null, "has a Skeleton3D")
	t.ok(r.body != null, "has the body mesh")
	t.ok(r.anim != null, "has an AnimationPlayer")
	r.free()


func test_bones(t) -> void:
	var r := _rig()
	var sk := r.skeleton
	t.eq(sk.get_bone_count(), BWCharacterRig.BONES.size(), "deform bones only, no IK controls exported")
	for b in BWCharacterRig.BONES:
		t.ok(sk.find_bone(b) >= 0, "bone %s present" % b)
	var parents := {
		"hips": "root", "spine": "hips", "chest": "spine", "neck": "chest", "head": "neck",
		"shoulder_l": "chest", "upper_arm_l": "shoulder_l", "forearm_l": "upper_arm_l", "hand_l": "forearm_l",
		"shoulder_r": "chest", "upper_arm_r": "shoulder_r", "forearm_r": "upper_arm_r", "hand_r": "forearm_r",
		"thigh_l": "hips", "shin_l": "thigh_l", "foot_l": "shin_l",
		"thigh_r": "hips", "shin_r": "thigh_r", "foot_r": "shin_r",
	}
	for b in parents:
		var i := sk.find_bone(b)
		t.eq(sk.get_bone_name(sk.get_bone_parent(i)) if i >= 0 else "", parents[b], "%s parent" % b)
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		t.ok(not (n.begins_with("ik_") or n.begins_with("pole_")), "no control bone %s in export" % n)
	# up-pointing bones have identity rest rotation (roll convention)
	for b in ["root", "hips", "spine", "chest", "neck", "head"]:
		var basis := sk.get_bone_global_rest(sk.find_bone(b)).basis
		t.ok(basis.is_equal_approx(Basis.IDENTITY), "%s rest is identity" % b)
	r.free()


func test_sockets(t) -> void:
	var r := _rig()
	for s in BWCharacterRig.SOCKETS:
		var n := r.socket(s)
		t.ok(n != null, "socket %s present" % s)
		if n == null:
			continue
		var att := n.get_parent() as BoneAttachment3D
		t.ok(att != null and att.bone_name == BWCharacterRig.SOCKETS[s], "%s rides on %s" % [s, BWCharacterRig.SOCKETS[s]])
		t.ok(r.socket_rest(s).basis.is_equal_approx(Basis.IDENTITY), "%s is world-aligned at rest" % s)
	t.ok(r.socket("hair") == r.socket("socket_hair"), "short socket names resolve")
	t.ok(r.socket("nope") == null, "unknown socket is null")
	t.near(r.socket_rest("hair").origin.y, 1.92, 0.01, "hair socket at head centre")
	t.near(r.socket_rest("hat").origin.y, 2.2, 0.01, "hat socket at crown")
	t.ok(r.socket_rest("back").origin.z < -0.05, "back socket behind the chest")
	# character faces +Z, so its right hand is on -X
	t.ok(r.socket_rest("weapon_r").origin.x < -0.3, "weapon_r on the character's right (-X)")
	t.ok(r.socket_rest("offhand_l").origin.x > 0.3, "offhand_l on the character's left (+X)")
	r.free()


func test_height_and_facing(t) -> void:
	var r := _rig()
	var box := r.body.get_aabb()
	t.near(box.position.y, 0.0, 0.005, "feet at the origin")
	t.near(box.size.y, BWCharacterRig.HEIGHT, 0.01, "2.2 units tall")
	t.near(box.get_center().x, 0.0, 0.005, "centred on X")
	var sk := r.skeleton
	for f in ["foot_l", "foot_r"]:
		var y := sk.get_bone_global_rest(sk.find_bone(f)).basis.y
		t.ok(y.z > 0.9, "%s points +Z (forward)" % f)
	t.ok(sk.get_bone_global_rest(sk.find_bone("thigh_l")).origin.x > 0, "left leg on +X")
	r.free()


func test_materials(t) -> void:
	var r := _rig()
	var mesh := r.body.mesh
	t.eq(mesh.get_surface_count(), 2, "two surfaces: ink, skin")
	var roles := []
	for i in mesh.get_surface_count():
		var role := BWCharacterRig._role(mesh, i)
		roles.append(role)
		var m := r.body.get_surface_override_material(i) as ShaderMaterial
		t.ok(m != null and m.shader.resource_path == BWCharacterRig.FLAT_SHADER, "%s uses the opaque flat shader" % role)
		var ol := m.next_pass as ShaderMaterial if m else null
		t.ok(ol != null and ol.shader.resource_path == "res://shaders/outline.gdshader", "%s has an inverted-hull pass" % role)
		if ol:
			var want := Color.WHITE if role == "ink" else Color.BLACK
			t.ok(Color(ol.get_shader_parameter("color")).is_equal_approx(want), "%s contour colour (D42)" % role)
		t.ok((mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0, "%s has vertex colours" % role)
		var cols: PackedColorArray = mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
		var v := cols[0].v if cols.size() > 0 else -1.0
		t.near(v, 1.0 if role == "skin" else 0.0, 0.01, "%s vertex colour" % role)
	t.ok("ink" in roles and "skin" in roles, "both roles present")
	r.free()


func test_budget_and_actions(t) -> void:
	var r := _rig()
	var tris := r.triangle_count()
	t.ok(tris > 1000 and tris < 3000, "under 3k tris (got %d)" % tris)
	for a in ["rig_idle", "rig_stress"]:
		t.ok(a in r.animations(), "action %s baked" % a)
	r.free()

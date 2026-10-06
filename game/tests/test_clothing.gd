extends RefCounted
## Clothing lane: art/clothing/<id>.glb through BWClothing on a BWCharacterRig.
## Roster coverage, binding to the rig's skeleton, bone names, documented
## extra bones, shading contract, slot handling, budget.
## Deformation quality (no ink through cloth at 120-degree bends, wide
## stance) is measured by build_clothing.py at build time (CLIP lines) and
## shown in design/art/clothing_*.png.

const MAX_TRIS := 1600


func _rig() -> BWCharacterRig:
	var r := BWCharacterRig.new()
	r.build()
	return r


func _glb_skeleton(id: String) -> Array:
	var scene := load(BWClothing.path_for(id)) as PackedScene
	if scene == null:
		return [null, null]
	var inst := scene.instantiate()
	var sk := inst.find_children("*", "Skeleton3D", true, false)
	return [inst, sk[0] if not sk.is_empty() else null]


func test_roster_garments_exist(t) -> void:
	var rows := BWData.table("roster")
	t.ok(rows.size() > 0, "roster loaded")
	for row in rows:
		for col in ["top", "bottom"]:
			var id := str(row.get(col, ""))
			t.ok(BWClothing.slot_of(id) == col, "%s: %s '%s' is a known %s" % [row.id, col, id, col])
			t.ok(BWClothing.has_garment(id), "%s: %s.glb exists" % [row.id, id])
		t.ok(BWClothing.SHADES.has(str(row.get("clothing_shade", ""))), "%s: clothing_shade is dark/mid/light" % row.id)


func test_catalogue(t) -> void:
	t.eq(BWClothing.TOPS.size(), 7, "7 tops")
	t.eq(BWClothing.BOTTOMS.size(), 7, "7 bottoms")
	for id in BWClothing.ids():
		t.ok(BWClothing.has_garment(id), "%s.glb present and imported" % id)


func test_bone_names_match_rig(t) -> void:
	var rig := _rig()
	for id in BWClothing.ids():
		var pair := _glb_skeleton(id)
		var inst: Node = pair[0]
		var sk: Skeleton3D = pair[1]
		t.ok(sk != null, "%s has a Skeleton3D" % id)
		if sk == null:
			if inst:
				inst.free()
			continue
		var names := []
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		for b in BWCharacterRig.BONES:
			t.ok(b in names, "%s carries rig bone %s" % [id, b])
			var gi := sk.find_bone(b)
			var ri := rig.skeleton.find_bone(b)
			if gi >= 0 and ri >= 0:
				t.ok(sk.get_bone_global_rest(gi).is_equal_approx(rig.skeleton.get_bone_global_rest(ri)),
					"%s: %s rest matches the rig" % [id, b])
		# no undocumented bones: everything beyond the 20 is a listed extra for this garment
		for n in names:
			if n in BWCharacterRig.BONES:
				continue
			t.ok(BWClothing.EXTRA_BONES.has(n) and id in BWClothing.EXTRA_BONES[n].garments,
				"%s: extra bone '%s' is documented in BWClothing.EXTRA_BONES" % [id, n])
		var expected := BWCharacterRig.BONES.size()
		for n in BWClothing.EXTRA_BONES:
			if id in BWClothing.EXTRA_BONES[n].garments:
				expected += 1
		t.eq(names.size(), expected, "%s bone count" % id)
		inst.free()
	rig.free()


func test_binds_to_rig_skeleton(t) -> void:
	for id in BWClothing.ids():
		var rig := _rig()
		var mi := BWClothing.wear(rig, id, "mid")
		t.ok(mi != null, "%s worn" % id)
		if mi == null:
			rig.free()
			continue
		t.ok(mi.get_parent() == rig.skeleton, "%s lives under the rig's Skeleton3D" % id)
		t.ok(mi.get_node_or_null(mi.skeleton) == rig.skeleton, "%s skin points at the rig's skeleton" % id)
		t.ok(mi.skin != null and mi.skin.get_bind_count() > 0, "%s has skin binds" % id)
		if mi.skin:
			var all_found := true
			for b in mi.skin.get_bind_count():
				var bn := str(mi.skin.get_bind_name(b))
				if rig.skeleton.find_bone(bn) < 0:
					all_found = false
					t.ok(false, "%s bind '%s' not in the rig skeleton" % [id, bn])
			t.ok(all_found, "%s: every bind resolves on the rig" % id)
		t.ok(mi.transform.is_equal_approx(Transform3D.IDENTITY), "%s sits at the skeleton origin" % id)
		t.ok(mi.get_aabb().size.y > 0.1, "%s has geometry" % id)
		rig.free()


func test_extra_bone_added_once(t) -> void:
	var rig := _rig()
	var n0 := rig.skeleton.get_bone_count()
	BWClothing.wear(rig, "sweater_scarf", "light")
	var bi := rig.skeleton.find_bone("scarf_tail")
	t.ok(bi >= 0, "scarf_tail added to the rig skeleton")
	t.eq(rig.skeleton.get_bone_count(), n0 + 1, "exactly one bone appended")
	if bi >= 0:
		t.eq(rig.skeleton.get_bone_name(rig.skeleton.get_bone_parent(bi)), "chest", "scarf_tail hangs from chest")
		t.ok(bi >= BWCharacterRig.BONES.size(), "rig bones keep their indices")
	t.ok(rig.skeleton.get_node_or_null("clothing_scarf_sway") is SkeletonModifier3D, "scarf sway modifier present")
	BWClothing.wear(rig, "sweater_scarf", "dark")
	t.eq(rig.skeleton.get_bone_count(), n0 + 1, "wearing it again adds nothing")
	BWClothing.wear(rig, "tshirt", "dark")
	t.ok(BWClothing.worn(rig).get("top") == "tshirt", "top replaced")
	rig.free()


func test_slots_and_shade(t) -> void:
	var rig := _rig()
	t.ok(BWClothing.dress(rig, "hoodie", "shorts", "dark"), "dress ok")
	t.eq(BWClothing.worn(rig), {"top": "hoodie", "bottom": "shorts"}, "worn")
	var top := BWClothing.garment(rig, "top")
	t.near(float(top.get_instance_shader_parameter("shade")), 0.0, 0.001, "dark -> shade 0")
	BWClothing.wear(rig, "tight_pants", "light")
	t.eq(BWClothing.worn(rig).get("bottom"), "tight_pants", "bottom replaced")
	var n := 0
	for c in rig.skeleton.get_children():
		if str(c.name).begins_with("clothing_bottom"):
			n += 1
	t.eq(n, 1, "one bottom at a time")
	BWClothing.set_shade(rig, "mid")
	t.near(float(BWClothing.garment(rig, "bottom").get_instance_shader_parameter("shade")), 1.0, 0.001, "set_shade mid")
	BWClothing.remove(rig, "top")
	t.ok(BWClothing.garment(rig, "top") == null, "top removed")
	t.ok(BWClothing.wear(rig, "nope", "mid") == null, "unknown garment refused")
	var row := BWRosterKits.row("kai")
	BWClothing.dress_from_row(rig, row)
	t.eq(BWClothing.worn(rig), {"top": str(row.top), "bottom": str(row.bottom)}, "dress_from_row")
	rig.free()


func test_material_contract(t) -> void:
	var m := BWClothing.material()
	t.ok(m.shader.resource_path == BWClothing.FILL_SHADER, "fill shader")
	var ol := m.next_pass as ShaderMaterial
	t.ok(ol != null and ol.shader.resource_path == BWClothing.OUTLINE_SHADER, "contour next pass")
	var pal := load(BWClothing.PALETTE) as Texture2D
	t.ok(pal != null, "palette texture loads")
	if pal == null:
		return
	var img := pal.get_image()
	t.eq(Vector2i(img.get_width(), img.get_height()), Vector2i(3, 3), "palette is 3x3")
	var fills := []
	for s in 3:
		var fill := img.get_pixel(s, 0)
		var fold := img.get_pixel(s, 1)
		var contour := img.get_pixel(s, 2)
		fills.append(fill.v)
		t.ok(fold.v < fill.v, "fold line darker than fill (shade %d)" % s)
		t.ok(contour.is_equal_approx(BWClothing.contour_for(fill.v)), "contour follows the value rule (shade %d)" % s)
	t.ok(fills[0] < fills[1] and fills[1] < fills[2], "dark < mid < light")
	t.near(fills[0], BWLook.GREY_DARK.v, 0.01, "dark matches BWLook")
	t.near(fills[2], BWLook.GREY_LIGHT.v, 0.01, "light matches BWLook")


func test_mesh_contract_and_budget(t) -> void:
	for id in BWClothing.ids():
		var rig := _rig()
		var mi := BWClothing.wear(rig, id)
		if mi == null:
			t.ok(false, "%s worn" % id)
			rig.free()
			continue
		var tris := 0
		var has_fill := false
		var has_hull := false
		for i in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_array_index_len(i) / 3
			t.ok((mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0, "%s has vertex colours" % id)
			var cols: PackedColorArray = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
			for c in cols:
				has_fill = has_fill or c.r > 0.75
				has_hull = has_hull or c.g > 0.5
			t.ok(mi.get_surface_override_material(i) == BWClothing.material(), "%s uses the shared clothing material" % id)
		t.eq(mi.mesh.get_surface_count(), 1, "%s is one surface (one material)" % id)
		t.ok(has_fill and has_hull, "%s has fill and contour channels" % id)
		t.ok(tris > 100 and tris <= MAX_TRIS, "%s within budget (%d tris)" % [id, tris])
		rig.free()

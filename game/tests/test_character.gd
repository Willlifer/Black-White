extends RefCounted
## Character lane: BWCharacter assembly (rig + hair + clothes + armour +
## weapon), the layering rules, the pose solver, BWUnitView's swap-in and its
## primitive fallback. Visual quality is checked by eye in
## design/art/roster_turntable_*.png and poses_*.png (tools/character_preview.gd).


func _unit(id: String) -> BWUnit:
	return BWRosterKits.unit(id)


func _item(base: String) -> Dictionary:
	var run := BWRun.start([], 11)
	return run.make_item(base, "E")


func test_every_roster_row_builds(t) -> void:
	var rows := BWData.table("roster")
	t.eq(rows.size(), 20, "20 roster rows")
	for row in rows:
		var u := BWUnit.from_roster(row)
		var c := BWCharacter.create(u)
		t.ok(c.rig != null and c.rig.skeleton != null, "%s: rig built" % row.id)
		t.ok(c.part("hair") is BWHair and str((c.part("hair") as BWHair).style) == str(row.hair_style), "%s: hair %s" % [row.id, row.hair_style])
		var top := c.part("top")
		var bottom := c.part("bottom")
		t.ok(top != null and str(top.get_meta("clothing_id")) == str(row.top), "%s: top %s" % [row.id, row.top])
		t.ok(bottom != null and str(bottom.get_meta("clothing_id")) == str(row.bottom), "%s: bottom %s" % [row.id, row.bottom])
		t.eq(str(top.get_meta("clothing_shade", "")), str(row.clothing_shade), "%s: shade" % row.id)
		var w := c.part("weapon") as BWWeaponView
		t.ok(w != null and w.weapon_id == str(row.weapon_model), "%s: weapon %s" % [row.id, row.weapon_model])
		if w:
			var sock := str(w.get_parent().name) if w.get_parent() else ""
			var want := "socket_offhand_l" if row.weapon_class == "bow" else "socket_weapon_r"
			t.eq(sock, want, "%s: weapon on %s" % [row.id, want])
			if row.weapon_class == "daggers":
				t.ok(c.part("offhand") != null and str(c.part("offhand").get_parent().name) == "socket_offhand_l", "%s: daggers paired" % row.id)
		t.ok((c.part("hair") as BWHair).color.is_equal_approx(BWLook.element_color(str(row.element))), "%s: hair coloured by element" % row.id)
		t.ok(c.triangle_count() < 12000, "%s: triangle budget (%d)" % [row.id, c.triangle_count()])
		c.free()


func test_leg_armour_hides_bottom_and_restores(t) -> void:
	var u := _unit("aureli")         # baggy_sweatpants
	var c := BWCharacter.create(u)
	t.ok(c.part("bottom").visible, "bottom visible before")
	for piece in ["platelegs", "tights", "robe_bottoms"]:
		u.equipment["legs"] = _item(piece)
		c.refresh_equipment()
		t.ok(c.part("legs") != null, "%s equipped" % piece)
		t.ok(not c.part("bottom").visible, "%s hides the baggy pants" % piece)
		t.eq(str(c.part("bottom").get_meta("clothing_id")), "baggy_sweatpants", "%s: bottom hidden, not deleted" % piece)
	u.equipment.erase("legs")
	c.refresh_equipment()
	t.ok(c.part("legs") == null, "legs unequipped")
	t.ok(c.part("bottom").visible, "bottom visible again")
	# chaps leave the seat open: a snug short goes under them
	u.equipment["legs"] = _item("chaps")
	c.refresh_equipment()
	t.eq(str(c.part("bottom").get_meta("clothing_id")), BWCharacter.UNDER_CHAPS, "chaps: snug short underneath")
	u.equipment.erase("legs")
	c.refresh_equipment()
	t.eq(str(c.part("bottom").get_meta("clothing_id")), "baggy_sweatpants", "chaps off: original bottom back")
	# tassets hang over the pants
	u.equipment["legs"] = _item("leather_tassets")
	c.refresh_equipment()
	t.ok(c.part("bottom").visible, "tassets layer over the bottom")
	c.free()


func test_chest_armour_trims_top_and_restores(t) -> void:
	var u := _unit("kai")                 # hoodie
	var c := BWCharacter.create(u)
	var full: Mesh = (c.part("top") as MeshInstance3D).mesh
	u.equipment["chest"] = _item("leather_cuirass")
	c.refresh_equipment()
	var top := c.part("top") as MeshInstance3D
	t.eq(str(c.layering.top), "sleeves", "cuirass trims the hoodie to its sleeves")
	t.ok(top.visible and top.mesh != full, "top shows a trimmed mesh")
	t.ok(top.mesh.get_surface_count() > 0 and top.mesh.surface_get_array_index_len(0) < full.surface_get_array_index_len(0), "sleeves are a subset")
	u.equipment["chest"] = _item("silken_robe")
	c.refresh_equipment()
	t.ok(not c.part("top").visible, "robe (covers arms) hides the top")
	u.equipment["chest"] = _item("vest")
	c.refresh_equipment()
	t.ok(c.part("top").visible and (c.part("top") as MeshInstance3D).mesh == full, "vest is open: full top under it")
	u.equipment.erase("chest")
	c.refresh_equipment()
	t.ok((c.part("top") as MeshInstance3D).mesh == full and c.part("top").visible, "top restored")
	# a second character shares the trimmed sleeves mesh
	var u2 := _unit("alexandra")                # hoodie too
	u2.equipment["chest"] = _item("leather_cuirass")
	u.equipment["chest"] = _item("leather_cuirass")
	c.refresh_equipment()
	var c2 := BWCharacter.create(u2)
	t.ok((c.part("top") as MeshInstance3D).mesh == (c2.part("top") as MeshInstance3D).mesh, "trimmed meshes are shared")
	c.free()
	c2.free()


func test_scarf_and_robe_swaps(t) -> void:
	var u := _unit("apollyon")          # sweater_scarf, tight_pants
	var c := BWCharacter.create(u)
	u.equipment["chest"] = _item("scarf")
	c.refresh_equipment()
	t.eq(str(c.part("top").get_meta("clothing_id")), "sweater", "scarf piece replaces the sweater's own scarf")
	u.equipment.erase("chest")
	c.refresh_equipment()
	t.eq(str(c.part("top").get_meta("clothing_id")), "sweater_scarf", "scarf off: sweater_scarf back")
	c.free()
	var v := _unit("demeter")            # baggy_sweatpants
	var d := BWCharacter.create(v)
	v.equipment["chest"] = _item("silken_robe")
	d.refresh_equipment()
	t.eq(str(d.part("bottom").get_meta("clothing_id")), "sweatpants", "robe skirt: baggy pants slimmed")
	t.ok(d.poser.stride < 1.0, "robe narrows the stance")
	d.free()


func test_hair_modes(t) -> void:
	var u := _unit("demeter")            # long_hair
	var c := BWCharacter.create(u)
	u.equipment["head"] = _item("feathered_full_helm")
	c.refresh_equipment()
	t.ok(c.part("hair").visible, "D490: full helm shows hair")
	u.equipment["head"] = _item("crown")
	c.refresh_equipment()
	t.ok(c.part("hair").visible, "crown shows hair")
	u.equipment.erase("head")
	c.refresh_equipment()
	t.ok(c.part("hair").visible, "hair back without a hat")
	t.ok(c.layering.hair_push >= 0.0 and c.layering.hair_push <= 0.6, "hair push measured and clamped")
	c.free()


func test_boss_default_look(t) -> void:
	var run := BWRun.start([], 5)
	var b := run.make_boss()
	var look := BWCharacter.look_for(b)
	t.eq(str(look.hair_style), "buzzed", "boss buzzed")
	t.eq(str(look.element), "dark", "boss dark")
	t.eq(str(look.weapon), "anchor", "boss anchor")
	var c := BWCharacter.create(b)
	t.eq(str(c.equipment.equipped().get("chest", "")), "platemail", "boss platemail")
	t.eq(str(c.equipment.equipped().get("legs", "")), "platelegs", "boss platelegs")
	t.ok(not b.equipment.has("chest"), "default armour is visual only")
	c.free()


func test_enemies_carry_cosmetics(t) -> void:
	var run := BWRun.start(["aureli", "della", "jericho", "will", "gail", "kira"], 9)
	for u in run.enemies_for(4):
		t.ok(u.cosmetics.has("hair_style") and u.cosmetics.has("top"), "%s carries roster cosmetics" % u.id)
		var c := BWCharacter.create(u)
		t.eq(str((c.part("hair") as BWHair).style), str(u.cosmetics.hair_style), "%s hair" % u.id)
		t.eq(c.weapon.weapon_id, str(u.equipment.main_hand.base), "%s weapon = equipped main hand" % u.id)
		for slot in ["head", "chest", "legs"]:
			if u.equipment.has(slot):
				t.eq(str(c.equipment.equipped().get(slot, "")), str(u.equipment[slot].base), "%s wears its %s" % [u.id, slot])
		c.free()


func test_poses_hold_weapons(t) -> void:
	for id in ["stryker", "della", "aureli", "rui", "jericho", "will", "gail", "sala", "dragtol"]:
		var u := _unit(id)
		var c := BWCharacter.create(u)
		for p in BWCharacterPose.POSE_NAMES:
			c.pose(p, 0.0)
			var pose := BWCharacterPose.resolve(p, c.weapon_style())
			# feet: ankles on their authored targets (unless out of reach)
			for s in ["l", "r"]:
				var ank := (c.poser.globals["foot_" + s] as Transform3D).origin
				t.ok(ank.y > 0.02 and ank.y < 0.35, "%s %s: ankle %s above the floor (%.3f)" % [id, p, s, ank.y])
			# two-handers and bows: the second hand is on its point
			var w := c.weapon
			var hold := w.second_hand()
			if c.has_clip(p):
				pose = c.animator.last_pose       # a clip's own frame (e.g. stricken lets go)
			var grip_l := float((pose.hand_l as Dictionary).get("grip", 0.0))
			var grip_r := float((pose.hand_r as Dictionary).get("grip", 0.0))
			if hold == "l" and grip_l > 0.5:
				var sock := (c.poser.globals.hand_r as Transform3D) * c.poser.socket_r
				var want := sock * BWWeaponView.v3(w.meta.second_hand.point)
				var hand := (c.poser.globals.hand_l as Transform3D)
				var fist := hand.origin + hand.basis.y.normalized() * 0.03
				t.ok(fist.distance_to(want) < 0.08, "%s %s: left fist on the grip (%.3f)" % [id, p, fist.distance_to(want)])
			if hold == "r" and grip_r > 0.5:
				var sock := (c.poser.globals.hand_l as Transform3D) * c.poser.socket_l
				var want := sock * BWWeaponView.v3(w.meta.second_hand.point)
				var hand := (c.poser.globals.hand_r as Transform3D)
				t.ok(hand.origin.distance_to(want) < 0.08, "%s %s: draw hand on the string" % [id, p])
		c.free()
	# every pose resolves for every style with complete hand specs
	for st in BWCharacterPose.STYLES:
		for p in BWCharacterPose.POSE_NAMES:
			var r := BWCharacterPose.resolve(p, st)
			t.ok((r.hand_r as Dictionary).has("aim") and (r.hand_l as Dictionary).has("pos") and r.has("foot_l"), "%s/%s resolves" % [st, p])


func test_blend_reaches_key(t) -> void:
	# the static key poses (the fallback under the clips)
	BWCharacter.animate = false
	var c := BWCharacter.create(_unit("stryker"))
	BWCharacter.animate = true
	c.pose("idle", 0.0)
	c.pose("strike")
	t.ok(c.poser.is_blending(), "strike blends")
	for i in 10:
		c.poser.update(0.02)
	t.ok(not c.poser.is_blending(), "blend done within 0.2 s")
	t.eq(c.pose_name(), "strike", "pose name")
	c.free()


func test_set_dim_fades_every_part(t) -> void:
	var u := _unit("will")
	u.equipment["head"] = _item("crown")
	u.equipment["chest"] = _item("platemail")
	var c := BWCharacter.create(u)
	c.set_aura("thunder", 1.0)
	BWLook.set_dim(c, 1.0)
	var n := 0
	var bad: PackedStringArray = []
	for g in c.find_children("*", "GeometryInstance3D", true, false):
		n += 1
		if float((g as GeometryInstance3D).get_instance_shader_parameter("dim")) < 0.99:
			bad.append(str(g.name))
	t.ok(n > 8, "parts found (%d)" % n)
	t.ok(bad.is_empty(), "every geometry dimmed: %s" % ", ".join(bad))
	var parts := c.find_children("aura_particles", "CPUParticles3D", true, false)
	t.ok(not parts.is_empty(), "aura particles present")
	for p in parts:
		var q := (p as CPUParticles3D).mesh
		t.ok(q.surface_get_material(0) is ShaderMaterial, "aura particles use a dim-aware shader")
	c.free()


func test_shared_resources(t) -> void:
	var a := BWCharacter.create(_unit("stryker"))
	var b := BWCharacter.create(_unit("rui"))
	t.ok(a.rig.body.mesh == b.rig.body.mesh, "body mesh shared")
	t.ok(a.rig.body.get_surface_override_material(0) == b.rig.body.get_surface_override_material(0), "body material shared")
	t.ok((a.part("top") as MeshInstance3D).get_surface_override_material(0) == (b.part("top") as MeshInstance3D).get_surface_override_material(0), "clothing material shared")
	# D146: hair materials are shared per look (affinity ranks), so give b a's ranks
	b.unit.affinity = a.unit.affinity.duplicate()
	b.unit.focus_element = a.unit.focus_element
	b.unit.element = a.unit.element
	b.refresh_hair()
	var h1 := (a.part("hair") as BWHair).meshes[0]
	var h2 := (b.part("hair") as BWHair).meshes[0]
	t.ok(h1.get_surface_override_material(0) == h2.get_surface_override_material(0), "hair material shared")
	a.free()
	b.free()


func test_unit_view_api_and_fallback(t) -> void:
	var u := _unit("gail")
	var v := BWUnitView.new()
	v.setup(u)
	t.ok(v.character != null, "rig view builds a BWCharacter")
	for p in BWCharacterPose.POSE_NAMES:
		v.pose_named(p)
		t.eq(v.character.pose_name(), p, "pose_named(%s)" % p)
	v.idle()
	t.eq(v.character.pose_name(), "idle", "idle()")
	v.show_label(false)
	v.refresh()
	u.equipment["chest"] = _item("vest")
	v.refresh()
	t.eq(str(v.character.equipment.equipped().get("chest", "")), "vest", "refresh() notices new gear")
	v.free()
	BWUnitView.use_rig = false
	var f := BWUnitView.new()
	f.setup(_unit("gail"))
	t.ok(f.character == null and f.find_children("*", "BWCharacterRig", true, false).is_empty(), "use_rig=false builds the primitive")
	f.pose_named("strike")
	f.idle()
	f.free()
	BWUnitView.use_rig = true
	var run := BWRun.start([], 2)
	var boss := BWUnitView.new()
	boss.setup(run.make_boss())
	t.near(boss.scale.y, 2.6, 0.001, "boss scaled x2.6")
	boss.free()

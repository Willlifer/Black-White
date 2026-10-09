extends RefCounted
## Armour models (tools/blender/build_equipment.py) through BWEquipmentView:
## every armour id in equipment.csv has a glb + manifest row, slots match,
## each piece attaches to the rig (socket or rebound skin), skinned pieces
## only use rig bone names, and the accent follows the enchantment element.

const ARMOUR_SLOTS := ["head", "chest", "legs"]


func _armour_rows() -> Array:
	var out: Array = []
	for r in BWData.table("equipment"):
		if str(r.slot) in ARMOUR_SLOTS:
			out.append(r)
	return out


func _rig() -> BWCharacterRig:
	var r := BWCharacterRig.new()
	r.build()
	return r


func _enchant_for(element: String) -> String:
	for e in BWData.table("enchantments"):
		if str(e.get("element", "")) == element:
			return str(e.id)
	return ""


func test_every_armour_id_has_a_model(t) -> void:
	var rows := _armour_rows()
	t.eq(rows.size(), 23, "23 armour pieces in equipment.csv")
	for r in rows:
		var id := str(r.id)
		t.ok(ResourceLoader.exists(BWEquipmentView.model_path(id)), "%s.glb exists" % id)
		var info := BWEquipmentView.info(id)
		t.ok(not info.is_empty(), "%s has a manifest row" % id)
		t.eq(str(info.get("slot", "")), str(r.slot), "%s slot matches the CSV" % id)
		t.ok(str(info.get("attach", "")) in ["socket", "skinned"], "%s attach type" % id)
	t.eq(BWEquipmentView.model_ids().size(), rows.size(), "no model without a CSV row")


func test_manifest_contract(t) -> void:
	for id in BWEquipmentView.model_ids():
		var info := BWEquipmentView.info(id)
		if str(info.slot) == "head":
			t.eq(str(info.socket), "socket_hat", "%s rides socket_hat" % id)
			t.ok(str(info.hair_mode) in BWEquipmentView.HAIR_MODES, "%s hair_mode is show/hide_top/hide_all" % id)
		if info.attach == "socket":
			t.ok(BWCharacterRig.SOCKETS.has(str(info.socket)), "%s socket %s exists on the rig" % [id, info.socket])
		var share := float(info.accent_share)
		t.ok(share > 0.04 and share < 0.6, "%s accent share %.2f is a splash" % [id, share])
		t.ok(int(info.tris) > 40 and int(info.tris) < 1200, "%s budget (%d tris)" % [id, int(info.tris)])
		for b in info.bones:
			t.ok(b in BWCharacterRig.BONES, "%s bone %s is a rig bone" % [id, b])


func test_attaches_to_rig(t) -> void:
	var r := _rig()
	var eq := BWEquipmentView.for_rig(r)
	for id in BWEquipmentView.model_ids():
		var info := BWEquipmentView.info(id)
		var n := eq.equip({ "base": id, "slot": str(info.slot), "enchant": "" })
		t.ok(n != null, "%s equips" % id)
		if n == null:
			continue
		t.ok(eq.piece(str(info.slot)) == n, "%s occupies %s" % [id, info.slot])
		if info.attach == "socket":
			t.ok(n.get_parent() == r.socket(str(info.socket)), "%s hangs on %s" % [id, info.socket])
		else:
			var mi := n as MeshInstance3D
			t.ok(mi != null and mi.get_parent() == r.skeleton, "%s rebound under the rig skeleton" % id)
			t.eq(str(mi.skeleton) if mi else "", "..", "%s points at the rig Skeleton3D" % id)
			t.ok(mi != null and mi.skin != null and mi.skin.get_bind_count() > 0, "%s keeps its skin" % id)
			if mi and mi.skin:
				for b in mi.skin.get_bind_count():
					var bn := str(mi.skin.get_bind_name(b))
					t.ok(bn in BWCharacterRig.BONES, "%s bind %s is a rig bone" % [id, bn])
		var roles := []
		for mi2 in BWEquipmentView.meshes_of(n):
			for i in mi2.mesh.get_surface_count():
				roles.append(BWEquipmentView.surface_role(mi2.mesh, i))
				var m := mi2.get_surface_override_material(i) as ShaderMaterial
				t.ok(m != null and m.shader.resource_path == BWEquipmentView.SHADER, "%s surface %d uses the equipment shader" % [id, i])
				t.ok(m != null and m.next_pass != null, "%s surface %d has a hull outline" % [id, i])
				t.ok((mi2.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0, "%s surface %d has facet colours" % [id, i])
		t.ok("armour" in roles and "accent" in roles, "%s has armour + accent surfaces" % id)
	# one piece per slot, wherever it hangs
	t.eq(eq.equipped().size(), 3, "head, chest and legs each hold one piece")
	t.eq(r.socket("hat").get_child_count(), 1, "re-equipping the head replaced the old hat")
	eq.clear()
	t.eq(eq.equipped().size(), 0, "clear empties every slot")
	t.eq(r.socket("hat").get_child_count(), 0, "clear removed the hat node")
	r.free()


func test_accent_follows_enchantment(t) -> void:
	var r := _rig()
	var eq := BWEquipmentView.for_rig(r)
	var fire := _enchant_for("fire")
	t.ok(fire != "", "a fire enchantment exists")
	for id in ["feathered_cap", "platemail", "tights"]:
		var slot := str(BWEquipmentView.info(id).slot)
		var n := eq.equip({ "base": id, "slot": slot, "enchant": fire })
		t.eq(str(n.get_meta("equip_element")), "fire", "%s of fire" % id)
		t.ok(_accent(n).is_equal_approx(BWLook.element_color("fire")), "%s accent is the fire colour" % id)
		n = eq.equip({ "base": id, "slot": slot, "enchant": "" })
		t.ok(_accent(n).is_equal_approx(BWEquipmentView.NEUTRAL), "plain %s accent is neutral grey" % id)
	var water := _enchant_for("water")
	eq.set_element("legs", "water")
	t.ok(_accent(eq.piece("legs")).is_equal_approx(BWLook.element_color("water")), "set_element retints in place")
	t.ok(water != "", "a water enchantment exists")
	# a wrong slot is refused
	t.ok(eq.equip({ "base": "crown", "slot": "chest", "enchant": "" }) == null, "slot mismatch refused")
	t.ok(eq.equip({ "base": "sword", "slot": "main_hand", "enchant": "" }) == null, "weapons are not armour models")
	r.free()


func test_hair_mode(t) -> void:
	var r := _rig()
	var eq := BWEquipmentView.for_rig(r)
	var hair := Node3D.new()
	r.attach(hair, "hair")
	eq.equip_model("tiara")
	t.ok(hair.visible, "tiara shows hair")
	eq.equip_model("feathered_full_helm")
	t.eq(eq.hair_mode(), "show", "D490: even a full helm shows hair")
	t.ok(hair.visible, "hair stays visible under the helm")
	eq.unequip("head")
	t.ok(hair.visible, "hair visible with the helm off")
	r.free()
	if BWEquipmentView.HATS_SHOW_HAIR:
		return                       # D490: the D228 hide_top check below only applies when hiding is on
	# hide_top against real hair: a buzz fits under the cap, a mohawk doesn't
	if ResourceLoader.exists("res://art/hair/buzzed.glb") and ResourceLoader.exists("res://art/hair/short_mohawk.glb"):
		for pair in [["buzzed", true], ["short_mohawk", false]]:
			var r2 := _rig()
			var eq2 := BWEquipmentView.for_rig(r2)
			var h = load("res://src/game/character/hair.gd").create(pair[0], "fire")
			h.attach_to(r2)
			eq2.equip_model("baseball_cap")
			t.eq(h.visible, pair[1], "%s under a baseball cap: visible=%s (rise %.3f, clearance %.3f)" % [
				pair[0], pair[1], BWEquipmentView.hair_rise(h), eq2.hair_clearance()])
			r2.free()


func _accent(n: Node) -> Color:
	for mi in BWEquipmentView.meshes_of(n):
		for i in mi.mesh.get_surface_count():
			if BWEquipmentView.surface_role(mi.mesh, i) == "accent":
				var m := mi.get_surface_override_material(i) as ShaderMaterial
				return Color(m.get_shader_parameter("paint"))
	return Color(0, 0, 0, 0)

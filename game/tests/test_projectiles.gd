extends RefCounted
## Projectiles (design/art/WEAPON_MODELS.md, "Projectiles"): the three
## models from tools/blender/build_projectiles.py through BWProjectileView,
## their sidecar, the weapon classes that shoot them, the bows' drawable
## strings, and BWProjectileFlight (arrow arc + stick, bullet straight,
## bolt aura) stepped by hand.

const DT := 1.0 / 60.0


func test_metadata_and_models(t) -> void:
	var m := BWProjectileView.load_projectile_meta(true)
	t.eq(int(m.get("version", 0)), BWProjectileView.PROJ_VERSION, "projectiles.json version")
	var ids := BWProjectileView.projectile_ids()
	for id in ["arrow", "bullet", "bolt"]:
		t.ok(id in ids, "%s in projectiles.json" % id)
		var p := BWProjectileView.create_projectile(id)
		t.ok(p != null, "%s builds" % id)
		if p == null:
			continue
		var tris := p.triangle_count()
		t.ok(tris >= 20 and tris <= 200, "%s within 200 tris (got %d)" % [id, tris])
		t.eq(tris, int(p.meta.tris), "%s tris match the build report" % id)
		var roles := []
		for mi in p.meshes():
			for i in mi.mesh.get_surface_count():
				roles.append(BWWeaponView.surface_role(mi.mesh, i))
				var mat := mi.get_surface_override_material(i) as ShaderMaterial
				t.ok(mat != null and mat.shader.resource_path == BWWeaponView.FILL_SHADER, "%s uses the weapon shader" % id)
				var ol := mat.next_pass as ShaderMaterial if mat else null
				t.ok(ol != null and Color(ol.get_shader_parameter("color")).is_equal_approx(Color.BLACK), "%s has a black hull" % id)
		t.ok("body" in roles and "accent" in roles, "%s has body and accent surfaces" % id)
		var tip := BWWeaponView.v3(p.meta.tip)
		var tail := BWWeaponView.v3(p.meta.tail)
		t.ok(tip.z > tail.z + 0.2, "%s flies along +Z (tip ahead of tail)" % id)
		t.ok(absf(tip.x) < 1e-3 and absf(tip.y) < 1e-3, "%s is on its flight axis" % id)
		t.ok((p.meta.aura_points as Array).size() >= 3, "%s has aura anchors" % id)
		p.set_accent("fire")
		p.set_aura("ice", 1.0)
		t.ok(p.has_aura(), "%s takes the aura" % id)
		p.free()
	t.eq(BWProjectileView.projectile_meta("arrow").tip, [0.0, 0.0, 0.0], "the arrow's origin is its tip (it sticks there)")


func test_weapons_shoot_them(t) -> void:
	for id in BWWeaponView.ids():
		var m := BWWeaponView.meta_for(id)
		var want: Variant = BWProjectileView.FOR_CLASS.get(str(m.get("class", "")))
		t.eq(m.get("projectile"), want, "%s shoots %s" % [id, want])
		if str(m.hands) == "bow":
			t.ok(m.get("string") is Array and (m.string as Array).size() == 2, "%s has string ends" % id)
			var w := BWWeaponView.create(id)
			var found := false
			for mi in w.meshes():
				for i in mi.mesh.get_surface_count():
					found = found or BWWeaponView._is_string_surface(mi.mesh, i)
			t.ok(found, "%s has a string surface" % id)
			w.set_string_draw(Vector3(0, 0.0, -0.5))
			t.ok(w._string_bent and w._string_segs.size() == 2, "%s bends its string" % id)
			w.set_string_draw(null)
			t.ok(not w._string_bent and not w._string_segs[0].visible, "%s straightens it" % id)
			w.free()


func test_flights(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var target := Node3D.new()
	holder.add_child(target)
	target.position = Vector3(0, 0, 5)
	t.eq(BWProjectileFlight.kind_for("bow", false), "arrow", "bows shoot arrows")
	t.eq(BWProjectileFlight.kind_for("pistols", false), "bullet", "pistols shoot bullets")
	t.eq(BWProjectileFlight.kind_for("bow", true), "bolt", "spells are bolts")
	# arrow: arcs above the straight line, faces its velocity, sticks, frees
	var a := BWProjectileFlight.launch(holder, "arrow", Vector3(0, 1.2, 0), target, "fire", true)
	a.manual = true
	var peak := 0.0
	var aligned := true
	var prev := a.global_position
	var steps := int(ceil(a.duration / DT))
	for i in steps:
		a.advance(DT)
		peak = maxf(peak, a.global_position.y - 1.15)
		var v := a.global_position - prev
		if v.length() > 1e-3 and i > 0 and i < steps - 1:
			aligned = aligned and a.global_basis.z.normalized().dot(v.normalized()) > 0.97
		prev = a.global_position
	t.ok(peak > 0.15, "the arrow arcs (%.2f above the line)" % peak)
	t.ok(aligned, "the arrow points along its flight")
	t.eq(a._phase, "stick", "a hit arrow sticks")
	for i in int((BWProjectileFlight.STICK_TIME + BWProjectileFlight.SHRINK_TIME) / DT) + 4:
		a.advance(DT)
	t.eq(a._phase, "done", "then shrinks away")
	# bullet: straight and fast, a muzzle flash
	var b := BWProjectileFlight.launch(holder, "bullet", Vector3(0, 1.2, 0), target, "thunder", true)
	b.manual = true
	t.ok(b.duration < 0.2, "the bullet is fast (%.3f s)" % b.duration)
	t.eq(b._flashes.size(), 1, "a muzzle flash on the shot")
	var dev := 0.0
	for i in int(ceil(b.duration / DT)):
		b.advance(DT)
		dev = maxf(dev, absf(b.global_position.y - lerpf(1.2, 1.1, b.t)))
	t.ok(dev < 0.06, "the bullet flies straight (%.3f)" % dev)
	# bolt: the aura and a spin
	var c := BWProjectileFlight.launch(holder, "bolt", Vector3(0, 1.2, 0), target, "ice", true)
	c.manual = true
	t.ok(c.model.has_aura(), "the bolt wears the element aura")
	c.advance(DT * 3)
	t.ok(c._spin > 0.0, "the bolt spins")
	# a miss flies on past the target
	var m := BWProjectileFlight.launch(holder, "arrow", Vector3(0, 1.2, 0), target, "", false)
	t.ok(m._to.z > 5.5, "a miss aims past the target")
	holder.queue_free()

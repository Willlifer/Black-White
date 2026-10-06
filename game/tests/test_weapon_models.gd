extends RefCounted
## Weapon models: art/weapons/<id>.glb + weapons.json through BWWeaponView.
## Every main_hand item has a model and metadata, classes match the data,
## each weapon lands on the right socket, aura on/off, budget.

const HANDS := ["one", "two", "pair", "bow", "fists"]
const FISTS := ["hand_wraps", "brass_knuckles", "gauntlets"]
const TWO_HANDED := ["lance", "halberd", "glaive", "staff", "moon_staff", "warhammer", "anchor", "double_axe", "flamberge"]


func _main_hand() -> Array:
	var out := []
	for row in BWData.table("equipment"):
		if str(row.get("slot")) == "main_hand":
			out.append(row)
	return out


func _rig() -> BWCharacterRig:
	var r := BWCharacterRig.new()
	r.build()
	return r


func test_metadata_file(t) -> void:
	var m := BWWeaponView.load_meta(true)
	t.eq(int(m.get("version", 0)), BWWeaponView.META_VERSION, "weapons.json version")
	t.eq(int(m.get("rig_version", 0)), BWCharacterRig.RIG_VERSION, "fitted to the current rig version")
	t.eq(BWWeaponView.ids().size(), 25, "25 weapon models (22 + 3 fists, D76)")


func test_every_main_hand_has_model(t) -> void:
	var rows := _main_hand()
	t.eq(rows.size(), 25, "25 main_hand rows in equipment.csv")
	for row in rows:
		var id := str(row.id)
		var m := BWWeaponView.meta_for(id)
		t.ok(not m.is_empty(), "%s has metadata" % id)
		t.ok(ResourceLoader.exists("res://art/weapons/%s.glb" % id), "%s.glb imported" % id)
		# the equipment `weight` column holds the weapon class for main_hand rows
		t.eq(str(m.get("class", "")), str(row.weight), "%s class matches equipment.csv" % id)
		t.ok(BWData.has_table("weapons") and not BWData.row("weapons", str(m.get("class", ""))).is_empty(),
			"%s class is a weapons.csv row" % id)
		t.ok(str(m.get("hands")) in HANDS, "%s hands is known" % id)


func test_metadata_points(t) -> void:
	for id in BWWeaponView.ids():
		var m := BWWeaponView.meta_for(id)
		var tip := BWWeaponView.v3(m.tip)
		var base := BWWeaponView.v3(m.trail_base)
		# bows: the tip is the arrow rest, just ahead of the grip by design
		# bows: the tip is the arrow rest; fists: the knuckle face, a fist's width out
		t.ok(tip.length() > (0.04 if m.hands in ["bow", "fists"] else 0.2), "%s tip away from the grip" % id)
		t.ok(tip.distance_to(base) > (0.15 if m.hands != "fists" else 0.12), "%s trail has length" % id)
		t.ok(m.aura_points.size() >= 3, "%s has aura anchors" % id)
		var lo := BWWeaponView.v3(m.aabb.min) - Vector3.ONE * 0.05
		var hi := BWWeaponView.v3(m.aabb.max) + Vector3.ONE * 0.05
		var inside := func(p: Vector3) -> bool: return p.x >= lo.x and p.y >= lo.y and p.z >= lo.z and p.x <= hi.x and p.y <= hi.y and p.z <= hi.z
		t.ok(inside.call(tip), "%s tip inside the model bounds" % id)
		for p in m.aura_points:
			t.ok(inside.call(BWWeaponView.v3(p)), "%s aura point inside the bounds" % id)
		var hands := str(m.hands)
		var sh: Variant = m.get("second_hand")
		if id in TWO_HANDED:
			t.eq(hands, "two", "%s is two-handed" % id)
		if hands == "two":
			t.ok(sh is Dictionary and sh.hand == "l", "%s has a left-hand target" % id)
		elif hands == "bow":
			t.ok(sh is Dictionary and sh.hand == "r", "%s has a draw-hand target" % id)
			t.eq(str(m.socket), "socket_offhand_l", "%s is held in the left hand" % id)
		else:
			t.ok(sh == null, "%s has no second hand" % id)
		if hands in ["pair", "fists"]:
			t.eq(str(m.offhand_socket), "socket_offhand_l", "%s pairs onto the off hand" % id)
		if hands == "fists":
			t.ok(id in FISTS, "%s is one of the three fists" % id)
			t.ok(m.get("mirror_offhand", false) == true and ResourceLoader.exists(str(m.get("offhand_glb", ""))),
				"%s has its mirrored left piece" % id)


func test_models_and_budget(t) -> void:
	for id in BWWeaponView.ids():
		var w := BWWeaponView.create(id)
		t.ok(w != null, "%s builds" % id)
		if w == null:
			continue
		var tris := w.triangle_count()
		t.ok(tris >= 40 and tris <= 600, "%s within 600 tris (got %d)" % [id, tris])
		t.eq(tris, int(w.meta.tris), "%s tris match the build report" % id)
		var roles := []
		for mi in w.meshes():
			for i in mi.mesh.get_surface_count():
				var role := BWWeaponView.surface_role(mi.mesh, i)
				roles.append(role)
				var mat := mi.get_surface_override_material(i) as ShaderMaterial
				t.ok(mat != null and mat.shader.resource_path == BWWeaponView.FILL_SHADER, "%s %s uses the weapon shader" % [id, role])
				var ol := mat.next_pass as ShaderMaterial if mat else null
				t.ok(ol != null and Color(ol.get_shader_parameter("color")).is_equal_approx(Color.BLACK), "%s %s has a black hull (D42)" % [id, role])
				t.ok((mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0, "%s %s has vertex colours" % [id, role])
		t.ok("body" in roles and "accent" in roles, "%s has body and accent surfaces" % id)
		# grip at the origin: the model straddles it, blade/shaft along +Y
		var box := AABB()
		var first := true
		for mi in w.meshes():
			box = mi.get_aabb() if first else box.merge(mi.get_aabb())
			first = false
		t.ok(box.has_point(Vector3.ZERO) or box.grow(0.05).has_point(Vector3.ZERO), "%s grip origin inside the model" % id)
		w.free()


func test_attach_to_rig(t) -> void:
	var r := _rig()
	for id in BWWeaponView.ids():
		var w := BWWeaponView.create(id)
		t.ok(w.attach_to(r), "%s attaches" % id)
		var want := str(w.meta.socket)
		t.ok(w.get_parent() == r.socket(want), "%s rides on %s" % [id, want])
		t.ok(w.transform.is_equal_approx(Transform3D.IDENTITY), "%s mount is identity (socket frame)" % id)
		# rest placement: the grip sits on the fist, the tip above it
		var rest := r.socket_rest(want) * w.transform
		var tip := rest * w.tip_local()
		t.ok(rest.origin.distance_to(r.socket_rest(want).origin) < 0.001, "%s grip on the socket" % id)
		# fists: the knuckles follow the hand, down and out at rest
		t.ok(tip.y > rest.origin.y or w.weapon_class() in ["pistols", "bow", "fists"], "%s tip above the hand at rest" % id)
		if w.hands() in ["pair", "fists"]:
			t.ok(w.offhand_view != null and w.offhand_view.get_parent() == r.socket("offhand_l"), "%s copy on the off hand" % id)
		else:
			t.ok(w.offhand_view == null, "%s has no off-hand copy" % id)
		var sh := w.second_hand_target()
		t.ok((sh != null) == (w.second_hand() != ""), "%s second-hand marker matches metadata" % id)
		w.detach()
		t.ok(w.get_parent() == null and w.offhand_view == null, "%s detaches cleanly" % id)
		w.free()
	for s in ["weapon_r", "offhand_l"]:
		t.eq(r.socket(s).get_child_count(), 0, "%s empty after detaching everything" % s)
	r.free()


func test_aura(t) -> void:
	var r := _rig()
	var w := BWWeaponView.create("dagger")
	w.attach_to(r)
	w.set_aura("fire", 1.0)
	t.ok(w.has_aura(), "aura on")
	var shells := w.find_children("aura_shell", "MeshInstance3D", true, false)
	t.eq(shells.size(), w.meshes().size(), "one shell per mesh, sharing its mesh")
	if not shells.is_empty():
		var sh := shells[0] as MeshInstance3D
		t.ok(sh.mesh == w.meshes()[0].mesh, "shell reuses the weapon mesh (no new geometry)")
		var mat := sh.material_override as ShaderMaterial
		t.ok(mat != null and mat.shader.resource_path == BWWeaponView.AURA_SHADER, "shell uses aura.gdshader")
		var want: Color = BWWeaponView.aura_colors(BWLook.element_color("fire"))[0]
		t.ok(Color(mat.get_shader_parameter("color")).is_equal_approx(want), "shell coloured by BWLook.element_color")
	var parts := w.find_children("aura_particles", "CPUParticles3D", true, false)
	t.eq(parts.size(), 1, "billboard particles")
	if not parts.is_empty():
		t.eq((parts[0] as CPUParticles3D).emission_points.size(), w.meta.aura_points.size(), "particles emit from the aura anchors")
	t.ok(w.offhand_view.has_aura(), "the off-hand dagger glows too")
	w.set_aura("ice", 0.5)
	t.eq(w.aura_element, "ice", "element switch")
	t.eq(w.find_children("aura_particles", "CPUParticles3D", true, false).size(), 1, "switch replaces, not stacks")
	w.set_aura("", 0.0)
	t.ok(not w.has_aura() and not w.offhand_view.has_aura(), "aura off")
	t.eq(w.find_children("aura_*", "", true, false).size(), 0, "aura nodes freed")
	# every element yields readable shell colours
	for e in ["fire", "water", "ice", "thunder", "wind", "dark", "light"]:
		var c: Array = BWWeaponView.aura_colors(BWLook.element_color(e))
		t.ok(c[1].get_luminance() > 0.15, "%s rim lifts off the black sky" % e)
		t.ok(c[0].get_luminance() < 0.75, "%s core holds on white tiles" % e)
	r.free()


func test_unknown_weapon(t) -> void:
	t.ok(BWWeaponView.meta_for("nope").is_empty(), "unknown id has no metadata")
	var w := BWWeaponView.new()
	t.ok(not w.setup("nope"), "setup refuses an unknown id")
	w.free()


## D76: fists are worn on both hands. The right piece rides socket_weapon_r,
## the left is its own MIRRORED mesh on socket_offhand_l (not a copy), its
## points mirrored too; the pieces cover the rig's ink fist; the pose
## solver's fist axes agree with the model's.
func test_fists_pair(t) -> void:
	var r := _rig()
	for id in FISTS:
		var w := BWWeaponView.create(id)
		t.ok(w.attach_to(r), "%s attaches" % id)
		var off := w.offhand_view
		t.ok(off != null and off.get_parent() == r.socket("offhand_l"), "%s: left piece on socket_offhand_l" % id)
		t.ok(w.get_parent() == r.socket("weapon_r"), "%s: right piece on socket_weapon_r" % id)
		if off == null:
			w.free()
			continue
		t.ok(off.is_mirrored() and not w.is_mirrored(), "%s: only the left piece is mirrored" % id)
		var a := _bounds(w)
		var b := _bounds(off)
		t.ok(absf(a.position.x + a.end.x + b.position.x + b.end.x) < 0.002 and a.size.is_equal_approx(b.size),
			"%s: the left mesh is the right one mirrored in x (%s vs %s)" % [id, a, b])
		t.ok(off.tip_local().is_equal_approx(Vector3(-w.tip_local().x, w.tip_local().y, w.tip_local().z)), "%s: mirrored tip" % id)
		t.eq(off.aura_points().size(), w.aura_points().size(), "%s: aura anchors on both hands" % id)
		# covers the ink fist (r 0.043 + its 0.018 white hull): no white rim
		t.ok(a.has_point(Vector3.ZERO) and minf(minf(a.size.x, a.size.y), a.size.z) > 0.11, "%s: fist-sized, round the grip (%s)" % [id, a.size])
		# the pose solver's knuckle axis is the model's (tip direction)
		var k := w.tip_local().normalized()
		t.ok(k.dot(BWCharacterPose.FIST_KNUCKLE_R.normalized()) > 0.97, "%s: knuckles along FIST_KNUCKLE_R (%.3f)" % [id, k.dot(BWCharacterPose.FIST_KNUCKLE_R.normalized())])
		var roles := []
		for mi in off.meshes():
			for i in mi.mesh.get_surface_count():
				roles.append(BWWeaponView.surface_role(mi.mesh, i))
				var mat := mi.get_surface_override_material(i) as ShaderMaterial
				t.ok(mat != null and mat.next_pass != null, "%s left: weapon fill + black hull" % id)
		t.ok("accent" in roles, "%s left: the accent surface the element tints" % id)
		w.set_aura("thunder", 1.0)
		t.ok(off.has_aura(), "%s: both fists glow" % id)
		w.detach()
		t.ok(w.offhand_view == null and r.socket("offhand_l").get_child_count() == 0, "%s detaches both" % id)
		w.free()
	t.eq(BWCharacterPose.style_for(BWWeaponView.meta_for("gauntlets")), "fists", "fists pose style")
	r.free()


func _bounds(w: BWWeaponView) -> AABB:
	var box := AABB()
	var first := true
	for mi in w.meshes():
		box = mi.get_aabb() if first else box.merge(mi.get_aabb())
		first = false
	return box


## D76: the fists static fallback (BWCharacterPose style "fists", no clip
## set yet): every pose holds both fists, the cross drives the right
## knuckles forward, the guard keeps both fists up in front.
func test_fists_static_poses(t) -> void:
	var u := BWRosterKits.unit("della")
	u.weapon_class = "fists"
	u.weapon_model = "gauntlets"
	u.equipment.erase("main_hand")
	# the static keys are the safety fallback under the fists clip set
	# (animation lane, D80): checked with the animator off
	BWCharacter.animate = false
	var c := BWCharacter.create(u)
	BWCharacter.animate = true
	t.ok(c.weapon != null and c.weapon.weapon_id == "gauntlets", "a fists unit wears gauntlets")
	t.eq(c.weapon_style(), "fists", "style fists")
	t.ok(c.animator == null, "animate = false: static key poses (the fallback)")
	t.eq(c.poser.hold_hand, "both", "both hands are weapon hands")
	for p in BWCharacterPose.POSE_NAMES:
		c.pose(p, 0.0)
		var pose := BWCharacterPose.resolve(p, "fists")
		for s in ["r", "l"]:
			var spec: Dictionary = pose["hand_" + s]
			var frame := c.poser.frame_of(pose, str(spec.get("frame", "chest")))
			var want: Vector3 = frame * (spec.pos as Vector3)
			var sock := (c.poser.globals["hand_" + s] as Transform3D) * (c.poser.socket_r if s == "r" else c.poser.socket_l)
			t.ok(sock.origin.distance_to(want) < 0.09, "%s %s: fist on its key (%.3f)" % [p, s, sock.origin.distance_to(want)])
	c.pose("strike", 0.0)
	var sock_r := (c.poser.globals.hand_r as Transform3D) * c.poser.socket_r
	var k := (sock_r.basis * c.weapon.tip_local()).normalized()
	t.ok(k.dot(Vector3(0, 0, 1)) > 0.8, "strike: the right knuckles drive forward (%s)" % k)
	c.pose("idle", 0.0)
	for s in ["r", "l"]:
		var g := (c.poser.globals["hand_" + s] as Transform3D)
		t.ok(g.origin.y > 1.25 and g.origin.z > 0.1, "guard: %s fist up and in front (%s)" % [s, g.origin])
	c.free()


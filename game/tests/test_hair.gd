extends RefCounted
## Hair archetypes: art/hair/<style>.glb through BWHair. Every roster style
## exists, attaches to socket_hair, carries the documented hair bones, has
## both colour slots, keeps the face window clear and stays in budget.

const MAX_TRIS := 4500
## Face window in socket space (head centre origin, +Z forward): nothing in
## front of the face below the fringe line (world 1.95). Matches
## build_hair.py FACE_*.
const FACE_HALF_X := 0.20
const FACE_TOP_Y := 0.03
const FACE_FRONT_Z := 0.12


func test_every_style_has_a_glb(t) -> void:
	for s in BWHair.styles():
		t.ok(ResourceLoader.exists(BWHair.path_for(s)), "%s.glb exists" % s)
		t.ok(BWHair.has_style(s), "has_style(%s)" % s)
	t.eq(BWHair.styles().size(), 10, "ten archetypes")
	t.ok(not BWHair.has_style("afro"), "unknown style is not a style")


func test_roster_styles_covered(t) -> void:
	if not BWData.has_table("roster"):
		t.ok(true, "roster not written yet")
		return
	for row in BWData.table("roster"):
		var s := str(row.hair_style)
		t.ok(BWHair.has_style(s), "%s wears %s, which has a glb" % [row.id, s])


func test_attaches_to_rig(t) -> void:
	var rig := BWCharacterRig.new()
	rig.build()
	var h := BWHair.create("bob", "water")
	t.ok(h != null, "creates")
	t.ok(h.attach_to(rig), "attach_to returns true")
	t.ok(h.get_parent() == rig.socket("hair"), "parented to socket_hair")
	t.ok(h.transform.is_equal_approx(Transform3D.IDENTITY), "sits at the socket origin")
	# swapping replaces, never stacks
	var h2 := BWHair.create("mullet", "fire")
	h2.attach_to(rig)
	var n := 0
	for c in rig.socket("hair").get_children():
		if c is BWHair and not c.is_queued_for_deletion():
			n += 1
	t.eq(n, 1, "one hair per socket after a swap")
	t.ok(h.is_queued_for_deletion(), "the old hair is freed")
	rig.free()


func test_bones_match_doc(t) -> void:
	for s in BWHair.styles():
		var h := BWHair.create(s)
		var want: int = BWHair.TAIL_BONES[s]
		t.eq(h.tail_bone_names().size(), want, "%s has %d hair_tail bones" % [s, want])
		if want > 0:
			t.ok(h.skeleton != null and h.skeleton.find_bone("hair_root") >= 0, "%s has hair_root" % s)
			t.eq(h.skeleton.get_bone_count(), want + 1, "%s: root + tails only" % s)
			for k in want:
				var b := h.skeleton.find_bone("hair_tail_%02d" % (k + 1))
				var parent := "hair_root" if k == 0 else "hair_tail_%02d" % k
				t.eq(h.skeleton.get_bone_name(h.skeleton.get_bone_parent(b)), parent, "%s tail %d chained" % [s, k + 1])
			t.ok(h.set_tail_rotation("hair_tail_01", Vector3(0.3, 0, 0)), "%s tail bone poses" % s)
		else:
			t.ok(h.skeleton == null, "%s is rigid (no skeleton)" % s)
		h.free()


func test_slots_and_colour(t) -> void:
	for s in BWHair.styles():
		var h := BWHair.create(s, "thunder")
		var roles := {}
		for mi in h.meshes:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i) as ShaderMaterial
				roles[m.resource_name] = true
				t.ok(m.next_pass != null, "%s surface %d has a contour pass" % [s, i])
		t.ok(roles.has("bw_hair") and roles.has("bw_hair_shade"), "%s has hair + hair_shade" % s)
		t.ok(h.color.is_equal_approx(BWLook.element_color("thunder")), "%s tinted with the element" % s)
		t.ok(h.triangle_count() > 300 and h.triangle_count() <= MAX_TRIS, "%s tris %d within budget" % [s, h.triangle_count()])
		h.free()
	var shade := BWHair.material_for("hair_shade")
	t.ok(float(shade.get_shader_parameter("value")) < 1.0, "shade slot is darker")
	t.ok(float(BWHair.material_for("hair").get_shader_parameter("value")) == 1.0, "fill slot is the colour")


func test_fit(t) -> void:
	for s in BWHair.styles():
		var h := BWHair.create(s)
		var box := h.get_aabb()
		t.ok(box.end.y > 0.3 and box.end.y < 0.7, "%s top %.2f sits on the crown" % [s, box.end.y])
		t.ok(box.position.y > -1.2, "%s doesn't reach the floor" % s)
		var hits := 0
		for mi in h.meshes:
			var xf := h._xform_to_self(mi)
			for i in mi.mesh.get_surface_count():
				for v in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = xf * v
					if p.z > FACE_FRONT_Z and absf(p.x) < FACE_HALF_X and p.y < FACE_TOP_Y:
						hits += 1
		t.eq(hits, 0, "%s keeps the face window clear" % s)
		h.free()


## v2: every style has a variant-1 mesh with the same bones and slots, and
## every hair_variant (alt geometry, mirror, wide) keeps the face window
## clear and the budget.
func test_variants(t) -> void:
	for s in BWHair.styles():
		t.ok(ResourceLoader.exists(BWHair.path_for(s, true)), "%s has an alt variant" % s)
		for v in BWHair.VARIANT_COUNT:
			var h := BWHair.create(s, "fire", v)
			t.ok(h != null, "%s variant %d creates" % [s, v])
			if h == null:
				continue
			t.eq(h.variant, v, "%s keeps its variant" % s)
			t.eq(h.tail_bone_names().size(), int(BWHair.TAIL_BONES[s]), "%s v%d bone count" % [s, v])
			t.ok(h.triangle_count() <= MAX_TRIS, "%s v%d tris %d within budget" % [s, v, h.triangle_count()])
			var hits := 0
			for mi in h.meshes:
				var xf := h._xform_to_self(mi)
				for i in mi.mesh.get_surface_count():
					for p0 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
						var p: Vector3 = xf * p0
						if p.z > FACE_FRONT_Z and absf(p.x) < FACE_HALF_X and p.y < FACE_TOP_Y:
							hits += 1
			t.eq(hits, 0, "%s v%d keeps the face window clear" % [s, v])
			t.eq(h.model.scale.x < 0.0, v & BWHair.VARIANT_MIRROR != 0, "%s v%d mirror bit" % [s, v])
			h.free()


func test_shine_slot(t) -> void:
	for s in BWHair.styles():
		var h := BWHair.create(s, "water")
		var roles := {}
		for mi in h.meshes:
			for i in mi.mesh.get_surface_count():
				roles[(mi.get_surface_override_material(i) as ShaderMaterial).resource_name] = true
		t.ok(roles.has("bw_hair_shine"), "%s has the hair_shine slot" % s)
		h.free()
	var shine := BWHair.material_for("hair_shine")
	t.ok(is_zero_approx(float(shine.get_shader_parameter("shine"))), "shine removed by the author (D64): the slot shades like the fill")
	t.ok(float(BWHair.material_for("hair").get_shader_parameter("shine")) == 0.0, "fill slot has no shine")


func test_variant_seed(t) -> void:
	t.eq(BWHair.variant_for("gail"), BWHair.variant_for("gail"), "variant_for is deterministic")
	for id in ["a", "gail", "aureli", "boss", ""]:
		var v := BWHair.variant_for(id)
		t.ok(v >= 0 and v < BWHair.VARIANT_COUNT, "variant_for(%s) = %d in range" % [id, v])
	if not BWData.has_table("roster"):
		return
	# people with the same style never share the same mesh: both meshes are
	# in use in every shared style, and no two wearers share a variant seed
	var by_style := {}
	for row in BWData.table("roster"):
		var s := str(row.hair_style)
		if not by_style.has(s):
			by_style[s] = []
		by_style[s].append(BWHair.variant_for(str(row.id)))
	for s in by_style:
		var a: Array = by_style[s]
		if a.size() < 2:
			continue
		var alts := {}
		var seeds := {}
		for v in a:
			alts[v & BWHair.VARIANT_ALT] = true
			seeds[v] = true
		t.ok(alts.size() == 2, "the %s wearers use both meshes" % s)
		t.eq(seeds.size(), a.size(), "the %d %s wearers all get different variants" % [a.size(), s])


## Short styles still fit under a baseball cap (hide_top, clearance 0.10)
## in every variant, so a cap never leaves them bald; the mohawk never does.
func test_cap_clearance(t) -> void:
	for s in ["buzzed", "high_and_tight", "bob", "ponytail"]:
		for v in [0, BWHair.VARIANT_ALT]:
			var h := BWHair.create(s, "", v)
			var rise := BWEquipmentView.hair_rise(h)
			t.ok(rise <= 0.10, "%s v%d crown rise %.3f fits under a cap" % [s, v, rise])
			h.free()
	var m := BWHair.create("short_mohawk")
	t.ok(BWEquipmentView.hair_rise(m) > 0.10, "the mohawk is too tall for a cap")
	m.free()


# ---------------------------------------------- D146-D148: colour by rank

static func _pts(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k]) * BWUnit.POINTS_PER_RANK
	return out


## Signed contrast-streak share at t: > 0 light streaks, < 0 black.
static func _streaks(g: Gradient, t: float) -> float:
	return (g.sample(t).a - 0.5) * 2.0


static func _hue_near(a: Color, b: Color) -> bool:
	return absf(a.h - b.h) < 0.03 or absf(a.h - b.h) > 0.97


func test_rank_framework(t) -> void:
	var fire := BWLook.element_color("fire")
	var g0 := BWLook.hair_gradient({}, "")
	t.ok(g0.sample(0.5).is_equal_approx(Color(BWLook.HAIR_NONE, 0.5)), "rank 0: unaligned grey, no streaks")
	t.eq(BWLook.hair_key({ "fire": 5 }, ""), "", "5 points is still rank 0")
	var g1 := BWLook.hair_gradient(_pts({ "fire": 1 }), "fire")
	t.ok(Color(g1.sample(0.5), 1).is_equal_approx(Color(fire, 1)), "rank 1: the element colour is the majority")
	var s1 := _streaks(g1, 0.5)
	t.ok(s1 < -0.2 and s1 > -0.35, "rank 1 fire: ~30%% black streaks (%.2f)" % s1)
	var s2 := _streaks(BWLook.hair_gradient(_pts({ "fire": 2 }), "fire"), 0.5)
	t.ok(s2 < -0.08 and s2 > -0.17, "rank 2: fewer streaks (%.2f)" % s2)
	var g3 := BWLook.hair_gradient(_pts({ "fire": 3 }), "fire")
	t.ok(is_zero_approx(_streaks(g3, 0.0)) and is_zero_approx(_streaks(g3, 1.0)), "rank 3: solid")
	t.ok(is_zero_approx(_streaks(BWLook.hair_gradient(_pts({ "fire": 9 }), "fire"), 0.5)), "rank 9: solid")


## Dark colours take light streaks, light colours black ones, by luminance.
func test_streak_colour(t) -> void:
	var light_side := ["water", "thunder", "dark"]
	var dark_side := ["fire", "wind", "ice", "light"]
	for el in light_side:
		var c := BWLook.element_color(el)
		t.ok(BWLook.light_streaks(c), "%s (lum %.3f) takes light streaks" % [el, BWLook.luminance(c)])
		t.ok(_streaks(BWLook.hair_gradient(_pts({ el: 1 }), el), 0.5) > 0.2, "%s rank 1 encodes light streaks" % el)
	for el in dark_side:
		var c := BWLook.element_color(el)
		t.ok(not BWLook.light_streaks(c), "%s (lum %.3f) takes black streaks" % [el, BWLook.luminance(c)])
	t.ok(BWLook.HAIR_STREAK_LUM > BWLook.luminance(BWLook.element_color("water")) and BWLook.HAIR_STREAK_LUM < BWLook.luminance(BWLook.element_color("fire")), "threshold sits between water and fire")
	t.ok(float(BWHair.material_for("hair", true, BWHair.OUTLINE, "").next_pass.get_shader_parameter("dark_lum")) == BWLook.HAIR_STREAK_LUM, "contour lifts dark hues at the same threshold")


func test_ombre_order(t) -> void:
	var fire := BWLook.element_color("fire")
	var water := BWLook.element_color("water")
	var g := BWLook.hair_gradient(_pts({ "water": 1, "fire": 3 }), "water")
	t.ok(Color(g.sample(1.0), 1).is_equal_approx(Color(fire, 1)), "fire 3 + water 1: fire at the tips (focus doesn't beat rank)")
	t.ok(Color(g.sample(0.0), 1).is_equal_approx(Color(water, 1)), "water at the root, its own colour (no black base)")
	t.ok(absf(_streaks(g, 0.0)) <= BWLook.HAIR_STREAKS[1] * BWLook.HAIR_MIX_STREAKS + 0.01, "streaks in an ombre are sparing")
	t.eq(BWLook.hair_key(_pts({ "water": 1, "fire": 3 }), "water"), "fire3,water1", "key: strongest first")
	var ld := _pts({ "light": 2, "dark": 2 })
	t.ok(_hue_near(BWLook.hair_gradient(ld, "light").sample(1.0), BWLook.element_color("light")), "tie: the focus (light) takes the tips")
	t.ok(_hue_near(BWLook.hair_gradient(ld, "dark").sample(1.0), BWLook.element_color("dark")), "tie: the focus (dark) takes the tips")
	t.eq(BWLook.hair_key(ld, ""), "dark2,light2", "tie without focus: data order")
	var g3 := BWLook.hair_gradient(_pts({ "wind": 1, "ice": 3, "thunder": 2 }), "wind")
	t.ok(_hue_near(g3.sample(1.0), BWLook.element_color("ice")), "three: ice 3 at the tips")
	t.ok(_hue_near(g3.sample(0.33), BWLook.element_color("thunder")), "three: thunder 2 in the middle")
	t.ok(_hue_near(g3.sample(0.02), BWLook.element_color("wind")), "three: wind 1 at the root")
	var offs := g3.offsets
	for i in range(1, offs.size()):
		t.ok(offs[i] > offs[i - 1], "offsets strictly increase")
	t.ok(is_equal_approx(offs[0], 0.0) and is_equal_approx(offs[offs.size() - 1], 1.0), "gradient spans root to tip")


func test_rank_hair_runtime(t) -> void:
	var a := BWHair.create("bob", "", 0)
	var b := BWHair.create("long_hair", "", 3)
	t.ok(a.set_affinity(_pts({ "fire": 1 }), "fire"), "set_affinity applies")
	t.ok(not a.set_affinity(_pts({ "fire": 1 }), "fire"), "same ranks: no work")
	b.set_affinity(_pts({ "fire": 1 }), "fire")
	t.eq(a.look_key, "fire1", "look key")
	var ma := a.meshes[0].get_surface_override_material(0)
	var mb := b.meshes[0].get_surface_override_material(0)
	t.ok(ma == BWHair.material_for("hair", true, BWHair.OUTLINE, "fire1"), "material cached by look key")
	t.ok(ma.get_shader_parameter("ramp") == mb.get_shader_parameter("ramp"), "one ramp texture per look, shared")
	t.ok(a.set_affinity({}, ""), "rank 0 applies")
	t.eq(a.look_key, "none", "rank 0 look")
	t.ok(a.color == BWLook.HAIR_NONE, "rank 0 colour")
	a.free()
	b.free()


## D147: every style (and variant mesh) carries a baked root->tip coordinate
## that runs from the crown to the ends, and a lock azimuth.
func test_root_to_tip_baked(t) -> void:
	for s in BWHair.styles():
		for v in [0, BWHair.VARIANT_ALT]:
			var h := BWHair.create(s, "", v)
			var lo := 1.0
			var hi := 0.0
			var pts: Array = []        # [y, t]
			var az := {}
			for mi in h.meshes:
				var xf := h._xform_to_self(mi)
				var arr := mi.mesh.surface_get_arrays(0)
				var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
				t.eq(cols.size(), (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "%s v%d COLOR per vertex" % [s, v])
				for k in cols.size():
					lo = minf(lo, cols[k].r)
					hi = maxf(hi, cols[k].r)
					az[int(cols[k].g * 14.0)] = true
					var p: Vector3 = xf * arr[Mesh.ARRAY_VERTEX][k]
					pts.append([p.y, cols[k].r])
			var top := -INF
			var bot := INF
			for q in pts:
				top = maxf(top, q[0])
				bot = minf(bot, q[0])
			# the crown band (top 15% of the style's height), mean t
			var sum := 0.0
			var n := 0
			for q in pts:
				if q[0] > top - 0.15 * (top - bot):
					sum += q[1]
					n += 1
			var crown := sum / maxf(n, 1)
			var spike := s == "short_mohawk"      # its tips point up: the crown is tip-side
			t.ok(lo < (0.4 if spike else 0.2) and hi > 0.8, "%s v%d root->tip spans %.2f..%.2f" % [s, v, lo, hi])
			t.ok(crown < 0.5 or spike, "%s v%d crown band is root-side (%.2f)" % [s, v, crown])
			t.ok(az.size() >= 6, "%s v%d locks spread round the head (%d sectors)" % [s, v, az.size()])
			t.ok(h.meshes[0].mesh.surface_get_name(0) != "" or BWHair._role(h.meshes[0].mesh, 0) == "hair", "%s keeps its slots" % s)
			h.free()


## D148: a character's hair follows its unit's ranks live.
func test_character_hair_live(t) -> void:
	var u := BWUnit.new()
	u.id = "hair_live"
	u.element = "fire"
	u.weapon_class = "sword"
	u.affinity = { "fire": BWUnit.POINTS_PER_RANK }
	u.cosmetics = { "hair_style": "bob" }
	var c := BWCharacter.create(u)
	t.eq(c.hair.look_key, "fire1", "built at rank 1")
	u.affinity["fire"] = 3 * BWUnit.POINTS_PER_RANK           # mid-fight rank-up
	c.set_wounded(false)
	t.eq(c.hair.look_key, "fire3", "rank-up shows at the next sync")
	u.affinity["water"] = BWUnit.POINTS_PER_RANK               # Branch out
	c.pose("idle", 0.0)
	t.eq(c.hair.look_key, "fire3,water1", "a new element joins the ombre")
	t.ok(not c.refresh_hair(), "unchanged ranks: no recolour")
	c.free()

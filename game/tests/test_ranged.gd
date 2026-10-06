extends RefCounted
## D164-D166: the archery clips (BWAnimBow), the nocked arrows on the string
## (BWCharacter._update_bow), and the pooled arrow flights (BWRangedVFX).
## Look is judged by eye: design/art/ranged_*.png / .gif (tools/ranged_shots.gd,
## tools/ranged_preview.gd).

const DT := 1.0 / 60.0
const SHOTS := ["strike", "shot_quick", "shot_aimed", "shot_sky", "shot_volley", "shot_fan"]


func test_bow_clips_and_markers(t) -> void:
	var lib := BWAnimClips.load_set("bow")
	var acts := BWAnimClips.actions_for("bow", "bow")
	var bad: PackedStringArray = []
	for n in SHOTS:
		if not lib.has_animation(n):
			bad.append(n + " missing")
			continue
		var m: Dictionary = lib.get_animation(n).get_meta("bw")
		var mk: Dictionary = m.markers
		for seq in [["nock", "coil", "release", "hit", "recovered"]]:
			for i in range(1, seq.size()):
				if float(mk.get(seq[i], -1)) < float(mk.get(seq[i - 1], 99)):
					bad.append("%s %s<%s" % [n, seq[i], seq[i - 1]])
		var w: Array = m.get("arrows", [])
		if w.is_empty():
			bad.append(n + " has no arrow windows")
		for x in w:
			if float(x[1]) <= float(x[0]):
				bad.append(n + " bad window")
		if n != "strike" and (not acts.has(n) or not acts.has("windup_" + n)):
			bad.append(n + " not a pose name")
	var vm: Dictionary = lib.get_animation("shot_volley").get_meta("bw")
	t.ok((vm.arrows as Array).size() >= 3 and (vm.arrows as Array).size() <= 5, "the volley looses 3-5 arrows (%d)" % (vm.arrows as Array).size())
	t.ok((vm.markers as Dictionary).has("release4"), "each volley arrow has its release marker")
	t.eq(int(lib.get_animation("shot_fan").get_meta("bw").get("fan", 0)), 3, "the fan nocks three")
	var am: Dictionary = lib.get_animation("shot_aimed").get_meta("bw").markers
	t.ok(float(am.release) - float(am.coil) > 0.5, "Aimed Shot holds the draw (%.2f s)" % (float(am.release) - float(am.coil)))
	var qm: Dictionary = lib.get_animation("shot_quick").get_meta("bw").markers
	t.ok(float(qm.release) - float(qm.coil) < 0.1, "the quick shot has no hold")
	t.ok(bad.is_empty(), "bow clips: markers, windows, pose names (%s)" % ", ".join(bad))
	# the defs name them, and the combat maps the area skills the same way
	for k in ["aimed_shot", "retreating_shot", "split_arrow", "arcing_shot", "rain_of_arrows"]:
		t.eq(BWSkillRegistry.clip(k), BWRangedVFX.clip_for(k), "%s plays %s" % [k, BWRangedVFX.clip_for(k)])


## Every shot clip draws to the anchor (the hand well behind the string, the
## string bent to it) and the sky shot really points up.
func test_draws_reach_the_anchor(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	tree.root.add_child(holder)
	for n in ["strike", "shot_aimed", "shot_sky", "shot_fan"]:
		var c := BWCharacter.create(BWRosterKits.unit("gail"))
		holder.add_child(c)
		c.set_process(false)
		c.animator.rotate_idles = false
		var an := c.animator
		an._push(an._clip_layer(n), 0.0, an.layers.back())
		var coil := an.marker_time(n, "coil")
		var tt := 0.0
		while tt < coil:
			c._process(DT)
			tt += DT
		var bow: Transform3D = (c.poser.globals.hand_l as Transform3D) * c.poser.socket_l
		var hand: Vector3 = bow.affine_inverse() * ((c.poser.globals.hand_r as Transform3D) * c.poser.socket_r).origin
		t.ok(hand.z < BWWeaponView.v3(c.weapon.meta.string[0]).z - 0.4, "%s: a full draw (hand %.2f behind the string)" % [n, -hand.z])
		t.ok(c.weapon._string_bent, "%s: the string bends to the hand" % n)
		var arrows := c.nocked_arrows()
		t.eq(arrows.size(), 3 if n == "shot_fan" else 1, "%s: arrows on the string" % n)
		if n == "shot_sky" and not arrows.is_empty():
			# (in skeleton space: the weapon nodes only follow the skeleton on a rendered frame)
			var fwd: Vector3 = (bow.basis * (c._nocks[0].transform as Transform3D).basis.z).normalized()
			t.ok(fwd.y > 0.55, "the sky shot points skyward (%.2f)" % fwd.y)
		holder.remove_child(c)
		c.free()
	holder.queue_free()


## The flights: pooled (no new arrows once warm), a flat hit lands, sticks,
## fades after STUCK_LIFE and goes back to the pool.
func test_pooled_flights(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var fx := BWRangedVFX.new()
	holder.add_child(fx)
	fx.set_process(false)
	fx.prewarm(12)
	t.eq(fx.pool_free(), 12, "prewarmed")
	var target := Node3D.new()
	holder.add_child(target)
	target.position = Vector3(0, 0, 6)
	var dur := fx._fly([Vector3(0, 1.3, 0), Vector3(0, 1.2, 6)], Basis(), "fire", { "stick": "unit", "target": target, "trail": true })
	t.ok(dur > 0.05 and dur < 0.4, "a flat shot is fast (%.2f s)" % dur)
	t.eq(fx.pool_free(), 11, "one arrow out")
	var tt := 0.0
	while tt < dur + 0.05:
		fx._process(DT)
		tt += DT
	t.eq(str(fx._live[0].mode), "stuck", "it sticks in the target")
	while tt < dur + BWRangedVFX.STUCK_LIFE + BWRangedVFX.FADE + 0.1:
		fx._process(DT)
		tt += DT
	t.eq(fx.live_count(), 0, "it fades after its life")
	t.eq(fx.pool_free(), 12, "and goes back to the pool")
	# a burst of 12 from a warm pool creates nothing new
	var made := int(fx.stats.created)
	for i in 12:
		fx._fly([Vector3(i, 8, 0), Vector3(i, 0, 1)], Basis(), "", { "dur": 0.2, "stick": "ground" })
	t.eq(int(fx.stats.created), made, "a volley from a warm pool instances nothing")
	holder.queue_free()

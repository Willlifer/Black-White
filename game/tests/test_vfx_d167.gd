extends RefCounted
## D167-D170: cast VFX weights and hit-feel sizing (pure), the shaders and
## the "Screen shake" setting. The pictures: tools/vfx_shots.gd.


func _tc(tier: int) -> Dictionary:
	return { "tier": tier }


func test_vfx_weights(t) -> void:
	var M := BWCutsceneTier.MINIMAL
	var S := BWCutsceneTier.SHORT
	var F := BWCutsceneTier.FULL
	var sk := { "type": "skill", "skill": "surge" }
	t.eq(BWVfxCasts.weight_for(sk, _tc(M), { "weapon": "staff" }), BWVfxCasts.NONE, "a minimal tier plays no cast VFX")
	t.eq(BWVfxCasts.weight_for(sk, _tc(S), { "weapon": "staff" }), BWVfxCasts.FULL, "a staff skill above minimal casts in full (Surge)")
	t.eq(BWVfxCasts.weight_for(sk, _tc(S), { "weapon": "sword" }), BWVfxCasts.SHORT, "a short non-staff skill: circle flash + release")
	t.eq(BWVfxCasts.weight_for(sk, _tc(F), { "weapon": "lance" }), BWVfxCasts.FULL, "a full tier plays everything")
	t.eq(BWVfxCasts.weight_for({ "type": "attack" }, _tc(F)), BWVfxCasts.NONE, "basic attacks get no cast VFX")
	t.eq(BWVfxCasts.setup_weight("default"), BWVfxCasts.FULL, "setup beats in full by default (Ley Line)")
	t.eq(BWVfxCasts.setup_weight("fast"), BWVfxCasts.SHORT, "Fast: the reduced setup show")
	t.eq(BWVfxCasts.setup_weight("minimal"), BWVfxCasts.NONE, "Minimal: no setup show")
	# the real tier path: Surge (cd 2) is SHORT under D122, so FULL here; Fast drops it to SHORT tier
	var row := BWSkills.get_skill("surge")
	var e := { "type": "skill", "skill": "surge", "results": [{ "target": "x", "result": { "hit": true, "crit": false, "damage": 9 }, "ko": false }] }
	t.eq(BWVfxCasts.weight_for(e, BWCutsceneTier.tier_for(e, "default"), row), BWVfxCasts.FULL, "Surge casts in full by default")
	t.eq(BWVfxCasts.weight_for(e, BWCutsceneTier.tier_for(e, "minimal"), row), BWVfxCasts.NONE, "Surge under Minimal: none")


func test_every_element_has_a_release(t) -> void:
	for el in BWVfxCasts.ELEMENTS:
		t.ok(BWVfxCasts.REL_MODE.has(el), "%s has a release shape" % el)
		t.ok(BWVfxCasts.REL_IMPACT.has(el), "%s has an impact time" % el)
	var modes := {}
	for el in BWVfxCasts.REL_MODE:
		modes[BWVfxCasts.REL_MODE[el]] = true
	t.eq(modes.size(), 7, "seven distinct release shapes")


func test_shaders_load(t) -> void:
	for p in ["res://shaders/vfx_ground.gdshader", "res://shaders/vfx_column.gdshader",
			"res://shaders/vfx_particle.gdshader", "res://shaders/vfx_ribbon.gdshader"]:
		var s: Shader = load(p)
		t.ok(s != null and s.code.length() > 0, "%s loads" % p)


func test_shake_scales_and_caps(t) -> void:
	t.eq(BWHitFeel.shake_for(0, 150), 0.0, "no damage, no shake")
	var chip := BWHitFeel.shake_for(5, 150)
	var mid := BWHitFeel.shake_for(30, 150)
	var big := BWHitFeel.shake_for(90, 150)
	t.ok(chip > 0.0 and chip < mid and mid < big, "shake grows with the hit's share of max HP")
	t.ok(chip <= 0.03, "a chip is barely a nudge")
	t.ok(BWHitFeel.shake_for(500, 150, true) <= BWHitFeel.SHAKE_CAP, "capped")
	t.ok(BWHitFeel.shake_for(30, 150, true) > mid, "a crit shakes a little more")


func test_hitstop_only_on_big_hits(t) -> void:
	t.eq(BWHitFeel.hitstop_for(10, 150), 0.0, "a normal hit has no stop")
	t.ok(BWHitFeel.hitstop_for(35, 150) > 0.0, "a fifth of max HP stops")
	t.ok(BWHitFeel.hitstop_for(60, 150) > BWHitFeel.hitstop_for(35, 150), "a huge hit stops longer")
	t.ok(BWHitFeel.hitstop_for(150, 150) <= 0.1, "and stays short")


func test_number_sizes(t) -> void:
	var miss := BWHitFeel.number_size(0, 150, false, false)
	var chip := BWHitFeel.number_size(4, 150)
	var mid := BWHitFeel.number_size(30, 150)
	var big := BWHitFeel.number_size(70, 150)
	t.eq(miss, BWHitFeel.NUM_MIN, "a miss is the smallest")
	t.ok(chip < mid and mid < big, "numbers grow with the hit (%d < %d < %d)" % [chip, mid, big])
	t.ok(BWHitFeel.number_size(30, 150, true) > mid, "a crit number is bigger")
	t.ok(BWHitFeel.number_size(999, 150, true) <= BWHitFeel.NUM_CAP, "capped")


func test_screen_shake_setting(t) -> void:
	t.eq(BWSettings.DEFAULTS.get("screen_shake"), true, "Screen shake defaults on")
	t.eq(BWHitFeel.shake_on(), true, "on in an isolated run")

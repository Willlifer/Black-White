extends RefCounted
## Animation lane (design/art/ANIMATION.md): the clip matrix and its baked
## libraries (one per weapon style), the clips' contracts (every style has
## every clip, markers, seamless loops, guard-to-guard one-shots, floor and
## contacts, feet that don't slide, weapons clear of the floor), the
## BWAnimator state machine (personality idles, wounded, run start / stop,
## turns, channel -> cast, fall holds), blends without pops for every pair
## of poses, the runtime foot lock, and the BWUnitView integration with its
## static-pose fallback. Motion quality is judged by eye:
## design/art/anim_*_sheet_*.png and anim_*.gif.

const DT := 1.0 / 60.0

## The clips every set must have.
const REQUIRED := ["idle", "idle_bouncy", "idle_fidget", "idle_weapon", "idle_look", "wounded",
	"walk", "walk_calm", "run", "run_start", "run_stop", "run_stop_r", "limp", "turn_l", "turn_r",
	"strike", "cast", "channel", "stricken", "block", "fumble", "dodge", "kneel", "fall",
	"cheer", "cheer_jump", "cheer_cool",
	"stricken_flinch", "stricken_shrug", "stricken_stumble", "stricken_knockback", "stricken_rage"]
## One roster character per style (and the axes), for the solved checks.
const REPS := { "one": "stryker", "heavy": "della", "polearm": "rui", "spear": "dragtol",
	"staff": "jericho", "pair": "rem", "bow": "gail", "pistol": "sala", "fists": "will" }
## No roster character starts with fists (D76): the fists rep wears hand wraps.
const REP_WEAPON := { "fists": "hand_wraps" }


func _unit(id: String) -> BWUnit:
	return BWRosterKits.unit(id)


## The representative unit of a style, holding a weapon of that style.
func _rep(st: String) -> BWUnit:
	var u := _unit(REPS[st])
	if REP_WEAPON.has(st):
		u.weapon_model = REP_WEAPON[st]
		u.equipment.erase("main_hand")
	return u


func _sample(a: Animation, t: float) -> Dictionary:
	var out := {}
	for i in a.get_track_count():
		out[str(a.track_get_path(i).get_concatenated_subnames())] = a.value_track_interpolate(i, t)
	return out


func _diff(x: Variant, y: Variant) -> float:
	if x is Vector3:
		return (x as Vector3).distance_to(y)
	return absf(float(x) - float(y))


func test_saved_libraries_match_source(t) -> void:
	var worst := 0.0
	var where := ""
	for set_id in BWAnimClips.SETS:
		var path := BWAnimClips.path_for(set_id)
		t.ok(ResourceLoader.exists(path), "%s: baked library exists (tools/build_anims.gd)" % set_id)
		var saved := load(path) as AnimationLibrary
		if saved == null:
			t.ok(false, "%s: library loads" % set_id)
			continue
		t.eq(int(saved.get_meta("bw").version), BWAnimClips.ANIM_VERSION, "%s: library version" % set_id)
		var fresh := BWAnimClips.build_library(set_id)
		t.eq(Array(saved.get_animation_list()), Array(fresh.get_animation_list()), "%s: same clips" % set_id)
		for n in fresh.get_animation_list():
			var a := fresh.get_animation(n)
			var b := saved.get_animation(n)
			if absf(a.length - b.length) > 1e-5:
				worst = 1.0
				where = "%s/%s length" % [set_id, n]
				continue
			var tt := 0.0
			while tt <= a.length:
				var sa := _sample(a, tt)
				var sb := _sample(b, tt)
				for k in sa:
					var d := _diff(sa[k], sb.get(k, sa[k]))
					if d > worst:
						worst = d
						where = "%s/%s %s @%.2f" % [set_id, n, k, tt]
				tt += 0.2
	t.ok(worst < 1e-4, "saved bakes == fresh bakes of the source (worst %.6f at %s): rerun tools/build_anims.gd" % [worst, where])


## Every style has every clip, and every pose name resolves to a real clip
## for every weapon class of the style.
func test_every_style_has_every_clip(t) -> void:
	var missing: PackedStringArray = []
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		for n in REQUIRED:
			if not lib.has_animation(n):
				missing.append("%s/%s" % [set_id, n])
		for cls in ["", "axe"]:
			var acts := BWAnimClips.actions_for(set_id, cls)
			for p in BWAnimClips.ACTION_NAMES:
				if not acts.has(p) or not lib.has_animation(StringName(str(acts[p].clip))):
					missing.append("%s(%s) pose %s" % [set_id, cls, p])
				var st := str(acts.get(p, {}).get("start", ""))
				if st != "" and not lib.has_animation(StringName(st)):
					missing.append("%s start %s" % [set_id, st])
	for set_id in ["one", "heavy"]:
		if not BWAnimClips.load_set(set_id).has_animation("strike_axe"):
			missing.append(set_id + "/strike_axe")
	if not BWAnimClips.load_set("heavy").has_animation("walk_heavy") or not BWAnimClips.load_set("heavy").has_animation("run_heavy"):
		missing.append("heavy/walk_heavy|run_heavy")
	t.ok(missing.is_empty(), "every style has every clip and pose (%s)" % ", ".join(missing))
	# every roster character gets an animator whose every pose is a clip
	var static_poses: PackedStringArray = []
	for row in BWData.table("roster"):
		var c := BWCharacter.create(BWUnit.from_roster(row))
		if c.animator == null:
			static_poses.append(str(row.id))
		else:
			for p in BWCharacterPose.POSE_NAMES + PackedStringArray(["walk", "run", "channel"]):
				if not c.has_clip(p):
					static_poses.append("%s:%s" % [row.id, p])
		c.free()
	t.ok(static_poses.is_empty(), "every roster character plays a clip for every pose (%s)" % ", ".join(static_poses))


func test_markers(t) -> void:
	var bad: PackedStringArray = []
	var order := func(mk: Dictionary, names: Array) -> bool:
		for i in names.size():
			if not mk.has(names[i]):
				return false
			if i > 0 and float(mk[names[i]]) < float(mk[names[i - 1]]) - 1e-5:
				return false
		return true
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		for n in ["strike", "strike_axe"]:
			if not lib.has_animation(n):
				continue
			var a := lib.get_animation(n)
			var mk: Dictionary = a.get_meta("bw").markers
			var ranged := mk.has("release")
			var seq := ["coil", "release", "hit", "recovered"] if ranged else ["coil", "launch", "land", "hit", "hop_start", "hop_end", "recovered"]
			if not order.call(mk, seq):
				bad.append("%s/%s order %s" % [set_id, n, mk])
			if a.has_method("has_marker") and not a.has_marker(&"hit"):
				bad.append("%s/%s: hit is not an Animation marker" % [set_id, n])
			if ranged and a.has_method("has_marker") and not a.has_marker(&"release"):
				bad.append("%s/%s: release is not an Animation marker" % [set_id, n])
		var cm: Dictionary = lib.get_animation("cast").get_meta("bw").markers
		if not order.call(cm, ["coil", "release", "hit", "recovered"]):
			bad.append("%s/cast %s" % [set_id, cm])
		for n in ["stricken", "block", "fumble", "dodge", "kneel", "fall"]:
			if not (lib.get_animation(n).get_meta("bw").markers as Dictionary).has("impact"):
				bad.append("%s/%s impact" % [set_id, n])
		# the hit variants: impact on the first frame, catch and recovered after
		for n in BWAnimStricken.VARIANTS:
			var vm: Dictionary = lib.get_animation(n).get_meta("bw").markers
			if not order.call(vm, ["impact", "catch", "recovered"]) or absf(float(vm.get("impact", -1.0))) > 1e-5:
				bad.append("%s/%s %s" % [set_id, n, vm])
			if not lib.get_animation(n).has_marker(&"impact"):
				bad.append("%s/%s: impact is not an Animation marker" % [set_id, n])
		if not order.call(lib.get_animation("stricken_rage").get_meta("bw").markers, ["impact", "catch", "shout", "recovered"]):
			bad.append("%s/stricken_rage shout" % set_id)
		if not order.call(lib.get_animation("stricken_knockback").get_meta("bw").markers, ["impact", "slide_end", "catch", "recovered"]):
			bad.append("%s/stricken_knockback slide_end" % set_id)
		var bm: Dictionary = lib.get_animation("strike").get_meta("bw").markers
		if set_id == "bow" and not order.call(bm, ["nock", "coil", "release"]):
			bad.append("bow/strike nock")
		var dm: Dictionary = lib.get_animation("dodge").get_meta("bw").markers
		if not order.call(dm, ["launch", "impact", "land", "hop_start", "hop_end"]):
			bad.append("%s/dodge %s" % [set_id, dm])
		var fm: Dictionary = lib.get_animation("fall").get_meta("bw")
		if not (fm.markers as Dictionary).has("grounded") or not bool(fm.get("hold_end", false)):
			bad.append("%s/fall grounded+hold_end" % set_id)
	t.ok(bad.is_empty(), "markers present and in order (%s)" % "; ".join(bad))


## Loops close; one-shots start and end on the set's guard (with the
## documented exceptions); hand-overs match exactly.
func test_loops_and_handovers(t) -> void:
	var bad: PackedStringArray = []
	var chans := ["root", "hips", "chest", "head", "hand_r_pos", "hand_l_pos", "foot_l_pos", "foot_r_pos", "hand_l_grip", "squash", "smear"]
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		var base := BWAnimClips.base_channels(set_id)
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			if a.loop_mode == Animation.LOOP_LINEAR:
				var s0 := _sample(a, 0.0)
				var s1 := _sample(a, a.length)
				for k in s0:
					if _diff(s0[k], s1[k]) > 0.002:
						bad.append("%s/%s loop %s" % [set_id, n, k])
				continue
			var ends := []
			if not str(n) in ["run_stop", "run_stop_r"]:
				ends.append(0.0)
			if not str(n) in ["fall", "run_start"]:
				ends.append(a.length)
			# weapon handling (D80): a handling one-shot starts on its `from`
			# hold and ends on its `to` hold (the guard is one of them)
			var hm: Dictionary = a.get_meta("bw", {})
			for tt in ends:
				var s := _sample(a, tt)
				var ref := base
				if hm.has("handling"):
					ref = _hold_ref(set_id, str(hm.get("from" if tt == 0.0 else "to", "guard")))
				for k in chans:
					if _diff(s[k], ref[k]) > 0.006:
						bad.append("%s/%s %s@%.2f" % [set_id, n, k, tt])
		# hand-overs
		var run := lib.get_animation(str(BWAnimClips.actions_for(set_id).run.clip))
		var pairs := [["run_start", -1.0, run, 0.0], ["run_stop", 0.0, run, 0.0], ["run_stop_r", 0.0, run, run.length * 0.5]]
		for pr in pairs:
			var a2 := lib.get_animation(pr[0])
			var ta := a2.length if float(pr[1]) < 0.0 else 0.0
			var sa := _sample(a2, ta)
			var sb := _sample(pr[2], float(pr[3]))
			for k in ["root", "hips", "spine", "chest", "head", "hand_r_pos", "hand_l_pos"]:
				if _diff(sa[k], sb[k]) > 0.01:
					bad.append("%s %s/run %s (%.3f)" % [set_id, pr[0], k, _diff(sa[k], sb[k])])
			for k in ["foot_l_pos", "foot_r_pos"]:
				if _diff(sa[k], sb[k]) > 0.08:
					bad.append("%s %s/run %s (%.3f)" % [set_id, pr[0], k, _diff(sa[k], sb[k])])
		var cast := lib.get_animation("cast")
		var ch := _sample(lib.get_animation("channel"), 0.0)
		var cc := _sample(cast, float(cast.get_meta("bw").markers.coil))
		for k in ["root", "chest", "head", "hand_r_pos", "hand_l_pos"]:
			if _diff(ch[k], cc[k]) > 0.005:
				bad.append("%s channel/cast-coil %s" % [set_id, k])
	t.ok(bad.is_empty(), "loops close, one-shots go guard to guard, hand-overs match (%s)" % ", ".join(bad.slice(0, 12)))


## The pose a handling clip starts / ends on: the guard's body plus the
## hold's posture, the hold's hands.
func _hold_ref(set_id: String, h: String) -> Dictionary:
	var ref := BWAnimClips.base_channels(set_id).duplicate()
	var p := BWAnimHandling.posture(set_id, h)
	for k in p:
		ref[k] = (ref[k] as Vector3) + (p[k] as Vector3)
	ref.merge(BWAnimHandling.hold_pose(set_id, h), true)
	return ref


func test_feet_and_floor(t) -> void:
	var bad: PackedStringArray = []
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			var lowest := 1.0
			var tt := 0.0
			while tt <= a.length:
				var s := _sample(a, tt)
				for side in ["l", "r"]:
					var low := (s["foot_%s_pos" % side] as Vector3).y + BWAnimClips.sole_low((s["foot_%s_rot" % side] as Vector3).x).y
					lowest = minf(lowest, low)
				tt += 1.0 / 60.0
			if lowest < -0.004:
				bad.append("%s/%s %.4f" % [set_id, n, lowest])
	t.ok(bad.is_empty(), "no sole under the floor in any clip (%s)" % ", ".join(bad))


## Gaits: a stance foot's ground point slides back at exactly the root
## speed (loops) or the authored root curve (start / stop): no skid.
func test_gaits_dont_slide(t) -> void:
	var bad: PackedStringArray = []
	var n := 0
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		for clip in lib.get_animation_list():
			var a := lib.get_animation(clip)
			var m: Dictionary = a.get_meta("bw")
			var curve: Array = m.get("root_s", [])
			if not m.has("gait") and curve.is_empty():
				continue
			var speed := float(m.get("speed", 0.0))
			var worst := 0.0
			var tt := 0.0
			while tt + DT <= a.length:
				var s0 := _sample(a, tt)
				var s1 := _sample(a, tt + DT)
				var dz := speed * DT
				if not curve.is_empty():
					var hz := float(m.get("root_hz", BWAnimClips.FPS))
					dz = BWAnimator._curve(curve, (tt + DT) * hz) - BWAnimator._curve(curve, tt * hz)
				for side in ["l", "r"]:
					if float(s0["contact_" + side]) > 0.99 and float(s1["contact_" + side]) > 0.99:
						var g0 := BWAnimator.ground_point(s0["foot_%s_pos" % side], s0["foot_%s_rot" % side])
						var g1 := BWAnimator.ground_point(s1["foot_%s_pos" % side], s1["foot_%s_rot" % side])
						worst = maxf(worst, Vector2(g1.x - g0.x, g1.z - g0.z + dz).length() / DT)
						n += 1
				tt += DT
			# 0.2 u/s = 3 mm per 60 Hz frame: the linear bake through a toe roll;
			# the limp's hurt foot is set down in a short scuff (6 mm / frame)
			if worst > (0.36 if clip == "limp" else 0.2):
				bad.append("%s/%s %.3f u/s" % [set_id, clip, worst])
	t.ok(n > 500, "gait stance samples (%d)" % n)
	t.ok(bad.is_empty(), "stance feet travel with the root: no slide (%s)" % ", ".join(bad))


## Solve every clip of every set on a character holding each weapon of the
## style: the weapon's ends stay above the floor. The solver's floor
## clearance (BWCharacterPose._clear_floor) guarantees it; the clips must
## not lean on it: the lift it applies stays small (< 8 cm), except in the
## fall, where she lies on the floor and the weapon rests on it.
func test_weapons_clear_the_floor(t) -> void:
	var bad: PackedStringArray = []
	var leaning: PackedStringArray = []
	var checked := 0
	var fixed := 0
	for wid in BWWeaponView.ids():
		var meta := BWWeaponView.meta_for(wid)
		var set_id := BWAnimClips.set_for(meta)
		if set_id == "":
			continue
		var u := _rep(set_id)
		u.weapon_model = wid
		u.equipment.erase("main_hand")
		var c := BWCharacter.create(u)
		if c.animator == null or c.weapon == null:
			bad.append(wid + ": no animator")
			c.free()
			continue
		var ends: Array = c.poser.weapon_ends
		var lib := c.animator.library
		var worst := 1.0
		var where := ""
		var most := 0.0
		var most_at := ""
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			var l := c.animator._clip_layer(n)
			var tt := 0.0
			while tt <= a.length:
				l.t = tt
				c.poser.apply(c.animator._sample(l))
				if c.poser.floor_fix > 0.0:
					fixed += 1
					if c.poser.floor_fix > most and n != "fall":
						most = c.poser.floor_fix
						most_at = "%s @%.2f" % [n, tt]
				var hk := "hand_l" if c.poser.hold_hand == "l" else "hand_r"
				var sock: Transform3D = (c.poser.globals[hk] as Transform3D) * (c.poser.socket_l if hk == "hand_l" else c.poser.socket_r)
				for pt in ends:
					var y: float = (sock * (pt as Vector3)).y
					if y < worst:
						worst = y
						where = "%s @%.2f" % [n, tt]
				checked += 1
				tt += 1.0 / 24.0
		if worst < 0.0:
			bad.append("%s %.3f (%s)" % [wid, worst, where])
		if most > 0.08:
			leaning.append("%s %.0f cm (%s)" % [wid, most * 100.0, most_at])
		c.free()
	t.ok(checked > 1000, "weapon poses checked (%d; floor clearance engaged on %d)" % [checked, fixed])
	t.ok(bad.is_empty(), "weapon ends stay above the floor (%s)" % "; ".join(bad))
	t.ok(leaning.is_empty(), "clips keep their weapons up themselves: floor lifts < 8 cm outside the fall (%s)" % "; ".join(leaning))


## Blade across the face: in the standing clips (the idles, the guard)
## no part of the weapon may cover the face from a camera in front of her
## (azimuth -75..75 degrees, 18 degrees down): a weapon point counts when it
## is nearer the camera than the head centre and inside the face disc.
## Returns, per weapon, the worst cover (m into the disc).
static func face_cover(c: BWCharacter, clips: Array, step: float = 1.0 / 12.0) -> Array:
	var worst := -1.0
	var where := ""
	var hk := "hand_l" if c.poser.hold_hand == "l" else "hand_r"
	var ends: Array = c.poser.weapon_ends
	var lib := c.animator.library
	var pts: Array = []
	for k in 9:
		pts.append(((ends[0] as Vector3) * (k / 8.0)) if k > 0 else Vector3.ZERO)
		pts.append((ends[1] as Vector3) * (k / 8.0))
	for n in clips:
		if not lib.has_animation(n):
			continue
		var a := lib.get_animation(n)
		var l := c.animator._clip_layer(n)
		var tt := 0.0
		while tt <= a.length:
			l.t = tt
			c.poser.apply(c.animator._sample(l))
			var G := c.poser.globals
			var head: Vector3 = (G.head as Transform3D) * Vector3(0, 0.26, 0)
			var socks := [(G[hk] as Transform3D) * (c.poser.socket_l if hk == "hand_l" else c.poser.socket_r)]
			if c.poser.hold_hand == "both":
				socks.append((G.hand_l as Transform3D) * c.poser.socket_l)
			for az in [-90, -70, -50, -25, 0, 25, 50, 70, 90]:
				var yaw := deg_to_rad(az)
				var pit := deg_to_rad(18.0)
				var d := Vector3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit))
				for sk in socks:
					for p in pts:
						var w: Vector3 = (sk as Transform3D) * (p as Vector3) - head
						var depth := w.dot(d)
						if depth <= 0.0:
							continue
						var cover := 0.32 - (w - d * depth).length()
						if cover > worst:
							worst = cover
							where = "%s @%.2f az %d" % [n, tt, az]
			tt += step
	return [worst, where]


func test_blade_off_the_face(t) -> void:
	var bad: PackedStringArray = []
	var report: PackedStringArray = []
	for wid in BWWeaponView.ids():
		var meta := BWWeaponView.meta_for(wid)
		var set_id := BWAnimClips.set_for(meta)
		if set_id == "":
			continue
		var u := _rep(set_id)
		u.weapon_model = wid
		u.equipment.erase("main_hand")
		var c := BWCharacter.create(u)
		var standing: Array = ["idle", "idle_bouncy", "wounded", "idle_fidget", "idle_look"]
		for h in c.animator.holds():
			if h != "guard":
				standing.append("hold_" + h)          # the weapon-handling holds stand too
		var r := face_cover(c, standing)
		report.append("%s %.2f" % [wid, float(r[0])])
		if float(r[0]) > 0.0:
			bad.append("%s %.3f m (%s)" % [wid, float(r[0]), r[1]])
		c.free()
	t.ok(bad.is_empty(), "standing, no weapon covers the face from the front half (%s) [%s]" % ["; ".join(bad), ", ".join(report)])


func test_state_machine(t) -> void:
	var c := BWCharacter.create(_unit("della"))
	t.ok(c.animator != null, "della (flamberge) gets an animator")
	var an := c.animator
	an.rotate_idles = false
	t.eq(an.top_clip(), "idle", "starts in her home idle")
	c.pose("windup")
	for i in 60:
		an.update(DT)
	t.eq(an.top_clip(), "strike", "windup plays the strike")
	t.near(float(an.layers.back().t), float(an.clip_meta("strike").markers.coil), 0.001, "windup holds at the coil")
	var seen := []
	an.marker.connect(func(_clip: String, m: String) -> void: seen.append(m))
	c.pose("strike")
	t.ok(an.time_to("hit") > 0.0, "strike released: hit ahead (%.3f s)" % an.time_to("hit"))
	c.pose("idle")
	t.eq(an.top_clip(), "strike", "idle() during the strike is deferred")
	for i in 120:
		an.update(DT)
	t.ok("hit" in seen and "hop_end" in seen, "markers fired: %s" % [seen])
	t.eq(an.top_clip(), "idle", "the strike ends on idle")
	for p in [["hit", "stricken"], ["fumble", "fumble"], ["block", "block"], ["dodge", "dodge"], ["kneel", "kneel"], ["cheer", str(an.personality.cheer)]]:
		c.pose(p[0])
		an.update(DT)
		t.eq(an.top_clip(), p[1], "%s plays %s" % p)
	# the fall holds on the ground
	c.pose("fall")
	for i in 150:
		an.update(DT)
	t.eq(an.top_clip(), "fall", "fall holds after its end")
	# run from a standstill: the start first, then the run; the stop; idle
	c.pose("idle", 0.0)
	c.pose("run")
	an.update(DT)
	t.eq(an.top_clip(), "run_start", "a run from a standstill starts with run_start")
	for i in 45:
		an.update(DT)
	t.eq(an.top_clip(), "run", "run_start hands over to the run")
	c.pose("run_stop")
	an.update(DT)
	t.ok(an.top_clip().begins_with("run_stop"), "run_stop (%s)" % an.top_clip())
	c.pose("idle")
	for i in 60:
		an.update(DT)
	t.eq(an.top_clip(), "idle", "the stop ends in idle")
	# channel -> cast starts at the cast's coil
	c.pose("channel")
	for i in 20:
		an.update(DT)
	t.eq(an.top_clip(), "channel", "channel loops")
	c.pose("cast")
	t.near(float(an.layers.back().t), float(an.clip_meta("cast").markers.coil), 0.001, "cast after channel starts at its coil")
	t.ok(an.time_to("release") > 0.0 and an.time_to("release") < 0.2, "release is close after a channel (%.3f)" % an.time_to("release"))
	# wounded swaps idle and the gaits
	c.pose("idle", 0.0)
	c.set_wounded(true)
	an.update(DT)
	t.eq(an.top_clip(), "wounded", "wounded idle below 35%")
	c.pose("walk")
	an.update(DT)
	t.eq(an.top_clip(), "limp", "wounded walk limps")
	c.pose("run")
	an.update(DT)
	t.eq(an.top_clip(), "limp", "wounded run limps (no start)")
	c.set_wounded(false)
	c.pose("idle", 0.0)
	# axes: the heavy set's chop and shouldered gaits
	var g := BWCharacter.create(_unit("burt"))
	t.eq(str(g.animator.actions.strike.clip), "strike_axe", "burt (double axe) chops")
	t.eq(str(g.animator.actions.walk.clip), "walk_heavy", "burt walks with it shouldered")
	t.eq(str(g.animator.actions.run.clip), "run_heavy", "burt runs with it shouldered")
	g.free()
	var j := BWCharacter.create(_unit("kai"))
	t.eq(str(j.animator.actions.strike.clip), "strike_axe", "kai (hatchet) chops")
	j.free()
	c.free()


## Personality (D153): the vibe comes from element + friendliness
## (BWAnimClips.vibe_of), the rest from the id; deterministic.
func test_personality_and_idle_rotation(t) -> void:
	var rem := BWAnimClips.personality("rem", "bouncy")
	t.eq(str(rem.vibe), "bouncy", "a bouncy vibe stays bouncy")
	t.eq(str(rem.idle), "idle", "D65: even the bouncy stand in the calm idle")
	var alex := BWAnimClips.personality("della", "cocky")
	t.eq(str(alex.idle), "idle", "della keeps the reference idle")
	t.eq(BWAnimClips.personality("x", "nonsense").vibe, "cocky", "an unknown vibe falls back to cocky")
	t.eq(BWAnimClips.vibe_of(BWRosterKits.unit("alexandra")), "stoic", "ice is stoic")
	t.eq(BWAnimClips.vibe_of(BWRosterKits.unit("jericho")), "dreamy", "light (neutral) is dreamy")
	t.eq(BWAnimClips.vibe_of(BWRosterKits.unit("rem")), "bouncy", "wind (friendly) is bouncy")
	t.eq(BWAnimClips.vibe_of(BWRosterKits.unit("della")), "cocky", "fire (unfriendly) hardens to cocky")
	t.eq(BWAnimClips.personality("rem", "dreamy"), BWAnimClips.personality("rem", "dreamy"), "deterministic")
	var vibes := {}
	for row in BWRosterKits.rows():
		var pz := BWAnimClips.personality(str(row.id), BWAnimClips.vibe_of(BWUnit.from_roster(row)))
		vibes[pz.vibe] = true
		t.ok((pz.variants as Array).size() >= 2, "%s has 2+ idle variants" % row.id)
		t.eq(str(pz.idle), "idle", "%s: everyone's home idle is the calm one (D65)" % row.id)
		t.ok(float(pz.rate) >= 0.85 and float(pz.rate) <= 1.0, "%s: idle rate in 0.85..1.0 (%.2f)" % [row.id, float(pz.rate)])
		t.ok(float(pz.interval[0]) >= 8.0, "%s: variants are rare (%s s)" % [row.id, pz.interval])
	t.ok(vibes.size() >= 4, "the roster spans 4+ vibes (%s)" % [vibes.keys()])
	# standing long enough plays a variant, which ends back in the home idle
	# (a bouncy kit: the shortest intervals; which variants come is per id)
	var c := BWCharacter.create(_unit("gail"))
	var an := c.animator
	t.eq(an.top_clip(), "idle", "gail stands in the calm idle")
	var variants := {}
	for i in 60 * 40:
		an.update(DT)
		if an.top_clip().begins_with("idle_"):
			variants[an.top_clip()] = true
			if an.is_busy():
				variants["BUSY"] = true
	t.ok(not variants.has("BUSY"), "a variant never blocks (is_busy false)")
	t.ok(variants.size() >= 2, "40 s of standing rotates 2+ variants (%s)" % [variants.keys()])
	t.eq(c.pose_name(), "idle", "the pose name stays idle through variants")
	c.pose("walk")
	an.update(DT)
	t.ok(an.top_clip().begins_with("walk"), "a request cuts into a variant at once")
	c.free()


## Request every pose after every pose (mid-clip) for each style and check
## that no joint pops. A pop is motion the blend adds on top of the clip it
## is going to: each frame's joint step is compared with the same joint's
## step in the outgoing and the incoming clip played alone at the same
## time (authored fast keys, a cut or a recoil, move those the same). A pop
## is a sudden excess: over 0.1 u in one 60 Hz frame AND 1.8x the joint's
## previous step (smooth stepping arcs ramp up), or any step over 0.35 u.
func test_no_pops_any_pair(t) -> void:
	var names := ["idle", "walk", "run", "windup", "strike", "cast", "channel", "hit", "kneel", "dodge", "block", "fumble", "fall", "cheer", "run_stop"]
	# the hit variants are requested from anything (and lead back to idle)
	var tos: Array = names + Array(BWAnimStricken.VARIANTS)
	var bones := ["head", "foot_l", "foot_r", "chest", "hand_r", "hand_l"]
	var bad: PackedStringArray = []
	var worst := 0.0
	for st in REPS:
		var c := BWCharacter.create(_rep(st))
		var r := BWCharacter.create(_rep(st))       # the incoming clip alone
		var o := BWCharacter.create(_rep(st))       # the outgoing clip alone
		for x in [c, r, o]:
			x.animator.rotate_idles = false
			x.animator.walk_rate = 1.0
		var an := c.animator
		for from in names:
			for to in tos:
				c.pose("idle", 0.0)
				an.update(DT)
				c.pose(from)
				for i in 14:
					an.update(DT)
				var out_l: Dictionary = (an.layers.back() as Dictionary).duplicate()
				c.pose(to)
				var top: Dictionary = an.layers.back()
				for pr in [[r, top], [o, out_l]]:
					var ref: BWCharacter = pr[0]
					var src: Dictionary = pr[1]
					if src.kind == "clip":
						var l: Dictionary = ref.animator._clip_layer(str(src.clip))
						l.t = float(src.t)
						l.hold = float(src.hold)
						ref.animator.layers = [l]
						ref.animator.pending = an.pending if ref == r else ""
					else:
						ref.animator.layers = [src.duplicate()]
					ref.animator.layers[0].alpha = 1.0
					ref.animator.layers[0].fade = 0.0
				var prev := {}
				var rprev := {}
				var oprev := {}
				var pstep := {}
				for i in 24:
					an.update(DT)
					r.animator.update(DT)
					o.animator.update(DT)
					for b in bones:
						var p: Vector3 = (c.poser.globals[b] as Transform3D).origin
						var q: Vector3 = (r.poser.globals[b] as Transform3D).origin
						var w: Vector3 = (o.poser.globals[b] as Transform3D).origin
						if prev.has(b):
							var d := p.distance_to(prev[b])
							var ex := d - maxf(q.distance_to(rprev[b]), w.distance_to(oprev[b]))
							if ex > worst:
								worst = ex
							# a pop is sudden: a big excess that also jumps from the last step
							if (ex > 0.1 and d > 1.8 * float(pstep.get(b, 0.0)) + 0.02) or d > 0.35:
								bad.append("%s %s>%s %s step %.3f excess %.3f @%d" % [st, from, to, b, d, ex, i])
							pstep[b] = d
						prev[b] = p
						rprev[b] = q
						oprev[b] = w
		c.free()
		r.free()
		o.free()
	t.ok(bad.is_empty(), "no pops in any blend pair (%d; worst excess %.3f u/frame; %s)" % [bad.size(), worst, ", ".join(bad.slice(0, 12))])


## In the tree: the root runs at the clip speed; the locked ground points
## stay put in the world while their foot is down. A snap turn plays an
## authored turn; a hitch frame keeps everything finite.
func test_foot_lock_and_turn_in_world(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var c := BWCharacter.create(_unit("della"))
	holder.add_child(c)
	c.set_process(false)
	c.animator.rotate_idles = false
	for gait in ["walk", "run"]:
		c.pose(gait, 0.0)
		c.animator.play(gait, 0.0)
		var speed := c.animator.walk_speed() if gait == "walk" else c.animator.run_speed()
		var worst := 0.0
		var locked := 0
		for i in 160:
			c.position.z += speed * DT
			c._process(DT)
			for s in ["l", "r"]:
				var L: Dictionary = c.animator._lock[s]
				if L.get("on", false) and i > 30:
					var f: Dictionary = c.animator.last_pose["foot_" + s]
					var g := c.rig.skeleton.global_transform * BWAnimator.ground_point(f.pos, f.rot)
					worst = maxf(worst, Vector2(g.x - L.world.x, g.z - L.world.z).length())
					locked += 1
		t.ok(locked > 40, "%s: feet lock while down (%d samples)" % [gait, locked])
		t.ok(worst < 0.004, "%s: locked feet hold in the world (worst %.4f u)" % [gait, worst])
	# a 90 degree snap of the view while standing: the authored turn plays
	c.pose("idle", 0.0)
	for i in 40:
		c._process(DT)
	c.rotation.y += PI / 2
	c._process(DT)
	t.eq(c.animator.top_clip(), "turn_l", "a snap turn to the left plays turn_l")
	t.ok(absf(c.rig.rotation.y) > 1.2, "the visual turn starts where it was (%.2f)" % c.rig.rotation.y)
	for i in 50:
		c._process(DT)
	t.ok(absf(c.rig.rotation.y) < 0.03, "and finishes with the clip (%.3f)" % c.rig.rotation.y)
	c.rotation.y -= PI / 2
	c._process(DT)
	t.eq(c.animator.top_clip(), "turn_r", "a snap turn to the right plays turn_r")
	# a hitch (one 0.6 s frame, a load) must not blow up the springs
	c.pose("walk")
	c.position.z += 1.0
	c._process(0.6)
	c.position.z += 0.05
	c._process(DT)
	var fine := true
	for b in c.poser.globals:
		fine = fine and (c.poser.globals[b] as Transform3D).origin.is_finite()
	t.ok(fine and is_finite(c.rig.rotation.y), "a 0.6 s frame keeps every joint finite")
	holder.queue_free()
	holder.remove_child(c)
	c.free()


func test_move_plan(t) -> void:
	var v := BWUnitView.new()
	v.setup(_unit("will"))
	var d3 := 3.0 * BWAnimClips.HEX_STEP
	var p := v.plan_move(d3, 3)
	t.eq(str(p.gait), "run", "3 hexes run")
	t.ok(float(p.dur) / 3.0 < 0.75 and float(p.dur) / 3.0 > 0.4, "about 0.4-0.7 s per hex with start and stop (%.2f s/hex)" % (float(p.dur) / 3.0))
	var s: Callable = p.s
	t.near(float(s.call(0.0)), 0.0, 1e-4, "starts at 0")
	t.near(float(s.call(float(p.dur))), d3, 1e-3, "arrives")
	var mono := true
	var prev := -1.0
	var tt := 0.0
	while tt <= float(p.dur):
		var x := float(s.call(tt))
		mono = mono and x >= prev - 1e-5
		prev = x
		tt += 0.01
	t.ok(mono, "the distance never goes back")
	t.ok(float(p.stop_at) > 0.0 and float(p.stop_at) < float(p.dur), "the stop is requested before arrival")
	var long := v.plan_move(8.0 * BWAnimClips.HEX_STEP, 8)
	t.ok(float(long.dur) / 8.0 < 0.5, "long runs approach 0.42 s per hex (%.2f)" % (float(long.dur) / 8.0))
	t.eq(str(v.plan_move(BWAnimClips.HEX_STEP, 1).gait), "walk", "one hex walks")
	v.unit.hp = int(v.unit.max_hp() * 0.2)
	v.refresh()
	t.eq(str(v.plan_move(d3, 3).gait), "limp", "a wounded unit limps")
	for i in 30:
		v.character.animator.update(DT)
	t.eq(v.character.animator.top_clip(), "wounded", "below 35% HP the view stands wounded")
	v.free()


func test_fallback_and_view_api(t) -> void:
	var v := BWUnitView.new()
	v.setup(_unit("della"))
	t.ok(v.has_clip("strike") and v.has_clip("walk") and v.has_clip("kneel") and v.has_clip("run"), "view: has_clip")
	t.ok(v.walk_speed() > 1.0, "view: walk speed %.2f" % v.walk_speed())
	v.pose_named("strike")
	t.ok(v.time_to_marker("hit") > 0.0, "view: time to hit %.3f" % v.time_to_marker("hit"))
	t.ok(v.lead_to_impact("block") > 0.0 and v.lead_to_impact("dodge") > 0.0, "view: reactions lead their impact")
	t.ok(v.weapon_tip().is_finite(), "view: weapon tip")
	v.pose_named("walk")
	t.eq(v.character.pose_name(), "walk", "view: walk")
	for p in BWCharacterPose.POSE_NAMES:
		v.pose_named(p)
		t.eq(v.character.pose_name(), p, "view: pose_named(%s)" % p)
	v.free()
	# a pose name with no clip still falls back to a static key
	var c := BWCharacter.create(_unit("gail"))
	c.animator.play("zz_not_a_clip")
	t.eq(str(c.animator.layers.back().kind), "key", "unknown pose: static key layer (the safety fallback)")
	c.free()
	BWCharacter.animate = false
	var s := BWCharacter.create(_unit("della"))
	t.ok(s.animator == null, "BWCharacter.animate = false: static poses")
	s.pose("strike")
	t.eq(s.pose_name(), "strike", "static pose name")
	s.free()
	BWCharacter.animate = true


## The five hit variants per style: the knockback's travel is in the clip
## (half a hex back and home again, the root never moves) with the feet
## unlocked while they skid; the rage rears up (chest back, head back,
## stretch) on its shout; the flinch is the quick one. Every character's
## plain "hit" is in character (only the cocky shake their head).
func test_stricken_variants(t) -> void:
	var bad: PackedStringArray = []
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		var base := BWAnimClips.base_channels(set_id)
		var kb := lib.get_animation("stricken_knockback")
		var mk: Dictionary = kb.get_meta("bw").markers
		var s_end := _sample(kb, float(mk.slide_end))
		var travel := (base.root as Vector3).z - (s_end.root as Vector3).z
		if absf(travel - BWAnimStricken.KNOCK_TRAVEL) > 0.03:
			bad.append("%s knockback travel %.2f" % [set_id, travel])
		if absf(float(kb.get_meta("bw").get("travel", 0.0)) - BWAnimStricken.KNOCK_TRAVEL) > 1e-4:
			bad.append("%s knockback meta.travel" % set_id)
		var mid := _sample(kb, float(mk.slide_end) * 0.5)
		if float(mid.contact_l) > 0.01 or float(mid.contact_r) > 0.01:
			bad.append("%s knockback: the skid must unlock the feet" % set_id)
		if float(_sample(kb, float(mk.slide_end) + 0.1).contact_l) < 0.99:
			bad.append("%s knockback: the feet lock again after the slide" % set_id)
		var rg := lib.get_animation("stricken_rage")
		var sh := _sample(rg, float(rg.get_meta("bw").markers.shout) + 0.05)
		if (sh.chest as Vector3).x > -0.3 or (sh.head as Vector3).x > -0.3 or float(sh.squash) < 0.03:
			bad.append("%s rage: the shout rears up (chest %s head %s)" % [set_id, sh.chest, sh.head])
		var lens := {}
		for n in BWAnimStricken.VARIANTS:
			lens[n] = lib.get_animation(n).length
		if float(lens.stricken_flinch) >= float(lens.stricken_shrug) or float(lens.stricken_knockback) <= float(lens.stricken_shrug):
			bad.append("%s lengths %s" % [set_id, lens])
	t.ok(bad.is_empty(), "variants: travel, skid, shout, timing (%s)" % "; ".join(bad))
	# the plain "hit" per character: varied, and only the cocky keep the head-shake
	var hits := {}
	for row in BWData.table("roster"):
		var c := BWCharacter.create(BWUnit.from_roster(row))
		var clip := str(c.animator.actions.hit.clip)
		hits[clip] = true
		var cocky := str(c.animator.personality.vibe) == "cocky"
		if (clip == "stricken") != cocky:
			bad.append("%s hit %s" % [row.id, clip])
		c.pose("hit")
		c.animator.update(DT)
		if c.animator.top_clip() != clip:
			bad.append("%s plays %s" % [row.id, c.animator.top_clip()])
		c.free()
	t.ok(bad.is_empty() and hits.size() >= 3, "the plain hit is in character (%s; %s)" % [hits.keys(), ", ".join(bad)])
	# a variant plays, fires its impact, and hands back to idle
	var a := BWCharacter.create(_unit("will"))
	a.animator.rotate_idles = false
	var seen := []
	a.animator.marker.connect(func(clip: String, m: String) -> void: seen.append(clip + ":" + m))
	a.pose("stricken_rage")
	for i in 150:
		a.animator.update(DT)
	t.ok("stricken_rage:impact" in seen and "stricken_rage:shout" in seen, "rage fires impact and shout (%s)" % [seen])
	t.eq(a.animator.top_clip(), str(a.animator.actions.idle.clip), "a variant ends in the home idle")
	t.eq(a.pose_name(), "idle", "and the pose name returns to idle (idle variants rotate again)")
	a.free()


## BWReactionPick: the table (design/art/ANIMATION.md), deterministic, every
## variant reachable, temperament leans the way the brief says.
func test_reaction_pick(t) -> void:
	var alex := _unit("della")
	var hit := func(dmg: int, crit := false, glance := false) -> Dictionary:
		return { "hit": true, "damage": dmg, "crit": crit, "glance": glance, "resisted": false }
	t.eq(str(BWReactionPick.pick(alex, { "hit": false }).reaction), "dodge", "a miss dodges")
	t.eq(str(BWReactionPick.pick(alex, hit.call(50), { "ko": true }).reaction), "kneel", "a KO blow kneels (the fall follows)")
	t.eq(str(BWReactionPick.pick(alex, { "hit": true, "damage": 10, "resisted": true }).reaction), "block", "resisted blocks")
	var a1 := BWReactionPick.pick(alex, hit.call(20), { "salt": "x" })
	var a2 := BWReactionPick.pick(alex, hit.call(20), { "salt": "x" })
	t.eq(a1, a2, "deterministic")
	var counts := {}
	var by_tier := { "small": {}, "big": {}, "glance": {}, "low": {} }
	var unf := { "rage": 0, "n": 0 }
	var fri := { "rage": 0, "n": 0 }
	for row in BWData.table("roster"):
		var u := BWUnit.from_roster(row)
		var m := u.max_hp()
		for k in 12:
			var salt := "s%d" % k
			var cases := [
				["small", BWReactionPick.pick(u, hit.call(int(m * 0.04)), { "salt": salt, "hp_after": m })],
				["big", BWReactionPick.pick(u, hit.call(int(m * 0.3), k % 2 == 0), { "salt": salt, "hp_after": int(m * 0.6) })],
				["glance", BWReactionPick.pick(u, hit.call(int(m * 0.1), false, true), { "salt": salt, "hp_after": m })],
				["low", BWReactionPick.pick(u, hit.call(int(m * 0.12)), { "salt": salt, "hp_after": int(m * 0.2), "melee": false })],
				["mid", BWReactionPick.pick(u, hit.call(int(m * 0.15)), { "salt": salt, "hp_after": int(m * 0.7) })],
			]
			for cs in cases:
				var r := str(cs[1].reaction)
				counts[r] = int(counts.get(r, 0)) + 1
				if by_tier.has(cs[0]):
					by_tier[cs[0]][r] = int(by_tier[cs[0]].get(r, 0)) + 1
				if cs[0] == "mid" and u.friendliness != "neutral":
					var bucket: Dictionary = unf if u.friendliness == "unfriendly" else fri
					bucket.n += 1
					if r == "stricken_rage":
						bucket.rage += 1
	for v in BWReactionPick.VARIANTS:
		t.ok(int(counts.get(v, 0)) > 0, "%s is reachable (%s)" % [v, counts])
	t.ok((by_tier.small as Dictionary).keys().all(func(k): return k in ["stricken_flinch", "stricken_shrug"]), "tiny damage: flinch or shrug (%s)" % [by_tier.small])
	t.ok((by_tier.big as Dictionary).keys().all(func(k): return k in ["stricken_knockback", "stricken_stumble", "kneel", "stricken_rage"]), "crit or > 25%%: knockback, stumble (kneel, rage) (%s)" % [by_tier.big])
	t.ok(int(by_tier.big.get("stricken_knockback", 0)) + int(by_tier.big.get("stricken_stumble", 0)) > int(by_tier.big.get("stricken_rage", 0)) + int(by_tier.big.get("kneel", 0)), "big blows mostly knock back or stumble (%s)" % [by_tier.big])
	t.ok((by_tier.glance as Dictionary).keys().all(func(k): return k in ["block", "stricken_flinch", "stricken_shrug"]), "glance: block, flinch or shrug (%s)" % [by_tier.glance])
	var low: Dictionary = by_tier.low
	var top := ""
	for k in low:
		if top == "" or int(low[k]) > int(low[top]):
			top = k
	t.eq(top, "stricken_stumble", "below 35%% HP the stumble leads (%s)" % [low])
	# D504: margin 0.1 -> 0.05: the seeded roster's sample moved when the 11
	# new models joined the class cycles (8/84 vs 0/84 is still a clear lean)
	t.ok(float(unf.rage) / maxf(float(unf.n), 1.0) > float(fri.rage) / maxf(float(fri.n), 1.0) + 0.05, "the unfriendly rage more than the friendly (%s vs %s)" % [unf, fri])
	var alexandra := _unit("alexandra")
	t.eq(str(BWReactionPick.pick(alexandra, hit.call(int(alexandra.max_hp() * 0.04)), { "salt": "a" }).reaction), "stricken_shrug", "Alexandra (never flinches) shrugs off a scratch")


## Bows: between the strike's nock and release an arrow sits on the string
## and the string bends to the draw hand; after the release both are gone
## (the string snaps straight after a short buzz).
func test_bow_draw(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var c := BWCharacter.create(_unit("gail"))
	holder.add_child(c)
	c.set_process(false)
	c.animator.rotate_idles = false
	t.ok(c.weapon.has_string(), "the recurve bow has a drawable string")
	var nk := c.animator.marker_time("strike", "nock")
	var rel := c.animator.marker_time("strike", "release")
	c.pose("windup")
	var tt := 0.0
	while tt < nk + 0.45:
		c._process(DT)
		tt += DT
	t.ok(c.nocked_arrow() != null and c._nocked.visible, "held at the coil: an arrow is nocked")
	t.ok(c.weapon._string_bent, "held at the coil: the string is drawn to the hand")
	# (in the bow's own frame: the socket nodes only follow the skeleton on a rendered frame)
	var arrow_tail: Vector3 = (c._nocked.transform as Transform3D) * Vector3(0, 0, -c._nocked.length())
	var bow: Transform3D = (c.poser.globals.hand_l as Transform3D) * c.poser.socket_l
	var hand: Vector3 = bow.affine_inverse() * ((c.poser.globals.hand_r as Transform3D) * c.poser.socket_r).origin
	t.ok(arrow_tail.distance_to(hand) < 0.02, "the arrow's nock sits in the draw hand (%.3f)" % arrow_tail.distance_to(hand))
	var rest := BWWeaponView.v3(c.weapon.meta.tip)
	var shaft := ((c._nocked.transform as Transform3D).origin - arrow_tail).normalized()
	t.ok(shaft.dot((rest - arrow_tail).normalized()) > 0.999, "and it points through the arrow rest")
	t.ok(hand.z < BWWeaponView.v3(c.weapon.meta.string[0]).z - 0.15, "drawn: the hand is well behind the string (%.2f)" % hand.z)
	c.pose("strike")
	for i in int((rel - c.animator.marker_time("strike", "coil")) / DT) + 3:
		c._process(DT)
	t.ok(not c._nocked.visible, "released: the arrow leaves the string")
	t.ok(c.nocked_arrow() != null, "... and its last transform is handed to the flight")
	for i in 30:
		c._process(DT)
	t.ok(not c.weapon._string_bent, "the string snaps straight after its buzz")
	holder.queue_free()
	holder.remove_child(c)
	c.free()



## D65: the standing clips are calm. The approved idle keeps its shape at
## about a fifth of its old motion: the root barely bobs, the weapon hand
## barely moves, and the loop still closes. Weapon handling (D80): the
## holds are loops like the idle (both bounds); the handling one-shots move
## the weapon at full size, so only their body (the root bob) is bounded.
func test_idles_are_calm(t) -> void:
	var bad: PackedStringArray = []
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		var names: Array = ["idle", "idle_bouncy", "wounded", "idle_fidget", "idle_look", "idle_weapon"]
		for n in lib.get_animation_list():
			if str(n).begins_with("hold_") or str(n).begins_with("act_"):
				names.append(str(n))
		for n in names:
			var a := lib.get_animation(n)
			var handling := (a.get_meta("bw", {}) as Dictionary).has("handling")
			var loop := a.loop_mode != Animation.LOOP_NONE
			var lo := Vector3.INF
			var hi := -Vector3.INF
			var hlo := Vector3.INF
			var hhi := -Vector3.INF
			var tt := 0.0
			while tt <= a.length:
				var s := _sample(a, tt)
				lo = lo.min(s.root)
				hi = hi.max(s.root)
				hlo = hlo.min(s.hand_r_pos)
				hhi = hhi.max(s.hand_r_pos)
				tt += 1.0 / 60.0
			var bob := hi.y - lo.y
			var hand := (hhi - hlo).length()
			var lim := 0.025 if loop else (0.03 if handling else 0.05)
			if bob > lim:
				bad.append("%s/%s bob %.3f" % [set_id, n, bob])
			if hand > (0.06 if loop else 0.22) and not (handling and not loop):
				bad.append("%s/%s hand %.3f" % [set_id, n, hand])
	t.ok(bad.is_empty(), "standing clips are calm (%s)" % "; ".join(bad))


# ------------------------------------------------------- weapon handling (D80)

## Every style has its holds (loop, in, out) and every action of every hold,
## each a non-blocking variant that knows its holds; the personality sets
## the cadence (stoic slowest), and the showcase (roster) handles more.
func test_handling_holds_and_actions(t) -> void:
	var bad: PackedStringArray = []
	for set_id in BWAnimClips.SETS:
		var lib := BWAnimClips.load_set(set_id)
		var hs: Array = BWAnimHandling.holds(set_id)
		if hs.size() < 3:
			bad.append("%s: only %s" % [set_id, hs])
		for h in hs:
			if h == "guard":
				continue
			for n in ["hold_" + h, "hold_%s_in" % h, "hold_%s_out" % h]:
				if not lib.has_animation(n):
					bad.append("%s/%s" % [set_id, n])
			var m: Dictionary = lib.get_animation("hold_%s_in" % h).get_meta("bw", {}) if lib.has_animation("hold_%s_in" % h) else {}
			if str(m.get("from", "")) != "guard" or str(m.get("to", "")) != h or not bool(m.get("variant", false)):
				bad.append("%s/hold_%s_in meta %s" % [set_id, h, m])
		for h in hs:
			var acts: Array = BWAnimHandling.actions(set_id, h)
			if acts.is_empty():
				bad.append("%s: no actions in %s" % [set_id, h])
			for a in acts:
				if not lib.has_animation(StringName(str(a[1]))):
					bad.append("%s/%s" % [set_id, a[1]])
					continue
				var am: Dictionary = lib.get_animation(StringName(str(a[1]))).get_meta("bw", {})
				if str(am.get("from", "")) != h or str(am.get("to", "")) != h:
					bad.append("%s/%s holds %s>%s" % [set_id, a[1], am.get("from"), am.get("to")])
		for need in ["side", "guard"]:
			if not need in hs:
				bad.append("%s lacks %s" % [set_id, need])
		if set_id in ["heavy", "staff"] and not "ground" in hs:
			bad.append(set_id + " lacks ground")
		if set_id in ["one", "heavy", "polearm", "staff"] and not "shoulder" in hs:
			bad.append(set_id + " lacks shoulder")
		for a in ["act_heft", "act_admire"]:
			if not lib.has_animation(a):
				bad.append("%s/%s" % [set_id, a])
	for sp in [["bow", "act_sight"], ["pistol", "act_check"], ["pistol", "act_blow"], ["staff", "act_twirl"], ["pair", "act_spin_reverse"], ["pair", "hold_reverse_in"]]:
		if not BWAnimClips.load_set(sp[0]).has_animation(sp[1]):
			bad.append("%s/%s" % sp)
	t.ok(bad.is_empty(), "every style has its holds and handling actions (%s)" % "; ".join(bad))
	var stoic: Dictionary = BWAnimClips.handling("stoic")
	var fussy: Dictionary = BWAnimClips.handling("fussy")
	t.ok(float(stoic.hold_iv[0]) > float(fussy.hold_iv[0]) and float(stoic.act_iv[0]) > float(fussy.act_iv[0]),
		"stoic holds longer and handles less than fussy")
	var counts := []
	for show in [false, true]:
		var c := BWCharacter.create(_unit("della"))
		c.showcase = show
		var an := c.animator
		var seen := 0
		var holds := {}
		var last := ""
		var busy := false
		for i in 60 * 60:
			an.update(DT)
			var top := an.top_clip()
			if top != last and (top.begins_with("act_") or top.ends_with("_in") or top.ends_with("_out") or top.begins_with("idle_")):
				seen += 1
			holds[an.hold] = true
			busy = busy or an.is_busy()
			last = top
		counts.append([seen, holds.size()])
		t.ok(not busy, "handling never blocks (showcase %s)" % show)
		c.free()
	t.ok(int(counts[0][0]) >= 4 and int(counts[0][1]) >= 2, "60 s standing in combat: holds change and the weapon is handled (%s events, %d holds)" % [counts[0][0], counts[0][1]])
	t.ok(int(counts[1][0]) > int(counts[0][0]) and int(counts[1][1]) >= 3, "the showcase (roster) shows more (%s vs %s)" % [counts[1], counts[0]])


## Daggers: the reverse grip persists through the idle and its actions;
## any combat pose flips the blades back to forward (the hand-led return)
## inside the incoming clip; flipping back by hand ends exactly on the guard.
func test_dagger_grip_round_trip(t) -> void:
	var c := BWCharacter.create(_unit("rem"))
	var an := c.animator
	an.rotate_idles = false
	t.eq(an.grip(), "forward", "rem starts in the forward grip")
	t.ok(an.handle("reverse"), "flip to reverse")
	for i in 60:
		an.update(DT)
	t.eq(an.grip(), "reverse", "the flip ends in the reverse grip")
	t.eq(an.top_clip(), "hold_reverse", "and stands in the reverse hold")
	t.ok((an.last_pose.hand_r.aim as Vector3).y < -0.2 and (an.last_pose.hand_l.aim as Vector3).y < -0.2, "both blades point down (%s)" % an.last_pose.hand_r.aim)
	t.ok(an.handle("act_spin_reverse"), "a flip in reverse grip")
	for i in 120:
		an.update(DT)
	t.eq(an.grip(), "reverse", "the grip persists through the idle's actions")
	c.pose("idle")
	an.update(DT)
	t.eq(an.grip(), "reverse", "an idle request keeps it")
	c.pose("windup")
	t.eq(an.grip(), "forward", "a combat pose flips back to forward")
	var ref := BWCharacter.create(_unit("rem"))
	ref.animator.rotate_idles = false
	ref.pose("windup")
	for i in 30:
		an.update(DT)
		ref.animator.update(DT)
	var ra: Vector3 = (ref.animator.last_pose.hand_r.aim as Vector3).normalized()
	var ca: Vector3 = (an.last_pose.hand_r.aim as Vector3).normalized()
	t.ok(ca.dot(ra) > 0.995, "by the coil the blade is the strike's own (dot %.4f)" % ca.dot(ra))
	c.pose("strike")
	for i in 150:
		an.update(DT)
	t.eq(an.top_clip(), "idle", "after the strike: the guard idle")
	an.handle("reverse")
	for i in 60:
		an.update(DT)
	an.handle("guard")
	for i in 60:
		an.update(DT)
	t.eq(an.grip(), "forward", "flipped back to forward")
	var base := BWAnimClips.base_channels("pair")
	var a := an.library.get_animation("hold_reverse_out")
	var end := _sample(a, a.length)
	t.ok((end.hand_r_aim as Vector3).distance_to((base.hand_r_aim as Vector3).normalized()) < 0.01 and (end.hand_l_aim as Vector3).distance_to((base.hand_l_aim as Vector3).normalized()) < 0.01,
		"the flip back ends on the guard's grip")
	c.free()
	ref.free()


## Through every hold's transitions and actions no joint jumps; from every
## hold (and mid-action) every combat request blends without a pop (the
## measure of test_no_pops_any_pair: each joint's step against the outgoing
## and the incoming clip alone).
func test_handling_no_pops(t) -> void:
	var tos := ["idle", "walk", "run", "windup", "cast", "hit", "kneel", "dodge", "block", "fumble", "fall", "cheer", "stricken_knockback"]
	var bones := ["head", "foot_l", "foot_r", "chest", "hand_r", "hand_l"]
	var bad: PackedStringArray = []
	var worst := 0.0
	var steps := 0.0
	for st in REPS:
		var c := BWCharacter.create(_rep(st))
		var r := BWCharacter.create(_rep(st))
		var o := BWCharacter.create(_rep(st))
		for x in [c, r, o]:
			x.animator.rotate_idles = false
			x.animator.walk_rate = 1.0
		var an := c.animator
		c.pose("idle", 0.0)
		an.update(DT)
		var prev := {}
		var plan: Array = []
		for h in an.holds():
			if h != "guard":
				plan.append(h)
			for a in BWAnimHandling.actions(st, h):
				plan.append(str(a[1]))
			if h != "guard":
				plan.append("guard")
		for what in plan:
			an.handle(str(what))
			for i in 200:
				an.update(DT)
				for b in bones:
					var p: Vector3 = (c.poser.globals[b] as Transform3D).origin
					if prev.has(b):
						var d := p.distance_to(prev[b])
						steps = maxf(steps, d)
						if d > 0.1:
							bad.append("%s %s %s step %.3f" % [st, what, b, d])
					prev[b] = p
				var tl: Dictionary = an.layers.back()
				if tl.loop and tl.alpha >= 1.0 and i > 20:
					break
		var froms: Array = []
		for h in an.holds():
			if h != "guard":
				froms.append([h, ""])
				var acts: Array = BWAnimHandling.actions(st, h)
				if not acts.is_empty():
					froms.append([h, str(acts[0][1])])
		froms.append(["guard", "act_admire"])
		for fr in froms:
			for to in tos:
				c.pose("idle", 0.0)
				an.hold = "guard"
				an.update(DT)
				if fr[0] != "guard":
					an.handle(str(fr[0]))
					for i in 90:
						an.update(DT)
				if fr[1] != "":
					an.handle(str(fr[1]))
					for i in 25:
						an.update(DT)
				var out_l: Dictionary = (an.layers.back() as Dictionary).duplicate()
				c.pose(to)
				var top: Dictionary = an.layers.back()
				for pr in [[r, top], [o, out_l]]:
					var ref: BWCharacter = pr[0]
					var src: Dictionary = pr[1]
					var l: Dictionary = ref.animator._clip_layer(str(src.clip))
					l.t = float(src.t)
					l.hold = float(src.hold)
					ref.animator.layers = [l]
					ref.animator.pending = an.pending if ref == r else ""
					ref.animator.hold = str(fr[0]) if ref == o else "guard"
					ref.animator.layers[0].alpha = 1.0
					ref.animator.layers[0].fade = 0.0
				var p0 := {}
				var rp := {}
				var op := {}
				var ps := {}
				for i in 30:
					an.update(DT)
					r.animator.update(DT)
					o.animator.update(DT)
					for b in bones:
						var p: Vector3 = (c.poser.globals[b] as Transform3D).origin
						var q: Vector3 = (r.poser.globals[b] as Transform3D).origin
						var w: Vector3 = (o.poser.globals[b] as Transform3D).origin
						if p0.has(b):
							var d := p.distance_to(p0[b])
							var ex := d - maxf(q.distance_to(rp[b]), w.distance_to(op[b]))
							worst = maxf(worst, ex)
							if (ex > 0.1 and d > 1.8 * float(ps.get(b, 0.0)) + 0.02) or d > 0.35:
								bad.append("%s %s/%s>%s %s step %.3f excess %.3f @%d" % [st, fr[0], fr[1], to, b, d, ex, i])
							ps[b] = d
						p0[b] = p
						rp[b] = q
						op[b] = w
		c.free()
		r.free()
		o.free()
	t.ok(bad.is_empty(), "handling: no pops through the holds and into combat (%d; worst excess %.3f, largest handling step %.3f u/frame; %s)" % [bad.size(), worst, steps, ", ".join(bad.slice(0, 10))])


## Fists (D76): the full matrix plus the three skills as melee strikes with
## the cutscene's markers (Flurry: a hit marker per jab), and the view's
## skill hook routes windup / strike to them.
func test_fists_clips(t) -> void:
	var lib := BWAnimClips.load_set("fists")
	var bad: PackedStringArray = []
	for n in ["strike", "strike_flurry", "strike_uppercut", "strike_palm", "cast", "channel"]:
		if not lib.has_animation(n):
			bad.append(n)
			continue
		var mk: Dictionary = lib.get_animation(n).get_meta("bw").markers
		var seq := ["coil", "release", "hit", "recovered"] if n == "cast" else (["coil", "launch", "land", "hit", "hop_start", "hop_end", "recovered"] if n != "channel" else [])
		var prev := -1.0
		for m in seq:
			if not mk.has(m) or float(mk[m]) < prev:
				bad.append("%s %s" % [n, mk])
				break
			prev = float(mk[m])
	var fm: Dictionary = lib.get_animation("strike_flurry").get_meta("bw").markers if lib.has_animation("strike_flurry") else {}
	t.ok(fm.has("hit") and fm.has("hit2") and fm.has("hit3") and float(fm.hit) < float(fm.get("hit2", 0)) and float(fm.get("hit2", 0)) < float(fm.get("hit3", 0)),
		"flurry: three jabs, hit < hit2 < hit3 (%s)" % [fm])
	t.ok(bad.is_empty(), "fists strikes and the palm cast carry the cutscene's markers (%s)" % ", ".join(bad))
	var u := _rep("fists")
	var v := BWUnitView.new()
	v.setup(u)
	t.eq(v.character.weapon_style(), "fists", "hand wraps pose as fists")
	v.character.animator.rotate_idles = false
	v.skill = "Flurry"
	v.pose_named("windup")
	v.character.animator.update(DT)
	t.eq(v.character.animator.top_clip(), "strike_flurry", "skill hook: windup plays the flurry's coil")
	v.pose_named("strike")
	t.ok(v.time_to_marker("hit3") > v.time_to_marker("hit") and v.time_to_marker("hit") > 0.0, "strike released: hit then hit3 ahead")
	t.eq(v.skill, "", "the hook clears once the strike starts")
	v.pose_named("strike")
	v.character.animator.update(DT)
	v.free()


## D102: the skill clips a def names ("spin": one and pair; "pistol_whip":
## pistol) carry the melee markers in order, the spin's whole-body turn is
## 0 before launch and a full TAU from the hit on (the hand-over can't
## unwind), the skill hook plays them, and a set without one plays its strike.
func test_skill_clips(t) -> void:
	var bad: PackedStringArray = []
	var seq := ["coil", "launch", "land", "hit", "hop_start", "hop_end", "recovered"]
	for pr in [["one", "strike_spin"], ["pair", "strike_spin"], ["pistol", "strike_pistol_whip"]]:
		var lib := BWAnimClips.load_set(pr[0])
		if not lib.has_animation(pr[1]):
			bad.append("%s/%s missing" % pr)
			continue
		var m: Dictionary = lib.get_animation(pr[1]).get_meta("bw")
		var mk: Dictionary = m.markers
		var prev := -1.0
		for n in seq:
			if not mk.has(n) or float(mk[n]) < prev:
				bad.append("%s/%s markers %s" % [pr[0], pr[1], mk])
				break
			prev = float(mk[n])
		if mk.has("release"):
			bad.append("%s/%s has a release (it would fire a shot)" % pr)
		if pr[1] == "strike_spin":
			var ys: Array = m.get("spin_yaw", [])
			var hz := float(m.get("spin_hz", 60.0))
			var at := func(tm: float) -> float: return BWAnimator._curve(ys, tm * hz)
			if ys.is_empty() or absf(at.call(float(mk.launch))) > 0.02 or absf(at.call(float(mk.hit)) - TAU) > 0.1 or absf(at.call(float(mk.hit) + 1.0 / 24.0) - TAU) > 1e-4 \
					or absf(float(ys.back()) - TAU) > 1e-4:
				bad.append("%s spin_yaw 0 -> TAU (%s)" % [pr[0], ys.size()])
			for i in range(1, ys.size()):
				if float(ys[i]) < float(ys[i - 1]) - 1e-5:
					bad.append("%s spin_yaw goes backwards" % pr[0])
					break
	t.ok(bad.is_empty(), "skill clips: markers in order, spin turns 0 -> TAU (%s)" % ", ".join(bad))
	# the hook: a sword unit's windup holds the spin's coil, the strike turns the rig
	var v := BWUnitView.new()
	v.setup(_rep("one"))
	v.character.animator.rotate_idles = false
	v.skill = "spin"
	v.pose_named("windup")
	v.character.animator.update(DT)
	t.eq(v.character.animator.top_clip(), "strike_spin", "skill hook: windup plays the spin's coil")
	v.pose_named("strike")
	var top: Dictionary = v.character.animator.layers.back()
	top.t = float(v.character.animator.clip_meta("strike_spin").markers.land) - 0.08
	t.ok(absf(v.character.animator.spin_yaw()) > 1.0, "mid-whip the body is turned (%.2f rad)" % v.character.animator.spin_yaw())
	v.free()
	# a set without the clip falls back to its strike
	var w := BWUnitView.new()
	w.setup(_rep("heavy"))
	w.character.animator.rotate_idles = false
	w.skill = "pistol_whip"
	w.pose_named("windup")
	w.character.animator.update(DT)
	t.eq(w.character.animator.top_clip(), BWAnimClips.actions_for("heavy").strike.clip, "no clip for the skill: the class strike")
	t.eq(w.character.animator.spin_yaw(), 0.0, "no spin, no turn")
	w.free()

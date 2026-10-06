class_name BWAnimClips
extends RefCounted
## The SOURCE of every animation clip, and the baker that turns it into an
## AnimationLibrary (design/art/ANIMATION.md).
##
##   godot --headless --path game -s res://tools/build_anims.gd     # writes art/animations/*.res
##   var lib := BWAnimClips.load_set("sword_heavy")                   # runtime (BWAnimator)
##
## A clip is keyed in POSE SPACE, not bone space: the same channels the
## static key poses use (BWCharacterPose: body eulers, ankle targets, grip
## targets), plus a few animation-only channels (squash & stretch, smear,
## foot contacts). BWAnimator samples the baked tracks, blends them, and the
## solver turns each frame into bone rotations, so feet stay where they are
## put, both fists stay on a two-hander's grip, and skirts still narrow the
## stance. Blending happens in pose space too, so transitions never pop.
##
## Authoring model (per channel, like a dope sheet):
##   c.key(channel, frame, value, mode)   mode: "a" auto (Catmull-Rom),
##                                        "f" flat tangent (ease in and out: extremes, holds)
##                                        "l" linear out of this key, "s" stepped
##   c.pose(frame, {channel: value}, mode) keys several channels on one frame
##   c.marker(name, frame)                named times (hit, coil, ...): Animation markers + meta
##   c.proc(channel, Callable(frame) -> value)   procedural channel (walk feet)
## Frames are authoring frames at FPS (24, "on ones"); the bake samples at
## BAKE_HZ with linear interpolation so the game plays the curve, not the keys.
##
## Bake passes (deterministic, run after the curves):
##   - contacts: contact_l / contact_r from the foot's lowest point (the real
##     foot-nub mesh, rolled about its sole), used by the runtime foot lock
##   - edge_lead: over a frame range the weapon's edge turns to face the
##     direction the blade tip is travelling, so a cut always leads with the edge
##
## Bump ANIM_VERSION when the source changes; test_animation checks that the
## saved library matches a fresh bake of this file.

const ANIM_VERSION := 8
const FPS := 24.0
const BAKE_HZ := 60.0
const DIR := "res://art/animations/"

## Clip sets: one library per weapon STYLE (BWCharacterPose.style_for), so
## every weapon of a style shares its clips (the solver puts the fists on
## each weapon's own grip). Class variants (axes) live inside a set and are
## picked by actions_for().
const SETS: PackedStringArray = ["one", "heavy", "polearm", "spear", "staff", "pair", "bow", "pistol", "fists"]

## Every pose name a set answers (BWCharacterPose.POSE_NAMES plus the
## animation-only names walk, run, run_stop, channel).
const ACTION_NAMES: PackedStringArray = ["idle", "walk", "run", "run_stop", "windup", "strike", "cast", "channel",
	"hit", "kneel", "dodge", "block", "fumble", "fall", "cheer",
	"stricken_flinch", "stricken_shrug", "stricken_stumble", "stricken_knockback", "stricken_rage"]

## pose name -> how a set plays it, for one weapon class:
##   clip       the clip
##   hold       stop and hold at this marker ("windup" holds the strike's
##              anticipation until "strike" releases it)
##   start      a one-shot played first when the request comes from a
##              standstill (run_start before run)
##   after      {clip: marker}: when that clip is on top, start at the marker
##              (cast after channel starts at its coil)
##   hold_end   the one-shot stays on its last frame (fall: grounded, holds)
static func actions_for(set_id: String, weapon_class: String = "") -> Dictionary:
	var axe := weapon_class == "axe"
	var heavy_carry := axe and set_id == "heavy"
	var strike := "strike_axe" if axe and set_id in ["one", "heavy"] else "strike"
	var out := {
		"idle": { "clip": "idle" },
		"walk": { "clip": "walk_heavy" if heavy_carry else "walk" },
		"run": { "clip": "run_heavy" if heavy_carry else "run", "start": "run_start" },
		"run_stop": { "clip": "run_stop" },
		"windup": { "clip": strike, "hold": "coil" },
		"strike": { "clip": strike },
		"cast": { "clip": "cast", "after": { "channel": "coil" } },
		"channel": { "clip": "channel" },
		"hit": { "clip": "stricken" },
		"fumble": { "clip": "fumble" },
		"block": { "clip": "block" },
		"dodge": { "clip": "dodge" },
		"kneel": { "clip": "kneel" },
		"fall": { "clip": "fall", "hold_end": true },
		"cheer": { "clip": "cheer" },
		# the hit-reaction variants (BWAnimStricken), picked by BWReactionPick;
		# "hit" itself is re-pointed per character (personality().hit)
		"stricken_flinch": { "clip": "stricken_flinch" },
		"stricken_shrug": { "clip": "stricken_shrug" },
		"stricken_stumble": { "clip": "stricken_stumble" },
		"stricken_knockback": { "clip": "stricken_knockback" },
		"stricken_rage": { "clip": "stricken_rage" },
	}
	if set_id == "fists":
		# the fists' skills (D76) as their own pose names; BWUnitView.skill
		# routes "windup" / "strike" to them for the cutscene
		out.merge({
			"flurry": { "clip": "strike_flurry" }, "windup_flurry": { "clip": "strike_flurry", "hold": "coil" },
			"uppercut": { "clip": "strike_uppercut" }, "windup_uppercut": { "clip": "strike_uppercut", "hold": "coil" },
			"palm_burst": { "clip": "strike_palm" }, "windup_palm_burst": { "clip": "strike_palm", "hold": "coil" },
		})
	# D102: the skill clips a def names (BWSkillDef clip "spin" / "pistol_whip");
	# BWUnitView.skill routes windup / strike to them, other sets play the strike
	if set_id in ["one", "pair"]:
		out.merge({ "spin": { "clip": "strike_spin" }, "windup_spin": { "clip": "strike_spin", "hold": "coil" } })
	if set_id == "bow":
		out.merge(BWAnimBow.actions())             # D164: shot_quick / _aimed / _sky / _volley / _fan
	if set_id == "pistol":
		out.merge({ "pistol_whip": { "clip": "strike_pistol_whip" },
			"windup_pistol_whip": { "clip": "strike_pistol_whip", "hold": "coil" } })
	# D221: the fit sweep's routes (brace, leap, land, war_cry, aim, tumble,
	# reload, and the skill strikes: thrust, hook, cut, sweep, throw, grapple, hundred)
	out.merge(BWAnimSkill.actions(set_id, strike))
	return out

## Channel id -> [pose key, sub key]. Order is the track order.
const CHANNELS := {
	"root": ["root", ""], "hips": ["hips", ""], "spine": ["spine", ""], "chest": ["chest", ""],
	"neck": ["neck", ""], "head": ["head", ""],
	"foot_l_pos": ["foot_l", "pos"], "foot_l_rot": ["foot_l", "rot"], "foot_l_pole": ["foot_l", "pole"],
	"foot_r_pos": ["foot_r", "pos"], "foot_r_rot": ["foot_r", "rot"], "foot_r_pole": ["foot_r", "pole"],
	"hand_r_pos": ["hand_r", "pos"], "hand_r_aim": ["hand_r", "aim"], "hand_r_edge": ["hand_r", "edge"], "hand_r_pole": ["hand_r", "pole"],
	"hand_r_grip": ["hand_r", "grip"],
	"hand_l_pos": ["hand_l", "pos"], "hand_l_aim": ["hand_l", "aim"], "hand_l_edge": ["hand_l", "edge"],
	"hand_l_pole": ["hand_l", "pole"], "hand_l_grip": ["hand_l", "grip"],
	"flat": ["flat", ""], "squash": ["squash", ""], "head_sq": ["head_sq", ""],
	"arm_stretch": ["arm_stretch", ""], "leg_stretch": ["leg_stretch", ""],
	"contact_l": ["contact_l", ""], "contact_r": ["contact_r", ""], "smear": ["smear", ""],
	"turn": ["turn", ""], "plant": ["plant", ""],
}
## Animation-only channels and their neutral values (static keys get these).
## `turn` is the progress (0..1) of a turn-in-place clip: BWCharacter drives
## the rig's visual yaw from it while a turn clip is on top.
## `plant` (0..1) grounds the weapon: the solver tilts it about the grip (then
## nudges the grip) until its lowest end rests on the floor, per weapon, so a
## planted greatsword and a planted hatchet both touch down (weapon handling).
const EXTRAS := { "squash": 0.0, "head_sq": 0.0, "arm_stretch": 0.0, "leg_stretch": 0.0,
	"contact_l": 1.0, "contact_r": 1.0, "smear": 0.0, "turn": 0.0, "plant": 0.0 }

## Walk: one cycle (two steps) covers one hex, centre to centre.
const HEX_STEP := 1.7320508          ## sqrt(3): neighbour distance at hex size 1
const WALK_FRAMES := 16              ## cycle length in authoring frames (0.667 s)
const RUN_FRAMES := 10               ## run cycle: one hex in 0.417 s (D62: ~0.4 s per hex)

static var _cache := {}              # set id -> AnimationLibrary
static var _foot := PackedVector2Array()   # foot-nub sole profile (z, y) about the ankle
static var _roll := {}                     # pitch index -> Vector2(dz, ankle_y)


# ================================================================ clip builder

class Clip:
	extends RefCounted
	var name := ""
	var frames := 0
	var loop := false
	var keys := {}            # channel -> Array of [frame, value, mode]
	var procs := {}           # channel -> Callable(frame) -> value
	var markers := {}         # name -> frame
	var meta := {}
	var edge_lead: Array = [] # [from, to, weight] or [[from, to, weight, hand], ...]
	var skid: Array = []      # [[from, to], ...]: frames where the feet slide (contacts forced off)
	var calm := 1.0           # < 1: the bake scales the motion down (loops about their mean, one-shots about the guard)
	var calm_hands := true    # false: the calm pass leaves the hands (weapon handling stays readable)
	var base := {}            # channel -> value (the set's guard pose)
	var style := "heavy"

	func key(ch: String, f: float, v: Variant, mode: String = "a") -> Clip:
		assert(BWAnimClips.CHANNELS.has(ch), "unknown channel " + ch)
		if not keys.has(ch):
			keys[ch] = []
		var arr: Array = keys[ch]
		for i in arr.size():
			if is_equal_approx(float(arr[i][0]), f):
				arr[i] = [f, v, mode]
				return self
		arr.append([f, v, mode])
		arr.sort_custom(func(a, b): return a[0] < b[0])
		return self

	func pose(f: float, d: Dictionary, mode: String = "a") -> Clip:
		for ch in d:
			key(ch, f, d[ch], mode)
		return self

	func marker(n: String, f: float) -> Clip:
		markers[n] = f
		return self

	func proc(ch: String, c: Callable) -> Clip:
		procs[ch] = c
		return self

	## Key every channel listed at its base (idle) value: used to pin the
	## first and last frames of one-shots to the idle so they hand over cleanly.
	func at_base(f: float, chans: Array, mode: String = "f") -> Clip:
		for ch in chans:
			key(ch, f, base[ch], mode)
		return self

	## Key a whole hold (a dictionary of channels, e.g. from BWAnimCarry).
	func hold(f: float, d: Dictionary, mode: String = "a") -> Clip:
		return pose(f, d, mode)

	func lead(f0: float, f1: float, w: float, hand: String = "hand_r") -> Clip:
		edge_lead.append([f0, f1, w, hand])
		return self

	func value(ch: String, f: float) -> Variant:
		if procs.has(ch):
			return procs[ch].call(f)
		if not keys.has(ch):
			return base[ch]
		return BWAnimClips.eval_keys(keys[ch], f, loop, float(frames))


# ================================================================== curves

## Cubic Hermite through keys. Auto tangents are Catmull-Rom (non-uniform
## spacing aware); "f" keys have zero tangents (slow in / slow out); "l" makes
## the segment after the key linear; "s" holds the key's value until the next.
static func eval_keys(arr: Array, f: float, loop: bool, length: float) -> Variant:
	var n := arr.size()
	if n == 1:
		return arr[0][1]
	if loop:
		f = fposmod(f, length)
	# keys for a loop wrap around: the curve sees [last - length] ... [first + length]
	var ks: Array = arr
	if loop:
		var last: Array = arr[n - 1]
		var first: Array = arr[0]
		ks = [[float(last[0]) - length, last[1], last[2]]] + arr + [[float(first[0]) + length, first[1], first[2]]]
		if float(arr[n - 1][0]) >= length - 0.001:
			# a key on the loop end duplicates frame 0; drop it from the wrap
			ks = [[float(arr[n - 2][0]) - length, arr[n - 2][1], arr[n - 2][2]]] + arr.slice(0, n - 1) + [[float(first[0]) + length, first[1], first[2]]]
	if f <= float(ks[0][0]):
		return ks[0][1]
	if f >= float(ks[ks.size() - 1][0]):
		return ks[ks.size() - 1][1]
	var i := 0
	while i < ks.size() - 2 and f > float(ks[i + 1][0]):
		i += 1
	var k0: Array = ks[i]
	var k1: Array = ks[i + 1]
	var f0 := float(k0[0])
	var f1 := float(k1[0])
	var span := maxf(f1 - f0, 1e-4)
	var u := clampf((f - f0) / span, 0.0, 1.0)
	var v0: Variant = k0[1]
	var v1: Variant = k1[1]
	match str(k0[2]):
		"s":
			return v0
		"l":
			return _lerp(v0, v1, u)
	var m0: Variant = _tangent(ks, i) if str(k0[2]) == "a" else _zero(v0)
	var m1: Variant = _tangent(ks, i + 1) if str(k1[2]) == "a" else _zero(v1)
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2 * u3 - 3 * u2 + 1
	var h10 := u3 - 2 * u2 + u
	var h01 := -2 * u3 + 3 * u2
	var h11 := u3 - u2
	return v0 * h00 + m0 * (h10 * span) + v1 * h01 + m1 * (h11 * span)


static func _tangent(ks: Array, i: int) -> Variant:
	var v: Variant = ks[i][1]
	if i == 0 or i == ks.size() - 1:
		return _zero(v)
	var fp := float(ks[i - 1][0])
	var fn := float(ks[i + 1][0])
	return (ks[i + 1][1] - ks[i - 1][1]) / maxf(fn - fp, 1e-4)


static func _zero(v: Variant) -> Variant:
	return Vector3.ZERO if v is Vector3 else 0.0


static func _lerp(a: Variant, b: Variant, t: float) -> Variant:
	return a + (b - a) * t


# ================================================================== the foot

## The foot nub's sole, read from base_rig.glb: (z forward, y up) of every
## vertex skinned mostly to foot_l, relative to the ankle at rest.
static func foot_profile() -> PackedVector2Array:
	if not _foot.is_empty():
		return _foot
	var scene := load(BWCharacterRig.DEFAULT_PATH) as PackedScene
	var pts := PackedVector2Array()
	if scene:
		var root := scene.instantiate()
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var fi := sk.find_bone("foot_l")
		var ankle := sk.get_bone_global_rest(fi).origin
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			var skin := (mi as MeshInstance3D).skin
			if m == null or skin == null:
				continue
			var bind := -1
			for b in skin.get_bind_count():
				if str(skin.get_bind_name(b)) == "foot_l" or skin.get_bind_bone(b) == fi:
					bind = b
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				if bones.is_empty():
					continue
				var per := bones.size() / vs.size()
				for v in vs.size():
					for k in per:
						if bones[v * per + k] == bind and ws[v * per + k] > 0.6 and vs[v].y < 0.14:
							pts.append(Vector2(vs[v].z - ankle.z, vs[v].y - ankle.y))
		root.free()
	if pts.is_empty():
		# fallback: the documented nub (ellipsoid 0.065 deep, 0.05 tall, nudged forward)
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(Vector2(0.02 + 0.065 * cos(a), -0.005 + 0.05 * sin(a)))
	# only the outline can touch the floor: keep the lower convex hull
	var hull := Geometry2D.convex_hull(pts)
	var low := PackedVector2Array()
	for q in hull:
		if q.y < -0.02:
			low.append(q)
	_foot = low if low.size() >= 3 else hull
	return _foot


## Lowest sole point about the ankle with the foot pitched by p (+ = toes
## down, the rig convention): Vector3(z, y, vertex index).
static func sole_low(p: float) -> Vector3:
	var best := Vector3(0, 1e9, -1)
	var c := cos(p)
	var s := sin(p)
	var prof := foot_profile()
	for i in prof.size():
		var q := prof[i]
		# rotate (z, y) about the ankle's X axis: toes (+z) go down for p > 0
		var y := q.y * c - q.x * s
		var z := q.y * s + q.x * c
		if y < best.y - 1e-7:
			best = Vector3(z, y, i)
	return best


## Rolling without slipping: Vector2(ankle z, ankle height) for the foot
## pitched by p, z relative to the ground point under the sole at p = 0.
## The contact vertex stays put in the world while the foot turns about it
## and hands over to the next vertex as the sole rolls, so a heel strike
## rolls onto the flat foot and a toe-off peels over the toes with no skid.
## Cached per 0.01 rad.
static func roll(p: float) -> Vector2:
	var k := int(round(clampf(p, -1.2, 1.4) * 100.0))
	if _roll.has(k):
		return _roll[k]
	var target := k / 100.0
	var prof := foot_profile()
	var a := 0.0
	var low := sole_low(0.0)
	var v := int(low.z)
	var world := 0.0                           # world z of the contact vertex
	var ankle_z := world - low.x
	var steps := int(ceil(absf(target) / 0.004))
	for i in steps:
		a = target * float(i + 1) / steps
		var nl := sole_low(a)
		var c := cos(a)
		var s := sin(a)
		if int(nl.z) != v:
			# hand over: the new vertex touches down where it is now
			var q := prof[v]
			ankle_z = world - (q.y * s + q.x * c)
			world = ankle_z + nl.x
			v = int(nl.z)
		var qv := prof[v]
		ankle_z = world - (qv.y * s + qv.x * c)
	var out := Vector2(ankle_z, -sole_low(target).y)
	_roll[k] = out
	return out


## Ankle target for a foot whose sole touches the ground at `ground`
## (x, z of the p = 0 contact) pitched by p, yawed by yaw, lifted by lift.
static func ankle(ground: Vector2, p: float, yaw: float = 0.0, lift: float = 0.0) -> Vector3:
	var r := roll(p)
	var fwd := Vector2(sin(yaw), cos(yaw))
	return Vector3(ground.x + fwd.x * r.x, r.y + lift, ground.y + fwd.y * r.x)


# =================================================================== bake

## Every clip of a set, as source.
static func clips(set_id: String) -> Array:
	if not set_id in SETS:
		return []
	var out: Array = []
	out.append_array(BWAnimIdle.clips(set_id))
	out.append_array(BWAnimLoco.clips(set_id))
	out.append_array(BWAnimAction.clips(set_id))
	out.append_array(BWAnimReact.clips(set_id))
	out.append_array(BWAnimHandling.clips(set_id))
	out.append_array(BWAnimSkill.clips(set_id))           # D221: brace, leap, the sweep's skill clips
	out.append_array(BWAnimEncounter.clips(set_id))       # D219-D220: the Colossus, the Horde's jab
	return out


## The set's guard: the static idle key for the style, with the per-style
## corrections the clips need (BWAnimCarry.guard_fix: blades out of the
## face silhouette from the cutscene and 3/4 angles).
static func base_channels(style: String = "heavy") -> Dictionary:
	var p := with_extras(BWCharacterPose.resolve("idle", style))
	var out := {}
	for ch in CHANNELS:
		var k: Array = CHANNELS[ch]
		out[ch] = p[k[0]] if k[1] == "" else p[k[0]][k[1]]
	out.merge(BWAnimCarry.guard_fix(style, out), true)
	return out


## A resolved pose with the animation-only channels at neutral.
static func with_extras(p: Dictionary) -> Dictionary:
	for k in EXTRAS:
		if not p.has(k):
			p[k] = EXTRAS[k]
	for h in ["hand_l", "hand_r"]:
		if not (p[h] as Dictionary).has("grip"):
			p[h]["grip"] = 0.0
	return p


static func _new(n: String, frames: int, loop: bool, style: String = "heavy") -> Clip:
	var c := Clip.new()
	c.name = n
	c.frames = frames
	c.loop = loop
	c.style = style
	c.base = base_channels(style)
	return c


## Public alias for the clip libraries (BWAnimIdle, BWAnimLoco, ...).
static func new_clip(n: String, frames: int, loop: bool, style: String) -> Clip:
	return _new(n, frames, loop, style)


## Bake one source clip to an Animation (value tracks "pose:<channel>",
## linear, BAKE_HZ samples; markers; meta).
static func bake(c: Clip) -> Animation:
	var a := Animation.new()
	var length := c.frames / FPS
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if c.loop else Animation.LOOP_NONE
	a.step = 1.0 / BAKE_HZ
	var n := int(round(length * BAKE_HZ))
	var samples := {}
	for ch in CHANNELS:
		var arr: Array = []
		for i in n + 1:
			arr.append(c.value(ch, i * FPS / BAKE_HZ))
		samples[ch] = arr
	_pass_edge_lead(c, samples, n)
	_pass_calm(c, samples, n)
	_pass_contacts(samples, n)
	_pass_skid(c, samples, n)
	for ch in CHANNELS:
		var t := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(t, NodePath("pose:" + ch))
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		a.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
		a.track_set_interpolation_loop_wrap(t, c.loop)
		var arr: Array = samples[ch]
		for i in arr.size():
			var v: Variant = arr[i]
			if v is Vector3 and (ch.ends_with("_aim") or ch.ends_with("_edge") or ch.ends_with("_pole")):
				v = (v as Vector3).normalized()
			a.track_insert_key(t, minf(i / BAKE_HZ, length), v)
	var marks := {}
	for m in c.markers:
		var tm := float(c.markers[m]) / FPS
		marks[m] = tm
		# Animation markers are one per time: "pose" (a still for tools) lives in
		# the meta only, so it never displaces "hit"
		if a.has_method("add_marker") and m != "pose":
			a.add_marker(StringName(m), tm)
	var meta := { "version": ANIM_VERSION, "fps": FPS, "frames": c.frames, "loop": c.loop, "markers": marks }
	meta.merge(c.meta)
	a.set_meta("bw", meta)
	return a


## The edge leads the cut: between the range's frames the edge direction is
## pulled toward the tip's direction of travel (chest frame), so the blade
## never slaps flat-first through an arc.
static func _pass_edge_lead(c: Clip, s: Dictionary, n: int) -> void:
	if c.edge_lead.is_empty():
		return
	var ranges: Array = c.edge_lead if c.edge_lead[0] is Array else [c.edge_lead + ["hand_r"]]
	for r in ranges:
		var f0 := float(r[0])
		var f1 := float(r[1])
		var w := float(r[2])
		var hk := str(r[3]) if r.size() > 3 else "hand_r"
		var tips: Array = []
		for i in n + 1:
			var aim := (s[hk + "_aim"][i] as Vector3).normalized()
			tips.append((s[hk + "_pos"][i] as Vector3) + aim * 1.0)
		for i in range(1, n):
			var f := i * FPS / BAKE_HZ
			if f < f0 or f > f1:
				continue
			var ramp := clampf(minf(f - f0, f1 - f) / 1.5, 0.0, 1.0) * w
			var vel: Vector3 = tips[i + 1] - tips[i - 1]
			var aim := (s[hk + "_aim"][i] as Vector3).normalized()
			vel -= aim * aim.dot(vel)
			if vel.length() < 0.01:
				continue
			var e0: Vector3 = s[hk + "_edge"][i]
			e0 = (e0 - aim * aim.dot(e0)).normalized()
			s[hk + "_edge"][i] = e0.slerp(vel.normalized(), ramp) if e0.dot(vel.normalized()) > -0.99 else vel.normalized()


## Calm (D65): every channel's motion scaled by c.calm about a centre:
## a loop's average pose (it keeps its posture and loops seamlessly), a
## one-shot's guard (it still starts and ends there). Directions (aims,
## edges, poles) mix the same way and are normalized at the bake.
static func _pass_calm(c: Clip, s: Dictionary, n: int) -> void:
	if c.calm >= 1.0:
		return
	for ch in CHANNELS:
		if str(ch).begins_with("contact_") or ch == "turn":
			continue
		if not c.calm_hands and (str(ch).begins_with("hand_") or ch in ["flat", "plant", "smear"]):
			continue
		var arr: Array = s[ch]
		var centre: Variant = c.base[ch]
		if c.loop:
			var sum: Variant = _zero(arr[0]) if (arr[0] is Vector3 or arr[0] is float) else null
			if sum == null:
				continue
			for i in n:
				sum = sum + arr[i]
			centre = sum / float(n)
		for i in n + 1:
			arr[i] = centre + (arr[i] - centre) * c.calm


## Skids (the knockback's slide): inside a skid range both contacts are 0,
## so the runtime foot lock lets the soles slide with the clip instead of
## pinning them and re-stepping. Eased over 1 authoring frame at each end.
static func _pass_skid(c: Clip, s: Dictionary, n: int) -> void:
	for r in c.skid:
		var f0 := float(r[0])
		var f1 := float(r[1])
		for i in n + 1:
			var f := i * FPS / BAKE_HZ
			var k := clampf(minf(f - f0, f1 - f) + 1.0, 0.0, 1.0)
			if k <= 0.0:
				continue
			for side in ["l", "r"]:
				s["contact_" + side][i] = minf(float(s["contact_" + side][i]), 1.0 - k)


## Floor + contacts. Interpolating between floor keys can dip a sole a few
## mm into the floor: lift the ankle so the lowest sole point is never below
## 0. Then contact_* = 1 while that point is on the floor (the runtime foot
## lock pins those frames in world space).
static func _pass_contacts(s: Dictionary, n: int) -> void:
	for side in ["l", "r"]:
		for i in n + 1:
			var pos: Vector3 = s["foot_%s_pos" % side][i]
			var rot: Vector3 = s["foot_%s_rot" % side][i]
			var under := pos.y + sole_low(rot.x).y
			if under < 0.0:
				pos.y -= under
				s["foot_%s_pos" % side][i] = pos
			var low := pos.y + sole_low(rot.x).y
			s["contact_" + side][i] = 1.0 - smoothstep(0.006, 0.025, low)


## Build every set (or one) as AnimationLibrary resources.
static func build_library(set_id: String) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for c in clips(set_id):
		lib.add_animation(StringName(c.name), bake(c))
	lib.set_meta("bw", { "set": set_id, "version": ANIM_VERSION, "actions": actions_for(set_id) })
	return lib


static func path_for(set_id: String) -> String:
	return DIR + set_id + ".res"


## The saved library for a set (falls back to an in-memory bake, with a
## warning, if the file is missing or older than this source).
static func load_set(set_id: String) -> AnimationLibrary:
	if _cache.has(set_id):
		return _cache[set_id]
	var lib: AnimationLibrary = null
	if ResourceLoader.exists(path_for(set_id)):
		lib = load(path_for(set_id)) as AnimationLibrary
	if lib == null or int((lib.get_meta("bw", {}) as Dictionary).get("version", -1)) != ANIM_VERSION:
		push_warning("BWAnimClips: %s missing or stale; baking in memory (run tools/build_anims.gd)" % path_for(set_id))
		lib = build_library(set_id)
	_cache[set_id] = lib
	return lib


## Which set a weapon uses ("" = none: static key poses only).
static func set_for(meta: Dictionary) -> String:
	if meta.is_empty():
		return ""
	var st := BWCharacterPose.style_for(meta)
	return st if st in SETS else ""


## D153: a character's temperament, from what it is rather than a line
## about it: its element sets the vibe, its friendliness bends it (the
## unfriendly harden, the friendly soften). Weapon and element are the
## personality now (author: "discovered naturally instead of announced").
const ELEMENT_VIBE := { "fire": "bouncy", "wind": "bouncy", "thunder": "cocky", "dark": "fussy",
	"light": "dreamy", "water": "dreamy", "ice": "stoic" }
const UNFRIENDLY_VIBE := { "bouncy": "cocky", "dreamy": "stoic" }
const FRIENDLY_VIBE := { "stoic": "dreamy", "cocky": "bouncy" }


static func vibe_of(u: BWUnit) -> String:
	if u == null:
		return "cocky"
	var v := str(ELEMENT_VIBE.get(u.element, "cocky"))
	match u.friendliness:
		"unfriendly": v = str(UNFRIENDLY_VIBE.get(v, v))
		"friendly": v = str(FRIENDLY_VIBE.get(v, v))
	return v


## A character's animation personality, picked deterministically from its id
## and its vibe (vibe_of: element + friendliness, D153). Returns:
##   vibe      bouncy | stoic | dreamy | fussy | cocky
##   idle      the home idle loop ("idle" for everyone since D65)
##   rate      playback rate of the idle loops (energy)
##   variants  the idle variants it rotates through, in its order of preference
##   interval  [min, max] seconds of standing between variants
##   walk      the walk clip for careful steps
##   cheer     its victory clip
##   hit       its default stricken clip (the plain "hit" pose)
##   handling  weapon-handling cadence and tastes (handling())
static func personality(id: String, p_vibe: String = "cocky") -> Dictionary:
	var vibe := p_vibe if p_vibe in ["bouncy", "stoic", "dreamy", "fussy", "cocky"] else "cocky"
	var h := absi(hash(id))
	# body variants (the weapon trick, idle_weapon, moved to the handling
	# actions below: its hands no longer calm down with the body)
	var pool := {
		"bouncy": ["idle_fidget", "idle_look"],
		"stoic": ["idle_look", "idle_fidget"],
		"dreamy": ["idle_look", "idle_fidget"],
		"fussy": ["idle_fidget", "idle_look"],
		"cocky": ["idle_look", "idle_fidget"],
	}
	var variants: Array = (pool[vibe] as Array).duplicate()
	# rotate the order by the id so two fussy characters don't fidget in sync
	var k := h % variants.size()
	variants = variants.slice(k) + variants.slice(0, k)
	var cheers := { "bouncy": "cheer_jump", "stoic": "cheer_cool", "dreamy": "cheer", "fussy": "cheer", "cocky": "cheer_cool" }
	var cheer: String = cheers[vibe]
	# the plain "hit" (no context: shoves, tools): a reaction in character.
	# Only the cocky keep the approved stricken's annoyed head-shake.
	var hits := { "bouncy": "stricken_flinch", "stoic": "stricken_shrug", "dreamy": "stricken_stumble",
		"fussy": "stricken_flinch", "cocky": "stricken" }
	if vibe in ["dreamy", "fussy"]:
		cheer = ["cheer", "cheer_jump", "cheer_cool"][(h / 3) % 3]
	return {
		"vibe": vibe,
		# D65: everyone stands in the calm idle (idle_bouncy is retired as a
		# home idle); rates 0.85 .. 1.0; variants about half as often as before
		"idle": "idle",
		"rate": clampf({ "bouncy": 1.0, "stoic": 0.86, "dreamy": 0.9, "fussy": 0.97, "cocky": 0.94 }[vibe] * (0.97 + 0.06 * float(h % 11) / 10.0), 0.85, 1.0),
		"variants": variants,
		"interval": { "bouncy": [8.0, 14.0], "stoic": [18.0, 28.0], "dreamy": [12.0, 20.0], "fussy": [9.0, 16.0], "cocky": [12.0, 20.0] }[vibe],
		"walk": "walk_calm" if vibe in ["stoic", "dreamy"] else "walk",
		"cheer": cheer,
		"hit": hits[vibe],
		"handling": handling(vibe),
	}


## Weapon handling (BWAnimHandling): how often a character changes how it
## holds its weapon, how often it does something with it, and what it likes.
##   hold_iv   [min, max] s standing in one hold before changing it
##   act_iv    [min, max] s between handling actions (heft, admire, trick ...)
##   holds     hold -> weight when picking the next hold
##   acts      action kind -> weight
## Stoic characters hold longest and act least; fussy ones check their
## weapon most. BWUnitView.showcase (the roster stage) shortens both.
static func handling(vibe: String) -> Dictionary:
	var t := {
		"bouncy": { "hold_iv": [8.0, 13.0], "act_iv": [5.0, 9.0],
			"holds": { "guard": 1.0, "side": 0.6, "shoulder": 1.3, "ground": 0.5, "reverse": 1.3 },
			"acts": { "heft": 1.0, "admire": 0.6, "trick": 1.5, "special": 1.2, "settle": 1.0, "lean": 0.6, "spin": 1.0 } },
		"stoic": { "hold_iv": [14.0, 22.0], "act_iv": [11.0, 18.0],
			"holds": { "guard": 1.2, "side": 0.8, "shoulder": 0.6, "ground": 1.8, "reverse": 0.6 },
			"acts": { "heft": 0.6, "admire": 0.5, "trick": 0.3, "special": 0.5, "settle": 0.6, "lean": 1.2, "spin": 0.4 } },
		"dreamy": { "hold_iv": [10.0, 16.0], "act_iv": [7.0, 12.0],
			"holds": { "guard": 0.8, "side": 1.4, "shoulder": 0.8, "ground": 1.0, "reverse": 0.8 },
			"acts": { "heft": 0.6, "admire": 1.5, "trick": 0.8, "special": 1.0, "settle": 0.8, "lean": 1.0, "spin": 0.8 } },
		"fussy": { "hold_iv": [9.0, 15.0], "act_iv": [3.5, 7.0],
			"holds": { "guard": 1.6, "side": 0.6, "shoulder": 0.6, "ground": 0.6, "reverse": 1.0 },
			"acts": { "heft": 1.2, "admire": 1.6, "trick": 0.9, "special": 1.4, "settle": 1.0, "lean": 0.6, "spin": 1.0 } },
		"cocky": { "hold_iv": [9.0, 14.0], "act_iv": [6.0, 10.0],
			"holds": { "guard": 0.9, "side": 0.7, "shoulder": 1.6, "ground": 1.0, "reverse": 1.3 },
			"acts": { "heft": 1.0, "admire": 1.1, "trick": 1.4, "special": 1.2, "settle": 1.2, "lean": 0.8, "spin": 1.2 } },
	}
	return (t.get(vibe, t.cocky) as Dictionary).duplicate(true)


# ================================================================ the clips
# Model space: +Y up, +Z forward (toward the target), +X the character's left.
# Eulers (pitch, yaw, roll): +pitch leans/tips forward, +yaw turns to her
# left, +roll tips the top toward her right (raises the left side).
# Hands: chest frame. For the two-handed flamberge hand_r is the centre
# between the fists, aim = blade direction, edge = cutting edge.

const PR := Vector3(-0.5, -0.1, -1.0)
const PL := Vector3(0.6, -0.6, -0.5)


## IDLE (60 f, 2.5 s loop). Alexandra "expects to win": chin up, weight
## sitting on one hip, the flamberge bounced in her hands like it weighs
## nothing. Two weight shifts per loop (left hip, right hip) on different
## timing from the breath, so the loop never reads as one sine.
static func _idle() -> Clip:
	var c := _new("idle", 60, true)
	var b := c.base
	# weight: over the left foot at f0, over the right at f30
	c.pose(0, { "root": Vector3(0.03, -0.044, 0.0), "hips": Vector3(0.0, -0.07, 0.085),
		"spine": Vector3(0.03, 0.02, -0.03), "chest": Vector3(0.0, 0.04, -0.05) }, "f")
	c.pose(14, { "root": Vector3(0.004, -0.030, 0.006) })
	c.pose(30, { "root": Vector3(-0.025, -0.048, 0.0), "hips": Vector3(0.0, 0.04, -0.07),
		"spine": Vector3(0.035, -0.01, 0.03), "chest": Vector3(0.02, -0.02, 0.04) }, "f")
	c.pose(44, { "root": Vector3(0.002, -0.032, 0.006) })
	# breath (2 per loop, offset from the weight): chest rises, head counters
	c.key("chest", 8, Vector3(-0.025, 0.02, -0.01))
	c.key("chest", 38, Vector3(-0.01, -0.03, 0.045))
	c.key("squash", 8, 0.012).key("squash", 22, -0.006).key("squash", 38, 0.012).key("squash", 52, -0.006)
	# the head: chin up, a slow dismissive look-off; it settles a beat after the body
	c.pose(0, { "neck": Vector3(-0.03, 0.0, 0.0), "head": Vector3(-0.07, 0.10, 0.06) }, "f")
	c.pose(18, { "head": Vector3(-0.04, 0.22, -0.02) })
	c.pose(34, { "head": Vector3(-0.08, 0.05, -0.07) }, "f")
	c.pose(50, { "head": Vector3(-0.05, -0.04, 0.02) })
	c.key("head_sq", 41, 0.0).key("head_sq", 44, 0.025).key("head_sq", 48, -0.01).key("head_sq", 52, 0.0)
	# feet: planted; the unweighted heel peels up when she sits on the other hip
	var fl := ground_of(b.foot_l_pos, 0.22)
	var fr := ground_of(b.foot_r_pos, -0.22)
	c.proc("foot_l_pos", func(f: float) -> Vector3:
		return ankle(fl, _bump(f, 30.0, 11.0) * 0.22, 0.24))
	c.proc("foot_l_rot", func(f: float) -> Vector3:
		return Vector3(_bump(f, 30.0, 11.0) * 0.22, 0.24, 0))
	c.proc("foot_r_pos", func(f: float) -> Vector3:
		return ankle(fr, _bump(fposmod(f + 30.0, 60.0), 30.0, 10.0) * 0.16, -0.24))
	c.proc("foot_r_rot", func(f: float) -> Vector3:
		return Vector3(_bump(fposmod(f + 30.0, 60.0), 30.0, 10.0) * 0.16, -0.24, 0))
	# the sword: low two-handed guard that drifts with the weight; at f36
	# she bounces it ("hup") - lift, drop, overshoot, settle. Hands drag a
	# couple of frames behind the chest.
	var h0: Vector3 = b.hand_r_pos
	# (the aims were authored against the style bar's guard aim; they are
	# keyed as the same turns away from the set's current guard, so moving
	# the guard (matrix review: blade off the face) keeps the motion)
	var ga := Vector3(-0.78, 0.58, 0.22).normalized()
	var rel := func(v: Vector3) -> Vector3: return (Quaternion(ga, v.normalized()) * (b.hand_r_aim as Vector3)).normalized()
	c.pose(2, { "hand_r_pos": h0 + Vector3(0.01, 0.0, 0.0), "hand_r_aim": rel.call(Vector3(-0.78, 0.58, 0.21)) }, "f")
	c.pose(20, { "hand_r_pos": h0 + Vector3(0.0, 0.012, 0.01), "hand_r_aim": rel.call(Vector3(-0.73, 0.62, 0.22)) })
	c.pose(33, { "hand_r_pos": h0 + Vector3(-0.012, -0.004, 0.0), "hand_r_aim": rel.call(Vector3(-0.81, 0.54, 0.24)) }, "f")
	c.pose(37, { "hand_r_pos": h0 + Vector3(-0.004, 0.065, 0.02), "hand_r_aim": rel.call(Vector3(-0.66, 0.68, 0.2)) })
	c.pose(39, { "hand_r_pos": h0 + Vector3(0.0, 0.075, 0.02), "hand_r_aim": rel.call(Vector3(-0.62, 0.72, 0.17)) }, "f")
	c.pose(43, { "hand_r_pos": h0 + Vector3(0.006, -0.022, 0.0), "hand_r_aim": rel.call(Vector3(-0.83, 0.52, 0.25)) })
	c.pose(47, { "hand_r_pos": h0 + Vector3(0.008, 0.008, 0.004), "hand_r_aim": rel.call(Vector3(-0.77, 0.59, 0.22)) })
	c.key("chest", 40, Vector3(-0.03, -0.02, 0.03))
	return c


## The ground point under a flat foot whose ankle is at `a` (yaw `yaw`):
## ankle(ground_of(a, yaw), 0, yaw) == a. Lets clips start on the static key.
static func ground_of(a: Vector3, yaw: float) -> Vector2:
	var r := roll(0.0)
	return Vector2(a.x - sin(yaw) * r.x, a.z - cos(yaw) * r.x)


## A 0..1..0 bump centred on `at`, half-width `w` frames (smooth).
static func _bump(f: float, at: float, w: float) -> float:
	var d := absf(f - at) / w
	return 0.0 if d >= 1.0 else 0.5 + 0.5 * cos(d * PI)


## WALK (16 f = 0.667 s, in place, one cycle = one hex = 1.732 u, so the
## game moves the root at 2.6 u/s). A bouncy, cocky stride: feet are
## procedural (exact stance travel, rolling heel-strike and toe-off, a lifted
## swing arc), the body is keyed on the classic contact / down / passing / up
## beats. The flamberge trails one-handed off her right hip, tip low and
## behind, and bobs late; the free left arm swings in arcs with drag.
static func _walk() -> Clip:
	var c := _new("walk", WALK_FRAMES, true)
	var T := float(WALK_FRAMES)
	var D := HEX_STEP
	var beta := 0.5                         # stance fraction: one foot down at a time
	c.meta = { "stride": D, "speed": D / (T / FPS), "beta": beta }
	for side in ["l", "r"]:
		var off := 0.0 if side == "l" else 0.5
		var x := 0.085 if side == "l" else -0.085
		var yaw := 0.10 if side == "l" else -0.10
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return _walk_foot(fposmod(f / T + off, 1.0), x, yaw, D, beta)[0])
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return _walk_foot(fposmod(f / T + off, 1.0), x, yaw, D, beta)[1])
	# body: left contact f0, down f2, passing f4, up f6; right contact f8 ...
	for half in [0, 1]:
		var f: float = half * 8.0
		var s: float = 1.0 if half == 0 else -1.0     # +1: left foot is the stance foot
		c.pose(f + 0, { "root": Vector3(0.012 * s, -0.115, 0.03), "hips": Vector3(0.0, -0.13 * s, 0.03 * s),
			"chest": Vector3(0.03, 0.11 * s, -0.02 * s), "squash": -0.01 })
		c.pose(f + 2, { "root": Vector3(0.026 * s, -0.150, 0.03), "hips": Vector3(0.02, -0.07 * s, 0.065 * s),
			"chest": Vector3(0.07, 0.06 * s, -0.05 * s), "squash": -0.035 }, "f")
		c.pose(f + 4, { "root": Vector3(0.018 * s, -0.075, 0.03), "hips": Vector3(0.0, 0.0, 0.04 * s),
			"chest": Vector3(0.02, 0.0, -0.03 * s), "squash": 0.01 })
		c.pose(f + 6, { "root": Vector3(0.004 * s, -0.035, 0.03), "hips": Vector3(-0.01, 0.08 * s, 0.0),
			"chest": Vector3(-0.01, -0.07 * s, 0.0), "squash": 0.028 }, "f")
		# the head is the heavy end: it nods a frame after the down and floats on the up
		c.pose(f + 3, { "head": Vector3(0.0, -0.05 * s, 0.03 * s), "head_sq": 0.045, "neck": Vector3(0.02, 0, 0) })
		c.pose(f + 7, { "head": Vector3(-0.1, 0.02 * s, -0.01 * s), "head_sq": -0.025, "neck": Vector3(-0.04, 0, 0) })
		# sword hand: counter to the right leg; blade bobs late (tip up after the down)
		c.pose(f + 1, { "hand_r_pos": Vector3(-0.27, -0.29, 0.03 if half == 0 else -0.08) })
		c.pose(f + 5, { "hand_r_pos": Vector3(-0.28, -0.25, -0.02 if half == 0 else -0.04) })
		c.pose(f + 4, { "hand_r_aim": Vector3(-0.22, -0.26, -0.94) })
		c.pose(f + 0, { "hand_r_aim": Vector3(-0.22, -0.42, -0.88) })
		# free left arm: pendulum arc (low at passing, high at the ends), 1 f drag
		c.pose(f + 1, { "hand_l_pos": Vector3(0.23, -0.24, -0.2) if half == 0 else Vector3(0.17, -0.12, 0.3) }, "f")
		c.pose(f + 5, { "hand_l_pos": Vector3(0.26, -0.34, 0.05) })
	c.key("spine", 0, Vector3(0.14, 0, 0))
	c.key("hand_r_edge", 0, Vector3(0, -1, 0))
	c.key("hand_r_pole", 0, Vector3(-0.8, -0.2, -0.6))
	c.key("hand_l_grip", 0, 0.0)
	c.key("hand_l_pole", 0, Vector3(0.5, -0.2, -1.0))
	c.key("flat", 0, 0.6)
	return c


## One foot of the walk at cycle phase u (0 = heel strike). Returns
## [ankle, rot]. Stance: the sole stays on one world point while the root
## advances D per cycle, so in model space it slides back at exactly the
## root speed (the runtime lock pins it in world space on top of that).
static func _walk_foot(u: float, x: float, yaw: float, D: float, beta: float) -> Array:
	return gait_foot(u, x, yaw, D, beta)


## One foot of a periodic gait at cycle phase u (0 = this foot's contact).
## g: strike (heel pitch at contact), toe (toe-off pitch), lift (swing
## height), shape (< 1 lifts early: a run's heel kick), ahead (contact point
## past half the stance travel), roll_in / peel (stance fractions of the
## heel roll and the toe peel), tuck (swing tuck toward the midline),
## match_v (true: the swing leaves and lands at the stance's own speed, so
## the foot never skids at toe-off or touchdown; the style bar's walk
## predates it and keeps its min-jerk swing).
## The defaults are the style bar's walk.
static func gait_foot(u: float, x: float, yaw: float, D: float, beta: float, g: Dictionary = {}) -> Array:
	var strike_p := float(g.get("strike", -0.30))
	var toe_p := float(g.get("toe", 0.72))
	var lift := float(g.get("lift", 0.15))
	var shape := float(g.get("shape", 0.8))
	var roll_in := float(g.get("roll_in", 0.16))
	var peel := float(g.get("peel", 0.55))
	var c0 := D * beta * 0.5 + float(g.get("ahead", 0.02))      # contact point ahead of the hips
	if u < beta:
		var s := u / beta
		var p := 0.0
		if s < roll_in:
			p = lerpf(strike_p, 0.0, _ease_out(s / roll_in))
		elif s > peel:
			p = toe_p * pow((s - peel) / (1.0 - peel), 1.6)
		var gp := Vector2(x, c0 - D * u)
		return [ankle(gp, p, yaw), Vector3(p, yaw, 0)]
	# swing: from toe-off to the next contact, ankle on a lifted arc
	var s := (u - beta) / (1.0 - beta)
	var a0 := ankle(Vector2(x, c0 - D * beta), toe_p, yaw)
	var a1 := ankle(Vector2(x, c0), strike_p, yaw)
	var e := 10 * pow(s, 3) - 15 * pow(s, 4) + 6 * pow(s, 5)    # minimum jerk
	var pos := a0.lerp(a1, e)
	if bool(g.get("match_v", false)):
		# cubic Hermite in z with end tangents at the stance speed (model space
		# -D per cycle): zero world speed at toe-off and at touchdown
		var m := -D * (1.0 - beta)
		var s2 := s * s
		var s3 := s2 * s
		pos.z = a0.z * (2 * s3 - 3 * s2 + 1) + m * (s3 - 2 * s2 + s) + a1.z * (-2 * s3 + 3 * s2) + m * (s3 - s2)
	pos.x = x - float(g.get("tuck", 0.012)) * signf(x) * sin(PI * s)
	pos.y += lift * pow(sin(PI * pow(s, shape)), 1.2)
	var p := lerpf(toe_p, strike_p, smoothstep(0.0, 1.0, s))
	p += 0.25 * sin(PI * s) * (1.0 - s)                         # toes hang after push-off
	return [pos, Vector3(p, yaw, 0)]


## A foot through a one-shot's footsteps (starts, stops, turns, kneels).
## plants: [[land_f, lift_f, Vector2 ground (clip world: x, z along the
## travel)], ...] in order; land_f of the first plant may be < 0 (planted
## from the start); lift_f of the last may be > the clip (stays planted).
## s(f): root travel along +z at frame f. The stance foot keeps its world
## ground point, so in model space it slides back by exactly the root's
## travel (no skid); the swing is a lifted minimum-jerk arc in world space.
## g: strike / toe / lift / yaw as in gait_foot.
static func plant_foot(f: float, plants: Array, s: Callable, yaw: float, g: Dictionary = {}) -> Array:
	var strike_p := float(g.get("strike", -0.30))
	var toe_p := float(g.get("toe", 0.72))
	var lift := float(g.get("lift", 0.13))
	var roll_f := float(g.get("roll_f", 1.6))       # frames of heel roll after a contact
	var peel_f := float(g.get("peel_f", 2.5))       # frames of toe peel before a lift
	var sf := float(s.call(f))
	for i in plants.size():
		var pl: Array = plants[i]
		var land := float(pl[0])
		var lift_at := float(pl[1])
		var gp: Vector2 = pl[2]
		var y := float(pl[3]) if pl.size() > 3 else yaw
		if f <= lift_at or i == plants.size() - 1:
			if f >= land or i == 0:
				# stance
				var p := 0.0
				if i > 0 and f - land < roll_f:
					p = lerpf(strike_p, 0.0, _ease_out(clampf((f - land) / roll_f, 0.0, 1.0)))
				if i < plants.size() - 1 and lift_at - f < peel_f:
					p = maxf(p, toe_p * pow(clampf(1.0 - (lift_at - f) / peel_f, 0.0, 1.0), 1.6))
				return [ankle(Vector2(gp.x, gp.y - sf), p, y), Vector3(p, y, 0)]
		# swing toward the next plant
		if i + 1 < plants.size() and f < float(plants[i + 1][0]):
			var nx: Array = plants[i + 1]
			var t0 := lift_at
			var t1 := float(nx[0])
			var q := clampf((f - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)
			var y1 := float(nx[3]) if nx.size() > 3 else yaw
			var a0 := ankle(gp, toe_p, y)
			var a1 := ankle(nx[2], strike_p, y1)
			var e := 10 * pow(q, 3) - 15 * pow(q, 4) + 6 * pow(q, 5)
			var pos := a0.lerp(a1, e)
			var d := Vector2(a1.x - a0.x, a1.z - a0.z).length()
			pos.y += minf(lift, 0.05 + d * 0.22) * pow(sin(PI * pow(q, 0.8)), 1.2)
			pos.z -= sf
			var p := lerpf(toe_p, strike_p, smoothstep(0.0, 1.0, q)) + 0.25 * sin(PI * q) * (1.0 - q)
			return [pos, Vector3(p, lerpf(y, y1, smoothstep(0.0, 1.0, q)), 0)]
	var last: Array = plants.back()
	return [ankle(Vector2(last[2].x, last[2].y - sf), 0.0, yaw), Vector3(0, yaw, 0)]


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## STRIKE (heavy set: the flamberge; 40 f = 1.67 s). Coil, dash, two-handed diagonal cut from
## over the right shoulder to low left, hit-stop, overshoot, hop back, settle.
## Markers: coil (anticipation held for "windup"), launch / land (both feet
## off the ground: the cutscene moves the root here), hit (damage frame),
## hop_start / hop_end (airborne hop back: the cutscene returns the root
## home here), recovered, pose (the still for static renders).
static func _strike_sword() -> Clip:
	var c := _new("strike", 40, false)
	var b := c.base
	c.marker("coil", 8).marker("launch", 10).marker("land", 13).marker("hit", 14)
	c.marker("hop_start", 27).marker("hop_end", 30).marker("recovered", 36).marker("pose", 14)
	# how close the dash brings her root to the target's (the blade does the rest)
	c.meta = { "engage": 1.2 }
	var all := ["root", "hips", "spine", "chest", "neck", "head", "hand_r_pos", "hand_r_aim", "hand_r_edge",
		"hand_r_pole", "hand_l_pos", "hand_l_pole", "squash", "head_sq", "arm_stretch", "flat", "smear"]
	c.at_base(0, all)
	c.at_base(40, all)
	# --- anticipation (f0-f8): the head finds the target first, then hips coil,
	# chest coils further, the blade goes back over the right shoulder last
	c.pose(2, { "head": Vector3(0.0, 0.18, 0.0) })
	c.pose(4, { "root": Vector3(0, -0.07, -0.01), "hips": Vector3(-0.02, -0.14, 0.0), "chest": Vector3(-0.03, -0.16, 0.0),
		"head": Vector3(0.02, 0.42, -0.03), "hand_r_pos": Vector3(-0.22, 0.04, 0.12), "hand_r_aim": Vector3(-0.55, 0.8, -0.1) })
	c.pose(6, { "root": Vector3(0, -0.115, -0.05), "hips": Vector3(-0.04, -0.3, 0.02), "chest": Vector3(-0.09, -0.36, 0.03),
		"head": Vector3(0.05, 0.62, -0.04), "hand_r_pos": Vector3(-0.2, 0.33, 0.0), "hand_r_aim": Vector3(-0.32, 0.68, -0.66),
		"squash": -0.02, "head_sq": 0.02 })
	c.pose(8, { "root": Vector3(0, -0.13, -0.065), "hips": Vector3(-0.05, -0.36, 0.03), "spine": Vector3(-0.04, -0.06, 0.0),
		"chest": Vector3(-0.13, -0.42, 0.05), "head": Vector3(0.07, 0.74, -0.05), "neck": Vector3(0.0, 0.0, 0.0),
		"hand_r_pos": Vector3(-0.15, 0.43, -0.07), "hand_r_aim": Vector3(-0.22, 0.52, -0.83), "hand_r_edge": Vector3(0, 1, 0.3),
		"hand_r_pole": Vector3(-1, 0.1, -0.3), "squash": 0.01, "head_sq": -0.01, "flat": 0.3 }, "f")
	# --- launch (f9 compress, f10 off the ground)
	c.pose(9, { "root": Vector3(0, -0.175, -0.04), "hips": Vector3(-0.02, -0.27, 0.02), "squash": -0.045, "head_sq": 0.045,
		"hand_r_pos": Vector3(-0.14, 0.39, -0.1) })
	c.pose(10, { "root": Vector3(0, -0.02, 0.03), "hips": Vector3(0.06, -0.04, 0.0), "spine": Vector3(0.08, 0, 0),
		"chest": Vector3(0.0, -0.32, 0.03), "squash": 0.05, "head_sq": -0.03, "hand_r_pos": Vector3(-0.12, 0.5, -0.03),
		"hand_r_aim": Vector3(-0.1, 0.72, -0.69) })
	c.pose(11, { "root": Vector3(0, 0.0, 0.06), "hips": Vector3(0.08, 0.14, -0.02), "chest": Vector3(0.05, -0.06, 0.0),
		"head": Vector3(0.02, 0.3, -0.02), "hand_r_pos": Vector3(-0.05, 0.56, 0.12), "hand_r_aim": Vector3(0.05, 0.96, -0.26) })
	# --- the cut (f12 smear, f13 land, f14 hit)
	c.pose(12, { "root": Vector3(0, -0.07, 0.08), "hips": Vector3(0.1, 0.28, -0.03), "spine": Vector3(0.1, 0.05, 0),
		"chest": Vector3(0.1, 0.26, -0.04), "head": Vector3(0.0, -0.1, 0.0), "hand_r_pos": Vector3(0.0, 0.38, 0.4),
		"hand_r_aim": Vector3(0.15, 0.76, 0.63), "arm_stretch": 0.05, "smear": 1.0, "flat": 0.15 }, "l")
	c.pose(13, { "root": Vector3(0, -0.2, 0.10), "hips": Vector3(0.12, 0.36, -0.04), "chest": Vector3(0.18, 0.45, -0.06),
		"head": Vector3(-0.04, -0.38, 0.03), "hand_r_pos": Vector3(0.08, 0.05, 0.56), "hand_r_aim": Vector3(0.45, 0.04, 0.89),
		"squash": -0.05, "head_sq": 0.02, "arm_stretch": 0.08, "smear": 1.0 }, "l")
	c.pose(14, { "root": Vector3(0, -0.22, 0.11), "chest": Vector3(0.2, 0.52, -0.07), "hand_r_pos": Vector3(0.13, -0.04, 0.53),
		"hand_r_aim": Vector3(0.55, -0.08, 0.83), "head_sq": 0.055, "squash": -0.055, "arm_stretch": 0.07, "head": Vector3(-0.02, -0.45, 0.04) })
	# hit-stop: two frames of almost nothing, then the overshoot
	c.pose(16, { "root": Vector3(0, -0.222, 0.112), "chest": Vector3(0.21, 0.55, -0.07), "hand_r_pos": Vector3(0.15, -0.07, 0.51),
		"hand_r_aim": Vector3(0.6, -0.13, 0.79), "smear": 0.35, "head_sq": 0.04, "squash": -0.045, "arm_stretch": 0.06 })
	c.pose(18, { "root": Vector3(0, -0.21, 0.10), "hips": Vector3(0.1, 0.42, -0.04), "chest": Vector3(0.24, 0.7, -0.08),
		"hand_r_pos": Vector3(0.25, -0.16, 0.38), "hand_r_aim": Vector3(0.84, -0.18, 0.5), "smear": 0.0, "squash": 0.02,
		"head_sq": -0.015, "arm_stretch": 0.02, "head": Vector3(0.12, -0.52, 0.06) }, "f")
	c.pose(22, { "root": Vector3(0, -0.195, 0.095), "chest": Vector3(0.2, 0.62, -0.06), "hand_r_pos": Vector3(0.21, -0.13, 0.41),
		"hand_r_aim": Vector3(0.78, -0.14, 0.6), "squash": 0.0, "head_sq": 0.0, "head": Vector3(0.04, -0.5, 0.03), "arm_stretch": 0.0 })
	# --- recovery: compress, hop back to the stance, settle with a bounce
	c.pose(25, { "root": Vector3(0, -0.215, 0.08), "hips": Vector3(0.06, 0.3, -0.02), "chest": Vector3(0.12, 0.4, -0.03),
		"hand_r_pos": Vector3(0.12, -0.12, 0.38), "hand_r_aim": Vector3(0.45, 0.2, 0.86), "squash": -0.03, "head_sq": 0.03 })
	c.pose(27, { "root": Vector3(0, -0.06, 0.02), "hips": Vector3(-0.02, 0.1, 0.0), "chest": Vector3(-0.02, 0.12, 0.0),
		"hand_r_pos": Vector3(-0.06, -0.08, 0.32), "hand_r_aim": Vector3(-0.25, 0.75, 0.6), "squash": 0.03, "head_sq": -0.02,
		"head": Vector3(-0.06, -0.12, 0.02) })
	c.pose(29, { "root": Vector3(0, -0.03, -0.01), "hips": Vector3(0.0, -0.02, 0.0), "chest": Vector3(0.0, 0.0, 0.0) })
	c.pose(30, { "root": Vector3(0, -0.115, -0.015), "squash": -0.04, "head_sq": 0.04, "hand_r_pos": b.hand_r_pos + Vector3(0.01, -0.05, 0.0),
		"hand_r_aim": Vector3(-0.66, 0.62, 0.4), "head": Vector3(0.06, 0.04, 0.0) }, "f")
	c.pose(33, { "root": Vector3(0, -0.02, 0.0), "squash": 0.015, "head_sq": -0.01, "hand_r_pos": b.hand_r_pos + Vector3(0, 0.03, 0) })
	c.pose(36, { "root": Vector3(0, -0.045, 0.0), "squash": 0.0, "head_sq": 0.0, "hand_r_pos": b.hand_r_pos }, "f")
	c.key("hand_r_edge", 30, b.hand_r_edge, "f")
	c.key("hand_r_pole", 22, Vector3(-1, -0.4, -0.2))
	c.key("flat", 22, 0.3).key("flat", 30, 0.8)
	c.edge_lead = [10.5, 18.0, 0.85]
	# --- feet: right foot steps back into the coil; both leave the ground at
	# f10, land in a lunge at f13; hop back at f27-f30 to the idle stance
	var fl0 := ground_of(b.foot_l_pos, 0.22)
	var fr0 := ground_of(b.foot_r_pos, -0.22)
	var fl_lunge := Vector2(0.15, 0.44)
	var fr_coil := Vector2(-0.16, -0.19)
	var fr_lunge := Vector2(-0.14, -0.31)
	c.pose(0, { "foot_l_pos": ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(2, { "foot_r_pos": ankle(fr0, 0.25, -0.3) })
	c.pose(3, { "foot_r_pos": ankle(fr0.lerp(fr_coil, 0.5), 0.2, -0.4, 0.07), "foot_r_rot": Vector3(0.2, -0.4, 0) })
	c.pose(5, { "foot_r_pos": ankle(fr_coil, 0, -0.55), "foot_r_rot": Vector3(0, -0.55, 0) }, "f")
	c.pose(9, { "foot_r_pos": ankle(fr_coil, 0, -0.55), "foot_r_rot": Vector3(0, -0.55, 0),
		"foot_l_pos": ankle(fl0, 0.4, 0.22), "foot_l_rot": Vector3(0.4, 0.22, 0) }, "f")
	c.pose(6, { "foot_l_pos": ankle(fl0, 0.3, 0.22), "foot_l_rot": Vector3(0.3, 0.22, 0) })
	c.pose(11, { "foot_l_pos": Vector3(0.14, 0.24, 0.26), "foot_l_rot": Vector3(-0.1, 0.18, 0),
		"foot_r_pos": Vector3(-0.15, 0.2, -0.28), "foot_r_rot": Vector3(0.9, -0.4, 0) })
	c.pose(13, { "foot_l_pos": ankle(fl_lunge, -0.12, 0.15), "foot_l_rot": Vector3(-0.12, 0.15, 0),
		"foot_r_pos": ankle(fr_lunge, 0.62, -0.35), "foot_r_rot": Vector3(0.62, -0.35, 0) }, "l")
	c.pose(14, { "foot_l_pos": ankle(fl_lunge, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0) }, "f")
	c.pose(25, { "foot_l_pos": ankle(fl_lunge, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0),
		"foot_r_pos": ankle(fr_lunge, 0.62, -0.35), "foot_r_rot": Vector3(0.62, -0.35, 0) }, "f")
	c.pose(28, { "foot_l_pos": Vector3(0.13, 0.18, 0.26), "foot_l_rot": Vector3(-0.15, 0.2, 0),
		"foot_r_pos": Vector3(-0.13, 0.16, -0.14), "foot_r_rot": Vector3(0.45, -0.3, 0) })
	c.pose(30, { "foot_l_pos": ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	# --- the blade, in the ROOT frame (model axes at chest height): the cut is
	# aimed at the target, not wherever the twisting chest points. Keys here
	# replace the chest-frame drafts above (round 2 of the review: with the
	# chest yawed ~1 rad at the overshoot, chest-frame aims swung the blade
	# behind her and into the floor).
	c.meta["hand_frame"] = "root"
	var hr := { 4: [Vector3(-0.24, 0.06, 0.08), Vector3(-0.6, 0.75, -0.1)],
		6: [Vector3(-0.26, 0.32, -0.06), Vector3(-0.42, 0.6, -0.68)],
		8: [Vector3(-0.24, 0.42, -0.14), Vector3(-0.35, 0.45, -0.82)],
		9: [Vector3(-0.22, 0.38, -0.17), Vector3(-0.33, 0.42, -0.85)],
		10: [Vector3(-0.18, 0.5, -0.1), Vector3(-0.18, 0.7, -0.69)],
		11: [Vector3(-0.08, 0.57, 0.08), Vector3(0.0, 0.97, -0.25)],
		12: [Vector3(0.0, 0.4, 0.38), Vector3(0.1, 0.78, 0.62)],
		13: [Vector3(0.06, 0.08, 0.55), Vector3(0.3, 0.08, 0.95)],
		14: [Vector3(0.1, -0.02, 0.55), Vector3(0.45, -0.12, 0.88)],
		16: [Vector3(0.12, -0.06, 0.53), Vector3(0.52, -0.18, 0.84)],
		18: [Vector3(0.26, -0.2, 0.4), Vector3(0.84, -0.42, 0.36)],
		22: [Vector3(0.22, -0.15, 0.43), Vector3(0.76, -0.33, 0.56)],
		25: [Vector3(0.1, -0.1, 0.42), Vector3(0.4, 0.2, 0.9)],
		27: [Vector3(-0.08, -0.06, 0.32), Vector3(-0.3, 0.75, 0.6)] }
	for f in hr:
		var mode := "f" if f in [8, 18] else ("l" if f in [12, 13] else "a")
		c.key("hand_r_pos", f, hr[f][0], mode)
		c.key("hand_r_aim", f, hr[f][1], mode)
	# less twist at the overshoot; the head stays on the target line
	c.pose(18, { "hips": Vector3(0.1, 0.36, -0.04), "chest": Vector3(0.22, 0.46, -0.08), "head": Vector3(0.12, -0.62, 0.06) }, "f")
	c.pose(22, { "chest": Vector3(0.18, 0.4, -0.06), "head": Vector3(0.04, -0.55, 0.03) })
	c.pose(14, { "chest": Vector3(0.2, 0.42, -0.07), "head": Vector3(-0.02, -0.5, 0.04) })
	c.pose(16, { "chest": Vector3(0.21, 0.45, -0.07) })
	c.key("hand_r_pole", 12, Vector3(-1, -0.3, -0.1)).key("hand_r_pole", 18, Vector3(-0.6, -1, 0.1))
	return c


## STRICKEN (32 f = 1.33 s). The blow lands on frame 0: the chest is
## shoved back at once, the head is left behind for a frame and then whips;
## the left hand lets go and flails; the right foot steps back to catch the
## weight; a second wobble; she shakes it off, re-grips and stands tall.
## Markers: impact, catch (weight caught), recovered, pose.
static func _stricken() -> Clip:
	var c := _new("stricken", 32, false)
	var b := c.base
	c.marker("impact", 0).marker("catch", 8).marker("recovered", 24).marker("pose", 4)
	var all := ["root", "hips", "spine", "chest", "neck", "head", "hand_r_pos", "hand_r_aim", "hand_l_pos",
		"hand_l_grip", "squash", "head_sq"]
	c.at_base(0, all, "l")
	c.at_base(32, all)
	# recoil: fast out of frame 0 (linear), extreme on f2-f4
	c.pose(2, { "root": Vector3(0, -0.07, -0.14), "hips": Vector3(-0.12, 0.05, 0.04), "spine": Vector3(-0.14, 0.0, 0.0),
		"chest": Vector3(-0.24, 0.1, 0.07), "neck": Vector3(0.02, 0, 0), "head": Vector3(0.14, -0.05, 0.0), "squash": 0.045,
		"head_sq": -0.03, "hand_r_pos": Vector3(-0.36, -0.14, 0.1), "hand_r_aim": Vector3(-0.85, 0.5, 0.05),
		"hand_l_grip": 0.0, "hand_l_pos": Vector3(0.36, 0.08, 0.16) })
	c.pose(4, { "root": Vector3(0, -0.09, -0.17), "chest": Vector3(-0.27, 0.14, 0.09), "neck": Vector3(-0.05, 0, 0),
		"head": Vector3(-0.2, 0.12, -0.05), "head_sq": 0.0, "squash": 0.03, "hand_l_pos": Vector3(0.44, 0.2, 0.0),
		"hand_r_pos": Vector3(-0.38, -0.12, 0.08), "hand_r_aim": Vector3(-0.88, 0.45, 0.05) }, "f")
	# the weight drops onto the stepped-back foot; the head follows through forward
	c.pose(8, { "root": Vector3(0, -0.17, -0.18), "hips": Vector3(0.0, 0.08, 0.03), "spine": Vector3(0.02, 0, 0),
		"chest": Vector3(0.04, 0.06, 0.03), "neck": Vector3(0.04, 0, 0), "head": Vector3(0.1, -0.05, 0.04),
		"squash": -0.05, "hand_r_pos": Vector3(-0.26, -0.26, 0.24), "hand_r_aim": Vector3(-0.62, 0.66, 0.4),
		"hand_l_pos": Vector3(0.36, -0.12, 0.12) })
	c.pose(9, { "head_sq": 0.06 })
	c.pose(10, { "head": Vector3(0.28, -0.08, 0.06) }, "f")
	c.pose(12, { "head_sq": -0.01 })
	# second wobble, then she shakes her head (annoyed) and re-grips
	c.pose(13, { "root": Vector3(0.02, -0.12, -0.16), "chest": Vector3(-0.04, -0.1, -0.05), "head": Vector3(0.0, 0.16, 0.06),
		"hand_l_pos": Vector3(0.22, -0.18, 0.28), "hand_l_grip": 0.3, "squash": 0.01, "head_sq": 0.0 })
	c.pose(15, { "head": Vector3(-0.02, -0.22, -0.04), "hand_l_grip": 1.0 })
	c.pose(18, { "head": Vector3(-0.05, 0.18, 0.05), "root": Vector3(0.0, -0.1, -0.12), "chest": Vector3(-0.02, 0.0, 0.0),
		"hand_r_pos": b.hand_r_pos + Vector3(0.02, -0.06, 0.0), "hand_r_aim": Vector3(-0.6, 0.7, 0.35) })
	c.pose(21, { "head": Vector3(-0.08, -0.04, 0.0) })
	c.pose(24, { "root": Vector3(0, -0.02, -0.02), "squash": 0.02, "head_sq": -0.015, "head": Vector3(-0.14, 0.06, 0.02),
		"hand_r_pos": b.hand_r_pos + Vector3(0, 0.03, 0) }, "f")
	c.pose(28, { "root": Vector3(0, -0.042, 0.0), "squash": 0.0, "head_sq": 0.0 })
	c.key("hand_l_pole", 0, PL).key("hand_l_pole", 4, Vector3(0.6, -1, 0.0)).key("hand_l_pole", 16, PL)
	# feet: right foot steps back (f2-f7) to catch, back in (f17-f22); the left heel
	# peels up while the weight is behind it
	var fl0 := ground_of(b.foot_l_pos, 0.22)
	var fr0 := ground_of(b.foot_r_pos, -0.22)
	var fr_back := Vector2(-0.16, -0.32)
	c.pose(0, { "foot_r_pos": ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0),
		"foot_l_pos": ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	c.pose(2, { "foot_r_pos": ankle(fr0, 0.3, -0.25), "foot_r_rot": Vector3(0.3, -0.25, 0) })
	c.pose(4, { "foot_r_pos": Vector3(-0.15, 0.15, -0.2), "foot_r_rot": Vector3(0.1, -0.3, 0) })
	c.pose(6, { "foot_r_pos": ankle(fr_back, -0.25, -0.35), "foot_r_rot": Vector3(-0.25, -0.35, 0) }, "l")
	c.pose(8, { "foot_r_pos": ankle(fr_back, 0, -0.35), "foot_r_rot": Vector3(0, -0.35, 0) }, "f")
	c.pose(16, { "foot_r_pos": ankle(fr_back, 0, -0.35), "foot_r_rot": Vector3(0, -0.35, 0) }, "f")
	c.pose(19, { "foot_r_pos": Vector3(-0.14, 0.14, -0.17), "foot_r_rot": Vector3(0.2, -0.3, 0) })
	c.pose(22, { "foot_r_pos": ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(4, { "foot_l_pos": ankle(fl0, 0.18, 0.22), "foot_l_rot": Vector3(0.18, 0.22, 0) })
	c.pose(9, { "foot_l_pos": ankle(fl0, 0.32, 0.22), "foot_l_rot": Vector3(0.32, 0.22, 0) }, "f")
	c.pose(16, { "foot_l_pos": ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	return c

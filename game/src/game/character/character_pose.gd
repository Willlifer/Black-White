class_name BWCharacterPose
extends RefCounted
## Static key poses for a dressed BWCharacter, solved on the rig's Skeleton3D.
##
## A pose is data, not bone angles: body-part eulers (hips, spine, chest,
## neck, head), ankle targets for the feet, and grip targets for the hands
## (position + where the weapon points). Every frame the solver runs FK down
## the spine, two-bone IK for both legs and both arms, and writes local bone
## rotations. That keeps the feet on the floor, both fists on a two-hander's
## grip (the weapon's second-hand point), the draw hand on a bow string, and
## lets the idle breathing move the hands with the chest.
##
## Poses are keyed per weapon STYLE (see style_for()), with fallbacks, so a
## new weapon class only needs a style entry where it differs.
## Interpolation happens in pose space (positions lerp, directions slerp), so
## a 0.12 s blend between two keys stays on the weapon the whole way.
##
## Frames for hand specs:
##   "chest" (default): relative to the chest bone, so hands follow lean and
##                      breathing; origin = chest pivot (1.22 at rest)
##   "root":            model axes, origin (0, 1.22, 0) + the hips offset;
##                      for aims that must stay on target (bow draw, pistols)
## Weapon frame (WEAPON_MODELS.md): +Y up the blade/shaft, +Z the edge or
## muzzle, +X the flat. `aim` = weapon +Y, `edge` = weapon +Z.
##
## The animation lane (Phase 4) replaces these keys with clips; the solver
## and the style table stay useful as the hold layer on top of them.

const POSE_NAMES: PackedStringArray = ["idle", "windup", "strike", "cast", "hit", "kneel",
	"dodge", "block", "fumble", "fall", "cheer"]
const BLEND := 0.12
const CHEST_ORIGIN := Vector3(0, 1.22, 0)
const STYLES: PackedStringArray = ["one", "spear", "pistol", "heavy", "polearm", "staff", "pair", "bow", "fists"]
const CHAIN := {
	"one": ["one", "default"],
	"spear": ["spear", "one", "default"],
	"pistol": ["pistol", "one", "default"],
	"heavy": ["heavy", "two", "default"],
	"polearm": ["polearm", "two", "default"],
	"staff": ["staff", "polearm", "two", "default"],
	"pair": ["pair", "default"],
	"bow": ["bow", "default"],
	"fists": ["fists", "default"],
}
const BODY_KEYS: PackedStringArray = ["root", "hips", "spine", "chest", "neck", "head", "foot_l", "foot_r"]
const DIR_KEYS: PackedStringArray = ["aim", "edge", "pole"]

var skeleton: Skeleton3D
var style := "one"
var hold_hand := "r"              ## hand on the weapon socket: r, l (bow) or both (pair)
var shield_arm := false            ## D520: the off hand holds a shield (its socket turned by hand_l aim / edge)
var second_point := Vector3.ZERO  ## weapon-local second-hand point (two-handers, bow string)
var has_second := false
var stride := 1.0                 ## 1 = authored stance; < 1 narrows it (skirts, robes)
var socket_r := Transform3D.IDENTITY   ## socket_weapon_r relative to hand_r
var socket_l := Transform3D.IDENTITY   ## socket_offhand_l relative to hand_l
var camera: Camera3D              ## for the flat-to-camera wrist roll; null = no roll
var hair_skeleton: Skeleton3D     ## long hair: tail bones kept hanging
var hair_push := 0.0              ## extra tail tilt back (radians) to clear collars/armour
var breathe := 0.0                ## phase input, radians; amplitude below
var current := ""                 ## last requested pose name
var weapon_roll := 0.0            ## last applied camera roll (tests, debugging)
var globals := {}                 ## bone -> skeleton-space Transform3D from the last solve
var breath_amount := 1.0          ## 0 when a clip (BWAnimator) carries its own breathing
var weapon_ends: Array = []       ## weapon-local points kept off the floor (tip, butt, limb tips)
var floor_clear := 0.03           ## how far above the floor those points must stay
var floor_fix := 0.0              ## the last solve's floor lift (metres; tests, tools)
var plant_fix := 0.0              ## the last solve's planting correction (radians of tilt + metres; tests, tools)

var _blend_time := BLEND
var _from := {}
var _to := {}
var _t := 1.0
var _state := {}
var _bones := {}                  # name -> index
var _rest := {}                   # name -> Transform3D (local rest)
var _parent := {}                 # name -> parent name
var _len := {}                    # "arm_l" -> [l1, l2] etc.
var _arm_k := 1.0                 # limb stretch factors for the current solve
var _leg_k := 1.0

static var _table := {}


func _init(sk: Skeleton3D = null) -> void:
	if sk:
		bind(sk)


func bind(sk: Skeleton3D) -> void:
	skeleton = sk
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		_bones[n] = i
		_rest[n] = sk.get_bone_rest(i)
		var p := sk.get_bone_parent(i)
		_parent[n] = sk.get_bone_name(p) if p >= 0 else ""
	for s in ["l", "r"]:
		_len["arm_" + s] = [(_rest["forearm_" + s] as Transform3D).origin.length(), (_rest["hand_" + s] as Transform3D).origin.length()]
		_len["leg_" + s] = [(_rest["shin_" + s] as Transform3D).origin.length(), (_rest["foot_" + s] as Transform3D).origin.length()]


## D520: lance-class weapons fought one-handed behind a shield (the spear
## set): the lance, the javelin and the trident, whatever their "hands".
## The other lance-class weapons (halberd, glaive, naginata) stay two-handed
## (the polearm set; a small forearm guard only).
const SHIELD_SPEARS: PackedStringArray = ["lance", "javelin", "trident"]


## Weapon style from weapons.json metadata (class + hands).
static func style_for(meta: Dictionary) -> String:
	var cls := str(meta.get("class", ""))
	var hands := str(meta.get("hands", "one"))
	match cls:
		"bow": return "bow"
		"daggers": return "pair"
		"fists": return "fists"
		"pistols": return "pistol"
		"staff": return "staff"
		"lance": return "spear" if hands != "two" or str(meta.get("id", "")) in SHIELD_SPEARS else "polearm"   # ---- D520
	if hands == "two":
		return "heavy"
	return "one"


## Set the weapon this pose set holds. meta = BWWeaponView.meta_for(id).
func set_weapon(meta: Dictionary) -> void:
	style = style_for(meta) if not meta.is_empty() else "one"
	hold_hand = "l" if style == "bow" else ("both" if style in ["pair", "fists"] else "r")
	shield_arm = style in BWAnimClips.SHIELD_SETS           # D520: the spear set holds a shield in the off hand
	weapon_ends = ends_of(meta)
	var sh: Variant = meta.get("second_hand")
	has_second = sh is Dictionary
	second_point = BWWeaponView.v3(sh.point) if has_second else Vector3.ZERO
	if not current.is_empty():
		_to = resolve(current, style)
		_t = 1.0
		_state = _to.duplicate(true)


## Start a pose. blend 0 snaps (tests, renders).
func play(pose_name: String, blend: float = BLEND) -> void:
	if not pose_name in POSE_NAMES:
		pose_name = "idle"
	current = pose_name
	_to = resolve(pose_name, style)
	if _state.is_empty() or blend <= 0.0:
		_state = _to.duplicate(true)
		_from = _state
		_t = 1.0
	else:
		_from = _state.duplicate(true)
		_t = 0.0
	_blend_time = maxf(blend, 0.001)


func is_blending() -> bool:
	return _t < 1.0


## Advance the blend and solve. Call every frame (or once after play for a still).
func update(delta: float) -> void:
	if skeleton == null or _to.is_empty():
		return
	if _t < 1.0:
		_t = minf(1.0, _t + delta / _blend_time)
		var e := 1.0 - pow(1.0 - _t, 3.0)        # ease out: snap into the key
		_state = _mix(_from, _to, e)
	apply(_state)


# ----------------------------------------------------------------- solver

## Solve one resolved pose onto the skeleton.
func apply(p: Dictionary) -> void:
	var G := {}
	var breath := sin(breathe) * breath_amount
	var root_off: Vector3 = p.root + Vector3(0, -0.006 + 0.006 * breath, 0)
	G["root"] = _rest["root"]
	var hips_l: Transform3D = _rest["hips"]
	_set_local("hips", Basis.from_euler(p.hips), hips_l.origin + root_off, G)
	_set_local("spine", Basis.from_euler(p.spine), Vector3.INF, G)
	# squash & stretch (animation clips only; static keys leave these at 0):
	# `squash` > 0 stretches the torso along the spine, < 0 compresses it;
	# `head_sq` > 0 squashes the head (shorter, wider), < 0 stretches it.
	var sq := float(p.get("squash", 0.0))
	var chest_e: Vector3 = p.chest + Vector3(-0.022 * breath, 0, 0)
	_set_local("chest", Basis.from_euler(chest_e), (_rest["chest"] as Transform3D).origin * (1.0 + sq) if sq != 0.0 else Vector3.INF, G)
	_set_local("neck", Basis.from_euler(p.neck), (_rest["neck"] as Transform3D).origin * (1.0 + sq) if sq != 0.0 else Vector3.INF, G)
	_set_local("head", Basis.from_euler(p.head + Vector3(0.012 * breath, 0, 0)), Vector3.INF, G)
	var hq := clampf(float(p.get("head_sq", 0.0)), -0.2, 0.2)
	skeleton.set_bone_pose_scale(_bones["head"], Vector3(1.0 + hq * 0.5, 1.0 - hq, 1.0 + hq * 0.5))
	_arm_k = 1.0 + clampf(float(p.get("arm_stretch", 0.0)), -0.1, 0.15)
	_leg_k = 1.0 + clampf(float(p.get("leg_stretch", 0.0)), -0.1, 0.15)
	for s in ["l", "r"]:
		_set_local("shoulder_" + s, Basis(), Vector3.INF, G)
	# legs: ankle targets in model space, knee toward the pole
	var narrow := clampf(stride, 0.0, 1.0)
	for s in ["l", "r"]:
		var f: Dictionary = p["foot_" + s]
		var target: Vector3 = f.pos
		var side := 1.0 if s == "l" else -1.0
		var neutral := Vector3(0.11 * side, target.y, 0.0)
		target = neutral.lerp(target, narrow) if narrow < 1.0 else target
		target.y = f.pos.y
		_leg(s, target, f.rot, f.pole, G)
	# arms
	var chest_x: Transform3D = G["chest"]
	var root_x := Transform3D(Basis(), CHEST_ORIGIN + root_off)
	var hr: Dictionary = p.hand_r
	var hl: Dictionary = p.hand_l
	var sr := _frame(hr, chest_x, root_x)
	var sl := _frame(hl, chest_x, root_x)
	weapon_roll = 0.0
	floor_fix = 0.0
	plant_fix = 0.0
	var plant := clampf(float(p.get("plant", 0.0)), 0.0, 1.0)
	match hold_hand:
		"r":
			var grip := _weapon_grip(hr, sr, p.flat)
			if has_second:
				# two-hander: hr.pos is the centre of the two fists
				grip.origin -= grip.basis * second_point * 0.5 * float(hl.get("grip", 0.0))
			grip = _clear_floor(_plant(grip, plant))
			var got := _arm_weapon("r", grip, sr * (hr.pole as Vector3) - sr.origin, G)
			if shield_arm:
				# D520: the off hand holds the shield: its socket turned by aim / edge like a grip
				_arm_weapon("l", _weapon_grip(hl, sl, 0.0), sl * (hl.pole as Vector3) - sl.origin, G)
			else:
				var hold := _free_target(hl, sl)
				if has_second:
					hold = hold.lerp(got * second_point, clampf(float(hl.get("grip", 0.0)), 0.0, 1.0))
				_arm_free("l", hold, sl * (hl.pole as Vector3) - sl.origin, G)
		"l":
			var grip := _clear_floor(_plant(_weapon_grip(hl, sl, p.flat), plant))
			var got := _arm_weapon("l", grip, sl * (hl.pole as Vector3) - sl.origin, G)
			var hold := _free_target(hr, sr)
			if has_second:
				hold = hold.lerp(got * second_point, clampf(float(hr.get("grip", 0.0)), 0.0, 1.0))
			_arm_free("r", hold, sr * (hr.pole as Vector3) - sr.origin, G)
		"both":
			_arm_weapon("r", _clear_floor(_plant(_weapon_grip(hr, sr, p.flat), plant)), sr * (hr.pole as Vector3) - sr.origin, G)
			_arm_weapon("l", _clear_floor(_plant(_weapon_grip(hl, sl, p.flat), plant)), sl * (hl.pole as Vector3) - sl.origin, G)
	_hair(G)
	globals = G


## The points of a weapon that must stay above the floor, weapon-local:
## the tip and the pommel / butt; a bow's two limb tips (held at its
## middle); a pistol's muzzle and the bottom of its grip.
static func ends_of(meta: Dictionary) -> Array:
	if meta.is_empty():
		return []
	var tip := BWWeaponView.v3(meta.get("tip", [0, 1, 0]))
	var ln := float(meta.get("length", 1.0))
	match str(meta.get("class", "")):
		"bow":
			return [Vector3(0, ln * 0.5, 0), Vector3(0, -ln * 0.5, 0)]
		"pistols":
			return [tip, Vector3(0, -0.12, 0)]
		"fists":
			return [tip, Vector3(-tip.x, tip.y, tip.z)]      # the knuckle faces, both hands
	return [tip, Vector3(0, tip.y - ln, 0)]


## Weapon floor clearance: if an end of the weapon held at `grip` (skeleton
## space; the floor is y = 0) would go below floor_clear, the grip is lifted
## by the shortfall (the arms follow by IK). A lift is continuous and always
## possible, where a turn about the grip cannot clear a shaft that is low at
## both ends. Clips keep their weapons up by themselves (test_animation
## bounds how much this ever lifts); it catches blends and the longest
## weapons of a style.
func _clear_floor(grip: Transform3D) -> Transform3D:
	if weapon_ends.is_empty():
		return grip
	var low := 1e9
	for e in weapon_ends:
		low = minf(low, grip.origin.y + (grip.basis * (e as Vector3)).y)
	if low >= floor_clear:
		return grip
	floor_fix = maxf(floor_fix, floor_clear - low)
	return Transform3D(grip.basis, grip.origin + Vector3(0, floor_clear - low, 0))


## Planting (the pose's `plant`, 0..1; weapon handling: a greatsword leant
## on, a staff stood butt-down): the weapon is tilted about the grip, in the
## plane of its own lean, by the smallest angle that puts its lowest end on
## the floor (at floor_clear), so every weapon of a style touches down
## whatever its length. A weapon too short to reach even upright is then
## lowered (at most 12 cm; the arms follow by IK). Weighted by `amount`,
## so a clip ramps it in as the end comes down.
func _plant(grip: Transform3D, amount: float) -> Transform3D:
	if amount <= 0.001 or weapon_ends.is_empty():
		return grip
	var target := floor_clear + 0.002
	var aim := grip.basis.y.normalized()
	var k := aim.cross(Vector3.UP)
	if k.length() < 0.05:
		k = Vector3(0, 0, 1)
	k = k.normalized()
	var low := func(th: float) -> float:
		var b := Basis(k, th) * grip.basis
		var lo := 1e9
		for e in weapon_ends:
			lo = minf(lo, grip.origin.y + (b * (e as Vector3)).y)
		return lo
	var f0: float = low.call(0.0)
	var th := 0.0
	if absf(f0 - target) > 0.001:
		var s0 := signf(f0 - target)
		var best := INF
		var best_th := 0.0
		var nearest := absf(f0 - target)
		var nearest_th := 0.0
		for dir in [1.0, -1.0]:
			var prev := 0.0
			for i in range(1, 25):
				var t1: float = dir * 0.05 * i
				var f1: float = low.call(t1)
				if absf(f1 - target) < nearest:
					nearest = absf(f1 - target)
					nearest_th = t1
				if signf(f1 - target) != s0:
					# bisect the crossing between prev and t1
					var a := prev
					var b2 := t1
					for j in 14:
						var m := (a + b2) * 0.5
						if signf(float(low.call(m)) - target) == s0:
							a = m
						else:
							b2 = m
					if absf(b2) < absf(best):
						best = absf(b2)
						best_th = b2
					break
				prev = t1
		th = best_th if best < INF else nearest_th
		# a plant is a small correction: never swing the weapon round by more
		th = clampf(th, -0.6, 0.6)
	var out := Transform3D(Basis(k, th * amount) * grip.basis, grip.origin)
	var rest: float = low.call(th) - target
	var drop := clampf(rest, -0.02, 0.12) * amount
	out.origin.y -= drop
	plant_fix = absf(th * amount) + absf(drop)
	return out


## Global transform of a hand spec's frame.
func _frame(h: Dictionary, chest_x: Transform3D, root_x: Transform3D) -> Transform3D:
	return root_x if str(h.get("frame", "chest")) == "root" else chest_x


## Skeleton-space transform of a hand frame ("chest" or "root") for a pose,
## by FK of its body eulers (no breathing): lets the animator carry hands
## keyed in one frame into another before blending.
func frame_of(p: Dictionary, frame: String) -> Transform3D:
	var root_off: Vector3 = p.root
	if frame == "root":
		return Transform3D(Basis(), CHEST_ORIGIN + root_off)
	var root_g: Transform3D = _rest["root"]
	var hr: Transform3D = _rest["hips"]
	var hips := root_g * Transform3D(hr.basis * Basis.from_euler(p.hips), hr.origin + root_off)
	var sr: Transform3D = _rest["spine"]
	var spine := hips * Transform3D(sr.basis * Basis.from_euler(p.spine), sr.origin)
	var cr: Transform3D = _rest["chest"]
	var sq := float(p.get("squash", 0.0))
	return spine * Transform3D(cr.basis * Basis.from_euler(p.chest), cr.origin * (1.0 + sq))


func _free_target(h: Dictionary, frame: Transform3D) -> Vector3:
	return frame * (h.pos as Vector3)


## The socket transform a weapon hand wants: origin = grip, +Y = aim, +Z = edge.
func _weapon_grip(h: Dictionary, frame: Transform3D, flat: float) -> Transform3D:
	var aim: Vector3 = (frame.basis * (h.aim as Vector3)).normalized()
	var edge: Vector3 = frame.basis * (h.edge as Vector3)
	edge = (edge - aim * aim.dot(edge))
	if edge.length_squared() < 1e-6:
		edge = (frame.basis.z - aim * aim.dot(frame.basis.z))
	edge = edge.normalized()
	var b := Basis(aim.cross(edge), aim, edge).orthonormalized()
	b = _flat_roll(b, frame * (h.pos as Vector3), flat)
	return Transform3D(b, frame * (h.pos as Vector3))


## Rotate the weapon about its own axis so its flat (+/-X) turns toward the
## camera: plate weapons seen edge-on shrink to their thickness (weapons lane
## open issue). `amount` 0..1 per pose; capped at 70 degrees.
func _flat_roll(b: Basis, at: Vector3, amount: float) -> Basis:
	if camera == null or amount <= 0.0 or not camera.is_inside_tree() or not skeleton.is_inside_tree():
		return b
	var cam_local := skeleton.global_transform.affine_inverse() * camera.global_position
	var c := cam_local - at
	var a := b.y
	var n := c - a * a.dot(c)
	if n.length_squared() < 1e-6:
		return b
	n = n.normalized()
	if b.x.dot(n) < 0.0:
		n = -n
	var ang := b.x.signed_angle_to(n, a)
	ang = clampf(ang, -1.22, 1.22) * clampf(amount, 0.0, 1.0)
	weapon_roll = ang
	return Basis(a, ang) * b


## Arm IK to a weapon socket transform. Returns the socket transform reached.
func _arm_weapon(s: String, grip: Transform3D, pole: Vector3, G: Dictionary) -> Transform3D:
	var sock := socket_r if s == "r" else socket_l
	var hand := grip * sock.affine_inverse()
	_arm(s, hand.origin, pole, hand.basis, G)
	return (G["hand_" + s] as Transform3D) * sock


func _arm_free(s: String, at: Vector3, pole: Vector3, G: Dictionary) -> void:
	# the fist centre is 0.03 past the wrist; aim the wrist short of the point
	var sh: Vector3 = (G["shoulder_" + s] as Transform3D) * (_rest["upper_arm_" + s] as Transform3D).origin
	var wrist := at - (at - sh).normalized() * 0.03
	_arm(s, wrist, pole, Basis(), G, true)


## Two-bone arm IK. Elbow flexion is +X (forearm toward the upper arm's +Z),
## so +Z of the upper arm faces away from the elbow pole.
func _arm(s: String, wrist: Vector3, pole: Vector3, hand_basis: Basis, G: Dictionary, free_hand: bool = false) -> void:
	var ua := "upper_arm_" + s
	var fa := "forearm_" + s
	var hn := "hand_" + s
	var sh: Vector3 = (G["shoulder_" + s] as Transform3D) * (_rest[ua] as Transform3D).origin
	var lens: Array = _len["arm_" + s]
	var pts := _two_bone(sh, wrist, pole, lens[0] * _arm_k, lens[1] * _arm_k)
	var elbow: Vector3 = pts[0]
	var w: Vector3 = pts[1]
	var y1 := (elbow - sh).normalized()
	var y2 := (w - elbow).normalized()
	var z1 := y2 - y1 * y1.dot(y2)
	if z1.length_squared() < 1e-6:
		z1 = -(pole - y1 * y1.dot(pole))
	z1 = z1.normalized()
	var x1 := y1.cross(z1)
	var b1 := Basis(x1, y1, z1)
	var z2 := x1.cross(y2).normalized()
	var b2 := Basis(x1, y2, z2)
	var bh := b2 if free_hand else hand_basis.orthonormalized()
	if not free_hand:
		# carry the wrist's twist in the forearm (round tube + elbow ball hide it)
		var rel := (b2.inverse() * bh).get_rotation_quaternion()
		var twist := 2.0 * atan2(rel.y, rel.w)
		b2 = b2 * Basis(Vector3.UP, twist)
	_set_global(ua, Transform3D(b1, sh), G)
	_set_global(fa, Transform3D(b2, elbow), G, _arm_k != 1.0)
	_set_global(hn, Transform3D(bh, w), G, _arm_k != 1.0)


## Two-bone leg IK. Knee flexion is -X (shin toward the thigh's -Z), so +Z of
## the thigh faces the knee pole.
func _leg(s: String, ankle: Vector3, rot: Vector3, pole: Vector3, G: Dictionary) -> void:
	var th := "thigh_" + s
	var sn := "shin_" + s
	var ft := "foot_" + s
	var hip: Vector3 = (G["hips"] as Transform3D) * (_rest[th] as Transform3D).origin
	var lens: Array = _len["leg_" + s]
	var pts := _two_bone(hip, ankle, pole, lens[0] * _leg_k, lens[1] * _leg_k)
	var knee: Vector3 = pts[0]
	var a: Vector3 = pts[1]
	var y1 := (knee - hip).normalized()
	var y2 := (a - knee).normalized()
	var z1 := -(y2 - y1 * y1.dot(y2))
	if z1.length_squared() < 1e-5:
		z1 = pole - y1 * y1.dot(pole)
	z1 = z1.normalized()
	var x1 := y1.cross(z1)
	_set_global(th, Transform3D(Basis(x1, y1, z1), hip), G)
	_set_global(sn, Transform3D(Basis(x1, y2, x1.cross(y2).normalized()), knee), G, _leg_k != 1.0)
	var rest_g := skeleton.get_bone_global_rest(_bones[ft])
	_set_global(ft, Transform3D(Basis.from_euler(rot) * rest_g.basis, a), G, _leg_k != 1.0)


## [joint, end] for a two-bone chain from a toward b, bending toward pole.
static func _two_bone(a: Vector3, b: Vector3, pole: Vector3, l1: float, l2: float) -> Array:
	var d := b - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.0005)
	var u := d.normalized() if d.length_squared() > 1e-8 else Vector3.DOWN
	var v := pole - u * u.dot(pole)
	if v.length_squared() < 1e-8:
		v = Vector3.FORWARD.cross(u) if absf(u.y) < 0.9 else Vector3.RIGHT
	v = v.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var joint := a + (u * cos_a + v * sin_a) * l1
	var end := joint + (a + u * dist - joint).normalized() * l2
	return [joint, end]


func _set_local(n: String, rot: Basis, pos: Vector3, G: Dictionary) -> void:
	var rest: Transform3D = _rest[n]
	var local := Transform3D(rest.basis * rot, rest.origin if pos == Vector3.INF else pos)
	var par: String = _parent[n]
	G[n] = (G[par] as Transform3D) * local if par != "" else local
	var i: int = _bones[n]
	skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(i, local.origin)


## `exact_pos`: write the solved local offset instead of the rest one (a
## stretched limb moves its child joint along the bone).
func _set_global(n: String, g: Transform3D, G: Dictionary, exact_pos: bool = false) -> void:
	var par: String = _parent[n]
	var local := (G[par] as Transform3D).affine_inverse() * g
	G[n] = g
	var i: int = _bones[n]
	skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(i, local.origin if exact_pos else (_rest[n] as Transform3D).origin)


## Long hair hangs: the first tail bone counters the head's pitch (so a lean
## doesn't drive the curtain into the back) and adds hair_push, the measured
## tilt that clears a collar, hood or chest plate (BWCharacter computes it).
func _hair(G: Dictionary) -> void:
	if hair_skeleton == null:
		return
	var i := hair_skeleton.find_bone("hair_tail_01")
	if i < 0:
		return
	var head_y: Vector3 = (G["head"] as Transform3D).basis.y
	var pitch := asin(clampf(head_y.z, -1.0, 1.0))    # + = head leaning forward
	var ang := clampf(-pitch * 0.85 - hair_push, -1.4, 0.6)
	var rest := hair_skeleton.get_bone_rest(i)
	hair_skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, ang))


# ------------------------------------------------------------- resolving

## The full pose dictionary for a pose name and weapon style.
static func resolve(pose_name: String, st: String) -> Dictionary:
	var t := table()
	var entry: Dictionary = t.get(pose_name, t.idle)
	var out: Dictionary = (t._default as Dictionary).duplicate(true)
	_merge(out, entry.get("body", {}))
	var chain: Array = CHAIN.get(st, ["default"])
	var styles: Dictionary = entry.get("styles", {})
	var idle_styles: Dictionary = (t.idle as Dictionary).styles
	for key in ["hand_r", "hand_l", "flat"] + Array(BODY_KEYS):
		for c in chain:
			if styles.has(c) and (styles[c] as Dictionary).has(key):
				var v: Variant = styles[c][key]
				if v is Dictionary and out.get(key) is Dictionary:
					_merge(out[key], v)
				else:
					out[key] = v
				break
	# weapon hands need an aim; borrow the style's idle hold if a pose skipped it
	for h in ["hand_r", "hand_l"]:
		if not (out[h] as Dictionary).has("aim"):
			for c in chain:
				if idle_styles.has(c) and (idle_styles[c] as Dictionary).has(h) and idle_styles[c][h].has("aim"):
					out[h]["aim"] = idle_styles[c][h].aim
					out[h]["edge"] = idle_styles[c][h].get("edge", Vector3.BACK)
					break
		if not (out[h] as Dictionary).has("aim"):
			out[h]["aim"] = Vector3.UP
			out[h]["edge"] = Vector3.BACK
		if not (out[h] as Dictionary).has("edge"):
			out[h]["edge"] = Vector3.BACK
	return out


static func _merge(into: Dictionary, src: Dictionary) -> void:
	for k in src:
		if src[k] is Dictionary and into.get(k) is Dictionary:
			_merge(into[k], src[k])
		else:
			into[k] = src[k]


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in b:
		var va: Variant = a.get(k, b[k])
		var vb: Variant = b[k]
		if vb is Dictionary:
			out[k] = _mix(va if va is Dictionary else vb, vb, t)
		elif vb is Vector3 and va is Vector3:
			if k in DIR_KEYS:
				var na: Vector3 = (va as Vector3).normalized()
				var nb: Vector3 = (vb as Vector3).normalized()
				if na.dot(nb) > -0.98:
					out[k] = na.slerp(nb, t)
				else:
					# (nearly) opposite: turn through a perpendicular instead of
					# snapping (a weapon flipped end for end)
					var ax := na.cross(Vector3.UP)
					if ax.length_squared() < 1e-4:
						ax = na.cross(Vector3.RIGHT)
					var r: Vector3 = na.rotated(ax.normalized(), PI * t)
					out[k] = r.slerp(nb, t * t) if r.dot(nb) > -0.98 else r
			else:
				out[k] = (va as Vector3).lerp(vb, t)
		elif (vb is float or vb is int) and (va is float or va is int):
			out[k] = lerpf(float(va), float(vb), t)
		else:
			out[k] = vb
	return out


# ----------------------------------------------------------------- table

static func _foot(x: float, z: float, yaw: float = 0.0, y: float = 0.055, pitch: float = 0.0, pole := Vector3(0, 0, 1)) -> Dictionary:
	return { "pos": Vector3(x, y, z), "rot": Vector3(pitch, yaw, 0), "pole": pole }


static func _hand(pos: Vector3, aim := Vector3.ZERO, edge := Vector3.ZERO, pole := Vector3.ZERO, frame := "", grip := -1.0) -> Dictionary:
	var h := { "pos": pos }
	if aim != Vector3.ZERO:
		h["aim"] = aim
		h["edge"] = edge if edge != Vector3.ZERO else Vector3.BACK
	if pole != Vector3.ZERO:
		h["pole"] = pole
	if frame != "":
		h["frame"] = frame
	if grip >= 0.0:
		h["grip"] = grip
	return h


## Fists (D76): the hand bone's rest direction, wrist -> knuckles, and the
## back of the hand, in SOCKET space (the socket is world-aligned at rest,
## the hand points down and out in the 35 deg A-pose). build_weapons.py
## fist_frame() models the fist pieces on the same axes; test_weapon_models
## checks the two agree. The left hand mirrors x.
const FIST_KNUCKLE_R := Vector3(-0.5718, -0.8166, 0.0797)
const FIST_BACK_R := Vector3(-0.8204, 0.5691, -0.0556)


## A fist hand spec: the knuckles drive toward `punch`, the back of the hand
## turns toward `back` (up = palm down). Solved into the socket aim/edge the
## weapon-grip IK takes, so the static fallback needs no new solver path.
static func _fist(side: String, pos: Vector3, punch: Vector3, back: Vector3, pole: Vector3, frame := "") -> Dictionary:
	var m := 1.0 if side == "r" else -1.0
	var k := Vector3(FIST_KNUCKLE_R.x * m, FIST_KNUCKLE_R.y, FIST_KNUCKLE_R.z).normalized()
	var b := Vector3(FIST_BACK_R.x * m, FIST_BACK_R.y, FIST_BACK_R.z)
	b = (b - k * k.dot(b)).normalized()
	var d := punch.normalized()
	var u := back - d * d.dot(back)
	if u.length_squared() < 1e-6:
		u = Vector3.UP - d * d.y
	u = u.normalized()
	# S maps socket axes into the frame: S*k = d, S*b = u
	var src := Basis(k, b, k.cross(b))
	var dst := Basis(d, u, d.cross(u))
	var sb := dst * src.inverse()
	return _hand(pos, sb.y.normalized(), sb.z.normalized(), pole, frame)


const PR := Vector3(-0.5, -0.1, -1.0)      # right elbow: back and out
const PL := Vector3(0.5, -0.1, -1.0)
const UP := Vector3(0, 1, 0)
const FWD := Vector3(0, 0, 1)


## Every key pose. Coordinates in metres on the 2.2-tall rig; hand positions
## in the chest frame unless frame = root. Built once.
static func table() -> Dictionary:
	if not _table.is_empty():
		return _table
	var T := {}
	T["_default"] = {
		"root": Vector3(0, -0.035, 0), "hips": Vector3.ZERO, "spine": Vector3(0.03, 0, 0),
		"chest": Vector3(0.02, 0, 0), "neck": Vector3.ZERO, "head": Vector3(0.04, 0, 0),
		"foot_l": _foot(0.12, 0.05, 0.22), "foot_r": _foot(-0.12, -0.04, -0.22),
		"hand_r": _hand(Vector3(-0.27, -0.36, 0.06), Vector3.ZERO, Vector3.ZERO, PR, "chest", 0.0),
		"hand_l": _hand(Vector3(0.27, -0.36, 0.06), Vector3.ZERO, Vector3.ZERO, PL, "chest", 0.0),
		"flat": 0.0,
	}
	# ------------------------------------------------------------- idle
	T["idle"] = { "body": {}, "styles": {
		"default": { "flat": 1.0,
			"hand_r": _hand(Vector3(-0.29, -0.26, 0.20), Vector3(-0.22, 0.8, 0.55), UP, PR),
			"hand_l": _hand(Vector3(0.26, -0.34, 0.08), Vector3.ZERO, Vector3.ZERO, PL) },
		"heavy": { "flat": 0.8,     # two-handed low guard, head up and forward
			"hand_r": _hand(Vector3(-0.16, -0.22, 0.28), Vector3(-0.55, 0.7, 0.45), FWD, PR),
			"hand_l": _hand(Vector3(0.2, -0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -0.6, -0.5), "", 1.0) },
		"polearm": { "flat": 0.8,   # stood upright at the side
			"hand_r": _hand(Vector3(-0.30, -0.10, 0.15), Vector3(0.0, 1, 0.06), FWD, PR),
			"hand_l": _hand(Vector3(0.26, -0.34, 0.08), Vector3.ZERO, Vector3.ZERO, PL, "", 0.0) },
		"staff": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.29, -0.06, 0.16), Vector3(0.03, 1, 0.05), FWD, PR),
			"hand_l": _hand(Vector3(0.26, -0.34, 0.08), Vector3.ZERO, Vector3.ZERO, PL, "", 0.0) },
		"spear": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.30, -0.16, 0.14), Vector3(0.0, 1, 0.06), FWD, PR) },
		"pair": { "flat": 1.0,
			"hand_r": _hand(Vector3(-0.26, -0.29, 0.22), Vector3(-0.2, 0.4, 0.9), UP, PR),
			"hand_l": _hand(Vector3(0.26, -0.29, 0.22), Vector3(0.2, 0.4, 0.9), UP, PL) },
		"bow": { "flat": 0.7,
			"hand_l": _hand(Vector3(0.29, -0.28, 0.12), Vector3(0.1, 1, 0.2), FWD, PL),
			"hand_r": _hand(Vector3(-0.26, -0.34, 0.08), Vector3.ZERO, Vector3.ZERO, PR, "", 0.0) },
		"pistol": { "flat": 0.3,
			"hand_r": _hand(Vector3(-0.27, -0.27, 0.22), Vector3(0, 0.87, 0.5), Vector3(0, -0.5, 0.87), PR) },
		"fists": { "flat": 0.0,     # boxer's guard: fists up at the shoulders, left leads
			"hand_r": _fist("r", Vector3(-0.19, 0.30, 0.26), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0), Vector3(-0.4, -1, -0.3)),
			"hand_l": _fist("l", Vector3(0.17, 0.34, 0.36), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0), Vector3(0.4, -1, -0.3)) },
	} }
	# ----------------------------------------------------------- windup
	T["windup"] = { "body": {
		"root": Vector3(0, -0.10, -0.05), "hips": Vector3(0, -0.35, 0), "spine": Vector3(-0.05, -0.15, 0),
		"chest": Vector3(-0.12, -0.25, 0), "head": Vector3(0.08, 0.7, 0),
		"foot_l": _foot(0.16, 0.22, 0.1), "foot_r": _foot(-0.15, -0.22, -0.45) }, "styles": {
		"default": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.26, 0.40, -0.06), Vector3(-0.35, 0.55, -0.76), UP, Vector3(-1, 0.3, 0)),
			"hand_l": _hand(Vector3(0.30, 0.02, 0.32), Vector3.ZERO, Vector3.ZERO, PL) },
		"two": { "flat": 0.5,
			"hand_r": _hand(Vector3(-0.26, 0.42, 0.0), Vector3(-0.45, 0.62, -0.64), UP, Vector3(-1, 0, 0)),
			"hand_l": _hand(Vector3(0.2, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.3, -1, -0.3), "", 1.0) },
		"polearm": { "flat": 0.3,
			"hand_r": _hand(Vector3(-0.12, -0.06, 0.06), Vector3(0.05, 0.18, 1), UP, Vector3(-0.6, -0.4, -0.8)),
			"hand_l": _hand(Vector3(0.2, 0.0, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.3, -1, 0), "", 1.0) },
		"staff": { "flat": 0.5,
			"hand_r": _hand(Vector3(-0.10, 0.30, 0.20), Vector3(0.15, 0.9, 0.3), FWD, Vector3(-1, -0.3, -0.3)),
			"hand_l": _hand(Vector3(0.2, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.5, -0.3), "", 1.0) },
		"spear": { "flat": 0.2,
			"hand_r": _hand(Vector3(-0.28, 0.38, -0.16), Vector3(0, 0.15, 1), UP, Vector3(-1, 0, -0.3)),
			"hand_l": _hand(Vector3(0.22, 0.18, 0.46), Vector3.ZERO, Vector3.ZERO, PL) },
		"pair": { "flat": 0.7,
			"hand_r": _hand(Vector3(-0.30, 0.24, -0.08), Vector3(-0.4, 0.5, -0.75), UP, Vector3(-1, 0, -0.2)),
			"hand_l": _hand(Vector3(0.28, 0.02, 0.28), Vector3(0.2, 0.6, 0.75), UP, PL) },
		"bow": { "flat": 0.0,
			"hips": Vector3(0, -0.5, 0), "spine": Vector3(0, -0.2, 0), "chest": Vector3(-0.05, -0.3, 0), "head": Vector3(0.05, 0.95, 0),
			"foot_l": _foot(0.12, 0.20, 0.2), "foot_r": _foot(-0.15, -0.20, -0.7),
			"hand_l": _hand(Vector3(0.05, 0.26, 0.64), Vector3(-0.12, 1, 0), FWD, Vector3(1, -0.2, -0.3), "root"),
			"hand_r": _hand(Vector3(-0.06, 0.36, 0.14), Vector3.ZERO, Vector3.ZERO, Vector3(-1, 0.3, -0.4), "root", 0.0) },
		"pistol": { "flat": 0.15,
			"hips": Vector3(0, -0.2, 0), "chest": Vector3(0, -0.1, 0), "head": Vector3(0, 0.3, 0),
			"hand_r": _hand(Vector3(-0.08, 0.24, 0.66), UP, FWD, Vector3(-1, -0.6, -0.2), "root"),
			"hand_l": _hand(Vector3(-0.03, 0.17, 0.58), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.6, -0.2), "root") },
		"fists": { "flat": 0.0,     # the rear fist cocked at the jaw, shoulder turned in
			"hand_r": _fist("r", Vector3(-0.17, 0.30, 0.04), Vector3(0.1, 0.2, 1), Vector3(-0.6, 0.8, 0), Vector3(-1, -0.6, -0.4)),
			"hand_l": _fist("l", Vector3(0.10, 0.30, 0.36), Vector3(0, 0.3, 1), Vector3(0.7, 0.7, 0), Vector3(0.4, -1, -0.3)) },
	} }
	# ----------------------------------------------------------- strike
	T["strike"] = { "body": {
		"root": Vector3(0, -0.16, 0.12), "hips": Vector3(0.1, 0.3, 0), "spine": Vector3(0.06, 0.1, 0),
		"chest": Vector3(0.08, 0.15, 0), "head": Vector3(-0.2, -0.55, 0),
		"foot_l": _foot(0.15, 0.44, 0.15), "foot_r": _foot(-0.13, -0.32, -0.3, 0.10, 0.45) }, "styles": {
		"default": { "flat": 0.4,
			"hand_r": _hand(Vector3(0.0, -0.04, 0.52), Vector3(0.65, 0.12, 0.75), Vector3(0, -1, 0), Vector3(-0.8, -0.4, -0.3)),
			"hand_l": _hand(Vector3(0.30, -0.10, -0.22), Vector3.ZERO, Vector3.ZERO, Vector3(0.4, 0, -1)) },
		"two": { "flat": 0.4,
			"hand_r": _hand(Vector3(0.0, 0.0, 0.46), Vector3(0, 0.12, 1), Vector3(0, -1, 0), Vector3(-1, -0.3, 0)),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.3, 0), "", 1.0) },
		"polearm": { "flat": 0.3,
			"hand_r": _hand(Vector3(-0.04, 0.06, 0.40), Vector3(0.02, 0.2, 1), UP, Vector3(-1, -0.5, -0.3)),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -1, 0), "", 1.0) },
		"staff": { "flat": 0.4,
			"hand_r": _hand(Vector3(0.0, 0.12, 0.42), Vector3(0, 0.6, 0.8), FWD, Vector3(-1, -0.5, -0.3)),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.5, -0.3), "", 1.0) },
		"spear": { "flat": 0.2,
			"hand_r": _hand(Vector3(-0.02, 0.12, 0.60), Vector3(0, 0.0, 1), UP, Vector3(-1, -0.4, -0.2)),
			"hand_l": _hand(Vector3(0.30, -0.08, -0.20), Vector3.ZERO, Vector3.ZERO, Vector3(0.4, 0, -1)) },
		"pair": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.02, 0.04, 0.62), Vector3(0.05, 0.15, 1), UP, Vector3(-1, -0.4, -0.2)),
			"hand_l": _hand(Vector3(0.28, -0.06, -0.14), Vector3(0.3, 0.6, -0.6), UP, Vector3(0.6, 0, -1)) },
		"bow": { "flat": 0.0,
			"root": Vector3(0, -0.08, 0.02), "hips": Vector3(0, -0.5, 0), "spine": Vector3(0, -0.2, 0), "chest": Vector3(-0.05, -0.3, 0), "head": Vector3(0.05, 0.95, 0),
			"foot_l": _foot(0.12, 0.20, 0.2), "foot_r": _foot(-0.15, -0.20, -0.7),
			"hand_l": _hand(Vector3(0.05, 0.27, 0.64), Vector3(-0.12, 1, 0.0), FWD, Vector3(1, -0.2, -0.3), "root"),
			"hand_r": _hand(Vector3(-0.30, 0.34, -0.22), Vector3.ZERO, Vector3.ZERO, Vector3(-0.6, 0, 1), "root", 0.0) },
		"pistol": { "flat": 0.15,
			"root": Vector3(0, -0.06, -0.03), "hips": Vector3(0, -0.2, 0), "chest": Vector3(-0.1, -0.1, 0), "head": Vector3(-0.05, 0.3, 0),
			"foot_l": _foot(0.13, 0.12, 0.1), "foot_r": _foot(-0.13, -0.12, -0.3),
			"hand_r": _hand(Vector3(-0.08, 0.32, 0.60), Vector3(0, 0.8, -0.6), Vector3(0, 0.6, 0.8), Vector3(-1, -0.6, -0.2), "root"),
			"hand_l": _hand(Vector3(-0.0, 0.14, 0.50), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.6, -0.2), "root") },
		"fists": { "flat": 0.0,     # the cross: rear arm long, palm down, lead fist back at the chin
			"hand_r": _fist("r", Vector3(-0.02, 0.30, 0.62), FWD, UP, Vector3(-1, -0.5, -0.2)),
			"hand_l": _fist("l", Vector3(0.12, 0.30, 0.20), Vector3(0, 0.4, 1), Vector3(0.7, 0.7, 0), Vector3(0.5, -1, -0.4)) },
	} }
	# ------------------------------------------------------------- cast
	T["cast"] = { "body": {
		"root": Vector3(0, -0.07, -0.02), "spine": Vector3(-0.04, 0, 0), "chest": Vector3(-0.12, 0, 0), "head": Vector3(-0.12, 0, 0),
		"foot_l": _foot(0.18, 0.10, 0.25), "foot_r": _foot(-0.16, -0.08, -0.3) }, "styles": {
		"default": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.32, -0.20, 0.16), Vector3(-0.3, 0.75, 0.55), UP, PR),
			"hand_l": _hand(Vector3(0.10, 0.20, 0.62), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -0.4, -0.6), "", 0.0) },
		"staff": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.22, 0.30, 0.38), Vector3(-0.2, 0.85, 0.45), FWD, Vector3(-1, -0.5, -0.3)),
			"hand_l": _hand(Vector3(0.2, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.5, -0.3), "", 1.0) },
		"pair": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.30, -0.20, 0.18), Vector3(-0.3, 0.6, 0.7), UP, PR),
			"hand_l": _hand(Vector3(0.12, 0.20, 0.60), Vector3(0.0, 1.0, 0.1), FWD, Vector3(0.6, -0.4, -0.6)) },
		"bow": { "flat": 0.3,
			"hand_l": _hand(Vector3(0.24, -0.05, 0.40), Vector3(0.0, 1, 0.1), FWD, PL),
			"hand_r": _hand(Vector3(-0.10, 0.20, 0.62), Vector3.ZERO, Vector3.ZERO, Vector3(-0.6, -0.4, -0.6), "", 0.0) },
		"fists": { "flat": 0.0,     # Palm Burst: heel of the open hand driven out, fingers up
			"hand_r": _fist("r", Vector3(-0.04, 0.26, 0.58), Vector3(0, 1, 0.15), Vector3(0, 0, -1), Vector3(-1, -0.5, -0.3)),
			"hand_l": _fist("l", Vector3(0.14, 0.24, 0.22), Vector3(0, 0.4, 1), Vector3(0.7, 0.7, 0), Vector3(0.5, -1, -0.4)) },
	} }
	# -------------------------------------------------------------- hit
	T["hit"] = { "body": {
		"root": Vector3(0, -0.09, -0.14), "hips": Vector3(-0.15, 0, 0.05), "spine": Vector3(-0.15, 0, 0),
		"chest": Vector3(-0.25, 0, 0.08), "neck": Vector3(-0.1, 0, 0), "head": Vector3(-0.32, 0.1, 0),
		"foot_l": _foot(0.14, 0.12, 0.2), "foot_r": _foot(-0.12, -0.20, -0.25) }, "styles": {
		"default": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.22, -0.04, 0.26), Vector3(-0.3, 0.8, 0.5), FWD, PR),
			"hand_l": _hand(Vector3(0.20, 0.02, 0.24), Vector3.ZERO, Vector3.ZERO, PL, "", 0.0) },
		"two": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.08, -0.04, 0.28), Vector3(0.35, 0.85, 0.4), FWD, PR),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, PL, "", 1.0) },
		"pair": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.18, 0.02, 0.26), Vector3(-0.3, 0.8, 0.5), UP, PR),
			"hand_l": _hand(Vector3(0.18, 0.02, 0.26), Vector3(0.3, 0.8, 0.5), UP, PL) },
		"bow": { "flat": 0.5,
			"hand_l": _hand(Vector3(0.24, -0.08, 0.22), Vector3(0.2, 1, 0.2), FWD, PL),
			"hand_r": _hand(Vector3(-0.20, 0.0, 0.24), Vector3.ZERO, Vector3.ZERO, PR, "", 0.0) },
		"fists": { "flat": 0.0,     # guard knocked back into the face
			"hand_r": _fist("r", Vector3(-0.13, 0.34, 0.16), Vector3(0.1, 1, 0.4), Vector3(-0.6, 0, 0.8), Vector3(-0.5, -1, -0.2)),
			"hand_l": _fist("l", Vector3(0.13, 0.36, 0.18), Vector3(-0.1, 1, 0.4), Vector3(0.6, 0, 0.8), Vector3(0.5, -1, -0.2)) },
	} }
	# ------------------------------------------------------------ kneel
	T["kneel"] = { "body": {
		"root": Vector3(0, -0.42, 0.02), "hips": Vector3(0.12, 0, 0), "spine": Vector3(0.15, 0, 0),
		"chest": Vector3(0.12, 0, 0), "head": Vector3(0.12, 0, 0),
		"foot_l": _foot(0.14, 0.30, 0.15), "foot_r": _foot(-0.13, -0.40, -0.1, 0.08, 1.0, Vector3(0, -0.3, 1)) }, "styles": {
		"default": { "flat": 0.8,       # blade held up, guard raised from the knee
			"hand_r": _hand(Vector3(-0.24, -0.20, 0.36), Vector3(0.05, 0.9, 0.4), FWD, PR),
			"hand_l": _hand(Vector3(0.14, -0.36, 0.30), Vector3.ZERO, Vector3.ZERO, PL, "", 0.0) },
		"two": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.08, -0.12, 0.40), Vector3(0.1, 0.9, 0.35), FWD, PR),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, PL, "", 1.0) },
		"polearm": { "flat": 0.8,       # shaft planted as a prop
			"hand_r": _hand(Vector3(-0.18, 0.02, 0.36), Vector3(0, 1, 0.12), FWD, PR),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, PL, "", 1.0) },
		"spear": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.22, -0.06, 0.34), Vector3(0, 1, 0.1), FWD, PR) },
		"pair": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.22, -0.26, 0.34), Vector3(-0.2, 0.3, 0.95), UP, PR),
			"hand_l": _hand(Vector3(0.18, -0.26, 0.36), Vector3(0.2, 0.3, 0.95), UP, PL) },
		"bow": { "flat": 0.6,
			"hand_l": _hand(Vector3(0.20, -0.34, 0.30), Vector3(0.4, 0.6, 0.7), FWD, PL),
			"hand_r": _hand(Vector3(-0.16, -0.36, 0.30), Vector3.ZERO, Vector3.ZERO, PR, "", 0.0) },
		"pistol": { "flat": 0.3,
			"hand_r": _hand(Vector3(-0.20, -0.30, 0.34), Vector3(0, 0.6, 0.8), Vector3(0, -0.8, 0.6), PR) },
		"fists": { "flat": 0.0,     # down on a knee, one fist propped on the thigh, the other still up
			"hand_r": _fist("r", Vector3(-0.22, -0.24, 0.34), Vector3(0, -0.5, 1), Vector3(-0.7, 0.7, 0), PR),
			"hand_l": _fist("l", Vector3(0.12, 0.10, 0.30), Vector3(0, 0.5, 1), Vector3(0.7, 0.7, 0), Vector3(0.4, -1, -0.3)) },
	} }
	# ------------------------------------------------------------ dodge
	T["dodge"] = { "body": {
		"root": Vector3(0.22, -0.14, -0.08), "hips": Vector3(0, 0.1, -0.18), "spine": Vector3(0, 0, -0.15),
		"chest": Vector3(-0.1, 0.2, -0.2), "head": Vector3(0, -0.3, 0.2),
		"foot_l": _foot(0.40, 0.0, 0.5), "foot_r": _foot(-0.08, 0.06, -0.1) }, "styles": {
		"default": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.30, 0.06, 0.12), Vector3(-0.3, 0.9, 0.2), FWD, Vector3(-1, -0.6, -0.2)),
			"hand_l": _hand(Vector3(0.36, 0.12, 0.06), Vector3.ZERO, Vector3.ZERO, Vector3(1, -0.6, -0.2), "", 0.0) },
		"two": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.14, 0.0, 0.22), Vector3(0.3, 0.9, 0.2), FWD, PR),
			"hand_l": _hand(Vector3(0.2, 0, 0.3), Vector3.ZERO, Vector3.ZERO, PL, "", 1.0) },
		"pair": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.30, 0.06, 0.14), Vector3(-0.3, 0.9, 0.2), UP, Vector3(-1, -0.6, -0.2)),
			"hand_l": _hand(Vector3(0.34, 0.10, 0.10), Vector3(0.3, 0.9, 0.2), UP, Vector3(1, -0.6, -0.2)) },
		"bow": { "flat": 0.6,
			"hand_l": _hand(Vector3(0.34, 0.08, 0.10), Vector3(0.3, 1, 0.1), FWD, Vector3(1, -0.6, -0.2)),
			"hand_r": _hand(Vector3(-0.30, 0.06, 0.12), Vector3.ZERO, Vector3.ZERO, Vector3(-1, -0.6, -0.2), "", 0.0) },
		"fists": { "flat": 0.0,     # slipping the blow, guard tight
			"hand_r": _fist("r", Vector3(-0.17, 0.28, 0.18), Vector3(0, 0.6, 1), Vector3(-0.7, 0.7, 0), Vector3(-1, -0.6, -0.2)),
			"hand_l": _fist("l", Vector3(0.10, 0.32, 0.22), Vector3(0, 0.6, 1), Vector3(0.7, 0.7, 0), Vector3(1, -0.6, -0.2)) },
	} }
	# ------------------------------------------------------------ block
	T["block"] = { "body": {
		"root": Vector3(0, -0.13, -0.04), "spine": Vector3(0.05, 0, 0), "chest": Vector3(-0.04, 0, 0), "head": Vector3(0.14, 0, 0),
		"foot_l": _foot(0.15, 0.18, 0.15), "foot_r": _foot(-0.14, -0.16, -0.35) }, "styles": {
		"default": { "flat": 0.0,      # blade across the face, edge out
			"hand_r": _hand(Vector3(-0.16, 0.34, 0.36), Vector3(0.95, 0.25, 0.1), FWD, Vector3(-0.6, -1, 0)),
			"hand_l": _hand(Vector3(0.20, 0.26, 0.40), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -1, 0), "", 0.0) },
		"heavy": { "flat": 0.0,
			"hand_r": _hand(Vector3(-0.30, 0.34, 0.34), Vector3(0.95, 0.3, 0.05), FWD, Vector3(-0.6, -1, 0)),
			"hand_l": _hand(Vector3(0.2, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -1, 0), "", 1.0) },
		"polearm": { "flat": 0.0,      # haft held across, hands spread
			"hand_r": _hand(Vector3(-0.02, 0.36, 0.34), Vector3(0.95, 0.3, 0.05), FWD, Vector3(-0.6, -1, 0)),
			"hand_l": _hand(Vector3(0.2, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -1, 0), "", 1.0) },
		"pair": { "flat": 0.0,         # crossed
			"hand_r": _hand(Vector3(0.03, 0.30, 0.40), Vector3(0.7, 0.7, 0.1), FWD, Vector3(-0.6, -1, 0)),
			"hand_l": _hand(Vector3(-0.03, 0.30, 0.40), Vector3(-0.7, 0.7, 0.1), FWD, Vector3(0.6, -1, 0)) },
		"bow": { "flat": 0.0,
			"hand_l": _hand(Vector3(0.10, 0.32, 0.40), Vector3(-1, 0.2, 0.1), FWD, Vector3(0.6, -1, 0)),
			"hand_r": _hand(Vector3(-0.16, 0.30, 0.40), Vector3.ZERO, Vector3.ZERO, Vector3(-0.6, -1, 0), "", 0.0) },
		"pistol": { "flat": 0.2,
			"hand_r": _hand(Vector3(-0.10, 0.30, 0.34), Vector3(0, 0.2, -1), Vector3(0, 1, 0.2), Vector3(-0.6, -1, 0)),
			"hand_l": _hand(Vector3(0.12, 0.30, 0.36), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, -1, 0)) },
		"fists": { "flat": 0.0,     # high guard: forearms up as a wall, knuckles to the sky
			"hand_r": _fist("r", Vector3(-0.09, 0.46, 0.26), Vector3(0.1, 1, 0.1), FWD, Vector3(-0.3, -1, 0.2)),
			"hand_l": _fist("l", Vector3(0.09, 0.48, 0.28), Vector3(-0.1, 1, 0.1), FWD, Vector3(0.3, -1, 0.2)) },
	} }
	# ----------------------------------------------------------- fumble
	T["fumble"] = { "body": {
		"root": Vector3(0, -0.06, -0.20), "hips": Vector3(-0.25, 0.1, 0.1), "spine": Vector3(-0.2, 0, 0),
		"chest": Vector3(-0.25, -0.2, 0.15), "head": Vector3(-0.25, 0.2, 0),
		"foot_l": _foot(0.13, 0.20, 0.2, 0.13, -0.4), "foot_r": _foot(-0.14, -0.22, -0.3) }, "styles": {
		"default": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.52, 0.34, -0.04), Vector3(-0.7, 0.6, -0.3), FWD, Vector3(0, -1, -0.3)),
			"hand_l": _hand(Vector3(0.44, 0.44, 0.14), Vector3.ZERO, Vector3.ZERO, Vector3(0, -1, -0.3), "", 0.0) },
		"pair": { "flat": 0.6,
			"hand_r": _hand(Vector3(-0.52, 0.34, -0.04), Vector3(-0.7, 0.6, -0.3), UP, Vector3(0, -1, -0.3)),
			"hand_l": _hand(Vector3(0.44, 0.44, 0.14), Vector3(0.5, 0.8, 0.1), UP, Vector3(0, -1, -0.3)) },
		"bow": { "flat": 0.6,
			"hand_l": _hand(Vector3(0.50, 0.34, -0.02), Vector3(0.6, 0.8, -0.2), FWD, Vector3(0, -1, -0.3)),
			"hand_r": _hand(Vector3(-0.44, 0.44, 0.14), Vector3.ZERO, Vector3.ZERO, Vector3(0, -1, -0.3), "", 0.0) },
		"fists": { "flat": 0.0,     # guard blown open
			"hand_r": _fist("r", Vector3(-0.50, 0.32, -0.04), Vector3(-0.6, 0.8, -0.2), Vector3(0, 0, 1), Vector3(0, -1, -0.3)),
			"hand_l": _fist("l", Vector3(0.44, 0.44, 0.14), Vector3(0.5, 0.8, 0.1), Vector3(0, 0, 1), Vector3(0, -1, -0.3)) },
	} }
	# ------------------------------------------------------------- fall
	T["fall"] = { "body": {
		"root": Vector3(0, -0.70, -0.45), "hips": Vector3(-1.45, 0, 0), "spine": Vector3(0.05, 0, 0),
		"chest": Vector3(0.08, 0, 0), "neck": Vector3(0.1, 0, 0), "head": Vector3(0.25, 0.35, 0),
		"foot_l": _foot(0.18, 0.42, 0.4, 0.06, -1.0, Vector3(0.2, 1, 0.2)), "foot_r": _foot(-0.14, 0.36, -0.3, 0.06, -1.0, Vector3(-0.2, 1, 0.2)) }, "styles": {
		"default": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.56, 0.14, 0.04), Vector3(-0.4, 1, 0.2), FWD, Vector3(-0.3, 0, -1)),
			"hand_l": _hand(Vector3(0.56, 0.08, 0.04), Vector3.ZERO, Vector3.ZERO, Vector3(0.3, 0, -1), "", 0.0) },
		"pair": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.56, 0.14, 0.04), Vector3(-0.4, 1, 0.2), UP, Vector3(-0.3, 0, -1)),
			"hand_l": _hand(Vector3(0.56, 0.08, 0.04), Vector3(0.4, 1, 0.2), UP, Vector3(0.3, 0, -1)) },
		"bow": { "flat": 0.8,
			"hand_l": _hand(Vector3(0.56, 0.10, 0.04), Vector3(0.4, 1, 0.2), FWD, Vector3(0.3, 0, -1)),
			"hand_r": _hand(Vector3(-0.56, 0.14, 0.04), Vector3.ZERO, Vector3.ZERO, Vector3(-0.3, 0, -1), "", 0.0) },
		"fists": { "flat": 0.0,
			"hand_r": _fist("r", Vector3(-0.56, 0.14, 0.04), Vector3(-1, 0.2, 0.1), UP, Vector3(-0.3, 0, -1)),
			"hand_l": _fist("l", Vector3(0.56, 0.08, 0.04), Vector3(1, 0.2, 0.1), UP, Vector3(0.3, 0, -1)) },
	} }
	# ------------------------------------------------------------ cheer
	T["cheer"] = { "body": {
		"root": Vector3(0, -0.01, 0), "spine": Vector3(-0.06, 0, 0), "chest": Vector3(-0.12, 0, 0), "head": Vector3(-0.3, 0, 0),
		"foot_l": _foot(0.15, 0.03, 0.25), "foot_r": _foot(-0.15, -0.02, -0.25) }, "styles": {
		"default": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.22, 0.80, 0.10), Vector3(-0.15, 1, 0.1), FWD, Vector3(-1, 0, -0.2)),
			"hand_l": _hand(Vector3(0.24, 0.74, 0.08), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, -0.2), "", 0.0) },
		"heavy": { "flat": 0.8,        # hoisted straight up in both fists
			"hand_r": _hand(Vector3(-0.06, 0.78, 0.10), Vector3(0.1, 1, 0.05), FWD, Vector3(-1, 0, -0.2)),
			"hand_l": _hand(Vector3(0.2, 0.7, 0.1), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, -0.2), "", 1.0) },
		"polearm": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.22, 0.80, 0.10), Vector3(0, 1, 0.05), FWD, Vector3(-1, 0, -0.2)),
			"hand_l": _hand(Vector3(0.24, 0.74, 0.08), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, -0.2), "", 0.0) },
		"pair": { "flat": 0.8,
			"hand_r": _hand(Vector3(-0.22, 0.80, 0.10), Vector3(-0.15, 1, 0.1), UP, Vector3(-1, 0, -0.2)),
			"hand_l": _hand(Vector3(0.22, 0.80, 0.10), Vector3(0.15, 1, 0.1), UP, Vector3(1, 0, -0.2)) },
		"bow": { "flat": 0.8,
			"hand_l": _hand(Vector3(0.22, 0.80, 0.10), Vector3(0.1, 1, 0.1), FWD, Vector3(1, 0, -0.2)),
			"hand_r": _hand(Vector3(-0.24, 0.74, 0.08), Vector3.ZERO, Vector3.ZERO, Vector3(-1, 0, -0.2), "", 0.0) },
		"pistol": { "flat": 0.3,
			"hand_r": _hand(Vector3(-0.22, 0.80, 0.10), Vector3(0, 0, -1), UP, Vector3(-1, 0, -0.2)) },
		"fists": { "flat": 0.0,     # fist pumped to the sky, the other clenched at the chest
			"hand_r": _fist("r", Vector3(-0.20, 0.80, 0.10), Vector3(0, 1, 0.05), Vector3(-1, 0, 0), Vector3(-1, 0, -0.2)),
			"hand_l": _fist("l", Vector3(0.14, 0.18, 0.26), Vector3(-0.3, 0.6, 0.6), Vector3(0.7, 0.7, 0), Vector3(1, -0.4, -0.2)) },
	} }
	_table = T
	return _table

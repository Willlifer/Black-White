class_name BWAnimStricken
extends RefCounted
## The five stricken VARIANTS for every set (design/art/ANIMATION.md,
## "Hit-reaction variety"). The cutscene picks one by context through
## BWReactionPick; the plain "hit" pose plays the character's own default
## (BWAnimClips.personality().hit).
##
##   stricken_flinch     16 f  mild and quick: the head turns away and ducks,
##                             the free forearm comes up, the heel peels
##   stricken_shrug      30 f  takes it, looks down at it, shrugs it off (a
##                             palm-up shrug), a neck roll, chin up
##   stricken_stumble    44 f  nearly falls: two steps back, teeters on the
##                             heel with both arms windmilling, lunges
##                             forward to catch it, walks back in
##   stricken_knockback  48 f  a big recoil: the body is thrown back half a
##                             hex (0.84 u) and SKIDS on both feet, braking
##                             low; it glares, then walks three steps home.
##                             The travel is faked in the clip: the unit's
##                             root stays in its hex (meta.travel)
##   stricken_rage       52 f  takes it, hunches and fumes (a tremble), then
##                             rears up into an enraged shout: chest out,
##                             head back, arms flared, up on the toes
##                             ("shout" marker), and comes down glaring
##
## Every variant has `impact` at f0 (the blow lands as it starts, like the
## approved stricken), `catch` and `recovered`; rage adds `shout` and the
## knockback `slide_end`. They start and end on the set's guard. Bodies and
## feet are shared choreography; the hands come per style: the weapon hand(s)
## move as offsets from the guard (x = outward, mirrored per hand), the free
## hand is keyed in the chest frame on its own side; two-handers let go
## with the left fist and re-grip.

const VARIANTS: PackedStringArray = ["stricken_flinch", "stricken_shrug", "stricken_stumble", "stricken_knockback", "stricken_rage"]
## How far the knockback throws the body back (u): about half a hex.
const KNOCK_TRAVEL := 0.84


static func clips(st: String) -> Array:
	return [flinch(st), shrug(st), stumble(st), knockback(st), rage(st)]


const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]


## Per-style hand keying for one clip.
class Arms:
	extends RefCounted
	var c: BWAnimClips.Clip
	var st := ""
	var guard := {}
	var w: Array = []          # the weapon hand(s)
	var other := ""            # the free hand ("" for the pair)
	var regrip := false        # the left fist holds the weapon in the guard
	var long := false          # long shafts: keep the butt off the floor

	func _init(clip: BWAnimClips.Clip) -> void:
		c = clip
		st = clip.style
		guard = BWAnimCarry.guard_hands(clip.base)
		var wh := BWAnimCarry.weapon_hand(st)
		w = ["hand_r", "hand_l"] if wh == "both" else ["hand_" + wh]
		other = "" if wh == "both" else ("hand_r" if wh == "l" else "hand_l")
		regrip = float(clip.base.get("hand_l_grip", 0.0)) > 0.5
		long = st in ["polearm", "staff", "spear"]

	## Weapon hand(s): guard + d (d.x outward, mirrored per hand), the aim
	## turned by rot (pitch +: tips forward; yaw / roll mirrored per hand).
	func weapon(f: float, d: Vector3, rot := Vector3.ZERO, mode: String = "a") -> Arms:
		for h in w:
			var s := -1.0 if h == "hand_r" else 1.0
			var dd := Vector3(d.x * s, d.y, d.z)
			if long and dd.y < 0.0:
				dd.y *= 0.3          # a long butt would go through the floor
			if st == "fists":
				# the fists' guard is already up at the chin, near full reach:
				# the reactions move it less (it would snap the arms straight)
				dd = Vector3(dd.x * 0.6, dd.y * 0.35, dd.z * 0.35)
			c.key(h + "_pos", f, (guard[h + "_pos"] as Vector3) + dd, mode)
			var r := Vector3(rot.x, rot.y * s, rot.z * s)
			c.key(h + "_aim", f, (Basis.from_euler(r) * (guard[h + "_aim"] as Vector3)).normalized(), mode)
		return self

	## Weapon hand(s) at guard + d with an explicit aim (outward convention,
	## mirrored per hand): poses the guard's rotation can't reach (the flare).
	func weapon_aim(f: float, d: Vector3, aim: Vector3, mode: String = "a") -> Arms:
		for h in w:
			var s := -1.0 if h == "hand_r" else 1.0
			c.key(h + "_pos", f, (guard[h + "_pos"] as Vector3) + Vector3(d.x * s, d.y, d.z), mode)
			c.key(h + "_aim", f, Vector3(aim.x * s, aim.y, aim.z).normalized(), mode)
		return self

	## The flared weapon aim for this style (rage): blades down and out
	## behind, long shafts up and back, bows and pistols up and out.
	func flare_aim() -> Vector3:
		match st:
			# (chest frame: the shout throws the chest back ~0.56 rad, which
			# turns these down and back in the world)
			"polearm", "staff", "spear": return Vector3(0.35, 0.85, -0.2)
			"pistol": return Vector3(0.4, 0.9, 0.05)
			"bow": return Vector3(0.25, 0.95, 0.15)
			"heavy": return Vector3(0.75, 0.15, -0.6)
		return Vector3(0.65, 0.1, -0.55)

	## The free hand at v (chest frame, v.x outward on its own side).
	func hand(f: float, v: Vector3, mode: String = "a") -> Arms:
		if other == "":
			return self
		var s := 1.0 if other == "hand_l" else -1.0
		c.key(other + "_pos", f, Vector3(v.x * s, v.y, v.z), mode)
		return self

	## The free hand back on its guard position.
	func free_home(f: float, mode: String = "a") -> Arms:
		if other != "":
			c.key(other + "_pos", f, guard[other + "_pos"], mode)
		return self

	## The left fist lets go of a two-hander at f0 and takes it again by f1.
	func let_go(f0: float, f1: float) -> Arms:
		if regrip:
			c.key("hand_l_grip", f0, 0.0).key("hand_l_grip", f1 - 2.0, 0.3).key("hand_l_grip", f1, 1.0)
		return self

	## The free elbow's pole (out to the side, down).
	func pole(f: float, v: Vector3) -> Arms:
		if other != "":
			var s := 1.0 if other == "hand_l" else -1.0
			c.key(other + "_pole", f, Vector3(v.x * s, v.y, v.z))
		return self


static func _hand_chans() -> Array:
	var out: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			out.append(ch)
	return out


static func _feet_base(c: BWAnimClips.Clip) -> Array:
	var b := c.base
	return [BWAnimClips.ground_of(b.foot_l_pos, 0.22), BWAnimClips.ground_of(b.foot_r_pos, -0.22)]


static func _foot(c: BWAnimClips.Clip, side: String, f: float, g: Vector2, pitch: float, yaw: float, lift: float = 0.0, mode: String = "a") -> void:
	c.pose(f, { "foot_%s_pos" % side: BWAnimClips.ankle(g, pitch, yaw, lift), "foot_%s_rot" % side: Vector3(pitch, yaw, 0) }, mode)


## A step of one foot from a to b between f0 (heel peels) and f1 (lands).
static func _step(c: BWAnimClips.Clip, side: String, f0: float, f1: float, a: Vector2, b: Vector2, lift: float = 0.07) -> void:
	var y := 0.22 if side == "l" else -0.22
	var fwd := (b - a).y >= 0.0
	_foot(c, side, f0, a, 0.0, y, 0.0, "f")
	_foot(c, side, lerpf(f0, f1, 0.3), a, 0.32 if fwd else 0.22, y)
	_foot(c, side, lerpf(f0, f1, 0.62), a.lerp(b, 0.55), 0.1 if fwd else 0.05, y, lift)
	if fwd:
		_foot(c, side, f1 - 0.6, b, -0.18, y, 0.0, "l")
	_foot(c, side, f1, b, 0.0, y, 0.0, "f")


static func _begin(name: String, frames: int, st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip(name, frames, false, st)
	c.at_base(0, BODY + _hand_chans(), "l")
	c.at_base(frames, BODY + _hand_chans())
	return c


static func _r(c: BWAnimClips.Clip, d: Vector3) -> Vector3:
	return (c.base.root as Vector3) + d


# -------------------------------------------------------------------- flinch

## FLINCH (16 f): mild, quick. The head turns away and ducks, the chest
## twists off the blow, the free forearm snaps up by the face, the weapon
## pulls in; the right heel peels; she comes back up with a small overshoot.
static func flinch(st: String) -> BWAnimClips.Clip:
	var c := _begin("stricken_flinch", 16, st)
	c.marker("impact", 0).marker("catch", 5).marker("recovered", 12).marker("pose", 3)
	c.pose(2, { "root": _r(c, Vector3(0, -0.045, -0.05)), "hips": Vector3(-0.04, 0.06, 0.0), "spine": Vector3(0.04, 0, 0),
		"chest": Vector3(-0.05, 0.16, 0.05), "neck": Vector3(0.08, 0, 0), "head": Vector3(0.24, -0.3, 0.12), "squash": -0.03, "head_sq": 0.035 })
	c.pose(4, { "root": _r(c, Vector3(0, -0.055, -0.055)), "chest": Vector3(-0.04, 0.18, 0.06), "head": Vector3(0.26, -0.34, 0.13),
		"squash": -0.032, "head_sq": 0.02 }, "f")
	c.pose(6, { "head_sq": 0.0 })
	c.pose(8, { "root": _r(c, Vector3(0, -0.03, -0.025)), "hips": Vector3(-0.01, 0.01, 0.0), "spine": Vector3(0.0, 0, 0),
		"chest": Vector3(0.02, 0.03, 0.0), "neck": Vector3(0.02, 0, 0), "head": Vector3(0.04, -0.06, 0.02), "squash": 0.012 })
	c.pose(11, { "root": _r(c, Vector3(0, -0.004, -0.005)), "chest": Vector3(0.0, -0.02, 0.0), "head": Vector3(-0.04, 0.04, -0.01),
		"squash": -0.004, "head_sq": -0.008 }, "f")
	var a := Arms.new(c)
	var lift := 0.16 if a.other == "" else 0.05
	a.weapon(2, Vector3(-0.03, lift, -0.04), Vector3(-0.14, 0, 0))
	a.weapon(4, Vector3(-0.035, lift + 0.01, -0.045), Vector3(-0.16, 0, 0), "f")
	a.weapon(9, Vector3(0.0, 0.0, 0.01), Vector3(0.03, 0, 0))
	a.hand(2, Vector3(0.12, 0.24, 0.26)).hand(4, Vector3(0.11, 0.27, 0.25), "f").hand(9, Vector3(0.22, -0.18, 0.12))
	a.pole(2, Vector3(0.6, -0.6, 0.1)).pole(10, Vector3(0.6, -0.6, -0.5))
	a.free_home(13)
	a.let_go(1, 10)
	var g := _feet_base(c)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 16, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 3, g[1], 0.16, -0.24)
	_foot(c, "r", 7, g[1], 0.0, -0.22, 0, "f")
	_foot(c, "r", 16, g[1], 0, -0.22, 0, "f")
	return c


# --------------------------------------------------------------------- shrug

## SHRUG (30 f): takes the blow (a short step back, f2-f5), looks down at
## where it landed (f9), a palm-up shrug, shoulders up (f12-f14), drops it,
## a neck roll (f19) and chin up (f22): "that's it?". Back to the guard.
static func shrug(st: String) -> BWAnimClips.Clip:
	var c := _begin("stricken_shrug", 30, st)
	c.marker("impact", 0).marker("catch", 5).marker("recovered", 25).marker("pose", 12)
	c.pose(2, { "root": _r(c, Vector3(0, -0.04, -0.09)), "hips": Vector3(-0.08, 0.04, 0.02), "spine": Vector3(-0.08, 0, 0),
		"chest": Vector3(-0.16, 0.12, 0.05), "head": Vector3(0.12, -0.06, 0.0), "squash": 0.03, "head_sq": -0.025 })
	c.pose(4, { "root": _r(c, Vector3(0, -0.05, -0.1)), "chest": Vector3(-0.18, 0.14, 0.06), "head": Vector3(-0.12, 0.1, -0.03), "head_sq": 0.0 }, "f")
	c.pose(7, { "root": _r(c, Vector3(0, -0.06, -0.06)), "hips": Vector3(0.0, 0.02, 0.0), "spine": Vector3(0.03, 0, 0),
		"chest": Vector3(0.04, 0.0, 0.0), "head": Vector3(0.1, 0.0, 0.0), "squash": -0.02 })
	c.pose(9, { "head": Vector3(0.2, 0.14, 0.03), "chest": Vector3(0.06, 0.06, 0.0) }, "f")
	# the shrug: up, held, dropped
	c.pose(12, { "root": _r(c, Vector3(0, -0.01, -0.04)), "spine": Vector3(-0.02, 0, 0), "chest": Vector3(-0.07, -0.04, 0.0),
		"neck": Vector3(0.08, 0, 0), "head": Vector3(0.0, -0.06, 0.1), "squash": 0.04, "head_sq": -0.02 }, "f")
	c.pose(14, { "root": _r(c, Vector3(0, -0.008, -0.04)), "chest": Vector3(-0.07, -0.05, 0.0), "squash": 0.042, "head": Vector3(0.0, -0.08, 0.11) }, "f")
	c.pose(16.5, { "root": _r(c, Vector3(0, -0.06, -0.03)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(0.02, 0.0, 0.0), "neck": Vector3(0.0, 0, 0),
		"head": Vector3(0.02, 0.0, 0.0), "squash": -0.025, "head_sq": 0.015 })
	# neck roll, chin up
	c.pose(19, { "head": Vector3(-0.06, 0.14, -0.15), "head_sq": 0.0, "squash": 0.0 })
	c.pose(22, { "root": _r(c, Vector3(0, -0.025, -0.01)), "head": Vector3(-0.15, -0.05, 0.06), "squash": 0.008 }, "f")
	c.pose(26, { "root": _r(c, Vector3(0, -0.006, 0.0)), "head": Vector3(-0.06, 0.0, 0.0), "squash": 0.0 })
	var a := Arms.new(c)
	a.weapon(2, Vector3(0.04, 0.08, -0.06), Vector3(-0.25, 0, 0))
	a.weapon(4, Vector3(0.05, 0.1, -0.07), Vector3(-0.3, 0, 0), "f")
	a.weapon(8, Vector3(0.0, -0.03, 0.03), Vector3(0.06, 0, 0))
	a.weapon(12, Vector3(0.08, 0.07, 0.02), Vector3(-0.05, 0.0, -0.12), "f")
	a.weapon(14, Vector3(0.08, 0.08, 0.02), Vector3(-0.05, 0.0, -0.12), "f")
	a.weapon(17, Vector3(0.0, -0.03, 0.01), Vector3(0.04, 0, 0))
	a.weapon(23, Vector3(0.0, 0.01, 0.0), Vector3.ZERO, "f")
	a.hand(2, Vector3(0.36, 0.06, 0.1)).hand(4, Vector3(0.4, 0.12, 0.0), "f").hand(8, Vector3(0.28, -0.2, 0.12))
	a.hand(12, Vector3(0.44, -0.06, 0.24), "f").hand(14, Vector3(0.45, -0.04, 0.25), "f")
	# dusts the spot off, flicks it away
	a.hand(17, Vector3(0.06, 0.1, 0.22)).hand(19.5, Vector3(0.36, 0.02, 0.28)).hand(23, Vector3(0.28, -0.26, 0.12))
	a.free_home(27)
	a.pole(4, Vector3(0.6, -1, 0.0)).pole(12, Vector3(0.8, -0.6, -0.2)).pole(20, Vector3(0.6, -0.6, -0.5))
	a.let_go(2, 24)
	var g := _feet_base(c)
	var fr2: Vector2 = g[1] + Vector2(-0.02, -0.14)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 4, g[0], 0.16, 0.22)
	_foot(c, "l", 8, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 30, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 2, g[1], 0.22, -0.24)
	_foot(c, "r", 4, g[1].lerp(fr2, 0.5), 0.08, -0.28, 0.05)
	_foot(c, "r", 6, fr2, 0, -0.3, 0, "f")
	_foot(c, "r", 19, fr2, 0, -0.3, 0, "f")
	_foot(c, "r", 20.5, fr2, 0.22, -0.28)
	_foot(c, "r", 22, g[1].lerp(fr2, 0.5), 0.08, -0.25, 0.05)
	_foot(c, "r", 23.5, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 30, g[1], 0, -0.22, 0, "f")
	return c


# ------------------------------------------------------------------- stumble

## STUMBLE (44 f): nearly falls. Thrown back (f2), the right foot steps
## back to catch it (f2-f5) and fails, the left goes back too (f6-f9) and
## lands on the heel: she teeters on her heels, toes up, both arms
## windmilling forward (f6-f17), wobbles, then lunges forward onto the
## left foot to catch it (f18), steadies hunched (f23), exhales and walks
## back in (f24-f35).
static func stumble(st: String) -> BWAnimClips.Clip:
	var c := _begin("stricken_stumble", 44, st)
	c.marker("impact", 0).marker("catch", 18).marker("recovered", 38).marker("pose", 12)
	c.pose(2, { "root": _r(c, Vector3(0, -0.03, -0.16)), "hips": Vector3(-0.14, 0.06, 0.04), "spine": Vector3(-0.16, 0, 0),
		"chest": Vector3(-0.28, 0.12, 0.08), "head": Vector3(0.18, -0.06, 0.0), "squash": 0.05, "head_sq": -0.035 })
	c.pose(4, { "head": Vector3(-0.24, 0.1, -0.04), "head_sq": 0.0 })
	c.pose(6, { "root": _r(c, Vector3(0, -0.07, -0.28)), "hips": Vector3(-0.1, 0.0, 0.0), "spine": Vector3(-0.1, 0, 0),
		"chest": Vector3(-0.2, 0.0, -0.04), "head": Vector3(0.0, 0.0, 0.0), "squash": -0.03 })
	c.pose(9, { "root": _r(c, Vector3(0.0, -0.05, -0.4)), "hips": Vector3(-0.2, -0.1, -0.06), "spine": Vector3(-0.12, 0, 0),
		"chest": Vector3(-0.3, -0.16, -0.14), "head": Vector3(-0.2, -0.1, -0.1), "squash": 0.02 })
	# the teeter: over the heels, toes up, wobbling side to side
	c.pose(12, { "root": _r(c, Vector3(0.025, -0.03, -0.46)), "hips": Vector3(-0.24, 0.05, 0.1), "spine": Vector3(-0.16, 0, 0),
		"chest": Vector3(-0.34, 0.15, 0.16), "head": Vector3(-0.28, 0.1, 0.12), "squash": 0.03 }, "f")
	c.pose(15, { "root": _r(c, Vector3(-0.025, -0.05, -0.45)), "hips": Vector3(-0.2, -0.05, -0.1), "chest": Vector3(-0.3, -0.12, -0.16),
		"head": Vector3(-0.2, -0.12, -0.12), "squash": 0.02 })
	# the catch: a lunge forward onto the left foot
	c.pose(18, { "root": _r(c, Vector3(0, -0.17, -0.34)), "hips": Vector3(0.15, 0, 0), "spine": Vector3(0.2, 0, 0), "chest": Vector3(0.2, 0, 0.0),
		"head": Vector3(0.3, 0, 0), "squash": -0.05, "head_sq": 0.04 })
	c.pose(20, { "head_sq": 0.0 })
	c.pose(23, { "root": _r(c, Vector3(0, -0.13, -0.3)), "hips": Vector3(0.1, 0, 0), "spine": Vector3(0.12, 0, 0), "chest": Vector3(0.06, 0, 0),
		"head": Vector3(0.1, 0, 0), "squash": -0.01 }, "f")
	c.pose(26, { "root": _r(c, Vector3(0, -0.08, -0.22)), "hips": Vector3(0.03, 0, 0), "spine": Vector3(0.04, 0, 0), "chest": Vector3(-0.04, 0, 0),
		"squash": 0.02, "head": Vector3(-0.08, 0, 0) })
	c.pose(29, { "root": _r(c, Vector3(0, -0.06, -0.12)), "squash": 0.0 })
	c.pose(33, { "root": _r(c, Vector3(0, -0.05, -0.03)), "hips": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(0, 0, 0),
		"head": Vector3(-0.06, 0.04, 0), "squash": -0.01 })
	c.pose(37, { "root": _r(c, Vector3(0, -0.012, 0.0)), "squash": 0.008, "head": Vector3(-0.04, 0.0, 0.0) }, "f")
	var a := Arms.new(c)
	# weapon: thrown up, then circles with the body (smaller), forward on the catch
	# (out at her side, not up: a raised blade crosses the face)
	a.weapon(2, Vector3(0.06, 0.08, -0.08), Vector3(-0.3, 0, 0))
	# (the chest is thrown back ~0.5 rad: the weapon is tipped forward
	# against it, or it stands up across the face)
	a.weapon(6, Vector3(0.14, 0.06, 0.1), Vector3(0.3, 0, -0.1))
	a.weapon(9, Vector3(0.18, 0.08, 0.0), Vector3(0.3, 0, -0.15))
	a.weapon(12, Vector3(0.16, 0.06, 0.12), Vector3(0.45, 0, -0.1))
	a.weapon(15, Vector3(0.18, 0.08, 0.0), Vector3(0.3, 0, -0.15))
	a.weapon(18, Vector3(0.06, 0.12, 0.08), Vector3(-0.45, 0, 0.0))
	a.weapon(23, Vector3(0.0, 0.05, 0.05), Vector3(-0.15, 0, 0), "f")
	a.weapon(30, Vector3(0.0, -0.02, 0.02), Vector3(0.03, 0, 0))
	a.weapon(36, Vector3(0.0, 0.01, 0.0), Vector3.ZERO, "f")
	# the free arm windmills forward, over the top, twice
	a.hand(3, Vector3(0.36, 0.06, 0.12)).hand(5.5, Vector3(0.44, -0.04, -0.16)).hand(8, Vector3(0.48, 0.3, -0.1))
	a.hand(10.5, Vector3(0.46, 0.34, 0.2)).hand(13, Vector3(0.42, 0.0, 0.3)).hand(15.5, Vector3(0.46, -0.04, -0.12))
	a.hand(18, Vector3(0.36, 0.2, 0.32)).hand(23, Vector3(0.24, -0.22, 0.26), "f").hand(30, Vector3(0.28, -0.3, 0.12))
	a.free_home(36)
	a.pole(5, Vector3(0.6, -0.4, 0.4)).pole(11, Vector3(0.7, -0.3, -0.5)).pole(18, Vector3(0.6, -0.6, -0.4)).pole(30, Vector3(0.6, -0.6, -0.5))
	a.let_go(2, 33)
	var g := _feet_base(c)
	var r_back: Vector2 = g[1] + Vector2(-0.03, -0.32)
	var l_back: Vector2 = g[0] + Vector2(0.04, -0.5)
	var l_catch: Vector2 = g[0] + Vector2(0.0, -0.22)
	var r_mid: Vector2 = g[1] + Vector2(0.0, -0.12)
	# right: back to catch (fails); later one step in and home
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 2, g[1], 0.3, -0.25)
	_foot(c, "r", 3.5, g[1].lerp(r_back, 0.5), 0.1, -0.3, 0.1)
	_foot(c, "r", 5, r_back, -0.25, -0.35, 0, "l")
	_foot(c, "r", 6, r_back, 0, -0.35, 0, "f")
	_foot(c, "r", 12, r_back, 0.0, -0.35, 0, "f")
	_foot(c, "r", 15, r_back, 0.2, -0.33)
	_foot(c, "r", 18, r_back, 0.0, -0.3, 0, "f")
	_step(c, "r", 24, 27.5, r_back, r_mid, 0.07)
	_step(c, "r", 32, 35.5, r_mid, g[1], 0.05)
	_foot(c, "r", 44, g[1], 0, -0.22, 0, "f")
	# left: heel up, back onto the heel (toes up: the teeter), forward to catch, home
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 5.5, g[0], 0.35, 0.22)
	_foot(c, "l", 7.3, g[0].lerp(l_back, 0.5), 0.1, 0.25, 0.12)
	_foot(c, "l", 9, l_back, -0.3, 0.28, 0, "l")
	_foot(c, "l", 10.5, l_back, -0.38, 0.28)
	_foot(c, "l", 12.5, l_back, -0.42, 0.28, 0, "f")
	_foot(c, "l", 14.5, l_back, -0.15, 0.28)
	_foot(c, "l", 15.5, l_back, 0.15, 0.26)
	_foot(c, "l", 16.8, l_back.lerp(l_catch, 0.5), 0.1, 0.24, 0.1)
	_foot(c, "l", 17.6, l_catch, -0.22, 0.22, 0, "l")
	_foot(c, "l", 18.5, l_catch, 0.0, 0.22, 0, "f")
	_step(c, "l", 28, 31.5, l_catch, g[0], 0.06)
	_foot(c, "l", 44, g[0], 0, 0.22, 0, "f")
	return c


# ----------------------------------------------------------------- knockback

## KNOCKBACK (48 f): the big one. The blow throws her back (f2: chest
## whipped back, the head lags forward, the arms flung forward) and she
## SKIDS back on both feet (f1-f12, contacts off so the foot lock lets the
## soles slide), braking low into the slide with the front toes up; the
## stop (f12, slide_end) squashes; a glare; then three steps home
## (f18-f33) and a settle. The root (the unit's hex) never moves: the
## 0.84 u of travel is all in the clip (meta.travel).
static func knockback(st: String) -> BWAnimClips.Clip:
	var c := _begin("stricken_knockback", 48, st)
	c.marker("impact", 0).marker("slide_end", 12).marker("catch", 14).marker("recovered", 42).marker("pose", 6)
	c.meta = { "travel": KNOCK_TRAVEL }
	c.skid.append([0.5, 12.5])
	var T := KNOCK_TRAVEL
	# root: thrown back, braking low, held, three steps home
	c.pose(2, { "root": _r(c, Vector3(0, -0.02, -0.2)), "hips": Vector3(-0.2, 0.05, 0.04), "spine": Vector3(-0.2, 0, 0),
		"chest": Vector3(-0.45, 0.1, 0.06), "head": Vector3(0.3, -0.04, 0.0), "squash": 0.06, "head_sq": -0.04 })
	c.pose(4, { "root": _r(c, Vector3(0, -0.1, -0.44)), "chest": Vector3(-0.3, 0.06, 0.04), "head": Vector3(-0.28, 0.06, 0.0), "squash": 0.03 })
	c.pose(5, { "head_sq": 0.0 })
	c.pose(7, { "root": _r(c, Vector3(0, -0.18, -0.66)), "hips": Vector3(0.12, 0.0, 0.0), "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.02, 0, 0),
		"head": Vector3(0.12, 0, 0), "squash": -0.02 })
	c.pose(10, { "root": _r(c, Vector3(0, -0.22, -T + 0.04)), "hips": Vector3(0.26, 0.03, 0.0), "spine": Vector3(0.16, 0, 0),
		"chest": Vector3(0.14, -0.04, 0.0), "head": Vector3(0.2, 0.0, 0.0), "squash": -0.04 })
	c.pose(12, { "root": _r(c, Vector3(0, -0.25, -T)), "hips": Vector3(0.3, 0.0, 0.0), "spine": Vector3(0.18, 0, 0),
		"chest": Vector3(0.17, 0.0, 0.0), "head": Vector3(0.14, 0.0, 0.0), "squash": -0.06, "head_sq": 0.05 }, "f")
	# glare: the head comes up while the body stays low
	c.pose(14.5, { "head": Vector3(-0.08, 0.0, 0.0), "head_sq": -0.01, "squash": -0.03 }, "f")
	c.pose(17, { "root": _r(c, Vector3(0, -0.22, -T)), "hips": Vector3(0.24, 0, 0), "spine": Vector3(0.14, 0, 0), "chest": Vector3(0.1, 0, 0),
		"head": Vector3(-0.08, 0.04, 0.0), "squash": 0.0, "head_sq": 0.0 })
	# home: R (f18-f22), L (f23-f27), R (f28-f32); the root lags the steps
	c.pose(20, { "root": _r(c, Vector3(0, -0.08, -T + 0.12)), "hips": Vector3(0.08, 0, 0), "spine": Vector3(0.05, 0, 0), "chest": Vector3(0.0, 0.06, 0),
		"head": Vector3(0.0, -0.04, 0), "squash": 0.015 })
	c.pose(22.5, { "root": _r(c, Vector3(0, -0.1, -0.54)), "chest": Vector3(0.02, 0.0, 0.0), "squash": -0.01 })
	c.pose(25, { "root": _r(c, Vector3(0, -0.06, -0.36)), "chest": Vector3(0.0, -0.06, 0), "head": Vector3(-0.02, 0.05, 0), "squash": 0.01 })
	c.pose(27.5, { "root": _r(c, Vector3(0, -0.1, -0.2)), "chest": Vector3(0.02, 0.0, 0.0), "squash": -0.01 })
	c.pose(30, { "root": _r(c, Vector3(0, -0.06, -0.07)), "hips": Vector3(0.03, 0, 0), "chest": Vector3(0.0, 0.04, 0), "head": Vector3(-0.04, -0.04, 0) })
	c.pose(33, { "root": _r(c, Vector3(0, -0.07, 0.0)), "hips": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(0.02, 0, 0), "squash": -0.012 })
	c.pose(37, { "root": _r(c, Vector3(0, -0.01, 0.0)), "chest": Vector3(-0.03, 0, 0), "head": Vector3(-0.07, 0, 0), "squash": 0.012, "head_sq": -0.01 }, "f")
	c.pose(42, { "root": _r(c, Vector3(0, -0.012, 0.0)), "chest": Vector3(0, 0, 0), "head": Vector3(-0.02, 0, 0), "squash": 0.0, "head_sq": 0.0 })
	var a := Arms.new(c)
	# arms flung forward as the body goes back, out for balance in the slide
	a.weapon(2, Vector3(-0.02, 0.12, 0.18), Vector3(0.25, 0, 0))
	a.weapon(5, Vector3(0.08, 0.14, 0.1), Vector3(0.1, 0, 0.15))
	# (braking low, the body pitches ~0.6 rad forward: the weapon is held
	# back against it so tips and muzzles stay off the floor)
	a.weapon(9, Vector3(0.12, 0.14, 0.06), Vector3(-0.3, 0, 0.2))
	a.weapon(12, Vector3(0.08, 0.13, 0.06), Vector3(-0.45, 0, 0.1), "f")
	a.weapon(17, Vector3(0.04, 0.06, 0.04), Vector3(-0.3, 0, 0.05))
	a.weapon(26, Vector3(0.0, -0.02, 0.02), Vector3(0.02, 0, 0))
	a.weapon(34, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, "f")
	a.hand(2, Vector3(0.24, 0.1, 0.34)).hand(5, Vector3(0.46, 0.1, 0.12)).hand(9, Vector3(0.5, 0.0, 0.0))
	a.hand(12, Vector3(0.44, -0.08, 0.06), "f").hand(17, Vector3(0.36, -0.14, 0.1))
	a.hand(22, Vector3(0.26, -0.3, 0.16)).hand(27, Vector3(0.26, -0.32, -0.02)).hand(32, Vector3(0.26, -0.32, 0.12))
	a.free_home(38)
	a.pole(3, Vector3(0.6, -0.8, -0.2)).pole(9, Vector3(0.5, -0.4, -0.7)).pole(22, Vector3(0.6, -0.6, -0.5))
	a.let_go(1, 36)
	var g := _feet_base(c)
	var back := Vector2(0, -T)
	# the skid: both feet ride back with the body, the front toes up
	for s in ["l", "r"]:
		var i := 0 if s == "l" else 1
		var y := 0.22 if s == "l" else -0.22
		var front: bool = s == "l"
		_foot(c, s, 0, g[i], 0, y, 0, "f")
		c.pose(1, { "foot_%s_pos" % s: BWAnimClips.ankle(g[i] + back * 0.02, -0.06 if front else 0.0, y), "foot_%s_rot" % s: Vector3(-0.06 if front else 0.0, y, 0) })
		c.pose(4, { "foot_%s_pos" % s: BWAnimClips.ankle(g[i] + back * 0.36, -0.3 if front else 0.05, y), "foot_%s_rot" % s: Vector3(-0.3 if front else 0.05, y, 0) })
		c.pose(7, { "foot_%s_pos" % s: BWAnimClips.ankle(g[i] + back * 0.7, -0.28 if front else 0.04, y), "foot_%s_rot" % s: Vector3(-0.28 if front else 0.04, y, 0) })
		c.pose(10, { "foot_%s_pos" % s: BWAnimClips.ankle(g[i] + back * 0.93, -0.12 if front else 0.0, y), "foot_%s_rot" % s: Vector3(-0.12 if front else 0.0, y, 0) })
		_foot(c, s, 12, g[i] + back, 0, y, 0, "f")
	# home in three steps
	var r1: Vector2 = g[1] + back * 0.36
	_foot(c, "r", 17.5, g[1] + back, 0, -0.22, 0, "f")
	_step(c, "r", 17.5, 22.5, g[1] + back, r1, 0.08)
	_foot(c, "l", 22.5, g[0] + back, 0, 0.22, 0, "f")
	_step(c, "l", 22.5, 27.5, g[0] + back, g[0], 0.08)
	_foot(c, "r", 27.5, r1, 0, -0.22, 0, "f")
	_step(c, "r", 27.5, 32, r1, g[1], 0.06)
	_foot(c, "r", 48, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 48, g[0], 0, 0.22, 0, "f")
	return c


# ---------------------------------------------------------------------- rage

## RAGE (52 f): takes the hit (a recoil, f2-f4), then hunches and fumes:
## low, chest over, head down, fists in, a tremble (f6-f13); REARS UP into
## the shout (f16, "shout"): up on the toes, chest out, head thrown back,
## both arms flared wide and down behind her, a stretch; the shout holds
## with a shake (f16-f30); she comes down with the breath out, a glare
## forward, and stomps back to the guard.
static func rage(st: String) -> BWAnimClips.Clip:
	var c := _begin("stricken_rage", 52, st)
	c.marker("impact", 0).marker("catch", 8).marker("shout", 16).marker("recovered", 46).marker("pose", 20)
	c.pose(2, { "root": _r(c, Vector3(0, -0.05, -0.12)), "hips": Vector3(-0.1, 0.05, 0.03), "spine": Vector3(-0.12, 0, 0),
		"chest": Vector3(-0.22, 0.1, 0.06), "head": Vector3(0.14, -0.05, 0.0), "squash": 0.04, "head_sq": -0.03 })
	c.pose(4, { "head": Vector3(-0.18, 0.08, -0.03), "head_sq": 0.0 })
	# the fume: low and hunched, a tremble on ones
	c.pose(7, { "root": _r(c, Vector3(0, -0.15, -0.1)), "hips": Vector3(0.05, 0, 0), "spine": Vector3(0.1, 0, 0),
		"chest": Vector3(0.18, 0.0, 0.0), "neck": Vector3(0.04, 0, 0), "head": Vector3(0.1, 0, 0), "squash": -0.05, "head_sq": 0.03 })
	c.pose(9, { "chest": Vector3(0.2, 0.0, 0.025), "head": Vector3(0.12, 0.02, 0.02) }, "l")
	c.pose(10, { "chest": Vector3(0.2, 0.0, -0.025), "head": Vector3(0.12, -0.02, -0.02) }, "l")
	c.pose(11, { "chest": Vector3(0.21, 0.0, 0.025), "head": Vector3(0.13, 0.02, 0.02) }, "l")
	c.pose(12, { "chest": Vector3(0.21, 0.0, -0.02), "head": Vector3(0.14, -0.02, -0.02), "root": _r(c, Vector3(0, -0.17, -0.1)), "squash": -0.055 }, "l")
	c.pose(13, { "chest": Vector3(0.2, 0.0, 0.0), "head": Vector3(0.14, 0.0, 0.0), "head_sq": 0.03 })
	# REAR UP: the shout
	c.pose(16, { "root": _r(c, Vector3(0, 0.02, -0.06)), "hips": Vector3(-0.08, 0, 0), "spine": Vector3(-0.16, 0, 0),
		"chest": Vector3(-0.4, 0.0, 0.0), "neck": Vector3(-0.12, 0, 0), "head": Vector3(-0.42, 0.0, 0.0), "squash": 0.055, "head_sq": -0.05 })
	c.pose(18, { "root": _r(c, Vector3(0, 0.025, -0.06)), "chest": Vector3(-0.42, 0.0, 0.0), "head": Vector3(-0.46, 0.0, 0.0), "squash": 0.05, "head_sq": -0.035 }, "f")
	for k in 6:
		var f := 19.0 + k * 2.0
		var s := 1.0 if k % 2 == 0 else -1.0
		c.pose(f, { "head": Vector3(-0.46 + 0.01 * k, 0.025 * s, 0.02 * s), "chest": Vector3(-0.42 + 0.004 * k, 0.0, 0.012 * s), "head_sq": -0.03 - 0.006 * s }, "l")
	c.pose(30, { "root": _r(c, Vector3(0, 0.02, -0.06)), "chest": Vector3(-0.38, 0.0, 0.0), "head": Vector3(-0.38, 0.0, 0.0), "squash": 0.045, "head_sq": -0.02 }, "f")
	# down: the breath out, a glare
	c.pose(34, { "root": _r(c, Vector3(0, -0.1, -0.03)), "hips": Vector3(0.04, 0, 0), "spine": Vector3(0.06, 0, 0), "chest": Vector3(0.1, 0, 0),
		"neck": Vector3(0.0, 0, 0), "head": Vector3(0.1, 0, 0), "squash": -0.04, "head_sq": 0.03 })
	c.pose(37, { "root": _r(c, Vector3(0, -0.07, -0.02)), "chest": Vector3(0.06, 0, 0), "head": Vector3(-0.04, 0, 0), "squash": -0.01, "head_sq": 0.0 }, "f")
	c.pose(42, { "root": _r(c, Vector3(0, -0.02, 0.0)), "hips": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(0.02, 0, 0),
		"head": Vector3(-0.05, 0, 0), "squash": 0.01 })
	c.pose(46, { "root": _r(c, Vector3(0, -0.006, 0.0)), "chest": Vector3(0, 0, 0), "head": Vector3(-0.02, 0, 0), "squash": 0.0 }, "f")
	var a := Arms.new(c)
	a.weapon(2, Vector3(0.04, 0.08, -0.06), Vector3(-0.25, 0, 0))
	# the fume: weapon low and tight, the fist clenched in
	a.weapon(7, Vector3(-0.04, 0.0, 0.06), Vector3(-0.12, 0, 0))
	a.weapon(13, Vector3(-0.05, -0.01, 0.07), Vector3(-0.1, 0, 0), "f")
	# the shout: flared out wide and down behind
	var fa := a.flare_aim()
	a.weapon_aim(16, Vector3(0.24, 0.06, -0.14), fa)
	a.weapon_aim(18, Vector3(0.26, 0.07, -0.15), fa, "f")
	a.weapon_aim(30, Vector3(0.24, 0.06, -0.13), fa, "f")
	a.weapon(35, Vector3(0.02, -0.04, 0.05), Vector3(0.12, 0, 0))
	a.weapon(42, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, "f")
	a.hand(2, Vector3(0.36, 0.06, 0.14)).hand(4, Vector3(0.38, 0.08, 0.04))
	a.hand(7, Vector3(0.18, -0.24, 0.2)).hand(13, Vector3(0.17, -0.25, 0.21), "f")
	a.hand(16, Vector3(0.5, 0.06, -0.16)).hand(18, Vector3(0.52, 0.08, -0.17), "f").hand(30, Vector3(0.5, 0.06, -0.15), "f")
	a.hand(35, Vector3(0.24, -0.3, 0.12))
	a.free_home(42)
	a.pole(7, Vector3(0.6, -0.4, -0.6)).pole(16, Vector3(0.4, -0.9, -0.2)).pole(30, Vector3(0.4, -0.9, -0.2)).pole(38, Vector3(0.6, -0.6, -0.5))
	a.let_go(2, 40)
	var g := _feet_base(c)
	var wide_r: Vector2 = g[1] + Vector2(-0.07, -0.1)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 3, g[0], 0.12, 0.22)
	_foot(c, "l", 6, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 14, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 16, g[0], 0.26, 0.22)
	_foot(c, "l", 30, g[0], 0.24, 0.22, 0, "f")
	_foot(c, "l", 33, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 52, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 2, g[1], 0.25, -0.24)
	_foot(c, "r", 3.5, g[1].lerp(wide_r, 0.5), 0.08, -0.3, 0.06)
	_foot(c, "r", 5, wide_r, 0, -0.36, 0, "f")
	_foot(c, "r", 14, wide_r, 0, -0.36, 0, "f")
	_foot(c, "r", 16, wide_r, 0.22, -0.36)
	_foot(c, "r", 30, wide_r, 0.2, -0.36, 0, "f")
	_foot(c, "r", 33, wide_r, 0, -0.36, 0, "f")
	_step(c, "r", 37, 41, wide_r, g[1], 0.05)
	_foot(c, "r", 52, g[1], 0, -0.22, 0, "f")
	return c

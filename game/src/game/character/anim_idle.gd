class_name BWAnimIdle
extends RefCounted
## Standing clips for every set (design/art/ANIMATION.md, "Idles"):
##
##   idle          the home loop. The heavy set keeps the approved style-bar
##                 idle (Alexandra) exactly; every other set gets the same
##                 body (two weight shifts on a different beat from two
##                 breaths, chin up, look-off) and its own weapon "hup"
##   idle_bouncy   the home loop of the energetic (bouncy) characters: up on
##                 the toes, two bounces per 0.67 s, weight rocking
##   idle_fidget   one-shot: weight onto one hip, the right foot shuffles out
##                 and back, a shoulder roll and a neck stretch
##   idle_weapon   one-shot, per style: a twirl or a check (sword twirl,
##                 heavy shoulder bounce, polearm blade check, spear sight,
##                 staff overhead spin, dagger flips, bow string pluck,
##                 pistol spin)
##   idle_look     one-shot: looks off left, then right, then back
##   wounded       the idle below 35% HP: hunched, breathing hard, weight off
##                 the hurt right leg, hand pressed to the side, a wince
##   cheer         victory loop: weapon hoisted, pumping on the toes
##   cheer_jump    victory loop: jumps with a fist pump
##   cheer_cool    victory loop: weapon on the shoulder, hand on the hip, nods
##
## Variants are picked per character by BWAnimClips.personality() and
## rotated by BWAnimator while the character stands.


static func clips(st: String) -> Array:
	var standing := [idle(st), idle_bouncy(st), idle_fidget(st), idle_weapon(st), idle_look(st), wounded(st)]
	for c in standing:
		calm(c)
	return standing + [cheer(st), cheer_jump(st), cheer_cool(st)]


## The author's call (D65, "the most bouncy thing I have ever seen"): every
## standing clip plays at CALM_LOOP (loops) / CALM_VARIANT (the one-shot
## variants) of its authored motion. The bake scales each channel's motion
## about the loop's own average pose (so the approved idle keeps its shape:
## chin up, the hip sit, the "hup", only smaller) or, for one-shots, about
## the guard they start and end on. The authored keys stay as written.
const CALM_LOOP := 0.22
const CALM_VARIANT := 0.22


static func calm(c: BWAnimClips.Clip) -> BWAnimClips.Clip:
	c.calm = CALM_LOOP if c.loop else CALM_VARIANT
	# the weapon trick is a handling action now (D80): the body stays calm,
	# the weapon moves at full size ("the weapons seem incredibly stiff")
	if c.name == "idle_weapon":
		c.calm_hands = false
	return c


# ----------------------------------------------------------------- helpers

static func _feet_at_base(c: BWAnimClips.Clip, f: float) -> void:
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	c.pose(f, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")


## Weapon hand channels (pos + aim) of the guard moved by d and turned by rot.
static func _weapon(c: BWAnimClips.Clip, f: float, d: Vector3, rot: Vector3, mode: String = "a") -> void:
	var wh := BWAnimCarry.weapon_hand(c.style)
	var hands := ["hand_r", "hand_l"] if wh == "both" else ["hand_" + wh]
	if BWAnimCarry.two_handed(c.style):
		hands = ["hand_r"]
	for h in hands:
		var dd := d if h == "hand_r" else Vector3(-d.x, d.y, d.z)
		var rr := rot if h == "hand_r" else Vector3(rot.x, -rot.y, -rot.z)
		c.key(h + "_pos", f, (c.base[h + "_pos"] as Vector3) + dd, mode)
		c.key(h + "_aim", f, (Basis.from_euler(rr) * (c.base[h + "_aim"] as Vector3)).normalized(), mode)


## The free hand moved from the guard by d (it rides the chest).
static func _free(c: BWAnimClips.Clip, f: float, d: Vector3, mode: String = "a") -> void:
	var fh := BWAnimCarry.free_hand(c.style)
	if fh == "" or BWAnimCarry.two_handed(c.style):
		return
	var dd := d if fh == "l" else Vector3(-d.x, d.y, d.z)
	c.key("hand_%s_pos" % fh, f, (c.base["hand_%s_pos" % fh] as Vector3) + dd, mode)


## Aims around an axis: one key every `step` frames while the aim turns
## `turns` full circles about `axis` (chest frame) from `from`.
static func _spin(c: BWAnimClips.Clip, ch: String, f0: float, f1: float, from: Vector3, axis: Vector3, turns: float) -> void:
	var n := int(ceil(absf(turns) * 6.0))
	for i in n + 1:
		var u := float(i) / n
		# eased spin: quick through the middle, slower at the catch
		var e := u * u * (3.0 - 2.0 * u) * 0.5 + u * 0.5
		c.key(ch, lerpf(f0, f1, u), (Basis(axis.normalized(), TAU * turns * e) * from).normalized(), "a")


## A static key's hand channels, shifted (cheers, holds).
static func _key(st: String, pose_name: String) -> Dictionary:
	return BWAnimCarry.key_hands(pose_name, st)


# --------------------------------------------------------------------- idle

## IDLE. Heavy: the approved style-bar clip. Others: its body and feet,
## with the weapon "hup" carried by each style's own guard.
static func idle(st: String) -> BWAnimClips.Clip:
	if st == "heavy":
		return BWAnimClips._idle()
	var c := BWAnimClips.new_clip("idle", 60, true, st)
	var b := c.base
	c.pose(0, { "root": Vector3(0.03, -0.044, 0.0), "hips": Vector3(0.0, -0.07, 0.085),
		"spine": Vector3(0.03, 0.02, -0.03), "chest": Vector3(0.0, 0.04, -0.05) }, "f")
	c.pose(14, { "root": Vector3(0.004, -0.030, 0.006) })
	c.pose(30, { "root": Vector3(-0.025, -0.048, 0.0), "hips": Vector3(0.0, 0.04, -0.07),
		"spine": Vector3(0.035, -0.01, 0.03), "chest": Vector3(0.02, -0.02, 0.04) }, "f")
	c.pose(44, { "root": Vector3(0.002, -0.032, 0.006) })
	c.key("chest", 8, Vector3(-0.025, 0.02, -0.01))
	c.key("chest", 38, Vector3(-0.01, -0.03, 0.045))
	c.key("squash", 8, 0.012).key("squash", 22, -0.006).key("squash", 38, 0.012).key("squash", 52, -0.006)
	c.pose(0, { "neck": Vector3(-0.03, 0.0, 0.0), "head": Vector3(-0.07, 0.10, 0.06) }, "f")
	c.pose(18, { "head": Vector3(-0.04, 0.22, -0.02) })
	c.pose(34, { "head": Vector3(-0.08, 0.05, -0.07) }, "f")
	c.pose(50, { "head": Vector3(-0.05, -0.04, 0.02) })
	c.key("head_sq", 41, 0.0).key("head_sq", 44, 0.025).key("head_sq", 48, -0.01).key("head_sq", 52, 0.0)
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	c.proc("foot_l_pos", func(f: float) -> Vector3:
		return BWAnimClips.ankle(fl, BWAnimClips._bump(f, 30.0, 11.0) * 0.22, 0.24))
	c.proc("foot_l_rot", func(f: float) -> Vector3:
		return Vector3(BWAnimClips._bump(f, 30.0, 11.0) * 0.22, 0.24, 0))
	c.proc("foot_r_pos", func(f: float) -> Vector3:
		return BWAnimClips.ankle(fr, BWAnimClips._bump(fposmod(f + 30.0, 60.0), 30.0, 10.0) * 0.16, -0.24))
	c.proc("foot_r_rot", func(f: float) -> Vector3:
		return Vector3(BWAnimClips._bump(fposmod(f + 30.0, 60.0), 30.0, 10.0) * 0.16, -0.24, 0))
	# the hup: lift, drop, overshoot, settle - each style's weapon in its own guard
	var lift: float = { "one": 0.07, "polearm": 0.05, "spear": 0.06, "staff": 0.05, "pair": 0.05, "bow": 0.05, "pistol": 0.06 }.get(st, 0.06)
	_weapon(c, 2, Vector3(0.01, 0.0, 0.0), Vector3.ZERO, "f")
	_weapon(c, 20, Vector3(0.0, 0.012, 0.01), Vector3(-0.03, 0.0, 0.0))
	_weapon(c, 33, Vector3(-0.012, -0.004, 0.0), Vector3(0.04, 0.0, 0.0), "f")
	_weapon(c, 37, Vector3(-0.004, lift * 0.87, 0.02), Vector3(-0.12, 0.0, 0.04))
	_weapon(c, 39, Vector3(0.0, lift, 0.02), Vector3(-0.16, 0.0, 0.05), "f")
	_weapon(c, 43, Vector3(0.006, -lift * 0.3, 0.0), Vector3(0.05, 0.0, -0.02))
	_weapon(c, 47, Vector3(0.008, 0.008, 0.004), Vector3.ZERO)
	_free(c, 4, Vector3(0.0, 0.0, 0.0), "f")
	_free(c, 24, Vector3(-0.01, 0.015, 0.01))
	_free(c, 40, Vector3(0.0, 0.03, 0.0))
	_free(c, 44, Vector3(0.0, -0.01, 0.0), "f")
	c.key("chest", 40, Vector3(-0.03, -0.02, 0.03))
	return c


## IDLE_BOUNCY (16 f loop, 0.67 s): up on the balls of the feet, two
## bounces, weight rocking side to side, chin up. Head and hands drag a
## frame; the weapon bobs a frame after that.
static func idle_bouncy(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("idle_bouncy", 16, true, st)
	var b := c.base
	for half in [0, 1]:
		var f: float = half * 8.0
		var s: float = 1.0 if half == 0 else -1.0
		c.pose(f + 0, { "root": Vector3(0.025 * s, -0.10, 0.02), "hips": Vector3(0.03, -0.05 * s, 0.06 * s),
			"chest": Vector3(0.05, 0.05 * s, -0.04 * s), "squash": -0.03 }, "f")
		c.pose(f + 4, { "root": Vector3(0.0, -0.025, 0.02), "hips": Vector3(0.0, 0.0, 0.0),
			"chest": Vector3(-0.02, 0.0, 0.0), "squash": 0.025 }, "f")
		c.pose(f + 1, { "head": Vector3(0.04, 0.06 * s, 0.03 * s), "head_sq": 0.04 })
		c.pose(f + 5, { "head": Vector3(-0.12, 0.02 * s, -0.02 * s), "head_sq": -0.025 })
		_weapon(c, f + 1.5, Vector3(0.0, -0.035, 0.0), Vector3(0.06, 0.0, 0.0), "f")
		_weapon(c, f + 5.5, Vector3(0.0, 0.03, 0.01), Vector3(-0.07, 0.0, 0.0), "f")
		_free(c, f + 1.5, Vector3(0.0, -0.03, 0.02), "f")
		_free(c, f + 5.5, Vector3(0.0, 0.03, 0.0), "f")
	c.key("spine", 0, Vector3(0.06, 0, 0))
	c.key("neck", 0, Vector3(-0.04, 0, 0))
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	# both heels peel on every rise; the unweighted heel more
	for side in ["l", "r"]:
		var g := fl if side == "l" else fr
		var y := 0.22 if side == "l" else -0.22
		var sd := 1.0 if side == "l" else -1.0
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return BWAnimClips.ankle(g, _bounce_heel(f, sd), y))
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return Vector3(_bounce_heel(f, sd), y, 0))
	return c


static func _bounce_heel(f: float, sd: float) -> float:
	var up := 0.5 - 0.5 * cos(fposmod(f, 8.0) / 8.0 * TAU)        # 0 down .. 1 up
	var weight := 0.5 + 0.5 * cos(f / 16.0 * TAU) * sd              # 1 when the weight is on this foot
	return up * (0.3 + 0.2 * (1.0 - weight))


# ------------------------------------------------------------------- fidget

## IDLE_FIDGET (48 f, 2 s): she sinks onto the left hip, the right foot
## shuffles out and turns (f12-f19), a shoulder roll and a neck stretch
## (head tipped to the left, f22-f30), then the foot comes back (f32-f37)
## and she resets with a little shake-out.
static func idle_fidget(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("idle_fidget", 48, false, st)
	var b := c.base
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_"):
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(48, all + hand_all)
	c.pose(6, { "root": Vector3(0.04, -0.06, 0.0), "hips": Vector3(0.0, -0.06, 0.1), "spine": Vector3(0.03, 0.02, -0.04),
		"chest": Vector3(0.0, 0.03, -0.06), "head": Vector3(0.0, 0.05, 0.04) }, "f")
	c.pose(12, { "root": Vector3(0.05, -0.065, 0.0) })
	# the shoulder roll: chest lifts and rolls back, then drops (f18-f26)
	c.pose(18, { "chest": Vector3(-0.08, 0.06, -0.09), "squash": 0.02, "neck": Vector3(-0.02, 0, 0) })
	c.pose(22, { "chest": Vector3(-0.04, -0.04, -0.05), "squash": 0.025 })
	c.pose(26, { "chest": Vector3(0.05, 0.0, -0.04), "squash": -0.015 }, "f")
	# neck stretch: head tips to the left shoulder, a beat, then the other way
	c.pose(24, { "head": Vector3(0.0, 0.06, 0.28), "head_sq": 0.0 }, "f")
	c.pose(29, { "head": Vector3(-0.02, -0.04, -0.2) }, "f")
	c.pose(33, { "head": Vector3(-0.06, 0.08, 0.04), "root": Vector3(0.02, -0.05, 0.0) })
	# shake-out: small quick wobble as she resets
	c.pose(38, { "root": Vector3(-0.01, -0.07, 0.0), "squash": -0.02, "head_sq": 0.02, "chest": Vector3(0.02, -0.03, 0.02) })
	c.pose(41, { "root": Vector3(0.0, -0.025, 0.0), "squash": 0.015, "head_sq": -0.01, "chest": Vector3(0.0, 0.02, -0.01) })
	# hands: ride the shoulder roll
	_weapon(c, 18, Vector3(0.0, 0.04, -0.02), Vector3(-0.06, 0.0, 0.0))
	_weapon(c, 26, Vector3(0.0, -0.03, 0.01), Vector3(0.05, 0.0, 0.0), "f")
	_weapon(c, 38, Vector3(0.0, -0.02, 0.0), Vector3(0.03, 0, 0))
	_free(c, 18, Vector3(0.0, 0.05, -0.03))
	_free(c, 26, Vector3(0.0, -0.02, 0.02), "f")
	# the right foot shuffles out and back
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fr2 := fr + Vector2(-0.07, 0.06)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	c.pose(48, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	c.pose(0, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(11, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(13, { "foot_r_pos": BWAnimClips.ankle(fr, 0.3, -0.22), "foot_r_rot": Vector3(0.3, -0.22, 0) })
	c.pose(15.5, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.1, -0.35, 0.06), "foot_r_rot": Vector3(0.1, -0.35, 0) })
	c.pose(18, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.5), "foot_r_rot": Vector3(0, -0.5, 0) }, "f")
	c.pose(32, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.5), "foot_r_rot": Vector3(0, -0.5, 0) }, "f")
	c.pose(34, { "foot_r_pos": BWAnimClips.ankle(fr2, 0.3, -0.5), "foot_r_rot": Vector3(0.3, -0.5, 0) })
	c.pose(36, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.1, -0.35, 0.05), "foot_r_rot": Vector3(0.1, -0.35, 0) })
	c.pose(38.5, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(48, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.meta = { "variant": true }
	return c


# --------------------------------------------------------------- look around

## IDLE_LOOK (56 f): the head dips (anticipation), snaps to look off to her
## left with a small overshoot, holds; sweeps to the right past the front,
## holds; then back. The chest follows 40% a frame late, the hips 15%.
static func idle_look(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("idle_look", 56, false, st)
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_"):
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(56, all + hand_all)
	_feet_at_base(c, 0)
	_feet_at_base(c, 56)
	var looks := [[3, Vector3(0.08, -0.06, 0.0), "f"], [7, Vector3(-0.06, 0.78, 0.06), "a"], [8.5, Vector3(-0.05, 0.84, 0.07), "f"],
		[10, Vector3(-0.05, 0.8, 0.06), "f"], [18, Vector3(-0.08, 0.76, 0.05), "f"], [21, Vector3(0.06, 0.2, 0.0), "a"],
		[25, Vector3(-0.04, -0.82, -0.06), "a"], [26.5, Vector3(-0.03, -0.88, -0.07), "f"], [28, Vector3(-0.03, -0.84, -0.06), "f"],
		[38, Vector3(-0.07, -0.8, -0.05), "f"], [42, Vector3(0.05, -0.2, 0.0), "a"], [45, Vector3(-0.06, 0.06, 0.02), "f"]]
	for k in looks:
		c.key("head", float(k[0]), k[1], str(k[2]))
		c.key("chest", float(k[0]) + 1.5, Vector3(0.0, (k[1] as Vector3).y * 0.4, 0.0), "a")
		c.key("hips", float(k[0]) + 2.5, Vector3(0.0, (k[1] as Vector3).y * 0.15, 0.0), "a")
	c.key("head_sq", 7, 0.03).key("head_sq", 9, -0.01).key("head_sq", 25, 0.03).key("head_sq", 27, -0.01).key("head_sq", 31, 0.0)
	c.pose(30, { "root": Vector3(-0.025, -0.05, 0.0) }, "f")
	_weapon(c, 9, Vector3(0.0, 0.02, 0.0), Vector3(-0.04, 0.0, 0.0))
	_weapon(c, 27, Vector3(0.0, 0.02, 0.0), Vector3(-0.04, 0.0, 0.0))
	# the first look is a proper search: up on her toes, the free hand up as
	# a visor, then down onto her heels with a little squash
	var fh := BWAnimCarry.free_hand(st)
	if fh != "" and not BWAnimCarry.two_handed(st):
		var sx := 1.0 if fh == "l" else -1.0
		var g0: Vector3 = c.base["hand_%s_pos" % fh]
		c.key("hand_%s_pos" % fh, 4, g0, "f")
		c.key("hand_%s_pos" % fh, 8, Vector3(0.07 * sx, 0.42, 0.24))
		c.key("hand_%s_pos" % fh, 9.5, Vector3(0.06 * sx, 0.45, 0.25), "f")
		c.key("hand_%s_pos" % fh, 17, Vector3(0.06 * sx, 0.44, 0.25), "f")
		c.key("hand_%s_pos" % fh, 22, g0 + Vector3(0, 0.02, 0.0))
		c.key("hand_%s_pole" % fh, 6, Vector3(1.0 * sx, -0.3, -0.4)).key("hand_%s_pole" % fh, 22, c.base["hand_%s_pole" % fh])
	c.pose(9, { "root": Vector3(0.02, -0.01, 0.0), "squash": 0.02 }, "f")
	c.pose(17, { "root": Vector3(0.02, -0.012, 0.0), "squash": 0.015 }, "f")
	c.pose(20.5, { "root": Vector3(0.0, -0.075, 0.0), "squash": -0.025, "head_sq": 0.02 })
	c.pose(23, { "root": Vector3(-0.01, -0.04, 0.0), "squash": 0.005, "head_sq": 0.0 })
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	for side in ["l", "r"]:
		var g: Vector2 = fl if side == "l" else fr
		var y := 0.22 if side == "l" else -0.22
		c.pose(6, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % side: Vector3(0, y, 0) }, "f")
		c.pose(9, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0.42, y), "foot_%s_rot" % side: Vector3(0.42, y, 0) }, "f")
		c.pose(17, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0.4, y), "foot_%s_rot" % side: Vector3(0.4, y, 0) }, "f")
		c.pose(20, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % side: Vector3(0, y, 0) }, "f")
	c.meta = { "variant": true }
	return c


# ------------------------------------------------------------ weapon idles

## IDLE_WEAPON: the per-style twirl or check. One-shot, guard to guard.
static func idle_weapon(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("idle_weapon", 54, false, st)
	var b := c.base
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch == "flat":
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(54, all + hand_all)
	_feet_at_base(c, 0)
	_feet_at_base(c, 54)
	c.meta = { "variant": true, "handling": "act", "kind": "trick", "from": "guard", "to": "guard" }
	# a shared body beat: settle in (f4), the trick (f8-f34), the "ta-da" (f36-f42)
	c.pose(4, { "root": Vector3(0.0, -0.07, 0.0), "squash": -0.015, "head": Vector3(0.12, 0.0, 0.0) }, "f")
	c.pose(38, { "root": Vector3(0.0, -0.015, 0.0), "squash": 0.02, "head_sq": -0.015, "head": Vector3(-0.12, 0.06, 0.03) }, "f")
	c.pose(44, { "root": Vector3(0.0, -0.05, 0.0), "squash": -0.005, "head_sq": 0.01 })
	match st:
		"one":
			# a wrist twirl at her side: the blade circles in the side plane twice,
			# then she lifts it level and sights along the edge
			var h0 := Vector3(-0.32, -0.02, 0.14)
			c.key("hand_r_pos", 6, h0, "f").key("hand_r_pos", 22, h0 + Vector3(0, 0.02, 0.02), "a")
			_spin(c, "hand_r_aim", 7.0, 21.0, Vector3(0, 0.45, 0.9).normalized(), Vector3(1, 0, 0), 2.0)
			c.key("hand_r_pos", 27, Vector3(-0.14, 0.24, 0.32), "f").key("hand_r_aim", 27, Vector3(0.95, 0.05, 0.3).normalized(), "f")
			c.key("hand_r_pos", 34, Vector3(-0.14, 0.25, 0.32), "f").key("hand_r_aim", 34, Vector3(0.95, 0.08, 0.3).normalized(), "f")
			c.key("hand_r_edge", 27, Vector3(0, 1, 0), "f").key("hand_r_edge", 34, Vector3(0, 1, 0), "f")
			c.pose(27, { "head": Vector3(0.1, 0.25, -0.12), "chest": Vector3(0.0, 0.1, 0.0) }, "f")
			c.pose(34, { "head": Vector3(0.1, 0.3, -0.12) }, "f")
			c.key("flat", 24, 0.2).key("flat", 36, 0.2)
		"heavy":
			# heave it onto the shoulder, two easy bounces, back down to the guard
			var sh := BWAnimCarry.loco("heavy", "walk_heavy")
			c.pose(8, { "hand_r_pos": Vector3(-0.2, 0.02, 0.24), "hand_r_aim": Vector3(-0.5, 0.75, -0.42).normalized(), "squash": -0.03 })
			c.pose(11, sh.a, "f")
			c.pose(11, sh.k)
			c.pose(15, { "hand_r_pos": (sh.a.hand_r_pos as Vector3) + Vector3(0, 0.05, 0) })
			c.pose(18, { "hand_r_pos": (sh.a.hand_r_pos as Vector3) + Vector3(0, -0.02, 0) }, "f")
			c.pose(22, { "hand_r_pos": (sh.a.hand_r_pos as Vector3) + Vector3(0, 0.05, 0) })
			c.pose(25, { "hand_r_pos": (sh.a.hand_r_pos as Vector3) + Vector3(0, -0.01, 0) }, "f")
			c.pose(14, { "root": Vector3(0, -0.03, 0), "head": Vector3(-0.1, -0.15, 0.05) })
			c.pose(17, { "root": Vector3(0, -0.075, 0), "squash": -0.02 })
			c.pose(21, { "root": Vector3(0, -0.03, 0), "squash": 0.015 })
			c.pose(24, { "root": Vector3(0, -0.07, 0), "squash": -0.015, "head": Vector3(-0.08, 0.1, -0.03) })
			c.pose(32, sh.a, "f")
			c.key("hand_l_grip", 30, 1.0)
		"polearm":
			# lifts the blade to eye level, turns it in the fingers to check the
			# edge, then a firm plant back to the guard
			var h1 := Vector3(-0.22, 0.12, 0.26)
			c.key("hand_r_pos", 10, h1, "f").key("hand_r_aim", 10, Vector3(-0.15, 0.95, 0.27).normalized(), "f")
			c.key("hand_l_grip", 8, 0.0)
			c.key("hand_r_pos", 30, h1 + Vector3(0, 0.02, 0), "f").key("hand_r_aim", 30, Vector3(-0.12, 0.96, 0.25).normalized(), "f")
			_spin(c, "hand_r_edge", 12.0, 28.0, Vector3(0, 0, 1), Vector3(0, 1, 0), 1.0)
			c.pose(12, { "head": Vector3(-0.3, -0.05, 0.0), "neck": Vector3(-0.05, 0, 0) }, "f")
			c.pose(28, { "head": Vector3(-0.32, 0.05, 0.03) }, "f")
			c.key("flat", 10, 0.0).key("flat", 30, 0.0)
		"spear":
			# sights along the javelin like a throw, then flips it back down
			c.key("hand_r_pos", 10, Vector3(-0.3, 0.26, -0.02), "f").key("hand_r_aim", 10, Vector3(0.05, 0.1, 0.99).normalized(), "f")
			c.key("hand_r_pos", 28, Vector3(-0.3, 0.28, 0.0), "f").key("hand_r_aim", 28, Vector3(0.05, 0.12, 0.99).normalized(), "f")
			c.pose(12, { "head": Vector3(0.08, -0.25, 0.1), "chest": Vector3(-0.04, -0.15, 0.0), "hips": Vector3(0, -0.08, 0) }, "f")
			c.pose(26, { "head": Vector3(0.08, -0.3, 0.1) }, "f")
			_free(c, 12, Vector3(-0.1, 0.15, 0.25), "f")
			_free(c, 26, Vector3(-0.1, 0.16, 0.26), "f")
			c.key("hand_r_pos", 33, Vector3(-0.3, 0.05, 0.1))
			_spin(c, "hand_r_aim", 30.0, 40.0, Vector3(0.05, 0.12, 0.99).normalized(), Vector3(1, 0, 0), -1.25)
		"staff":
			# overhead spin: the staff lies flat and turns a circle and a half above her
			c.key("hand_l_grip", 6, 0.0)
			c.key("hand_r_pos", 9, Vector3(-0.12, 0.5, 0.12), "f")
			c.key("hand_r_pos", 28, Vector3(-0.12, 0.52, 0.12), "a")
			_spin(c, "hand_r_aim", 9.0, 27.0, Vector3(0.0, 0.08, 1.0).normalized(), Vector3(0, 1, 0), 1.5)
			c.key("hand_r_edge", 9, Vector3(0, 1, 0)).key("hand_r_edge", 27, Vector3(0, 1, 0))
			c.pose(10, { "head": Vector3(-0.25, 0.0, 0.0), "chest": Vector3(-0.05, 0, 0) }, "f")
			c.pose(20, { "head": Vector3(-0.22, 0.1, 0.04), "root": Vector3(0, -0.04, 0) })
			c.pose(27, { "head": Vector3(-0.2, -0.05, 0.0) }, "f")
			_free(c, 12, Vector3(-0.02, 0.25, 0.1))
			_free(c, 26, Vector3(-0.02, 0.27, 0.1))
			c.key("flat", 9, 0.0).key("flat", 28, 0.0)
		"pair":
			# flips: the right dagger spins a full turn in the hand, then the left
			c.key("hand_r_pos", 8, Vector3(-0.24, -0.12, 0.26), "f").key("hand_l_pos", 8, Vector3(0.24, -0.12, 0.26), "f")
			_spin(c, "hand_r_aim", 9.0, 16.0, Vector3(-0.1, 0.5, 0.86).normalized(), Vector3(1, 0, 0), 1.0)
			_spin(c, "hand_l_aim", 17.0, 24.0, Vector3(0.1, 0.5, 0.86).normalized(), Vector3(1, 0, 0), 1.0)
			c.key("hand_r_pos", 13, Vector3(-0.24, 0.0, 0.28)).key("hand_r_pos", 17, Vector3(-0.24, -0.13, 0.26), "f")
			c.key("hand_l_pos", 21, Vector3(0.24, 0.0, 0.28)).key("hand_l_pos", 25, Vector3(0.24, -0.13, 0.26), "f")
			# and a cross-guard flourish
			c.key("hand_r_pos", 30, Vector3(0.0, 0.1, 0.34), "f").key("hand_r_aim", 30, Vector3(0.65, 0.7, 0.3).normalized(), "f")
			c.key("hand_l_pos", 30, Vector3(0.02, 0.1, 0.32), "f").key("hand_l_aim", 30, Vector3(-0.65, 0.7, 0.3).normalized(), "f")
			c.key("hand_r_pos", 34, Vector3(0.0, 0.11, 0.34), "f").key("hand_l_pos", 34, Vector3(0.02, 0.11, 0.32), "f")
			c.key("hand_r_aim", 34, Vector3(0.65, 0.7, 0.3).normalized(), "f").key("hand_l_aim", 34, Vector3(-0.65, 0.7, 0.3).normalized(), "f")
			c.pose(12, { "head": Vector3(0.18, 0.2, 0.04) })
			c.pose(20, { "head": Vector3(0.18, -0.2, -0.04) })
			c.pose(31, { "head": Vector3(-0.1, 0.0, 0.0) }, "f")
		"bow":
			# brings the bow up, plucks the string twice and listens
			c.key("hand_l_pos", 9, Vector3(0.12, 0.05, 0.36), "f").key("hand_l_aim", 9, Vector3(-0.2, 0.95, 0.1).normalized(), "f")
			c.key("hand_l_pos", 32, Vector3(0.12, 0.06, 0.36), "f").key("hand_l_aim", 32, Vector3(-0.22, 0.95, 0.1).normalized(), "f")
			c.key("hand_r_grip", 11, 0.0).key("hand_r_grip", 14, 1.0).key("hand_r_grip", 16, 0.2).key("hand_r_grip", 20, 1.0)
			c.key("hand_r_grip", 22, 0.2).key("hand_r_grip", 26, 0.0)
			c.key("hand_r_pos", 12, Vector3(-0.05, 0.05, 0.2)).key("hand_r_pos", 18, Vector3(-0.08, 0.08, 0.16))
			c.key("hand_r_pos", 24, Vector3(-0.1, 0.0, 0.12))
			c.pose(14, { "head": Vector3(0.12, 0.22, 0.3), "neck": Vector3(0.0, 0.0, 0.08) }, "f")
			c.pose(26, { "head": Vector3(0.1, 0.18, 0.32) }, "f")
			c.key("flat", 9, 0.0).key("flat", 32, 0.0)
		"fists":
			# shadowboxing: a double jab and a cross into the air, then the
			# wraps tugged tight (fists squeezed in at the chest)
			var g := { "r": BWCharacterPose._fist("r", Vector3(-0.19, 0.30, 0.26), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0), Vector3.ZERO),
				"l": BWCharacterPose._fist("l", Vector3(0.17, 0.34, 0.36), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0), Vector3.ZERO) }
			var jab := BWCharacterPose._fist("l", Vector3.ZERO, Vector3(-0.08, 0.05, 1), Vector3(0.2, 1, 0), Vector3.ZERO)
			var cross := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.12, 0.05, 1), Vector3(-0.2, 1, 0), Vector3.ZERO)
			for k in [[7.0, g.l.pos, g.l.aim, "f"], [9.0, Vector3(0.08, 0.33, 0.6), jab.aim, "a"], [11.0, Vector3(0.15, 0.33, 0.4), g.l.aim, "a"],
					[13.0, Vector3(0.08, 0.33, 0.62), jab.aim, "a"], [15.5, g.l.pos, g.l.aim, "f"], [24.0, g.l.pos, g.l.aim, "f"]]:
				c.key("hand_l_pos", float(k[0]), k[1], str(k[3])).key("hand_l_aim", float(k[0]), k[2], str(k[3]))
			for k in [[14.0, g.r.pos, g.r.aim, "f"], [17.0, Vector3(-0.04, 0.31, 0.64), cross.aim, "a"], [20.5, g.r.pos, g.r.aim, "f"]]:
				c.key("hand_r_pos", float(k[0]), k[1], str(k[3])).key("hand_r_aim", float(k[0]), k[2], str(k[3]))
			c.key("hand_l_edge", 9, jab.edge).key("hand_l_edge", 15.5, g.l.edge, "f").key("hand_r_edge", 17, cross.edge).key("hand_r_edge", 20.5, g.r.edge, "f")
			# the wraps: fists pulled in together at the chest, a squeeze, apart
			c.key("hand_r_pos", 27, Vector3(-0.06, 0.08, 0.26), "f").key("hand_l_pos", 27, Vector3(0.06, 0.08, 0.26), "f")
			c.key("hand_r_pos", 31, Vector3(-0.05, 0.09, 0.25)).key("hand_l_pos", 31, Vector3(0.05, 0.09, 0.25))
			c.key("hand_r_pos", 34, Vector3(-0.07, 0.07, 0.26), "f").key("hand_l_pos", 34, Vector3(0.07, 0.07, 0.26), "f")
			c.pose(9, { "head": Vector3(0.05, 0.08, 0.0), "chest": Vector3(0.0, -0.08, 0.0) })
			c.pose(17, { "head": Vector3(0.05, -0.08, 0.0), "chest": Vector3(0.02, 0.12, 0.0) })
			c.pose(28, { "head": Vector3(0.22, 0.0, 0.0) }, "f")
			c.pose(34, { "head": Vector3(0.2, 0.02, 0.0) }, "f")
		"pistol":
			# spins it on the trigger finger (two turns), catches it and checks the muzzle
			c.key("hand_r_pos", 7, Vector3(-0.3, -0.05, 0.2), "f")
			_spin(c, "hand_r_aim", 8.0, 20.0, Vector3(0, 0.87, 0.5).normalized(), Vector3(1, 0, 0), -2.0)
			_spin(c, "hand_r_edge", 8.0, 20.0, Vector3(0, -0.5, 0.87).normalized(), Vector3(1, 0, 0), -2.0)
			c.key("hand_r_pos", 20, Vector3(-0.3, -0.04, 0.2), "f")
			c.key("hand_r_pos", 26, Vector3(-0.14, 0.32, 0.18), "f").key("hand_r_aim", 26, Vector3(0.1, 0.05, -1.0).normalized(), "f")
			c.key("hand_r_edge", 26, Vector3(0, 1, 0.1), "f").key("hand_r_edge", 33, Vector3(0, 1, 0.1), "f")
			c.key("hand_r_pos", 33, Vector3(-0.14, 0.33, 0.18), "f").key("hand_r_aim", 33, Vector3(0.1, 0.05, -1.0).normalized(), "f")
			c.pose(12, { "head": Vector3(0.15, -0.15, 0.0) })
			c.pose(26, { "head": Vector3(0.05, -0.25, -0.1) }, "f")
			c.pose(33, { "head": Vector3(0.02, -0.28, -0.1) }, "f")
	return c


# ------------------------------------------------------------------ wounded

## WOUNDED (40 f loop): hunched over the hurt right side, weight on the
## left leg, the right heel up. Hard breathing (fast in, slower out, two
## per loop) and a wince on f26 (a jolt, the shoulders hitch).
static func wounded(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("wounded", 40, true, st)
	var b := c.base
	c.pose(0, { "root": Vector3(0.05, -0.12, 0.0), "hips": Vector3(0.06, -0.08, 0.1), "spine": Vector3(0.18, 0.0, 0.03),
		"chest": Vector3(0.14, 0.06, 0.08), "neck": Vector3(0.08, 0, 0), "head": Vector3(0.12, 0.05, 0.04), "squash": -0.02 }, "f")
	for i in 2:
		var f := i * 20.0
		c.pose(f + 5, { "chest": Vector3(0.06, 0.06, 0.07), "squash": 0.02, "root": Vector3(0.05, -0.105, 0.0), "head": Vector3(0.06, 0.05, 0.04) })
		c.pose(f + 14, { "chest": Vector3(0.15, 0.06, 0.09), "squash": -0.025, "root": Vector3(0.05, -0.125, 0.0), "head": Vector3(0.13, 0.05, 0.05) }, "f")
	# the wince
	c.pose(25, { "chest": Vector3(0.1, 0.07, 0.08) })
	c.pose(26.5, { "chest": Vector3(0.24, 0.12, 0.16), "head": Vector3(0.24, 0.1, 0.12), "squash": -0.045, "head_sq": 0.05,
		"root": Vector3(0.06, -0.15, 0.0) })
	c.pose(30, { "chest": Vector3(0.12, 0.06, 0.08), "head": Vector3(0.1, 0.02, 0.03), "head_sq": -0.01 })
	c.pose(33, { "head_sq": 0.0 })
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22) + Vector2(0.0, 0.06)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0.45, -0.3), "foot_r_rot": Vector3(0.45, -0.3, 0),
		"foot_r_pole": Vector3(-0.2, 0, 1) }, "f")
	c.pose(26.5, { "foot_r_pos": BWAnimClips.ankle(fr, 0.6, -0.3), "foot_r_rot": Vector3(0.6, -0.3, 0) })
	c.pose(31, { "foot_r_pos": BWAnimClips.ankle(fr, 0.45, -0.3), "foot_r_rot": Vector3(0.45, -0.3, 0) }, "f")
	BWAnimLoco._wounded_hands(c, st, [[0.0, 0.0], [14.0, 0.6], [26.5, 1.0], [32.0, 0.2]])
	return c


# ------------------------------------------------------------------- cheers

## The weapon raised: the static cheer key's hands (reviewed, per style).
static func _raised(st: String) -> Dictionary:
	return _key(st, "cheer")


## CHEER (24 f loop): weapon hoisted, pumping on the toes. Down on f0 (arms
## bend, squash), up and stretched on f5, overshoot f7, settle f10; then a
## smaller second pump. The chin is up, the head bobs a frame late.
static func cheer(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("cheer", 24, true, st)
	var up := _raised(st)
	var down := BWAnimCarry.shifted(up, Vector3(0, -0.2, 0.04), Vector3(0.35, 0, 0))
	for k in [[0, down, "f"], [5, up, "a"], [7, BWAnimCarry.shifted(up, Vector3(0, 0.03, 0), Vector3(-0.08, 0, 0)), "f"],
			[12, BWAnimCarry.shifted(up, Vector3(0, -0.12, 0.02), Vector3(0.2, 0, 0)), "f"], [16, up, "a"], [19, up, "f"]]:
		c.pose(float(k[0]), k[1], str(k[2]))
	for ch in up:
		if str(ch).ends_with("_pole") or str(ch).ends_with("_grip") or str(ch).ends_with("_edge") or ch == "flat":
			c.key(ch, 0, up[ch])
	c.pose(0, { "root": Vector3(0, -0.12, 0.0), "squash": -0.035, "spine": Vector3(-0.04, 0, 0), "chest": Vector3(-0.06, 0, 0) }, "f")
	c.pose(5, { "root": Vector3(0, 0.0, 0.0), "squash": 0.04, "chest": Vector3(-0.16, 0.05, 0.02), "spine": Vector3(-0.08, 0, 0) })
	c.pose(7, { "root": Vector3(0, 0.01, 0.0), "squash": 0.03 }, "f")
	c.pose(12, { "root": Vector3(0, -0.08, 0.0), "squash": -0.02, "chest": Vector3(-0.1, -0.04, -0.02) }, "f")
	c.pose(16, { "root": Vector3(0, -0.01, 0.0), "squash": 0.03 })
	c.pose(19, { "root": Vector3(0, -0.02, 0.0), "squash": 0.02, "chest": Vector3(-0.15, 0.0, 0.0) }, "f")
	c.pose(1, { "head": Vector3(0.0, 0.0, 0.0), "head_sq": 0.04 })
	c.pose(6, { "head": Vector3(-0.32, 0.05, 0.05), "head_sq": -0.03 })
	c.pose(13, { "head": Vector3(-0.15, -0.05, -0.03), "head_sq": 0.02 })
	c.pose(18, { "head": Vector3(-0.3, 0.0, 0.0), "head_sq": -0.015 })
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	for side in ["l", "r"]:
		var g := fl if side == "l" else fr
		var y := 0.25 if side == "l" else -0.25
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return BWAnimClips.ankle(g, _cheer_heel(f), y))
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return Vector3(_cheer_heel(f), y, 0))
	return c


static func _cheer_heel(f: float) -> float:
	return 0.42 * BWAnimClips._bump(fposmod(f, 24.0), 6.0, 4.5) + 0.3 * BWAnimClips._bump(fposmod(f, 24.0), 17.0, 4.0)


## CHEER_JUMP (20 f loop): crouch (f0-f2), spring up with the free fist
## punched high (both feet off f5-f11), land and squash (f13), re-gather.
static func cheer_jump(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("cheer_jump", 20, true, st)
	var b := c.base
	var up := _raised(st)
	var guard := BWAnimCarry.guard_hands(b)
	var shaft := st in ["spear", "polearm", "staff", "bow"]
	var low := BWAnimCarry.shifted(guard, Vector3(0, 0.04 if shaft else -0.06, 0.04), Vector3(0.0 if shaft else 0.2, 0, 0))
	c.pose(0, low, "f")
	c.pose(7, up, "a")
	c.pose(9, BWAnimCarry.shifted(up, Vector3(0, 0.03, 0), Vector3(-0.1, 0, 0)), "f")
	c.pose(14, low, "a")
	var fh := BWAnimCarry.free_hand(st)
	if fh != "" and not BWAnimCarry.two_handed(st):
		var sx := 1.0 if fh == "l" else -1.0
		c.key("hand_%s_pos" % fh, 1, Vector3(0.18 * sx, -0.1, 0.18), "f")
		c.key("hand_%s_pos" % fh, 7, Vector3(0.2 * sx, 0.78, 0.12))
		c.key("hand_%s_pos" % fh, 9, Vector3(0.22 * sx, 0.82, 0.1), "f")
		c.key("hand_%s_pos" % fh, 14, Vector3(0.2 * sx, 0.1, 0.2))
	c.pose(0, { "root": Vector3(0, -0.15, 0.02), "squash": -0.04, "spine": Vector3(0.12, 0, 0), "head": Vector3(0.12, 0, 0), "head_sq": 0.03 }, "f")
	c.pose(2, { "root": Vector3(0, -0.17, 0.02), "squash": -0.05 }, "f")
	c.pose(5, { "root": Vector3(0, 0.12, 0.0), "squash": 0.05, "spine": Vector3(-0.06, 0, 0), "chest": Vector3(-0.12, 0, 0),
		"head": Vector3(-0.15, 0.0, 0.0), "head_sq": -0.04, "leg_stretch": 0.04 })
	c.pose(8, { "root": Vector3(0, 0.22, 0.0), "squash": 0.02, "head": Vector3(-0.3, 0.05, 0.04), "head_sq": -0.01, "leg_stretch": 0.0 }, "f")
	c.pose(11, { "root": Vector3(0, 0.08, 0.0), "squash": 0.03 })
	c.pose(13, { "root": Vector3(0, -0.16, 0.02), "squash": -0.055, "head_sq": 0.05, "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.04, 0, 0),
		"head": Vector3(0.1, 0, 0) })
	c.pose(16, { "root": Vector3(0, -0.11, 0.02), "squash": -0.02, "head_sq": 0.0 })
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	for side in ["l", "r"]:
		var g := fl if side == "l" else fr
		var y := 0.22 if side == "l" else -0.22
		var lag := 0.0 if side == "l" else 0.5
		c.pose(0, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % side: Vector3(0, y, 0) }, "f")
		c.pose(3.5 + lag, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0.55, y), "foot_%s_rot" % side: Vector3(0.55, y, 0) })
		c.pose(7 + lag, { "foot_%s_pos" % side: BWAnimClips.ankle(g + Vector2(0, -0.04), 0.5, y, 0.2), "foot_%s_rot" % side: Vector3(0.5, y, 0),
			"foot_%s_pole" % side: Vector3(0, 0, 1) })
		c.pose(10.5 + lag * 0.5, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0.3, y, 0.06), "foot_%s_rot" % side: Vector3(0.3, y, 0) })
		c.pose(12.5, { "foot_%s_pos" % side: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % side: Vector3(0, y, 0) }, "f")
	return c


## The weapon at rest on the shoulder (or the style's equivalent) for cheer_cool.
static func _rested(st: String) -> Dictionary:
	match st:
		"heavy":
			var sh := BWAnimCarry.loco("heavy", "walk_heavy")
			var d: Dictionary = sh.a.duplicate()
			d.merge(sh.k, true)
			return d
		"polearm", "staff":
			var sl := BWAnimCarry.loco(st, "run")
			var d2: Dictionary = sl.a.duplicate()
			d2.merge(sl.k, true)
			return d2
		"one":
			return { "hand_r_pos": Vector3(-0.2, 0.02, 0.18), "hand_r_aim": Vector3(-0.3, 0.55, -0.78).normalized(),
				"hand_r_edge": Vector3(0, 0.8, 0.6), "hand_r_pole": Vector3(-1, -0.6, -0.2), "flat": 0.5 }
		"spear":
			return { "hand_r_pos": Vector3(-0.2, 0.04, 0.18), "hand_r_aim": Vector3(-0.25, 0.5, -0.83).normalized(),
				"hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": Vector3(-1, -0.6, -0.2), "flat": 0.4 }
		"pair":
			# arms crossed, a dagger standing up in each fist
			return { "hand_r_pos": Vector3(0.1, -0.06, 0.2), "hand_r_aim": Vector3(-0.1, 0.95, 0.2).normalized(),
				"hand_l_pos": Vector3(-0.1, -0.03, 0.22), "hand_l_aim": Vector3(0.1, 0.95, 0.2).normalized(),
				"hand_r_pole": Vector3(-0.5, -1, -0.2), "hand_l_pole": Vector3(0.5, -1, -0.2), "flat": 0.9 }
		"bow":
			# the bow slung over the shoulder, hooked by the left arm
			return { "hand_l_pos": Vector3(0.2, 0.12, 0.12), "hand_l_aim": Vector3(-0.35, -0.6, -0.72).normalized(),
				"hand_l_edge": Vector3(0, 0.6, -0.6), "hand_l_pole": Vector3(1, -0.6, -0.2), "hand_r_grip": 0.0, "flat": 0.6 }
		"fists":
			# both fists on the hips
			var r := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.3, -0.5, -0.8), Vector3(-1, 0, 0), Vector3.ZERO)
			var l := BWCharacterPose._fist("l", Vector3.ZERO, Vector3(-0.3, -0.5, -0.8), Vector3(1, 0, 0), Vector3.ZERO)
			return { "hand_r_pos": Vector3(-0.24, -0.33, -0.02), "hand_r_aim": r.aim, "hand_r_edge": r.edge, "hand_r_pole": Vector3(-1, 0.2, 0.2),
				"hand_l_pos": Vector3(0.24, -0.33, -0.02), "hand_l_aim": l.aim, "hand_l_edge": l.edge, "hand_l_pole": Vector3(1, 0.2, 0.2), "flat": 0.0 }
		"pistol":
			# muzzle up by her cheek
			return { "hand_r_pos": Vector3(-0.17, 0.26, 0.17), "hand_r_aim": Vector3(0.05, 0.1, -1).normalized(),
				"hand_r_edge": Vector3(0, 1, 0.1), "hand_r_pole": Vector3(-1, -0.6, -0.3), "flat": 0.3 }
	return {}


## CHEER_COOL (48 f loop): the weapon on the shoulder, free hand on the
## hip, chin up; two slow nods and a weight shift. Too cool to jump.
static func cheer_cool(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("cheer_cool", 48, true, st)
	var rest := _rested(st)
	c.pose(0, rest, "f")
	c.pose(24, BWAnimCarry.shifted(rest, Vector3(0, 0.015, 0), Vector3.ZERO), "f")
	var fh := BWAnimCarry.free_hand(st)
	if fh != "" and not BWAnimCarry.two_handed(st) and st != "pair":
		var sx := 1.0 if fh == "l" else -1.0
		c.key("hand_%s_pos" % fh, 0, Vector3(0.24 * sx, -0.34, -0.02), "f")
		c.key("hand_%s_pos" % fh, 24, Vector3(0.25 * sx, -0.33, -0.02), "f")
		c.key("hand_%s_pole" % fh, 0, Vector3(1.0 * sx, 0.2, 0.2))
		c.key("hand_%s_grip" % fh, 0, 0.0)
	c.pose(0, { "root": Vector3(0.035, -0.05, 0.0), "hips": Vector3(0.0, -0.1, 0.1), "chest": Vector3(-0.08, 0.06, -0.06),
		"spine": Vector3(-0.03, 0, 0), "head": Vector3(-0.2, 0.15, 0.08), "neck": Vector3(-0.04, 0, 0) }, "f")
	c.pose(8, { "head": Vector3(-0.06, 0.12, 0.06), "head_sq": 0.02 })
	c.pose(12, { "head": Vector3(-0.22, 0.14, 0.08), "head_sq": -0.01 }, "f")
	c.pose(24, { "root": Vector3(0.03, -0.035, 0.0), "chest": Vector3(-0.1, 0.03, -0.05), "head": Vector3(-0.2, 0.05, 0.06) }, "f")
	c.pose(32, { "head": Vector3(-0.04, 0.08, 0.05), "head_sq": 0.02 })
	c.pose(36, { "head": Vector3(-0.22, 0.12, 0.08), "head_sq": -0.01 }, "f")
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22) + Vector2(-0.04, 0.04)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0.12, -0.45), "foot_r_rot": Vector3(0.12, -0.45, 0) }, "f")
	c.pose(24, { "foot_r_pos": BWAnimClips.ankle(fr, 0.2, -0.45), "foot_r_rot": Vector3(0.2, -0.45, 0) }, "f")
	return c

class_name BWAnimLoco
extends RefCounted
## Locomotion clips for every set (design/art/ANIMATION.md, "Locomotion"):
##
##   walk        one hex per 16 f cycle (0.667 s): careful / short steps (D62)
##   walk_calm   the walk with less bounce and twist (stoic, dreamy characters)
##   walk_heavy  heavy set, axes: shouldered in both fists, long stance, 20 f
##   run         one hex per 10 f cycle (0.417 s): the default move (D62)
##   run_heavy   heavy set, axes: the run with the weapon shouldered
##   run_start   standstill -> run frame 0, authored footsteps (14 f)
##   run_stop    run frame 0 (left contact) -> guard, braking step (18 f)
##   run_stop_r  the same entered on the right contact (run frame 5)
##   limp        wounded walk (HP < 35%): the right leg is hurt, 20 f
##   turn_l/_r   turn in place: `turn` channel 0..1 drives the rig's yaw
##
## Gait feet are procedural (BWAnimClips.gait_foot / plant_foot): the
## stance foot's ground point travels back at exactly the root speed, so
## the runtime foot lock has nothing to correct. Bodies are keyed on the
## contact / down / passing / up beats; arms drag the legs by a frame.

## The run's footwork (shared by run, run_heavy, run_start, run_stop).
const RUN_GAIT := { "strike": -0.12, "toe": 0.95, "lift": 0.24, "shape": 0.6, "roll_in": 0.2, "peel": 0.45,
	"ahead": 0.0, "tuck": 0.02 }
const RUN_BETA := 0.36
const RUN_X := 0.08
const RUN_YAW := 0.06


static func clips(st: String) -> Array:
	var run := run_clip(st, false)
	var out: Array = [walk(st), walk_calm(st), run, run_start(st, run), run_stop(st, run, 1.0), run_stop(st, run, -1.0),
		limp(st), turn(st, 1.0), turn(st, -1.0)]
	if st == "heavy":
		out.append(walk_heavy())
		out.append(run_clip(st, true))
	return out


# ------------------------------------------------------------------ helpers

## Key a carry (BWAnimCarry.loco) on a cycle of T frames: extremes one
## frame after each contact (drag), aims a frame later still (the weapon
## lags the fist), passing positions dipped (pendulum arcs).
static func _carry(c: BWAnimClips.Clip, T: float, carry: Dictionary, dip: float, drag: float = 1.0) -> void:
	for half in [0, 1]:
		var f: float = half * T * 0.5 + drag
		var ex: Dictionary = carry.a if half == 0 else carry.b
		var other: Dictionary = carry.b if half == 0 else carry.a
		for ch in ex:
			var v: Variant = ex[ch]
			if str(ch).ends_with("_aim"):
				c.key(ch, f + 1.0, v, "f")
			else:
				c.key(ch, f, v, "f")
				if other.has(ch):
					# passing: halfway, lower (the arm swings on an arc)
					var mid: Vector3 = ((v as Vector3) + (other[ch] as Vector3)) * 0.5 + Vector3(0, -dip, 0)
					c.key(ch, f + T * 0.25, mid)
	for ch in carry.k:
		c.key(ch, 0, carry.k[ch])


## Feet of a periodic gait (both sides).
static func _feet(c: BWAnimClips.Clip, T: float, D: float, beta: float, x: float, yaw: float, g: Dictionary,
		beta_r: float = -1.0, off_r: float = 0.5, g_r: Dictionary = {}) -> void:
	for side in ["l", "r"]:
		var off := 0.0 if side == "l" else off_r
		var bx := x if side == "l" else -x
		var by := yaw if side == "l" else -yaw
		var bb := beta if side == "l" or beta_r < 0.0 else beta_r
		var gg: Dictionary = g if side == "l" or g_r.is_empty() else g_r
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return BWAnimClips.gait_foot(fposmod(f / T - off, 1.0), bx, by, D, bb, gg)[0])
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return BWAnimClips.gait_foot(fposmod(f / T - off, 1.0), bx, by, D, bb, gg)[1])


## The style bar walk's body beats, scaled: b = bounce, w = twist, on a
## cycle of T frames (contact, down, passing, up per step).
static func _walk_body(c: BWAnimClips.Clip, T: float, b: float, w: float, lean: float, head_up: float = 0.0) -> void:
	var h := T * 0.5
	var q := h / 8.0                      # the style bar's beats were on an 8 f step
	for half in [0, 1]:
		var f: float = half * h
		var s: float = 1.0 if half == 0 else -1.0
		var y := func(v: float) -> float: return -0.09 + (v + 0.09) * b
		c.pose(f + 0, { "root": Vector3(0.012 * s, y.call(-0.115), 0.03), "hips": Vector3(0.0, -0.13 * s * w, 0.03 * s * w),
			"chest": Vector3(0.03, 0.11 * s * w, -0.02 * s * w), "squash": -0.01 * b })
		c.pose(f + 2 * q, { "root": Vector3(0.026 * s, y.call(-0.150), 0.03), "hips": Vector3(0.02, -0.07 * s * w, 0.065 * s * w),
			"chest": Vector3(0.07, 0.06 * s * w, -0.05 * s * w), "squash": -0.035 * b }, "f")
		c.pose(f + 4 * q, { "root": Vector3(0.018 * s, y.call(-0.075), 0.03), "hips": Vector3(0.0, 0.0, 0.04 * s * w),
			"chest": Vector3(0.02, 0.0, -0.03 * s * w), "squash": 0.01 * b })
		c.pose(f + 6 * q, { "root": Vector3(0.004 * s, y.call(-0.035), 0.03), "hips": Vector3(-0.01, 0.08 * s * w, 0.0),
			"chest": Vector3(-0.01, -0.07 * s * w, 0.0), "squash": 0.028 * b }, "f")
		c.pose(f + 3 * q, { "head": Vector3(0.0 - head_up, -0.05 * s * w, 0.03 * s * w), "head_sq": 0.045 * b, "neck": Vector3(0.02, 0, 0) })
		c.pose(f + 7 * q, { "head": Vector3(-0.1 * b - head_up, 0.02 * s * w, -0.01 * s * w), "head_sq": -0.025 * b, "neck": Vector3(-0.04, 0, 0) })
	c.key("spine", 0, Vector3(lean, 0, 0))


# --------------------------------------------------------------------- walk

## WALK: the style bar's bouncy, cocky stride for every style. The heavy set
## keeps the approved clip exactly; the others carry their own weapon.
static func walk(st: String) -> BWAnimClips.Clip:
	if st == "heavy":
		return BWAnimClips._walk()
	var T := float(BWAnimClips.WALK_FRAMES)
	var c := BWAnimClips.new_clip("walk", int(T), true, st)
	var D := BWAnimClips.HEX_STEP
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": 0.5, "gait": "walk" }
	_feet(c, T, D, 0.5, 0.085, 0.10, {})
	_walk_body(c, T, 1.0, 1.0, 0.14)
	_carry(c, T, BWAnimCarry.loco(st, "walk"), 0.08)
	return c


## WALK_CALM: same stride and speed, half the bounce, less twist, upright,
## chin level. Stoic and dreamy characters walk like this.
static func walk_calm(st: String) -> BWAnimClips.Clip:
	var T := float(BWAnimClips.WALK_FRAMES)
	var c := BWAnimClips.new_clip("walk_calm", int(T), true, st)
	var D := BWAnimClips.HEX_STEP
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": 0.52, "gait": "walk" }
	_feet(c, T, D, 0.52, 0.09, 0.12, { "strike": -0.22, "toe": 0.6, "lift": 0.11, "match_v": true })
	_walk_body(c, T, 0.5, 0.7, 0.07, 0.03)
	var carry := BWAnimCarry.loco(st, "walk")
	if st == "heavy":
		# calmer, and the long blade (or an axe head) rides a little higher
		for ex in [carry.a, carry.b]:
			ex["hand_r_aim"] = (Basis.from_euler(Vector3(0.16, 0, 0)) * (ex.hand_r_aim as Vector3)).normalized()
	_carry(c, T, carry, 0.05, 1.5)
	return c


## WALK_HEAVY (heavy set, axes): the weapon shouldered in both fists. A
## longer stance (0.58), a lower, heavier bounce, the hips roll over each
## planted leg and the upper body lags the hips by two frames.
static func walk_heavy() -> BWAnimClips.Clip:
	var T := 20.0
	var c := BWAnimClips.new_clip("walk_heavy", int(T), true, "heavy")
	var D := BWAnimClips.HEX_STEP
	var beta := 0.58
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": beta, "gait": "walk" }
	_feet(c, T, D, beta, 0.1, 0.16, { "strike": -0.24, "toe": 0.6, "lift": 0.12, "roll_in": 0.2, "match_v": true })
	for half in [0, 1]:
		var f: float = half * T * 0.5
		var s: float = 1.0 if half == 0 else -1.0
		c.pose(f + 0, { "root": Vector3(0.02 * s, -0.12, 0.03), "hips": Vector3(0.03, -0.1 * s, 0.05 * s), "squash": -0.01 })
		c.pose(f + 3, { "root": Vector3(0.045 * s, -0.17, 0.03), "hips": Vector3(0.05, -0.04 * s, 0.1 * s), "squash": -0.04 }, "f")
		c.pose(f + 6, { "root": Vector3(0.03 * s, -0.10, 0.03), "hips": Vector3(0.02, 0.03 * s, 0.07 * s), "squash": 0.005 })
		c.pose(f + 8.5, { "root": Vector3(0.01 * s, -0.085, 0.03), "hips": Vector3(0.0, 0.08 * s, 0.02 * s), "squash": 0.015 }, "f")
		# the upper body lags: chest beats two frames after the hips
		c.pose(f + 2, { "chest": Vector3(0.06, 0.06 * s, -0.06 * s) })
		c.pose(f + 5, { "chest": Vector3(0.1, 0.03 * s, -0.09 * s) }, "f")
		c.pose(f + 9, { "chest": Vector3(0.05, -0.05 * s, -0.02 * s) })
		c.pose(f + 5.5, { "head": Vector3(0.05, -0.04 * s, 0.05 * s), "head_sq": 0.04 })
		c.pose(f + 9.5, { "head": Vector3(-0.05, 0.02 * s, 0.0), "head_sq": -0.015 })
	c.key("spine", 0, Vector3(0.2, 0, 0))
	var carry := BWAnimCarry.loco("heavy", "walk_heavy")
	_carry(c, T, carry, 0.0, 3.0)
	return c


# ---------------------------------------------------------------------- run

## RUN: one hex per 10 f cycle, stance 0.36 (a flight phase each step).
## Lean in, chin level; the free arm pumps with a bent elbow; the body
## sinks on the down, stretches on the push and floats in the flight.
## heavy_carry: the heavy set's axes, shouldered in both fists (run_heavy).
static func run_clip(st: String, heavy_carry: bool) -> BWAnimClips.Clip:
	var T := float(BWAnimClips.RUN_FRAMES)
	var n := "run_heavy" if heavy_carry else "run"
	var c := BWAnimClips.new_clip(n, int(T), true, st)
	var D := BWAnimClips.HEX_STEP
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": RUN_BETA, "gait": "run" }
	_feet(c, T, D, RUN_BETA, RUN_X, RUN_YAW, RUN_GAIT)
	var b := 0.75 if heavy_carry else 1.0      # bounce
	var w := 0.45 if heavy_carry or st == "pair" else 1.0      # twist (two fists on the weapon twist less)
	for half in [0, 1]:
		var f: float = half * T * 0.5
		var s: float = 1.0 if half == 0 else -1.0
		c.pose(f + 0, { "root": Vector3(0.01 * s, -0.10, 0.05), "hips": Vector3(0.02, -0.16 * s, 0.04 * s),
			"chest": Vector3(0.04, 0.2 * s * w, -0.03 * s), "squash": 0.0, "leg_stretch": 0.0 })
		c.pose(f + 1, { "root": Vector3(0.02 * s, -0.10 - 0.065 * b, 0.05), "hips": Vector3(0.05, -0.1 * s, 0.07 * s),
			"chest": Vector3(0.09, 0.14 * s * w, -0.05 * s), "squash": -0.045 * b }, "f")
		c.pose(f + 2.5, { "root": Vector3(0.01 * s, -0.08, 0.05), "hips": Vector3(0.0, 0.02 * s, 0.03 * s),
			"chest": Vector3(0.02, 0.0, -0.02 * s), "squash": 0.03 * b, "leg_stretch": 0.04 })
		c.pose(f + 3.7, { "root": Vector3(0.0, -0.10 + 0.08 * b, 0.05), "hips": Vector3(-0.01, 0.12 * s, 0.0),
			"chest": Vector3(0.0, -0.14 * s * w, 0.01 * s), "squash": 0.035 * b, "leg_stretch": 0.0 }, "f")
		# the head trails the down by a frame, then floats
		c.pose(f + 2, { "head": Vector3(-0.26, -0.06 * s * w, 0.02 * s), "head_sq": 0.04 * b, "neck": Vector3(-0.04, 0, 0) })
		c.pose(f + 4.3, { "head": Vector3(-0.34, 0.03 * s * w, 0.0), "head_sq": -0.02 * b, "neck": Vector3(-0.08, 0, 0) })
	c.key("spine", 0, Vector3(0.40 if heavy_carry else 0.37, 0, 0))
	var carry := BWAnimCarry.loco(st, "run_heavy" if heavy_carry else "run")
	_carry(c, T, carry, 0.06, 1.0)
	return c


# ------------------------------------------------------------ start / stop

## RUN_START (14 f = 0.58 s): from the guard she sinks and leans back a
## touch (f2-3), throws her weight forward (f4) and drives off the left
## foot while the right takes a short first step; the left swings through
## and lands exactly on the run's frame 0 (f14), so the run continues
## without a seam. The root accelerates from f3 (meta root_s: distance per
## authoring frame, which the move planner follows).
static func run_start(st: String, run: BWAnimClips.Clip) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("run_start", 14, false, st)
	var b := c.base
	var V := float(run.meta.speed)
	var s := func(f: float) -> float:
		return 0.0 if f <= 3.0 else V / BWAnimClips.FPS * pow(f - 3.0, 2) / 22.0
	c.meta = { "root_s": _root_samples(s, 14.0), "root_hz": BWAnimClips.BAKE_HZ }
	var D := BWAnimClips.HEX_STEP
	var c0 := D * RUN_BETA * 0.5 + float(RUN_GAIT.ahead)
	var fl0 := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr0 := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	# left: the drive foot, toe-off at f9.5, lands on the run's contact at f14
	var pl_l := [[-1.0, 9.5, fl0, 0.22], [14.0, 99.0, Vector2(RUN_X, c0 + s.call(14.0)), RUN_YAW]]
	# right: a short first step (f4 -> f8.5), then the push that puts it in the air
	# (the right plant is placed so its toe-off at f13 is where the run's
	# own swing starts; the last plant is a far dummy: it is in the air)
	var pl_r := [[-1.0, 4.0, fr0, -0.22], [8.5, 13.0, Vector2(-RUN_X, 0.477), -RUN_YAW], [99.0, 99.0, Vector2(-RUN_X, 3.0), -RUN_YAW]]
	var g := RUN_GAIT.duplicate()
	g["lift"] = 0.2
	for side in ["l", "r"]:
		var pl: Array = pl_l if side == "l" else pl_r
		var is_r: bool = side == "r"
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			var a: Vector3 = BWAnimClips.plant_foot(f, pl, s, 0.0, g)[0]
			if is_r and f > 13.0:
				a = a.lerp(_run_swing_r(f)[0], smoothstep(13.0, 14.0, f))
			return a)
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			var a: Vector3 = BWAnimClips.plant_foot(f, pl, s, 0.0, g)[1]
			if is_r and f > 13.0:
				a = a.lerp(_run_swing_r(f)[1], smoothstep(13.0, 14.0, f))
			return a)
	var chans := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq", "leg_stretch"]
	var hand_chans: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch == "flat":
			hand_chans.append(ch)
	c.at_base(0, chans + hand_chans)
	# anticipation: sink, a little lean back, the head leads forward and down
	c.pose(2, { "root": Vector3(0, -0.12, -0.02), "spine": Vector3(-0.02, 0, 0), "chest": Vector3(-0.04, 0, 0),
		"head": Vector3(0.1, 0, 0), "squash": -0.03, "head_sq": 0.02 })
	c.pose(3, { "root": Vector3(0, -0.13, -0.025), "squash": -0.035 }, "f")
	# throw the weight forward: the body falls into the run
	c.pose(5, { "root": Vector3(0.0, -0.11, 0.06), "spine": Vector3(0.3, 0, 0), "chest": Vector3(0.12, -0.15, 0.03),
		"hips": Vector3(0.06, 0.1, -0.03), "head": Vector3(-0.12, 0.05, 0), "squash": 0.02, "head_sq": -0.02 })
	c.pose(8.5, { "root": Vector3(-0.02, -0.17, 0.06), "hips": Vector3(0.05, 0.1, -0.06), "chest": Vector3(0.1, -0.16, 0.05),
		"squash": -0.04, "head_sq": 0.035 }, "f")
	c.pose(10.5, { "root": Vector3(0.0, -0.08, 0.05), "squash": 0.035, "leg_stretch": 0.04, "head_sq": -0.01 })
	# f14 = the run's first frame, every channel
	for ch in chans + hand_chans:
		c.key(ch, 14, run.value(ch, 0.0), "a")
	# the arms: the free arm swings forward with the first step, the weapon
	# arm settles into the run carry by f8
	var carry := BWAnimCarry.loco(st, "run")
	c.pose(6, carry.b, "a")
	c.pose(10, carry.a, "f")
	for ch in carry.k:
		c.key(ch, 5, carry.k[ch])
	return c


## A root curve s(f) sampled at the bake rate (meta root_s, root_hz): the
## move planner and the tests read the distance at any time from it.
static func _root_samples(s: Callable, frames: float) -> Array:
	var out: Array = []
	var n := int(round(frames / BWAnimClips.FPS * BWAnimClips.BAKE_HZ))
	for i in n + 1:
		out.append(float(s.call(i * BWAnimClips.FPS / BWAnimClips.BAKE_HZ)))
	return out


## The right foot during the last frames of the start: follow the run's own
## swing (run phase 0.5 at f14), shifted so the start's root travel is respected.
static func _run_swing_r(f: float) -> Array:
	var u := (f - 14.0) / float(BWAnimClips.RUN_FRAMES)       # run cycle phase (0 at f14)
	return BWAnimClips.gait_foot(fposmod(u - 0.5, 1.0), -RUN_X, -RUN_YAW, BWAnimClips.HEX_STEP, RUN_BETA, RUN_GAIT)


## RUN_STOP (18 f = 0.75 s), entered on the run's contact frame (side 1:
## left contact, frame 0; side -1: right contact, frame 5). The trailing foot
## swings through into a hard braking step (heel first, f3.5), the body
## sinks and leans back while the head, the hair and the weapon carry on
## forward (follow-through), the back foot steps up beside it (f7-f11) and
## she bobs up through the guard and settles. The root decelerates to a
## stop by f9 (meta root_s).
static func run_stop(st: String, run: BWAnimClips.Clip, side: float) -> BWAnimClips.Clip:
	var n := "run_stop" if side > 0.0 else "run_stop_r"
	var c := BWAnimClips.new_clip(n, 18, false, st)
	var b := c.base
	var V := float(run.meta.speed)
	var s := func(f: float) -> float:
		var ff := minf(f, 9.0)
		return V / BWAnimClips.FPS * (ff - ff * ff / 18.0)
	c.meta = { "root_s": _root_samples(s, 18.0), "root_hz": BWAnimClips.BAKE_HZ, "root_end": 9.0 / BWAnimClips.FPS }
	var D := BWAnimClips.HEX_STEP
	var c0 := D * RUN_BETA * 0.5 + float(RUN_GAIT.ahead)
	var end_s: float = s.call(9.0)
	var fl0 := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr0 := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var lead := "l" if side > 0.0 else "r"           # the foot on contact at f0
	var trail := "r" if side > 0.0 else "l"
	var gl := { "l": fl0 + Vector2(0, end_s), "r": fr0 + Vector2(0, end_s) }
	var yaw := { "l": 0.22, "r": -0.22 }
	var gx := { "l": RUN_X, "r": -RUN_X }
	# lead foot: planted on its run contact, then steps up beside the brake (f7 -> f11)
	var pl_lead := [[-1.0, 7.0, Vector2(gx[lead], c0), RUN_YAW * signf(gx[lead])], [11.0, 99.0, gl[lead], yaw[lead]]]
	# trailing foot: in the air (run phase 0.5 at f0), lands the brake at f3.5
	var pl_trail := [[-1.0, -0.5, Vector2(gx[trail], c0 - D * RUN_BETA), RUN_YAW * signf(gx[trail])], [3.5, 99.0, gl[trail], yaw[trail]]]
	var g := RUN_GAIT.duplicate()
	g["strike"] = -0.42
	g["lift"] = 0.12
	g["roll_f"] = 2.5
	var run_f0 := 0.0 if side > 0.0 else float(run.frames) * 0.5
	for ft in ["l", "r"]:
		var pl: Array = pl_lead if ft == lead else pl_trail
		var is_trail: bool = ft == trail
		c.proc("foot_%s_pos" % ft, func(f: float) -> Vector3:
			if is_trail and f < 1.0:
				return run.value("foot_%s_pos" % ft, run_f0 + f).lerp(BWAnimClips.plant_foot(f, pl, s, 0.0, g)[0], f)
			return BWAnimClips.plant_foot(f, pl, s, 0.0, g)[0])
		c.proc("foot_%s_rot" % ft, func(f: float) -> Vector3:
			if is_trail and f < 1.0:
				return run.value("foot_%s_rot" % ft, run_f0 + f).lerp(BWAnimClips.plant_foot(f, pl, s, 0.0, g)[1], f)
			return BWAnimClips.plant_foot(f, pl, s, 0.0, g)[1])
	var chans := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq", "leg_stretch"]
	var hand_chans: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch == "flat":
			hand_chans.append(ch)
	for ch in chans + hand_chans:
		c.key(ch, 0, run.value(ch, run_f0), "l" if ch in ["root", "spine"] else "a")
	c.at_base(18, chans + hand_chans)
	var sd := side
	# the brake: the hips drop and the spine comes upright and back...
	c.pose(3.5, { "root": Vector3(-0.02 * sd, -0.16, -0.03), "spine": Vector3(-0.08, 0, 0), "hips": Vector3(-0.06, 0.08 * sd, -0.04 * sd),
		"chest": Vector3(-0.06, 0.1 * sd, -0.02 * sd), "squash": -0.045 }, "f")
	# ...while the head carries on forward a beat (follow-through) and squashes
	c.pose(2.5, { "head": Vector3(-0.12, 0.0, 0.0) })
	c.pose(5, { "head": Vector3(0.18, -0.04 * sd, 0.02 * sd), "head_sq": 0.06, "neck": Vector3(0.06, 0, 0) })
	c.pose(6.5, { "root": Vector3(-0.01 * sd, -0.19, -0.02), "chest": Vector3(0.05, 0.04 * sd, 0.0), "squash": -0.05 }, "f")
	c.pose(8, { "head": Vector3(-0.06, 0.0, 0.0), "head_sq": -0.02 })
	# the back foot steps up; she bobs up through the guard (overshoot) and settles
	c.pose(11, { "root": Vector3(0, -0.07, 0.0), "squash": 0.0, "chest": Vector3(-0.01, 0, 0), "spine": Vector3(0.03, 0, 0) })
	c.pose(13, { "root": Vector3(0, -0.02, 0.0), "squash": 0.02, "head_sq": -0.015, "head": Vector3(-0.04, 0, 0) }, "f")
	c.pose(15.5, { "root": Vector3(0, -0.05, 0.0), "squash": -0.008, "head_sq": 0.01 })
	# arms: thrown forward by the brake, then back to the guard
	var guard := BWAnimCarry.guard_hands(c.base)
	# (bows and shafts reach far below the hand: they ride higher through the brake)
	var fwd := BWAnimCarry.shifted(guard, Vector3(0, 0.04 + (0.12 if st in ["bow", "spear", "polearm", "staff"] else 0.0), 0.1), Vector3(-0.25, 0, 0))
	var free := BWAnimCarry.free_hand(st)
	if free != "":
		fwd["hand_%s_pos" % free] = Vector3(0.18 * (1.0 if free == "l" else -1.0), -0.04, 0.32)
	# the weapon carries on forward with the brake (follow-through), swinging
	# round over five frames rather than snapping to the guard
	c.pose(7, fwd)
	c.pose(11, BWAnimCarry.shifted(guard, Vector3(0, -0.03, 0.02), Vector3(0.06, 0, 0)))
	for ch in ["hand_l_grip", "hand_r_grip"]:
		c.key(ch, 4, run.value(ch, run_f0))
	return c


# ---------------------------------------------------------------------- limp

## LIMP (20 f, one hex): the right leg is hurt. The good left leg holds
## most of the cycle (stance 0.62), the hurt right one is set down briefly
## (0.38) with a stiff knee and no push; the body drops onto the good leg
## and lurches over the hurt one, the free hand presses the hurt side and
## the weapon drags low.
static func limp(st: String) -> BWAnimClips.Clip:
	var T := 20.0
	var c := BWAnimClips.new_clip("limp", int(T), true, st)
	var D := BWAnimClips.HEX_STEP
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": 0.62, "gait": "walk" }
	_feet(c, T, D, 0.62, 0.095, 0.14, { "strike": -0.2, "toe": 0.55, "lift": 0.1, "match_v": true }, 0.38, 0.56,
		{ "strike": -0.32, "toe": 0.35, "lift": 0.085, "roll_in": 0.14, "peel": 0.7, "shape": 1.1, "match_v": true })
	# left (good) contact f0; right (hurt) contact f11.2 (0.56 of the cycle)
	c.pose(0, { "root": Vector3(0.02, -0.17, 0.02), "hips": Vector3(0.06, -0.08, 0.06), "chest": Vector3(0.12, 0.06, 0.06),
		"squash": -0.03 }, "f")
	c.pose(5, { "root": Vector3(0.05, -0.12, 0.02), "hips": Vector3(0.05, 0.0, 0.1), "chest": Vector3(0.1, 0.02, 0.1), "squash": 0.0 })
	c.pose(9, { "root": Vector3(0.04, -0.10, 0.02), "hips": Vector3(0.04, 0.06, 0.06), "chest": Vector3(0.1, -0.03, 0.08), "squash": 0.01 }, "f")
	# onto the hurt leg: a quick, shallow lurch, the shoulder dips to the good side
	c.pose(12.5, { "root": Vector3(-0.03, -0.14, 0.02), "hips": Vector3(0.03, 0.06, -0.09), "chest": Vector3(0.14, -0.05, 0.12),
		"squash": -0.02 })
	c.pose(15.5, { "root": Vector3(-0.01, -0.12, 0.02), "hips": Vector3(0.05, -0.04, -0.02), "chest": Vector3(0.15, 0.03, 0.1) }, "f")
	# the head: down, wincing on the hurt step
	c.pose(1.5, { "head": Vector3(0.18, 0.04, 0.02), "head_sq": 0.03, "neck": Vector3(0.08, 0, 0) })
	c.pose(8, { "head": Vector3(0.1, 0.0, -0.02), "head_sq": -0.01 })
	c.pose(13.5, { "head": Vector3(0.22, -0.08, 0.08), "head_sq": 0.04 })
	c.pose(17, { "head": Vector3(0.12, 0.02, 0.0), "head_sq": 0.0 })
	c.key("spine", 0, Vector3(0.22, 0, 0.0))
	_wounded_hands(c, st, [[0.0, 0.0], [12.5, 1.0]])
	return c


## Wounded hands: the free hand presses the right side, the weapon hangs low.
## beats: [[frame, sway 0..1], ...]. Shared by limp and wounded.
static func _wounded_hands(c: BWAnimClips.Clip, st: String, beats: Array) -> void:
	# (a staff hangs low at the side like the other shafts, not upright in
	# front as the walking stick: that covered the face from the side)
	var low := BWAnimCarry.loco("polearm" if st == "staff" else st, "walk")
	var hold: Dictionary = low.b.duplicate()
	hold.merge(low.k, true)
	var free := BWAnimCarry.free_hand(st)
	var wh := BWAnimCarry.weapon_hand(st)
	for bt in beats:
		var f := float(bt[0])
		var k := float(bt[1])
		var d := hold.duplicate()
		if free == "l":
			d["hand_l_pos"] = Vector3(-0.02, -0.2 + 0.02 * k, 0.17)       # pressing the right side
			d["hand_l_pole"] = Vector3(0.6, -0.4, -0.8)
		elif free == "r":
			d["hand_r_pos"] = Vector3(0.0, -0.2 + 0.02 * k, 0.17)
			d["hand_r_pole"] = Vector3(-0.6, -0.4, -0.8)
		# the weapon hangs; it sways with the lurch
		for h in (["hand_r", "hand_l"] if wh == "both" else ["hand_" + wh]):
			if d.has(h + "_pos"):
				d[h + "_pos"] = (d[h + "_pos"] as Vector3) + Vector3(0.0, -0.04 - 0.02 * k, 0.02 * k)
		c.pose(f, d, "f")


# ---------------------------------------------------------------------- turn

## TURN (16 f), side 1 = to her left (turn_l), -1 = to her right. The head
## leads (f1-f3), the hips follow, the chest swings through; the foot on
## the turning side lifts first and is set down pointing the new way
## (f2-f5.5), the other follows (f4.5-f8). `turn` (0..1, with a 3%
## overshoot at f8) is the share of the angle done: BWCharacter turns the
## rig by it while the clip is on top, so the planted foot pivots under the
## lock and each lifted foot lands where the new facing wants it.
static func turn(st: String, side: float) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("turn_l" if side > 0.0 else "turn_r", 16, false, st)
	var b := c.base
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch == "flat":
			all.append(ch)
	c.at_base(0, all)
	c.at_base(16, all)
	c.key("turn", 0, 0.0, "f").key("turn", 2, -0.03, "f").key("turn", 4.5, 0.55).key("turn", 7, 0.97)
	c.key("turn", 8.5, 1.03, "f").key("turn", 11, 0.995).key("turn", 14, 1.0, "f")
	c.pose(1.5, { "head": Vector3(0.0, 0.42 * side, 0.03 * side), "root": Vector3(0, -0.09, 0), "squash": -0.02 })
	c.pose(3, { "head": Vector3(-0.02, 0.5 * side, 0.04 * side), "hips": Vector3(0.0, -0.05 * side, 0), "chest": Vector3(0, -0.08 * side, 0),
		"root": Vector3(0, -0.11, 0), "squash": -0.03, "head_sq": 0.02 }, "f")
	c.pose(5, { "root": Vector3(0.02 * side, -0.04, 0), "hips": Vector3(0, 0.12 * side, 0.03 * side), "chest": Vector3(0.02, 0.22 * side, 0.03 * side),
		"head": Vector3(-0.04, 0.2 * side, 0), "squash": 0.02, "head_sq": -0.02 })
	c.pose(8, { "root": Vector3(0, -0.10, 0), "hips": Vector3(0, -0.02 * side, 0), "chest": Vector3(0.03, -0.06 * side, -0.02 * side),
		"head": Vector3(0.04, -0.1 * side, -0.03 * side), "squash": -0.025, "head_sq": 0.03 }, "f")
	c.pose(11, { "root": Vector3(0, -0.03, 0), "chest": Vector3(0.0, 0.02 * side, 0), "head": Vector3(-0.02, 0.03 * side, 0), "squash": 0.01, "head_sq": -0.01 })
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var first := "l" if side > 0.0 else "r"
	for s in ["l", "r"]:
		var g := fl if s == "l" else fr
		var y := 0.22 if s == "l" else -0.22
		var t0 := 2.0 if s == first else 4.5
		var t1 := 5.5 if s == first else 8.0
		c.pose(0, { "foot_%s_pos" % s: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % s: Vector3(0, y, 0) }, "f")
		c.pose(t0 - 1.0, { "foot_%s_pos" % s: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % s: Vector3(0, y, 0) }, "f")
		c.pose(t0, { "foot_%s_pos" % s: BWAnimClips.ankle(g, 0.35, y), "foot_%s_rot" % s: Vector3(0.35, y, 0) })
		c.pose((t0 + t1) * 0.5, { "foot_%s_pos" % s: BWAnimClips.ankle(g, 0.15, y + 0.2 * side, 0.09), "foot_%s_rot" % s: Vector3(0.15, y + 0.2 * side, 0) })
		c.pose(t1, { "foot_%s_pos" % s: BWAnimClips.ankle(g, 0, y), "foot_%s_rot" % s: Vector3(0, y, 0) }, "f")
	var guard := BWAnimCarry.guard_hands(b)
	c.pose(4, BWAnimCarry.shifted(guard, Vector3(-0.03 * side, 0.02, -0.02), Vector3(0, -0.15 * side, 0)))
	c.pose(8.5, BWAnimCarry.shifted(guard, Vector3(0.02 * side, -0.02, 0.01), Vector3(0, 0.08 * side, 0)), "f")
	c.pose(13, guard)
	c.meta = { "turn": side }
	return c

class_name BWAnimEncounter
extends RefCounted
## The special encounters' own motion (D208-D214 looks; D219-D220 motion,
## design/art/ANIMATION.md "Encounters").
##
## Authored clips (baked with their sets):
##   walk_colossus    polearm: the Colossus's heavy walk. 32 f a cycle, a
##                    long stance, low lift, flat-footed; the body DROPS onto
##                    each planted foot (f2 / f18, marker "step": the camera
##                    and board shake), sinks, then hauls itself up over the
##                    leg; the chest and head lag two frames
##   stomp_colossus   polearm: the arrival stomp: weight onto the left leg,
##                    the right knee up, held, DRIVEN down ("stomp"), the
##                    whole body drops with it, the spear jolts, settle
##   strike_colossus  polearm: the line thrust (3 hexes). A long
##                    anticipation: side-on, the rear foot slides back, the
##                    spear drawn far back to the hip and held trembling on
##                    the line ("coil", held by "windup"); the lunge: the front
##                    foot strides out, the root drives forward, the spear
##                    rams down the line ("hit" f31); a held follow-through
##                    (to f46), then hauled back. No airborne hop: a giant
##                    doesn't hop (the cutscene skips its dash)
##   strike_jab / strike_axe_jab   one, polearm: the Horde's quick jab, the
##                    set's strike retimed short (anticipation 3.5 f instead
##                    of 7-9) with the wind-up made smaller (60%)
## Runtime layer (BWAnimator._encounter_layer, every set, no bake):
##   grunt   hunched (spine and chest over, chin up, knees bent), a
##           shuffling low swing on the gaits, its own walk pace (0.82-1.12)
##   blank   economy of motion: standing, the body holds the guard dead
##           still and the head turns in quick, exact snaps, ALL Blanks at
##           once (a shared clock); walking, the torso, head and hands are
##           locked level, only the legs move, no bob
##   being   hovers 16-19 cm off the floor on a slow sine, toes hanging, no
##           foot contacts; glides when it moves (no steps), leaning in;
##           the body flickers in its element (BWCharacter) and attacks
##           with a cast (BWClipRoute)

const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]


static func clips(st: String) -> Array:
	var out: Array = []
	if st == "polearm":
		out.append_array([walk_colossus(), stomp_colossus(), strike_colossus()])
	if st in ["one", "polearm"]:
		out.append(jab(BWAnimAction.strike(st), "strike_jab"))
	if st == "one":
		out.append(jab(BWAnimAction.strike_axe(st), "strike_axe_jab"))
	return out


static func _hand_chans() -> Array:
	var out: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			out.append(ch)
	return out


static func _foot(c: BWAnimClips.Clip, side: String, f: float, g: Vector2, pitch: float, yaw: float, lift: float = 0.0, mode: String = "a") -> void:
	c.pose(f, { "foot_%s_pos" % side: BWAnimClips.ankle(g, pitch, yaw, lift), "foot_%s_rot" % side: Vector3(pitch, yaw, 0) }, mode)


static func _r(c: BWAnimClips.Clip, d: Vector3) -> Vector3:
	return (c.base.root as Vector3) + d


# ------------------------------------------------------------------ colossus

## WALK_COLOSSUS (polearm, 32 f loop, 0.36 hex per cycle in model space:
## the 2.6x figure covers a hex in ~0.74 s at a step every 0.67 s).
static func walk_colossus() -> BWAnimClips.Clip:
	var T := 32.0
	var c := BWAnimClips.new_clip("walk_colossus", int(T), true, "polearm")
	var D := 1.2
	var beta := 0.62
	c.meta = { "stride": D, "speed": D / (T / BWAnimClips.FPS), "beta": beta, "gait": "walk" }
	BWAnimLoco._feet(c, T, D, beta, 0.12, 0.16, { "strike": -0.24, "toe": 0.6, "lift": 0.16, "roll_in": 0.3,
		"match_v": true })
	c.marker("step", 2.0).marker("step_r", 18.0)
	for half in [0, 1]:
		var f: float = half * T * 0.5
		var s: float = 1.0 if half == 0 else -1.0
		# contact: the foot is down; the DROP onto it over two frames, a sink,
		# then the haul up over the leg through the passing
		c.pose(f + 0, { "root": Vector3(0.03 * s, -0.07, 0.04), "hips": Vector3(0.04, -0.12 * s, 0.05 * s), "squash": 0.0 })
		c.pose(f + 2, { "root": Vector3(0.06 * s, -0.15, 0.04), "hips": Vector3(0.07, -0.08 * s, 0.11 * s), "squash": -0.055 }, "l")
		c.pose(f + 5, { "root": Vector3(0.07 * s, -0.16, 0.04), "hips": Vector3(0.06, -0.03 * s, 0.13 * s), "squash": -0.03 }, "f")
		c.pose(f + 10, { "root": Vector3(0.04 * s, -0.09, 0.04), "hips": Vector3(0.02, 0.05 * s, 0.08 * s), "squash": 0.01 })
		c.pose(f + 14, { "root": Vector3(0.01 * s, -0.04, 0.04), "hips": Vector3(0.0, 0.1 * s, 0.02 * s), "squash": 0.02 }, "f")
		# the upper body lags the drop by two frames, the head by three
		c.pose(f + 4, { "chest": Vector3(0.14, 0.06 * s, -0.08 * s), "neck": Vector3(0.04, 0, 0) })
		c.pose(f + 8, { "chest": Vector3(0.1, 0.03 * s, -0.1 * s) }, "f")
		c.pose(f + 13, { "chest": Vector3(0.05, -0.05 * s, -0.03 * s), "neck": Vector3(0.0, 0, 0) })
		c.pose(f + 5, { "head": Vector3(0.1, -0.04 * s, 0.06 * s), "head_sq": 0.05 })
		c.pose(f + 12, { "head": Vector3(-0.06, 0.03 * s, 0.0), "head_sq": -0.02 })
	c.key("spine", 0, Vector3(0.16, 0, 0))
	var carry := BWAnimCarry.loco("polearm", "walk")
	# the spear rides the drop: the fist dips a frame after each landing
	BWAnimLoco._carry(c, T, carry, 0.06, 3.0)
	return c


## STOMP_COLOSSUS (polearm, 40 f): the arrival. The weight shifts onto the
## left leg (f6), the right knee comes up high (f12) and holds a beat
## (f15), then is driven down: the foot lands flat on f17 ("stomp"), the
## whole body drops after it (f19, a deep squash, the head nods), the
## spear jolts, a slow rise back to the guard.
static func stomp_colossus() -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("stomp_colossus", 40, false, "polearm")
	c.marker("stomp", 17).marker("recovered", 36).marker("pose", 12)
	c.meta = { "kind": "stomp" }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(40, BODY + _hand_chans())
	c.pose(6, { "root": _r(c, Vector3(0.08, -0.06, 0.0)), "hips": Vector3(0.0, 0.0, -0.1), "chest": Vector3(0.04, 0, 0.06),
		"head": Vector3(0.02, 0, 0.04) })
	c.pose(12, { "root": _r(c, Vector3(0.1, 0.02, 0.0)), "hips": Vector3(-0.06, 0.06, -0.12), "spine": Vector3(-0.06, 0, 0),
		"chest": Vector3(-0.08, 0.04, 0.08), "head": Vector3(-0.1, 0, 0.04), "squash": 0.03 })
	c.pose(15, { "root": _r(c, Vector3(0.1, 0.03, 0.0)), "chest": Vector3(-0.1, 0.04, 0.08), "head": Vector3(-0.12, 0, 0.04), "squash": 0.035 }, "f")
	c.pose(17, { "root": _r(c, Vector3(0.04, -0.14, 0.02)), "hips": Vector3(0.06, 0.0, -0.02), "spine": Vector3(0.08, 0, 0),
		"chest": Vector3(0.12, 0.0, 0.0), "head": Vector3(0.02, 0, 0.0), "squash": -0.04 }, "l")
	c.pose(19, { "root": _r(c, Vector3(0.02, -0.24, 0.02)), "chest": Vector3(0.2, 0, 0), "head": Vector3(0.18, 0, 0),
		"squash": -0.07, "head_sq": 0.06 }, "l")
	c.pose(22, { "root": _r(c, Vector3(0.02, -0.2, 0.02)), "chest": Vector3(0.14, 0, 0), "head": Vector3(0.06, 0, 0), "squash": -0.03, "head_sq": 0.0 }, "f")
	c.pose(30, { "root": _r(c, Vector3(0.0, -0.06, 0.0)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3(0.02, 0, 0),
		"head": Vector3(-0.04, 0, 0), "squash": 0.01, "head_sq": 0.0 })
	var a := BWAnimStricken.Arms.new(c)
	a.weapon(12, Vector3(0.0, 0.05, 0.0), Vector3(-0.06, 0, 0))
	a.weapon(15, Vector3(0.0, 0.06, 0.0), Vector3(-0.07, 0, 0), "f")
	a.weapon(19, Vector3(0.0, -0.06, 0.02), Vector3(0.1, 0, 0), "l")
	a.weapon(22, Vector3(0.0, -0.03, 0.01), Vector3(0.04, 0, 0))
	a.weapon(30, Vector3.ZERO, Vector3.ZERO)
	var g := [BWAnimClips.ground_of(c.base.foot_l_pos, 0.22), BWAnimClips.ground_of(c.base.foot_r_pos, -0.22)]
	var down: Vector2 = g[1] + Vector2(-0.04, 0.2)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 40, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 5, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 8, g[1], 0.45, -0.22)
	c.pose(12, { "foot_r_pos": Vector3(g[1].x + 0.02, 0.44, 0.3), "foot_r_rot": Vector3(-0.25, -0.22, 0) })
	c.pose(15, { "foot_r_pos": Vector3(g[1].x + 0.02, 0.46, 0.28), "foot_r_rot": Vector3(-0.28, -0.22, 0) }, "f")
	_foot(c, "r", 16.4, down, -0.05, -0.22, 0.04, "l")
	_foot(c, "r", 17, down, 0, -0.22, 0, "f")
	_foot(c, "r", 26, down, 0, -0.22, 0, "f")
	BWAnimStricken._step(c, "r", 27, 31, down, g[1], 0.04)
	_foot(c, "r", 40, g[1], 0, -0.22, 0, "f")
	return c


## STRIKE_COLOSSUS (polearm, 64 f = 2.7 s, root frame). Anticipation to
## the coil (f22): turned side-on, the right foot slides back and wide,
## sinking low, the spear drawn far back to the right hip on the target
## line, the head locked on; held with a tremble (f22-f26, the cutscene
## holds "coil" for the windup). The lunge (launch f26): the left foot
## strides a long step out (lands f30, "land"), the root drives 0.5 u
## forward, the hips and chest unwind, the spear rams straight down the
## line, arm long, "hit" on f31 with a squash. Held follow-through f31-f46
## (a slow settle into the lunge), then hauled back, the front foot steps
## home (f54), recovered f60.
static func strike_colossus() -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("strike_colossus", 64, false, "polearm")
	c.marker("coil", 22).marker("launch", 26).marker("land", 30).marker("hit", 31).marker("recovered", 60).marker("pose", 33)
	c.meta = { "hand_frame": "root", "kind": "melee", "engage": 99.0 }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(64, BODY + _hand_chans())
	# body
	c.pose(4, { "head": Vector3(0.04, 0.16, 0.0) })
	c.pose(10, { "root": _r(c, Vector3(0, -0.1, -0.06)), "hips": Vector3(0.0, -0.36, 0.0), "chest": Vector3(-0.04, -0.4, 0.02),
		"head": Vector3(0.06, 0.4, 0.0), "squash": -0.02 })
	c.pose(18, { "root": _r(c, Vector3(0, -0.2, -0.14)), "hips": Vector3(0.02, -0.52, 0.0), "spine": Vector3(0.04, 0, 0),
		"chest": Vector3(-0.06, -0.62, 0.04), "head": Vector3(0.08, 0.62, 0.0), "squash": -0.035, "head_sq": 0.02 })
	c.pose(22, { "root": _r(c, Vector3(0, -0.22, -0.16)), "hips": Vector3(0.02, -0.56, 0.0), "chest": Vector3(-0.07, -0.66, 0.04),
		"head": Vector3(0.08, 0.66, 0.0), "squash": -0.04, "head_sq": 0.02 }, "f")
	for k in 4:
		var s := 1.0 if k % 2 == 0 else -1.0
		c.pose(22.0 + k + 0.5, { "chest": Vector3(-0.07, -0.66 + 0.012 * s, 0.04), "head": Vector3(0.08, 0.66 - 0.01 * s, 0.006 * s) }, "l")
	c.pose(26, { "root": _r(c, Vector3(0, -0.23, -0.16)), "chest": Vector3(-0.08, -0.68, 0.04), "squash": -0.045 }, "f")
	c.pose(28, { "root": _r(c, Vector3(0, -0.16, 0.12)), "hips": Vector3(0.06, -0.1, 0.0), "spine": Vector3(0.12, 0, 0),
		"chest": Vector3(0.1, 0.0, 0.0), "head": Vector3(-0.02, 0.06, 0.0), "squash": 0.02 })
	c.pose(30, { "root": _r(c, Vector3(0, -0.26, 0.42)), "hips": Vector3(0.1, 0.16, 0.0), "spine": Vector3(0.2, 0, 0),
		"chest": Vector3(0.2, 0.22, -0.02), "head": Vector3(-0.1, -0.14, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(31, { "root": _r(c, Vector3(0, -0.3, 0.5)), "chest": Vector3(0.24, 0.26, -0.02), "head": Vector3(-0.08, -0.18, 0.0),
		"squash": -0.06, "head_sq": 0.05 }, "l")
	c.pose(34, { "root": _r(c, Vector3(0, -0.32, 0.5)), "chest": Vector3(0.24, 0.28, -0.02), "squash": -0.03, "head_sq": 0.02 }, "f")
	c.pose(46, { "root": _r(c, Vector3(0, -0.33, 0.48)), "chest": Vector3(0.22, 0.26, -0.02), "head": Vector3(-0.1, -0.16, 0.0),
		"squash": -0.035, "head_sq": 0.0 }, "f")
	c.pose(52, { "root": _r(c, Vector3(0, -0.18, 0.2)), "hips": Vector3(0.04, 0.04, 0.0), "spine": Vector3(0.06, 0, 0),
		"chest": Vector3(0.04, 0.04, 0.0), "head": Vector3(0.0, 0.0, 0.0), "squash": 0.0 })
	c.pose(57, { "root": _r(c, Vector3(0, -0.05, 0.0)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3(-0.02, 0, 0) })
	# the spear (root frame: +z the target line): both fists on the shaft
	var g := { "hand_l_grip": 1.0 }
	var hk := {
		6: [Vector3(-0.24, 0.0, 0.02), Vector3(-0.05, 0.55, 0.83)],
		12: [Vector3(-0.28, -0.02, -0.24), Vector3(0.0, 0.16, 0.99)],
		18: [Vector3(-0.3, -0.02, -0.44), Vector3(0.02, 0.1, 0.99)],
		22: [Vector3(-0.3, -0.02, -0.48), Vector3(0.02, 0.09, 1.0)],
		26: [Vector3(-0.3, -0.01, -0.5), Vector3(0.02, 0.08, 1.0)],
		28: [Vector3(-0.22, 0.03, -0.12), Vector3(0.01, 0.06, 1.0)],
		30: [Vector3(-0.12, 0.08, 0.34), Vector3(0.0, 0.04, 1.0)],
		31: [Vector3(-0.1, 0.09, 0.44), Vector3(0.0, 0.03, 1.0)],
		34: [Vector3(-0.1, 0.09, 0.43), Vector3(0.0, 0.03, 1.0)],
		46: [Vector3(-0.1, 0.07, 0.41), Vector3(0.02, 0.0, 1.0)],
		52: [Vector3(-0.18, 0.04, 0.12), Vector3(0.0, 0.3, 0.95)],
		57: [Vector3(-0.26, -0.04, 0.06), Vector3(-0.05, 0.7, 0.7)],
	}
	for f in hk:
		var m := "f" if f in [22, 26, 34, 46] else ("l" if f in [28, 30] else "a")
		c.key("hand_r_pos", float(f), hk[f][0], m).key("hand_r_aim", float(f), (hk[f][1] as Vector3).normalized(), m)
		c.key("hand_l_grip", float(f), 1.0)
	c.key("hand_r_edge", 12, Vector3(0, 1, 0)).key("hand_r_edge", 46, Vector3(0, 1, 0)).key("hand_r_edge", 58, c.base.hand_r_edge)
	c.key("hand_r_pole", 12, Vector3(-1, -0.6, -0.4)).key("hand_l_pole", 12, Vector3(0.6, -1, 0.0))
	c.key("hand_r_pole", 56, c.base.hand_r_pole).key("hand_l_pole", 56, c.base.hand_l_pole)
	c.key("smear", 27, 0.0).key("smear", 29, 0.9).key("smear", 31, 1.0).key("smear", 34, 0.0)
	c.key("arm_stretch", 28, 0.0).key("arm_stretch", 31, 0.1).key("arm_stretch", 46, 0.08).key("arm_stretch", 52, 0.0)
	c.key("flat", 12, 0.2).key("flat", 52, 0.2)
	# feet: the right slides back and wide; the left strides out; home
	var gl := BWAnimClips.ground_of(c.base.foot_l_pos, 0.22)
	var gr := BWAnimClips.ground_of(c.base.foot_r_pos, -0.22)
	var gr1: Vector2 = gr + Vector2(-0.08, -0.3)
	var gl1: Vector2 = gl + Vector2(0.02, 0.62)
	_foot(c, "l", 0, gl, 0, 0.22, 0, "f")
	_foot(c, "r", 0, gr, 0, -0.22, 0, "f")
	BWAnimStricken._step(c, "r", 8, 15, gr, gr1, 0.04)
	_foot(c, "r", 15, gr1, 0, -0.5, 0, "f")
	_foot(c, "l", 15, gl, 0, 0.0, 0, "f")
	_foot(c, "l", 25, gl, 0, 0.0, 0, "f")
	_foot(c, "l", 26.5, gl, 0.4, 0.0)
	_foot(c, "l", 28.4, gl.lerp(gl1, 0.6), 0.0, 0.05, 0.09)
	_foot(c, "l", 29.6, gl1, -0.2, 0.08, 0.0, "l")
	_foot(c, "l", 30, gl1, 0, 0.08, 0, "f")
	_foot(c, "r", 27, gr1, 0.35, -0.5)
	_foot(c, "r", 31, gr1, 0.5, -0.45, 0, "f")
	_foot(c, "r", 47, gr1, 0.5, -0.45, 0, "f")
	_foot(c, "r", 50, gr1, 0, -0.45, 0, "f")
	_foot(c, "l", 47, gl1, 0, 0.08, 0, "f")
	BWAnimStricken._step(c, "l", 49, 55, gl1, gl, 0.06)
	BWAnimStricken._step(c, "r", 54, 59, gr1, gr, 0.04)
	_foot(c, "l", 64, gl, 0, 0.22, 0, "f")
	_foot(c, "r", 64, gr, 0, -0.22, 0, "f")
	return c


# ---------------------------------------------------------------------- jab

## A melee strike retimed short and small: the Horde's jab. The beats map
## coil 3.5 / launch 4.5 / land 6 / hit 6.5 on a 22-frame clip (the class
## strike's 7-9 / 36-42), and every channel but the feet moves 60% as far
## from the guard before the hit (a short wind-up), full on the hit.
static func jab(src: BWAnimClips.Clip, name: String) -> BWAnimClips.Clip:
	var mk: Dictionary = src.markers
	var ends := float(src.frames)
	var from := [0.0, float(mk.coil), float(mk.launch), float(mk.land), float(mk.hit), float(mk.hop_start), float(mk.hop_end), float(mk.recovered), ends]
	var to := [0.0, 3.5, 4.5, 6.0, 6.5, 12.0, 14.5, 19.0, 22.0]
	var warp := func(f: float) -> float:
		for i in range(1, from.size()):
			if f <= float(from[i]) or i == from.size() - 1:
				var u := (f - float(from[i - 1])) / maxf(float(from[i]) - float(from[i - 1]), 1e-4)
				return lerpf(float(to[i - 1]), float(to[i]), clampf(u, 0.0, 1.0))
		return f
	var c := BWAnimClips.new_clip(name, 22, false, src.style)
	var hit := float(mk.hit)
	for ch in src.keys:
		var feet := str(ch).begins_with("foot_")
		for k in src.keys[ch]:
			var f := float(k[0])
			var v: Variant = k[1]
			if not feet and f < hit and (v is Vector3 or v is float):
				var amt := 0.6 if f > 0.0 else 1.0
				v = c.base[ch] + (v - c.base[ch]) * amt
			c.key(ch, warp.call(f), v, str(k[2]))
	for m in mk:
		c.markers[m] = warp.call(float(mk[m]))
	c.meta = src.meta.duplicate(true)
	c.meta["jab"] = true
	for r in src.edge_lead:
		c.edge_lead.append([warp.call(float(r[0])), warp.call(float(r[1])), float(r[2]), str(r[3]) if (r as Array).size() > 3 else "hand_r"])
	return c

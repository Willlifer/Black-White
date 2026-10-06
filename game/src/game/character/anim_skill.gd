class_name BWAnimSkill
extends RefCounted
## Skill clips from the animation fit sweep (D219-D222,
## design/art/ANIMATION-AUDIT.md). Every clip starts and ends on its set's
## guard, like every other one-shot.
##
##   brace          every set: a free self-guard (Brace, Phalanx, Set Spear,
##                  Riposte). A dip, a step out into a wide, low stance, the
##                  guard snapped up and SET (marker "set"), held on a slow
##                  breath, eased back. Lances level the shaft at the front,
##                  butt low behind (a set spear); everyone else uses the
##                  reviewed static block key.
##   leap           every set: a leap's body (Daggerleap, Vault, Dragoon
##                  Dive). Crouch, spring off both feet ("launch"), tucked in
##                  the air, a three-point landing ("land") with the free hand
##                  down, rise. The game flies the root between launch and land.
##   strike_thrust  one, heavy: a straight fencing thrust (Heart Seeker, Lunge)
##   strike_sweep   polearm, spear: a level sweep of the shaft from her right
##                  across the front (Sweep)
##   strike_throw / strike_throw_l   pair: an overhand dagger throw, the right
##                  blade (Dualthrow) or the left (Second Dagger). "release"
##                  lets the blade fly
##   strike_hook    one, heavy (axes): a sidearm cast of the axe on its line,
##                  then the haul back in two heaves (Hook)
##   strike_grapple fists: reach, seize on "hit", load, heave up and over to
##                  her left ("throw": the foe leaves her hands), slam down
##   strike_hundred fists: six blows, left-right, "hit" .. "hit6", the last
##                  one a full cross (Hundred Fists)
## Routes (pose names) live in actions(); BWClipRoute picks them per skill.

const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]


static func clips(st: String) -> Array:
	var out: Array = [brace(st), leap(st)]
	if st in ["one", "heavy"]:
		out.append(_thrust(st))
		out.append(_hook(st))
	if st == "heavy":
		out.append(BWAnimAction._strike_spin(st))   # Whirlwind Blade on a flamberge (one and pair have it, D102)
	if st in ["polearm", "spear"]:
		out.append(_sweep(st))
	if st == "pair":
		out.append(_throw(false))
		out.append(_throw(true))
	if st == "fists":
		out.append(_grapple())
		out.append(_hundred())
	return out


## Pose names the sets answer (merged into BWAnimClips.actions_for).
##   from   start the clip at this marker (the war cry is the rage's shout
##          without the blow that starts it; "land" is the leap's landing)
##   hold   hold at this marker (aim: the strike's anticipation)
static func actions(st: String, strike: String) -> Dictionary:
	var out := {
		"brace": { "clip": "brace" },
		"leap": { "clip": "leap" },
		"land": { "clip": "leap", "from": "land" },
		"war_cry": { "clip": "stricken_rage", "from": "catch" },
		"aim": { "clip": strike, "hold": "coil" },
		"tumble": { "clip": "dodge" },
	}
	var skills := {}
	if st in ["one", "heavy"]:
		skills.merge({ "thrust": "strike_thrust", "hook": "strike_hook", "cut": "strike" })
	if st == "heavy":
		skills["spin"] = "strike_spin"
	if st in ["polearm", "spear"]:
		skills["sweep"] = "strike_sweep"
	if st == "pair":
		skills.merge({ "throw": "strike_throw", "throw_l": "strike_throw_l" })
	if st == "fists":
		skills.merge({ "grapple": "strike_grapple", "hundred": "strike_hundred" })
	if st == "pistol":
		out["reload"] = { "clip": "act_check" }          # the pan / chamber check (BWAnimHandling)
	for k in skills:
		out[k] = { "clip": skills[k] }
		out["windup_" + k] = { "clip": skills[k], "hold": "coil" }
	return out


static func _hand_chans() -> Array:
	var out: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			out.append(ch)
	return out


static func _foot(c: BWAnimClips.Clip, side: String, f: float, g: Vector2, pitch: float, yaw: float, lift: float = 0.0, mode: String = "a") -> void:
	c.pose(f, { "foot_%s_pos" % side: BWAnimClips.ankle(g, pitch, yaw, lift), "foot_%s_rot" % side: Vector3(pitch, yaw, 0) }, mode)


static func _feet_base(c: BWAnimClips.Clip) -> Array:
	var b := c.base
	return [BWAnimClips.ground_of(b.foot_l_pos, 0.22), BWAnimClips.ground_of(b.foot_r_pos, -0.22)]


static func _r(c: BWAnimClips.Clip, d: Vector3) -> Vector3:
	return (c.base.root as Vector3) + d


# --------------------------------------------------------------------- brace

## The guard a brace snaps up to (chest frame): the set spear for lances,
## else the reviewed static block key.
static func _brace_hands(st: String, c: BWAnimClips.Clip) -> Dictionary:
	if st in ["polearm", "spear"]:
		var d := BWAnimCarry.guard_hands(c.base)
		# the shaft levelled at the front, head a little up, the butt low
		# behind the right hip (still clear of the floor)
		d["hand_r_pos"] = Vector3(-0.2, -0.24, 0.14)
		d["hand_r_aim"] = Vector3(0.04, 0.36, 0.93).normalized()
		d["hand_r_edge"] = Vector3(-1, 0.0, 0.0)
		d["hand_r_pole"] = Vector3(-1, -0.4, -0.5)
		if st == "spear":
			d["hand_l_pos"] = Vector3(0.18, -0.06, 0.34)       # the free hand out in front, palm down
		d["flat"] = 0.3
		return d
	return BWAnimCarry.key_hands("block", st, 0.4)


## BRACE (36 f): a dip (f3), a step out to the right and down into a wide,
## low stance, the guard snapped up on f7 ("set": a squash), a firm settle,
## the hold on a slow breath with the chin down and the eyes up, eased back
## to the guard (f30), the foot steps home.
static func brace(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("brace", 36, false, st)
	c.marker("set", 7).marker("pose", 14).marker("recovered", 32)
	c.meta = { "kind": "setup" }
	c.at_base(0, BODY + _hand_chans(), "l")
	c.at_base(36, BODY + _hand_chans())
	var bk := _brace_hands(st, c)
	c.pose(3, { "root": _r(c, Vector3(0, -0.06, 0.0)), "head": Vector3(0.1, 0, 0), "squash": -0.015 })
	c.pose(6, { "root": _r(c, Vector3(0, -0.2, -0.04)), "hips": Vector3(0.05, 0.12, 0), "spine": Vector3(0.1, 0, 0),
		"chest": Vector3(0.1, -0.1, 0.0), "head": Vector3(0.16, 0.08, 0.0), "squash": -0.02 })
	c.pose(7, { "root": _r(c, Vector3(0, -0.22, -0.04)), "squash": -0.05, "head_sq": 0.035 }, "l")
	c.pose(9, { "root": _r(c, Vector3(0, -0.18, -0.04)), "squash": 0.012, "head_sq": -0.01 })
	c.pose(11, { "root": _r(c, Vector3(0, -0.19, -0.04)), "chest": Vector3(0.09, -0.1, 0.0), "head": Vector3(0.15, 0.08, 0.0),
		"squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(18, { "root": _r(c, Vector3(0, -0.175, -0.04)), "chest": Vector3(0.06, -0.1, 0.0), "head": Vector3(0.13, 0.08, 0.0) })
	c.pose(25, { "root": _r(c, Vector3(0, -0.19, -0.04)), "chest": Vector3(0.09, -0.1, 0.0), "head": Vector3(0.15, 0.06, 0.0) }, "f")
	c.pose(30, { "root": _r(c, Vector3(0, -0.04, 0.0)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3(0.02, 0, 0) })
	# the guard snaps up with the step and is SET with the squash
	c.pose(5, BWAnimCarry.shifted(bk, Vector3(0, -0.04, -0.04)))
	c.pose(7, BWAnimCarry.shifted(bk, Vector3(0, -0.02, 0.02)), "l")
	c.pose(9, bk)
	c.pose(25, bk, "f")
	var g := _feet_base(c)
	var wide: Vector2 = g[1] + Vector2(-0.1, -0.16)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 6, g[0], 0, 0.3, 0, "f")
	_foot(c, "l", 30, g[0], 0, 0.3, 0, "f")
	_foot(c, "l", 33, g[0], 0, 0.22, 0, "f")
	BWAnimStricken._step(c, "r", 2, 6.5, g[1], wide, 0.06)
	_foot(c, "r", 28, wide, 0, -0.22, 0, "f")
	BWAnimStricken._step(c, "r", 28, 33, wide, g[1], 0.05)
	_foot(c, "l", 36, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 36, g[1], 0, -0.22, 0, "f")
	return c


# ---------------------------------------------------------------------- leap

## LEAP (40 f). Crouch and load (f3-f5, "coil"), spring on f7 ("launch":
## up on the toes, stretched, the free arm thrown up), tucked through the
## air (f9-f14), the legs reach for the floor, a three-point landing on f17
## ("land": deep squash, the free hand down on the floor, the weapon out to
## the side), held a beat with the head coming up, then rise to the guard.
## The game flies the root between launch and land (a sine arc).
static func leap(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("leap", 40, false, st)
	c.marker("coil", 5).marker("launch", 7).marker("land", 17).marker("recovered", 34).marker("pose", 18)
	c.meta = { "kind": "leap" }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(40, BODY + _hand_chans())
	c.pose(3, { "root": _r(c, Vector3(0, -0.2, -0.04)), "spine": Vector3(0.22, 0, 0), "chest": Vector3(0.14, 0, 0),
		"head": Vector3(-0.2, 0, 0), "squash": -0.045, "head_sq": 0.03 })
	c.pose(5, { "root": _r(c, Vector3(0, -0.26, -0.05)), "spine": Vector3(0.28, 0, 0), "chest": Vector3(0.16, 0, 0),
		"head": Vector3(-0.24, 0, 0), "squash": -0.06, "head_sq": 0.04 }, "f")
	c.pose(7, { "root": _r(c, Vector3(0, 0.06, 0.04)), "spine": Vector3(0.06, 0, 0), "chest": Vector3(-0.08, 0, 0),
		"head": Vector3(-0.12, 0, 0), "squash": 0.06, "head_sq": -0.04, "leg_stretch": 0.05 }, "l")
	c.pose(9, { "root": _r(c, Vector3(0, 0.16, 0.04)), "spine": Vector3(0.18, 0, 0), "chest": Vector3(0.1, 0, 0),
		"head": Vector3(-0.14, 0, 0), "squash": 0.0, "head_sq": 0.0, "leg_stretch": 0.0 })
	c.pose(13, { "root": _r(c, Vector3(0, 0.15, 0.04)), "spine": Vector3(0.2, 0, 0), "chest": Vector3(0.12, 0, 0), "head": Vector3(-0.16, 0, 0) }, "f")
	c.pose(16, { "root": _r(c, Vector3(0, 0.02, 0.04)), "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.04, 0, 0), "head": Vector3(-0.06, 0, 0),
		"squash": 0.03 })
	c.pose(17, { "root": _r(c, Vector3(0, -0.3, 0.06)), "spine": Vector3(0.32, 0, 0.0), "chest": Vector3(0.22, 0.1, 0.0),
		"head": Vector3(0.06, -0.1, 0.0), "squash": -0.07, "head_sq": 0.06 }, "l")
	c.pose(19, { "root": _r(c, Vector3(0, -0.34, 0.06)), "squash": -0.05, "head_sq": 0.03, "head": Vector3(0.14, -0.1, 0.0) }, "f")
	c.pose(24, { "root": _r(c, Vector3(0, -0.31, 0.06)), "spine": Vector3(0.28, 0, 0.0), "chest": Vector3(0.16, 0.06, 0.0),
		"head": Vector3(-0.26, 0.02, 0.0), "squash": -0.03, "head_sq": 0.0 }, "f")
	c.pose(30, { "root": _r(c, Vector3(0, -0.08, 0.02)), "spine": Vector3(0.05, 0, 0), "chest": Vector3(0.0, 0, 0),
		"head": Vector3(-0.04, 0, 0), "squash": 0.015 })
	c.pose(34, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.0 }, "f")
	# hands: the weapon drawn back low, held out of the way in the air, out
	# to the side on the landing; the free hand swings back, up, then down
	# onto the floor beside the front foot
	var a := BWAnimStricken.Arms.new(c)
	a.weapon(3, Vector3(0.04, 0.03, -0.1), Vector3(-0.2, 0, 0))
	a.weapon(5, Vector3(0.05, 0.04, -0.12), Vector3(-0.25, 0, 0), "f")
	a.weapon(8, Vector3(0.06, 0.1, 0.0), Vector3(0.2, 0, 0))
	a.weapon(14, Vector3(0.08, 0.1, 0.02), Vector3(0.25, 0, 0), "f")
	a.weapon(17, Vector3(0.2, 0.2, 0.06), Vector3(-0.15, 0.25, 0.0), "l")
	a.weapon(24, Vector3(0.2, 0.22, 0.06), Vector3(-0.15, 0.25, 0.0), "f")
	a.weapon(31, Vector3(0.02, 0.0, 0.0), Vector3.ZERO)
	a.hand(3, Vector3(0.3, -0.2, -0.22)).hand(5, Vector3(0.32, -0.22, -0.26), "f")
	a.hand(7, Vector3(0.3, 0.36, 0.26)).hand(13, Vector3(0.42, 0.16, 0.12), "f")
	a.hand(17, Vector3(0.3, -0.5, 0.4), "l").hand(24, Vector3(0.3, -0.52, 0.42), "f")
	a.free_home(31)
	a.let_go(4, 31)
	a.pole(7, Vector3(0.6, -0.4, -0.6)).pole(17, Vector3(0.6, -0.2, -0.8)).pole(30, Vector3(0.6, -0.6, -0.5))
	var g := _feet_base(c)
	var fl1: Vector2 = g[0] + Vector2(0.04, 0.24)
	var fr1: Vector2 = g[1] + Vector2(-0.04, -0.3)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 5, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 5, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 6.5, g[0], 0.55, 0.22)
	_foot(c, "r", 6.5, g[1], 0.6, -0.22)
	# tucked in the air (model space: the game lifts the whole figure)
	c.pose(9, { "foot_l_pos": Vector3(0.12, 0.5, 0.16), "foot_l_rot": Vector3(0.3, 0.2, 0),
		"foot_r_pos": Vector3(-0.12, 0.44, -0.08), "foot_r_rot": Vector3(0.6, -0.2, 0) })
	c.pose(13, { "foot_l_pos": Vector3(0.12, 0.52, 0.16), "foot_l_rot": Vector3(0.25, 0.2, 0),
		"foot_r_pos": Vector3(-0.12, 0.46, -0.1), "foot_r_rot": Vector3(0.6, -0.2, 0) }, "f")
	_foot(c, "l", 16, fl1, -0.25, 0.18, 0.1)
	_foot(c, "r", 16, fr1, 0.5, -0.3, 0.1)
	_foot(c, "l", 17, fl1, 0, 0.18, 0, "f")
	_foot(c, "r", 17, fr1, 0.62, -0.32, 0, "f")
	_foot(c, "l", 26, fl1, 0, 0.18, 0, "f")
	_foot(c, "r", 26, fr1, 0.62, -0.32, 0, "f")
	BWAnimStricken._step(c, "r", 27, 31, fr1, g[1], 0.06)
	BWAnimStricken._step(c, "l", 31, 35, fl1, g[0], 0.05)
	_foot(c, "l", 40, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 40, g[1], 0, -0.22, 0, "f")
	return c


# -------------------------------------------------------------------- thrust

## THRUST (one, heavy): the point drawn back to the right hip on the line
## (free hand pointing at the target), driven straight down the line on the
## dash, the arm long on the hit, a short twist, pulled back to the guard.
static func _thrust(st: String) -> BWAnimClips.Clip:
	var heavy := st == "heavy"
	var beats := [0, 4, 9, 11, 13, 14, 18, 22, 27, 30, 35, 40] if heavy else [0, 3, 8, 10, 12, 13, 16, 20, 25, 28, 33, 37]
	var L := "hand_l_pos"
	var A := BWAnimAction
	var hands := {
		4.0: A._h(Vector3(-0.26, 0.0, 0.04), Vector3(0.0, 0.55, 0.84)),
		6.0: A._h(Vector3(-0.28, 0.02, -0.14), Vector3(0.03, 0.18, 0.98)),
		8.0: A._h(Vector3(-0.3, 0.04, -0.22), Vector3(0.04, 0.12, 0.99), { "hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": Vector3(-1, -0.5, -0.3),
			"flat": 0.2, "_mode": "f" }),
		10.0: A._h(Vector3(-0.27, 0.07, -0.14), Vector3(0.03, 0.1, 0.99)),
		12.0: A._h(Vector3(-0.17, 0.12, 0.22), Vector3(0.0, 0.06, 1.0), { "smear": 0.8, "_mode": "l" }),
		13.0: A._h(Vector3(-0.1, 0.15, 0.5), Vector3(0.0, 0.04, 1.0), { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" }),
		14.0: A._h(Vector3(-0.08, 0.16, 0.6), Vector3(0.0, 0.03, 1.0), { "arm_stretch": 0.1 }),
		16.0: A._h(Vector3(-0.08, 0.16, 0.59), Vector3(0.0, 0.03, 1.0), { "smear": 0.0, "arm_stretch": 0.08 }),
		18.0: A._h(Vector3(-0.1, 0.13, 0.54), Vector3(0.05, -0.02, 1.0), { "arm_stretch": 0.03, "_mode": "f" }),
		22.0: A._h(Vector3(-0.16, 0.07, 0.36), Vector3(0.0, 0.1, 1.0), { "arm_stretch": 0.0 }),
		25.0: A._h(Vector3(-0.22, 0.0, 0.22), Vector3(-0.2, 0.6, 0.77)),
	}
	if heavy:
		for f in hands:
			hands[f]["hand_l_grip"] = 1.0
	else:
		hands[6.0][L] = Vector3(0.22, 0.14, 0.34)
		hands[8.0][L] = Vector3(0.24, 0.2, 0.42)
		hands[12.0][L] = Vector3(0.3, 0.1, 0.14)
		hands[14.0][L] = Vector3(0.36, 0.0, -0.24)
		hands[18.0][L] = Vector3(0.36, 0.02, -0.26)
		hands[25.0][L] = Vector3(0.28, -0.12, 0.04)
	var c := A._melee("strike_thrust", st, beats, 0.35, hands, 1.35 if heavy else 1.25)
	# a thrust stays on the line: the edge turns a quarter on the hit
	c.key("hand_r_edge", A._warp(14.0, beats), Vector3(0, 1, 0)).key("hand_r_edge", A._warp(18.0, beats), Vector3(-0.7, 0.7, 0))
	c.key("hand_r_edge", A._warp(25.0, beats), Vector3(0, 0.3, 1))
	return c


# --------------------------------------------------------------------- sweep

## SWEEP (polearm, spear): the shaft swung level from back-right, across
## the front (the hit), through to her left, at hip height; the hips and
## chest turn with it (a full cut's twist); hop home, back to the guard.
static func _sweep(st: String) -> BWAnimClips.Clip:
	var two := st == "polearm"
	var beats := [0, 4, 9, 11, 14, 15, 20, 24, 29, 32, 38, 43]
	var A := BWAnimAction
	var L := "hand_l_pos"
	var hands := {
		4.0: A._h(Vector3(-0.28, 0.0, 0.02), Vector3(-0.5, 0.4, 0.3)),
		6.0: A._h(Vector3(-0.32, -0.02, -0.08), Vector3(-0.85, 0.16, -0.3)),
		8.0: A._h(Vector3(-0.34, -0.02, -0.14), Vector3(-0.8, 0.14, -0.55), { "hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": Vector3(-1, -0.5, -0.3),
			"flat": 0.3, "_mode": "f" }),
		10.0: A._h(Vector3(-0.32, 0.0, -0.04), Vector3(-0.95, 0.12, -0.1)),
		12.0: A._h(Vector3(-0.22, 0.03, 0.22), Vector3(-0.6, 0.1, 0.78), { "smear": 1.0, "_mode": "l" }),
		13.0: A._h(Vector3(-0.1, 0.04, 0.34), Vector3(-0.2, 0.08, 0.98), { "smear": 1.0, "arm_stretch": 0.06, "_mode": "l" }),
		14.0: A._h(Vector3(0.02, 0.04, 0.38), Vector3(0.2, 0.06, 0.98), { "smear": 1.0, "arm_stretch": 0.07 }),
		16.0: A._h(Vector3(0.12, 0.02, 0.32), Vector3(0.7, 0.05, 0.7), { "smear": 0.4 }),
		18.0: A._h(Vector3(0.16, 0.0, 0.26), Vector3(0.9, 0.06, 0.42), { "smear": 0.0, "arm_stretch": 0.0, "_mode": "f" }),
		22.0: A._h(Vector3(0.12, 0.0, 0.26), Vector3(0.8, 0.15, 0.55)),
		25.0: A._h(Vector3(-0.08, 0.0, 0.22), Vector3(0.0, 0.5, 0.86)),
		27.0: A._h(Vector3(-0.24, -0.04, 0.1), Vector3(-0.1, 0.8, 0.55), { "flat": 0.6 }),
	}
	if two:
		for f in hands:
			hands[f]["hand_l_grip"] = 1.0
	else:
		hands[8.0][L] = Vector3(0.3, 0.12, 0.3)
		hands[13.0][L] = Vector3(0.34, 0.06, 0.06)
		hands[16.0][L] = Vector3(0.36, 0.02, -0.22)
		hands[22.0][L] = Vector3(0.34, 0.0, -0.2)
		hands[27.0][L] = Vector3(0.28, -0.12, 0.04)
	var c := A._melee("strike_sweep", st, beats, 1.0, hands, 1.5)
	c.lead(A._warp(10.5, beats), A._warp(18.0, beats), 0.85)
	return c


# --------------------------------------------------------------------- throw

## THROW (pair, 30 f, root frame): the blade drawn back high by the ear,
## the other one pointing at the target (coil 7); the arm whips over on
## the release (f10), wrist flicked, the body unwinds and the front foot
## steps; the arm follows through across the body; back to the guard.
## left: the mirror (the left blade flies, the right one points).
static func _throw(left: bool) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("strike_throw_l" if left else "strike_throw", 30, false, "pair")
	c.marker("coil", 7).marker("release", 10).marker("hit", 11).marker("recovered", 24).marker("pose", 10)
	c.meta = { "hand_frame": "root", "kind": "shot" }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(30, BODY + _hand_chans())
	var s := -1.0 if left else 1.0          # mirror x and yaws
	var t := "hand_l" if left else "hand_r"
	var o := "hand_r" if left else "hand_l"
	BWAnimAction._feet_cast(c)
	c.pose(2, { "head": Vector3(0.04, 0.18 * s, 0.0) })
	c.pose(5, { "root": Vector3(0, -0.08, -0.03), "hips": Vector3(0, -0.22 * s, 0), "chest": Vector3(-0.1, -0.34 * s, 0.03 * s),
		"head": Vector3(0.02, 0.32 * s, 0.0), "squash": -0.02 })
	c.pose(7, { "root": Vector3(0, -0.1, -0.05), "hips": Vector3(0, -0.26 * s, 0), "chest": Vector3(-0.14, -0.4 * s, 0.04 * s),
		"spine": Vector3(-0.05, 0, 0), "head": Vector3(0.0, 0.36 * s, 0.0), "squash": -0.01 }, "f")
	c.pose(10, { "root": Vector3(0, -0.06, 0.06), "hips": Vector3(0.04, 0.14 * s, 0), "chest": Vector3(0.16, 0.26 * s, -0.03 * s),
		"spine": Vector3(0.1, 0, 0), "head": Vector3(-0.04, -0.16 * s, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(12, { "root": Vector3(0, -0.09, 0.07), "chest": Vector3(0.2, 0.34 * s, -0.03 * s), "head": Vector3(-0.02, -0.22 * s, 0.0),
		"squash": -0.02, "head_sq": 0.02 })
	c.pose(17, { "root": Vector3(0, -0.08, 0.06), "chest": Vector3(0.16, 0.3 * s, -0.02 * s), "head": Vector3(-0.04, -0.2 * s, 0.0),
		"squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(24, { "root": Vector3(0, -0.04, 0.0), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3(-0.03, 0, 0) })
	var mx := func(v: Vector3) -> Vector3: return Vector3(v.x * s, v.y, v.z)
	# the throwing hand: back high by the ear, the blade tipped up
	c.key(t + "_pos", 4, mx.call(Vector3(-0.3, 0.22, 0.02))).key(t + "_aim", 4, mx.call(Vector3(-0.2, 0.8, 0.5)).normalized())
	c.key(t + "_pos", 7, mx.call(Vector3(-0.32, 0.4, -0.22)), "f").key(t + "_aim", 7, mx.call(Vector3(-0.05, 0.75, 0.66)).normalized(), "f")
	c.key(t + "_pos", 8.5, mx.call(Vector3(-0.3, 0.44, -0.12))).key(t + "_aim", 8.5, mx.call(Vector3(0.0, 0.85, 0.5)).normalized())
	c.key(t + "_pos", 10, mx.call(Vector3(-0.12, 0.32, 0.46)), "l").key(t + "_aim", 10, mx.call(Vector3(0.05, 0.12, 0.99)).normalized(), "l")
	c.key(t + "_pos", 12, mx.call(Vector3(0.06, 0.06, 0.5))).key(t + "_aim", 12, mx.call(Vector3(0.3, -0.35, 0.88)).normalized())
	c.key(t + "_pos", 17, mx.call(Vector3(0.1, 0.0, 0.42)), "f").key(t + "_aim", 17, mx.call(Vector3(0.4, -0.2, 0.9)).normalized(), "f")
	c.key(t + "_pole", 7, mx.call(Vector3(-1, -0.3, -0.4))).key(t + "_pole", 12, mx.call(Vector3(-0.6, -1, 0.0))).key(t + "_pole", 22, c.base[t + "_pole"])
	c.key("smear", 8.5, 0.0).key("smear", 9.5, 1.0).key("smear", 11, 1.0).key("smear", 13, 0.0)
	c.key("arm_stretch", 9, 0.0).key("arm_stretch", 10, 0.08).key("arm_stretch", 13, 0.02).key("arm_stretch", 17, 0.0)
	# the other blade points the way, then is flung back for balance
	c.key(o + "_pos", 5, mx.call(Vector3(0.22, 0.2, 0.36))).key(o + "_aim", 5, mx.call(Vector3(0.05, 0.25, 0.97)).normalized())
	c.key(o + "_pos", 7, mx.call(Vector3(0.22, 0.26, 0.42)), "f").key(o + "_aim", 7, mx.call(Vector3(0.05, 0.2, 0.98)).normalized(), "f")
	c.key(o + "_pos", 11, mx.call(Vector3(0.34, 0.02, -0.12))).key(o + "_aim", 11, mx.call(Vector3(0.4, 0.5, -0.75)).normalized())
	c.key(o + "_pos", 17, mx.call(Vector3(0.34, 0.0, -0.14)), "f").key(o + "_aim", 17, mx.call(Vector3(0.4, 0.55, -0.7)).normalized(), "f")
	c.key(o + "_pole", 6, mx.call(Vector3(0.8, -1, -0.2))).key(o + "_pole", 22, c.base[o + "_pole"])
	c.lead(8.5, 12.5, 0.8, t)
	return c


# ---------------------------------------------------------------------- hook

## HOOK (one, heavy; the axes, 40 f, root frame): the axe swung back low at
## her right (coil 6), cast out sidearm along the line on the release (f10,
## the hook flies), held out while it bites (f11-14), then HAULED in two
## heaves: a hard yank back to the hip with the body thrown back and the
## right foot stepping back (f18, "haul"), a second pull (f23); back.
static func _hook(st: String) -> BWAnimClips.Clip:
	var heavy := st == "heavy"
	var c := BWAnimClips.new_clip("strike_hook", 40, false, st)
	c.marker("coil", 6).marker("release", 10).marker("hit", 11).marker("haul", 18).marker("recovered", 35).marker("pose", 18)
	c.meta = { "hand_frame": "root", "kind": "shot" }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(40, BODY + _hand_chans())
	c.pose(3, { "root": Vector3(0, -0.06, -0.02), "hips": Vector3(0, -0.2, 0), "chest": Vector3(0.02, -0.3, 0.0), "head": Vector3(0.02, 0.3, 0.0) })
	c.pose(6, { "root": Vector3(0, -0.12, -0.04), "hips": Vector3(0, -0.3, 0), "chest": Vector3(0.06, -0.46, 0.04), "spine": Vector3(0.06, 0, 0),
		"head": Vector3(0.04, 0.44, 0.0), "squash": -0.03, "head_sq": 0.02 }, "f")
	c.pose(10, { "root": Vector3(0, -0.08, 0.08), "hips": Vector3(0.04, 0.16, 0), "chest": Vector3(0.18, 0.22, -0.02), "spine": Vector3(0.12, 0, 0),
		"head": Vector3(-0.06, -0.14, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(13, { "root": Vector3(0, -0.1, 0.08), "chest": Vector3(0.18, 0.2, -0.02), "head": Vector3(-0.08, -0.12, 0.0), "squash": 0.0, "head_sq": 0.0 }, "f")
	# the haul: thrown back, low, the head down with the effort
	c.pose(16, { "root": Vector3(0, -0.12, 0.02), "chest": Vector3(0.1, 0.1, 0.0) })
	c.pose(18, { "root": Vector3(0, -0.18, -0.14), "hips": Vector3(-0.06, -0.12, 0), "spine": Vector3(-0.12, 0, 0), "chest": Vector3(-0.26, -0.18, 0.02),
		"head": Vector3(0.16, 0.12, 0.0), "squash": -0.05, "head_sq": 0.04 }, "l")
	c.pose(20, { "root": Vector3(0, -0.15, -0.1), "chest": Vector3(-0.12, -0.1, 0.0), "squash": 0.01, "head_sq": 0.0 })
	c.pose(23, { "root": Vector3(0, -0.19, -0.16), "spine": Vector3(-0.14, 0, 0), "chest": Vector3(-0.28, -0.22, 0.02), "head": Vector3(0.18, 0.1, 0.0),
		"squash": -0.04, "head_sq": 0.03 }, "l")
	c.pose(27, { "root": Vector3(0, -0.12, -0.1), "spine": Vector3(-0.04, 0, 0), "chest": Vector3(-0.08, -0.08, 0.0), "head": Vector3(0.06, 0.04, 0.0),
		"squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(33, { "root": Vector3(0, -0.03, -0.02), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3(0.0, 0, 0) })
	var hk := { 3: [Vector3(-0.3, -0.04, 0.0), Vector3(-0.4, 0.5, -0.75)],
		6: [Vector3(-0.36, -0.06, -0.22), Vector3(-0.3, 0.2, -0.93)],
		8: [Vector3(-0.36, -0.02, -0.1), Vector3(-0.5, 0.3, -0.8)],
		10: [Vector3(-0.14, 0.18, 0.5), Vector3(0.0, 0.25, 0.97)],
		13: [Vector3(-0.12, 0.2, 0.52), Vector3(0.0, 0.2, 0.98)],
		18: [Vector3(-0.2, 0.08, 0.06), Vector3(-0.15, 0.7, 0.7)],
		20: [Vector3(-0.16, 0.1, 0.18), Vector3(-0.05, 0.55, 0.83)],
		23: [Vector3(-0.22, 0.06, 0.0), Vector3(-0.2, 0.8, 0.55)],
		28: [Vector3(-0.24, -0.04, 0.12), Vector3(-0.3, 0.75, 0.6)] }
	for f in hk:
		var m := "f" if f in [6, 13, 18, 23] else ("l" if f == 10 else "a")
		c.key("hand_r_pos", float(f), hk[f][0], m).key("hand_r_aim", float(f), (hk[f][1] as Vector3).normalized(), m)
	c.key("hand_r_edge", 6, Vector3(0, 1, 0)).key("hand_r_edge", 13, Vector3(0, 1, 0)).key("hand_r_edge", 30, c.base.hand_r_edge)
	c.key("hand_r_pole", 6, Vector3(-1, -0.6, -0.3)).key("hand_r_pole", 30, c.base.hand_r_pole)
	c.key("smear", 8, 0.0).key("smear", 9.5, 0.9).key("smear", 11, 0.0)
	c.key("arm_stretch", 9, 0.0).key("arm_stretch", 10, 0.08).key("arm_stretch", 14, 0.04).key("arm_stretch", 17, 0.0)
	if heavy:
		c.key("hand_l_grip", 2, 1.0).key("hand_l_grip", 7, 0.0).key("hand_l_grip", 15, 0.0).key("hand_l_grip", 17, 1.0).key("hand_l_grip", 38, 1.0)
	# the free hand: out for balance on the cast, grabs the haft for the haul
	c.key("hand_l_pos", 6, Vector3(0.26, 0.04, 0.3)).key("hand_l_pos", 10, Vector3(0.32, 0.06, -0.1))
	c.key("hand_l_pos", 14, Vector3(0.2, 0.08, 0.26))
	c.key("hand_l_pos", 18, Vector3(-0.08, 0.1, 0.16), "f").key("hand_l_pos", 23, Vector3(-0.1, 0.08, 0.1), "f")
	c.key("hand_l_pos", 30, (c.base.hand_l_pos as Vector3))
	c.key("hand_l_pole", 6, Vector3(1, -0.6, -0.2)).key("hand_l_pole", 30, c.base.hand_l_pole)
	var g := _feet_base(c)
	var back: Vector2 = g[1] + Vector2(-0.04, -0.2)
	BWAnimAction._feet_cast(c)
	BWAnimStricken._step(c, "r", 15, 18.5, g[1], back, 0.06)
	_foot(c, "r", 26, back, 0, -0.3, 0, "f")
	BWAnimStricken._step(c, "r", 27, 31, back, g[1], 0.05)
	_foot(c, "r", 40, g[1], 0, -0.22, 0, "f")
	return c


# ------------------------------------------------------------------- grapple

## GRAPPLE (fists, 46 f): the dash in with both hands open and low, both
## hands SEIZE on the hit (f14, at the foe's chest), the body sinks and
## pulls it in (f17-19), then heaves: up on the toes, turning to her left,
## the hands carry it up and over the left shoulder ("throw", f22, the foe
## leaves her hands), and slam down to her left (f24) with a deep squash;
## the hop home.
static func _grapple() -> BWAnimClips.Clip:
	var beats := [0, 4, 8, 10, 13, 14, 24, 30, 34, 37, 42, 46]
	var A := BWAnimAction
	var hands := {
		4.0: A._m(A._fist_guard("r"), A._fist_guard("l")),
		8.0: A._m(A._fk("r", Vector3(-0.16, 0.16, 0.3), Vector3(0.1, 0.1, 1), Vector3(-0.3, 1, 0), { "_mode": "f" }),
			A._fk("l", Vector3(0.16, 0.16, 0.3), Vector3(-0.1, 0.1, 1), Vector3(0.3, 1, 0))),
		12.0: A._m(A._fk("r", Vector3(-0.14, 0.27, 0.64), Vector3(0.2, 0.1, 1), Vector3(-0.3, 1, 0), { "arm_stretch": 0.05 }),
			A._fk("l", Vector3(0.14, 0.27, 0.64), Vector3(-0.2, 0.1, 1), Vector3(0.3, 1, 0))),
		14.0: A._m(A._fk("r", Vector3(-0.12, 0.28, 0.72), Vector3(0.6, 0.0, 0.8), Vector3(0, 1, 0), { "arm_stretch": 0.07 }),
			A._fk("l", Vector3(0.12, 0.28, 0.72), Vector3(-0.6, 0.0, 0.8), Vector3(0, 1, 0))),
		15.5: A._m(A._fk("r", Vector3(-0.12, 0.18, 0.34), Vector3(0.6, 0.0, 0.8), Vector3(0, 1, 0), { "arm_stretch": 0.0 }),
			A._fk("l", Vector3(0.12, 0.18, 0.34), Vector3(-0.6, 0.0, 0.8), Vector3(0, 1, 0))),
		16.5: A._m(A._fk("r", Vector3(0.08, 0.6, 0.42), Vector3(0.6, 0.6, 0.5), Vector3(0, 1, 0), { "smear": 0.0 }),
			A._fk("l", Vector3(0.32, 0.58, 0.34), Vector3(0.0, 0.6, 0.8), Vector3(0, 1, 0))),
		17.5: A._m(A._fk("r", Vector3(0.3, 0.66, 0.22), Vector3(0.7, 0.4, 0.5), Vector3(0, 1, 0), { "smear": 0.6 }),
			A._fk("l", Vector3(0.48, 0.5, 0.12), Vector3(0.6, 0.1, 0.8), Vector3(0, 1, 0))),
		18.0: A._m(A._fk("r", Vector3(0.34, -0.06, 0.52), Vector3(0.6, -0.6, 0.5), Vector3(0, 1, 0), { "smear": 0.8, "_mode": "l" }),
			A._fk("l", Vector3(0.48, -0.12, 0.42), Vector3(0.6, -0.6, 0.5), Vector3(0, 1, 0))),
		20.0: A._m(A._fk("r", Vector3(0.24, 0.0, 0.36), Vector3(0.5, -0.3, 0.8), Vector3(0, 1, 0), { "smear": 0.0, "_mode": "f" }),
			A._fk("l", Vector3(0.36, -0.02, 0.26), Vector3(0.5, -0.3, 0.8), Vector3(0, 1, 0))),
		24.0: A._m(A._fk("r", Vector3(-0.08, 0.16, 0.3), Vector3(0.1, 0.3, 1), Vector3(-0.6, 0.8, 0)),
			A._fk("l", Vector3(0.16, 0.22, 0.34), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0))),
		27.0: A._m(A._fist_guard("r"), A._fist_guard("l")),
	}
	var c := A._melee("strike_grapple", "fists", beats, 0.4, hands, 0.8)
	var f_pull := A._warp(15.5, beats)
	var f_throw := A._warp(17.2, beats)
	var f_slam := A._warp(18.0, beats)
	c.marker("throw", f_throw)
	# the heave: sink and pull in, up on the toes turning left, the slam
	c.key("root", f_pull, Vector3(0, -0.2, 0.04), "f")
	c.key("chest", f_pull, Vector3(0.12, -0.12, 0.0), "f")
	c.key("root", f_throw, Vector3(0, 0.02, 0.06))
	c.key("chest", f_throw, Vector3(-0.22, 0.5, -0.12))
	c.key("hips", f_throw, Vector3(-0.04, 0.36, 0.0))
	c.key("head", f_throw, Vector3(-0.1, -0.2, 0.0))
	c.key("squash", f_throw, 0.05)
	c.key("root", f_slam, Vector3(0, -0.26, 0.08), "l")
	c.key("chest", f_slam, Vector3(0.34, 0.62, -0.08), "l")
	c.key("hips", f_slam, Vector3(0.08, 0.42, 0.0), "l")
	c.key("head", f_slam, Vector3(0.2, -0.3, 0.0), "l")
	c.key("squash", f_slam, -0.07)
	c.key("chest", A._warp(19.0, beats), Vector3(0.24, 0.5, -0.06))
	c.key("chest", A._warp(22.0, beats), Vector3(0.06, 0.12, 0.0))
	c.key("hips", A._warp(22.0, beats), Vector3(0.0, 0.08, 0.0))
	return c


# ------------------------------------------------------------------- hundred

## HUNDRED FISTS (fists, 46 f): the dash in, then six blows on ones-and-twos
## (left, right, left, right, left, a full right cross), "hit" .. "hit6",
## the chest rocking into each, the last with a stretch; the hop home.
static func _hundred() -> BWAnimClips.Clip:
	var beats := [0, 2, 5, 7, 9, 10, 27, 31, 35, 38, 42, 46]
	var A := BWAnimAction
	var hands := {
		4.0: A._m(A._fist_guard("r"), A._fist_guard("l")),
		8.0: A._m(A._fk("r", Vector3(-0.17, 0.31, 0.22), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0)),
			A._fk("l", Vector3(0.16, 0.30, 0.26), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0), { "_mode": "f" })),
		12.5: A._fk("l", Vector3(0.12, 0.32, 0.5), Vector3(-0.06, 0.1, 1), Vector3(0.4, 0.9, 0), { "_mode": "l", "smear": 0.5 }),
	}
	# the barrage, keyed in real frames after the hit (ref 14 = f10, ref 18 = f27)
	var hits := [10.0, 13.0, 16.0, 19.0, 22.0, 25.5]
	var c := A._melee("strike_hundred", "fists", beats, -0.5, hands, 0.85)
	var ch0: Vector3 = c.value("chest", 9.0)
	ch0.y = 0.0
	for i in hits.size():
		var f: float = hits[i]
		var left := i % 2 == 0
		var depth := 1.15 if i == hits.size() - 1 else 1.0
		var punch: Dictionary = A._jab_l(depth) if left else A._cross_r(depth)
		var home: Dictionary = A._fist_guard("l") if left else A._fist_guard("r")
		var other: Dictionary = A._fist_guard("r") if left else A._fist_guard("l")
		c.pose(f - 1.0, A._m(A._m(home, other), { "smear": 0.0 }))
		c.pose(f, A._m(A._m(punch, other), { "smear": 0.7 }), "l")
		c.pose(f + 1.0, A._m(A._jab_l(0.7) if left else A._cross_r(0.7), { "smear": 0.0 }))
		c.key("chest", f, ch0 + Vector3(0.03, (-0.3 if left else 0.3) * (1.4 if i == hits.size() - 1 else 1.0), 0.0))
		c.marker("hit" if i == 0 else "hit%d" % (i + 1), f)
	c.pose(27.5, A._m(A._fist_guard("r"), A._fist_guard("l")))
	c.key("chest", 28.0, ch0 + Vector3(0.0, 0.1, 0.0))
	c.key("arm_stretch", 25.5, 0.07).key("arm_stretch", 28.0, 0.0)
	c.meta["hits"] = 6
	return c

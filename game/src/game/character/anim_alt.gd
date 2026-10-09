class_name BWAnimAlt
extends RefCounted
## D510-D519: the alternate clips (design/art/ANIMATION.md, "Alternates").
## BWClipRoute.pick chooses them per blow (ALTERNATES, the author's weights);
## skills name some of them in their defs (Earthsplitter: sweep_under, Axe
## Throw: throw_under, Tempest: tempest). Every clip starts and ends on its
## set's guard. Hands are keyed in the ROOT frame (aimed at the target).
##
##   strike_smash        heavy, polearm, one (axes; routed to the axe class):
##                       both hands on the haft, a crouch, a jump with the
##                       weapon thrown back over the head, slammed down on the
##                       landing (hit = land) into a one-legged crouch, the
##                       rear leg stretched out behind (D511)
##   strike_smash_flip   the same with a forward somersault in the air (meta
##                       flip_pitch: 0 -> TAU, BWCharacter turns the rig about
##                       the hips). Crits always play it (D511)
##   strike_sweep_under  one, heavy (axes): one-handed, weight on the back
##                       foot, the axe hanging down-back behind the rear leg
##                       (the coil); swung down past the floor and up through
##                       the target to ~120 deg (D512; Earthsplitter)
##   strike_throw_under  one, heavy (axes): the underhand toss (release: the
##                       axe flies, the hand is empty: meta.toss), the hand
##                       reaches over the shoulder and draws a new one (draw)
##                       (D513; Axe Throw)
##   strike_thrust_2h    one (swords): both hands close at the hip, the blade
##                       level, driven straight in (D514)
##   strike_lunge        one (swords), spear (lance, javelin, trident): the
##                       fencing lunge. En garde side-on, a hop in, then the
##                       long step: the front knee over the foot, the rear leg
##                       straight, the point a touch above level, the off arm
##                       flung back (on the lance, the shield arm swings back
##                       with it) (D515)
##   strike_flourish     pair: crouched with the arms crossed, a jump up and
##                       forward slashing out and up until both blades are
##                       over the head (hit at the top), land, hop home (D516;
##                       Self-detonate plays it in place)
##   strike_backstab     pair: low and coiled, the slither round to the back
##                       (launch..land; BWBackstab moves the root on an S),
##                       the stab down into the back, the slither home
##                       (slide_back..slide_home) (D517)
##   shot_jump           bow: nock on the ground, spring up drawing, aim and
##                       loose at the top (release), land (D518)
##   cast_tempest        staff: the cast's gather, then she floats up a little
##                       and turns once (meta spin_yaw) with the staff raised,
##                       looses at the top (release) and settles (D519)

const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
const AXE_SETS := ["one", "heavy"]
const SMASH_SETS := ["one", "heavy", "polearm"]
const LUNGE_SETS := ["one", "spear"]


static func clips(st: String) -> Array:
	var out: Array = []
	if st in SMASH_SETS:
		out.append(smash(st, false))
		out.append(smash(st, true))
	if st in AXE_SETS:
		out.append(sweep_under(st))
		out.append(throw_under(st))
	if st == "one":
		out.append(thrust_2h())
	if st in LUNGE_SETS:
		out.append(lunge(st))
	if st == "pair":
		out.append(flourish())
		out.append(backstab())
	if st == "bow":
		out.append(shot_jump())
	if st == "staff":
		out.append(cast_tempest())
	return out


## Pose names (merged into BWAnimClips.actions_for): each strike with its
## held-coil windup, like the skill clips (BWUnitView.skill routes them).
static func actions(st: String) -> Dictionary:
	var skills := {}
	if st in SMASH_SETS:
		skills.merge({ "smash": "strike_smash", "smash_flip": "strike_smash_flip" })
	if st in AXE_SETS:
		skills.merge({ "sweep_under": "strike_sweep_under", "throw_under": "strike_throw_under" })
	if st == "one":
		skills["thrust_2h"] = "strike_thrust_2h"
	if st in LUNGE_SETS:
		skills["lunge"] = "strike_lunge"
	if st == "pair":
		skills.merge({ "flourish": "strike_flourish", "backstab": "strike_backstab" })
	if st == "bow":
		skills["shot_jump"] = "shot_jump"
	var out := {}
	for k in skills:
		out[k] = { "clip": skills[k] }
		out["windup_" + k] = { "clip": skills[k], "hold": "coil" }
	if st == "staff":
		out["cast_tempest"] = { "clip": "cast_tempest", "after": { "channel": "coil" } }
		out["tempest"] = { "clip": "cast_tempest", "after": { "channel": "coil" } }   # the def's clip name
	return out


# ------------------------------------------------------------------ helpers

static func _hand_chans() -> Array:
	return BWAnimSkill._hand_chans()


static func _begin(name: String, frames: int, st: String, kind: String = "melee") -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip(name, frames, false, st)
	c.at_base(0, BODY + _hand_chans())
	c.at_base(frames, BODY + _hand_chans())
	c.meta = { "hand_frame": "root", "kind": kind }
	return c


static func _r(c: BWAnimClips.Clip, d: Vector3) -> Vector3:
	return (c.base.root as Vector3) + d


static func _foot(c: BWAnimClips.Clip, side: String, f: float, g: Vector2, pitch: float, yaw: float, lift: float = 0.0, mode: String = "a") -> void:
	BWAnimSkill._foot(c, side, f, g, pitch, yaw, lift, mode)


## A foot in the air (model space: the clip lifts the body itself).
static func _air(c: BWAnimClips.Clip, side: String, f: float, pos: Vector3, pitch: float, mode: String = "a") -> void:
	var yaw := 0.2 if side == "l" else -0.2
	c.pose(f, { "foot_%s_pos" % side: pos, "foot_%s_rot" % side: Vector3(pitch, yaw, 0) }, mode)


static func _hand(c: BWAnimClips.Clip, h: String, f: float, pos: Vector3, aim: Vector3, mode: String = "a") -> void:
	c.key(h + "_pos", f, pos, mode).key(h + "_aim", f, aim.normalized(), mode)


## Both feet planted on the guard stance at f.
static func _feet_home(c: BWAnimClips.Clip, f: float) -> void:
	var g := BWAnimSkill._feet_base(c)
	_foot(c, "l", f, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", f, g[1], 0, -0.22, 0, "f")


## A whole-body curve sampled at the bake rate (spin_yaw / flip_pitch meta):
## keys [[frame, share 0..1, mode]], scaled by TAU.
static func _turn_meta(keys: Array, frames: int) -> Array:
	var ys: Array = []
	for i in int(round(frames / BWAnimClips.FPS * BWAnimClips.BAKE_HZ)) + 1:
		var f := i * BWAnimClips.FPS / BWAnimClips.BAKE_HZ
		ys.append(TAU * clampf(float(BWAnimClips.eval_keys(keys, f, false, float(frames))), 0.0, 1.0))
	return ys


# -------------------------------------------------------------------- smash

## SMASH (D511): 46 f plain, 50 f with the flip. Both hands on the haft
## through the jump (the hatchet too). The landing is the blow: the weapon
## comes over the top and down on `hit` = `land`, the left knee deep over
## its foot, the right leg stretched out behind on its toes.
static func smash(st: String, flip: bool) -> BWAnimClips.Clip:
	var x := 3.0 if flip else 0.0            # the flip's extra air time
	var n := 50 if flip else 46
	var c := _begin("strike_smash_flip" if flip else "strike_smash", n, st)
	var land := 19.0 + x
	c.marker("coil", 9).marker("launch", 11).marker("land", land).marker("hit", land)
	c.marker("hop_start", 32 + x).marker("hop_end", 35 + x).marker("recovered", 42 + x).marker("pose", land)
	c.meta["engage"] = { "heavy": 1.2, "polearm": 1.45, "one": 1.05 }.get(st, 1.15)
	# a long shaft lands flatter so its head rests at the floor, not under it
	var low := { "heavy": 0.04, "polearm": 0.12, "one": 0.3 }.get(st, 0.3) as float
	var hy := { "heavy": 0.16, "polearm": 0.08, "one": 0.0 }.get(st, 0.0) as float
	var a := func(f: float) -> float: return f if f <= 12.0 else (f + x * clampf((f - 12.0) / 7.0, 0.0, 1.0) if f < 19.0 else f + x)
	# --- the gather and the crouch: the head finds the target, the weapon
	# goes back low at her right, both fists on it
	c.pose(3, { "root": _r(c, Vector3(0, -0.05, -0.02)), "chest": Vector3(0.05, -0.18, 0.0), "head": Vector3(0.0, 0.2, 0.0) })
	c.pose(6, { "root": _r(c, Vector3(0, -0.17, -0.05)), "spine": Vector3(0.16, 0, 0), "chest": Vector3(0.14, -0.3, 0.02),
		"head": Vector3(-0.16, 0.3, 0.0), "squash": -0.025 })
	c.pose(9, { "root": _r(c, Vector3(0, -0.25, -0.06)), "spine": Vector3(0.28, 0, 0), "chest": Vector3(0.2, -0.36, 0.03),
		"head": Vector3(-0.26, 0.32, 0.0), "squash": -0.045, "head_sq": 0.035 }, "f")
	c.pose(10, { "root": _r(c, Vector3(0, -0.29, -0.05)), "squash": -0.06, "head_sq": 0.045 })
	# --- the spring: stretched, then high, arched back with the weapon laid
	# back over the head
	c.pose(11, { "root": _r(c, Vector3(0, 0.04, 0.02)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(-0.1, -0.15, 0.0),
		"head": Vector3(-0.12, 0.12, 0.0), "squash": 0.06, "head_sq": -0.04, "leg_stretch": 0.05 }, "l")
	if flip:
		# tucked for the somersault: knees up, back rounded, head in
		c.pose(13, { "root": _r(c, Vector3(0, 0.34, 0.04)), "spine": Vector3(0.3, 0, 0), "chest": Vector3(0.25, 0.0, 0.0),
			"head": Vector3(0.2, 0.0, 0.0), "squash": -0.02, "head_sq": 0.0, "leg_stretch": 0.0 })
		c.pose(17, { "root": _r(c, Vector3(0, 0.42, 0.05)), "spine": Vector3(0.4, 0, 0), "chest": Vector3(0.3, 0.0, 0.0),
			"head": Vector3(0.25, 0.0, 0.0), "squash": -0.03 }, "f")
		c.pose(19.5, { "root": _r(c, Vector3(0, 0.3, 0.07)), "spine": Vector3(-0.05, 0, 0), "chest": Vector3(-0.2, 0.0, 0.0),
			"head": Vector3(-0.1, 0.0, 0.0), "squash": 0.02 })
	else:
		c.pose(13, { "root": _r(c, Vector3(0, 0.28, 0.04)), "spine": Vector3(-0.08, 0, 0), "chest": Vector3(-0.24, 0.0, 0.0),
			"head": Vector3(-0.08, 0.0, 0.0), "squash": 0.02, "head_sq": 0.0, "leg_stretch": 0.0 })
		c.pose(15, { "root": _r(c, Vector3(0, 0.33, 0.05)), "spine": Vector3(-0.12, 0, 0), "chest": Vector3(-0.3, 0.0, 0.0),
			"head": Vector3(-0.1, 0.0, 0.0) }, "f")
	# --- the slam: hips and chest jackknife over, down onto the front foot
	c.pose(a.call(17.0), { "root": _r(c, Vector3(0, 0.22, 0.08)), "spine": Vector3(0.18, 0, 0), "chest": Vector3(0.12, 0.0, 0.0),
		"head": Vector3(0.0, 0.0, 0.0), "squash": 0.0 })
	c.pose(a.call(18.0), { "root": _r(c, Vector3(0, 0.02, 0.1)), "spine": Vector3(0.36, 0, 0), "chest": Vector3(0.3, 0.02, 0.0),
		"head": Vector3(-0.2, 0.0, 0.0) }, "l")
	c.pose(land, { "root": _r(c, Vector3(0, -0.38, 0.12)), "spine": Vector3(0.46, 0, 0), "chest": Vector3(0.34, 0.06, -0.02),
		"head": Vector3(-0.42, -0.04, 0.0), "squash": -0.07, "head_sq": 0.055 }, "l")
	c.pose(land + 2.0, { "root": _r(c, Vector3(0, -0.4, 0.12)), "squash": -0.055, "head_sq": 0.04 })
	c.pose(land + 5.0, { "root": _r(c, Vector3(0, -0.37, 0.11)), "spine": Vector3(0.42, 0, 0), "chest": Vector3(0.28, 0.05, -0.02),
		"head": Vector3(-0.3, -0.04, 0.0), "squash": -0.02, "head_sq": 0.01 }, "f")
	c.pose(28 + x, { "root": _r(c, Vector3(0, -0.22, 0.06)), "spine": Vector3(0.16, 0, 0), "chest": Vector3(0.08, 0.0, 0.0),
		"head": Vector3(-0.04, 0.0, 0.0), "squash": 0.0, "head_sq": 0.0 })
	c.pose(32 + x, { "root": _r(c, Vector3(0, -0.05, 0.02)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(0.0, 0.0, 0.0),
		"head": Vector3(0.0, 0.0, 0.0), "squash": 0.03, "head_sq": -0.02 })
	c.pose(35 + x, { "root": _r(c, Vector3(0, -0.12, -0.01)), "squash": -0.04, "head_sq": 0.035 }, "f")
	c.pose(38 + x, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.01, "head_sq": -0.01 })
	# --- the weapon (root frame), both fists on it
	var hk := {
		4.0: [Vector3(-0.24, -0.08, 0.16), Vector3(-0.4, 0.5, 0.75)],
		9.0: [Vector3(-0.26, -0.3, -0.06), Vector3(-0.35, -0.12, -0.93)],
		11.0: [Vector3(-0.2, 0.12, 0.2), Vector3(-0.15, 0.9, 0.4)],
		13.0: [Vector3(-0.06, 0.6, 0.04), Vector3(0.0, 0.5, -0.86)],
		15.0: [Vector3(-0.04, 0.64, -0.03), Vector3(0.0, 0.38, -0.92)],
		17.0: [Vector3(-0.04, 0.58, 0.2), Vector3(0.0, 0.96, 0.28)],
		18.0: [Vector3(-0.03, 0.22, 0.5), Vector3(0.0, 0.3, 0.95)],
		19.0: [Vector3(-0.03, -0.3 + hy, 0.46), Vector3(0.0, -low, 1.0)],
		21.0: [Vector3(-0.03, -0.32 + hy, 0.45), Vector3(0.0, -low - 0.02, 1.0)],
		24.0: [Vector3(-0.04, -0.28 + hy, 0.44), Vector3(0.0, -low + 0.04, 1.0)],
		28.0: [Vector3(-0.12, -0.12, 0.36), Vector3(-0.2, 0.45, 0.87)],
	}
	if flip:
		# through the somersault the weapon is held level across the chest (no
		# end can point into the floor while she turns over), then swung up
		hk.erase(13.0)
		hk.erase(15.0)
		hk[13.0] = [Vector3(-0.02, 0.12, 0.26), Vector3(-1.0, 0.1, 0.05)]     # held across the chest: level all the way round
		hk[16.0] = [Vector3(0.0, 0.18, 0.24), Vector3(-1.0, 0.15, 0.0)]
	for f in hk:
		var fa: float = a.call(float(f)) if float(f) > 12.0 and float(f) < 19.0 else (float(f) + (x if float(f) >= 19.0 else 0.0))
		if flip and float(f) in [13.0, 16.0]:
			fa = float(f) + (0.5 if float(f) == 13.0 else 1.0)
		var mode := "f" if float(f) in [9.0, 15.0, 24.0] else ("l" if float(f) in [18.0, 19.0] else "a")
		_hand(c, "hand_r", fa, hk[f][0], hk[f][1], mode)
	c.key("hand_r_edge", 9, Vector3(0, 1, 0)).key("hand_r_edge", land + 6.0, Vector3(0, 1, 0)).key("hand_r_edge", 34 + x, c.base.hand_r_edge)
	c.key("hand_r_pole", 9, Vector3(-1, -0.5, -0.3)).key("hand_r_pole", 15 + x, Vector3(-1, -0.2, 0.0)).key("hand_r_pole", land, Vector3(-1, -0.6, 0.2))
	c.key("hand_r_pole", 34 + x, c.base.hand_r_pole)
	c.key("hand_l_grip", 2, float(c.base.hand_l_grip)).key("hand_l_grip", 6, 1.0).key("hand_l_grip", 34 + x, 1.0)
	c.key("hand_l_grip", 38 + x, float(c.base.hand_l_grip))
	c.key("hand_l_pole", 9, Vector3(1, -0.5, -0.2)).key("hand_l_pole", land, Vector3(1, -0.6, 0.2)).key("hand_l_pole", 36 + x, c.base.hand_l_pole)
	c.key("hand_l_pos", 6, Vector3(-0.1, -0.2, 0.1)).key("hand_l_pos", 34 + x, Vector3(-0.1, -0.12, 0.3))
	c.key("flat", 6, 0.2).key("flat", 30 + x, 0.3)
	c.key("smear", a.call(16.5) if not flip else 13.0, 0.0).key("smear", a.call(17.5), 1.0).key("smear", land + 1.0, 1.0).key("smear", land + 3.0, 0.0)
	c.key("arm_stretch", a.call(17.5), 0.0).key("arm_stretch", land, 0.08).key("arm_stretch", land + 5.0, 0.0)
	c.lead(a.call(16.5), land + 1.0, 0.85)
	# --- feet: planted through the crouch, up on the toes, off on launch;
	# tucked; the left foot reaches and lands, the right stretches back on its toes
	var g := BWAnimSkill._feet_base(c)
	var fl1 := Vector2(0.15, 0.38)
	var fr1 := Vector2(-0.12, -0.5)
	_feet_home(c, 0)
	_feet_home(c, 8)
	_foot(c, "l", 10, g[0], 0.4, 0.22)
	_foot(c, "r", 10, g[1], 0.45, -0.22)
	if flip:
		_air(c, "l", 13, Vector3(0.12, 0.5, 0.22), 0.3)
		_air(c, "r", 13, Vector3(-0.12, 0.48, 0.16), 0.4)
		_air(c, "l", 17, Vector3(0.12, 0.6, 0.2), 0.3, "f")
		_air(c, "r", 17, Vector3(-0.12, 0.58, 0.14), 0.4, "f")
	else:
		_air(c, "l", 13, Vector3(0.12, 0.44, 0.18), 0.25)
		_air(c, "r", 13, Vector3(-0.12, 0.4, -0.08), 0.6)
		_air(c, "l", 15, Vector3(0.12, 0.46, 0.2), 0.2, "f")
		_air(c, "r", 15, Vector3(-0.12, 0.42, -0.1), 0.6, "f")
	_air(c, "l", a.call(17.0), Vector3(0.14, 0.3, 0.36), -0.3)
	_air(c, "r", a.call(17.0), Vector3(-0.12, 0.3, -0.32), 0.9)
	_foot(c, "l", a.call(18.3), fl1, -0.25, 0.15, 0.05)
	_air(c, "r", a.call(18.3), Vector3(-0.12, 0.12, -0.46), 1.0)
	_foot(c, "l", land, fl1, 0, 0.15, 0, "f")
	_foot(c, "r", land, fr1, 1.05, -0.28, 0, "f")
	_foot(c, "l", 27 + x, fl1, 0, 0.15, 0, "f")
	_foot(c, "r", 27 + x, fr1, 1.05, -0.28, 0, "f")
	_foot(c, "r", 30 + x, fr1 + Vector2(0.0, 0.18), 0.6, -0.25)
	_foot(c, "r", 31.5 + x, fr1 + Vector2(0.0, 0.26), 0.45, -0.25, 0, "f")
	_air(c, "l", 33.5 + x, Vector3(0.13, 0.17, 0.22), -0.15)
	_air(c, "r", 33.5 + x, Vector3(-0.13, 0.15, -0.12), 0.45)
	_feet_home(c, 35 + x)
	_feet_home(c, n)
	if flip:
		# the somersault (BWCharacter: the rig turns about the hips): 0 until
		# the take-off, exactly TAU from the landing on
		var turn := [[11.5, 0.0, "a"], [12.5, 0.04, "a"], [14.0, 0.2, "a"], [16.0, 0.48, "a"], [18.0, 0.75, "a"],
			[19.5, 0.92, "a"], [21.0, 0.99, "a"], [land, 1.0, "f"]]
		c.meta["flip_pitch"] = _turn_meta(turn, n)
		c.meta["flip_hz"] = BWAnimClips.BAKE_HZ
		c.meta["flip_pivot"] = 1.55
	return c


# ------------------------------------------------------------- sweep under

## UNDERHAND SWEEP (D512, one / heavy axes, 40 f). The coil (held by the
## windup) is the reference pose: one hand on the haft, the arm hanging long
## and back, the head of the axe low behind the rear leg pointing down-back;
## the weight sunk on the back foot, turned away, the free arm reaching at
## the target. The dash; the axe swings down past the floor and up through
## the target (hit) to ~120 deg from the floor, the body unwinding up onto
## the front toes; hold; hop home.
static func sweep_under(st: String) -> BWAnimClips.Clip:
	var heavy := st == "heavy"
	var c := _begin("strike_sweep_under", 40, st)
	c.marker("coil", 9).marker("launch", 11).marker("land", 13).marker("hit", 13.5)
	c.marker("hop_start", 26).marker("hop_end", 29).marker("recovered", 35).marker("pose", 9)
	c.meta["engage"] = 1.25 if heavy else 1.05
	# body: turned away to her right and sunk on the back foot, then the unwind
	c.pose(3, { "root": _r(c, Vector3(0, -0.06, -0.03)), "hips": Vector3(0, -0.18, 0), "chest": Vector3(0.04, -0.24, 0.0),
		"head": Vector3(0.02, 0.24, 0.0) })
	c.pose(6, { "root": _r(c, Vector3(0, -0.14, -0.08)), "hips": Vector3(0.02, -0.34, 0.02), "spine": Vector3(0.1, -0.05, 0),
		"chest": Vector3(0.12, -0.44, 0.06), "head": Vector3(-0.04, 0.46, -0.04), "squash": -0.02 })
	c.pose(9, { "root": _r(c, Vector3(0, -0.17, -0.1)), "hips": Vector3(0.03, -0.4, 0.03), "spine": Vector3(0.12, -0.06, 0),
		"chest": Vector3(0.16, -0.52, 0.08), "head": Vector3(-0.06, 0.55, -0.05), "squash": -0.025, "head_sq": 0.02 }, "f")
	c.pose(10, { "root": _r(c, Vector3(0, -0.22, -0.08)), "squash": -0.045, "head_sq": 0.035 })
	c.pose(11, { "root": _r(c, Vector3(0, -0.12, 0.02)), "hips": Vector3(0.06, -0.2, 0.02), "chest": Vector3(0.18, -0.3, 0.04),
		"head": Vector3(-0.04, 0.32, -0.02), "squash": 0.02, "head_sq": -0.01 }, "l")
	c.pose(12.2, { "root": _r(c, Vector3(0, -0.2, 0.08)), "hips": Vector3(0.08, 0.05, 0.0), "chest": Vector3(0.14, 0.05, 0.0),
		"head": Vector3(-0.02, 0.0, 0.0) }, "l")
	c.pose(13.5, { "root": _r(c, Vector3(0, -0.08, 0.1)), "hips": Vector3(-0.02, 0.3, -0.02), "spine": Vector3(-0.08, 0.06, 0),
		"chest": Vector3(-0.16, 0.42, -0.04), "head": Vector3(0.06, -0.36, 0.02), "squash": 0.04, "head_sq": -0.03, "leg_stretch": 0.03 }, "l")
	c.pose(15.5, { "root": _r(c, Vector3(0, -0.04, 0.1)), "hips": Vector3(-0.04, 0.4, -0.03), "spine": Vector3(-0.12, 0.08, 0),
		"chest": Vector3(-0.26, 0.52, -0.05), "head": Vector3(0.12, -0.44, 0.03), "squash": 0.03, "head_sq": -0.02, "leg_stretch": 0.04 })
	c.pose(19, { "root": _r(c, Vector3(0, -0.06, 0.09)), "hips": Vector3(-0.03, 0.36, -0.02), "chest": Vector3(-0.2, 0.46, -0.04),
		"head": Vector3(0.08, -0.4, 0.02), "squash": 0.0, "head_sq": 0.0, "leg_stretch": 0.0 }, "f")
	c.pose(23, { "root": _r(c, Vector3(0, -0.14, 0.07)), "hips": Vector3(0.0, 0.16, 0.0), "spine": Vector3(0.02, 0.0, 0),
		"chest": Vector3(0.02, 0.18, 0.0), "head": Vector3(0.0, -0.14, 0.0) })
	c.pose(26, { "root": _r(c, Vector3(0, -0.05, 0.02)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO,
		"head": Vector3.ZERO, "squash": 0.03, "head_sq": -0.02 })
	c.pose(29, { "root": _r(c, Vector3(0, -0.11, -0.01)), "squash": -0.035, "head_sq": 0.03 }, "f")
	c.pose(32, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.01, "head_sq": 0.0 })
	# the axe (root frame): one hand. Long hafts hang a little higher so the
	# head stays off the floor; the bottom of the arc carries the head low
	# and forward, past the floor
	var dy := 0.2 if heavy else 0.0
	var hk := {
		4.0: [Vector3(-0.3, -0.24, 0.02), Vector3(-0.3, -0.2, -0.93)],
		6.5: [Vector3(-0.32, -0.38 + dy * 0.5, -0.16), Vector3(-0.25, -0.42 + dy, -0.86)],
		9.0: [Vector3(-0.32, -0.44 + dy * 0.5, -0.22), Vector3(-0.3, -0.45 + dy, -0.84)],
		10.0: [Vector3(-0.33, -0.46 + dy * 0.5, -0.12), Vector3(-0.7, -0.45 + dy, -0.5)],
		11.0: [Vector3(-0.32, -0.46 + dy * 0.5, -0.02), Vector3(-0.85, -0.42 + dy, 0.2)],
		12.2: [Vector3(-0.26, -0.36 + dy * 0.3, 0.24), Vector3(-0.45, -0.2 + dy * 0.5, 0.86)],
		13.0: [Vector3(-0.16, -0.06, 0.46), Vector3(0.0, 0.45, 0.9)],
		13.8: [Vector3(-0.12, 0.24, 0.42), Vector3(0.0, 0.85, 0.52)],
		15.5: [Vector3(-0.1, 0.58, 0.28), Vector3(0.0, 0.88, -0.48)],
		19.0: [Vector3(-0.1, 0.56, 0.26), Vector3(0.0, 0.86, -0.5)],
		23.0: [Vector3(-0.16, 0.18, 0.3), Vector3(-0.1, 0.9, 0.3)],
		27.0: [Vector3(-0.2, -0.08, 0.3), Vector3(-0.35, 0.7, 0.6)],
	}
	for f in hk:
		var mode := "f" if float(f) in [9.0, 19.0] else ("l" if float(f) in [11.0, 12.2, 13.0] else "a")
		_hand(c, "hand_r", float(f), hk[f][0], hk[f][1], mode)
	c.key("hand_r_edge", 6, Vector3(0, 0, 1)).key("hand_r_edge", 19, Vector3(0, 0, 1)).key("hand_r_edge", 30, c.base.hand_r_edge)
	c.key("hand_r_pole", 6, Vector3(-1, 0.2, -0.4)).key("hand_r_pole", 12, Vector3(-1, -0.6, 0.0)).key("hand_r_pole", 16, Vector3(-1, -0.7, 0.2))
	c.key("hand_r_pole", 30, c.base.hand_r_pole)
	c.key("smear", 10.5, 0.0).key("smear", 11.5, 1.0).key("smear", 14.5, 1.0).key("smear", 16.5, 0.0)
	c.key("arm_stretch", 8, 0.04).key("arm_stretch", 9, 0.06).key("arm_stretch", 11, 0.02).key("arm_stretch", 13.5, 0.07).key("arm_stretch", 18, 0.0)
	c.key("flat", 5, 0.2).key("flat", 26, 0.3)
	c.lead(10.5, 16.0, 0.85)
	# the free hand: reaching at the target, then thrown back as the axe rises
	if heavy:
		c.key("hand_l_grip", 2, 1.0).key("hand_l_grip", 4, 0.0).key("hand_l_grip", 27, 0.0).key("hand_l_grip", 31, 1.0)
	c.key("hand_l_pos", 5, Vector3(0.22, -0.02, 0.3)).key("hand_l_pos", 9, Vector3(0.24, 0.06, 0.4), "f")
	c.key("hand_l_pos", 13.5, Vector3(0.3, -0.04, -0.06)).key("hand_l_pos", 16, Vector3(0.32, -0.08, -0.26))
	c.key("hand_l_pos", 19, Vector3(0.32, -0.08, -0.26), "f")
	c.key("hand_l_pos", 27, Vector3(0.26, -0.22, 0.04) if not heavy else Vector3(-0.08, -0.12, 0.28))
	c.key("hand_l_pole", 5, Vector3(0.8, -1, -0.2)).key("hand_l_pole", 28, c.base.hand_l_pole)
	# feet: the right foot steps back and takes the weight; off on the dash;
	# a lunge landing, up onto the front toes as the axe rises; hop home
	var g := BWAnimSkill._feet_base(c)
	var fr_back: Vector2 = g[1] + Vector2(-0.04, -0.2)
	var fl1 := Vector2(0.14, 0.4)
	var fr1 := Vector2(-0.14, -0.26)
	_feet_home(c, 0)
	BWAnimStricken._step(c, "r", 2, 6, g[1], fr_back, 0.06)
	_foot(c, "r", 9, fr_back, 0, -0.5, 0, "f")
	_foot(c, "l", 9, g[0], 0.0, 0.3, 0, "f")
	_foot(c, "l", 10.2, g[0], 0.35, 0.3)
	_foot(c, "r", 10.2, fr_back, 0.45, -0.5)
	_air(c, "l", 11.6, Vector3(0.14, 0.18, 0.28), -0.1)
	_air(c, "r", 11.6, Vector3(-0.14, 0.16, -0.24), 0.8)
	_foot(c, "l", 13, fl1, 0, 0.15, 0, "l")
	_foot(c, "r", 13, fr1, 0.6, -0.3, 0, "l")
	_foot(c, "l", 15.5, fl1, 0.35, 0.15)
	_foot(c, "l", 19, fl1, 0.3, 0.15, 0, "f")
	_foot(c, "r", 19, fr1, 0.6, -0.3, 0, "f")
	_foot(c, "l", 23, fl1, 0, 0.15, 0, "f")
	_foot(c, "r", 25, fr1, 0.6, -0.3, 0, "f")
	_air(c, "l", 27.5, Vector3(0.13, 0.17, 0.22), -0.15)
	_air(c, "r", 27.5, Vector3(-0.13, 0.15, -0.12), 0.45)
	_feet_home(c, 29)
	_feet_home(c, 40)
	return c


# ------------------------------------------------------------- throw under

## UNDERHAND THROW (D513, one / heavy axes, 42 f, shot markers). The same
## hanging coil as the sweep (coil 8), the arm swings through and the axe
## leaves the hand rising on `release` (f11, the left foot stepping in; the
## combat flies it end over end). The hand is empty (meta.toss: the held
## weapon is hidden from release to draw), reaches up over the right
## shoulder and draws a fresh axe on `draw` (f20), brings it round to the guard.
static func throw_under(st: String) -> BWAnimClips.Clip:
	var heavy := st == "heavy"
	var c := _begin("strike_throw_under", 42, st, "shot")
	c.marker("coil", 8).marker("release", 11).marker("hit", 12).marker("draw", 20).marker("recovered", 36).marker("pose", 11)
	c.meta["toss"] = [11.0 / BWAnimClips.FPS, 20.0 / BWAnimClips.FPS]
	BWAnimAction._feet_cast(c)
	c.pose(3, { "root": _r(c, Vector3(0, -0.06, -0.03)), "hips": Vector3(0, -0.2, 0), "chest": Vector3(0.04, -0.26, 0.0),
		"head": Vector3(0.02, 0.26, 0.0) })
	c.pose(8, { "root": _r(c, Vector3(0, -0.16, -0.08)), "hips": Vector3(0.03, -0.36, 0.03), "spine": Vector3(0.12, -0.05, 0),
		"chest": Vector3(0.14, -0.46, 0.07), "head": Vector3(-0.06, 0.5, -0.04), "squash": -0.03, "head_sq": 0.02 }, "f")
	c.pose(11, { "root": _r(c, Vector3(0, -0.08, 0.06)), "hips": Vector3(0.0, 0.18, 0.0), "spine": Vector3(-0.04, 0.04, 0),
		"chest": Vector3(-0.1, 0.28, -0.02), "head": Vector3(0.04, -0.2, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(14, { "root": _r(c, Vector3(0, -0.1, 0.06)), "chest": Vector3(-0.06, 0.32, -0.02), "head": Vector3(0.0, -0.24, 0.0),
		"squash": 0.0, "head_sq": 0.0 }, "f")
	# the draw: the chest turns to bring the hand over the shoulder
	c.pose(19, { "root": _r(c, Vector3(0, -0.06, 0.03)), "hips": Vector3(0.0, -0.08, 0.0), "chest": Vector3(-0.08, -0.22, 0.03),
		"head": Vector3(0.0, 0.18, 0.0) })
	c.pose(21, { "root": _r(c, Vector3(0, -0.07, 0.02)), "chest": Vector3(-0.06, -0.26, 0.03), "head": Vector3(0.02, 0.22, 0.0) }, "f")
	c.pose(28, { "root": _r(c, Vector3(0, -0.04, 0.0)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO,
		"head": Vector3(0.0, 0.0, 0.0) })
	var dy := 0.2 if heavy else 0.0
	var hk := {
		4.0: [Vector3(-0.3, -0.24, 0.02), Vector3(-0.3, -0.2, -0.93)],
		8.0: [Vector3(-0.32, -0.42 + dy * 0.5, -0.2), Vector3(-0.3, -0.45 + dy, -0.84)],
		9.5: [Vector3(-0.32, -0.44 + dy * 0.5, -0.02), Vector3(-0.85, -0.42 + dy, 0.2)],
		11.0: [Vector3(-0.2, -0.12, 0.42), Vector3(0.0, 0.55, 0.84)],
		13.0: [Vector3(-0.16, 0.12, 0.44), Vector3(0.0, 0.8, 0.6)],
		16.0: [Vector3(-0.18, 0.3, 0.12), Vector3(0.0, 0.9, -0.4)],
		19.0: [Vector3(-0.16, 0.42, -0.1), Vector3(-0.1, 0.4, -0.9)],
		20.0: [Vector3(-0.16, 0.42, -0.12), Vector3(-0.1, 0.35, -0.93)],
		24.0: [Vector3(-0.26, 0.26, 0.04), Vector3(-0.4, 0.88, 0.25)],
		29.0: [Vector3(-0.28, -0.1, 0.2), Vector3(-0.4, 0.6, 0.7)],
	}
	for f in hk:
		var mode := "f" if float(f) in [8.0, 20.0] else ("l" if float(f) in [9.5, 11.0] else "a")
		_hand(c, "hand_r", float(f), hk[f][0], hk[f][1], mode)
	c.key("hand_r_edge", 6, Vector3(0, 0, 1)).key("hand_r_edge", 13, Vector3(0, 0, 1)).key("hand_r_edge", 30, c.base.hand_r_edge)
	c.key("hand_r_pole", 6, Vector3(-1, 0.2, -0.4)).key("hand_r_pole", 11, Vector3(-1, -0.7, 0.1)).key("hand_r_pole", 19, Vector3(-0.8, 0.6, -0.4))
	c.key("hand_r_pole", 30, c.base.hand_r_pole)
	c.key("smear", 9, 0.0).key("smear", 10, 0.8).key("smear", 11.5, 0.0)
	c.key("arm_stretch", 9, 0.03).key("arm_stretch", 11, 0.08).key("arm_stretch", 14, 0.0)
	c.key("flat", 5, 0.2).key("flat", 28, 0.3)
	if heavy:
		c.key("hand_l_grip", 2, 1.0).key("hand_l_grip", 4, 0.0).key("hand_l_grip", 27, 0.0).key("hand_l_grip", 32, 1.0)
	c.key("hand_l_pos", 5, Vector3(0.22, -0.02, 0.3)).key("hand_l_pos", 8, Vector3(0.24, 0.06, 0.38), "f")
	c.key("hand_l_pos", 12, Vector3(0.3, -0.04, -0.12)).key("hand_l_pos", 15, Vector3(0.3, -0.1, -0.16), "f")
	c.key("hand_l_pos", 22, Vector3(0.24, -0.1, 0.16))
	c.key("hand_l_pos", 30, Vector3(0.26, -0.22, 0.06) if not heavy else Vector3(-0.08, -0.12, 0.28))
	c.key("hand_l_pole", 5, Vector3(0.8, -1, -0.2)).key("hand_l_pole", 30, c.base.hand_l_pole)
	return c


# --------------------------------------------------------------- thrust 2h

## TWO-HANDED THRUST (D514, one: swords, 40 f, the reference body). Both
## fists close together at the right hip, the blade level on the line
## (coil); the dash drives both hands straight in, the arms long, a short
## twist on the hit; drawn back, the left hand lets go, the guard.
static func thrust_2h() -> BWAnimClips.Clip:
	var beats := [0, 4, 9, 11, 13, 14, 18, 22, 27, 30, 35, 40]
	var A := BWAnimAction
	var g := { "hand_l_grip": 1.0 }
	var hands := {
		4.0: A._h(Vector3(-0.2, -0.12, 0.12), Vector3(0.0, 0.3, 0.95), { "hand_l_grip": 0.6 }),
		6.0: A._h(Vector3(-0.16, -0.16, -0.02), Vector3(0.02, 0.06, 1.0), g),
		8.0: A._h(Vector3(-0.15, -0.16, -0.08), Vector3(0.03, 0.04, 1.0), A._m(g, { "hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": Vector3(-1, -0.6, -0.3),
			"hand_l_pole": Vector3(0.8, -1, -0.2), "flat": 0.2, "_mode": "f" })),
		10.0: A._h(Vector3(-0.14, -0.13, -0.04), Vector3(0.03, 0.04, 1.0), g),
		12.0: A._h(Vector3(-0.08, -0.04, 0.26), Vector3(0.0, 0.04, 1.0), A._m(g, { "smear": 0.8, "_mode": "l" })),
		13.0: A._h(Vector3(-0.04, 0.0, 0.46), Vector3(0.0, 0.03, 1.0), A._m(g, { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" })),
		14.0: A._h(Vector3(-0.03, 0.01, 0.54), Vector3(0.0, 0.03, 1.0), A._m(g, { "arm_stretch": 0.1 })),
		16.0: A._h(Vector3(-0.03, 0.01, 0.53), Vector3(0.0, 0.03, 1.0), A._m(g, { "smear": 0.0, "arm_stretch": 0.08 })),
		18.0: A._h(Vector3(-0.05, -0.01, 0.48), Vector3(0.04, 0.0, 1.0), A._m(g, { "arm_stretch": 0.03, "_mode": "f" })),
		22.0: A._h(Vector3(-0.12, -0.08, 0.3), Vector3(0.0, 0.1, 1.0), A._m(g, { "arm_stretch": 0.0 })),
		25.0: A._h(Vector3(-0.22, -0.16, 0.22), Vector3(-0.3, 0.45, 0.84), { "hand_l_grip": 0.0, "hand_l_pos": Vector3(0.26, -0.24, 0.1) }),
	}
	var c := A._melee("strike_thrust_2h", "one", beats, 0.3, hands, 1.2)
	c.key("hand_l_grip", 2, 0.0)
	# a thrust stays on the line: the edge turns a quarter on the hit
	c.key("hand_r_edge", A._warp(14.0, beats), Vector3(0, 1, 0)).key("hand_r_edge", A._warp(18.0, beats), Vector3(-0.7, 0.7, 0))
	c.key("hand_r_edge", A._warp(25.0, beats), Vector3(0, 0.3, 1))
	# low over the hip: she sits into it
	c.key("root", A._warp(8.0, beats), _r(c, Vector3(0, -0.14, -0.06)), "f")
	return c


# -------------------------------------------------------------------- lunge

## FENCING LUNGE (D515, one: swords; spear: lance, javelin, trident; 42 f).
## En garde side-on, the right foot and the point leading, the weapon level
## by the hip (coil 7, the off arm raised behind). A hop in (launch..land,
## the cutscene's dash: a balestra), then the lunge: the right foot reaches
## far forward, the left leg straightens behind, the hips drop between, the
## arm drives the point out a touch above level (hit, f17) and the off arm is
## flung back straight (the lance's shield arm swings back with it, D520).
## Held, the front foot pulls back, the hop home, the guard.
static func lunge(st: String) -> BWAnimClips.Clip:
	var spear := st == "spear"
	var c := _begin("strike_lunge", 42, st)
	c.marker("coil", 7).marker("launch", 9).marker("land", 11.5).marker("hit", 17)
	c.marker("hop_start", 30).marker("hop_end", 33).marker("recovered", 38).marker("pose", 17)
	c.meta["engage"] = 1.55 if spear else 1.3
	# body: side-on (+yaw: the right shoulder leads), the head on the target
	c.pose(3, { "root": _r(c, Vector3(0, -0.08, -0.02)), "hips": Vector3(0, 0.36, 0), "chest": Vector3(0.0, 0.42, 0.0),
		"head": Vector3(0.02, -0.5, 0.0) })
	c.pose(7, { "root": _r(c, Vector3(0, -0.15, -0.03)), "hips": Vector3(0.0, 0.62, 0), "spine": Vector3(0.04, 0.06, 0),
		"chest": Vector3(0.0, 0.7, -0.02), "head": Vector3(0.0, -0.95, 0.04), "squash": -0.015 }, "f")
	c.pose(8, { "root": _r(c, Vector3(0, -0.19, -0.03)), "squash": -0.035, "head_sq": 0.03 })
	c.pose(10, { "root": _r(c, Vector3(0, -0.06, 0.0)), "squash": 0.02, "head_sq": -0.015 })
	c.pose(11.5, { "root": _r(c, Vector3(0, -0.18, 0.0)), "squash": -0.03, "head_sq": 0.025 }, "l")
	c.pose(13, { "root": _r(c, Vector3(0, -0.15, 0.02)), "squash": 0.0, "head_sq": 0.0 })
	# the lunge: the hips travel out over the front knee and drop
	c.pose(15.5, { "root": _r(c, Vector3(0, -0.24, 0.26)), "hips": Vector3(0.04, 0.66, 0), "chest": Vector3(0.1, 0.76, -0.03),
		"head": Vector3(-0.06, -1.0, 0.04) }, "l")
	c.pose(17, { "root": _r(c, Vector3(0, -0.33, 0.35)), "hips": Vector3(0.06, 0.7, 0), "spine": Vector3(0.1, 0.06, 0),
		"chest": Vector3(0.14, 0.8, -0.04), "head": Vector3(-0.1, -1.02, 0.05), "squash": -0.04, "head_sq": 0.035 })
	c.pose(19, { "root": _r(c, Vector3(0, -0.34, 0.36)), "squash": -0.02, "head_sq": 0.01 })
	c.pose(23, { "root": _r(c, Vector3(0, -0.32, 0.34)), "chest": Vector3(0.12, 0.78, -0.04), "squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(27, { "root": _r(c, Vector3(0, -0.15, 0.04)), "hips": Vector3(0.0, 0.5, 0), "spine": Vector3(0.03, 0.04, 0),
		"chest": Vector3(0.02, 0.56, -0.02), "head": Vector3(0.0, -0.75, 0.03) })
	c.pose(30, { "root": _r(c, Vector3(0, -0.06, 0.01)), "hips": Vector3(0.0, 0.2, 0), "spine": Vector3.ZERO,
		"chest": Vector3(0.0, 0.22, 0.0), "head": Vector3(0.0, -0.28, 0.0), "squash": 0.03, "head_sq": -0.02 })
	c.pose(33, { "root": _r(c, Vector3(0, -0.11, -0.01)), "hips": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3.ZERO,
		"squash": -0.035, "head_sq": 0.03 }, "f")
	c.pose(36, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.01, "head_sq": 0.0 })
	# the weapon: level by the hip in the guard, out a touch above level on the hit
	var hk := {
		4.0: [Vector3(-0.2, -0.22, 0.14), Vector3(-0.1, 0.2, 0.97)],
		7.0: [Vector3(-0.14, -0.3, 0.1), Vector3(0.0, 0.04, 1.0)],
		11.5: [Vector3(-0.13, -0.29, 0.12), Vector3(0.0, 0.05, 1.0)],
		13.5: [Vector3(-0.12, -0.24, 0.16), Vector3(0.0, 0.06, 1.0)],
		15.5: [Vector3(-0.08, -0.06, 0.4), Vector3(0.0, 0.1, 0.99)],
		17.0: [Vector3(-0.05, 0.06, 0.66), Vector3(0.0, 0.13, 0.99)],
		19.0: [Vector3(-0.05, 0.06, 0.65), Vector3(0.0, 0.12, 0.99)],
		23.0: [Vector3(-0.06, 0.04, 0.62), Vector3(0.0, 0.1, 0.99)],
		27.0: [Vector3(-0.14, -0.2, 0.3), Vector3(-0.05, 0.25, 0.97)],
	}
	if spear:
		# the lance is long and level under the arm: the butt behind the elbow
		for f in hk:
			hk[f][0] = (hk[f][0] as Vector3) + Vector3(-0.02, 0.06, 0.0)
	for f in hk:
		var mode := "f" if float(f) in [7.0, 23.0] else ("l" if float(f) in [15.5] else "a")
		_hand(c, "hand_r", float(f), hk[f][0], hk[f][1], mode)
	c.key("hand_r_edge", 6, Vector3(0, 1, 0)).key("hand_r_edge", 24, Vector3(0, 1, 0)).key("hand_r_edge", 32, c.base.hand_r_edge)
	c.key("hand_r_pole", 6, Vector3(-1, -0.7, -0.2)).key("hand_r_pole", 17, Vector3(-0.6, -1, 0.0)).key("hand_r_pole", 30, c.base.hand_r_pole)
	c.key("smear", 14.5, 0.0).key("smear", 15.5, 0.9).key("smear", 17.5, 0.9).key("smear", 19, 0.0)
	c.key("arm_stretch", 15, 0.0).key("arm_stretch", 17, 0.1).key("arm_stretch", 23, 0.08).key("arm_stretch", 27, 0.0)
	c.key("flat", 5, 0.25).key("flat", 28, 0.3)
	# the off arm: raised behind in the guard, flung back straight on the lunge
	c.key("hand_l_pos", 4, Vector3(0.22, 0.02, -0.04)).key("hand_l_pos", 7, Vector3(0.18, 0.24, -0.2), "f")
	c.key("hand_l_pos", 13.5, Vector3(0.18, 0.22, -0.22))
	c.key("hand_l_pos", 17, Vector3(0.16, 0.02, -0.52), "l").key("hand_l_pos", 23, Vector3(0.16, 0.04, -0.5), "f")
	c.key("hand_l_pos", 28, Vector3(0.24, -0.12, -0.1))
	c.key("hand_l_pole", 4, Vector3(0.6, -1, -0.2)).key("hand_l_pole", 7, Vector3(0.5, -0.6, 0.3)).key("hand_l_pole", 17, Vector3(0.6, -0.8, 0.4))
	c.key("hand_l_pole", 30, c.base.hand_l_pole)
	if spear:
		# D520 (the author): the shield arm swings back with the lunge, out of the guard
		c.shield(0, 0.0, 1.0).shield(9, 0.1, 1.0).shield(14, 0.0, 0.4).shield(16.5, 0.0, 0.0, "f").shield(24, 0.0, 0.0, "f")
		c.shield(29, 0.0, 1.0).shield(42, 0.0, 1.0)
	# feet: en garde (the right foot forward pointing at the target, the left
	# back and turned out), the hop, the long step, back, the hop home
	var g := BWAnimSkill._feet_base(c)
	var fr_g := Vector2(-0.1, 0.18)
	var fl_g := Vector2(0.1, -0.18)
	var fr_l := Vector2(-0.08, 0.76)
	_feet_home(c, 0)
	BWAnimStricken._step(c, "r", 1, 5, g[1], fr_g, 0.06)
	_foot(c, "r", 5, fr_g, 0, 0.0, 0, "f")
	BWAnimStricken._step(c, "l", 2.5, 6.5, g[0], fl_g, 0.05)
	_foot(c, "l", 6.5, fl_g, 0, 0.9, 0, "f")
	_foot(c, "l", 8, fl_g, 0, 0.9, 0, "f")
	_foot(c, "r", 8, fr_g, 0, 0.0, 0, "f")
	_foot(c, "l", 8.8, fl_g, 0.35, 0.9)
	_foot(c, "r", 8.8, fr_g, 0.35, 0.0)
	_air(c, "l", 10.2, Vector3(0.1, 0.1, -0.1), 0.3)
	_air(c, "r", 10.2, Vector3(-0.1, 0.11, 0.2), -0.1)
	_foot(c, "l", 11.5, fl_g, 0, 0.9, 0, "f")
	_foot(c, "r", 11.5, fr_g, 0, 0.0, 0, "f")
	_foot(c, "r", 13, fr_g, 0, 0.0, 0, "f")
	_foot(c, "r", 14.5, fr_g.lerp(fr_l, 0.5), -0.1, 0.0, 0.08)
	_foot(c, "r", 16.3, fr_l, -0.3, 0.0, 0.0, "l")
	_foot(c, "r", 17.2, fr_l, 0, 0.0, 0, "f")
	_foot(c, "l", 13, fl_g, 0, 0.9, 0, "f")
	_foot(c, "l", 24, fl_g, 0, 0.9, 0, "f")
	_foot(c, "r", 24, fr_l, 0, 0.0, 0, "f")
	_foot(c, "r", 25.5, fr_l.lerp(fr_g, 0.5), 0.2, 0.0, 0.07)
	_foot(c, "r", 27.5, fr_g, 0, 0.0, 0, "f")
	_foot(c, "l", 29.5, fl_g, 0.3, 0.9)
	_foot(c, "r", 29.5, fr_g, 0.3, 0.0)
	_air(c, "l", 31.5, Vector3(0.12, 0.13, -0.02), 0.2)
	_air(c, "r", 31.5, Vector3(-0.12, 0.12, 0.06), 0.1)
	_feet_home(c, 33)
	_feet_home(c, 42)
	return c


# ----------------------------------------------------------------- flourish

## FLOURISH (D516, pair, 40 f). Down into a crouch with the arms crossed at
## the chest, blades out past the shoulders (coil 8); springs up and forward
## (launch 10), the arms uncross and slash out and up, the blades smearing
## two arcs, until both are over the head at the top (hit 15); lands (land
## 18) with the blades coming down to the ready, hop home.
static func flourish() -> BWAnimClips.Clip:
	var c := _begin("strike_flourish", 40, "pair")
	c.marker("coil", 8).marker("launch", 10).marker("hit", 15).marker("land", 18)
	c.marker("hop_start", 27).marker("hop_end", 30).marker("recovered", 35).marker("pose", 15)
	c.meta["engage"] = 0.95
	c.pose(3, { "root": _r(c, Vector3(0, -0.1, -0.02)), "spine": Vector3(0.12, 0, 0), "chest": Vector3(0.1, 0, 0), "head": Vector3(-0.06, 0, 0) })
	c.pose(8, { "root": _r(c, Vector3(0, -0.3, -0.02)), "spine": Vector3(0.34, 0, 0), "chest": Vector3(0.24, 0, 0),
		"head": Vector3(-0.34, 0, 0), "squash": -0.05, "head_sq": 0.04 }, "f")
	c.pose(9, { "root": _r(c, Vector3(0, -0.33, -0.01)), "squash": -0.065, "head_sq": 0.05 })
	c.pose(10, { "root": _r(c, Vector3(0, 0.02, 0.04)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(-0.08, 0, 0),
		"head": Vector3(-0.16, 0, 0), "squash": 0.06, "head_sq": -0.04, "leg_stretch": 0.05 }, "l")
	c.pose(12.5, { "root": _r(c, Vector3(0, 0.36, 0.06)), "spine": Vector3(-0.12, 0, 0), "chest": Vector3(-0.24, 0, 0),
		"head": Vector3(-0.2, 0, 0), "squash": 0.03, "head_sq": -0.01, "leg_stretch": 0.0 })
	c.pose(15, { "root": _r(c, Vector3(0, 0.44, 0.06)), "spine": Vector3(-0.18, 0, 0), "chest": Vector3(-0.32, 0, 0),
		"head": Vector3(-0.26, 0, 0), "squash": 0.04, "head_sq": -0.03 }, "f")
	c.pose(16.5, { "root": _r(c, Vector3(0, 0.26, 0.06)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(-0.1, 0, 0),
		"head": Vector3(-0.1, 0, 0), "squash": 0.0, "head_sq": 0.0 })
	c.pose(18, { "root": _r(c, Vector3(0, -0.24, 0.08)), "spine": Vector3(0.24, 0, 0), "chest": Vector3(0.16, 0.0, 0),
		"head": Vector3(-0.16, 0, 0), "squash": -0.06, "head_sq": 0.05 }, "l")
	c.pose(20, { "root": _r(c, Vector3(0, -0.26, 0.08)), "squash": -0.04, "head_sq": 0.03 })
	c.pose(24, { "root": _r(c, Vector3(0, -0.2, 0.07)), "spine": Vector3(0.14, 0, 0), "chest": Vector3(0.06, 0.0, 0),
		"head": Vector3(-0.08, 0, 0), "squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(27, { "root": _r(c, Vector3(0, -0.05, 0.02)), "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3.ZERO,
		"squash": 0.03, "head_sq": -0.02 })
	c.pose(30, { "root": _r(c, Vector3(0, -0.11, -0.01)), "squash": -0.035, "head_sq": 0.03 }, "f")
	c.pose(33, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.01, "head_sq": 0.0 })
	# the blades: [pos, aim] per hand, mirrored (the right hand crosses to her left)
	var hk := {
		4.0: [Vector3(-0.08, -0.08, 0.24), Vector3(0.3, 0.5, 0.8)],
		8.0: [Vector3(0.1, 0.0, 0.2), Vector3(0.75, 0.6, 0.25)],
		10.0: [Vector3(0.04, 0.06, 0.26), Vector3(0.55, 0.6, 0.6)],
		11.5: [Vector3(-0.22, 0.12, 0.4), Vector3(-0.35, 0.3, 0.88)],
		13.0: [Vector3(-0.32, 0.32, 0.3), Vector3(-0.55, 0.75, 0.35)],
		15.0: [Vector3(-0.16, 0.62, 0.06), Vector3(-0.2, 0.95, -0.2)],
		16.5: [Vector3(-0.16, 0.58, 0.06), Vector3(-0.2, 0.9, -0.3)],
		18.0: [Vector3(-0.3, 0.1, 0.3), Vector3(-0.4, 0.3, 0.86)],
		21.0: [Vector3(-0.3, -0.02, 0.3), Vector3(-0.35, 0.4, 0.85)],
		27.0: [Vector3(-0.24, -0.12, 0.26), Vector3(-0.2, 0.4, 0.9)],
	}
	for f in hk:
		var mode := "f" if float(f) in [8.0, 15.0, 21.0] else ("l" if float(f) in [11.5, 13.0] else "a")
		var p: Vector3 = hk[f][0]
		var aim: Vector3 = hk[f][1]
		_hand(c, "hand_r", float(f), p, aim, mode)
		# the left hand mirrors it, a touch behind the right (and under it in the cross)
		var pl := Vector3(-p.x, p.y + (0.04 if float(f) <= 10.0 else 0.0), p.z - (0.03 if float(f) <= 10.0 else 0.0))
		_hand(c, "hand_l", float(f) + (0.4 if float(f) > 10.0 and float(f) < 16.0 else 0.0), pl, Vector3(-aim.x, aim.y, aim.z), mode)
	c.key("hand_r_edge", 8, Vector3(0, 1, 0)).key("hand_r_edge", 24, c.base.hand_r_edge)
	c.key("hand_l_edge", 8, Vector3(0, 1, 0)).key("hand_l_edge", 24, c.base.hand_l_edge)
	c.key("hand_r_pole", 8, Vector3(-0.6, -1, -0.2)).key("hand_r_pole", 15, Vector3(-1, 0.0, -0.3)).key("hand_r_pole", 24, c.base.hand_r_pole)
	c.key("hand_l_pole", 8, Vector3(0.6, -1, -0.2)).key("hand_l_pole", 15, Vector3(1, 0.0, -0.3)).key("hand_l_pole", 24, c.base.hand_l_pole)
	c.key("smear", 10.5, 0.0).key("smear", 11.5, 1.0).key("smear", 15, 1.0).key("smear", 16.5, 0.0)
	c.key("arm_stretch", 10, 0.0).key("arm_stretch", 13, 0.07).key("arm_stretch", 15, 0.06).key("arm_stretch", 18, 0.0)
	c.key("flat", 6, 0.4).key("flat", 26, 0.8)
	c.lead(10.5, 15.5, 0.8, "hand_r")
	c.lead(11.0, 16.0, 0.8, "hand_l")
	var g := BWAnimSkill._feet_base(c)
	var fl1 := Vector2(0.15, 0.3)
	var fr1 := Vector2(-0.14, -0.2)
	_feet_home(c, 0)
	_foot(c, "l", 8, g[0], 0, 0.3, 0, "f")
	_foot(c, "r", 8, g[1], 0, -0.3, 0, "f")
	_foot(c, "l", 9.5, g[0], 0.45, 0.25)
	_foot(c, "r", 9.5, g[1], 0.5, -0.25)
	_air(c, "l", 12.5, Vector3(0.12, 0.4, -0.04), 0.7)
	_air(c, "r", 12.5, Vector3(-0.12, 0.44, -0.14), 0.9)
	_air(c, "l", 15, Vector3(0.12, 0.46, -0.02), 0.7, "f")
	_air(c, "r", 15, Vector3(-0.12, 0.5, -0.16), 0.9, "f")
	_air(c, "l", 17, Vector3(0.14, 0.2, 0.26), -0.1)
	_air(c, "r", 17, Vector3(-0.13, 0.14, -0.16), 0.6)
	_foot(c, "l", 18, fl1, 0, 0.15, 0, "l")
	_foot(c, "r", 18, fr1, 0.55, -0.3, 0, "l")
	_foot(c, "l", 25, fl1, 0, 0.15, 0, "f")
	_foot(c, "r", 25, fr1, 0.55, -0.3, 0, "f")
	_air(c, "l", 28.5, Vector3(0.13, 0.17, 0.22), -0.15)
	_air(c, "r", 28.5, Vector3(-0.13, 0.15, -0.12), 0.45)
	_feet_home(c, 30)
	_feet_home(c, 40)
	return c


# ----------------------------------------------------------------- backstab

## BACKSTAB (D517, pair, 44 f). Down low, coiled forward, the blades held
## back along the forearms (coil 6). The slither (launch 8 .. land 16:
## BWBackstab moves the root on an S round to the target's back; the feet
## skid with it, the hips and chest weave), rises behind it with the right
## blade high and drives it down into the back (hit 19), a beat, pulls it
## out, sinks and slithers home (slide_back 26 .. slide_home 33), rises.
static func backstab() -> BWAnimClips.Clip:
	var c := _begin("strike_backstab", 44, "pair")
	c.marker("coil", 6).marker("launch", 8).marker("land", 16).marker("hit", 19)
	c.marker("slide_back", 26).marker("slide_home", 33).marker("recovered", 40).marker("pose", 19)
	c.meta["engage"] = 0.9
	c.meta["backstab"] = true
	c.pose(3, { "root": _r(c, Vector3(0, -0.14, -0.02)), "spine": Vector3(0.2, 0, 0), "chest": Vector3(0.14, 0, 0), "head": Vector3(-0.14, 0, 0),
		"squash": -0.02 })
	c.pose(6, { "root": _r(c, Vector3(0, -0.38, 0.02)), "spine": Vector3(0.52, 0, 0), "chest": Vector3(0.26, 0, 0),
		"head": Vector3(-0.5, 0, 0), "squash": -0.04, "head_sq": 0.03 }, "f")
	# the slither: low, the hips and chest weaving against each other
	var weave := [[9.0, 1.0], [11.5, -1.0], [14.0, 1.0]]
	for w in weave:
		var s: float = w[1]
		c.pose(float(w[0]), { "root": _r(c, Vector3(0.04 * s, -0.42, 0.04)), "hips": Vector3(0.0, 0.3 * s, -0.08 * s),
			"spine": Vector3(0.5, -0.1 * s, 0.0), "chest": Vector3(0.24, -0.32 * s, 0.06 * s), "head": Vector3(-0.5, 0.3 * s, 0.0),
			"squash": -0.03 })
	c.pose(16, { "root": _r(c, Vector3(0, -0.3, 0.04)), "hips": Vector3.ZERO, "spine": Vector3(0.38, 0, 0), "chest": Vector3(0.2, 0, 0),
		"head": Vector3(-0.36, 0, 0), "squash": -0.02 })
	# up behind it, the blade high
	c.pose(17.5, { "root": _r(c, Vector3(0, -0.1, 0.04)), "spine": Vector3(0.0, 0, 0), "chest": Vector3(-0.16, 0.18, 0),
		"head": Vector3(0.1, -0.1, 0), "squash": 0.04, "head_sq": -0.03 })
	c.pose(19, { "root": _r(c, Vector3(0, -0.2, 0.08)), "spine": Vector3(0.24, 0, 0), "chest": Vector3(0.3, -0.14, 0.02),
		"head": Vector3(0.18, 0.06, 0), "squash": -0.05, "head_sq": 0.045 }, "l")
	c.pose(22, { "root": _r(c, Vector3(0, -0.21, 0.08)), "chest": Vector3(0.28, -0.12, 0.02), "squash": -0.02, "head_sq": 0.01 }, "f")
	c.pose(24.5, { "root": _r(c, Vector3(0, -0.16, 0.04)), "spine": Vector3(0.1, 0, 0), "chest": Vector3(-0.08, 0.1, 0),
		"head": Vector3(0.0, 0, 0), "squash": 0.0, "head_sq": 0.0 })
	for w in [[27.5, -1.0], [30.5, 1.0]]:
		var s: float = w[1]
		c.pose(float(w[0]), { "root": _r(c, Vector3(0.04 * s, -0.38, 0.02)), "hips": Vector3(0.0, 0.26 * s, -0.06 * s),
			"spine": Vector3(0.42, -0.08 * s, 0.0), "chest": Vector3(0.2, -0.28 * s, 0.05 * s), "head": Vector3(-0.42, 0.26 * s, 0.0),
			"squash": -0.02 })
	c.pose(33, { "root": _r(c, Vector3(0, -0.24, 0.0)), "hips": Vector3.ZERO, "spine": Vector3(0.24, 0, 0), "chest": Vector3(0.12, 0, 0),
		"head": Vector3(-0.2, 0, 0), "squash": -0.03, "head_sq": 0.02 })
	c.pose(37, { "root": _r(c, Vector3(0, -0.04, 0.0)), "spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3.ZERO,
		"squash": 0.01, "head_sq": 0.0 })
	# the blades: laid back along the forearms on the slither, the right one
	# raised point-down over the back and driven in, the left held low
	var r := {
		4.0: [Vector3(-0.24, -0.16, 0.18), Vector3(-0.2, -0.3, -0.93)],
		6.0: [Vector3(-0.24, -0.22, 0.14), Vector3(-0.15, -0.35, -0.92)],
		16.0: [Vector3(-0.22, -0.18, 0.18), Vector3(-0.1, -0.3, -0.95)],
		17.5: [Vector3(-0.14, 0.34, 0.12), Vector3(0.0, -0.3, 0.95)],
		19.0: [Vector3(-0.06, -0.06, 0.4), Vector3(0.05, -0.75, 0.66)],
		22.0: [Vector3(-0.06, -0.08, 0.39), Vector3(0.05, -0.75, 0.66)],
		24.5: [Vector3(-0.16, 0.1, 0.2), Vector3(-0.1, 0.3, 0.95)],
		27.0: [Vector3(-0.24, -0.2, 0.16), Vector3(-0.15, -0.35, -0.92)],
		33.0: [Vector3(-0.24, -0.2, 0.16), Vector3(-0.15, -0.35, -0.92)],
	}
	var l := {
		4.0: [Vector3(0.24, -0.16, 0.18), Vector3(0.2, -0.3, -0.93)],
		6.0: [Vector3(0.24, -0.22, 0.14), Vector3(0.15, -0.35, -0.92)],
		16.0: [Vector3(0.22, -0.18, 0.18), Vector3(0.1, -0.3, -0.95)],
		19.0: [Vector3(0.22, -0.06, 0.24), Vector3(0.3, 0.3, 0.9)],
		24.5: [Vector3(0.22, -0.08, 0.22), Vector3(0.3, 0.3, 0.9)],
		27.0: [Vector3(0.24, -0.2, 0.16), Vector3(0.15, -0.35, -0.92)],
		33.0: [Vector3(0.24, -0.2, 0.16), Vector3(0.15, -0.35, -0.92)],
	}
	for f in r:
		_hand(c, "hand_r", float(f), r[f][0], r[f][1], "l" if float(f) == 17.5 else ("f" if float(f) in [6.0, 22.0] else "a"))
	for f in l:
		_hand(c, "hand_l", float(f), l[f][0], l[f][1], "f" if float(f) in [6.0] else "a")
	c.key("hand_r_edge", 6, Vector3(0, 1, 0)).key("hand_r_edge", 36, c.base.hand_r_edge)
	c.key("hand_l_edge", 6, Vector3(0, 1, 0)).key("hand_l_edge", 36, c.base.hand_l_edge)
	c.key("hand_r_pole", 6, Vector3(-0.8, -0.6, -0.4)).key("hand_r_pole", 17.5, Vector3(-1, 0.3, -0.4)).key("hand_r_pole", 19, Vector3(-1, 0.2, 0.0))
	c.key("hand_r_pole", 36, c.base.hand_r_pole)
	c.key("hand_l_pole", 6, Vector3(0.8, -0.6, -0.4)).key("hand_l_pole", 36, c.base.hand_l_pole)
	c.key("smear", 17.6, 0.0).key("smear", 18.4, 1.0).key("smear", 19.2, 0.8).key("smear", 20.5, 0.0)
	c.key("arm_stretch", 18, 0.0).key("arm_stretch", 19, 0.07).key("arm_stretch", 22, 0.04).key("arm_stretch", 24, 0.0)
	c.key("flat", 6, 0.7).key("flat", 36, 0.8)
	# feet: a low, wide stance that skids with the root on both slithers
	var g := BWAnimSkill._feet_base(c)
	var fl1: Vector2 = g[0] + Vector2(0.06, 0.12)
	var fr1: Vector2 = g[1] + Vector2(-0.06, -0.12)
	_feet_home(c, 0)
	BWAnimStricken._step(c, "l", 1, 4.5, g[0], fl1, 0.05)
	BWAnimStricken._step(c, "r", 2, 5.5, g[1], fr1, 0.05)
	_foot(c, "l", 6, fl1, 0, 0.3, 0, "f")
	_foot(c, "r", 6, fr1, 0.3, -0.35, 0, "f")
	_foot(c, "l", 33, fl1, 0, 0.3, 0, "f")
	_foot(c, "r", 33, fr1, 0.3, -0.35, 0, "f")
	BWAnimStricken._step(c, "r", 34, 37, fr1, g[1], 0.05)
	BWAnimStricken._step(c, "l", 35, 38.5, fl1, g[0], 0.05)
	_feet_home(c, 44)
	c.skid = [[7.5, 16.5], [25.5, 33.5]]
	return c


# ---------------------------------------------------------------- jump shot

## JUMP SHOT (D518, bow, 46 f). The nock on the ground (f6, side-on), a dip
## and the spring (launch 11) drawing on the way up, full draw at the top
## (coil 15), loosed at the apex (release 17), the follow-through on the way
## down, the landing (land 22) with a squash, the bow lowered.
static func shot_jump() -> BWAnimClips.Clip:
	var c := BWAnimBow._new("shot_jump", 46)
	var y := BWAnimBow.Cycle.new()
	y.nock = 6.0
	y.anchor = 15.0
	y.release = 17.0
	y.pitch = -0.06
	c.marker("nock", 6).marker("launch", 11).marker("coil", 15).marker("release", 17).marker("hit", 18).marker("land", 22)
	c.marker("recovered", 40).marker("pose", 16)
	c.pose(2, { "head": Vector3(0.0, 0.5, 0.0) })
	BWAnimAction._side_on(c, 4.5, 0.7)
	BWAnimBow._body(c, y, 0.0)
	BWAnimBow._cycle(c, y, true)
	BWAnimBow._settle(c, y, 27.0, 34.0, 0.0)
	BWAnimBow._feet(c, 5.0, 32.0, 46.0)
	BWAnimBow._meta(c, [[y.nock, y.release]])
	# the jump: the root's height on top of the cycle's own keys
	var arr: Array = c.keys["root"]
	var frames := float(c.frames)
	var hop := [[0.0, 0.0, "f"], [8.0, 0.0, "f"], [10.0, -0.12, "a"], [11.0, 0.03, "l"], [13.5, 0.36, "a"], [16.0, 0.44, "f"],
		[18.0, 0.41, "a"], [20.5, 0.16, "a"], [22.0, -0.1, "l"], [24.0, -0.06, "a"], [27.0, 0.0, "f"], [46.0, 0.0, "f"]]
	c.proc("root", func(f: float) -> Variant:
		var v: Vector3 = BWAnimClips.eval_keys(arr, f, false, frames)
		return v + Vector3(0, float(BWAnimClips.eval_keys(hop, f, false, frames)), 0))
	c.pose(10, { "squash": -0.04, "head_sq": 0.03 })
	c.pose(11, { "squash": 0.05, "head_sq": -0.03, "leg_stretch": 0.05 }, "l")
	c.pose(14, { "squash": 0.0, "head_sq": 0.0, "leg_stretch": 0.0 })
	c.pose(22, { "squash": -0.06, "head_sq": 0.05 }, "l")
	c.pose(25, { "squash": 0.0, "head_sq": 0.0 })
	# feet: the side-on stance from BWAnimBow._feet, off the floor 11..22
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr2 := Vector2(-0.16, -0.22)
	_foot(c, "l", 9, fl, 0, 0.22, 0, "f")
	_foot(c, "r", 9, fr2, 0, -0.72, 0, "f")
	_foot(c, "l", 10.6, fl, 0.45, 0.22)
	_foot(c, "r", 10.6, fr2, 0.5, -0.72)
	c.pose(13.5, { "foot_l_pos": Vector3(0.13, 0.36, 0.02), "foot_l_rot": Vector3(0.6, 0.22, 0),
		"foot_r_pos": Vector3(-0.15, 0.42, -0.22), "foot_r_rot": Vector3(0.9, -0.72, 0) })
	c.pose(17, { "foot_l_pos": Vector3(0.13, 0.42, 0.0), "foot_l_rot": Vector3(0.6, 0.22, 0),
		"foot_r_pos": Vector3(-0.15, 0.48, -0.24), "foot_r_rot": Vector3(0.9, -0.72, 0) }, "f")
	c.pose(20.5, { "foot_l_pos": BWAnimClips.ankle(fl, 0.3, 0.22, 0.06), "foot_l_rot": Vector3(0.3, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr2, 0.5, -0.72, 0.1), "foot_r_rot": Vector3(0.5, -0.72, 0) })
	_foot(c, "l", 22, fl, 0, 0.22, 0, "l")
	_foot(c, "r", 22, fr2, 0, -0.72, 0, "l")
	_foot(c, "l", 26, fl, 0, 0.22, 0, "f")
	_foot(c, "r", 30, fr2, 0, -0.72, 0, "f")
	return c


# ------------------------------------------------------------------ tempest

## TEMPEST (D519, staff, 54 f; a cast: coil 9 is the channel's pose). The
## cast's gather; then she rises off the floor (f12-f22, the feet hanging,
## toes pointed), turning once round (meta spin_yaw, 0 -> TAU by f24) with
## the staff raised high and circling; at the top the staff is thrust at
## the target (release 26); she hangs a beat and settles back down (f40).
static func cast_tempest() -> BWAnimClips.Clip:
	var base := BWAnimAction.cast("staff")
	var c := BWAnimClips.new_clip("cast_tempest", 54, false, "staff")
	c.marker("coil", 9).marker("release", 26).marker("hit", 27).marker("recovered", 48).marker("pose", 26)
	c.meta = { "hand_frame": "root", "kind": "cast" }
	# the gather is the cast's own, frame for frame, up to its coil
	for ch in base.keys:
		for k in base.keys[ch]:
			if float(k[0]) <= 9.0 or float(k[0]) == 0.0:
				c.key(ch, float(k[0]), k[1], str(k[2]))
	c.at_base(54, BODY + _hand_chans())
	# the rise and the turn, the staff raised high over the head
	var up := 0.22
	c.pose(13, { "root": _r(c, Vector3(0, 0.06, 0.0)), "hips": Vector3(0.0, 0.0, 0), "spine": Vector3(-0.04, 0, 0),
		"chest": Vector3(-0.12, 0.0, 0.0), "head": Vector3(-0.12, 0.0, 0.0), "squash": 0.02 })
	c.pose(18, { "root": _r(c, Vector3(0, up, 0.0)), "chest": Vector3(-0.16, 0.0, 0.0), "head": Vector3(-0.16, 0.0, 0.0), "squash": 0.0 })
	c.pose(24, { "root": _r(c, Vector3(0, up + 0.04, 0.0)), "hips": Vector3(0.0, -0.18, 0), "chest": Vector3(-0.18, -0.24, 0.02),
		"head": Vector3(-0.08, 0.26, 0.0) }, "f")
	c.pose(26, { "root": _r(c, Vector3(0, up + 0.02, 0.06)), "hips": Vector3(0.04, 0.12, 0), "spine": Vector3(0.08, 0, 0),
		"chest": Vector3(0.12, 0.18, -0.02), "head": Vector3(-0.04, -0.12, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(28, { "root": _r(c, Vector3(0, up + 0.03, 0.06)), "chest": Vector3(0.14, 0.2, -0.02), "squash": 0.0, "head_sq": 0.0 })
	c.pose(34, { "root": _r(c, Vector3(0, up, 0.04)), "chest": Vector3(0.08, 0.12, -0.01), "head": Vector3(-0.02, -0.08, 0.0) }, "f")
	c.pose(40, { "root": _r(c, Vector3(0, -0.1, 0.0)), "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3(0.02, 0.0, 0.0),
		"head": Vector3(0.02, 0.0, 0.0), "squash": -0.04, "head_sq": 0.03 })
	c.pose(44, { "root": _r(c, Vector3(0, -0.02, 0.0)), "squash": 0.01, "head_sq": 0.0 })
	# the staff: overhead, circling with the turn, then thrust at the target
	var hk := {
		13.0: [Vector3(-0.3, 0.5, 0.0), Vector3(-0.25, 0.95, -0.1)],
		16.0: [Vector3(-0.28, 0.6, 0.02), Vector3(-0.2, 0.97, 0.05)],
		20.0: [Vector3(-0.27, 0.62, -0.02), Vector3(-0.18, 0.96, -0.1)],
		24.0: [Vector3(-0.28, 0.5, -0.08), Vector3(-0.3, 0.75, -0.6)],
		25.2: [Vector3(-0.24, 0.52, 0.08), Vector3(-0.2, 0.92, 0.2)],
		26.0: [Vector3(-0.1, 0.36, 0.42), Vector3(0.0, 0.55, 0.83)],
		28.0: [Vector3(-0.1, 0.32, 0.46), Vector3(0.0, 0.5, 0.87)],
		34.0: [Vector3(-0.1, 0.3, 0.45), Vector3(0.0, 0.52, 0.85)],
		42.0: [Vector3(-0.34, -0.08, -0.04), Vector3(-0.2, 0.88, -0.45)],
	}
	for f in hk:
		_hand(c, "hand_r", float(f), hk[f][0], hk[f][1], "f" if float(f) in [24.0, 34.0] else ("l" if float(f) == 26.0 else "a"))
	c.key("hand_r_edge", 20, Vector3(0, 0, 1)).key("hand_r_edge", 42, Vector3(0, 0, 1))
	c.key("hand_l_pos", 13, Vector3(0.3, 0.16, 0.12)).key("hand_l_pos", 20, Vector3(0.34, 0.22, 0.0))
	c.key("hand_l_pos", 24, Vector3(0.26, 0.32, 0.18), "f").key("hand_l_pos", 26, Vector3(0.14, 0.2, 0.5), "l")
	c.key("hand_l_pos", 34, Vector3(0.15, 0.18, 0.52), "f").key("hand_l_pos", 42, Vector3(0.24, -0.2, 0.1))
	c.key("hand_l_pole", 13, Vector3(1, -0.4, -0.4)).key("hand_l_pole", 42, Vector3(1, -0.4, -0.4))
	c.key("hand_l_grip", 44, float(c.base.hand_l_grip))
	c.key("arm_stretch", 25, 0.0).key("arm_stretch", 26, 0.07).key("arm_stretch", 29, 0.03).key("arm_stretch", 34, 0.0)
	c.key("flat", 24, 0.3).key("flat", 42, 0.3)
	c.key("smear", 0, 0.0).key("smear", 54, 0.0)
	# feet: planted for the gather, then hanging (toes pointed) in the float
	var g := BWAnimSkill._feet_base(c)
	_feet_home(c, 0)
	_feet_home(c, 10)
	_foot(c, "l", 12, g[0], 0.4, 0.22)
	_foot(c, "r", 12, g[1], 0.45, -0.22)
	_air(c, "l", 18, Vector3(0.11, 0.2, 0.06), 0.75)
	_air(c, "r", 18, Vector3(-0.11, 0.18, -0.06), 0.85)
	_air(c, "l", 34, Vector3(0.11, 0.2, 0.06), 0.75, "f")
	_air(c, "r", 34, Vector3(-0.11, 0.18, -0.06), 0.85, "f")
	_air(c, "l", 38.5, Vector3(0.12, 0.08, 0.05), 0.4)
	_air(c, "r", 38.5, Vector3(-0.12, 0.07, -0.04), 0.45)
	_feet_home(c, 40)
	_feet_home(c, 54)
	# the turn (radians CCW from above): once round in the air, 0 before the
	# rise and exactly TAU after it
	var turn := [[12.0, 0.0, "a"], [14.0, 0.06, "a"], [17.0, 0.3, "a"], [20.0, 0.62, "a"], [22.5, 0.88, "a"], [24.0, 1.0, "f"]]
	c.meta["spin_yaw"] = _turn_meta(turn, 54)
	c.meta["spin_hz"] = BWAnimClips.BAKE_HZ
	return c

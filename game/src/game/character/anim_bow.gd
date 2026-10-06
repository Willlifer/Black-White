class_name BWAnimBow
extends RefCounted
## D164: the archery clips of the bow set (design/art/ANIMATION.md, "Bow").
## One draw cycle, keyed in the ROOT frame, reused by every variant:
##
##   nock     the string hand meets the string at the arrow rest's height
##            (the arrow appears on the string; BWCharacter._update_bow)
##   draw     push-pull: the bow arm extends to the target line while the
##            string hand pulls straight back along the arrow to the ANCHOR
##            under the jaw; the shoulders open (chest further side-on, the
##            draw elbow high), the legs sink a little; the string bends to
##            the hand (BWWeaponView.set_string_draw: two segments, tips to nock)
##   hold     the anchor held (coil). Aimed Shot holds long with a small aim
##            tremble that settles on a breath just before the release
##   release  the string hand flies back past the ear and opens, the bow
##            rolls forward in the open bow hand, a recoil runs down the body;
##            the follow-through is held, then the bow comes down
##
## Clips (all 24 fps, `meta.arrows` = [[nock s, release s], ...] windows):
##   strike        the standard shot (basic attacks, Energized, Pinning)
##   shot_quick    Retreating Shot: snap-nock, short draw, no hold
##   shot_aimed    Aimed Shot: a long hold with the tremble
##   shot_sky      Arcing Shot: the same cycle pitched 50 deg skyward, the
##                 body leaning back from the hips
##   shot_volley   Rain of Arrows: skyward, four arrows nocked and loosed in
##                 quick succession (release, release2 .. release4)
##   shot_fan      Split Arrow: the bow canted, three arrows fanned on the string
##
## Markers: nock, coil, release (release2..), hit, recovered, pose; the
## combat looses an arrow on each release (BWRangedVFX).

const FPS := 24.0
## Root-frame landmarks (origin: the chest pivot, 1.22 above the feet).
const SHOULDER := Vector3(0.02, 0.27, 0.0)
const REACH := 0.63          # shoulder -> bow hand at full draw
const DRAW := 0.70           # bow hand -> anchor along the arrow line
const ANCHOR_SIDE := -0.07   # the anchor sits a hand's width to her right of the line
const SKY := 0.87            # 50 deg: Arcing Shot / Rain

static func clips() -> Array:
	return [strike(), shot_quick(), shot_aimed(), shot_sky(), shot_volley(), shot_fan()]


## The skill clips as pose names (BWUnitView.skill routes windup / strike).
static func actions() -> Dictionary:
	var out := {}
	for n in ["shot_quick", "shot_aimed", "shot_sky", "shot_volley", "shot_fan"]:
		out[n] = { "clip": n }
		out["windup_" + n] = { "clip": n, "hold": "coil" }
	return out


# ------------------------------------------------------------------ geometry

static func _dir(pitch: float) -> Vector3:
	return Vector3(0, sin(pitch), cos(pitch))


## Bow hand at full draw for a pitch, with the lean-back shift (sky shots
## lean the chest back, carrying the shoulders back).
static func _bow_full(pitch: float, lean_z: float = 0.0) -> Vector3:
	return SHOULDER + Vector3(0.03, 0.02, lean_z) + _dir(pitch) * REACH


static func _anchor(pitch: float, lean_z: float = 0.0) -> Vector3:
	return _bow_full(pitch, lean_z) - _dir(pitch) * DRAW + Vector3(ANCHOR_SIDE, 0.04, 0.0)


## The bow's limb axis (its +Y) for a pitch, canted `cant` toward her right.
static func _limb(pitch: float, cant: float = 0.12) -> Vector3:
	var up := Vector3(0, cos(pitch), -sin(pitch))
	return (up + Vector3(-1, 0, 0) * tan(cant)).normalized()


# ------------------------------------------------------------- the builder

class Cycle:
	var nock := 6.0          # the string hand on the string
	var anchor := 11.0       # full draw
	var release := 14.0
	var pitch := 0.0
	var lean_z := 0.0
	var cant := 0.12
	var reach_nock := 0.42   # how far out the bow is at the nock (share of REACH)


## Hands for one draw cycle. `first` keys the bow coming up from the guard.
static func _cycle(c: BWAnimClips.Clip, y: Cycle, first: bool) -> void:
	var d := _dir(y.pitch)
	var bow := _bow_full(y.pitch, y.lean_z)
	var anc := _anchor(y.pitch, y.lean_z)
	var limb := _limb(y.pitch, y.cant)
	var bow_nock := SHOULDER + Vector3(0.10, -0.04, y.lean_z * 0.6) + _dir(y.pitch * 0.85) * (REACH * y.reach_nock + 0.05)
	var n := y.nock
	if first:
		# the bow comes up out of the guard, top limb leading
		c.key("hand_l_pos", n - 3.0, SHOULDER + Vector3(0.18, -0.2, 0.3))
		c.key("hand_l_aim", n - 3.0, Vector3(0.05, 0.95, 0.3).normalized())
	c.key("hand_l_pos", n, bow_nock).key("hand_l_aim", n, _limb(y.pitch * 0.85, y.cant + 0.15))
	c.key("hand_l_edge", n, _dir(y.pitch * 0.85))
	# push: the bow arm finishes its extension a beat before the anchor
	var push := lerpf(n, y.anchor, 0.7)
	c.key("hand_l_pos", push, bow - d * 0.015).key("hand_l_aim", push, limb).key("hand_l_edge", push, d)
	c.key("hand_l_pos", y.anchor, bow, "f").key("hand_l_aim", y.anchor, limb, "f").key("hand_l_edge", y.anchor, d, "f")
	c.key("hand_l_pos", y.release - 0.5, bow, "f").key("hand_l_aim", y.release - 0.5, limb, "f").key("hand_l_edge", y.release - 0.5, d, "f")
	# release: the bow kicks out and rolls forward in the open hand
	c.key("hand_l_pos", y.release + 1.0, bow + d * 0.05 + Vector3(0, -0.035, 0), "l")
	c.key("hand_l_aim", y.release + 1.0, (limb + d * 0.45).normalized(), "l")
	c.key("hand_l_pos", y.release + 3.0, bow + d * 0.03 + Vector3(0, -0.02, 0))
	c.key("hand_l_aim", y.release + 3.0, (limb + d * 0.25).normalized())
	c.key("hand_l_pole", n, Vector3(1, -0.25, -0.3)).key("hand_l_pole", y.release + 3.0, Vector3(1, -0.3, -0.2))
	# pull: the string hand meets the string, then draws along the line
	var on_string := bow_nock - _dir(y.pitch * 0.85) * 0.05 + Vector3(-0.03, 0.0, 0.0)
	if first:
		c.key("hand_r_pos", n - 2.5, on_string + Vector3(-0.12, -0.04, -0.12)).key("hand_r_grip", n - 2.5, 0.0)
	# grip = the solver's pull onto the string's nock point (1 = on it): only
	# for the nock itself; the draw is the keyed hand (the string follows it)
	c.key("hand_r_pos", n, on_string, "f").key("hand_r_grip", n - 0.5, 1.0, "f").key("hand_r_grip", n + 0.5, 1.0, "f")
	c.key("hand_r_grip", n + 2.0, 0.0, "f")
	var mid := on_string.lerp(anc, 0.62) + Vector3(-0.015, 0.03, 0.0)
	c.key("hand_r_pos", lerpf(n, y.anchor, 0.5), mid)
	c.key("hand_r_pos", y.anchor, anc, "f")
	c.key("hand_r_pos", y.release - 0.5, anc + d * 0.004, "f")
	# the string slips: the hand flies straight back past the ear and opens
	c.key("hand_r_pos", y.release + 1.0, anc - d * 0.14 + Vector3(-0.07, 0.03, 0.0), "l")
	c.key("hand_r_pos", y.release + 3.0, anc - d * 0.19 + Vector3(-0.12, 0.02, 0.0))
	# the draw elbow rides high and behind (pole), the release lets it open
	c.key("hand_r_pole", n, Vector3(-1, 0.2, -0.5)).key("hand_r_pole", y.anchor, Vector3(-0.6, 0.45, -1))
	c.key("hand_r_pole", y.release + 2.0, Vector3(-0.8, 0.2, -0.8))


## Body for one cycle: the shoulders open over the draw, settle at the
## anchor, a recoil on the release. `k` scales (later volley cycles smaller).
static func _body(c: BWAnimClips.Clip, y: Cycle, lean: float, k: float = 1.0) -> void:
	var hips := -0.5
	var chest_x := -0.05 - lean
	c.pose(y.nock, { "hips": Vector3(lean * 0.25, hips, 0), "spine": Vector3(-lean * 0.35, -0.2, 0),
		"chest": Vector3(chest_x + 0.03 * k, -0.28, 0.02), "head": Vector3(0.06 - lean * 0.35, 0.9, 0.0) })
	# the draw: the chest turns further side-on and the shoulders open; the
	# head tips onto the string; the legs sink
	c.pose(y.anchor, { "hips": Vector3(lean * 0.3, hips - 0.04, 0), "spine": Vector3(-lean * 0.4, -0.24, 0),
		"chest": Vector3(chest_x - 0.02, -0.4, -0.03), "head": Vector3(0.1 - lean * 0.5, 1.02, -0.1),
		"root": Vector3(0, -0.085, -0.01 - lean * 0.08), "squash": -0.012 * k }, "f")
	c.pose(y.release - 0.5, { "hips": Vector3(lean * 0.3, hips - 0.04, 0), "spine": Vector3(-lean * 0.4, -0.24, 0),
		"chest": Vector3(chest_x - 0.02, -0.4, -0.03), "head": Vector3(0.1 - lean * 0.5, 1.02, -0.1),
		"root": Vector3(0, -0.085, -0.01 - lean * 0.08), "squash": -0.012 * k }, "f")
	# the recoil: the chest kicks back and opens, the head rides it
	c.pose(y.release + 1.0, { "chest": Vector3(chest_x - 0.1 * k, -0.46, 0.0), "head": Vector3(0.02 - lean * 0.5, 1.05, -0.04),
		"root": Vector3(0, -0.095, -0.03 - lean * 0.08), "squash": -0.03 * k, "head_sq": 0.035 * k }, "l")
	c.pose(y.release + 3.0, { "chest": Vector3(chest_x - 0.04, -0.42, -0.01), "root": Vector3(0, -0.08, -0.02 - lean * 0.08),
		"squash": 0.008 * k, "head_sq": -0.012 * k })


## Feet: the right foot steps back and turns out (side-on), back in at the end.
static func _feet(c: BWAnimClips.Clip, step_in: float, step_out: float, end: float, wide: float = 0.0) -> void:
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fr2 := Vector2(-0.16 - wide, -0.22 - wide * 0.5)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(step_in - 3.5, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(step_in - 2.0, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.15, -0.45, 0.07), "foot_r_rot": Vector3(0.15, -0.45, 0) })
	c.pose(step_in, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.72), "foot_r_rot": Vector3(0, -0.72, 0) }, "f")
	c.pose(step_out, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.72), "foot_r_rot": Vector3(0, -0.72, 0) }, "f")
	c.pose(step_out + 2.0, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.15, -0.45, 0.06), "foot_r_rot": Vector3(0.15, -0.45, 0) })
	c.pose(step_out + 4.0, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(end, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0),
		"foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	c.pose(step_in + 4.0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")


static func _new(name: String, frames: int) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip(name, frames, false, "bow")
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	c.at_base(0, all + hand_all)
	c.at_base(frames, all + hand_all)
	c.key("flat", 4, 0.0).key("flat", frames - 8, 0.0)
	return c


## The follow-through held, then the bow comes down and she turns back.
static func _settle(c: BWAnimClips.Clip, y: Cycle, hold_to: float, down: float, lean: float) -> void:
	var d := _dir(y.pitch)
	var bow := _bow_full(y.pitch, y.lean_z)
	var anc := _anchor(y.pitch, y.lean_z)
	c.key("hand_l_pos", hold_to, bow + d * 0.02 + Vector3(0, -0.03, 0), "f")
	c.key("hand_l_aim", hold_to, (_limb(y.pitch, y.cant) + d * 0.2).normalized(), "f")
	c.key("hand_r_pos", hold_to, anc - d * 0.18 + Vector3(-0.12, 0.0, 0.0), "f")
	c.key("hand_l_pos", down, SHOULDER + Vector3(0.18, -0.36, 0.3))
	c.key("hand_l_aim", down, Vector3(0.05, 0.95, 0.3).normalized())
	c.key("hand_l_edge", down, Vector3(0, 0, 1))
	c.key("hand_r_pos", down, SHOULDER + Vector3(-0.26, -0.38, 0.06))
	c.key("hand_r_pole", down, Vector3(-0.5, -0.1, -1))
	BWAnimAction._side_on(c, hold_to, 1.0, "f")
	c.pose(hold_to, { "chest": Vector3(-0.05 - lean - 0.03, -0.4, 0), "spine": Vector3(-lean * 0.4, -0.22, 0),
		"hips": Vector3(lean * 0.3, -0.5, 0), "head": Vector3(0.06 - lean * 0.4, 0.98, 0), "root": Vector3(0, -0.075, -0.01) }, "f")
	BWAnimAction._side_on(c, down, 0.45)
	c.pose(down, { "root": Vector3(0, -0.04, 0.0) })


static func _meta(c: BWAnimClips.Clip, windows: Array) -> void:
	var arr: Array = []
	for w in windows:
		arr.append([float(w[0]) / FPS, float(w[1]) / FPS])
	c.meta = { "hand_frame": "root", "kind": "shot", "arrows": arr }


# ------------------------------------------------------------------- clips

## STRIKE (36 f): the standard shot.
static func strike() -> BWAnimClips.Clip:
	var c := _new("strike", 36)
	var y := Cycle.new()
	y.nock = 6.0
	y.anchor = 11.0
	y.release = 14.0
	c.marker("nock", 6).marker("coil", 12).marker("release", 14).marker("hit", 15).marker("recovered", 30).marker("pose", 12)
	c.pose(2, { "head": Vector3(0.0, 0.5, 0.0) })
	BWAnimAction._side_on(c, 4.5, 0.7)
	_body(c, y, 0.0)
	_cycle(c, y, true)
	_settle(c, y, 21.0, 28.0, 0.0)
	_feet(c, 5.5, 26.0, 36.0)
	_meta(c, [[y.nock, y.release]])
	return c


## QUICK (26 f): Retreating Shot. Nock on the way up, a short snap draw,
## no hold; she is already turning away on the follow-through.
static func shot_quick() -> BWAnimClips.Clip:
	var c := _new("shot_quick", 26)
	var y := Cycle.new()
	y.nock = 4.0
	y.anchor = 7.5
	y.release = 8.5
	y.reach_nock = 0.6
	c.marker("nock", 4).marker("coil", 7.5).marker("release", 8.5).marker("hit", 9.5).marker("recovered", 21).marker("pose", 7.5)
	c.pose(1.5, { "head": Vector3(0.0, 0.55, 0.0) })
	BWAnimAction._side_on(c, 3.5, 0.75)
	_body(c, y, 0.0, 0.8)
	_cycle(c, y, true)
	_settle(c, y, 13.0, 20.0, 0.0)
	# the turn away: the head leaves the target first
	c.pose(15, { "head": Vector3(0.0, 0.4, 0.0) })
	_feet(c, 3.5, 17.0, 26.0)
	_meta(c, [[y.nock, y.release]])
	return c


## AIMED (52 f): Aimed Shot. A full draw held long: the tremble builds in
## both hands, a breath, the hands settle still, then the release.
static func shot_aimed() -> BWAnimClips.Clip:
	var c := _new("shot_aimed", 52)
	var y := Cycle.new()
	y.nock = 7.0
	y.anchor = 13.0
	y.release = 30.0
	c.marker("nock", 7).marker("coil", 14).marker("release", 30).marker("hit", 31).marker("recovered", 46).marker("pose", 20)
	c.pose(2, { "head": Vector3(0.0, 0.5, 0.0) })
	BWAnimAction._side_on(c, 5.0, 0.7)
	_body(c, y, 0.0)
	_cycle(c, y, true)
	# the breath in the hold: a slow rise and settle of the chest
	c.pose(20, { "squash": 0.01, "root": Vector3(0, -0.08, -0.012) })
	c.pose(26, { "squash": -0.014, "root": Vector3(0, -0.09, -0.01) }, "f")
	_settle(c, y, 37.0, 44.0, 0.0)
	_feet(c, 6.0, 42.0, 52.0, 0.04)
	_tremble(c, "hand_l_pos", 14.0, 29.0, 0.0065, 1.0)
	_tremble(c, "hand_r_pos", 14.0, 29.0, 0.0045, 2.3)
	_meta(c, [[y.nock, y.release]])
	return c


## A small aim tremble on a hand channel between f0 and f1: two detuned
## sines per axis, swelling to the middle of the hold, then settling still
## on the breath before the release.
static func _tremble(c: BWAnimClips.Clip, ch: String, f0: float, f1: float, amp: float, salt: float) -> void:
	var arr: Array = c.keys[ch]
	var frames := float(c.frames)
	c.proc(ch, func(f: float) -> Variant:
		var v: Vector3 = BWAnimClips.eval_keys(arr, f, false, frames)
		if f <= f0 or f >= f1:
			return v
		var u := (f - f0) / (f1 - f0)
		var env := smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.62, 0.9, u))
		var s := f / FPS
		return v + Vector3(sin(s * 41.0 + salt) * 0.4, sin(s * 47.0 + salt * 1.7) + 0.5 * sin(s * 73.0 + salt), sin(s * 37.0 + salt * 0.6) * 0.3) * amp * env)


## SKY (40 f): Arcing Shot. The cycle pitched skyward: she leans back from
## the hips, the head tips up the line, and the draw comes to a lower
## anchor at the throat; the release follows through up the arc.
static func shot_sky() -> BWAnimClips.Clip:
	var c := _new("shot_sky", 40)
	var y := Cycle.new()
	y.nock = 7.0
	y.anchor = 13.0
	y.release = 17.0
	y.pitch = SKY
	y.lean_z = -0.09
	c.marker("nock", 7).marker("coil", 14).marker("release", 17).marker("hit", 18).marker("recovered", 34).marker("pose", 14)
	c.pose(2, { "head": Vector3(-0.1, 0.5, 0.0) })
	BWAnimAction._side_on(c, 5.0, 0.7)
	_body(c, y, 0.4)
	_cycle(c, y, true)
	_settle(c, y, 25.0, 32.0, 0.35)
	_feet(c, 6.0, 30.0, 40.0, 0.05)
	_meta(c, [[y.nock, y.release]])
	return c


## VOLLEY (64 f): Rain of Arrows. Skyward like the sky shot, then four
## arrows nocked and loosed one after another (a fresh nock from the hip
## each time); each later draw is a touch shorter and quicker.
const VOLLEY := [[7.0, 12.0, 14.0], [18.0, 21.5, 23.0], [26.5, 30.0, 31.5], [35.0, 38.5, 40.0]]

static func shot_volley() -> BWAnimClips.Clip:
	var c := _new("shot_volley", 64)
	var windows: Array = []
	c.pose(2, { "head": Vector3(-0.1, 0.5, 0.0) })
	BWAnimAction._side_on(c, 5.0, 0.7)
	for i in VOLLEY.size():
		var y := Cycle.new()
		y.nock = VOLLEY[i][0]
		y.anchor = VOLLEY[i][1]
		y.release = VOLLEY[i][2]
		y.pitch = SKY + 0.06 * (i % 2)
		y.lean_z = -0.09
		y.reach_nock = 0.85 if i > 0 else 0.42
		_body(c, y, 0.4, 1.0 if i == 0 else 0.7)
		_cycle(c, y, i == 0)
		if i > 0:
			# between shots the string hand dips to the hip quiver and back
			var prev: float = VOLLEY[i - 1][2]
			c.key("hand_r_pos", prev + 2.2, SHOULDER + Vector3(-0.22, -0.2, -0.12))
			c.key("hand_r_grip", prev + 2.2, 0.0)
		c.marker("release" if i == 0 else "release%d" % (i + 1), y.release)
		windows.append([y.nock, y.release])
	c.marker("nock", 7).marker("coil", 13).marker("hit", 15).marker("recovered", 58).marker("pose", 13)
	var last := Cycle.new()
	last.pitch = SKY + 0.06
	last.lean_z = -0.09
	last.release = 40.0
	_settle(c, last, 48.0, 56.0, 0.35)
	_feet(c, 6.0, 53.0, 64.0, 0.07)
	_meta(c, windows)
	c.meta["volley"] = VOLLEY.size()
	return c


## FAN (38 f): Split Arrow. Three arrows taken together and nocked fanned,
## the bow canted well over so the fan lies across the field.
static func shot_fan() -> BWAnimClips.Clip:
	var c := _new("shot_fan", 38)
	var y := Cycle.new()
	y.nock = 7.0
	y.anchor = 12.0
	y.release = 15.0
	y.cant = 0.85
	c.marker("nock", 7).marker("coil", 13).marker("release", 15).marker("hit", 16).marker("recovered", 32).marker("pose", 13)
	c.pose(2, { "head": Vector3(0.0, 0.5, 0.0) })
	BWAnimAction._side_on(c, 5.0, 0.7)
	_body(c, y, 0.0)
	_cycle(c, y, true)
	_settle(c, y, 22.0, 30.0, 0.0)
	_feet(c, 6.0, 28.0, 38.0, 0.03)
	_meta(c, [[y.nock, y.release]])
	c.meta["fan"] = 3
	return c

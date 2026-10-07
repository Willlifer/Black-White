class_name BWAnimAction
extends RefCounted
## Action clips for every set (design/art/ANIMATION.md, "Actions"):
##
##   strike       per style (heavy: the approved flamberge cut). Melee:
##                coil (held by "windup"), launch / land (airborne: the game
##                dashes the root), hit, hop_start / hop_end (the hop home),
##                recovered. Bow and pistol: coil (full draw / aimed),
##                release (the projectile leaves), hit, recovered.
##   strike_axe   one and heavy sets, axe class: an overhead chop
##   cast         staff spells and elemental skills: coil (gathered),
##                release, hit, recovered. Started from "coil" when it
##                follows a channel.
##   channel      a held, looping cast whose every frame sits on the cast's
##                coil pose, so cast continues from it without a seam
##
## MELEE STRIKES share the approved flamberge strike's body and feet (the
## coil, the dash, the lunge landing, the hit-stop, the hop home), retimed
## per style through its beats and with the twist scaled (thrusts twist
## less than cuts). Hands are keyed per style in the ROOT frame, so the
## cut is aimed at the target, not wherever the twisting chest points.

## The reference strike's beats (frames of the flamberge strike).
const REF_BEATS := [0.0, 4.0, 8.0, 10.0, 13.0, 14.0, 18.0, 22.0, 27.0, 30.0, 36.0, 40.0]
## beat names, same order: start, wind, coil, launch, land, hit, over,
## settle, hop_start, hop_end, recovered, end

static var _ref: BWAnimClips.Clip


static func clips(st: String) -> Array:
	var out: Array = [strike(st), cast(st)]
	out.append(channel(st, out[1]))
	if st in ["one", "heavy"]:
		out.append(strike_axe(st))
	if st == "fists":
		out.append_array([_strike_flurry(), _strike_uppercut(), _strike_palm()])
	if st in ["one", "pair"]:
		out.append(_strike_spin(st))                 # D102: skill clip "spin"
	if st == "pistol":
		out.append(_strike_pistol_whip())            # D102: skill clip "pistol_whip"
	if st == "bow":
		out.append_array(BWAnimBow.clips().slice(1))  # D164: the archery variants (strike is above)
	return out


static func _reference() -> BWAnimClips.Clip:
	if _ref == null:
		_ref = BWAnimClips._strike_sword()
	return _ref


## Piecewise-linear retime of a reference frame onto a style's beats.
static func _warp(f: float, beats: Array) -> float:
	for i in range(1, REF_BEATS.size()):
		if f <= REF_BEATS[i] or i == REF_BEATS.size() - 1:
			var u := (f - float(REF_BEATS[i - 1])) / maxf(float(REF_BEATS[i]) - float(REF_BEATS[i - 1]), 1e-4)
			return lerpf(float(beats[i - 1]), float(beats[i]), u)
	return f


const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq",
	"foot_l_pos", "foot_l_rot", "foot_r_pos", "foot_r_rot"]


## A melee strike on the reference body: beats (12 frames, see REF_BEATS),
## tw (twist scale on hips/chest/head yaw), hands {ref beat frame: {ch: v}}
## in the root frame.
static func _melee(name: String, st: String, beats: Array, tw: float, hands: Dictionary, engage: float) -> BWAnimClips.Clip:
	var ref := _reference()
	var end := int(beats[beats.size() - 1])
	var c := BWAnimClips.new_clip(name, end, false, st)
	for ch in BODY:
		if not ref.keys.has(ch):
			continue
		for k in ref.keys[ch]:
			var v: Variant = k[1]
			if v is Vector3 and ch in ["hips", "chest", "head"]:
				v = Vector3(v.x, v.y * tw, v.z * lerpf(1.0, tw, 0.5))
			c.key(ch, _warp(float(k[0]), beats), v, str(k[2]))
	var m := ["start", "wind", "coil", "launch", "land", "hit", "over", "settle", "hop_start", "hop_end", "recovered", "end"]
	for i in m.size():
		if m[i] in ["coil", "launch", "land", "hit", "hop_start", "hop_end", "recovered"]:
			c.marker(m[i], float(beats[i]))
	c.marker("pose", float(beats[5]))
	c.meta = { "engage": engage, "hand_frame": "root", "kind": "melee" }
	# guard at both ends, the style's own hands in between
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	c.at_base(0, hand_all)
	c.at_base(end, hand_all)
	for f in hands:
		var d: Dictionary = hands[f]
		var mode := str(d.get("_mode", "a"))
		for ch in d:
			if ch == "_mode":
				continue
			c.key(ch, _warp(float(f), beats), d[ch], mode)
	return c


static func _h(pos: Vector3, aim: Vector3, extra: Dictionary = {}, hand: String = "hand_r") -> Dictionary:
	var d := { hand + "_pos": pos, hand + "_aim": aim.normalized() }
	d.merge(extra, true)
	return d


static func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.merge(b, true)
	return d


# ------------------------------------------------------------------ strikes

static func strike(st: String) -> BWAnimClips.Clip:
	match st:
		"heavy": return BWAnimClips._strike_sword()
		"one": return _strike_one()
		"polearm": return _strike_polearm()
		"spear": return _strike_spear()
		"staff": return _strike_staff()
		"pair": return _strike_pair()
		"bow": return BWAnimBow.strike()                # D164 (anim_bow.gd)
		"pistol": return _strike_pistol()
		"fists": return _strike_fists()
	return BWAnimClips._strike_sword()


## ONE: a one-handed forehand cut, high right to low left. The free arm
## reaches for the target in the coil (aim) and is flung back on the cut
## for balance. Quicker than the flamberge (36 f).
static func _strike_one() -> BWAnimClips.Clip:
	var beats := [0, 3, 7, 9, 11, 12, 15, 19, 24, 27, 32, 36]
	var L := "hand_l_pos"
	var hands := {
		4.0: _h(Vector3(-0.3, 0.1, 0.1), Vector3(-0.6, 0.7, -0.2), { L: Vector3(0.25, 0.05, 0.3) }),
		6.0: _h(Vector3(-0.36, 0.26, -0.06), Vector3(-0.55, 0.62, -0.55), { L: Vector3(0.28, 0.12, 0.36) }),
		8.0: _h(Vector3(-0.38, 0.32, -0.12), Vector3(-0.5, 0.55, -0.67), { L: Vector3(0.3, 0.14, 0.4), "hand_r_edge": Vector3(0, 1, 0.3),
			"hand_r_pole": Vector3(-1, 0.1, -0.3), "flat": 0.3, "_mode": "f" }),
		10.0: _h(Vector3(-0.36, 0.38, -0.05), Vector3(-0.4, 0.75, -0.5)),
		11.0: _h(Vector3(-0.3, 0.42, 0.12), Vector3(-0.3, 0.9, 0.3), { L: Vector3(0.3, 0.02, 0.22) }),
		12.0: _h(Vector3(-0.1, 0.25, 0.42), Vector3(0.2, 0.6, 0.77), { "smear": 1.0, "arm_stretch": 0.06, "_mode": "l" }),
		13.0: _h(Vector3(0.08, 0.02, 0.5), Vector3(0.6, 0.0, 0.8), { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" }),
		14.0: _h(Vector3(0.16, -0.06, 0.46), Vector3(0.75, -0.15, 0.64), { L: Vector3(0.36, 0.05, -0.25), "arm_stretch": 0.07 }),
		16.0: _h(Vector3(0.18, -0.09, 0.44), Vector3(0.78, -0.2, 0.6), { "smear": 0.35, "arm_stretch": 0.05 }),
		18.0: _h(Vector3(0.28, -0.18, 0.3), Vector3(0.85, -0.45, 0.25), { L: Vector3(0.38, 0.1, -0.3), "smear": 0.0, "arm_stretch": 0.0,
			"hand_r_pole": Vector3(-0.6, -1, 0.1), "_mode": "f" }),
		22.0: _h(Vector3(0.24, -0.14, 0.33), Vector3(0.8, -0.35, 0.45), { "flat": 0.3 }),
		25.0: _h(Vector3(0.08, -0.1, 0.36), Vector3(0.35, 0.25, 0.9), { L: Vector3(0.3, -0.1, 0.0) }),
		27.0: _h(Vector3(-0.14, -0.12, 0.3), Vector3(-0.3, 0.65, 0.7), { "flat": 0.8 }),
	}
	var c := _melee("strike", "one", beats, 1.0, hands, 1.0)
	c.lead(_warp(10.5, beats), _warp(18.0, beats), 0.85)
	return c


## STRIKE_AXE (one: hatchet; heavy: double axe, warhammer, anchor): an
## overhead chop. The head goes back behind her head in the coil (held),
## comes over the top and down through the target; the heavy version waits
## longer in the coil and lands harder.
static func strike_axe(st: String) -> BWAnimClips.Clip:
	var heavy := st == "heavy"
	var beats := [0, 5, 12, 14, 17, 18, 22, 26, 31, 34, 40, 46] if heavy else [0, 3, 7, 9, 11, 12, 15, 19, 24, 27, 32, 36]
	var y := 0.06 if heavy else 0.0
	var L := "hand_l_pos"
	var hands := {
		4.0: _h(Vector3(-0.16, 0.25 + y, 0.12), Vector3(-0.2, 0.9, -0.3)),
		6.0: _h(Vector3(-0.16, 0.46 + y, 0.0), Vector3(-0.1, 0.65, -0.75)),
		8.0: _h(Vector3(-0.14, 0.55 + y, -0.12), Vector3(-0.05, 0.45, -0.89), { "hand_r_edge": Vector3(0, 1, 0), "flat": 0.2,
			"hand_r_pole": Vector3(-1, -0.2, 0.0), "_mode": "f" }),
		10.0: _h(Vector3(-0.12, 0.6 + y, -0.04), Vector3(-0.05, 0.75, -0.66)),
		11.0: _h(Vector3(-0.1, 0.64 + y, 0.08), Vector3(0.0, 0.98, -0.2)),
		12.0: _h(Vector3(-0.06, 0.48 + y, 0.36), Vector3(0.0, 0.6, 0.8), { "smear": 1.0, "arm_stretch": 0.05, "_mode": "l" }),
		13.0: _h(Vector3(-0.04, 0.16, 0.5), Vector3(0.0, 0.08, 1.0), { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" }),
		14.0: _h(Vector3(-0.03, 0.0, 0.5), Vector3(0.0, -0.26, 0.97), { "arm_stretch": 0.06 }),
		16.0: _h(Vector3(-0.03, -0.03, 0.49), Vector3(0.0, -0.32, 0.95), { "smear": 0.3 }),
		18.0: _h(Vector3(-0.03, -0.06, 0.46), Vector3(0.0, -0.32, 0.95), { "smear": 0.0, "arm_stretch": 0.0, "_mode": "f" }),
		22.0: _h(Vector3(-0.04, -0.03, 0.44), Vector3(0.0, -0.2, 0.98)),
		25.0: _h(Vector3(-0.08, 0.0, 0.38), Vector3(-0.1, 0.4, 0.9)),
		27.0: _h(Vector3(-0.14, -0.06, 0.3), Vector3(-0.35, 0.7, 0.6), { "flat": 0.7 }),
	}
	if heavy:
		for f in hands:
			hands[f]["hand_l_grip"] = 1.0
	else:
		# the free hand counters the chop: up and forward in the coil, down and back on the hit
		hands[8.0][L] = Vector3(0.3, 0.25, 0.3)
		hands[11.0][L] = Vector3(0.32, 0.15, 0.25)
		hands[14.0][L] = Vector3(0.34, -0.05, -0.2)
		hands[18.0][L] = Vector3(0.36, -0.08, -0.24)
		hands[25.0][L] = Vector3(0.3, -0.2, 0.0)
	var c := _melee("strike_axe", st, beats, 0.45, hands, 1.25 if heavy else 1.05)
	c.lead(_warp(10.5, beats), _warp(18.0, beats), 0.9)
	# a chop sits lower on the landing: the knees take the weight
	c.key("root", _warp(14.0, beats), Vector3(0, -0.26 if heavy else -0.23, 0.1))
	c.key("squash", _warp(14.0, beats), -0.06 if heavy else -0.05)
	return c


## POLEARM: a two-handed thrust. The shaft drops from upright to level on
## the target line (f2-f8, the head leads), drawn back to the rear hip in
## the coil; the lunge drives both hands straight down the line; the hit
## stops dead (hit-stop), a little twist of the shaft, and it recovers
## back to upright at the side.
static func _strike_polearm() -> BWAnimClips.Clip:
	var beats := [0, 4, 9, 11, 14, 15, 19, 23, 28, 31, 37, 42]
	var g := { "hand_l_grip": 1.0 }
	var hands := {
		4.0: _h(Vector3(-0.22, 0.0, 0.0), Vector3(-0.05, 0.6, 0.8), g),
		6.0: _h(Vector3(-0.22, -0.02, -0.16), Vector3(0.0, 0.2, 0.98), g),
		8.0: _h(Vector3(-0.22, 0.0, -0.26), Vector3(0.04, 0.12, 0.99), _m(g, { "hand_r_edge": Vector3(0, 1, 0), "flat": 0.2,
			"hand_r_pole": Vector3(-1, -0.6, -0.4), "hand_l_pole": Vector3(0.6, -1, 0.0), "_mode": "f" })),
		10.0: _h(Vector3(-0.2, 0.03, -0.18), Vector3(0.03, 0.1, 0.99), g),
		12.0: _h(Vector3(-0.15, 0.07, 0.05), Vector3(0.0, 0.07, 1.0), _m(g, { "smear": 0.8, "_mode": "l" })),
		13.0: _h(Vector3(-0.11, 0.09, 0.2), Vector3(0.0, 0.05, 1.0), _m(g, { "smear": 1.0, "arm_stretch": 0.06, "_mode": "l" })),
		14.0: _h(Vector3(-0.09, 0.1, 0.26), Vector3(0.0, 0.04, 1.0), _m(g, { "arm_stretch": 0.08 })),
		16.0: _h(Vector3(-0.09, 0.1, 0.25), Vector3(0.0, 0.04, 1.0), _m(g, { "smear": 0.0, "arm_stretch": 0.06 })),
		18.0: _h(Vector3(-0.1, 0.06, 0.24), Vector3(0.05, -0.02, 1.0), _m(g, { "arm_stretch": 0.02, "_mode": "f" })),
		22.0: _h(Vector3(-0.14, 0.04, 0.12), Vector3(0.04, 0.05, 1.0), g),
		25.0: _h(Vector3(-0.2, 0.0, 0.0), Vector3(0.0, 0.3, 0.95), g),
		27.0: _h(Vector3(-0.26, -0.06, 0.08), Vector3(0.0, 0.8, 0.6), { "hand_l_grip": 0.6 }),
	}
	var c := _melee("strike", "polearm", beats, 0.4, hands, 1.6)
	# a thrust: the shaft spins a quarter in the hands on the hit (the edge turns)
	c.key("hand_r_edge", _warp(14.0, beats), Vector3(0, 1, 0)).key("hand_r_edge", _warp(18.0, beats), Vector3(-0.7, 0.7, 0))
	c.key("hand_r_edge", _warp(25.0, beats), Vector3(0, 0.3, 1))
	return c


## SPEAR (javelin, one hand): an overhand stab. The javelin comes up to
## the shoulder (f3-f7) with the free hand pointing at the target, the
## dash drives it down the line, the free arm is thrown back on the hit.
static func _strike_spear() -> BWAnimClips.Clip:
	var beats := [0, 3, 7, 9, 11, 12, 15, 19, 23, 26, 31, 35]
	var L := "hand_l_pos"
	var hands := {
		4.0: _h(Vector3(-0.3, 0.2, 0.0), Vector3(0.0, 0.3, 0.95), { L: Vector3(0.22, 0.15, 0.3) }),
		6.0: _h(Vector3(-0.32, 0.28, -0.14), Vector3(0.04, 0.05, 1.0), { L: Vector3(0.24, 0.28, 0.42) }),
		8.0: _h(Vector3(-0.32, 0.3, -0.2), Vector3(0.05, 0.02, 1.0), { L: Vector3(0.25, 0.3, 0.45), "hand_r_edge": Vector3(0, 1, 0),
			"hand_r_pole": Vector3(-1, -0.4, -0.2), "flat": 0.2, "_mode": "f" }),
		10.0: _h(Vector3(-0.3, 0.3, -0.1), Vector3(0.05, 0.0, 1.0)),
		12.0: _h(Vector3(-0.22, 0.24, 0.24), Vector3(0.06, -0.04, 1.0), { L: Vector3(0.3, 0.1, 0.1), "smear": 1.0, "arm_stretch": 0.06, "_mode": "l" }),
		13.0: _h(Vector3(-0.15, 0.18, 0.52), Vector3(0.08, -0.07, 1.0), { "smear": 1.0, "arm_stretch": 0.1, "_mode": "l" }),
		14.0: _h(Vector3(-0.12, 0.16, 0.6), Vector3(0.08, -0.08, 0.99), { L: Vector3(0.36, 0.02, -0.26), "arm_stretch": 0.1 }),
		16.0: _h(Vector3(-0.11, 0.15, 0.6), Vector3(0.08, -0.09, 0.99), { "smear": 0.0, "arm_stretch": 0.08 }),
		18.0: _h(Vector3(-0.1, 0.12, 0.62), Vector3(0.1, -0.12, 0.99), { L: Vector3(0.38, 0.05, -0.3), "arm_stretch": 0.04, "_mode": "f" }),
		22.0: _h(Vector3(-0.14, 0.12, 0.52), Vector3(0.06, -0.06, 1.0), { "arm_stretch": 0.0 }),
		25.0: _h(Vector3(-0.22, 0.14, 0.26), Vector3(0.03, 0.1, 1.0), { L: Vector3(0.28, -0.1, 0.05) }),
		27.0: _h(Vector3(-0.3, -0.06, 0.12), Vector3(0.0, 0.7, 0.7), { "flat": 0.6 }),
	}
	return _melee("strike", "spear", beats, 0.55, hands, 1.5)


## STAFF (melee): both hands, the head comes over the top and cracks down
## on the target; the free hand slides back onto the shaft for the blow.
static func _strike_staff() -> BWAnimClips.Clip:
	var beats := [0, 4, 9, 11, 14, 15, 19, 23, 28, 31, 37, 42]
	var g := { "hand_l_grip": 1.0 }
	var hands := {
		4.0: _h(Vector3(-0.2, 0.2, 0.1), Vector3(-0.15, 0.95, -0.1), { "hand_l_grip": 0.5 }),
		6.0: _h(Vector3(-0.14, 0.42, 0.0), Vector3(-0.12, 0.65, -0.75), g),
		8.0: _h(Vector3(-0.12, 0.5, -0.1), Vector3(-0.12, 0.45, -0.88), _m(g, { "hand_r_edge": Vector3(0, 1, 0), "flat": 0.2,
			"hand_r_pole": Vector3(-1, -0.2, 0.0), "hand_l_pole": Vector3(1, -0.2, 0.0), "_mode": "f" })),
		10.0: _h(Vector3(-0.1, 0.56, -0.02), Vector3(-0.08, 0.78, -0.62), g),
		11.0: _h(Vector3(-0.08, 0.6, 0.1), Vector3(0.0, 0.98, -0.15), g),
		12.0: _h(Vector3(-0.04, 0.46, 0.36), Vector3(0.0, 0.62, 0.78), _m(g, { "smear": 1.0, "arm_stretch": 0.05, "_mode": "l" })),
		13.0: _h(Vector3(-0.02, 0.16, 0.48), Vector3(0.0, 0.12, 0.99), _m(g, { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" })),
		14.0: _h(Vector3(0.0, 0.02, 0.48), Vector3(0.0, -0.12, 0.99), _m(g, { "arm_stretch": 0.06 })),
		16.0: _h(Vector3(0.0, 0.0, 0.47), Vector3(0.0, -0.16, 0.99), _m(g, { "smear": 0.3 })),
		18.0: _h(Vector3(0.0, -0.06, 0.45), Vector3(0.0, -0.3, 0.95), _m(g, { "smear": 0.0, "arm_stretch": 0.0, "_mode": "f" })),
		22.0: _h(Vector3(-0.02, -0.03, 0.42), Vector3(0.0, -0.2, 0.98), g),
		25.0: _h(Vector3(-0.1, 0.05, 0.34), Vector3(-0.05, 0.5, 0.86), g),
		27.0: _h(Vector3(-0.24, -0.04, 0.2), Vector3(0.0, 0.9, 0.4), { "hand_l_grip": 0.3, "flat": 0.6 }),
	}
	var c := _melee("strike", "staff", beats, 0.5, hands, 1.4)
	c.lead(_warp(10.5, beats), _warp(18.0, beats), 0.6)
	return c


## PAIR (daggers): a flurry. A low crouching coil with the right blade
## back and the left forward, a right cross-cut on the hit, and the left
## stabbing straight in two frames later ("hit2"). Fast (32 f).
static func _strike_pair() -> BWAnimClips.Clip:
	var beats := [0, 2, 5, 7, 9, 10, 15, 18, 21, 24, 28, 32]
	var hands := {
		4.0: _m(_h(Vector3(-0.28, 0.12, 0.0), Vector3(-0.5, 0.65, -0.55)), _h(Vector3(0.22, -0.02, 0.32), Vector3(0.2, 0.35, 0.92), {}, "hand_l")),
		8.0: _m(_h(Vector3(-0.32, 0.26, -0.12), Vector3(-0.5, 0.6, -0.62), { "_mode": "f", "flat": 0.4 }),
			_h(Vector3(0.2, -0.06, 0.36), Vector3(0.2, 0.3, 0.93), {}, "hand_l")),
		11.0: _h(Vector3(-0.26, 0.3, 0.12), Vector3(-0.3, 0.8, 0.5)),
		12.0: _h(Vector3(-0.1, 0.2, 0.42), Vector3(0.25, 0.45, 0.86), { "smear": 1.0, "arm_stretch": 0.05, "_mode": "l" }),
		13.0: _m(_h(Vector3(0.06, 0.1, 0.5), Vector3(0.6, 0.2, 0.78), { "smear": 1.0, "arm_stretch": 0.08, "_mode": "l" }),
			_h(Vector3(0.24, 0.0, 0.14), Vector3(0.2, 0.4, 0.9), {}, "hand_l")),
		14.0: _h(Vector3(0.15, 0.04, 0.48), Vector3(0.8, 0.0, 0.6), { "arm_stretch": 0.06 }),
		# the second blade (between hit and over): left stab straight in
		16.0: _m(_h(Vector3(-0.12, 0.04, 0.24), Vector3(-0.1, 0.4, 0.9), { "smear": 0.0, "arm_stretch": 0.02 }),
			_h(Vector3(0.12, 0.1, 0.38), Vector3(0.05, 0.1, 0.99), {}, "hand_l")),
		18.0: _m(_h(Vector3(-0.2, 0.02, 0.14), Vector3(-0.25, 0.5, 0.82), { "_mode": "f" }),
			_h(Vector3(0.06, 0.12, 0.62), Vector3(0.0, 0.05, 1.0), { "_mode": "f" }, "hand_l")),
		22.0: _m(_h(Vector3(-0.22, 0.0, 0.18), Vector3(-0.2, 0.45, 0.86)), _h(Vector3(0.1, 0.06, 0.52), Vector3(0.05, 0.15, 0.99), {}, "hand_l")),
		25.0: _h(Vector3(0.18, -0.06, 0.3), Vector3(0.2, 0.35, 0.9), {}, "hand_l"),
		27.0: _m(_h(Vector3(-0.26, -0.1, 0.22), Vector3(-0.2, 0.4, 0.9), { "flat": 0.9 }), _h(Vector3(0.24, -0.12, 0.22), Vector3(0.2, 0.4, 0.9), {}, "hand_l")),
	}
	var c := _melee("strike", "pair", beats, 0.8, hands, 0.9)
	c.marker("hit2", _warp(18.0, beats) - 0.5)
	c.lead(_warp(10.5, beats), _warp(16.0, beats), 0.85, "hand_r")
	c.lead(_warp(16.0, beats), _warp(20.0, beats), 0.6, "hand_l")
	# a lower crouch: she fights close
	c.key("root", _warp(8.0, beats), Vector3(0, -0.18, -0.06), "f")
	return c


## The body turned side-on for a shot (the static bow / pistol windup bodies).
static func _side_on(c: BWAnimClips.Clip, f: float, k: float, mode: String = "a") -> void:
	c.pose(f, { "hips": Vector3(0, -0.5 * k, 0), "spine": Vector3(0, -0.2 * k, 0), "chest": Vector3(-0.05 * k, -0.3 * k, 0),
		"head": Vector3(0.05 * k, 0.95 * k, 0) }, mode)


## BOW: see BWAnimBow (anim_bow.gd, D164): the draw cycle and its variants.


## PISTOL: a shot with recoil. Half side-on, the pistol comes up into a
## two-handed cup grip on the target line (coil f8, held by "windup"),
## the shot on f9: the muzzle kicks up and back, the chest and head snap
## back with a squash; she rides it down onto the line again (f13), holds
## a beat (smug), and lowers it.
static func _strike_pistol() -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("strike", 30, false, "pistol")
	var b := c.base
	c.marker("coil", 8).marker("release", 9).marker("hit", 10).marker("recovered", 24).marker("pose", 8)
	c.meta = { "hand_frame": "root", "kind": "shot" }
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(30, all + hand_all)
	c.pose(2, { "head": Vector3(0.0, 0.3, 0.0) })
	c.pose(5, { "hips": Vector3(0, -0.2, 0), "chest": Vector3(0, -0.1, 0), "head": Vector3(0, 0.3, 0), "root": Vector3(0, -0.06, 0) })
	c.pose(8, { "hips": Vector3(0, -0.22, 0), "chest": Vector3(0.02, -0.12, 0), "head": Vector3(0.02, 0.32, 0), "root": Vector3(0, -0.07, 0.0),
		"squash": 0.0 }, "f")
	c.pose(9, { "chest": Vector3(-0.14, -0.1, 0.03), "head": Vector3(-0.12, 0.34, 0.04), "root": Vector3(0, -0.06, -0.035), "squash": 0.02,
		"head_sq": -0.04 }, "l")
	c.pose(10, { "chest": Vector3(-0.16, -0.1, 0.03), "head": Vector3(-0.1, 0.33, 0.04), "root": Vector3(0, -0.08, -0.04), "squash": -0.025,
		"head_sq": 0.04 })
	c.pose(13, { "chest": Vector3(0.0, -0.12, 0.0), "head": Vector3(0.02, 0.32, 0.0), "root": Vector3(0, -0.07, -0.01), "squash": 0.005, "head_sq": 0.0 }, "f")
	c.pose(18, { "chest": Vector3(-0.03, -0.1, 0.0), "head": Vector3(-0.08, 0.26, 0.05) }, "f")
	c.pose(23, { "hips": Vector3(0, -0.08, 0), "chest": Vector3(0, -0.03, 0), "head": Vector3(0.0, 0.1, 0.0), "root": Vector3(0, -0.05, 0) })
	c.key("hand_r_pos", 4, Vector3(-0.2, 0.0, 0.4)).key("hand_r_aim", 4, Vector3(0, 0.95, 0.3).normalized())
	c.key("hand_r_pos", 7, Vector3(-0.08, 0.24, 0.64), "f").key("hand_r_aim", 7, Vector3(0, 1, 0), "f").key("hand_r_edge", 7, Vector3(0, 0, 1), "f")
	c.key("hand_r_pos", 8, Vector3(-0.08, 0.24, 0.66), "f").key("hand_r_aim", 8, Vector3(0, 1, 0), "f").key("hand_r_edge", 8, Vector3(0, 0, 1), "f")
	c.key("hand_r_pos", 9, Vector3(-0.08, 0.32, 0.6), "l").key("hand_r_aim", 9, Vector3(0, 0.8, -0.6).normalized(), "l").key("hand_r_edge", 9, Vector3(0, 0.6, 0.8).normalized(), "l")
	c.key("hand_r_pos", 10, Vector3(-0.08, 0.34, 0.57)).key("hand_r_aim", 10, Vector3(0, 0.72, -0.7).normalized()).key("hand_r_edge", 10, Vector3(0, 0.7, 0.72).normalized())
	c.key("hand_r_pos", 13, Vector3(-0.08, 0.25, 0.64), "f").key("hand_r_aim", 13, Vector3(0, 1, 0.02).normalized(), "f").key("hand_r_edge", 13, Vector3(0, 0, 1), "f")
	c.key("hand_r_pos", 18, Vector3(-0.08, 0.26, 0.64), "f").key("hand_r_aim", 18, Vector3(0, 1, 0.05).normalized(), "f").key("hand_r_edge", 18, Vector3(0, -0.05, 1).normalized(), "f")
	c.key("hand_r_pos", 23, Vector3(-0.22, -0.1, 0.34))
	c.key("hand_r_pole", 7, Vector3(-1, -0.6, -0.2)).key("hand_r_pole", 20, Vector3(-1, -0.6, -0.2))
	c.key("hand_l_pos", 4, Vector3(0.1, -0.1, 0.35))
	c.key("hand_l_pos", 7, Vector3(-0.03, 0.17, 0.58), "f").key("hand_l_pos", 8, Vector3(-0.03, 0.17, 0.6), "f")
	c.key("hand_l_pos", 10, Vector3(-0.03, 0.24, 0.54)).key("hand_l_pos", 13, Vector3(-0.03, 0.17, 0.58), "f")
	c.key("hand_l_pos", 18, Vector3(-0.03, 0.18, 0.58), "f").key("hand_l_pos", 23, Vector3(0.2, -0.15, 0.2))
	c.key("hand_l_pole", 7, Vector3(1, -0.6, -0.2)).key("hand_l_pole", 20, Vector3(1, -0.6, -0.2))
	c.key("flat", 6, 0.15).key("flat", 20, 0.15)
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fr2 := fr + Vector2(-0.02, -0.08)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(2.5, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.2, -0.3, 0.05), "foot_r_rot": Vector3(0.2, -0.3, 0) })
	c.pose(4, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.4), "foot_r_rot": Vector3(0, -0.4, 0) }, "f")
	c.pose(23, { "foot_r_pos": BWAnimClips.ankle(fr2, 0, -0.4), "foot_r_rot": Vector3(0, -0.4, 0) }, "f")
	c.pose(25, { "foot_r_pos": BWAnimClips.ankle(fr.lerp(fr2, 0.5), 0.2, -0.3, 0.05), "foot_r_rot": Vector3(0.2, -0.3, 0) })
	c.pose(26.5, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(30, { "foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0),
		"foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	return c


# ---------------------------------------------------------------- casting

## Which hand casts: the staff itself for staves; otherwise the free hand
## (bows: the right; pairs: the left, dagger and all).
static func _caster(st: String) -> String:
	if st == "staff":
		return "staff"
	if st == "fists":
		return "hand_r"                         # Palm Burst: the rear hand's open palm
	var fh := BWAnimCarry.free_hand(st)
	return "hand_" + (fh if fh != "" else "l")


## CAST (36 f). The head finds the target (f2); she gathers (f4-f8: the
## casting hand draws in to the chest, the body sinks and coils, the
## staff rises overhead) and holds the coil (f8-f10, the channel's pose);
## the release on f12 thrusts the staff head or the open hand at the
## target with a stretch; follow-through held, then back to the guard.
static func cast(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("cast", 36, false, st)
	var b := c.base
	c.marker("coil", 9).marker("release", 12).marker("hit", 13).marker("recovered", 30).marker("pose", 12)
	c.meta = { "hand_frame": "root", "kind": "cast" }
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(36, all + hand_all)
	_feet_cast(c)
	# body
	c.pose(2, { "head": Vector3(0.06, 0.2, 0.0) })
	c.pose(5, { "root": Vector3(0, -0.1, -0.02), "hips": Vector3(0, -0.18, 0), "chest": Vector3(-0.06, -0.22, 0.02),
		"head": Vector3(0.04, 0.24, 0.0), "squash": -0.025 })
	c.pose(9, { "root": Vector3(0, -0.12, -0.04), "hips": Vector3(0, -0.22, 0), "chest": Vector3(-0.1, -0.28, 0.03), "spine": Vector3(-0.04, 0, 0),
		"head": Vector3(0.0, 0.28, 0.0), "squash": -0.01, "head_sq": 0.01 }, "f")
	c.pose(11, { "root": Vector3(0, -0.14, -0.04), "squash": -0.035, "head_sq": 0.03 })
	c.pose(12, { "root": Vector3(0, -0.06, 0.06), "hips": Vector3(0.04, 0.12, 0), "chest": Vector3(0.12, 0.18, -0.02), "spine": Vector3(0.08, 0, 0),
		"head": Vector3(-0.04, -0.12, 0.0), "squash": 0.04, "head_sq": -0.03 }, "l")
	c.pose(14, { "root": Vector3(0, -0.08, 0.07), "chest": Vector3(0.14, 0.2, -0.02), "head": Vector3(-0.02, -0.16, 0.0), "squash": 0.0, "head_sq": 0.0 })
	c.pose(19, { "root": Vector3(0, -0.075, 0.06), "chest": Vector3(0.12, 0.17, -0.02) }, "f")
	c.pose(26, { "root": Vector3(0, -0.04, 0.0), "chest": Vector3(0.0, 0.0, 0.0), "hips": Vector3(0, 0, 0), "head": Vector3(-0.04, 0.0, 0.0) })
	var who := _caster(st)
	if who == "staff":
		var g := 0.0
		c.key("hand_l_grip", 3, 0.0)
		# raised high at her right and laid back (not stood up in front of
		# her face), so the thrust has a long arc to travel
		c.key("hand_r_pos", 5, Vector3(-0.3, 0.26, 0.02)).key("hand_r_aim", 5, Vector3(-0.25, 0.9, -0.36).normalized())
		c.key("hand_r_pos", 9, Vector3(-0.32, 0.42, -0.06), "f").key("hand_r_aim", 9, Vector3(-0.3, 0.75, -0.6).normalized(), "f")
		c.key("hand_r_pos", 10.5, Vector3(-0.3, 0.44, -0.1)).key("hand_r_aim", 10.5, Vector3(-0.3, 0.7, -0.66).normalized())
		c.key("hand_r_pos", 11.3, Vector3(-0.24, 0.46, 0.08)).key("hand_r_aim", 11.3, Vector3(-0.2, 0.92, 0.2).normalized())
		c.key("hand_r_pos", 12, Vector3(-0.1, 0.32, 0.42), "l").key("hand_r_aim", 12, Vector3(0.0, 0.55, 0.83).normalized(), "l")
		c.key("hand_r_pos", 14, Vector3(-0.1, 0.28, 0.46)).key("hand_r_aim", 14, Vector3(0.0, 0.5, 0.87).normalized())
		c.key("hand_r_pos", 19, Vector3(-0.1, 0.28, 0.45), "f").key("hand_r_aim", 19, Vector3(0.0, 0.52, 0.85).normalized(), "f")
		c.key("hand_r_pos", 26, Vector3(-0.34, -0.08, -0.04)).key("hand_r_aim", 26, Vector3(-0.2, 0.88, -0.45).normalized())
		c.key("hand_r_edge", 5, Vector3(0, 0, 1)).key("hand_r_edge", 26, Vector3(0, 0, 1))
		# the free hand opens up and pushes after the staff
		c.key("hand_l_pos", 5, Vector3(0.24, 0.1, 0.25)).key("hand_l_pos", 9, Vector3(0.26, 0.32, 0.18), "f")
		c.key("hand_l_pos", 12, Vector3(0.14, 0.2, 0.5), "l").key("hand_l_pos", 14, Vector3(0.14, 0.18, 0.56))
		c.key("hand_l_pos", 19, Vector3(0.15, 0.18, 0.54), "f").key("hand_l_pos", 26, Vector3(0.24, -0.2, 0.1))
		c.key("hand_l_pole", 5, Vector3(1, -0.4, -0.4)).key("hand_l_pole", 24, Vector3(1, -0.4, -0.4))
		c.key("arm_stretch", 11, 0.0).key("arm_stretch", 12, 0.07).key("arm_stretch", 15, 0.03).key("arm_stretch", 19, 0.0)
		c.key("flat", 6, 0.3).key("flat", 24, 0.3)
		c.key("hand_l_grip", 26, g)
		return c
	# a hand cast: the casting hand gathers at the chest, then thrusts open
	var sx := 1.0 if who == "hand_l" else -1.0
	c.key(who + "_pos", 5, Vector3(0.1 * sx, 0.04, 0.2))
	c.key(who + "_pos", 9, Vector3(0.04 * sx, 0.1, 0.16), "f")
	c.key(who + "_pos", 11, Vector3(0.02 * sx, 0.08, 0.12))
	c.key(who + "_pos", 12, Vector3(0.06 * sx, 0.22, 0.56), "l")
	c.key(who + "_pos", 14, Vector3(0.06 * sx, 0.24, 0.62))
	c.key(who + "_pos", 19, Vector3(0.06 * sx, 0.24, 0.6), "f")
	c.key(who + "_pos", 26, Vector3(0.24 * sx, -0.2, 0.12))
	c.key(who + "_pole", 5, Vector3(0.8 * sx, -1, -0.2)).key(who + "_pole", 24, Vector3(0.8 * sx, -1, -0.2))
	c.key(who + "_grip", 3, 0.0).key(who + "_grip", 27, float(b[who + "_grip"]))
	if st == "pair":
		c.key("hand_l_aim", 9, Vector3(0.1, 0.9, 0.3).normalized(), "f").key("hand_l_aim", 12, Vector3(0.0, 0.5, 0.86).normalized())
	if st == "fists":
		# the palm turned out: fingers up, the heel of the hand leading
		var pa := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0, 1, 0.15), Vector3(0, 0.1, -1), Vector3.ZERO)
		var pb := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.1, 1, 0.3), Vector3(-0.3, 0, -1), Vector3.ZERO)
		c.key("hand_r_aim", 9, pb.aim, "f").key("hand_r_edge", 9, pb.edge, "f")
		c.key("hand_r_aim", 12, pa.aim, "l").key("hand_r_edge", 12, pa.edge, "l")
		c.key("hand_r_aim", 19, pa.aim, "f").key("hand_r_edge", 19, pa.edge, "f")
	c.key("arm_stretch", 11, 0.0).key("arm_stretch", 12, 0.06).key("arm_stretch", 15, 0.02).key("arm_stretch", 19, 0.0)
	# the weapon hand draws back and out of the way (bows: the bow is the weapon, left)
	var wh := "hand_l" if st in ["bow", "fists"] else "hand_r"
	var wb: Vector3 = b[wh + "_pos"]
	var wx := -1.0 if wh == "hand_r" else 1.0
	c.key(wh + "_pos", 5, wb + Vector3(0.04 * wx, 0.04, -0.08))
	c.key(wh + "_pos", 9, wb + Vector3(0.06 * wx, 0.08, -0.16), "f")
	c.key(wh + "_pos", 12, wb + Vector3(0.08 * wx, 0.05, -0.24), "l")
	c.key(wh + "_pos", 19, wb + Vector3(0.08 * wx, 0.04, -0.22), "f")
	c.key(wh + "_aim", 9, (Basis.from_euler(Vector3(0.25, 0, 0)) * (b[wh + "_aim"] as Vector3)).normalized(), "f")
	c.key(wh + "_aim", 19, (Basis.from_euler(Vector3(0.3, 0, 0)) * (b[wh + "_aim"] as Vector3)).normalized(), "f")
	if BWAnimCarry.two_handed(st):
		c.key("hand_l_grip", 2, float(b.hand_l_grip)).key("hand_l_grip", 4, 0.0).key("hand_l_grip", 28, 0.0)
	return c


static func _feet_cast(c: BWAnimClips.Clip) -> void:
	var b := c.base
	var fl := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fl2 := fl + Vector2(0.03, 0.08)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	# the left foot steps out toward the target for the release, back after
	c.pose(9, { "foot_l_pos": BWAnimClips.ankle(fl, 0.25, 0.22), "foot_l_rot": Vector3(0.25, 0.22, 0) }, "f")
	c.pose(10.5, { "foot_l_pos": BWAnimClips.ankle(fl.lerp(fl2, 0.5), 0.0, 0.2, 0.06), "foot_l_rot": Vector3(0.0, 0.2, 0) })
	c.pose(12, { "foot_l_pos": BWAnimClips.ankle(fl2, -0.2, 0.18), "foot_l_rot": Vector3(-0.2, 0.18, 0) }, "l")
	c.pose(13, { "foot_l_pos": BWAnimClips.ankle(fl2, 0, 0.18), "foot_l_rot": Vector3(0, 0.18, 0) }, "f")
	c.pose(22, { "foot_l_pos": BWAnimClips.ankle(fl2, 0, 0.18), "foot_l_rot": Vector3(0, 0.18, 0) }, "f")
	c.pose(24, { "foot_l_pos": BWAnimClips.ankle(fl.lerp(fl2, 0.5), 0.1, 0.2, 0.05), "foot_l_rot": Vector3(0.1, 0.2, 0) })
	c.pose(26, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0) }, "f")
	c.pose(36, { "foot_l_pos": BWAnimClips.ankle(fl, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")


## CHANNEL (24 f loop): the cast's coil held and alive. Every channel is
## the cast's coil value plus a loop: the body bobs on a slow breath, the
## casting hand (or the staff head) circles twice, the head stays on the
## target. Frame 0 equals the coil exactly, so "cast" continues from it.
static func channel(st: String, cast_clip: BWAnimClips.Clip) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("channel", 24, true, st)
	c.meta = { "hand_frame": "root", "kind": "channel" }
	var coil := float(cast_clip.markers.coil)
	for ch in BWAnimClips.CHANNELS:
		if ch in ["contact_l", "contact_r"]:
			continue
		c.key(ch, 0, cast_clip.value(ch, coil), "a")
	var who := _caster(st)
	var hk := "hand_r" if who == "staff" else who
	var h0: Vector3 = cast_clip.value(hk + "_pos", coil)
	for i in 4:
		var f := 3.0 + i * 6.0
		var a := TAU * float(i + 1) / 4.0 * 2.0
		c.key(hk + "_pos", f, h0 + Vector3(0.03 * cos(a), 0.03 * sin(a), 0.01 * sin(a)))
	c.key(hk + "_pos", 24, h0)
	var r0: Vector3 = cast_clip.value("root", coil)
	c.key("root", 6, r0 + Vector3(0, -0.02, 0), "f").key("root", 18, r0 + Vector3(0, 0.012, 0), "f")
	var ch0: Vector3 = cast_clip.value("chest", coil)
	c.key("chest", 7, ch0 + Vector3(0.02, 0, 0)).key("chest", 19, ch0 + Vector3(-0.025, 0, 0))
	c.key("squash", 6, -0.012).key("squash", 18, 0.012)
	c.key("head_sq", 8, 0.015).key("head_sq", 20, -0.01)
	c.key(hk + "_pos", 0, h0)
	return c


# -------------------------------------------------------------------- fists

## A fist's hand channels (root frame in the strikes): the knuckles drive
## toward `punch`, the back of the hand toward `back` (BWCharacterPose._fist).
static func _fk(side: String, pos: Vector3, punch: Vector3, back: Vector3, extra: Dictionary = {}) -> Dictionary:
	var h := "hand_" + side
	var s := 1.0 if side == "r" else -1.0
	var f := BWCharacterPose._fist(side, pos, punch, back, Vector3(-0.8 * s, -0.6, -0.3))
	var d := { h + "_pos": pos, h + "_aim": f.aim, h + "_edge": f.edge }
	d.merge(extra, true)
	return d


## Guard fists (chest-ish; the static idle key): rear right at the jaw,
## lead left forward.
static func _fist_guard(side: String) -> Dictionary:
	if side == "r":
		return _fk("r", Vector3(-0.19, 0.30, 0.26), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0))
	return _fk("l", Vector3(0.17, 0.34, 0.36), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0))


## The lead (left) jab out and back, palm down; the rear fist stays home.
static func _jab_l(depth: float = 1.0) -> Dictionary:
	return _fk("l", Vector3(0.04, 0.32, 0.36 + 0.4 * depth), Vector3(-0.08, 0.05, 1), Vector3(0.2, 1, 0), { "arm_stretch": 0.04 * depth })


static func _cross_r(depth: float = 1.0) -> Dictionary:
	return _fk("r", Vector3(-0.02, 0.31, 0.3 + 0.44 * depth), Vector3(0.12, 0.05, 1), Vector3(-0.2, 1, 0), { "arm_stretch": 0.04 * depth })


## FISTS: the jab (the basic attack, 30 f). The dash in on the reference
## body, the lead fist snapped out on the hit and pulled straight back to
## the guard (a jab returns on the line it went out on), the rear fist
## kept at the jaw.
static func _strike_fists() -> BWAnimClips.Clip:
	var beats := [0, 2, 5, 7, 9, 10, 13, 16, 20, 23, 27, 30]
	var hands := {
		4.0: _m(_fist_guard("r"), _fk("l", Vector3(0.17, 0.32, 0.32), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0))),
		8.0: _m(_fk("r", Vector3(-0.17, 0.32, 0.22), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0)),
			_fk("l", Vector3(0.16, 0.30, 0.26), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0), { "_mode": "f" })),
		# D389 (it read small): the fist dips and drives out on a wider arc,
		# rising into a longer, stretched punch; the shoulders turn harder
		11.0: _fk("l", Vector3(0.2, 0.24, 0.34), Vector3(-0.1, 0.2, 1), Vector3(0.5, 0.85, 0), { "_mode": "l", "smear": 0.5 }),
		12.5: _fk("l", Vector3(0.12, 0.27, 0.58), Vector3(-0.08, 0.12, 1), Vector3(0.4, 0.9, 0), { "_mode": "l", "smear": 1.0 }),
		14.0: _m(_jab_l(1.22), { "smear": 0.7, "arm_stretch": 0.1 }),
		15.0: _m(_jab_l(1.18), { "smear": 0.2, "arm_stretch": 0.09 }),
		17.0: _m(_jab_l(0.95), { "smear": 0.0, "arm_stretch": 0.03 }),
		20.0: _fk("l", Vector3(0.15, 0.33, 0.4), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0), { "arm_stretch": 0.0 }),
		27.0: _m(_fist_guard("r"), _fist_guard("l")),
	}
	# (twist reversed: a lead-hand jab turns the left shoulder in, the
	# chest to her right, where the reference cut turns it left)
	var c := _melee("strike", "fists", beats, -0.95, hands, 0.85)
	# the weight goes in behind it: a deeper lunge and a squash on the hit
	var fh := _warp(14.0, beats)
	c.key("root", fh, (c.value("root", fh) as Vector3) + Vector3(0, -0.035, 0.1))
	c.key("squash", fh, -0.045).key("head_sq", fh, 0.035)
	c.key("squash", _warp(16.0, beats), 0.0).key("head_sq", _warp(16.0, beats), 0.0)
	return c


## FLURRY (36 f): three jabs (left, right, left) on hit / hit2 / hit3,
## each snapped out and back, the body rocking with each; the last one is
## the one that lays the element on the hex.
static func _strike_flurry() -> BWAnimClips.Clip:
	var beats := [0, 2, 5, 7, 9, 10, 16, 22, 26, 29, 33, 36]
	var hands := {
		4.0: _m(_fist_guard("r"), _fist_guard("l")),
		8.0: _m(_fk("r", Vector3(-0.17, 0.31, 0.22), Vector3(0.1, 0.35, 1), Vector3(-0.7, 0.7, 0)),
			_fk("l", Vector3(0.16, 0.30, 0.26), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0), { "_mode": "f" })),
		12.5: _m(_fk("l", Vector3(0.12, 0.32, 0.5), Vector3(-0.06, 0.1, 1), Vector3(0.4, 0.9, 0), { "_mode": "l", "smear": 0.5 }), {}),
		14.0: _m(_jab_l(), _fist_guard("r")),
		15.0: _m(_jab_l(0.6), _fk("r", Vector3(-0.12, 0.31, 0.4), Vector3(0.1, 0.1, 1), Vector3(-0.3, 1, 0))),
		16.0: _m(_m(_fist_guard("l"), _cross_r()), { "smear": 0.5 }),
		17.0: _m(_cross_r(0.9), {}),
		18.0: _m(_cross_r(0.5), _fk("l", Vector3(0.12, 0.32, 0.5), Vector3(-0.06, 0.1, 1), Vector3(0.4, 0.9, 0))),
		19.0: _m(_m(_fist_guard("r"), _jab_l()), { "smear": 0.5 }),
		21.0: _m(_jab_l(0.9), { "smear": 0.0 }),
		24.0: _fk("l", Vector3(0.15, 0.33, 0.42), Vector3(-0.05, 0.3, 1), Vector3(0.6, 0.8, 0), { "arm_stretch": 0.0 }),
		28.0: _m(_fist_guard("r"), _fist_guard("l")),
	}
	var c := _melee("strike_flurry", "fists", beats, -0.5, hands, 0.85)
	var f2 := _warp(17.0, beats)
	var f3 := _warp(20.0, beats)
	c.marker("hit2", f2).marker("hit3", f3)
	# each jab rocks the shoulders: the chest turns into the punching side
	var f1 := _warp(14.0, beats)
	var ch0: Vector3 = c.value("chest", f2 - 2.0)
	ch0.y = 0.0
	c.key("chest", f1, ch0 + Vector3(0.02, -0.32, 0.0)).key("chest", f2, ch0 + Vector3(0.03, 0.3, 0.0))
	c.key("chest", f3, ch0 + Vector3(0.03, -0.32, 0.0)).key("chest", f3 + 3.0, ch0 + Vector3(0.0, -0.12, 0.0))
	c.meta["hits"] = 3
	return c


## UPPERCUT (42 f): sinks low with the rear fist dropped to the hip, drives
## up through the legs and the fist rises under the chin line on the hit,
## up on the toes, the follow-through high; the lead fist keeps covering.
static func _strike_uppercut() -> BWAnimClips.Clip:
	var beats := [0, 4, 9, 11, 14, 15, 19, 23, 28, 31, 37, 42]
	var hands := {
		4.0: _m(_fk("r", Vector3(-0.2, 0.18, 0.2), Vector3(0.1, 0.6, 0.8), Vector3(-0.8, 0.4, 0)), _fist_guard("l")),
		8.0: _m(_fk("r", Vector3(-0.22, -0.04, 0.16), Vector3(0.15, 1, 0.3), Vector3(-0.3, 0, -1), { "_mode": "f" }),
			_fk("l", Vector3(0.15, 0.34, 0.32), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0))),
		12.0: _fk("r", Vector3(-0.12, 0.24, 0.42), Vector3(0.05, 1, 0.3), Vector3(0, 0, -1), { "_mode": "l", "smear": 0.8 }),
		14.0: _fk("r", Vector3(-0.05, 0.5, 0.46), Vector3(0, 1, 0.15), Vector3(0, 0.1, -1), { "arm_stretch": 0.07, "smear": 0.8 }),
		16.0: _fk("r", Vector3(-0.05, 0.56, 0.42), Vector3(0, 1, 0.1), Vector3(0, 0.1, -1), { "smear": 0.3 }),
		18.0: _fk("r", Vector3(-0.07, 0.6, 0.36), Vector3(-0.05, 1, -0.05), Vector3(0, 0.1, -1), { "smear": 0.0, "arm_stretch": 0.0, "_mode": "f" }),
		22.0: _fk("r", Vector3(-0.14, 0.42, 0.3), Vector3(0.1, 0.7, 0.7), Vector3(-0.6, 0.6, 0)),
		27.0: _m(_fist_guard("r"), _fist_guard("l")),
	}
	var c := _melee("strike_uppercut", "fists", beats, 0.85, hands, 0.9)
	# the drive: lower in the coil, up through the toes on the hit
	c.key("root", _warp(8.0, beats), Vector3(0, -0.2, -0.05), "f")
	c.key("root", _warp(15.0, beats), Vector3(0, -0.06, 0.1))
	c.key("squash", _warp(14.0, beats), 0.05).key("leg_stretch", _warp(14.0, beats), 0.04).key("leg_stretch", _warp(19.0, beats), 0.0)
	c.key("leg_stretch", 0.0, 0.0).key("leg_stretch", float(beats[11]), 0.0)
	return c


## PALM BURST as a strike (36 f): the right hand drawn back to the hip,
## then the heel of the open hand driven out at chest height on the hit,
## fingers up, the body behind it; held a beat while the element pours.
static func _strike_palm() -> BWAnimClips.Clip:
	var beats := [0, 3, 8, 10, 12, 13, 18, 22, 26, 29, 33, 36]
	var palm := func(pos: Vector3, x: Dictionary = {}) -> Dictionary:
		return _fk("r", pos, Vector3(0, 1, 0.15), Vector3(0, 0.1, -1), x)
	var hands := {
		4.0: _m(_fk("r", Vector3(-0.2, 0.06, 0.12), Vector3(0.1, 0.8, 0.6), Vector3(-0.6, 0.2, -0.6)), _fist_guard("l")),
		8.0: _m(palm.call(Vector3(-0.24, -0.04, -0.02), { "_mode": "f" }), _fk("l", Vector3(0.16, 0.3, 0.38), Vector3(-0.05, 0.3, 1), Vector3(0.7, 0.7, 0))),
		12.0: palm.call(Vector3(-0.1, 0.2, 0.44), { "_mode": "l", "smear": 0.7 }),
		14.0: _m(palm.call(Vector3(-0.04, 0.26, 0.64), { "arm_stretch": 0.07, "smear": 0.4 }), _fk("l", Vector3(0.18, 0.22, 0.12), Vector3(0, 0.4, 1), Vector3(0.7, 0.7, 0))),
		18.0: palm.call(Vector3(-0.04, 0.27, 0.62), { "arm_stretch": 0.05, "smear": 0.0, "_mode": "f" }),
		22.0: palm.call(Vector3(-0.06, 0.25, 0.58), { "arm_stretch": 0.0 }),
		27.0: _m(_fist_guard("r"), _fist_guard("l")),
	}
	var c := _melee("strike_palm", "fists", beats, 0.4, hands, 0.85)
	return c



# ------------------------------------------------------- skill clips (D102)

## A horizontal blade held out at local azimuth `a` (0 = straight ahead,
## -PI/2 = her right, +PI/2 = her left; root frame), `r` out from the
## body, at height `y`; the edge faces the way a counter-clockwise turn
## (seen from above) carries it.
static func _out(a: float, r: float, y: float, hand: String = "hand_r", extra: Dictionary = {}) -> Dictionary:
	var d := { hand + "_pos": Vector3(r * sin(a), y, r * cos(a)), hand + "_aim": Vector3(sin(a), 0.1, cos(a)).normalized(),
		hand + "_edge": Vector3(cos(a), 0.0, -sin(a)) }
	d.merge(extra, true)
	return d


## SPIN (one: sword, scimitar; pair: daggers), 40 f. A leaping 360° cut.
## Anticipation (f0-f9, coil held by "windup"): she sinks and winds the
## hips and chest to the right, the blade reaching back-right and low, the
## head kept on the target; compresses on f10. The whip (f11-f19): off both
## feet, the whole body turns a full circle counter-clockwise (meta
## spin_yaw, applied to the rig by BWCharacter: 0 before launch, exactly
## TAU from the hit on, so planted feet never twist), the head spotting
## ahead, the blade held flat and extended so the smear draws the circle;
## she lands on f18 skidding through the last of the turn (skid), and the
## arm whips the blade across the front on the hit (f19). Hit-stop, the
## chest overshoots left, the blade follows through low-left, then the hop
## home and a settle. Daggers: the left blade rides the opposite side
## (out front-left in the coil, opening wide back-left on the hit).
static func _strike_spin(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("strike_spin", 40, false, st)
	var b := c.base
	var pair := st == "pair"
	c.marker("coil", 9).marker("launch", 11).marker("land", 18).marker("hit", 19)
	c.marker("hop_start", 28).marker("hop_end", 31).marker("recovered", 36).marker("pose", 15)
	c.meta = { "engage": 0.95 if pair else 1.05, "hand_frame": "root", "kind": "melee" }
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(40, all + hand_all)
	# --- body: coil right, unwind through the air, overshoot left, settle
	c.pose(3, { "root": Vector3(0, -0.07, -0.01), "hips": Vector3(-0.02, -0.15, 0), "chest": Vector3(-0.02, -0.2, 0), "head": Vector3(0.03, 0.22, 0) })
	c.pose(6, { "root": Vector3(0, -0.12, -0.03), "hips": Vector3(-0.03, -0.34, 0.02), "chest": Vector3(-0.06, -0.48, 0.04),
		"head": Vector3(0.05, 0.55, -0.03), "squash": -0.015, "head_sq": 0.015 })
	c.pose(9, { "root": Vector3(0, -0.15, -0.04), "hips": Vector3(-0.04, -0.42, 0.03), "spine": Vector3(-0.03, -0.06, 0),
		"chest": Vector3(-0.08, -0.6, 0.05), "head": Vector3(0.06, 0.66, -0.04), "squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(10, { "root": Vector3(0, -0.2, -0.03), "squash": -0.045, "head_sq": 0.04 })
	c.pose(11, { "root": Vector3(0, -0.02, 0.02), "hips": Vector3(0.02, -0.3, 0.0), "chest": Vector3(-0.02, -0.45, 0.02),
		"head": Vector3(0.0, 0.85, 0.0), "squash": 0.05, "head_sq": -0.03 })
	# the head spots ahead of the turn, the chest unwinds after the hips
	c.pose(13, { "root": Vector3(0, 0.06, 0.04), "hips": Vector3(0.04, -0.05, 0.0), "spine": Vector3(0.0, 0.0, 0.0),
		"chest": Vector3(0.02, -0.25, 0.0), "head": Vector3(-0.02, 0.6, 0.0), "squash": 0.02, "head_sq": 0.0 })
	c.pose(16, { "root": Vector3(0, 0.04, 0.05), "hips": Vector3(0.06, 0.12, -0.02), "chest": Vector3(0.06, 0.05, -0.02),
		"head": Vector3(-0.02, 0.2, 0.0), "squash": 0.0 })
	c.pose(18, { "root": Vector3(0, -0.16, 0.08), "hips": Vector3(0.1, 0.2, -0.03), "chest": Vector3(0.12, 0.22, -0.04),
		"head": Vector3(0.0, -0.15, 0.02), "squash": -0.04, "head_sq": 0.03 }, "l")
	c.pose(19, { "root": Vector3(0, -0.21, 0.1), "hips": Vector3(0.12, 0.3, -0.04), "chest": Vector3(0.18, 0.4, -0.06),
		"head": Vector3(-0.02, -0.38, 0.04), "squash": -0.055, "head_sq": 0.05 })
	c.pose(21, { "root": Vector3(0, -0.212, 0.1), "chest": Vector3(0.19, 0.44, -0.06), "squash": -0.045, "head_sq": 0.04 })
	c.pose(23, { "root": Vector3(0, -0.2, 0.09), "hips": Vector3(0.1, 0.38, -0.04), "chest": Vector3(0.2, 0.6, -0.07),
		"head": Vector3(0.08, -0.5, 0.05), "squash": 0.02, "head_sq": -0.015 }, "f")
	c.pose(26, { "root": Vector3(0, -0.21, 0.07), "hips": Vector3(0.06, 0.26, -0.02), "chest": Vector3(0.12, 0.38, -0.03),
		"head": Vector3(0.04, -0.36, 0.02), "squash": -0.03, "head_sq": 0.03 })
	c.pose(28, { "root": Vector3(0, -0.06, 0.02), "hips": Vector3(-0.02, 0.08, 0.0), "chest": Vector3(-0.02, 0.1, 0.0),
		"head": Vector3(-0.04, -0.1, 0.02), "squash": 0.03, "head_sq": -0.02 })
	c.pose(30, { "root": Vector3(0, -0.03, -0.01), "hips": Vector3(0.0, -0.02, 0.0), "chest": Vector3(0.0, 0.0, 0.0) })
	c.pose(31, { "root": Vector3(0, -0.11, -0.015), "squash": -0.04, "head_sq": 0.04, "head": Vector3(0.06, 0.04, 0.0) }, "f")
	c.pose(34, { "root": Vector3(0, -0.02, 0.0), "squash": 0.015, "head_sq": -0.01 })
	c.pose(36, { "root": Vector3(0, -0.045, 0.0), "squash": 0.0, "head_sq": 0.0 }, "f")
	# --- the right blade: [local azimuth, reach, height] (the rig adds the turn)
	var ar := { 4: [-1.0, 0.3, -0.05], 7: [-1.95, 0.4, 0.06], 9: [-2.36, 0.42, 0.1], 10: [-2.38, 0.4, 0.06],
		13: [-2.2, 0.44, 0.12], 15: [-1.95, 0.46, 0.12], 17: [-1.3, 0.47, 0.1], 18: [-0.65, 0.48, 0.06],
		19: [0.0, 0.5, 0.04], 20: [0.32, 0.48, 0.02], 21: [0.42, 0.46, 0.01], 23: [0.8, 0.4, -0.04], 26: [0.55, 0.32, -0.08] }
	var al := { 4: [0.4, 0.3, 0.0], 7: [0.6, 0.34, 0.08], 9: [0.78, 0.36, 0.1], 10: [0.78, 0.34, 0.06],
		13: [0.94, 0.38, 0.12], 15: [1.24, 0.4, 0.12], 17: [1.84, 0.4, 0.1], 18: [2.1, 0.38, 0.06],
		19: [2.3, 0.38, 0.04], 21: [2.36, 0.36, 0.02], 23: [2.4, 0.34, -0.02], 26: [1.7, 0.3, -0.06] }
	for f in ar:
		var k: Array = ar[f]
		var mode := "f" if f in [9, 23] else ("l" if f in [17, 18] else "a")
		var x := {}
		if f >= 12 and f <= 20:
			x["smear"] = 1.0
		if f in [19, 20]:
			x["arm_stretch"] = 0.06
		c.pose(float(f), _out(float(k[0]), float(k[1]), float(k[2]), "hand_r", x), mode)
	c.key("smear", 11.0, 0.0).key("smear", 22.0, 0.35).key("smear", 24.0, 0.0)
	c.key("arm_stretch", 17.0, 0.02).key("arm_stretch", 23.0, 0.0)
	c.key("hand_r_pole", 7, Vector3(-0.6, -1, -0.2)).key("hand_r_pole", 23, Vector3(-0.4, -1, 0.3)).key("hand_r_pole", 27, Vector3(-0.6, -0.6, -0.6))
	c.key("flat", 6, 0.2).key("flat", 26, 0.3)
	if pair:
		for f in al:
			var k: Array = al[f]
			c.pose(float(f), _out(float(k[0]), float(k[1]), float(k[2]), "hand_l"), "f" if f in [9, 23] else "a")
		c.key("hand_l_pole", 7, Vector3(0.6, -1, -0.2)).key("hand_l_pole", 23, Vector3(0.6, -1, 0.0))
	else:
		# the free arm: reaches at the target in the coil, opens out for the
		# turn, is flung back on the cut
		c.key("hand_l_pos", 6, Vector3(0.26, 0.1, 0.3)).key("hand_l_pos", 9, Vector3(0.28, 0.14, 0.34), "f")
		c.key("hand_l_pos", 14, Vector3(0.38, 0.12, 0.02)).key("hand_l_pos", 19, Vector3(0.34, 0.02, -0.24))
		c.key("hand_l_pos", 23, Vector3(0.36, 0.04, -0.3), "f").key("hand_l_pos", 28, Vector3(0.3, -0.18, 0.0))
	# recovery: the blade comes back in to the guard on the hop
	c.key("hand_r_pos", 29, Vector3(-0.1, -0.12, 0.3)).key("hand_r_aim", 29, Vector3(-0.3, 0.7, 0.6).normalized())
	c.key("hand_r_pos", 32, b.hand_r_pos + Vector3(0.01, -0.04, 0.0)).key("hand_r_aim", 32, b.hand_r_aim, "f")
	c.key("hand_r_edge", 31, b.hand_r_edge, "f")
	if pair:
		c.key("hand_l_pos", 29, Vector3(0.12, -0.12, 0.3)).key("hand_l_aim", 29, Vector3(0.3, 0.7, 0.6).normalized())
		c.key("hand_l_pos", 32, b.hand_l_pos + Vector3(-0.01, -0.04, 0.0)).key("hand_l_aim", 32, b.hand_l_aim, "f")
		c.key("hand_l_edge", 31, b.hand_l_edge, "f")
	# --- feet: planted through the coil, up on the balls on f10, tucked in
	# the air (they turn with her), a landing lunge, the hop home
	var fl0 := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr0 := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fl1 := Vector2(0.15, 0.32)
	var fr1 := Vector2(-0.14, -0.22)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(8, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(10, { "foot_l_pos": BWAnimClips.ankle(fl0, 0.4, 0.22), "foot_l_rot": Vector3(0.4, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0.45, -0.22), "foot_r_rot": Vector3(0.45, -0.22, 0) })
	c.pose(12, { "foot_l_pos": Vector3(0.12, 0.24, 0.1), "foot_l_rot": Vector3(-0.05, 0.2, 0),
		"foot_r_pos": Vector3(-0.12, 0.22, -0.08), "foot_r_rot": Vector3(0.6, -0.2, 0) })
	c.pose(15, { "foot_l_pos": Vector3(0.12, 0.28, 0.14), "foot_l_rot": Vector3(-0.1, 0.18, 0),
		"foot_r_pos": Vector3(-0.12, 0.25, -0.1), "foot_r_rot": Vector3(0.7, -0.25, 0) })
	c.pose(17, { "foot_l_pos": BWAnimClips.ankle(fl1, -0.2, 0.15, 0.07), "foot_l_rot": Vector3(-0.2, 0.15, 0),
		"foot_r_pos": BWAnimClips.ankle(fr1, 0.6, -0.3, 0.08), "foot_r_rot": Vector3(0.6, -0.3, 0) })
	c.pose(18, { "foot_l_pos": BWAnimClips.ankle(fl1, -0.12, 0.15), "foot_l_rot": Vector3(-0.12, 0.15, 0),
		"foot_r_pos": BWAnimClips.ankle(fr1, 0.62, -0.32), "foot_r_rot": Vector3(0.62, -0.32, 0) }, "l")
	c.pose(19, { "foot_l_pos": BWAnimClips.ankle(fl1, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0) }, "f")
	c.pose(26, { "foot_l_pos": BWAnimClips.ankle(fl1, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0),
		"foot_r_pos": BWAnimClips.ankle(fr1, 0.62, -0.32), "foot_r_rot": Vector3(0.62, -0.32, 0) }, "f")
	c.pose(29, { "foot_l_pos": Vector3(0.13, 0.18, 0.24), "foot_l_rot": Vector3(-0.15, 0.2, 0),
		"foot_r_pos": Vector3(-0.13, 0.16, -0.12), "foot_r_rot": Vector3(0.45, -0.3, 0) })
	c.pose(31, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(40, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	# the landing pivots through the last of the turn: contacts off
	c.skid = [[17.0, 19.5]]
	# --- the turn itself (radians, CCW from above), sampled at the bake rate:
	# 0 until launch, TAU from the hit on (BWAnimator.spin_yaw)
	var turn := [[11.0, 0.0, "a"], [12.0, 0.03, "a"], [13.0, 0.1, "a"], [14.0, 0.22, "a"], [15.0, 0.38, "a"],
		[16.0, 0.55, "a"], [17.0, 0.72, "l"], [18.0, 0.88, "l"], [19.0, 1.0, "f"]]
	var ys: Array = []
	for i in int(round(40.0 / BWAnimClips.FPS * BWAnimClips.BAKE_HZ)) + 1:
		var f := i * BWAnimClips.FPS / BWAnimClips.BAKE_HZ
		ys.append(TAU * clampf(float(BWAnimClips.eval_keys(turn, f, false, 40.0)), 0.0, 1.0))
	c.meta["spin_yaw"] = ys
	c.meta["spin_hz"] = BWAnimClips.BAKE_HZ
	return c


## PISTOL WHIP (pistol), 32 f. A close backhand with the butt. Wind-up
## (f0-f7): the gun comes up and flips butt-first, cocked by her left
## shoulder, the chest wound left, head on the target. The blow (f9-f12):
## a hop in (launch..land) and a backhanded clubbing arc, high-left to
## front-right and down, the butt leading (smear); hit-stop, the gun
## rebounds off the blow (f15) and the arm carries on low to her right;
## she flips it back to a hip-level aim (a smug look), hops home, settles.
static func _strike_pistol_whip() -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("strike_pistol_whip", 32, false, "pistol")
	var b := c.base
	c.marker("coil", 7).marker("launch", 9).marker("land", 11).marker("hit", 12)
	c.marker("hop_start", 22).marker("hop_end", 25).marker("recovered", 28).marker("pose", 12)
	c.meta = { "engage": 0.85, "hand_frame": "root", "kind": "melee" }
	var all := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hand_all: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hand_all.append(ch)
	c.at_base(0, all + hand_all)
	c.at_base(32, all + hand_all)
	# body: wind left, swing right through the blow, recoil, settle
	c.pose(2, { "head": Vector3(0.0, -0.12, 0.0) })
	c.pose(5, { "root": Vector3(0, -0.08, -0.02), "hips": Vector3(-0.02, 0.16, 0.0), "chest": Vector3(-0.06, 0.32, -0.03),
		"head": Vector3(0.04, -0.34, 0.02) })
	c.pose(7, { "root": Vector3(0, -0.11, -0.03), "hips": Vector3(-0.03, 0.2, 0.0), "chest": Vector3(-0.1, 0.4, -0.04),
		"head": Vector3(0.06, -0.42, 0.03), "squash": 0.0, "head_sq": 0.0 }, "f")
	c.pose(8, { "root": Vector3(0, -0.17, -0.02), "squash": -0.04, "head_sq": 0.035 })
	c.pose(9, { "root": Vector3(0, -0.02, 0.03), "hips": Vector3(0.04, 0.1, 0.0), "chest": Vector3(0.0, 0.25, -0.02),
		"head": Vector3(0.0, -0.3, 0.0), "squash": 0.045, "head_sq": -0.03 })
	c.pose(11, { "root": Vector3(0, -0.15, 0.09), "hips": Vector3(0.08, -0.18, 0.03), "chest": Vector3(0.12, -0.3, 0.05),
		"head": Vector3(-0.02, 0.2, -0.02), "squash": -0.04, "head_sq": 0.03 }, "l")
	c.pose(12, { "root": Vector3(0, -0.19, 0.1), "hips": Vector3(0.1, -0.26, 0.04), "chest": Vector3(0.16, -0.45, 0.06),
		"head": Vector3(-0.04, 0.32, -0.03), "squash": -0.05, "head_sq": 0.05 })
	c.pose(14, { "root": Vector3(0, -0.18, 0.09), "chest": Vector3(0.1, -0.38, 0.05), "head": Vector3(-0.08, 0.28, -0.02),
		"squash": -0.02, "head_sq": 0.0 })
	c.pose(17, { "root": Vector3(0, -0.17, 0.08), "hips": Vector3(0.06, -0.3, 0.03), "chest": Vector3(0.12, -0.52, 0.05),
		"head": Vector3(0.0, 0.4, -0.02), "squash": 0.01 }, "f")
	c.pose(20, { "root": Vector3(0, -0.19, 0.07), "hips": Vector3(0.03, -0.18, 0.02), "chest": Vector3(0.02, -0.25, 0.02),
		"head": Vector3(-0.1, 0.2, 0.04), "squash": -0.025, "head_sq": 0.02 })
	c.pose(22, { "root": Vector3(0, -0.05, 0.02), "hips": Vector3(0.0, -0.06, 0.0), "chest": Vector3(0.0, -0.08, 0.0),
		"head": Vector3(-0.04, 0.08, 0.0), "squash": 0.025, "head_sq": -0.02 })
	c.pose(25, { "root": Vector3(0, -0.1, -0.01), "squash": -0.035, "head_sq": 0.03 }, "f")
	c.pose(28, { "root": Vector3(0, -0.03, 0.0), "squash": 0.01, "head_sq": -0.01 })
	# the gun (root frame): aim = the gun's up, edge = the barrel; the butt
	# leads the blow (aim points back along the swing)
	c.pose(3, _gun(Vector3(-0.12, -0.02, 0.32), Vector3(0, 0.9, 0.3), Vector3(0, -0.3, 0.95)))
	c.pose(5, _gun(Vector3(0.1, 0.2, 0.08), Vector3(0.3, 0.5, -0.8), Vector3(0.1, 0.85, 0.5), { "flat": 0.2 }))
	c.pose(7, _gun(Vector3(0.22, 0.3, -0.1), Vector3(0.6, 0.25, -0.75), Vector3(0.25, 0.9, 0.5)), "f")
	c.pose(8, _gun(Vector3(0.24, 0.31, -0.13), Vector3(0.6, 0.25, -0.75), Vector3(0.25, 0.9, 0.5)))
	c.pose(10, _gun(Vector3(0.12, 0.3, 0.4), Vector3(0.58, 0.3, -0.76), Vector3(0.28, 0.88, 0.5), { "smear": 1.0 }), "l")
	c.pose(11, _gun(Vector3(-0.06, 0.24, 0.56), Vector3(0.62, 0.35, -0.7), Vector3(0.3, 0.85, 0.5), { "smear": 1.0, "arm_stretch": 0.05 }), "l")
	c.pose(12, _gun(Vector3(-0.2, 0.16, 0.55), Vector3(0.7, 0.35, -0.6), Vector3(0.3, 0.88, 0.4), { "smear": 1.0, "arm_stretch": 0.07 }))
	c.pose(13, _gun(Vector3(-0.26, 0.13, 0.5), Vector3(0.72, 0.37, -0.58), Vector3(0.3, 0.88, 0.4), { "smear": 0.4, "arm_stretch": 0.06 }))
	# the rebound: the blow kicks the gun back up, then it carries on low right
	c.pose(15, _gun(Vector3(-0.24, 0.22, 0.46), Vector3(0.4, 0.65, -0.65), Vector3(0.2, 0.7, 0.7), { "smear": 0.0, "arm_stretch": 0.02 }))
	c.pose(17, _gun(Vector3(-0.38, 0.04, 0.3), Vector3(0.3, 0.75, -0.55), Vector3(0.1, 0.6, 0.8), { "arm_stretch": 0.0 }), "f")
	# flipped back to a low aim at them
	c.pose(20, _gun(Vector3(-0.2, 0.0, 0.44), Vector3(0, 0.95, 0.3), Vector3(0, -0.3, 0.95)))
	c.pose(23, _gun(Vector3(-0.2, -0.04, 0.42), Vector3(0, 0.95, 0.3), Vector3(0, -0.3, 0.95)), "f")
	c.key("hand_r_pos", 27, b.hand_r_pos + Vector3(0.0, 0.02, 0.02))
	c.key("hand_r_pole", 5, Vector3(-0.6, -1, -0.3)).key("hand_r_pole", 12, Vector3(-1, -0.6, -0.2)).key("hand_r_pole", 22, Vector3(-1, -0.6, -0.2))
	# the free hand: up to guard the face in the wind-up, flung back on the blow
	c.key("hand_l_pos", 5, Vector3(0.16, 0.16, 0.3)).key("hand_l_pos", 8, Vector3(0.18, 0.2, 0.32), "f")
	c.key("hand_l_pos", 12, Vector3(0.32, 0.04, -0.18)).key("hand_l_pos", 17, Vector3(0.34, 0.0, -0.24), "f")
	c.key("hand_l_pos", 23, Vector3(0.3, -0.2, 0.02))
	c.key("hand_l_pole", 5, Vector3(0.6, -1, -0.2)).key("hand_l_pole", 22, Vector3(0.6, -1, -0.2))
	c.key("flat", 20, 0.2)
	c.key("smear", 8, 0.0, "f")
	# feet: a short hop in onto a lunge (launch..land), the hop home
	var fl0 := BWAnimClips.ground_of(b.foot_l_pos, 0.22)
	var fr0 := BWAnimClips.ground_of(b.foot_r_pos, -0.22)
	var fl1 := Vector2(0.14, 0.34)
	var fr1 := Vector2(-0.13, -0.2)
	c.pose(0, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(7, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(8, { "foot_l_pos": BWAnimClips.ankle(fl0, 0.35, 0.22), "foot_l_rot": Vector3(0.35, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0.4, -0.22), "foot_r_rot": Vector3(0.4, -0.22, 0) })
	c.pose(9.5, { "foot_l_pos": Vector3(0.13, 0.2, 0.22), "foot_l_rot": Vector3(-0.1, 0.18, 0),
		"foot_r_pos": Vector3(-0.13, 0.18, -0.14), "foot_r_rot": Vector3(0.7, -0.3, 0) })
	c.pose(11, { "foot_l_pos": BWAnimClips.ankle(fl1, -0.1, 0.15), "foot_l_rot": Vector3(-0.1, 0.15, 0),
		"foot_r_pos": BWAnimClips.ankle(fr1, 0.55, -0.3), "foot_r_rot": Vector3(0.55, -0.3, 0) }, "l")
	c.pose(12, { "foot_l_pos": BWAnimClips.ankle(fl1, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0) }, "f")
	c.pose(20, { "foot_l_pos": BWAnimClips.ankle(fl1, 0, 0.15), "foot_l_rot": Vector3(0, 0.15, 0),
		"foot_r_pos": BWAnimClips.ankle(fr1, 0.55, -0.3), "foot_r_rot": Vector3(0.55, -0.3, 0) }, "f")
	c.pose(23, { "foot_l_pos": Vector3(0.13, 0.17, 0.22), "foot_l_rot": Vector3(-0.15, 0.2, 0),
		"foot_r_pos": Vector3(-0.13, 0.15, -0.1), "foot_r_rot": Vector3(0.45, -0.3, 0) })
	c.pose(25, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	c.pose(32, { "foot_l_pos": BWAnimClips.ankle(fl0, 0, 0.22), "foot_l_rot": Vector3(0, 0.22, 0),
		"foot_r_pos": BWAnimClips.ankle(fr0, 0, -0.22), "foot_r_rot": Vector3(0, -0.22, 0) }, "f")
	return c


static func _gun(pos: Vector3, aim: Vector3, edge: Vector3, extra: Dictionary = {}) -> Dictionary:
	var d := { "hand_r_pos": pos, "hand_r_aim": aim.normalized(), "hand_r_edge": edge.normalized() }
	d.merge(extra, true)
	return d

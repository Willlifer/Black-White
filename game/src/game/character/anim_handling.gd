class_name BWAnimHandling
extends RefCounted
## Weapon handling for every set (design/art/ANIMATION.md, "Weapon
## handling", D80). The author: "the weapons seem incredibly stiff ... have
## units swap between holding the weapon at their sides, to placing them
## over their shoulder, to testing their heft. Admiring them." Bodies stay
## CALM (D65); the variety is in how the weapon is held.
##
## HOLDS: sustained ways of standing with the weapon. The idle rotates
## between them (BWAnimator), each change an authored transition:
##   guard      the home pose (the set's guard, the `idle` loop)
##   side       at the side, blade down, relaxed (heavy: one hand, the tip
##              resting on the floor)
##   shoulder   resting on the shoulder (bow: slung; pistol: muzzle up)
##   ground     heavy weapons and staves planted, leaning on them (the
##              solver's `plant` puts each weapon's end on the floor)
##   reverse    daggers: the reverse (icepick) grip. The flip in and out is
##              the transition; the grip persists through the idle until it
##              flips back, and any combat pose flips it back to forward
##              first (BWAnimator's hand-led return, ~0.25 s)
## Clips: hold_<h> (loop: the calm idle body + the hold's hands),
## hold_<h>_in (guard -> h), hold_<h>_out (h -> guard).
##
## ACTIONS: one-shots that start and end on a hold:
##   act_heft (guard) / act_heft_side      lift it, weigh it (two small
##                                         bounces of the weapon, the tip
##                                         lagging), tilt it, back
##   act_admire (guard) / act_admire_side  raise it to eye level, turn it to
##                                         see both flats, sight along it,
##                                         wipe it with the free hand
##   idle_weapon (guard)                   the style's trick, now at full
##                                         size (hands uncalmed)
##   act_settle (shoulder)                 lifts it off the shoulder, drops
##                                         it back with a small bounce
##   act_lean (ground)                     leans onto it, drums the fingers
##   act_spin_reverse (reverse)            daggers: a flip in reverse grip
##   per style (guard): bow act_sight (nocks an arrow, half-draws, sights
##   down it, lets down); pistol act_check (the pan / chamber) and
##   act_blow (blows on the barrel); staff act_twirl (a tilted twirl, then
##   the head sparkles: meta.sparkle drives the weapon aura)
## Every handling clip is a non-blocking variant (meta.variant) with
## meta.handling ("hold" | "in" | "out" | "act"), meta.from and meta.to.
##
## Hand positions are chest frame. Weapon-hand poses are authored for the
## right hand ("rhs") and mirrored for a left weapon hand (the bow); the
## free hand is authored as the left hand and mirrored for the bow's right.

const HOLDS := {
	"one": ["guard", "side", "shoulder"],
	"heavy": ["guard", "side", "shoulder", "ground"],
	"polearm": ["guard", "side", "shoulder"],
	"spear": ["guard", "side", "shoulder"],
	"staff": ["guard", "side", "shoulder", "ground"],
	"pair": ["guard", "side", "reverse"],
	"bow": ["guard", "side", "shoulder"],
	"pistol": ["guard", "side", "shoulder"],
	"fists": ["guard", "side", "shoulder"],
}
## Transition lengths (authoring frames, in / out).
const TRANS := { "side": [18, 16], "shoulder": [22, 20], "ground": [26, 22], "reverse": [16, 14] }

const BODY := ["root", "hips", "spine", "chest", "neck", "head"]
const PR := Vector3(-0.5, -0.1, -1.0)
const PL := Vector3(0.5, -0.1, -1.0)


static func holds(st: String) -> Array:
	return HOLDS.get(st, ["guard"])


## The loop a hold stands in.
static func loop_clip(h: String) -> String:
	return "idle" if h == "guard" else "hold_" + h


## Actions available in a hold: [[kind, clip], ...] (kinds weight the
## personality's picks: heft, admire, trick, special, settle, lean, spin).
static func actions(st: String, h: String) -> Array:
	match h:
		"guard":
			var a: Array = [["heft", "act_heft"], ["admire", "act_admire"], ["trick", "idle_weapon"]]
			match st:
				"bow": a.append(["special", "act_sight"])
				"pistol": a.append_array([["special", "act_check"], ["special", "act_blow"]])
				"staff": a.append(["special", "act_twirl"])
			return a
		"side":
			return [["heft", "act_heft_side"], ["admire", "act_admire_side"]]
		"shoulder":
			return [["settle", "act_settle"]]
		"ground":
			return [["lean", "act_lean"]]
		"reverse":
			return [["spin", "act_spin_reverse"]]
	return []


static func clips(st: String) -> Array:
	var out: Array = []
	for h in holds(st):
		if h == "guard":
			continue
		out.append(hold_loop(st, h))
		if h == "reverse":
			out.append(flip(st, true))
			out.append(flip(st, false))
		else:
			out.append(transition(st, "guard", h))
			out.append(transition(st, h, "guard"))
	out.append(heft(st, "guard"))
	out.append(heft(st, "side"))
	out.append(admire(st, "guard"))
	out.append(admire(st, "side"))
	if "shoulder" in holds(st):
		out.append(settle(st))
	if "ground" in holds(st):
		out.append(lean(st))
	if st == "pair":
		out.append(spin_reverse(st))
	match st:
		"bow": out.append(sight(st))
		"pistol":
			out.append(check(st))
			out.append(blow(st))
		"staff": out.append(twirl(st))
	return out


# ------------------------------------------------------------------ roles

## Hand channels a hold sets (every hand_* channel, flat, plant).
static func hand_channels() -> Array:
	var out: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_"):
			out.append(ch)
	return out + ["flat", "plant"]


## The weapon hand(s): ["hand_r"], ["hand_l"] (bow) or both (pair).
static func whands(st: String) -> Array:
	var wh := BWAnimCarry.weapon_hand(st)
	if wh == "both":
		return ["hand_r", "hand_l"]
	return ["hand_" + wh]


## The free hand ("" for the pair).
static func fhand(st: String) -> String:
	var f := BWAnimCarry.free_hand(st)
	return "" if f == "" else "hand_" + f


## Mirror an rhs vector for hand h (the left hand of a weapon pair, or the
## bow's left weapon hand).
static func mx(v: Vector3, h: String) -> Vector3:
	return Vector3(-v.x, v.y, v.z) if h == "hand_l" else v


## Mirror a free-hand (lhs) vector for the free hand h.
static func fx(v: Vector3, h: String) -> Vector3:
	return Vector3(-v.x, v.y, v.z) if h == "hand_r" else v


## The grip channel of a style's second hand: the left fist on a
## two-hander, the string hand on a bow.
static func grip_ch(st: String) -> String:
	return "hand_r_grip" if st == "bow" else "hand_l_grip"


## Which side the weapon is on: +1 right (most), -1 left (the bow).
static func side_of(st: String) -> float:
	return -1.0 if st == "bow" else 1.0


# ------------------------------------------------------------------- holds

## Every hand channel (+ flat, plant) of a hold.
static func hold_pose(st: String, h: String) -> Dictionary:
	var base := BWAnimClips.base_channels(st)
	var d := BWAnimCarry.guard_hands(base)
	d["plant"] = 0.0
	if h == "guard":
		return d
	var spec := _spec(st, h, base)
	for hk in whands(st):
		if not spec.has("w"):
			break
		var w: Dictionary = spec.w
		if hk == "hand_l" and spec.has("w2"):
			w = spec.w2
		for k in ["pos", "aim", "edge", "pole"]:
			if w.has(k):
				var v: Vector3 = mx(w[k], hk) if not (hk == "hand_l" and spec.has("w2")) else w[k]
				d["%s_%s" % [hk, k]] = v.normalized() if k in ["aim", "edge"] else v
	var fh := fhand(st)
	if fh != "" and spec.has("f"):
		var f: Dictionary = spec.f
		d[fh + "_pos"] = fx(f.pos, fh)
		d[fh + "_pole"] = fx(f.get("pole", PL), fh)
	if spec.has("grip"):
		d[grip_ch(st)] = float(spec.grip)
	for k in ["flat", "plant"]:
		if spec.has(k):
			d[k] = float(spec[k])
	if spec.has("raw"):
		d.merge(spec.raw, true)
	return d


## Posture of a hold: small offsets added to the guard's body (the lean
## onto a planted weapon, the chest opened under a shouldered one).
static func posture(st: String, h: String) -> Dictionary:
	var s := side_of(st)
	match h:
		"side":
			return { "chest": Vector3(0.02, 0.0, 0.0), "head": Vector3(0.03, 0.0, 0.0), "root": Vector3(0, -0.003, 0) }
		"shoulder":
			return { "chest": Vector3(-0.03, -0.04 * s, 0.015 * s), "hips": Vector3(0, 0.03 * s, -0.015 * s),
				"head": Vector3(-0.05, 0.06 * s, 0.0) }
		"ground":
			if st == "staff":
				# sunk a little and leaning into it: the right shoulder drops so
				# the hand reaches the staff low on its shaft
				return { "root": Vector3(-0.03 * s, -0.025, 0.0), "hips": Vector3(0.0, -0.03 * s, 0.07 * s),
					"spine": Vector3(0.04, 0.0, 0.06 * s), "chest": Vector3(0.03, -0.05 * s, 0.07 * s), "head": Vector3(0.03, -0.08 * s, -0.08 * s) }
			return { "root": Vector3(-0.018 * s, -0.012, 0.01), "hips": Vector3(0.0, -0.03 * s, 0.04 * s),
				"spine": Vector3(0.05, 0.0, 0.0), "chest": Vector3(0.04, -0.06 * s, 0.03 * s), "head": Vector3(0.03, -0.1 * s, 0.03 * s) }
		"reverse":
			return { "root": Vector3(0, -0.012, 0), "chest": Vector3(0.03, 0, 0), "head": Vector3(0.02, 0, 0) }
	return {}


## A hold in role terms (rhs weapon hand "w", pair's left "w2" (real
## coordinates), free hand "f" (lhs), second-hand "grip", flat, plant).
static func _spec(st: String, h: String, base: Dictionary) -> Dictionary:
	var hip := { "pos": Vector3(0.24, -0.33, -0.02), "pole": Vector3(1.0, 0.2, 0.2) }     # free hand on the hip
	var hang := { "pos": Vector3(0.26, -0.37, 0.05), "pole": PL }                       # free hand hanging
	match h:
		"side":
			match st:
				"one":
					return { "w": { "pos": Vector3(-0.30, -0.40, 0.08), "aim": Vector3(-0.12, -0.6, 0.79), "edge": Vector3(0, 0.8, 0.6),
						"pole": Vector3(-0.35, 0.0, -1.0) }, "f": hang, "flat": 0.6 }
				"heavy":
					# one hand on the hilt, the tip resting on the floor ahead (planted)
					return { "w": { "pos": Vector3(-0.30, -0.36, 0.10), "aim": Vector3(-0.3, -0.42, 0.86), "edge": Vector3(0, 0.9, 0.44),
						"pole": Vector3(-0.4, 0.0, -1.0) }, "f": hang, "grip": 0.0, "flat": 0.6, "plant": 1.0 }
				"polearm", "spear", "staff":
					# trailed low in the hanging hand, the head forward and up
					return { "w": { "pos": Vector3(-0.29, -0.36, 0.06), "aim": Vector3(-0.06, 0.4 if st == "staff" else 0.36, 0.92),
						"edge": Vector3(0, 0.92, -0.38), "pole": Vector3(-0.4, 0.0, -1.0) }, "f": hang, "grip": 0.0, "flat": 0.5 }
				"pair":
					return { "w": { "pos": Vector3(-0.27, -0.40, 0.08), "aim": Vector3(-0.1, -0.72, 0.69), "edge": Vector3(0, 0.69, 0.72),
						"pole": Vector3(-0.3, 0.0, -1.0) }, "flat": 0.8 }
				"bow":
					# lowered, the top limb tipped forward
					return { "w": { "pos": Vector3(-0.28, -0.36, 0.08), "aim": Vector3(-0.1, 0.72, 0.69), "edge": Vector3(0, -0.69, 0.72),
						"pole": Vector3(-0.4, 0.0, -1.0) }, "f": hang, "grip": 0.0, "flat": 0.7 }
				"pistol":
					# arm hanging, the muzzle (the edge axis) at the floor
					return { "w": { "pos": Vector3(-0.28, -0.40, 0.06), "aim": Vector3(0, 0.25, 0.97), "edge": Vector3(0, -0.97, 0.25),
						"pole": Vector3(-0.4, 0.0, -1.0) }, "f": hang, "flat": 0.3 }
				"fists":
					# hands down and loose, knuckles to the floor
					var fd := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.05, -1, 0.15), Vector3(-1, 0, 0.2), Vector3.ZERO)
					return { "w": { "pos": Vector3(-0.27, -0.38, 0.06), "aim": fd.aim, "edge": fd.edge, "pole": PR }, "flat": 0.0 }
		"shoulder":
			match st:
				"one":
					return { "w": { "pos": Vector3(-0.21, -0.03, 0.18), "aim": Vector3(-0.36, 0.4, -0.84), "edge": Vector3(0, 0.9, -0.43),
						"pole": Vector3(-1, -0.6, -0.2) }, "f": hip, "flat": 0.5 }
				"heavy":
					var sh := BWAnimCarry.loco("heavy", "walk_heavy")
					var d: Dictionary = (sh.a as Dictionary).duplicate()
					d.merge(sh.k, true)
					# standing, laid further back than the walk's carry (a long
					# haft by the ear covered the face from her right side)
					d["hand_r_pos"] = (d.hand_r_pos as Vector3) + Vector3(-0.02, -0.06, 0.0)
					d["hand_r_aim"] = Vector3(-0.32, 0.38, -0.87).normalized()
					return { "raw": d }
				"polearm", "staff":
					var sl := BWAnimCarry.loco(st, "run")
					var d2: Dictionary = (sl.a as Dictionary).duplicate()
					d2.merge(sl.k, true)
					d2.erase("hand_l_pos")
					d2.erase("hand_l_pole")
					return { "raw": d2, "f": hip }
				"spear":
					return { "w": { "pos": Vector3(-0.2, 0.04, 0.18), "aim": Vector3(-0.25, 0.5, -0.83), "edge": Vector3(0, 1, 0),
						"pole": Vector3(-1, -0.6, -0.2) }, "f": hip, "flat": 0.4 }
				"bow":
					# slung over the (left) shoulder, hooked by the arm (cheer_cool's rest)
					return { "w": { "pos": Vector3(-0.2, 0.12, 0.12), "aim": Vector3(0.35, -0.6, -0.72), "edge": Vector3(0, 0.6, -0.6),
						"pole": Vector3(-1, -0.6, -0.2) }, "f": hip, "grip": 0.0, "flat": 0.6 }
				"pistol":
					# muzzle up by the shoulder, relaxed
					# laid back on the shoulder, the muzzle behind her (clear of the face)
					return { "w": { "pos": Vector3(-0.22, 0.08, 0.16), "aim": Vector3(0, 0.97, 0.25), "edge": Vector3(0, 0.25, -0.97),
						"pole": Vector3(-1, -0.6, -0.3) }, "f": hip, "flat": 0.3 }
				"fists":
					# (no shoulder to rest a fist on: both on the hips, chin up)
					var fh2 := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.3, -0.5, -0.8), Vector3(-1, 0, 0), Vector3.ZERO)
					return { "w": { "pos": Vector3(-0.24, -0.33, -0.02), "aim": fh2.aim, "edge": fh2.edge, "pole": Vector3(-1.0, 0.2, 0.2) }, "flat": 0.0 }
		"ground":
			match st:
				"heavy":
					# both fists stacked on the hilt, the blade / head planted ahead
					return { "w": { "pos": Vector3(-0.14, 0.2, 0.3), "aim": Vector3(0.05, -0.72, 0.69), "edge": Vector3(0, 0.69, 0.72),
						"pole": Vector3(-1, -0.3, -0.3) }, "f": { "pos": Vector3(0.02, 0.26, 0.3), "pole": Vector3(1, -0.3, -0.3) },
						"grip": 1.0, "flat": 0.5, "plant": 1.0 }
				"staff":
					# stood butt-down at her right, both hands on it, leaning in
					return { "w": { "pos": Vector3(-0.30, -0.24, 0.2), "aim": Vector3(-0.2, 0.75, -0.63), "edge": Vector3(0, 0.64, 0.77),
						"pole": Vector3(-1, -0.4, -0.4) }, "f": { "pos": Vector3(-0.2, -0.1, 0.2), "pole": Vector3(0.6, -1, -0.2) },
						"grip": 1.0, "flat": 0.6, "plant": 0.0 }      # (the arm's reach sets it: the butt lands within a few cm)
		"reverse":
			# daggers in the icepick grip: each blade turned over (a half turn
			# about the fist's axis, so the flip lands exactly here)
			var g_r: Vector3 = base.hand_r_aim
			var g_l: Vector3 = base.hand_l_aim
			var x := Basis(Vector3(1, 0, 0), PI)
			return { "w": { "pos": Vector3(-0.25, -0.22, 0.25), "aim": x * g_r, "edge": x * (base.hand_r_edge as Vector3), "pole": Vector3(-0.8, -0.4, -0.6) },
				"w2": { "pos": Vector3(0.25, -0.22, 0.25), "aim": x * g_l, "edge": x * (base.hand_l_edge as Vector3), "pole": Vector3(0.8, -0.4, -0.6) },
				"flat": 1.0 }
	return {}


# ------------------------------------------------------------------ keying

## Key every hand channel (+ flat, plant) from a hold pose dictionary.
static func _hands(c: BWAnimClips.Clip, f: float, d: Dictionary, mode: String = "f") -> void:
	for ch in d:
		c.key(ch, f, d[ch], mode)


## Key the body at a hold's posture (+ extra offsets), feet planted.
static func _body(c: BWAnimClips.Clip, f: float, h: String, extra: Dictionary = {}, mode: String = "f") -> void:
	var p := posture(c.style, h)
	for ch in BODY:
		var v: Vector3 = (c.base[ch] as Vector3) + (p.get(ch, Vector3.ZERO) as Vector3) + (extra.get(ch, Vector3.ZERO) as Vector3)
		c.key(ch, f, v, mode)
	c.key("squash", f, float(extra.get("squash", 0.0)), mode)
	c.key("head_sq", f, float(extra.get("head_sq", 0.0)), mode)


static func _feet(c: BWAnimClips.Clip, frames: Array) -> void:
	for f in frames:
		BWAnimIdle._feet_at_base(c, float(f))


## Weapon hand(s) at an rhs pose (each hand mirrored); missing keys skipped.
static func _w(c: BWAnimClips.Clip, f: float, pos: Variant, aim: Variant = null, edge: Variant = null, mode: String = "a") -> void:
	for hk in whands(c.style):
		if pos != null:
			c.key(hk + "_pos", f, mx(pos, hk), mode)
		if aim != null:
			c.key(hk + "_aim", f, mx(aim, hk).normalized(), mode)
		if edge != null:
			c.key(hk + "_edge", f, mx(edge, hk).normalized(), mode)


## Weapon hand(s) offset from a hold pose: position + d (rhs, mirrored),
## aim and edge turned by the euler rot (yaw / roll mirrored).
static func _wrel(c: BWAnimClips.Clip, f: float, hp: Dictionary, d: Vector3, rot := Vector3.ZERO, mode: String = "a") -> void:
	for hk in whands(c.style):
		var s := -1.0 if hk == "hand_l" else 1.0
		var r := Basis.from_euler(Vector3(rot.x, rot.y * s, rot.z * s))
		c.key(hk + "_pos", f, (hp[hk + "_pos"] as Vector3) + Vector3(d.x * s, d.y, d.z), mode)
		c.key(hk + "_aim", f, (r * (hp[hk + "_aim"] as Vector3)).normalized(), mode)
		c.key(hk + "_edge", f, (r * (hp[hk + "_edge"] as Vector3)).normalized(), mode)


## Free hand at an lhs position (mirrored for the bow's right hand).
static func _f(c: BWAnimClips.Clip, f: float, pos: Vector3, mode: String = "a") -> void:
	var fh := fhand(c.style)
	if fh != "":
		c.key(fh + "_pos", f, fx(pos, fh), mode)


static func _new(st: String, n: String, frames: int, loop: bool, kind: String, from: String, to: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip(n, frames, loop, st)
	c.meta = { "variant": true, "handling": kind, "from": from, "to": to }
	return c


## Start and end an action on its hold: hands, body, feet.
static func _ends(c: BWAnimClips.Clip, h: String) -> Dictionary:
	var hp := hold_pose(c.style, h)
	_hands(c, 0, hp)
	_hands(c, c.frames, hp)
	_body(c, 0, h)
	_body(c, c.frames, h)
	_feet(c, [0, c.frames])
	return hp


## The head turned to look at the weapon (rhs; mirrored for the bow).
static func _look(c: BWAnimClips.Clip, f: float, h: String, look: Vector3, chest_yaw: float = 0.0, mode: String = "a", extra: Dictionary = {}) -> void:
	var s := side_of(c.style)
	var e := { "head": Vector3(look.x, look.y * s, look.z * s), "chest": Vector3(0, chest_yaw * s, 0) }
	for k in extra:
		e[k] = extra[k]
	_body(c, f, h, e, mode)


# ------------------------------------------------------------- hold loops

## HOLD loop (60 f): the calm idle body (two weight shifts, two breaths,
## the look-off) at the hold's posture; the weapon rests in the hold and
## only rides the body (a 6 mm drift of the hand).
static func hold_loop(st: String, h: String) -> BWAnimClips.Clip:
	var c := _new(st, "hold_" + h, 60, true, "hold", h, h)
	var b := c.base
	var p := posture(st, h)
	var add := func(ch: String, v: Vector3) -> Vector3: return v + (p.get(ch, Vector3.ZERO) as Vector3)
	# the idle's own body keys (BWAnimIdle.idle), shifted by the posture
	c.pose(0, { "root": add.call("root", Vector3(0.03, -0.044, 0.0)), "hips": add.call("hips", Vector3(0.0, -0.07, 0.085)),
		"spine": add.call("spine", Vector3(0.03, 0.02, -0.03)), "chest": add.call("chest", Vector3(0.0, 0.04, -0.05)) }, "f")
	c.pose(14, { "root": add.call("root", Vector3(0.004, -0.030, 0.006)) })
	c.pose(30, { "root": add.call("root", Vector3(-0.025, -0.048, 0.0)), "hips": add.call("hips", Vector3(0.0, 0.04, -0.07)),
		"spine": add.call("spine", Vector3(0.035, -0.01, 0.03)), "chest": add.call("chest", Vector3(0.02, -0.02, 0.04)) }, "f")
	c.pose(44, { "root": add.call("root", Vector3(0.002, -0.032, 0.006)) })
	c.key("chest", 8, add.call("chest", Vector3(-0.025, 0.02, -0.01)))
	c.key("chest", 38, add.call("chest", Vector3(-0.01, -0.03, 0.045)))
	c.key("squash", 8, 0.012).key("squash", 22, -0.006).key("squash", 38, 0.012).key("squash", 52, -0.006)
	c.pose(0, { "neck": add.call("neck", Vector3(-0.03, 0.0, 0.0)), "head": add.call("head", Vector3(-0.07, 0.10, 0.06)) }, "f")
	c.pose(18, { "head": add.call("head", Vector3(-0.04, 0.22, -0.02)) })
	c.pose(34, { "head": add.call("head", Vector3(-0.08, 0.05, -0.07)) }, "f")
	c.pose(50, { "head": add.call("head", Vector3(-0.05, -0.04, 0.02)) })
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
	var hp := hold_pose(st, h)
	_hands(c, 0, hp, "a")
	for hk in whands(st) + ([fhand(st)] if fhand(st) != "" else []):
		var v: Vector3 = hp[hk + "_pos"]
		c.key(hk + "_pos", 22, v + Vector3(0.0, 0.006, 0.003))
		c.key(hk + "_pos", 46, v + Vector3(0.002, -0.004, 0.0))
	BWAnimIdle.calm(c)
	return c


# ------------------------------------------------------------ transitions

## guard <-> hold: the weapon travels on an arc (lifted through `via`),
## the head follows it, a little settle of the weapon as it lands; a
## second hand lets go early or takes hold late; a planted end ramps its
## `plant` in as it comes down (or out as it lifts).
static func transition(st: String, from: String, to: String) -> BWAnimClips.Clip:
	var h := to if from == "guard" else from
	var going_in := from == "guard"
	var n: int = TRANS[h][0 if going_in else 1]
	var c := _new(st, "hold_%s_%s" % [h, "in" if going_in else "out"], n, false, "in" if going_in else "out", from, to)
	var A := hold_pose(st, from)
	var B := hold_pose(st, to)
	_hands(c, 0, A)
	_hands(c, n, B)
	_body(c, 0, from)
	_body(c, n, to)
	_feet(c, [0, n])
	# the arc: a lift through the middle (rhs, mirrored per hand)
	var lift := Vector3(-0.02, 0.07, 0.07)
	match h:
		"shoulder": lift = Vector3(-0.03, 0.12, 0.1)
		"ground": lift = Vector3(0.0, 0.1, 0.08)
		"side": lift = Vector3(-0.01, 0.03, 0.08)
	var m := n * 0.45
	for hk in whands(st):
		var s := -1.0 if hk == "hand_l" else 1.0
		var pa: Vector3 = A[hk + "_pos"]
		var pb: Vector3 = B[hk + "_pos"]
		var aa: Vector3 = (A[hk + "_aim"] as Vector3).normalized()
		var ab: Vector3 = (B[hk + "_aim"] as Vector3).normalized()
		var ea: Vector3 = (A[hk + "_edge"] as Vector3).normalized()
		var eb: Vector3 = (B[hk + "_edge"] as Vector3).normalized()
		var up := aa.slerp(ab, 0.5) if aa.dot(ab) > -0.95 else (aa + ab + Vector3(0, 0.5, 0)).normalized()
		if up.y < 0.4 and h in ["shoulder", "ground"]:
			# long weapons swing up and over, not through the body
			up = (up + Vector3(0, 0.8, 0)).normalized()
		c.key(hk + "_pos", m, pa.lerp(pb, 0.5) + Vector3(lift.x * s, lift.y, lift.z))
		c.key(hk + "_aim", m, up.normalized())
		if ea.dot(eb) > -0.95:
			c.key(hk + "_edge", m, ea.slerp(eb, 0.5).normalized())
		if float(B.get("plant", 0.0)) < 0.5:
			# the weapon settles: a dip with the tip lagging, then rest
			c.key(hk + "_pos", n - 3.5, pb + Vector3(0, -0.018, 0.004))
			c.key(hk + "_aim", n - 2.5, (Basis(Vector3(1, 0, 0), 0.06) * ab).normalized())
	# the second hand: lets go first / takes hold last
	var gc := grip_ch(st)
	var ga := float(A.get(gc, 0.0))
	var gb := float(B.get(gc, 0.0))
	if ga > 0.5 and gb < 0.5:
		c.key(gc, 2, ga, "f").key(gc, 6, gb, "f")
	elif ga < 0.5 and gb > 0.5:
		c.key(gc, n - 6, ga, "f").key(gc, n - 2, gb, "f")
	# planting: ramps in as the end comes down / out as it lifts
	var pa2 := float(A.get("plant", 0.0))
	var pb2 := float(B.get("plant", 0.0))
	if pb2 > pa2:
		c.key("plant", n * 0.5, pa2, "f").key("plant", n - 3.0, pb2, "f")
	elif pa2 > pb2:
		c.key("plant", n * 0.3, pa2, "f").key("plant", n * 0.5, pb2, "f")
	# the head follows the weapon; the body barely moves
	var look := Vector3(0.14, -0.28, -0.04)
	if h == "shoulder":
		look = Vector3(-0.02, -0.35, -0.06)
	_look(c, n * 0.4, from if n * 0.4 < n * 0.5 else to, look, -0.04, "a", { "root": Vector3(0, -0.003, 0) })
	return c


## DAGGER FLIPS: forward -> reverse (to_reverse) or back. Each blade spins
## a turn and a half about the fist (the left a beat after the right), the
## hands toss up a little and catch.
static func flip(st: String, to_reverse: bool) -> BWAnimClips.Clip:
	var n: int = TRANS.reverse[0 if to_reverse else 1]
	var from := "guard" if to_reverse else "reverse"
	var to := "reverse" if to_reverse else "guard"
	var c := _new(st, "hold_reverse_%s" % ("in" if to_reverse else "out"), n, false, "in" if to_reverse else "out", from, to)
	var A := hold_pose(st, from)
	var B := hold_pose(st, to)
	_hands(c, 0, A)
	_hands(c, n, B)
	_body(c, 0, from)
	_body(c, n, to)
	_feet(c, [0, n])
	var x := Vector3(1, 0, 0)
	var lag := { "hand_r": 0.0, "hand_l": 1.5 }
	for hk in ["hand_r", "hand_l"]:
		var f0 := 3.0 + float(lag[hk])
		var f1 := f0 + 7.0
		var pa: Vector3 = A[hk + "_pos"]
		var pb: Vector3 = B[hk + "_pos"]
		c.key(hk + "_aim", f0 - 1.0, A[hk + "_aim"], "f")
		c.key(hk + "_edge", f0 - 1.0, A[hk + "_edge"], "f")
		BWAnimIdle._spin(c, hk + "_aim", f0, f1, (A[hk + "_aim"] as Vector3).normalized(), x, 1.5)
		BWAnimIdle._spin(c, hk + "_edge", f0, f1, (A[hk + "_edge"] as Vector3).normalized(), x, 1.5)
		# a small toss and the catch
		c.key(hk + "_pos", f0 - 1.0, pa + Vector3(0, -0.02, 0.0), "f")
		c.key(hk + "_pos", (f0 + f1) * 0.5, pa.lerp(pb, 0.5) + Vector3(0, 0.05, 0.03))
		c.key(hk + "_pos", f1 + 0.5, pb + Vector3(0, -0.015, 0.0))
	_look(c, 6, from, Vector3(0.12, -0.1, 0.0), 0.0)
	return c


# ------------------------------------------------------------------ actions

## Where a style lifts its weapon to weigh it (rhs): [pos, aim, edge].
static func _lifted(st: String) -> Array:
	match st:
		"heavy":
			return [Vector3(-0.26, -0.08, 0.3), Vector3(-0.72, 0.42, 0.55), Vector3(0, 0.8, -0.6)]
		"polearm", "spear", "staff":
			return [Vector3(-0.26, -0.06, 0.28), Vector3(-0.45, 0.4, 0.8), Vector3(0, 0.9, -0.44)]
		"pair":
			return [Vector3(-0.22, -0.14, 0.34), Vector3(-0.45, 0.5, 0.74), Vector3(0, 0.83, -0.56)]
		"bow":
			return [Vector3(-0.2, -0.12, 0.34), Vector3(-0.35, 0.8, 0.48), Vector3(0, -0.5, 0.86)]
		"pistol":
			# lying in the open palm, muzzle forward-left
			return [Vector3(-0.18, -0.12, 0.32), Vector3(-0.15, 0.97, 0.2), Vector3(0.5, -0.1, 0.86)]
		"fists":
			# the fist turned up in front of her, knuckles up: flexing the wraps
			var f := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(0.0, 1, 0.3), Vector3(0, 0.2, 1), Vector3.ZERO)
			return [Vector3(-0.2, 0.0, 0.3), f.aim, f.edge]
	return [Vector3(-0.26, -0.1, 0.32), Vector3(-0.62, 0.5, 0.6), Vector3(0, 0.77, -0.64)]


## HEFT (40 f): lift it, weigh it (two small bounces of the WEAPON, the tip
## a frame behind the hand), tilt it one way and the other, back to the
## hold. A two-hander's left hand lets go to weigh it one-handed.
static func heft(st: String, h: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_heft" if h == "guard" else "act_heft_side", 40, false, "act", h, h)
	c.meta["kind"] = "heft"
	var hp := _ends(c, h)
	var L := _lifted(st)
	var p0: Vector3 = L[0]
	var a0: Vector3 = (L[1] as Vector3).normalized()
	var e0: Vector3 = L[2]
	var gc := grip_ch(st)
	var g := float(hp.get(gc, 0.0))
	if g > 0.5:
		c.key(gc, 2, g, "f").key(gc, 6, 0.0, "f").key(gc, 34, 0.0, "f").key(gc, 38, g, "f")
	if float(hp.plant) > 0.5:
		c.key("plant", 1.5, hp.plant, "f").key("plant", 6, 0.0, "f").key("plant", 33, 0.0, "f").key("plant", 38.5, hp.plant, "f")
	var pitch := func(a: Vector3, r: float) -> Vector3: return (Basis(Vector3(1, 0, 0), r) * a).normalized()
	_w(c, 8, p0, a0, e0, "f")
	# weigh: down-up twice, the tip lagging a frame (pitch + = tip down)
	_w(c, 11.5, p0 + Vector3(0, -0.045, 0.0), null, null, "a")
	_w(c, 12.5, null, pitch.call(a0, 0.16), null)
	_w(c, 14.5, p0 + Vector3(0, 0.022, 0.0), null, null)
	_w(c, 15.5, null, pitch.call(a0, -0.08), null)
	_w(c, 17.5, p0 + Vector3(0, -0.034, 0.0), null, null)
	_w(c, 18.5, null, pitch.call(a0, 0.12), null)
	_w(c, 20.5, p0 + Vector3(0, 0.01, 0.0), null, null)
	_w(c, 21.5, null, pitch.call(a0, -0.03), null)
	_w(c, 23, p0, a0, e0, "f")
	# tilt: roll it to one side and the other about its own line
	var axis := Vector3(0, 0, 1)
	_w(c, 27, p0 + Vector3(0.01, 0.005, 0.0), (Basis(axis, 0.28) * a0), (Basis(a0, 0.6) * e0), "f")
	_w(c, 31, p0 + Vector3(-0.01, 0.005, 0.0), (Basis(axis, -0.22) * a0), (Basis(a0, -0.5) * e0), "f")
	_w(c, 34, p0, a0, e0)
	# the free hand drifts in to steady, then back (not on the pair)
	var fh := fhand(st)
	if fh != "" and not (g > 0.5):
		var fp: Vector3 = fx(hp[fh + "_pos"], fh)
		_f(c, 10, fp + Vector3(-0.02, 0.03, 0.04))
		_f(c, 30, fp + Vector3(-0.02, 0.03, 0.04))
	elif fh != "":
		_f(c, 8, Vector3(0.24, -0.3, 0.1))
		_f(c, 33, Vector3(0.24, -0.3, 0.1))
	# head: watches it; the body only answers the weighing with a breath
	_look(c, 6, h, Vector3(0.22, -0.22, -0.05), -0.04, "f")
	_look(c, 12, h, Vector3(0.25, -0.22, -0.05), -0.04, "a", { "root": Vector3(0, -0.006, 0) })
	_look(c, 18, h, Vector3(0.24, -0.24, -0.06), -0.04, "a", { "root": Vector3(0, -0.005, 0) })
	_look(c, 27, h, Vector3(0.2, -0.26, 0.08), -0.05, "f")
	_look(c, 31, h, Vector3(0.2, -0.2, -0.1), -0.05, "f")
	_look(c, 36, h, Vector3(0.06, -0.08, 0.0), -0.01)
	return c


## ADMIRE (56 f): up to eye level, a half turn to see both flats, then
## held out level and sighted along, a wipe with the free hand along it
## (the pair: the left blade scrapes the right), and down to the hold.
static func admire(st: String, h: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_admire" if h == "guard" else "act_admire_side", 56, false, "act", h, h)
	c.meta["kind"] = "admire"
	var hp := _ends(c, h)
	var gc := grip_ch(st)
	var g := float(hp.get(gc, 0.0))
	if g > 0.5:
		c.key(gc, 2, g, "f").key(gc, 6, 0.0, "f").key(gc, 50, 0.0, "f").key(gc, 54, g, "f")
	if float(hp.plant) > 0.5:
		c.key("plant", 1.5, hp.plant, "f").key("plant", 6, 0.0, "f").key("plant", 49, 0.0, "f").key("plant", 54.5, hp.plant, "f")
	var longw := st in ["heavy", "polearm", "spear", "staff"]
	# 1: raised upright at her right, at eye level (out past the shoulder so
	# the blade stands beside the face, not across it)
	var up_pos := Vector3(-0.34, 0.20, 0.30) if not longw else Vector3(-0.36, 0.02, 0.28)
	var up_aim := Vector3(-0.3, 0.94, 0.12)
	var up_edge := Vector3(0, -0.12, 0.99)
	var blade_axis_edge := st == "pistol"
	if st == "pistol":
		up_aim = Vector3(0.0, 0.2, 0.98)        # muzzle (edge) up, the grip axis forward
		up_edge = Vector3(-0.15, 0.97, -0.2)
		up_pos = Vector3(-0.3, 0.14, 0.32)
	elif st == "fists":
		# the right fist raised by her cheek and turned to look at the knuckles
		var f := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(-0.3, 0.6, -0.75), Vector3(-0.8, 0, 0.5), Vector3.ZERO)
		up_aim = f.aim
		up_edge = f.edge
		up_pos = Vector3(-0.26, 0.28, 0.34)
	elif st == "bow":
		up_aim = Vector3(-0.2, 0.96, 0.18)
		up_edge = Vector3(0, -0.18, 0.98)
		up_pos = Vector3(-0.3, 0.02, 0.34)
	_w(c, 10, up_pos, up_aim, up_edge, "f")
	# 2: turned in the fingers: a half turn about its own line, then back
	var ax: Vector3 = up_edge.normalized() if blade_axis_edge else up_aim.normalized()
	var turn_ch := "_aim" if blade_axis_edge else "_edge"
	var turn_from: Vector3 = (up_aim if blade_axis_edge else up_edge).normalized()
	for hk in whands(st):
		var axh := mx(ax, hk)
		var fromh := mx(turn_from, hk)
		c.key(hk + turn_ch, 13, fromh)
		c.key(hk + turn_ch, 17, (Basis(axh, PI * 0.5) * fromh).normalized())
		c.key(hk + turn_ch, 21, (Basis(axh, PI * 0.95) * fromh).normalized(), "f")
		c.key(hk + turn_ch, 25, (Basis(axh, PI * 0.5) * fromh).normalized())
		c.key(hk + turn_ch, 28, fromh)
	_w(c, 21, up_pos + Vector3(0, 0.02, 0.0), null, null)
	# 3: held out level to her right and sighted along (head turned along it)
	var out_pos := Vector3(-0.2, 0.22, 0.24) if not longw else Vector3(-0.22, 0.06, 0.26)
	var out_aim := Vector3(-0.95, 0.12, 0.28)
	var out_edge := Vector3(0, 1, 0)
	if st == "pistol":
		out_aim = Vector3(0, 1, 0)
		out_edge = Vector3(-0.95, 0.0, 0.3)
		out_pos = Vector3(-0.18, 0.18, 0.28)
	elif st == "fists":
		var f2 := BWCharacterPose._fist("r", Vector3.ZERO, Vector3(-0.6, 0.2, -0.75), Vector3(0, 1, 0), Vector3.ZERO)
		out_aim = f2.aim
		out_edge = f2.edge
		out_pos = Vector3(-0.14, 0.3, 0.36)
	elif st == "bow":
		out_aim = Vector3(-0.95, 0.2, 0.22)
		out_edge = Vector3(0.2, 0.0, 0.98)
	_w(c, 32, out_pos, out_aim, out_edge, "f")
	_w(c, 46, out_pos + Vector3(0.0, 0.01, 0.0), out_aim, out_edge, "f")
	# 4: the wipe: the free hand slides along the blade, hilt to tip
	var axis: Vector3 = (out_edge if blade_axis_edge else out_aim).normalized()
	var fh := fhand(st)
	if fh != "":
		var near := 0.08 if st == "pistol" else 0.12
		var far := 0.3 if st == "pistol" else (0.42 if not longw else 0.5)
		var hand_r_side := mx(out_pos, whands(st)[0])
		var ax2 := mx(axis, whands(st)[0])
		var off := Vector3(0, 0.035, 0.03)
		c.key(fh + "_pos", 28, (hp[fh + "_pos"] as Vector3).lerp(hand_r_side + ax2 * near + off, 0.5))
		c.key(fh + "_pos", 34, hand_r_side + ax2 * near + off, "f")
		c.key(fh + "_pos", 39, hand_r_side + ax2 * far + off, "f")
		c.key(fh + "_pos", 41, hand_r_side + ax2 * (near + 0.08) + off + Vector3(0, 0.03, 0))
		c.key(fh + "_pos", 44, hand_r_side + ax2 * far + off, "f")
		c.key(fh + "_pos", 52, hp[fh + "_pos"])
		c.key(fh + "_pole", 34, fx(Vector3(0.6, -1, -0.2), fh)).key(fh + "_pole", 50, hp[fh + "_pole"])
	elif st == "pair":
		# the left dagger scrapes along the right blade, twice
		var rp := out_pos
		var ra := out_aim.normalized()
		c.key("hand_r_pos", 32, rp, "f").key("hand_r_aim", 32, ra, "f").key("hand_r_edge", 32, out_edge, "f")
		c.key("hand_r_pos", 46, rp + Vector3(0, 0.01, 0), "f").key("hand_r_aim", 46, ra, "f").key("hand_r_edge", 46, out_edge, "f")
		var la := Vector3(-0.3, 0.6, 0.74).normalized()
		c.key("hand_l_pos", 30, Vector3(0.0, 0.1, 0.3))
		c.key("hand_l_aim", 32, la, "f").key("hand_l_aim", 44, la, "f")
		c.key("hand_l_pos", 34, rp + Vector3(0.12, -0.04, 0.06), "f")
		c.key("hand_l_pos", 38, rp + Vector3(0.02, -0.06, 0.12))
		c.key("hand_l_pos", 40, rp + Vector3(0.12, -0.04, 0.06))
		c.key("hand_l_pos", 44, rp + Vector3(0.02, -0.06, 0.12), "f")
		c.key("hand_l_pos", 32, rp + Vector3(0.14, -0.03, 0.05))
		c.key("hand_l_pos", 46, rp + Vector3(0.1, -0.05, 0.08))
		c.key("hand_l_aim", 46, la)
		c.key("hand_l_edge", 32, Vector3(1, 0, 0)).key("hand_l_edge", 46, Vector3(1, 0, 0))
		c.key("hand_l_pos", 50, hp.hand_l_pos)
	# the head: up at it, then turned along it
	_look(c, 8, h, Vector3(-0.08, -0.3, -0.06), -0.05, "f")
	_look(c, 21, h, Vector3(-0.1, -0.36, 0.1), -0.06, "f")
	_look(c, 31, h, Vector3(0.02, -0.62, -0.14), -0.1, "f")
	_look(c, 38, h, Vector3(0.14, -0.5, -0.08), -0.08, "a", { "root": Vector3(0, -0.004, 0) })
	_look(c, 46, h, Vector3(0.1, -0.52, -0.06), -0.08, "f")
	_look(c, 52, h, Vector3(0.04, -0.1, 0.0), -0.01)
	return c


## SETTLE (shoulder, 30 f): lifts it off the shoulder, lets it drop back,
## a small bounce of the weapon; a glance at it.
static func settle(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_settle", 30, false, "act", "shoulder", "shoulder")
	c.meta["kind"] = "settle"
	var hp := _ends(c, "shoulder")
	_wrel(c, 6, hp, Vector3(0.0, 0.05, 0.03), Vector3(-0.18, 0, 0))
	_wrel(c, 10, hp, Vector3(0.0, 0.075, 0.035), Vector3(-0.26, 0, 0), "f")
	_wrel(c, 13, hp, Vector3(0.0, -0.028, 0.0), Vector3(0.05, 0, 0))
	_wrel(c, 16, hp, Vector3(0.0, 0.012, 0.0), Vector3(-0.02, 0, 0))
	_wrel(c, 20, hp, Vector3(0.0, -0.004, 0.0), Vector3.ZERO, "f")
	_look(c, 5, "shoulder", Vector3(0.05, -0.32, -0.08), -0.02, "f")
	_look(c, 12, "shoulder", Vector3(0.0, -0.28, -0.06), -0.02, "a", { "chest": Vector3(-0.015, 0, 0), "root": Vector3(0, 0.003, 0) })
	_look(c, 22, "shoulder", Vector3(-0.02, 0.0, 0.0), 0.0)
	return c


## LEAN (ground, 48 f): the weight eases onto the planted weapon, the
## fingers of the top hand drum on it, a look around, back.
static func lean(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_lean", 48, false, "act", "ground", "ground")
	c.meta["kind"] = "lean"
	var hp := _ends(c, "ground")
	var s := side_of(st)
	_wrel(c, 10, hp, Vector3(0.0, -0.015, 0.0), Vector3.ZERO, "f")
	_wrel(c, 36, hp, Vector3(0.0, -0.015, 0.0), Vector3.ZERO, "f")
	var gc := grip_ch(st)
	var fh := fhand(st)
	if fh != "":
		var fp: Vector3 = hp[fh + "_pos"]
		c.key(fh + "_pos", 12, fp + Vector3(0, 0.08, 0.02), "f").key(fh + "_pos", 30, fp + Vector3(0, 0.08, 0.02), "f")
	for k in [[12.0, 1.0], [14.0, 0.55], [16.0, 1.0], [18.0, 0.6], [20.0, 1.0], [23.0, 0.55], [25.0, 1.0]]:
		c.key(gc, float(k[0]), float(k[1]), "a" if float(k[1]) < 1.0 else "f")
	_body(c, 10, "ground", { "root": Vector3(-0.012 * s, -0.006, 0), "chest": Vector3(0.02, 0, 0.025 * s), "head": Vector3(0.1, 0.0, 0.0) }, "f")
	_body(c, 22, "ground", { "root": Vector3(-0.012 * s, -0.006, 0), "chest": Vector3(0.015, 0, 0.025 * s), "head": Vector3(0.06, 0.05 * s, 0.02) }, "a")
	_body(c, 31, "ground", { "root": Vector3(-0.008 * s, -0.004, 0), "chest": Vector3(0.0, 0.04 * s, 0.015 * s), "head": Vector3(-0.06, 0.35 * s, 0.03) }, "f")
	_body(c, 40, "ground", { "head": Vector3(-0.03, 0.1 * s, 0.0) }, "a")
	return c


## Daggers in reverse grip: the right blade flips a full turn and is
## caught back in the icepick grip, then the left.
static func spin_reverse(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_spin_reverse", 30, false, "act", "reverse", "reverse")
	c.meta["kind"] = "spin"
	var hp := _ends(c, "reverse")
	var x := Vector3(1, 0, 0)
	for k in [["hand_r", 4.0], ["hand_l", 15.0]]:
		var hk: String = k[0]
		var f0: float = k[1]
		c.key(hk + "_aim", f0 - 1.0, hp[hk + "_aim"], "f")
		c.key(hk + "_edge", f0 - 1.0, hp[hk + "_edge"], "f")
		BWAnimIdle._spin(c, hk + "_aim", f0, f0 + 7.0, (hp[hk + "_aim"] as Vector3).normalized(), x, -1.0)
		BWAnimIdle._spin(c, hk + "_edge", f0, f0 + 7.0, (hp[hk + "_edge"] as Vector3).normalized(), x, -1.0)
		var p: Vector3 = hp[hk + "_pos"]
		c.key(hk + "_pos", f0 - 1.0, p + Vector3(0, -0.015, 0), "f")
		c.key(hk + "_pos", f0 + 3.5, p + Vector3(0, 0.05, 0.03))
		c.key(hk + "_pos", f0 + 7.5, p + Vector3(0, -0.012, 0))
		c.key(hk + "_pos", f0 + 10.0, p, "f")
	_look(c, 6, "reverse", Vector3(0.14, -0.2, -0.04), 0.0)
	_look(c, 17, "reverse", Vector3(0.14, 0.2, 0.04), 0.0)
	_look(c, 26, "reverse", Vector3(0.02, 0.0, 0.0), 0.0)
	return c


## BOW: sight down an arrow (60 f). The bow comes up in front, the string
## hand nocks an arrow (meta.arrow: from nock to stow, the arrow is on the
## string and the string bends to the hand), a half draw, a sight along it
## (head canted to it), let down, the arrow stowed, the bow lowered.
static func sight(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_sight", 60, false, "act", "guard", "guard")
	c.meta["kind"] = "special"
	_ends(c, "guard")
	# real coordinates (bow in the left hand)
	c.key("hand_l_pos", 9, Vector3(0.1, 0.06, 0.42), "f").key("hand_l_aim", 9, Vector3(-0.1, 0.97, 0.2).normalized(), "f")
	c.key("hand_l_edge", 9, Vector3(0, -0.2, 1).normalized(), "f").key("hand_l_pole", 9, Vector3(1, -0.4, -0.3))
	c.key("hand_l_pos", 20, Vector3(0.08, 0.14, 0.46), "f").key("hand_l_aim", 20, Vector3(-0.35, 0.92, 0.18).normalized(), "f")
	c.key("hand_l_pos", 40, Vector3(0.08, 0.15, 0.46), "f").key("hand_l_aim", 40, Vector3(-0.33, 0.93, 0.18).normalized(), "f")
	c.key("hand_l_edge", 40, Vector3(0, -0.2, 1).normalized(), "f")
	c.key("hand_l_pos", 48, Vector3(0.1, 0.04, 0.42)).key("hand_l_aim", 48, Vector3(-0.1, 0.97, 0.2).normalized())
	# the string hand: to the string (grip 1) = nock; a half draw (grip 0,
	# the string follows the hand); eased forward; off the string
	c.key("hand_r_pos", 8, Vector3(-0.06, 0.02, 0.3)).key("hand_r_grip", 8, 0.0, "f")
	c.key("hand_r_grip", 11, 1.0, "f").key("hand_r_grip", 13, 1.0).key("hand_r_grip", 15, 0.0, "f")
	c.key("hand_r_pos", 15, Vector3(-0.04, 0.13, 0.3))
	c.key("hand_r_pos", 20, Vector3(-0.05, 0.17, 0.18), "f")
	c.key("hand_r_pos", 40, Vector3(-0.05, 0.18, 0.19), "f")
	c.key("hand_r_pos", 44, Vector3(-0.04, 0.14, 0.3))
	c.key("hand_r_grip", 44, 0.0, "f").key("hand_r_grip", 46, 1.0, "f").key("hand_r_grip", 47.5, 1.0).key("hand_r_grip", 49, 0.0, "f")
	c.key("hand_r_pos", 50, Vector3(-0.12, -0.04, 0.2))
	c.key("hand_r_pole", 14, Vector3(-1, 0.2, -0.4)).key("hand_r_pole", 46, Vector3(-1, 0.2, -0.4))
	c.key("flat", 9, 0.1).key("flat", 48, 0.1)
	# head: canted to sight along the shaft, a slow breath held
	c.meta["arrow"] = [11.5 / BWAnimClips.FPS, 47.5 / BWAnimClips.FPS]
	_body(c, 8, "guard", { "head": Vector3(0.1, 0.1, 0.0) }, "a")
	_body(c, 20, "guard", { "head": Vector3(0.06, 0.18, -0.22), "chest": Vector3(-0.01, 0.05, 0.0), "root": Vector3(0, -0.004, 0) }, "f")
	_body(c, 32, "guard", { "head": Vector3(0.07, 0.2, -0.24), "chest": Vector3(-0.02, 0.06, 0.0), "squash": 0.006, "root": Vector3(0, -0.004, 0) }, "f")
	_body(c, 40, "guard", { "head": Vector3(0.06, 0.18, -0.2), "chest": Vector3(-0.01, 0.05, 0.0) }, "f")
	_body(c, 50, "guard", { "head": Vector3(0.08, 0.05, 0.0) }, "a")
	return c


## PISTOL: check the pan / chamber (48 f). Brought in, turned on its side,
## the free thumb works the pan (three taps), a look down the side, a flick
## back level, down to the guard.
static func check(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_check", 48, false, "act", "guard", "guard")
	c.meta["kind"] = "special"
	var hp := _ends(c, "guard")
	var hpos := Vector3(-0.08, -0.04, 0.32)
	var muz := Vector3(0.7, 0.0, 0.7).normalized()                 # the edge: muzzle forward-left
	var gripax := Vector3(-0.5, 0.7, 0.5).normalized()             # rolled so the side faces up to her
	c.key("hand_r_pos", 8, hpos, "f").key("hand_r_aim", 8, gripax, "f").key("hand_r_edge", 8, muz, "f")
	c.key("hand_r_pos", 30, hpos + Vector3(0, 0.01, 0.0), "f").key("hand_r_aim", 30, gripax, "f").key("hand_r_edge", 30, muz, "f")
	c.key("hand_r_pole", 8, Vector3(-1, -0.6, -0.2)).key("hand_r_pole", 36, hp.hand_r_pole)
	# the flick: snapped back level (a quarter roll), then lowered
	c.key("hand_r_pos", 33, hpos + Vector3(-0.04, 0.03, 0.02)).key("hand_r_aim", 33, Vector3(0, 0.9, 0.3).normalized())
	c.key("hand_r_edge", 33, Vector3(0.1, -0.3, 0.95).normalized())
	var tp := hpos + Vector3(0.1, 0.05, 0.02)
	c.key("hand_l_pos", 10, tp + Vector3(0.04, -0.02, 0.0))
	for k in [[14, 0.0], [16, 0.02], [18, 0.0], [20, 0.02], [22, 0.0], [24, 0.025], [27, 0.0]]:
		c.key("hand_l_pos", float(k[0]), tp + Vector3(0, float(k[1]), 0))
	c.key("hand_l_pos", 32, (hp.hand_l_pos as Vector3).lerp(tp, 0.4))
	c.key("hand_l_pole", 10, Vector3(0.6, -1, -0.3)).key("hand_l_pole", 34, hp.hand_l_pole)
	_body(c, 7, "guard", { "head": Vector3(0.28, -0.1, -0.06), "chest": Vector3(0.02, -0.03, 0.0) }, "f")
	_body(c, 20, "guard", { "head": Vector3(0.3, -0.06, 0.1), "chest": Vector3(0.02, -0.03, 0.0) }, "a")
	_body(c, 30, "guard", { "head": Vector3(0.24, -0.12, -0.04) }, "f")
	_body(c, 36, "guard", { "head": Vector3(-0.04, 0.0, 0.0), "head_sq": 0.006 }, "a")
	return c


## PISTOL: blow on the barrel (40 f). The muzzle comes up by her chin, a
## short blow (the head eases in, a tiny head squash), then twirled down.
static func blow(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_blow", 40, false, "act", "guard", "guard")
	c.meta["kind"] = "special"
	var hp := _ends(c, "guard")
	var p := Vector3(-0.1, 0.02, 0.28)
	var muz := Vector3(0.12, 0.98, 0.0).normalized()               # edge = muzzle, straight up
	var ga := Vector3(0.0, 0.0, 1.0)
	c.key("hand_r_pos", 10, p, "f").key("hand_r_aim", 10, ga, "f").key("hand_r_edge", 10, muz, "f")
	c.key("hand_r_pos", 22, p + Vector3(0, 0.01, -0.01), "f").key("hand_r_aim", 22, ga, "f").key("hand_r_edge", 22, muz, "f")
	c.key("hand_r_pole", 10, Vector3(-1, -0.8, -0.2)).key("hand_r_pole", 30, hp.hand_r_pole)
	# down with a spin about the trigger finger
	BWAnimIdle._spin(c, "hand_r_edge", 24.0, 31.0, muz, Vector3(1, 0, 0), 0.75)
	c.key("hand_r_pos", 28, Vector3(-0.22, -0.14, 0.26))
	_body(c, 9, "guard", { "head": Vector3(0.12, -0.12, -0.04) }, "f")
	_body(c, 14, "guard", { "head": Vector3(0.2, -0.1, -0.04), "neck": Vector3(0.06, 0, 0), "head_sq": 0.0 }, "a")
	_body(c, 16, "guard", { "head": Vector3(0.24, -0.1, -0.04), "neck": Vector3(0.08, 0, 0), "head_sq": 0.03 }, "f")
	_body(c, 20, "guard", { "head": Vector3(0.16, -0.1, -0.04), "neck": Vector3(0.04, 0, 0), "head_sq": 0.0 }, "a")
	_body(c, 30, "guard", { "head": Vector3(-0.08, 0.06, 0.04) }, "a")
	return c


## STAFF: twirl and sparkle (52 f). Twirled one-handed at her right in a
## tilted plane (the long end stays off the floor), caught upright and
## raised; the head sparkles (meta.sparkle: aura strength over time), she
## looks up at it, then lowers it to the guard.
static func twirl(st: String) -> BWAnimClips.Clip:
	var c := _new(st, "act_twirl", 52, false, "act", "guard", "guard")
	c.meta["kind"] = "special"
	var hp := _ends(c, "guard")
	var hpos := Vector3(-0.34, 0.16, 0.26)
	var axis := Vector3(-0.35, 0.65, 0.68).normalized()            # the twirl's tilted plane
	var from := axis.cross(Vector3(0, 0, 1)).normalized()
	if from.y < 0.0:
		from = -from
	c.key("hand_r_pos", 6, hpos, "f").key("hand_r_aim", 6, from, "f")
	BWAnimIdle._spin(c, "hand_r_aim", 7.0, 25.0, from, axis, 2.0)
	c.key("hand_r_pos", 16, hpos + Vector3(0.0, 0.02, 0.02)).key("hand_r_pos", 25, hpos, "f")
	c.key("hand_r_edge", 6, axis, "f").key("hand_r_edge", 25, axis, "f")
	# caught upright and raised, the head lit
	c.key("hand_r_pos", 30, Vector3(-0.36, 0.1, 0.18), "f").key("hand_r_aim", 30, Vector3(-0.25, 0.95, -0.15).normalized(), "f")
	c.key("hand_r_edge", 30, Vector3(0, 0.15, 1).normalized(), "f")
	c.key("hand_r_pos", 42, Vector3(-0.36, 0.12, 0.18), "f").key("hand_r_aim", 42, Vector3(-0.25, 0.95, -0.15).normalized(), "f")
	c.key("hand_l_pos", 8, (hp.hand_l_pos as Vector3) + Vector3(0.0, 0.03, 0.04))
	c.key("hand_l_pos", 34, (hp.hand_l_pos as Vector3) + Vector3(-0.04, 0.12, 0.12)).key("hand_l_pos", 42, (hp.hand_l_pos as Vector3) + Vector3(-0.04, 0.12, 0.12))
	c.key("flat", 6, 0.0).key("flat", 25, 0.0)
	c.meta["sparkle"] = [[29.0 / BWAnimClips.FPS, 0.0], [32.0 / BWAnimClips.FPS, 1.3], [36.0 / BWAnimClips.FPS, 0.8],
		[40.0 / BWAnimClips.FPS, 1.0], [46.0 / BWAnimClips.FPS, 0.0]]
	c.marker("sparkle", 32)
	_body(c, 6, "guard", { "head": Vector3(0.12, -0.2, -0.04) }, "a")
	_body(c, 16, "guard", { "head": Vector3(0.05, -0.28, -0.06), "chest": Vector3(0, -0.03, 0) }, "a")
	_body(c, 31, "guard", { "head": Vector3(-0.3, -0.18, -0.06), "chest": Vector3(-0.02, -0.03, 0), "root": Vector3(0, 0.004, 0) }, "f")
	_body(c, 42, "guard", { "head": Vector3(-0.28, -0.14, -0.04), "chest": Vector3(-0.02, -0.03, 0) }, "f")
	_body(c, 48, "guard", { "head": Vector3(0.0, -0.04, 0.0) }, "a")
	return c

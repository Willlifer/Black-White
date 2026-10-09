class_name BWAnimCarry
extends RefCounted
## Per-style hand data for the clip matrix (design/art/ANIMATION.md):
## which hand holds the weapon, which hand is free, the guard corrections,
## and how each style carries its weapon on the move.
##
## Every hand position here is in the CHEST frame (BWCharacterPose: origin
## at the chest pivot, +X her left, +Y up, +Z forward), so carried weapons
## ride the body's bounce and twist. Aimed actions (strikes, casts, shots)
## key their own hands in the root frame inside their clips.
##
## A carry is a pair of extremes, keyed by the gait one frame after each
## contact (the arms drag the legs):
##   a   at the LEFT foot's contact: left leg forward, so the right arm is
##       forward and the left arm back
##   b   at the RIGHT foot's contact
##   k   constants for the whole cycle (edges, poles, grips, flat)
## Weapon hands give pos + aim; free hands give pos only.

const PR := Vector3(-0.5, -0.1, -1.0)
const PL := Vector3(0.5, -0.1, -1.0)


## The hand holding the weapon: "r", "l" (bows) or "both" (paired daggers).
static func weapon_hand(style: String) -> String:
	match style:
		"bow": return "l"
		"pair", "fists": return "both"
	return "r"


## The hand that is free on the move and casts: "l", "r" (bows) or "" (pair).
static func free_hand(style: String) -> String:
	match style:
		"bow": return "r"
		"pair", "fists": return ""
	return "l"


## Two-handed in the guard (the left fist on the weapon's second point).
static func two_handed(style: String) -> bool:
	return style in ["heavy", "polearm", "staff"]


## Corrections to the static idle key that the clips use as their guard.
## Returned channels replace the static values.
static func guard_fix(style: String, g: Dictionary) -> Dictionary:
	match style:
		"heavy":
			# the static key's blade stood straight across her face from the
			# front 3/4 (style bar review round 3); leaning it out still grazed
			# the face on the idle's "hup", and any blade raised to her right
			# covers the face from a side camera (the face-cover test, azimuths
			# -90..90). The guard is now low and ready: fists at the right hip,
			# the blade out to her right and forward with the tip at chest
			# height, under the head from every camera.
			return {
				"hand_r_pos": (g.hand_r_pos as Vector3) + Vector3(-0.1, -0.04, -0.06),
				"hand_r_aim": Vector3(-0.84, 0.22, 0.5).normalized(),
				"hand_r_edge": Vector3(0.2, 0.9, 0.1).normalized(),
			}
		"one":
			# blade forward and out to her right, tip at chin height: reads
			# as ready without crossing the face
			return { "hand_r_pos": Vector3(-0.32, -0.26, 0.18), "hand_r_aim": Vector3(-0.45, 0.38, 0.81).normalized(),
				"hand_r_edge": Vector3(0.2, 0.75, -0.6).normalized() }
		"staff", "polearm", "spear":
			# upright at her side, but behind the shoulder line and tipped out
			# and back: a shaft stood in front of the shoulder covered the face
			# from the front 3/4 (the face-cover test)
			var out := { "hand_r_pos": (g.hand_r_pos as Vector3) + Vector3(-0.06, -0.04, -0.24),
				"hand_r_aim": Vector3(-0.2, 0.86, -0.52).normalized() }
			if style in BWAnimClips.SHIELD_SETS:
				# D520: the off hand is the shield arm, its forearm across the chest
				out.merge(BWAnimClips.shield_hand(0.0), true)
				out["hand_l_grip"] = 0.0
			return out
		"pistol":
			return { "hand_r_pos": Vector3(-0.27, -0.27, 0.22), "hand_r_aim": Vector3(0, 0.87, 0.5).normalized(),
				"hand_r_edge": Vector3(0, -0.5, 0.87).normalized() }
	return {}


## Locomotion carry for a style and gait ("walk", "run", "walk_heavy",
## "run_heavy", "limp").
static func loco(style: String, gait: String) -> Dictionary:
	var run := gait.begins_with("run")
	var out := { "a": {}, "b": {}, "k": {} }
	var fh := free_hand(style)
	# ----- the free arm: a pendulum when walking, a bent pump when running
	if fh != "":
		var sx := 1.0 if fh == "l" else -1.0
		var back := Vector3(0.23 * sx, -0.24, -0.2) if not run else Vector3(0.2 * sx, -0.1, -0.32)
		var front := Vector3(0.17 * sx, -0.12, 0.3) if not run else Vector3(0.1 * sx, 0.1, 0.33)
		var key := "hand_%s_pos" % fh
		# the left arm is back at the left contact; the right arm is forward
		out.a[key] = back if fh == "l" else front
		out.b[key] = front if fh == "l" else back
		out.k["hand_%s_pole" % fh] = (PL if fh == "l" else PR) + (Vector3(0, -0.3, 0) if run else Vector3.ZERO)
		out.k["hand_%s_grip" % fh] = 0.0
	# ----- the weapon
	var k: Dictionary = out.k
	var A: Dictionary = out.a
	var B: Dictionary = out.b
	match style:
		"one":
			# blade trails behind, edge down; tip low but clear of the floor
			if not run:
				_w(A, "r", Vector3(-0.25, -0.27, 0.14), Vector3(-0.15, -0.45, -0.88))
				_w(B, "r", Vector3(-0.28, -0.30, -0.10), Vector3(-0.2, -0.55, -0.81))
			else:
				_w(A, "r", Vector3(-0.2, -0.12, 0.26), Vector3(-0.2, -0.3, -0.93))
				_w(B, "r", Vector3(-0.27, -0.22, -0.2), Vector3(-0.25, -0.42, -0.87))
			k.merge({ "hand_r_edge": Vector3(0, -1, 0), "hand_r_pole": Vector3(-0.8, -0.2, -0.6), "flat": 0.6 }, true)
		"heavy":
			if gait.ends_with("_heavy"):
				# shouldered in both fists: the shaft lies back over the right
				# shoulder, the head (or anchor) behind her right ear
				_w(A, "r", Vector3(-0.10, 0.02, 0.26), Vector3(-0.34, 0.55, -0.76))
				_w(B, "r", Vector3(-0.12, -0.02, 0.24), Vector3(-0.34, 0.5, -0.8))
				k.merge({ "hand_r_edge": Vector3(0, 0.6, 0.8), "hand_r_pole": Vector3(-1, -0.6, -0.2), "hand_l_grip": 1.0,
					"hand_l_pos": Vector3(0.1, -0.1, 0.3), "hand_l_pole": Vector3(0.6, -1, 0.0), "flat": 0.5 }, true)
				A.erase("hand_l_pos")
				B.erase("hand_l_pos")
			elif run:
				# the flamberge trails one-handed off her right hip, flatter at speed
				_w(A, "r", Vector3(-0.24, -0.16, 0.12), Vector3(-0.25, -0.22, -0.94))
				_w(B, "r", Vector3(-0.28, -0.20, -0.12), Vector3(-0.25, -0.30, -0.92))
				k.merge({ "hand_r_edge": Vector3(0, -1, 0), "hand_r_pole": Vector3(-0.8, -0.2, -0.6), "flat": 0.6 }, true)
			else:
				_w(A, "r", Vector3(-0.27, -0.29, 0.03), Vector3(-0.22, -0.42, -0.88))
				_w(B, "r", Vector3(-0.27, -0.29, -0.08), Vector3(-0.22, -0.34, -0.9))
				k.merge({ "hand_r_edge": Vector3(0, -1, 0), "hand_r_pole": Vector3(-0.8, -0.2, -0.6), "flat": 0.6 }, true)
		"polearm", "staff":
			# at the slope: one fist, the shaft back over the right shoulder
			if style == "staff" and not run:
				# walking stick: upright, swung forward with the stride
				_w(A, "r", Vector3(-0.27, -0.10, 0.24), Vector3(0.0, 0.97, 0.25))
				_w(B, "r", Vector3(-0.29, -0.14, 0.0), Vector3(0.0, 0.99, -0.1))
			elif not run:
				_w(A, "r", Vector3(-0.20, -0.04, 0.20), Vector3(-0.12, 0.72, -0.68))
				_w(B, "r", Vector3(-0.22, -0.08, 0.12), Vector3(-0.12, 0.68, -0.72))
			else:
				_w(A, "r", Vector3(-0.18, 0.0, 0.22), Vector3(-0.15, 0.62, -0.77))
				_w(B, "r", Vector3(-0.22, -0.06, 0.10), Vector3(-0.15, 0.58, -0.8))
			k.merge({ "hand_r_edge": Vector3(0, 0.3, 1), "hand_r_pole": Vector3(-1, -0.6, -0.4), "hand_l_grip": 0.0, "flat": 0.6 }, true)
		"spear":
			if not run:
				# low trail, tip forward and up
				_w(A, "r", Vector3(-0.27, -0.26, 0.14), Vector3(-0.05, 0.35, 0.94))
				_w(B, "r", Vector3(-0.29, -0.30, -0.06), Vector3(-0.05, 0.25, 0.97))
				k.merge({ "hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": PR, "flat": 0.4 }, true)
			else:
				# over the shoulder, ready to throw
				_w(A, "r", Vector3(-0.29, 0.25, 0.0), Vector3(0.05, 0.12, 0.99))
				_w(B, "r", Vector3(-0.31, 0.20, -0.08), Vector3(0.05, 0.16, 0.99))
				k.merge({ "hand_r_edge": Vector3(0, 1, 0), "hand_r_pole": Vector3(-1, -0.5, -0.2), "flat": 0.3 }, true)
		"pair":
			if not run:
				_w(A, "r", Vector3(-0.24, -0.26, 0.22), Vector3(-0.15, 0.35, 0.92))
				_w(B, "r", Vector3(-0.26, -0.30, 0.0), Vector3(-0.2, 0.2, 0.96))
				_w(A, "l", Vector3(0.26, -0.30, 0.0), Vector3(0.2, 0.2, 0.96))
				_w(B, "l", Vector3(0.24, -0.26, 0.22), Vector3(0.15, 0.35, 0.92))
			else:
				# blades laid back along the forearms, arms pumping
				_w(A, "r", Vector3(-0.17, -0.04, 0.27), Vector3(-0.1, -0.25, -0.96))
				_w(B, "r", Vector3(-0.23, -0.18, -0.23), Vector3(-0.15, -0.4, -0.9))
				_w(A, "l", Vector3(0.23, -0.18, -0.23), Vector3(0.15, -0.4, -0.9))
				_w(B, "l", Vector3(0.17, -0.04, 0.27), Vector3(0.1, -0.25, -0.96))
			k.merge({ "hand_r_edge": Vector3(0, 1, 0), "hand_l_edge": Vector3(0, 1, 0), "hand_r_pole": PR, "hand_l_pole": PL,
				"flat": 0.8 }, true)
		"bow":
			if not run:
				_w(A, "l", Vector3(0.27, -0.30, -0.04), Vector3(0.15, 0.97, -0.1))
				_w(B, "l", Vector3(0.24, -0.24, 0.20), Vector3(0.12, 0.95, 0.25))
			else:
				_w(A, "l", Vector3(0.24, -0.18, -0.12), Vector3(0.2, 0.9, -0.35))
				_w(B, "l", Vector3(0.18, -0.06, 0.24), Vector3(0.15, 0.85, 0.5))
			k.merge({ "hand_l_edge": Vector3(0, 0, 1), "hand_l_pole": PL, "hand_r_grip": 0.0, "flat": 0.7 }, true)
		"fists":
			# a boxer's carry: the guard kept up and bobbing at a walk; at a
			# run the fists pump close to the body, knuckles forward
			var g := BWAnimClips.base_channels("fists")
			var up := func(h: String, punch: Vector3) -> Vector3:
				return (BWCharacterPose._fist(h, Vector3.ZERO, punch, Vector3(-0.7 if h == "r" else 0.7, 0.7, 0), PR).aim as Vector3)
			if not run:
				_w(A, "r", Vector3(-0.19, 0.24, 0.30), g.hand_r_aim)
				_w(B, "r", Vector3(-0.19, 0.27, 0.22), g.hand_r_aim)
				_w(A, "l", Vector3(0.17, 0.29, 0.30), g.hand_l_aim)
				_w(B, "l", Vector3(0.17, 0.26, 0.38), g.hand_l_aim)
			else:
				_w(A, "r", Vector3(-0.17, 0.12, 0.30), up.call("r", Vector3(0, 0.5, 1)))
				_w(B, "r", Vector3(-0.2, 0.0, -0.12), up.call("r", Vector3(0, 0.9, 0.3)))
				_w(A, "l", Vector3(0.2, 0.0, -0.12), up.call("l", Vector3(0, 0.9, 0.3)))
				_w(B, "l", Vector3(0.17, 0.12, 0.30), up.call("l", Vector3(0, 0.5, 1)))
			k.merge({ "hand_r_edge": g.hand_r_edge, "hand_l_edge": g.hand_l_edge, "hand_r_pole": Vector3(-0.5, -1, -0.3),
				"hand_l_pole": Vector3(0.5, -1, -0.3), "flat": 0.0 }, true)
		"pistol":
			if not run:
				# low ready, muzzle forward and down
				_w(A, "r", Vector3(-0.25, -0.26, 0.18), Vector3(0, 0.8, 0.6))
				_w(B, "r", Vector3(-0.27, -0.29, 0.04), Vector3(0, 0.85, 0.5))
				k.merge({ "hand_r_edge": Vector3(0, -0.6, 0.8), "hand_r_pole": PR, "flat": 0.3 }, true)
			else:
				# muzzle up by the shoulder
				_w(A, "r", Vector3(-0.2, 0.08, 0.2), Vector3(0.05, 0.1, -1))
				_w(B, "r", Vector3(-0.23, 0.02, 0.12), Vector3(0.05, 0.1, -1))
				k.merge({ "hand_r_edge": Vector3(0, 1, 0.1), "hand_r_pole": Vector3(-1, -0.5, -0.3), "flat": 0.3 }, true)
	return out


static func _w(d: Dictionary, hand: String, pos: Vector3, aim: Vector3) -> void:
	d["hand_%s_pos" % hand] = pos
	d["hand_%s_aim" % hand] = aim.normalized()


## The hand channels of a static key pose (BWCharacterPose.resolve), for
## clips that hit a reviewed key as an extreme (block, kneel, fall, ...).
## Only chest-frame keys are returned as-is; callers key them in clips whose
## hand_frame is the chest.
## lean_out (radians): a weapon pointing up is tipped out away from the
## head (right hand to her right, left hand to her left), so a reaction
## that borrows a static key doesn't stand a blade across the face.
static func key_hands(pose_name: String, style: String, lean_out: float = 0.0) -> Dictionary:
	var p := BWAnimClips.with_extras(BWCharacterPose.resolve(pose_name, style))
	var out := {}
	var wh := weapon_hand(style)
	for h in ["hand_r", "hand_l"]:
		var d: Dictionary = p[h]
		out[h + "_pos"] = d.pos
		out[h + "_aim"] = (d.aim as Vector3).normalized()
		var holds: bool = wh == "both" or "hand_" + wh == h
		if lean_out > 0.0 and holds and (out[h + "_aim"] as Vector3).y > 0.5:
			var sgn := 1.0 if h == "hand_r" else -1.0
			out[h + "_aim"] = (Basis(Vector3(0, 0, 1), sgn * lean_out) * (out[h + "_aim"] as Vector3)).normalized()
		out[h + "_edge"] = (d.edge as Vector3).normalized()
		out[h + "_pole"] = d.pole
		out[h + "_grip"] = float(d.get("grip", 0.0))
	out["flat"] = p.flat
	return out


## Hand channels offset from a hold: every hand position moved by `d`
## (chest frame) and every aim turned by `rot` (euler, radians).
static func shifted(hold: Dictionary, d: Vector3, rot := Vector3.ZERO, hands := ["hand_r", "hand_l"]) -> Dictionary:
	var out := {}
	var b := Basis.from_euler(rot)
	for h in hands:
		if hold.has(h + "_pos"):
			out[h + "_pos"] = (hold[h + "_pos"] as Vector3) + (d if h == "hand_r" else Vector3(d.x, d.y, d.z))
		if hold.has(h + "_aim"):
			out[h + "_aim"] = (b * (hold[h + "_aim"] as Vector3)).normalized()
	return out


## The hand channels of a clip's guard (its base pose).
static func guard_hands(base: Dictionary) -> Dictionary:
	var out := {}
	for ch in base:
		if str(ch).begins_with("hand_") or ch == "flat":
			out[ch] = base[ch]
	return out

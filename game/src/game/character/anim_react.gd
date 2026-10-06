class_name BWAnimReact
extends RefCounted
## Reaction clips for every set (design/art/ANIMATION.md, "Reactions"):
##
##   stricken  a clean hit ("hit"). Heavy: the approved style-bar clip; the
##             others share its body and feet, with their own hands
##   block     a glance or a resist: the guard snaps up, takes the blow
##             with the hands locked to the body, gives ground, re-sets
##   fumble    a normal hit in a cutscene: the block comes up late and is
##             knocked aside, a stagger step, a re-grip
##   dodge     a miss: a hop away (launch / land: the game shifts the root
##             by meta.shift), a crouch, a hop home (hop_start / hop_end)
##   kneel     a crit or a knockout blow: driven to one knee, a held
##             breath, then up again (a "fall" request cuts in for a KO)
##   fall      the knockout: two stagger steps, the knees go, flat on her
##             back with a bounce; grounded at "grounded" and HELD
##
## Every reaction has an `impact` marker: the frame the blow lands. The
## cutscene starts the reaction so its impact meets the attacker's `hit`
## (a block is up and a dodge is already moving when the blow arrives).
## Hands are in the chest frame: the reactions throw the whole body.


static func clips(st: String) -> Array:
	return [stricken(st), block(st), fumble(st), dodge(st), kneel(st), fall(st)] + BWAnimStricken.clips(st)


static func _hand_chans() -> Array:
	var out: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			out.append(ch)
	return out


const BODY := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]


static func _feet_base(c: BWAnimClips.Clip) -> Array:
	var b := c.base
	return [BWAnimClips.ground_of(b.foot_l_pos, 0.22), BWAnimClips.ground_of(b.foot_r_pos, -0.22)]


static func _foot(c: BWAnimClips.Clip, side: String, f: float, g: Vector2, pitch: float, yaw: float, lift: float = 0.0, mode: String = "a") -> void:
	c.pose(f, { "foot_%s_pos" % side: BWAnimClips.ankle(g, pitch, yaw, lift), "foot_%s_rot" % side: Vector3(pitch, yaw, 0) }, mode)


## Hand flail for the free (or second) hand: the reference stricken's left
## hand path, mirrored for a right free hand.
static func _flail(c: BWAnimClips.Clip, hand: String, frames: Dictionary) -> void:
	var sx := 1.0 if hand == "hand_l" else -1.0
	for f in frames:
		var v: Vector3 = frames[f]
		c.key(hand + "_pos", float(f), Vector3(v.x * sx, v.y, v.z))


# ------------------------------------------------------------------ stricken

static func stricken(st: String) -> BWAnimClips.Clip:
	if st == "heavy":
		return BWAnimClips._stricken()
	var ref := BWAnimClips._stricken()
	var c := BWAnimClips.new_clip("stricken", 32, false, st)
	for ch in BODY + ["foot_l_pos", "foot_l_rot", "foot_r_pos", "foot_r_rot"]:
		if ref.keys.has(ch):
			for k in ref.keys[ch]:
				c.key(ch, float(k[0]), k[1], str(k[2]))
	c.markers = ref.markers.duplicate()
	c.at_base(0, _hand_chans(), "l")
	c.at_base(32, _hand_chans())
	var guard := BWAnimCarry.guard_hands(c.base)
	var wh := BWAnimCarry.weapon_hand(st)
	var w := ["hand_r", "hand_l"] if wh == "both" else ["hand_" + wh]
	# the weapon is thrown back and up with the chest, then dips and re-sets
	c.pose(2, BWAnimCarry.shifted(guard, Vector3(-0.08, 0.1, -0.08), Vector3(-0.35, 0, 0), w))
	c.pose(4, BWAnimCarry.shifted(guard, Vector3(-0.1, 0.12, -0.1), Vector3(-0.4, 0, 0), w), "f")
	# (long shafts stood on end ride up with the weight drop instead: their
	# butts would go through the floor)
	var dip := 0.06 if st in ["polearm", "staff", "spear"] else -0.08
	c.pose(8, BWAnimCarry.shifted(guard, Vector3(0.0, dip, 0.06), Vector3(0.25 if dip < 0.0 else 0.08, 0, 0), w))
	c.pose(18, BWAnimCarry.shifted(guard, Vector3(0.02, dip * 0.75, 0.0), Vector3(0.08, 0, 0), w))
	c.pose(24, BWAnimCarry.shifted(guard, Vector3(0.0, 0.03, 0.0), Vector3(-0.04, 0, 0), w), "f")
	# the other hand lets go and flails (two-handers re-grip on f15)
	var other := "hand_l" if wh != "l" else "hand_r"
	if wh == "both":
		_flail(c, "hand_l", { 2: Vector3(0.36, 0.08, 0.16), 4: Vector3(0.44, 0.2, 0.02), 8: Vector3(0.34, -0.1, 0.14), 14: Vector3(0.28, -0.2, 0.2) })
	else:
		_flail(c, other, { 2: Vector3(0.36, 0.08, 0.16), 4: Vector3(0.44, 0.2, 0.0), 8: Vector3(0.36, -0.12, 0.12), 13: Vector3(0.28, -0.24, 0.16) })
		c.key(other + "_grip", 2, 0.0)
		if BWAnimCarry.two_handed(st):
			c.key(other + "_grip", 13, 0.3).key(other + "_grip", 15, 1.0)
		c.key(other + "_pole", 4, Vector3(0.6 if other == "hand_l" else -0.6, -1, 0.0))
	return c


# --------------------------------------------------------------------- block

## BLOCK (26 f): a 1 f dip, the block snaps up (f1-f3: the static block
## key, reviewed per style), the blow lands on f4 (impact): she is shoved
## back a step with the hands locked to the body, squashes, holds through
## the hit-stop, pushes back forward (f9), holds the guard up a beat, lowers.
static func block(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("block", 26, false, st)
	c.marker("impact", 4).marker("recovered", 20).marker("pose", 5)
	c.at_base(0, BODY + _hand_chans())
	c.at_base(26, BODY + _hand_chans())
	var bk := BWAnimCarry.key_hands("block", st)
	c.pose(1, { "root": Vector3(0, -0.07, 0.0), "squash": -0.015, "head": Vector3(0.1, 0, 0) })
	c.pose(3, { "root": Vector3(0, -0.11, -0.02), "spine": Vector3(0.05, 0, 0), "chest": Vector3(0.0, 0, 0), "head": Vector3(0.16, 0, 0), "squash": -0.01 }, "f")
	c.pose(3, bk, "f")
	# impact: the whole body gives; the hands ride the chest (locked)
	c.pose(5, { "root": Vector3(0, -0.15, -0.1), "spine": Vector3(-0.04, 0, 0), "chest": Vector3(-0.12, 0.06, 0.03), "head": Vector3(0.04, -0.12, 0.0),
		"squash": -0.045, "head_sq": 0.05 }, "f")
	c.pose(5, BWAnimCarry.shifted(bk, Vector3(0, -0.02, -0.05)), "f")
	c.pose(6.5, { "head_sq": 0.0 })
	c.pose(9, { "root": Vector3(0, -0.12, -0.08), "chest": Vector3(0.04, 0.0, 0.0), "head": Vector3(0.14, 0.0, 0.0), "squash": 0.015, "head_sq": -0.015 })
	c.pose(9, BWAnimCarry.shifted(bk, Vector3(0, 0.01, 0.03)))
	c.pose(14, { "root": Vector3(0, -0.115, -0.08), "chest": Vector3(0.0, 0.0, 0.0), "head": Vector3(0.12, 0.05, 0.0), "squash": 0.0 }, "f")
	c.pose(14, bk, "f")
	c.pose(19, { "root": Vector3(0, -0.05, -0.03), "head": Vector3(0.0, 0.0, 0.0) })
	var g := _feet_base(c)
	var fr2: Vector2 = g[1] + Vector2(-0.02, -0.12)
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 4, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 7, g[0], 0.3, 0.22)
	_foot(c, "l", 11, g[0], 0.12, 0.22)
	_foot(c, "l", 14, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 4.5, g[1], 0.2, -0.25)
	_foot(c, "r", 5.5, g[1].lerp(fr2, 0.5), 0.0, -0.3, 0.06)
	_foot(c, "r", 7, fr2, 0, -0.35, 0, "f")
	_foot(c, "r", 17, fr2, 0, -0.35, 0, "f")
	_foot(c, "r", 19, g[1].lerp(fr2, 0.5), 0.15, -0.3, 0.05)
	_foot(c, "r", 21, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 26, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 26, g[1], 0, -0.22, 0, "f")
	return c


# -------------------------------------------------------------------- fumble

## FUMBLE (34 f): the block starts up (f0-f2) but the blow (f3, impact)
## knocks it aside: the hands fly wide (the static fumble key), the chest
## spins and is thrown back, the head whips; the right foot steps back to
## catch (f5-f9), a wobble (f14), a re-grip and a re-set to the guard.
static func fumble(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("fumble", 34, false, st)
	c.marker("impact", 3).marker("catch", 10).marker("recovered", 27).marker("pose", 5)
	c.at_base(0, BODY + _hand_chans())
	c.at_base(34, BODY + _hand_chans())
	var bk := BWAnimCarry.key_hands("block", st)
	var fk := BWAnimCarry.key_hands("fumble", st, 0.5)
	var guard := BWAnimCarry.guard_hands(c.base)
	c.pose(2, BWAnimCarry.shifted(bk, Vector3(0, -0.12, 0.0)), "a")
	c.pose(2, { "root": Vector3(0, -0.08, 0.0), "head": Vector3(0.12, 0, 0), "squash": -0.01 })
	c.pose(3, { "root": Vector3(0, -0.07, -0.02) }, "l")
	c.pose(5, fk, "f")
	c.pose(5, { "root": Vector3(0, -0.06, -0.18), "hips": Vector3(-0.2, 0.1, 0.08), "spine": Vector3(-0.18, 0, 0),
		"chest": Vector3(-0.26, -0.22, 0.14), "head": Vector3(-0.22, 0.25, 0.05), "squash": 0.04, "head_sq": -0.035 }, "f")
	c.pose(4, { "head": Vector3(0.1, 0.05, 0.0), "head_sq": 0.0 })
	c.pose(9, { "root": Vector3(0, -0.17, -0.2), "hips": Vector3(-0.02, 0.08, 0.04), "spine": Vector3(0.02, 0, 0),
		"chest": Vector3(0.05, 0.02, 0.04), "head": Vector3(0.22, -0.06, 0.04), "squash": -0.05, "head_sq": 0.05 })
	c.pose(9, BWAnimCarry.shifted(fk, Vector3(0, -0.26, 0.1), Vector3(0.3, 0, 0)))
	c.pose(14, { "root": Vector3(0.02, -0.12, -0.17), "chest": Vector3(-0.04, -0.1, -0.05), "head": Vector3(0.0, 0.14, 0.05), "squash": 0.01, "head_sq": 0.0 })
	c.pose(18, { "root": Vector3(0.0, -0.1, -0.12), "chest": Vector3(-0.02, 0.0, 0.0), "head": Vector3(-0.06, -0.08, 0.0) })
	c.pose(18, BWAnimCarry.shifted(guard, Vector3(0.0, -0.05, 0.0), Vector3(0.1, 0, 0)))
	c.pose(26, { "root": Vector3(0, -0.02, -0.02), "squash": 0.02, "head_sq": -0.015, "head": Vector3(-0.1, 0.04, 0.02) }, "f")
	c.pose(26, BWAnimCarry.shifted(guard, Vector3(0, 0.025, 0)), "f")
	c.pose(30, { "root": Vector3(0, -0.042, 0.0), "squash": 0.0, "head_sq": 0.0 })
	if BWAnimCarry.two_handed(st):
		c.key("hand_l_grip", 4, 0.0).key("hand_l_grip", 15, 0.0).key("hand_l_grip", 18, 1.0)
	var g := _feet_base(c)
	var fr_back: Vector2 = g[1] + Vector2(-0.04, -0.28)
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 4, g[1], 0.3, -0.25)
	_foot(c, "r", 6, g[1].lerp(fr_back, 0.5), 0.1, -0.3, 0.12)
	_foot(c, "r", 8, fr_back, -0.25, -0.35, 0, "l")
	_foot(c, "r", 10, fr_back, 0, -0.35, 0, "f")
	_foot(c, "r", 19, fr_back, 0, -0.35, 0, "f")
	_foot(c, "r", 21.5, g[1].lerp(fr_back, 0.5), 0.2, -0.3, 0.12)
	_foot(c, "r", 24, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 6, g[0], 0.2, 0.22)
	_foot(c, "l", 10, g[0], 0.38, 0.22, 0, "f")
	_foot(c, "l", 18, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 34, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 34, g[0], 0, 0.22, 0, "f")
	return c


# --------------------------------------------------------------------- dodge

## DODGE (30 f): a 1 f dip, she springs away (launch f2: both feet off; the
## game moves the root by meta.shift, back and to her left, until land f6),
## the blow whiffs past (impact f5), she lands in a crouch, holds a cocky
## beat, and hops home (hop_start f16 .. hop_end f19).
static func dodge(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("dodge", 30, false, st)
	c.marker("launch", 2).marker("impact", 5).marker("land", 6).marker("hop_start", 16).marker("hop_end", 19).marker("recovered", 25).marker("pose", 7)
	c.meta = { "shift": Vector3(0.18, 0.0, -0.28) }
	c.at_base(0, BODY + _hand_chans())
	c.at_base(30, BODY + _hand_chans())
	var dk := BWAnimCarry.key_hands("dodge", st, 0.5)
	var guard := BWAnimCarry.guard_hands(c.base)
	c.pose(1, { "root": Vector3(0, -0.12, 0.0), "squash": -0.035, "head": Vector3(0.08, 0, 0) }, "f")
	c.pose(2, { "root": Vector3(0.02, -0.02, -0.02), "squash": 0.04, "head_sq": -0.03, "hips": Vector3(-0.04, 0.05, -0.08),
		"spine": Vector3(-0.06, 0, -0.06), "chest": Vector3(-0.12, 0.15, -0.12), "head": Vector3(0.0, -0.2, 0.12), "leg_stretch": 0.04 })
	c.pose(4, { "root": Vector3(0.04, 0.05, -0.04), "squash": 0.02, "leg_stretch": 0.0, "chest": Vector3(-0.14, 0.2, -0.18),
		"head": Vector3(0.02, -0.3, 0.18) }, "f")
	c.pose(3, dk, "a")
	c.pose(6, { "root": Vector3(0.05, -0.17, -0.02), "squash": -0.05, "head_sq": 0.045, "hips": Vector3(0.04, 0.1, -0.12),
		"spine": Vector3(0.08, 0, -0.1), "chest": Vector3(0.0, 0.15, -0.12), "head": Vector3(0.14, -0.25, 0.14) })
	c.pose(8, { "root": Vector3(0.05, -0.15, -0.02), "squash": -0.01, "head_sq": 0.0 }, "f")
	c.pose(8, BWAnimCarry.shifted(dk, Vector3(0, -0.06, 0.04)), "f")
	# the cocky beat: chin up, head tilts at the attacker
	c.pose(12, { "head": Vector3(-0.12, -0.3, 0.2), "root": Vector3(0.05, -0.13, -0.02) }, "f")
	c.pose(15, { "root": Vector3(0.04, -0.16, -0.01), "squash": -0.03, "head": Vector3(0.0, -0.15, 0.08) })
	c.pose(17, { "root": Vector3(0.02, -0.02, 0.0), "squash": 0.03, "head": Vector3(-0.04, 0.0, 0.0), "hips": Vector3(0, 0, 0),
		"spine": Vector3(0.03, 0, 0), "chest": Vector3(0.0, 0, 0) })
	c.pose(17, BWAnimCarry.shifted(guard, Vector3(0, 0.06, 0)))
	c.pose(19, { "root": Vector3(0, -0.11, 0.0), "squash": -0.035, "head_sq": 0.03 }, "f")
	c.pose(22, { "root": Vector3(0, -0.02, 0.0), "squash": 0.012, "head_sq": -0.01 })
	c.pose(22, guard)
	var g := _feet_base(c)
	var wide_l: Vector2 = g[0] + Vector2(0.12, -0.02)
	var wide_r: Vector2 = g[1] + Vector2(-0.04, -0.06)
	for s in ["l", "r"]:
		var i := 0 if s == "l" else 1
		var y := 0.22 if s == "l" else -0.22
		var wide: Vector2 = wide_l if s == "l" else wide_r
		_foot(c, s, 0, g[i], 0, y, 0, "f")
		_foot(c, s, 1.5, g[i], 0.35, y)
		_foot(c, s, 3.5, g[i].lerp(wide, 0.5), 0.2, y + 0.15 * (1.0 if s == "l" else -1.0), 0.14)
		_foot(c, s, 6 if s == "l" else 6.4, wide, 0, y + 0.2 * (1.0 if s == "l" else -1.0), 0, "f")
		_foot(c, s, 15.5, wide, 0, y + 0.2 * (1.0 if s == "l" else -1.0), 0, "f")
		_foot(c, s, 16.5, wide, 0.35, y + 0.15 * (1.0 if s == "l" else -1.0))
		_foot(c, s, 17.8, g[i].lerp(wide, 0.5), 0.15, y, 0.1)
		_foot(c, s, 19 if s == "l" else 19.3, g[i], 0, y, 0, "f")
		_foot(c, s, 30, g[i], 0, y, 0, "f")
	return c


# --------------------------------------------------------------------- kneel

## KNEEL (46 f): the blow lands on f0 (impact), recoil (f0-f3), the knees
## go (f5), the right knee hits the floor on f8 (squash, the head drops a
## frame later), a heavy held breath with the weapon propped (the static
## kneel key), then she pushes up off the front foot (f28-f34), overshoots
## and settles to the guard.
static func kneel(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("kneel", 46, false, st)
	c.marker("impact", 0).marker("down", 8).marker("rise", 28).marker("recovered", 40).marker("pose", 14)
	c.at_base(0, BODY + _hand_chans(), "l")
	c.at_base(46, BODY + _hand_chans())
	# the static kneel key, lifted: on the clip's deeper knee and lean the
	# key's propped shafts and low muzzles would go through the floor
	var kk := BWAnimCarry.key_hands("kneel", st)
	kk.merge(BWAnimCarry.shifted(kk, Vector3(0, 0.2, 0.02), Vector3(-0.3 if st == "pistol" else -0.2, 0, 0)), true)
	match st:
		"polearm", "staff", "spear":
			# the shaft laid across the thigh (a planted prop went through the
			# floor with the longer shafts)
			kk.merge({ "hand_r_pos": Vector3(-0.2, -0.1, 0.34), "hand_r_aim": Vector3(0.95, 0.22, 0.2).normalized(),
				"hand_r_edge": Vector3(0, 1, 0), "flat": 0.6 }, true)
		"pistol":
			# muzzle up and forward, still covering the attacker
			kk.merge({ "hand_r_pos": Vector3(-0.2, -0.12, 0.34), "hand_r_aim": Vector3(0, 0.9, 0.42).normalized(),
				"hand_r_edge": Vector3(0, -0.42, 0.9).normalized() }, true)
	var hk := BWAnimCarry.key_hands("hit", st, 0.5)
	var kb := BWCharacterPose.resolve("kneel", st)
	c.pose(2, { "root": Vector3(0, -0.08, -0.12), "spine": Vector3(-0.12, 0, 0), "chest": Vector3(-0.22, 0.08, 0.06),
		"head": Vector3(0.1, 0.0, 0.0), "squash": 0.04, "head_sq": -0.03 })
	c.pose(3, hk, "a")
	c.pose(4, { "head": Vector3(-0.22, 0.1, 0.0) })
	c.pose(5, { "root": Vector3(0, -0.22, -0.06), "hips": Vector3(0.08, 0, 0), "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.05, 0, 0), "squash": -0.02 })
	c.pose(8, { "root": (kb.root as Vector3) + Vector3(0, -0.02, 0), "hips": kb.hips, "spine": (kb.spine as Vector3) + Vector3(0.03, 0, 0),
		"chest": (kb.chest as Vector3) + Vector3(0.03, 0, 0), "squash": -0.05 }, "l")
	c.pose(9, { "head": (kb.head as Vector3) + Vector3(0.25, 0, 0), "head_sq": 0.06, "neck": Vector3(0.1, 0, 0) })
	c.pose(8, kk, "a")
	c.pose(11, { "root": kb.root, "squash": 0.0, "head_sq": -0.01 }, "f")
	c.pose(12, { "head": (kb.head as Vector3) + Vector3(0.18, 0, 0), "head_sq": 0.0 })
	# the held breath: two heavy breaths, head down
	c.pose(16, { "chest": (kb.chest as Vector3) + Vector3(-0.04, 0, 0), "squash": 0.015, "head": (kb.head as Vector3) + Vector3(0.1, 0.05, 0) })
	c.pose(21, { "chest": (kb.chest as Vector3) + Vector3(0.06, 0, 0), "squash": -0.012, "head": (kb.head as Vector3) + Vector3(0.2, 0.0, 0) })
	c.pose(25, { "chest": kb.chest, "squash": 0.01, "head": (kb.head as Vector3) + Vector3(-0.05, -0.05, 0), "root": kb.root }, "f")
	c.pose(25, kk, "f")
	# up: lean onto the front foot, drive
	c.pose(28, { "root": (kb.root as Vector3) + Vector3(0, -0.02, 0.06), "spine": Vector3(0.24, 0, 0), "chest": Vector3(0.08, 0, 0),
		"head": Vector3(0.0, 0, 0), "squash": -0.03 })
	# the weapon comes up with the push (it would swing into the floor on the lean)
	c.pose(28, BWAnimCarry.shifted(kk, Vector3(0, 0.08, 0.0), Vector3(-0.2, 0, 0)))
	c.pose(32, { "root": Vector3(0, -0.14, 0.04), "spine": Vector3(0.15, 0, 0), "chest": Vector3(0.05, 0, 0), "squash": 0.02 })
	c.pose(35, { "root": Vector3(0, -0.01, 0.0), "spine": Vector3(0.0, 0, 0), "squash": 0.025, "head": Vector3(-0.12, 0, 0), "head_sq": -0.02 }, "f")
	c.pose(39, { "root": Vector3(0, -0.05, 0.0), "squash": -0.005, "head_sq": 0.01 })
	c.pose(33, BWAnimCarry.guard_hands(c.base))
	var g := _feet_base(c)
	var fk: Dictionary = kb.foot_l
	var rk: Dictionary = kb.foot_r
	var gl := BWAnimClips.ground_of(fk.pos, float(fk.rot.y))
	var gr := Vector2(float(rk.pos.x), float(rk.pos.z))
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 3, g[0], 0.25, 0.22)
	_foot(c, "l", 4.5, g[0].lerp(gl, 0.5), 0.0, 0.18, 0.07)
	_foot(c, "l", 6.5, gl, 0, float(fk.rot.y), 0, "f")
	_foot(c, "l", 30, gl, 0, float(fk.rot.y), 0, "f")
	_foot(c, "l", 34, gl, 0, float(fk.rot.y), 0, "f")
	_foot(c, "l", 36, g[0].lerp(gl, 0.5), 0.1, 0.2, 0.06)
	_foot(c, "l", 38, g[0], 0, 0.22, 0, "f")
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 4, g[1], 0.4, -0.2)
	c.pose(8, { "foot_r_pos": rk.pos, "foot_r_rot": rk.rot, "foot_r_pole": rk.pole }, "f")
	c.pose(29, { "foot_r_pos": rk.pos, "foot_r_rot": rk.rot, "foot_r_pole": rk.pole }, "f")
	_foot(c, "r", 31.5, g[1].lerp(gr, 0.4), 0.5, -0.2, 0.08)
	_foot(c, "r", 33.5, g[1], 0, -0.22, 0, "f")
	c.pose(33.5, { "foot_r_pole": Vector3(0, 0, 1) }, "f")
	_foot(c, "r", 46, g[1], 0, -0.22, 0, "f")
	_foot(c, "l", 46, g[0], 0, 0.22, 0, "f")
	return c


# ---------------------------------------------------------------------- fall

## FALL (40 f, held at the end): the blow (f0, impact) throws her back, the
## right foot steps back to catch (f2-f5) and fails, the left staggers
## (f6-f9), the knees go (f10), she drops onto her seat (f13) and back
## (f16, grounded), the legs kick up with the impact and drop (f16-f20), a
## small bounce, and she lies still with the head lolled to one side.
static func fall(st: String) -> BWAnimClips.Clip:
	var c := BWAnimClips.new_clip("fall", 40, false, st)
	c.marker("impact", 0).marker("grounded", 16).marker("still", 26).marker("pose", 30)
	c.meta = { "hold_end": true }
	c.at_base(0, BODY + _hand_chans(), "l")
	var fb := BWCharacterPose.resolve("fall", st)
	var fh := BWAnimCarry.key_hands("fall", st, 0.5)
	var hk := BWAnimCarry.key_hands("hit", st, 0.5)
	c.pose(2, { "root": Vector3(0, -0.06, -0.16), "hips": Vector3(-0.14, 0.05, 0.05), "spine": Vector3(-0.16, 0, 0),
		"chest": Vector3(-0.28, 0.12, 0.08), "head": Vector3(0.18, -0.05, 0.0), "squash": 0.05, "head_sq": -0.035 })
	c.pose(3, hk, "a")
	c.pose(4, { "head": Vector3(-0.28, 0.12, -0.04), "head_sq": 0.0 })
	c.pose(6, { "root": Vector3(0, -0.14, -0.26), "hips": Vector3(-0.2, 0.0, 0.0), "chest": Vector3(-0.1, -0.06, -0.05), "head": Vector3(0.1, -0.1, 0.0),
		"squash": -0.03 })
	c.pose(9, { "root": Vector3(0, -0.12, -0.34), "hips": Vector3(-0.3, 0.06, 0.04), "chest": Vector3(-0.18, 0.1, 0.06), "head": Vector3(-0.15, 0.1, 0.0),
		"squash": 0.01 })
	c.pose(11, { "root": Vector3(0, -0.34, -0.38), "hips": Vector3(-0.55, 0.0, 0.0), "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.1, 0, 0),
		"head": Vector3(0.2, 0.0, 0.0), "squash": -0.02 })
	c.pose(13, { "root": Vector3(0, -0.58, -0.42), "hips": Vector3(-0.9, 0.0, 0.0), "spine": Vector3(0.05, 0, 0), "chest": Vector3(-0.05, 0, 0),
		"head": Vector3(0.3, 0.0, 0.0), "squash": -0.04, "head_sq": 0.04 }, "l")
	c.pose(16, { "root": (fb.root as Vector3) + Vector3(0, -0.01, 0), "hips": fb.hips, "spine": fb.spine, "chest": (fb.chest as Vector3) + Vector3(-0.06, 0, 0),
		"head": (fb.head as Vector3) + Vector3(-0.3, -0.3, 0), "neck": fb.neck, "squash": -0.05, "head_sq": 0.06 }, "l")
	c.pose(18.5, { "root": (fb.root as Vector3) + Vector3(0, 0.035, 0), "chest": (fb.chest as Vector3) + Vector3(0.04, 0, 0), "squash": 0.02, "head_sq": -0.02,
		"head": (fb.head as Vector3) + Vector3(0.15, -0.1, 0) })
	c.pose(21, { "root": fb.root, "squash": 0.0, "head_sq": 0.0, "chest": fb.chest, "head": (fb.head as Vector3) + Vector3(-0.05, 0.1, 0) }, "f")
	c.pose(26, { "head": (fb.head as Vector3) + Vector3(0.0, 0.25, 0.1) }, "f")
	c.pose(40, { "root": fb.root, "hips": fb.hips, "spine": fb.spine, "chest": fb.chest, "neck": fb.neck,
		"head": (fb.head as Vector3) + Vector3(0.0, 0.27, 0.1), "squash": 0.0, "head_sq": 0.0 }, "f")
	# arms fling up as she goes over, flop out at the impact
	var up := BWAnimCarry.shifted(fh, Vector3(0, 0.2, 0.1), Vector3(-0.3, 0, 0))
	c.pose(12, up)
	c.pose(16, BWAnimCarry.shifted(fh, Vector3(0, -0.04, 0.06)), "l")
	c.pose(19, BWAnimCarry.shifted(fh, Vector3(0, 0.03, 0.0)))
	c.pose(23, fh, "f")
	c.pose(40, fh, "f")
	# feet: catch step back (right), stagger (left), then forward and up as she
	# goes down; a kick on the ground impact; still
	var g := _feet_base(c)
	var fl: Dictionary = fb.foot_l
	var fr: Dictionary = fb.foot_r
	var r_back: Vector2 = g[1] + Vector2(-0.02, -0.3)
	var l_back: Vector2 = g[0] + Vector2(0.02, -0.26)
	_foot(c, "r", 0, g[1], 0, -0.22, 0, "f")
	_foot(c, "r", 2, g[1], 0.3, -0.25)
	_foot(c, "r", 3.5, g[1].lerp(r_back, 0.5), 0.1, -0.3, 0.1)
	_foot(c, "r", 5, r_back, -0.2, -0.35, 0, "l")
	_foot(c, "r", 6, r_back, 0, -0.35, 0, "f")
	_foot(c, "l", 0, g[0], 0, 0.22, 0, "f")
	_foot(c, "l", 5.5, g[0], 0.35, 0.22)
	_foot(c, "l", 7.5, g[0].lerp(l_back, 0.5), 0.1, 0.25, 0.1)
	_foot(c, "l", 9, l_back, -0.2, 0.3, 0, "l")
	_foot(c, "l", 10, l_back, 0, 0.3, 0, "f")
	_foot(c, "r", 10, r_back, 0, -0.35, 0, "f")
	for s in ["l", "r"]:
		var fd: Dictionary = fl if s == "l" else fr
		var pos: Vector3 = fd.pos
		var rot: Vector3 = fd.rot
		c.pose(13, { "foot_%s_pos" % s: Vector3(pos.x, 0.09, lerpf(-0.15, pos.z, 0.5)), "foot_%s_rot" % s: Vector3(-0.4, rot.y, 0),
			"foot_%s_pole" % s: fd.pole })
		c.pose(16.5, { "foot_%s_pos" % s: pos + Vector3(0, 0.2 if s == "l" else 0.14, 0.06), "foot_%s_rot" % s: rot + Vector3(-0.2, 0, 0) })
		c.pose(19.5, { "foot_%s_pos" % s: pos, "foot_%s_rot" % s: rot }, "f")
		c.pose(40, { "foot_%s_pos" % s: pos, "foot_%s_rot" % s: rot, "foot_%s_pole" % s: fd.pole }, "f")
	return c

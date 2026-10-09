class_name BWClipRoute
extends RefCounted
## Which clip an action plays: the animation fit sweep (D219-D222,
## design/art/ANIMATION-AUDIT.md). The combat screen asks here; the skill
## defs name their pose in `clip` (a strike hook such as "thrust", or a
## setup pose such as "brace"), BWAnimClips.actions_for maps poses to clips
## per weapon style, and tools/anim_audit.gd prints the whole table.
##
## The rules:
##   cast     a spell weapon (the staff) casts; an Elemental Being casts
##            every attack (D220); a def whose clip is "cast" casts. A
##            weapon skill used at range STRIKES with its weapon and the bolt
##            leaves on the hit (D221: before, any elemental skill at range
##            played the free-hand cast: Earthsplitter, Tridentpierce,
##            Guardrush, Hook, Shockwave Palm at reach)
##   strike   the def's clip when the unit's style has it, else the class
##            strike (unchanged, D102)
##   setup    a skill with no blows plays the def's clip when the style has
##            it (brace, war_cry, aim, reload, tumble); else a staff
##            channels (a channel aimed at a tile ends in a cast at it) and
##            any other weapon plays nothing (Vault's and an empty Charge's
##            beat: the leap or the dash already showed it; it was the
##            free-hand channel, D221)
##   multi    a multi-blow clip (flurry: 3, hundred: 6) carries its later
##            strikes on its own hit2.. markers, in one cutscene, instead of
##            replaying the jab per strike (D221)

## Clips that land several blows: pose -> blows the clip shows.
const MULTI := { "flurry": 3, "hundred": 6 }
## A setup pose's hold before the unit returns to idle (s).
const SETUP_HOLD := { "brace": 1.15, "war_cry": 1.35, "aim": 0.75, "reload": 1.6, "tumble": 0.95, "channel": 0.35,
	"flourish": 0.83 }    # D516: Self-detonate blows at the flourish's peak (its "hit", f20)
## What a status does to the unit when it lands (D222): a reaction clip.
## Pinned has none (its arrow at the feet and the blow's reaction carry it).
const STATUS_POSE := { "staggered": "stricken_stumble", "blinded": "stricken_flinch" }


## ---------------------------------------------------------------- D510
## ALTERNATE CLIPS. A blow can play an alternate clip instead of its usual
## one: the author's tuning table, "<set>|<weapon class>|<base pose>" ->
## { pose: weight }. The base pose is the def's clip ("thrust") or "strike"
## (basic attacks, counters and skills with no clip of their own). "" in a
## table = the usual clip itself. The pick is a weighted roll on a hash of
## the blow (attacker, target, damage, hit, crit, HP left, strike index), so
## the same blow always plays the same clip (replays, the showcase, tests);
## it never touches the battle's RNG: it is view only.
## Weights are relative: { "": 1.0, "smash": 1.0 } plays each half the time.
const ALTERNATES := {
	# D511 the 2h smash (and its flip, a quarter of the smashes) for the
	# two-handers; D512 the underhand sweep for the axes
	"heavy|sword|strike": { "": 1.0, "smash": 0.75, "smash_flip": 0.25 },
	"heavy|axe|strike": { "": 1.0, "sweep_under": 1.0, "smash": 0.75, "smash_flip": 0.25 },
	"one|axe|strike": { "": 1.0, "sweep_under": 1.0, "smash": 0.75, "smash_flip": 0.25 },
	"polearm|lance|strike": { "": 1.0, "smash": 0.75, "smash_flip": 0.25 },
	# D514 / D515 the sword's thrusts: the 2h thrust and the fencing lunge
	"one|sword|strike": { "": 1.0, "thrust_2h": 0.5, "lunge": 0.5 },
	"one|sword|thrust": { "": 1.0, "thrust_2h": 1.0, "lunge": 1.0 },
	# D515 every lance stab (basics, Tridentpierce, Guardrush ...): half lunges
	"spear|lance|strike": { "": 1.0, "lunge": 1.0 },
	# D516 the dagger flourish; D518 the bow's jump shot
	"pair|daggers|strike": { "": 1.0, "flourish": 1.0 },
	"bow|bow|strike": { "": 1.0, "shot_jump": 1.0 },
}
## A crit plays this pose whenever the blow's table offers it (D511: crits
## always flip).
const CRIT_POSE := "smash_flip"
## Alternates that only fit a blow at arm's length.
const MELEE_ONLY: PackedStringArray = ["smash", "smash_flip", "sweep_under", "flourish", "backstab"]
## D517: a dagger blow from behind (BWBattle.behind; the attack event's
## "behind") sneaks round and stabs the back. Every basic dagger attack from
## behind, and Assassinate (from behind by its rule).
const BACKSTAB_SKILLS: PackedStringArray = ["assassinate"]
## D516: setup skills that play a pose of their own where the set has it
## (else the def's clip, as before): Self-detonate's flourish (daggers).
const SETUP_BY_SKILL := { "self_detonate": "flourish" }


## The pose a blow plays (assigned to BWUnitView.skill; "" = the class
## strike). `has` answers whether the unit's set has a pose. ctx:
##   melee (bool), single (bool: one target), crit (bool), behind (bool),
##   skill_name (display name, for Assassinate), salt (String: the blow).
static func pick(set_id: String, weapon_class: String, skill_clip: String, has: Callable, ctx: Dictionary = {}) -> String:
	var melee := bool(ctx.get("melee", true))
	var sk := str(ctx.get("skill_name", "")).to_lower()
	if set_id == "pair" and melee and skill_clip == "" and bool(has.call("backstab")) \
			and ((bool(ctx.get("behind", false)) and sk == "") or sk in BACKSTAB_SKILLS):
		return "backstab"                  # Assassinate is from behind by its rule
	var base := skill_clip if skill_clip != "" else "strike"
	var table: Dictionary = ALTERNATES.get("%s|%s|%s" % [set_id, weapon_class, base], {})
	if table.is_empty() or not bool(ctx.get("single", true)):
		return skill_clip
	var opts: Array = []
	var total := 0.0
	for p in table:
		var pose := str(p)
		var w := float(table[p])
		if w <= 0.0 or (pose in MELEE_ONLY and not melee):
			continue
		if pose != "" and pose != skill_clip and not bool(has.call(pose)):
			continue
		opts.append([pose, w])
		total += w
	if bool(ctx.get("crit", false)):
		for o in opts:
			if o[0] == CRIT_POSE:
				return CRIT_POSE
	if opts.is_empty() or total <= 0.0:
		return skill_clip
	var r := roll(str(ctx.get("salt", ""))) * total
	for o in opts:
		r -= float(o[1])
		if r < 0.0:
			return skill_clip if str(o[0]) == "" else str(o[0])
	return skill_clip if str(opts.back()[0]) == "" else str(opts.back()[0])


## A deterministic 0..1 from a string (the blow's salt): never the battle RNG.
static func roll(salt: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("alt|" + salt)
	return rng.randf()


## The salt of one blow (combat screen and tests): the same blow, the same pick.
static func salt_of(attacker_id: String, r: Dictionary) -> String:
	var res: Dictionary = r.get("result", {})
	return "%s|%s|%d|%s|%s|%d|%d" % [attacker_id, str(r.get("target", "")), int(res.get("damage", 0)), str(bool(res.get("hit", true))),
		str(bool(res.get("crit", false))), int(r.get("target_hp", -1)), int(r.get("strike", 0))]


## The setup pose a skill with no blows plays (D516: a skill's own pose
## first, e.g. Self-detonate's flourish; then the def's clip; then the channel).
static func setup_pose_for(skill_key: String, skill_clip: String, has_clip: Callable, staff: bool = true) -> String:
	var own := str(SETUP_BY_SKILL.get(skill_key, ""))
	if own != "" and bool(has_clip.call(own)):
		return own
	return setup_pose(skill_clip, has_clip, staff)
## ------------------------------------------------------------ end D510


## Does the attacker cast (channel + cast, a bolt on the release) rather
## than strike with its weapon?
static func casts(u: BWUnit, spell: bool, skill_clip: String = "") -> bool:
	if u != null and str(u.encounter) == "being":
		return true
	return spell or skill_clip == "cast"


## The pose a setup beat plays ("" = none): the def's clip when the unit
## has it, else the channel.
static func setup_pose(skill_clip: String, has_clip: Callable, staff: bool = true) -> String:
	if skill_clip != "" and bool(has_clip.call(skill_clip)):
		return skill_clip
	return "channel" if staff and bool(has_clip.call("channel")) else ""


static func setup_hold(pose: String) -> float:
	return float(SETUP_HOLD.get(pose, 0.35))


## The later strikes of a multi-blow skill a clip shows itself: how many
## blows the pose lands (0 = it isn't one).
static func multi_hits(skill_clip: String) -> int:
	return int(MULTI.get(skill_clip, 0))


## Audit / tests: the route of one skill use for a weapon style.
## { mode: area | setup | cast | strike, pose, clip, melee }
static func skill(key: String, set_id: String, weapon_class: String, dist: int, _element: String, has_results: bool, u: BWUnit = null) -> Dictionary:
	var dclip := BWSkillRegistry.clip(key)
	var acts := BWAnimClips.actions_for(set_id, "axe" if weapon_class == "axe" else "")
	var lib := BWAnimClips.load_set(set_id)
	var has := func(p: String) -> bool:
		return acts.has(p) and lib.has_animation(StringName(str(acts[p].clip)))
	if set_id == "bow" and key in BWRangedVFX.AREA_SKILLS:
		return { "mode": "area", "pose": dclip, "clip": str(acts.get(dclip, {}).get("clip", "")) }
	if not has_results:
		var sp := setup_pose(dclip, has, set_id == "staff")
		var out := { "mode": "setup", "pose": sp, "clip": str(acts.get(sp, {}).get("clip", "")) }
		if sp == "channel" and BWSkillRegistry.row(key).get("targeting", "") in ["hex", "dir", "unit"]:
			out["then"] = "cast"
		return out
	if casts(u, set_id == "staff", dclip):
		return { "mode": "cast", "pose": "channel>cast", "clip": "cast", "melee": dist <= 1 }
	var pose := dclip if dclip != "" and bool(has.call(dclip)) else "strike"
	return { "mode": "strike", "pose": pose, "clip": str(acts[pose].clip), "melee": dist <= 1, "multi": multi_hits(dclip) }

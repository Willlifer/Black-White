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
const SETUP_HOLD := { "brace": 1.15, "war_cry": 1.35, "aim": 0.75, "reload": 1.6, "tumble": 0.95, "channel": 0.35 }
## What a status does to the unit when it lands (D222): a reaction clip.
## Pinned has none (its arrow at the feet and the blow's reaction carry it).
const STATUS_POSE := { "staggered": "stricken_stumble", "blinded": "stricken_flinch" }


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

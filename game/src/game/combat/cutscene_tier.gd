class_name BWCutsceneTier
extends RefCounted
## D122: how much cutscene an action gets. One pure function, event -> tier,
## so the rule is testable and the screen only plays what it is told.
##
##   MINIMAL  in place: the clip, the reaction, the number, the odds strip
##            briefly. No zoom, no dim, no callout.
##   SHORT    the zoom and dim, a brief callout (~0.3 s), no long holds.
##   FULL     the whole cutscene: zoom, callout hold, crit flash, returns.
##
## Defaults (author): basic / auto attacks, extra strikes, riposte answers,
## counters and overwatch shots, and setup skills (no damage) are MINIMAL;
## once-per-battle skills and long-cooldown skills (cd >= 3) are FULL;
## other damaging skills (cd <= 2) are SHORT. A crit or a KO anywhere in the
## event's results upgrades it to FULL (results are known before playback).
## Enemy turns use the same rules.
##
## D237 (author, playtest 1: "when targeting the ground, we don't need a
## cutscene unless someone is being damaged"): a skill aimed at a hex or a
## direction (GROUND_TARGETING: paints, Saturate, Ley Line, Transfer,
## Inversion, Aegis, Siphon, gale spreads, arming a fuse, an area shot at
## nobody ...) plays in place (MINIMAL, `ground` true) unless the action
## damages a unit: a direct blow that lands, or, in the action's queued
## events up to its `growth` (`after`), a detonation / splash `tile_damage`,
## a `chain` arc or a follow-on strike. Then the rules above apply as before.
## The results are known before playback, so this is decided up front.
##
## Modes (the player's setting, F cycles them): "default"; "fast" = one
## tier lower (Full -> Short, Short -> Minimal); "minimal" = everything
## MINIMAL. A crit always keeps a flash: the full white-out on FULL, a tiny
## one otherwise.

enum { MINIMAL, SHORT, FULL }
const NAMES := ["minimal", "short", "full"]
const MODES := ["default", "fast", "minimal"]
const MODE_LABELS := { "default": "Default", "fast": "Fast", "minimal": "Minimal" }
const LONG_CD := 3
## D237: targeting kinds that aim at the ground rather than at a unit.
const GROUND_TARGETING := ["hex", "dir"]
## Events that close an action's tail (D237's look-ahead stops there).
const ACTION_END := ["growth", "turn", "battle_end", "cycle"]

## Event types that carry blows and get a tier.
const BLOW_EVENTS := ["attack", "counter", "riposte", "skill"]


## { tier: int, name: String, base: int, crit: bool, ko: bool, flash: "full"|"tiny"|"none",
##   callout: bool, ground: bool }. `row` overrides the skill lookup (tests).
## `after`: the events queued behind `e` (D237: its action's detonations,
## splash and arcs); empty = only `e`'s own results count.
static func tier_for(e: Dictionary, mode: String = "default", row: Variant = null, after: Array = []) -> Dictionary:
	var b := base(e, row)
	var crit := has_crit(e)
	var ko := has_ko(e)
	var t := FULL if (crit or ko) else b
	var ground := ground_quiet(e, row, after)
	if ground:
		t = MINIMAL                                   # D237: aimed at the ground, nobody hurt
	match mode:
		"fast": t = maxi(t - 1, MINIMAL)
		"minimal": t = MINIMAL
	var flash := "none"
	if crit:
		flash = "full" if t == FULL else "tiny"
	return { "tier": t, "name": NAMES[t], "base": b, "crit": crit, "ko": ko, "flash": flash,
		"callout": t >= SHORT and str(e.get("type", "")) == "skill", "ground": ground }


## D237: a skill aimed at the ground whose action hurts nobody.
static func ground_quiet(e: Dictionary, row: Variant = null, after: Array = []) -> bool:
	if str(e.get("type", "")) != "skill":
		return false
	var r: Dictionary = row if row is Dictionary else BWSkills.get_skill(str(e.get("skill", "")))
	if not str(r.get("targeting", "")) in GROUND_TARGETING:
		return false
	return not damages(e, after)


## D237: does the action hurt a unit? `e`'s own blows that land, then its
## tail in `after` (to the action's end): detonation / splash ground damage,
## a chain arc, a follow-on strike.
static func damages(e: Dictionary, after: Array = []) -> bool:
	for x in _results(e):
		if _lands((x as Dictionary).get("result", {})):
			return true
	for q in after:
		var ty := str((q as Dictionary).get("type", ""))
		if ty in ACTION_END:
			return false
		match ty:
			"tile_damage":
				if int(q.get("amount", 0)) > 0 and str(q.get("cause", "")) != "pulse":
					return true
			"chain":
				if int(q.get("amount", 0)) > 0:
					return true
			"attack":
				if _lands(q.get("result", {})):
					return true
	return false


## D237: does a detonation hurt anyone? The blast's own damage lines follow
## its `detonate` event(s) in the queue (`after`), up to the action's end.
static func blast_hurts(after: Array) -> bool:
	for q in after:
		var ty := str((q as Dictionary).get("type", ""))
		if ty in ACTION_END:
			return false
		if ty == "tile_damage" and str(q.get("cause", "")) == "detonation" and int(q.get("amount", 0)) > 0:
			return true
	return false


static func _lands(res: Dictionary) -> bool:
	return bool(res.get("hit", true)) and int(res.get("damage", 0)) > 0


## The tier before any upgrade or mode.
static func base(e: Dictionary, row: Variant = null) -> int:
	match str(e.get("type", "")):
		"skill":
			var r: Dictionary = row if row is Dictionary else BWSkills.get_skill(str(e.get("skill", "")))
			return skill_base(r)
	return MINIMAL          # attack (basic, auto, extra strikes), counter, overwatch, riposte


## A skill's default tier from its row.
static func skill_base(r: Dictionary) -> int:
	if r.is_empty() or bool(r.get("basic", false)):
		return MINIMAL
	if bool(r.get("once_per_battle", false)):
		return FULL
	if int(r.get("power", 0)) <= 0:
		return MINIMAL       # setup: buffs, guards, paints, Transfer, Inversion, Set Spear, Aegis ...
	if int(r.get("cd", 0)) >= LONG_CD:
		return FULL
	return SHORT


static func _results(e: Dictionary) -> Array:
	if e.has("results"):
		return e.results
	if e.has("result"):
		return [e]
	return []


static func has_crit(e: Dictionary) -> bool:
	for r in _results(e):
		var res: Dictionary = (r as Dictionary).get("result", {})
		if bool(res.get("crit", false)) and bool(res.get("hit", true)):
			return true
	return false


static func has_ko(e: Dictionary) -> bool:
	if bool(e.get("ko", false)):
		return true
	for r in _results(e):
		if bool((r as Dictionary).get("ko", false)):
			return true
	return false


static func next_mode(mode: String) -> String:
	var i := MODES.find(mode)
	return MODES[(i + 1) % MODES.size()]

class_name BWReactionPick
extends RefCounted
## Which reaction a defender plays for one blow (design/art/ANIMATION.md,
## "Hit-reaction variety"). Deterministic: the same blow on the same unit
## always picks the same reaction; a small seeded jitter keeps a fight from
## feeling scripted.
##
##   var r := BWReactionPick.pick(unit, result, { "ko": false, "melee": true, "hp_after": 40, "salt": "alexandra" })
##   r.reaction   pose name for BWUnitView.pose_named ("stricken_rage", "block", ...)
##   r.tier       "miss" | "ko" | "resist" | "glance" | "small" | "mid" | "big"
##   r.why        short reason (feeds, tools)
##
## THE TABLE (base weights per tier; then the temperament multipliers; the
## pick is the highest weight x (0.75 .. 1.25 seeded jitter)):
##
##   miss                      dodge
##   ko                        kneel (the fall follows on the "ko" event)
##   resisted                  block
##   glance                    block 1.0 (melee) / 0.5 (ranged), shrug 0.8, flinch 0.8
##   small  (< 8% max HP)      flinch 1.0, shrug 1.0
##   mid    (8 .. 22%)         s = how far into the band (0 .. 1):
##                             fumble 1.0 (melee only), rage 0.45,
##                             flinch 0.15 + 0.8 (1 - s), shrug 0.2 + 0.7 (1 - s),
##                             stumble 0.2 + 0.5 s, knockback 0.1 + 0.6 s
##   big    (crit or > 22%)    knockback 1.0, stumble 0.85, kneel 0.5 (crit only), rage 0.35
##   low HP (after the blow < 35% max HP, not a KO): stumble x2.4, knockback x1.2,
##                             flinch x0.5, shrug x0.4, rage x0.8 (it's still in them)
##
## Temperament:
##   friendliness  unfriendly: rage x2.2, shrug x1.6, flinch x0.6
##                 friendly:   flinch x1.4, stumble x1.2, rage x0.25
##   vibe (BWAnimClips.vibe_of: element + friendliness, D153)
##                 stoic:  shrug x2.0, flinch x0.3 ("never flinches"), rage x0.6
##                 cocky:  shrug x1.5, rage x1.3
##                 bouncy: flinch x1.6, stumble x1.2
##                 fussy:  stumble x1.4, flinch x1.3 (dramatic)
##                 dreamy: stumble x1.3, flinch x1.1
##   build         small and fast (spd >= 5): flinch x1.35, knockback x1.3 (light: it flies)
##                 heavy (a two-handed sword or axe): knockback x0.7, shrug x1.3

const VARIANTS := ["stricken_flinch", "stricken_shrug", "stricken_stumble", "stricken_knockback", "stricken_rage"]
const LOW_HP := 0.35
const SMALL := 0.08
const BIG := 0.22
const JITTER := 0.25


static func pick(u: BWUnit, res: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := { "reaction": "", "tier": "", "why": "" }
	if not bool(res.get("hit", false)):
		out.reaction = "dodge"
		out.tier = "miss"
		return out
	if bool(ctx.get("ko", false)):
		out.reaction = "kneel"
		out.tier = "ko"
		return out
	if bool(res.get("resisted", false)):
		out.reaction = "block"
		out.tier = "resist"
		return out
	var melee := bool(ctx.get("melee", true))
	var max_hp := maxf(float(u.max_hp()) if u else 100.0, 1.0)
	var dmg := float(res.get("damage", 0))
	var pct := dmg / max_hp
	var hp_after := float(ctx.get("hp_after", u.hp if u else max_hp))
	var low := hp_after < LOW_HP * max_hp
	var crit := bool(res.get("crit", false))
	var w := {}
	if bool(res.get("glance", false)):
		out.tier = "glance"
		w = { "block": 1.0 if melee else 0.5, "stricken_shrug": 0.8, "stricken_flinch": 0.8 }
	elif crit or pct > BIG:
		out.tier = "big"
		w = { "stricken_knockback": 1.0, "stricken_stumble": 0.85, "stricken_rage": 0.35 }
		if crit:
			w["kneel"] = 0.5
	elif pct < SMALL:
		out.tier = "small"
		w = { "stricken_flinch": 1.0, "stricken_shrug": 1.0 }
	else:
		out.tier = "mid"
		var s := clampf((pct - SMALL) / (BIG - SMALL), 0.0, 1.0)
		w = { "stricken_flinch": 0.15 + 0.8 * (1.0 - s), "stricken_shrug": 0.2 + 0.7 * (1.0 - s), "stricken_rage": 0.45,
			"stricken_stumble": 0.2 + 0.5 * s, "stricken_knockback": 0.1 + 0.6 * s }
		if melee:
			w["fumble"] = 1.0
	if low and out.tier != "glance":
		_mul(w, { "stricken_stumble": 2.4, "stricken_knockback": 1.2, "stricken_shrug": 0.4, "stricken_rage": 0.8, "stricken_flinch": 0.5 })
		if not w.has("stricken_stumble"):
			w["stricken_stumble"] = 1.2
	var why: PackedStringArray = [out.tier + (" low" if low else "")]
	if u:
		match u.friendliness:
			"unfriendly":
				_mul(w, { "stricken_rage": 2.2, "stricken_shrug": 1.6, "stricken_flinch": 0.6 })
			"friendly":
				_mul(w, { "stricken_flinch": 1.4, "stricken_stumble": 1.2, "stricken_rage": 0.25 })
		why.append(u.friendliness)
		var vibe := BWAnimClips.vibe_of(u)
		why.append(vibe)
		match vibe:
			"stoic": _mul(w, { "stricken_shrug": 2.0, "stricken_flinch": 0.3, "stricken_rage": 0.6 })
			"cocky": _mul(w, { "stricken_shrug": 1.5, "stricken_rage": 1.3 })
			"bouncy": _mul(w, { "stricken_flinch": 1.6, "stricken_stumble": 1.2 })
			"fussy": _mul(w, { "stricken_stumble": 1.4, "stricken_flinch": 1.3 })
			"dreamy": _mul(w, { "stricken_stumble": 1.3, "stricken_flinch": 1.1 })
		if int(u.stats.get("spd", 0)) >= 5:
			_mul(w, { "stricken_flinch": 1.35, "stricken_knockback": 1.3 })
			why.append("quick")
		var meta := BWWeaponView.meta_for(u.weapon_model) if u.weapon_model != "" else {}
		if str(meta.get("hands", "")) == "two" and str(meta.get("class", "")) in ["sword", "axe"]:
			_mul(w, { "stricken_knockback": 0.7, "stricken_shrug": 1.3 })
			why.append("heavy")
	# the seeded jitter: per unit and per blow (damage, HP left, the salt:
	# the attacker and the strike index), never the global RNG
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash("%s|%d|%d|%s|%s" % [u.id if u else "", int(dmg), int(hp_after), str(ctx.get("salt", "")), out.tier]))
	var best := ""
	var best_w := -1.0
	var keys := w.keys()
	keys.sort()                          # fixed order: the jitter draws are stable
	for k in keys:
		var s := float(w[k]) * (1.0 - JITTER + 2.0 * JITTER * rng.randf())
		if s > best_w:
			best_w = s
			best = str(k)
	out.reaction = best
	out.why = " ".join(why)
	return out


static func _mul(w: Dictionary, m: Dictionary) -> void:
	for k in m:
		if w.has(k):
			w[k] = float(w[k]) * float(m[k])


## True for the stricken family (the audio lane matches grunts on these).
static func is_stricken(reaction: String) -> bool:
	return reaction.begins_with("stricken")

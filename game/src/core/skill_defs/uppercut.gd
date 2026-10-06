extends BWSkillDef
## Fists (D76). A heavy blow that knocks the target back UPPERCUT_PUSH hexes
## (+ Rebound: knockback skill=uppercut). If jagged ground, a too-steep rise
## or a unit stops the push, it slams for +slam_pct%; the map edge is open
## air and an immune target braced, so neither slams. The knockback is a
## secondary effect: it lands on an avoid, a resist stops it. Uppercut+:
## the slam is +PLUS_SLAM_PCT% and the slammed foe is Staggered.

const PLUS_SLAM_PCT := 75


func _init() -> void:
	define({
		"key": "uppercut", "name": "Uppercut", "weapon": "fists", "clip": "uppercut",
		"desc": "A heavy blow that knocks the target back a hex. If rock or a unit stops it, it slams for +50%",
		"plus": "Uppercut+: the slam is +75%, and the slammed foe is Staggered",
		"targeting": "adjacent_unit", "needs_element": false, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.UPPERCUT_DMG, "push": BWSkills.UPPERCUT_PUSH, "slam_pct": BWSkills.UPPERCUT_SLAM_PCT,
	}, 170)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [_target])
	if not p.victims.is_empty():
		p["knockback"] = push_plan(b, u, p.victims[0])


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	var kb: Dictionary = p.get("knockback", {})
	if not kb.is_empty() and kb.unit == v and str(kb.slam) != "":
		var what := { "rock": "rock", "edge": "the edge", "ledge": "a ledge", "unit": str(kb.get("into", "a unit")) }
		mods.append({ "stage": "dmg", "value": 1.0 + float(kb.slam_pct) / 100.0,
			"label": "Slammed into %s (+%d%%)" % [what.get(str(kb.slam), "rock"), int(kb.slam_pct)] })
		if kb.get("stagger", false):
			notes.append("Uppercut+: the slam Staggers it")


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	var kb: Dictionary = p.get("knockback", {})
	if kb.is_empty() or results.is_empty():
		return
	var kv: BWUnit = kb.unit
	var first: Dictionary = results[0].result
	if kv.alive() and first.secondary and not b.over:
		b._displace(kv, int(kb.dir), int(kb.hexes), "knockback")
		if str(kb.slam) != "":
			b._emit({ "type": "slam", "unit": kv.id, "by": u.id, "into": kb.slam, "with": str(kb.get("into", "")) })
			if kb.get("stagger", false) and kv.alive():
				b._add_status(kv, "staggered", u)


## The knockback plan, read before anything moves: straight away from the
## puncher. { unit, dir, hexes, path, slam: ""|rock|unit, into }.
func push_plan(b: BWBattle, u: BWUnit, v: BWUnit) -> Dictionary:
	var dir := BWHex.direction_index(u.pos, v.pos)    # any distance: the nearest heading (multi-hex foes)
	var n := int(data.get("push", 1)) + b._skill_rider(u, "knockback", "uppercut", "hexes")
	var pp := b.push_path(v, dir, n)
	var slam: String = pp.stop
	if slam == "edge" or b._immune(v, "displace"):
		slam = ""
	var out := { "unit": v, "dir": dir, "hexes": n, "path": pp.path, "slam": slam, "into": pp.into,
		"slam_pct": int(data.get("slam_pct", 0)), "stagger": false }
	if upgraded(u):
		out.slam_pct = PLUS_SLAM_PCT
		out.stagger = slam != ""
	return out

extends BWSkillDef
## Axe (D104). Hook a foe within RANGE and haul it in, straight toward you,
## until it stands next to you (or something stops it), onto whatever ground
## is there. The pull is a secondary effect: it lands on an avoid, a resist
## stops it; an immune foe braces.
## D437: a free action (spends nothing: like Riposte, use it before or after
## acting), cooldown 2. Hook, then move and act as normal. The AI opens its
## turn with it (`ai_opener`) when the pull brings a foe in.

const POWER := 9
const CD := 2
const RANGE := 3


func _init() -> void:
	define({
		"key": "hook", "name": "Hook", "weapon": "axe", "clip": "hook",
		"desc": "Hook an enemy up to 3 tiles away and haul it in next to you, onto whatever ground is there. Free: it spends no action, so you can still move and act",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER, "free_action": true,
	}, 312)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	if p.victims.is_empty():
		return
	var v: BWUnit = p.victims[0]
	var n := b.gap(u, v) - 1
	if n <= 0:
		return
	var dir := BWHex.direction_index(v.pos, u.pos)
	var pp := b.push_path(v, dir, n)
	p["pull"] = { "unit": v, "dir": dir, "hexes": n, "to": pp.path[-1] }
	if b._immune(v, "displace"):
		p.notes.append("%s can't be moved" % v.name)
	elif pp.path.size() > 1:
		p.notes.append("Pull: %s is hauled %d toward you" % [v.name, pp.path.size() - 1])


func after_hits(b: BWBattle, _u: BWUnit, p: Dictionary, results: Array) -> void:
	var pl: Dictionary = p.get("pull", {})
	if pl.is_empty() or results.is_empty() or b.over:
		return
	var v: BWUnit = pl.unit
	if v.alive() and results[0].result.secondary:
		b._displace(v, int(pl.dir), int(pl.hexes), "pull")


## D437: open the turn with a free Hook on the foe whose pull lands it next
## to you (the most expected damage first); nothing to pull, no hook.
func ai_opener(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var best := {}
	for el in row.get("elements", []):
		for h in b.skill_targets(u, id, str(el)):
			var pv := b.skill_preview(u, id, str(el), h)
			if pv.is_empty():
				continue
			var p := b._plan(u, data, str(el), h)
			var pl: Dictionary = p.get("pull", {})
			if pl.is_empty() or b._immune(pl.unit, "displace") or BWHex.distance(pl.to, u.pos) > 1:
				continue
			var score := ai_score(b, u, pv)
			if best.is_empty() or score > float(best.score):
				best = { "target": h, "element": el, "score": score }
	return best

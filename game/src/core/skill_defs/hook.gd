extends BWSkillDef
## Axe (D104). Hook a foe within RANGE and haul it in, straight toward you,
## until it stands next to you (or something stops it), onto whatever ground
## is there. The pull is a secondary effect: it lands on an avoid, a resist
## stops it; an immune foe braces.

const POWER := 9
const CD := 2
const RANGE := 3


func _init() -> void:
	define({
		"key": "hook", "name": "Hook", "weapon": "axe", "clip": "hook",
		"desc": "Hook an enemy up to 3 tiles away and haul it in next to you, onto whatever ground is there",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": POWER,
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

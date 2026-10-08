extends BWSkillDef
## RETIRED (D442: Sweep covers the shove): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Lance (D105; drafted as Skewer). Drive the spear into a foe within reach
## (2) and shove it back PUSH hex, straight away from you. If rock or a unit
## stops it, it slams: SLAM_PCT% max HP to it, and to a unit it hits (the
## Charge rule: the map edge is open air, an immune foe braces). The shove is
## a secondary effect: it lands on an avoid, a resist stops it. The shove and
## slam helpers below are shared by Sweep, Point Blank and Shockwave Palm.

const POWER := 12
const CD := 2
const REACH := 2
const PUSH := 1
const SLAM_PCT := 8


func _init() -> void:
	define({
		"key": "guardrush", "name": "Guardrush", "weapon": "lance", "clip": "",
		"desc": "Drive the spear into an enemy within reach and shove it back 1. If rock or a unit stops it, it slams for 8% HP (and so does what it hits)",
		"targeting": "unit", "needs_element": true, "range": REACH, "cd": CD,
		"power": POWER,
		"retired": true,
	}, 321)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	for v in p.victims:
		note(b, v, BWHex.direction_index(u.pos, v.pos), PUSH, SLAM_PCT, p.notes)


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	for v in landed(p, results):
		shove(b, u, v, BWHex.direction_index(u.pos, v.pos), PUSH, SLAM_PCT, id)


# ---------------------------------------------------------------- shared

## The victims whose secondary effect landed (avoids count, resists don't).
static func landed(p: Dictionary, results: Array) -> Array:
	var ok := {}
	for r in results:
		ok[str(r.target)] = bool(r.result.secondary)
	return (p.victims as Array).filter(func(v): return ok.get(v.id, false))


## What a shove of `n` along `dir` will do to `v`: { path, slam: "" | rock |
## unit, into (BWUnit or null) }. Pure.
static func shove_plan(b: BWBattle, v: BWUnit, dir: int, n: int) -> Dictionary:
	var pp := b.push_path(v, dir, n)
	var slam := str(pp.stop)
	var into: BWUnit = null
	if slam == "edge" or b._immune(v, "displace") or v.size > 1 or dir < 0:
		slam = ""
	elif slam == "unit":
		into = b.unit_at(BWHex.neighbors(pp.path[-1])[dir])
	return { "path": pp.path, "slam": slam, "into": into }


## The forecast line for one shove.
static func note(b: BWBattle, v: BWUnit, dir: int, n: int, slam_pct: int, notes: Array) -> void:
	if b._immune(v, "displace"):
		notes.append("%s braces: no shove" % v.name)
		return
	var sp := shove_plan(b, v, dir, n)
	var moved: int = (sp.path as Array).size() - 1
	var s := "Shove: %s back %d" % [v.name, moved]
	if str(sp.slam) != "" and slam_pct > 0:
		s += ", slams into %s for %d%% HP" % [sp.into.name if sp.into != null else "rock", slam_pct]
		if sp.into != null:
			s += " (and so does %s)" % sp.into.name
	notes.append(s)


## Shove `v` now (positions re-read), then slam if something stopped it.
static func shove(b: BWBattle, u: BWUnit, v: BWUnit, dir: int, n: int, slam_pct: int, skill: String) -> void:
	if not v.alive() or b.over or dir < 0:
		return
	var sp := shove_plan(b, v, dir, n)
	b._displace(v, dir, n, "push")
	if str(sp.slam) == "" or slam_pct <= 0 or not v.alive() or b.over:
		return
	var into: BWUnit = sp.into
	b._emit({ "type": "slam", "unit": v.id, "by": u.id, "into": sp.slam,
		"with": into.name if into != null else "", "skill": skill })
	b._tile_hurt(v, b._tile_dmg(v, slam_pct, ""), "slam", u.id)
	if into != null and into.alive():
		b._tile_hurt(into, b._tile_dmg(into, slam_pct, ""), "slam", u.id)

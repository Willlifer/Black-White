extends BWSkillDef
## Pistols. Once per battle: fan the hammer at everyone in reach. SHOTS
## shots at PCT% of POWER, spread over up to MAX_FOES foes within RANGE
## (nearest first; with fewer foes the spare shots go round again), each
## rolled on its own. A seated round lays its trail along every shot's line,
## then it is spent (and the Quick Shot with it).

const POWER := 12
const RANGE := 5
const SHOTS := 4
const MAX_FOES := 4
const PCT := 35
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "empty_the_chamber", "name": "Empty the Chamber", "weapon": "pistols", "clip": "chamber",
		"desc": "Once per battle: 4 shots at 35% spread over up to 4 enemies within 5, each rolled; a seated round lays its trail along every shot",
		"targeting": "self", "needs_element": false, "range": 0, "cd": 0, "once_per_battle": true,
		"power": POWER,
	}, 365)


## Someone has to be in reach.
func target_ok(b: BWBattle, u: BWUnit, _h: Vector2i, _element: String) -> bool:
	return not foes(b, u).is_empty()


## Foes in reach (range and sight), nearest first, then setup order.
func foes(b: BWBattle, u: BWUnit) -> Array:
	var out: Array = b.foes_of(u).filter(func(f): return b._reaches_unit(u, u.pos, f, RANGE))
	out.sort_custom(func(x, y): return b.gap(u, x) < b.gap(u, y))
	return out.slice(0, MAX_FOES)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	var fs := foes(b, u)
	if fs.is_empty():
		return
	for k in SHOTS:
		var f: BWUnit = fs[k % fs.size()]
		p.victims.append(f)
		p.shares[f.id] = [PCT / 100.0, "Empty the Chamber: %d%% a shot" % PCT]
	var per := {}
	for f in p.victims:
		per[f.name] = int(per.get(f.name, 0)) + 1
	var parts: Array = []
	for n in per:
		parts.append("%s x%d" % [n, per[n]])
	p.notes.append("%d shots: %s" % [SHOTS, ", ".join(parts)])
	if u.loaded != "":
		for f in fs:
			for h in b._on_board(BWHex.trail(u.pos, f.pos)):
				if not h in p.hexes:
					p.hexes.append(h)
		p.notes.append("The seated %s round trails every shot" % u.loaded)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	u.quick_shot_ready = false
	if u.loaded != "" and not p.hexes.is_empty():
		var el := u.loaded
		u.loaded = ""
		b.paint(p.hexes, el, u)
	return 0


## Every shot counts (the default sums one forecast per foe).
func ai_considers(_row: Dictionary) -> bool:
	return true


func ai_score(b: BWBattle, _u: BWUnit, pv: Dictionary) -> float:
	var score := 0.0
	for vid in pv.units:
		var ev: float = pv.forecasts[vid].expected.value
		score += ev + float(pv.forecasts[vid].get("arc_ev", 0.0))
	for vid in pv.forecasts:
		var shots: int = (pv.units as Array).count(vid)
		if pv.forecasts[vid].expected.value * shots >= b._unit(vid).hp:
			score += 1000.0
	return score


## Once per battle: it goes dark for the rest of the fight.
func cooldown(u: BWUnit) -> int:
	for el in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, el)] = ONCE_CD
	return ONCE_CD

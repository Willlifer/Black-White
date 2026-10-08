extends BWSkillDef
## Axe. Barrel up to CHARGE_LEN hexes (D414: 7), pushing one foe along ahead
## of you, then a basic follow-up. Running, so fire on the way burns (D44).
## D87: where the pushed foe can't go on it slams into what stopped it:
## CHARGE_SLAM_PCT% max HP to it, and to a unit it hits. Charge+ (D104):
## reach PLUS_LEN and the slam is PLUS_SLAM_PCT%. Downhill (D362): reach +1
## and the shove carries one hex further. The AI charges through
## ai_support (D414): the follow-up from where the run ends, plus the slam.
## D434 Momentum: every hex the run travels adds MOMENTUM_PCT% to the end
## swing (the basic follow-up), a named forecast line (7 hexes: +21%); the
## unit's fx `charge_momentum` holds the hexes until that swing or the turn's end.

const PLUS_LEN := 8
const PLUS_SLAM_PCT := 12
const MOMENTUM_PCT := 3
const FX := "charge_momentum"


func _init() -> void:
	define({
		"key": "charge", "name": "Charge", "weapon": "axe", "clip": "",
		"desc": "Barrel up to 7 tiles, pushing whoever is in the way along ahead of you, then swing. Where the foe can't be pushed on, it slams into what stopped it: 8% HP to it, and to a unit it hits",
		"plus": "Charge+: reach 8, and the slam is 12%",
		"targeting": "dir", "needs_element": true, "range": BWSkills.CHARGE_LEN, "cd": BWSkills.DEFAULT_CD,
		"power": 0, "follow_up": ["basic"],
	}, 60)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var high := BWWeaponMove.above(b, u, target)     # D362: charging down off high ground
	var reach := (PLUS_LEN if upgraded(u) else BWSkills.CHARGE_LEN) + (1 if high else 0)
	rush(b, u, target, p, reach, 2 if high else 1)
	p.hexes = p.walk.duplicate()
	if high:
		p.notes.append("High ground: charging downhill, reach %d and the shove 1 hex further" % reach)
	if upgraded(u):
		p.notes.append("Charge+: reach %d, slam %d%%" % [PLUS_LEN, PLUS_SLAM_PCT])
	var sh: Dictionary = p.shove
	if not sh.is_empty():
		p.notes.append("Shove: %s pushed %d hex%s" % [sh.unit.name, BWHex.distance(sh.from, sh.to),
			"" if BWHex.distance(sh.from, sh.to) == 1 else "es"])
	if not (p.walk as Array).is_empty():
		p.notes.append("Momentum: %d hexes run, the swing after +%d%%" % [(p.walk as Array).size(), momentum_pct((p.walk as Array).size())])
	var sl: Dictionary = p.get("slam", {})
	if not sl.is_empty():
		var into: BWUnit = sl.get("into", null)
		p.notes.append("Slam: %s can't be pushed on and takes %d%% HP%s" % [sl.unit.name, slam_pct(u),
			(", and so does %s" % into.name) if into != null else ""])


static func momentum_pct(hexes: int) -> int:
	return MOMENTUM_PCT * maxi(hexes, 0)


## D434: the run's hexes ride into the follow-up swing (BWBattle's forecast
## reads fx `charge_momentum`; the swing, or the turn's end, spends it).
func on_follow_up(_b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	var n := (p.walk as Array).size()
	if n > 0:
		u.fx[FX] = n
	else:
		u.fx.erase(FX)


func slam_pct(u: BWUnit) -> int:
	return PLUS_SLAM_PCT if upgraded(u) else BWSkills.CHARGE_SLAM_PCT


func relocate(b: BWBattle, u: BWUnit, p: Dictionary, _target_hex: Vector2i) -> void:
	var path: Array = [u.pos] + (p.walk as Array)
	b.skill_relocate(u, p, path, "charge")
	for h in p.walk:                    # running, so the ground burns; leaps fly over
		var pct := b.tiles.crossing_pct(h)
		if pct > 0 and u.alive():
			b._tile_hurt(u, b._tile_dmg(u, pct, "fire"), "fire_cross", str(b.tiles.at(h).get("source", "")))
	b._lay_on_move(u, path)
	var sl: Dictionary = p.get("slam", {})
	if not sl.is_empty() and u.alive() and not b.over:
		var cv: BWUnit = sl.unit
		var into: BWUnit = sl.get("into", null)
		b._emit({ "type": "slam", "unit": cv.id, "by": u.id, "into": sl.kind,
			"with": into.name if into != null else "", "skill": "charge" })
		b._tile_hurt(cv, b._tile_dmg(cv, slam_pct(u), ""), "slam", u.id)
		if into != null and into.alive():
			b._tile_hurt(into, b._tile_dmg(into, slam_pct(u), ""), "slam", u.id)


## D414: the AI charges. Per heading: the best basic follow-up from where the
## run ends (the pushed foe where it lands), plus the slam's HP, minus fire
## crossed. BWAI adds the follow-up from where the unit stands now itself, so
## that is taken off here: the total is the charge's own worth.
func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var best := {}
	var here := BWAI._best_target(b, u, u.pos)
	var base := float(here.get("score", 0.0))
	for el in row.get("elements", []):
		for h in b.skill_targets(u, id, str(el)):
			var p := b._plan(u, data, str(el), h)
			if p.dest == u.pos:
				continue
			var score := _ai_value(b, u, p)
			if score > base + 0.5 and (best.is_empty() or score - base > float(best.score)):
				best = { "target": h, "element": el, "score": score - base }
	return best


func _ai_value(b: BWBattle, u: BWUnit, p: Dictionary) -> float:
	var start := u.pos
	var sh: Dictionary = p.shove
	var moved: BWUnit = sh.get("unit", null)
	var was := moved.pos if moved != null else Vector2i.ZERO
	u.pos = p.dest
	if moved != null:
		moved.pos = sh.to
	var had: Variant = u.fx.get(FX, null)
	u.fx[FX] = (p.walk as Array).size()          # D434: the swing carries the run
	var t := BWAI._best_target(b, u, u.pos)
	if had == null:
		u.fx.erase(FX)
	else:
		u.fx[FX] = had
	u.pos = start
	if moved != null:
		moved.pos = was
	var score := float(t.get("score", 0.0))
	var sl: Dictionary = p.get("slam", {})
	if not sl.is_empty():
		score += BWTiles.tile_damage(sl.unit, slam_pct(u), "")
		var into: BWUnit = sl.get("into", null)
		if into != null:
			score += BWTiles.tile_damage(into, slam_pct(u), "") * (1.0 if into.team != u.team else -1.0)
	for h in p.walk:
		var pct := b.tiles.crossing_pct(h)
		if pct > 0:
			score -= u.max_hp() * pct / 100.0
	return score


## V8 _rush_destination (BWBattle._rush, with the reach as a parameter): walk
## the heading as far as the ground allows, stopping at an ally or a second
## enemy. D414: a caught enemy is PUSHED ALONG ahead of the run, a hex per
## step; where it can't go on (rock, a unit, a pillar) the run stops behind it
## and it slams (D87) on the stop. The map edge just stops it (open air); an
## immune foe braces (the run stops short, no slam). A multi-hex enemy stops
## the charge at its edge and is shoved one hex (unchanged).
## D362 `shove` > 1 (high ground): the shoved foe goes on past the last
## landing while the ground allows, up to `shove` - 1 more hexes.
static func rush(b: BWBattle, u: BWUnit, toward: Vector2i, p: Dictionary, dist: int, shove: int = 1) -> void:
	var prev := u.pos
	var walk: Array = []
	var caught: BWUnit = null
	var fpath: Array = []                 # the caught foe's hexes, as pushed
	var dir := BWHex.direction_index(u.pos, toward)
	for h in b.board.ray(u.pos, toward, dist):
		if b.board.step_cost(prev, h) < 0:
			break
		if caught == null:
			var o := b.unit_at(h)
			if o != null and o != u:
				if o.team == u.team:
					break
				if o.size > 1:
					walk.append(h)
					_shove_big(b, u, toward, p, walk, o)
					return
				caught = o
				fpath = [h]
			else:
				walk.append(h)
				prev = h
				continue
		# the foe stands on h (pushed there): it goes on one hex, or the run stops
		var at: Vector2i = fpath[-1]
		var nxt: Vector2i = BWHex.neighbors(at)[dir]
		var why := _blocked(b, u, caught, at, nxt)
		if why != "":
			if why in ["rock", "unit"]:
				var into := b.unit_at(nxt) if why == "unit" else null
				p["slam"] = { "unit": caught, "kind": why, "into": into }
			break
		walk.append(h)
		prev = h
		fpath.append(nxt)
	if caught != null and fpath.size() > 1:
		for _i in shove - 1:                         # D362: on down the line
			var at: Vector2i = fpath[-1]
			var nxt: Vector2i = BWHex.neighbors(at)[dir]
			if _blocked(b, u, caught, at, nxt) != "":
				break
			fpath.append(nxt)
		p.shove = { "unit": caught, "from": caught.pos, "to": fpath[-1], "path": fpath }
	p.walk = walk
	p.dest = walk[-1] if not walk.is_empty() else u.pos


## D414: why a pushed foe can't go from `at` to `nxt` ("" = it can):
## "edge" (off the map), "immune" (it braces), "unit", "rock" (jagged, a
## pillar, a rise too steep).
static func _blocked(b: BWBattle, u: BWUnit, v: BWUnit, at: Vector2i, nxt: Vector2i) -> String:
	if b._immune(v, "displace"):
		return "immune"
	if not b.board.exists(nxt):
		return "edge"
	var o := b.unit_at(nxt)
	if o != null and o != v and o != u:
		return "unit"
	if b.board.step_cost(at, nxt) < 0 or not b.can_stand(v, nxt):
		return "rock"
	return ""


## A multi-hex enemy (the boss): the walk ends at its edge and it is shoved
## one hex along the heading if its whole footprint fits (else the charge
## stops short of it, no slam).
static func _shove_big(b: BWBattle, u: BWUnit, toward: Vector2i, p: Dictionary, walk: Array, caught: BWUnit) -> void:
	var dest: Vector2i = walk[-1]
	var landing: Vector2i = BWHex.neighbors(caught.pos)[BWHex.direction_index(u.pos, toward)]
	var ok := not b._immune(caught, "displace") and b.board.step_cost(caught.pos, landing) >= 0 		and b.can_stand(caught, landing) and not dest in caught.footprint(landing)
	if ok:
		p.shove = { "unit": caught, "from": caught.pos, "to": landing }
	else:
		walk = walk.slice(0, walk.size() - 1)
	p.walk = walk
	p.dest = walk[-1] if not walk.is_empty() else u.pos

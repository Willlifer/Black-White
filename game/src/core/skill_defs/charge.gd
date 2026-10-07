extends BWSkillDef
## Axe. Barrel up to CHARGE_LEN hexes, shoving one foe ahead, then a basic
## follow-up. Running, so fire on the way burns (D44). D87: a foe that can't
## be shoved slams into what stopped it: CHARGE_SLAM_PCT% max HP to it, and
## to a unit it hits. Charge+ (D104): reach PLUS_LEN and the slam is
## PLUS_SLAM_PCT%. The walk is BWBattle._rush's rule with the reach as a
## parameter (rush() below).

const PLUS_LEN := 4
const PLUS_SLAM_PCT := 12


func _init() -> void:
	define({
		"key": "charge", "name": "Charge", "weapon": "axe", "clip": "",
		"desc": "Barrel up to 3 tiles, shoving whoever is in the way ahead of you, then swing. A foe that can't be shoved slams into what's behind it: 8% HP to it, and to a unit it hits",
		"plus": "Charge+: reach 4, and the slam is 12%",
		"targeting": "dir", "needs_element": true, "range": BWSkills.CHARGE_LEN, "cd": BWSkills.DEFAULT_CD,
		"power": 0, "follow_up": ["basic"],
	}, 60)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var high := BWWeaponMove.above(b, u, target)     # D362: charging down off high ground
	var reach := (PLUS_LEN if upgraded(u) else BWSkills.CHARGE_LEN) + (1 if high else 0)
	rush(b, u, target, p, reach, 2 if high else 1)
	p.hexes = p.walk.duplicate()
	if high:
		p.notes.append("High ground: charging downhill, reach %d and the shove 2 hexes" % reach)
	if upgraded(u):
		p.notes.append("Charge+: reach %d, slam %d%%" % [PLUS_LEN, PLUS_SLAM_PCT])
	var sl: Dictionary = p.get("slam", {})
	if not sl.is_empty():
		var into: BWUnit = sl.get("into", null)
		p.notes.append("Slam: %s can't be shoved and takes %d%% HP%s" % [sl.unit.name, slam_pct(u),
			(", and so does %s" % into.name) if into != null else ""])


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


## V8 _rush_destination (BWBattle._rush, with the reach as a parameter): walk
## the heading as far as the ground allows, stopping at an ally or a second
## enemy, and shove one enemy to the hex beyond where it ends; if that hex is
## blocked the charge stops short of it (and it slams, D87). A multi-hex
## enemy stops the charge at its edge; immune displace stops it short.
## D362 `shove` > 1 (high ground): the shoved foe goes on past the first
## landing while the ground allows, up to `shove` hexes.
static func rush(b: BWBattle, u: BWUnit, toward: Vector2i, p: Dictionary, dist: int, shove: int = 1) -> void:
	var prev := u.pos
	var walk: Array = []
	var caught: BWUnit = null
	var caught_at := -1
	for h in b.board.ray(u.pos, toward, dist):
		if b.board.step_cost(prev, h) < 0:
			break
		var o := b.unit_at(h)
		if o != null and o != u:
			if o == caught or o.team == u.team or caught != null:
				break
			caught = o
			caught_at = walk.size()
		walk.append(h)
		prev = h
	if caught != null:
		var dest: Vector2i = walk[-1]
		var landing := BWHex.step_beyond(u.pos, dest)
		var from := dest
		if caught.size > 1:
			landing = BWHex.neighbors(caught.pos)[BWHex.direction_index(u.pos, toward)]
			from = caught.pos
		var ok := not b._immune(caught, "displace") and b.board.step_cost(from, landing) >= 0 \
			and b.can_stand(caught, landing) and not dest in caught.footprint(landing)
		if ok:
			var dir := BWHex.direction_index(u.pos, toward)
			for _i in shove - 1:                         # D362: on down the line
				var nxt: Vector2i = BWHex.neighbors(landing)[dir]
				if caught.size > 1 or not b.board.exists(nxt) or b.board.step_cost(landing, nxt) < 0 or not b.can_stand(caught, nxt):
					break
				landing = nxt
			p.shove = { "unit": caught, "from": caught.pos, "to": landing }
		else:
			walk = walk.slice(0, caught_at)
			if caught.size <= 1 and not b._immune(caught, "displace") and b.board.exists(landing):
				var o := b.unit_at(landing)
				if o != null and o != caught and o != u:
					p["slam"] = { "unit": caught, "kind": "unit", "into": o }
				elif o == null:
					p["slam"] = { "unit": caught, "kind": "rock", "into": null }
	p.walk = walk
	p.dest = walk[-1] if not walk.is_empty() else u.pos

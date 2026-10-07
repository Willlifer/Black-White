class_name BWKsWater
extends RefCounted
## D295 water's keystones (design/ELEMENTS-v3.md §4 "Keystones", ELEMENTS.md
## §16.3). Pure rules; BWKeystoneFx and the tidal_release def call them.
##
## Tidal Release  an action (skill def tidal_release), cooldown 4. Pick a pool
##                hex within 3, then a heading (the second pick). The pool
##                DRAINS (every hex of it loses its water; an electrified
##                field on it is gone). A wave runs along the line from that
##                hex, its length the pool's size (max WAVE_MAX), stopping at
##                the map edge or rock. Every unit on the line is pushed
##                WAVE_PUSH along it, front first (a block slams 8% to both;
##                onto glaze it slides). Then the line gets water WAVE_WATER.
## Riptide        at the start of your turn, every foe standing in water
##                (unglazed) within RIPTIDE_RADIUS is pulled 1 toward you,
##                closest first: a field move under BWWind's caps.
## Wellspring     at the tick, you and your allies standing in YOUR water
##                heal WELL_PCT per level (4/8/12%). Not on top of light: a
##                hex whose light heal at the turn start is as big or bigger
##                gives nothing here, a smaller one leaves the difference (the
##                higher counts). Several holders: the best one counts.

const TIDAL := "tidal_release"
const RIPTIDE := "riptide"
const WELLSPRING := "wellspring"
const TIDAL_RANGE := 3
const WAVE_MAX := 6
const WAVE_PUSH := 3
const WAVE_WATER := 2
const WAVE_SLAM_PCT := 8.0
const RIPTIDE_RADIUS := 4
const WELL_PCT := 4.0


static func has(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


# ---------------------------------------------------------------- Tidal Release

## Legal first clicks: pool water within TIDAL_RANGE.
static func tidal_ok(b: BWBattle, h: Vector2i) -> bool:
	return BWPools.is_water(b.tiles, h) and not BWPools.pool(b.tiles, h).is_empty()


## The wave's line from `start` heading `dir`: up to the pool's size (max
## WAVE_MAX) hexes, start included, stopping at the edge or rock.
static func wave_line(b: BWBattle, start: Vector2i, dir: int) -> Array:
	var out: Array = []
	if dir < 0 or dir > 5:
		return out
	var n := mini(BWPools.pool(b.tiles, start).size(), WAVE_MAX)
	var cur := start
	for i in n:
		if i > 0:
			cur = BWHex.neighbors(cur)[dir]
		if not b.tiles.can_hold(cur):
			break
		out.append(cur)
	return out


## Resolve the release: drain, the wave, the water. Returns the line.
static func release(b: BWBattle, u: BWUnit, start: Vector2i, dir: int) -> Array:
	var pool := BWPools.pool(b.tiles, start)
	var line := wave_line(b, start, dir)
	if line.is_empty():
		return []
	for h in pool:
		_drain(b.tiles, h)
	b.tiles.pool_cache.clear()
	b._emit({ "type": "tidal", "unit": u.id, "hex": start, "dir": dir, "line": line.duplicate(), "pool": pool.duplicate() })
	# every unit on the line, front first, pushed along it
	var on: Array = []
	for v in b.units:
		if not v.alive() or BWObelisk.is_objective(v):
			continue
		for f in v.footprint():
			if f in line:
				on.append([line.find(f), v])
				break
	on.sort_custom(func(a, c) -> bool: return a[0] > c[0])
	for r in on:
		if b.over:
			break
		wave_push(b, r[1], dir, WAVE_PUSH, u)
	if not b.over:
		b.paint(line, "water", u, WAVE_WATER, false)
	return line


static func _drain(t: BWTiles, h: Vector2i) -> void:
	var e := t.at(h)
	if e.is_empty() or int(e.h) >= 0:
		return
	BWPools._unshock(t, h)
	if int(e.v) == 0 and str(e.get("marker", "")) == "":
		t.entries.erase(h)
	else:
		e.h = 0
		e.permanent = false
		e.erase("seeded")


## The wave's push: WAVE_PUSH along `dir`; blocked, it slams (8% both);
## onto glaze it slides on (BWSlides.after_push).
static func wave_push(b: BWBattle, v: BWUnit, dir: int, n: int, by: BWUnit) -> void:
	if not v.alive() or b.over:
		return
	if b._immune(v, "displace"):
		b._emit({ "type": "displace_resisted", "unit": v.id, "kind": "push" })
		return
	if b._negate(v, "displacement"):
		return
	n = BWCurse.gravity_step(b, v, dir, n)
	var pp := b.push_path(v, dir, n)
	var path: Array = pp.path
	var slid := false
	if path.size() >= 2:
		v.pos = path[-1]
		b._emit({ "type": "move", "unit": v.id, "path": path, "kind": "push", "wave": true })
		var sp := BWSlides.after_push(b, v, dir, by.id if by != null else "")
		slid = (sp.get("path", []) as Array).size() > 1
	if not slid and str(pp.stop) in ["rock", "unit"] and v.alive() and not b.over:
		var nxt: Vector2i = BWHex.neighbors(v.pos)[dir]
		var o := b.unit_at(nxt)
		var src := by.id if by != null else ""
		b._emit({ "type": "slam", "unit": v.id, "by": src, "into": "unit" if o != null else "rock",
			"name": "Wave", "target": o.id if o != null else "", "hex": v.pos })
		b._tile_hurt(v, b._tile_dmg(v, WAVE_SLAM_PCT, ""), "slam", src)
		if o != null and o != v and o.alive() and not b.over:
			b._tile_hurt(o, b._tile_dmg(o, WAVE_SLAM_PCT, ""), "slam", src)


## The AI: the release that pushes the most foes (2+), heading toward the
## nearest slam or away from its own side. {target, element, choice, score}.
static func ai_tidal(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var best := {}
	for h in b.skill_targets(u, str(row.key), ""):
		for d in 6:
			var line := wave_line(b, h, d)
			if line.size() < 2:
				continue
			var foes := 0
			var friends := 0
			var sc := 0.0
			for v in b.units:
				if not v.alive() or BWObelisk.is_objective(v) or not v.pos in line:
					continue
				var pp := b.push_path(v, d, WAVE_PUSH)
				var slam := str(pp.stop) in ["rock", "unit"]
				if v.team == u.team:
					friends += 1
					sc -= 6.0 + (8.0 if slam else 0.0)
				else:
					foes += 1
					sc += 6.0 + (v.max_hp() * WAVE_SLAM_PCT / 100.0 if slam else 0.0)
					sc += 4.0 * BWPools.hazard_pct(b, v, (pp.path as Array)[-1]) / 10.0
			if foes < 2 or friends > 0:
				continue
			if best.is_empty() or sc > float(best.score):
				best = { "target": h, "element": "", "score": sc, "choice": BWHex.neighbors(h)[d] }
	return best


# ---------------------------------------------------------------- Riptide

static func in_water(b: BWBattle, h: Vector2i) -> bool:
	return b.tiles.intensity(h, "water") > 0 and not b.tiles.is_glazed(h)


## At `u`'s turn start: foes in water within RIPTIDE_RADIUS are pulled 1
## toward it (closest first, a field move).
static func riptide(b: BWBattle, u: BWUnit) -> void:
	if not has(u, RIPTIDE) or not u.alive() or b.over:
		return
	var rows: Array = []
	for f in b.foes_of(u):
		if BWObelisk.is_objective(f) or maxi(f.size, 1) > 1 or not in_water(b, f.pos):
			continue
		var d := BWHex.distance(u.pos, f.pos)
		if d >= 2 and d <= RIPTIDE_RADIUS:
			rows.append([d, b.units.find(f), f])
	rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
	var moved: Array = []
	for r in rows:
		if b.over:
			break
		var f: BWUnit = r[2]
		var res := BWWind.push(b, f, BWBattle.pulse_heading(u.pos, f.pos, false), 1, "pull", u, true, false)
		if res.moved:
			moved.append(f.id)
	if not moved.is_empty():
		b._emit({ "type": "riptide", "unit": u.id, "units": moved })


# ---------------------------------------------------------------- Wellspring

## The heal `a` gets at the tick from Wellspring holders on its side (% max
## HP, after the light rule), and the holder.
static func well_pct(b: BWBattle, a: BWUnit) -> Array:
	var lvl := b.tiles.intensity(a.pos, "water")
	if lvl <= 0 or b.tiles.is_glazed(a.pos):
		return [0.0, null]
	var src := b._unit(str(b.tiles.at(a.pos).get("source", "")))
	if src == null or src.team != a.team or not has(src, WELLSPRING) or not src.alive():
		return [0.0, null]
	var pct := WELL_PCT * lvl
	var light := float(b.tiles.standing(a.pos).heal)
	return [maxf(0.0, pct - light), src]


static func tick(b: BWBattle) -> void:
	for a in b.units:
		if b.over:
			return
		if not a.alive() or BWObelisk.is_objective(a) or a.hp >= a.max_hp():
			continue
		var w := well_pct(b, a)
		if float(w[0]) > 0.0:
			b._emit({ "type": "wellspring", "unit": a.id, "hex": a.pos, "by": (w[1] as BWUnit).id, "pct": w[0] })
			b._heal(a, float(w[0]), "wellspring")


## The AI: a Riptide holder likes standing where foes in water are within 4.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if not has(u, RIPTIDE):
		return 0.0
	var n := 0.0
	for f in b.foes_of(u):
		var d := BWHex.distance(h, f.pos)
		if d >= 2 and d <= RIPTIDE_RADIUS and in_water(b, f.pos):
			n += 1.0
	return 2.0 * n


## The tile card's lines.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u != null:
		var w := well_pct(b, u)
		if float(w[0]) > 0.0:
			out.append("Wellspring (%s): %s heals %d%% at the tick" % [(w[1] as BWUnit).name, u.name, int(w[0])])
	return out

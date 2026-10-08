class_name BWPools
extends RefCounted
## D262-D265 water as a network, and ice pillars (design/ELEMENTS-v3.md §2,
## §4 with the author's 2026-10-07 rulings). Pure rules on BWTiles (begin /
## finish wrap BWTiles.apply, tick runs inside BWTiles.tick); the battle
## parts (turn_shock, on_walk, hazard_pct, report) take the battle.
##
## A POOL is the connected unglazed water (h < 0, glaze 0) reached by BFS from
## a hex, nearest first (hex distance, ties by hex order), capped at POOL_MAX.
## Only fresh fire, ice and thunder cast on a pool hex react; light, dark,
## water and wind never travel through a pool, nor does any propagated arrival.
##
##   fire     nothing pool-wide (D421: steam is gone). The cast hex DOUSES
##            (fire meeting water clears both, BWTiles._route); fire on an
##            electrified hex still clears the field there.
##   ice      GLAZE within radius 1 (2 with the Water set, D422) of each cast water hex: those pool hexes
##            glaze (Unsteady ground, BWUnsteady), and every empty water 3 among them
##            (and any fresh glaze on empty water 3 anywhere) becomes a PILLAR.
##   thunder  ELECTRIFIED within radius 1 (Water set 2) of each cast water hex (always: no
##            detonation, even on a 1-hex puddle; glazed water still shatters).
##            SHOCK_PCT at an occupant's turn start (both teams, thunder class)
##            and Staggered; SHOCK_ENTRY_PCT on entering a field hex, once per
##            walk; occupants are conductive. Each unit's resistance ramps:
##            full, then 25%, then immune for the rest of that field. It lasts
##            ELEC_TICKS ticks (decay frozen), then DISCHARGES (each hex steps
##            down 1 water; a static scars for a tick). Thunder on a live field
##            does nothing (never refreshed, one field per pool); fire on a hex
##            clears it there. Water landing on a fuse electrifies too.
## PILLAR: impassable, blocks sight, stops pushes (they slam). It
## lasts PILLAR_TICKS ticks (decay frozen), then thaws to water 3. Fire melts
## it, thunder shatters it (the glazed water 3 blast: 34% centre, 17% ring).
## At most PILLAR_MAX per caster: a fifth melts the caster's oldest.

const POOL_MAX := 19
const ELEC_TICKS := 2
const SHOCK_PCT := 15.0
const SHOCK_ENTRY_PCT := 5.0
const SHOCK_RAMP := [1.0, 0.25]          # per unit per field: full, 25%, then immune
const PILLAR_TICKS := 3
const PILLAR_MAX := 4
const REACT := ["fire", "ice", "thunder", "water"]


# ------------------------------------------------------------------ pools

## Unglazed water, not a pillar: a hex a pool is made of.
static func is_water(t: BWTiles, hex: Vector2i) -> bool:
	var e := t.at(hex)
	return not e.is_empty() and int(e.h) < 0 and int(e.glaze) == 0 and str(e.get("marker", "")) == ""


## The pool through `hex` (BFS, nearest first, ties by hex order, capped at
## POOL_MAX). [] when `hex` isn't water. `cached`: inside one action (begin)
## the pools are cached; the cache is dropped at every apply and tick.
static func pool(t: BWTiles, hex: Vector2i, cached: bool = false, cap: int = POOL_MAX) -> Array:
	if cached and t.pool_cache.has(hex):
		return t.pool_cache[hex]
	var out: Array = []
	if is_water(t, hex):
		var seen := { hex: true }
		var frontier: Array = [hex]
		while not frontier.is_empty() and out.size() < cap:
			var bi := 0
			for i in range(1, frontier.size()):
				var a: Vector2i = frontier[i]
				var c: Vector2i = frontier[bi]
				var da := BWHex.distance(hex, a)
				var dc := BWHex.distance(hex, c)
				if da < dc or (da == dc and a < c):
					bi = i
			var h: Vector2i = frontier.pop_at(bi)
			out.append(h)
			for n in t.board.neighbors(h):
				if not seen.has(n) and is_water(t, n):
					seen[n] = true
					frontier.append(n)
	t.pool_cache[hex] = out
	return out


static func _live(t: BWTiles, hexes: Array) -> bool:
	for h in hexes:
		if t.shock.has(h):
			return true
	return false


# ------------------------------------------------------------------ BWTiles.apply hooks

## Before routing (the pre-action board): which pool reactions this cast makes,
## and plan overrides (thunder on water: no detonation; water on a fuse: no
## detonation, it electrifies after).
static func begin(t: BWTiles, hexes: Array, element: String, fresh: bool, steps: int, caster: String, opts: Dictionary) -> Dictionary:
	var sp := { "plans": {}, "glaze": {}, "shock": {}, "fuse_water": [], "fire_on": [] }
	t.pool_cache.clear()
	t.set_meta("pillar_plus", int(opts.get("pillar_plus", 0)))   # D282: the Ice set (raise_pillar)
	t.set_meta("pillar_cap", int(opts.get("pillar_cap", PILLAR_MAX)))   # D459 Sculptor: 6
	if not fresh or not element in REACT:
		return sp
	var cap := POOL_MAX
	var reach := int(opts.get("pool_reach", 1))   # D422: the Water set (2) reacts within 2
	var guard: Array = opts.get("fuse_guard", [])
	for hex in hexes:
		if not t.can_hold(hex) or t.fuse_guarded(hex, guard):
			continue
		match element:
			"water":
				var e := t.at(hex)
				if str(e.get("marker", "")) == "fuse":
					var p := t._route({}, "water", true, steps, caster, opts)
					p["fired"] = true
					sp.plans[hex] = p
					sp.fuse_water.append([hex, str(e.get("source", caster))])
			"fire":
				if t.shock.has(hex):
					sp.fire_on.append(hex)
			"ice":
				var pl := pool(t, hex, true, cap)
				var whole := bool(opts.get("flash_flood", false)) and str(t.at(hex).get("source", "")) == caster
				for h in (pl if whole else t.board.area(hex, reach)):   # D458 Flash Flood: your pool glazes at once
					if h in pl:
						sp.glaze[h] = true
			"thunder":
				if not is_water(t, hex):
					continue
				sp.plans[hex] = { "op": "none" }
				var pl := pool(t, hex, true, cap)
				if _live(t, pl):
					continue                          # a live field is never refreshed
				var key: Vector2i = pl[0]
				for ph in pl:
					if ph < key:
						key = ph
				if not sp.shock.has(key):
					sp.shock[key] = {}
				for h in t.board.area(hex, reach):
					if h in pl:
						sp.shock[key][h] = true
	return sp


## After the plans are applied: pool glaze, pillars, fields; a melted
## or shattered pillar is dropped. Adds out.pools = {glaze, shock,
## pillars, melted} when anything happened.
static func finish(t: BWTiles, sp: Dictionary, element: String, caster: String, fresh: bool, out: Dictionary, glaze_plus: int = 0) -> void:
	var rep := { "glaze": [], "shock": [], "pillars": [], "melted": [] }
	for h in sp.fire_on:
		_unshock(t, h)
	var glaze_keys: Array = sp.glaze.keys()
	glaze_keys.sort()
	for h in glaze_keys:
		var e := t.at(h)
		if e.is_empty() or int(e.h) >= 0:
			continue
		if int(e.glaze) <= 0:
			e.glaze = BWTiles.GLAZE_CYCLES + glaze_plus
			e["glaze_source"] = caster
		_unseed(t, h)
		rep.glaze.append(h)
		if not h in out.changed:
			out.changed.append(h)
	if fresh and element == "ice":
		for h in out.changed:
			if h in sp.get("no_pillar", []):
				continue                              # D312: an Overfreeze centre just shattered: no pillar
			if raise_pillar(t, h, caster, rep.melted):
				rep.pillars.append(h)
	var groups: Array = sp.shock.values()
	t.pool_cache.clear()
	for fw in sp.fuse_water:                       # water landed on a fuse: it electrifies
		var pl := pool(t, fw[0])
		if pl.is_empty() or _live(t, pl):
			continue
		var g := { "_src": fw[1] }
		for h in t.board.area(fw[0], 1):
			if h in pl:
				g[h] = true
		groups.append(g)
	for g in groups:
		var src := str(g.get("_src", caster))
		var hs: Array = (g as Dictionary).keys().filter(func(k): return k is Vector2i)
		hs.sort()
		if hs.is_empty():
			continue
		t.spine_serial += 1
		var id := t.spine_serial
		t.fields[id] = { "hexes": hs, "ticks": ELEC_TICKS, "source": src, "ramp": {} }
		for h in hs:
			t.shock[h] = id
			_unseed(t, h)
			rep.shock.append(h)
	prune(t, rep.melted)
	t.pool_cache.clear()
	for k in rep.keys():
		if not (rep[k] as Array).is_empty():
			out["pools"] = rep
			break


## A fresh glaze on EMPTY water 3 makes a pillar (owner `caster`). The fifth
## of one caster's melts its oldest. Returns true when one rose.
static func raise_pillar(t: BWTiles, h: Vector2i, caster: String, melted: Array = []) -> bool:
	var e := t.at(h)
	if e.is_empty() or int(e.h) != -3 or int(e.glaze) <= 0 or t.pillars.has(h):
		return false
	if t.occupant.is_valid() and t.occupant.call(h) != null:
		return false
	var mine: Array = []
	for p in t.pillars:
		if str(t.pillars[p].owner) == caster:
			mine.append(p)
	if mine.size() >= int(t.get_meta("pillar_cap", PILLAR_MAX)):
		mine.sort_custom(func(a, b): return int(t.pillars[a].born) < int(t.pillars[b].born))
		melt(t, mine[0])
		melted.append(mine[0])
	t.spine_serial += 1
	t.pillars[h] = { "owner": caster, "ticks": PILLAR_TICKS + int(t.get_meta("pillar_plus", 0)), "born": t.spine_serial }
	e.glaze = maxi(int(e.glaze), 1)
	e.permanent = false
	e.erase("seeded")
	return true


## A pillar thaws or melts: water 3, unglazed, decaying again.
static func melt(t: BWTiles, h: Vector2i) -> void:
	t.pillars.erase(h)
	var e := t.at(h)
	if not e.is_empty():
		e.glaze = 0
		e.timer = BWTiles.STEP_CYCLES


## Drop pillars whose ice is gone (fire melted it, thunder shattered it,
## Siphon stripped it).
static func prune(t: BWTiles, gone: Array = []) -> void:
	for h in t.pillars.keys():
		if not t.is_glazed(h) or int(t.at(h).get("h", 0)) >= 0:
			t.pillars.erase(h)
			if not h in gone:
				gone.append(h)


static func _unseed(t: BWTiles, h: Vector2i) -> void:
	var e := t.at(h)
	if not e.is_empty() and bool(e.get("seeded", false)):
		e.permanent = false
		e.erase("seeded")                         # D134: a seed that reacts is ordinary water now


static func _unshock(t: BWTiles, h: Vector2i) -> void:
	var id: int = t.shock.get(h, -1)
	t.shock.erase(h)
	if t.fields.has(id):
		var f: Dictionary = t.fields[id]
		f.hexes = (f.hexes as Array).filter(func(x): return x != h)
		if (f.hexes as Array).is_empty():
			t.fields.erase(id)


# ------------------------------------------------------------------ the tick (inside BWTiles.tick)

## Decay step of the tick: fields and pillars count down. A field at 0
## discharges, a pillar at 0 thaws. t.spine_tick reports what changed.
static func tick(t: BWTiles) -> void:
	t.pool_cache.clear()
	var rep := { "discharged": [], "thawed": [], "melted": [] }
	var ids: Array = t.fields.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = t.fields[id]
		f.ticks = int(f.ticks) - 1
		if int(f.ticks) > 0:
			continue
		for h in f.hexes:
			if int(t.shock.get(h, -1)) != id:
				continue
			t.shock.erase(h)
			rep.discharged.append(h)
			var e := t.at(h)
			if not e.is_empty() and int(e.h) < 0 and int(e.glaze) == 0:
				e.h = int(e.h) + 1
				e.timer = BWTiles.STEP_CYCLES
				if int(e.h) == 0 and int(e.v) == 0:
					t.entries.erase(h)
			if t.statics.has(h):
				t.scars[h] = BWTiles.STATIC_SCAR_TICKS + 1   # +1: this tick's static phase counts it too
		t.fields.erase(id)
	prune(t, rep.melted)
	var pk: Array = t.pillars.keys()
	pk.sort()
	for h in pk:
		var p: Dictionary = t.pillars[h]
		p.ticks = int(p.ticks) - 1
		if int(p.ticks) <= 0:
			melt(t, h)
			rep.thawed.append(h)
	t.spine_tick = rep


# ------------------------------------------------------------------ the battle's side

## Turn start (after the fire burn, before the dark drain): an occupant of an
## electrified hex is shocked, SHOCK_PCT × its ramp (thunder class), and
## Staggered for this turn. The ramp: full, then 25%, then immune for the rest
## of that field.
static func turn_shock(b: BWBattle, u: BWUnit) -> void:
	var id := int(b.tiles.shock.get(u.pos, -1))
	if id < 0 or not u.alive() or b.over or not b.tiles.fields.has(id):
		return
	var f: Dictionary = b.tiles.fields[id]
	var n := int(f.ramp.get(u.id, 0))
	f.ramp[u.id] = n + 1
	if n >= SHOCK_RAMP.size():
		b._emit({ "type": "shock_immune", "unit": u.id, "hex": u.pos })
		return
	var dmg := b._tile_dmg(u, SHOCK_PCT * float(SHOCK_RAMP[n]) * BWSets.shock_mult(u), "thunder")   # D282: Thunder set halves it
	b._tile_hurt(u, dmg, "shock", str(f.source))
	if u.alive() and not b.over:
		b._add_status(u, "staggered", b._unit(str(f.source)), 1, true)


## A walk or a push crossed `path` (start excluded): the first electrified
## hex entered shocks for SHOCK_ENTRY_PCT, once per walk.
static func on_walk(b: BWBattle, u: BWUnit, path: Array) -> void:
	for i in range(1, path.size()):
		var id := int(b.tiles.shock.get(path[i], -1))
		if id < 0 or not b.tiles.fields.has(id):
			continue
		if u.alive() and not b.over:
			b._tile_hurt(u, b._tile_dmg(u, SHOCK_ENTRY_PCT, "thunder"), "shock", str(b.tiles.fields[id].source))
		return


## What standing on `h` until the next turn start costs `u` (% max HP), for
## the AI: an electrified hex counts double (it must never end a turn there);
## standing Unsteady on glaze counts BWUnsteady.AI_HAZARD (D401).
static func hazard_pct(b: BWBattle, u: BWUnit, h: Vector2i, _reach_entry: Dictionary = {}) -> float:
	var out := 0.0
	var id := int(b.tiles.shock.get(h, -1))
	if id >= 0 and b.tiles.fields.has(id) and int(b.tiles.fields[id].ticks) >= 1:
		var n := int(b.tiles.fields[id].ramp.get(u.id, 0))
		if n < SHOCK_RAMP.size():
			out += 2.0 * SHOCK_PCT * float(SHOCK_RAMP[n])
	out += BWUnsteady.ai_hazard(b, u, h)
	return out


## The electrified field's shock on `u` at its next turn start (ground_report).
static func shock_next(b: BWBattle, u: BWUnit, hex: Vector2i) -> int:
	var id := int(b.tiles.shock.get(hex, -1))
	if id < 0 or not b.tiles.fields.has(id):
		return 0
	var f: Dictionary = b.tiles.fields[id]
	var n := int(f.ramp.get(u.id, 0))
	if n >= SHOCK_RAMP.size():
		return 0
	return b._tile_dmg(u, SHOCK_PCT * float(SHOCK_RAMP[n]) * BWSets.shock_mult(u), "thunder")


## The tile card's lines for the spine (D266): [[title, words]].
static func report(b: BWBattle, hex: Vector2i) -> Array:
	var t := b.tiles
	var out: Array = []
	if t.is_pillar(hex):
		var pt := int(t.pillars[hex].ticks)
		out.append(["Pillar", "%d tick%s left. Blocks moves and sight; pushes slam on it. Fire melts it, thunder shatters it (17%% to the ring)." % [pt, "" if pt == 1 else "s"]])
	elif BWUnsteady.on_glaze(t, hex):
		out.append(BWUnsteady.card_line(b, hex))       # D397: Unsteady footing
	var id := int(t.shock.get(hex, -1))
	if id >= 0 and t.fields.has(id):
		var f: Dictionary = t.fields[id]
		var words := "%d%% + Staggered at turn start, %d%% on entry, conductive; %d tick%s left, then discharges" % [
			int(SHOCK_PCT), int(SHOCK_ENTRY_PCT), int(f.ticks), "" if int(f.ticks) == 1 else "s"]
		var u := b._centre_at(hex)
		if u != null:
			var n := int(f.ramp.get(u.id, 0))
			words += ". %s: next shock %s" % [u.name, "immune" if n >= SHOCK_RAMP.size() else "%d%%" % int(SHOCK_PCT * float(SHOCK_RAMP[n]))]
		out.append(["Electrified", words])
	var pl := pool(t, hex)
	if pl.size() > 1:
		out.append(["Pool", "%d%s connected water hexes: ice and thunder react within 1 of the cast hex; fire douses the hex it lands on" % [pl.size(), "+" if pl.size() >= POOL_MAX else ""]])
	return out

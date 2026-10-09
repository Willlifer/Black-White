class_name BWWeather
extends RefCounted
## D249-D254 weather (design/WEATHER.md). A modifier tag on about a quarter
## of the rooms from fight 5 (never the Obelisks, the Giant or a boss), rolled
## from the run seed and shown on the room card. In the fight it acts once per
## cycle, at the tick (after the tiles' own tick and any eruptions), through
## tick() below: the battle's only hook. Pure rules, no nodes.
##
##   rain      every hex gains water, up to water 1 (deeper water stays); fire
##             steps down one. Everything stands in water, so everything conducts.
##   ashfall   fire 2+ seeds fire 1 onto every neighbour that isn't mud (not
##             only grass), every tick (seeds are fire 1, so they never spread).
##   eclipse   every hex is pulled one step toward dark 1 (light steps down,
##             bare ground turns dark 1, dark 2-3 eases to dark 1); light heals x2.
##   blizzard  4 hexes glaze each tick (charged ones first; bare ground gets a
##             stasis marker). They are picked a tick AHEAD and shown.
##   gale      every unit is pushed 1 along the heading (D143 rules: rock or a
##             unit in the way = a slam for 5% max HP, the map edge is open air,
##             immune displace holds). The heading turns every 3 ticks; the
##             next one is known in advance.
##
## Static and seeded hexes (D115, D134) are the map: weather never paints on a
## static or an untouched seed (nor on any authored, permanent entry). They
## still act as sources (a static or seeded fire 2+ drops ash on its ring),
## and Blizzard may glaze a static (frozen in time, ELEMENTS §5.5). Glazed
## hexes and markers are left alone by rain and eclipse (a propagated arrival
## never fires a marker, §5.3).
##
## The battle keeps its weather as a plain Dictionary (`BWBattle.weather`,
## deep-copied by clone()), and every random pick is a hash of the fight seed
## and the tick, so a fight replays event for event.

const RAIN := "rain"
const ASHFALL := "ashfall"
const ECLIPSE := "eclipse"
const BLIZZARD := "blizzard"
const GALE := "gale"
const KINDS := [RAIN, ASHFALL, ECLIPSE, BLIZZARD, GALE]
const NAMES := { RAIN: "Rain", ASHFALL: "Ashfall", ECLIPSE: "Eclipse", BLIZZARD: "Blizzard", GALE: "Gale" }
## The room card's and the plate's one line.
const RULES := {
	RAIN: "Each tick: water 1 on every hex, fire steps down. Everything conducts.",
	ASHFALL: "Each tick: fire 2+ spreads fire 1 to every neighbour but mud.",
	ECLIPSE: "Each tick: every hex is pulled toward dark 1. Light heals ×2.",
	BLIZZARD: "Each tick: 4 marked hexes glaze. The next 4 are shown.",
	GALE: "Each tick: every unit is pushed 1 along the wind. It turns every 3 ticks.",
}
## Map-relative compass name per heading (BWHex.CUBE_DIRS order).
const HEADING_NAMES := ["east", "north-east", "north-west", "west", "south-west", "south-east"]

## D249 offers.
const FROM_FIGHT := 5
const DEFAULT_RATE := 0.25
static var RATE := DEFAULT_RATE
## D249: a Hard room with weather pays one more drop.
const HARD_EXTRA_DROPS := 1

## D250 tick rules.
const RAIN_CAP := 1                 # rain alone wets to water 1
const ECLIPSE_PULL := -1            # every hex is pulled toward dark 1
const ECLIPSE_HEAL_MULT := 2.0
const ASH_MIN := 2                  # fire 2+ drops ash
const BLIZZARD_GLAZES := 4
const GALE_TURN_TICKS := 3


# ------------------------------------------------------------------ offers

## The weather on room i of fight n ("" = none). Its own seeded stream, so
## the run's other rolls don't move. Never before FROM_FIGHT, never on a fight
## without a choice (the opening fights, the Obelisks, the Giant), never on a
## boss room.
static func kind_for(run: BWRun, n: int, i: int, room: Dictionary = {}) -> String:
	if n < FROM_FIGHT or not BWRooms.has_choice(n) or n >= BWRun.BOSS_FIGHT or bool(room.get("boss", false)):
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = hash("weather|%d|%d|%d" % [run.seed_value, n, i])
	if r.randf() >= RATE:
		return ""
	return str(KINDS[r.randi() % KINDS.size()])


## Tag fight n's offered rooms with their weather (in place).
static func tag_rooms(run: BWRun, n: int, rooms: Array) -> void:
	for i in rooms.size():
		var k := kind_for(run, n, i, rooms[i])
		if k != "":
			rooms[i]["weather"] = k


## The room card / plate name, "" for none.
static func label(kind: String) -> String:
	return str(NAMES.get(kind, ""))


# ------------------------------------------------------------------ battle state

## A fresh weather state for a fight. Blizzard's first four marks and Gale's
## first two headings are chosen now, so cycle 1 already shows them.
static func start(b: BWBattle, kind: String, seed_value: int) -> Dictionary:
	if not kind in KINDS:
		return {}
	var w := { "kind": kind, "seed": seed_value, "ticks": 0, "marks": [], "heading": -1, "next_heading": -1, "turn_in": 0 }
	if kind == GALE:
		w.heading = _pick(seed_value, "heading", 0) % 6
		w.next_heading = _next_heading(seed_value, 1, int(w.heading))
		w.turn_in = GALE_TURN_TICKS
	if kind == BLIZZARD:
		w.marks = pick_marks(b.tiles, seed_value, 0)
	return w


static func _pick(seed_value: int, what: String, n: int) -> int:
	return absi(hash("weather|%d|%s|%d" % [seed_value, what, n]))


## The heading after `cur`: any of the other five, seeded.
static func _next_heading(seed_value: int, n: int, cur: int) -> int:
	return (cur + 1 + _pick(seed_value, "turn", n) % 5) % 6


## Light standing heal multiplier under this weather (Eclipse x2).
static func heal_mult(w: Dictionary) -> float:
	return ECLIPSE_HEAL_MULT if str(w.get("kind", "")) == ECLIPSE else 1.0


## The tick: the battle calls this once per cycle, after the tiles' tick.
## Emits one `weather` event (its state after the tick, for the plate and the
## telegraphs), then Gale's pushes as `move` (kind "gale") / `slam` events.
static func tick(b: BWBattle) -> void:
	var w: Dictionary = b.weather
	if w.is_empty() or b.over:
		return
	w.ticks = int(w.ticks) + 1
	var e := { "type": "weather", "kind": w.kind, "tick": w.ticks }
	var push_dir := int(w.heading)
	match str(w.kind):
		RAIN:
			e["changed"] = rain(b.tiles)
		ASHFALL:
			e["ignited"] = ashfall(b.tiles)
		ECLIPSE:
			e["changed"] = eclipse(b.tiles)
		BLIZZARD:
			e["glazed"] = glaze(b.tiles, w.marks)
			w.marks = pick_marks(b.tiles, int(w.seed), int(w.ticks))
		GALE:
			w.turn_in = int(w.turn_in) - 1
			if int(w.turn_in) <= 0:
				w.heading = w.next_heading
				w.next_heading = _next_heading(int(w.seed), int(w.ticks) + 1, int(w.heading))
				w.turn_in = GALE_TURN_TICKS
			e["push"] = push_dir
	e.merge(snapshot(w))
	b._emit(e)
	if str(w.kind) == GALE:
		gale_push(b, push_dir)


## What the plate and the telegraphs show (copied into each weather event).
static func snapshot(w: Dictionary) -> Dictionary:
	return { "marks": (w.get("marks", []) as Array).duplicate(), "heading": int(w.get("heading", -1)),
		"next_heading": int(w.get("next_heading", -1)), "turn_in": int(w.get("turn_in", 0)) }


# ------------------------------------------------------------------ tile rules (pure on BWTiles)

## Weather never paints on the map's own charge (D115 statics, D134 seeds,
## any authored permanent entry).
static func _held(t: BWTiles, hex: Vector2i) -> bool:
	return t.is_static(hex) or bool(t.at(hex).get("permanent", false))


static func _hexes(t: BWTiles) -> Array:
	var out: Array = t.board.cells().filter(func(h): return t.can_hold(h))
	out.sort()
	return out


## Rain: bare ground -> water 1; fire steps down one (fire 1 dries out);
## water 1 is kept wet (its timer refreshed); deeper water stays as it is.
## Returns the hexes whose charge changed.
static func rain(t: BWTiles) -> Array:
	var out: Array = []
	for hex in _hexes(t):
		if _held(t, hex):
			continue
		var e := t.at(hex)
		if e.is_empty():
			t.entries[hex] = t._entry(-RAIN_CAP, 0, "", "", "spread")
			out.append(hex)
			continue
		if str(e.marker) != "" or int(e.glaze) > 0:
			continue
		var h := int(e.h)
		if h > 0:
			e.h = h - 1
			if int(e.h) == 0 and int(e.v) == 0:
				t.entries.erase(hex)
			out.append(hex)
		elif h > -RAIN_CAP:
			e.h = -RAIN_CAP
			e.timer = BWTiles.STEP_CYCLES
			out.append(hex)
		elif h == -RAIN_CAP:
			e.timer = BWTiles.STEP_CYCLES
	return out


## Ashfall: every unglazed hex at fire 2+ (any origin, statics and seeds
## included) seeds fire 1 onto each neighbour that can hold charge and isn't
## mud, the grass rule's way (§6.2): fire 1+ is left alone, wet ground dries
## one step, markers and glazes are skipped. Seeds are fire 1, so nothing a
## tick lays spreads on the next (containment, §5.3). Returns the hexes lit.
static func ashfall(t: BWTiles) -> Array:
	var seeds := {}
	for hex in _hexes(t):
		var e := t.at(hex)
		if e.is_empty() or int(e.h) < ASH_MIN or int(e.glaze) > 0:
			continue
		for n in t.board.neighbors(hex):
			if t.can_hold(n) and t.board.terrain(n) != BWBoard.MUDDY and not seeds.has(n):
				seeds[n] = str(e.source)
	var lit: Array = []
	var keys := seeds.keys()
	keys.sort()
	for n in keys:
		if _held(t, n):
			continue
		var cur := t.at(n)
		if not cur.is_empty() and (str(cur.marker) != "" or int(cur.glaze) > 0):
			continue
		var h := int(cur.get("h", 0))
		if h >= 1:
			continue
		if h < 0:
			cur.h = h + 1
			if int(cur.h) == 0 and int(cur.v) == 0:
				t.entries.erase(n)
			continue
		t.entries[n] = t._entry(1, int(cur.get("v", 0)), "", seeds[n], "spread")
		if int(cur.get("v", 0)) > 0:
			t.entries[n]["lsrc"] = BWTiles._lsrc(cur, "fire", "")   # D496
		lit.append(n)
	return lit


## The hexes ashfall would light at the next tick (the telegraph, the AI).
static func ash_preview(t: BWTiles) -> Array:
	var c: BWTiles = BWTiles.new(t.board)
	c.entries = t.entries.duplicate(true)
	c.statics = t.statics
	return ashfall(c)


## Eclipse: every hex steps once toward dark 1 on the light/dark axis (light
## steps down, bare ground and v 0 become dark 1, dark 2-3 ease toward 1).
static func eclipse(t: BWTiles) -> Array:
	var out: Array = []
	for hex in _hexes(t):
		if _held(t, hex):
			continue
		var e := t.at(hex)
		if e.is_empty():
			t.entries[hex] = t._entry(0, ECLIPSE_PULL, "", "", "spread")
			out.append(hex)
			continue
		if str(e.marker) != "" or int(e.glaze) > 0:
			continue
		var v := int(e.v)
		if v == ECLIPSE_PULL:
			if int(e.h) == 0:
				e.timer = BWTiles.STEP_CYCLES        # kept dark, like rain keeps water 1 wet
			continue
		e.v = v - signi(v - ECLIPSE_PULL)
		if int(e.h) == 0 and int(e.v) == 0:
			t.entries.erase(hex)
		out.append(hex)
	return out


## Blizzard: glaze each marked hex. Charged: glazed for GLAZE_CYCLES (a
## static too: frozen in time, §5.5); already glazed: re-glazed; bare
## ground: a stasis marker (ice on empty ground arms, §3.3); a marker or the
## map's seed: left alone. Returns the hexes that took ice.
static func glaze(t: BWTiles, marks: Array) -> Array:
	var out: Array = []
	for hex in marks:
		if not t.can_hold(hex):
			continue
		var e := t.at(hex)
		if bool(e.get("permanent", false)):
			continue
		if e.is_empty():
			t.entries[hex] = t._entry(0, 0, "stasis", "", "spread")
			out.append(hex)
			continue
		if str(e.marker) != "":
			continue
		e.glaze = BWTiles.GLAZE_CYCLES
		e["glaze_source"] = ""
		BWPools.raise_pillar(t, hex, "")          # D262: Blizzard on empty water 3 raises a pillar
		out.append(hex)
	return out


## The next four marks: charged hexes first (not glazed, not the map's seeds;
## a static is fair game), seeded order; bare ground fills the rest.
static func pick_marks(t: BWTiles, seed_value: int, n: int) -> Array:
	var charged: Array = []
	var bare: Array = []
	for hex in _hexes(t):
		var e := t.at(hex)
		if bool(e.get("permanent", false)):
			continue
		if t.charged(hex) and int(e.glaze) == 0:
			charged.append(hex)
		elif e.is_empty():
			bare.append(hex)
	var out: Array = []
	for pool in [charged, bare]:
		var keyed: Array = pool.map(func(h): return [_pick(seed_value, "mark%d|%d,%d" % [n, h.x, h.y], 0), h])
		keyed.sort()
		for k in keyed:
			if out.size() >= BLIZZARD_GLAZES:
				return out
			out.append(k[1])
	return out


# ------------------------------------------------------------------ gale

## The unit-relative order for one gale push: the units farthest along the
## heading move first (so nobody blocks a hex about to empty), ties by setup
## order. Every living unit but an obelisk.
static func push_order(b: BWBattle, dir: int) -> Array:
	var d := heading_vector(dir)
	var rows: Array = []
	for i in b.units.size():
		var v: BWUnit = b.units[i]
		if v.alive() and not BWObelisk.is_objective(v):
			rows.append([BWHex.to_world(v.pos).dot(d), i, v])
	rows.sort_custom(func(a, c) -> bool:
		if absf(a[0] - c[0]) > 1e-4:
			return a[0] > c[0]
		return a[1] < c[1])
	return rows.map(func(r): return r[2])


## World-plane (x, z) unit vector of heading `dir`.
static func heading_vector(dir: int) -> Vector2:
	if dir < 0:
		return Vector2.ZERO
	var o := Vector2i(0, 0)
	return (BWHex.to_world(BWHex.neighbors(o)[dir]) - BWHex.to_world(o)).normalized()


## D251: every unit pushed one hex along `dir`, one at a time (push_order),
## with BWBattle.push_path: a step it can't take into rock or a unit is a
## slam for BWObelisk.SLAM_PCT max HP (credited to nobody, like a pulse),
## the map edge is open air (it just stays), immune displace holds. Pushing
## is not moving: no crossing damage.
static func gale_push(b: BWBattle, dir: int) -> void:
	if dir < 0:
		return
	for v in push_order(b, dir):
		if b.over or not v.alive():
			continue
		if b._immune(v, "displace"):
			b._emit({ "type": "displace_resisted", "unit": v.id, "kind": "gale" })
			continue
		var pp := b.push_path(v, dir, 1)
		if (pp.path as Array).size() > 1:
			v.pos = pp.path[-1]
			b._emit({ "type": "move", "unit": v.id, "path": pp.path, "kind": "gale" })
		elif str(pp.stop) in ["rock", "unit"]:
			b._emit({ "type": "slam", "unit": v.id, "by": "", "into": pp.stop, "name": "Gale" })
			hurt(b, v, BWTiles.tile_damage(v, BWObelisk.SLAM_PCT, "", 1.0), "slam")


## Environmental damage (a gale slam): flat, credited to nobody.
static func hurt(b: BWBattle, v: BWUnit, amount: int, cause: String) -> void:
	if amount <= 0 or not v.alive():
		return
	var before := v.hp
	v.hp = maxi(0, v.hp - amount)
	b._emit({ "type": "tile_damage", "unit": v.id, "amount": amount, "cause": cause, "hp": v.hp, "source": "", "weather": "gale" })
	if not v.alive():
		b._ko(v, null, cause)
		b._check_end()
	else:
		b._hurt_triggers(v, before)


# ------------------------------------------------------------------ forecasts (telegraph, AI)

## What the next tick will do, for the plate, the board telegraphs and the
## AI: { kind, glaze: [hex], ignite: [hex], push: dir, turn_in, next_heading }.
static func forecast(b: BWBattle) -> Dictionary:
	var w: Dictionary = b.weather
	if w.is_empty():
		return {}
	var out := { "kind": w.kind, "glaze": [], "ignite": [], "push": -1 }
	out.merge(snapshot(w))
	match str(w.kind):
		BLIZZARD: out.glaze = (w.marks as Array).duplicate()
		ASHFALL: out.ignite = ash_preview(b.tiles)
		GALE: out.push = int(w.heading)
	return out


## D253: what standing on `h` costs `u` at the next tick, in % of its max HP
## (cheap: the AI weighs its reachable hexes with it). Blizzard: a marked
## hex glazes under you (+15% on every hit you take there, §8.5): counted as
## 6%. Ashfall: a hex that catches is fire 1 at your turn start (4%). Gale:
## a push from `h` that slams (5%), or one that lands you on fire.
static func hazard_pct(b: BWBattle, u: BWUnit, h: Vector2i, fc: Dictionary = {}) -> float:
	var w: Dictionary = b.weather
	if w.is_empty():
		return 0.0
	match str(w.kind):
		BLIZZARD:
			return 6.0 if h in (w.marks as Array) else 0.0
		ASHFALL:
			if fc.is_empty():
				fc = forecast(b)
			return float(BWTiles.FIRE_STAND_PCT) if h in (fc.ignite as Array) else 0.0
		GALE:
			if b._immune(u, "displace"):
				return 0.0
			var at := u.pos
			u.pos = h
			var pp := b.push_path(u, int(w.heading), 1)
			u.pos = at
			if str(pp.stop) in ["rock", "unit"]:
				return float(BWObelisk.SLAM_PCT)
			var land: Vector2i = pp.path[-1]
			return float(b.tiles.standing(land).fire)
	return 0.0


## The weather of fight n's room on `run` (the chosen room for the current
## fight; "" for none).
static func for_fight(run: BWRun, n: int) -> String:
	if n >= BWRun.BOSS_FIGHT or not BWRooms.has_choice(n):
		return ""
	return str(BWRooms.room_for(run, n).get("weather", ""))

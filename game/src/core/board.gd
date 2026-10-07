class_name BWBoard
extends RefCounted
## One hex map: terrain, elevation, spawns. Pure data + queries, no nodes.
##
## Loads the HexMapEditor / Temporal Sea map JSON unchanged
## ({name, cols, rows, cells:[{q,r,terrain,elevation}], ...}) and folds its
## 27 terrains into the four Black | White kinds (DECISIONS D11). A map may
## also use the four kinds directly. Black | White adds one optional field:
##   "spawns": { "player": [[q,r], ...], "enemy": [[q,r], ...] }
## and static charge (D115, design/MAPS.md "Static tiles"), either per cell
##   { "q":.., "r":.., ..., "static": { "h": -3 } }        (h and/or v, -3..3)
## or as a top-level list, which survives a HexMapEditor re-save:
##   "statics": [ { "q":.., "r":.., "h": -3, "v": 0 }, ... ]
## and seeded charge (D134), the same two forms with the key "seed" / "seeds":
##   { "q":.., "r":.., ..., "seed": { "v": -2 } }   or   "seeds": [ {q, r, h, v}, ... ]
## A seeded hex starts charged and holds without decay until play changes it;
## from then on it is ordinary charge and never regrows (ELEMENTS §5.6).

const NEUTRAL := "neutral"
const GRASSY := "grassy"     # fire spreads here
const MUDDY := "muddy"       # 2x movement
const JAGGED := "jagged"     # impassable, blocks sight

const KINDS := [NEUTRAL, GRASSY, MUDDY, JAGGED]

## HexMapEditor terrain -> B|W kind. Anything unlisted is neutral.
const TERRAIN_FOLD := {
	"grass": GRASSY, "tall_grass": GRASSY, "flowers": GRASSY, "forest": GRASSY,
	"windy_mountain_grass": GRASSY, "burning_flower": GRASSY, "thatch": GRASSY,
	"mud": MUDDY, "shallow_water": MUDDY, "snow": MUDDY, "sand": MUDDY,
	"rock": JAGGED, "water": JAGGED, "deep_water": JAGGED, "cliff": JAGGED,
}

## Climbing (DECISIONS D20): a step may rise at most MAX_CLIMB levels, and
## every level climbed costs one extra move. Dropping down is free and
## unlimited.
const MAX_CLIMB := 2

var name := ""
var cols := 0
var rows := 0
var _terrain := {}     # Vector2i -> kind
var _elev := {}        # Vector2i -> int
var spawns := { "player": [] as Array[Vector2i], "enemy": [] as Array[Vector2i] }
## Legal pre-battle placement hexes per side (the 3 rows at each edge).
var deploy := { "player": [] as Array[Vector2i], "enemy": [] as Array[Vector2i] }
var notes := ""
var camera_focus := Vector2i(-1, -1)
## D115: permanent floor charge per hex, Vector2i -> Vector2i(h, v). BWTiles
## lays it and re-forms it every tick (ELEMENTS §5.5).
var statics := {}
## D134: seeded charge per hex, Vector2i -> Vector2i(h, v): laid at the start,
## held until play changes it, never regrown (ELEMENTS §5.6). A hex is static
## or seeded, not both (static wins, with a load error).
var seeds := {}
var errors: PackedStringArray = []
## D140: the map's objective, as authored ({} = a plain fight: wipe the other
## side). "obelisks" mode: { "mode": "obelisks", "obelisks": [{ kind, at: [q, r] }] };
## BWBattle.setup() places them (BWObelisk).
var objective := {}
## Optional extra cost to enter a hex (the battle plugs in water from BWTiles).
var extra_cost: Callable
## D263 dynamic blockers (the battle plugs in BWTiles): `blocker` (hex -> bool)
## makes a hex impassable for now (an ice pillar), `sight_blocker`
## (hex, from, to) -> bool blocks line of sight through it (a pillar, steam).
## Unset = none.
var blocker: Callable
var sight_blocker: Callable


static func from_dict(d: Dictionary) -> BWBoard:
	var b := BWBoard.new()
	b.name = str(d.get("name", "unnamed"))
	b.cols = int(d.get("cols", 0))
	b.rows = int(d.get("rows", 0))
	if b.cols <= 0 or b.rows <= 0:
		b.errors.append("map '%s' has no size" % b.name)
	for c in d.get("cells", []):
		var h := Vector2i(int(c.get("q", -1)), int(c.get("r", -1)))
		if not b.in_bounds(h):
			b.errors.append("cell %s outside %dx%d" % [h, b.cols, b.rows])
			continue
		b._terrain[h] = fold_terrain(str(c.get("terrain", NEUTRAL)))
		b._elev[h] = clampi(int(c.get("elevation", 0)), 0, 15)
		if c.get("static") is Dictionary:
			b._add_static(h, c.static)
		if c.get("seed") is Dictionary:
			b._add_static(h, c.seed, true)
	for st in d.get("statics", []):
		if st is Dictionary:
			b._add_static(Vector2i(int(st.get("q", -1)), int(st.get("r", -1))), st)
	for st in d.get("seeds", []):
		if st is Dictionary:
			b._add_static(Vector2i(int(st.get("q", -1)), int(st.get("r", -1))), st, true)
	for h in b.seeds.keys():
		if b.statics.has(h):
			b.errors.append("hex %s is both static and seeded (static kept)" % h)
			b.seeds.erase(h)
	var sp: Dictionary = d.get("spawns", {})
	for team in ["player", "enemy"]:
		for p in sp.get(team, []):
			var h := Vector2i(int(p[0]), int(p[1]))
			if not b.is_passable(h):
				b.errors.append("%s spawn %s is not standable" % [team, h])
			b.spawns[team].append(h)
		for p in d.get("deploy", {}).get(team, []):
			var h := Vector2i(int(p[0]), int(p[1]))
			if not b.is_passable(h):
				b.errors.append("%s deploy %s is not standable" % [team, h])
			b.deploy[team].append(h)
		if b.deploy[team].is_empty():
			b.deploy[team] = b.spawns[team].duplicate()
	b.notes = str(d.get("notes", ""))
	if d.get("objective") is Dictionary:                  # D140
		b.objective = (d.objective as Dictionary).duplicate(true)
		for o in b.objective.get("obelisks", []):
			var at: Array = o.get("at", [])
			if at.size() != 2 or not b.is_passable(Vector2i(int(at[0]), int(at[1]))):
				b.errors.append("objective %s is not on a standable hex" % [at])
	var cf: Array = d.get("camera", {}).get("focus", [])
	b.camera_focus = Vector2i(int(cf[0]), int(cf[1])) if cf.size() == 2 else Vector2i(b.cols / 2, b.rows / 2)
	return b


func _add_static(h: Vector2i, st: Dictionary, seeded: bool = false) -> void:
	var hv := Vector2i(clampi(int(st.get("h", 0)), -3, 3), clampi(int(st.get("v", 0)), -3, 3))
	var what := "seed" if seeded else "static"
	if not is_passable(h):
		errors.append("%s %s is not on a standable hex" % [what, h])
	elif hv == Vector2i.ZERO:
		errors.append("%s %s has no charge (h and v both 0)" % [what, h])
	elif seeded:
		seeds[h] = hv
	else:
		statics[h] = hv


static func load_file(path: String) -> BWBoard:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		var b := BWBoard.new()
		b.errors.append("could not parse map " + path)
		return b
	return from_dict(parsed)


static func fold_terrain(t: String) -> String:
	if t in KINDS:
		return t
	return TERRAIN_FOLD.get(t, NEUTRAL)


func in_bounds(h: Vector2i) -> bool:
	return h.x >= 0 and h.y >= 0 and h.x < cols and h.y < rows


## A hex with no authored cell is treated as off the map.
func exists(h: Vector2i) -> bool:
	return _terrain.has(h)


func terrain(h: Vector2i) -> String:
	return _terrain.get(h, JAGGED)


func elevation(h: Vector2i) -> int:
	return _elev.get(h, 0)


func set_cell(h: Vector2i, kind: String, elev: int = 0) -> void:
	_terrain[h] = fold_terrain(kind)
	_elev[h] = elev


func is_passable(h: Vector2i) -> bool:
	return exists(h) and terrain(h) != JAGGED


func cells() -> Array:
	return _terrain.keys()


## Cost to step from `a` into adjacent `b`; -1 if the step is not allowed.
## FX hook `opts` (immune): no_muddy (Sure Stride) prices mud as neutral,
## no_water (Wading, Drift) skips the extra cost the tiles plug in.
func step_cost(a: Vector2i, b: Vector2i, opts: Dictionary = {}) -> int:
	if not is_passable(b) or blocked(b):
		return -1
	var rise := elevation(b) - elevation(a)
	if rise > MAX_CLIMB:
		return -1
	var cost := 2 if terrain(b) == MUDDY and not opts.get("no_muddy", false) else 1
	if extra_cost.is_valid() and not opts.get("no_water", false):
		cost += int(extra_cost.call(b))
	return cost + maxi(rise, 0)


## Multi-hex units: every hex of the footprint around `h` (radius `r`) is on
## the map, passable and not in `blocked`. Costs and elevation read the
## centre only (ELEMENTS E15).
func fits(h: Vector2i, r: int, blocked: Dictionary = {}) -> bool:
	for f in BWHex.area(h, r):
		if not is_passable(f) or blocked.has(f) or self.blocked(f):
			return false
	return true


## D263: is `h` impassable right now (an ice pillar)? Terrain is is_passable.
func blocked(h: Vector2i) -> bool:
	return blocker.is_valid() and bool(blocker.call(h))


func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in BWHex.neighbors(h):
		if exists(n):
			out.append(n)
	return out


func area(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in BWHex.area(center, radius):
		if exists(h):
			out.append(h)
	return out


func ray(origin: Vector2i, toward: Vector2i, dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in BWHex.ray(origin, toward, dist):
		if not exists(h):
			break
		out.append(h)
	return out


## Dijkstra over step_cost. `blocked` hexes cannot be entered (enemies);
## `no_stop` hexes can be passed through but not ended on (allies).
## Returns { hex: {cost, from, stop} }; `stop` is false on pass-through
## hexes, which stay in the result so path_to() can route through them.
## `opts`: step_cost's no_muddy / no_water, and `footprint` (ring radius of a
## multi-hex unit: the whole footprint must fit and may not stop on an ally).
func reachable(start: Vector2i, move: int, blocked: Dictionary = {}, no_stop: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var fp := int(opts.get("footprint", 0))
	var best := { start: { "cost": 0, "from": start } }
	var frontier: Array = [[0, start]]
	while not frontier.is_empty():
		var idx := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[idx][0]:
				idx = i
		var cur: Array = frontier.pop_at(idx)
		var cost: int = cur[0]
		var h: Vector2i = cur[1]
		if cost > best[h].cost:
			continue
		for n in neighbors(h):
			if blocked.has(n):
				continue
			if fp > 0 and not fits(n, fp, blocked):
				continue
			var sc := step_cost(h, n, opts)
			if sc < 0:
				continue
			var nc := cost + sc
			if nc > move:
				continue
			if not best.has(n) or nc < best[n].cost:
				best[n] = { "cost": nc, "from": h }
				frontier.append([nc, n])
	for h in best:
		var stop: bool = h == start or not no_stop.has(h)
		if fp > 0 and h != start:
			for f in BWHex.area(h, fp):
				if no_stop.has(f):
					stop = false
		best[h]["stop"] = stop
	return best


static func path_to(reach: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not reach.has(goal) or not reach[goal].get("stop", true):
		return out
	if reach[goal].has("path"):            # BWBattle's perk search keeps each route (D93)
		out.assign(reach[goal].path)
		return out
	var h := goal
	for _i in reach.size() + 1:             # D308: bounded (a from-cycle once hung the sim)
		out.push_front(h)
		var prev: Vector2i = reach[h].from
		if prev == h:
			return out
		if not reach.has(prev):
			break
		h = prev
	out.clear()                             # no route back to the start: not a legal path
	return out


## Line of sight (D20): blocked by jagged hexes and by any hex between that
## stands 2+ levels above both ends. Units never block sight. D263: nor can it
## pass a dynamic sight blocker between (an ice pillar, steam).
func has_los(a: Vector2i, b: Vector2i) -> bool:
	var line := BWHex.line(a, b)
	var top := maxi(elevation(a), elevation(b))
	for i in range(1, line.size() - 1):
		var h: Vector2i = line[i]
		if not exists(h) or terrain(h) == JAGGED:
			return false
		if elevation(h) >= top + 2:
			return false
		if sight_blocker.is_valid() and bool(sight_blocker.call(h, a, b)):
			return false
	return true

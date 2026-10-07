class_name BWSplitFront
extends BWObjectiveMode
## D328-D330: SPLIT FRONT, the fixed 6v6 at fight 5 (the author's concept: "a
## 6v6 map that starts as 2 separate engagements, with a 3-tile wind wall,
## fire wall or ice wall spanning between engagements. So you can unite 2
## teams of 3 units or have them fight 2 other squads of 3").
##
## The map (maps/splitfront.json, 19x15): a west and an east arena split by a
## rock spine (column `split_q`) except a 3-hex gap, the DIVIDER. Spawns 1-3 of
## each side are the west arena, 4-6 the east. Win: every enemy down (the
## default rules). The divider's element is seeded per run (element_for_seed,
## the fight seed; BWObjectives.configure { "divider": ... } overrides):
##   fire  static fire 3 on the three hexes (seeded: it holds until play
##         changes it). Passable at a cost: crossing burns (fire 3 = 6% a hex,
##         ending a turn there 12%). Douse it with water: any water on a hex
##         puts that hex out (at the turn's end).
##   ice   ice pillars on water 3, owner "divider": impassable, they block
##         sight. The existing pillar rules break them: thunder shatters,
##         fire melts, and they thaw on their own after ICE_TICKS ticks (the
##         tick count shows on each pillar), leaving water 3.
##   wind  a Wind Wall (BWWind's walls, owner "divider", no countdown): blocks
##         moves and skills both ways, basic attacks pierce (the D269 ruling).
##         Each hex holds a wall segment (BWObjective, WIND_HP, both sides may
##         strike it with basics): deal WIND_HP to a hex, or land a wind basic
##         in Gust mode on it, and that hex opens.
## The ENEMY breaks through (D330, Claude): at the start of round
## ENEMY_BREAK_ROUND, if it is behind in either arena (fewer units standing
## there, or as many with less HP), it opens the whole divider at once to
## reinforce (`divider_open`, by "enemy"). The squad can open it any time
## with the counters above.

const ELEMENTS := ["fire", "ice", "wind"]
const NAMES := { "fire": "Fire Wall", "ice": "Ice Wall", "wind": "Wind Wall" }
const COUNTER := {
	"fire": "Fire 3 you can walk through (it burns), or douse with water",
	"ice": "Ice pillars: thunder shatters, fire melts; they thaw in %d ticks",
	"wind": "Blocks moves and skills (basics pierce): deal %d to a hex, or Gust it",
}
const ICE_TICKS := 6
static var WIND_HP := 60
const ENEMY_BREAK_ROUND := 4
## Enemy strength on this fight: base stats x this on top of the curve row
## (tuning, campaign_sim; D334).
static var ENEMY_MULT := 1.05
const TITLE := "Split Front"


static func element_for_seed(seed_value: int) -> String:
	return ELEMENTS[absi(hash("divider|%d" % seed_value)) % ELEMENTS.size()]


func title() -> String:
	return TITLE


func objective_text(b: BWBattle) -> String:
	var el := element(b)
	var nm := str(NAMES.get(el, "wall")).to_lower()
	return "Two fronts, one wall: defeat every enemy. The divider is %s %s." % ["an" if nm.begins_with("i") else "a", nm]


static func element(b: BWBattle) -> String:
	return str(b.objective_state.get("split", {}).get("element", ""))


static func state(b: BWBattle) -> Dictionary:
	return b.objective_state.get("split", {})


static func split_q(b: BWBattle) -> int:
	return int(b.board.objective.get("split_q", b.board.cols / 2))


static func divider_hexes(b: BWBattle) -> Array:
	return Array(b.board.objective.get("divider", [])).map(func(p): return Vector2i(int(p[0]), int(p[1])))


## "west", "east" or "gap" (the divider's column).
static func arena_of(b: BWBattle, h: Vector2i) -> String:
	var q := split_q(b)
	return "west" if h.x < q else ("east" if h.x > q else "gap")


static func is_open(b: BWBattle) -> bool:
	return bool(state(b).get("open", false))


## Divider hexes still holding their wall.
static func standing(b: BWBattle) -> Array:
	var st := state(b)
	return Array(st.get("hexes", [])).filter(func(h): return not h in st.get("broken", []))


func setup(b: BWBattle) -> void:
	var el := str(BWObjectives.opt(b, "divider", ""))
	if not el in ELEMENTS:
		el = element_for_seed(int(b.rng.seed))
	var hexes := divider_hexes(b)
	b.objective_state["split"] = { "element": el, "hexes": hexes, "broken": [], "open": false, "opened_by": "", "opened_cycle": 0 }
	match el:
		"fire":
			for h in hexes:
				b.tiles.seed_hex(h, BWTiles.AXIS_MAX, 0)
		"ice":
			for h in hexes:
				b.tiles.seed_hex(h, -BWTiles.AXIS_MAX, 0)
				var e := b.tiles.at(h)
				e.glaze = 1
				e.permanent = false
				e.erase("seeded")
				b.tiles.spine_serial += 1
				b.tiles.pillars[h] = { "owner": "divider", "ticks": ICE_TICKS, "born": b.tiles.spine_serial, "divider": true }
		"wind":
			if not b.wind.has("walls"):
				b.wind["walls"] = {}
			b.wind.walls["divider"] = { "hexes": hexes.duplicate(), "ticks": 99, "divider": true }
			for i in hexes.size():
				var o := BWObjective.make("wind_wall", hexes[i], { "id": "divider_%d" % (i + 1), "name": "Wind Wall",
					"hp": WIND_HP, "def": 0, "res": 0, "hittable": ["player", "enemy"], "look": "wind", "height": 1.5,
					"tag": "divider", "rule": COUNTER.wind % WIND_HP,
					"codex": "A standing gale between the fronts. Arrows and blades pierce it; nothing walks through." })
				BWObjectives.place(b, o)


## The divider's state now, read off the board (fire doused, pillars gone).
static func _settle(b: BWBattle) -> void:
	var st := state(b)
	if st.is_empty() or bool(st.open):
		return
	var gone: Array = []
	for h in standing(b):
		match str(st.element):
			"fire":
				if b.tiles.intensity(h, "fire") < BWTiles.AXIS_MAX:
					b.tiles.entries.erase(h)              # D329: water (or a blast) put the hex out
					gone.append(h)
			"ice":
				if not b.tiles.is_pillar(h):
					gone.append(h)
			"wind":
				var o := _segment(b, h)
				if o == null or not o.alive():
					gone.append(h)
	for h in gone:
		_open_hex(b, h, "player")


static func _segment(b: BWBattle, h: Vector2i) -> BWObjective:
	for o in BWObjectives.objects(b, "divider"):
		if o.pos == h:
			return o
	return null


static func _open_hex(b: BWBattle, h: Vector2i, by: String) -> void:
	var st := state(b)
	if h in st.broken:
		return
	(st.broken as Array).append(h)
	if str(st.element) == "wind" and b.wind.get("walls", {}).has("divider"):
		var w: Dictionary = b.wind.walls.divider
		w.hexes = (w.hexes as Array).filter(func(x): return x != h)
		if (w.hexes as Array).is_empty():
			b.wind.walls.erase("divider")
	b._emit({ "type": "divider_break", "hex": h, "element": str(st.element), "by": by,
		"left": standing(b).size() })
	if standing(b).is_empty() or (str(st.element) != "fire" and standing(b).size() < (st.hexes as Array).size()):
		if not bool(st.open):
			st.open = true                               # a way through: the fronts can merge
			st.opened_by = by
			st.opened_cycle = b.cycle
			b._emit({ "type": "divider_open", "by": by, "element": str(st.element), "hexes": (st.broken as Array).duplicate() })


## Open the whole divider (the enemy's break-through, or a tool).
static func open_all(b: BWBattle, by: String) -> void:
	var st := state(b)
	if st.is_empty():
		return
	var was_open := bool(st.open)
	st.open = true                                   # one divider_open below, naming every hex
	var hexes := standing(b)
	for h in hexes:
		match str(st.element):
			"fire":
				b.tiles.entries.erase(h)
			"ice":
				b.tiles.pillars.erase(h)
				b.tiles.entries.erase(h)
			"wind":
				var o := _segment(b, h)
				if o != null and o.alive():
					o.hp = 0
					b._ko(o, null, "divider")
		_open_hex(b, h, by)
	if not was_open:
		st.opened_by = by
		st.opened_cycle = b.cycle
		b._emit({ "type": "divider_open", "by": by, "element": str(st.element), "hexes": hexes })


## Per arena: [squad standing, squad HP, enemy standing, enemy HP].
static func arena_score(b: BWBattle, arena: String) -> Array:
	var out := [0, 0, 0, 0]
	for u in b.units:
		if not u.alive() or BWObjective.is_object(u) or arena_of(b, u.pos) != arena:
			continue
		var k := 0 if u.team == "player" else 2
		out[k] += 1
		out[k + 1] += u.hp
	return out


## D330: is the enemy behind in this arena?
static func enemy_behind(b: BWBattle, arena: String) -> bool:
	var s := arena_score(b, arena)
	if s[0] == 0 and s[2] == 0:
		return false
	return s[2] < s[0] or (s[2] == s[0] and s[3] < s[1])


func cycle_start(b: BWBattle, c: int) -> void:
	_settle(b)
	if c == ENEMY_BREAK_ROUND and not is_open(b) and not standing(b).is_empty():
		if enemy_behind(b, "west") or enemy_behind(b, "east"):
			b._emit({ "type": "divider_breach", "element": element(b) })
			open_all(b, "enemy")


func turn_end(b: BWBattle, _u: BWUnit) -> void:
	_settle(b)


func after_move(b: BWBattle, _u: BWUnit) -> void:
	_settle(b)


func on_ko(b: BWBattle, victim: BWUnit, _by: BWUnit) -> void:
	if victim is BWObjective and (victim as BWObjective).tag == "divider":
		_settle(b)


## A wind basic in Gust mode aimed at a wall segment blows that hex open.
func after_basic(b: BWBattle, u: BWUnit, target: BWUnit, first: Dictionary) -> void:
	if target is BWObjective and (target as BWObjective).tag == "divider" and target.alive():
		if b.basic_element(u) == "wind" and BWWind.mode(u) == BWWind.GUST and bool(first.get("hit", false)):
			b._emit({ "type": "divider_gust", "unit": u.id, "hex": target.pos })
			BWObjectives.break_object(b, target as BWObjective, u, "gust")
	_settle(b)


## A wall segment is a target only for a unit with no foe left on its own
## side of the wall (it fights the arena first, then breaks through).
func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	if not (f is BWObjective):
		return 1.0
	var mine := arena_of(b, u.pos)
	for o in b.foes_of(u):
		if not BWObjective.is_object(o) and arena_of(b, o.pos) in [mine, "gap"]:
			return 0.0
	return 0.02


## With nothing to hit from any hex it can reach, a unit walks the real way
## to the nearest foe (around the spine, through the gap) instead of hugging
## the rock closest as the crow flies; a wall in the way: to the gap.
func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	if u.team == "neutral" or not b.can_move(u):
		return false
	if not BWAI._best_target(b, u, u.pos).is_empty():
		return false
	var dest := BWAI._best_hex(b, u)
	if dest != u.pos and not BWAI._best_target(b, u, dest).is_empty():
		b.move(u, dest)
		return false
	var goals: Array = []
	for f in b.foes_of(u):
		if not BWObjective.is_object(f):
			goals.append(f.pos)
	var field := BWObjectives.walk_field(b, goals)
	if not field.has(u.pos):
		field = BWObjectives.walk_field(b, standing(b))       # the wall stands between: go to it
	var reach := b.reachable(u)
	var best := u.pos
	var best_v := float(field.get(u.pos, 1 << 20))
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop:
			continue
		var v: float = float(field.get(h, 1 << 20)) + float(reach[h].cost) * 0.01
		if v < best_v:
			best_v = v
			best = h
	if best != u.pos:
		b.move(u, best)
	return false


func hud_lines(b: BWBattle) -> Array:
	var st := state(b)
	if st.is_empty():
		return []
	var el := str(st.element)
	var out := ["%s: %s" % [NAMES.get(el, "Divider"), "OPEN" if bool(st.open) else "%d of %d standing" % [standing(b).size(), (st.hexes as Array).size()]]]
	if not bool(st.open) and b.cycle < ENEMY_BREAK_ROUND:
		out.append("Enemy may break in: round %d" % ENEMY_BREAK_ROUND)
	for arena in ["west", "east"]:
		var sc := arena_score(b, arena)
		out.append("%s front: %d v %d" % [arena.capitalize(), sc[0], sc[2]])
	return out


## The divider's counter text for the banner and the pre-battle screen.
static func counter_text(el: String) -> String:
	match el:
		"ice":
			return COUNTER.ice % ICE_TICKS
		"wind":
			return COUNTER.wind % WIND_HP
	return str(COUNTER.get(el, ""))

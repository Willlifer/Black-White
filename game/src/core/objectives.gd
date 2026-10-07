class_name BWObjectives
extends RefCounted
## D327: the generic OBJECTIVE framework shared by the 6v6 fight modes (Split
## Front and Stop the Horde, D328-D333; Defend / Storm the Castle, the castle
## lane). Pure rules, no nodes, no rng of its own.
##
## A map opts in with "objective": { "mode": "<mode>", ... } (BWBoard.objective;
## "obelisks" stays D140's own). The battle calls the hooks below at fixed
## points; each one dispatches to the mode's BWObjectiveMode subclass, found in
## MODES (mode name -> script path). A mode file that doesn't exist yet is
## skipped (the fight plays as a plain wipe-out), so lanes can land apart.
##
## What the framework gives every mode:
##   OBJECTS  BWObjective (src/core/objective_unit.gd): HP, team "neutral", an
##            allegiance, who may strike it (hittable_by), no turn by default.
##            place(b, o) mid-setup, or the map's objective.objects list.
##   STATE    b.objective_state: a plain dictionary (ids and numbers) the mode
##            owns, plus the framework's keys: "mode", "waves", "reserve" (unit
##            refs waiting to spawn), "escaped", "escape_limit", "exit".
##   VERDICT  BWObjectiveMode.verdict: "" (default rules), "player"/"enemy"
##            (ends), "-" (not over: e.g. waves still to come).
##   WAVES    schedule_wave(b, cycle, units, hexes): units held off the board
##            until `cycle`; the cycle BEFORE, a `wave_incoming` event names
##            the hexes (the telegraph, one tick ahead); at the start of
##            `cycle` they appear (`spawn` per unit, then `wave`). An occupied
##            hex gives way to the nearest free edge hex.
##   EXITS    set_exit(b, hexes, limit): an enemy unit that ends a move or a
##            turn on an exit hex ESCAPES (removed, no KO, no XP; `escape`
##            event); escaped(b) counts them, escape_limit(b) is the cap the
##            mode's verdict reads.
##   AI       ai_turn / ai_target_weight hooks (BWAI).
##
## Hook points in BWBattle (each a one-line call): setup (after the map's
## obelisks), _new_cycle (before the queue: spawns, telegraphs), move (after
## the walk), end_turn, _ko, attack (after the basic), _check_end (verdict).
## foes_of / can_harm read BWObelisk.hittable_by (an objective object's
## `hittable` list). BWTurnQueue skips objects that don't act.

## Mode name -> its rules (a BWObjectiveMode subclass). Lanes add a line.
const MODES := {
	"splitfront": "res://src/core/split_front.gd",
	"horde": "res://src/core/horde_mode.gd",
	"defend": "res://src/core/castle_defend.gd",
	"storm": "res://src/core/castle_storm.gd",
}

static var _cache := {}
static var _none := BWObjectiveMode.new()


## The map's mode name ("" = none, or the obelisks).
static func mode_of(b: BWBattle) -> String:
	var m := str(b.board.objective.get("mode", ""))
	return m if MODES.has(m) else ""


static func handler_for(mode: String) -> BWObjectiveMode:
	if mode == "" or not MODES.has(mode):
		return _none
	if not _cache.has(mode):
		var path: String = MODES[mode]
		var h: BWObjectiveMode = _none
		if ResourceLoader.exists(path):
			var s: Script = load(path)
			if s != null:
				h = s.new()
		_cache[mode] = h
	return _cache[mode]


static func handler(b: BWBattle) -> BWObjectiveMode:
	return handler_for(mode_of(b))


static func active(b: BWBattle) -> bool:
	return not b.objective_state.is_empty()


## Options for this battle's mode (the divider's element ...), set by the
## caller BEFORE setup (the game, tools, tests). Absent = the mode's default
## (usually seeded from the battle seed).
static func configure(b: BWBattle, opts: Dictionary) -> void:
	b.objective_state["opts"] = opts.duplicate(true)


static func opt(b: BWBattle, key: String, def: Variant = null) -> Variant:
	return (b.objective_state.get("opts", {}) as Dictionary).get(key, def)


# ---------------------------------------------------------------- battle hooks

## BWBattle.setup: place the map's objects, then the mode's own setup.
static func setup(b: BWBattle) -> void:
	var mode := mode_of(b)
	if mode == "":
		return
	b.objective_state["mode"] = mode
	for od in b.board.objective.get("objects", []):
		var at: Array = od.get("at", [])
		if at.size() == 2:
			place(b, BWObjective.make(str(od.get("kind", "object")), Vector2i(int(at[0]), int(at[1])), od))
	if b.board.objective.has("exit"):
		set_exit(b, Array(b.board.objective.exit).map(func(p): return Vector2i(int(p[0]), int(p[1]))),
			int(b.board.objective.get("escape_limit", 8)))
	handler_for(mode).setup(b)


## BWBattle._new_cycle, before cycle `c`'s queue: spawns due, the telegraph
## of the next wave, then the mode.
static func cycle_start(b: BWBattle, c: int) -> void:
	if not active(b):
		return
	_spawn_due(b, c)
	_telegraph(b, c)
	handler(b).cycle_start(b, c)


static func after_move(b: BWBattle, u: BWUnit) -> void:
	if not active(b):
		return
	_escape_check(b, u)
	if not b.over:
		handler(b).after_move(b, u)


static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if not active(b):
		return
	for v in b.side("enemy"):              # a pushed or slid grunt on the exit leaves too
		_escape_check(b, v)
	if not b.over:
		handler(b).turn_end(b, u)


static func on_ko(b: BWBattle, victim: BWUnit, by: BWUnit) -> void:
	if active(b):
		handler(b).on_ko(b, victim, by)


static func after_basic(b: BWBattle, u: BWUnit, target: BWUnit, first: Dictionary) -> void:
	if active(b) and not b.over:
		handler(b).after_basic(b, u, target, first)


static func verdict(b: BWBattle) -> String:
	if not active(b):
		return ""
	return handler(b).verdict(b)


static func ai_turn(b: BWBattle, u: BWUnit) -> bool:
	if not active(b):
		return false
	if handler(b).ai_turn(b, u):
		return true                          # D348: a mode may play an acting object (the Lil Fella flees)
	if BWObjective.is_object(u):
		b.end_turn()                         # an acting object with no rules of its own passes
		return true
	return false


## D347: a group block's resolve order (lower first; BWBattle._group_open).
static func group_order(b: BWBattle, u: BWUnit) -> float:
	if not active(b):
		return 0.0
	return handler(b).group_order(b, u)


## D347: the turn order's name for a group ("Horde").
static func group_label(b: BWBattle, key: String) -> String:
	var l := handler(b).group_label(b, key) if active(b) else ""
	return l if l != "" else key.capitalize()


static func ai_target_weight(b: BWBattle, u: BWUnit, f: BWUnit) -> float:
	if not active(b):
		return 1.0
	return handler(b).ai_target_weight(b, u, f)


## A unit takes a slot in the speed queue (objects only when they act).
static func in_queue(u: BWUnit) -> bool:
	return not (u is BWObjective) or (u as BWObjective).acts


# ---------------------------------------------------------------- objects

## Put objective object `o` on the board (from a mode's setup).
static func place(b: BWBattle, o: BWObjective) -> void:
	o.begin_battle()
	b.units.append(o)


## Every objective object of the fight (standing or broken), board order.
static func objects(b: BWBattle, tag: String = "") -> Array:
	return b.units.filter(func(u): return u is BWObjective and (tag == "" or (u as BWObjective).tag == tag))


## Break object `o` now (a scripted break, a Gust): HP to 0, a `ko` event.
static func break_object(b: BWBattle, o: BWObjective, by: BWUnit = null, cause: String = "") -> void:
	if o == null or not o.alive():
		return
	o.hp = 0
	b._ko(o, by, cause)
	b._check_end()


# ---------------------------------------------------------------- waves

## Hold `units` off the board until the start of cycle `cycle`, then place
## them on `hexes` (one each; missing or taken: the nearest free hex of the
## map's spawn edge, objective.spawn_edge, else the enemy deploy zone).
## Units keep their order; returns the wave's index (1-based).
static func schedule_wave(b: BWBattle, cycle: int, units: Array, hexes: Array = []) -> int:
	var waves: Array = b.objective_state.get("waves", [])
	var reserve: Array = b.objective_state.get("reserve", [])
	var ids: Array = []
	for u in units:
		b.units.erase(u)
		u.team = "enemy"
		if not u in reserve:
			reserve.append(u)
		ids.append(u.id)
	waves.append({ "cycle": cycle, "units": ids, "hexes": hexes.duplicate(), "state": "waiting", "index": waves.size() + 1 })
	b.objective_state["waves"] = waves
	b.objective_state["reserve"] = reserve
	return waves.size()


static func waves(b: BWBattle) -> Array:
	return b.objective_state.get("waves", [])


## Waves that have appeared so far.
static func waves_spawned(b: BWBattle) -> int:
	return waves(b).filter(func(w): return str(w.state) == "spawned").size()


static func waves_left(b: BWBattle) -> int:
	return waves(b).filter(func(w): return str(w.state) != "spawned").size()


## The next wave not yet on the board ({} = none).
static func next_wave(b: BWBattle) -> Dictionary:
	for w in waves(b):
		if str(w.state) != "spawned":
			return w
	return {}


## The hexes the map's waves come from: objective.spawn_edge, else the enemy
## deploy zone.
static func spawn_edge(b: BWBattle) -> Array:
	var e: Array = b.board.objective.get("spawn_edge", [])
	if not e.is_empty():
		return e.map(func(p): return Vector2i(int(p[0]), int(p[1])))
	return b.board.deploy.enemy.duplicate()


## Where wave `w`'s units will stand, as of now (free hexes, the wave's own
## first, then the nearest free edge hexes). Deterministic.
static func wave_hexes(b: BWBattle, w: Dictionary) -> Array:
	var edge := spawn_edge(b)
	var want: Array = w.get("hexes", [])
	var taken := {}
	var out: Array = []
	for i in (w.units as Array).size():
		var h: Vector2i = BWBattle.NOWHERE
		if i < want.size():
			var c: Vector2i = want[i]
			if b.board.is_passable(c) and not b.board.blocked(c) and b.unit_at(c) == null and not taken.has(c):
				h = c
		if h == BWBattle.NOWHERE:
			var anchor: Vector2i = want[i] if i < want.size() else (edge[0] if not edge.is_empty() else Vector2i.ZERO)
			var best_d := 1 << 20
			for c in edge:
				if taken.has(c) or not b.board.is_passable(c) or b.board.blocked(c) or b.unit_at(c) != null:
					continue
				var d := BWHex.distance(c, anchor)
				if d < best_d:
					best_d = d
					h = c
		if h != BWBattle.NOWHERE:
			taken[h] = true
		out.append(h)
	return out


static func _reserve_unit(b: BWBattle, id: String) -> BWUnit:
	for u in b.objective_state.get("reserve", []):
		if u.id == id:
			return u
	return null


## The cycle BEFORE a wave: the telegraph (its hexes, its size).
static func _telegraph(b: BWBattle, c: int) -> void:
	for w in waves(b):
		if str(w.state) == "waiting" and int(w.cycle) == c + 1:
			w.state = "telegraphed"
			var hs := wave_hexes(b, w)
			w["shown"] = hs.filter(func(h): return h != BWBattle.NOWHERE)
			b._emit({ "type": "wave_incoming", "wave": int(w.index), "cycle": int(w.cycle), "hexes": w.shown.duplicate(),
				"count": (w.units as Array).size(), "of": waves(b).size() })


static func _spawn_due(b: BWBattle, c: int) -> void:
	for w in waves(b):
		if str(w.state) == "spawned" or int(w.cycle) > c:
			continue
		w.state = "spawned"
		var hs := wave_hexes(b, w)
		var placed: Array = []
		for i in (w.units as Array).size():
			var src := _reserve_unit(b, str(w.units[i]))
			if src == null or hs[i] == BWBattle.NOWHERE:
				continue                           # nowhere to stand: it doesn't come
			# a preview clone never moves the real battle's units
			var u: BWUnit = src
			if b.has_meta("clone"):
				u = src.get_script().new()
				BWBattle._copy_vars(src, u, true)
			u.team = "enemy"
			u.begin_battle()
			u.pos = hs[i]
			u.fx_hook = b._situational
			b.units.append(u)
			if not u.effects.is_empty():
				b._fx_units.append(u)
			var near: BWUnit = null
			for f in b.foes_of(u):
				if near == null or b.gap(u, f) < b.gap(u, near):
					near = f
			if near != null:
				u.facing = BWHex.direction_index(u.pos, near.pos)
			placed.append(u.id)
			b._emit({ "type": "spawn", "unit": u.id, "hex": u.pos, "wave": int(w.index) })
		b._emit({ "type": "wave", "wave": int(w.index), "of": waves(b).size(), "units": placed })


# ---------------------------------------------------------------- exits

## Enemy units ending a move or a turn on `hexes` escape; the mode's verdict
## reads escaped() against `limit`.
static func set_exit(b: BWBattle, hexes: Array, limit: int) -> void:
	b.objective_state["exit"] = hexes.duplicate()
	b.objective_state["escape_limit"] = limit
	b.objective_state["escaped"] = 0
	b.objective_state["escaped_ids"] = []


static func exit_hexes(b: BWBattle) -> Array:
	return b.objective_state.get("exit", [])


static func on_exit(b: BWBattle, h: Vector2i) -> bool:
	return h in exit_hexes(b)


static func escaped(b: BWBattle) -> int:
	return int(b.objective_state.get("escaped", 0))


static func escape_limit(b: BWBattle) -> int:
	return int(b.objective_state.get("escape_limit", 0))


static func _escape_check(b: BWBattle, u: BWUnit) -> void:
	if u == null or b.over or not u.alive() or u.team != "enemy" or BWObjective.is_object(u):
		return
	if exit_hexes(b).is_empty() or not on_exit(b, u.pos):
		return
	u.hp = 0                                      # off the board: not a KO (no XP, no on-kill)
	b.objective_state["escaped"] = escaped(b) + 1
	(b.objective_state["escaped_ids"] as Array).append(u.id)
	b._emit({ "type": "escape", "unit": u.id, "hex": u.pos, "escaped": escaped(b), "limit": escape_limit(b) })
	b._check_end()


## Every enemy unit of the fight, spawned or still waiting (results, loot).
static func all_enemies(b: BWBattle) -> Array:
	var out: Array = b.units.filter(func(u): return u.team == "enemy" and not BWObjective.is_object(u))
	for u in b.objective_state.get("reserve", []):
		if not u in out:
			out.append(u)
	return out


# ---------------------------------------------------------------- display

static func title(b: BWBattle) -> String:
	return handler(b).title() if active(b) else ""


static func objective_text(b: BWBattle) -> String:
	return handler(b).objective_text(b) if active(b) else ""


static func hud_lines(b: BWBattle) -> Array:
	return handler(b).hud_lines(b) if active(b) else []


# ---------------------------------------------------------------- walking

## Walking cost from every hex to the nearest of `goals` (terrain, climbs and
## blockers such as pillars and walls; units ignored). A goal hex that is
## itself blocked (a wall) counts as reached from beside it. hex -> cost.
static func walk_field(b: BWBattle, goals: Array) -> Dictionary:
	var dist := {}
	var buckets := {}
	var gset := {}
	for g in goals:
		gset[g] = true
		dist[g] = 0
		if not buckets.has(0):
			buckets[0] = []
		buckets[0].append(g)
	var c := 0
	var left := goals.size()
	while left > 0:
		var bucket: Array = buckets.get(c, [])
		buckets.erase(c)
		for h in bucket:
			left -= 1
			if int(dist.get(h, -1)) != c:
				continue
			for n in b.board.neighbors(h):
				var sc: int
				if gset.has(h) and b.board.blocked(h):
					sc = 1 if b.board.is_passable(n) and not b.board.blocked(n) else -1
				else:
					sc = b.board.step_cost(n, h, BWBoard.WALK)        # walking n -> h, toward the goal
				if sc < 0:
					continue
				var nc := c + sc
				if nc < int(dist.get(n, 1 << 20)):
					dist[n] = nc
					if not buckets.has(nc):
						buckets[nc] = []
					buckets[nc].append(n)
					left += 1
		c += 1
		if c > 4096:
			break
	return dist

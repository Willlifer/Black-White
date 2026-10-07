class_name BWPhases
extends RefCounted
## D255: the boss PHASE FRAMEWORK. A boss is a set of units plus a phase
## script (data): the phases, what triggers each one, and the rules each one
## turns on. The battle holds the state in `BWBattle.boss` (a plain
## dictionary of ids and numbers, so BWBattle.clone copies it for previews);
## this file evaluates the triggers, merges the rules and emits the events;
## a boss's own file (BWTwins; the Procession next) reads the rules and owns
## its mechanics. Pure rules, no nodes, no rng.
##
## A script:
##   { "kind": "twins", "units": [ids], "rules": { base rules },
##     "phases": [ { "id", "name", "text",
##                   "trigger": { ... }, "rules": { ... },
##                   "scope": "all" | "survivors" } ] }
## Triggers (all optional keys, every given one must hold):
##   hp_below: f     a living script unit is under f of its max HP
##   of: "any"|"all" with hp_below: any one (default) or every living one
##   ko: n           n script units are down; with
##   delay_cycles: d the phase waits d cycles after the n-th fall: it fires at
##                   the start of cycle (fall cycle + d), and is PENDING until
##                   then (countdown() reads it; a `phase_pending` event says so)
##   after: id       another phase has already fired
## A pending phase is cancelled when every script unit is down (nothing left
## to rage). Rules: `scope` "all" merges the phase's rules into the shared
## rules; "survivors" merges them into the per-unit rules of the script units
## alive when it fires. rule(b, key, u) reads per-unit, then shared, then the
## default. Each phase fires once, in script order when several are due.
##
## The battle calls the hooks below at fixed points (BWBattle: setup, turn
## start, move, paint, KO, turn end, new cycle, after damage); each one
## dispatches to the boss kind's file. A battle with no boss (`boss` empty)
## returns at once from every hook.


static func active(b: BWBattle) -> bool:
	return not b.boss.is_empty()


static func kind(b: BWBattle) -> String:
	return str(b.boss.get("kind", ""))


## Begin a script on `b` (BWBattle.setup, through the boss kind's begin()).
static func start(b: BWBattle, script: Dictionary) -> void:
	b.boss["kind"] = str(script.kind)
	b.boss["script"] = script.duplicate(true)
	b.boss["rules"] = Dictionary(script.get("rules", {})).duplicate(true)
	b.boss["unit_rules"] = {}
	b.boss["fired"] = []
	b.boss["pending"] = {}         # phase id -> { due, units }
	b.boss["fallen"] = {}          # unit id -> cycle it fell


## A rule's value for `u` (per-unit rules first), else the shared rules, else `def`.
static func rule(b: BWBattle, key: String, u: BWUnit = null, def: Variant = null) -> Variant:
	if not active(b):
		return def
	if u != null:
		var ur: Dictionary = b.boss.unit_rules.get(u.id, {})
		if ur.has(key):
			return ur[key]
	return b.boss.rules.get(key, def)


static func fired(b: BWBattle, id: String) -> bool:
	return active(b) and id in b.boss.fired


## Cycles until pending phase `id` fires (-1: not pending).
static func countdown(b: BWBattle, id: String) -> int:
	if not active(b) or not b.boss.pending.has(id):
		return -1
	return maxi(0, int(b.boss.pending[id].due) - b.cycle)


static func units(b: BWBattle) -> Array:
	if not active(b):
		return []
	var out: Array = []
	for id in b.boss.script.units:
		var u := b._unit(str(id))
		if u != null:
			out.append(u)
	return out


static func phase_def(b: BWBattle, id: String) -> Dictionary:
	for p in b.boss.script.phases:
		if str(p.id) == id:
			return p
	return {}


## Evaluate every trigger now; fire what holds. Returns the ids fired.
static func check(b: BWBattle) -> Array:
	var out: Array = []
	if not active(b) or b.over:
		return out
	var us := units(b)
	var alive: Array = us.filter(func(u): return u.alive())
	for p in b.boss.script.phases:
		var id := str(p.id)
		if id in b.boss.fired:
			continue
		var tr: Dictionary = p.get("trigger", {})
		if tr.has("after") and not str(tr.after) in b.boss.fired:
			continue
		if tr.has("hp_below"):
			var f := float(tr.hp_below)
			var low: Array = alive.filter(func(u): return float(u.hp) < f * u.max_hp())
			var need_all := str(tr.get("of", "any")) == "all"
			if low.is_empty() or (need_all and low.size() < alive.size()):
				continue
		if tr.has("ko"):
			var down: int = b.boss.fallen.size()
			if down < int(tr.ko):
				continue
			if alive.is_empty():
				if b.boss.pending.has(id):         # nobody left to rage: cancelled
					b.boss.pending.erase(id)
					b._emit({ "type": "phase_cancel", "boss": kind(b), "phase": id })
				continue
			var d := int(tr.get("delay_cycles", 0))
			if d > 0:
				var times: Array = b.boss.fallen.values()
				times.sort()
				var due := int(times[int(tr.ko) - 1]) + d
				if not b.boss.pending.has(id):
					b.boss.pending[id] = { "due": due, "units": alive.map(func(u): return u.id) }
					b._emit({ "type": "phase_pending", "boss": kind(b), "phase": id, "due": due,
						"in": due - b.cycle, "units": alive.map(func(u): return u.id), "name": str(p.get("name", id)) })
				if b.cycle < due:
					continue
		_fire(b, p, alive)
		out.append(id)
	return out


static func _fire(b: BWBattle, p: Dictionary, alive: Array) -> void:
	var id := str(p.id)
	b.boss.fired.append(id)
	b.boss.pending.erase(id)
	var rules: Dictionary = p.get("rules", {})
	var who: Array = alive.map(func(u): return u.id)
	if str(p.get("scope", "all")) == "survivors":
		for uid in who:
			var ur: Dictionary = b.boss.unit_rules.get(uid, {})
			ur.merge(rules, true)
			b.boss.unit_rules[uid] = ur
	else:
		b.boss.rules.merge(rules, true)
	b._emit({ "type": "phase", "boss": kind(b), "phase": id, "name": str(p.get("name", id)),
		"text": str(p.get("text", "")), "units": who })
	dispatch(b, "on_phase", [id])


## A script unit fell (BWBattle._ko).
static func note_ko(b: BWBattle, v: BWUnit) -> void:
	if not active(b) or not v.id in b.boss.script.units or b.boss.fallen.has(v.id):
		return
	b.boss.fallen[v.id] = b.cycle
	check(b)


# ---------------------------------------------------------------- battle hooks

## Called by BWBattle at its fixed points; each forwards to the boss kind's file.
static func dispatch(b: BWBattle, hook: String, args: Array = []) -> Variant:
	if not active(b):
		return null
	match kind(b):
		"twins":
			match hook:
				"on_phase": BWTwins.on_phase(b, args[0])
				"turn_start": return BWTwins.turn_start(b, args[0])
				"turn_end": BWTwins.turn_end(b, args[0])
				"after_move": BWTwins.after_move(b, args[0], args[1])
				"after_paint": BWTwins.after_paint(b, args[0], args[1], args[2])
				"on_ko": BWTwins.on_ko(b, args[0])
				"new_cycle": BWTwins.new_cycle(b)
				"move_plus": return BWTwins.move_plus(b, args[0])
	return null


## BWBattle.setup: begin a boss when the enemy side carries one.
static func setup(b: BWBattle) -> void:
	b.boss = {}
	if b.units.any(func(u): return BWTwins.is_twin(u)):
		BWTwins.begin(b)


## Start of `u`'s turn, before the ground acts. True = the boss handled u's
## light / dark standing itself (the battle skips the light heal and dark drain).
static func turn_start(b: BWBattle, u: BWUnit) -> bool:
	return dispatch(b, "turn_start", [u]) == true


static func turn_end(b: BWBattle, u: BWUnit) -> void:
	dispatch(b, "turn_end", [u])
	check(b)


static func after_move(b: BWBattle, u: BWUnit, path: Array) -> void:
	dispatch(b, "after_move", [u, path])


static func after_paint(b: BWBattle, hexes: Array, element: String, by: BWUnit) -> void:
	dispatch(b, "after_paint", [hexes, element, by])


static func on_ko(b: BWBattle, v: BWUnit) -> void:
	if not active(b):
		return
	note_ko(b, v)
	dispatch(b, "on_ko", [v])


static func new_cycle(b: BWBattle) -> void:
	if not active(b):
		return
	check(b)
	dispatch(b, "new_cycle", [])


static func move_plus(b: BWBattle, u: BWUnit) -> int:
	if not active(b):
		return 0
	return int(rule(b, "move_plus", u, 0))

class_name BWRooms
extends RefCounted
## D186-D188: the room choice. Before every fight except the Obelisks (fight
## 4) and the Giant, the run offers two rooms: a Standard room (the D133
## curve) and a Hard room (tougher enemies, better pay, "Slay the Spire
## elite"). Each room has its own map and its own three enemies, so the
## matchups differ. Pure rules, no nodes; the run state lives on BWRun
## (map_queue, room_offer, room_log) and is saved with it.
##
## Maps (D187): the run's seeded shuffle (BWRun.shuffled_maps, D145) becomes
## a queue of unplayed maps. An offer takes the front two (Standard the first,
## Hard the second). The chosen map is played and leaves the queue; the
## unchosen one goes to the BACK of the queue (it returns to the pool, but the
## next offer shows fresh maps first). Nine maps, nine choice fights: the last
## offer has one unplayed map left, so its Hard room replays an earlier map
## (seeded pick).
##
## Enemies: the Standard squad is three roster characters outside your squad
## drawn on the fight's enemy rng; the Hard squad is three more from the rest
## of that pool (overlapping only when recruits have thinned the roster).
##
## Everything is rolled from the run seed and the run's own state, and the
## offer is stored when shown, so a loaded run shows the same two rooms.

const STANDARD := "standard"
const HARD := "hard"
const KINDS := [STANDARD, HARD]
const NAMES := { STANDARD: "Standard", HARD: "Hard" }

## D188 Hard room tuning (tools/campaign_sim.gd, ROOMS=hard vs standard).
## The fight's own curve row, then: HARD_STAGES stages further on (gear tier,
## ranks), HARD_LEVELS more levels, the base-stat multiplier times HARD_MULT,
## HARD_ARMOR more armour pieces. Perks follow the curve (off in fights 1-2).
## Env HARD (tuning only, the sim): "stages,levels,mult,armor".
## Shipped: x1.18 (D194; was x1.15) and +1 armour only. Measured paired
## (SHADOW=1): +1 level alone or a stage on was a cliff (fights 2-6 near 0%);
## x1.3 put Hard 30-40 points under Standard, x1.2 ~20-35.
static var HARD_STAGES := 0
static var HARD_LEVELS := 0
static var HARD_MULT := 1.18
static var HARD_ARMOR := 1
## Enemy levels gained per stage past the first (D99: 2/3; D194: 1, so an
## enemy's level is its stage: the squad's level, which is the fight number
## since every fight levels it, minus the curve's lag). Tuning: campaign_sim env ELVL.
static var LEVELS_PER_STAGE := 1.0
## D188 Hard room pay (on a win): every drop one tier up, plus one extra drop.
const HARD_TIER_UP := 1
const HARD_EXTRA_DROPS := 1


## D208: the room choice starts at this fight; fights 1-2 go straight to one
## battle (the queue's front map, the Standard squad), no room screen.
const CHOICE_FROM := 3


## Fight n offers a choice of rooms (fight 3 on; not the Obelisks, not the Giant).
static func has_choice(n: int) -> bool:
	return n >= CHOICE_FROM and n <= BWRun.FIGHTS and n != BWRun.OBJECTIVE_FIGHT and n != BWRun.TWINS_FIGHT   # D256: the Twins are fixed


## D208: fight n plays a map off the queue (every fight but the Obelisks and
## the Giant): the opening fights without a choice, then every choice fight.
static func queued(n: int) -> bool:
	return n >= 1 and n <= BWRun.FIGHTS and n != BWRun.OBJECTIVE_FIGHT and n != BWRun.TWINS_FIGHT


## The two rooms for the run's current fight, rolled once and stored on the
## run (a loaded run shows the same two). [] when the fight has no choice.
static func offer(run: BWRun) -> Array:
	if not has_choice(run.fight):
		return []
	if int(run.room_offer.get("fight", 0)) != run.fight:
		run.room_offer = { "fight": run.fight, "rooms": roll(run, run.fight), "chosen": -1 }
	return run.room_offer.rooms


## Take room i (0 = Standard, 1 = Hard) for the current fight. False when
## there is no choice here or i is out of range.
static func choose(run: BWRun, i: int) -> bool:
	var rooms := offer(run)
	if i < 0 or i >= rooms.size():
		return false
	run.room_offer.chosen = i
	return true


## The room picked for the current fight (-1 = not yet).
static func chosen_index(run: BWRun) -> int:
	if int(run.room_offer.get("fight", 0)) != run.fight:
		return -1
	return int(run.room_offer.get("chosen", -1))


## Fight n's room: for the current fight the chosen room (the Standard one
## until a choice is made, so tools and sims that never choose play the
## curve); for a later fight the Standard room it would offer if every room
## in between were Standard; the Obelisks and the Giant a fixed room.
static func room_for(run: BWRun, n: int) -> Dictionary:
	if not has_choice(n):
		return { "kind": STANDARD, "map": projected_map(run, n), "enemies": _draw_ids(run, n, [], false), "fight": n }
	if n == run.fight:
		var rooms: Array = run.room_offer.rooms if int(run.room_offer.get("fight", 0)) == n else roll(run, n)
		var i := chosen_index(run)
		return rooms[i if i >= 0 else 0]
	return { "kind": STANDARD, "map": projected_map(run, n), "enemies": _draw_ids(run, n, [], false), "fight": n }


## Both rooms for fight n from the run's state now (pure; offer() stores it).
static func roll(run: BWRun, n: int) -> Array:
	var maps := offer_maps(run, run.map_queue, n)
	var std_ids := _draw_ids(run, n, [], false)
	var hard_ids := _draw_ids(run, n, std_ids, true)
	var enc := BWEncounters.kind_for(run, n)           # D208: a third of the Hard rooms are encounters
	var rooms := [
		{ "kind": STANDARD, "map": maps[0], "enemies": std_ids, "fight": n },
		BWEncounters.room(n, enc, maps[1]) if enc != "" else { "kind": HARD, "map": maps[1], "enemies": hard_ids, "fight": n },
	]
	BWWeather.tag_rooms(run, n, rooms)                 # D249: a weather tag on ~25% of rooms from fight 5
	return rooms


## [standard map, hard map] for fight n from queue `q`: the front two; with
## one left, Hard replays a played map (seeded on the fight).
static func offer_maps(run: BWRun, q: Array, n: int) -> Array:
	var std: String = str(q[0]) if not q.is_empty() else "arena"
	if q.size() >= 2:
		return [std, str(q[1])]
	var others: Array = BWRun.MAP_POOL.filter(func(m): return m != std)
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash("replay|%d|%d" % [run.seed_value, n])
	return [std, str(others[mrng.randi() % others.size()])]


## The queue after a fight played `played` with `other` unchosen: the played
## map leaves, the other goes to the back.
static func advance(q: Array, played: String, other: String) -> Array:
	var out: Array = q.filter(func(m): return m != played)
	if other in out:
		out.erase(other)
		out.append(other)
	return out


## Fight n's map if every room from now to n is Standard (the current
## fight's own choice counts once it is made).
static func projected_map(run: BWRun, n: int) -> String:
	if not queued(n):
		return _fixed_map(n)
	if run.room_log.has(str(n)):
		return str(run.room_log[str(n)].map)
	if n < run.fight:
		return str(run.map_order[_slot(n) % run.map_order.size()]) if not run.map_order.is_empty() else "arena"
	var q: Array = run.map_queue.duplicate()
	for k in range(run.fight, n + 1):
		if not queued(k):
			continue
		if not has_choice(k):                          # D208: an opening fight takes the front map
			var m: String = str(q[0]) if not q.is_empty() else "arena"
			if k == n:
				return m
			q = advance(q, m, "")
			continue
		var pair := offer_maps(run, q, k)
		if k == run.fight and int(run.room_offer.get("fight", 0)) == k:
			pair = run.room_offer.rooms.map(func(r): return str(r.map))
		var i := chosen_index(run) if k == run.fight else -1
		var pick := maxi(i, 0)
		if k == n:
			return str(pair[pick])
		q = advance(q, str(pair[pick]), str(pair[1 - pick]))
	return "arena"


## After the current fight: record the room, move the map queue on, clear the
## offer. Returns the room that was played.
static func close_fight(run: BWRun) -> Dictionary:
	var n := run.fight
	if not has_choice(n):
		var m := projected_map(run, n)
		if queued(n):
			run.map_queue = advance(run.map_queue, m, "")   # D208: the opening fights use up their map
		run.room_log[str(n)] = { "kind": STANDARD, "map": m }
		return run.room_log[str(n)]
	var rooms: Array = run.room_offer.rooms if int(run.room_offer.get("fight", 0)) == n else roll(run, n)
	var i := maxi(chosen_index(run), 0)
	var room: Dictionary = rooms[i]
	run.map_queue = advance(run.map_queue, str(room.map), str(rooms[1 - i].map))
	run.room_log[str(n)] = { "kind": str(room.kind), "map": str(room.map) }
	if str(room.get("encounter", "")) != "":
		run.room_log[str(n)]["encounter"] = str(room.encounter)   # D208
	if str(room.get("weather", "")) != "":
		run.room_log[str(n)]["weather"] = str(room.weather)       # D249
	run.room_offer = {}
	return room


## D188: the curve row a room's enemies are built from: { stage, mult, perks,
## armor, levels }. Hard = fight n's row with the HARD_* knobs on top.
static func enemy_build(n: int, kind: String) -> Dictionary:
	var c := BWRun.enemy_curve(n)
	var stage := BWRun.enemy_stage(n)
	var out := { "stage": stage, "mult": float(c.mult), "perks": bool(c.perks), "armor": int(c.armor) }
	out["levels"] = floori((stage - 1) * LEVELS_PER_STAGE + 0.001)
	if kind == HARD:
		out.stage = mini(stage + HARD_STAGES, n)
		out.mult = float(c.mult) * HARD_MULT
		out.armor = mini(int(c.armor) + HARD_ARMOR, BWRun.ARMOR_SLOTS.size())
		out.levels = floori((int(out.stage) - 1) * LEVELS_PER_STAGE + 0.001) + HARD_LEVELS
	return out


## The loot tier for a room at fight n.
static func loot_tier(run: BWRun, kind: String) -> String:
	var t := BWRun.tier_index(run.fight) + (HARD_TIER_UP if kind == HARD else 0)
	return BWRun.TIERS[mini(t, BWRun.TIERS.size() - 1)]


## The reward line on a room card.
static func reward_text(run: BWRun, room: Dictionary) -> String:
	var kind := str(room.get("kind", STANDARD))
	var tier := loot_tier(run, kind)
	if kind == HARD and str(room.get("weather", "")) != "":
		return "Win: 5 drops at tier %s (two extra: Hard, weather)" % tier   # D249
	if kind == HARD:
		return "Win: 4 drops at tier %s (one extra, a tier up)" % tier
	return "Win: 3 drops at tier %s" % tier


## D189: restore the room state from a save (after map_order and fight are
## set). A save before v7 has none: the fights already played took their
## D145 slot of map_order, the queue is the rest in order, and no offer is
## pending (the next room screen rolls it).
static func load_state(r: BWRun, d: Dictionary) -> void:
	r.room_log = {}
	r.room_offer = {}
	if d.has("map_queue"):
		r.map_queue = Array(d.map_queue).map(func(m): return str(m))
		for k in Dictionary(d.get("room_log", {})):
			var e: Dictionary = d.room_log[k]
			r.room_log[str(k)] = { "kind": str(e.get("kind", STANDARD)), "map": str(e.get("map", "")) }
			if str(e.get("encounter", "")) != "":
				r.room_log[str(k)]["encounter"] = str(e.encounter)
			if str(e.get("weather", "")) != "":
				r.room_log[str(k)]["weather"] = str(e.weather)          # D249
		var o: Dictionary = d.get("room_offer", {})
		if not o.is_empty():
			r.room_offer = { "fight": int(o.fight), "chosen": int(o.get("chosen", -1)), "rooms": Array(o.rooms).map(
				func(x): return _load_room(x, int(o.fight))) }
		return
	r.map_queue = []
	for n in range(1, BWRun.FIGHTS + 1):
		if not queued(n):
			continue
		var m := str(r.map_order[_slot(n) % r.map_order.size()])
		if n < r.fight:
			r.room_log[str(n)] = { "kind": STANDARD, "map": m }
		else:
			r.map_queue.append(m)


static func _load_room(x: Dictionary, fight: int) -> Dictionary:
	var out := { "kind": str(x.kind), "map": str(x.map), "fight": int(x.get("fight", fight)),
		"enemies": Array(x.enemies).map(func(id): return str(id)) }
	if str(x.get("encounter", "")) != "":
		out["encounter"] = str(x.encounter)          # D208
	if str(x.get("weather", "")) != "":
		out["weather"] = str(x.weather)              # D249
	return out


## The Hard card's note: what makes the squad tougher (from the knobs).
static func hard_note() -> String:
	var parts: PackedStringArray = []
	if HARD_STAGES > 0:
		parts.append("better gear")
	if HARD_LEVELS > 0:
		parts.append("+%d level%s" % [HARD_LEVELS, "s" if HARD_LEVELS > 1 else ""])
	if HARD_MULT > 1.0:
		parts.append("%d%% stronger" % roundi((HARD_MULT - 1.0) * 100))
	if HARD_ARMOR > 0:
		parts.append("more armour")
	return "Tougher squad: " + ", ".join(parts)


static func _fixed_map(n: int) -> String:
	if n == BWRun.TWINS_FIGHT:
		return BWRun.TWINS_MAP                    # D256: the Twins' court
	return BWRun.OBJECTIVE_MAP if n == BWRun.OBJECTIVE_FIGHT else "arena"


## D145's slot for fight n (fights 1-3 -> 0-2, 5-10 -> 3-8).
static func _slot(n: int) -> int:
	return (n - 1) if n < BWRun.OBJECTIVE_FIGHT else (n - 2)


## Three roster ids outside the squad (and outside `avoid` while the pool
## allows), drawn on fight n's enemy rng (Hard: its own stream).
static func _draw_ids(run: BWRun, n: int, avoid: Array, hard: bool) -> Array:
	var pool: Array = []
	for row in run.roster_rows:
		if run.unit(str(row.id)) == null:
			pool.append(str(row.id))
	pool.sort()
	var fresh: Array = pool.filter(func(id): return not id in avoid)
	if fresh.size() >= BWRun.DEPLOY:
		pool = fresh
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("hard|%d|%d" % [run.seed_value, n]) if hard else run.seed_value * 7919 + n
	var out: Array = []
	for i in mini(BWRun.DEPLOY, pool.size()):
		out.append(pool.pop_at(erng.randi() % pool.size()))
	return out

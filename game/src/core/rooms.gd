class_name BWRooms
extends RefCounted
## D186-D188: the room choice. A choice fight offers cards (D353: which ones
## is BWSchedule.TABLE): a Standard room (the D133 curve) and a Hard room
## (tougher enemies, better pay, "Slay the Spire elite"), or a boss card (the
## Obelisks, the Twins), or a 6v6 card (a mode on its map). Each card has its
## own map and its own enemies, so the matchups differ. Pure rules, no nodes; the run state lives on BWRun
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
const NAMES := { STANDARD: "Standard", HARD: "Hard", "boss": "Boss", "six": "6v6" }

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
## D353: the whole schedule is BWSchedule.TABLE; this stays for readers.
const CHOICE_FROM := 3
## D353: the card kinds past Standard / Hard: a boss card (the Obelisks, the
## Twins; field `boss`) and a 6v6 card (field `mode`, a Split Front `divider`).
const BOSS := "boss"
const SIX := "six"


## Fight n offers a choice of cards (BWSchedule.TABLE: two cards or more).
static func has_choice(n: int) -> bool:
	return n <= BWRun.FIGHTS and BWSchedule.has_choice(n)


## D208: fight n can play a map off the queue: the openers and every fight
## with a 3v3 card (D353).
static func queued(n: int) -> bool:
	return n >= 1 and n <= BWRun.FIGHTS and BWSchedule.queued(n)


## The cards for the run's current fight, rolled once and stored on the run
## (a loaded run shows the same ones). [] when the fight has no choice.
static func offer(run: BWRun) -> Array:
	if not has_choice(run.fight):
		return []
	if int(run.room_offer.get("fight", 0)) != run.fight:
		run.room_offer = { "fight": run.fight, "rooms": roll(run, run.fight), "chosen": -1 }
	return run.room_offer.rooms


## Take card i for the current fight. False when there is no choice here or
## i is out of range.
static func choose(run: BWRun, i: int) -> bool:
	var rooms := offer(run)
	if i < 0 or i >= rooms.size():
		return false
	run.room_offer.chosen = i
	return true


## The card picked for the current fight (-1 = not yet).
static func chosen_index(run: BWRun) -> int:
	if int(run.room_offer.get("fight", 0)) != run.fight:
		return -1
	return int(run.room_offer.get("chosen", -1))


## Fight n's room: for the current fight the chosen card (card 0 until a
## choice is made, so tools and sims that never choose play it); for a later
## fight the card it would play if every choice in between took card 0; a
## played fight its logged room; the Giant a fixed room.
static func room_for(run: BWRun, n: int) -> Dictionary:
	if run.mode_override.has(n):                       # tools only (campaign_sim SIX=1)
		var md := str(run.mode_override[n])
		var om := BWRun.mode_map(md)
		var ro := { "kind": SIX, "mode": md, "map": om, "fight": n, "enemies": _draw_ids(run, n, [], false, _count(run, om)) }
		if md == "splitfront":
			ro["divider"] = str(BWSchedule.dividers(run.seed_value, n, 1)[0])
		return ro
	if n >= BWRun.BOSS_FIGHT:
		return { "kind": STANDARD, "map": "arena", "enemies": [], "fight": n }
	if n < run.fight:
		var logged: Dictionary = run.room_log.get(str(n), {})
		if logged.is_empty():                          # an older save: the D145 slot
			logged = { "kind": STANDARD, "map": str(run.map_order[_slot(n) % run.map_order.size()]) if not run.map_order.is_empty() else "arena" }
		var past := logged.duplicate()
		past["fight"] = n
		past["enemies"] = _draw_ids(run, n, [], false, _count(run, str(past.map)))
		return past
	return _walk(run, n)


## D319: the enemies a room on `map` fields: its deploy_count (run.force_map wins).
static func _count(run: BWRun, map: String) -> int:
	return BWRun.deploy_count_of(run.force_map if run.force_map != "" else map)


## Every card for fight n from the run's state now (pure; offer() stores it).
static func roll(run: BWRun, n: int) -> Array:
	return cards(run, n, run.map_queue, played_modes(run), played_maps(run))


## D353: fight n's cards (BWSchedule.TABLE) from queue `q` and the 6v6 modes
## and maps already played. Pure.
static func cards(run: BWRun, n: int, q: Array, p_modes: Array, p_maps: Array) -> Array:
	var sl := BWSchedule.slots(n)
	var out: Array = []
	var qmaps: Array = offer_maps(run, q, n) if BWSchedule.queue_cards(n) >= 2 else [str(q[0]) if not q.is_empty() else _replay(run, n, [])]
	var qi := 0
	var drawn: Array = []                              # enemy ids already on a card: the next card's squad avoids them
	var taken: Array = []                              # 6v6 maps already on a card
	var divs := BWSchedule.dividers(run.seed_value, n, sl.size())
	for i in sl.size():
		var s := str(sl[i])
		var room := {}
		match s:
			BWSchedule.SINGLE, BWSchedule.STANDARD:
				var m: String = qmaps[mini(qi, qmaps.size() - 1)]
				qi += 1
				room = { "kind": STANDARD, "map": m, "enemies": _draw_ids(run, n, [], false, _count(run, m)), "fight": n }
			BWSchedule.HARD:
				var m: String = qmaps[mini(qi, qmaps.size() - 1)]
				qi += 1
				var enc := BWEncounters.kind_for(run, n)   # D208: a third of the Hard rooms are encounters
				if enc != "":
					room = BWEncounters.room(n, enc, m)
				else:
					room = { "kind": HARD, "map": m, "enemies": _draw_ids(run, n, drawn, true, _count(run, m)), "fight": n }
			BWSchedule.OBELISKS:
				room = { "kind": BOSS, "boss": s, "map": BWRun.OBJECTIVE_MAP, "fight": n,
					"enemies": _draw_ids(run, n, [], false, _count(run, BWRun.OBJECTIVE_MAP)) }
			BWSchedule.TWINS:
				room = { "kind": BOSS, "boss": s, "map": BWRun.TWINS_MAP, "fight": n, "enemies": [] }
			BWSchedule.SPLIT:
				room = { "kind": SIX, "mode": "splitfront", "map": str(BWSchedule.SPLIT_MAPS[i % BWSchedule.SPLIT_MAPS.size()]), "fight": n }
			BWSchedule.SIX:
				var e := BWSchedule.draw_six(run.seed_value, n, i, p_modes, p_maps, taken)
				room = { "kind": SIX, "mode": str(e.get("mode", "")), "map": str(e.get("map", BWRun.MODE_PLACEHOLDER)), "fight": n }
			_:
				room = { "kind": STANDARD, "map": "arena", "enemies": [], "fight": n }
		if room.kind == SIX:
			taken.append(str(room.map))
			room["enemies"] = _draw_ids(run, n, drawn, i > 0, _count(run, str(room.map)))
			if str(room.mode) == "splitfront":
				room["divider"] = str(divs[i])         # D354: two Split Front cards, two dividers
		drawn.append_array(room.get("enemies", []))
		out.append(room)
	_tag_weather(run, n, out)
	return out


## D357: a weather tag (BWWeather's seeded roll per card) on the 3v3 cards and
## the Split Front / Horde cards; never a castle, never a boss.
static func _tag_weather(run: BWRun, n: int, rooms: Array) -> void:
	if not has_choice(n):
		return
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var ok: bool = str(r.kind) in [STANDARD, HARD] or (str(r.kind) == SIX and str(r.get("mode", "")) in BWSchedule.WEATHER_MODES)
		if not ok:
			continue
		var k := BWWeather.kind_for(run, n, i)
		if k != "":
			r["weather"] = k


## Fight n's room if every choice from now to n takes card 0 (the current
## fight's own offer and choice count once made).
static func _walk(run: BWRun, n: int) -> Dictionary:
	var q: Array = run.map_queue.duplicate()
	var pmo := played_modes(run)
	var pma := played_maps(run)
	for k in range(run.fight, n + 1):
		var cs: Array
		var pick := 0
		if k == run.fight and has_choice(k) and int(run.room_offer.get("fight", 0)) == k:
			cs = run.room_offer.rooms
			pick = maxi(chosen_index(run), 0)
		else:
			cs = cards(run, k, q, pmo, pma)
		if cs.is_empty():
			break
		var room: Dictionary = cs[pick]
		if k == n:
			return room
		q = advance_cards(q, k, cs, pick)
		if str(room.get("mode", "")) != "":
			pmo.append(str(room.mode))
			pma.append(str(room.map))
	return { "kind": STANDARD, "map": "arena", "enemies": [], "fight": n }


## D356: the 6v6 modes and maps the run has played (the room log).
static func played_modes(run: BWRun) -> Array:
	return run.room_log.values().filter(func(e): return str(e.get("mode", "")) != "").map(func(e): return str(e.mode))


static func played_maps(run: BWRun) -> Array:
	return run.room_log.values().filter(func(e): return str(e.get("mode", "")) != "").map(func(e): return str(e.map))


## [standard map, hard map] for fight n from queue `q`: the front two; with
## one left, Hard replays a played map (seeded on the fight).
static func offer_maps(run: BWRun, q: Array, n: int) -> Array:
	var std: String = str(q[0]) if not q.is_empty() else "arena"
	if q.size() >= 2:
		return [std, str(q[1])]
	return [std, _replay(run, n, [std])]


## A pool map to replay when the queue has run dry (seeded on the fight).
static func _replay(run: BWRun, n: int, avoid: Array) -> String:
	var others: Array = BWRun.MAP_POOL.filter(func(m): return not m in avoid)
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash("replay|%d|%d" % [run.seed_value, n])
	return str(others[mrng.randi() % others.size()])


## The queue after a fight played `played` with `other` unchosen: the played
## map leaves, the other goes to the back.
static func advance(q: Array, played: String, other: String) -> Array:
	var out: Array = q.filter(func(m): return m != played)
	if other in out:
		out.erase(other)
		out.append(other)
	return out


## D353: the queue after fight k played card `pick` of `cs`: a 3v3 card's map
## leaves, every unchosen 3v3 card's map goes to the back; 6v6 and boss maps
## are not queue maps.
static func advance_cards(q: Array, k: int, cs: Array, pick: int) -> Array:
	var sl := BWSchedule.slots(k)
	var out := advance(q, str(cs[pick].map) if _is_queue(sl, pick) else "", "")
	for i in cs.size():
		if i != pick and _is_queue(sl, i):
			out = advance(out, "", str(cs[i].map))
	return out


static func _is_queue(sl: Array, i: int) -> bool:
	return i < sl.size() and str(sl[i]) in BWSchedule.QUEUE_SLOTS


## Fight n's map if every card from now to n is card 0 (the current fight's
## own choice counts once it is made).
static func projected_map(run: BWRun, n: int) -> String:
	return str(room_for(run, n).get("map", "arena"))


## D354: the battle options of fight n's room (the Split Front divider), for
## BWObjectives.configure: the game, the sim and the pre-battle all read it.
static func battle_opts(run: BWRun, n: int) -> Dictionary:
	var d := str(room_for(run, n).get("divider", ""))
	return { "divider": d } if d != "" else {}


## After the current fight: record the room, move the map queue on, clear the
## offer. Returns the room that was played.
static func close_fight(run: BWRun) -> Dictionary:
	var n := run.fight
	var cs: Array = run.room_offer.rooms if has_choice(n) and int(run.room_offer.get("fight", 0)) == n else roll(run, n)
	if cs.is_empty():
		run.room_log[str(n)] = { "kind": STANDARD, "map": "arena" }
		run.room_offer = {}
		return run.room_log[str(n)].duplicate()
	var i := maxi(chosen_index(run), 0) if has_choice(n) else 0
	var room: Dictionary = cs[i]
	run.map_queue = advance_cards(run.map_queue, n, cs, i)
	var entry := { "kind": str(room.kind), "map": str(room.map) }
	for k in ["encounter", "weather", "mode", "boss", "divider"]:   # D208, D249, D327, D353, D354
		if str(room.get(k, "")) != "":
			entry[k] = str(room[k])
	run.room_log[str(n)] = entry
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
	if kind == SIX:
		return "Win: %d drops at tier %s" % [BWRun.MODE_DROPS, tier]         # D334
	if str(room.get("boss", "")) == BWSchedule.TWINS:
		return "Win: a free pick for every unit, and 2 drops at tier %s" % tier   # D258
	if str(room.get("boss", "")) == BWSchedule.OBELISKS:
		return "Win: a drop for every enemy down, tier %s" % tier
	return "Win: 3 drops at tier %s" % tier


## D189: restore the room state from a save (after map_order and fight are
## set). A save before v7 has none: the fights already played took their
## D145 slot of map_order, the queue is the rest in order, and no offer is
## pending (the next room screen rolls it).
## D358 (save v12): an offer whose cards don't fit fight n's slots in
## BWSchedule.TABLE (a v11 save made under D325's schedule) is dropped, so the
## room screen rolls the new schedule's cards; the log and the queue carry over.
static func load_state(r: BWRun, d: Dictionary) -> void:
	r.room_log = {}
	r.room_offer = {}
	if d.has("map_queue"):
		r.map_queue = Array(d.map_queue).map(func(m): return str(m))
		for k in Dictionary(d.get("room_log", {})):
			var e: Dictionary = d.room_log[k]
			r.room_log[str(k)] = { "kind": str(e.get("kind", STANDARD)), "map": str(e.get("map", "")) }
			for f in ["encounter", "weather", "mode", "boss", "divider"]:   # D208, D249, D327, D353, D354
				if str(e.get(f, "")) != "":
					r.room_log[str(k)][f] = str(e[f])
		var o: Dictionary = d.get("room_offer", {})
		if not o.is_empty():
			var rooms: Array = Array(o.rooms).map(func(x): return _load_room(x, int(o.fight)))
			if fits(int(o.fight), rooms):
				r.room_offer = { "fight": int(o.fight), "chosen": int(o.get("chosen", -1)), "rooms": rooms }
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


## D358: do these cards fit fight n's slots (card for card)?
static func fits(n: int, rooms: Array) -> bool:
	var sl := BWSchedule.slots(n)
	if sl.size() != rooms.size():
		return false
	for i in sl.size():
		var want := { BWSchedule.SINGLE: STANDARD, BWSchedule.STANDARD: STANDARD, BWSchedule.HARD: HARD,
			BWSchedule.OBELISKS: BOSS, BWSchedule.TWINS: BOSS, BWSchedule.SPLIT: SIX, BWSchedule.SIX: SIX }
		if str(rooms[i].get("kind", "")) != str(want.get(str(sl[i]), "")):
			return false
		if str(want.get(str(sl[i]), "")) == BOSS and str(rooms[i].get("boss", "")) != str(sl[i]):
			return false
	return true


static func _load_room(x: Dictionary, fight: int) -> Dictionary:
	var out := { "kind": str(x.kind), "map": str(x.map), "fight": int(x.get("fight", fight)),
		"enemies": Array(x.get("enemies", [])).map(func(id): return str(id)) }
	for f in ["encounter", "weather", "mode", "boss", "divider"]:   # D208, D249, D327, D353, D354
		if str(x.get(f, "")) != "":
			out[f] = str(x[f])
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


## D145's slot for fight n (fights 1-3 -> 0-2, 5-10 -> 3-8).
static func _slot(n: int) -> int:
	return (n - 1) if n < BWRun.OBJECTIVE_FIGHT else (n - 2)


## `count` (3; D319: the map's deploy_count) roster ids outside the squad (and
## outside `avoid` while the pool allows), drawn on fight n's enemy rng (Hard:
## its own stream). The first three draws are the same at any count.
static func _draw_ids(run: BWRun, n: int, avoid: Array, hard: bool, count: int = BWRun.DEPLOY) -> Array:
	var pool: Array = []
	for row in run.roster_rows:
		if run.unit(str(row.id)) == null:
			pool.append(str(row.id))
	pool.sort()
	var fresh: Array = pool.filter(func(id): return not id in avoid)
	if fresh.size() >= count:
		pool = fresh
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("hard|%d|%d" % [run.seed_value, n]) if hard else run.seed_value * 7919 + n
	var out: Array = []
	for i in mini(count, pool.size()):
		out.append(pool.pop_at(erng.randi() % pool.size()))
	return out

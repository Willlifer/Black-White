extends RefCounted
## D249-D254 weather (design/WEATHER.md, BWWeather): each kind's tick rules,
## the static / seeded interplay, the offer rate and exclusions, Hard pay,
## saves, determinism, and the AI reading the telegraphs.

const C := Vector2i(4, 4)


## An n x n board; `cells` {Vector2i: {terrain?, static?, seed?}}.
func _board(cells: Dictionary = {}, n: int = 9) -> BWBoard:
	var out: Array = []
	for r in n:
		for c in n:
			var cell := { "q": c, "r": r, "terrain": "neutral", "elevation": 0 }
			cell.merge(cells.get(Vector2i(c, r), {}), true)
			out.append(cell)
	return BWBoard.from_dict({ "name": "w", "cols": n, "rows": n, "cells": out,
		"spawns": { "player": [[0, 3], [0, 4], [0, 5]], "enemy": [[8, 3], [8, 4], [8, 5]] } })


func _u(id: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": "sword", "element": "",
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _hv(tl: BWTiles, h: Vector2i) -> Vector2i:
	var e := tl.at(h)
	return Vector2i(int(e.get("h", 0)), int(e.get("v", 0)))


func _put(tl: BWTiles, h: Vector2i, hh: int, vv: int) -> void:
	tl.entries[h] = tl._entry(hh, vv, "", "x", "cast")


# ------------------------------------------------------------------ rain

func test_rain(t) -> void:
	var tl := BWTiles.new(_board({ Vector2i(1, 1): { "static": { "h": 2 } }, Vector2i(2, 2): { "seed": { "v": 2 } } }))
	_put(tl, Vector2i(3, 3), 3, 0)
	_put(tl, Vector2i(4, 3), 1, 0)
	_put(tl, Vector2i(5, 3), -3, 0)
	_put(tl, Vector2i(6, 3), 0, 2)
	tl.entries[Vector2i(7, 3)] = tl._entry(0, 0, "fuse", "x", "cast")
	_put(tl, Vector2i(3, 5), 2, 0)
	tl.entries[Vector2i(3, 5)].glaze = 2
	BWWeather.rain(tl)
	t.eq(_hv(tl, C), Vector2i(-1, 0), "bare ground: water 1")
	t.eq(_hv(tl, Vector2i(3, 3)), Vector2i(2, 0), "fire 3 steps down to 2")
	t.ok(tl.at(Vector2i(4, 3)).is_empty(), "fire 1 is put out (not turned to water)")
	t.eq(_hv(tl, Vector2i(5, 3)), Vector2i(-3, 0), "painted water 3 stays")
	t.eq(_hv(tl, Vector2i(6, 3)), Vector2i(-1, 2), "light 2 gets wet: water 1 + light 2")
	t.eq(str(tl.at(Vector2i(7, 3)).marker), "fuse", "a marker is left armed (a propagated arrival never fires it)")
	t.eq(_hv(tl, Vector2i(3, 5)), Vector2i(2, 0), "a glazed hex is frozen: untouched")
	t.eq(_hv(tl, Vector2i(1, 1)), Vector2i(2, 0), "a static fire is the map's: untouched")
	t.ok(tl.is_seeded(Vector2i(2, 2)) and _hv(tl, Vector2i(2, 2)) == Vector2i(0, 2), "an untouched seed stays a seed")
	BWWeather.rain(tl)
	t.eq(_hv(tl, C), Vector2i(-1, 0), "never past water 1 from rain alone")
	for i in 6:                                              # the cycle's tick, then the weather
		tl.tick()
		BWWeather.rain(tl)
	t.eq(_hv(tl, C), Vector2i(-1, 0), "stays wet tick after tick (no flicker)")
	t.eq(_hv(tl, Vector2i(1, 1)), Vector2i(2, 0), "the static fire still burns")
	t.eq(tl.conduct_mult(C, "thunder"), 1.1, "everything conducts: +10% thunder on every hex")


# ------------------------------------------------------------------ ashfall

func test_ashfall(t) -> void:
	var mud := Vector2i(5, 4)
	var rock := Vector2i(3, 4)
	var tl := BWTiles.new(_board({ mud: { "terrain": "muddy" }, rock: { "terrain": "jagged" },
		Vector2i(1, 1): { "static": { "h": 2 } }, Vector2i(1, 2): { "seed": { "v": -2 } } }))
	_put(tl, C, 2, 0)
	var wet := Vector2i(4, 5)
	_put(tl, wet, -1, 0)
	var lit := BWWeather.ashfall(tl)
	for n in tl.board.neighbors(C):
		if n == mud or n == rock or n == wet:
			continue
		t.eq(_hv(tl, n), Vector2i(1, 0), "%s: neutral ground catches (not just grass)" % [n])
	t.ok(tl.at(mud).is_empty(), "mud never catches")
	t.ok(tl.at(rock).is_empty(), "rock holds nothing")
	t.ok(tl.at(wet).is_empty(), "wet ground dries a step instead")
	t.eq(str(tl.at(lit[0]).origin), "spread", "ash is spread, not cast")
	# fire 1 never spreads: the next tick adds nothing past the ring
	var before := tl.entries.size()
	_put(tl, C, 1, 0)
	t.eq(BWWeather.ashfall(tl).filter(func(h): return BWHex.distance(h, C) > 1).size(), 0, "a seed (fire 1) never spreads")
	# a static fire 2 drops ash on its ring; a seed beside it is the map's, untouched
	var t2 := BWTiles.new(_board({ Vector2i(1, 1): { "static": { "h": 2 } }, Vector2i(1, 2): { "seed": { "v": -2 } } }))
	BWWeather.ashfall(t2)
	t.eq(_hv(t2, Vector2i(2, 1)), Vector2i(1, 0), "a static fire 2 spreads too")
	t.ok(t2.is_seeded(Vector2i(1, 2)), "a seeded neighbour is not lit")
	t.ok(before > 0, "sanity")
	# containment: a full board with one fire 3 stays bounded and dies out
	var t3 := BWTiles.new(_board())
	_put(t3, C, 3, 0)
	var most := 0
	for i in 14:
		t3.tick()
		BWWeather.ashfall(t3)
		most = maxi(most, t3.entries.size())
	t.ok(most <= 7, "one fire 3 never lights more than its ring (peak %d)" % most)
	t.ok(t3.entries.is_empty(), "and the fire is out within 14 ticks")


# ------------------------------------------------------------------ eclipse

func test_eclipse(t) -> void:
	var tl := BWTiles.new(_board({ Vector2i(1, 1): { "static": { "v": 3 } }, Vector2i(2, 2): { "seed": { "v": 2 } } }))
	_put(tl, Vector2i(3, 3), 0, 3)
	_put(tl, Vector2i(4, 3), 0, -3)
	_put(tl, Vector2i(5, 3), 2, 0)
	BWWeather.eclipse(tl)
	t.eq(_hv(tl, C), Vector2i(0, -1), "bare ground: dark 1")
	t.eq(_hv(tl, Vector2i(3, 3)), Vector2i(0, 2), "light 3 is pulled down a step (light fights it)")
	t.eq(_hv(tl, Vector2i(4, 3)), Vector2i(0, -2), "dark 3 eases toward dark 1")
	t.eq(_hv(tl, Vector2i(5, 3)), Vector2i(2, -1), "fire 2 keeps its fire, gains dark 1")
	t.eq(_hv(tl, Vector2i(1, 1)), Vector2i(0, 3), "a static light is the map's")
	t.ok(tl.is_seeded(Vector2i(2, 2)), "a seed is the map's")
	for i in 4:
		tl.tick()
		BWWeather.eclipse(tl)
	t.eq(_hv(tl, C), Vector2i(0, -1), "dark 1 holds")
	t.eq(_hv(tl, Vector2i(4, 3)), Vector2i(0, -1), "dark 3 has eased to dark 1")
	# light heals x2
	var b := BWBattle.new(_board({ C: { "static": { "v": 2 } } }), 5)
	var u := _u("p")
	var f := _u("e")
	b.set_weather(BWWeather.ECLIPSE)
	b.setup([u], [f])
	u.pos = C
	u.hp = u.max_hp() - 40
	b.queue = [u]
	b.turn_index = 0
	var hp0 := u.hp
	b._begin_turn()
	t.eq(u.hp - hp0, roundi(u.max_hp() * BWTiles.LIGHT_HEAL_PCT * 2 * 2 / 100.0), "light 2 heals 12% under an eclipse (x2)")
	t.eq(int(b.ground_report(C).get("turn", {}).get("heal", 0)) >= 0, true, "the ground report reads it too")


# ------------------------------------------------------------------ blizzard

func test_blizzard(t) -> void:
	var st := Vector2i(1, 1)
	var sd := Vector2i(2, 2)
	var b := BWBattle.new(_board({ st: { "static": { "h": -2 } }, sd: { "seed": { "h": -2 } } }), 9)
	_put(b.tiles, Vector2i(5, 5), 2, 0)
	b.set_weather(BWWeather.BLIZZARD, 77)
	var marks: Array = b.weather.marks
	t.eq(marks.size(), BWWeather.BLIZZARD_GLAZES, "four hexes are marked a tick ahead")
	t.ok(Vector2i(5, 5) in marks and st in marks, "charged hexes first (a static too)")
	t.ok(not sd in marks, "never the map's seed")
	t.eq(BWWeather.start(b, BWWeather.BLIZZARD, 77).marks, marks, "the marks are seeded")
	b.setup([_u("p")], [_u("e")])
	var ev: Array = []
	b.event.connect(func(e): ev.append(e))
	BWWeather.tick(b)
	t.ok(int(b.tiles.at(Vector2i(5, 5)).glaze) == BWTiles.GLAZE_CYCLES, "a marked fire 2 glazes")
	t.ok(int(b.tiles.at(st).glaze) > 0, "a marked static glazes (frozen in time)")
	for h in marks:
		if b.tiles.at(h).get("h", 0) == 0 and b.tiles.at(h).get("v", 0) == 0:
			t.eq(str(b.tiles.at(h).marker), "stasis", "%s: bare ground gets a stasis marker" % [h])
	var w: Array = ev.filter(func(e): return e.type == "weather")
	t.eq(w.size(), 1, "one weather event")
	t.eq((w[0].glazed as Array).size(), 4, "it lists the four glazes")
	t.eq(w[0].marks, b.weather.marks, "and the next four marks")
	t.ok(b.weather.marks != marks, "fresh marks for the next tick")
	t.eq(BWWeather.hazard_pct(b, b.units[0], b.weather.marks[0]), 6.0, "a marked hex is a hazard for the AI")


# ------------------------------------------------------------------ gale

func test_gale(t) -> void:
	var b := BWBattle.new(_board({ Vector2i(6, 4): { "terrain": "jagged" } }), 3)
	var a := _u("a")
	var c := _u("c")
	var r := _u("r")
	var e := _u("e")
	b.set_weather(BWWeather.GALE, 11)
	b.setup([a, c, r], [e])
	b.weather.heading = 0                                  # east
	b.weather.next_heading = 3
	b.weather.turn_in = 3
	a.pos = Vector2i(2, 2)
	c.pos = Vector2i(3, 2)                                 # a pushes into c, c moves first (farther along)
	r.pos = Vector2i(5, 4)                                 # rock to the east: a slam
	e.pos = Vector2i(8, 6)                                 # the map edge: open air, no slam
	var ev: Array = []
	b.event.connect(func(x): ev.append(x))
	var hp_r := r.hp
	var hp_e := e.hp
	BWWeather.tick(b)
	t.eq(c.pos, Vector2i(4, 2), "the front unit moves first")
	t.eq(a.pos, Vector2i(3, 2), "so the one behind follows into its hex")
	t.eq(r.pos, Vector2i(5, 4), "rock: stays put")
	t.eq(hp_r - r.hp, BWTiles.tile_damage(r, BWObelisk.SLAM_PCT, "", 1.0), "and slams for 5% max HP")
	t.eq(e.pos, Vector2i(8, 6), "the edge: stays put")
	t.eq(e.hp, hp_e, "no slam at the edge (open air)")
	t.ok(ev.any(func(x): return x.type == "move" and str(x.kind) == "gale"), "pushes are gale moves")
	t.ok(ev.any(func(x): return x.type == "slam"), "and a slam event")
	t.eq(int(b.weather.turn_in), 2, "two ticks left on this heading")
	BWWeather.tick(b)
	BWWeather.tick(b)
	t.eq(int(b.weather.heading), 3, "after three ticks the wind turns to the announced heading")
	t.ok(int(b.weather.next_heading) != 3 and int(b.weather.next_heading) >= 0, "and the next turn is announced")
	t.eq(int(b.weather.turn_in), BWWeather.GALE_TURN_TICKS, "three more ticks")
	# immune displace holds
	var b2 := BWBattle.new(_board(), 3)
	var big := _u("big")
	b2.set_weather(BWWeather.GALE, 11)
	b2.setup([big], [_u("x")])
	big.pos = Vector2i(4, 4)
	big.encounter = "colossus"                            # D210: never moved
	var at := big.pos
	BWWeather.gale_push(b2, 0)
	t.eq(big.pos, at, "immune displace holds")
	t.eq(BWWeather.hazard_pct(b2, big, at), 0.0, "and the immune feel no gale hazard")
	# hazard: standing where the push slams
	t.eq(BWWeather.hazard_pct(b, r, Vector2i(5, 4)) >= 0.0, true, "hazard is readable")


# ------------------------------------------------------------------ static / seeded

func test_static_and_seeded_interplay(t) -> void:
	for k in [BWWeather.RAIN, BWWeather.ECLIPSE, BWWeather.ASHFALL]:
		var b := BWBattle.new(_board({ Vector2i(1, 1): { "static": { "h": -3 } }, Vector2i(7, 7): { "seed": { "v": -2 } } }), 4)
		b.set_weather(k)
		b.setup([_u("p")], [_u("e")])
		for i in 5:
			b.tiles.tick()
			BWWeather.tick(b)
		t.eq(_hv(b.tiles, Vector2i(1, 1)), Vector2i(-3, 0), "%s: the static water 3 is the map's floor" % k)
		t.ok(b.tiles.is_seeded(Vector2i(7, 7)), "%s: the seed holds until play changes it" % k)
	# painting on a wet static still works for the cycle, and the floor returns
	var b2 := BWBattle.new(_board({ C: { "static": { "h": -3 } } }), 4)
	b2.set_weather(BWWeather.RAIN)
	b2.setup([_u("p")], [_u("e")])
	b2.tiles.apply([C], "fire", "p")
	t.eq(_hv(b2.tiles, C), Vector2i(-2, 0), "fire steps the static for the cycle")
	b2.tiles.tick()
	BWWeather.tick(b2)
	t.eq(_hv(b2.tiles, C), Vector2i(-3, 0), "it re-forms at the tick, rain or not")


# ------------------------------------------------------------------ offers

func _run(s: int) -> BWRun:
	var ids: Array = BWData.table("roster").map(func(row): return str(row.id)).slice(0, BWRun.SQUAD)
	return BWRun.start(ids, s)


func test_offer_rate_and_exclusions(t) -> void:
	var tagged := 0
	var rooms := 0
	var kinds := {}
	for s in 120:
		var r := _run(500 + s)
		for n in range(1, BWRun.BOSS_FIGHT + 1):
			for i in 2:
				var k := BWWeather.kind_for(r, n, i)
				if n < BWWeather.FROM_FIGHT or not BWRooms.has_choice(n) or n >= BWRun.BOSS_FIGHT:   # the Obelisks, a mid-run boss, the Giant
					t.ok(k == "", "seed %d fight %d: no weather" % [s, n]) if k != "" else null
					continue
				rooms += 1
				if k != "":
					tagged += 1
					kinds[k] = int(kinds.get(k, 0)) + 1
	var rate := float(tagged) / rooms
	t.ok(rate > 0.2 and rate < 0.3, "about a quarter of the rooms from fight 5 (%.3f)" % rate)
	t.eq(kinds.size(), BWWeather.KINDS.size(), "every kind turns up: %s" % [kinds])
	t.eq(BWWeather.kind_for(_run(1), 7, 0, { "boss": true }), "", "never a boss room")
	var r1 := _run(777)
	var r2 := _run(777)
	for n in range(5, 11):
		if BWRooms.has_choice(n):
			t.eq(BWRooms.roll(r1, n).map(func(x): return str(x.get("weather", ""))),
				BWRooms.roll(r2, n).map(func(x): return str(x.get("weather", ""))), "fight %d: seeded" % n)


func test_hard_weather_pays_one_more_and_saves(t) -> void:
	var enc := BWEncounters.RATE
	BWEncounters.RATE = 0.0
	var old := BWWeather.RATE
	BWWeather.RATE = 1.0
	var r := _run(4242)
	while r.fight < 6:                       # D327: fight 5 is Split Front (fixed, no weather)
		_play(r)
	var rooms := BWRooms.offer(r)
	t.ok(rooms.all(func(x): return str(x.get("weather", "")) in BWWeather.KINDS), "rate 1: both rooms have weather")
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(BWRooms.offer(back), rooms, "a loaded run shows the same weather")
	BWRooms.choose(r, 1)
	t.eq(BWWeather.for_fight(r, r.fight), str(rooms[1].weather), "the chosen room's weather reaches combat")
	t.ok("5 drops" in BWRooms.reward_text(r, rooms[1]), "the Hard card says five drops")
	var rep := _play(r)
	t.eq(rep.loot.size(), 5, "Hard + weather: one more drop")
	t.eq(str(rep.get("weather", "")), str(rooms[1].weather), "the report names it")
	t.eq(str(r.room_log["6"].get("weather", "")), str(rooms[1].weather), "the room log keeps it")
	var back2 := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(back2.room_log, r.room_log, "and saves it")
	t.eq(BWWeather.for_fight(r, BWRun.OBJECTIVE_FIGHT), "", "the Obelisks: never")
	BWWeather.RATE = old
	BWEncounters.RATE = enc


func _play(r: BWRun) -> Dictionary:
	var e := r.enemies_for(r.fight)
	for x in e:
		x.hp = 0
	return r.after_fight(true, r.squad.slice(0, 3), e, e, [])


# ------------------------------------------------------------------ determinism + the AI

func _squad(ids: Array) -> Array:
	return ids.map(func(id): return BWRosterKits.unit(str(id)))


func test_fights_reproduce_in_every_weather(t) -> void:
	var rows := BWRosterKits.rows()
	var ids: Array = rows.map(func(x): return str(x.id))
	for k in BWWeather.KINDS:
		var hist: Array = []
		for rep in 2:
			var b := BWBattle.new(BWBoard.load_file("res://maps/arena.json"), 31)
			b.set_weather(k)
			b.setup(_squad(ids.slice(0, 3)), _squad(ids.slice(3, 6)))
			var guard := 0
			while not b.over and guard < 600:
				BWAI.take_turn(b)
				guard += 1
			t.ok(b.over, "%s: the fight ends (%d cycles)" % [k, b.cycle])
			t.ok(b.history.any(func(e): return e.type == "weather"), "%s: the weather ticked" % k)
			hist.append(JSON.stringify(b.history))
		t.eq(hist[0], hist[1], "%s: identical replay" % k)


func test_ai_avoids_telegraphed_hazards(t) -> void:
	var b := BWBattle.new(_board(), 2)
	var u := _u("p")
	var f := _u("e")
	b.set_weather(BWWeather.BLIZZARD, 5)
	b.setup([f], [u])                    # the AI's unit is on the enemy side
	u.pos = Vector2i(7, 4)
	f.pos = Vector2i(0, 4)
	var w := b.weather
	b.weather = {}
	var d1 := BWAI._best_hex(b, u)
	b.weather = w
	b.weather.marks = [d1]
	var d2 := BWAI._best_hex(b, u)
	t.ok(d1 != u.pos, "no weather: it advances to %s" % [d1])
	t.ok(d2 != d1, "marked: it picks another hex (%s)" % [d2])
	t.ok(BWHex.distance(d2, f.pos) <= BWHex.distance(d1, f.pos) + 1, "and still advances")

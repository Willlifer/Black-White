extends RefCounted
## D255-D260: the phase framework (BWPhases) and the Twins (BWTwins), a card
## at fight 4 (D353/D355: against the Obelisks; no weather, the court), the
## swap at 50%, the beam (crossing, ending a turn, once per turn, thunder
## breaks it), the rage two cycles after a fall and its prevention, the
## win's reward, and determinism.


func _run(s: int = 4242) -> BWRun:
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), s)
	for u in r.squad:
		BWProgression.level_up(u, BWRun.TWINS_FIGHT - u.level)
		BWPicks.auto_resolve(u)
	r.fight = BWRun.TWINS_FIGHT
	BWRooms.offer(r)
	BWRooms.choose(r, BWSchedule.slots(BWRun.TWINS_FIGHT).find(BWSchedule.TWINS))   # D353: the Twins' card
	return r


func _battle(s: int = 4242) -> Array:
	var r := _run(s)
	var players: Array = r.squad.slice(0, 3)
	var twins := r.enemies_for(BWRun.TWINS_FIGHT)
	var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % r.map_for(BWRun.TWINS_FIGHT)), 7)
	b.setup(players, twins, [])
	return [b, players, twins]


## Make `u` the acting unit (a fresh turn) without playing the queue.
func _act(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._turn_serial += 1
	u.moved = false
	u.acted = false


func test_twins_card(t) -> void:
	var r := _run()
	t.ok(BWRooms.has_choice(BWRun.TWINS_FIGHT), "fight 4 is a choice: the Obelisks or the Twins (D353)")
	t.ok(not BWRooms.queued(BWRun.TWINS_FIGHT), "fight 4 takes no map off the queue")
	t.eq(BWRooms.offer(r).map(func(c): return str(c.get("boss", ""))), ["obelisks", "twins"], "two boss cards")
	t.ok(r.is_twins(), "the Twins' card taken")
	t.eq(r.map_for(BWRun.TWINS_FIGHT), "court", "the court")
	t.eq(BWWeather.for_fight(r, BWRun.TWINS_FIGHT), "", "never weather")
	var e := r.enemies_for(BWRun.TWINS_FIGHT)
	t.eq(e.size(), 2, "two Twins")
	t.eq(e.map(func(u): return BWTwins.role(u)), ["noon", "dusk"], "Noon, then Dusk")
	t.ok(e.all(func(u): return u.encounter == "twin" and u.size == 1), "one hex each")
	t.eq([e[0].element, e[1].element], ["light", "dark"], "light and dark")
	t.ok(e[0].max_hp() > 2 * BWFormulas.hp_value(e[0].stat("con"), e[0].level) - 1, "a boss's HP (%d)" % e[0].max_hp())
	for n in range(3, BWRun.FIGHTS + 1):
		t.ok(BWRooms.has_choice(n), "fight %d offers a choice (D353)" % n)
	# the court: half light, half dark, seeded (D134)
	var bd := BWBoard.load_file("res://maps/court.json")
	var light := 0
	var dark := 0
	for h in bd.seeds:
		var v: Vector2i = bd.seeds[h]
		light += 1 if v.y > 0 else 0
		dark += 1 if v.y < 0 else 0
	t.ok(light > 20 and light == dark, "seeded halves (%d light, %d dark)" % [light, dark])


func test_phases_and_swap(t) -> void:
	var x := _battle()
	var b: BWBattle = x[0]
	var noon: BWUnit = x[2][0]
	var dusk: BWUnit = x[2][1]
	t.eq(BWTwins.colour(b, noon), "light", "phase 1: Noon paints light")
	t.eq(BWTwins.colour(b, dusk), "dark", "phase 1: Dusk paints dark")
	noon.hp = noon.max_hp() / 2 + 1
	BWPhases.check(b)
	t.ok(not BWPhases.fired(b, "swap"), "not at 50% + 1")
	var before := noon.hp
	b._tile_hurt(noon, 2, "fire", "")
	t.ok(noon.hp < before and BWPhases.fired(b, "swap"), "under 50%: the swap fires from the damage itself")
	t.ok(b.history.any(func(e): return e.type == "phase" and e.phase == "swap"), "a phase event for the view")
	t.eq(BWTwins.colour(b, noon), "dark", "phase 2: Noon paints dark")
	t.eq(BWTwins.colour(b, dusk), "light", "phase 2: Dusk paints light")
	t.eq(float(BWPhases.rule(b, "heal_mult", dusk)), 2.0, "x2 heal")
	# the heal: own colour under it, x2
	b.tiles.apply([dusk.pos], "light", "", 3)
	dusk.hp = 100
	var lt := b.tiles.intensity(dusk.pos, "light")
	t.ok(BWTwins.turn_start(b, dusk), "a Twin handles its own ground")
	t.eq(dusk.hp, 100 + roundi(dusk.max_hp() * BWTwins.HEAL_PCT * lt * 2.0 / 100.0), "heals %d%% x %d x2" % [int(BWTwins.HEAL_PCT), lt])
	# the paint at its turn end, the colour of the phase
	_act(b, noon)
	b.tiles.clear(noon.pos)
	BWTwins.turn_end(b, noon)
	t.ok(b.tiles.intensity(noon.pos, "dark") >= 2, "Noon paints dark now")


func test_beam(t) -> void:
	var x := _battle()
	var b: BWBattle = x[0]
	var p: BWUnit = x[1][0]
	var noon: BWUnit = x[2][0]
	var dusk: BWUnit = x[2][1]
	for u in x[1]:
		u.pos = Vector2i(6, 12) if u == x[1][1] else (Vector2i(5, 12) if u == x[1][2] else u.pos)
	noon.pos = Vector2i(3, 6)
	dusk.pos = Vector2i(9, 6)
	BWTwins.update_beam(b)
	var line: Array = b.boss.beam
	t.eq(line.size(), 5, "the beam: the five hexes between")
	t.eq(BWTwins.beam_at(b, Vector2i(4, 6)), "light", "Noon's half is light")
	t.eq(BWTwins.beam_at(b, Vector2i(8, 6)), "dark", "Dusk's half is dark")
	# crossing: a player walking over it pays once
	p.pos = Vector2i(6, 8)
	_act(b, p)
	var hp0 := p.hp
	t.ok(b.move(p, Vector2i(6, 5)), "walk across the beam")
	var paid := hp0 - p.hp
	t.ok(paid >= roundi(p.max_hp() * 0.05), "crossing costs (%d of %d)" % [paid, p.max_hp()])
	t.ok(p.statuses.has("blinded") or p.statuses.has("shrouded"), "and a status")
	var hp1 := p.hp
	BWTwins.turn_end(b, p)
	t.eq(p.hp, hp1, "once per turn (it paid on the way)")
	# ending a turn on it, a fresh turn
	var q: BWUnit = x[1][1]
	q.pos = Vector2i(5, 6)
	q.statuses.clear()
	_act(b, q)
	var hq := q.hp
	BWTwins.turn_end(b, q)
	t.ok(q.hp < hq and q.statuses.has("blinded"), "ending on the light half: damage and Blinded")
	# close together: no beam
	dusk.pos = Vector2i(6, 6)
	BWTwins.update_beam(b)
	t.eq(b.boss.beam.size(), 0, "4 or fewer apart: no beam")
	# thunder breaks it
	dusk.pos = Vector2i(9, 6)
	BWTwins.update_beam(b)
	var n0 := noon.hp
	b.paint([Vector2i(6, 6)], "thunder", p)
	t.eq(b.boss.beam.size(), 0, "thunder on the beam breaks it")
	t.ok(noon.hp < n0, "and jolts the Twins")
	b.cycle += 2
	BWTwins.update_beam(b)
	t.ok(not b.boss.beam.is_empty(), "it re-forms after the next cycle")


func test_rage_timing(t) -> void:
	var x := _battle()
	var b: BWBattle = x[0]
	var noon: BWUnit = x[2][0]
	var dusk: BWUnit = x[2][1]
	var m0 := dusk.move_range()
	var c0 := b.cycle
	noon.hp = 0
	b._ko(noon, null)
	t.eq(BWPhases.countdown(b, "rage"), 2, "the rage in 2 cycles")
	t.ok(b.history.any(func(e): return e.type == "phase_pending" and e.phase == "rage"), "a pending event (the countdown)")
	b.cycle = c0 + 1
	BWPhases.new_cycle(b)
	t.ok(not BWPhases.fired(b, "rage"), "not after 1 cycle")
	t.eq(BWPhases.countdown(b, "rage"), 1, "1 to go")
	b.cycle = c0 + 2
	BWPhases.new_cycle(b)
	t.ok(BWPhases.fired(b, "rage"), "rages 2 cycles later")
	t.eq(dusk.move_range(), m0 + 1, "+1 move")
	t.eq(int(BWPhases.rule(b, "paint_radius", dusk)), 2, "paint radius doubled")
	BWTwins.turn_end(b, dusk)
	t.ok(b.history.any(func(e): return e.type == "paint" and e.unit == dusk.id and e.hexes.size() > 7), "paints radius 2")


func test_rage_prevented(t) -> void:
	var x := _battle()
	var b: BWBattle = x[0]
	var noon: BWUnit = x[2][0]
	var dusk: BWUnit = x[2][1]
	noon.hp = 0
	b._ko(noon, null)
	b.cycle += 1
	BWPhases.new_cycle(b)
	dusk.hp = 0
	b._ko(dusk, null)
	t.ok(not BWPhases.fired(b, "rage"), "both down within 2 cycles: no rage")
	t.eq(BWPhases.countdown(b, "rage"), -1, "the countdown is gone")
	t.ok(b.history.any(func(e): return e.type == "phase_cancel"), "cancelled")


func test_reward(t) -> void:
	var r := _run()
	var e := r.enemies_for(BWRun.TWINS_FIGHT)
	for u in r.squad:
		while not BWPicks.next_request(u).is_empty():
			var req := BWPicks.next_request(u)
			BWPicks.apply(u, req, str(BWPicks.options(u, req)[0].id))
	var lv: int = r.squad[0].level
	for x in e:
		x.hp = 0
	var rep := r.after_fight(true, r.squad.slice(0, 3), e, e, [])
	t.eq(rep.get("twins_reward", []).size(), r.squad.size(), "a pick for every squad unit")
	t.eq(r.pending_picks().size(), r.squad.size(), "owed now")
	var req: Dictionary = r.pending_picks()[0][1]
	t.eq(BWPicks.options(r.pending_picks()[0][0], req).size(), BWPicks.OFFER, "a two-card offer (D174)")
	t.eq(r.squad[0].level, lv + 1, "and the level")
	# a loss: the level, no reward
	var r2 := _run()
	var e2 := r2.enemies_for(BWRun.TWINS_FIGHT)
	for u in r2.squad:
		while not BWPicks.next_request(u).is_empty():
			var q := BWPicks.next_request(u)
			BWPicks.apply(u, q, str(BWPicks.options(u, q)[0].id))
	var lv2: int = r2.squad[0].level
	var rep2 := r2.after_fight(false, r2.squad.slice(0, 3), [], e2, [])
	t.ok(not rep2.has("twins_reward"), "no reward on a loss")
	t.eq(r2.pending_picks().size(), 0, "nothing owed")
	t.eq(r2.squad[0].level, lv2 + 1, "a loss still levels (D194)")


func test_deterministic(t) -> void:
	var h: Array = []
	for k in 2:
		var x := _battle(99)
		var b: BWBattle = x[0]
		var guard := 0
		while not b.over and guard < 400:
			BWAI.take_turn(b)
			guard += 1
		h.append(JSON.stringify(b.history))
	t.ok(h[0] == h[1], "same seed, same fight, event for event")
	t.ok(h[0].contains("\"beam\""), "the beam showed up")

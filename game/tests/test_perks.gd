extends RefCounted
## D93: the element perks (data/perks.csv, design/ELEMENTS.md §12), one
## test each, asserted on the number or the rule they change. D281 re-cut
## them to 28 (4 per element); merged perks are tested through their new home.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}, perks: Array = []) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	var u := BWUnit.from_roster(row)
	for p in perks:
		var pel := str(BWPicks.perk(p).element)
		if u.affinity_rank(pel) < 1:
			u.affinity[pel] = 10
		u.perks.append(p)
	return u


func _foe(id: String = "f", extra: Dictionary = {}, perks: Array = []) -> BWUnit:
	var x := { "con": 300 }
	x.merge(extra, true)
	return _u(id, "axe", "water", x, perks)


## Both sides placed, facing unknown (D96 has its own test), statuses and
## history cleared. No turn is given: call _turn.
func _fight(players: Array, foes: Array, ppos: Array, fpos: Array, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1
		u.statuses = {}
		u.fx = {}
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _mod(fc: Dictionary, label_start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(label_start):
			return m
	return {}


# ------------------------------------------------------------------ water

func test_waterwalking(t) -> void:
	var me := _u("me", "sword", "water", {}, ["water_walk"])
	var plain := _u("p", "sword", "water")
	var b := _fight([me, plain], [_foe()], [C, Vector2i(4, 8)], [Vector2i(10, 10)])
	b.tiles.apply([E], "water", "x", 3)
	b.tiles.apply([Vector2i(5, 8)], "water", "x", 3)
	_turn(b, me)
	t.eq(int(b.reachable(me)[E].cost), 0, "entering water 3 costs 0")
	_turn(b, plain)
	t.eq(int(b.reachable(plain)[Vector2i(5, 8)].cost), 3, "without it: 1 + 2")


func test_tidal_guard_covers_allies(t) -> void:
	var me := _u("me", "sword", "water", {}, ["water_guard"])      # D281: Flow State joined Tidal Guard
	var mate := _u("m", "sword", "fire")
	var foe := _foe()
	var b := _fight([me, mate], [foe], [C, Vector2i(4, 8)], [Vector2i(5, 8)])
	b.tiles.apply([Vector2i(4, 8)], "water", "x", 2)
	var m := _mod(b.forecast_basic(foe, mate), "Tidal Guard")
	t.eq(float(m.get("value", 0)), 30.0, "an ally in water 2: +30 glance")
	t.eq(str(m.get("stage", "")), "glance", "a glance term")


func test_current_push(t) -> void:
	var me := _u("me", "sword", "water", {}, ["water_push"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	t.ok(_mod(b.forecast_basic(me, foe), "Current Push (").is_empty(), "not from dry ground")
	b.tiles.apply([C], "water", "x", 2)
	t.near(float(_mod(b.forecast_basic(me, foe), "Current Push (").get("value", 0)), 1.16, 0.001, "from water 2: +16% (D281: 8 per level)")
	t.ok(me.effects.any(func(e): return e.key == "attack_mod" and e.name == "Current Push"), "Tidewalker folded in (D281)")


func test_current_push_moves_along_water(t) -> void:
	var pushed := false
	for sd in range(1, 20):
		var me := _u("me", "sword", "water", { "dex": 100 }, ["water_push"])
		var foe := _foe()
		var b := _fight([me], [foe], [C], [E], sd)
		b.tiles.apply([E, Vector2i(6, 4)], "water", "x", 1)
		_turn(b, me)
		if b.attack(me, foe).hit:
			t.eq(foe.pos, Vector2i(6, 4), "pushed 1 along the water, away from me")
			pushed = true
			break
	t.ok(pushed, "a hit landed")


func test_tidal_guard(t) -> void:
	var me := _u("me", "sword", "water", {}, ["water_guard"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([C], "water", "x", 3)
	var fc := b.forecast_basic(foe, me)
	t.eq(float(_mod(fc, "Tidal Guard").get("value", 0)), 45.0, "water 3: +45 glance")
	t.near(fc.glance.value, 10.0 + 4.0 + 45.0, 0.001, "on the glance line")


func test_undertow(t) -> void:
	var me := _u("me", "staff", "fire")             # D359: a move-4 class (the sword is 5)
	var holder := _foe("h", {}, ["water_undertow"])
	var b := _fight([me], [holder], [C], [Vector2i(10, 10)])
	_turn(b, me)
	t.ok(not b.reachable(me).has(Vector2i(9, 4)), "no water 3: plain move 4")
	b.tiles.apply([Vector2i(10, 4)], "water", "x", 3)
	var r := b.reachable(me)
	t.ok(r[Vector2i(9, 4)].stop, "toward the pool: +1 move (5 hexes)")
	t.ok(r[Vector2i(1, 4)].stop, "away, 3 hexes: allowed")
	t.ok(not r[Vector2i(0, 4)].stop, "away, 4 hexes: -1 move")
	t.ok(not b.can_move_to(me, Vector2i(0, 4)), "and not a legal click (the overlay uses the same reach)")
	holder.hp = 0
	t.ok(not b.reachable(me).has(Vector2i(9, 4)), "the holder down: no pull")


# ------------------------------------------------------------------ fire

func test_heat_rush(t) -> void:
	var me := _u("me", "sword", "fire", {}, ["fire_rush"])
	var b := _fight([me], [_foe()], [C], [Vector2i(10, 10)])
	b.tiles.apply([E], "fire", "x", 2)
	_turn(b, me)
	t.ok(b.reachable(me)[Vector2i(9, 4)].stop, "the first fire hex gives +1 move")
	t.ok(b.move(me, Vector2i(9, 4)), "moved 5")
	t.ok(_ev(b, "tile_damage").filter(func(e): return e.cause == "fire_cross").is_empty(), "no crossing damage")
	t.ok(me.fx.get("heat_rush_used", false), "spent for the turn")


func test_ember_skin(t) -> void:
	var me := _u("me", "sword", "fire", {}, ["fire_skin"])
	var foe := _foe("f", { "dex": 100 })
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([C], "fire", "x", 2)
	_turn(b, me)
	var st := _ev(b, "tile_damage").filter(func(e): return e.cause == "fire" and e.unit == "me")
	t.eq(int(st[0].amount), BWTiles.tile_damage(me, 8.0, "fire", 0.5), "own standing fire halved")
	t.ok(b.forecast_basic(foe, me).notes.any(func(n): return str(n).begins_with("Ember Skin")), "the attacker's forecast warns")
	var burned := false
	for sd in range(1, 10):
		var b2 := _fight([me], [foe], [C], [E], sd)
		b2.tiles.apply([C], "fire", "x", 2)
		_turn(b2, foe)
		var res := b2.attack(foe, me)
		if res.hit:
			var back := _ev(b2, "tile_damage").filter(func(e): return e.cause == "ember_skin")
			t.eq(back.size(), 1, "the hitter burns")
			t.eq(int(back[0].amount), BWTiles.tile_damage(foe, 4.0, "fire"), "fire 2: 4%")
			burned = true
			break
	t.ok(burned, "a hit landed")


func test_kindling(t) -> void:
	var me := _u("me", "sword", "fire", {}, ["fire_kindling"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([E], "fire", "x", 3)
	b.tiles.apply([C], "fire", "x", 1)
	var m := _mod(b.forecast_basic(me, foe), "Kindling")
	t.near(float(m.get("value", 0)), 1.18, 0.001, "the higher level counts: the target's fire 3 (D281: 6 per level)")
	t.ok(str(m.label).contains("target on Fire 3"), "named")
	b.tiles.clear(E)
	t.near(float(_mod(b.forecast_basic(me, foe), "Kindling").get("value", 0)), 1.06, 0.001, "or your own fire 1")


func test_wildfire(t) -> void:
	var me := _u("me", "staff", "fire", {}, ["fire_wild"])
	var plain := _u("p", "staff", "fire")
	var b := _fight([me, plain], [_foe()], [C, Vector2i(0, 8)], [Vector2i(10, 10)])
	b.paint([E], "fire", me, 2)
	b.paint([Vector2i(2, 8)], "fire", plain, 2)
	b.tiles.tick()
	var lit := BWHex.neighbors(E).filter(func(h): return b.tiles.intensity(h, "fire") == 1)
	t.eq(lit.size(), 6, "neutral neighbours seeded with fire 1")
	t.ok(BWHex.neighbors(Vector2i(2, 8)).all(func(h): return b.tiles.intensity(h, "fire") == 0), "without it: no spread off grass")
	t.eq(str(b.tiles.at(E).origin), "spread", "once per cast")
	b.tiles.tick()
	var two := BWHex.area(E, 2).filter(func(h): return BWHex.distance(h, E) == 2 and b.tiles.intensity(h, "fire") > 0)
	t.eq(two.size(), 0, "seeds never seed")


func test_heat_rush_moves_allies_on_fire(t) -> void:
	var me := _u("me", "sword", "fire", {}, ["fire_rush"])         # D281: Coal Engine joined Heat Rush
	var mate := _u("m", "sword", "water")
	var b := _fight([me, mate], [_foe()], [C, Vector2i(8, 8)], [Vector2i(10, 0)])
	b.tiles.apply([Vector2i(8, 8)], "fire", "x", 2)
	_turn(b, mate)
	t.eq(mate.move_range(), 5 + 2, "an ally starting on fire 2: +2 move (sword 5)")
	t.ok(mate.move_notes().any(func(n): return str(n[0]).begins_with("Heat Rush")), "named on the Move hover")


# ------------------------------------------------------------------ ice

func test_skate(t) -> void:
	var me := _u("me", "sword", "ice", {}, ["ice_skate"])
	var b := _fight([me], [_foe()], [C], [Vector2i(10, 10)])
	b.board.set_cell(E, "muddy")
	b.tiles.apply([E], "water", "x")
	b.tiles.apply([E], "ice", "x")
	t.eq(b.board.step_cost(C, E), 2, "glazed mud costs 2 normally")
	b.tiles.apply([C], "ice", "x")                     # a stasis marker under me
	_turn(b, me)
	t.eq(int(b.reachable(me)[E].cost), 1, "glazed: 1, even on mud")
	t.eq(me.move_range(), 6, "+1 move starting on stasis")


func test_rime_armour(t) -> void:
	var me := _u("me", "sword", "ice", {}, ["ice_rime"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([C], "water", "x")
	b.tiles.apply([C], "ice", me.id)
	var fc := b.forecast_basic(foe, me)
	t.near(float(_mod(fc, "Shatter").get("value", 0)), 1.0, 0.001, "Shatter doesn't apply")
	t.near(float(_mod(fc, "Rime Armour (").get("value", 0)), 0.95, 0.001, "-5% per glaze level on my glaze (D281, Permafrost folded in)")
	t.eq(BWPerkRules.slam_pct(b, me, foe.id, 8.0, false), 0.0, "no slam damage on glaze")


func test_fault_lines(t) -> void:
	var done := false
	for sd in range(1, 12):
		var me := _u("me", "sword", "ice", { "dex": 100 }, ["ice_fault"])
		var foe := _foe()
		var b := _fight([me], [foe], [C], [E], sd)
		b.tiles.apply([E], "water", "x")
		b.tiles.apply([E], "ice", "x")
		_turn(b, me)
		t.near(float(_mod(b.forecast_basic(me, foe), "Shatter").get("value", 0)), 1.30, 0.001, "Shatter doubled: +30%")
		t.eq(BWPerkRules.slam_pct(b, foe, me.id, 8.0, false), 16.0, "slams I cause: +8%")
		var res := b.attack(me, foe)
		if res.hit:
			t.ok(b.tiles.is_glazed(E), "D281: the hit no longer breaks the glaze")
			done = true
			break
	t.ok(done, "a hit landed")


func test_frostbite(t) -> void:
	var me := _u("me", "staff", "ice", {}, ["ice_frostbite"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([E], "water", "x")
	b.tiles.apply([E], "ice", me.id)
	_turn(b, foe)
	t.ok(foe.statuses.has("drenched"), "a foe starting on my glaze is Drenched")
	t.eq(foe.move_range(), 3, "-1 move this turn")


func test_frost_ward(t) -> void:
	var me := _u("me", "sword", "ice")                  # D282: Frost Ward is the Ice set's 3-piece now
	for slot in ["head", "chest", "legs"]:
		me.equipment[slot] = { "uid": "ice_" + slot, "slot": slot, "base": "", "enchant": "glacial", "tier": "E", "stats": {} }
	var mate := _u("m", "sword", "fire")
	var b := _fight([me, mate], [_foe()], [C, Vector2i(4, 6)], [Vector2i(10, 10)])
	_turn(b, me)
	t.ok(mate.statuses.has("frost_ward"), "the nearest ally within 2 is warded")
	t.ok(not me.statuses.has("frost_ward"), "not me while an ally can take it")
	b.tiles.apply([mate.pos], "fire", "x", 2)
	_turn(b, mate)
	t.ok(_ev(b, "tile_damage").filter(func(e): return e.unit == "m").is_empty(), "the ward negated the fire")
	t.eq(str(_ev(b, "ward_break")[0].source), "frost_ward", "named")


# ------------------------------------------------------------------ thunder

func test_bolt_step(t) -> void:
	var me := _u("me", "staff", "thunder", {}, ["thunder_step"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([E], "fire", "x")
	_turn(b, me)
	b.attack(me, foe)
	t.eq(_ev(b, "detonate").size(), 1, "the channel detonated the fire")
	t.eq(me.move_range(), 4 + 2, "move 2 more")


func test_grounded(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var f := _foe("f")
	var g := _foe("g", {}, ["thunder_rod"])               # D281: Grounded joined Lightning Rod
	var ok := false
	for sd in range(1, 12):
		for u in [me, f, g]:
			u.hp = u.max_hp()
		var b := _fight([me], [f, g], [C], [E, Vector2i(7, 4)], sd)
		b.tiles.apply([E], "thunder", "x")
		_turn(b, me)
		var res := b.attack(me, f)
		if res.hit and int(res.damage) > 0:
			var ch := _ev(b, "chain")
			t.eq(int(ch[0].amount), BWTiles.tile_damage(g, 100.0 * 0.25 * int(res.damage) / g.max_hp(), "thunder"), "the arc on me: half")
			ok = true
			break
	t.ok(ok, "an arc happened")


func test_overcharge(t) -> void:
	var ok := false
	for sd in range(1, 12):
		var me := _u("me", "sword", "thunder", { "dex": 100 }, ["thunder_overcharge"])
		var f := _foe("f")
		var t1 := _foe("t1")
		var t2 := _foe("t2")
		var b := _fight([me], [f, t1, t2], [C], [E, Vector2i(7, 4), Vector2i(9, 4)], sd)
		b.tiles.apply([E], "thunder", "x")
		_turn(b, me)
		var res := b.attack(me, f)
		if not res.hit:
			continue
		var ch := _ev(b, "chain")
		t.eq(ch.map(func(e): return e.to), ["t1", "t2"], "a second arc to the next-nearest")
		t.eq(str(ch[1].get("kind", "")), "overcharge", "marked")
		t.eq(int(ch[1].amount), BWTiles.tile_damage(t2, 100.0 * 0.5 * int(ch[0].amount) / t2.max_hp(), "thunder"), "at 50% of the first")
		ok = true
		break
	t.ok(ok, "an arc happened")


func test_static_field(t) -> void:
	var me := _u("me", "staff", "thunder", {}, ["thunder_static"])
	var foe := _foe()
	var H := Vector2i(6, 4)
	var b := _fight([me], [foe], [C], [Vector2i(8, 4)])
	b.paint([H], "thunder", me)
	t.eq(int(b.tiles.at(H).timer), 5, "my fuse lasts 5 cycles")
	_turn(b, foe)
	t.ok(b.move(foe, H), "a foe walks onto it")
	t.ok(foe.statuses.has("staggered"), "Staggered")
	t.eq(b.skills_for(foe), [], "so no skills")


func test_lightning_rod(t) -> void:
	var ok := false
	for sd in range(1, 12):
		var me := _u("me", "sword", "fire", { "dex": 100 })
		var f := _foe("f")
		var w := _foe("w")
		var rod := _foe("r", {}, ["thunder_rod"])
		var b := _fight([me], [f, w, rod], [C], [E, Vector2i(7, 4), Vector2i(9, 4)], sd)
		b.tiles.apply([E], "thunder", "x")
		_turn(b, me)
		var res := b.attack(me, f)
		if not res.hit:
			continue
		var ch := _ev(b, "chain")
		t.eq(str(ch[0].to), "r", "the rod takes the arc")
		t.eq(str(ch[0].meant), "w", "meant for the ally within 3")
		t.eq(int(ch[0].amount), BWTiles.tile_damage(rod, 100.0 * 0.25 * int(res.damage) / rod.max_hp(), "thunder"), "at 50%")
		ok = true
		break
	t.ok(ok, "an arc happened")


# ------------------------------------------------------------------ wind

func test_tailwind(t) -> void:
	var me := _u("me", "staff", "wind", {}, ["wind_tail"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([C], "wind", "x")
	_turn(b, me)
	t.eq(me.move_range(), 6, "+2 starting on a gale")
	b.attack(me, foe)                                   # the staff channels wind
	t.eq(me.move_range(), 7, "a wind action: +1 more")


func test_eye_of_the_storm(t) -> void:
	var me := _u("me", "sword", "wind", {}, ["wind_eye"])
	var archer := _u("a", "bow", "fire")
	var sword := _foe("s")
	var b := _fight([me], [archer, sword], [C], [Vector2i(8, 4), E])
	t.ok(not b._displace(me, 0, 1, "push"), "immune to displacement")
	t.eq(_ev(b, "displace_resisted").size(), 1, "resisted")
	var fc := b.forecast_basic(archer, me)
	t.ok(_mod(fc, "Eye of the Storm (missile): -").is_empty(), "D281: no -hit any more")
	t.eq(float(_mod(fc, "Eye of the Storm (missile): can't crit").get("value", -1)), 0.0, "arrows can't crit")
	t.eq(fc.crit.value, 0.0, "on the crit line")
	t.ok(_mod(b.forecast_basic(sword, me), "Eye of the Storm").is_empty(), "a sword: nothing")


func test_gale_force(t) -> void:
	var me := _u("me", "sword", "wind", {}, ["wind_force"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [Vector2i(8, 4)])
	_turn(b, me)
	b.move(me, Vector2i(7, 4))
	t.near(float(_mod(b.forecast_basic(me, foe), "Gale Force").get("value", 0)), 1.15, 0.001, "3 hexes: +15%")
	me.fx["moved_hexes"] = 6
	t.near(float(_mod(b.forecast_basic(me, foe), "Gale Force").get("value", 0)), 1.20, 0.001, "capped at +20%")


func test_gust(t) -> void:
	var pushed := false
	var slammed := false
	for sd in range(1, 20):
		for blocked in [false, true]:
			var me := _u("me", "sword", "wind", { "dex": 100 }, ["wind_force"])
			var foe := _foe()
			var b := _fight([me], [foe], [C], [E], sd)
			if blocked:
				b.board.set_cell(Vector2i(6, 4), "jagged")
			_turn(b, me)
			var ev := b.use_skill(me, "striketwice", "wind", E)
			var r: Dictionary = ev.results[0].result
			if not (r.hit and r.secondary):
				continue
			if not blocked:
				t.eq(foe.pos, Vector2i(6, 4), "pushed 1 away")
				pushed = true
			else:
				var sl := _ev(b, "tile_damage").filter(func(e): return e.cause == "slam")
				t.eq(foe.pos, E, "blocked: stays")
				t.eq(int(sl[0].amount), BWTiles.tile_damage(foe, 8.0, ""), "slams for 8%")
				slammed = true
		if pushed and slammed:
			break
	t.ok(pushed and slammed, "both cases seen")


func test_slipstream(t) -> void:
	var me := _u("me", "sword", "wind", {}, ["wind_tail"])          # D281: Slipstream joined Tailwind
	var near := _u("n", "sword", "fire")
	var far := _u("x", "sword", "fire")
	var b := _fight([me, near, far], [_foe()], [C, Vector2i(4, 6), Vector2i(4, 9)], [Vector2i(10, 10)])
	_turn(b, near)
	t.eq(near.move_range(), 6, "an ally within 2: +1")
	_turn(b, far)
	t.eq(far.move_range(), 5, "farther: nothing")
	_turn(b, me)
	t.eq(me.move_range(), 5, "not the holder (sword 5)")


# ------------------------------------------------------------------ dark

func test_shadowstep(t) -> void:
	var me := _u("me", "sword", "dark", {}, ["dark_step"])
	var b := _fight([me], [_foe()], [C], [Vector2i(10, 10)])
	var to := Vector2i(7, 4)
	for h in [Vector2i(5, 4), Vector2i(6, 4)]:
		b.board.set_cell(h, "muddy")
	b.tiles.apply([C, to], "dark", "x")
	_turn(b, me)
	var r := b.reachable(me)
	t.eq(int(r[to].cost), 1, "dark to dark within 3 in sight: 1 move")
	t.eq(BWBoard.path_to(r, to).size(), 2, "the path is one jump")
	t.ok(b.move(me, to), "stepped")
	t.ok(_ev(b, "move")[0].has("shadowstep"), "the move says so")
	t.ok(me.fx.get("shadowstep_used", false), "once per turn")
	var me2 := _u("me2", "sword", "dark", {}, ["dark_step"])
	var b2 := _fight([me2], [_foe()], [C], [Vector2i(10, 10)])
	for h in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 3), Vector2i(5, 5), Vector2i(6, 3), Vector2i(6, 5)]:
		b2.board.set_cell(h, "jagged")
	b2.tiles.apply([C, to], "dark", "x")
	_turn(b2, me2)
	t.ok(not b2.reachable(me2).has(to), "D281: not through a rock wall (needs sight)")


func test_nightborn(t) -> void:
	var me := _u("me", "sword", "dark", {}, ["dark_night"])
	var b := _fight([me], [_foe()], [C], [Vector2i(10, 10)])
	b.tiles.apply([C], "dark", "x", 3)
	_turn(b, me)
	t.ok(_ev(b, "tile_damage").is_empty(), "no dark 3 drain")
	var hp := me.hp
	b._tile_hurt(me, 10, "fire", "")
	t.eq(me.hp, hp, "the first elemental effect this turn is negated")
	t.eq(str(_ev(b, "ward_break")[0].source), "nightborn", "ward_break, source nightborn")
	b._tile_hurt(me, 10, "fire", "")
	t.eq(me.hp, hp - 10, "the second lands")
	_turn(b, me)
	hp = me.hp
	b._tile_hurt(me, 10, "fire", "")
	t.eq(me.hp, hp, "next turn: negated again")


func test_ambush(t) -> void:
	var me := _u("me", "sword", "dark", {}, ["dark_ambush"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	b.tiles.apply([C], "dark", "x", 2)
	var fc := b.forecast_basic(me, foe)
	t.eq(float(_mod(fc, "Ambush (").get("value", 0)), 12.0, "from dark 2: +12 crit (D281: 6 per level)")
	t.near(fc.crit.value, 0.4 + 12.0, 0.001, "on the crit line")
	t.ok(fc.mods.any(func(m): return str(m.stage) == "crit_mult" and str(m.label).begins_with("Ambush")), "Nightfall folded in: crit multiplier")


## Pall: the first seed whose basic attack on a foe standing on dark `lvl` lands.
func _pall(lvl: int) -> BWUnit:
	for sd in range(1, 21):
		var me := _u("me", "sword", "dark", { "dex": 100 }, ["dark_pall"])
		var foe := _foe()
		var b := _fight([me], [foe], [C], [E], sd)
		b.tiles.apply([E], "dark", "x", lvl)
		_turn(b, me)
		if b.attack(me, foe).hit:
			return foe
	return null


func test_pall(t) -> void:
	var f2 := _pall(2)
	t.ok(f2 != null and f2.statuses.has("blinded"), "a foe hit on dark 2 is Blinded")
	var f1 := _pall(1)
	t.ok(f1 != null and not f1.statuses.has("blinded"), "dark 1: no")


func test_nightborn_covers_adjacent_allies(t) -> void:
	var me := _u("me", "sword", "dark", {}, ["dark_night"])          # D281: Cover of Night joined Nightborn (no -hit)
	var mate := _u("m", "sword", "fire")
	var b := _fight([me, mate], [_foe()], [C, Vector2i(4, 5)], [Vector2i(10, 10)])
	b.tiles.apply([mate.pos], "dark", "x", 1)
	_turn(b, mate)
	var hp := mate.hp
	b._tile_hurt(mate, 10, "fire", "")
	t.eq(mate.hp, hp, "an adjacent ally on dark: its first elemental effect is negated")
	t.ok(_mod(b.forecast_basic(_foe("z"), mate), "Cover of Night").is_empty(), "no -hit any more")


# ------------------------------------------------------------------ light

func test_sunpath(t) -> void:
	var me := _u("me", "sword", "light", {}, ["light_sun"])
	var b := _fight([me], [_foe()], [C], [Vector2i(10, 10)])
	b.tiles.apply([C], "light", "x")
	_turn(b, me)
	t.eq(me.move_range(), 6, "light 1: +1")
	b.tiles.apply([C], "light", "x", 2)
	_turn(b, me)
	t.eq(me.move_range(), 7, "light 3: +2")


func test_radiant_guard(t) -> void:
	var me := _u("me", "sword", "light", {}, ["light_sanct"])        # D281: Radiant Guard joined Sanctuary
	var plain := _u("p", "sword", "light")
	var foe := _foe()
	var b := _fight([me, plain], [foe], [C, Vector2i(4, 8)], [E])
	b.tiles.apply([C, Vector2i(4, 8)], "light", "x", 2)
	t.eq(float(_mod(b.forecast_basic(foe, me), "Target on Light 2").get("value", -1)), 0.0, "light's +14 ignored on me")
	t.eq(float(_mod(b.forecast_basic(foe, plain), "Target on Light 2").get("value", -1)), 0.0, "and on my allies")
	var b2 := _fight([plain], [foe], [Vector2i(4, 8)], [E])
	b2.tiles.apply([Vector2i(4, 8)], "light", "x", 2)
	t.eq(float(_mod(b2.forecast_basic(foe, plain), "Target on Light 2").get("value", -1)), 14.0, "without a Sanctuary holder: +14")


func test_judgement(t) -> void:
	var me := _u("me", "sword", "light", {}, ["light_judge"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	t.ok(b.forecast_basic(me, foe).glance.value > 0.0, "off light it can glance")
	b.tiles.apply([E], "light", "x")
	var fc := b.forecast_basic(me, foe)
	t.eq(fc.glance.value, 0.0, "on light: can't glance")
	t.ok(not _mod(fc, "Judgement").is_empty(), "named")


func test_glare(t) -> void:
	var me := _u("me", "staff", "light", {}, ["light_glare"])
	var foe := _foe()
	var b := _fight([me], [foe], [C], [E])
	foe.hp -= 50
	b.tiles.apply([E], "light", me.id, 2)
	_turn(b, foe)
	t.ok(_ev(b, "heal").is_empty(), "my light doesn't heal a foe")
	t.ok(foe.statuses.has("blinded"), "light 2: Blinded")
	var foe2 := _foe("g")
	var b2 := _fight([me], [foe2], [C], [E])
	foe2.hp -= 50
	b2.tiles.apply([E], "light", me.id, 1)
	_turn(b2, foe2)
	t.ok(_ev(b2, "heal").is_empty() and not foe2.statuses.has("blinded"), "light 1: no heal, no blind")


func test_sanctuary(t) -> void:
	var me := _u("me", "staff", "light", {}, ["light_sanct"])
	var mate := _u("m", "sword", "fire", { "con": 100 })
	var b := _fight([me, mate], [_foe()], [C, Vector2i(4, 6)], [Vector2i(10, 10)])
	mate.hp = mate.max_hp() - 60
	b.tiles.apply([mate.pos], "light", me.id, 2)
	_turn(b, mate)
	t.eq(int(_ev(b, "heal")[0].amount), roundi(mate.max_hp() * 9 / 100.0), "my light 2 heals an ally 9%")
	b.tiles.clear(mate.pos)
	mate.hp = int(mate.max_hp() * 0.4)
	b._tile_hurt(mate, int(mate.max_hp() * 0.1), "slam", "")
	t.eq(b.tiles.intensity(mate.pos, "light"), 2, "under 35%: its hex gains light 2")
	b.tiles.clear(mate.pos)
	mate.hp = int(mate.max_hp() * 0.4)
	b._tile_hurt(mate, int(mate.max_hp() * 0.1), "slam", "")
	t.eq(b.tiles.intensity(mate.pos, "light"), 0, "once per battle")

extends RefCounted
## D87, the skills pass (design/SKILLS.md): one hook per skill, the short
## statuses, facing, and the AI's free guard.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)          # C's east neighbour (cube direction 0)
const T := Vector2i(4, 2)


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _foe(id: String = "f", extra: Dictionary = {}) -> BWUnit:
	var x := { "con": 300 }
	x.merge(extra, true)
	return _u(id, "axe", "water", x)


## `me` (and `mates`) at C (and `mate_at`) with the turn; foes at `at`.
func _fight(me: BWUnit, foes: Array, at: Array, seed_value: int = 7, mates: Array = [], mate_at: Array = []) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me] + mates, foes)
	me.pos = C
	for i in mates.size():
		mates[i].pos = mate_at[i]
	for i in foes.size():
		foes[i].pos = at[i]
	_give_turn(b, me)
	return b


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _mod(fc: Dictionary, label_start: String) -> Dictionary:
	for m in fc.mods:
		if str(m.label).begins_with(label_start):
			return m
	return {}


# ------------------------------------------------------------------ sword

func test_riposte_is_free_cd3_refund(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var foe := _foe("f", { "dex": 100 })
	var b := _fight(me, [foe], [E])
	t.eq(BWSkills.get_skill("riposte").cd, 3, "riposte cooldown 3")
	b.use_skill(me, "riposte", "fire", C)
	t.ok(not me.acted, "setting the guard spends nothing")
	t.eq(me.cooldowns.get("riposte_fire", 0), 3, "cooling 3")
	t.ok(not b.attack(me, foe).is_empty(), "and the duelist still attacks")
	# after acting it's still offered (it is free), in another element if learned
	me.affinity["water"] = 10
	t.ok(b.skills_for(me).any(func(s): return s.key == "riposte"), "free: offered after the attack too")
	# the answer lands: 1 off the cooldown
	_give_turn(b, foe)
	b.attack(foe, me)
	var r := _events(b, "riposte")
	t.eq(r.size(), 1, "answered")
	t.ok(r[0].results[0].result.hit, "the answer lands (dex 100)")
	t.eq(_events(b, "riposte_refund").size(), 1, "refund event")
	t.eq(me.cooldowns.get("riposte_fire", 0), 2, "cooldown 3 -> 2")


func test_striketwice_same_target_staggers(t) -> void:
	var applied := 0
	for sd in 8:
		var me := _u("me", "sword", "fire", { "dex": 100 })
		var foe := _foe("f")
		var b := _fight(me, [foe], [E], 40 + sd)
		b.use_skill(me, "striketwice", "fire", E)
		var pv := b.skill_preview(me, "striketwice_second", "fire", E)
		var fc: Dictionary = pv.forecasts["f"]
		t.eq(fc.glance.value, 0.0, "same foe: the second cut can't glance")
		t.ok(fc.notes.any(func(n): return str(n).contains("Staggers")), "the forecast says it staggers")
		var ev := b.use_skill(me, "striketwice_second", "fire", E)
		t.ok(not ev.results[0].result.glance, "no glance rolled")
		t.eq(ev.retarget, false, "not a retarget")
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.statuses.has("staggered"), sec, "staggered iff the secondary effect landed (seed %d)" % sd)
		if sec:
			applied += 1
			# D94: Staggered = no skills on its next turn, and no hit penalty
			t.ok(_mod(b.forecast_basic(foe, me), "Staggered").is_empty(), "no hit penalty any more (D94)")
			t.eq(b.skills_for(foe), [], "a staggered foe can only make its basic attack (D94)")
	t.ok(applied > 0, "stagger landed at least once over 8 seeds")


func test_striketwice_retarget(t) -> void:
	var me := _u("me", "sword", "fire", { "dex": 100 })
	var a := _foe("a")
	var o := _foe("o")
	var other: Vector2i = BWHex.neighbors(C)[2]
	var b := _fight(me, [a, o], [E, other])
	b.use_skill(me, "striketwice", "fire", E)
	t.ok(other in b.skill_targets(me, "striketwice_second", "fire"), "the second cut may go to another adjacent foe")
	var pv := b.skill_preview(me, "striketwice_second", "fire", other)
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Retargeted")), "retarget is named")
	t.ok(pv.forecasts["o"].glance.value > 0.0, "a retargeted cut can glance")
	var ev := b.use_skill(me, "striketwice_second", "fire", other)
	t.eq(ev.retarget, true, "the event says retarget (for the one-shot)")
	t.ok(not o.statuses.has("staggered"), "no stagger on a retarget")


func test_striketwice_reactions(t) -> void:
	# steam: fire then water on the same hex; a foe beside it takes 8%, the cutter never
	var me := _u("me", "sword", "fire", { "dex": 100 })
	me.affinity["water"] = 10
	var foe := _foe("f")
	var side_hex := Vector2i(6, 4)
	t.eq(BWHex.distance(E, side_hex), 1, "set-up: beside the target")
	var nb := _foe("nb")
	var b := _fight(me, [foe, nb], [E, side_hex])
	b.use_skill(me, "striketwice", "fire", E)
	var pv := b.skill_preview(me, "striketwice_second", "water", E)
	t.eq(pv.reaction, "steam", "fire + water = steam")
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Fire meets water")), "named in the preview")
	b.use_skill(me, "striketwice_second", "water", E)
	t.eq(_events(b, "reaction").map(func(e): return e.kind), ["steam"], "a reaction event")
	var steam := _events(b, "tile_damage").filter(func(e): return e.cause == "steam")
	t.eq(steam.map(func(e): return e.unit), ["nb"], "steam scalds the ring, not the cutter")
	t.eq(int(steam[0].amount), BWTiles.tile_damage(nb, BWSkills.STEAM_PCT, "fire"), "8% HP, fire resistance applies")
	# eclipse: light then dark blinds the foe and its neighbours
	var me2 := _u("me", "sword", "light", { "dex": 100 })
	me2.affinity["dark"] = 10
	var f2 := _foe("f")
	var n2 := _foe("n2")
	var b2 := _fight(me2, [f2, n2], [E, side_hex])
	b2.use_skill(me2, "striketwice", "light", E)
	b2.use_skill(me2, "striketwice_second", "dark", E)
	t.ok(f2.statuses.has("blinded") and n2.statuses.has("blinded"), "eclipse blinds the target and the foes beside it")
	t.eq(float(_mod(b2.forecast_basic(f2, me2), "Blinded: can't crit").get("value", -1.0)), 0.0,
		"blinded: can't crit, no hit penalty (D94)")
	# storm: thunder then wind pushes the ring out 1
	var me3 := _u("me", "sword", "thunder", { "dex": 100 })
	me3.affinity["wind"] = 10
	me3.wind_mode = "becalm"          # D271: a wind cut's mode moves nobody here (the storm is the subject)
	var f3 := _foe("f")
	var n3 := _foe("n3")
	var b3 := _fight(me3, [f3, n3], [E, side_hex])
	b3.use_skill(me3, "striketwice", "thunder", E)
	b3.use_skill(me3, "striketwice_second", "wind", E)
	t.eq(n3.pos, BWHex.step_beyond(E, side_hex), "storm pushes the neighbour straight out")
	t.eq(me3.pos, C, "the cutter stands firm")
	t.eq(f3.pos, E, "the target itself isn't pushed")
	# same element still floods, no reaction
	var me4 := _u("me", "sword", "fire", { "dex": 100 })
	var b4 := _fight(me4, [_foe("f")], [E])
	b4.use_skill(me4, "striketwice", "fire", E)
	t.eq(b4.skill_preview(me4, "striketwice_second", "fire", E).reaction, "", "same element: flood, no reaction")


# ------------------------------------------------------------------ axe

func test_cleave_per_foe(t) -> void:
	var me := _u("me", "axe", "fire")
	var arc: Array = b_arc()
	var foes := [_foe("a"), _foe("b"), _foe("c")]
	var b := _fight(me, foes, arc)
	var pv := b.skill_preview(me, "cleave", "fire", E)
	t.eq(pv.units.size(), 3, "three foes in the arc")
	var m := _mod(pv.forecasts["a"], "Cleave: 3 foes caught (+20%)")
	t.near(float(m.get("value", 0.0)), 1.2, 0.001, "+10% per foe beyond the first")
	var me2 := _u("me", "axe", "fire")
	var b2 := _fight(me2, [_foe("a")], [E])
	t.ok(_mod(b2.skill_preview(me2, "cleave", "fire", E).forecasts["a"], "Cleave").is_empty(), "one foe: no bonus")


func b_arc() -> Array:
	var nb := BWHex.neighbors(C)
	return [nb[5], nb[0], nb[1]]       # the arc centred on E (direction 0)


func test_charge_slam(t) -> void:
	var me := _u("me", "axe", "fire")
	var foe := _foe("f")
	var g := _foe("g")
	var b := _fight(me, [foe, g], [Vector2i(6, 4), Vector2i(7, 4)])
	var pv := b.skill_preview(me, "charge", "fire", E)
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Slam: f")), "the preview names the slam (%s)" % [pv.notes])
	b.use_skill(me, "charge", "fire", E)
	t.eq(me.pos, E, "the charge stops short of the stuck foe")
	t.eq(foe.pos, Vector2i(6, 4), "it can't be shoved")
	var sl := _events(b, "tile_damage").filter(func(e): return e.cause == "slam")
	t.eq(sl.map(func(e): return e.unit), ["f", "g"], "both the caught foe and the unit behind are hurt")
	t.eq(int(sl[0].amount), BWTiles.tile_damage(foe, BWSkills.CHARGE_SLAM_PCT, ""), "8% HP")
	t.eq(_events(b, "slam").size(), 1, "a slam event for the view")
	# rock behind: the caught foe alone
	var me2 := _u("me", "axe", "fire")
	var f2 := _foe("f")
	var b2 := _fight(me2, [f2], [Vector2i(6, 4)])
	b2.board.set_cell(Vector2i(7, 4), "jagged")
	b2.use_skill(me2, "charge", "fire", E)
	t.eq(_events(b2, "tile_damage").filter(func(e): return e.cause == "slam").map(func(e): return e.unit), ["f"], "rock: the foe slams alone")


# ------------------------------------------------------------------ lance

func test_tridentpierce_in_line(t) -> void:
	var me := _u("me", "lance", "fire")
	var a := _foe("a")
	var b_ := _foe("b")
	var b := _fight(me, [a, b_], [E, Vector2i(6, 4)])
	var pv := b.skill_preview(me, "tridentpierce", "fire", E)
	t.near(float(_mod(pv.forecasts["b"], "Pierce (in line behind a): +20%").get("value", 0.0)), 1.2, 0.001, "the foe behind the first is pierced")
	t.ok(_mod(pv.forecasts["a"], "Pierce").is_empty(), "the first foe is not")
	var b2 := _fight(_u("me", "lance", "fire"), [_foe("b")], [Vector2i(6, 4)])
	t.ok(_mod(b2.skill_preview(b2.units[0], "tridentpierce", "fire", E).forecasts["b"], "Pierce").is_empty(),
		"no foe in front: nothing to pierce through")


## D105 rework: the momentum strike is part of the Vault (no follow-up).
func test_vault_momentum(t) -> void:
	var me := _u("me", "lance", "fire")
	var foe := _foe("f")
	var b := _fight(me, [foe], [Vector2i(7, 4)])
	b.use_skill(me, "vault", "fire", Vector2i(7, 4))
	t.eq(me.pos, Vector2i(6, 4), "vaulted beside the foe")
	var hit: Array = _events(b, "attack")
	t.eq(hit.size(), 1, "the strike is part of the vault")
	t.ok("Momentum" in hit[0].tags, "and it carries momentum (+25%)")
	t.ok(not me.fx.has("momentum"), "spent by the strike")
	t.ok(me.follow_up.is_empty(), "no follow-up")


# ------------------------------------------------------------------ daggers

func test_daggerleap_backstab(t) -> void:
	var me := _u("me", "daggers", "fire")
	var foe := _foe("f")
	var X := Vector2i(6, 4)
	var b := _fight(me, [foe], [X])
	foe.facing = 3                                    # facing west, toward the leaper
	var front: Vector2i = BWHex.neighbors(X)[3]
	var back: Vector2i = BWHex.neighbors(X)[0]
	t.ok(b.behind(foe, back) and not b.behind(foe, front), "behind = the back three sides against its facing")
	t.ok(b.behind(foe, BWHex.neighbors(X)[1]) and b.behind(foe, BWHex.neighbors(X)[5]), "back diagonals count")
	var pv := b.skill_preview(me, "daggerleap", "fire", back)
	t.near(float(_mod(pv.forecasts["f"], "Backstab").get("value", 0.0)), 1.5, 0.001, "landing behind: +50%")
	t.ok(_mod(b.skill_preview(me, "daggerleap", "fire", front).forecasts["f"], "Backstab").is_empty(), "in front: no bonus")


func test_facing_follows_moves_and_strikes(t) -> void:
	var me := _u("me", "sword", "fire")
	var b := _fight(me, [_foe("f")], [Vector2i(9, 9)])
	b.move(me, Vector2i(4, 6))
	var path := BWBoard.path_to(b.reachable(me), me.pos)
	t.ok(me.facing >= 0, "a move sets facing")
	b.undo_move(me)
	var foe: BWUnit = b.units[1]
	foe.pos = E
	b.attack(me, foe)
	t.eq(me.facing, BWHex.direction_index(C, E), "striking faces the target")


func test_dualthrow_bounce(t) -> void:
	var me := _u("me", "daggers", "fire", { "dex": 100 })
	var a := _foe("a")
	var o := _foe("o")
	var far := _foe("far")
	var b := _fight(me, [a, o, far], [Vector2i(7, 4), Vector2i(8, 5), Vector2i(10, 10)])
	b.use_skill(me, "dualthrow", "fire", Vector2i(7, 4))
	var pv := b.skill_preview(me, "dualthrow_second", "fire", Vector2i(7, 4))
	t.ok("o" in pv.units and not "far" in pv.units, "the second blade bounces to the foe within 2")
	t.near(float(_mod(pv.forecasts["o"], "Bounce (off a): 75%").get("value", 0.0)), 0.75, 0.001, "at 75%")
	var ev := b.use_skill(me, "dualthrow_second", "fire", Vector2i(7, 4))
	t.eq(ev.bounce, "o", "the skill event names the bounce")
	t.ok(o.hp < o.max_hp() or not ev.results[1].result.hit, "bounce dealt (or avoided)")


func test_consume_heals(t) -> void:
	var me := _u("me", "daggers", "fire", { "dex": 100 })
	var foe := _foe("f")
	var b := _fight(me, [foe], [E])
	me.hp = 20
	b.tiles.apply([E], "fire", "x", 3)
	var pv := b.skill_preview(me, "consume", "", E)
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Consume heals you 15%")), "the preview names the heal")
	b.use_skill(me, "consume", "", E)
	var h := _events(b, "heal").filter(func(e): return str(e.get("cause", "")) == "consume")
	t.eq(h.size(), 1, "a consume heal")
	t.eq(int(h[0].amount), roundi(me.max_hp() * 0.15), "5% per point eaten (3 points)")


# ------------------------------------------------------------------ bow

func test_arcing_high_ground(t) -> void:
	var me := _u("me", "bow", "fire")
	var b := _fight(me, [], [])
	t.eq(b.skill_preview(me, "arcing_shot", "fire", T).hexes.size(), 7, "flat: radius 1")
	b.board.set_cell(C, "neutral", 2)
	var pv := b.skill_preview(me, "arcing_shot", "fire", T)
	t.eq(pv.hexes.size(), 19, "2 levels above: radius 2")
	t.ok(pv.notes.any(func(n): return str(n).begins_with("High ground")), "named in the preview")


func test_energized_pierces(t) -> void:
	var me := _u("me", "bow", "fire", { "dex": 100 })
	var a := _foe("a")
	var o := _foe("o")
	var b := _fight(me, [a, o], [Vector2i(6, 4), Vector2i(8, 4)])
	var pv := b.skill_preview(me, "energized_shot", "fire", Vector2i(6, 4))
	t.eq(pv.units, ["a", "o"], "the shot punches through to the next foe in line")
	t.near(float(_mod(pv.forecasts["o"], "Pierced through a: 60%").get("value", 0.0)), 0.6, 0.001, "at 60%")
	t.eq(pv.hexes, [Vector2i(5, 4), Vector2i(6, 4)], "the trail still ends at the target")
	var b2 := _fight(_u("me", "bow", "fire"), [_foe("a"), _foe("o")], [Vector2i(6, 4), Vector2i(10, 4)])
	t.eq(b2.skill_preview(b2.units[0], "energized_shot", "fire", Vector2i(6, 4)).units, ["a"], "beyond 3 hexes: no pierce")


# ------------------------------------------------------------------ pistols

func test_reload_own_round(t) -> void:
	var me := _u("me", "pistols", "fire")
	me.affinity["water"] = 10
	var foe := _foe("f")
	var b := _fight(me, [foe], [Vector2i(8, 4)])
	b.use_skill(me, "reload", "fire", C)
	t.near(float(_mod(b.forecast_basic(me, foe), "Own round (fire): +10%").get("value", 0.0)), 1.1, 0.001, "own element round +10%")
	me.loaded = "water"
	t.ok(_mod(b.forecast_basic(me, foe), "Own round").is_empty(), "another element: no bonus")


func test_fan_needs_stillness(t) -> void:
	var me := _u("me", "pistols", "fire", { "dex": 100 })
	var foe := _foe("f")
	var b := _fight(me, [foe], [Vector2i(9, 4)])
	b.use_skill(me, "reload", "fire", C)
	_give_turn(b, me)
	b.move(me, Vector2i(4, 5))
	b.use_skill(me, "quick_shot", "", foe.pos)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "quick_shot"), "moved first: one quick shot")
	var me2 := _u("me", "pistols", "fire", { "dex": 100 })
	var f2 := _foe("f")
	var b2 := _fight(me2, [f2], [Vector2i(9, 4)])
	b2.use_skill(me2, "reload", "fire", C)
	_give_turn(b2, me2)
	b2.use_skill(me2, "quick_shot", "", f2.pos)
	t.eq(_events(b2, "fan").size(), 1, "unmoved: the hammer fans")
	b2.move(me2, Vector2i(4, 5))
	t.ok(not b2.skills_for(me2).any(func(s): return s.key == "quick_shot"), "moving spends the fanned shot")


# ------------------------------------------------------------------ staff

func test_surge_centre(t) -> void:
	var me := _u("me", "staff", "fire")
	var c := _foe("c")
	var s := _foe("s")
	var b := _fight(me, [c, s], [T, BWHex.neighbors(T)[0]])
	var pv := b.skill_preview(me, "surge", "fire", T)
	t.near(float(_mod(pv.forecasts["c"], "Surge centre: +30%").get("value", 0.0)), 1.3, 0.001, "centre +30%")
	t.ok(_mod(pv.forecasts["s"], "Surge centre").is_empty(), "the ring: no bonus")


func test_saturate_status(t) -> void:
	var applied := 0
	for sd in 8:
		var me := _u("me", "staff", "fire", { "dex": 100 })
		var foe := _foe("f")
		var b := _fight(me, [foe], [T], 60 + sd)
		b.tiles.apply([T], "fire", "x")
		var pv := b.skill_preview(me, "saturate", "fire", T)
		t.ok(pv.notes.any(func(n): return str(n).begins_with("Fire to 3: f is Scorched")), "the preview names the status")
		var ev := b.use_skill(me, "saturate", "fire", T)
		t.eq(b.tiles.intensity(T, "fire"), 3, "fire 1 + 2 = 3")
		var sec: bool = ev.results[0].result.secondary
		t.eq(foe.statuses.has("scorched"), sec, "scorched iff not resisted (seed %d)" % sd)
		if sec:
			applied += 1
			t.near(float(_mod(b.forecast_basic(me, foe), "Scorched: +10%").get("value", 0.0)), 1.1, 0.001, "scorched: attacks on it +10%")
	t.ok(applied > 0, "scorched at least once over 8 seeds")
	# already at 3: no status
	var me2 := _u("me", "staff", "water")
	var f2 := _foe("f")
	var b2 := _fight(me2, [f2], [T])
	b2.tiles.apply([T], "water", "x", 3)
	t.ok(b2.skill_preview(me2, "saturate", "water", T).notes.is_empty(), "already at 3: nothing pushed")


func test_status_lifecycle_and_drenched(t) -> void:
	var me := _u("me", "staff", "water")
	var foe := _foe("f")
	var b := _fight(me, [foe], [T])
	var mv := foe.move_range()
	b._add_status(foe, "drenched", me)
	t.eq(foe.move_range(), mv - 1, "drenched: -1 move")
	_give_turn(b, foe)
	t.ok(foe.statuses.drenched.armed, "armed at its turn start")
	b.end_turn()
	t.ok(not foe.statuses.has("drenched"), "gone at the end of its turn")
	t.eq(_events(b, "status_end").map(func(e): return e.status), ["drenched"], "status_end event")
	b._add_status(foe, "shrouded", me)
	_give_turn(b, foe)
	t.eq(_events(b, "tile_damage").filter(func(e): return e.cause == "shrouded").size(), 1, "shrouded drains at its turn start")


func test_ley_line_swift(t) -> void:
	var me := _u("me", "staff", "fire")
	var ally := _u("al", "sword", "fire")
	var b := _fight(me, [_foe("f")], [Vector2i(10, 10)], 7, [ally], [Vector2i(6, 4)])
	var pv := b.skill_preview(me, "ley_line", "fire", E)
	t.ok(pv.notes.any(func(n): return str(n).begins_with("Swift: al")), "the preview names the swift ally")
	var mv := ally.move_range()
	b.use_skill(me, "ley_line", "fire", E)
	t.ok(ally.statuses.has("swift"), "ally on the line is swift")
	t.eq(ally.move_range(), mv + 1, "+1 move")
	t.ok(not me.statuses.has("swift"), "never the caster")


func test_siphon_heals(t) -> void:
	var me := _u("me", "staff", "fire")
	var b := _fight(me, [_foe("f")], [Vector2i(10, 10)])
	me.hp = 10
	b.tiles.apply([T], "fire", "x", 3)
	b.tiles.apply([T], "light", "x", 1)
	b.use_skill(me, "siphon", "", T)
	var h := _events(b, "heal").filter(func(e): return str(e.get("cause", "")) == "siphon")
	t.eq(int(h[0].amount), roundi(me.max_hp() * 0.12), "4% x 3 steps (fire 2 + light 1)")


# ------------------------------------------------------------------ fists

func test_flurry_finisher_and_palm_push(t) -> void:
	var me := _u("me", "fists", "fire")
	var foe := _foe("f")
	var b := _fight(me, [foe], [E])
	var s := BWSkills.get_skill("flurry")
	var p := b._plan(me, s, "fire", E)
	t.ok(_mod(b._skill_forecast(me, s, "fire", foe, p, 0), "Flurry finisher").is_empty(), "first strike: no bonus")
	var last := b._skill_forecast(me, s, "fire", foe, p, 2)
	t.eq(float(_mod(last, "Flurry finisher").get("value", 0.0)), 15.0, "the third strike: +15 crit")
	t.ok(last.crit.formula.contains("Flurry finisher"), "in the crit breakdown")
	var pushed := 0
	for sd in 8:
		var me2 := _u("me", "fists", "fire", { "dex": 100 })
		var f2 := _foe("f")
		var b2 := _fight(me2, [f2], [E], 80 + sd)
		t.ok(b2.skill_preview(me2, "palm_burst", "fire", E).notes.is_empty(), "bare hex: no push")
		b2.tiles.apply([E], "fire", "x")
		t.ok(b2.skill_preview(me2, "palm_burst", "fire", E).notes.any(func(n): return str(n).contains("pushes f back 1")), "carried: push named")
		var ev := b2.use_skill(me2, "palm_burst", "fire", E)
		var sec: bool = ev.results[0].result.secondary
		t.eq(f2.pos == BWHex.step_beyond(C, E), sec, "pushed iff not resisted (seed %d)" % sd)
		if sec:
			pushed += 1
	t.ok(pushed > 0, "the push landed at least once")


# ------------------------------------------------------------------ AI, determinism

func test_ai_guards_and_replays(t) -> void:
	var me := _u("me", "sword", "fire")
	var b := _fight(me, [_foe("f")], [Vector2i(6, 4)])
	BWAI.take_turn(b)
	t.eq(_events(b, "skill").filter(func(e): return e.skill == "riposte").size(), 1,
		"the AI sets the free guard with a foe within 3")
	t.ok(_events(b, "attack").size() + _events(b, "skill").filter(func(e): return e.skill != "riposte").size() > 0,
		"and still acted")
	var logs: Array = []
	for i in 2:
		var cells: Array = []
		for r in 10:
			for c in 10:
				cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
		var bb := BWBattle.new(BWBoard.from_dict({ "name": "m", "cols": 10, "rows": 10, "cells": cells,
			"spawns": { "player": [[1, 4], [1, 5], [1, 6]], "enemy": [[8, 4], [8, 5], [8, 6]] } }), 900)
		bb.setup([_u("a1", "sword", "thunder"), _u("a2", "staff", "thunder"), _u("a3", "pistols", "fire")],
			[_u("e1", "daggers", "wind"), _u("e2", "fists", "water"), _u("e3", "lance", "light")])
		bb.tiles.apply([Vector2i(7, 5), Vector2i(8, 5)], "thunder", "x")
		var n := 0
		while not bb.over and n < 400:
			BWAI.take_turn(bb)
			n += 1
		t.ok(bb.over, "a fight with fuses on the board ends")
		logs.append(JSON.stringify(bb.history))
	t.eq(logs[0], logs[1], "same seed, same fight, chains and statuses included")

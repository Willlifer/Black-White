extends RefCounted
## Equipment effects (BWEffects, design/EQUIPMENT.md §1): every one of the 25
## effect_keys, each asserted on what it actually does to a number or a tile.
## The key under test is named at the top of each test.

const N := 11
const C := Vector2i(5, 5)
const X := Vector2i(5, 2)          # a hex 3 rows up: clear of C's reach


func _board() -> BWBoard:
	var cells: Array = []
	for r in N:
		for c in N:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "fx", "cols": N, "rows": N, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String = "sword", el: String = "fire", extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


## Put enchantment `ench_id` on the first item it applies to (stats 0).
func _ench(u: BWUnit, ench_id: String) -> BWUnit:
	var row := BWData.row("enchantments", ench_id)
	var base := str(BWData.list(row.applies_to)[0])
	var b := BWData.row("equipment", base)
	u.equipment[str(b.slot)] = { "uid": "t_" + ench_id, "base": base, "slot": str(b.slot),
		"weight": str(b.weight), "tier": "E", "stats": {}, "enchant": ench_id, "worn": {} }
	u.refresh_effects()
	return u


func _ab(u: BWUnit, id: String, rank: int = 1) -> BWUnit:
	u.abilities[BWRun.ability_type(id)] = { "id": id, "rank": rank }
	u.refresh_effects()
	return u


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


## Players then foes, placed by hand; the first player has the turn.
func _fight(players: Array, foes: Array, ppos: Array, fpos: Array, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup(players, foes)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1          # D96: facing has its own test; these read the effects alone
	_turn(b, players[0])
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _far() -> BWUnit:
	return _u("far", "axe", "water")


const FAR := Vector2i(10, 10)


# ------------------------------------------------------------------ engine

func test_parse_collect_and_conversions(t) -> void:
	var pp := BWEffects.parse_params("a=1;b=wil+res;c=-1.5;d=hit")
	t.eq(pp.a, 1, "ints parse")
	t.eq(pp.b, "wil+res", "stat lists stay strings")
	t.near(pp.c, -1.5, 0.0001, "floats parse")
	t.eq(pp.d, "hit", "enum words stay strings")
	var u := _ab(_ench(_u("a"), "explosive"), "deadeye")
	t.eq(u.effects.size(), 2, "one record per enchantment + one per ability")
	t.eq(u.effects[0].key, "tile_erupt", "enchantment first")
	t.eq(u.effects[0].name, "Explosive Chaps", "the forecast name fills {item}")
	t.eq(u.effects[0].element, "fire", "element from the row")
	t.eq(u.effects[1].source, "deadeye", "ability second")
	# D33: flat per-point damage converts to % max HP at 4/3 (EQUIPMENT.md §8)
	var pct := func(id): return BWEffects.make(BWData.row("enchantments", id), "enchant").params
	t.eq(pct.call("explosive").dmg_pct_per_point, 4, "Explosive 3 flat -> 4% per point")
	t.eq(pct.call("collapsing").dmg_pct_per_point, 3, "Collapsing 2 flat -> 3% per point")
	t.eq(pct.call("geyser").dmg_pct_per_point, 1, "Geyser 1 flat -> 1% per point")
	t.eq(pct.call("flaring").heal_pct_per_point, 3, "Flaring heal 2 flat -> 3% per point")
	var keys := {}
	for r in BWData.table("enchantments") + BWData.table("abilities"):
		keys[str(r.effect_key)] = true
	t.eq(keys.size(), 25, "the data uses exactly the 25 keys")


func test_rank_scaling(t) -> void:
	var row := BWData.row("abilities", "brace")
	t.eq(BWEffects.make(row, "ability", 1).params.amount, 1, "rank 1 = as written")
	t.eq(BWEffects.make(row, "ability", 3).params.amount, 2, "rank 3 = ×1.5, rounded")
	t.eq(BWEffects.make(row, "ability", 3).params.cap, 3, "caps don't scale")
	t.eq(BWEffects.make(row, "ability", 9).params.amount, 2, "ranks above 3 count as 3")
	t.eq(BWEffects.make(BWData.row("abilities", "deadeye"), "ability", 2).params.hit_per_hex, 6, "×1.25 at rank 2")
	t.near(BWEffects.make(BWData.row("abilities", "bastion"), "ability", 3).params.chance_mult, 2.5, 0.001,
		"multipliers scale their excess: ×2 -> ×2.5")
	t.eq(BWEffects.make(BWData.row("abilities", "leap_ready"), "ability", 3).params.move, 1, "move never scales")
	var u := _ab(_u("r"), "flair", 2)
	t.eq(u.effects[0].name, "Flair 2", "rank shows in the name")


func test_sleeping_enchantments(t) -> void:
	var u := _ench(_u("w", "sword", "water"), "blazing")
	t.ok(not BWEffects.has(u, "stand_on_bonus"), "a fire row sleeps on a unit without fire")
	u.affinity["fire"] = 10
	t.ok(BWEffects.has(u, "stand_on_bonus"), "and wakes once fire is learned")
	t.ok(BWEffects.has(_ench(_u("v", "sword", "water"), "fireproof"), "damage_taken_mod"), "defensive rows never sleep")


# ------------------------------------------------------------------ element keys

func test_tile_duration_plus(t) -> void:
	var me := _ench(_u("me", "staff", "fire"), "smouldering")
	var plain := _u("p", "staff", "fire")
	var icy := _ench(_u("ice", "staff", "ice"), "frozen")
	var b := _fight([me, plain, icy], [_far()], [C, Vector2i(0, 5), Vector2i(0, 6)], [FAR])
	b.paint([X], "fire", me)
	t.eq(b.tiles.at(X).timer, BWTiles.STEP_CYCLES + 1, "Smouldering: fire lasts 1 cycle longer")
	b.paint([Vector2i(2, 2)], "fire", plain)
	t.eq(b.tiles.at(Vector2i(2, 2)).timer, BWTiles.STEP_CYCLES, "control: plain fire")
	b.paint([Vector2i(2, 2)], "ice", icy)
	t.eq(b.tiles.at(Vector2i(2, 2)).glaze, BWTiles.GLAZE_CYCLES + 1, "Frozen: the lock lasts 1 longer")
	var windy := _ench(_u("wi", "staff", "wind"), "lingering")
	var b2 := _fight([windy], [_far()], [C], [FAR])
	b2.tiles.apply([X], "fire", "x")
	b2.paint([X], "wind", windy)
	t.eq(b2.tiles.at(_nb(X, 0)).timer, 2, "Lingering: gale copies last 1 longer")


func test_tile_erupt_explosive(t) -> void:
	var me := _ench(_u("me", "staff", "fire"), "explosive")
	var f1 := _u("f1", "axe", "water")
	var f2 := _u("f2", "axe", "water")
	var b := _fight([me], [f1, f2], [C], [X, _nb(X, 0)])
	b.tiles.apply([_nb(X, 3)], "thunder", "x")          # a fuse right next door
	b.paint([X], "fire", me)
	t.ok(b.tiles.at(X).has("erupt"), "the cast arms the tile")
	var paints := _events(b, "paint").size()
	var h1 := f1.hp
	var h2 := f2.hp
	b.end_turn()                                         # cycle ends: tick, then the eruption
	t.eq(_events(b, "erupt").size(), 1, "it went off once")
	t.eq(h1 - f1.hp, BWTiles.tile_damage(f1, 4.0, "fire"), "occupant: 4% × fire 1, after resistance")
	t.eq(h2 - f2.hp, BWTiles.tile_damage(f2, 4.0, "fire"), "neighbour: same (radius 1)")
	t.ok(b.tiles.at(X).is_empty(), "consume=1: the tile went neutral")
	t.eq(_events(b, "paint").size(), paints, "an eruption paints nothing")
	t.eq(b.tiles.at(_nb(X, 3)).marker, "fuse", "and fires no marker: no chain")
	b.tiles.tick()
	t.ok(b.tiles.eruptions.is_empty(), "spent: it never goes off twice")


func test_tile_erupt_geyser_and_flaring(t) -> void:
	var me := _ench(_u("me", "staff", "water"), "geyser")
	var foe := _u("f", "axe", "fire")
	var E := _nb(C, 0)
	var b := _fight([me], [foe], [C], [E])
	b.paint([E], "water", me)
	var h := foe.hp
	b.end_turn()
	t.eq(h - foe.hp, BWTiles.tile_damage(foe, 1.0, "water"), "Geyser: 1% × water 1")
	t.eq(foe.pos, _nb(E, 0), "the occupant is pushed 1 hex away from the owner")
	t.ok(b.tiles.intensity(E, "water") >= 1, "consume=0: the water stays")
	# Flaring: heals the owner's side 3% per light point, then the tile goes neutral.
	var priest := _ench(_u("pr", "staff", "light"), "flaring")
	var ally := _u("al", "sword", "fire")
	var b2 := _fight([priest, ally], [_far()], [C, X], [FAR])
	ally.hp -= 50
	b2.paint([X], "light", priest)
	var before := ally.hp
	b2.end_turn()
	t.eq(ally.hp - before, roundi(ally.max_hp() * 3 / 100.0), "Flaring heals 3% × light 1")
	t.ok(b2.tiles.at(X).is_empty(), "and the tile went neutral")
	t.ok(_events(b2, "heal").any(func(e): return e.get("cause", "") == "erupt"), "heal event carries cause=erupt")


func test_effect_repeat(t) -> void:
	var me := _ench(_u("me", "staff", "thunder"), "thundering")
	var foe := _u("f", "axe", "water")
	var b := _fight([me], [foe], [C], [X])
	b.tiles.apply([X], "fire", "x")
	var h := foe.hp
	b.paint([X], "thunder", me)
	var dets := _events(b, "detonate")
	t.eq(dets.size(), 2, "Thundering: the detonation triggers twice")
	t.ok(dets[1].get("echo", false), "the second is the echo")
	t.near(dets[1].pct, 4.5, 0.001, "at 50%")
	t.eq(h - foe.hp, BWTiles.tile_damage(foe, 9.0 * 1.5, "thunder", 1.05), "damage = blast × 1.5 (thunder rank 1: ×1.05)")


func test_cast_step_plus(t) -> void:
	var me := _ench(_u("me", "staff", "fire"), "kindled")
	var b := _fight([me], [_far()], [C], [FAR])
	b.paint([X], "fire", me)
	t.eq(b.tiles.intensity(X, "fire"), 2, "Kindled: one cast lays 2 steps")
	b.paint([X], "fire", me)
	t.eq(b.tiles.intensity(X, "fire"), 3, "still capped at 3")
	b.paint([C], "fire", me, 1, false)
	t.eq(b.tiles.intensity(C, "fire"), 1, "a lay_on trigger is not a cast: no extra step")


func test_element_area_plus(t) -> void:
	var tidal := _ench(_u("me", "staff", "water"), "tidal")
	var b := _fight([tidal], [_far()], [Vector2i(0, 5)], [FAR])
	b.paint([C], "water", tidal)
	t.eq(b.tiles.intensity(C, "water"), 1, "Tidal: the target")
	var ring_ok := true
	for n in BWHex.neighbors(C):
		ring_ok = ring_ok and b.tiles.intensity(n, "water") == 1
	t.ok(ring_ok, "Tidal: and the ring around it, 1 step")
	var glacial := _ench(_u("g", "staff", "ice"), "glacial")
	var bg := _fight([glacial], [_far()], [Vector2i(0, 5)], [FAR])
	bg.paint([C], "ice", glacial)
	t.eq(bg.tiles.at(_nb(C, 2)).get("marker", ""), "stasis", "Glacial: ice reaches the ring (arms stasis on bare ground)")
	# Arcing: detonation splash reaches 2 rings.
	var Z := _nb(_nb(X, 0), 0)
	for arcing in [true, false]:
		var me := _u("me", "staff", "thunder")
		if arcing:
			_ench(me, "arcing")
		var far := _u("f", "axe", "water")
		var ba := _fight([me], [far], [C], [Z])
		ba.tiles.apply([X], "fire", "x")
		var h := far.hp
		ba.paint([X], "thunder", me)
		var want := maxi(1, int(BWTiles.tile_damage(far, 9.0, "thunder", 1.05) / 2.0)) if arcing else 0
		t.eq(h - far.hp, want, "Arcing %s: a unit 2 hexes from the blast" % ("on" if arcing else "off"))
	var gust := _ench(_u("w", "staff", "wind"), "gusting")
	var bw := _fight([gust], [_far()], [C], [FAR])
	bw.tiles.apply([X], "fire", "x")
	bw.paint([X], "wind", gust)
	t.eq(bw.tiles.intensity(Z, "fire"), 1, "Gusting: gales copy 2 rings out")


func test_tile_potency_pct(t) -> void:
	var dark := _ench(_u("d", "staff", "dark"), "gloaming")
	var light := _ench(_u("l", "staff", "light"), "radiant")
	var water := _ench(_u("w", "staff", "water"), "brimming")
	var b := _fight([dark, light, water], [_far()], [C, Vector2i(0, 5), Vector2i(0, 6)], [FAR])
	b.paint([X], "dark", dark)
	t.near(b.tiles.hit_mod(X), -10.5, 0.001, "Gloaming: dark 1 hides 7 × 1.5")
	var L := Vector2i(2, 2)
	b.paint([L], "light", light)
	t.near(b.tiles.standing(L).heal, 4.5, 0.001, "Radiant: light 1 heals 3% × 1.5")
	t.near(b.tiles.hit_mod(L), 10.5, 0.001, "Radiant: and exposes 7 × 1.5")
	var W := Vector2i(8, 8)
	b.paint([W], "water", water, 2)
	t.eq(b.tiles.move_penalty(W), 2, "Brimming: water 2 costs ceil(1 × 1.5)")
	b.tiles.apply([Vector2i(8, 7)], "water", "x", 2)
	t.eq(b.tiles.move_penalty(Vector2i(8, 7)), 1, "control: someone else's water 2")
	# Shattering: a lock you made shatters ×1.5 × 1.33 (≈ ×2).
	var icy := _ench(_u("i", "staff", "ice"), "shattering")
	var other := _u("o", "staff", "thunder")
	var b2 := _fight([icy, other], [_far()], [C, Vector2i(0, 5)], [FAR])
	b2.tiles.apply([X], "fire", "x")
	b2.paint([X], "ice", icy)
	b2.paint([X], "thunder", other)
	t.near(_events(b2, "detonate")[0].pct, 9.0 * 1.5 * 1.33, 0.01, "Shattering: fire 1 shatter")


func test_stand_on_bonus(t) -> void:
	var me := _ench(_u("me", "sword", "fire"), "blazing")
	var b := _fight([me], [_far()], [C], [FAR])
	t.eq(me.stat("str"), 4, "off the fire")
	b.tiles.apply([C], "fire", "anyone", 2)
	t.eq(me.stat("str"), 6, "Blazing: +1 str per fire point under you (anyone's)")
	var rimed := _ench(_u("r", "sword", "ice"), "rimed")
	var b2 := _fight([rimed], [_far()], [C], [FAR])
	b2.tiles.apply([C], "fire", "x")
	t.eq(rimed.stat("def"), 4, "unlocked fire: nothing")
	b2.tiles.apply([C], "ice", "x")
	t.eq(rimed.stat("def"), 6, "Rimed: +2 def on a glazed tile")


func test_lay_on(t) -> void:
	# move: Emberstep lays fire on every tile you leave.
	var me := _ench(_u("me", "sword", "fire"), "emberstep")
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	var b := _fight([me], [_far()], [C], [FAR])
	t.ok(b.move(me, E2), "moved 2")
	t.eq(b.tiles.intensity(C, "fire"), 1, "Emberstep: the start hex")
	t.eq(b.tiles.intensity(E, "fire"), 1, "Emberstep: the hex passed through")
	t.eq(b.tiles.intensity(E2, "fire"), 0, "not the hex you stop on")
	# struck: Soaking puts water under whoever hits you; attuned is unchanged.
	var tank := _ench(_u("tank", "sword", "fire", { "con": 30 }), "soaking")
	tank.affinity["water"] = 10
	var foe := _u("f", "sword", "fire", { "dex": 60 })
	var b2 := _fight([tank], [foe], [C], [E])
	_turn(b2, foe)
	b2.attack(foe, tank)
	t.eq(b2.tiles.intensity(E, "water"), 1, "Soaking: the attacker's tile gains water")
	t.eq(tank.attuned, "fire", "a trigger is not a cast: attuned unchanged")
	# struck + melee_only: Static arms thunder under an adjacent attacker only.
	for adjacent in [true, false]:
		var st := _ench(_u("st", "sword", "thunder", { "con": 30 }), "static")
		var archer := _u("a", "bow", "fire", { "dex": 60 })
		var at := E if adjacent else Vector2i(5, 8)
		var b3 := _fight([st], [archer], [C], [at])
		_turn(b3, archer)
		b3.attack(archer, st)
		t.eq(b3.tiles.at(at).get("marker", ""), "fuse" if adjacent else "",
			"Static %s attacker" % ("arms a fuse under an adjacent" if adjacent else "ignores a ranged"))


func test_element_damage_pct(t) -> void:
	var foe := _u("f", "axe", "water")
	var me := _ench(_u("me", "staff", "thunder"), "stormcallers")
	var plain := _u("p", "staff", "thunder")
	var b := _fight([me, plain], [foe], [C, Vector2i(0, 5)], [_nb(C, 0)])
	var fc := b.forecast_basic(me, foe)
	var base := b.forecast_basic(plain, foe)
	t.eq(fc.damage.value, maxf(1.0, roundf(base.damage.value * 1.2)), "Stormcaller's: thunder +20%")
	t.ok(fc.damage.formula.contains("Stormcaller's Wizard Hat"), "named in the damage breakdown")
	# Imbued: once you use an element, your next attack with it is +25%.
	var mage := _ab(_u("m", "staff", "fire"), "imbued")
	var b2 := _fight([mage], [_u("g", "axe", "water", { "con": 40 })], [C], [_nb(C, 0)])
	var target: BWUnit = b2.foes_of(mage)[0]
	t.ok(not b2.forecast_basic(mage, target).damage.formula.contains("Imbued"), "not primed yet")
	b2.attack(mage, target)
	var after := b2.forecast_basic(mage, target)
	t.ok(after.damage.formula.contains("Imbued"), "after a fire Channel, the next fire attack is primed")
	t.ok(after.damage.values.contains("1.25"), "at ×1.25")


func test_damage_taken_mod(t) -> void:
	var att := _u("a", "staff", "fire")
	var proof := _ench(_u("p", "axe", "water"), "fireproof")
	var bare := _u("q", "axe", "water")
	var b := _fight([att], [proof, bare], [C], [_nb(C, 0), _nb(C, 3)])
	var fc := b.forecast_basic(att, proof)
	t.eq(fc.damage.value, maxf(1.0, roundf(b.forecast_basic(att, bare).damage.value * 0.85)), "Fireproof: fire −15%")
	t.ok(fc.damage.formula.contains("Fireproof"), "in the breakdown")
	t.eq(b._tile_dmg(proof, 8.0, "fire"), BWTiles.tile_damage(proof, 8.0, "fire", 0.5), "Fireproof: burning tiles at half")
	var visor := _ab(_u("v", "axe", "water"), "visor")
	var b2 := _fight([att], [visor], [C], [_nb(C, 0)])
	var fv := b2.forecast_basic(att, visor)
	t.near(fv.crit_mult, 1.25, 0.001, "Visor: crits against you ×1.25")
	t.ok(fv.crit.formula.contains("Visor"), "shown on the crit line")


func test_affinity_gain_plus(t) -> void:
	for attuned in [true, false]:
		var me := _u("me", "staff", "fire")
		if attuned:
			_ab(me, "attuned")
		var b := _fight([me], [_u("f", "axe", "water", { "con": 40 })], [C], [_nb(C, 0)])
		var before := int(me.affinity.fire)
		b.attack(me, b.foes_of(me)[0])
		t.eq(int(me.affinity.fire) - before, 2 if attuned else 1, "Attuned %s: affinity per attack" % attuned)


func test_immune(t) -> void:
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	for unbowed in [false, true]:
		var me := _ench(_u("me", "axe", "fire", { "dex": 60 }), "impact")
		var foe := _u("f", "axe", "water", { "con": 40 })
		if unbowed:
			_ab(foe, "unbowed")
		var b := _fight([me], [foe], [C], [E])
		b.attack(me, foe)
		t.eq(foe.pos, E if unbowed else E2, "Impact vs Unbowed=%s" % unbowed)
		if unbowed:
			t.eq(_events(b, "displace_resisted").size(), 1, "the resist is an event")
	# Unflinching covers allies next to the holder.
	var me2 := _ench(_u("me", "axe", "fire", { "dex": 60 }), "impact")
	var f1 := _u("f1", "axe", "water", { "con": 40 })
	var f2 := _ab(_u("f2", "axe", "water"), "unflinching")
	var b2 := _fight([me2], [f1, f2], [C], [E, _nb(E, 1)])
	b2.attack(me2, f1)
	t.eq(f1.pos, E, "Unflinching: the neighbour can't be knocked back")
	# Wading and Sure Stride: terrain and water costs.
	var wader := _ench(_u("w", "sword", "water"), "wading")
	var plain := _u("p", "sword", "water")
	var b3 := _fight([wader, plain], [_far()], [C, Vector2i(5, 8)], [FAR])
	b3.tiles.apply([E], "water", "x", 3)
	b3.tiles.apply([_nb(Vector2i(5, 8), 0)], "water", "x", 3)
	t.eq(b3.reachable(wader)[E].cost, 1, "Wading: water 3 costs nothing extra")
	_turn(b3, plain)
	t.eq(b3.reachable(plain)[_nb(Vector2i(5, 8), 0)].cost, 3, "control: water 3 = 1 + 2")
	var strider := _ab(_u("s", "sword", "fire"), "sure_stride")
	var b4 := _fight([strider], [_far()], [C], [FAR])
	b4.board.set_cell(E, "muddy")
	t.eq(b4.reachable(strider)[E].cost, 1, "Sure Stride: mud costs 1")


# ------------------------------------------------------------------ weapon keys

func test_aoe_radius_plus(t) -> void:
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	var spare := Vector2i(-1, -1)
	for n in BWHex.neighbors(E):
		if BWHex.distance(n, C) == 2 and n != E2:
			spare = n
			break
	var me := _ench(_u("me", "axe", "fire", { "dex": 60 }), "cleaving")
	var ally := _u("al", "sword", "fire")
	var f1 := _u("f1", "axe", "water", { "con": 40 })
	var f2 := _u("f2", "axe", "water", { "con": 40 })
	var b := _fight([me, ally], [f1, f2], [C, spare], [E, E2])
	b.attack(me, f1)
	var hit := _events(b, "attack").map(func(e): return e.target)
	t.eq(hit, ["f1", "f2"], "Cleaving: the basic also hits the ring around the target, once each")
	t.ok(not "al" in hit, "and spares allies there")
	# Channelling: the staff's Surge reaches one more ring.
	var T := X
	var outer := _nb(_nb(T, 0), 0)
	for ch in [false, true]:
		var mage := _u("m", "staff", "fire")
		if ch:
			_ench(mage, "channelling")
		var foe := _u("f", "axe", "water")
		var b2 := _fight([mage], [foe], [C], [outer])
		var pv := b2.skill_preview(mage, "surge", "fire", T)
		t.eq("f" in pv.units, ch, "Channelling=%s: a foe 2 from the Surge's centre" % ch)
		if ch:
			b2.use_skill(mage, "surge", "fire", T)
			t.eq(b2.tiles.intensity(outer, "fire"), 0, "the added ring takes damage, not paint")


func test_range_mod(t) -> void:
	var b := _fight([_u("a")], [_far()], [C], [FAR])
	t.eq(b.weapon_range(_ench(_u("s", "sword"), "piercing_strikes")), 2, "Piercing: sword range 1 × 2")
	t.eq(b.weapon_range(_ench(_u("l", "bow"), "longshot")), 8, "Longshot: bow 6 + 2")
	t.eq(b.weapon_range(_ab(_u("ab", "sword"), "ammo_belt")), 1, "Ammo Belt: not on a sword")
	t.eq(b.weapon_range(_ab(_u("ab2", "bow"), "ammo_belt")), 7, "Ammo Belt: bows +1")
	var thrower := _ench(_u("th", "daggers", "fire"), "throwing")
	var foe := _u("f", "axe", "water")
	var b2 := _fight([thrower], [foe], [C], [Vector2i(5, 2)])
	t.eq(b2.weapon_range(thrower), 3, "Throwing: daggers 1 + 2")
	t.ok(b2.in_range(thrower, foe), "a target 3 away is in reach")
	var fc := b2.forecast_basic(thrower, foe)
	t.ok(fc.damage.formula.contains("beyond normal range"), "the long throw is named")
	foe.pos = _nb(C, 0)
	t.ok(not b2.forecast_basic(thrower, foe).damage.formula.contains("beyond"), "no penalty in normal reach")


func test_multi_hit(t) -> void:
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	var me := _ench(_u("me", "daggers", "fire", { "dex": 60 }), "doubleshot")
	var foe := _u("f", "axe", "water", { "con": 40 })
	var b := _fight([me], [foe], [C], [E])
	var plain: float = b.forecast_basic(me, foe).damage.value
	var strikes := b.basic_strikes(me, foe)
	t.eq(strikes.size(), 2, "Doubleshot: two strikes")
	t.near(strikes[0].share, 0.75, 0.001, "at 75%")
	t.eq(b.forecast_basic(me, foe, 0.75, "x").damage.value, maxf(1.0, roundf(plain * 0.75)), "75% in the forecast")
	b.attack(me, foe)
	t.eq(_events(b, "attack").size(), 2, "each strike rolls and lands as its own event")
	# Lancing: the unit behind takes 75%.
	var lancer := _ench(_u("l", "lance", "fire", { "dex": 60 }), "lancing")
	var front := _u("f1", "axe", "water", { "con": 40 })
	var back := _u("f2", "axe", "water", { "con": 40 })
	var b2 := _fight([lancer], [front, back], [C], [E, E2])
	b2.attack(lancer, front)
	t.eq(_events(b2, "attack").map(func(e): return e.target), ["f1", "f2"], "Lancing: passes through to the next in line")
	# Spreadshot: one shot per line, the side lines included.
	var archer := _ench(_u("a", "bow", "fire", { "dex": 60 }), "spreadshot")
	var ahead := _u("f1", "axe", "water", { "con": 40 })
	var side := _u("f2", "axe", "water", { "con": 40 })
	var b3 := _fight([archer], [ahead, side], [C], [Vector2i(8, 5), _nb(_nb(C, 1), 1)])
	var ss := b3.basic_strikes(archer, ahead)
	t.eq(ss.size(), 2, "Spreadshot: the main line and the side line with a foe on it")
	t.eq(ss[1].unit, side, "the side shot finds the foe on its line")
	t.near(ss[1].share, 0.5, 0.001, "at 50%")


func test_move_after_attack(t) -> void:
	var me := _ench(_u("me", "lance", "fire", { "dex": 60 }), "flowing")
	var foe := _u("f", "axe", "water", { "con": 40 })
	var E := _nb(C, 0)
	var b := _fight([me], [foe], [C], [Vector2i(8, 5)])
	t.ok(b.move(me, E), "move first")
	t.ok(not b.can_move(me), "moved: no more moving")
	b.attack(me, foe)
	t.ok(b.can_move(me), "Flowing: attacking grants a second move")
	var maxc := 0
	for h in b.reachable(me):
		maxc = maxi(maxc, b.reachable(me)[h].cost)
	t.eq(maxc, 2, "of 2 hexes")
	t.ok(b.move(me, _nb(_nb(E, 3), 3)), "and it moves")
	t.ok(not b.can_move(me), "once")
	t.eq(_events(b, "move")[-1].get("kind", ""), "flow", "the move is tagged for the view")


func test_knockback(t) -> void:
	var E := _nb(C, 0)
	var E2 := _nb(E, 0)
	var me := _ench(_u("me", "axe", "fire", { "dex": 60 }), "impact")
	var foe := _u("f", "axe", "water", { "con": 40 })
	var b := _fight([me], [foe], [C], [E])
	b.attack(me, foe)
	t.eq(foe.pos, E2, "Impact: 1 hex straight back")
	var hooker := _ench(_u("h", "lance", "fire", { "dex": 60 }), "hooking")
	var foe2 := _u("f", "axe", "water", { "con": 40 })
	var b2 := _fight([hooker], [foe2], [C], [E2])
	b2.attack(hooker, foe2)
	t.eq(foe2.pos, E, "Hooking: dragged 1 hex in")
	# on=trigger, thunder: Jolting knocks the detonation's occupant away from you.
	var jolt := _ench(_u("j", "staff", "thunder"), "jolting")
	var foe3 := _u("f", "axe", "water", { "con": 40 })
	var b3 := _fight([jolt], [foe3], [C], [X])
	b3.tiles.apply([X], "fire", "x")
	b3.paint([X], "thunder", jolt)
	t.eq(foe3.pos, BWHex.neighbors(X)[BWHex.direction_index(C, X)], "Jolting: pushed away from the detonator")
	# on=trigger, wind: Howling pushes units on the copied tiles outward.
	var howl := _ench(_u("w", "staff", "wind"), "howling")
	var foe4 := _u("f", "axe", "water", { "con": 40 })
	var Y := _nb(X, 0)
	var b4 := _fight([howl], [foe4], [C], [Y])
	b4.tiles.apply([X], "fire", "x")
	b4.paint([X], "wind", howl)
	t.eq(foe4.pos, _nb(Y, 0), "Howling: pushed 1 hex out from the gale")


func test_counter_attack(t) -> void:
	var me := _ench(_u("me", "daggers", "fire", { "dex": 60 }), "doubleshot")
	var duelist := _ench(_u("d", "sword", "water", { "dex": 60, "con": 40 }), "riposting")
	var b := _fight([me], [duelist], [C], [_nb(C, 0)])
	var h := me.hp
	b.attack(me, duelist)
	var cs := _events(b, "counter")
	t.eq(cs.size(), 1, "Riposting: one counter per enemy turn, even against two strikes")
	t.eq(cs[0].target, "me", "aimed at the attacker")
	t.eq(h - me.hp, int(cs[0].result.damage), "and its damage lands")
	var fc := b.forecast_basic(duelist, me, 0.5, "Riposting Sword (counter)")
	t.ok(fc.damage.formula.contains("(counter)"), "counter strikes at 50%, named")
	var archer := _u("a", "bow", "fire", { "dex": 60 })
	var b2 := _fight([archer], [_ench(_u("d", "sword", "water", { "con": 40 }), "riposting")], [C], [Vector2i(5, 1)])
	b2.attack(archer, b2.foes_of(archer)[0])
	t.eq(_events(b2, "counter").size(), 0, "out of range: no counter")


func test_attack_mod(t) -> void:
	var E := _nb(C, 0)
	var foe := _u("f", "axe", "water", { "def": 12 })
	var plain := _u("p", "sword", "fire")
	var keen := _ench(_u("k", "sword", "fire"), "keen")
	var b := _fight([plain, keen], [foe], [C, Vector2i(6, 4)], [E])
	var base := b.forecast_basic(plain, foe)
	var fk := b.forecast_basic(keen, foe)
	t.near(fk.crit.value, base.crit.value + 10.0, 0.001, "Keen: +10 crit")
	t.ok(fk.crit.formula.contains("Keen"), "named")
	var serr := _ench(_u("s", "sword", "fire"), "serrated")
	t.near(b.forecast_basic(serr, foe).crit_mult, 2.0, 0.001, "Serrated: crits ×2")
	# Sundering: 16 − 0.75 × 12 = 7; ignoring 25%: 16 − 0.75 × 9 = 9.25 → 9.
	var sund := _ench(_u("u", "sword", "fire"), "sundering")
	t.eq(base.damage.value, 7.0, "control")
	t.eq(b.forecast_basic(sund, foe).damage.value, 9.0, "Sundering: 25% of DEF ignored")
	t.ok(b.forecast_basic(sund, foe).damage.formula.contains("Sundering"), "named in the mitigation")
	# Jousting: +10% per hex moved this turn, up to 40%.
	var joust := _ench(_u("j", "lance", "fire"), "jousting")
	var foe2 := _u("f2", "axe", "water")
	var b2 := _fight([joust], [foe2], [C], [Vector2i(9, 5)])
	b2.move(joust, Vector2i(8, 5))
	var fj := b2.forecast_basic(joust, foe2)
	t.ok(fj.damage.formula.contains("Jousting Lance (3 hexes moved)"), "Jousting counts the hexes")
	t.ok(fj.damage.values.contains("1.30"), "×1.30")
	# Deadeye (ability): +5 hit per hex between.
	var eye := _ab(_u("e", "bow", "fire"), "deadeye")
	var bow := _u("b", "bow", "fire")
	var foe3 := _u("f3", "axe", "water")
	var b3 := _fight([eye, bow], [foe3], [C, C], [X])
	t.near(b3.forecast_basic(eye, foe3).hit.value, b3.forecast_basic(bow, foe3).hit.value + 10.0, 0.001,
		"Deadeye: 2 hexes between = +10 hit")
	# Fletcher's Eye gates on min_range 3.
	var fl := _ab(_u("fe", "bow", "fire"), "fletchers_eye")
	var b4 := _fight([fl], [foe3], [C], [X])
	t.ok(b4.forecast_basic(fl, foe3).crit.formula.contains("Fletcher"), "at 3: +5 crit")
	foe3.pos = _nb(_nb(C, 0), 0)
	t.ok(not b4.forecast_basic(fl, foe3).crit.formula.contains("Fletcher"), "at 2: nothing")
	# Conducting: +25% against a target on charge.
	var cond := _ench(_u("c", "staff", "fire"), "conducting")
	var foe5 := _u("f5", "axe", "water")
	var b5 := _fight([cond], [foe5], [C], [E])
	t.ok(not b5.forecast_basic(cond, foe5).damage.formula.contains("Conducting"), "bare ground: nothing")
	b5.tiles.apply([E], "dark", "x")
	t.ok(b5.forecast_basic(cond, foe5).damage.formula.contains("Conducting"), "on charge: ×1.25")
	# Dragoon's Descent: +10% per level above the target.
	var dragoon := _ab(_u("dr", "sword", "fire"), "dragoons_descent")
	var foe6 := _u("f6", "axe", "water")
	var b6 := _fight([dragoon], [foe6], [C], [E])
	b6.board.set_cell(C, "neutral", 2)
	var fd := b6.forecast_basic(dragoon, foe6)
	t.ok(fd.damage.formula.contains("(2 above)") and fd.damage.values.contains("1.20"), "Dragoon's Descent: 2 levels = ×1.2")


func test_skill_cd_minus(t) -> void:
	var me := _ench(_u("me", "bow", "fire"), "quickdraw")
	var b := _fight([me], [_far()], [C], [FAR])
	b.use_skill(me, "arcing_shot", "fire", X)
	t.eq(int(me.cooldowns["arcing_shot_fire"]), 1, "Quickdraw: cooldown 2 -> 1")
	var once := _ab(_u("q", "bow", "fire"), "quick_draw")
	var b2 := _fight([once], [_far()], [C], [FAR])
	b2.use_skill(once, "arcing_shot", "fire", X)
	t.eq(int(once.cooldowns["arcing_shot_fire"]), 1, "Quick Draw: the first time, 1 early")
	_turn(b2, once)
	b2.use_skill(once, "arcing_shot", "fire", X)
	t.eq(int(once.cooldowns["arcing_shot_fire"]), 2, "once per battle")


func test_guard(t) -> void:
	var me := _ench(_u("me", "sword", "fire", { "dex": 60 }), "guarding")
	var foe := _u("f", "axe", "water", { "con": 40 })
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	var before: float = b.forecast_basic(foe, me).damage.value
	b.attack(me, foe)
	t.near(float(me.fx.guard), 25.0, 0.001, "Guarding: raised after attacking")
	var fc := b.forecast_basic(foe, me)
	t.eq(fc.damage.value, maxf(1.0, roundf(before * 0.75)), "incoming −25%")
	t.ok(fc.damage.formula.contains("Guarding"), "named")
	_turn(b, me)
	t.ok(not me.fx.has("guard"), "gone at your next turn")


# ------------------------------------------------------------------ ability keys

func test_trigger_stat(t) -> void:
	var me := _ab(_u("me", "sword", "fire", { "con": 100 }), "brace")
	var b := _fight([me], [_far()], [C], [FAR])
	for i in 5:
		b._tile_hurt(me, 5, "test", "")
	t.eq(int(me.battle_mods.get("def", 0)), 3, "Brace: +1 def per hit taken, capped at +3")
	t.eq(me.stat("def"), 7, "and stat() reads it")
	t.eq(_events(b, "stat_up").size(), 3, "one stat_up event per grant")
	# low_hp, once: Second Wind.
	var sw := _ab(_u("sw", "sword", "fire"), "second_wind")
	var b2 := _fight([sw], [_far()], [C], [FAR])
	b2._tile_hurt(sw, 60, "test", "")
	t.eq(int(sw.battle_mods.get("spd", 0)), 2, "Second Wind: below half, +2 spd")
	sw.hp = sw.max_hp()
	b2._tile_hurt(sw, 60, "test", "")
	t.eq(int(sw.battle_mods.get("spd", 0)), 2, "only the first time")
	# knockout: Encore. ally_ko: Heavy Is the Head. avoided: Poise.
	var enc := _ab(_u("en", "sword", "fire"), "encore")
	var crown := _ab(_u("cr", "sword", "fire"), "heavy_is_the_head")
	var buddy := _u("bu", "sword", "fire")
	var f1 := _u("f1", "axe", "water")
	var b3 := _fight([enc, crown, buddy], [f1, _far()], [C, Vector2i(0, 5), Vector2i(0, 6)], [X, FAR])
	b3._tile_hurt(f1, 9999, "test", "en")
	t.eq(int(enc.battle_mods.get("spd", 0)), 1, "Encore: a knockout credited to you, +1 spd")
	b3._tile_hurt(buddy, 9999, "test", "")
	t.eq(int(crown.battle_mods.get("wil", 0)), 2, "Heavy Is the Head: an ally falls, +2 wil")
	t.eq(int(crown.battle_mods.get("res", 0)), 2, "and +2 res")
	var poise := _ab(_u("po", "sword", "fire"), "poise")
	var b4 := _fight([poise], [_far()], [C], [FAR])
	b4._after_blow(b4.foes_of(poise)[0], poise, { "hit": false, "damage": 0 }, poise.hp, "")
	t.eq(int(poise.battle_mods.get("wil", 0)), 1, "Poise: an avoided attack, +1 wil")


func test_aura_mod(t) -> void:
	var E := _nb(C, 0)
	var guard := _ab(_u("g", "sword", "fire"), "guardian")
	var ally := _u("a", "sword", "fire")
	var b := _fight([guard, ally], [_far()], [C, E], [FAR])
	t.eq(ally.stat("def"), 6, "Guardian: an ally next to you +2 def")
	t.eq(guard.stat("def"), 4, "not the holder")
	ally.pos = Vector2i(5, 9)
	t.eq(ally.stat("def"), 4, "out of reach: gone")
	var leap := _ab(_u("l", "sword", "fire"), "leap_ready")
	t.eq(leap.move_range(), 5, "Leap Ready: +1 move, on the sheet too")
	var b2 := _fight([leap], [_far()], [C], [FAR])
	t.eq(leap.move_range(), 5, "and in battle")
	# Heads Up (+5 avoid to allies within 2) and Royal Presence (+10% damage).
	var cap := _ab(_u("c", "sword", "fire"), "heads_up")
	var crown := _ab(_u("k", "sword", "fire"), "royal_presence")
	var mate := _u("m", "sword", "fire")
	var foe := _u("f", "axe", "water")
	var b3 := _fight([cap, crown, mate], [foe], [C, _nb(C, 3), E], [_nb(E, 0)])
	var fc := b3.forecast_basic(foe, mate)
	t.near(fc.avoid.value, 5.0 + 0.4 + 5.0, 0.001, "Heads Up: +5 avoid")
	t.ok(fc.avoid.formula.contains("Heads Up (c)"), "named with its holder")
	t.ok(b3.forecast_basic(mate, foe).damage.formula.contains("Royal Presence (k)"), "Royal Presence: ally damage ×1.1")


func test_glance_mod(t) -> void:
	var E := _nb(C, 0)
	var foe := _u("f", "axe", "water")
	var bast := _ab(_u("b", "sword", "fire"), "bastion")
	var b := _fight([bast], [foe], [C], [E])
	t.near(b.forecast_basic(foe, bast).glance.value, 28.0, 0.001, "Bastion: (10 + 4) × 2")
	var woven := _ab(_u("w", "sword", "fire"), "woven_rings")
	var b2 := _fight([woven], [foe], [C], [E])
	var fw := b2.forecast_basic(foe, woven)
	t.near(fw.glance_mult, 0.25, 0.001, "Woven Rings: glances deal 25%")
	t.ok(fw.glance.formula.contains("Woven Rings"), "named on the glance line")
	var sc := _ab(_u("s", "sword", "fire"), "shoulder_check")
	var b3 := _fight([sc], [foe], [C], [E])
	t.near(b3.forecast_basic(foe, sc).glance.value, 19.0, 0.001, "Shoulder Check: +5 vs melee")
	var archer := _u("a", "bow", "fire")
	var b4 := _fight([sc], [archer], [C], [X])
	t.near(b4.forecast_basic(archer, sc).glance.value, 14.0, 0.001, "nothing vs ranged")
	var rg := _ab(_u("r", "sword", "fire"), "ring_guard")
	var mate := _u("m", "sword", "fire")
	var b5 := _fight([rg, mate], [foe], [C, E], [_nb(E, 0)])
	t.near(b5.forecast_basic(foe, mate).glance.value, 19.0, 0.001, "Ring Guard: the ally next to you +5")
	t.near(b5.forecast_basic(foe, rg).glance.value, 14.0, 0.001, "not the holder")


func test_stat_share(t) -> void:
	var u := _ab(_u("s", "sword", "fire", { "dex": 10 }), "steel_under_cloth")
	t.eq(u.stat("str"), 4 + 2, "Steel Under Cloth: + floor(25% × DEX 10)")
	var both := _u("b", "sword", "fire", { "dex": 8, "str": 8 })
	both.abilities = { "passive": { "id": "nimble_strength", "rank": 1 } }
	both.refresh_effects()
	t.eq(both.stat("dex"), 10, "Nimble Strength: + 25% STR")


# ------------------------------------------------------------------ plumbing

func test_every_mod_is_in_the_breakdown(t) -> void:
	var att := _ab(_ench(_u("a", "bow", "fire"), "keen"), "deadeye")
	var crown := _ab(_u("k", "sword", "fire"), "royal_presence")
	var dfn := _ab(_ench(_u("d", "axe", "water"), "fireproof"), "supple")
	var b := _fight([att, crown], [dfn], [C, _nb(C, 3)], [X])
	b.tiles.apply([X], "dark", "x")
	var fc := b.forecast_basic(att, dfn)
	t.ok(fc.mods.size() >= 5, "ground + keen + deadeye + royal presence + supple")
	var text := ""
	for k in ["hit", "avoid", "glance", "crit", "damage"]:
		text += str(fc[k].formula) + "|"
	for m in fc.mods:
		t.ok(text.contains(str(m.label)), "'%s' is in a hovered formula" % m.label)


func test_prepare_for_battle(t) -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))
	var r := BWRun.start(ids, 5)
	var u: BWUnit = r.squad[0]
	r.learned[u.id] = ["deadeye", "brace", "ward", "flair"]
	r.ability_ranks[u.id] = { "brace": 2 }
	var auto := r.prepare_for_battle([u])
	t.eq(u.abilities.reactive.id, "brace", "auto-equip: the first learned reactive")
	t.eq(u.abilities.reactive.rank, 2, "at its trained rank")
	t.eq(u.abilities.supportive.id, "deadeye", "first supportive")
	t.eq(u.abilities.passive.id, "flair", "first passive")
	t.eq(auto.size(), 3, "each auto-equip is reported")
	t.eq(r.equipped_ability[u.id].reactive, "brace", "and saved")
	t.ok(r.equip_ability(u, "ward"), "equip another")
	t.eq(r.prepare_for_battle([u]).size(), 0, "nothing to auto-equip now")
	t.eq(u.abilities.reactive.id, "ward", "the chosen one is used")
	t.ok(BWEffects.has(u, "trigger_stat"), "and its effect is live")
	var stranger := _u("x")
	r.prepare_for_battle([stranger])
	t.ok(stranger.abilities.is_empty(), "units outside the run get none")


func test_effects_fight_reproduces(t) -> void:
	var histories: Array = []
	for k in 2:
		var p1 := _ab(_ench(_u("p1", "staff", "fire"), "explosive"), "imbued")
		var p2 := _ab(_ench(_u("p2", "daggers", "fire"), "doubleshot"), "brace")
		var p3 := _ab(_ench(_u("p3", "sword", "water"), "riposting"), "guardian")
		var e1 := _ab(_ench(_u("e1", "axe", "water"), "impact"), "enrage")
		var e2 := _ab(_ench(_u("e2", "bow", "thunder"), "spreadshot"), "deadeye")
		var e3 := _ab(_ench(_u("e3", "lance", "dark"), "flowing"), "flair")
		var b := BWBattle.new(_board(), 99)
		b.setup([p1, p2, p3], [e1, e2, e3])
		var turns := 0
		while not b.over and turns < 600:
			BWAI.take_turn(b)
			turns += 1
		t.ok(b.over, "a fight with effects on both sides ends (%d turns)" % turns)
		histories.append(str(b.history))
	t.ok(histories[0] == histories[1], "same seed, same fight, effects included")

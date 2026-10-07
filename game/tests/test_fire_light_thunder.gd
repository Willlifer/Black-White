extends RefCounted
## D285-D292 Element Overhaul, fire / light / thunder (design/ELEMENTS-v3.md
## §3, §5, §7 with the author's rulings of 2026-10-07; ELEMENTS.md §15; D306 Self-detonate):
## Overheat and its caps, Conflagration's depth, Trailblazer, Phoenix Heart;
## beams (forming, blocking, limits), Empowered, Dawn, Prism, Overflow,
## Magnify's caps; Static Blades, Blast Rider, Daisy Chain; the AI hooks.

const C := Vector2i(6, 6)
const E := 0                 # heading index east (same row, col + 1)


func _board(n: int = 13, terrain: Dictionary = {}) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			var h := Vector2i(c, r)
			cells.append({ "q": c, "r": r, "terrain": terrain.get(h, "neutral"), "elevation": 0 })
	return BWBoard.from_dict({ "name": "flt", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[n - 1, 0], [n - 1, 1], [n - 1, 2]] } })


func _u(id: String, wc: String = "sword", el: String = "wind", ks: Array = []) -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	u.keystones = ks.duplicate()
	return u


func _fight(players: Array, foes: Array, ppos: Array, fpos: Array, terrain: Dictionary = {}) -> BWBattle:
	var b := BWBattle.new(_board(13, terrain), 7)
	b.setup(players, foes, ppos)
	for i in players.size():
		players[i].pos = ppos[i]
	for i in foes.size():
		foes[i].pos = fpos[i]
	for u in players + foes:
		u.facing = -1
		u.statuses = {}
		u.fx = {}
	b.tiles.entries.clear()
	b.refresh_effects()
	b.history.clear()
	return b


func _turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _lay(b: BWBattle, h: Vector2i, hv: int, v: int = 0, src: String = "") -> void:
	b.tiles.entries[h] = b.tiles._entry(hv, v, "", src, "cast")


func _fuse(b: BWBattle, h: Vector2i, src: String) -> void:
	b.tiles.entries[h] = b.tiles._entry(0, 0, "fuse", src, "cast")


func _nb(h: Vector2i, d: int) -> Vector2i:
	return BWHex.neighbors(h)[d]


func _far(h: Vector2i, d: int, n: int) -> Vector2i:
	var x := h
	for i in n:
		x = _nb(x, d)
	return x


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return str(e.type) == type)


func _hurt(b: BWBattle, u: BWUnit, cause: String) -> int:
	var n := 0
	for e in b.history:
		if str(e.type) == "tile_damage" and str(e.unit) == u.id and str(e.cause) == cause:
			n += int(e.amount)
	return n


# ------------------------------------------------------------------ Overheat

func test_overheat_erupts(t) -> void:
	var me := _u("me", "staff", "fire")
	var ally := _u("al")
	var foe := _u("fo")
	var far := _u("fx")
	var b := _fight([me, ally], [foe, far], [Vector2i(0, 12), _nb(C, 1)], [_nb(C, 0), Vector2i(12, 12)])
	_lay(b, C, 3)
	_lay(b, _nb(C, 2), -3)                       # water 3 -> water 1
	_lay(b, _nb(C, 3), 1)                        # fire 1 -> fire 3
	b.tiles.entries[_nb(C, 4)] = b.tiles._entry(1, 0, "", "", "cast")
	b.tiles.entries[_nb(C, 4)].glaze = 2         # glazed: skipped
	_fuse(b, _nb(C, 5), "fo")                    # marked: skipped (the fuse doesn't fire)
	var r := b.paint([C], "fire", me)
	t.eq((r.get("overheat", []) as Array).size(), 1, "fresh fire on fire 3 erupts once")
	t.eq(b.tiles.intensity(C, "fire"), 2, "the centre vents to fire 2")
	t.eq(b.tiles.intensity(_nb(C, 0), "fire"), 2, "an empty ring hex gets fire 2")
	t.eq(str(b.tiles.at(_nb(C, 0)).origin), "spread", "ring fire is propagated (no grass ignition)")
	t.eq(b.tiles.intensity(_nb(C, 2), "water"), 1, "water 3 on the ring becomes water 1")
	t.eq(b.tiles.intensity(_nb(C, 3), "fire"), 3, "fire 1 on the ring becomes fire 3")
	t.eq(b.tiles.intensity(_nb(C, 4), "fire"), 1, "a glazed ring hex is skipped")
	t.eq(str(b.tiles.at(_nb(C, 5)).marker), "fuse", "a marked ring hex is skipped, its fuse unfired")
	t.ok(r.detonations.is_empty(), "nothing detonated")
	t.eq(_hurt(b, foe, "overheat"), b._tile_dmg(foe, 6.0, "fire"), "a foe on the ring takes 6%")
	t.eq(_hurt(b, ally, "overheat"), b._tile_dmg(ally, 6.0, "fire"), "an ally on the ring takes 6% too")
	t.eq(_hurt(b, far, "overheat"), 0, "a unit off the ring takes nothing")
	t.eq(_ev(b, "overheat").size(), 1, "one overheat event")


func test_overheat_caps(t) -> void:
	var me := _u("me", "staff", "fire")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b, C, 2)
	var r := b.paint([C], "fire", me)
	t.ok(not r.has("overheat"), "fire 2 -> 3 does not erupt (it must already be fire 3)")
	r = b.paint([C], "fire", me, 1, false, { "propagated": true })
	t.ok(not r.has("overheat"), "propagated fire never erupts")
	r = b.paint([C], "fire", me)
	t.eq((r.get("overheat", []) as Array).size(), 1, "a fresh recast erupts")
	r = b.paint([C], "fire", me)
	t.ok(not r.has("overheat"), "the vented centre (fire 2) needs another recast")
	# two adjacent fire 3 in one shape: each erupts once, neither paints the other
	var b2 := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	var c2 := _nb(C, 0)
	_lay(b2, C, 3)
	_lay(b2, c2, 3)
	r = b2.paint([C, c2], "fire", me)
	t.eq((r.overheat as Array).size(), 2, "two centres, two eruptions (once per hex per action)")
	t.eq(b2.tiles.intensity(C, "fire"), 2, "each centre vents to 2")
	t.eq(b2.tiles.intensity(c2, "fire"), 2, "and is not raised by its neighbour's ring")
	var shared := _nb(C, 1)                      # a neighbour of both
	t.eq(b2.tiles.intensity(shared, "fire"), 3, "a hex on both rings gets +2 twice (capped at 3)")


func test_conflagration_depth(t) -> void:
	var me := _u("me", "staff", "fire", ["conflagration"])
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	var r1 := _nb(C, 0)
	var r2 := _nb(r1, 0)
	var r3 := _nb(r2, 0)
	_lay(b, C, 3)
	_lay(b, r1, 1)         # raised to 3 by C: erupts (depth 2)
	_lay(b, r2, 1)         # raised to 3 by r1's ring: depth 3 would be too deep
	var r := b.paint([C], "fire", me)
	var depths: Array = (r.overheat as Array).map(func(x): return int(x.depth))
	t.eq(depths, [1, 2], "the chain stops at depth 2")
	t.eq(b.tiles.intensity(r2, "fire"), 3, "the depth-2 ring raises r2 to fire 3 ...")
	t.ok(not (r.overheat as Array).any(func(x): return x.hex == r2), "... but r2 does not erupt")
	t.eq(b.tiles.intensity(r3, "fire"), 0, "and r3 is untouched")
	var me2 := _u("m2", "staff", "fire")
	var b2 := _fight([me2], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b2, C, 3)
	_lay(b2, r1, 1)
	r = b2.paint([C], "fire", me2)
	t.eq((r.overheat as Array).size(), 1, "without Conflagration nothing chains")


func test_trailblazer(t) -> void:
	var me := _u("me", "sword", "fire", ["trailblazer"])
	var foe := _u("fo")
	var b := _fight([me], [foe], [C], [Vector2i(12, 12)])
	_lay(b, _far(C, E, 2), 2, 0, "fo")
	_turn(b, me)
	b.history.clear()
	var dest := _far(C, E, 3)
	var hp := me.hp
	t.ok(b.move(me, dest), "it walks 3 east")
	t.eq(b.tiles.intensity(C, "fire"), 1, "fire 1 on the start hex it left")
	t.eq(b.tiles.intensity(_nb(C, E), "fire"), 1, "and on the next")
	t.eq(b.tiles.intensity(_far(C, E, 2), "fire"), 3, "a fire 2 it crossed gets +1 (propagated: no eruption)")
	t.eq(b.tiles.intensity(dest, "fire"), 0, "not on the hex it stands on")
	t.eq(me.hp, hp, "no crossing burns")
	t.eq(int(me.fx.trail_n), 3, "3 of 4 used")
	t.eq(_ev(b, "overheat").size(), 0, "the trail never erupts")


func test_phoenix_heart(t) -> void:
	var me := _u("me", "fists", "fire", ["phoenix_heart"])
	var foe := _u("fo", "axe")
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	_lay(b, C, 1, 0, "me")
	me.hp = me.max_hp() - 20
	var hp := me.hp
	_turn(b, me)
	t.eq(me.hp, hp, "its own fire 1 doesn't burn it")
	_lay(b, C, 3, 0, "fo")
	_turn(b, me)
	t.ok(me.hp > hp, "fire 3 (anyone's) heals it instead of burning")
	t.ok(_ev(b, "phoenix").any(func(e): return str(e.what) == "heal"), "a phoenix heal event")
	# the KO hold, once a battle
	me.hp = 3
	b.history.clear()
	b._tile_hurt(me, 50, "slam", "fo")
	t.eq(me.hp, 1, "a KO on fire leaves it at 1 HP")
	t.eq(_ev(b, "overheat").size(), 1, "and its hex Overheats")
	t.eq(b.tiles.intensity(C, "fire"), 2, "the hex vents to fire 2")
	t.ok(_hurt(b, foe, "overheat") > 0, "the foe beside it takes the ring")
	b._tile_hurt(me, 50, "slam", "fo")
	t.ok(not me.alive(), "only once a battle")


# ------------------------------------------------------------------ beams

func test_beam_forms_and_ticks(t) -> void:
	var a := _u("a")
	var c := _u("c")
	var foe := _u("fo")
	var foe2 := _u("f2")
	var ca := _far(C, E, 3)
	var b := _fight([a, c], [foe, foe2], [C, ca], [_nb(C, E), Vector2i(12, 12)])
	_lay(b, C, 0, 1)
	_lay(b, ca, 0, 2)
	var bms := BWBeams.beams(b)
	t.eq(bms.size(), 1, "two allies on light, in line, 3 apart: one beam")
	t.eq((bms[0].hexes as Array).size(), 2, "two beam hexes between them")
	t.eq(float(bms[0].pct), 6.0, "4% + 2% x the lower end's light (1)")
	b.history.clear()
	BWBeams.tick(b)
	t.eq(_hurt(b, foe, "light_beam"), b._tile_dmg(foe, 6.0, "light"), "the foe on the beam takes 6%")
	t.eq(_hurt(b, foe2, "light_beam"), 0, "a foe off it takes nothing")
	t.eq(BWBeams.empowered(a), 15, "an end is Empowered +15%")
	t.eq(BWBeams.empowered(c), 15, "so is the other end")
	t.eq(BWBeams.empowered(foe), 0, "a foe is not")
	t.eq(_ev(b, "light_beams").size(), 1, "the tick's beam event")
	# Empowered on the next attack, then spent
	_turn(b, a)
	var fc := b.forecast_basic(a, foe)
	t.ok((fc.mods as Array).any(func(m): return str(m.get("tag", "")) == "Empowered"), "the forecast carries Empowered")
	b.attack(a, foe)
	t.eq(BWBeams.empowered(a), 0, "the attack spent it")
	# and it fades at the end of the unit's next turn
	_turn(b, c)
	t.eq(BWBeams.empowered(c), 15, "c still has it during its turn")
	b.tiles.entries.clear()                      # no beam at the next tick, so nothing re-empowers
	b.end_turn()
	t.ok(_ev(b, "empowered_end").any(func(e): return str(e.unit) == "c" and str(e.why) == "faded"), "it fades when c's turn ends")
	t.eq(BWBeams.empowered(c), 0, "gone")


func test_beam_blocking_and_limits(t) -> void:
	var a := _u("a")
	var c := _u("c")
	var foe := _u("fo")
	var ca := _far(C, E, 3)
	var b := _fight([a, c], [foe], [C, ca], [Vector2i(12, 12)], { _nb(C, E): "jagged" })
	_lay(b, C, 0, 1)
	_lay(b, ca, 0, 1)
	t.eq(BWBeams.beams(b).size(), 0, "rock between: no beam")
	var b2 := _fight([a, c], [foe], [C, ca], [Vector2i(12, 12)])
	_lay(b2, C, 0, 1)
	_lay(b2, ca, 0, 1)
	var mid := _nb(C, E)
	b2.tiles.entries[mid] = b2.tiles._entry(-3, 0, "", "", "cast")
	b2.tiles.entries[mid].glaze = 2
	b2.tiles.pillars[mid] = { "owner": "", "ticks": 3, "born": 1 }
	t.eq(BWBeams.beams(b2).size(), 0, "a pillar between: no beam")
	b2.tiles.pillars.clear()
	b2.tiles.entries.erase(mid)
	t.eq(BWBeams.beams(b2).size(), 1, "the line clears: the beam forms")
	c.pos = _far(C, E, 5)
	_lay(b2, c.pos, 0, 1)
	t.eq(BWBeams.beams(b2).size(), 0, "5 apart: too far")
	c.pos = Vector2i(C.x + 2, C.y + 1)
	_lay(b2, c.pos, 0, 1)
	t.ok(BWBeams.span(b2, a.pos, c.pos) == null, "off the straight line: no beam")
	t.eq(BWBeams.beams(b2).size(), 0, "so none forms")
	# five allies in a row on light: each is the end of 2 beams at most
	var row: Array = []
	var pos: Array = []
	for i in 5:
		row.append(_u("r%d" % i))
		pos.append(_far(Vector2i(1, 6), E, i * 2))
	var b3 := _fight(row, [foe], pos, [Vector2i(12, 0)])
	for p in pos:
		_lay(b3, p, 0, 1)
	var ends := {}
	var pairs := {}
	for bm in BWBeams.beams(b3):
		for id in bm.ends:
			ends[id] = int(ends.get(id, 0)) + 1
		var k := "%s|%s" % [bm.ends[0], bm.ends[1]]
		t.ok(not pairs.has(k), "one beam per pair")
		pairs[k] = true
	t.ok(ends.values().all(func(n): return int(n) <= 2), "no unit ends more than 2 beams")
	t.ok(pairs.size() >= 4, "the chain of neighbours all beam")


func test_dawn(t) -> void:
	var a := _u("a", "axe")
	var foe := _u("fo")
	var b := _fight([a], [foe], [C], [Vector2i(12, 12)])
	_lay(b, C, 0, 2)
	a.cooldowns["cleave"] = 3
	a.cooldowns["charge"] = 1
	_turn(b, a)
	t.eq(int(a.cooldowns.cleave), 1, "the longest cooldown: -1 for the turn, -1 for Dawn")
	t.eq(int(a.cooldowns.charge), 0, "the other ticks as normal")
	t.eq(_ev(b, "dawn").size(), 1, "a dawn event")


func test_prism_and_overflow(t) -> void:
	var a := _u("a", "sword", "light", ["prism", "overflow"])
	var m := _u("m")
	var c := _u("c")
	var foe := _u("fo")
	# a -> m east (2), m -> c north-east-ish: a and c not on one line
	var mp := _far(C, E, 2)
	var cp := _far(mp, 5, 2)
	var b := _fight([a, m, c], [foe], [C, mp, cp], [Vector2i(12, 12)])
	for p in [C, mp, cp]:
		_lay(b, p, 0, 1, "a")
	t.ok(BWBeams.span(b, C, cp) == null, "a and c are not in line")
	var bent: Array = BWBeams.beams(b).filter(func(x): return str(x.bend) == "m")
	t.eq(bent.size(), 1, "Prism bends a beam through m")
	t.eq(int(bent[0].empower), 25, "Overflow: the beam Empowers +25%")
	m.hp = m.max_hp() - 2
	b.history.clear()
	BWBeams.tick(b)
	t.ok(_ev(b, "heal").any(func(e): return str(e.unit) == "m"), "Prism: allies on the beam heal at the tick")
	t.ok(not (m.fx.get("light_ward", {}) as Dictionary).is_empty(), "Overflow: the excess becomes a Ward of Light")
	var w := int(m.fx.light_ward.hp)
	t.ok(w > 0 and w <= roundi(m.max_hp() * 0.15), "capped at 15% max HP")
	var hp := m.hp
	b._tile_hurt(m, w + 3, "slam", "fo")
	t.eq(m.hp, hp - 3, "the ward absorbs, then breaks")
	t.ok(not m.fx.has("light_ward"), "until hit")


func test_magnify(t) -> void:
	var holder := _u("h", "sword", "light", ["magnify"])
	var caster := _u("s", "staff", "fire")
	caster.affinity["fire"] = 10
	var foe := _u("fo")
	var b := _fight([holder, caster], [foe], [Vector2i(0, 12), C], [Vector2i(12, 12)])
	_lay(b, C, 0, 1, "h")
	_turn(b, caster)
	var tgt := _far(C, E, 3)
	var pv := b.skill_preview(caster, "surge", "fire", tgt)
	t.eq((pv.hexes as Array).size(), 19, "Surge (radius 1) magnified to radius 2")
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Magnify")), "the forecast names Magnify")
	b.use_skill(caster, "surge", "fire", tgt)
	t.eq(_ev(b, "magnify").size(), 1, "the cast spends it")
	caster.acted = false
	caster.cooldowns.clear()
	pv = b.skill_preview(caster, "surge", "fire", tgt)
	t.eq((pv.hexes as Array).size(), 7, "once per ally per turn")
	# the holder itself is not magnified on its own light
	var b2 := _fight([holder, caster], [foe], [C, Vector2i(0, 12)], [Vector2i(12, 12)])
	holder.affinity["fire"] = 10
	_lay(b2, C, 0, 1, "h")
	_turn(b2, holder)
	t.ok(BWBeams.magnifier(b2, holder) == null, "the holder's own light doesn't magnify it")
	# a radius-2 shape becomes 3, never more
	var b3 := _fight([holder, caster], [foe], [Vector2i(0, 12), C], [Vector2i(12, 12)])
	_lay(b3, C, 0, 1, "h")
	_turn(b3, caster)
	var p3 := { "hexes": b3._on_board(b3.board.area(tgt, 2)), "steps": 1, "victims": [], "element": "fire",
		"dest": caster.pos, "notes": [] }
	BWBeams.magnify(b3, caster, BWSkillRegistry.get_def("tempest"), p3)
	t.eq(int(p3.magnify.radius), 3, "radius 2 -> 3")
	var p4 := { "hexes": b3._on_board(b3.board.area(tgt, 3)), "steps": 1, "victims": [], "element": "fire",
		"dest": caster.pos, "notes": [] }
	BWBeams.magnify(b3, caster, BWSkillRegistry.get_def("tempest"), p4)
	t.eq(str(p4.magnify.kind), "step", "a radius-3 shape is not widened (a charge step instead)")
	t.eq(int(p4.steps), 2, "+1 step")
	# a non-area element skill: +1 charge step
	var b5 := _fight([holder, caster], [foe], [Vector2i(0, 12), C], [_far(C, E, 2)])
	_lay(b5, C, 0, 1, "h")
	_turn(b5, caster)
	var p5 := { "hexes": [foe.pos], "steps": 1, "victims": [foe], "element": "fire", "dest": caster.pos, "notes": [] }
	BWBeams.magnify(b5, caster, BWSkillRegistry.get_def("channel") if BWSkillRegistry.has("channel") else BWSkillRegistry.get_def("surge"), p5)
	t.ok(p5.has("magnify"), "a single-hex paint is magnified too")
	t.eq(int(p5.steps), 2, "+1 charge step")


# ------------------------------------------------------------------ thunder

func test_static_blades(t) -> void:
	var me := _u("me", "daggers", "thunder", ["static_blades"])
	me.affinity["thunder"] = 10
	var foe := _u("fo")
	var b := _fight([me], [foe], [_nb(C, 3)], [C])
	foe.facing = E                               # facing east, away from me (west)
	_turn(b, me)
	b.expected_rolls = true                      # every blow lands
	b.attack(me, foe)
	t.eq(str(b.tiles.at(C).get("marker", "")), "fuse", "a basic hit arms my fuse on the foe's hex")
	t.eq(str(b.tiles.at(C).source), "me", "my fuse")
	t.eq(_ev(b, "static_arm").size(), 1, "a static_arm event")
	t.eq(_ev(b, "blade_burst").size(), 0, "no burst yet (the hex held no fuse when struck)")
	# next turn, from behind: the burst
	_turn(b, me)
	b.history.clear()
	var hp := foe.hp
	b.attack(me, foe)
	t.eq(_ev(b, "blade_burst").size(), 1, "a backstab on a foe on my fuse bursts")
	t.ok(b.tiles.at(C).is_empty() or str(b.tiles.at(C).get("marker", "")) != "fuse" or _ev(b, "static_arm").size() == 0, "the fuse is spent")
	var want := b._tile_dmg(foe, BWThunderKeys.BLADE_PCT, "thunder", BWThunderKeys.det_mult(me))
	t.eq(_hurt(b, foe, "detonation"), want, "12% x the thunder bonus to the occupant")
	t.ok(foe.hp < hp, "it hurt")
	# once per turn
	_fuse(b, C, "me")
	me.acted = false
	b.history.clear()
	b.attack(me, foe)
	t.eq(_ev(b, "blade_burst").size(), 0, "one burst per turn")
	# from the front: no burst
	var b2 := _fight([me], [foe], [_nb(C, 0)], [C])
	foe.facing = E
	_fuse(b2, C, "me")
	_turn(b2, me)
	b2.expected_rolls = true
	b2.attack(me, foe)
	t.eq(_ev(b2, "blade_burst").size(), 0, "not a backstab: no burst")


func test_blast_rider(t) -> void:
	var me := _u("me", "daggers", "thunder", ["blast_rider"])
	var foe := _u("fo")
	var b := _fight([me], [foe], [C], [_nb(C, 0)])
	_lay(b, C, 1, 0, "me")
	_turn(b, me)
	var hp := me.hp
	b.history.clear()
	var r := b.paint([C], "thunder", me)
	t.eq(r.detonations.size(), 1, "thunder on my own charged hex detonates")
	t.eq(me.hp, hp, "immune to my own blast")
	t.eq(_ev(b, "launch").size(), 1, "launched")
	var splash := _hurt(b, foe, "detonation")
	var full := b._tile_dmg(foe, float(r.detonations[0].pct), "thunder", BWThunderKeys.det_mult(me))
	t.eq(splash, maxi(1, int(full / 2.0)), "the ring takes the normal half (no full ring)")
	b._after_action(me, "thunder", true)
	t.eq(int(me.fx.get("extra_move", 0)), BWThunderKeys.LAUNCH, "move 2 after the action")
	# once per turn, and the hex can't be re-armed by me until my next turn
	_lay(b, C, 1, 0, "me")
	b.history.clear()
	b.paint([C], "thunder", me)
	t.eq(_ev(b, "launch").size(), 0, "one launch per turn")
	t.ok(b.tiles.at(C).is_empty(), "the charge is spent")
	b.paint([C], "thunder", me)
	t.ok(b.tiles.at(C).is_empty(), "my locked hex can't be re-armed by me")
	_turn(b, me)
	b.paint([C], "thunder", me)
	t.eq(str(b.tiles.at(C).get("marker", "")), "fuse", "next turn it can")
	# Bolt Step doesn't stack: the launch replaces its +2
	var names: Array = []
	me.fx["launch"] = true
	t.eq(BWThunderKeys.launch_move(me, 0, names), 2, "launch = 2")


## D306 Self-detonate: Blast Rider's free action on a charge or the holder's
## own fuse: immunity, the half ring, the launch, once per turn, the lock;
## never on unglazed water; the dagger dive (leap in, blow, launch out); the AI.
func test_self_detonate(t) -> void:
	var plain := _u("pl", "daggers", "thunder")
	var me := _u("me", "daggers", "thunder", ["blast_rider"])
	var f1 := _u("f1")
	var f2 := _u("f2")
	var b := _fight([me, plain], [f1, f2], [C, _far(C, 3, 4)], [_nb(C, 0), _nb(C, 1)])
	_turn(b, me)
	t.ok(b.skills_for(plain).all(func(r): return r.key != "self_detonate"), "no keystone, no Self-detonate")
	t.ok(b.skills_for(me).any(func(r): return r.key == "self_detonate"), "a Blast Rider holder has it")
	t.ok(b.skill_targets(me, "self_detonate", "").is_empty(), "bare ground: nothing to blow")
	_lay(b, C, 1, 0, "f1")                        # fire 1, anyone's
	t.eq(b.skill_targets(me, "self_detonate", ""), [C] as Array[Vector2i], "on a charge: its own hex")
	var hp := me.hp
	b.history.clear()
	var e := b.use_skill(me, "self_detonate", "", C)
	t.ok(not e.is_empty(), "it plays")
	t.eq(_ev(b, "detonate").size(), 1, "the hex blows")
	t.eq(me.hp, hp, "immune to its own blast")
	var full := b._tile_dmg(f1, float(BWTiles.DETONATE_BASE_PCT + BWTiles.DETONATE_PER_POINT_PCT), "thunder", BWThunderKeys.det_mult(me))
	t.eq(_hurt(b, f1, "detonation"), maxi(1, int(full / 2.0)), "the ring takes the normal half")
	t.eq(_ev(b, "launch").size(), 1, "launched")
	t.eq(int(me.fx.get("extra_move", 0)) + int(me.fx.get("bonus_move", 0)), BWThunderKeys.LAUNCH, "move 2 after it")
	t.ok(not me.acted, "free: the action is still there")
	t.ok(b.tiles.at(C).is_empty(), "the charge is spent")
	_lay(b, C, 2, 0, "f1")
	t.ok(b.skill_targets(me, "self_detonate", "").is_empty(), "once per turn")
	# the holder's own empty fuse blows at the 5% base; unglazed water never
	_turn(b, me)
	b.tiles.entries.erase(C)
	_fuse(b, C, "me")
	b.history.clear()
	t.ok(not b.use_skill(me, "self_detonate", "", C).is_empty(), "its own fuse")
	t.eq(_ev(b, "detonate").size(), 1, "the fuse blows")
	t.near(float(_ev(b, "detonate")[0].pct), float(BWTiles.DETONATE_BASE_PCT), 0.01, "at the empty-fuse base")
	_turn(b, me)
	_lay(b, C, -2, 0, "f1")
	t.ok(b.skill_targets(me, "self_detonate", "").is_empty(), "unglazed water electrifies: no self-detonation")
	b.tiles.entries.erase(C)
	_fuse(b, C, "f1")
	t.ok(b.skill_targets(me, "self_detonate", "").is_empty(), "a foe's fuse isn't yours")
	# the AI: blows it with foes in the ring, not with only an ally there
	b.tiles.entries.erase(C)
	_lay(b, C, 1, 0, "f1")
	t.ok(BWThunderKeys.ai_self_det(b, me), "AI: foes in the ring, blow it")
	f1.pos = _far(C, 3, 6)
	f2.pos = _far(C, 4, 6)
	plain.pos = _nb(C, 0)
	t.ok(not BWThunderKeys.ai_self_det(b, me), "AI: only an ally in the ring, hold it")


## D306: the dagger bomber dive: Daggerleap into the pack onto a fire hex,
## self-detonate, launch out.
func test_dagger_dive(t) -> void:
	var me := _u("me", "daggers", "thunder", ["blast_rider"])
	var f1 := _u("f1")
	var f2 := _u("f2")
	var land := _far(C, E, 3)
	var b := _fight([me], [f1, f2], [C], [_nb(land, 0), _nb(land, 1)])
	_lay(b, land, 2, 0, "f1")
	_turn(b, me)
	t.ok(land in b.skill_targets(me, "daggerleap", "thunder"), "the fire hex is a leap target")
	b.use_skill(me, "daggerleap", "thunder", land)
	t.eq(me.pos, land, "landed in the pack on the fire")
	b.history.clear()
	t.ok(not b.use_skill(me, "self_detonate", "", land).is_empty(), "blows its hex")
	t.ok(_hurt(b, f1, "detonation") > 0 and _hurt(b, f2, "detonation") > 0, "the pack takes the ring")
	t.ok(b.can_move(me), "and launches out (move 2)")


## D307 the L-30 riders: Sunpath's beam move, Static Field's ally-paint
## guard, Gale Force applying the mode, Wildfire's wild eruption ring, and the
## Water set's pools reaching 25.
func test_l30_riders(t) -> void:
	# Sunpath: an ally on the holder's beam starts its turn with +1 move
	var a := _u("a", "staff", "light")
	a.perks = ["light_sun"]
	var c := _u("c", "staff", "light")
	var d := _u("d")
	var foe := _u("fo")
	var ca := _far(C, E, 4)
	var b := _fight([a, c, d], [foe], [C, ca, _far(C, E, 2)], [Vector2i(12, 12)])
	_lay(b, C, 0, 1)
	_lay(b, ca, 0, 1)
	_turn(b, d)
	t.eq(int(d.fx.get("start_move", 0)), 1, "Sunpath: an ally on the holder's beam starts with +1 move")
	_turn(b, c)
	t.eq(int(c.fx.get("start_move", 0)), 1, "the other end too")
	a.perks = []
	b.refresh_effects()
	_turn(b, d)
	t.eq(int(d.fx.get("start_move", 0)), 0, "without Sunpath: nothing")
	# Static Field: an ally's paint can't set off the holder's fuse; a foe's can
	var h := _u("h", "daggers", "thunder")
	h.perks = ["thunder_static"]
	var al := _u("al", "staff", "fire")
	var f2 := _u("f2", "staff", "fire")
	var x := _far(C, 2, 2)
	var b2 := _fight([h, al], [f2], [C, _nb(C, 3)], [Vector2i(12, 12)])
	_fuse(b2, x, "h")
	_turn(b2, al)
	var r := b2.paint([x], "fire", al)
	t.eq(r.detonations.size(), 0, "Static Field: an ally's fire doesn't set off the fuse")
	t.eq(str(b2.tiles.at(x).get("marker", "")), "fuse", "the fuse stands")
	_turn(b2, f2)
	t.eq(b2.paint([x], "fire", f2).detonations.size(), 1, "a foe's fire does")
	# Gale Force: after moving 4+, the first landed hit applies the mode, once a turn
	var g := _u("g", "sword", "fire")
	g.perks = ["wind_force"]
	var v := _u("v")
	var b3 := _fight([g], [v], [C], [_nb(C, E)])
	_turn(b3, g)
	g.fx["moved_hexes"] = 4
	BWWind.set_mode(g, BWWind.GUST)
	var at := v.pos
	b3._gale_force(g, v, { "hit": true })
	t.eq(v.pos, _nb(at, E), "Gale Force: the hit pushes it 1 (Gust)")
	var at2 := v.pos
	b3._gale_force(g, v, { "hit": true })
	t.eq(v.pos, at2, "once a turn")
	_turn(b3, g)
	g.fx["moved_hexes"] = 3
	b3._gale_force(g, v, { "hit": true })
	t.eq(v.pos, at2, "under 4 hexes moved: nothing")
	# Wildfire: the eruption ring is wild
	var w := _u("w", "staff", "fire")
	w.perks = ["fire_wild"]
	var b4 := _fight([w], [_u("f4")], [_far(C, 3, 3)], [Vector2i(12, 12)])
	_lay(b4, C, 3, 0, "w")
	_turn(b4, w)
	b4.paint([C], "fire", w)
	var wild := 0
	for n in BWHex.neighbors(C):
		if b4.tiles.at(n).get("wild", false):
			wild += 1
	t.eq(wild, 6, "Wildfire: every eruption ring hex is wild")
	b4.tiles.tick()
	var seeded := 0
	for n in b4.board.area(C, 2):
		if BWHex.distance(n, C) == 2 and b4.tiles.intensity(n, "fire") > 0:
			seeded += 1
	t.ok(seeded > 0, "and seeds the next ring at the tick")
	# Water set (2): pools reach 25
	var ws := _u("ws", "staff", "water")          # a set sleeps until its element is learned
	ws.equipment["head"] = { "uid": "ws_h", "base": "", "slot": "head", "tier": "E", "stats": {}, "enchant": "brimming", "worn": {} }
	ws.equipment["chest"] = { "uid": "ws_c", "base": "", "slot": "chest", "tier": "E", "stats": {}, "enchant": "soaking", "worn": {} }
	ws.refresh_effects()
	t.eq(BWSets.pool_max(ws), 25, "Water set (2): pools reach 25")
	var plain := _u("pl", "staff", "fire")
	var b5 := _fight([ws, plain], [_u("f5")], [Vector2i(0, 12), Vector2i(1, 12)], [Vector2i(12, 12)])
	for rr in 6:
		for cc in 6:
			_lay(b5, Vector2i(cc, rr), -1)
	_turn(b5, ws)
	b5.paint([Vector2i(0, 0)], "fire", ws)
	t.eq(b5.tiles.steam.size(), 25, "its fire steams 25 hexes of a 36-hex pool")
	b5.tiles.steam.clear()
	for rr in 6:
		for cc in 6:
			_lay(b5, Vector2i(cc, rr), -1)
	_turn(b5, plain)
	b5.paint([Vector2i(0, 0)], "fire", plain)
	t.eq(b5.tiles.steam.size(), BWPools.POOL_MAX, "without the set: 19")


func test_daisy_chain(t) -> void:
	var me := _u("me", "daggers", "thunder", ["daisy_chain"])
	var foe := _u("fo")
	var f2 := _u("f2")
	var f3 := _u("f3")
	var a := C
	var bb := _far(C, E, 3)
	var cc := _far(bb, E, 2)
	var b := _fight([me], [foe, f2, f3], [Vector2i(0, 12)], [a, bb, cc])
	_fuse(b, a, "me")
	_fuse(b, bb, "me")
	_fuse(b, cc, "me")
	_turn(b, me)
	b.history.clear()
	var r := b.paint([a], "fire", me)
	t.eq(r.detonations.size(), 2, "my fuse blows and one more within 3 follows")
	t.ok(b.tiles.at(bb).is_empty(), "the second fuse is spent")
	t.eq(str(b.tiles.at(cc).get("marker", "")), "fuse", "nothing chains further")
	t.eq(float(r.detonations[1].pct), 5.0, "an empty fuse blows at the 5% base")
	t.ok(_hurt(b, f2, "detonation") > 0, "the foe on it is hurt")
	b.history.clear()
	_fuse(b, a, "me")
	r = b.paint([a], "fire", me)
	t.eq(r.detonations.size(), 1, "once per turn")


# ------------------------------------------------------------------ AI + simulate

func test_ai_and_preview(t) -> void:
	var a := _u("a")
	var c := _u("c")
	var foe := _u("fo")
	var b := _fight([a, c], [foe], [Vector2i(0, 12), _far(C, E, 3)], [_nb(C, E)])
	_lay(b, C, 0, 1)
	_lay(b, c.pos, 0, 1)
	t.ok(BWBeams.ai_hex(b, a, C) > 2.0, "a hex on light in line with an ally scores the beam")
	t.ok(BWBeams.ai_hex(b, foe, _nb(_nb(C, E), E)) < 0.0 or BWBeams.beams(b).is_empty(), "a foe's hex on a live beam scores negative")
	a.pos = C
	t.ok(BWBeams.ai_hex(b, foe, _far(C, E, 2)) < 0.0, "the foe avoids the enemy beam")
	# simulate carries the after-action beams and an Overheat
	var s := _u("s", "staff", "fire")
	s.affinity["fire"] = 10
	var b2 := _fight([s], [foe], [Vector2i(3, 6)], [_nb(C, 1)])
	_lay(b2, C, 3)
	_turn(b2, s)
	var sim := b2.simulate(s, { "kind": "skill", "key": "surge", "element": "fire", "hex": C })
	t.ok(sim.has("beams"), "simulate carries the beams")
	t.ok((sim.events as Array).any(func(e): return str(e.type) == "overheat"), "and the eruption")
	t.ok(BWOverheat.ai_skill(b2, s, b2.skill_preview(s, "surge", "fire", C)) > 0.0, "the AI scores the Overheat")
	# determinism: the same fight twice gives the same history
	var h1 := _replay()
	var h2 := _replay()
	t.eq(h1, h2, "seeded fights with the new rules reproduce")


func _replay() -> String:
	var a := _u("a", "sword", "light", ["prism"])
	var c := _u("c", "daggers", "thunder", ["static_blades", "blast_rider"])
	var f := _u("f", "staff", "fire", ["conflagration"])
	var g := _u("g", "axe", "fire", ["phoenix_heart"])
	var b := BWBattle.new(_board(), 3)
	b.setup([a, c], [f, g])
	_lay(b, a.pos, 0, 2)
	for i in 40:
		if b.over:
			break
		BWAI.take_turn(b)
	return var_to_str(b.history.map(func(e): return str(e.type)))

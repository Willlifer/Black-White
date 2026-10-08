extends RefCounted
## D309-D314 the author's two element rules of 2026-10-07 (ELEMENTS.md §17):
## wind's SQUALL (a front that spreads light/dark a ring a tick, pushing
## outward) and ice's OVERFREEZE (fresh ice on glazed water shatters: 12% on
## and around, a radius-1 rink, no pillar). Their caps, light/dark only, one
## squall per caster, determinism, no chaining, and the AI's simulate hooks.

const C := Vector2i(6, 6)
const E := 0


func _board(n: int = 13) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "so", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[n - 1, 0], [n - 1, 1], [n - 1, 2]] } })


func _u(id: String, wc: String = "sword", el: String = "wind") -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	u.keystones = []
	return u


func _fight(players: Array, foes: Array, ppos: Array, fpos: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
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


func _lay(b: BWBattle, h: Vector2i, hv: int, v: int = 0, src: String = "") -> void:
	b.tiles.entries[h] = b.tiles._entry(hv, v, "", src, "cast")


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


func _tick(b: BWBattle) -> void:
	b.cycle += 1
	BWWind.tick(b)


# ------------------------------------------------------------------ Squall

func test_squall_starts_and_advances(t) -> void:
	var me := _u("me", "staff", "wind")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [_far(C, E, 2)])
	_lay(b, C, 0, 2, "me")
	b.paint([C], "wind", me)
	var s: Dictionary = BWSquall.squalls(b).get("me", {})
	t.ok(not s.is_empty(), "wind on light 2 starts a squall")
	t.eq(str(s.get("element", "")), "light", "of light")
	t.eq(int(s.get("ring", 0)), 2, "its front starts past the gale's ring 1")
	t.eq(int(s.get("left", 0)), BWSquall.TICKS, "for 3 ticks")
	t.eq(_ev(b, "squall").size(), 1, "one squall event")
	t.eq(b.tiles.intensity(_nb(C, 1), "light"), 2, "the gale copies ring 1 as ever")
	t.eq(b.tiles.intensity(_far(C, 1, 2), "light"), 0, "ring 2 waits for the tick")
	# tick 1: ring 2
	_tick(b)
	var r2 := _far(C, 1, 2)
	t.eq(b.tiles.intensity(r2, "light"), 1, "ring 2 gets +1 light at the first tick")
	t.eq(str(b.tiles.at(r2).origin), "spread", "propagated")
	t.eq(str(b.tiles.at(r2).source), "me", "owned by the caster (beams, Rot read it)")
	t.eq(foe.pos, _far(C, E, 3), "the foe on ring 2 is pushed 1 outward")
	# tick 2: ring 3 (the foe again)
	_tick(b)
	t.eq(b.tiles.intensity(_far(C, 1, 3), "light"), 1, "ring 3 at the second tick")
	t.eq(foe.pos, _far(C, E, 4), "the front catches the foe again (a new cycle)")
	_tick(b)
	t.eq(b.tiles.intensity(_far(C, 1, 4), "light"), 1, "ring 4 at the third tick")
	t.ok(BWSquall.squalls(b).is_empty(), "then the squall is spent")
	_tick(b)
	t.eq(b.tiles.intensity(_far(C, 1, 5), "light"), 0, "nothing at a fourth tick")
	t.eq(_ev(b, "squall_advance").size(), 3, "three advances")


func test_squall_caps(t) -> void:
	var me := _u("me", "staff", "wind")
	var a := _u("a")
	var bl := _u("bl")
	var cp := _u("cp")
	var r2a := _far(C, E, 2)
	var r2b := _far(C, 3, 2)
	var b := _fight([me], [a, bl, cp], [Vector2i(0, 12)], [r2a, _far(C, E, 3), r2b])
	_lay(b, C, 0, -2, "me")                      # dark 2: no gravity to shorten the push
	var gm := _far(C, 1, 2)
	b.tiles.entries[gm] = b.tiles._entry(0, 0, "gale", "zz", "cast")
	var gz := _far(C, 2, 2)
	_lay(b, gz, -1)
	b.tiles.entries[gz].glaze = 2
	var sd := _far(C, 4, 2)
	b.tiles.seed_hex(sd, 0, 2)
	b.paint([C], "wind", me)
	t.eq(str(BWSquall.squalls(b).me.element), "dark", "dark 2 makes a dark squall")
	cp.fx["wind_cycle"] = b.cycle + 1             # it has already been moved 2 hexes by wind this cycle
	cp.fx["wind_hexes"] = 2
	b.history.clear()
	_tick(b)
	t.eq(str(b.tiles.at(gm).marker), "gale", "a gale marker on the front is never fired or washed")
	t.eq(b.tiles.intensity(gm, "dark"), 0, "and holds no dark")
	t.eq(b.tiles.intensity(gz, "dark"), 0, "a glazed hex is skipped")
	t.eq(b.tiles.intensity(sd, "light"), 1, "a seeded light 2 takes the dark step: light 1")
	t.ok(not b.tiles.is_seeded(sd), "and is ordinary charge now")
	t.eq(a.pos, r2a, "a push blocked by a unit doesn't move")
	t.ok(_hurt(b, a, "slam") > 0 and _hurt(b, bl, "slam") > 0, "it slams both (8%)")
	t.eq(cp.pos, r2b, "a unit out of wind budget this cycle isn't pushed (the caps)")
	t.eq(b.tiles.intensity(r2b, "dark"), 1, "though its hex still gets the dark")


func test_squall_gravity(t) -> void:
	var me := _u("me", "staff", "wind")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [_far(C, E, 2)])
	_lay(b, C, 0, -3, "me")
	b.paint([C], "wind", me)                     # ring 1 gets my dark 3 copies
	_tick(b)
	t.eq(foe.pos, _far(C, E, 2), "my dark 3 beside it holds the foe: gravity takes 1 off the push (D276)")
	t.eq(b.tiles.intensity(foe.pos, "dark"), 1, "and the dark spreads under it (Rot at its turn end)")


func test_squall_light_dark_only(t) -> void:
	var me := _u("me", "staff", "wind")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b, C, 3, 0)
	b.paint([C], "wind", me)
	t.ok(BWSquall.squalls(b).is_empty(), "fire 3 makes no squall")
	_lay(b, C, -3, 1)
	b.paint([C], "wind", me)
	t.ok(BWSquall.squalls(b).is_empty(), "water 3 + light 1 makes no squall (light 2+ needed)")
	_lay(b, C, 0, 2)
	b.paint([C], "wind", me, 1, false, { "propagated": true })
	t.ok(BWSquall.squalls(b).is_empty(), "a propagated wind arrival makes no squall")
	_lay(b, C, 0, 2)
	b.tiles.entries[C].glaze = 2
	b.paint([C], "wind", me)
	t.ok(BWSquall.squalls(b).is_empty(), "a glazed hex never gales, so no squall")
	# a firing gale: light landing on a gale marker at 2+ (Saturate's 2 steps)
	var al := _u("al", "staff", "light")
	var b2 := _fight([me, al], [foe], [Vector2i(0, 12), Vector2i(1, 12)], [Vector2i(12, 12)])
	b2.paint([C], "wind", me)                    # arms me's gale
	b2.paint([C], "light", al, 1)
	t.ok(BWSquall.squalls(b2).is_empty(), "light 1 firing the gale is too weak")
	b2.tiles.entries.erase(C)
	b2.paint([C], "wind", me)
	b2.paint([C], "light", al, 2)
	t.eq(str(BWSquall.squalls(b2).get("me", {}).get("element", "")), "light", "light 2 firing my gale starts MY squall")


func test_squall_single_per_caster(t) -> void:
	var me := _u("me", "staff", "wind")
	var other := _u("ot", "staff", "wind")
	var foe := _u("fo")
	var b := _fight([me, other], [foe], [Vector2i(0, 12), Vector2i(1, 12)], [Vector2i(12, 12)])
	var c2 := Vector2i(3, 3)
	_lay(b, C, 0, 2)
	_lay(b, c2, 0, -2)
	b.paint([C], "wind", me)
	b.paint([c2], "wind", me)
	t.eq(BWSquall.squalls(b).size(), 1, "one squall per caster")
	t.eq(BWSquall.squalls(b).me.origin, c2, "the new one replaced the old")
	t.eq(str(BWSquall.squalls(b).me.element), "dark", "with its own element")
	t.ok(bool(_ev(b, "squall")[1].replaced), "the event says it replaced one")
	_lay(b, C, 0, 2)
	b.paint([C], "wind", other)
	t.eq(BWSquall.squalls(b).size(), 2, "another caster's squall stands beside it")
	# one action over two light hexes: one squall, the stronger
	var b2 := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b2, C, 0, 2)
	_lay(b2, c2, 0, 3)
	b2.paint([C, c2], "wind", me)
	t.eq(BWSquall.squalls(b2).size(), 1, "one squall from one action")
	t.eq(BWSquall.squalls(b2).me.origin, c2, "from the stronger hex")


func test_squall_determinism(t) -> void:
	t.eq(_squall_run(), _squall_run(), "the same squall twice gives the same board and positions")


func _squall_run() -> String:
	var me := _u("me", "staff", "wind")
	var f1 := _u("f1")
	var f2 := _u("f2")
	var b := _fight([me], [f1, f2], [Vector2i(0, 12)], [_far(C, E, 2), _far(C, 2, 3)])
	_lay(b, C, 0, 3, "me")
	b.paint([C], "wind", me)
	for i in 4:
		_tick(b)
	var keys := b.tiles.entries.keys()
	keys.sort()
	var out: PackedStringArray = []
	for k in keys:
		out.append("%s:%d,%d" % [k, int(b.tiles.entries[k].h), int(b.tiles.entries[k].v)])
	out.append("%s %s" % [f1.pos, f2.pos])
	return " ".join(out)


# ------------------------------------------------------------------ Overfreeze

func test_overfreeze_burst(t) -> void:
	var me := _u("me", "staff", "ice")
	var foe := _u("fo")
	var al := _u("al")
	var far := _u("fx")
	var b := _fight([me, al], [foe, far], [Vector2i(0, 12), _nb(C, 1)], [C, _far(C, E, 2)])
	_lay(b, C, -2)
	b.tiles.entries[C].glaze = 1
	_lay(b, _nb(C, 3), 2)                        # fire 2: glazes (ice on charge)
	b.tiles.entries[_nb(C, 4)] = b.tiles._entry(0, 0, "fuse", "fo", "cast")   # marked: untouched
	var r := b.paint([C], "ice", me)
	t.eq((r.get("overfreeze", []) as Array).size(), 1, "fresh ice on glazed water overfreezes")
	t.eq(_hurt(b, foe, "overfreeze"), b._tile_dmg(foe, 12.0, "ice"), "12% to the unit on the hex")
	t.eq(_hurt(b, al, "overfreeze"), b._tile_dmg(al, 12.0, "ice"), "12% to an ally on the ring (both teams)")
	t.eq(_hurt(b, far, "overfreeze"), 0, "nothing 2 away")
	t.ok(b.tiles.is_glazed(C), "the centre is glazed")
	t.ok(b.tiles.is_glazed(_nb(C, 0)) and b.tiles.intensity(_nb(C, 0), "water") == 1, "empty ground gets a glazed ice sheet")
	t.ok(b.tiles.is_glazed(_nb(C, 3)), "a charged ring hex glazes")
	t.ok(BWUnsteady.on_glaze(b.tiles, _nb(C, 0)), "and it's Unsteady ground (D398, no rink)")
	if foe.alive():
		t.ok(BWUnsteady.unsteady(b, foe), "the foe left on the centre is Unsteady")
	if al.alive():
		t.ok(BWUnsteady.unsteady(b, al), "and so is the ally on the ring (both teams)")
	for n in (r.get("overfreeze", []) as Array):
		t.ok(not str(n).to_lower().contains("rink"), "no rink in the result")
	t.eq(str(b.tiles.at(_nb(C, 4)).marker), "fuse", "a marked hex is untouched")
	t.ok(not b.tiles.is_glazed(_nb(C, 4)), "and not glazed")
	t.eq(_ev(b, "overfreeze").size(), 1, "one overfreeze event")
	t.ok(r.detonations.is_empty(), "nothing detonates")


func test_overfreeze_conditions(t) -> void:
	var me := _u("me", "staff", "ice")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b, C, -2)
	var r := b.paint([C], "ice", me)
	t.ok(not r.has("overfreeze"), "unglazed water just glazes (the pool path)")
	r = b.paint([C], "ice", me, 1, false, { "propagated": true })
	t.ok(not r.has("overfreeze"), "a propagated ice arrival never overfreezes")
	_lay(b, C, 2)
	b.tiles.entries[C].glaze = 2
	r = b.paint([C], "ice", me)
	t.ok(not r.has("overfreeze"), "glazed fire isn't water")
	# empty glazed water 3: it shatters, and NO pillar rises (D313)
	_lay(b, C, -3)
	b.tiles.entries[C].glaze = 2
	r = b.paint([C], "ice", me)
	t.ok(r.has("overfreeze"), "glazed water 3 overfreezes")
	t.ok(b.tiles.pillars.is_empty(), "and raises no pillar: it just shattered")
	# a pillar is not a target (Glacier Wall's and thunder's to break)
	var b2 := _fight([me], [foe], [Vector2i(0, 12)], [Vector2i(12, 12)])
	_lay(b2, C, -3)
	b2.paint([C], "ice", me)
	t.ok(b2.tiles.is_pillar(C), "ice on empty water 3 raises a pillar (as ever)")
	r = b2.paint([C], "ice", me)
	t.ok(not r.has("overfreeze"), "ice on a pillar doesn't overfreeze")
	# thunder on glazed water still detonates with the shatter
	_lay(b, C, -2)
	b.tiles.entries[C].glaze = 2
	r = b.paint([C], "thunder", me)
	t.eq((r.detonations as Array).size(), 1, "thunder on glazed water still detonates")
	t.ok(not r.has("overfreeze"), "and doesn't overfreeze")


func test_overfreeze_no_chain(t) -> void:
	var me := _u("me", "staff", "ice")
	var foe := _u("fo")
	var b := _fight([me], [foe], [Vector2i(0, 12)], [_nb(C, E)])
	var c2 := _far(C, E, 2)
	for h in [C, c2, _far(C, 3, 1)]:
		_lay(b, h, -2)
		b.tiles.entries[h].glaze = 2
	var r := b.paint([C, c2], "ice", me)
	t.eq((r.overfreeze as Array).size(), 2, "two glazed water hexes cast on: two bursts (once per hex)")
	t.eq(_hurt(b, foe, "overfreeze"), b._tile_dmg(foe, 12.0, "ice"), "a unit between them takes ONE burst")
	t.ok(not (r.overfreeze as Array).any(func(x): return x.hex == _far(C, 3, 1)), "a glazed water ring hex doesn't chain")
	var tile_events := b.history.filter(func(e): return str(e.type) == "tile_damage" and str(e.unit) == foe.id)
	t.eq(tile_events.size(), 1, "one damage event per unit")


# ------------------------------------------------------------------ AI, preview, readability

func test_ai_and_preview(t) -> void:
	var s := _u("s", "staff", "ice")
	s.affinity["ice"] = 10
	s.affinity["wind"] = 10
	var foe := _u("fo")
	var b := _fight([s], [foe], [Vector2i(3, 6)], [C])
	_lay(b, C, -2)
	b.tiles.entries[C].glaze = 2
	b.queue = [s]
	b.turn_index = 0
	b._begin_turn()
	var sim := b.simulate(s, { "kind": "skill", "key": "surge", "element": "ice", "hex": C })
	t.ok((sim.events as Array).any(func(e): return str(e.type) == "overfreeze"), "simulate carries the Overfreeze")
	t.ok(BWOverfreeze.ai_skill(b, s, "surge", "ice", C, b.skill_preview(s, "surge", "ice", C)) > 0.0, "the AI scores it")
	t.eq(BWOverfreeze.ai_skill(b, s, "surge", "fire", C, b.skill_preview(s, "surge", "fire", C)), 0.0, "not for fire")
	t.ok(BWOverfreeze.card_lines(b, C).size() == 1, "the tile card names Overfreeze")
	var pv := b.skill_preview(s, "surge", "ice", C)
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("Overfreeze")), "the forecast names it")
	# squall: dark 3 under the foe's side
	var b2 := _fight([s], [foe], [Vector2i(3, 6)], [_far(C, E, 2)])
	_lay(b2, C, 0, -3, "s")
	b2.queue = [s]
	b2.turn_index = 0
	b2._begin_turn()
	var sim2 := b2.simulate(s, { "kind": "skill", "key": "surge", "element": "wind", "hex": C })
	t.ok((sim2.events as Array).any(func(e): return str(e.type) == "squall"), "simulate carries the squall start")
	t.ok(BWSquall.ai_skill(b2, s, "surge", "wind", C, b2.skill_preview(s, "surge", "wind", C)) > 0.0, "the AI scores a dark squall toward a foe")
	t.ok(BWSquall.squalls(b2).is_empty(), "simulate leaves the real battle alone")
	var pv2 := b2.skill_preview(s, "surge", "wind", C)
	t.ok((pv2.notes as Array).any(func(n): return str(n).begins_with("Squall")), "the forecast names the squall")
	b2.paint([C], "wind", s)
	var lines := BWSquall.card_lines(b2, _far(C, 1, 2))
	t.ok(lines.size() == 1 and str(lines[0]).begins_with("Squall: advances next tick"), "the front's tile card says it advances next tick")
	t.ok(BWGlossary.markup("Squall and Overfreeze").find("[hint") >= 0, "both are glossary terms")


## D343: once per unit per ACTION, not per paint. One staff basic paints twice
## on the target's hex (Frostbitten's lay_on, then the staff's channel); the
## second fresh ice found the centre still glazed water and burst again
## ("Aureli 50 overfreeze (x2)" from one Rem attack).
func test_overfreeze_once_per_action(t) -> void:
	var me := _u("me", "staff", "ice")
	me.stats["dex"] = 99
	var row := BWData.row("enchantments", "frostbitten")
	var base := str(BWData.list(row.applies_to)[0])
	var eq := BWData.row("equipment", base)
	me.equipment[str(eq.slot)] = { "uid": "t_fb", "base": base, "slot": str(eq.slot),
		"weight": str(eq.weight), "tier": "E", "stats": {}, "enchant": "frostbitten", "worn": {} }
	me.affinity["ice"] = 10
	var foe := _u("fo")
	foe.stats["con"] = 300
	var al := _u("al")
	al.stats["con"] = 300
	var b := _fight([me, al], [foe], [_far(C, 3, 1), _far(C, 0, 1)], [C])
	me.refresh_effects()
	me.attuned = "ice"
	_lay(b, C, -2)
	b.tiles.entries[C].glaze = 2
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	b.attack(me, foe)
	t.ok(_ev(b, "paint").size() >= 2, "the blow paints the target's hex twice (lay_on + channel)")
	t.eq(_ev(b, "overfreeze").size(), 1, "one burst: the hex overfreezes once per action")
	t.eq(_hurt(b, al, "overfreeze"), b._tile_dmg(al, 12.0, "ice"), "an ally on the ring takes ONE burst")
	var foe_hits := b.history.filter(func(e): return str(e.type) == "tile_damage" and str(e.unit) == foe.id and str(e.cause) == "overfreeze")
	t.eq(foe_hits.size(), 1, "the target takes ONE burst")
	# two paints in one action on two different glazed water hexes: a unit
	# between them still takes one burst; the next action may burst again
	var b2 := _fight([me], [foe], [Vector2i(0, 12)], [_nb(C, E)])
	var c2 := _far(C, E, 2)
	for h in [C, c2]:
		_lay(b2, h, -2)
		b2.tiles.entries[h].glaze = 2
	BWEnchant.begin_action(b2, me)
	b2.paint([C], "ice", me)
	b2.paint([c2], "ice", me)
	t.eq(_ev(b2, "overfreeze").size(), 2, "two hexes, two bursts")
	t.eq(_hurt(b2, foe, "overfreeze"), b2._tile_dmg(foe, 12.0, "ice"), "but one per unit per action")
	_lay(b2, C, -2)
	b2.tiles.entries[C].glaze = 2
	BWEnchant.begin_action(b2, me)
	var before := _hurt(b2, foe, "overfreeze")
	b2.paint([C], "ice", me)
	t.eq(_hurt(b2, foe, "overfreeze") - before, b2._tile_dmg(foe, 12.0, "ice"), "a new action bursts again")

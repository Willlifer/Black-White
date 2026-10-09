extends RefCounted
## D443-D465 Keystones v3: the fourteen keystones (two per element), titles,
## the ladder (one per element, rank 6's wildcard), the eleven old keystones
## as item enchantments, the save migration, and the eight duo perks.

const C := Vector2i(5, 5)


func _board(n: int = 11, cells: Dictionary = {}) -> BWBoard:
	var out: Array = []
	for r in n:
		for c in n:
			var cell := { "q": c, "r": r, "terrain": "neutral", "elevation": 0 }
			cell.merge(cells.get(Vector2i(c, r), {}), true)
			out.append(cell)
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": out,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, ks: Array = []) -> BWUnit:
	var u := BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	for k in ks:
		u.keystones.append(k)
	return u


func _give_turn(b: BWBattle, u: BWUnit) -> void:
	b.queue = [u]
	b.turn_index = 0
	b._begin_turn()


func _duel(me: BWUnit, foes: Array, at: Array, allies: Array = [], ally_at: Array = []) -> BWBattle:
	var b := BWBattle.new(_board(), 7)
	b.setup([me] + allies, foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	for i in allies.size():
		allies[i].pos = ally_at[i]
	_give_turn(b, me)
	return b


func _nb(h: Vector2i, d: int, n: int = 1) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[d]
	return h


func _ev(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


func _lay(b: BWBattle, h: Vector2i, hv: int, v: int = 0, src: String = "", marker: String = "") -> void:
	b.tiles.entries[h] = b.tiles._entry(hv, v, marker, src, "cast")


func _perk(u: BWUnit, ids: Array) -> void:
	for id in ids:
		u.perks.append(id)
	u.refresh_effects()


# ------------------------------------------------------------------ the frame

func test_titles(t) -> void:
	var u := _u("Will", "sword", "fire")
	t.eq(BWKeystones.titled(u), "Will", "no keystone: just the name")
	BWKeystones.grant(u, "lava_walker")
	t.eq(BWKeystones.titled(u), "Will, the Lava Walker", "a keystone names you")
	u.affinity["wind"] = 10
	BWKeystones.grant(u, "la_nina")
	t.eq(BWKeystones.titled(u), "Will, La Niña", "two: the most recent names you")
	t.eq(BWKeystones.titles_line(u), "the Lava Walker · La Niña", "both on the hover line")


func test_conversions_are_enchantments(t) -> void:
	var want := { "conflagration": "B", "phoenix_heart": "B", "doom": "B", "contagion": "B", "daisy_chain": "B",
		"eye_of_vortex": "B", "sure_footed": "B", "event_horizon": "C", "ward_of_light": "C", "wellspring": "B", "magnify": "B" }
	for id in want:
		var r := BWData.row("enchantments", str(id))
		t.ok(not r.is_empty(), "%s is an enchantment" % id)
		t.eq(str(r.get("effect_key", "")), "keystone", "%s: the keystone key" % id)
		t.eq(str(r.get("tier", "")), want[id], "%s: tier %s or higher" % [id, want[id]])
		t.ok(int(r.get("strength", 0)) >= 1, "%s: a strength" % id)
	for old in BWKeystones.LEGACY:
		t.ok(BWKeystones.row(str(old)).is_empty(), "%s left the keystone pool" % old)
		t.ok(not BWKeystones.enchant_of(str(old)).is_empty(), "%s has its enchantment" % old)
	for gone in BWKeystones.REMOVED:
		t.ok(BWKeystones.row(str(gone)).is_empty() and not BWKeystones.LEGACY.has(gone), "%s is removed" % gone)
	for k in ["wind_wall", "tidal_release", "glacier_shatter", "flash_freeze"]:
		t.ok(not BWSkillRegistry.has(k), "%s's def is gone" % k)
	t.ok(BWSkillRegistry.has("self_detonate"), "Self-detonate is kept (provisional)")
	# wearing one grants the old effect, asleep until its element is learned
	var u := _u("d", "staff", "fire")
	u.equipment["head"] = { "uid": "x1", "base": "wizard_hat", "slot": "head", "tier": "B", "stats": {}, "enchant": "doom" }
	u.refresh_effects()
	t.ok(not BWKeystones.has(u, "doom"), "dark not learned: the Doom enchantment sleeps")
	u.affinity["dark"] = 10
	t.ok(BWKeystones.has(u, "doom"), "dark learned: the wearer has Doom")
	t.eq(u.keystones, [], "it takes no keystone slot")


func test_migration(t) -> void:
	var r := BWRun.start(["aureli", "della"], 5)
	var u: BWUnit = r.squad[0]
	u.keystones = ["prism", "doom"]
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	d["squad"][0]["keystones"] = ["prism", "doom", "lava_walker"]
	var inv0: int = (d.inventory as Array).size()
	var back := BWRun.from_dict(d)
	var bu: BWUnit = back.squad[0]
	t.eq(bu.keystones, ["lava_walker"], "the old keystones leave; a v3 one stays")
	t.eq(back.inventory.size(), inv0 + 1, "the converted one (Doom) comes back as an item")
	var it: Dictionary = back.inventory[-1]
	t.eq(str(it.enchant), "doom", "the matching enchantment")
	t.eq(str(it.tier), "B", "at its own tier")
	t.eq(back.keystone_notes.size(), 2, "both named for the screen (removed, converted)")
	t.eq(BWRun.SAVE_VERSION, 13, "save version 13 (D446)")
	var again := BWRun.from_dict(JSON.parse_string(JSON.stringify(back.to_dict())))
	t.eq(again.inventory.size(), back.inventory.size(), "a second load grants nothing more")


# ------------------------------------------------------------------ fire

func test_lava_walker(t) -> void:
	var me := _u("lw", "staff", "fire", ["lava_walker"])
	var al := _u("al", "axe", "ice")
	var f := _u("f", "staff", "water")
	var x := _nb(C, 0, 2)
	var b := _duel(me, [f], [Vector2i(9, 9)], [al], [_nb(x, 0)])
	b.paint([x], "fire", me, 3)
	b.paint([x], "fire", me, 3)
	t.eq(b.tiles.intensity(x, "fire"), 4, "D494: your fire climbs to 4")
	t.ok(b.tiles.is_lava(x), "it is lava")
	t.eq(BWTileFX.layers(b.tiles.at(x)).h.tier, 4, "the tile draws it at tier 4")
	t.eq(int(b.tiles.standing(x).fire), 20, "fire 4 burns 5% a step: 20%")
	t.eq(int(b.tiles.crossing_pct(x)), 12, "crossing 3% a step")
	b.history.clear()
	# D494: no more fizzle. Water meets it as fire 1: a douse, one step spent
	var r := b.paint([x], "water", f, 3)
	t.eq(b.tiles.intensity(x, "fire"), 3, "water douses one step: lava 4 -> 3")
	t.ok(b.tiles.is_lava(x) and str(b.tiles.at(x).source) == "lw", "still the walker's lava")
	t.ok(x in r.doused and x in r.lava_hit and not _ev(b, "lava_react").is_empty(), "a douse, and the lava_react event")
	t.ok(_ev(b, "fizzle").is_empty(), "no fizzle event")
	# thunder: a detonation of fire 1 (1 point), the lava steps down
	var r2 := b.paint([x], "thunder", f, 1)
	t.eq(r2.detonations.size(), 1, "thunder detonates it")
	if r2.detonations.size() == 1:
		t.eq(int(r2.detonations[0].points), 1, "the blast reads fire 1 (1 point)")
		t.near(float(r2.detonations[0].pct), float(BWTiles.DETONATE_BASE_PCT + BWTiles.DETONATE_PER_POINT_PCT), 0.01, "a fire-1 blast's %")
	t.eq(b.tiles.intensity(x, "fire"), 2, "lava 3 -> 2")
	# ice (even its own) freezes it: a glaze, a step spent
	b.paint([x], "ice", me, 1)
	t.ok(b.tiles.is_glazed(x) and b.tiles.intensity(x, "fire") == 1 and b.tiles.is_lava(x), "ice glazes it: lava 2 -> 1, glazed")
	# anyone else's fire leaves it standing (it melts the glaze, as fire does)
	b.paint([x], "fire", f, 1)
	t.ok(b.tiles.intensity(x, "fire") == 1 and b.tiles.is_lava(x) and not b.tiles.is_glazed(x), "another's fire: the lava stands, the glaze melts")
	# light lays beside it
	b.paint([x], "light", f, 2)
	t.ok(b.tiles.intensity(x, "fire") == 1 and b.tiles.intensity(x, "light") == 2 and b.tiles.is_lava(x), "light lays beside lava 1")
	# the last step: a douse leaves only the light
	b.paint([x], "water", f, 1)
	t.ok(not b.tiles.is_lava(x) and b.tiles.intensity(x, "fire") == 0 and b.tiles.intensity(x, "light") == 2, "lava 1 doused: gone, the light stays")
	# a gale carries fire 1 off: lava 4 -> 3, fire 1 on the ring
	var g := _nb(C, 1, 3)
	b.paint([g], "fire", me, 3)
	b.paint([g], "fire", me, 1)
	var rg := b.paint([g], "wind", f, 1)
	t.eq(b.tiles.intensity(g, "fire"), 3, "a gale carries one step off: lava 4 -> 3")
	var cps: Array = (rg.gales[0].copies as Array) if not rg.gales.is_empty() else []
	t.ok(not cps.is_empty() and cps.all(func(c): return b.tiles.intensity(c, "fire") == 1 and not b.tiles.is_lava(c)), "its copies are plain fire 1")
	# Inversion flips one step (fire 1 -> water 1 douses against the rest)
	var inv := BWSkillRegistry.get_def("inversion")
	t.eq(inv.swap_text(b.tiles.at(g)), "lava 3 → 2", "Inversion's text")
	inv.ground(b, f, "", g, { "hexes": [g] })
	t.ok(b.tiles.intensity(g, "fire") == 2 and b.tiles.is_lava(g) and b.tiles.intensity(g, "water") == 0, "Inversion: lava 3 -> 2, no water")
	# Overheat only at the cap
	var y := _nb(C, 3, 2)
	b.paint([y], "fire", me, 3)
	var r4 := b.paint([y], "fire", me, 1)
	t.ok((r4.get("overheat", []) as Array).is_empty(), "fire 3 + 1 climbs to 4, no eruption")
	var r5 := b.paint([y], "fire", me, 1)
	t.ok(not (r5.get("overheat", []) as Array).is_empty(), "fresh fire on its fire 4 erupts")
	# the aura: no fire ground damage for it and allies next to it
	al.pos = _nb(me.pos, 0)
	_lay(b, me.pos, 3)
	_lay(b, al.pos, 3)
	var h0 := me.hp
	var a0 := al.hp
	_give_turn(b, me)
	_give_turn(b, al)
	t.eq(me.hp, h0, "the walker doesn't burn")
	t.eq(al.hp, a0, "an ally next to it doesn't burn")
	al.pos = Vector2i(0, 9)
	_lay(b, al.pos, 3)
	_give_turn(b, al)
	t.ok(al.hp < a0, "an ally away from it burns")


func test_island_maker(t) -> void:
	var me := _u("im", "staff", "fire", ["island_maker"])
	var f := _u("f", "axe", "ice")
	var x := _nb(C, 0, 2)
	var b := _duel(me, [f], [_nb(x, 0, 2)])
	_lay(b, x, 3, 0, "im")
	var r := b.paint([x], "fire", me, 1)
	var ov: Array = r.get("overheat", [])
	t.eq(ov.size(), 1, "it erupts")
	t.ok((ov[0].ring as Array).any(func(h): return BWHex.distance(h, x) == 2), "the ring reaches radius 2")
	t.ok(_ev(b, "tile_damage").any(func(e): return e.unit == "f" and str(e.cause) == "overheat"), "a foe 2 away is hit")
	# 75% less from its own reactions
	var b2 := _duel(_u("im2", "staff", "fire", ["island_maker"]), [_u("g", "axe", "ice")], [Vector2i(9, 9)])
	var me2: BWUnit = b2.units[0]
	var full := b2._tile_dmg(me2, 40.0, "fire")
	var h0 := me2.hp
	b2._tile_hurt(me2, full, "overheat", me2.id)
	t.eq(h0 - me2.hp, roundi(full * 0.25), "its own reaction: a quarter")
	var h1 := me2.hp
	b2._tile_hurt(me2, full, "overheat", "g")
	t.eq(h1 - me2.hp, full, "someone else's: in full")


# ------------------------------------------------------------------ dark

func test_abyssal_pitch_black(t) -> void:
	var me := _u("ab", "staff", "dark", ["abyssal"])
	var x := _nb(C, 0, 2)
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var b := _duel(me, [f, g], [_nb(x, 1), Vector2i(9, 9)])
	_lay(b, x, 0, -3, "f")
	t.ok(b.skills_for(me).any(func(r): return r.key == "pitch_black"), "the menu row")
	t.ok(x in b.skill_targets(me, "pitch_black", ""), "a dark 3 within 3 (anyone's)")
	var f0 := f.hp
	var want := b._tile_dmg(f, 15.0, "dark")
	b.use_skill(me, "pitch_black", "", x)
	t.eq(f0 - f.hp, want, "15% to a foe within 1")
	t.eq(BWCurse.rot(f), 1, "+1 Rot")
	t.eq(g.hp, g.max_hp(), "a foe further off is untouched")
	t.eq(b.tiles.intensity(x, "dark"), 4, "not consumed: dark 4 for the turn")
	t.ok(not me.acted, "free")
	t.ok(b.skill_targets(me, "pitch_black", "").is_empty(), "once per turn")
	b.end_turn()
	t.eq(b.tiles.intensity(x, "dark"), 3, "dark 3 again after the turn")
	t.ok(not _ev(b, "pitch_black").is_empty(), "the event for the view")
	# the AI opens with it
	_give_turn(b, me)
	var o := BWSkillRegistry.get_def("pitch_black").ai_opener(b, me, {})
	t.eq(o.get("target", Vector2i(-1, -1)), x, "the AI's opener picks the burst with a foe in it")


func test_hopekiller(t) -> void:
	var me := _u("hk", "staff", "dark", ["hopekiller"])
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(C, 0, 2)])
	_lay(b, f.pos, 0, -1, "hk")
	f.hp = f.max_hp() - 30
	var h0 := f.hp
	b._heal(f, 10.0, "light")
	t.eq(h0 - f.hp, maxi(1, roundi(f.max_hp() * 0.1)), "a heal on its dark hurts for the same amount")
	BWBeams.empower(b, f, 15)
	t.eq(BWBeams.empowered(f), 0, "no buffs on its dark")
	f.hp = 1
	b._tile_hurt(f, 5, "slam", "hk")
	t.ok(not f.alive(), "KO'd on its dark")
	t.eq(b.tiles.intensity(f.pos, "dark"), 3, "it leaves dark 3")
	# off its dark: heals as normal
	var g := _u("g", "axe", "fire")
	var b2 := _duel(_u("hk2", "staff", "dark", ["hopekiller"]), [g], [_nb(C, 0, 2)])
	g.hp = g.max_hp() - 30
	var g0 := g.hp
	b2._heal(g, 10.0, "light")
	t.ok(g.hp > g0, "a foe off its dark heals")


# ------------------------------------------------------------------ light

func test_judicator(t) -> void:
	var me := _u("ju", "staff", "light", ["judicator"])
	var a := _u("a", "axe", "fire")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(C, 0, 2)], [a], [_nb(C, 3, 2)])
	_lay(b, a.pos, 0, 2, "ju")
	_lay(b, f.pos, 0, 2, "ju")
	a.hp = a.max_hp() - 40
	var a0 := a.hp
	_give_turn(b, a)
	t.eq(a.hp - a0, maxi(1, roundi(a.max_hp() * 0.12)), "your light 2 heals 12% (6% doubled)")
	var f0 := f.hp
	_give_turn(b, f)
	t.eq(f0 - f.hp, b._tile_dmg(f, 12.0, "light"), "a foe on it burns 12% instead")


func test_sunburst_solar_flare(t) -> void:
	var me := _u("sb", "staff", "light", ["sunburst"])
	var x := _nb(C, 0, 2)
	var f := _u("f", "axe", "fire")
	var a := _u("a", "axe", "fire")
	var b := _duel(me, [f], [_nb(x, 1)], [a], [_nb(x, 4)])
	_lay(b, x, 0, 3)
	a.hp = a.max_hp() - 30
	var a0 := a.hp
	var f0 := f.hp
	var want := b._tile_dmg(f, 15.0, "light")
	t.ok(x in b.skill_targets(me, "solar_flare", ""), "a light 3 within 3")
	b.use_skill(me, "solar_flare", "", x)
	t.eq(f0 - f.hp, want, "15% to a foe within 1")
	t.eq(a.hp - a0, maxi(1, roundi(a.max_hp() * 0.05)), "an ally within 1 heals 5%")
	t.eq(b.tiles.intensity(x, "light"), 4, "light 4 for the turn")
	b.end_turn()
	t.eq(b.tiles.intensity(x, "light"), 3, "then light 3")


# ------------------------------------------------------------------ water

func test_leviathan_drowned(t) -> void:
	var me := _u("lv", "axe", "water", ["leviathan"])
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(10, 10)])
	var pool := _nb(C, 0, 1)
	_lay(b, pool, -3, 0)
	b.move(me, pool)
	var pend := b.pending_picks("player").filter(func(x): return str(x[1].kind) == "leviathan")
	t.eq(pend.size(), 1, "ending a walk on water 3: the prompt")
	var req: Dictionary = pend[0][1]
	t.eq(str(req.kind), "leviathan", "the Leviathan's")
	t.eq(str(req.step), "submerge", "submerge first")
	t.eq(BWPicks.options(me, req).size(), 2, "two cards")
	t.ok(b.apply_pick(me, req, "submerge"), "submerge")
	t.ok(me.acted and not b.can_move(me), "its turn is spent")
	t.ok(_lev(b).is_empty(), "nothing owed now (the form waits for its next turn)")
	_give_turn(b, me)
	var req2: Dictionary = _lev(b)[0][1]
	t.eq(str(req2.step), "form", "its next turn: the form")
	var cards := BWPicks.options(me, req2)
	t.ok(cards.any(func(o): return str(o.id) == "leviathos" and not bool(o.owned)), "Leviathos is offered (D451b: the one-hex fallback)")
	t.ok(b.apply_pick(me, req2, "drowned"), "Drowned")
	t.eq(b.reachable(me).size(), 1, "Drowned: it can't move")
	t.ok(b._immune(me, "displace"), "nor be moved")
	t.ok(b.in_range(me, f), "its basic reaches a foe across the board")
	b.history.clear()
	b.attack(me, f)
	t.eq(_ev(b, "drowned_lunge").size(), 1, "a melee blow lunges (for the view)")
	t.eq(_ev(b, "drowned_return").size(), 1, "and comes back")
	t.eq(me.pos, pool, "the rules never move it")
	# Leviathos: double max and current HP, a one-hex body, splashing blows
	var lz := _u("lz", "axe", "water", ["leviathan"])
	var f1 := _u("f1", "axe", "fire")
	var f2 := _u("f2", "axe", "fire")
	var bl := _duel(lz, [f1, f2], [_nb(C, 0), _nb(_nb(C, 0), 1)])
	lz.fx["lev"] = "submerged"
	lz.fx["lev_used"] = true
	var mh := lz.max_hp()
	lz.hp = mh - 10
	_give_turn(bl, lz)
	t.ok(bl.apply_pick(lz, _lev(bl)[0][1], "leviathos"), "Leviathos")
	t.eq(lz.max_hp(), mh * 2, "double max HP")
	t.eq(lz.hp, mh * 2 - 10, "and current HP grows with it")
	t.eq(lz.size, 1, "still one hex")
	t.ok(bl.reachable(lz).size() > 1, "it still walks")
	var st := bl.basic_strikes(lz, f1)
	t.ok(st.any(func(x): return x.unit == f2 and is_equal_approx(float(x.share), 0.5)), "its blow splashes the foe next to the target at 50%")
	# once a battle; pushes never offer
	var g := _u("g", "axe", "water", ["leviathan"])
	var b2 := _duel(g, [_u("h", "axe", "fire")], [Vector2i(10, 10)])
	var p2 := _nb(C, 0, 1)
	_lay(b2, p2, -3, 0)
	b2._displace(g, 0, 1, "push")
	t.ok(_lev(b2).is_empty(), "a push onto water 3 offers nothing")
	# the AI side answers at once
	var e := _u("e", "axe", "water", ["leviathan"])
	var b3 := BWBattle.new(_board(), 7)
	b3.setup([_u("p", "axe", "fire")], [e])
	e.pos = C
	b3.units[0].pos = Vector2i(0, 10)
	_give_turn(b3, e)
	_lay(b3, _nb(C, 0, 1), -3, 0)
	b3.move(e, _nb(C, 0, 1))
	t.eq(BWKs3Water.state(e), "submerged", "an enemy with no one in reach submerges on its own")
	_give_turn(b3, e)
	t.ok(BWKs3Water.leviathos(e), "and, melee, rises as Leviathos at its next turn (a ranged one drowns)")


func _lev(b: BWBattle) -> Array:
	return b.pending_picks("player").filter(func(x): return str(x[1].kind) == "leviathan")


func test_being_of_rain(t) -> void:
	var me := _u("br", "axe", "water", ["being_of_rain"])
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(10, 10)])
	var line: Array = []
	var h := C
	for i in 5:
		h = _nb(h, 0)
		line.append(h)
		_lay(b, h, -2, 0)
	var r := b.reachable(me)
	t.ok(r.has(line[4]), "five water hexes: free to cross")
	t.eq(int(r.get(line[4], {}).get("cost", -1)), 0, "water costs no move")
	b.tiles.entries.clear()
	var dest := _nb(C, 3, 3)
	b.history.clear()
	b.move(me, dest)
	t.ok(not _ev(b, "rain_cloud").is_empty() and not _ev(b, "rain").is_empty(), "the cloud and the rain")
	t.eq(b.tiles.intensity(C, "water"), 1, "the start of the walk gets water 1")
	t.eq(b.tiles.intensity(_nb(dest, 0), "water"), 1, "and the neighbours of the end")
	# no painting as it walks (an Emberstep piece does nothing)
	var me2 := _u("br2", "axe", "fire", ["being_of_rain"])
	me2.equipment["legs"] = { "uid": "x2", "base": "chaps", "slot": "legs", "tier": "E", "stats": {}, "enchant": "emberstep" }
	var b2 := _duel(me2, [_u("g", "axe", "fire")], [Vector2i(10, 10)])
	b2.refresh_effects()
	b2.history.clear()
	b2.move(me2, _nb(C, 3, 2))
	t.ok(_ev(b2, "paint").all(func(e): return str(e.element) != "fire"), "it never paints as it walks (the Emberstep piece lays nothing)")


# ------------------------------------------------------------------ thunder

func test_superconductor(t) -> void:
	var me := _u("sc", "staff", "thunder", ["superconductor"])
	var f := _u("f", "axe", "fire")
	var x := _nb(C, 0, 3)
	var b := _duel(me, [f], [_nb(x, 0, 2)])
	_lay(b, x, 2)
	b.history.clear()
	b.paint([x], "thunder", me)
	var d := _ev(b, "detonate")
	t.eq(int(d[0].radius), 2, "your detonation reaches radius 2")
	t.ok(_ev(b, "tile_damage").any(func(e): return e.unit == "f"), "a foe 2 away is hit")
	# a reaction on its own hex: immune for the whole action
	_lay(b, C, 2)
	var h0 := me.hp
	b._action_serial += 1
	b.paint([C, _nb(C, 3)], "thunder", me)
	t.eq(me.hp, h0, "its own hex blew: nothing from that action hurts it")
	t.ok(not _ev(b, "superconductor").is_empty(), "the immunity is announced")


func test_thunder_overflow(t) -> void:
	var me := _u("of", "staff", "thunder", ["thunder_overflow"])
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [Vector2i(10, 10)])
	me.hp = me.max_hp() - 30
	var h0 := me.hp
	var x := _nb(C, 0, 3)
	_lay(b, x, 1)
	b._action_serial += 1
	b.paint([x], "thunder", me)
	t.eq(me.hp - h0, maxi(1, roundi(me.max_hp() * 0.05)), "a reaction heals it 5%")
	me.hp = me.max_hp()
	var far := [Vector2i(9, 1), Vector2i(9, 3), Vector2i(1, 9), Vector2i(3, 9)]
	for h in far:
		_lay(b, h, 1)
	b._action_serial += 1
	b.paint(far, "thunder", me)
	var w: Dictionary = me.fx.get("light_ward", {})
	t.ok(not w.is_empty(), "overheal becomes a shield")
	t.eq(int(w.get("hp", 0)), roundi(me.max_hp() * 0.2), "four reactions: 20% (the per-action cap), all of it shield")
	for k in 3:
		b._action_serial += 1
		for h in far:
			_lay(b, h, 1)
		b.paint(far, "thunder", me)
	t.eq(int(me.fx.light_ward.hp), roundi(me.max_hp() * 0.3), "the shield caps at 30%")


# ------------------------------------------------------------------ wind

func test_el_nino(t) -> void:
	var me := _u("en", "staff", "wind", ["el_nino"])
	var plain := _u("pl", "staff", "wind")
	var x := _nb(C, 0, 2)
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(10, 10)])
	var pv := b.skill_preview(me, "surge", "wind", x)
	var b2 := _duel(plain, [_u("g", "axe", "fire")], [Vector2i(10, 10)])
	var pv2 := b2.skill_preview(plain, "surge", "wind", x)
	t.ok((pv.hexes as Array).size() > (pv2.hexes as Array).size(), "a wind area grows a ring (%d vs %d)" % [(pv.hexes as Array).size(), (pv2.hexes as Array).size()])
	t.ok((pv.notes as Array).any(func(n): return str(n).begins_with("El Niño")), "the forecast names it")
	# gales spread a ring further
	var y := _nb(C, 3, 2)
	_lay(b, y, 0, 0, "en", "gale")
	var r := b.paint([y], "fire", me)
	var far := false
	for g in r.gales:
		for c in g.copies:
			if BWHex.distance(c, y) == 2:
				far = true
	t.ok(far, "its gale copies reach 2")


func test_la_nina(t) -> void:
	var me := _u("ln", "bow", "wind", ["la_nina"])
	var f := _u("f", "axe", "fire")
	var g := _u("g", "axe", "fire")
	var b := _duel(me, [f, g], [_nb(C, 0, 4), _nb(C, 3, 3)])
	f.pos = _nb(C, 0, 4)
	g.pos = _nb(C, 3, 3)
	b.cycle += 1                                    # a fresh cycle: the wind budget is whole again
	for x in [f, g]:
		x.hp = x.max_hp()
	var d0 := BWHex.distance(C, f.pos)
	var e0 := BWHex.distance(C, g.pos)
	var fh := f.hp
	_give_turn(b, me)
	var pct := BWKeystones.param("la_nina", "pct", 1.5)          # D476: 1.5 (was 2.5)
	t.eq(fh - f.hp, b._tile_dmg(f, pct, "wind"), "%.1f%% to every foe" % pct)
	t.eq(BWHex.distance(C, f.pos), d0 - 1, "pulled 1 toward it")
	t.eq(BWHex.distance(C, g.pos), e0 - 1, "every foe")
	t.ok(not _ev(b, "la_nina").is_empty(), "the event")


# ------------------------------------------------------------------ ice

func test_shatterer(t) -> void:
	var me := _u("sh", "axe", "ice", ["shatterer"])
	var f := _u("f", "axe", "fire")
	var o := _u("o", "axe", "fire")
	var at := _nb(C, 0)
	var b := _duel(me, [f, o], [at, _nb(at, 0)])
	for h in [at, _nb(at, 0), _nb(at, 1)]:
		_lay(b, h, -1)
		b.tiles.entries[h].glaze = 2
	var fc := b.forecast_basic(me, f)
	t.ok(str(fc).contains("Shatterer (2 glazed hexes around): +30%"), "+15% for each glazed hex around")
	var o0 := o.hp
	b.attack(me, f)
	if _ev(b, "attack")[0].result.hit:
		t.ok(not b.tiles.is_glazed(_nb(at, 0)) and not b.tiles.is_glazed(_nb(at, 1)), "the glaze around shatters")
		t.eq(o0 - o.hp, b._tile_dmg(o, 8.0, "ice"), "8% to a unit on a shattered hex")
	else:
		t.ok(b.tiles.is_glazed(_nb(at, 0)), "a miss shatters nothing")


func test_sculptor(t) -> void:
	var me := _u("sc", "staff", "ice", ["sculptor"])
	var a := _u("a", "axe", "fire")
	var f := _u("f", "axe", "fire")
	var x := _nb(C, 0, 2)
	var b := _duel(me, [f], [Vector2i(10, 10)], [a], [_nb(x, 0)])
	_lay(b, x, 1)
	b.tiles.entries[x].glaze = 2
	b.paint([x], "ice", me)
	t.ok(BWKs3Ice.sculpted(b.tiles, x), "ice on glaze raises a pillar")
	t.eq(b.board.elevation(x) - b.board.ground_elevation(x), 2, "2 levels up")
	t.ok(b.can_stand(a, x), "an ally can stand on it")
	t.ok(not b.can_stand(f, x), "a foe can't")
	_give_turn(b, a)
	t.ok(b.reachable(a).has(x), "an ally next to it climbs it")
	b.move(a, x)
	t.eq(a.pos, x, "and stands on it")
	# the cap is 6
	for i in 7:
		var h := Vector2i(1 + i, 9)
		_lay(b, h, 1)
		b.tiles.entries[h].glaze = 2
		b.paint([h], "ice", me)
	var mine: Array = b.tiles.pillars.keys().filter(func(p): return str(b.tiles.pillars[p].owner) == me.id)
	t.eq(mine.size(), 6, "six pillars at most")
	# a detonation on its pillar: double
	var z := Vector2i(9, 9)
	var b2 := _duel(_u("sc2", "staff", "ice", ["sculptor"]), [_u("g", "axe", "fire")], [Vector2i(10, 10)])
	var s2: BWUnit = b2.units[0]
	_lay(b2, z, 1)
	b2.tiles.entries[z].glaze = 2
	b2.paint([z], "ice", s2)
	var base := float(b2.tiles._operate(b2.tiles.at(z).duplicate(), "fuse", "g").detonate)
	b2.history.clear()
	b2.paint([z], "thunder", _u("q", "axe", "thunder"))
	var dd := _ev(b2, "detonate")
	t.ok(not dd.is_empty() and is_equal_approx(float(dd[0].pct), base * 2.0), "a Sculptor's pillar shatters for double")


# ------------------------------------------------------------------ duo perks (D455-D463)

func test_duo_offers(t) -> void:
	t.eq(BWDuo.rows().size(), 8, "eight duo perks")
	var seen := 0
	for k in 60:
		var u := _u("d%d" % k, "staff", "fire")
		u.pick_seed = k * 7919
		u.affinity["fire"] = 50                   # D498: rank 5 owes the 4th fire perk
		u.affinity["wind"] = 40
		u.perks = ["fire_rush", "fire_skin", "fire_kindling", "wind_tail", "wind_eye", "wind_force"]
		var req := { "kind": "perk", "element": "fire" }
		var o := BWPicks.options(u, req)
		t.eq(BWPicks.options(u, req), o, "%s: the same cards each time" % u.id)
		if o.any(func(x): return str(x.id) == "duo_wildfire"):
			seen += 1
			t.ok(not BWPicks.apply(u, req, "duo_wildfire").is_empty(), "%s: take it" % u.id)
			u.refresh_effects()
			t.ok(BWDuo.has(u, "wildfire_gale"), "%s: it holds Wildfire Gale" % u.id)
	t.eq(seen, 60, "D498: eligible = always offered: %d of 60" % seen)
	var thin := _u("th", "staff", "fire")
	thin.affinity["fire"] = 20
	thin.affinity["wind"] = 20
	thin.perks = ["fire_rush", "fire_skin", "fire_kindling", "wind_tail", "wind_eye"]
	t.ok(BWDuo.eligible(thin, "fire").is_empty(), "D498: 2 wind picks: not yet")
	var lone := _u("l", "staff", "fire")
	lone.affinity["fire"] = 20
	lone.perks = ["fire_rush"]
	t.ok(BWDuo.eligible(lone, "fire").is_empty(), "no perk in the other element: no duo")


func test_duo_wildfire_and_powder_keg(t) -> void:
	var me := _u("w", "staff", "fire")
	var b := _duel(me, [_u("f", "axe", "ice")], [Vector2i(10, 10)])
	me.fx["duo:wildfire_gale"] = true
	me.fx["duo:powder_keg"] = true
	var y := _nb(C, 3, 2)
	_lay(b, y, 0, 0, "w", "gale")
	var r := b.paint([y], "fire", me)
	t.ok(r.gales.any(func(g): return (g.copies as Array).any(func(c): return BWHex.distance(c, y) == 2)), "Wildfire Gale: fire it carries goes 2 rings")
	var x := _nb(C, 0, 3)
	_lay(b, x, 2, 0, "w")
	b.history.clear()
	b.paint([x], "thunder", me)
	t.eq(int(_ev(b, "detonate")[0].radius), 2, "Powder Keg: a fuse on your fire blows 1 wider")
	var lw := _u("lw", "staff", "fire", ["lava_walker"])
	var b2 := _duel(lw, [_u("g", "axe", "ice")], [Vector2i(10, 10)])
	var me2 := _u("p", "staff", "thunder")
	b2.units.append(me2)
	me2.fx["duo:powder_keg"] = true
	b2.paint([x], "fire", lw, 3)
	b2.paint([x], "fire", lw, 1)
	b2.history.clear()
	var r2 := b2.paint([x], "thunder", me2)
	t.eq(r2.detonations.size(), 1, "D494: thunder on lava detonates it as fire 1")
	var dets := _ev(b2, "detonate")
	t.ok(not dets.is_empty() and int(dets[0].radius) == 2, "Powder Keg: fire 1 is fire, the blast goes 1 wider")
	t.eq(b2.tiles.intensity(x, "fire"), 3, "and the lava drops a step: 4 -> 3")


func test_duo_storm_drain_and_flash_flood(t) -> void:
	var me := _u("s", "staff", "water")
	var b := _duel(me, [_u("f", "axe", "fire")], [Vector2i(10, 10)])
	me.fx["duo:storm_drain"] = true
	me.fx["duo:flash_flood"] = true
	var pool: Array = []
	for i in 6:
		pool.append(Vector2i(1 + i, 8))
		_lay(b, Vector2i(1 + i, 8), -2, 0, "s")
	b.paint([pool[0]], "thunder", me)
	t.ok(pool.all(func(h): return b.tiles.shock.has(h)), "Storm Drain: the whole connected pool is electrified")
	var b2 := _duel(_u("s2", "staff", "water"), [_u("g", "axe", "fire")], [Vector2i(10, 10)])
	var me2: BWUnit = b2.units[0]
	me2.fx["duo:flash_flood"] = true
	for h in pool:
		_lay(b2, h, -2, 0, "s2")
	b2.paint([pool[0]], "ice", me2)
	t.ok(pool.all(func(h): return b2.tiles.is_glazed(h)), "Flash Flood: your pool glazes at once")


func test_duo_permafrost(t) -> void:
	var me := _u("p", "axe", "ice")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(C, 0)])
	me.fx["duo:permafrost"] = true
	_lay(b, f.pos, 0, -3, "p")
	t.ok(BWUnsteady.unsteady_at(b, f, f.pos), "a foe on your dark 3 is Unsteady")
	t.ok(str(b.forecast_basic(me, f)).contains("Permafrost"), "and takes Shatter")


func test_duo_solar_wind(t) -> void:
	var me := _u("sw", "staff", "light")
	var a := _u("a", "axe", "ice")
	var f := _u("f", "axe", "ice")
	var b := _duel(me, [f], [_nb(C, 0, 3)], [a], [_nb(C, 3, 3)])
	me.fx["duo:solar_wind"] = true
	_lay(b, a.pos, 2, 2, "sw")
	_lay(b, f.pos, 2, 2, "sw")
	a.hp = a.max_hp() - 40
	var a0 := a.hp
	_give_turn(b, a)
	t.eq(a.hp - a0, maxi(1, roundi(a.max_hp() * 0.12)), "an ally heals for the light and the fire (6% + 6%), no burn")
	var f0 := f.hp
	_give_turn(b, f)
	t.eq(f0 - f.hp, b._tile_dmg(f, 16.0, "fire"), "a foe burns for the fire and the light (8% + 8%), no heal")


func test_duo_eclipse(t) -> void:
	var me := _u("ec", "staff", "light")
	var b := _duel(me, [_u("f", "axe", "ice")], [Vector2i(10, 10)])
	me.fx["duo:eclipse"] = true
	var x := _nb(C, 0, 2)
	b.paint([x], "dark", me, 2)
	b.paint([x], "light", me, 2)
	t.eq(b.tiles.intensity(x, "dark"), 2, "your dark stays")
	t.eq(b.tiles.intensity(x, "light"), 2, "and your light stays beside it")
	var plain := _u("pl", "staff", "light")
	var b2 := _duel(plain, [_u("g", "axe", "ice")], [Vector2i(10, 10)])
	b2.paint([x], "dark", plain, 2)
	b2.paint([x], "light", plain, 2)
	t.eq(b2.tiles.intensity(x, "dark") + b2.tiles.intensity(x, "light"), 0, "without it they cancel")


func test_duo_blizzard(t) -> void:
	var me := _u("bz", "staff", "wind")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(C, 0)])
	me.fx["duo:blizzard"] = true
	b._action_serial += 1
	BWWind.push(b, f, 0, 1, "push", me, false, false)
	t.ok(b.tiles.is_glazed(f.pos), "the landing hex glazes")
	t.ok(BWUnsteady.unsteady_at(b, f, f.pos), "the foe stands Unsteady")


## D474 Fatigue (not a keystone: lives here beside the heal hooks): round 15
## halves every heal, round 20 ends them; the overheal shield wanes too.
func test_fatigue_d474(t) -> void:
	var me := _u("fa", "sword", "light")
	var f := _u("f", "axe", "fire")
	var b := _duel(me, [f], [_nb(C, 0, 3)])
	var got := []
	for cyc in [1, BWFormulas.FATIGUE_HALF, BWFormulas.FATIGUE_NONE]:
		b.cycle = cyc
		me.hp = me.max_hp() / 2
		var h0 := me.hp
		b._heal(me, 20.0, "test")
		got.append(me.hp - h0)
	t.eq(got[0], roundi(me.max_hp() * 0.2), "a heal before round 15 is whole")
	t.eq(got[1], roundi(me.max_hp() * 0.1), "round 15 halves it")
	t.eq(got[2], 0, "round 20 ends it")
	t.eq(BWFormulas.fatigue_heal_mult(14), 1.0, "round 14 untouched")

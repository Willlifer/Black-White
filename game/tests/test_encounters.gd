extends RefCounted
## D208-D213: special encounters. No room choice in fights 1-2 (test_rooms);
## here: the encounter offer rate, scaling to the squad's level, the Horde's
## ten spawns, the Colossus's size and thrust, the damage classification
## matrix (BWFormulas.damage_class) against Blanks and Elemental Beings, and
## the AI choosing around the immunities.


func _run(s: int = 4242) -> BWRun:
	BWEncounters.RATE = BWEncounters.DEFAULT_RATE
	return BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), s)


func _board(n: int = 14) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "t", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[1, 4], [1, 6], [1, 8]], "enemy": [[12, 4], [12, 6], [12, 8]] } })


func _unit(id: String, wc: String, model: String, el: String, team: String) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "weapon_model": model, "element": el,
		"con": 5, "str": 6, "dex": 5, "wil": 6, "def": 3, "res": 3, "spd": 5 }
	var u := BWUnit.from_roster(row)
	u.team = team
	return u


## Player `u` against `foes`, placed by hand: u at (5, 6), foes from (6, 6) on.
func _battle(u: BWUnit, foes: Array) -> BWBattle:
	var b := BWBattle.new(_board(), 3)
	var far := _unit("far", "sword", "sword", "", "player")
	b.setup([u, far], foes)
	far.pos = Vector2i(0, 13)
	u.pos = Vector2i(5, 6)
	for i in foes.size():
		foes[i].pos = Vector2i(6, 6 + 2 * i) if i > 0 else Vector2i(6, 6)
	return b


func _foe(id: String, kind: String, el: String = "") -> BWUnit:
	var f := _unit(id, "sword", "sword", el, "enemy")
	f.encounter = kind
	f.affinity = {} if el == "" else { el: 10 }
	return f


func test_offer_rate_and_kinds(t) -> void:
	var seen := {}
	var enc := 0
	var total := 0
	for s in 120:
		var r := _run(1000 + s)
		for n in range(1, BWRun.FIGHTS + 1):
			var k := BWEncounters.kind_for(r, n)
			if n < 3 or n == BWRun.OBJECTIVE_FIGHT:
				if k != "":
					t.ok(false, "fight %d never has an encounter" % n)
				continue
			total += 1
			if k != "":
				enc += 1
				seen[k] = true
	var rate := float(enc) / total
	t.ok(rate > 0.27 and rate < 0.41, "about a third of the Hard rooms from fight 3 are encounters (%.2f)" % rate)
	t.eq(seen.keys().size(), 4, "all four kinds turn up (%s)" % [seen.keys()])
	var r := _run(77)
	t.eq(BWEncounters.kind_for(r, 5), BWEncounters.kind_for(_run(77), 5), "seeded from the run seed")


func test_encounter_room_is_hard_and_pays_hard(t) -> void:
	var r := _run(5)
	while r.fight < 3:
		var e := r.enemies_for(r.fight)
		r.after_fight(true, r.squad.slice(0, 3), e, e, [])
	var rooms := BWRooms.offer(r)
	rooms[1] = BWEncounters.room(3, "horde", str(rooms[1].map))
	BWRooms.choose(r, 1)
	var es := r.enemies_for(3)
	t.eq(es.size(), 10, "the chosen Horde reaches combat (10)")
	for x in es:
		x.hp = 0
	var rep := r.after_fight(true, r.squad.slice(0, 3), es, es, [])
	t.eq(rep.room, "hard", "an encounter is a Hard room")
	t.eq(rep.get("encounter", ""), "horde", "reported as the Horde")
	t.eq(rep.loot.size(), 4, "Hard pay: 4 drops, not one per grunt")
	t.ok(rep.loot.all(func(it): return it.tier == "C"), "a tier up")
	t.ok(r.last_enemies.is_empty(), "grunts can't be recruited")
	t.eq(r.room_log["3"].get("encounter", ""), "horde", "logged")
	var back := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(back.room_log["3"].get("encounter", ""), "horde", "the log survives a save")


func test_scales_to_squad_level(t) -> void:
	var r := _run()
	var prev := 0
	for n in [3, 6, 9]:
		while r.fight < n:
			var e := r.enemies_for(r.fight)
			r.after_fight(true, r.squad.slice(0, 3), e, e, [])
		for k in BWEncounters.KINDS:
			var es := BWEncounters.build(r, n, k)
			t.ok(es.all(func(u): return u.level == r.squad_level()), "fight %d %s: level %d = squad level" % [n, k, r.squad_level()])
			t.ok(es.all(func(u): return u.encounter != ""), "%s units are tagged" % k)
		var hp: int = BWEncounters.build(r, n, "blank")[0].max_hp()
		t.ok(hp > prev, "fight %d: tougher than before (%d > %d)" % [n, hp, prev])
		prev = hp


func test_horde_spawns_ten(t) -> void:
	var r := _run()
	var horde := BWEncounters.build(r, 5, "horde")
	t.eq(horde.size(), 10, "ten grunts")
	t.ok(horde.all(func(u): return u.element == "" and u.affinity.is_empty()), "elementless")
	t.ok(horde.all(func(u): return BWObelisk.attack_type(u, 1) == "melee" and not u.weapon_class in ["bow", "pistols", "staff", "daggers"]), "melee weapons")
	var normal := r.enemies_for(5, { "kind": "hard", "enemies": BWRooms._draw_ids(r, 5, [], true) })
	var share: float = float(horde[0].max_hp()) / normal[0].max_hp()
	t.ok(share > 0.2 and share < 0.5, "low HP: %.0f%% of a Hard enemy's" % (share * 100))
	for m in BWRun.MAP_POOL:
		var bd := BWBoard.load_file("res://maps/%s.json" % m)
		var players: Array = BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), 1).squad.slice(0, 3)
		var b := BWBattle.new(bd, 1)
		b.setup(players, BWEncounters.build(r, 5, "horde"))
		var at := {}
		for u in b.side("enemy"):
			at[u.pos] = true
			if not bd.is_passable(u.pos):
				t.ok(false, "%s: %s stands on a passable hex" % [m, u.name])
		t.eq(at.size(), 10, "%s: ten distinct spawn hexes" % m)
		t.ok(players.all(func(p): return not at.has(p.pos)), "%s: none on a player" % m)


func test_colossus_size_and_thrust(t) -> void:
	var r := _run()
	var c: BWUnit = BWEncounters.build(r, 6, "colossus")[0]
	t.eq(c.size, 2, "size 2")
	t.eq(c.footprint(Vector2i(6, 6)).size(), 7, "seven hexes")
	t.eq(c.weapon_class, "lance", "a spear (lance, reach 2)")
	t.ok(c.element == "", "elementless")
	var normal := r.enemies_for(6, { "kind": "hard", "enemies": BWRooms._draw_ids(r, 6, [], true) })
	t.ok(c.max_hp() > 2 * normal[0].max_hp(), "a big pool (%d)" % c.max_hp())
	var b := BWBattle.new(_board(), 1)
	var a := _unit("a", "sword", "sword", "", "player")
	var d := _unit("d", "sword", "sword", "", "player")
	var far := _unit("far", "sword", "sword", "", "player")
	b.setup([a, d, far], [c])
	t.ok(b._immune(c, "displace"), "it can't be displaced")
	c.pos = Vector2i(6, 6)
	far.pos = Vector2i(0, 13)
	var line: Array = []
	var n1: Vector2i = BWHex.neighbors(c.pos)[0]
	a.pos = BWHex.neighbors(n1)[0]                  # 2 out: just past its body
	d.pos = BWHex.neighbors(BWHex.neighbors(a.pos)[0])[0]   # 4 out: the line's last hex
	line = b.thrust_line(c, a)
	t.eq(line.size(), BWBattle.THRUST_LEN, "the thrust runs three hexes out from its body")
	t.ok(a.pos in line and d.pos in line, "both foes on it")
	var st := b.basic_strikes(c, a)
	t.eq(st.size(), 2, "the line thrust strikes both foes")
	t.eq(st.map(func(x): return x.unit), [a, d], "the target first, then the one behind")
	t.ok(b.in_range(c, a), "the target is in its reach")


## The author's matrix: physical vs elemental, against a Blank and a Being.
func test_damage_class_matrix(t) -> void:
	var W := BWFormulas.WEAPON
	var S := BWFormulas.SKILL
	var P := BWFormulas.SPELL
	var cases := [
		[{ "source": "basic", "kind": W, "element": "" }, "physical", "basic"],
		[{ "source": "basic", "kind": W, "element": "fire" }, "physical", "imbued basic"],
		[{ "source": "skill", "kind": S, "element": "ice" }, "elemental", "element skill"],
		[{ "source": "skill", "kind": S, "element": "" }, "physical", "non-element skill"],
		[{ "source": "basic", "kind": P, "element": "fire" }, "elemental", "staff basic"],
		[{ "source": "skill", "kind": P, "element": "fire" }, "elemental", "staff spell"],
		[{ "source": "tile" }, "elemental", "tile"],
		[{ "source": "detonation" }, "elemental", "detonation"],
		[{ "source": "chain" }, "elemental", "chain arc"],
		[{ "source": "slam" }, "physical", "slam"],
		[{ "source": "pulse" }, "", "obelisk pulse"],
	]
	for c in cases:
		t.eq(BWFormulas.damage_class(c[0]), c[1], "%s is %s" % [c[2], c[1] if c[1] != "" else "neither"])
	var blank := _foe("bl", "blank")
	var being := _foe("be", "being", "fire")
	t.ok(BWFormulas.immune_to(blank, "elemental") and not BWFormulas.immune_to(blank, "physical"), "Blank: immune to elemental only")
	t.ok(BWFormulas.immune_to(being, "physical") and not BWFormulas.immune_to(being, "elemental"), "Being: immune to physical only")


## The same matrix through the battle: forecasts, tiles, blasts and arcs.
func test_matrix_in_battle(t) -> void:
	for kind in ["blank", "being"]:
		var sw := _unit("sw", "sword", "sword", "ice", "player")
		var v := _foe("v", kind, "fire" if kind == "being" else "")
		var w := _foe("w", kind, "fire" if kind == "being" else "")
		var b := _battle(sw, [v, w])
		var blank: bool = kind == "blank"
		# basic (melee)
		var fc := b.forecast_basic(sw, v)
		t.eq(fc.has("immune"), not blank, "%s: basic %s" % [kind, "lands" if blank else "immune"])
		if blank:
			t.ok(fc.notes.has("×2: melee vs Blank"), "Blank: the ×2 melee line (%s)" % [fc.notes])
		else:
			t.ok(fc.notes.has("Immune: physical"), "Being: the Immune line")
			t.eq(int(fc.damage.value), 0, "Being: no damage")
			t.eq(BWFormulas.resolve(fc, b.rng).damage, 0, "Being: a rolled basic deals 0")
		# imbued basic
		sw.equipment["main_hand"] = { "base": "sword", "weight": "sword", "slot": "main_hand", "tier": "C", "stats": {}, "enchant": "", "worn": {}, "imbue": "fire" }
		var fi := b.forecast_basic(sw, v)
		t.eq(fi.has("immune"), not blank, "%s: imbued basic %s" % [kind, "lands" if blank else "immune"])
		if blank:
			t.eq(str(fi.element), "", "Blank: the imbue's element is stripped")
		sw.equipment.erase("main_hand")
		# element skill / non-element skill
		var row := BWSkills.get_skill("cleave")
		var fe := b._skill_forecast(sw, row, "ice", v)
		t.eq(fe.has("immune"), blank, "%s: element skill %s" % [kind, "immune" if blank else "lands"])
		var fn := b._skill_forecast(sw, row, "", v)
		t.eq(fn.has("immune"), not blank, "%s: non-element skill %s" % [kind, "lands" if blank else "immune"])
		# staff
		var st := _unit("st", "staff", "staff", "fire", "player")
		st.pos = Vector2i(5, 8)
		var fs := b.forecast_basic(st, v)
		t.eq(fs.has("immune"), blank, "%s: staff spell %s" % [kind, "immune" if blank else "lands"])
		# tile, detonation, chain, slam
		for cause in ["fire", "detonation"]:
			var hp := v.hp
			b._tile_hurt(v, 10, cause, "")
			t.eq(v.hp == hp, blank, "%s: %s damage %s" % [kind, cause, "immune" if blank else "lands"])
		var hp2 := w.hp
		b._arc(sw, v, w, 20.0)
		t.eq(w.hp == hp2, blank, "%s: chain arc %s" % [kind, "immune" if blank else "lands"])
		var hp3 := v.hp
		b._tile_hurt(v, 10, "slam", "")
		t.eq(v.hp == hp3, not blank, "%s: slam %s" % [kind, "lands" if blank else "immune"])
		if blank:
			b._add_status(v, "scorched", sw, 1)
			t.ok(not v.statuses.has("scorched"), "Blank: no elemental status")


## The AI reads the immunities: no basic at a Being, an element skill
## instead; a melee basic goes to a Blank first (×2).
func test_ai_chooses_by_immunity(t) -> void:
	var sw := _unit("sw", "axe", "axe", "ice", "player")      # Cleave and Charge, both with an element
	sw.affinity["ice"] = 20
	var being := _foe("be", "being", "fire")
	var b := _battle(sw, [being])
	t.ok(BWAI._best_target(b, sw, sw.pos).is_empty(), "no basic attack on a Being")
	var sk := BWAI._best_skill(b, sw)
	t.ok(not sk.is_empty() and str(sk.element) != "", "an element skill instead (%s)" % [sk])
	var sw2 := _unit("sw2", "sword", "sword", "ice", "player")
	var blank := _foe("bl", "blank")
	var plain := _foe("pl", "")
	var b2 := _battle(sw2, [plain, blank])
	blank.pos = Vector2i(5, 7)
	plain.pos = Vector2i(6, 6)
	var bt := BWAI._best_target(b2, sw2, sw2.pos)
	t.ok(not bt.is_empty() and bt.target == blank, "a melee basic goes to the Blank (×2)")
	# a Blank, struck by an element skill, is immune: the AI's skill score is 0 on it alone
	var b3 := _battle(_unit("sw3", "axe", "axe", "ice", "player"), [_foe("bl2", "blank")])
	var u3: BWUnit = b3.side("player")[0]
	u3.affinity["ice"] = 20
	var s3 := BWAI._best_skill(b3, u3)
	t.ok(s3.is_empty() or str(s3.element) == "", "no element skill at a lone Blank (%s)" % [s3])

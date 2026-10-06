extends RefCounted
## D160-D161 (readability): the action simulator behind the blast preview
## (BWBattle.simulate on a clone, expected rolls), its purity, that its
## ground outcome matches the real resolution, and the tile hover card's
## ground report. Helpers come from test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const T := Vector2i(7, 4)          # the glazed water 3 + dark 3 hex, 3 east of C
const G := Vector2i(8, 4)          # east of T: a foe on a fuse (conductive)
const A := Vector2i(7, 5)          # south-east of T: an ally in the splash

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


## The reference scene: a thunder staff bolts a foe on glazed water 3 +
## dark 3; a second foe beside it stands on a fuse; an ally stands in the splash.
func _scene(seed_value: int = 7) -> Array:
	var me: BWUnit = K._equip(K._u("me", "staff", "thunder", { "wil": 6 }), ["bolt"])
	var ally: BWUnit = K._u("ally", "sword", "fire", { "con": 40 })
	var f: BWUnit = K._foe("f")
	var g: BWUnit = K._foe("g")
	var b: BWBattle = K._fight(me, [f, g], [T, G], seed_value, [ally], [A])
	b.tiles.apply([T], "water", "x", 3)
	b.tiles.apply([T], "dark", "x", 3)
	b.tiles.apply([T], "ice", "x")
	b.tiles.apply([G], "thunder", "x")
	return [b, me, ally, f, g]


func test_simulate_shows_the_whole_blast(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var me: BWUnit = s[1]
	t.ok(b.tiles.is_glazed(T) and b.tiles.conductive(G), "scene: glazed water+dark under f, a fuse under g")
	var sim := b.simulate(me, { "kind": "skill", "key": "bolt", "element": "thunder", "hex": T })
	t.ok(not sim.is_empty(), "the bolt simulates")
	if sim.is_empty():
		return
	t.eq(sim.detonations.size(), 1, "one detonation")
	t.near(float(sim.detonations[0].pct), 52.5, 0.01, "water 3 + dark 3 glazed = 35% x 1.5 shatter")
	t.ok("detonate" in sim.hexes[T].kinds, "the target hex is marked to detonate")
	t.ok(sim.units.has("ally") and sim.units.ally.friendly and sim.units.ally.damage > 0, "the ally in the splash is flagged friendly, with damage")
	t.ok(sim.units.ally.sources.any(func(x): return x.kind == "splash"), "the ally's damage is splash")
	t.ok(sim.units.has("f") and sim.units.f.sources.any(func(x): return x.kind == "blast"), "the target takes the full blast")
	t.ok(sim.units.f.sources.any(func(x): return x.kind == "hit" and x.approx), "the bolt's own hit is an expected value (~)")
	t.ok(not sim.chains.is_empty() and sim.chains[0].from == "g", "g's splash on its fuse arcs (chain preview)")
	t.ok(not sim.chains.is_empty() and not sim.chains[0].approx, "an arc from splash is exact (no roll)")


func test_simulate_is_pure(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var me: BWUnit = s[1]
	var rng_state := b.rng.state
	var hist := b.history.size()
	var tiles_before := var_to_str(b.tiles.entries)
	var hps: Array = b.units.map(func(u): return u.hp)
	var poss: Array = b.units.map(func(u): return u.pos)
	var cds := var_to_str(me.cooldowns)
	for k in 3:
		b.simulate(me, { "kind": "skill", "key": "bolt", "element": "thunder", "hex": T })
	t.eq(b.rng.state, rng_state, "no rng drawn from the real battle")
	t.eq(b.history.size(), hist, "no event in the real battle")
	t.eq(var_to_str(b.tiles.entries), tiles_before, "the real ground is untouched")
	t.eq(b.units.map(func(u): return u.hp), hps, "nobody's HP changed")
	t.eq(b.units.map(func(u): return u.pos), poss, "nobody moved")
	t.eq(var_to_str(me.cooldowns), cds, "no cooldown spent")
	t.ok(not me.acted and b.current() == me, "the actor still has its action")


func test_simulated_ground_matches_the_real_resolution(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var me: BWUnit = s[1]
	var ally: BWUnit = s[2]
	var sim := b.simulate(me, { "kind": "skill", "key": "bolt", "element": "thunder", "hex": T })
	var hp0 := ally.hp
	var n := b.history.size()
	b.use_skill(me, "bolt", "thunder", T)
	var real := b.history.slice(n)
	var dets: Array = real.filter(func(e): return e.type == "detonate")
	t.eq(dets.size(), sim.detonations.size(), "same detonations")
	t.eq(hp0 - ally.hp, int(sim.units.ally.damage), "the ally's splash is exactly what the preview said")
	var arcs: Array = real.filter(func(e): return e.type == "chain")
	t.eq(arcs.size(), sim.chains.size(), "same arcs")
	if not arcs.is_empty() and not sim.chains.is_empty():
		t.eq(int(arcs[0].amount), int(sim.chains[0].amount), "the arc amount matches")
		t.eq(str(arcs[0].to), str(sim.chains[0].to), "the arc goes where the preview said")


func test_simulate_attack_and_illegal(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var me: BWUnit = s[1]
	t.ok(b.simulate(me, { "kind": "skill", "key": "bolt", "element": "thunder", "hex": Vector2i(0, 10) }).is_empty(),
		"an illegal target simulates to {}")
	var f: BWUnit = s[3]
	var sim := b.simulate(me, { "kind": "attack", "target": "f" })
	var legal := b.in_range(me, f)
	t.ok(sim.is_empty() != legal, "a basic attack simulates exactly when it is legal (%s)" % legal)


func test_clone_is_independent(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var c := b.clone()
	t.eq(c.units.size(), b.units.size(), "same units")
	t.ok(c.units.all(func(u): return not u in b.units), "every unit is a copy")
	t.ok(c.queue.all(func(u): return u in c.units), "the queue points at the copies")
	t.eq(c.current().id, b.current().id, "same turn")
	c.tiles.apply([C], "fire", "x", 3)
	c.units[0].hp = 1
	t.ok(b.tiles.at(C).is_empty() and b.units[0].hp > 1, "changing the copy leaves the battle alone")
	t.ok(b.board.extra_cost.get_object() == b.tiles, "the board's move cost still reads the real tiles")


func test_ground_report(t) -> void:
	var s := _scene()
	var b: BWBattle = s[0]
	var f: BWUnit = s[3]
	var ally: BWUnit = s[2]
	var r := b.ground_report(T)
	t.eq(int(r.entry.h), -3, "water 3")
	t.eq(int(r.entry.v), -3, "dark 3")
	t.ok(int(r.entry.glaze) > 0, "glazed")
	t.eq(r.unit, "f", "f stands on it")
	t.ok(int(r.turn.damage) > 0, "dark 3 drains f next turn")
	t.ok(b.ground_report(G).conductive, "the fuse reads conductive")
	b.tiles.apply([A], "fire", "x", 2)
	var ra := b.ground_report(A)
	var want := ally.hp
	K._give_turn(b, ally)
	t.eq(want - ally.hp, int(ra.turn.damage), "the fire's damage at the ally's turn start matches the card")

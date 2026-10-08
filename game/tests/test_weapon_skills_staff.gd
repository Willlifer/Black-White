extends RefCounted
## D107 (staff): the new spells and the Improve riders. Helpers come from
## test_weapon_skills_melee.gd.

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)
const X := Vector2i(4, 2)          # 2 north of C

var K: Object = preload("res://tests/test_weapon_skills_melee.gd").new()


func test_bolt(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["bolt"])
	var at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [at])
	var fc: Dictionary = b.skill_preview(me, "bolt", "fire", at).forecasts["f"]
	t.eq(fc.kind, BWFormulas.SPELL, "a spell")
	t.ok(K._mod(fc, "Bolt").is_empty() and fc.notes.any(func(n): return str(n).begins_with("+20%")), "bare ground: the bonus is only a note")
	b.tiles.apply([at], "fire", "x")
	fc = b.skill_preview(me, "bolt", "fire", at).forecasts["f"]
	t.near(float(K._mod(fc, "Bolt").get("value", 0)), 1.2, 0.001, "+20% on its own element")
	K._use(t, b, me, "bolt", "fire", at)
	t.eq(me.cooldowns.get("bolt_fire", 0), 1, "cd 1")


func test_transfer_lifts_under_a_foe(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["transfer"])
	var foe_at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [foe_at])
	b.tiles.apply([X], "fire", "x", 2)
	var pv := b.skill_preview(me, "transfer", "", X)
	t.eq(pv.hexes, [X, foe_at], "fire goes under the foe")
	t.eq(pv.follow_up, ["basic"], "then a basic")
	K._use(t, b, me, "transfer", "", X)
	t.ok(b.tiles.at(X).is_empty(), "lifted off the source")
	t.eq(b.tiles.intensity(foe_at, "fire"), 2, "set down whole")
	t.eq(str(b.tiles.at(foe_at).source), "me", "now the caster's")
	t.eq(me.follow_up, ["basic"], "follow-up granted")
	t.eq(me.cooldowns.get("transfer", 0), 3, "cd 3")
	# nothing on the hex: not a target
	t.ok(not E in b.skill_targets(me, "transfer", ""), "bare ground is not a target")


func test_transfer_plus_spreads(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	K._equip(me, ["transfer"])
	me.skill_ranks["transfer"] = 2
	var foe_at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [foe_at])
	b.tiles.apply([X], "dark", "x", 2)
	b.use_skill(me, "transfer", "", X)
	t.ok(Array(BWHex.area(foe_at, 1)).filter(func(h): return h != X).all(func(h): return b.tiles.intensity(h, "dark") == 2),
		"Transfer+: the destination and its ring")


## D418: Inversion flips every tile within 2 of the aimed hex and does
## nothing else (no damage, no status, no follow-up), cd 4.
func test_inversion(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["inversion"])
	var foe_at := Vector2i(5, 2)                        # inside X's radius
	var b: BWBattle = K._fight(me, [K._foe()], [foe_at])
	var far := Vector2i(4, 8)                           # 6 from X: outside
	var ring2: Array = Array(BWHex.ring(X, 2))
	b.tiles.apply([X], "fire", "x", 3)
	b.tiles.apply([foe_at], "dark", "x", 2)
	b.tiles.apply([ring2[0]], "thunder", "x")          # a fuse 2 away
	b.tiles.apply([far], "fire", "x", 2)
	t.ok(not Vector2i(4, 9) in b.skill_targets(me, "inversion", ""), "nothing to flip in the area: not a target")
	t.ok(Vector2i(4, 0) in b.skill_targets(me, "inversion", ""), "a bare hex with charged tiles within 2 is a target")
	var sim := b.simulate(me, { "kind": "skill", "key": "inversion", "element": "", "hex": X })
	t.eq((sim.inversion.area as Array).size(), BWHex.area(X, 2).filter(func(h): return b.board.exists(h)).size(), "the preview carries the whole area")
	t.eq((sim.inversion.swaps as Array).size(), 3, "and one swap per charged tile")
	t.ok(sim.hexes.has(X) and "invert" in sim.hexes[X].kinds, "the preview marks the flipped tile")
	t.ok(sim.units.is_empty(), "nobody's HP changes")
	var hp0: int = b.units[1].hp
	K._use(t, b, me, "inversion", "", X)
	t.eq(b.tiles.intensity(X, "water"), 3, "fire 3 becomes water 3")
	t.eq(b.tiles.intensity(foe_at, "light"), 2, "dark 2 under the foe becomes light 2")
	t.eq(str(b.tiles.at(ring2[0]).marker), "gale", "a fuse 2 away becomes a gale")
	t.eq(b.tiles.intensity(far, "fire"), 2, "outside the radius: untouched")
	t.eq(me.follow_up, [], "no follow-up any more")
	t.eq(b.units[1].hp, hp0, "no damage")
	t.ok(b.units[1].statuses.is_empty(), "no status")
	t.eq(me.cooldowns.get("inversion", 0), 4, "cd 4")


func test_inversion_plus_ring(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["inversion"])
	me.skill_ranks["inversion"] = 2
	var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)])
	var area: Array = Array(BWHex.area(X, 2)).filter(func(h): return b.board.exists(h))
	b.tiles.apply(area, "light", "x", 2)
	b.use_skill(me, "inversion", "", X)
	t.ok(area.all(func(h): return b.tiles.intensity(h, "dark") == 2), "all 19 flip")
	t.eq(me.cooldowns.get("inversion", 0), 3, "Inversion+: cd 3")


## D418: the AI flips a field of enemy fire from under its allies.
func test_inversion_ai(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["inversion"])
	var mate: BWUnit = K._u("m", "sword", "fire")
	var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)], 7, [mate], [X])
	var area: Array = Array(BWHex.area(X, 1)).filter(func(h): return b.board.exists(h))
	b.tiles.apply(area, "fire", "f", 3)
	var pick: Dictionary = BWSkillRegistry.get_def("inversion").ai_support(b, me, {})
	t.ok(not pick.is_empty() and BWHex.distance(pick.target, X) <= 2, "the AI aims Inversion over its ally on fire: %s" % pick)


func test_tempest(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["tempest"])
	var centre: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [centre])
	var pv := b.skill_preview(me, "tempest", "fire", centre)
	t.eq(pv.hexes.size(), 19, "radius 2")
	t.eq(pv.forecasts["f"].kind, BWFormulas.SPELL, "a spell")
	K._use(t, b, me, "tempest", "fire", centre)
	t.ok((pv.hexes as Array).all(func(h): return b.tiles.carries(h, "fire")), "all 19 painted")
	K._give_turn(b, me)
	t.ok(not b.skills_for(me).any(func(s): return s.key == "tempest"), "once per battle")


func test_surge_plus(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	me.skill_ranks["surge"] = 2
	var at: Vector2i = K._line(3)[2]
	var b: BWBattle = K._fight(me, [K._foe()], [at])
	t.near(float(K._mod(b.skill_preview(me, "surge", "fire", at).forecasts["f"], "Surge+ centre").get("value", 0)), 1.5, 0.001, "+50%")


func test_saturate_plus_marks_at_two(t) -> void:
	var marked := 0
	for sd in 8:
		var me: BWUnit = K._u("me", "staff", "fire")
		me.skill_ranks["saturate"] = 2
		var foe: BWUnit = K._foe()
		var at: Vector2i = K._line(2)[1]
		var b: BWBattle = K._fight(me, [foe], [at], 80 + sd)
		t.ok(b.skill_preview(me, "saturate", "fire", at).notes.any(func(n): return str(n).begins_with("Fire to 2")), "named")
		var ev := b.use_skill(me, "saturate", "fire", at)
		t.eq(b.tiles.intensity(at, "fire"), 2, "poured to 2")
		t.eq(foe.statuses.has("scorched"), bool(ev.results[0].result.secondary), "Scorched at 2 iff not resisted")
		marked += 1 if foe.statuses.has("scorched") else 0
	t.ok(marked > 0, "marked at least once")
	var plain: BWUnit = K._u("me", "staff", "fire")
	var f2: BWUnit = K._foe()
	var b2: BWBattle = K._fight(plain, [f2], [K._line(2)[1]])
	b2.use_skill(plain, "saturate", "fire", K._line(2)[1])
	t.ok(not f2.statuses.has("scorched"), "without the Improve, 2 doesn't mark")


func test_ley_line_plus(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	me.skill_ranks["ley_line"] = 2
	var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)])
	t.eq(b.skill_preview(me, "ley_line", "fire", E).hexes.size(), 6, "length 6")


func test_siphon_plus_heals_the_ally_on_the_hex(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	me.skill_ranks["siphon"] = 2
	var mate: BWUnit = K._u("m", "sword", "fire")
	var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)], 7, [mate], [X])
	b.tiles.apply([X], "dark", "x", 2)
	mate.hp = 50
	t.ok(b.skill_preview(me, "siphon", "", X).notes.any(func(n): return str(n).begins_with("Siphon heals m 12%")), "named: the ally, 6% a step")
	b.use_skill(me, "siphon", "", X)
	var heals: Array = K._events(b, "heal").filter(func(e): return e.get("cause", "") == "siphon")
	t.eq(heals.map(func(e): return e.unit), ["m"], "the ally on the hex heals")
	t.eq(int(heals[0].amount), roundi(mate.max_hp() * 12 / 100.0), "6% per step, 2 steps")


## D109: the player's second pick sets the destination; an illegal one is refused.
func test_transfer_second_pick(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["transfer"])
	var b: BWBattle = K._fight(me, [K._foe()], [Vector2i(9, 9)])
	b.tiles.apply([X], "fire", "x", 2)
	var seconds: Array = BWSkillRegistry.get_def("transfer").second_targets(b, me, "", X)
	var dest := Vector2i(3, 5)
	t.ok(dest in seconds and not X in seconds, "empty hexes within 4, not the source")
	t.ok(not Vector2i(10, 10) in seconds, "nothing past range 4")
	t.eq(b.skill_preview(me, "transfer", "", X, dest).hexes, [X, dest], "the preview follows the pick")
	t.ok(b.skill_preview(me, "transfer", "", X, Vector2i(10, 10)).is_empty(), "an illegal pick: no preview")
	t.ok(b.use_skill(me, "transfer", "", X, Vector2i(10, 10)).is_empty(), "... and no use")
	t.ok(not b.use_skill(me, "transfer", "", X, dest).is_empty(), "a legal pick resolves")
	t.eq(b.tiles.intensity(dest, "fire"), 2, "set down where picked")


## D112: the AI lifts fire under a foe and then takes its basic follow-up.
func test_ai_transfers_then_strikes(t) -> void:
	var me: BWUnit = K._equip(K._u("me", "staff", "fire"), ["transfer"])
	var foe: BWUnit = K._foe()
	var b: BWBattle = K._fight(me, [foe], [E])
	b.tiles.apply([X], "fire", "x", 3)
	BWAI.take_turn(b)
	var kinds: Array = b.history.filter(func(e): return e.type in ["skill", "attack"]).map(func(e): return str(e.get("skill", e.type)))
	t.eq(kinds.slice(0, 2), ["transfer", "attack"], "Transfer, then the basic (%s)" % [kinds])
	t.ok(b.history.any(func(e): return e.type == "paint" and e.get("kind", "") == "transfer" and E in e.hexes), "the fire went under the foe")
	# D285: the staff's fire basic then lands on that fire 3: it Overheats and vents to 2
	t.ok(b.history.any(func(e): return e.type == "overheat" and e.hex == E), "and the fire blow on it Overheats")
	t.eq(b.tiles.intensity(E, "fire"), 2, "venting to fire 2")


## D435-D442: the retired skills' tests moved to test_kit3 (their replacements; the defs stay only for old saves).

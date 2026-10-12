extends RefCounted
## D564-D569 (author, 2026-10-11): Runneth Over (water on water 3), Glinting
## (light on light 3), and the duos The Scalding (fire + water), FrostFire
## (fire + ice), Charged Ice (ice + thunder) and Sunbolt (thunder + light).

const C := Vector2i(5, 5)

var K: Object = preload("res://tests/test_keystones_v3.gd").new()


func _scene(me: BWUnit, foe_at: Vector2i, ally_at: Vector2i = Vector2i(-1, -1)) -> Array:
	var f: BWUnit = K._u("f", "axe", "fire")
	var allies: Array = []
	var apos: Array = []
	if ally_at.x >= 0:
		allies = [K._u("a", "axe", "fire")]
		apos = [ally_at]
	var b: BWBattle = K._duel(me, [f], [foe_at], allies, apos)
	b.history.clear()
	return [b, f, allies[0] if not allies.is_empty() else null]


func _glaze(b: BWBattle, h: Vector2i, hv: int, by: String) -> void:
	K._lay(b, h, hv, 0, by)
	b.tiles.entries[h].glaze = BWTiles.GLAZE_CYCLES
	b.tiles.entries[h]["glaze_source"] = by


# ------------------------------------------------------------------ Runneth Over, Glinting

func test_runneth_over(t) -> void:
	var me: BWUnit = K._u("me", "staff", "water")
	var x: Vector2i = K._nb(C, 0, 3)
	var s := _scene(me, K._nb(x, 1), K._nb(x, 4))
	var b: BWBattle = s[0]
	var f: BWUnit = s[1]
	var a: BWUnit = s[2]
	K._lay(b, x, -3, 0, "me")
	var hot: Vector2i = K._nb(x, 2)
	K._lay(b, hot, 1, 0, "f")
	var r := b.paint([x], "water", me)
	t.eq((r.get("brim", []) as Array).size(), 1, "water on water 3 runs over")
	t.eq(b.tiles.intensity(x, "water"), 3, "the hex stays water 3")
	t.eq(b.tiles.intensity(K._nb(x, 3), "water"), 1, "an empty neighbour gets water 1")
	t.ok(b.tiles.at(hot).is_empty(), "a fire 1 neighbour is doused")
	t.ok(f.statuses.has("drenched"), "the foe on the ring is Drenched")
	t.ok(not a.statuses.has("drenched"), "the ally isn't")
	t.eq(K._ev(b, "runneth_over").size(), 1, "the event")
	var y: Vector2i = K._nb(C, 3, 3)
	K._lay(b, y, -2, 0, "me")
	t.ok((b.paint([y], "water", me).get("brim", []) as Array).is_empty(), "water 2 just fills to 3")


func test_glinting(t) -> void:
	var me: BWUnit = K._u("me", "staff", "light")
	var x: Vector2i = K._nb(C, 0, 3)
	var s := _scene(me, x, K._nb(x, 4))
	var b: BWBattle = s[0]
	var f: BWUnit = s[1]
	var a: BWUnit = s[2]
	K._lay(b, x, 0, 3, "me")
	b.paint([x], "light", me)
	t.eq(K._ev(b, "glinting").size(), 1, "light on light 3 glints")
	t.ok(f.statuses.has("blinded"), "the foe on it is Blinded")
	t.ok(not a.statuses.has("blinded"), "the ally beside it isn't")
	t.eq(b.tiles.intensity(x, "light"), 2, "the hex dims to light 2")
	b.history.clear()
	b.paint([x], "light", me)
	t.ok(K._ev(b, "glinting").is_empty(), "light 2 + 1 is light 3 again: no glint")


func test_forecast_and_card(t) -> void:
	var me: BWUnit = K._u("me", "staff", "water")
	var b: BWBattle = _scene(me, Vector2i(10, 10))[0]
	var x: Vector2i = K._nb(C, 0, 2)
	K._lay(b, x, -3, 0, "me")
	t.ok(BWBrim.card_lines(b, x).any(func(l): return str(l).begins_with("Runneth Over")), "the tile card names it")
	var p := { "element": "water", "hexes": [x], "notes": [] }
	BWBrim.plan_notes(b, me, p)
	t.ok(str(p.notes).contains("Runneth Over"), "the forecast names it")


# ------------------------------------------------------------------ duos

func test_rows(t) -> void:
	for id in ["duo_scalding", "duo_frostfire", "duo_charged_ice", "duo_sunbolt"]:
		t.ok(not BWData.row("perks", id).is_empty(), id)
	t.eq(str(BWData.row("perks", "duo_scalding").name), "The Scalding", "named The Scalding")


func test_scalding(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	var x: Vector2i = K._nb(C, 0, 3)
	var s := _scene(me, x)
	var b: BWBattle = s[0]
	var f: BWUnit = s[1]
	me.fx["duo:scalding"] = true
	K._lay(b, x, -2, 0, "me")
	var hp := f.hp
	var r := b.paint([x], "fire", me)
	t.eq(r.detonations.size(), 1, "your fire on your water goes off")
	t.eq(float(r.detonations[0].pct), float(BWTiles.DETONATE_BASE_PCT), "the base 5% blast")
	t.ok(f.hp < hp, "the foe on it takes it")
	t.ok(b.tiles.at(x).is_empty(), "and it's still a douse")
	K._lay(b, x, 2, 0, "me")
	t.eq(b.paint([x], "water", me).detonations.size(), 1, "your water on your fire too")
	K._lay(b, x, -2, 0, "f")
	t.eq(b.paint([x], "fire", me).detonations.size(), 0, "someone else's water: a plain douse")
	var plain: BWUnit = K._u("p", "staff", "fire")
	var b2: BWBattle = _scene(plain, Vector2i(10, 10))[0]
	K._lay(b2, x, -2, 0, "p")
	t.eq(b2.paint([x], "fire", plain).detonations.size(), 0, "without it: a plain douse")


func test_frostfire(t) -> void:
	var me: BWUnit = K._u("me", "staff", "fire")
	var b: BWBattle = _scene(me, Vector2i(10, 10))[0]
	me.fx["duo:frostfire"] = true
	var x: Vector2i = K._nb(C, 0, 2)
	_glaze(b, x, -3, "me")
	b.paint([x], "fire", me)
	t.ok(b.tiles.is_glazed(x), "your glaze holds")
	t.eq(b.tiles.intensity(x, "fire"), 1, "the fire burns under it")
	t.eq(b.tiles.intensity(x, "water"), 0, "in place of the water")
	b.paint([x], "fire", me, 2)
	t.eq(b.tiles.intensity(x, "fire"), 3, "and stacks")
	var y: Vector2i = K._nb(C, 3, 2)
	_glaze(b, y, -2, "f")
	b.paint([y], "fire", me)
	t.ok(not b.tiles.is_glazed(y), "someone else's glaze melts as ever")


func test_charged_ice(t) -> void:
	var me: BWUnit = K._u("me", "staff", "ice")
	var x: Vector2i = K._nb(C, 0, 3)
	var s := _scene(me, x)
	var b: BWBattle = s[0]
	me.fx["duo:charged_ice"] = true
	_glaze(b, x, -2, "me")
	var r := b.paint([x], "light", me)
	t.eq(r.detonations.size(), 1, "light on your glaze sets it off")
	t.eq(float(r.detonations[0].pct), (BWTiles.DETONATE_BASE_PCT + BWTiles.DETONATE_PER_POINT_PCT * 2 + BWTiles.CONDUCT_DET_PCT * 2) * BWTiles.SHATTER_MULT, "as a shatter (x1.5)")
	t.ok(b.tiles.at(x).is_empty(), "consumed")
	_glaze(b, x, -2, "me")
	t.eq(b.paint([x], "wind", me).detonations.size(), 1, "wind too")
	_glaze(b, x, -2, "me")
	t.eq(b.paint([x], "ice", me).detonations.size(), 0, "ice re-glazes instead")
	var y: Vector2i = K._nb(C, 3, 2)
	_glaze(b, y, -2, "f")
	t.eq(b.paint([y], "light", me).detonations.size(), 0, "someone else's glaze: washes off")
	me.fx["duo:frostfire"] = true
	_glaze(b, y, -2, "me")
	t.eq(b.paint([y], "fire", me).detonations.size(), 0, "FrostFire's fire holds the glaze instead")
	t.ok(b.tiles.is_glazed(y), "still glazed")


func test_sunbolt(t) -> void:
	var me: BWUnit = K._u("me", "staff", "thunder")
	var x: Vector2i = K._nb(C, 0, 3)
	var s := _scene(me, x, K._nb(x, 1))
	var b: BWBattle = s[0]
	var f: BWUnit = s[1]
	var a: BWUnit = s[2]
	me.fx["duo:sunbolt"] = true
	K._lay(b, x, 2, 0, "me")
	a.hp = a.max_hp() - 40
	var a0 := a.hp
	var f0 := f.hp
	b.paint([x], "thunder", me)
	t.ok(f.hp < f0, "the foe on it takes the blast")
	t.eq(a.hp - a0, maxi(1, roundi(a.pct_base_hp() * BWTiles.DETONATE_BASE_PCT / 100.0)), "the ally on the ring heals 5%")
	t.eq(K._ev(b, "sunbolt").size(), 1, "the event")

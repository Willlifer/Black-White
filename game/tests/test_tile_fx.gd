extends RefCounted
## Tile FX (Phase 5, D82): the entry -> layer mapping, BWBoardView's
## refresh / animation state, hex_parts, the event hooks, authored tiles.

const C := Vector2i(4, 4)


func _view(n: int = 9, terrain: String = "neutral") -> BWBoardView:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": terrain, "elevation": 0 })
	var board := BWBoard.from_dict({ "name": "t", "cols": n, "rows": n, "cells": cells })
	var bv := BWBoardView.new()
	bv.build(board, BWTiles.new(board))
	return bv


func _settle(bv: BWBoardView, secs: float = 1.0) -> void:
	var steps := int(secs / 0.05)
	for i in steps:
		bv._process(0.05)


func test_layers_mapping(t) -> void:
	var L := BWTileFX.layers({})
	t.ok(L.h.is_empty() and L.v.is_empty() and L.mark == "", "empty entry draws nothing")
	L = BWTileFX.layers({ "h": 2, "v": -1, "marker": "", "glaze": 0 })
	t.eq(L.h.el, "fire", "h>0 = fire")
	t.eq(L.h.tier, 2, "fire tier 2")
	t.eq(L.v.el, "dark", "v<0 = dark")
	t.eq(L.v.tier, 1, "dark tier 1")
	t.eq(L.top, "h", "dominant axis on top")
	L = BWTileFX.layers({ "h": -1, "v": 3, "marker": "", "glaze": 0 })
	t.eq(L.h.el, "water", "h<0 = water")
	t.eq(L.v.el, "light", "v>0 = light")
	t.eq(L.top, "v", "light 3 over water 1")
	L = BWTileFX.layers({ "h": 2, "v": -2, "marker": "", "glaze": 0 })
	t.eq(L.top, "h", "tie: fire/water on top")
	for mk in ["fuse", "gale", "stasis"]:
		L = BWTileFX.layers({ "h": 0, "v": 0, "marker": mk, "glaze": 0 })
		t.eq(L.mark, mk, "marker %s drawn" % mk)
	L = BWTileFX.layers({ "h": 1, "v": 0, "marker": "", "glaze": 2 })
	t.eq(L.mark, "glaze", "glazed charge shows the frost sheet")
	t.ok(not L.crack, "no cracks with 2 cycles left")
	L = BWTileFX.layers({ "h": 1, "v": 0, "marker": "", "glaze": 1 })
	t.ok(L.crack, "cracks in the glaze's last cycle")


func test_refresh_and_tier_animation(t) -> void:
	var bv := _view()
	t.eq(bv.hex_parts(C).size(), 7, "hex_parts: tile, highlight, five FX layers")
	var nodes := bv.fx_nodes(C)
	t.ok(not nodes.face_h.visible and not nodes.mark.visible, "nothing shows on a clean board")
	bv.tiles.apply([C], "fire", "a")
	bv.refresh_tiles()
	t.eq(bv.fx_state(C).h.tier, 1, "state follows the board")
	t.near(bv.fx_tier(C, "h"), 0.0, 0.001, "tier does not pop")
	bv._process(0.15)
	t.ok(bv.fx_tier(C, "h") > 0.2 and bv.fx_tier(C, "h") < 0.9, "half-way through the 0.3 s grow")
	_settle(bv)
	t.near(bv.fx_tier(C, "h"), 1.0, 0.001, "grown to tier 1")
	t.ok(nodes.face_h.visible and nodes.face_h.material_override == BWTileFX.material("tile_fire"), "fire face shown")
	t.ok(nodes.cards_h.visible, "smoke cards at tier 1")
	bv.tiles.apply([C], "fire", "a", 2)
	bv.refresh_tiles()
	bv._process(0.15)
	t.ok(bv.fx_tier(C, "h") > 1.5 and bv.fx_tier(C, "h") < 2.9, "1 -> 3 also takes ~0.3 s")
	_settle(bv)
	t.near(bv.fx_tier(C, "h"), 3.0, 0.001, "tier 3")
	# element swap on one axis: fade out, then grow the other
	bv.tiles.entries[C].h = -2
	bv.refresh_tiles()
	_settle(bv)
	t.eq(nodes.face_h.material_override, BWTileFX.material("tile_water"), "swapped to water")
	t.ok(not nodes.cards_h.visible, "water stands nothing up")
	t.near(bv.fx_tier(C, "h"), 2.0, 0.001, "water 2")
	bv.tiles.clear(C)
	bv.refresh_tiles()
	_settle(bv)
	t.ok(not nodes.face_h.visible, "erased tile shrinks away and hides")
	bv.free()


func test_mixed_markers_glaze(t) -> void:
	var bv := _view()
	var nodes := bv.fx_nodes(C)
	bv.tiles.author(C, 1, -3)
	bv.refresh_tiles()
	_settle(bv)
	t.ok(nodes.face_h.visible and nodes.face_v.visible, "mixed tile layers both axes")
	t.ok(nodes.face_v.sorting_offset > nodes.face_h.sorting_offset, "dark 3 drawn over fire 1")
	t.ok(nodes.cards_v.visible and nodes.cards_v.material_override == BWTileFX.material("tile_tendril"), "abyss tendrils")
	bv.tiles.apply([C], "ice", "a")
	bv.refresh_tiles()
	t.near(float(bv._fx_anim[C].mark.form), 0.0, 0.001, "glaze forming starts at the centre")
	_settle(bv)
	t.ok(nodes.mark.visible and nodes.mark.material_override == BWTileFX.material("glaze"), "frost sheet")
	t.near(float(bv._fx_anim[C].mark.frost), 1.0, 0.001, "glows under the glaze are dimmed")
	bv.tiles.tick()
	bv.refresh_tiles()
	_settle(bv)
	t.near(float(bv._fx_anim[C].mark.crack), 1.0, 0.001, "last cycle cracks")
	for mk in ["thunder", "wind", "ice"]:
		var m := Vector2i(2, 2) + Vector2i(["thunder", "wind", "ice"].find(mk) * 2, 0)   # D405: ice / wind on a fuse would ignite it
		bv.tiles.apply([m], mk, "a")
		bv.refresh_tiles()
		_settle(bv)
		t.eq(bv.fx_nodes(m).mark.material_override,
			BWTileFX.material(BWTiles.OPERATORS[mk]), "%s marker material" % mk)
	bv.free()


func test_event_hooks(t) -> void:
	var bv := _view()
	var before := bv.get_child_count()
	bv.on_tile_event({ "type": "detonate", "hex": C, "pct": 9.0, "radius": 1 })
	t.eq(bv.get_child_count(), before + 2, "detonation: ring + flash")
	# gale: wind on a charged tile copies to the neighbours, the origin gusts
	bv.tiles.apply([C], "fire", "a")
	bv.refresh_tiles()
	var r := bv.tiles.apply([C], "wind", "a")
	var n := bv.get_child_count()
	bv.on_tile_event({ "type": "paint", "element": "wind", "hexes": r.changed })
	t.eq(bv.get_child_count(), n + 1, "one gust ring at the origin only")
	n = bv.get_child_count()
	bv.on_tile_event({ "type": "tiles_tick", "seeded": [Vector2i(1, 1), Vector2i(1, 2)] })
	t.eq(bv.get_child_count(), n + 6, "ignition: ring + flash + flare per seeded hex")
	_settle(bv, 1.5)
	t.ok(bv._bursts.is_empty(), "one-shots retire themselves")
	bv.free()


func test_authored_maps(t) -> void:
	var board := BWBoard.load_file("res://maps/arena.json")
	var tl := BWTileFX.authored(board, "res://maps/arena.json")
	t.ok(tl != null and tl.board == board, "authored() always returns live tiles")
	var path := "user://test_tile_fx_map.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "name": "x", "cols": 3, "rows": 1, "effects": [
		{ "q": 0, "r": 0, "effect": "charge_2_-1" }, { "q": 1, "r": 0, "effect": "mark_fuse" }],
		"cells": [{ "q": 0, "r": 0, "terrain": "neutral", "elevation": 0 },
			{ "q": 1, "r": 0, "terrain": "neutral", "elevation": 0 },
			{ "q": 2, "r": 0, "terrain": "neutral", "elevation": 0, "effect": "charge_0_3" }] }))
	f.close()
	var b2 := BWBoard.load_file(path)
	var t2 := BWTileFX.authored(b2, path)
	t.eq(t2.at(Vector2i(0, 0)).h, 2, "authored fire 2")
	t.eq(t2.at(Vector2i(0, 0)).v, -1, "authored dark 1")
	t.ok(t2.at(Vector2i(0, 0)).permanent, "authored = permanent")
	t.eq(t2.at(Vector2i(1, 0)).marker, "fuse", "authored fuse")
	t.eq(t2.at(Vector2i(2, 0)).v, 3, "per-cell effect key")
	var bv := BWBoardView.new()
	bv.build(b2, t2)
	t.eq(bv.fx_state(Vector2i(0, 0)).h.tier, 2, "board view shows authored charge at build")
	t.near(bv.fx_tier(Vector2i(0, 0), "h"), 2.0, 0.001, "build snaps (no grow-in on screen open)")
	bv.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

extends RefCounted
## D423 (the author, 2026-10-08): "The rings that thunder explosions create are
## currently always purple. Change that based on the non-thunder components of
## the reaction." A detonation records what it consumed (BWTiles.blast_mix);
## the view colours the ring by it (BWTileFX.blast_colors). Renders:
## tools/sys5_ring_shots.gd -> design/art/sys5_ring_*.png.

const C := Vector2i(4, 4)


func _board(n: int = 9) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[8, 0], [8, 1], [8, 2]] } })


func _u(id: String, wc: String, el: String) -> BWUnit:
	return BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 6, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })


func test_blast_mix_records_what_blew(t) -> void:
	var tl := BWTiles.new(_board())
	tl.author(C, 2, -3)
	var r := tl.apply([C], "thunder", "a", 1)
	t.eq(r.detonations.size(), 1, "thunder on fire 2 + dark 3 detonates")
	t.eq(r.detonations[0].mix, { "fire": 2, "dark": 3 }, "the mix: fire 2, dark 3")
	tl.author(C, 0, 2)
	tl.entries[C].glaze = 2
	var r2 := tl.apply([C], "thunder", "a", 1)
	t.eq(r2.detonations[0].mix, { "light": 2, "ice": 1 }, "glazed light: light 2 + ice 1")
	tl.author(C, 0, 0, "fuse")
	var r3 := tl.apply([C], "wind", "a", 1)
	t.eq(r3.detonations.size(), 1, "wind sets off a lone fuse (D405)")
	t.eq(r3.detonations[0].mix, {}, "a pure fuse pop consumes nothing else")


func test_blast_colors_weights(t) -> void:
	var c := BWTileFX.blast_colors({ "fire": 2, "dark": 3 })
	t.eq(c.size(), 2, "two colours")
	t.eq(str(c[0][0]), "dark", "dark 3 is the base")
	t.ok(absf(float(c[0][1]) - 0.6) < 0.001 and absf(float(c[1][1]) - 0.4) < 0.001, "weights 0.6 / 0.4 by steps")
	t.eq(BWTileFX.blast_colors({}), [["thunder", 1.0]], "nothing else: thunder purple")
	t.eq(BWTileFX.blast_colors({ "thunder": 2 }), [["thunder", 1.0]], "thunder never counts")
	t.eq(str(BWTileFX.blast_colors({ "fire": 3 })[0][0]), "fire", "fire only: fire")


func test_detonate_event_carries_mix(t) -> void:
	var me := _u("me", "staff", "thunder")
	var foe := _u("foe", "sword", "fire")
	var b := BWBattle.new(_board(), 7)
	b.setup([me], [foe])
	me.pos = Vector2i(0, 4)
	foe.pos = Vector2i(8, 8)
	b.tiles.author(C, 3, 0)
	b.paint([C], "thunder", me)
	var dets: Array = b.history.filter(func(e): return e.type == "detonate")
	t.eq(dets.size(), 1, "one detonation event")
	t.eq(dets[0].get("mix", null), { "fire": 3 }, "the event carries the mix")

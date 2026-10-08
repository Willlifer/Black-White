extends SceneTree
## D423 review renders: a thunder detonation's blast ring coloured by what it
## consumed (BWTiles.blast_mix -> BWTileFX.blast_colors / tint_blast). Each
## case authors a tile, lands thunder on it through the real BWTiles.apply,
## and bursts with the detonation's own mix. Three moments of the ring per
## case side by side, then a contact sheet of every case.
##
##   godot --path game --resolution 1600x900 --fixed-fps 20 --script res://tools/sys5_ring_shots.gd
##
## -> design/art/sys5_ring_fire.png, sys5_ring_fire_dark.png,
##    sys5_ring_light_ice.png, sys5_ring_thunder.png, sys5_ring_sheet.png

const ART := "res://../design/art/"
## [file tag, caption, h, v, glaze]
const CASES := [
	["fire", "fire 3", 3, 0, 0],
	["fire_dark", "2 fire + 3 dark", 2, -3, 0],
	["light_ice", "light 2 + ice (glazed)", 0, 2, 2],
	["thunder", "pure fuse pop (thunder only)", 0, 0, 0],
]
## Frames after the burst (20 fps) to capture: ages ~0.13, ~0.33, ~0.6.
const AT := [2, 5, 9]
const CROP := Rect2i(450, 170, 700, 520)

var _cam: Camera3D
var _bv: BWBoardView


func _init() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	var rows: Array = []
	for cs in CASES:
		var strip := await _case(cs)
		strip.save_png(ART + "sys5_ring_%s.png" % cs[0])
		print("saved ", ProjectSettings.globalize_path(ART + "sys5_ring_%s.png" % cs[0]))
		rows.append(strip)
	var w: int = rows[0].get_width()
	var h: int = rows[0].get_height()
	var sheet := Image.create(w, h * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(0, 0, w, h), Vector2i(0, h * i))
	sheet.save_png(ART + "sys5_ring_sheet.png")
	print("saved ", ProjectSettings.globalize_path(ART + "sys5_ring_sheet.png"))
	quit()


func _case(cs: Array) -> Image:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	root.add_child(we)
	var cells: Array = []
	for r in 7:
		for q in 7:
			cells.append({ "q": q, "r": r, "terrain": "neutral", "elevation": 0 })
	var board := BWBoard.from_dict({ "name": "fx", "cols": 7, "rows": 7, "cells": cells })
	_bv = BWBoardView.new()
	root.add_child(_bv)
	_bv.build(board, BWTiles.new(board))
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var cap := Label.new()
	cap.add_theme_font_size_override("font_size", 30)
	cap.add_theme_color_override("font_color", Color.WHITE)
	cap.add_theme_color_override("font_outline_color", Color.BLACK)
	cap.add_theme_constant_override("outline_size", 8)
	cap.position = Vector2(CROP.position.x + 16, CROP.position.y + 10)
	ui.add_child(cap)
	var c := Vector2i(3, 3)
	var at := _bv.top_center(c)
	var p := deg_to_rad(52.0)
	_cam.fov = 34.0
	_cam.position = at + Vector3(0, sin(p), cos(p)) * 9.0
	_cam.look_at(at, Vector3.UP)
	# the tile before
	if int(cs[2]) != 0 or int(cs[3]) != 0:
		_bv.tiles.author(c, int(cs[2]), int(cs[3]))
		_bv.tiles.entries[c].glaze = int(cs[4])
		_bv.refresh_tiles(true)
	await _frames(12)
	# thunder lands: the real rules give the detonation and its mix
	var mix := {}
	if int(cs[2]) == 0 and int(cs[3]) == 0:
		_bv.tiles.author(c, 0, 0, "fuse")          # a lone fuse set off by wind (D405): nothing but thunder
		var r0 := _bv.tiles.apply([c], "wind", "x", 1)
		mix = r0.detonations[0].mix if not r0.detonations.is_empty() else {}
	else:
		var r := _bv.tiles.apply([c], "thunder", "x", 1)
		mix = r.detonations[0].mix if not r.detonations.is_empty() else {}
	cap.text = "%s   mix %s" % [cs[1], JSON.stringify(mix)]
	_bv.refresh_tiles(true)
	_bv.on_tile_event({ "type": "detonate", "hex": c, "pct": 10.0, "radius": 1, "mix": mix })
	var shots: Array = []
	var f := 0
	for want in AT:
		while f < int(want):
			await process_frame
			f += 1
		await RenderingServer.frame_post_draw
		shots.append(root.get_viewport().get_texture().get_image().get_region(CROP))
	var out := Image.create(CROP.size.x * shots.size(), CROP.size.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGBA8)
		out.blit_rect(im, Rect2i(Vector2i.ZERO, CROP.size), Vector2i(CROP.size.x * i, 0))
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame

extends SceneTree
## Tile FX review renders and the frame-time measurement (Phase 5, D82).
## Real renderer, windowed; run with a fixed step so shader TIME and the tier
## animation advance by exactly one frame per capture:
##
##   godot --path game --fixed-fps 20 -s res://tools/tilefx_review.gd -- <mode> [out]
##
## modes
##   grid    design/art/tilefx_grid_combat.png (combat camera: 24 u, FOV 34,
##           pitch 42), tilefx_grid_axes.png and tilefx_grid_ops.png (close)
##   gif     PNG frames per element into <out>/<element>/ (tiers 1 -> 3, and
##           the operators' marker + event); tools/tilefx_gif.py makes GIFs
##   combat  design/art/tilefx_combat.png: a real fight, a thunder line
##           detonating three charged tiles in one action
##   perf    14x14 board, every tile charged, combat camera: frame times with
##           the FX on vs. a clean board (run WITHOUT --fixed-fps, vsync off)

const ART := "res://../design/art/"
const AXES := ["fire", "water", "light", "dark"]

var _cam: Camera3D
var _bv: BWBoardView
var _labels: Array = []
var _ui: CanvasLayer


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "grid"
	var out := args[1] if args.size() > 1 else ""
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	match mode:
		"grid": await _grid()
		"gif": await _gifs(out)
		"combat": await _combat()
		"perf": await _perf()
	quit()


# ---------------------------------------------------------------- scene

func _stage(cols: int, rows: int) -> BWBoardView:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	root.add_child(we)
	var cells: Array = []
	for r in rows:
		for c in cols:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	var board := BWBoard.from_dict({ "name": "fx", "cols": cols, "rows": rows, "cells": cells })
	_bv = BWBoardView.new()
	root.add_child(_bv)
	_bv.build(board, BWTiles.new(board))
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	_ui = CanvasLayer.new()
	root.add_child(_ui)
	_labels.clear()
	return _bv


func _look(at: Vector3, dist: float, fov: float = 34.0, pitch_deg: float = 42.0, yaw_deg: float = 0.0) -> void:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	_cam.fov = fov
	_cam.position = at + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	_cam.look_at(at, Vector3.UP)


func _label(text: String, world: Vector3, size: int = 18) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_ui.add_child(l)
	_labels.append([l, world])


func _place_labels() -> void:
	for pair in _labels:
		var l: Label = pair[0]
		var p := _cam.unproject_position(pair[1])
		l.position = p - Vector2(l.get_minimum_size().x * 0.5, 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(path: String) -> void:
	_place_labels()
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- grid

## Column specs: [label, [entry per tier row]] ; an entry is [h, v, marker, glaze]
func _grid_cols() -> Array:
	return [
		["Fire", [[1, 0, "", 0], [2, 0, "", 0], [3, 0, "", 0]]],
		["Water", [[-1, 0, "", 0], [-2, 0, "", 0], [-3, 0, "", 0]]],
		["Light", [[0, 1, "", 0], [0, 2, "", 0], [0, 3, "", 0]]],
		["Dark", [[0, -1, "", 0], [0, -2, "", 0], [0, -3, "", 0]]],
		["Markers", [[0, 0, "fuse", 0], [0, 0, "gale", 0], [0, 0, "stasis", 0]]],
		["Glaze", [[2, 0, "", 2], [-3, 0, "", 2], [0, -2, "", 1]]],
		["Mixed", [[3, -1, "", 0], [1, -3, "", 0], [-2, 2, "", 0]]],
	]


const ROW_NOTE := {
	"Markers": ["fuse", "gale", "stasis"],
	"Glaze": ["fire 2", "water 3", "dark 2 cracking"],
	"Mixed": ["fire 3 + dark 1", "dark 3 + fire 1", "water 2 + light 2"],
}


func _fill(cols: Array, first_col: int = 0, count: int = 99) -> Array:
	var placed: Array = []
	var ci := 0
	for k in range(first_col, mini(cols.size(), first_col + count)):
		var col: Array = cols[k]
		for row in 3:
			var hex := Vector2i(1 + ci * 2, 1 + row * 2)
			var spec: Array = col[1][row]
			if spec[2] != "":
				_bv.tiles.author(hex, 0, 0, spec[2])
			else:
				_bv.tiles.author(hex, spec[0], spec[1])
				_bv.tiles.entries[hex].glaze = spec[3]
			var note := "T%d" % (row + 1)
			if ROW_NOTE.has(col[0]):
				note = ROW_NOTE[col[0]][row]
			_label(note, _bv.top_center(hex) + Vector3(0, 0, 0.95), 15)
			placed.append(hex)
		_label(col[0], _bv.top_center(Vector2i(1 + ci * 2, 0)) + Vector3(0, 0.1, -0.9), 22)
		ci += 1
	_bv.refresh_tiles(true)
	return placed


func _grid() -> void:
	var cols := _grid_cols()
	await _stage(15, 7)
	_fill(cols)
	_look(_bv.top_center(Vector2i(7, 3)), 24.0)
	await _frames(30)
	await _shot(ART + "tilefx_grid_combat.png")

	await _stage(9, 7)
	_fill(cols, 0, 4)
	_look(_bv.top_center(Vector2i(4, 3)) + Vector3(0.5, 0, 0), 13.0)
	await _frames(30)
	await _shot(ART + "tilefx_grid_axes.png")

	await _stage(7, 7)
	_fill(cols, 4, 3)
	_look(_bv.top_center(Vector2i(3, 3)) + Vector3(0.5, 0, 0), 11.0)
	await _frames(30)
	await _shot(ART + "tilefx_grid_ops.png")


# ---------------------------------------------------------------- gifs

func _gifs(out: String) -> void:
	if out == "":
		out = OS.get_user_data_dir().path_join("tilefx_frames")
	for el in AXES + ["thunder", "wind", "ice"]:
		var dir := out.path_join(el)
		DirAccess.make_dir_recursive_absolute(dir)
		await _stage(5, 5)
		var c := Vector2i(2, 2)
		_look(_bv.top_center(c) + Vector3(0, 0.35, 0), 7.5, 34.0, 38.0, 20.0)
		var cap := Label.new()
		cap.add_theme_font_size_override("font_size", 30)
		cap.add_theme_color_override("font_color", Color.WHITE)
		cap.add_theme_color_override("font_outline_color", Color.BLACK)
		cap.add_theme_constant_override("outline_size", 8)
		cap.position = Vector2(560, 40)
		_ui.add_child(cap)
		var steps: Array = _gif_script(el)
		var f := 0
		await _frames(4)
		for st in steps:
			cap.text = st[0]
			call(st[1], c, st[2])
			for i in int(st[3]):
				await RenderingServer.frame_post_draw
				var img := root.get_viewport().get_texture().get_image()
				img = img.get_region(Rect2i(400, 90, 800, 650))
				img.resize(560, 455, Image.INTERPOLATE_LANCZOS)
				img.save_png(dir.path_join("f%04d.png" % f))
				f += 1
				await process_frame
		print("frames ", el, " ", f)


## [caption, step method, argument, frames at 20 fps]
func _gif_script(el: String) -> Array:
	var name: String = el.capitalize()
	match el:
		"thunder":
			return [["Fuse marker", "_st_mark", "fuse", 40], ["Fire lands: detonation", "_st_detonate", 0, 30]]
		"wind":
			return [["Gale marker", "_st_mark", "gale", 40], ["Fire lands: gale fires", "_st_gale", 0, 36]]
		"ice":
			return [["Stasis marker", "_st_mark", "stasis", 34], ["Ice on fire 2: glaze forms", "_st_glaze", 2, 34],
				["Last cycle: cracks", "_st_glaze", 1, 26]]
	var sgn := 1 if el in ["fire", "light"] else -1
	var on_h := el in ["fire", "water"]
	return [
		["%s 1" % name, "_st_axis", Vector3i(sgn, int(on_h), 1), 34],
		["%s 2" % name, "_st_axis", Vector3i(sgn, int(on_h), 2), 34],
		["%s 3" % name, "_st_axis", Vector3i(sgn, int(on_h), 3), 40],
	]


func _st_axis(c: Vector2i, a: Vector3i) -> void:
	if a.y == 1:
		_bv.tiles.author(c, a.x * a.z, 0)
	else:
		_bv.tiles.author(c, 0, a.x * a.z)
	_bv.refresh_tiles()


func _st_mark(c: Vector2i, mk: String) -> void:
	_bv.tiles.author(c, 0, 0, mk)
	_bv.refresh_tiles()


func _st_detonate(c: Vector2i, _a: int) -> void:
	_bv.tiles.clear(c)
	_bv.refresh_tiles(true)
	_bv.burst("detonate", c)


func _st_gale(c: Vector2i, _a: int) -> void:
	_bv.tiles.clear(c)
	var r := _bv.tiles.apply([c], "fire", "x", 2)
	r.changed.append_array(_gale_spread(_bv.tiles, c))
	_bv.on_tile_event({ "type": "paint", "element": "fire", "hexes": r.changed })


func _st_glaze(c: Vector2i, g: int) -> void:
	if g == 2:
		_bv.tiles.author(c, 2, 0)
		_bv.refresh_tiles(true)
	_bv.tiles.entries[c].glaze = g
	_bv.refresh_tiles()


## The gale copies of a fire charge at c (what BWTiles does when a fresh
## charge lands on a gale marker), so the GIF shows the neighbours catching.
func _gale_spread(tl: BWTiles, c: Vector2i) -> Array:
	var out: Array = []
	for n in tl.board.neighbors(c):
		tl.author(n, 2, 0)
		tl.entries[n].permanent = false
		out.append(n)
	_bv._last_entries[c] = { "h": 0, "v": 0, "marker": "gale", "glaze": 0, "timer": 3 }
	return out


# ---------------------------------------------------------------- combat

func _combat() -> void:
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	for id in ["will", "aureli", "jericho"]:
		p.append(BWRosterKits.unit(id))
	for i in 3:
		e.append(BWUnit.from_roster(roster[i + 10]))
	var s := BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	await _frames(60)
	s._busy = true                     # hold the AI; this is a staged frame
	var tl := s.battle.tiles
	var u: BWUnit = s.battle.units[0]
	var foe: BWUnit = s.battle.units[3]
	# a field laid over the last few turns: fire / water / dark / light, a fuse
	var line: Array = []
	var cur := foe.pos
	for k in 3:
		cur = s.board_view.board.neighbors(cur)[0] if k > 0 else cur
		line.append(cur)
	var around: Array = BWHex.area(foe.pos, 3)
	var kinds := [[2, 0], [-3, 0], [0, -2], [1, -1], [0, 2], [3, 0], [-1, 0], [0, -3], [2, 1]]
	var k := 0
	for h in around:
		if h in line or not tl.can_hold(h) or (k % 3) == 2:
			k += 1
			continue
		var kv: Array = kinds[k % kinds.size()]
		tl.author(h, kv[0], kv[1])
		k += 1
	tl.author(line[0], 2, -1)
	tl.author(line[1], -3, 0)
	tl.author(line[2], 3, 0)
	s.board_view.refresh_tiles(true)
	s.rig.follow(BWLook.world(foe.pos, s.board_view.board.elevation(foe.pos)), true)
	await _frames(40)
	s._queue.clear()
	s.battle.paint(line, "thunder", u)
	for ev in s._queue:
		if ev.type in ["paint", "detonate"]:
			s.board_view.on_tile_event(ev)
	s._queue.clear()
	await _frames(5)
	_cam = s.cam
	await _shot(ART + "tilefx_combat.png")
	await _frames(25)
	await _shot(ART + "tilefx_combat_after.png")
	# the attack cutscene's dim: everything but the target's tile fades
	var keep: Array = s.board_view.hex_parts(line[1])
	for c in s.board_view.get_children():
		if not c in keep:
			BWLook.set_dim(c, 0.9)
	await _frames(3)
	await _shot(ART + "tilefx_combat_dim.png")


# ---------------------------------------------------------------- perf

func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _stage(14, 14)
	var c := _bv.top_center(Vector2i(7, 7))
	_look(c, 24.0)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var clean := await _measure("clean board")
	var kinds := [[3, -1], [-3, 0], [0, 3], [0, -3], [2, 2], [-2, -2], [3, 0], [1, 3]]
	var i := 0
	for h in _bv.board.cells():
		var kv: Array = kinds[i % kinds.size()]
		_bv.tiles.author(h, kv[0], kv[1])
		if i % 11 == 5:
			_bv.tiles.entries[h].glaze = 1
		i += 1
	_bv.refresh_tiles(true)
	var full := await _measure("196 tiles charged (tier 2-3, mixed, glazed)")
	# worst case: the transition frame, every layer animating at once
	for h in _bv.board.cells():
		_bv.tiles.entries[h].h = -_bv.tiles.entries[h].h
	_bv.refresh_tiles()
	var t0 := Time.get_ticks_usec()
	for k in 12:
		await process_frame
	var trans_ms := (Time.get_ticks_usec() - t0) / 12000.0
	var nodes := 0
	for n in _bv.get_children():
		if n is MeshInstance3D and n.visible:
			nodes += 1
	print("PERF visible meshes on the full board: %d" % nodes)
	print("PERF transition frames (all 196 tiles swapping element): %.2f ms/frame" % trans_ms)
	print("PERF summary: clean %.2f ms (gpu %.2f), full %.2f ms (gpu %.2f)" % [clean.x, clean.y, full.x, full.y])


func _measure(what: String) -> Vector2:
	await _frames(60)
	var vp := root.get_viewport_rid()
	var n := 300
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t0
	for k in n:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("PERF %s: %.2f ms/frame avg (%.0f fps), worst %.2f ms, GPU %.2f ms" % [what, ms, 1000.0 / ms, worst, gpu / n])
	return Vector2(ms, gpu / n)

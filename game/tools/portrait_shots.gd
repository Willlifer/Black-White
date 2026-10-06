extends SceneTree
## D156 review: BWPortraits on the real roster, plus the Giant, the two
## stones, a rank-up and a helmet, as BWWidgets.Portrait at the game's sizes.
## Needs a window (not --headless):
##
##   godot --path . -s res://tools/portrait_shots.gd [-- --out <dir>] [--cold] [--res 1920x1080]
##
## --cold empties user://portraits/v<N>/ first, so the printed timings are
## first renders (build = assembling the dressed character, total = build +
## the two GPU frames). Writes portraits_sheet.png (the widget at 104/78/58/42/34
## px) and portraits_raw.png (the 256 px renders, unframed).

var out_dir := ""
var _ui: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	i = args.find("--res")                        # e.g. --res 1920x1080: a windowed frame of that size
	if i >= 0 and i + 1 < args.size():
		var wh := args[i + 1].split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	if "--cold" in args:
		var d := ProjectSettings.globalize_path(BWPortraits.DIR)
		for f in (DirAccess.get_files_at(d) if DirAccess.dir_exists_absolute(d) else PackedStringArray()):
			DirAccess.remove_absolute(d.path_join(f))
	_run.call_deferred()


func _units() -> Array:
	var out: Array = []
	for row in BWData.table("roster"):
		out.append(BWUnit.from_roster(row))
	var run := BWRun.new()
	out.append(run.make_boss())
	out.append(BWObelisk.create("lantern", Vector2i.ZERO))
	out.append(BWObelisk.create("well", Vector2i.ZERO))
	# a rank-up: the first unit with a second element at rank 1 and its own at 3
	var r: BWUnit = BWUnit.from_roster(BWData.table("roster")[0])
	r.id += "_ranked"
	r.affinity = { r.element: 30, ("water" if r.element != "water" else "fire"): 10 }
	r.name += " (ranked)"
	out.append(r)
	# headgear: two helmets on two roster units
	var enchant_of := {}
	for e in BWData.table("enchantments"):
		if str(e.get("element", "")) != "" and not enchant_of.has(str(e.element)):
			enchant_of[str(e.element)] = str(e.id)
	for pair in [[1, "feathered_full_helm"], [2, "wizard_hat"], [3, "crown"]]:
		var h: BWUnit = BWUnit.from_roster(BWData.table("roster")[pair[0]])
		h.id += "_" + pair[1]
		h.name += " + " + str(pair[1]).replace("_", " ")
		h.equipment["head"] = { "base": pair[1], "slot": "head", "enchant": enchant_of.get(h.element, "") }
		out.append(h)
	return out


func _run() -> void:
	var units := _units()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	BWPortraits.ensure(bg)
	await process_frame
	var t0 := Time.get_ticks_msec()
	BWPortraits.prewarm(units)
	while BWPortraits.pending() > 0:
		await process_frame
	var wall := Time.get_ticks_msec() - t0
	var builds: Array = []
	var totals: Array = []
	for t in BWPortraits.timings:
		builds.append(t.build)
		totals.append(t.total)
		print("  %-60s build %6.1f ms  total %6.1f ms" % [t.key, t.build, t.total])
	if not builds.is_empty():
		builds.sort()
		totals.sort()
		print("renders %d  wall %d ms  build median %.1f max %.1f  total median %.1f max %.1f" % [builds.size(), wall,
			builds[builds.size() / 2], builds[-1], totals[totals.size() / 2], totals[-1]])
	else:
		print("all %d portraits came from the disk cache (%d ms)" % [units.size(), wall])
	# ---- the sheet: each unit at the HUD sizes
	var scroll := VBoxContainer.new()
	scroll.position = Vector2(16, 12)
	scroll.add_theme_constant_override("separation", 10)
	bg.add_child(scroll)
	var sizes := [104.0, 78.0, 58.0, 42.0, 34.0]
	var per_row := 6
	var row: HBoxContainer
	for k in units.size():
		if k % per_row == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 22)
			scroll.add_child(row)
		var u: BWUnit = units[k]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		row.add_child(cell)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 4)
		cell.add_child(strip)
		for s in sizes:
			var p := BWWidgets.Portrait.new(u, s)
			p.size_flags_vertical = Control.SIZE_SHRINK_END
			p.selected = s == 58.0
			strip.add_child(p)
		var l := Label.new()
		l.text = "%s · %s" % [u.name, u.element]
		l.add_theme_font_size_override("font_size", 12)
		cell.add_child(l)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("portraits_sheet.png"))
	# ---- raw renders, unframed, 128 px each on mid grey (alpha check)
	bg.remove_child(scroll)
	scroll.queue_free()
	var grid := GridContainer.new()
	grid.columns = 12
	grid.position = Vector2(16, 16)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	bg.add_child(grid)
	for u in units:
		var cr := ColorRect.new()
		cr.color = Color(0.35, 0.35, 0.37)
		cr.custom_minimum_size = Vector2(148, 148)
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture = BWPortraits.cached(BWPortraits.key_for(u))
		tr.position = Vector2(10, 10)
		tr.size = Vector2(128, 128)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		cr.add_child(tr)
		grid.add_child(cr)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("portraits_raw.png"))
	quit(0)

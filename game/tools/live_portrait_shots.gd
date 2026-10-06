extends SceneTree
## D156 review: the two live portrait feeds (BWWidgets.LivePortrait) on a
## real attacker and defender while the defender plays its hit reactions.
## Needs a window:
##
##   godot --path . -s res://tools/live_portrait_shots.gd [-- --out <dir>]
##
## Writes portraits_live_hit.png: a strip of frames, each the scene with the
## two 104 px cards (attacker left, defender right), through a strike and
## the defender's stricken_knockback / hit / kneel.

var out_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	we.environment = BWLook.starfield_environment()
	world.add_child(we)
	var rows: Array = BWData.table("roster")
	var att := BWUnit.from_roster(rows[6])
	var dfn := BWUnit.from_roster(rows[2])
	dfn.team = "enemy"
	var av := BWUnitView.new()
	world.add_child(av)
	av.setup(att)
	av.position = Vector3(-0.9, 0, 0)
	var dv := BWUnitView.new()
	world.add_child(dv)
	dv.setup(dfn)
	dv.position = Vector3(0.9, 0, 0)
	av.face(dv.global_position)
	dv.face(av.global_position)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 2.6, 6.0)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.current = true
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var row := HBoxContainer.new()
	row.position = Vector2(24, 24)
	row.add_theme_constant_override("separation", 16)
	ui.add_child(row)
	var pa := BWWidgets.LivePortrait.new(att, 104.0)
	var pd := BWWidgets.LivePortrait.new(dfn, 104.0)
	row.add_child(pa)
	row.add_child(pd)
	var frames: Array[Image] = []
	for f in 20:
		await process_frame
	var beats := [["strike", "idle"], ["strike", "stricken_knockback"], ["idle", "hit"], ["idle", "kneel"]]
	for b in beats:
		av.pose_named(b[0])
		dv.pose_named(b[1])
		for k in 3:
			for f in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			frames.append(root.get_viewport().get_texture().get_image())
	print("live feeds: %d  (attacker live %s, defender live %s)" % [BWWidgets.LivePortrait.live, pa.is_live(), pd.is_live()])
	frames[4].save_png(out_dir.path_join("portraits_live_hit_frame.png"))
	# strip: the two cards of each frame, 3 per beat, one beat per row
	var fw := frames[0].get_width()
	var fh := frames[0].get_height()
	var cell := Vector2i(int(fw * 0.17), int(fh * 0.17))
	var sheet := Image.create(cell.x * 3, cell.y * beats.size(), false, Image.FORMAT_RGBA8)
	for k in frames.size():
		var im := frames[k]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, cell), Vector2i((k % 3) * cell.x, (k / 3) * cell.y))
	sheet.save_png(out_dir.path_join("portraits_live_hit.png"))
	quit(0)

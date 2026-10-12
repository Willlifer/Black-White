extends SceneTree
## D560/D561 review renders to design/art/settled_*.png:
##   settled_hall.png        the downtime hall: a 3-element unit offered both
##                           Specialize and Branch out, each a "Specialize in
##                           X, Y" pairing card
##   settled_hall_taken.png  the same after taking the Branch out tile's card
##   settled_duo.png         a duo pick (its own pick, gold-ruled)
##   [SHOTS=<dir>] godot --path . --script res://tools/settled_shots.gd
## Needs a window (real renders, not headless).

var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _go() -> void:
	BWMusic.ensure(root)
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 1234)
	for u in run.squad:
		var others: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
		u.affinity[str(others[0])] = 10
		u.affinity[str(others[2])] = 10
		u.expertise[str(BWRun.weapon_classes().filter(func(c): return c != u.weapon_class)[1])] = 10
		BWPicks.auto_resolve(u)
	run.fight = 5
	run.day = 5
	for dd in range(5, 40):                  # a day where someone is offered both tiles
		run.day = dd
		if run.squad.any(func(x): return "branch_out" in run.day_choices(x) and "specialize" in run.day_choices(x)):
			break
	var d := BWDowntimeScreen.new()
	d.run = run
	root.add_child(d)
	await _wait(1.4)
	var bi := 0
	for i in run.squad.size():
		var ch := run.day_choices(run.squad[i])
		if "branch_out" in ch and "specialize" in ch:
			bi = i
			break
	d._select(bi)
	await _wait(1.4)
	var su: BWUnit = run.squad[bi]
	print("hall: %s offered %s, pairings %s" % [su.name, run.day_choices(su), run.specialize_preview(su)])
	await _shot("settled_hall")
	d._choose("branch_out", 0)
	await _wait(0.6)
	await _shot("settled_hall_taken")
	d.queue_free()
	await _wait(0.3)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# ---- a duo pick: fire 4 + wind 4
	var p: BWUnit = run.squad[0]
	p.affinity["fire"] = 50
	p.affinity["wind"] = 50
	p.perks = ["fire_rush", "fire_skin", "fire_kindling", "wind_tail", "wind_eye", "wind_force", "wind_cross"]
	p.keystones = ["lava_walker"]
	var owed := BWDuo.owed(p)
	print("duo owed: ", owed)
	if not owed.is_empty():
		var pk := BWPicker.new(p, owed[0], "day 5")
		root.add_child(pk)
		await _wait(0.8)
		await _shot("settled_duo")
	quit(0)

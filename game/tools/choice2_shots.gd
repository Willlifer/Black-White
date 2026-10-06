extends SceneTree
## D174-D176 review renders ("fewer, better choices") to design/art/choice2_*.png:
##   choice2_hall.png    the downtime hall: a unit offered Branch out, its two
##                       tiles, the Branch out tile showing its two cards
##   choice2_hall_taken.png  the same after taking a card (the chip names it)
##   choice2_perks.png   a perk pick: two random perks of the element
##   choice2_skills.png  a skill pick: two random improve / learn options
##   [SHOTS=<dir>] godot --path . --script res://tools/choice2_shots.gd
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
		BWPicks.auto_resolve(u)
	run.fight = 3
	run.day = 3
	# ---- the hall: select a unit that is offered Branch out
	var d := BWDowntimeScreen.new()
	d.run = run
	root.add_child(d)
	await _wait(1.4)
	var bi := 0
	for i in run.squad.size():
		if "branch_out" in run.day_choices(run.squad[i]) and run.branch_preview(run.squad[i]).size() == 2:
			bi = i
			break
	for k in run.squad.size():
		if k != bi:
			var u: BWUnit = run.squad[k]
			var c: String = run.day_choices(u)[0]
			d._plans[u.id] = c
			if c == "branch_out":
				d._branch[u.id] = 0
	d._refresh_go()
	d._select(bi)
	await _wait(1.4)
	print("hall: %s offered %s, cards %s" % [run.squad[bi].name, run.day_choices(run.squad[bi]), run.branch_preview(run.squad[bi])])
	await _shot("choice2_hall")
	d._choose("branch_out", 1)
	await _wait(0.6)
	await _shot("choice2_hall_taken")
	d.queue_free()
	await _wait(0.3)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# ---- a perk pick: rank 2 in its element, two of the four it lacks
	var p: BWUnit = run.squad[2]
	p.affinity[p.element] = 20
	var preq := BWPicks.next_request(p)
	var pk := BWPicker.new(p, preq, "day 3")
	root.add_child(pk)
	await _wait(0.6)
	print("perks offered: %s" % [BWPicks.offered(p, preq)])
	await _shot("choice2_perks")
	pk.queue_free()
	await _wait(0.2)
	# ---- a skill pick: an expertise letter
	var v: BWUnit = run.squad[4]
	v.expertise[v.weapon_class] = 10
	var sreq := BWPicks.next_request(v)
	var sk := BWPicker.new(v, sreq, "day 3")
	root.add_child(sk)
	await _wait(0.6)
	print("skills offered: %s" % [BWPicks.offered(v, sreq)])
	await _shot("choice2_skills")
	quit()

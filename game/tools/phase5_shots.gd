extends SceneTree
## Phase 5 review renders (D83): the downtime hall and the title.
##   SHOTS=<dir> MODE=hall|progress|title [GIF=<frames dir>] godot --path . --script res://tools/phase5_shots.gd
## hall      phase5_hall_select.png (one unit chosen, a picker open),
##           phase5_hall_set.png (all six set, the arrow live)
## progress  phase5_hall_day_1..3.png (the day scene), and every 0.1 s a
##           frame into GIF (if set) for tools' GIF assembly
## prep      phase5_prep_hall.png (the six, before fight 1), phase5_prep_gear.png
##           (a unit's panel open, a loose piece picked: "Equip on")
## title     phase5_title_fadein.png (1.1 s), phase5_title_full.png (5 s)
## Needs a window (real renders, not headless). Renders at 1920x1080.
var out := ""
var gif := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	gif = OS.get_environment("GIF")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> BWRun:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var e := run.enemies_for(1)
	for x in e:
		x.hp = 0
	run.after_fight(true, run.squad.slice(0, 3), e, e, [])
	return run


func _go() -> void:
	BWMusic.ensure(root)
	var mode := OS.get_environment("MODE")
	if mode == "title":
		var t := BWTitleScreen.new()
		t.has_save = true
		root.add_child(t)
		await _wait(1.1)
		await _shot("phase5_title_fadein")
		await _wait(3.9)
		await _shot("phase5_title_full")
		quit()
		return
	if mode == "prep":
		var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
		var pr := BWRun.start(ids, 7)
		var ps := BWPrepScreen.new()
		ps.run = pr
		root.add_child(ps)
		await _wait(1.8)
		await _shot("phase5_prep_hall")
		ps._select(2)
		await _wait(1.4)
		for t in ps._panel._grid.get_children():
			if t is BWItemTile:
				ps._panel._pick_tile(t)
				break
		await _wait(0.6)
		await _shot("phase5_prep_gear")
		quit()
		return
	var run := _run()
	var d := BWDowntimeScreen.new()
	d.run = run
	root.add_child(d)
	await _wait(1.6)
	if mode == "progress":
		var k := 0
		for u in run.squad:
			d._plans[u.id] = BWRun.DOWNTIME_CHOICES[k % 3]      # D127: one choice each
			k += 1
		d._refresh_go()
		# slow the clock so every 0.1 s of game time gets its frame saved
		var slow := 0.25 if gif != "" else 1.0
		Engine.time_scale = slow
		d._progress()
		var t0 := Time.get_ticks_msec()
		var marks := [0.9, 2.5, 4.1]
		var mi := 0
		var fi := 0
		while true:
			var t := (Time.get_ticks_msec() - t0) / 1000.0 * slow
			if mi < marks.size() and t >= marks[mi]:
				await _shot("phase5_hall_day_%d" % (mi + 1))
				mi += 1
			if gif != "" and t >= fi * 0.1:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/f_%03d.png" % [gif, fi])
				fi += 1
			if t > 7.2:
				break
			await process_frame
		Engine.time_scale = 1.0
		await _shot("phase5_hall_day_end")
		quit()
		return
	# hall: one unit chosen and its choice made, then everyone set (D127)
	d._select(2)
	await _wait(0.4)
	d._choose("branch_out")
	await _wait(1.2)
	await _shot("phase5_hall_select")
	var k := 0
	for u in run.squad:
		d._plans[u.id] = BWRun.DOWNTIME_CHOICES[k % 3]
		k += 1
	d._refresh_go()
	d._select(4)
	await _wait(1.5)
	await _shot("phase5_hall_set")
	quit()

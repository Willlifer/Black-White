extends SceneTree
## D127-D132 review renders: the three-choice hall, the per-unit result cards
## (D177 removed the rogue and its shot; see tools/choice2_shots.gd for D174-D176).
##   [SHOTS=<dir>] godot --path . --script res://tools/downtime2_shots.gd
## downtime2_hall.png             the hall: a unit selected, three name-only tiles, its choice made
## downtime2_specialize.png       a Specialize card (found items with icons, or free points)
## downtime2_branch_options.png   a Branch out card offering its two pairings
## downtime2_branch.png           the same card after the pick
## downtime2_wander.png           a Wander card with two or more successes
## downtime2_jackpot.png          the jackpot card (the nine rerolled at 30%, D177)
## Outcomes are found by seed search on a throwaway run, then replayed on the
## shown run with that seed (the run is deterministic). Needs a window.
var out := ""
const RUN_SEED := 1234


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
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", out.path_join(name + ".png"))


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


func _run() -> BWRun:
	var r := BWRun.start(_ids(), RUN_SEED)
	for u in r.squad:
		BWPicks.auto_resolve(u)
	r.fight = 3                      # tier D: finds look like mid-run
	r.day = 3                        # the cards read "day 2"
	return r


## The first seed whose `choice` for squad[i] passes `ok(rep)`.
func _find(i: int, choice: String, ok: Callable, tries: int = 3000) -> int:
	for s in tries:
		var r := _run()
		r.rng.seed = s
		if ok.call(r.downtime(r.squad[i], choice)):
			return s
	return -1


func _go() -> void:
	BWMusic.ensure(root)
	var mode := OS.get_environment("MODE")
	if mode == "" or mode == "hall":
		await _hall()
	if mode == "" or mode == "cards":
		await _cards()
	quit()


func _screen(run: BWRun) -> BWDowntimeScreen:
	var d := BWDowntimeScreen.new()
	d.run = run
	root.add_child(d)
	return d


func _hall() -> void:
	var run := _run()
	var d := _screen(run)
	await _wait(1.4)
	for k in 5:
		d._plans[run.squad[k].id] = BWRun.DOWNTIME_CHOICES[k % 3]
	d._refresh_go()
	d._select(5)
	await _wait(0.5)
	d._choose("wander")
	await _wait(1.4)
	await _shot("downtime2_hall")
	d.queue_free()
	await _wait(0.3)


## One result card on a fresh hall: the outcome replayed with `seed_value`.
func _card(i: int, choice: String, seed_value: int, name: String, branch: bool = false) -> void:
	var run := _run()
	var d := _screen(run)
	await _wait(1.2)
	run.rng.seed = seed_value
	var rep := run.downtime(run.squad[i], choice, not branch)
	d._day = true
	d._plan_ui.visible = false
	d._tag_layer.visible = false
	d.reports = [rep]
	d._show_report(rep, i, 0)
	await _wait(2.2)
	await _shot(name)
	if branch:
		d._option = 0
		await _wait(1.8)
		await _shot("downtime2_branch")
	d.queue_free()
	await _wait(0.3)


func _cards() -> void:
	var s1 := _find(0, "specialize", func(r): return r.items.size() >= 1)
	await _card(0, "specialize", s1, "downtime2_specialize")
	var s2 := _find(1, "branch_out", func(r): return r.options.size() == 2)
	await _card(1, "branch_out", s2, "downtime2_branch_options", true)
	var s3 := _find(2, "wander", func(r): return r.successes.size() >= 2 and r.items.size() >= 1 and not r.jackpot)
	await _card(2, "wander", s3, "downtime2_wander")
	var s4 := _find(3, "wander", func(r): return r.jackpot, 6000)
	print("seeds: specialize %d, branch %d, wander %d, jackpot %d" % [s1, s2, s3, s4])
	if s4 >= 0:
		await _card(3, "wander", s4, "downtime2_jackpot")

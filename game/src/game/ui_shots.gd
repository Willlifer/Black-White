class_name BWUIShots
extends Node
## Renders the review frames for the roster, codex, loading and results
## screens into design/art/ui_*.png (real frames from the live viewport):
## `godot --path game -- --ui-shots [dir]` (windowed). Quits when done.

var out_dir := ""


func _ready() -> void:
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("ui_%s.png" % name)
	img.save_png(path)
	print("captured ", path)


func _run() -> void:
	# ---- roster: 0, 3 and 6 picks
	var r := BWRosterScreen.new()
	add_child(r)
	await _wait(2.5)
	await _shot("roster_0")
	for i in [0, 7, 13]:
		r._toggle(i)
		await _wait(0.25)
	r._select(13)
	await _wait(1.6)
	await _shot("roster_3")
	for i in [3, 10, 18]:
		r._toggle(i)
		await _wait(0.25)
	r._select(18)
	await _wait(1.6)
	await _shot("roster_6")
	# ---- the codex, each tab, over the roster
	r.open_codex()
	for t in BWCodex.TABS:
		r._codex.open(t)
		await _wait(0.5)
		await _shot("codex_" + t)
	r._codex.close()
	r.queue_free()
	await _wait(0.3)

	# ---- loading: first map, mid-crossfade, ready
	var l := BWLoadingScreen.new()
	l.next_map = "arena"
	add_child(l)
	await _wait(2.2)
	await _shot("loading_map")
	await _wait(1.8)
	await _shot("loading_crossfade")
	l._show_ready()
	await _wait(1.6)
	await _shot("loading_ready")
	l.queue_free()
	await _wait(0.3)

	# ---- results, on a sample run (as boot --screen results)
	var ids := BWData.table("roster").slice(0, 6).map(func(row): return str(row.id))
	var run := BWRun.start(ids, 99)
	var e := run.enemies_for(1)
	for x in e:
		x.hp = 0
	var report := run.after_fight(true, run.squad.slice(0, 3), e, e, [])
	var s := BWResultsScreen.new()
	s.run = run
	s.report = report
	add_child(s)
	await _wait(2.0)
	await _shot("results")
	get_tree().quit(0)

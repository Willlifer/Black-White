extends SceneTree
## Frame cost of the roster screen (20 dressed characters), rig vs the
## primitive stand-in. Needs a window for GPU numbers:
##
##   godot --path game --resolution 1600x900 -s res://tools/character_perf.gd
##
## Prints one PERF line per mode: mean/p95 frame ms, process ms, GPU ms,
## CPU render ms, draw calls, objects, primitives. Vsync is turned off so
## frame time is real. Run headless for the CPU-only (process) figures.

const WARMUP := 90
const SAMPLES := 300


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	for rig in [true, false]:
		BWUnitView.use_rig = rig
		var t0 := Time.get_ticks_usec()
		var scr := BWRosterScreen.new()
		root.add_child(scr)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		await _measure("rig" if rig else "primitive", build_ms)
		scr.queue_free()
		for i in 5:
			await process_frame
	BWUnitView.use_rig = true
	quit(0)


func _measure(label: String, build_ms: float) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in WARMUP:
		await process_frame
	var frames: Array[float] = []
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var last := Time.get_ticks_usec()
	for i in SAMPLES:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	# the pose solver on its own: every character's per-frame update
	var chars := root.find_children("*", "BWCharacter", true, false)
	var solve := 0.0
	if not chars.is_empty():
		var s0 := Time.get_ticks_usec()
		for k in 100:
			for c in chars:
				(c as BWCharacter).poser.update(0.016)
		solve = (Time.get_ticks_usec() - s0) / 100.0 / 1000.0
	frames.sort()
	var mean := 0.0
	for f in frames:
		mean += f
	mean /= frames.size()
	var n := float(SAMPLES)
	print("PERF %s: build %.0f ms | frame mean %.2f ms p95 %.2f ms | solver %.3f ms for %d characters | gpu %.2f ms | cpu render %.2f ms | draw calls %d | objects %d | primitives %d" % [
		label, build_ms, mean, frames[int(frames.size() * 0.95)], solve, chars.size(), gpu / n, cpu / n, int(draws / n), int(objs / n), int(prims / n)])

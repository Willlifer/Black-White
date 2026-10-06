extends SceneTree
## D232 (L-6): the first-use hitch of each VFX shader, cold vs pre-warmed.
## Puts each BWShaderWarm.catalog() object on the main screen one at a time
## and times the frame it first draws in (and a quiet frame for reference).
##
##   BW_PREWARM=0 godot --path . --resolution 1600x900 -s res://tools/prewarm_probe.gd   # cold
##   godot --path . --resolution 1600x900 -s res://tools/prewarm_probe.gd                 # warmed first
##
## Prints one line per object and a summary "PREWARM cold|warm: total … ms, worst … ms".
## Run each a couple of times: the driver's own pipeline cache warms between runs.

var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _frame() -> float:
	var t := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - t) / 1000.0


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	cam = Camera3D.new()
	cam.fov = 38
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 16.5, 13), Vector3.ZERO)
	cam.current = true
	for i in 20:
		await _frame()
	var warm := OS.get_environment("BW_PREWARM") != "0"
	var warm_ms := 0.0
	if warm:
		warm_ms = await BWShaderWarm.warm(root)
		for i in 5:
			await _frame()
	var quiet: Array = []
	for i in 10:
		quiet.append(await _frame())
	quiet.sort()
	var base: float = quiet[quiet.size() / 2]
	var total := 0.0
	var worst := 0.0
	var worst_k := ""
	for it in BWShaderWarm.catalog():
		var node: Node3D = it[1]
		world.add_child(node)
		BWShaderWarm._instance_params(world)
		var ms: float = await _frame()
		ms = maxf(ms, await _frame())
		var extra := maxf(0.0, ms - base)
		total += extra
		if extra > worst:
			worst = extra
			worst_k = it[0]
		print("  %-14s first frame %6.1f ms (+%.1f)" % [it[0], ms, extra])
		node.queue_free()
		await _frame()
	print("PREWARM %s: quiet frame %.1f ms, first-use extra total %.1f ms, worst %.1f ms (%s); warm pass %.1f ms" % [
		"warm" if warm else "cold", base, total, worst, worst_k, warm_ms])
	quit(0)

extends SceneTree
## Runs one test suite (or a few methods of it), for iterating:
##   SUITE=test_animation [ONLY=test_markers,test_feet_and_floor] godot --headless --path . --script res://tools/one_suite.gd
## The real gate is still `-- --self-test` (all suites).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suite := OS.get_environment("SUITE")
	var only := OS.get_environment("ONLY").split(",", false)
	var script: GDScript = load("res://tests/%s.gd" % suite)
	var inst: Object = script.new()
	var bad := 0
	for m in inst.get_method_list():
		var n: String = m.name
		if not n.begins_with("test_") or (not only.is_empty() and not n in only):
			continue
		var c := BWSelfTest.BWCheck.new()
		var t0 := Time.get_ticks_msec()
		inst.call(n, c)
		var ok := c.failures.is_empty() and c.count > 0
		bad += 0 if ok else 1
		print("%s %s (%d checks, %d ms)" % ["PASS" if ok else "FAIL", n, c.count, Time.get_ticks_msec() - t0])
		for f in c.failures:
			print("    ", f)
	quit(1 if bad > 0 else 0)

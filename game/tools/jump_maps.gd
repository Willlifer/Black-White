extends SceneTree
## D360 / D373: what the jump opens and closes on each map. Since D371 the
## base jump is 2 (the lance and a HighGrounder bow 4). For both teams' first
## spawn, an unlimited walk with jump 1 (D360's old default), 2 and 4:
##   "jump-1 closed" = hexes jump 2 reaches that jump 1 didn't (D360's perches,
##   open again); "only jump 4" = hexes only the lance / HighGrounder reach.
## The castle maps' perch rule (every wall perch has a melee route of at most
## 2 turns, 8 move, from the berm) lives in tools/castle_maps.py (JUMP = 2).
## And the walk search's cost: a 6-move reach from every hex at jump 1, 2, 4.
##   godot --headless --path . --script res://tools/jump_maps.gd


func _init() -> void:
	var dir := DirAccess.open("res://maps")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var b := BWBoard.load_file("res://maps/" + f)
		if b == null:
			continue
		var line := "%-16s" % f.get_basename()
		for team in ["player", "enemy"]:
			var starts: Array = b.spawns.get(team, [])
			if starts.is_empty():
				starts = b.deploy.get(team, [])
			if starts.is_empty():
				continue
			var r1 := b.reachable(starts[0], 999, {}, {}, { "jump": 1 })
			var r2 := b.reachable(starts[0], 999, {}, {}, { "jump": 2 })
			var r4 := b.reachable(starts[0], 999, {}, {}, { "jump": 4 })
			var opened: Array = r2.keys().filter(func(h): return not r1.has(h))
			var only4: Array = r4.keys().filter(func(h): return not r2.has(h))
			line += "  %s: %d hexes, %d jump-1 closed, %d only jump 4 %s" % [team, r2.size(), opened.size(), only4.size(),
				str(only4.slice(0, 4)) if not only4.is_empty() else ""]
		print(line)
		var t := [0, 0, 0]
		var js := [1, 2, 4]
		for h in b.cells():
			if not b.is_passable(h):
				continue
			for i in 3:
				var a := Time.get_ticks_usec()
				b.reachable(h, 6, {}, {}, { "jump": js[i] })
				t[i] += Time.get_ticks_usec() - a
		var n := maxi(1, b.cells().size())
		print("%-16s  reach(6) mean: jump 1 %.2f ms, jump 2 %.2f ms, jump 4 %.2f ms" % ["", t[0] / 1000.0 / n, t[1] / 1000.0 / n, t[2] / 1000.0 / n])
	quit(0)

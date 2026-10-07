extends SceneTree
## D390 check (LEDGER L-13 "knockback rarely fires early"): plays an autoplay
## fight and logs, for every reaction the screen poses on a melee blow, how
## far its start sits from the attacker's own "hit" marker (the frame the
## blow lands). Every stricken variant has `impact` on f0, so a reaction
## that starts more than a frame before its blow lands is early.
##   godot --path . --script res://tools/react_timing.gd [-- --map arena --secs 90 --seed 3]
var s: BWCombatScreen
var hits: Array = []            # [time, unit id]
var reacts: Array = []          # [time, unit id, reaction]


func _initialize() -> void:
	_go.call_deferred()


func _arg(k: String, d: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(k)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else d


func _now() -> float:
	return Time.get_ticks_usec() / 1e6


func _go() -> void:
	var ids := ["della", "will", "stryker"]
	var foes := ["demeter", "apollyon", "burt"]
	var P := ids.map(func(i): return BWRosterKits.unit(i))
	var E := foes.map(func(i): return BWRosterKits.unit(i))
	s = BWCombatScreen.new()
	s.autoplay = true
	s.configure("res://maps/%s.json" % _arg("--map", "arena"), P, E, [], int(_arg("--seed", "3")))
	root.add_child(s)
	await create_timer(1.0).timeout
	for id in s._views:
		var v: BWUnitView = s._views[id]
		if v.character and v.character.animator:
			v.character.animator.marker.connect(func(_clip: String, m: String):
				if m == "hit" or m.begins_with("hit"):
					hits.append([_now(), id]))
	s.reaction_chosen.connect(func(uid: String, r: String, _info: Dictionary): reacts.append([_now(), uid, r]))
	var secs := float(_arg("--secs", "90"))
	var t0 := _now()
	while _now() - t0 < secs and not s.battle.over:
		await process_frame
	# pair each reaction with the nearest attacker hit marker (another unit,
	# within 0.6 s either side)
	var by := {}
	for r in reacts:
		var best := 99.0
		for h in hits:
			if h[1] == r[1]:
				continue
			var d: float = float(r[0]) - float(h[0])
			if absf(d) < absf(best) and absf(d) < 0.6:
				best = d
		if best == 99.0:
			continue                  # a ranged blow or a cast: no melee hit marker near it
		if not by.has(r[2]):
			by[r[2]] = []
		by[r[2]].append(best)
	var early := 0
	for k in by:
		var arr: Array = by[k]
		arr.sort()
		var n_early := arr.filter(func(x): return x < -0.05).size()
		early += n_early
		print("REACT %-20s n=%3d  min %+.3f  median %+.3f  max %+.3f  early(<-50ms) %d" % [k, arr.size(), arr[0], arr[arr.size() / 2], arr[-1], n_early])
	print("REACT total early: %d of %d paired (%d reactions, %d hit markers)" % [early, by.values().reduce(func(a, b): return a + b.size(), 0), reacts.size(), hits.size()])
	quit()

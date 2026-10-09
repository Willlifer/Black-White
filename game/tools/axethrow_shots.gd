extends SceneTree
## D531 review frames: Axe Throw played by the real combat screen (until the
## "throw_under" clip lands: the class strike, and the axe itself flies).
##   [SHOTS=<dir>] [CRIT=1] godot --path . --resolution 1600x900 --script res://tools/axethrow_shots.gd
## -> <dir>/axethrow_NN.png, a frame every 0.12 s from the skill event on.
var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _go() -> void:
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	for row in roster:
		if p.is_empty() and str(row.weapon_class) == "axe":
			p.append(BWUnit.from_roster(row))
	for row in roster:
		if e.size() < 3 and str(row.id) != p[0].id:
			e.append(BWUnit.from_roster(row))
	var a: BWUnit = p[0]
	a.known_skills.append("axe_throw")
	a.skill_loadout["axe"] = ["cleave", "axe_throw"]
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	await _wait(1.6)
	a = s.battle._unit(a.id)
	var d: BWUnit = s.battle._unit(e[0].id)
	# the foe 3 hexes away on a free line
	for n in BWHex.neighbors(a.pos):
		var line := BWHex.ray(a.pos, n, 3)
		if line.size() < 3:
			continue
		var ok := true
		for h in line:
			if not s.battle.board.exists(h) or not s.battle.board.is_passable(h) or (s.battle.unit_at(h) != null and s.battle.unit_at(h) != d):
				ok = false
				break
		if ok:
			d.pos = line[2]
			break
	s._views[d.id].position = s.board_view.top_center(d.pos)
	s._face_all()
	await _wait(0.4)
	var crit := OS.get_environment("CRIT") == "1"
	var res := { "hit": true, "crit": crit, "glance": false, "resisted": false, "damage": 21, "secondary": true }
	var ev := { "type": "skill", "unit": a.id, "skill": "axe_throw", "element": a.element, "target": d.pos, "hexes": [d.pos],
		"results": [{ "target": d.id, "result": res, "ko": false, "target_hp": maxi(d.hp - 21, 1), "tags": [] }] }
	s._queue.append(ev)
	s._after_events()
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 3600:
		await _wait(0.12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/axethrow_%02d.png" % [out, n])
		n += 1
	print("frames ", n)
	quit()

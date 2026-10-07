extends SceneTree
## D340 review renders of the castle modes (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/castle_shots.gd
## mode_defend_overview.png  Defend the Castle: the whole keep from above (walls, gate, moat, braziers, the plate)
## mode_defend_gate.png      the iron gate under attack, its HP bar and the plate (autoplay to round 3+)
## mode_storm_overview.png   Storm the Castle: the stronghold, the guards on the walls, the sealed throne
## mode_storm_break.png      the wooden gate breaking: the phase change banner (the gate is worn to 1 HP
##                           first so the squad's next blow breaks it)
## mode_storm_throne.png     the throne room after the breach: the seal gone, the Warden, the squad coming in
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _screen(mode: String) -> BWCombatScreen:
	var q := BWCastle.quick_run(mode, 3, 8)
	var s := BWCombatScreen.new()
	s.configure("res://maps/%s.json" % q.map, q.players, q.enemies, [], 31)
	s.autoplay = true
	root.add_child(s)
	return s


func _look(s: BWCombatScreen, h: Vector2i, dist: float, pitch_deg: float = 48.0) -> void:
	s.rig.following = false
	s.rig.pivot = BWLook.world(h, s.battle.board.elevation(h))
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(pitch_deg)


func _go() -> void:
	BWSettings.put("cutscenes", "fast")
	BWMusic.ensure(root)
	await _defend()
	await _storm()
	quit()


func _defend() -> void:
	var s := _screen("defend")
	await _wait(3.0)
	_look(s, Vector2i(9, 9), 40.0, 52.0)
	await _wait(0.5)
	await _shot("mode_defend_overview")
	s.rig.following = true
	var g := BWCastle.gate(s.battle)
	var t := 0.0
	while not s.battle.over and t < 150.0 and not (s.battle.cycle >= 3 and g.hp < g.max_hp()):
		await _wait(0.5)
		t += 0.5
	print("defend: round %d, gate %d/%d" % [s.battle.cycle, g.hp, g.max_hp()])
	s.autoplay = false
	while s._busy and not s.battle.over:
		await _wait(0.2)
	_look(s, g.pos, 20.0, 46.0)
	s.rig.yaw += PI                              # from outside the wall, the raiders' side
	await _wait(0.8)
	await _shot("mode_defend_gate")
	s.queue_free()
	await _wait(0.3)


func _storm() -> void:
	var s := _screen("storm")
	await _wait(3.0)
	_look(s, Vector2i(9, 7), 40.0, 52.0)
	await _wait(0.5)
	await _shot("mode_storm_overview")
	s.rig.following = true
	var g := BWCastle.gate(s.battle)
	g.hp = 1                                     # staged: the squad's next blow on it breaks it
	var t := 0.0
	while not s.castle_view.breach_shown and not s.battle.over and t < 150.0:
		if not s.battle.history.any(func(e): return e.type == "castle_breach"):
			await _wait(0.05)
		else:
			_look(s, g.pos, 17.0, 44.0)          # hold the frame on the gate as it falls
			await process_frame
		t += 0.05
	_look(s, g.pos, 17.0, 44.0)
	await _wait(0.15)
	await _shot("mode_storm_break")
	print("storm: breach at round %d" % s.battle.cycle)
	var tt := 0.0
	while not s.battle.over and tt < 60.0 and s.battle.cycle < 3:
		await _wait(0.5)
		tt += 0.5
	s.autoplay = false
	while s._busy and not s.battle.over:
		await _wait(0.2)
	var th := BWCastleStorm.throne(s.battle)
	_look(s, th.pos + Vector2i(0, 2), 19.0, 50.0)
	await _wait(0.8)
	await _shot("mode_storm_throne")
	s.queue_free()

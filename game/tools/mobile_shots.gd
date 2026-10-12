extends SceneTree
## D574 review renders: combat in the mobile layout, walked through with the
## pad's own entry points (BWTouchCombat.press / step), at a phone's
## landscape shape. -> design/art/mobile_<step>.png
##   [SHOTS=<dir>] [SIZE=1920x864] [MAP=arena] godot --path . --script res://tools/mobile_shots.gd
## Shots: the commands on the turn start; Move with the cursor walked off;
## the commands after the move; the Act list; aiming at a foe; its one-line
## forecast; X on a foe (its full card); X on a skill row.
## SCREEN=roster: character select with the stick, A and B (D577).

var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	var sz := OS.get_environment("SIZE")
	if sz == "":
		sz = "1920x864"
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(sz.get_slice("x", 0)), int(sz.get_slice("x", 1))))
	BWSettings._v["layout"] = "mobile"
	root.content_scale_factor = BWSettings.TOUCH_SCALE
	_go.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("mobile_" + name + ".png"))
	print("shot ", name, " ", img.get_size(), "  mode=", s.touch.mode if s.touch else "-")


func _shot_plain(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("mobile_" + name + ".png"))
	print("shot ", name)


func _until(f: Callable, limit: float = 30.0) -> bool:
	var t := 0.0
	while not f.call() and t < limit:
		await _wait(0.2)
		t += 0.2
	return f.call()


func _go() -> void:
	BWMusic.ensure(root)
	if OS.get_environment("SCREEN") == "roster":     # D577: character select with the stick, A and B
		var r := BWRosterScreen.new()
		root.add_child(r)
		await _wait(3.5)
		await _shot_plain("roster_1")
		for d in [0, 0, 0]:
			r.pad_step(d)
			await _wait(0.2)
		r.pad_press("a")
		r.pad_step(4)
		r.pad_press("a")
		await _wait(1.0)
		await _shot_plain("roster_2_two_picked")
		r.pad_press("b")
		await _wait(0.8)
		await _shot_plain("roster_3_b_unpicks")
		quit(0)
		return
	var roster := BWData.table("roster")
	var players: Array = []
	var enemies: Array = []
	for i in 3:
		players.append(BWUnit.from_roster(roster[i]))
		enemies.append(BWUnit.from_roster(roster[(i + 10) % roster.size()]))
	s = BWCombatScreen.new()
	var map := OS.get_environment("MAP")
	s.configure("res://maps/%s.json" % (map if map != "" else "arena"), players, enemies, [], 1)
	root.add_child(s)
	var ok := await _until(func(): return s.touch != null and s.touch.mode == "root", 60.0)
	print("player turn: ", ok, "  ", s.battle.current().name if s.battle.current() else "-")
	await _wait(1.2)
	await _shot("1_commands")
	var t := s.touch
	t.press("a")                                    # Move (the first row)
	await _wait(0.3)
	for d in [0, 0, 7]:
		t.step(d)
		await _wait(0.15)
	await _wait(0.6)
	await _shot("2_move")
	t.press("a")                                    # walk there
	await _wait(0.45)
	await _shot("2b_walking")                       # D578: the camera rides along
	await _until(func(): return t.mode == "root", 20.0)
	await _wait(0.8)
	await _shot("3_after_move")
	t.press("tilt_up")                              # D578: ▲ a steeper view
	t.press("tilt_up")
	await _wait(0.6)
	await _shot("3b_tilted_up")
	t.press("tilt_down")
	t.press("tilt_down")
	await _wait(0.4)
	t.press("a")                                    # Act (the spent Move row is skipped)
	await _wait(0.6)
	await _shot("4_act")
	t.press("x")                                    # X on the highlighted row
	await _wait(0.5)
	await _shot("5_x_on_row")
	t.press("b")
	await _wait(0.2)
	t.press("a")                                    # Attack
	await _wait(0.6)
	await _shot("6_aim")
	var u := s.battle.current()
	var foes: Array = s.battle.attack_targets(u)
	if not foes.is_empty():
		t.set_cursor((foes[0] as BWUnit).pos)
		t.press("a")
		await _wait(0.6)
		await _shot("7_forecast")
		t.press("b")
		await _wait(0.3)
	var foe: BWUnit = null
	for o in s.battle.units:
		if o.team != u.team and o.alive():
			foe = o
			break
	t.set_cursor(foe.pos)
	t.press("x")
	await _wait(0.6)
	await _shot("8_x_on_foe")
	quit(0)

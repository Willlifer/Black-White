extends SceneTree
## D579: the tutorial played on the mobile layout with the pad's own entry
## points only (BWTouchCombat: the commands, the Act list, the cursor, A / B /
## X), step by step to the closing card. Prints one line per step and a
## verdict; saves the steps named in SHOT_STEPS (default below) to
## design/art/mobile_tut_<id>.png (or SHOTS=<dir>).
##   [SHOTS=<dir>] [SHOT_STEPS=a,b] godot --path . --script res://tools/mobile_tutorial.gd
## Exit code 0 when every step completed.

const STEP_TIMEOUT := 25.0
const DEFAULT_SHOTS := "controls,rim,move,undo,forecast,paint,tile_hover,overheat,others,shatter,skill_tip,rear,finish"

var out := ""
var shots: PackedStringArray
var tut: BWTutorial
var fails := 0


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	shots = (OS.get_environment("SHOT_STEPS") if OS.get_environment("SHOT_STEPS") != "" else DEFAULT_SHOTS).split(",", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 864))
	BWSettings._v["layout"] = "mobile"
	root.content_scale_factor = BWSettings.TOUCH_SCALE
	_go.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("mobile_tut_" + name + ".png"))


func _go() -> void:
	BWMusic.ensure(root)
	BWEsc.ensure(root)
	BWEsc.synthetic = true
	tut = BWTutorial.new()
	var ended := [false, false]
	tut.finished.connect(func(c): ended[0] = true; ended[1] = c)
	root.add_child(tut)
	var last := -1
	while not ended[0]:
		var t := 0.0
		while not ended[0] and not (tut.index != last and tut.ready_for_input and (tut.screen == null or not tut.screen._busy)):
			await process_frame
			t += 1.0 / 60.0
			if t > STEP_TIMEOUT:
				break
		if ended[0]:
			break
		var s := tut.step()
		if tut.index == last:
			print("FAIL step %s never completed" % str(s.get("id", "?")))
			fails += 1
			break
		last = tut.index
		await _wait(0.5)
		if str(s.id) in shots:
			await _shot(str(s.id))
		await _perform(s)
		print("step %-12s %s" % [str(s.id), str(s.wait)])
		if str(s.id) in shots and str(s.wait) in ["forecast", "aim"]:
			await _wait(0.5)
			await _shot(str(s.id) + "_after")
	var all_done: bool = ended[1] and tut.done_ids.size() >= tut.steps.size() - 1
	print("mobile tutorial: %s (%d / %d steps, %d fails)" % ["COMPLETED" if all_done else "STOPPED", tut.done_ids.size(), tut.steps.size(), fails])
	quit(0 if all_done and fails == 0 else 1)


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await _wait(0.2)


func _touch() -> BWTouchCombat:
	return tut.screen.touch if tut.screen and is_instance_valid(tut.screen) else null


## Highlight the open list's row whose words start with `label`, then A.
func _choose(label: String) -> bool:
	var ui := tut.screen.ui
	var bs: Array = ui._focusable()
	for i in bs.size():
		if (bs[i] as Button).text.strip_edges().begins_with(label):
			ui._focus = i
			ui._restyle_focus()
			_touch().press("a")
			await _wait(0.35)
			return true
	print("  no row \"%s\" in %s" % [label, bs.map(func(b): return (b as Button).text.strip_edges())])
	return false


func _press_row(b: Button) -> void:
	var ui := tut.screen.ui
	var bs: Array = ui._focusable()
	ui._focus = bs.find(b)
	ui._restyle_focus()
	_touch().press("a")
	await _wait(0.35)


func _open_act() -> void:
	var tc := _touch()
	if tc.mode != "root":
		tc.open_root()
		await _wait(0.3)
	await _choose("Act")


func _perform(s: Dictionary) -> void:
	var act: Dictionary = s.get("act", {})
	var tc := _touch()
	match str(s.wait):
		"next":
			if tc != null:
				tc.press("a")                         # the coach's Next (BWTutorial._touch_next)
			else:
				tut._next = true
		"hover":
			if tc.mode in ["root", "act"]:
				tc.press("b")                         # a free cursor (aiming already has one)
				await _wait(0.3)
			tc.set_cursor(s.hex)
			tc.press("x")
			await _wait(1.2)
			tc.press("x")
		"move":
			if tc.mode != "root":
				tc.open_root()
				await _wait(0.3)
			await _choose("Move")
			tc.set_cursor(tut.rear if str(act.hex) == "rear" else act.hex)
			await _wait(0.2)
			tc.press("a")
		"undo":
			if tc.mode != "root":
				tc.open_root()
				await _wait(0.3)
			await _choose("Undo move")
		"forecast":
			await _open_act()
			await _choose("Attack")
			tc.set_cursor(tut.unit(str(act.target)).pos)
			await _wait(0.2)
			tc.press("a")
		"aim":
			await _open_act()
			for k in 3:
				var b := tut.menu_button(str(act.key), str(act.element))
				if b == null:
					break
				await _press_row(b)
				if str(tut.screen._skill.get("key", "")) == str(act.key):
					break
		"act":
			match str(act.kind):
				"attack":
					tc.press("a")
				"swap":
					await _open_act()
					await _choose("Swap weapon")
				"skill":
					var at: Vector2i = act.hex if act.has("hex") else tut.unit(str(act.target)).pos
					tc.set_cursor(at)
					await _wait(0.25)
					tc.press("a")
					await _wait(0.4)
					if tut.screen and tut.screen.ui.forecast_open():
						if str(s.id) in shots:
							await _shot(str(s.id) + "_confirm")
						tc.press("a")
		"results":
			await _wait(1.4)
			await _key(KEY_ENTER)
		"pick":
			await _wait(0.5)
			await _key(KEY_1)                         # the picker's own keys (its cards are taps on a phone)
			await _key(KEY_ENTER)
		"card":
			await _wait(0.6)
			var back: Button = tut.card.find_child("card_back", true, false)
			back.pressed.emit()
		"over":
			print("FAIL the Surge left someone standing")
			fails += 1
			tut.exit()

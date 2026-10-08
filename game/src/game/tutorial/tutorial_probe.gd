class_name BWTutorialProbe
extends Node
## D223: steps through the whole tutorial with synthetic input, the way a
## player would: the title's T entry, every Next, every click on the marked
## hex or unit, the menu rows, Enter on the confirm box, Esc for the undo,
## the coach's Esc dialog, the summary, both picks, the closing card. Checks
## each step completes and the fight did what the lessons say (a detonation,
## a chain arc, Shatter, Spark, the swap, the statuses, a rear attack, the
## win, a level each). `godot --path . -- --tutorial-probe` (needs a window);
## SHOTS=<dir> saves the review frames (design/art/tutorial_*.png). Exit 0 = ok.

const STEP_TIMEOUT := 90.0
const SHOT_AT := {
	"intro": "tutorial_intro", "detonate": "tutorial_detonation", "chain": "tutorial_chain",
	"swap": "tutorial_swap", "perk": "tutorial_pick",
}

var tut: BWTutorial
var _fails: PackedStringArray = []
var _passes := 0
var _shots := ""
var _seen_rear := false


func _ready() -> void:
	_shots = OS.get_environment("SHOTS")
	_run.call_deferred()


func _run() -> void:
	BWEsc.synthetic = true
	# ---- the title's entry: T opens the tutorial
	var title := BWTitleScreen.new()
	add_child(title)
	var picked := [""]
	title.done.connect(func(c): picked[0] = c)
	var t := 0.0
	while not title._ready_for_input and t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(1.2).timeout
	var entry: Control = title.find_child("tutorial_entry", true, false)
	_check(entry != null and entry.is_visible_in_tree(), "the title shows the tutorial entry next to settings")
	await _shot("tutorial_title")
	await _key(KEY_T)
	await get_tree().process_frame
	_check(picked[0] == "tutorial", "T on the title picks the tutorial (%s)" % picked[0])
	title.queue_free()
	await get_tree().process_frame

	var save_before := FileAccess.get_modified_time("user://run.json") if FileAccess.file_exists("user://run.json") else -1
	# ---- the tutorial, step by step
	tut = BWTutorial.new()
	var ended := [false, false]
	tut.finished.connect(func(c): ended[0] = true; ended[1] = c)
	add_child(tut)
	var last := -1
	var esc_tested := false
	while not ended[0]:
		var ok := await _wait_step(last)
		if ended[0]:
			break
		if not ok:
			_check(false, "step %d (%s) came up in time" % [tut.index, str(tut.step().get("id", "?"))])
			break
		last = tut.index
		var s := tut.step()
		if not esc_tested:
			esc_tested = true
			await _esc_dialog()
		if SHOT_AT.has(str(s.id)) and str(s.wait) != "results":
			await get_tree().create_timer(0.35).timeout
			await _shot(SHOT_AT[str(s.id)])
		var done_before := tut.done_ids.size()
		await _perform(s)
		var t2 := 0.0
		while tut.index == last and not ended[0] and t2 < STEP_TIMEOUT:
			await get_tree().process_frame
			t2 += get_process_delta_time()
		if tut.index == last and not ended[0]:
			_check(false, "step %s completed (still waiting after %ds)" % [s.id, int(STEP_TIMEOUT)])
			break
		_check(tut.done_ids.size() > done_before or ended[0], "step %s done" % s.id)
	_check(ended[0] and ended[1], "the tutorial ran to the end (completed = %s)" % ended[1])
	_check(tut.done_ids.size() == tut.steps.size() - 1 or tut.done_ids.size() == tut.steps.size(),
		"every step was played (%d of %d)" % [tut.done_ids.size(), tut.steps.size()])
	_lessons()
	var save_after := FileAccess.get_modified_time("user://run.json") if FileAccess.file_exists("user://run.json") else -1
	_check(save_after == save_before, "the player's save is untouched")
	print("tutorial-probe: %d passed, %d failed" % [_passes, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)


## What the fight did, from the tutorial's battle history and run.
func _lessons() -> void:
	var h: Array = tut.history
	var has := func(pred: Callable) -> bool: return h.any(pred)
	_check(has.call(func(e): return e.type == "undo_move"), "lesson 1: a move was undone")
	_check(has.call(func(e): return e.type == "attack" and e.unit == "della" and e.target == "burt"), "lesson 2: Della attacked Burt")
	_check(has.call(func(e): return e.type == "paint" and e.element == "fire" and Vector2i(2, 2) in e.hexes), "lesson 4: fire painted")
	_check(has.call(func(e): return e.type == "detonate"), "lesson 5: a detonation")
	_check(has.call(func(e): return e.type == "attack" and "Shatter" in e.get("tags", [])), "lesson 5: a Shatter blow")
	_check(has.call(func(e): return e.type == "skill" and e.skill == "bolt" and e.results.any(func(r): return "Spark" in r.get("tags", [])) ), "lesson 5: a Spark bolt")
	_check(has.call(func(e): return e.type == "chain"), "lesson 5: a chain arc")
	_check(has.call(func(e): return e.type == "paint" and e.has("gales")), "lesson 6: a gale spread")
	_check(has.call(func(e): return e.type == "skill" and e.skill == "thread_needle"), "lesson 7: a skill used")
	_check(has.call(func(e): return e.type == "swap"), "lesson 7: the weapon swap")
	_check(has.call(func(e): return e.type == "status" and e.status == "pinned" and e.unit == "burt"), "lesson 8: Burt Pinned (D419: was a pistol whip's Stagger)")
	_check(has.call(func(e): return e.type == "status" and e.status == "pinned" and e.unit == "rui"), "lesson 8: Rui Pinned")
	_check(has.call(func(e): return e.type == "attack" and "Rear" in e.get("tags", [])), "lesson 9: a rear attack")
	_check(has.call(func(e): return e.type == "battle_end" and e.winner == "player"), "lesson 10: the fight was won")
	_check(tut.run.squad.all(func(u): return u.level == 2), "lesson 10: every unit levelled once")
	var della := tut.run.unit("della")
	_check(della != null and della.perks.size() >= 2, "lesson 10: a perk was picked on top of the drawn first one (D233) (%s)" % [della.perks if della else []])
	_check(della != null and int(della.skill_picks.get("sword", 0)) >= 1, "lesson 10: a skill was picked")


## Wait for the next step to be up and waiting for input.
func _wait_step(last: int) -> bool:
	var t := 0.0
	while t < STEP_TIMEOUT:
		if tut.index != last and tut.ready_for_input and (tut.screen == null or not tut.screen._busy):
			await get_tree().process_frame
			return true
		if tut.index >= tut.steps.size():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


func _perform(s: Dictionary) -> void:
	var act: Dictionary = s.get("act", {})
	match str(s.wait):
		"next":
			if str(s.id) == "forecast":
				await _hover_ctl(tut.ui_target("hit_row"))       # hover a number: its formula
			await _click_ctl(tut.coach.next_button())
		"hover":
			await _hover_hex(s.hex)
			await get_tree().create_timer(1.0).timeout
		"move":
			await _click_hex(tut.rear if str(act.hex) == "rear" else act.hex)
		"undo":
			await _key(KEY_ESCAPE)
		"forecast":
			await _click_hex(tut.unit(str(act.target)).pos)
		"aim":
			for k in 3:
				var b := tut.menu_button(str(act.key), str(act.element))
				if b == null:
					break
				await _click_ctl(b)
				await get_tree().create_timer(0.15).timeout
				if str(tut.screen._skill.get("key", "")) == str(act.key):
					break
		"act":
			match str(act.kind):
				"attack":
					if str(s.id) == "rear":
						var row := tut.ui_target("hit_row")
						_seen_rear = row != null and row.tooltip_text.contains("Rear attack")
						_check(_seen_rear, "the hit chance's formula names the rear attack")
					await _key(KEY_ENTER)
				"swap":
					await _click_ctl(tut.ui_target("swap"))
				"skill":
					var at: Vector2i = act.hex if act.has("hex") else tut.unit(str(act.target)).pos
					await _click_hex(at)
					await get_tree().create_timer(0.3).timeout
					if tut.screen and tut.screen.ui.forecast_open():
						if str(s.id) == "finish":
							await _shot("tutorial_finish")
						await _key(KEY_ENTER)
		"results":
			await get_tree().create_timer(1.6).timeout
			await _shot("tutorial_levelup")
			await _key(KEY_ENTER)
		"pick":
			await get_tree().create_timer(0.5).timeout
			if str(s.id) == "skill_pick":
				await _shot("tutorial_skill_pick")
			await _key(KEY_1)
			await _key(KEY_ENTER)
		"card":
			await get_tree().create_timer(0.8).timeout
			await _shot("tutorial_closing")
			await _click_ctl(tut.card.find_child("card_back", true, false))
		"over":
			_check(false, "the Surge left someone standing (free play reached)")
			tut.exit()


## Esc opens the coach's dialog (skip / exit / keep going); Esc closes it.
func _esc_dialog() -> void:
	await _key(KEY_ESCAPE)
	_check(tut.coach.dialog_open(), "Esc opens the coach's skip / exit dialog")
	await _shot("tutorial_esc")
	await _key(KEY_ESCAPE)
	_check(not tut.coach.dialog_open(), "Esc again closes it")


# ---------------------------------------------------------------- input

func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _hex_point(h: Vector2i) -> Vector2:
	return _to_window(tut.screen.cam.unproject_position(tut.screen.board_view.top_center(h)))


func _move(p: Vector2) -> void:
	for k in 2:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame


func _press(p: Vector2) -> void:
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		Input.parse_input_event(mb)
		await get_tree().process_frame


func _click_hex(h: Vector2i) -> void:
	var p := _hex_point(h)
	await _move(p)
	await _press(p)


func _hover_hex(h: Vector2i) -> void:
	await _move(_hex_point(h))


func _hover_ctl(c: Control) -> void:
	if c != null:
		await _move(_to_window(c.get_global_rect().get_center()))
		await get_tree().create_timer(0.3).timeout


func _click_ctl(c: Control) -> void:
	if c == null:
		_check(false, "a control to click for step %s" % str(tut.step().get("id", "?")))
		return
	var p := _to_window(c.get_global_rect().get_center())
	await _move(p)
	await _press(p)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(name: String) -> void:
	if _shots == "":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots)
	get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("  ok   ", what)
	else:
		_fails.append(what)
		print("  FAIL ", what)

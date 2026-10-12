extends RefCounted
## D574-D575 (author, 2026-10-11): the mobile layout. The pad's 8-way stick,
## the layout setting (tests and tools stay on desktop; a player's first run
## starts on mobile), and the menu-row commands.


func test_stick_directions(t) -> void:
	t.eq(BWTouchPad.dir_of(Vector2(1, 0)), 0, "right")
	t.eq(BWTouchPad.dir_of(Vector2(1, 1)), 1, "down-right")
	t.eq(BWTouchPad.dir_of(Vector2(0, 1)), 2, "down (screen y runs down)")
	t.eq(BWTouchPad.dir_of(Vector2(-1, 0)), 4, "left")
	t.eq(BWTouchPad.dir_of(Vector2(0, -1)), 6, "up")
	t.eq(BWTouchPad.dir_of(Vector2(1, -1)), 7, "up-right")
	t.eq(BWTouchPad.dir_of(Vector2(5, 0), 22.0), -1, "inside the dead zone: nothing")
	for d in 8:
		t.eq(BWTouchPad.dir_of(BWTouchPad.dir_vec(d)), d, "dir_vec(%d) round-trips" % d)


func test_layout_setting(t) -> void:
	t.eq(str(BWSettings.DEFAULTS.layout), "desktop", "isolated runs (tests, probes, tools) stay desktop")
	t.ok(not BWSettings.touch(), "so the self-test runs the desktop layout")
	t.eq(BWSettings._clean("layout", "phone"), "desktop", "an unknown layout falls back")
	t.eq(BWSettings._clean("layout", "mobile"), "mobile", "mobile is kept")
	t.ok(BWSettings.TOUCH_SCALE >= 1.25, "the mobile UI is drawn at least 1.25x")


func test_no_y_button(t) -> void:
	var p := BWTouchPad.new()
	p._ready()
	t.ok(p.button("a") != null and p.button("b") != null and p.button("x") != null, "A, B and X")
	t.ok(p.button("y") == null, "no Y: the commands open on the turn, or on A over your unit")
	for id in ["turn_left", "turn_right", "pause"]:
		t.ok(p.button(id) != null, id)
	p.free()


## D577 (author: "Stick was stuck permanently aiming up and right"): a finger
## owns the stick from its press to its own lift, wherever it lifts; a second
## finger on A doesn't disturb it; focus loss lets everything go.
func test_finger_lifts_free_the_stick(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := CanvasLayer.new()
	tree.root.add_child(layer)
	var p := BWTouchPad.new()
	layer.add_child(p)
	if p._stick == null:
		p._ready()                                # a tree that isn't running yet (the one-suite runner)
	p.size = Vector2(1600, 900)
	p._stick.position = Vector2(28, 652)
	p._stick.size = Vector2(220, 220)
	var a: Control = p.button("a")
	a.position = Vector2(1400, 700)
	a.size = Vector2(84, 84)
	var steps: Array = []
	p.step.connect(func(d): steps.append(d))
	var c: Vector2 = p._stick.get_global_rect().get_center()
	p._input(_touch(0, c + Vector2(60, -60), true))
	t.eq(p._stick.held_dir(), 7, "a finger up-right of centre holds up-right")
	t.eq(steps, [7], "and steps once at once")
	p._input(_drag(0, c + Vector2(-70, 0)))
	t.eq(p._stick.held_dir(), 4, "dragging left turns it left")
	p._input(_touch(1, a.get_global_rect().get_center(), true))
	t.ok(p.held.has("a"), "a second finger presses A")
	p._input(_touch(0, Vector2(800, 100), false))
	t.eq(p._stick.held_dir(), -1, "the first finger lifting far away lets the stick go")
	t.ok(p.held.has("a"), "A is still held by its own finger")
	p._input(_touch(1, Vector2(10, 10), false))
	t.ok(not p.held.has("a"), "and lets go when that finger lifts")
	p._input(_touch(2, c + Vector2(0, 70), true))
	p._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	t.eq(p._stick.held_dir(), -1, "losing focus lets everything go")
	layer.queue_free()
	BWTouchPad.touch_seen = false


func _touch(i: int, at: Vector2, down: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	return e


func _drag(i: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = at
	return e

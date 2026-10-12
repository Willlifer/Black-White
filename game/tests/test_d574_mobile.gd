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

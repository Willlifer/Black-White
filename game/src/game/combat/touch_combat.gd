class_name BWTouchCombat
extends Node
## D574-D575 (author, 2026-10-11): combat in the mobile layout, played like
## Fire Emblem / Final Fantasy Tactics with an on-screen pad (BWTouchPad).
##
##   your turn     the camera centres on the unit, the cursor sits on it and
##                 its commands open: Move · Act · (Undo move) · Wait
##   Move          the stick walks the cursor over the walk rim; A moves
##                 there, then the commands open again (Act · Wait)
##   Act           the desktop action list (Attack, Swap weapon, the skills,
##                 Wait): the stick moves the highlight, A picks; then the
##                 stick aims and A opens the one-line forecast; A again
##                 confirms
##   B             one step back: forecast → aim → Act → the commands →
##                 a free cursor (A on your own unit opens the commands again)
##   X             the full card for whatever the cursor is on (unit, tile,
##                 or the highlighted skill); X or B closes it
##   ◀ ▶  II       turn the camera 60°, pause (Quit to title is in there)
##   A or B held   fast-forwards playback, like holding Space
## The same actions answer the keyboard (arrows / WASD, Enter, Esc, I, Q / E,
## P) and a gamepad (by position: right = A, bottom = B, left = X, Start).
## The screen keeps every rule: this only turns pad input into the screen's
## own hover (_on_hover), click (_on_click) and actions (_on_action).

const TILT := 12.0                 # D578: degrees per ▲ / ▼ press
const TOUCH_DIST := 17.0          # a closer camera than the desktop's 24 (a phone screen)
const FOLLOW_EDGE := 0.30          # the camera follows the cursor once it leaves the middle 40% of the screen

var s: BWCombatScreen
var pad: BWTouchPad
var cursor := Vector2i(-1, -1)
var mode := "idle"                 # idle · root · act · move · aim · look
var _ring: MeshInstance3D
var _t := 0.0
## D579 (the tutorial): A goes here first (true = taken, e.g. the coach's
## Next); II calls pause_hook instead of the pause menu when set.
var a_hook: Callable
var pause_hook: Callable


func setup(screen: BWCombatScreen) -> void:
	s = screen
	pad = BWTouchPad.new()
	pad.name = "touch_pad"
	s.ui._root.add_child(pad)
	pad.step.connect(step)
	pad.pressed.connect(press)
	s.ui.action_pressed.connect(_on_ui_action)
	s.ui.skill_chosen.connect(func(_k, _e): _after_pick.call_deferred())
	s.rig.input_enabled = false
	s.rig.dist = TOUCH_DIST
	_ring = _make_ring()
	s.add_child(_ring)
	_ring.visible = false


func fast_forward_held() -> bool:
	return pad != null and (pad.held.has("a") or pad.held.has("b"))


# ---------------------------------------------------------------- turn flow

## The screen hands over: a player unit may act (end of BWCombatScreen._after_events).
func ready_for_input() -> void:
	var u := s.battle.current()
	if u == null or not s._player_turn():
		mode = "idle"
		s.ui.touch_close()
		return
	set_cursor(u.pos)
	s.rig.follow(s._unit_pos(u.pos))
	open_root()


func open_root() -> void:
	var u := s.battle.current()
	if u == null or not s._player_turn():
		return
	s._skill = {}
	s.ui.hide_info()
	if s.ui.forecast_open():
		s._on_action("cancel")
	var fu := not u.follow_up.is_empty()
	var dance := BWKit2.dance_pending(s.battle, u)
	var items: Array = []
	if dance:
		items.append({ "id": "move", "label": "Blade Dance step" })
	else:
		items.append({ "id": "move", "label": "Move", "enabled": s.battle.can_move(u) })
	items.append({ "id": "act", "label": "Follow-up" if fu else "Act", "enabled": fu or not u.acted })
	if s.battle.can_undo_move(u):
		items.append({ "id": "undo", "label": "Undo move" })
	items.append({ "id": "wait", "label": "Skip follow-up" if fu else "Wait" })
	mode = "root"
	set_cursor(u.pos)
	s.rig.follow(s._unit_pos(u.pos))
	s._show_options()
	s.ui.touch_root(u, items)


func _on_ui_action(id: String) -> void:
	var u := s.battle.current()
	match id:
		"touch:move":
			mode = "move"
			s.ui.touch_close()
			set_cursor(u.pos)
		"touch:act":
			mode = "act"
			s.ui.touch_act()
		"touch:undo":                                  # D579: through the screen's own Esc (so the tutorial's gate sees it)
			if s._player_turn() and s.battle.can_undo_move(u):
				s.ui.touch_close()
				s._on_action("cancel")
		"touch:wait":
			s.ui.touch_close()
			s._on_action("wait")
		"attack":
			mode = "aim"
			s.ui.touch_close()
			var foes: Array = s.battle.attack_targets(u)
			if not foes.is_empty():
				set_cursor((foes[0] as BWUnit).pos)
		"wait", "swap":
			s.ui.touch_close()


## After a skill row: aiming, or straight to its confirm (a self-centred skill).
func _after_pick() -> void:
	if not s._player_turn():
		return
	s.ui.touch_close()
	mode = "aim"
	if s._skill.is_empty() or s.ui.forecast_open():
		return
	var u := s.battle.current()
	var tg: Array = s.battle.skill_targets(u, s._skill.key, s._skill.element)
	var foe: Array = tg.filter(func(h): return s.battle.unit_at(h) != null and s.battle.unit_at(h).team != u.team)
	if not foe.is_empty():
		set_cursor(foe[0])
	elif not tg.is_empty() and not u.pos in tg:
		set_cursor(tg[0])


# ---------------------------------------------------------------- the pad

func step(d: int) -> void:
	if s.ui.info_open():
		return
	if mode == "root" or mode == "act":
		if d in [5, 6, 7]:
			s.ui.menu_nav(-1)
		elif d in [1, 2, 3]:
			s.ui.menu_nav(1)
		return
	if not s._player_turn() or s.ui.forecast_open():
		return
	var to := best_step(cursor, d)
	if to != cursor:
		set_cursor(to)


func press(id: String) -> void:
	match id:
		"turn_left": s.rig.rotate_by(-60.0)
		"turn_right": s.rig.rotate_by(60.0)
		"tilt_up": s.rig.tilt_by(TILT)               # D578: a steeper, more top-down view
		"tilt_down": s.rig.tilt_by(-TILT)            # flatter, toward side-on
		"pause":
			if pause_hook.is_valid():
				pause_hook.call()
			else:
				s.open_pause()
		"x": _info()
		"a": _a()
		"b": _b()


func _a() -> void:
	if a_hook.is_valid() and a_hook.call():
		return
	if s.ui.info_open():
		s.ui.hide_info()
		return
	if not s._player_turn():
		return
	if s.ui.forecast_open():
		s._on_action("confirm")
		return
	var u := s.battle.current()
	match mode:
		"root", "act":
			s.ui.menu_press()
		"move":
			var o := s.battle.unit_at(cursor)
			if o == u or cursor == u.pos:
				open_root()
			elif o == null:
				s._on_click(cursor)
		"aim":
			var t := s.battle.unit_at(cursor)
			if not s._skill.is_empty() or (t != null and t.team != u.team):   # a basic attack never walks
				s._on_click(cursor)
		_:
			if s.battle.unit_at(cursor) == u or cursor == u.pos:
				open_root()


func _b() -> void:
	if s.ui.info_open():
		s.ui.hide_info()
		return
	if not s._player_turn():
		return
	if s.ui.forecast_open():
		s._on_action("cancel")
		return
	match mode:
		"aim":
			if s._skill.has("first"):
				s._on_action("cancel")
				return
			s._skill = {}
			s._show_options()
			mode = "act"
			s.ui.touch_act()
		"act", "move":
			open_root()
		"root":
			mode = "look"
			s.ui.touch_close()
		"look":
			open_root()


func _info() -> void:
	if s.ui.info_open():
		s.ui.hide_info()
		return
	if mode == "act" or mode == "root":
		var tip := s.ui.menu_focus_tip()
		if tip != "":
			var lines := tip.split("\n")
			s.ui.show_info(null, s.battle.tiles, "[b]%s[/b]\n%s" % [lines[0], "\n".join(lines.slice(1))])
		return
	if not s.battle.board.exists(cursor):
		return
	var o := s.battle.unit_at(cursor)
	if o != null:
		s.ui.show_info(o, s.battle.tiles)
		return
	var bb: String = BWReadability.card_bbcode(s.battle, cursor)
	s.ui.show_info(null, s.battle.tiles, bb)


## A tap on the board (a finger or the mouse): the cursor goes there; a tap on
## the cursor's own hex is A.
func tap(screen_pos: Vector2) -> void:
	if not s._player_turn() or s.ui.forecast_open() or s.ui.info_open():
		return
	if mode == "root" or mode == "act":
		return
	var h := s.board_view.pick(s.cam, screen_pos)
	if h == Vector2i(-1, -1):
		return
	if h == cursor:
		_a()
	else:
		set_cursor(h)


## Keys and gamepad buttons in the mobile layout. True when it took the event.
func key(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed:
		var d := _arrow_dir()
		if d >= 0 and ev.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]:
			step(d)
			return true
		if ev.echo:
			return false
		match ev.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_Z: press("a")
			KEY_ESCAPE, KEY_BACKSPACE: press("b")
			KEY_I, KEY_TAB: press("x")
			KEY_Q: press("turn_left")
			KEY_E: press("turn_right")
			KEY_PAGEUP, KEY_R: press("tilt_up")
			KEY_PAGEDOWN, KEY_V: press("tilt_down")
			KEY_P: press("pause")
			_: return false
		return true
	if ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_B: press("a")              # right face button
			JOY_BUTTON_A: press("b")              # bottom
			JOY_BUTTON_X: press("x")              # left
			JOY_BUTTON_START: press("pause")
			JOY_BUTTON_LEFT_SHOULDER: press("turn_left")
			JOY_BUTTON_RIGHT_SHOULDER: press("turn_right")
			JOY_BUTTON_RIGHT_STICK: press("tilt_up")
			JOY_BUTTON_LEFT_STICK: press("tilt_down")
			JOY_BUTTON_DPAD_UP: step(6)
			JOY_BUTTON_DPAD_DOWN: step(2)
			JOY_BUTTON_DPAD_LEFT: step(4)
			JOY_BUTTON_DPAD_RIGHT: step(0)
			_: return false
		return true
	return false


static func _arrow_dir() -> int:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S): v.y += 1
	return BWTouchPad.dir_of(v)


# ---------------------------------------------------------------- the cursor

func set_cursor(h: Vector2i) -> void:
	if not s.battle.board.exists(h):
		return
	cursor = h
	_ring.position = s.board_view.top_center(h) + Vector3(0, 0.05, 0)
	if s._player_turn():
		s._hover = Vector2i(-99, -99)          # the screen's hover runs again for this hex
		s._on_hover(h)
	var vp := s.get_viewport().get_visible_rect().size
	var p := s.cam.unproject_position(_ring.position)
	var off := (p / vp - Vector2(0.5, 0.5)).abs()
	if off.x > FOLLOW_EDGE or off.y > FOLLOW_EDGE:
		s.rig.follow(s._unit_pos(h))


## The hex one stick push away: the neighbour (or the hex two rows on, for a
## straight push between two neighbours) whose screen direction is nearest
## the push. Screen space, so it turns with the camera.
func best_step(from: Vector2i, d: int) -> Vector2i:
	var want := BWTouchPad.dir_vec(d)
	var c0 := s.cam.unproject_position(BWLook.world(from, 0))
	var best := from
	var best_score := INF
	for h in BWHex.area(from, 2):
		if h == from or not s.battle.board.exists(h):
			continue
		var v := s.cam.unproject_position(BWLook.world(h, 0)) - c0
		if v.length() < 1.0:
			continue
		var err := rad_to_deg(absf(want.angle_to(v)))
		if err > 40.0:
			continue
		var score := err + (BWHex.distance(from, h) - 1) * 14.0
		if score < best_score:
			best_score = score
			best = h
	return best


func _process(delta: float) -> void:
	if s == null or s.battle == null:
		return
	_t += delta
	var on := s._player_turn() and not s.battle.over and mode != "idle"
	_ring.visible = on
	if on:
		var m := _ring.material_override as StandardMaterial3D
		m.albedo_color.a = 0.65 + 0.35 * sin(_t * 5.0)


func _make_ring() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := BWLook.hex_corners(Vector3.ZERO, 0.97)
	var inner := BWLook.hex_corners(Vector3.ZERO, 0.74)
	for i in 6:
		var j := (i + 1) % 6
		for p in [outer[i], outer[j], inner[i], inner[i], outer[j], inner[j]]:
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	m.albedo_color = Color(0, 0, 0, 1)                 # ink on the white tiles
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "touch_cursor"
	return mi

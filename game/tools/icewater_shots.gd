extends SceneTree
## D266 review renders of the ice/water spine on the real combat screen (needs
## a window):
##   RES=1920x1080 [SHOTS=<dir>] [ONLY=slide,walk,pillar,steam,shock,rink] godot --path . --script res://tools/icewater_shots.gd
## v3_icewater_slide.png   Demeter aims an ice Charge: the shove onto the rink,
##                         the slide's ink arrow, its ghost ring and "SLAM 8%"
##                         where it ends against a pillar
## v3_icewater_slam.png    the same, played: the foe slid into the pillar
## v3_icewater_walk.png    Kira hovers a hex past a rink: the walk arrow runs on
##                         across the ice, the end hex marked, the slide hint
## v3_icewater_pillar.png  an ice pillar between Wilona's bow and a foe: no
##                         shot (no pulse on the foe), the pillar's tile card
## v3_icewater_steam.png   fire on a lake: steam over the whole pool, a unit in
##                         it, its tile card
## v3_icewater_shock_preview.png  a thunder Saturate aimed at the lake: the
##                         radius-1 field outlined, "ELECTRIFIED"
## v3_icewater_shock.png   the field live after two of the foe's turn starts:
##                         the crackling outline, the timer pips, the card
##                         with the ramp ("next shock immune")
## v3_icewater_rink.png    ice on the lake: radius 1 glazed with the sheen,
##                         two pillars risen from its water 3
var out := ""
var s: BWCombatScreen
var demeter: BWUnit
var kira: BWUnit
var wilona: BWUnit
var rui: BWUnit
var bob: BWUnit
var gail: BWUnit
var C := Vector2i(-1, -1)


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()          # D301: no leftover "Battle start"
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _unit(id: String, keys: Array = []) -> BWUnit:
	var u := BWRosterKits.unit(id)
	for k in keys:
		u.known_skills.append(k)
	if not keys.is_empty():
		u.skill_loadout[u.weapon_class] = keys + BWSkillRegistry.starter(u.weapon_class).slice(0, 1)
	for el in ["fire", "ice", "thunder", "water"]:
		u.affinity[el] = maxi(int(u.affinity.get(el, 0)), 10)
	return u


func _go() -> void:
	var wres := OS.get_environment("RES")
	if wres.contains("x"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3:
			await process_frame
		DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
		for i in 3:
			await process_frame
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	demeter = _unit("demeter", ["charge"])
	kira = _unit("kira", ["saturate", "surge"])
	wilona = _unit("wilona")
	rui = _unit("rui")
	bob = _unit("bob")
	gail = _unit("gail")
	for u in [demeter, kira, wilona]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure("res://maps/court.json", [demeter, kira, wilona], [rui, bob, gail], [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	C = Vector2i(6, 9)                        # court: flat for 3 east and west, a radius-2 lake fits
	if not s.battle.board.is_passable(C):
		C = _centre()
	print("centre ", C)
	var only := OS.get_environment("ONLY").split(",", false)
	for k in ["slide", "walk", "pillar", "steam", "shock", "rink"]:
		if only.is_empty() or k in only:
			await call("_" + k)
	quit()


## A hex whose radius-4 flower is all flat, standable ground.
func _centre() -> Vector2i:
	var b := s.battle
	var keys := b.board.cells()
	keys.sort()
	for h in keys:
		var ok := true
		for a in BWHex.area(h, 3):
			if not b.board.is_passable(a) or b.board.elevation(a) != b.board.elevation(h) or b.board.terrain(a) != BWBoard.NEUTRAL:
				ok = false
				break
		if ok:
			return h
	for h in keys:
		var ok2 := true
		for a in BWHex.area(h, 3):
			if not b.board.is_passable(a) or b.board.elevation(a) != b.board.elevation(h):
				ok2 = false
				break
		if ok2:
			return h
	return Vector2i(b.board.cols / 2, b.board.rows / 2)


func _east(h: Vector2i, n: int) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[0]
	return h


func _west(h: Vector2i, n: int) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[3]
	return h


func _reset(placed: Dictionary) -> void:
	var b := s.battle
	b.tiles.entries.clear()
	for d in [b.tiles.pillars, b.tiles.steam, b.tiles.fields, b.tiles.shock]:
		d.clear()
	var far: Array = []
	var keys := b.board.cells()
	keys.sort()
	for h in keys:
		if b.board.is_passable(h) and BWHex.distance(h, C) >= 5:
			far.append(h)
	far.sort_custom(func(x, y): return BWHex.distance(x, C) > BWHex.distance(y, C))
	var i := 0
	for u in [demeter, kira, wilona, rui, bob, gail]:
		var at: Vector2i = placed.get(u, far[i * 2] if i * 2 < far.size() else far[i])
		i += 1
		u.pos = at
		u.statuses = {}
		u.hp = u.max_hp()
		s._views[u.id].position = s.board_view.top_center(at)
		s._views[u.id].refresh()
	s.board_view.refresh_tiles(true)
	s._face_all()


func _lay(hexes: Array, h: int, glaze: int = 0) -> void:
	for x in hexes:
		var e := s.battle.tiles._entry(h, 0, "", "map", "cast")
		e.glaze = glaze
		s.battle.tiles.entries[x] = e


func _turn(u: BWUnit) -> void:
	s.ui.hide_forecast()
	s._skill = {}
	s._pending_skill = {}
	s._pending_target = null
	s.battle.queue = [u]
	s.battle.turn_index = 0
	u.acted = false
	u.moved = false
	u.follow_up = []
	s.battle._begin_turn()
	s._queue.clear()
	s.ui.set_acting(u, s.battle.tiles)
	s._show_options()
	s.ui.set_actions_visible(true)
	await _wait(0.4)


func _cam(at: Vector2i, yaw_deg: float = -30.0, dist: float = 15.0, pitch: float = 52.0) -> void:
	s.rig.follow(s.board_view.top_center(at), true)
	s.rig.yaw = deg_to_rad(yaw_deg)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(pitch)
	await _wait(0.6)


func _move_mouse(h: Vector2i) -> void:
	var vp_pos := s.cam.unproject_position(s.board_view.top_center(h))
	var p := root.get_final_transform() * vp_pos
	for k in 2:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await process_frame


func _click(h: Vector2i) -> void:
	var p := root.get_final_transform() * s.cam.unproject_position(s.board_view.top_center(h))
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		Input.parse_input_event(mb)
		await process_frame


# ---------------------------------------------------------------- scenes

## Demeter -> foe -> rink (3) -> pillar: the Charge shoves the foe onto the
## ice, it slides and slams the pillar.
func _slide() -> void:
	var d0 := _west(C, 3)                            # Demeter charges 3: ends on C, Rui lands C+1
	var foe := _west(C, 2)
	var rink: Array = [_east(C, 1), _east(C, 2)]
	var pil := _east(C, 3)
	_reset({ demeter: d0, rui: foe })
	_lay(rink, -1, 2)
	_lay([pil], -3)
	s.battle.tiles.apply([pil], "ice", demeter.id)
	s.board_view.refresh_tiles(true)
	await _turn(demeter)
	await _cam(C, -10.0, 19.0, 50.0)
	s.ui.skill_chosen.emit("charge", "ice")
	await _wait(0.3)
	await _move_mouse(foe)
	await _wait(0.8)
	var sim: Dictionary = s.readability.preview.last
	print("slide preview: moves ", sim.get("moves", []), " slams ", sim.get("slams", []))
	await _shot("v3_icewater_slide")
	await _click(foe)
	await _wait(0.5)
	s._on_action("confirm")
	var t := 0
	var shot := false
	while (s._busy or t < 5) and t < 4000:
		await process_frame
		t += 1
		if not shot and s.battle.history.any(func(e): return str(e.type) == "slam") \
				and not s._queue.any(func(e): return str(e.type) == "slam"):
			await _wait(0.12)
			await _shot("v3_icewater_slam")
			shot = true
	print("slam: rui at ", rui.pos, " hp ", rui.hp, "/", rui.max_hp(), " pillar ", s.battle.tiles.is_pillar(pil))
	if not shot:
		await _shot("v3_icewater_slam")


## Kira west of a rink of 4: hover the hex past it.
func _walk() -> void:
	var k0 := _west(C, 2)
	var rink: Array = [_east(k0, 1), _east(k0, 2), _east(k0, 3), _east(k0, 4)]
	_reset({ kira: k0, bob: BWHex.neighbors(_east(C, 3))[1] })
	_lay(rink, -1, 2)
	s.board_view.refresh_tiles(true)
	await _turn(kira)
	await _cam(_east(k0, 3), -25.0, 14.0, 55.0)
	var r := s.battle.reachable(kira)
	var end := Vector2i(-1, -1)
	for h in r:
		if r[h].has("slide") and (end.x < 0 or BWHex.distance(h, k0) > BWHex.distance(end, k0)):
			end = h
	print("walk: slide ends ", end, " ", r.get(end, {}).get("slide", {}).get("stop", ""))
	await _move_mouse(end)
	await _wait(0.6)
	await _shot("v3_icewater_walk")


## Wilona 3 west of a foe, a pillar between.
func _pillar() -> void:
	var w0 := _west(C, 2)
	var mid := C
	var foe := _east(C, 2)
	_reset({ wilona: w0, gail: foe })
	_lay([mid], -3)
	s.battle.tiles.apply([mid], "ice", wilona.id)
	s.board_view.refresh_tiles(true)
	await _turn(wilona)
	await _cam(mid, -60.0, 13.0, 45.0)
	print("pillar: los ", s.battle.board.has_los(w0, foe), " in range ", s.battle.in_range(wilona, gail))
	await _move_mouse(mid)
	await _wait(0.7)
	print("card: ", s.readability.card_text())
	await _shot("v3_icewater_pillar")


func _lake() -> Array:
	var out: Array = []
	for h in BWHex.area(C, 2):
		out.append(h)
	for h in [_east(C, 3), _east(_east(C, 3), 1)]:
		out.append(h)
	return out


## Fire on the lake: steam over it all.
func _steam() -> void:
	var lake := _lake()
	var k0 := _west(C, 3)
	_reset({ kira: k0, bob: BWHex.neighbors(C)[0], gail: BWHex.neighbors(C)[4] })
	_lay(lake, -2)
	s.battle.paint([_east(C, 2)], "fire", kira)
	s.board_view.refresh_tiles()
	await _turn(kira)
	await _cam(C, -20.0, 15.0, 50.0)
	await _move_mouse(bob.pos)
	await _wait(1.0)
	print("steam: ", s.battle.tiles.steam.size(), " hexes; kira reaches bob ", s.battle.in_range(kira, bob), "; card ", s.readability.card_text())
	await _shot("v3_icewater_steam")


## Thunder on the lake: the preview, then the live field after two turn starts.
func _shock() -> void:
	var lake := _lake()
	var k0 := _west(C, 3)
	_reset({ kira: k0, bob: C, gail: _east(C, 3) })
	_lay(lake, -2)
	s.board_view.refresh_tiles(true)
	await _turn(kira)
	await _cam(C, -20.0, 15.0, 52.0)
	s.ui.skill_chosen.emit("saturate", "thunder")
	await _wait(0.3)
	await _move_mouse(C)
	await _wait(0.8)
	var sim: Dictionary = s.readability.preview.last
	print("shock preview: kinds ", sim.get("hexes", {}).values().map(func(r): return r.kinds))
	await _shot("v3_icewater_shock_preview")
	s.ui.hide_forecast()
	s.battle.paint([C], "thunder", kira)
	s.board_view.refresh_tiles()
	for i in 2:
		s.battle.queue = [bob]
		s.battle.turn_index = 0
		s.battle._begin_turn()
	bob.statuses = {}
	s._queue.clear()
	s._views[bob.id].refresh()
	await _turn(kira)
	kira.acted = true                               # no attack preview: the hover shows the tile card
	s._show_options()
	s.board_view.refresh_tiles()
	await _cam(C, -20.0, 14.0, 52.0)
	await _move_mouse(_east(C, 1))
	await _wait(0.3)
	await _move_mouse(C)
	await _wait(1.0)
	print("shock card: ", s.readability.card_text())
	await _shot("v3_icewater_shock")


## Ice on the lake (two water 3 beside the cast hex): radius 1 rinks.
func _rink() -> void:
	var lake := _lake()
	var k0 := _west(C, 3)
	_reset({ kira: k0 })
	_lay(lake, -1)
	for h in [BWHex.neighbors(C)[0], BWHex.neighbors(C)[2], BWHex.area(C, 2)[0]]:
		s.battle.tiles.entries[h].h = -3
	s.battle.paint([C], "ice", kira)
	s.board_view.refresh_tiles()
	await _turn(kira)
	await _cam(C, -20.0, 14.0, 52.0)
	await _move_mouse(BWHex.neighbors(C)[4])
	await _wait(1.2)
	print("rink: pillars ", s.battle.tiles.pillars.keys(), " card ", s.readability.card_text())
	await _shot("v3_icewater_rink")

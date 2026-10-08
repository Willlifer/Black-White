extends SceneTree
## D266 review renders of the ice/water spine on the real combat screen (needs
## a window); D397-D401 replaced the slide scenes with Unsteady footing:
##   RES=1920x1080 [SHOTS=<dir>] [ONLY=unsteady,overfreeze,pillar,douse,shock,pool] godot --path . --script res://tools/icewater_shots.gd
## ice2_unsteady_hover.png  Wilona hovers Gail standing on glaze: the crack
##                         ring under Gail, the damage sticker
## ice2_unsteady_forecast.png  the confirm box: "Unsteady footing -10 avoid /
##                         -15 glance" lines and Shatter
## ice2_unsteady_tile.png  the tile hover on a glazed hex: the Unsteady line
## ice2_overfreeze.png     an ice Surge on glazed water: the burst done, the
##                         seven hexes left glazed (no rink, no pillar), the
##                         units on them Unsteady (crack rings), the tile card
## v3_icewater_pillar.png  an ice pillar between Wilona's bow and a foe: no
##                         shot (no pulse on the foe), the pillar's tile card
## sys5_douse_hiss|after.png  D421: fire on two lake hexes douses them (the
##                         hiss puff, then the cleared hexes; no steam)
## v3_icewater_shock_preview.png  a thunder Saturate aimed at the lake: the
##                         radius-1 field outlined, "ELECTRIFIED"
## v3_icewater_shock.png   the field live after two of the foe's turn starts:
##                         the crackling outline, the timer pips, the card
##                         with the ramp ("next shock immune")
## ice2_pool_glaze.png     ice on the lake: radius 1 glazed with the sheen,
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
	for k in ["unsteady", "overfreeze", "pillar", "douse", "shock", "pool"]:
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
	for d in [b.tiles.pillars, b.tiles.fields, b.tiles.shock]:
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

## Wilona 3 west of Gail, Gail on glaze: hover Gail for the forecast.
func _unsteady() -> void:
	var w0 := _west(C, 2)
	var foe := _east(C, 1)
	_reset({ wilona: w0, gail: foe, rui: _east(C, 4) })
	_lay([foe, _east(C, 2), BWHex.neighbors(foe)[1], BWHex.neighbors(foe)[5]], -1, 2)
	s.board_view.refresh_tiles(true)
	await _turn(wilona)
	await _cam(C, -25.0, 12.0, 50.0)
	await _move_mouse(foe)
	await _wait(1.2)
	var fc := s.battle.forecast_basic(wilona, gail)
	print("unsteady: notes ", fc.notes, " avoid ", fc.avoid.value, " glance ", fc.glance.value,
		" rings ", s.ks_view.shown.get("unsteady", []))
	await _shot("ice2_unsteady_hover")
	await _click(foe)                               # the confirm box: the forecast's named lines
	await _wait(1.0)
	await _shot("ice2_unsteady_forecast")
	s.ui.hide_forecast()
	s._pending_target = null
	await _wait(0.3)
	wilona.acted = true                             # no attack preview: the hover shows the tile card
	s._show_options()
	await _move_mouse(_east(C, 2))
	await _wait(0.3)
	await _move_mouse(foe)
	await _wait(1.0)
	print("unsteady card: ", s.readability.card_text())
	await _shot("ice2_unsteady_tile")


## Glazed water round C, Kira's ice on it: Overfreeze bursts and leaves glaze.
func _overfreeze() -> void:
	var k0 := _west(C, 3)
	_reset({ kira: k0, bob: C, gail: BWHex.neighbors(C)[1], rui: _east(C, 4) })
	var lake: Array = []
	for h in BWHex.area(C, 1):
		lake.append(h)
	_lay(lake, -1, 1)
	s.board_view.refresh_tiles(true)
	await _turn(kira)
	await _cam(C, -20.0, 13.0, 52.0)
	var r := s.battle.paint([C], "ice", kira)
	s.board_view.refresh_tiles()
	for u in [bob, gail]:
		s._views[u.id].refresh()
	kira.acted = true
	s._show_options()
	await _move_mouse(_east(C, 1))
	await _wait(0.3)
	await _move_mouse(BWHex.neighbors(C)[0])
	await _wait(1.2)
	var glazed := lake.filter(func(h): return s.battle.tiles.is_glazed(h))
	print("overfreeze: ", r.get("overfreeze", []), " glazed ", glazed.size(), "/7 pillars ", s.battle.tiles.pillars.size(),
		" bob unsteady ", BWUnsteady.unsteady(s.battle, bob), " card ", s.readability.card_text())
	await _shot("ice2_overfreeze")


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


## D421: fire on the lake douses the hex it lands on (no steam): the small
## hiss puff mid-play, the cleared hex in the lake.
func _douse() -> void:
	var lake := _lake()
	var k0 := _west(C, 3)
	_reset({ kira: k0, bob: BWHex.neighbors(C)[0], gail: BWHex.neighbors(C)[4] })
	_lay(lake, -2)
	s.board_view.refresh_tiles(true)
	await _turn(kira)
	await _cam(C, -20.0, 15.0, 50.0)
	s.battle.paint([_east(C, 2), C], "fire", kira)
	var pe: Dictionary = {}
	for e in s.battle.history:
		if str(e.get("type", "")) == "paint":
			pe = e
	s.board_view.on_tile_event(pe)
	await _wait(0.12)
	print("douse: ", pe.get("doused", []), "; kira reaches bob ", s.battle.in_range(kira, bob))
	await _shot("sys5_douse_hiss")
	await _wait(1.0)
	await _shot("sys5_douse_after")


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


## Ice on the lake (two water 3 beside the cast hex): radius 1 glazes.
func _pool() -> void:
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
	print("pool glaze: pillars ", s.battle.tiles.pillars.keys(), " card ", s.readability.card_text())
	await _shot("ice2_pool_glaze")

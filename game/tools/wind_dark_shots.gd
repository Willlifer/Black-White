extends SceneTree
## D269-D276 review renders of wind and dark on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=fields,toggle,cleave,wall,rot,gravity] godot --path . --resolution 1920x1080 --script res://tools/wind_dark_shots.gd
## → design/art/v3_wind_fields.png (a gust, a vortex and a becalm field),
##   v3_wind_toggle.png (the forecast's mode toggle + the pull arrows),
##   v3_wind_becalm_preview.png (the toggle flipped to Becalm: the preview's marks),
##   v3_wind_cleave_1..3.png (a wind Cleave: aimed, the pull, the swing),
##   v3_wind_wall.png, v3_dark_rot.png (marks over units + the card), v3_dark_gravity.png.
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()          # D301: no leftover "Battle start"
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _row(roster: Array, wc: String, el: String, skip: Array) -> Dictionary:
	for r in roster:
		if str(r.get("weapon_class", "")) == wc and not str(r.id) in skip:
			var d: Dictionary = r.duplicate()
			d["element"] = el
			skip.append(str(r.id))
			return d
	var any: Dictionary = roster[skip.size()].duplicate()
	any["weapon_class"] = wc
	any["weapon_model"] = wc
	any["element"] = el
	skip.append(str(any.id))
	return any


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	var roster := BWData.table("roster")
	var used: Array = []
	var players: Array = [BWUnit.from_roster(_row(roster, "staff", "wind", used)),
		BWUnit.from_roster(_row(roster, "axe", "wind", used)),
		BWUnit.from_roster(_row(roster, "staff", "dark", used))]
	var enemies: Array = []
	for wc in ["sword", "lance", "bow"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in players + enemies:
		u.stats["con"] = 40                     # nobody falls while we look
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	var f := _flat_centre(b)
	var stf: BWUnit = players[0]
	var axe: BWUnit = players[1]
	var dk: BWUnit = players[2]
	# a clean stage: everyone placed round the focus
	var spots := _open(b, f, 14)
	_place(stf, spots[0])
	_place(axe, spots[1])
	_place(dk, spots[2])
	for i in enemies.size():
		_place(enemies[i], spots[3 + i])
	s.rig.pitch = deg_to_rad(50.0)
	s.rig.dist = 17.0

	if _want("fields"):
		var c: Vector2i = spots[6]
		var hs := _open(b, c, 3)
		stf.wind_mode = "gust"
		b.paint([hs[0]], "wind", stf)
		stf.wind_mode = "vortex"
		b.paint([hs[1]], "wind", stf)
		stf.wind_mode = "becalm"
		b.paint([hs[2]], "wind", stf)
		await _settle()
		var mid := (BWLook.world(hs[0], 0) + BWLook.world(hs[1], 0) + BWLook.world(hs[2], 0)) / 3.0
		s.rig.follow(mid, true)
		s.rig.dist = 13.0
		await _wait(0.8)
		print("fields: ", s.wind_view.shown.fields)
		await _shot("v3_wind_fields")
		b.tiles.entries.erase(hs[0])
		b.tiles.entries.erase(hs[1])
		b.tiles.entries.erase(hs[2])
		s.board_view.refresh_tiles()

	if _want("toggle"):
		_turn(stf)
		var t: Vector2i = enemies[0].pos
		_place(enemies[1], _free_near(b, t, 2))
		stf.wind_mode = "vortex"
		var tgt := _surge_target(b, stf, enemies[0])
		s._skill = { "key": "surge", "element": "wind", "row": BWSkills.get_skill("surge") }
		s._aim_skill(stf, tgt)
		s.rig.follow(BWLook.world(tgt, b.board.elevation(tgt)), true)
		s.rig.dist = 15.0
		await _wait(1.0)
		print("toggle: forecast open ", s.ui.forecast_open(), " preview ", s.readability.preview.last.get("moves", []))
		await _shot("v3_wind_toggle")
		var bt := s.ui.find_child("Mode_becalm", true, false) as Button
		if bt:
			bt.button_pressed = true
			bt.pressed.emit()
		await _wait(1.0)
		print("becalm mode: ", stf.wind_mode)
		await _shot("v3_wind_becalm_preview")
		s._on_action("cancel")
		s._on_action("cancel")
		await _wait(0.3)

	if _want("cleave"):
		_turn(axe)
		var e := BWHex.neighbors(axe.pos)[0]
		var far := BWHex.neighbors(e)[0]
		for h in [e, far]:
			if not b.board.is_passable(h):
				print("cleave: blocked at ", h)
		if b.unit_at(e) != null and b.unit_at(e) != enemies[2]:
			_place(b.unit_at(e), _free_near(b, axe.pos, 4))
		_place(enemies[2], far)
		axe.wind_mode = "vortex"
		s._skill = { "key": "cleave", "element": "wind", "row": BWSkills.get_skill("cleave") }
		s._aim_skill(axe, e)
		s.rig.follow(BWLook.world(e, b.board.elevation(e)), true)
		s.rig.dist = 11.0
		await _wait(1.0)
		await _shot("v3_wind_cleave_1")
		s._on_action("confirm")
		await _wait(0.22)
		await _shot("v3_wind_cleave_2")
		var tt := 0.0
		while not b.history.any(func(x): return x.type == "skill" and x.skill == "cleave") and tt < 3.0:
			await _wait(0.05)
			tt += 0.05
		await _wait(0.55)
		await _shot("v3_wind_cleave_3")
		await _idle()

	if _want("wall"):
		_turn(stf)
		BWKeystones.grant(stf, "wind_wall")        # D293: the keystone
		stf.cooldowns.clear()
		var start := Vector2i(-1, -1)
		for h in _open(b, stf.pos, 12):
			if BWHex.distance(stf.pos, h) == 2 and not BWWind.wall_dirs(b, h).is_empty():
				start = h
				break
		var ev := b.use_skill(stf, "wind_wall", "", start)
		print("wall: ", BWWind.wall_hexes(b), " ", not ev.is_empty())
		s._after_events()
		await _wait(1.2)
		s.rig.follow(BWLook.world(start, b.board.elevation(start)), true)
		s.rig.pitch = deg_to_rad(28.0)
		s.rig.dist = 12.0
		await _wait(0.8)
		await _shot("v3_wind_wall")
		s.rig.pitch = deg_to_rad(50.0)

	if _want("rot") or _want("gravity"):
		_turn(dk)
		var pit: Vector2i = enemies[0].pos
		var area: Array = [pit] + BWHex.neighbors(pit).slice(0, 2)
		area = area.filter(func(h): return b.tiles.can_hold(h))
		b.paint(area, "dark", dk, 3)
		BWCurse.add_rot(b, enemies[0], 3, dk.id)
		BWCurse.add_rot(b, enemies[1], 1, dk.id)
		s._after_events()
		await _wait(1.0)
		s.board_view.refresh_tiles()
		s.rig.follow(BWLook.world(pit, b.board.elevation(pit)), true)
		s.rig.dist = 11.0
		s.ui.set_card(enemies[0], b.tiles, b.current())
		await _wait(0.8)
		print("rot labels: ", s.wind_view.rot_text(enemies[0].id), " / ", s.wind_view.rot_text(enemies[1].id), " gravity ", s.wind_view.shown.gravity)
		if _want("rot"):
			await _shot("v3_dark_rot")
		if _want("gravity"):
			_place(enemies[0], _free_near(b, pit, 3))
			s.ui.set_card(null)
			s.rig.dist = 9.0
			s.rig.pitch = deg_to_rad(62.0)
			await _wait(0.8)
			await _shot("v3_dark_gravity")
	quit()


# ---------------------------------------------------------------- helpers

func _idle() -> void:
	var t := 0.0
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and t < 60.0:
		await _wait(0.2)
		t += 0.2


func _settle() -> void:
	s.board_view.refresh_tiles()
	await _wait(0.3)


## Hand the turn to `u` now (review only).
func _turn(u: BWUnit) -> void:
	var b := s.battle
	b.queue = [u] + b.queue.filter(func(x): return x != u)
	b.turn_index = 0
	b._begin_turn()
	s._queue.clear()
	s._skill = {}
	u.acted = false
	u.moved = false
	s.ui.set_acting(u, b.tiles)
	s._show_options()


func _place(u: BWUnit, h: Vector2i) -> void:
	if h == Vector2i(-1, -1):
		return
	u.pos = h
	var v: Node3D = s._views[u.id]
	v.position = s._unit_pos(h)


## The hex with the most level, open ground within 2 (ties: nearest the focus).
func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 2):
			if b.board.is_passable(a) and b.board.elevation(a) == b.board.elevation(h):
				k += 1
		k = k * 100 - BWHex.distance(h, b.board.camera_focus)
		if k > best_k:
			best_k = k
			best = h
	return best


## Up to n free passable hexes round `c`, nearest first.
func _open(b: BWBattle, c: Vector2i, n: int) -> Array:
	var out: Array = []
	for r in 9:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out.size() >= n:
				return out
			if b.board.is_passable(h) and not b.board.blocked(h) and absi(b.board.elevation(h) - b.board.elevation(c)) <= 1 and b.unit_at(h) == null:
				out.append(h)
	return out


func _free_near(b: BWBattle, c: Vector2i, r: int) -> Vector2i:
	for h in _open(b, c, 30):
		if BWHex.distance(c, h) == r or BWHex.distance(c, h) >= 2:
			return h
	return Vector2i(-1, -1)


## A Surge hex beside the foe, so it is pulled into the centre.
func _surge_target(b: BWBattle, u: BWUnit, foe: BWUnit) -> Vector2i:
	var targets := b.skill_targets(u, "surge", "wind")
	for h in BWHex.neighbors(foe.pos):
		if h in targets and b.unit_at(h) == null:
			return h
	return foe.pos

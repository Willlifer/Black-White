extends SceneTree
## D343-D346 polish pass 3 review renders (needs a window):
##   [SHOTS=<dir>] [ONLY=sixes,rot,floaters,threes] godot --path . --resolution 1920x1080 --script res://tools/polish3_shots.gd
## polish3_6v6_midfight.png  12 units on Commons at round 3: names only where they fit (D344)
## polish3_floaters.png      a word-floater pile on the crowd: Chain, immune, a status, two numbers
## polish3_rot.png           Rot 1 and Rot 3 at the 6v6 game distance (D346)
## polish3_3v3_names.png     a 3v3 at a player turn: the names still read
## polish3_rot_3v3.png       Rot 1 and Rot 3 at the 3v3 distance
## (the chain + immune dive and the dark squall come from final_shots / squall_shots with SHOTS=)
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _to_player_turn(min_cycle: int) -> void:
	while s.battle.cycle < min_cycle and not s.battle.over:
		await _wait(0.2)
	s.autoplay = false
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and not s.battle.over:
		await _wait(0.2)
	await _wait(1.0)


func _go() -> void:
	BWSettings.put("cutscenes", "fast")
	BWMusic.ensure(root)
	if _want("sixes") or _want("rot") or _want("floaters"):
		await _sixes()
	if _want("threes"):
		await _threes()
	quit()


func _sixes() -> void:
	const P := preload("res://tools/sixes_perf.gd")
	var sd := P.sides(6, 7)
	s = BWCombatScreen.new()
	s.configure("res://maps/commons.json", sd[0], sd[1], [], 7)
	s.autoplay = true
	root.add_child(s)
	await _wait(2.2)
	await _to_player_turn(3)
	BWHPBar3D.hover_unit = null
	await _wait(0.3)
	print("names: ", s.name_labels.shown)
	if OS.get_environment("DBG") != "":
		for id in s._views:
			var vv = s._views[id]
			if vv is BWUnitView:
				print(id, " bar ", vv._hp_bar.screen_rect(s.cam), " name ", BWNameLabels._rect(s.cam, vv._label, vv._label.pixel_size), " vis ", vv._label.visible, " fov ", s.cam.fov, " proj ", s.cam.projection)
	if _want("sixes"):
		await _shot("polish3_6v6_midfight")
	var b := s.battle
	var cur := b.current()
	# the crowd: the three living units nearest the acting one
	var near: Array = b.units.filter(func(u): return u.alive() and u != cur and not BWObelisk.is_objective(u))
	near.sort_custom(func(a, c): return BWHex.distance(a.pos, cur.pos) < BWHex.distance(c.pos, cur.pos))
	if _want("floaters") and near.size() >= 3:
		var v0: BWUnitView = s._views[near[0].id]
		var v1: BWUnitView = s._views[near[1].id]
		var v2: BWUnitView = s._views[near[2].id]
		s.feel.float_number(v0, "-31", { "damage": 31, "hit": true })
		s._float_text(v0, "Chain", BWLook.glow_color("thunder"), 0.6)
		s._float_text(v0, "immune", Color.WHITE, 0.6)
		s.feel.float_number(v1, "-88", { "damage": 88, "hit": true, "crit": true })
		s._float_status(v1, "pinned", "Pinned", "no move")
		s._float_text(v1, "SLAM", Color.WHITE, 0.7)
		s._float_text(v2, "Chain", BWLook.glow_color("thunder"), 0.6)
		s._float_text(v2, "-12", BWLook.glow_color("thunder"), 0.8)
		await _wait(0.28)
		await _shot("polish3_floaters")
		await _wait(1.5)
	if _want("rot") and near.size() >= 2:
		var foes: Array = near.filter(func(u): return u.team != cur.team)
		var a: BWUnit = foes[0] if foes.size() > 0 else near[0]
		var c: BWUnit = foes[1] if foes.size() > 1 else near[1]
		BWCurse.add_rot(b, a, 1, cur.id, "dark")
		BWCurse.add_rot(b, c, 3, cur.id, "dark")
		s.rig.follow(s._views[a.id].global_position, true)
		await _wait(1.2)
		print("rot: ", s.wind_view.rot_text(a.id), " / ", s.wind_view.rot_text(c.id))
		await _shot("polish3_rot")
	s.queue_free()
	await process_frame


func _threes() -> void:
	const P := preload("res://tools/sixes_perf.gd")
	var sd := P.sides(6, 7)
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", (sd[0] as Array).slice(0, 3), (sd[1] as Array).slice(0, 3), [], 7)
	s.autoplay = true
	root.add_child(s)
	await _wait(2.2)
	await _to_player_turn(2)
	BWHPBar3D.hover_unit = null
	await _wait(0.3)
	print("names 3v3: ", s.name_labels.shown)
	await _shot("polish3_3v3_names")
	var foes: Array = s.battle.units.filter(func(u): return u.alive() and u.team != s.battle.current().team)
	if foes.size() >= 2:
		BWCurse.add_rot(s.battle, foes[0], 1, s.battle.current().id, "dark")
		BWCurse.add_rot(s.battle, foes[1], 3, s.battle.current().id, "dark")
		await _wait(0.6)
		print("rot 3v3: ", s.wind_view.rot_text(foes[0].id), " / ", s.wind_view.rot_text(foes[1].id))
		await _shot("polish3_rot_3v3")
	s.queue_free()
	await process_frame

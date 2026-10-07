extends SceneTree
## D371–D374 review renders (needs a window):
##   RES=1920x1080 [SHOTS=<dir>] [ONLY=pick,lance,bow] godot --path . --script res://tools/jump2_shots.gd
## jump2_pick.png    a bow's expertise pick offering HighGrounder (selected)
## jump2_lance.png   Bob (lance, jump 4, Swift for the 5 a 4-level step costs)
##                   beside a 4-level block: the walk rim climbs onto it, the
##                   hover names "Climb 4 (Lance)"
## jump2_bow.png     Gail (bow) with the HighGrounder pick climbs a 3-level
##                   ledge; her card lists "HighGrounder"
var out := ""
var s: BWCombatScreen
var bob: BWUnit
var gail: BWUnit
var foes: Array = []
const MAP := "user://jump2_shots.json"
const BLOCK := Vector2i(9, 3)          # elevation 4
const LEDGE := Vector2i(9, 8)          # elevation 3


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	_go.call_deferred()


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


func _write_map() -> void:
	var cells: Array = []
	for r in 11:
		for q in 14:
			var h := Vector2i(q, r)
			var e := 0
			if BWHex.distance(h, BLOCK) <= 1:
				e = 4
			elif BWHex.distance(h, LEDGE) <= 1:
				e = 3
			cells.append({ "q": q, "r": r, "terrain": "neutral", "elevation": e })
	var d := { "name": "Jump review", "cols": 14, "rows": 11, "deploy_count": 3, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 2], [0, 4]], "enemy": [[13, 0], [13, 4], [13, 10]] } }
	var f := FileAccess.open(MAP, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _go() -> void:
	var wres := OS.get_environment("RES")
	if wres.contains("x"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3:
			await process_frame
		DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
		for i in 3:
			await process_frame
	var only := OS.get_environment("ONLY").split(",", false)
	if only.is_empty() or "pick" in only:
		await _pick()
	if only.is_empty() or "lance" in only or "bow" in only:
		BWMusic.ensure(root)
		BWSettings.put("cutscenes", "minimal")
		_write_map()
		bob = BWRosterKits.unit("bob")
		gail = BWRosterKits.unit("gail")
		gail.known_skills.append(BWWeaponMove.HIGH_GROUNDER)
		foes = [BWRosterKits.unit("rui"), BWRosterKits.unit("kai"), BWRosterKits.unit("opus")]
		for u in [bob, gail]:
			u.stats["spd"] = 30
		s = BWCombatScreen.new()
		s.configure(MAP, [bob, gail], foes, [], 3)
		root.add_child(s)
		await _wait(7.0)
		while s._busy:
			await process_frame
		if only.is_empty() or "lance" in only:
			await _climb(bob, BLOCK, "jump2_lance", true)
		if only.is_empty() or "bow" in only:
			await _climb(gail, LEDGE, "jump2_bow", false)
	quit()


## A bow unit whose expertise pick offers HighGrounder: the picker, it chosen.
func _pick() -> void:
	var v := BWRosterKits.unit("gail")
	v.expertise["bow"] = 10
	var req := { "kind": "skill", "weapon": "bow" }
	for sd in 200:
		v.pick_seed = sd
		if ("passive:" + BWWeaponMove.HIGH_GROUNDER) in BWPicks.offered(v, req):
			break
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var pk := BWPicker.new(v, req, "day 3")
	root.add_child(pk)
	await _wait(0.5)
	for i in pk.options.size():
		if str(pk.options[i].kind) == "passive":
			pk.select(i)
	await _wait(0.3)
	print("pick options: %s" % str(pk.options.map(func(o): return o.id)))
	await _shot("jump2_pick")
	pk.queue_free()
	bg.queue_free()
	await _wait(0.2)


func _west(h: Vector2i, n: int) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[3]
	return h


func _reset(placed: Dictionary) -> void:
	var parks := [Vector2i(0, 10), Vector2i(1, 10), Vector2i(13, 10), Vector2i(13, 9), Vector2i(12, 10)]
	var i := 0
	for u in [bob, gail] + foes:
		var at: Vector2i = placed.get(u, parks[i])
		i += 1
		u.pos = at
		u.statuses = {}
		u.hp = u.max_hp()
		s._views[u.id].position = s.board_view.top_center(at)
		s._views[u.id].refresh()
	s.board_view.refresh_tiles(true)
	s._face_all()


func _turn(u: BWUnit, swift: bool) -> void:
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
	if swift:
		u.statuses["swift"] = { "armed": true }
	s._queue.clear()
	s.ui.set_acting(u, s.battle.tiles)
	s._show_options()
	s.ui.set_actions_visible(true)
	await _wait(0.4)


func _cam(at: Vector2i) -> void:
	s.rig.follow(s.board_view.top_center(at), true)
	s.rig.yaw = deg_to_rad(-20.0)
	s.rig.dist = 15.0
	s.rig.pitch = deg_to_rad(42.0)
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


## A climber 2 west of the block centre: hover the block's west edge (one step up).
func _climb(u: BWUnit, top: Vector2i, name: String, swift: bool) -> void:
	var at := _west(top, 2)
	_reset({ u: at })
	await _turn(u, swift)
	s._show_options()
	await _cam(top)
	var r := s.battle.reachable(u)
	var edge := _west(top, 1)
	print("%s at %s (jump %d, move %d): edge %s reach=%s cost=%s" % [u.name, at, BWWeaponMove.jump(u), u.move_range(),
		edge, r.has(edge), str(r.get(edge, {}).get("cost", "-"))])
	await _move_mouse(edge)
	await _wait(0.6)
	await _shot(name)

extends SceneTree
## D359–D364 review renders on the real combat screen (needs a window):
##   RES=1920x1080 [SHOTS=<dir>] [ONLY=lance,bow,axe,leap] godot --path . --script res://tools/move_shots.gd
## A generated 14×11 test board (user://move_shots.json): two 2-level
## plateaus, a mud strip, a 2-level tower.
## move_lance.png   Bob (lance) beside a 2-level plateau: the walk rim climbs
##                  onto it (D371: every class climbs 2 now; jump 4 is
##                  tools/jump2_shots.gd)
## move_bow.png     Gail (bow): the same climb
## move_axe.png     Burt (axe) before the mud: the rim crosses it at 1 a hex,
##                  the hover names "mud at 1 (Rough-Footed)"
## move_leap.png    Will (daggers) on the tower aims Daggerleap 4 hexes down:
##                  the radius-2 landing ring, "High ground" in the hint
var out := ""
var s: BWCombatScreen
var bob: BWUnit
var gail: BWUnit
var burt: BWUnit
var will: BWUnit
var foes: Array = []
const MAP := "user://move_shots.json"
const PLAT_A := Vector2i(10, 2)
const PLAT_B := Vector2i(10, 8)
const TOWER := Vector2i(3, 8)


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


func _unit(id: String) -> BWUnit:
	var u := BWRosterKits.unit(id)
	for el in ["fire", "ice", "thunder", "water"]:
		u.affinity[el] = maxi(int(u.affinity.get(el, 0)), 10)
	return u


func _write_map() -> void:
	var cells: Array = []
	for r in 11:
		for q in 14:
			var h := Vector2i(q, r)
			var t := "neutral"
			var e := 0
			if BWHex.distance(h, PLAT_A) <= 1 or BWHex.distance(h, PLAT_B) <= 1 or h == TOWER:
				e = 2
			elif q in [4, 5] and r <= 5:
				t = "muddy"
			cells.append({ "q": q, "r": r, "terrain": t, "elevation": e })
	var d := { "name": "Move review", "cols": 14, "rows": 11, "deploy_count": 4, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 2], [0, 4], [0, 6]], "enemy": [[13, 0], [13, 4], [13, 10]] } }
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
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	_write_map()
	bob = _unit("bob")
	gail = _unit("gail")
	burt = _unit("burt")
	will = _unit("will")
	will.known_skills.append("daggerleap")
	foes = [_unit("rui"), _unit("kai"), _unit("opus")]
	for u in [bob, gail, burt, will]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure(MAP, [bob, gail, burt, will], foes, [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	var only := OS.get_environment("ONLY").split(",", false)
	for k in ["lance", "bow", "axe", "leap"]:
		if only.is_empty() or k in only:
			await call("_" + k)
	quit()


func _west(h: Vector2i, n: int) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[3]
	return h


func _east(h: Vector2i, n: int) -> Vector2i:
	for i in n:
		h = BWHex.neighbors(h)[0]
	return h


func _reset(placed: Dictionary) -> void:
	var parks := [Vector2i(0, 10), Vector2i(1, 10), Vector2i(2, 10), Vector2i(13, 10), Vector2i(13, 9), Vector2i(12, 10), Vector2i(0, 9)]
	var i := 0
	for u in [bob, gail, burt, will] + foes:
		var at: Vector2i = placed.get(u, parks[i])
		i += 1
		u.pos = at
		u.statuses = {}
		u.hp = u.max_hp()
		s._views[u.id].position = s.board_view.top_center(at)
		s._views[u.id].refresh()
	s.board_view.refresh_tiles(true)
	s._face_all()


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


## A climber 2 west of a plateau centre: hover it (edge +3, flat +1 = 4).
func _climb(u: BWUnit, plat: Vector2i, name: String) -> void:
	var at := _west(plat, 2)
	_reset({ u: at })
	await _turn(u)
	await _cam(plat, -20.0, 15.0, 48.0)
	var r := s.battle.reachable(u)
	print("%s at %s: plateau centre %s reach=%s edge=%s" % [u.name, at, plat, r.has(plat), r.has(_west(plat, 1))])
	await _move_mouse(plat if r.has(plat) else _west(plat, 1))
	await _wait(0.6)
	await _shot(name)


func _lance() -> void:
	await _climb(bob, PLAT_A, "move_lance")


func _bow() -> void:
	await _climb(gail, PLAT_B, "move_bow")


## Burt west of the mud: the rim crosses it.
func _axe() -> void:
	var at := Vector2i(2, 3)
	_reset({ burt: at })
	await _turn(burt)
	await _cam(Vector2i(5, 3), -10.0, 15.0, 55.0)
	var r := s.battle.reachable(burt)
	var far := Vector2i(6, 3)
	print("axe: (6,3) cost %s" % str(r.get(far, {}).get("cost", "-")))
	await _move_mouse(far if r.has(far) else Vector2i(5, 3))
	await _wait(0.6)
	await _shot("move_axe")


## Will on the tower aims Daggerleap 4 hexes east, down onto two foes.
func _leap() -> void:
	var land := _east(TOWER, 4)
	_reset({ will: TOWER, foes[0]: _east(land, 1), foes[1]: BWHex.neighbors(_east(land, 2))[1] })
	await _turn(will)
	await _cam(_east(TOWER, 2), -15.0, 16.0, 45.0)
	s.ui.skill_chosen.emit("daggerleap", will.element)
	await _wait(0.3)
	print("leap targets include %s: %s" % [land, land in s.battle.skill_targets(will, "daggerleap", will.element)])
	await _move_mouse(land)
	await _wait(0.8)
	await _shot("move_leap")

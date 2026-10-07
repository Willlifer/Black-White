extends SceneTree
## D375–D378 review renders (needs a window):
##   RES=1920x1080 [SHOTS=<dir>] [ONLY=updraft,obelisks] godot --path . --script res://tools/updraft_shots.gd
## updraft_ally.png      Gail (bow, no pick) starts on Bob's gale (Bob holds
##                       Tailwind): jump 3, the walk rim climbs a 3-level
##                       ledge for 1 move; the hover names the Updraft
## updraft_holder.png    Bob (lance) with Tailwind: jump 4 + 1 = 5, a 5-level
##                       block for 1 move; the hover names the Updraft
## obelisk_shared_plate.png   the Obelisks after 70 damage on the Lantern:
##                       the plate's one bar "The Stones 150 / 220", both
##                       stones' bars on the board at the same 150
## obelisk_shared_card.png    the untouched Well's hover card: HP 150 / 220 (shared)
var out := ""
var s: BWCombatScreen
var bob: BWUnit
var gail: BWUnit
var foes: Array = []
const MAP := "user://updraft_shots.json"
const BLOCK := Vector2i(9, 3)          # elevation 5
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
				e = 5
			elif BWHex.distance(h, LEDGE) <= 1:
				e = 3
			cells.append({ "q": q, "r": r, "terrain": "neutral", "elevation": e })
	var d := { "name": "Updraft review", "cols": 14, "rows": 11, "deploy_count": 3, "cells": cells,
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
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	if only.is_empty() or "updraft" in only:
		await _updraft()
	if only.is_empty() or "obelisks" in only:
		await _obelisks()
	quit()


func _updraft() -> void:
	_write_map()
	bob = BWRosterKits.unit("bob")
	gail = BWRosterKits.unit("gail")
	bob.affinity["wind"] = maxi(int(bob.affinity.get("wind", 0)), 10)
	bob.perks.append("wind_tail")
	bob.refresh_effects()
	foes = [BWRosterKits.unit("rui"), BWRosterKits.unit("kai"), BWRosterKits.unit("opus")]
	for u in [bob, gail]:
		u.stats["spd"] = 30
	s = BWCombatScreen.new()
	s.configure(MAP, [bob, gail], foes, [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	# Gail on Bob's gale, two west of the ledge
	var at := _west(LEDGE, 2)
	_reset({ gail: at, bob: Vector2i(5, 10) })
	s.battle.tiles.apply([at], "wind", bob.id)
	s.board_view.refresh_tiles(true)
	await _turn(gail)
	await _climb(gail, LEDGE, "updraft_ally")
	# Bob (lance + Tailwind) beside the 5-level block
	s.battle.tiles.entries.erase(at)
	_reset({ bob: _west(BLOCK, 2) })
	await _turn(bob)
	await _climb(bob, BLOCK, "updraft_holder")
	s.queue_free()
	await _wait(0.3)


func _obelisks() -> void:
	var p: Array = [BWRosterKits.unit("gail"), BWRosterKits.unit("bob"), BWRosterKits.unit("kai")]
	var e: Array = [BWRosterKits.unit("rui"), BWRosterKits.unit("opus"), BWRosterKits.unit("ana") if BWData.row("roster", "ana").size() > 0 else BWRosterKits.unit("lionel")]
	for u in p:
		u.stats["spd"] = 40
	s = BWCombatScreen.new()
	s.configure("res://maps/obelisks.json", p, e, [], 5)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	var l: BWUnit = s.battle.objectives()[0]
	var w: BWUnit = s.battle.objectives()[1]
	l.hp -= 70                                    # a blow on the Lantern ...
	s.battle._emit({ "type": "review_tick" })     # ... folds into the shared pool (D378)
	print("pool %s, lantern %d, well %d" % [str(s.battle.stones_life()), l.hp, w.hp])
	s.ui.set_objectives(s.battle.objectives())
	s._views[l.id].refresh()
	s._views[w.id].refresh()
	s.rig.following = false
	s.rig.input_enabled = false
	s.rig.pivot = s.board_view.top_center(Vector2i(8, 6))
	s.rig.dist = 26.0
	s.rig.pitch = deg_to_rad(52.0)
	s.rig.yaw = 0.0
	await _wait(1.0)
	await _shot("obelisk_shared_plate")
	s.ui.set_actions_visible(false)
	s.ui.set_card(w, s.battle.tiles, s.battle.current())
	await _wait(0.4)
	await _shot("obelisk_shared_card")
	print("plate: %s" % str(s.ui.objective_texts()))


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


## Hover the top's west edge (one step up from 1 west of the climber).
func _climb(u: BWUnit, top: Vector2i, name: String) -> void:
	s._show_options()
	await _cam(top)
	var r := s.battle.reachable(u)
	var edge := _west(top, 1)
	print("%s (jump %d, move %d): edge %s reach=%s cost=%s | %s" % [u.name, BWWeaponMove.jump(u), u.move_range(),
		edge, r.has(edge), str(r.get(edge, {}).get("cost", "-")), BWFormulas.move_text(u)])
	await _move_mouse(edge)
	await _wait(0.6)
	await _shot(name)

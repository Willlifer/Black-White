extends SceneTree
## D319-D324 review renders of the 6v6 infrastructure on Commons (needs a window):
##   [SHOTS=<dir>] [RES=1920x1080] godot --path . --resolution 1920x1080 --script res://tools/sixes_shots.gd
## 6v6_prebattle.png    the pre-battle screen: six slots, the auto-placement default
## 6v6_prebattle_drag.png  a drag onto a free deploy hex (a swap target shown)
## 6v6_opening.png      the combat camera's opening frame on Commons
## 6v6_rotated.png      the same after a 60° rotate (E)
## 6v6_midfight.png     mid-fight, 12 units, HP bars, the turn order (autoplay to round 3)
## 6v6_turnorder.png    the top strip of that frame: the current unit, the round, "+N", NEXT
## 6v6_blast.png        a player's aimed skill: the blast preview among 12 units
var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	var res := OS.get_environment("RES")
	if res == "":
		res = "1920x1080"
	var wh := res.split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String, crop := Rect2i()) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if crop.has_area():
		img = img.get_region(crop)
	var p := "%s/%s.png" % [out, name]
	img.save_png(p)
	print("shot ", p)


func _go() -> void:
	BWSettings.put("cutscenes", "fast")
	BWMusic.ensure(root)
	await _prebattle()
	await _combat()
	quit()


func _prebattle() -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 99)
	run.force_map = "commons"
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(2.5)
	await _shot("6v6_prebattle")
	var u: BWUnit = pre._deployed[0]
	var a := pre._cam.unproject_position(pre._bv.top_center(pre._placed[u.id]))
	pre._begin_drag(u, "map", a)
	var free: Array = pre._board.deploy.player.filter(func(h): return not h in pre._placed.values())
	pre._activate_drag()
	pre._update_drag(pre._cam.unproject_position(pre._bv.top_center(free[0])))
	await _wait(0.3)
	await _shot("6v6_prebattle_drag")
	pre._cancel_drag()
	pre.queue_free()
	await process_frame


func _combat() -> void:
	const P := preload("res://tools/sixes_perf.gd")
	var sd := P.sides(6, 7)
	s = BWCombatScreen.new()
	s.configure("res://maps/commons.json", sd[0], sd[1], [], 7)
	s.autoplay = true
	root.add_child(s)
	await _wait(2.2)
	await _shot("6v6_opening")
	var yaw0 := s.rig.yaw
	s.rig.rotate_by(60.0)                       # Q/E on a big board (D322 check)
	await _wait(0.6)
	await _shot("6v6_rotated")
	print("rotate: yaw %.2f -> %.2f rad" % [yaw0, s.rig.yaw])
	while s.battle.cycle < 3 and not s.battle.over:
		await _wait(0.2)
	# stop at the next player turn (autoplay off: the screen waits for input there)
	s.autoplay = false
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and not s.battle.over:
		await _wait(0.2)
	await _wait(1.0)
	var vp := root.get_texture().get_size()
	await _shot("6v6_midfight")
	await _shot("6v6_turnorder", Rect2i(int(vp.x * 0.15), 0, int(vp.x * 0.7), int(vp.y * 0.16)))
	var u := s.battle.current()
	var sk := BWAI._best_skill(s.battle, u)
	if not sk.is_empty():
		var sim := s.battle.simulate(u, { "kind": "skill", "key": sk.key, "element": sk.element, "hex": sk.target })
		s.readability.preview.show_sim(sim, str(sk.element))
		s.rig.follow(BWLook.world(sk.target, s.battle.board.elevation(sk.target)), true)
		await _wait(1.0)
		await _shot("6v6_blast")
		print("blast preview: %s %s on %s" % [sk.key, sk.element, sk.target])
	else:
		print("blast preview: no damaging skill for %s" % u.name)

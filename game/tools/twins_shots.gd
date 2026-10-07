extends SceneTree
## D260 review renders of the Twins on the real combat screen (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/twins_shots.gd
## twins_intro.png         the title card over the court
## twins_beam.png          phase 1: the court from above, the beam between them
## twins_noon.png          Noon close up (white, the halo-ring head)
## twins_dusk.png          Dusk close up (black, white contour, the hollow ring)
## twins_pair.png          both, mirrored, side by side
## twins_swap_<n>.png      the swap's inversion flash, a few frames
## twins_swapped.png       after the swap: the beam's colours traded
## twins_countdown.png     one down: "RAGE IN 2" over the survivor, the plate
## twins_rage.png          the rage: the survivor's column and ring
var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _settle() -> void:
	if not s._busy:
		s._after_events()
	await _wait(0.3)
	while s._busy:
		await process_frame


func _look(c: Vector3, dist: float, pitch: float, yaw: float = INF) -> void:
	s.rig.follow(c, true)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(pitch)
	if yaw != INF:
		s.rig.yaw = deg_to_rad(yaw)
	await _wait(0.8)


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "default")
	var n := BWRun.TWINS_FIGHT
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	for u in run.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
	run.fight = n
	var players: Array = run.squad.slice(0, 3)
	run.prepare_for_battle(players)
	var enemies := run.enemies_for(n)
	s = BWCombatScreen.new()
	s.configure("res://maps/court.json", players, enemies, [], 5)
	root.add_child(s)
	await _wait(1.2)
	await _shot("twins_intro")
	await _wait(2.5)
	while s._busy:
		await process_frame
	var b := s.battle
	var noon := BWTwins.twin(b, BWTwins.NOON)
	var dusk := BWTwins.twin(b, BWTwins.DUSK)
	var centre := BWLook.world(Vector2i(6, 4), 0)
	await _look(centre, 22.0, 48.0, 0.0)
	await _shot("twins_beam")
	var nv: BWUnitView = s._views[noon.id]
	var dv: BWUnitView = s._views[dusk.id]
	await _look(nv.global_position + Vector3(0, 2.2, 0), 7.5, 12.0, 20.0)
	await _shot("twins_noon")
	await _look(dv.global_position + Vector3(0, 2.2, 0), 7.5, 12.0, -30.0)
	await _shot("twins_dusk")
	await _look((nv.global_position + dv.global_position) * 0.5 + Vector3(0, 1.6, 0), 16.0, 14.0)
	await _shot("twins_pair")
	# the swap: Noon over the line
	noon.hp = noon.max_hp() / 2 + 2
	b._tile_hurt(noon, 4, "fire", "")
	s._after_events()
	for k in 6:
		await _wait(0.07)
		await _shot("twins_swap_%d" % k)
	while s._busy:
		await process_frame
	await _look(centre, 22.0, 48.0, 0.0)
	await _shot("twins_swapped")
	# one down: the countdown
	dusk.hp = 0
	b._ko(dusk, null)
	b._check_end()
	await _settle()
	await _look(nv.global_position + Vector3(0, 1.5, 0), 13.0, 22.0)
	await _shot("twins_countdown")
	b.cycle += 2
	BWPhases.new_cycle(b)
	await _settle()
	await _look(nv.global_position + Vector3(0, 1.6, 0), 11.0, 18.0)
	await _wait(0.6)
	await _shot("twins_rage")
	quit()

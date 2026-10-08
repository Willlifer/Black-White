extends SceneTree
## D485 review renders (needs a window): the 5000-HP Giant's bar.
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/giant10_shots.gd
## giant10_full.png   full (black, white pips), hovered: "5000 / 5000"
## giant10_62.png     62%, hovered, after a 60-point burn's grey ghost
## giant10_31.png     31% (white, black pips), not hovered
## giant10_deploy6.png  D487: the pre-battle screen at the Giant, six slots placed
## MODE=deploy renders only the last one.
var out := ""
var s: BWCombatScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _go() -> void:
	BWSettings.put("cutscenes", "default")
	BWMusic.ensure(root)
	if OS.get_environment("MODE") != "deploy":
		await _bar()
	await _deploy()
	quit()


func _deploy() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
		await process_frame
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	run.fight = BWRun.BOSS_FIGHT
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(3.0)
	print("deploy slots %d, placed %d" % [pre._need, pre._placed.size()])
	await _shot("giant10_deploy6")


func _bar() -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	for u in run.squad:
		BWProgression.level_up(u, 10 - u.level)
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(10))
	run.fight = BWRun.BOSS_FIGHT
	var players: Array = run.squad.slice(0, 3)
	run.prepare_for_battle(players)
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, [run.make_boss()], [], 5)
	root.add_child(s)
	await _wait(6.0)
	while s._busy:
		await process_frame
	var g: BWUnit = s.battle.side("enemy")[0]
	print("giant hp %d / %d, pct base %d" % [g.hp, g.max_hp(), g.pct_base_hp()])
	s.rig.follow(s._views[g.id].global_position, true)
	s.rig.dist = 26.0
	s.rig.pitch = deg_to_rad(32.0)
	BWHPBar3D.hover_unit = g
	await _wait(1.2)
	await _shot("giant10_full")
	g.hp = 3160
	s._views[g.id].refresh()
	await _wait(1.5)
	g.hp = 3100                     # a 60-point burn (12% of the 500 pct base)
	s._views[g.id].refresh()
	await _wait(0.12)
	await _shot("giant10_62")
	BWHPBar3D.hover_unit = null
	g.hp = 1550
	s._views[g.id].refresh()
	await _wait(1.5)
	await _shot("giant10_31")

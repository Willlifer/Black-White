extends SceneTree
## D208-D213 review renders of the special encounters on the real combat
## screen (needs a window):
##   [SHOTS=<dir>] [FIGHT=n] godot --path . --resolution 1920x1080 --script res://tools/encounter_shots.gd
## encounters_horde.png      the ten grunts on the board at their start
## encounters_colossus.png   the Colossus over its 7 hexes, the squad facing it
## encounters_blank.png      three Blanks close up (white, bald)
## encounters_being.png      three Elemental Beings close up (their element's glow)
## encounters_immune.png     a basic attack aimed at a Being: "Immune: physical"
## encounters_blank_x2.png   a sword aimed at a Blank: "×2: melee vs Blank"
## The room cards: tools/room_shots.gd with ENC=<kind>.
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


func _squad(n: int) -> Array:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	for u in run.squad:
		BWProgression.level_up(u, n - u.level)
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
	run.fight = n
	return [run, run.squad.slice(0, 3)]


func _fight(kind: String, map: String, n: int) -> void:
	var rp := _squad(n)
	var run: BWRun = rp[0]
	var players: Array = rp[1]
	# the squad: a sword up front for the forecast shots
	var sw: BWUnit = players[0]
	sw.equipment["main_hand"] = run.make_item("sword", run.tier_for(n))
	sw.sync_weapon()
	run.prepare_for_battle(players)
	var enemies := BWEncounters.build(run, n, kind)
	if s and is_instance_valid(s):
		s.queue_free()
		await process_frame
	s = BWCombatScreen.new()
	s.configure("res://maps/%s.json" % map, players, enemies, [], 5)
	root.add_child(s)
	await _wait(6.0)
	while s._busy:
		await process_frame


func _close_on(us: Array, dist: float) -> void:
	var c := Vector3.ZERO
	for u in us:
		c += s._views[u.id].global_position
	c /= maxf(us.size(), 1)
	s.rig.follow(c, true)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(30.0)
	await _wait(1.0)


## Aim `u`'s basic attack at `v` (moved beside it) and open the forecast.
func _aim(u: BWUnit, v: BWUnit) -> void:
	var b := s.battle
	for h in BWHex.neighbors(v.pos):
		if b.board.is_passable(h) and b.unit_at(h) == null:
			u.pos = h
			s._views[u.id].position = s.board_view.top_center(h)
			break
	var fc := b.forecast_basic(u, v)
	s.ui.show_forecast(u, v, fc)
	await _close_on([u, v], 11.0)


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "default")
	var n := int(OS.get_environment("FIGHT")) if OS.get_environment("FIGHT") != "" else 6
	await _fight("horde", "arena", n)
	s.rig.dist = 30.0
	await _wait(1.0)
	await _shot("encounters_horde")
	await _fight("colossus", "arena", n)
	await _close_on([s.battle.side("enemy")[0]], 30.0)
	s.rig.pitch = deg_to_rad(24.0)
	await _wait(0.6)
	await _shot("encounters_colossus")
	await _fight("blank", "arena", n)
	await _close_on(s.battle.side("enemy"), 12.0)
	await _shot("encounters_blank")
	await _aim(s.battle.side("player")[0], s.battle.side("enemy")[0])
	await _shot("encounters_blank_x2")
	await _fight("being", "arena", n)
	await _close_on(s.battle.side("enemy"), 12.0)
	await _shot("encounters_being")
	await _aim(s.battle.side("player")[0], s.battle.side("enemy")[0])
	await _shot("encounters_immune")
	quit()

extends SceneTree
## D252 review renders of the weather on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=rain,gale] godot --path . --resolution 1920x1080 --script res://tools/weather_shots.gd
## weather_<kind>.png: an AI-played fight in that weather, stopped at a player
## turn after the second tick (particles, the plate, the telegraphs).
## The room card with a weather tag: WEATHER=<kind> FIGHT=5 tools/room_shots.gd.
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


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	var only := OS.get_environment("ONLY").split(",", false)
	var roster := BWData.table("roster")
	for k in BWWeather.KINDS:
		if not only.is_empty() and not k in only:
			continue
		var players: Array = []
		var enemies: Array = []
		for i in 3:
			players.append(BWUnit.from_roster(roster[i]))
			enemies.append(BWUnit.from_roster(roster[i + 10]))
		if s and is_instance_valid(s):
			s.queue_free()
			await process_frame
		s = BWCombatScreen.new()
		s.configure("res://maps/arena.json", players, enemies, [], 4)
		s.weather_kind = k
		s.autoplay = true
		root.add_child(s)
		var t := 0.0
		while int(s.battle.weather.get("ticks", 0)) < 2 and not s.battle.over and t < 120.0:
			await _wait(0.25)
			t += 0.25
		s.autoplay = false                          # stop at the next player turn: the telegraphs draw when idle
		t = 0.0
		while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and not s.battle.over and t < 60.0:
			await _wait(0.25)
			t += 0.25
		if k == BWWeather.ASHFALL:                  # a fresh fire 3 pair to drop ash from at the next tick
			for h in [Vector2i(5, 7), Vector2i(8, 5)]:
				s.battle.tiles.apply([h], "fire", "", 3)
			s.board_view.refresh_tiles()
			s.weather_view._rebuild_telegraph()
		s.rig.dist = 30.0
		await _wait(1.5)
		print(k, ": ", s.weather_view.plate_texts(), " telegraph ", s.weather_view.tele_hexes, " ", s.weather_view.tele_hexes.map(func(h): return s.battle.tiles.at(h)))
		await _shot("weather_" + k)
	quit()

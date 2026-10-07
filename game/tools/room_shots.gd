extends SceneTree
## D190 review renders of the room select (a sample run at fight 2, after a
## day): the two cards, then a hover state (the Hard card lifted, its detail
## open, an enemy's unit card) → <SHOTS>/rooms_select.png, rooms_hover.png.
##   [SHOTS=<dir>] [FIGHT=n] [SEED=n] godot --path . --resolution 1600x900 --script res://tools/room_shots.gd
## Needs a window (real renders). Re-renders the map thumbnails (no disk cache).
## D208: the choice starts at fight 3 (the default FIGHT). ENC=<horde|colossus|
## blank|being> puts that encounter in the Hard room's place and saves
## encounters_room_<kind>.png (the select only). WEATHER=<kind> (D252, use
## FIGHT=5+) tags the Hard room with that weather -> weather_room.png.
var out := ""
var scr: BWRoomScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", out + "/" + name + ".png")


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _win(p)
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await process_frame
	await process_frame


func _go() -> void:
	BWMapThumbs.fresh = true
	BWEsc.synthetic = true
	var fight := int(OS.get_environment("FIGHT")) if OS.get_environment("FIGHT") != "" else 3
	var s := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 99
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, s)
	while run.fight < fight:
		var e := run.enemies_for(run.fight)
		for x in e:
			x.hp = 0
		run.after_fight(true, run.squad.slice(0, 3), e, e, [])
	var enc := OS.get_environment("ENC")
	if enc != "":
		var rooms := BWRooms.offer(run)
		rooms[1] = BWEncounters.room(run.fight, enc, str(rooms[1].map))
	var wk := OS.get_environment("WEATHER")          # D252: WEATHER=<kind> tags the Hard room -> weather_room.png
	if wk != "":
		var wrooms := BWRooms.offer(run)
		wrooms[1]["weather"] = wk
		enc = "_weather"
	scr = BWRoomScreen.new()
	scr.run = run
	root.add_child(scr)
	var t := 0.0
	while not scr.thumbs_ready() and t < 15.0:
		await _wait(0.2)
		t += 0.2
	await _wait(2.0)                      # portraits
	await _move(Vector2(800, 30))
	await _wait(0.4)
	if enc == "_weather":
		await _shot("weather_room")
		quit(0)
		return
	if enc != "":
		await _shot("encounters_room_" + enc)
		quit(0)
		return
	await _shot("rooms_select")
	# hover the Hard card's second enemy
	var card: Control = scr.cards[1]
	await _move(card.get_global_rect().position + Vector2(40, 40))
	await _wait(0.3)
	var cols: Array = card.find_children("*", "VBoxContainer", true, false).filter(func(c): return c.mouse_filter == Control.MOUSE_FILTER_PASS)
	if cols.size() >= 2:
		await _move(cols[1].get_global_rect().get_center())
	await _wait(1.2)
	await _shot("rooms_hover")
	quit(0)

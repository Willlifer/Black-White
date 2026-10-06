extends SceneTree
## D145 review frames for the Obelisks: the map overview, both stones up
## close, a push pulse and a pull pulse mid-ring, the objective UI (plate,
## turn order, a stone's hover card, a forecast with the dodge line).
##   godot --path . --script res://tools/obelisk_shots.gd     (windowed)
## Writes design/art/obelisks_*.png (SHOTS=<dir> to write elsewhere).

var s: BWCombatScreen
var out := "res://../design/art/"


func _init() -> void:
	if OS.get_environment("SHOTS") != "":
		out = OS.get_environment("SHOTS").path_join("")
	var roster := BWData.table("roster")
	var p: Array = []
	var e: Array = []
	var want := ["bow", "sword", "lance"]
	for wc in want:
		for row in roster:
			if str(row.weapon_class) == wc and p.size() < 3 and not p.any(func(u): return u.id == str(row.id)):
				p.append(BWUnit.from_roster(row))
				break
	for row in roster:
		if e.size() < 3 and not p.any(func(u): return u.id == str(row.id)):
			e.append(BWUnit.from_roster(row))
	for u in p:
		u.stats["spd"] = 40                       # the player acts first and waits for input
	s = BWCombatScreen.new()
	s.configure("res://maps/obelisks.json", p, e, [], 5)
	root.add_child(s)
	await _frames(70)
	var l: BWUnit = s.battle.objectives()[0]
	var w: BWUnit = s.battle.objectives()[1]
	# the objective UI: the banner is up, the plate, the stones in the turn order, a stone's card
	s.ui.set_card(l, s.battle.tiles, s.battle.current())
	await _frames(10)
	_save("obelisks_ui")
	# the forecast on a stone: a bow at range on the Lantern (dodged) after some damage
	var bow: BWUnit = p[0]
	l.hp = 380
	s.ui.set_objectives(s.battle.objectives())
	s._views[l.id].refresh()
	var spot := Vector2i(5, 6)
	bow.pos = spot
	s._views[bow.id].position = s.board_view.top_center(spot)
	_aim(spot + Vector2i(1, 0), 9.0, 30.0, 140.0)
	s.ui.show_forecast(bow, l, s.battle.forecast_basic(bow, l))
	await _frames(14)
	_save("obelisks_forecast")
	s.ui.hide_forecast()
	s.ui.set_card(null)
	# the overview (after the banner has gone)
	_aim(Vector2i(8, 6), 30.0, 62.0, 0.0)
	await create_timer(2.5).timeout
	_save("obelisks_map")
	# up close
	_aim(l.pos, 11.0, 16.0, 120.0, 1.3)
	await _frames(20)
	_save("obelisks_lantern")
	_aim(w.pos, 11.0, 16.0, -60.0, 1.3)
	await _frames(20)
	_save("obelisks_well")
	# the pulses, mid-ring: out from the Lantern, in toward the Well
	_aim(Vector2i(5, 6), 20.0, 48.0, 15.0)
	await _frames(5)
	(s._views[l.id] as BWObeliskView).pulse("push")
	await create_timer(0.2).timeout
	_save("obelisks_push")
	await create_timer(1.2).timeout
	_aim(Vector2i(12, 6), 20.0, 48.0, -15.0)
	await _frames(5)
	(s._views[w.id] as BWObeliskView).pulse("pull")
	await create_timer(0.5).timeout
	_save("obelisks_pull")
	quit()


func _aim(h: Vector2i, dist: float, pitch_deg: float, yaw_deg: float, lift: float = 0.0) -> void:
	s.rig.following = false
	s.rig.input_enabled = false
	s.rig.pivot = s.board_view.top_center(h) + Vector3(0, lift, 0)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(pitch_deg)
	s.rig.yaw = deg_to_rad(yaw_deg)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _save(name: String) -> void:
	var path := out + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

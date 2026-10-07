extends SceneTree
## D301-D306 review renders for the Element Overhaul's final pass, on the real
## combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=card,dive] godot --path . --resolution 1920x1080 --script res://tools/final_shots.gd
## → design/art/v3_final_card.png (an ice staff holding two keystones: the
##   card's one keystone line, no leaked BBCode; an enemy's card beside it),
##   v3_final_dive_1|2|3.png (the dagger bomber: a Blast Rider dagger leaps
##   into the pack onto a fire hex, Self-detonates its own hex, then launches
##   out with move 2).
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()          # D301: no leftover "Battle start"
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _row(roster: Array, wc: String, el: String, skip: Array) -> Dictionary:
	for r in roster:
		if str(r.get("weapon_class", "")) == wc and not str(r.id) in skip:
			var d: Dictionary = r.duplicate()
			d["element"] = el
			skip.append(str(r.id))
			return d
	var any: Dictionary = roster[skip.size()].duplicate()
	any["weapon_class"] = wc
	any["weapon_model"] = wc
	any["element"] = el
	skip.append(str(any.id))
	return any


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	var roster := BWData.table("roster")
	var used: Array = []
	var players: Array = [BWUnit.from_roster(_row(roster, "staff", "ice", used)),
		BWUnit.from_roster(_row(roster, "daggers", "thunder", used)),
		BWUnit.from_roster(_row(roster, "bow", "light", used))]
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in players + enemies:
		u.stats["con"] = 40
	var ice: BWUnit = players[0]
	var dg: BWUnit = players[1]
	BWKeystones.grant(ice, "flash_freeze")
	BWKeystones.grant(ice, "tidal_release")       # the long one whose "=" leaked the tag
	BWKeystones.grant(ice, "glacier_wall")        # refused: the cap of 2 (D302)
	print("ice keystones: ", ice.keystones)
	BWKeystones.grant(dg, "blast_rider")
	BWKeystones.grant(dg, "static_blades")
	BWKeystones.grant(enemies[0], "conflagration")
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	var f := _flat_centre(b)
	s.rig.pitch = deg_to_rad(50.0)

	if _want("card"):
		_turn(ice)
		_look(BWLook.world(ice.pos, b.board.elevation(ice.pos)), 14.0, 55.0)
		await _wait(0.8)
		await _shot("v3_final_card")
		s.ui.set_card(enemies[0], b.tiles, ice)       # the enemy card: its keystone line
		await _wait(0.4)
		await _shot("v3_final_card_enemy")

	if _want("dive"):
		_park(players + enemies, f, 5)
		var land := f
		_place(enemies[0], BWHex.neighbors(land)[0])
		_place(enemies[1], BWHex.neighbors(land)[2])
		_place(enemies[2], BWHex.neighbors(land)[4])
		var start := _at(b, land, 3)
		_place(dg, start)
		b.tiles.entries[land] = b.tiles._entry(2, 0, "", enemies[0].id, "cast")   # fire 2 in the pack
		await _settle()
		_turn(dg)
		_look(BWLook.world(land, b.board.elevation(land)), 13.0, 52.0)
		await _wait(0.8)
		var ok := land in b.skill_targets(dg, "daggerleap", "thunder")
		print("leap target ok: ", ok)
		if ok:
			b.use_skill(dg, "daggerleap", "thunder", land)
		else:
			_place(dg, land)
		s._after_events()
		await _idle_busy()
		_turn_keep(dg)
		await _wait(0.5)
		await _shot("v3_final_dive_1")             # in the pack, on the fire, the menu offers Self-detonate
		print("self-det targets: ", b.skill_targets(dg, "self_detonate", ""))
		var ev := b.use_skill(dg, "self_detonate", "", dg.pos)
		print("self-det: ", not ev.is_empty(), " launch ", b.history.any(func(e): return str(e.type) == "launch"))
		s._after_events()
		var t := 0.0
		while t < 0.55:
			await _wait(0.05)
			t += 0.05
		await _shot("v3_final_dive_2")             # the blast: rider immune, the ring takes the half
		await _idle_busy()
		var away := land
		for h in b.reachable(dg):
			if BWHex.distance(h, land) == 3 and (away == land or h < away):
				away = h
		if away != land:
			b.move(dg, away)
			s._after_events()
			await _idle_busy()
		s.ui.set_acting(dg, b.tiles)
		var mid := (BWLook.world(land, b.board.elevation(land)) + BWLook.world(dg.pos, b.board.elevation(dg.pos))) * 0.5
		_look(mid, 15.0, 55.0)
		await _wait(0.6)
		await _shot("v3_final_dive_3")             # launched out: move 2 after the blast
	quit()


func _look(c: Vector3, dist: float, pitch: float, yaw: float = INF) -> void:
	s.rig.follow(c, true)
	s.rig.dist = dist
	s.rig.pitch = deg_to_rad(pitch)
	if yaw != INF:
		s.rig.yaw = deg_to_rad(yaw)


func _idle() -> void:
	var t := 0.0
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and t < 60.0:
		await _wait(0.2)
		t += 0.2


func _idle_busy() -> void:
	var t := 0.0
	await _wait(0.1)
	while s._busy and t < 20.0:
		await _wait(0.1)
		t += 0.1


func _settle() -> void:
	s.board_view.refresh_tiles()
	await _wait(0.3)


func _turn(u: BWUnit) -> void:
	var b := s.battle
	b.queue = [u] + b.queue.filter(func(x): return x != u)
	b.turn_index = 0
	b._begin_turn()
	s._queue.clear()
	s._skill = {}
	u.acted = false
	u.moved = false
	s.ui.set_acting(u, b.tiles)
	s._show_options()


## Refresh the menu and card mid-turn (after an action), keeping its state.
func _turn_keep(u: BWUnit) -> void:
	s._queue.clear()
	s._skill = {}
	s.ui.set_acting(u, s.battle.tiles)
	s._show_options()


func _place(u: BWUnit, h: Vector2i) -> void:
	if h == Vector2i(-1, -1):
		return
	u.pos = h
	var v: Node3D = s._views[u.id]
	v.position = s._unit_pos(h)


func _park(us: Array, c: Vector2i, r: int) -> void:
	var b := s.battle
	for u in us:
		if BWHex.distance(u.pos, c) <= r:
			for h in _open(b, c, 80):
				if BWHex.distance(h, c) > r + 1:
					_place(u, h)
					break


func _at(b: BWBattle, c: Vector2i, d: int) -> Vector2i:
	for h in _open(b, c, 60):
		if BWHex.distance(c, h) == d:
			return h
	return Vector2i(-1, -1)


func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 3):
			if b.board.is_passable(a) and b.board.elevation(a) == b.board.elevation(h):
				k += 1
		k = k * 100 - BWHex.distance(h, b.board.camera_focus)
		if k > best_k:
			best_k = k
			best = h
	return best


func _open(b: BWBattle, c: Vector2i, n: int) -> Array:
	var out2: Array = []
	for r in 9:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out2.size() >= n:
				return out2
			if b.board.is_passable(h) and not b.board.blocked(h) and absi(b.board.elevation(h) - b.board.elevation(c)) <= 0 and b.unit_at(h) == null:
				out2.append(h)
	return out2

extends SceneTree
## D293-D299 review renders of the wind, ice, water and dark keystones on the
## real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=freeze,glacier,tidal,doom,rot,twins] godot --path . --resolution 1920x1080 --script res://tools/keystones_c3_shots.gd
## (D408: the v3_c3_eye_* frames are retired)
##   v3_c3_freeze.png (Flash Freeze: the ice shell, FROZEN x2), v3_c3_glacier_1|2.png
##   (a Glacier pillar ∞, its shatter), v3_c3_tidal_1|2.png (the wave mid-run, after),
##   v3_c3_doom_1|2.png (the DOOM mark, the burst), v3_c3_rot.png (ROT / marks on the
##   HP bars, one under the turn order), v3_c3_twins_1|2|3.png (the Twins' hover, a glide,
##   RAGE IN n clamped).
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
	if only.size() == 1 and only[0] == "twins":
		await _twins()
		quit()
		return
	var roster := BWData.table("roster")
	var used: Array = []
	var players: Array = [BWUnit.from_roster(_row(roster, "staff", "wind", used)),
		BWUnit.from_roster(_row(roster, "staff", "ice", used)),
		BWUnit.from_roster(_row(roster, "staff", "dark", used))]
	var enemies: Array = []
	for wc in ["sword", "lance", "bow"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in players + enemies:
		u.stats["con"] = 40
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	var f := _flat_centre(b)
	var wnd: BWUnit = players[0]
	var ice: BWUnit = players[1]
	var dk: BWUnit = players[2]
	var spots := _open(b, f, 30)
	s.rig.pitch = deg_to_rad(50.0)

	# D408: Eye of the Vortex is a Draw in rider now (no Vortex field to frame);
	# its old "eye" frames are retired. A Draw in preview: tools/wind_shape_shots.gd ONLY=rain.

	if _want("freeze"):
		BWKeystones.grant(ice, "flash_freeze")
		_turn(ice)
		var foe: BWUnit = enemies[1]
		_place(foe, _at(b, ice.pos, 2))
		var ev := b.use_skill(ice, "flash_freeze", "", foe.pos)
		print("freeze: ", not ev.is_empty(), " frozen ", BWKsIce.frozen(foe))
		s._after_events()
		await _idle()
		_look(s._views[foe.id].global_position + Vector3(0, 1.2, 0), 8.0, 22.0)
		await _wait(0.9)
		print("freeze tag: ", s.ks_view.tag_text(foe.id))
		await _shot("v3_c3_freeze")
		BWKsIce.thaw(b, foe, "review")

	if _want("glacier"):
		BWKeystones.grant(ice, "glacier_wall")
		_turn(ice)
		var p := _at(b, ice.pos, 2)
		b.tiles.entries[p] = b.tiles._entry(-3, 0, "", "", "cast")
		b.paint([p], "ice", ice)
		var ns: Array = BWHex.neighbors(p).filter(func(h): return b.board.is_passable(h) and b.unit_at(h) == null and h != ice.pos)
		if ns.size() >= 2:
			_place(enemies[0], ns[0])
			_place(dk, ns[1])
		await _settle()
		_look(BWLook.world(p, b.board.elevation(p)) + Vector3(0, 1.0, 0), 10.0, 30.0)
		await _wait(0.8)
		print("pillar: ", b.tiles.pillars.get(p, {}))
		await _shot("v3_c3_glacier_1")
		var t := b.skill_targets(ice, "glacier_shatter", "")
		print("shatter targets: ", t)
		if p in t:
			b.use_skill(ice, "glacier_shatter", "", p)
		else:
			BWKsIce.shatter(b, ice, p)
		_look(BWLook.world(p, b.board.elevation(p)) + Vector3(0, 0.5, 0), 12.0, 55.0)
		s._after_events()
		var gt := 0.0
		while not s.ks_view.get_children().any(func(n): return n is MeshInstance3D and n.mesh is PrismMesh) and gt < 6.0:
			await process_frame
			gt += 0.016
		await _wait(0.12)
		await _shot("v3_c3_glacier_2")
		await _idle()

	if _want("tidal"):
		ice.keystones.erase("glacier_wall")          # D302: the cap of 2 (the old shot showed 3)
		BWKeystones.grant(ice, "tidal_release")
		_turn(ice)
		var start := Vector2i(-1, -1)
		var dir := 0
		for h in _open(b, ice.pos, 30):
			if BWHex.distance(ice.pos, h) != 2:
				continue
			for d in 6:
				var ok := true
				var cur: Vector2i = h
				for i in 5:
					if i > 0:
						cur = BWHex.neighbors(cur)[d]
					if not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(h) or (b.unit_at(cur) != null and i < 1):
						ok = false
						break
				if ok and BWHex.distance(ice.pos, BWHex.neighbors(h)[d]) >= 2:
					start = h
					dir = d
					break
			if start.x >= 0:
				break
		var line: Array = []
		var cur2 := start
		for i in 5:
			if i > 0:
				cur2 = BWHex.neighbors(cur2)[dir]
			line.append(cur2)
			b.tiles.entries[cur2] = b.tiles._entry(-2, 0, "", "", "cast")
		_place(enemies[0], line[1])
		_place(enemies[2], line[3])
		await _settle()
		_look(BWLook.world(line[2], b.board.elevation(line[2])), 13.0, 50.0)
		await _wait(0.6)
		var ev2 := b.use_skill(ice, "tidal_release", "", start, BWHex.neighbors(start)[dir])
		print("tidal: ", not ev2.is_empty(), " line ", line)
		s._after_events()
		var tt := 0.0
		while not s.ks_view.get_children().any(func(n): return n is MeshInstance3D and n != s.ks_view._mesh and n.mesh is ArrayMesh) and tt < 6.0:
			await _wait(0.03)
			tt += 0.03
		await _wait(0.28)
		await _shot("v3_c3_tidal_1")
		await _idle()
		await _wait(0.5)
		await _shot("v3_c3_tidal_2")

	if _want("doom") or _want("rot"):
		BWKeystones.grant(dk, "doom")
		_turn(dk)
		var foe2: BWUnit = enemies[1]
		var mate: BWUnit = enemies[0]
		_place(foe2, _at(b, dk.pos, 3))
		var nb: Array = BWHex.neighbors(foe2.pos).filter(func(h): return b.board.is_passable(h) and b.unit_at(h) == null)
		if not nb.is_empty():
			_place(mate, nb[0])
		BWCurse.add_rot(b, foe2, 3, dk.id, "dark")
		BWCurse.add_rot(b, mate, 1, dk.id, "dark")
		s._after_events()
		await _idle()
		_look(s._views[foe2.id].global_position + Vector3(0, 1.0, 0), 10.0, 30.0)
		await _wait(0.9)
		print("doom tag: ", s.ks_view.tag_text(foe2.id), " rot ", s.wind_view.rot_text(mate.id))
		if _want("doom"):
			await _shot("v3_c3_doom_1")
			foe2.fx.doom.at = -1
			BWCurse.turn_end(b, foe2)
			s._after_events()
			await _wait(0.22)
			await _shot("v3_c3_doom_2")
			await _idle()
			await _wait(0.5)
			print("after doom: ", s.ks_view.shown, " tag '", s.ks_view.tag_text(foe2.id), "' doomed ", BWKsDark.doomed(foe2))
		if _want("rot"):
			BWCurse.add_rot(b, enemies[2], 1, dk.id, "dark")
			s._after_events()
			await _idle()
			# a wide view with a unit high on the screen, under the turn order
			_look(s._views[mate.id].global_position + Vector3(0, -4.0, 4.0), 14.0, 40.0)
			await _wait(1.0)
			print("rot: ", s.wind_view.rot_text(mate.id), " / ", s.wind_view.rot_text(enemies[2].id))
			await _shot("v3_c3_rot")
	if _want("twins"):
		s.queue_free()
		await _wait(0.5)
		await _twins()
	quit()


func _twins() -> void:
	BWSettings.put("cutscenes", "minimal")
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
	s.autoplay = false
	root.add_child(s)
	await _wait(4.0)
	while s._busy:
		await process_frame
	var b := s.battle
	var noon := BWTwins.twin(b, BWTwins.NOON)
	var dusk := BWTwins.twin(b, BWTwins.DUSK)
	var nv: BWUnitView = s._views[noon.id]
	var dv: BWUnitView = s._views[dusk.id]
	_look(nv.global_position + Vector3(0, 1.2, 0), 8.0, 4.0, 20.0)
	await _wait(1.0)
	await _shot("v3_c3_twins_1")
	await _wait(1.3)
	await _shot("v3_c3_twins_1b")
	# a glide: Dusk moves 2-3 hexes
	_turn(dusk)
	var r := b.reachable(dusk)
	var dest := dusk.pos
	for h in r:
		if r[h].stop and BWHex.distance(h, dusk.pos) == 3 and b.board.elevation(h) == b.board.elevation(dusk.pos):
			dest = h
			break
	b.move(dusk, dest)
	_look((dv.global_position + BWLook.world(dest, b.board.elevation(dest))) * 0.5 + Vector3(0, 1.2, 0), 11.0, 5.0, -30.0)
	s._after_events()
	await _wait(0.75)
	await _shot("v3_c3_twins_2")
	await _wait(1.5)
	# one down: RAGE IN n, with the camera so the survivor sits high on screen
	dusk.hp = 0
	b._ko(dusk, null)
	b._check_end()
	s._after_events()
	await _wait(4.0)
	_look(nv.global_position + Vector3(0, 1.0, 0), 13.0, 26.0)
	await _wait(1.0)
	await _shot("v3_c3_twins_3")


# ---------------------------------------------------------------- helpers

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


func _place(u: BWUnit, h: Vector2i) -> void:
	if h == Vector2i(-1, -1):
		return
	u.pos = h
	var v: Node3D = s._views[u.id]
	v.position = s._unit_pos(h)


## Move everyone off the area round `c` (radius r) so a scene is clean.
func _park(us: Array, c: Vector2i, r: int) -> void:
	var b := s.battle
	for u in us:
		if BWHex.distance(u.pos, c) <= r:
			for h in _open(b, c, 80):
				if BWHex.distance(h, c) > r + 1:
					_place(u, h)
					break


## A free passable hex at distance `d` from `c` on its level.
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
	var out: Array = []
	for r in 9:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out.size() >= n:
				return out
			if b.board.is_passable(h) and not b.board.blocked(h) and absi(b.board.elevation(h) - b.board.elevation(c)) <= 0 and b.unit_at(h) == null:
				out.append(h)
	return out

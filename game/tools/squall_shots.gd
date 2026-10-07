extends SceneTree
## D309-D313 review renders of wind's Squall and ice's Overfreeze on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=light,dark,freeze] godot --path . --resolution 1920x1080 --script res://tools/squall_shots.gd
## → design/art/v3_squall_light_preview.png (a wind Surge aimed at light 2: the first front and its tags),
##   v3_squall_light.png (mid-advance: the front sweeping over ring 2, the next ring's swirls),
##   v3_squall_light_after.png (the spread light and the moving front marks), v3_squall_dark*.png (the same on dark),
##   v3_overfreeze_preview.png (an ice Surge aimed at glazed water: the burst's seven hexes, OVERFREEZE 12%),
##   v3_overfreeze.png (the burst playing), v3_overfreeze_after.png (the rink, no pillar).
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	_go.call_deferred()
	create_timer(240.0, true, false, true).timeout.connect(func(): print("watchdog: quitting"); quit(1))


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	if s and is_instance_valid(s) and s.ui:
		await s.ui.banner_gone()
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
	var players: Array = [BWUnit.from_roster(_row(roster, "staff", "wind", used)),
		BWUnit.from_roster(_row(roster, "staff", "ice", used)),
		BWUnit.from_roster(_row(roster, "bow", "light", used))]
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "fire", used)))
	for u in players + enemies:
		u.stats["con"] = 40
	for el in ["wind", "ice", "light", "dark"]:
		for u in players:
			u.affinity[el] = maxi(int(u.affinity.get(el, 0)), 12)
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	await _wait(2.5)
	var b := s.battle
	var f := _flat_centre(b)
	var wst: BWUnit = players[0]
	var ist: BWUnit = players[1]
	var spots := _open(b, f, 18)
	for i in players.size():
		_place(players[i], spots[i])
	for i in enemies.size():
		_place(enemies[i], spots[10 + i])
	s.rig.pitch = deg_to_rad(55.0)
	s.rig.dist = 15.0

	for el in ["light", "dark"]:
		if not _want(el):
			continue
		b.tiles.entries.clear()
		BWSquall.squalls(b).clear()
		var c := _flower(b, f, [wst])
		_place(wst, _free_at(b, c, 4))
		var r2: Array = Array(BWHex.ring(c, 2))
		_place(enemies[0], r2[1])
		_place(enemies[1], r2[7])
		_place(players[2], _free_at(b, c, 3))
		b.tiles.entries[c] = b.tiles._entry(0, 2 if el == "light" else -2, "", wst.id, "cast")
		wst.cooldowns.clear()
		_turn(wst)
		s.board_view.refresh_tiles()
		s._skill = { "key": "surge", "element": "wind", "row": BWSkills.get_skill("surge") }
		var tgt := c
		if not c in b.skill_targets(wst, "surge", "wind"):
			print("surge can't target the centre")
		s._aim_skill(wst, tgt)
		s.rig.follow(BWLook.world(c, b.board.elevation(c)), true)
		s.rig.dist = 14.0
		await _wait(1.0)
		print(el, " squall preview: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "squall").size())
		await _shot("v3_squall_%s_preview" % el)
		s._on_action("confirm")
		await _wait_event_played("squall", 6.0)
		await _idle()
		await _wait(0.8)
		b.cycle += 1
		BWWind.tick(b)                          # the first advance: ring 2
		s._after_events()
		await _wait_event_played("squall_advance", 4.0)
		await _wait(0.1)
		await _shot("v3_squall_%s" % el)
		await _wait(1.2)
		s.board_view.refresh_tiles()
		print(el, " front shown: ", s.squall_view.shown.get("front", []).size())
		await _shot("v3_squall_%s_after" % el)
		s.squall_view.played.clear()

	if _want("freeze"):
		b.tiles.entries.clear()
		BWSquall.squalls(b).clear()
		var c2 := _flower(b, f, [ist])
		var ring: Array = Array(BWHex.neighbors(c2))
		_place(enemies[0], c2)
		_place(enemies[1], ring[2])
		_place(ist, _free_at(b, c2, 3))
		b.tiles.entries[c2] = b.tiles._entry(-2, 0, "", ist.id, "cast")
		b.tiles.entries[c2].glaze = 2
		b.tiles.entries[ring[4]] = b.tiles._entry(-1, 0, "", ist.id, "cast")
		b.tiles.entries[ring[0]] = b.tiles._entry(2, 0, "", "", "cast")
		_turn(ist)
		s.board_view.refresh_tiles()
		s._skill = { "key": "surge", "element": "ice", "row": BWSkills.get_skill("surge") }
		s._aim_skill(ist, c2)
		s.rig.follow(BWLook.world(c2, b.board.elevation(c2)), true)
		s.rig.dist = 12.0
		await _wait(1.0)
		print("overfreeze preview: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "overfreeze").size())
		await _shot("v3_overfreeze_preview")
		s._on_action("confirm")
		await _wait_event_played("overfreeze", 6.0)
		await _wait(0.14)
		await _shot("v3_overfreeze")
		await _idle()
		await _wait(0.8)
		s.board_view.refresh_tiles()
		print("pillars: ", b.tiles.pillars.size())
		await _shot("v3_overfreeze_after")
	quit(0)


# ---------------------------------------------------------------- helpers

## Wait until the screen's elements view has played an event of `type`.
func _wait_event_played(type: String, limit: float) -> void:
	var t := 0.0
	while t < limit and not type in s.squall_view.played:
		await _wait(0.03)
		t += 0.03
	print("played ", type, ": ", type in s.squall_view.played, " after ", t)


func _idle() -> void:
	var t := 0.0
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and t < 60.0:
		await _wait(0.2)
		t += 0.2


## Hand the turn to `u` now (review only).
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


## The nearest hex to `near` whose whole flower (it and its six neighbours) is
## passable, level and free (units in `ignore` don't count; others are moved off).
func _flower(b: BWBattle, near: Vector2i, ignore: Array) -> Vector2i:
	var cells := b.board.cells()
	cells.sort_custom(func(x, y): return BWHex.distance(x, near) < BWHex.distance(y, near))
	for c in cells:
		var ok := true
		for h in [c] + Array(BWHex.neighbors(c)):
			if not b.board.is_passable(h) or b.board.blocked(h) or b.board.elevation(h) != b.board.elevation(c):
				ok = false
				break
		if not ok:
			continue
		for h in [c] + Array(BWHex.neighbors(c)):
			var o := b.unit_at(h)
			if o != null and not o in ignore:
				var away := _open(b, BWHex.neighbors(c)[0], 40)
				for a in away:
					if BWHex.distance(a, c) >= 3:
						_place(o, a)
						break
		return c
	return near


func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 2):
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
			if b.board.is_passable(h) and not b.board.blocked(h) and absi(b.board.elevation(h) - b.board.elevation(c)) <= 1 and b.unit_at(h) == null:
				out.append(h)
	return out


## A free hex exactly `r` from `c` (else the nearest free one).
func _free_at(b: BWBattle, c: Vector2i, r: int) -> Vector2i:
	for h in BWHex.ring(c, r):
		if b.board.is_passable(h) and b.unit_at(h) == null:
			return h
	var o := _open(b, c, 6)
	return o[o.size() - 1] if not o.is_empty() else Vector2i(-1, -1)

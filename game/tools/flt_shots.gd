extends SceneTree
## D285-D292 review renders of fire, light and thunder on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=overheat,beam,magnify,blades,rider] godot --path . --resolution 1920x1080 --script res://tools/flt_shots.gd
## → design/art/v3_fire_overheat_preview.png (a fire Surge aimed at fire 3: the eruption ring and its tag),
##   v3_fire_overheat.png (the eruption playing), v3_fire_overheat_after.png (the ring on fire, the pulsing rims),
##   v3_light_beam_tick.png (the tick's beam ribbon), v3_light_beam.png (the dashed beam, EMPOWERED over the ends),
##   v3_light_magnify.png (an ally on a Magnify holder's light aims a Surge: +1 radius, the forecast line),
##   v3_thunder_blades_preview.png (a backstab on a foe on a Static fuse: BLADE BURST), v3_thunder_blades.png,
##   v3_thunder_rider_preview.png (a thunder Surge on the rider's own hex: the launch arrow), v3_thunder_rider.png.
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
	var players: Array = [BWUnit.from_roster(_row(roster, "staff", "fire", used)),
		BWUnit.from_roster(_row(roster, "bow", "light", used)),
		BWUnit.from_roster(_row(roster, "daggers", "thunder", used))]
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "water", used)))
	for u in players + enemies:
		u.stats["con"] = 40                     # nobody falls while we look
	for el in ["fire", "light", "thunder"]:
		for u in players:
			u.affinity[el] = maxi(int(u.affinity.get(el, 0)), 12)
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	await _wait(2.5)                          # the "Battle start" banner fades
	var b := s.battle
	var f := _flat_centre(b)
	var stf: BWUnit = players[0]
	var bow: BWUnit = players[1]
	var dg: BWUnit = players[2]
	var spots := _open(b, f, 18)
	for i in players.size():
		_place(players[i], spots[i])
	for i in enemies.size():
		_place(enemies[i], spots[10 + i])
	s.rig.pitch = deg_to_rad(52.0)
	s.rig.dist = 15.0

	if _want("overheat"):
		var c := _flower(b, f, [stf])
		var ring: Array = Array(BWHex.neighbors(c))
		_place(enemies[0], ring[0])
		_place(enemies[1], ring[3])
		_place(stf, _free_at(b, c, 3))
		b.tiles.entries[c] = b.tiles._entry(3, 0, "", stf.id, "cast")
		b.tiles.entries[ring[1]] = b.tiles._entry(-3, 0, "", "", "cast")
		b.tiles.entries[ring[2]] = b.tiles._entry(1, 0, "", "", "cast")
		_turn(stf)
		s.board_view.refresh_tiles()
		s._skill = { "key": "surge", "element": "fire", "row": BWSkills.get_skill("surge") }
		var tgt := c
		for h in b.skill_targets(stf, "surge", "fire"):
			if BWHex.distance(h, c) == 1 and b.unit_at(h) == null and not h in [ring[1], ring[2]]:
				tgt = h
				break
		s._aim_skill(stf, tgt)
		s.rig.follow(BWLook.world(c, b.board.elevation(c)), true)
		s.rig.dist = 12.0
		await _wait(1.0)
		print("overheat preview: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "overheat").size())
		await _shot("v3_fire_overheat_preview")
		s._on_action("confirm")
		var tt := 0.0
		while not b.history.any(func(x): return str(x.type) == "overheat") and tt < 4.0:
			await _wait(0.05)
			tt += 0.05
		await _wait_event_played("overheat", 6.0)
		await _wait(0.12)
		await _shot("v3_fire_overheat")
		await _idle()
		await _wait(0.6)
		s.board_view.refresh_tiles()
		print("hot rims: ", s.elements_view.shown.get("overheat", []))
		await _shot("v3_fire_overheat_after")
		b.tiles.entries.clear()
		s.board_view.refresh_tiles()

	if _want("beam"):
		var a: Vector2i = spots[7]
		var line: Array = [a]
		var dir := -1
		for d in 6:
			var ok := true
			var x := a
			var hs: Array = [a]
			for k in 3:
				x = BWHex.neighbors(x)[d]
				if not b.board.is_passable(x) or absi(b.board.elevation(x) - b.board.elevation(a)) > 1:
					ok = false
				hs.append(x)
			if ok and b.unit_at(hs[1]) in [null, enemies[2]] and b.unit_at(hs[3]) in [null, bow, dg]:
				dir = d
				line = hs
				break
		print("beam line: ", line, " dir ", dir)
		_place(stf, line[0])
		_place(bow, line[3])
		_place(enemies[2], line[1])
		_place(dg, _free_at(b, line[2], 1))
		for h in [line[0], line[3]]:
			b.tiles.entries[h] = b.tiles._entry(0, 2, "", bow.id, "cast")
		s.board_view.refresh_tiles()
		s.rig.follow((BWLook.world(line[0], 0) + BWLook.world(line[3], 0)) / 2.0, true)
		s.rig.dist = 13.0
		s.rig.pitch = deg_to_rad(74.0)
		await _wait(0.6)
		BWBeams.tick(b)
		s._after_events()
		await _wait(0.12)
		await _shot("v3_light_beam_tick")
		await _idle()
		await _wait(0.8)
		print("beams shown: ", s.elements_view.shown.get("beams", 0), " empowered ", s.elements_view.shown.get("empowered", []))
		await _shot("v3_light_beam")

	if _want("magnify"):
		s.rig.pitch = deg_to_rad(52.0)
		bow.keystones = ["magnify"]
		_turn(stf)
		b.tiles.entries.clear()
		b.tiles.entries[stf.pos] = b.tiles._entry(0, 1, "", bow.id, "cast")
		s.board_view.refresh_tiles()
		var foe: BWUnit = enemies[2]
		var tgt2 := foe.pos
		for h in b.skill_targets(stf, "surge", "fire"):
			if BWHex.distance(h, foe.pos) == 2 and b.unit_at(h) == null:
				tgt2 = h
				break
		s._skill = { "key": "surge", "element": "fire", "row": BWSkills.get_skill("surge") }
		s._aim_skill(stf, tgt2)
		s.rig.follow(BWLook.world(tgt2, b.board.elevation(tgt2)), true)
		s.rig.dist = 13.0
		await _wait(1.0)
		print("magnify notes: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "magnify"))
		await _shot("v3_light_magnify")
		s._on_action("cancel")
		s._on_action("cancel")
		await _wait(0.3)

	if _want("blades"):
		dg.keystones = ["static_blades", "blast_rider"]
		b.tiles.entries.clear()
		var foe2: BWUnit = enemies[0]
		var fc: Vector2i = spots[5]
		_place(foe2, fc)
		var back := -1
		for d in 6:
			var h := BWHex.neighbors(fc)[d]
			if b.board.is_passable(h) and b.unit_at(h) == null and absi(b.board.elevation(h) - b.board.elevation(fc)) <= 1:
				back = d
				break
		foe2.facing = (back + 3) % 6                  # facing away from the dagger
		_place(dg, BWHex.neighbors(fc)[back])
		b.tiles.entries[fc] = b.tiles._entry(0, 0, "fuse", dg.id, "cast")
		b.tiles.entries[fc]["static"] = true
		_turn(dg)
		s.board_view.refresh_tiles()
		s._face_all()
		foe2.facing = (back + 3) % 6
		s.rig.follow(BWLook.world(fc, b.board.elevation(fc)), true)
		s.rig.dist = 10.0
		await _wait(0.6)
		s._on_click(fc)
		await _wait(1.0)
		print("blade preview: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "blade_burst").size())
		await _shot("v3_thunder_blades_preview")
		s._on_action("confirm")
		await _wait_event_played("blade_burst", 8.0)
		await _wait(0.08)
		await _shot("v3_thunder_blades")
		await _idle()

	if _want("rider"):
		# the bomber on a staff: Surge (thunder) on its own charged hex
		stf.keystones = ["blast_rider"]
		b.tiles.entries.clear()
		var land := _flower(b, f, [stf])
		_place(stf, land)
		_place(enemies[0], BWHex.neighbors(land)[0])
		_place(enemies[1], BWHex.neighbors(land)[3])
		_turn(stf)
		stf.cooldowns.clear()
		b.tiles.entries[land] = b.tiles._entry(2, 0, "", stf.id, "cast")
		s.board_view.refresh_tiles()
		s._skill = { "key": "surge", "element": "thunder", "row": BWSkills.get_skill("surge") }
		print("rider: own hex targetable ", land in b.skill_targets(stf, "surge", "thunder"))
		s._aim_skill(stf, land)
		s.rig.follow(BWLook.world(land, b.board.elevation(land)), true)
		s.rig.dist = 12.0
		s.rig.pitch = deg_to_rad(40.0)
		await _wait(1.0)
		print("rider preview: ", s.readability.preview.last.get("events", []).filter(func(e): return str(e.type) == "launch"))
		await _shot("v3_thunder_rider_preview")
		s._on_action("confirm")
		await _wait_event_played("launch", 8.0)
		await _wait(0.15)
		await _shot("v3_thunder_rider")
		print("rider hp ", stf.hp, "/", stf.max_hp(), " extra_move ", stf.fx.get("extra_move", 0), " bonus ", stf.fx.get("bonus_move", 0))
	quit()


# ---------------------------------------------------------------- helpers

## Wait until the screen's elements view has played an event of `type`.
func _wait_event_played(type: String, limit: float) -> void:
	var t := 0.0
	while t < limit and not type in s.elements_view.played:
		await _wait(0.03)
		t += 0.03
	print("played ", type, ": ", type in s.elements_view.played, " after ", t)


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

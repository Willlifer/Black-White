extends SceneTree
## D443-D463 Keystones v3 review renders (needs a window):
##   [SHOTS=<dir>] [ONLY=pick,duo,lava,abyssal,drowned,rain,sculptor] godot --path . --resolution 1920x1080 --script res://tools/ks3_shots.gd
## → design/art/ks3_pick.png       a fire unit's rank-3 keystone pick: Lava Walker / Island Maker, each card
##                                 naming the title it gives ("Name, the Lava Walker")
##   ks3_pick_titled.png           the same unit's card in battle after taking one (its titled name)
##   ks3_duo.png                   a fire perk pick showing the Wildfire Gale duo card
##   ks3_lava.png                  a Lava Walker's fire 5 / 4 / 3 beside a foe's water that fizzled on it; the
##                                 tile card on the lava
##   ks3_pitch_black.png           Abyssal's Pitch Black going off on a dark 3 among foes
##   ks3_drowned.png               a Drowned Leviathan (ring, DROWNED tag) aiming a basic across the board
##   ks3_drowned_lunge.png         the same blow mid-lunge (the view takes it to the target)
##   ks3_leviathos.png             Leviathos (the one-hex fallback): scaled up, double HP, a blow's splash forecast
##   ks3_rain.png / ks3_rain_after.png   Being of Rain walking under its cloud; the water it leaves
##   ks3_sculptor.png              a Sculptor's pillars, an ally standing on one (high ground)
var out := ""
var s: BWCombatScreen
var only: PackedStringArray


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	only = OS.get_environment("ONLY").split(",", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


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


func _snap(name: String) -> void:            # no banner wait: a moment mid-event
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _backdrop() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.theme = BWStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	root.add_child(c)
	return c


func _pick_shot(u: BWUnit, req: Dictionary, want: String, shot: String, after: String) -> void:
	for sd in range(1, 600):
		u.pick_seed = sd
		if want in BWPicks.options(u, req).map(func(o): return str(o.id)):
			break
	var ids: Array = BWPicks.options(u, req).map(func(o): return str(o.id))
	print(shot, ": seed ", u.pick_seed, " options ", ids)
	var back := _backdrop()
	var p := BWPicker.new(u, req, after)
	back.add_child(p)
	await _wait(1.0)
	p.select(maxi(0, ids.find(want)))
	await _wait(0.4)
	await _shot(shot)
	back.queue_free()
	await _wait(0.2)


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
	BWItemIcons.ensure(root)
	BWSettings.put("cutscenes", "minimal")
	var roster := BWData.table("roster")
	var used: Array = []
	if _want("pick") or _want("duo"):
		var fu := BWUnit.from_roster(_row(roster, "staff", "fire", used))
		fu.affinity["fire"] = 30
		BWPicks.auto_resolve(fu)
		fu.keystones.clear()
		if _want("pick"):
			await _pick_shot(fu, { "kind": "keystone", "element": "fire" }, "lava_walker", "ks3_pick", "after fight 3")
		if _want("duo"):
			var du := BWUnit.from_roster(_row(roster, "staff", "fire", used))
			du.affinity["fire"] = 20
			du.affinity["wind"] = 20
			du.perks = ["fire_rush", "wind_tail"]
			await _pick_shot(du, { "kind": "perk", "element": "fire" }, "duo_wildfire", "ks3_duo", "after fight 5")
	# ---- the board
	var lw := BWUnit.from_roster(_row(roster, "staff", "fire", used))
	var ab := BWUnit.from_roster(_row(roster, "staff", "dark", used))
	var lv := BWUnit.from_roster(_row(roster, "axe", "water", used))
	var br := BWUnit.from_roster(_row(roster, "sword", "water", used))
	var sc := BWUnit.from_roster(_row(roster, "staff", "ice", used))
	var al := BWUnit.from_roster(_row(roster, "lance", "fire", used))
	lw.keystones = ["lava_walker"]
	ab.keystones = ["abyssal"]
	lv.keystones = ["leviathan"]
	br.keystones = ["being_of_rain"]
	sc.keystones = ["sculptor"]
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "wind", used)))
	var mine: Array = [lw, ab, lv, br, sc, al]
	for u in mine + enemies:
		u.stats["con"] = 40
	s = BWCombatScreen.new()
	s.configure("res://maps/commons.json", mine, enemies, [], 6)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	var f := _flat_centre(b)
	var park := _open(b, f, 400)
	var far_spots: Array = park.slice(park.size() - 12)
	var all: Array = mine + enemies
	for i in all.size():
		_place(all[i], far_spots[i])
	s.rig.pitch = deg_to_rad(55.0)

	if _want("pick"):
		BWKeystones.grant(lw, "lava_walker")
		_place(lw, f)
		await _settle()
		_turn(lw)
		s.ui.set_card(lw, b.tiles, lw)
		_look(f, _step(f, 0, 1), 11.0)
		await _wait(0.8)
		print("titled: ", BWKeystones.titled(lw))
		await _shot("ks3_pick_titled")
		_place(lw, far_spots[0])

	if _want("lava"):
		var x := _step(f, 0, 1)
		var y := _step(x, 0, 1)
		var z := _step(y, 0, 1)
		_place(lw, _step(f, 3, 1))
		_place(enemies[0], _step(y, 1, 1))
		_place(enemies[1], _step(x, 5, 1))
		b.paint([x], "fire", lw, 3)
		b.paint([x], "fire", lw, 2)                  # fire 5
		b.paint([y], "fire", lw, 3)
		b.paint([y], "fire", lw, 1)                  # fire 4
		b.paint([z], "fire", lw, 3)                  # fire 3 (lava, still)
		var r := b.paint([y, _step(y, 1, 1)], "water", enemies[0], 2)
		print("lava: x %d y %d z %d, fizzled %s" % [b.tiles.intensity(x, "fire"), b.tiles.intensity(y, "fire"), b.tiles.intensity(z, "fire"), r.fizzled])
		await _settle()
		_turn(lw)
		s._show_options()
		_look(x, z, 10.0)
		s._hover = x
		s._on_hover(x)
		await _wait(1.6)
		print("lava card: ", s.readability.card_text())
		await _shot("ks3_lava")
		s._hover = Vector2i(-99, -99)
		b.tiles.entries.clear()
		_place(lw, far_spots[0])
		_place(enemies[0], far_spots[6])
		_place(enemies[1], far_spots[7])
		await _settle()

	if _want("abyssal"):
		var x := _step(f, 0, 2)
		_place(ab, f)
		_place(enemies[0], _step(x, 1, 1))
		_place(enemies[1], _step(x, 5, 1))
		_place(enemies[2], _step(x, 0, 1))
		b.paint([x], "dark", ab, 3)
		await _settle()
		_turn(ab)
		_look(f, x, 11.0)
		await _wait(0.8)
		b.use_skill(ab, "pitch_black", "", x)
		s._after_events()
		await _wait(0.42)
		await _snap("ks3_pitch_black")
		var t := 0.0
		while s._busy and t < 15.0:
			await _wait(0.2)
			t += 0.2
		print("pitch black: dark now ", b.tiles.intensity(x, "dark"))
		b.tiles.entries.clear()
		for i in 3:
			_place(enemies[i], far_spots[6 + i])
		_place(ab, far_spots[1])
		await _settle()

	if _want("drowned"):
		var x := _step(f, 3, 2)
		_place(lv, x)
		b.tiles.entries[x] = b.tiles._entry(-3, 0, "", lv.id, "cast")
		_place(enemies[0], _step(f, 0, 4))
		lv.fx["lev"] = "drowned"
		lv.fx["lev_used"] = true
		await _settle()
		_turn(lv)
		lv.fx["lev"] = "drowned"
		_look(x, enemies[0].pos, 15.0)
		s._on_click(enemies[0].pos)
		await _wait(1.4)
		await _shot("ks3_drowned")
		b.expected_rolls = true
		s._on_action("confirm")
		await _wait(0.5)
		await _snap("ks3_drowned_lunge")
		var t2 := 0.0
		while s._busy and t2 < 15.0:
			await _wait(0.2)
			t2 += 0.2
		b.expected_rolls = false
		# Leviathos (D451b fallback): one hex, double HP, scaled up; its blow splashes
		lv.fx["lev"] = "submerged"
		lv.fx["lev_turn"] = -1
		_place(lv, f)
		_place(enemies[0], _step(f, 0, 1))
		_place(enemies[1], _step(_step(f, 0, 1), 1, 1))
		await _settle()
		_turn(lv)
		b.apply_pick(lv, BWKs3Water.request(b, lv), "leviathos")
		s._after_events()
		var t5 := 0.0
		while s._busy and t5 < 10.0:
			await _wait(0.2)
			t5 += 0.2
		_turn(lv)
		_look(lv.pos, enemies[0].pos, 13.0)
		s._on_click(enemies[0].pos)
		await _wait(1.3)
		print("leviathos hp ", lv.hp, "/", lv.max_hp(), " forecast open ", s.ui.forecast_open())
		await _shot("ks3_leviathos")
		if s.ui.forecast_open():
			s._on_action("cancel")
		b.tiles.entries.clear()
		_place(lv, far_spots[2])
		_place(enemies[0], far_spots[6])
		_place(enemies[1], far_spots[7])
		await _settle()

	if _want("rain"):
		_place(br, f)
		await _settle()
		_turn(br)
		var dest := _step(f, 0, 4)
		_look(f, dest, 14.0)
		await _wait(0.6)
		s._on_click(dest)
		await _wait(1.0)
		await _snap("ks3_rain")
		var t3 := 0.0
		while s._busy and t3 < 15.0:
			await _wait(0.2)
			t3 += 0.2
		await _wait(0.8)
		await _shot("ks3_rain_after")
		b.tiles.entries.clear()
		_place(br, far_spots[3])
		await _settle()

	if _want("sculptor"):
		var c := _step(f, 0, 1)
		_place(sc, _step(f, 3, 1))
		var spots := [c, _step(c, 1, 1), _step(c, 5, 1), _step(c, 0, 2)]
		for h in spots:
			b.tiles.entries[h] = b.tiles._entry(-1, 0, "", sc.id, "cast")
			b.tiles.entries[h].glaze = 2
		_turn(sc)
		b.paint(spots, "ice", sc)
		print("sculpted: ", spots.filter(func(h): return BWKs3Ice.sculpted(b.tiles, h)))
		_place(al, _step(c, 0, 1))
		await _settle()
		_turn(al)
		var r2 := b.reachable(al)
		print("ally may climb: ", r2.has(c))
		b.move(al, c)
		s._after_events()
		var t4 := 0.0
		while s._busy and t4 < 10.0:
			await _wait(0.2)
			t4 += 0.2
		_place(al, c)
		_place(enemies[0], _step(c, 2, 2))
		await _settle()
		_turn(al)
		s._on_hover(enemies[0].pos)
		_look(_step(c, 3, 1), _step(c, 3, 1), 13.0)
		await _wait(1.2)
		print("ally elevation: ", b.board.elevation(al.pos))
		await _shot("ks3_sculptor")
	await _wait(0.3)
	quit(0)


func _look(a: Vector2i, c: Vector2i, dist: float) -> void:
	var b := s.battle
	var mid := (BWLook.world(a, b.board.ground_elevation(a)) + BWLook.world(c, b.board.ground_elevation(c))) * 0.5
	s.rig.dist = dist
	var cam := root.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam else Vector3.ZERO
	right.y = 0.0
	s.rig.follow(mid + right.normalized() * dist * 0.16, true)


func _step(h: Vector2i, d: int, n: int) -> Vector2i:
	var c := h
	for i in n:
		c = BWHex.neighbors(c)[d]
	return c


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
	u.cooldowns.clear()
	s.ui.set_acting(u, b.tiles)
	s._show_options()


func _place(u: BWUnit, h: Vector2i) -> void:
	if h == Vector2i(-1, -1):
		return
	u.pos = h
	var v: Node3D = s._views[u.id]
	v.position = s._unit_pos(h)


func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 4):
			if b.board.is_passable(a) and b.board.ground_elevation(a) == b.board.ground_elevation(h):
				k += 1
		k = k * 100 - BWHex.distance(h, b.board.camera_focus)
		if k > best_k:
			best_k = k
			best = h
	return best


func _open(b: BWBattle, c: Vector2i, n: int) -> Array:
	var out_h: Array = []
	for r in 14:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out_h.size() >= n:
				return out_h
			if b.board.is_passable(h) and not b.board.blocked(h) and b.unit_at(h) == null:
				out_h.append(h)
	return out_h

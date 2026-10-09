extends SceneTree
## D493-D495 review renders (needs a window):
##   [SHOTS=<dir>] [ONLY=split,lava,hp] [RES=1920x1080] godot --path . --script res://tools/fix492_shots.gd
## fix492_split_gear.png    Split Front's pre-battle with Equipment open: no mode plate over the panel (D493)
## fix492_split_back.png    the panel closed again: the plate is back
## fix492_lava4.png         a Lava Walker 4 tile, hovered: its tile card (D494)
## fix492_hpbars.png        a fight: ally bars black with white pips, enemy bars white with black pips (D495)
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	var res := OS.get_environment("RES")
	if res == "":
		res = "1920x1080"
	var wh := res.split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = root.get_final_transform() * p
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await process_frame
	await process_frame


func _go() -> void:
	BWSettings.put("cutscenes", "fast")
	BWMusic.ensure(root)
	var only := OS.get_environment("ONLY")
	if only == "" or "split" in only:
		await _split()
	if only == "" or "lava" in only:
		await _lava()
	if only == "" or "hp" in only:
		await _hp()
	quit()


## A run at fight n with its six levelled and geared (as mode_shots does).
static func run_at(n: int, seed_value: int) -> BWRun:
	var r := BWRun.start(BWData.table("roster").slice(0, 6).map(func(x): return str(x.id)), seed_value)
	for u in r.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(x): return x.slot == slot)
			u.equipment[slot] = r.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), r.tier_for(n))
		u.equipment["main_hand"] = r.make_item(u.weapon_model, r.tier_for(n))
	r.fight = n
	r.mode_override = { n: "splitfront" }
	return r


func _split() -> void:
	var run := run_at(BWRun.SPLIT_FIGHT, 1)
	for i in 8:
		run.inventory.append(run.random_item(["D", "C", "B"][i % 3]))
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(2.8)
	pre._open_overlay(pre._equip)
	await _wait(0.6)
	print("split gear: plate visible %s" % pre._mode_plate.plate_visible)
	await _shot("fix492_split_gear")
	pre._close_overlays()
	await _wait(0.3)
	print("split back: plate visible %s" % pre._mode_plate.plate_visible)
	await _shot("fix492_split_back")
	pre.queue_free()
	await process_frame


var s: BWCombatScreen


func _lava() -> void:
	var roster := BWData.table("roster")
	var used: Array = []
	var lw := BWUnit.from_roster(_row(roster, "staff", "fire", used))
	var al := BWUnit.from_roster(_row(roster, "sword", "fire", used))
	var al2 := BWUnit.from_roster(_row(roster, "axe", "ice", used))
	lw.keystones = ["lava_walker"]
	var enemies: Array = []
	for wc in ["sword", "lance", "axe"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "water", used)))
	for u in [lw, al, al2] + enemies:
		u.stats["con"] = 40
	await _screen("res://maps/commons.json", [lw, al, al2], enemies)
	var b := s.battle
	var f := _flat_centre(b)
	var park := _open(b, f, 400)
	var far: Array = park.slice(park.size() - 8)
	var all: Array = [lw, al, al2] + enemies
	for i in all.size():
		_place(all[i], far[i])
	# a row: fire 1, 2, 3 (a plain caster's), then the walker's lava 4
	var row: Array = [f]
	for i in 3:
		row.append(_step(row[-1], 0, 1))
	b.paint([row[0]], "fire", al, 1)
	b.paint([row[1]], "fire", al, 2)
	b.paint([row[2]], "fire", al, 3)
	b.paint([row[3]], "fire", lw, 3)
	b.paint([row[3]], "fire", lw, 1)
	_place(lw, _step(row[3], 1, 1))
	_place(enemies[0], _step(row[1], 5, 1))
	print("lava row: %s" % [row.map(func(h): return "%d%s" % [b.tiles.intensity(h, "fire"), "L" if b.tiles.is_lava(h) else ""])])
	s.board_view.refresh_tiles()
	_turn(lw)
	s.rig.pitch = deg_to_rad(52.0)
	_look(row[0], row[3], 11.0)
	s._hover = row[3]
	s._on_hover(row[3])
	await _wait(1.6)
	print("lava card: ", s.readability.card_text())
	print("lava ground: ", s.ui._ground_text(b.tiles.at(row[3])) if s.ui.has_method("_ground_text") else "?")
	await _shot("fix492_lava4")
	s.queue_free()
	await process_frame


func _hp() -> void:
	var r := run_at(6, 7)
	r.mode_override = {}
	var players: Array = r.squad.slice(0, 3)
	r.prepare_for_battle(players)
	var enemies: Array = r.enemies_for(6)
	await _screen("res://maps/arena.json", players, enemies)
	var b := s.battle
	players = b.side("player")
	enemies = b.side("enemy")
	# full, half and low on each side, so the empty part shows on both
	var fr := [1.0, 0.55, 0.22]
	for i in players.size():
		players[i].hp = maxi(1, int(round(players[i].max_hp() * fr[i % 3])))
	for i in enemies.size():
		enemies[i].hp = maxi(1, int(round(enemies[i].max_hp() * fr[(i + 1) % 3])))
	# close together in the middle: three a side, two hexes apart
	var f := _flat_centre(b)
	var spots := _open(b, f, 30)
	var lane: Array = [_step(f, 3, 1), f, _step(f, 0, 1)]
	for i in 3:
		_place(players[i], _step(lane[i], 4, 1))
		_place(enemies[i], _step(lane[i], 2, 1))
	for id in s._views:
		s._views[id].refresh()
	await _wait(1.2)
	var c := Vector3.ZERO
	for u in players + enemies:
		c += s._views[u.id].global_position
	s.rig.follow(c / float(players.size() + enemies.size()), true)
	s.rig.dist = 11.0
	s.rig.pitch = deg_to_rad(42.0)
	BWHPBar3D.hover_unit = null
	s.ui.set_card(players[1], b.tiles, players[1])
	await _wait(1.2)
	print("hp bars: ", (players + enemies).map(func(u): return "%s %s %d/%d %s" % [u.team, u.name, u.hp, u.max_hp(), s._views[u.id]._hp_bar.mode()]))
	await _shot("fix492_hpbars")
	s.queue_free()
	await process_frame


func _screen(map: String, players: Array, enemies: Array) -> void:
	s = BWCombatScreen.new()
	s.configure(map, players, enemies, [], 6)
	s.autoplay = false
	root.add_child(s)
	var t := 0.0
	await _wait(2.0)
	while (s._busy or s.battle.current() == null or s.battle.current().team != "player") and t < 60.0:
		await _wait(0.2)
		t += 0.2
	if s.ui.has_method("banner_gone"):
		await s.ui.banner_gone()


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


func _look(a: Vector2i, c: Vector2i, dist: float) -> void:
	var b := s.battle
	var mid := (BWLook.world(a, b.board.ground_elevation(a)) + BWLook.world(c, b.board.ground_elevation(c))) * 0.5
	s.rig.dist = dist
	s.rig.follow(mid, true)


func _step(h: Vector2i, d: int, n: int) -> Vector2i:
	var c := h
	for i in n:
		c = BWHex.neighbors(c)[d]
	return c


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

extends SceneTree
## D425-D432 review renders on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=enpassant,riposte,charge,leap,fan] [CUT=fast] godot --path . --resolution 1600x900 --script res://tools/kit2_shots.gd
## → design/art/kit2_<mode>_preview.png (the aim / the set-up) and frames in
##   <SHOTS>/kit2_frames/<mode>/NN.png (python tools/kit2_strip.py makes the
##   kit2_<mode>_strip.png sheets). AUTO=1: an AI-vs-AI fight on Commons with
##   sword / lance / dagger squads carrying the new skills (Blade Dance
##   included), no shots; it prints KIT2 AUTO and the skills used.
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


func _kit(u: BWUnit, keys: Array) -> void:
	for k in keys:
		if not k in u.known_skills:
			u.known_skills.append(k)
	u.skill_loadout[u.weapon_class] = keys.filter(func(k): return not BWWeaponMove.is_passive(k))


func _frames(mode: String, dt: float, n: int, go: Callable) -> void:
	var dir := "%s/kit2_frames/%s" % [out, mode]
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	Engine.time_scale = 0.3
	go.call()
	for i in n:
		await _wait(dt)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d.png" % [dir, i])
	Engine.time_scale = 1.0
	var t := 0.0
	while s._busy and t < 20.0:
		await _wait(0.2)
		t += 0.2


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", OS.get_environment("CUT") if OS.get_environment("CUT") != "" else "fast")
	if OS.get_environment("AUTO") != "":
		await _auto()
		return
	var roster := BWData.table("roster")
	var used: Array = []
	var sword := BWUnit.from_roster(_row(roster, "sword", "fire", used))
	var lance := BWUnit.from_roster(_row(roster, "lance", "thunder", used))
	var dag := BWUnit.from_roster(_row(roster, "daggers", "fire", used))
	var enemies: Array = []
	for wc in ["axe", "bow", "staff"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "water", used)))
	for u in [sword, lance, dag] + enemies:
		u.stats["con"] = 60
		u.stats["dex"] = 40
	_kit(sword, ["en_passant", "riposte", BWKit2.BLADE_DANCE])
	_kit(lance, ["lance_charge", "vault"])
	_kit(dag, ["daggerleap", "fan_of_knives", "consume"])
	s = BWCombatScreen.new()
	s.configure("res://maps/commons.json", [sword, lance, dag], enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	b.expected_rolls = true
	var all: Array = [sword, lance, dag] + enemies
	var c := _flat_centre(b)
	var d := _long_dir(b, c)
	var start := _step(c, (d + 3) % 6, 3)
	var park := _open(b, c, 300)
	var far_spots: Array = park.slice(park.size() - 8)
	var reset := func():
		s._queue.clear()
		b.tiles.entries.clear()
		for i in all.size():
			_place(all[i], far_spots[i])
			all[i].riposte = {}
			all[i].fx.erase("lance_charge")
			all[i].fx.erase(BWKit2.BARRIER)
			all[i].hp = all[i].max_hp()
	reset.call()
	s.rig.pitch = deg_to_rad(55.0)

	if _want("enpassant"):
		_place(sword, start)
		var tgt := _step(start, d, 2)
		var land := _step(start, d, 3)
		_place(enemies[0], tgt)
		_place(enemies[1], _step(land, (d + 1) % 6, 1))
		await _settle()
		_turn(sword)
		s._skill = { "key": "en_passant", "element": "fire", "row": BWSkills.get_skill("en_passant") }
		s._show_options()
		s._on_hover(tgt)
		_look(start, _step(start, d, 4), 13.0)
		await _wait(1.0)
		await _shot("kit2_enpassant_preview")
		# the blocked case: a foe on the landing turns it red
		_place(enemies[2], land)
		s._hover = Vector2i(-99, -99)
		s._show_options()
		s._on_hover(tgt)
		await _wait(0.6)
		await _shot("kit2_enpassant_blocked")
		_place(enemies[2], far_spots[5])
		s._hover = Vector2i(-99, -99)
		s._on_hover(tgt)
		await _wait(0.3)
		await _frames("enpassant", 0.06, 26, func():
			s._aim_skill(sword, tgt)
			s._on_action("confirm"))
		print("en passant: sword at ", sword.pos, " follow ", sword.follow_up)
		# the Passing Cut, then Blade Dance's prompt
		var side: BWUnit = enemies[1]
		await _frames("passing", 0.08, 16, func():
			s._on_skill_chosen("en_passant_strike", "fire")
			s._aim_skill(sword, side.pos)
			s._on_action("confirm"))
		await _wait(0.6)
		print("dance pending ", BWKit2.dance_pending(b, sword))
		_look(sword.pos, sword.pos, 11.0)
		await _wait(0.6)
		await _shot("kit2_dance_prompt")
		reset.call()
		await _settle()

	if _want("riposte"):
		_place(sword, c)
		_place(enemies[0], _step(c, d, 5))
		await _settle()
		_turn(sword)
		b.use_skill(sword, "riposte", "fire", sword.pos)
		s._queue.clear()
		_look(_step(c, (d + 3) % 6, 3), _step(c, d, 3), 15.0)
		await _wait(1.0)
		await _shot("kit2_riposte_guard")
		await _frames("riposte", 0.06, 22, func():
			b.queue = [sword] + b.queue.filter(func(x): return x != sword)
			b.turn_index = 0
			b._begin_turn()
			s._after_events())
		await _wait(0.5)
		await _shot("kit2_riposte_after")
		reset.call()
		await _settle()

	if _want("charge"):
		var lr := _longest(b)
		var ls: Vector2i = lr[0]
		d = lr[1]
		_place(lance, ls)
		await _settle()
		_turn(lance)
		var aim := _step(ls, d, 8)
		print("charge aim legal: ", aim in b.skill_targets(lance, "lance_charge", "thunder"))
		s._skill = { "key": "lance_charge", "element": "thunder", "row": BWSkills.get_skill("lance_charge") }
		s._show_options()
		s._on_hover(aim)
		_look(ls, aim, 17.0)
		await _wait(1.0)
		await _shot("kit2_charge_aim")
		s._aim_skill(lance, aim)
		await _wait(1.5)
		_place(enemies[0], _step(ls, d, 3))
		_place(enemies[1], _step(ls, d, 6))
		await _settle()
		s._skill = {}
		s._show_options()
		await _wait(0.6)
		await _shot("kit2_charge_set")
		_look(ls, _step(ls, d, 8), 17.0)
		await _frames("charge", 0.12, 30, func():
			b.queue = [lance] + b.queue.filter(func(x): return x != lance)
			b.turn_index = 0
			b._begin_turn()
			s._after_events())
		await _wait(0.5)
		_look(ls, _step(ls, d, 8), 17.0)
		await _wait(0.8)
		await _shot("kit2_charge_after")
		print("charge: lance at ", lance.pos, " busy ", s._busy, " shown ", s.kit2_view.shown, " fx ", lance.fx.has("lance_charge"))
		reset.call()
		await _settle()

	if _want("leap"):
		c = _open(b, b.board.camera_focus, 1)[0]
		d = _long_dir(b, c)
		_place(dag, c)
		var land := _step(c, d, 3)
		_place(enemies[0], _step(land, d, 1))
		enemies[0].facing = (d + 0) % 6
		await _settle()
		_turn(dag)
		s._skill = { "key": "daggerleap", "element": "fire", "row": BWSkills.get_skill("daggerleap") }
		s._show_options()
		s._aim_skill(dag, land)
		var back := _step(land, (d + 2) % 6, 2)
		s._on_hover(back)
		_look(c, _step(c, d, 4), 13.0)
		await _wait(1.0)
		await _shot("kit2_leap_preview")
		_look(c, land, 12.0)
		BWSettings.put("cutscenes", "minimal")          # the board view: the leap in, the flourish, the leap away
		await _frames("leap", 0.2, 64, func():
			s._aim_skill(dag, back)
			s._on_action("confirm"))
		print("leap: dagger at ", dag.pos, " (back ", back, ")")
		await _wait(0.5)
		await _shot("kit2_leap_after")
		reset.call()
		await _settle()

	if _want("fan"):
		_place(dag, c)
		_place(enemies[0], _step(c, d, 1))
		_place(enemies[1], _step(c, (d + 2) % 6, 2))
		_place(enemies[2], _step(c, (d + 4) % 6, 2))
		b.tiles.apply([_step(c, (d + 1) % 6, 1)], "water", "x", 2)
		await _settle()
		_turn(dag)
		s._on_skill_chosen("fan_of_knives", "fire")
		_look(c, c, 13.0)
		await _wait(1.0)
		await _shot("kit2_fan_preview")
		BWSettings.put("cutscenes", "minimal")          # the knives fly over the board, radius 2
		await _frames("fan", 0.05, 26, func(): s._on_action("confirm"))
		await _wait(0.5)
		await _shot("kit2_fan_after")
	await _wait(0.3)
	quit(0)


## AUTO=1: one AI-vs-AI fight with the new kits on both sides.
func _auto() -> void:
	var roster := BWData.table("roster")
	var used: Array = []
	var p: Array = []
	var e: Array = []
	for side in [p, e]:
		var sw := BWUnit.from_roster(_row(roster, "sword", "fire" if side == p else "thunder", used))
		var la := BWUnit.from_roster(_row(roster, "lance", "water" if side == p else "ice", used))
		var dg := BWUnit.from_roster(_row(roster, "daggers", "thunder" if side == p else "fire", used))
		_kit(sw, ["en_passant", "riposte", "striketwice", BWKit2.BLADE_DANCE])
		_kit(la, ["lance_charge", "vault", "tridentpierce"])
		_kit(dg, ["daggerleap", "fan_of_knives", "consume"])
		side.append_array([sw, la, dg])
	s = BWCombatScreen.new()
	s.configure("res://maps/" + (OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "commons") + ".json", p, e, [], int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3)
	s.autoplay = true
	root.add_child(s)
	var t := 0.0
	while not s.battle.over and t < 600.0:
		await _wait(1.0)
		t += 1.0
	var used_k := {}
	for ev in s.battle.history:
		if ev.type == "skill":
			used_k[ev.skill] = int(used_k.get(ev.skill, 0)) + 1
		elif ev.type in ["riposte_release", "lance_charge_run", "blade_dance", "barrier"]:
			used_k[ev.type] = int(used_k.get(ev.type, 0)) + 1
	print("KIT2 AUTO over=%s winner=%s cycles=%d t=%ds used=%s" % [s.battle.over, s.battle.winner, s.battle.cycle, int(t), used_k])
	await _wait(1.0)
	quit(0)


func _look(a: Vector2i, c: Vector2i, dist: float) -> void:
	var b := s.battle
	var mid := (BWLook.world(a, b.board.elevation(a)) + BWLook.world(c, b.board.elevation(c))) * 0.5
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
	v.visible = true


## The start hex and heading with the longest open, level run (up to 9).
func _longest(b: BWBattle) -> Array:
	var best := [b.board.camera_focus, 0]
	var best_n := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		if not b.board.is_passable(h):
			continue
		for d in 6:
			var n := 0
			var cur: Vector2i = h
			for i in 9:
				cur = BWHex.neighbors(cur)[d]
				if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(h):
					break
				n += 1
			var score := n * 100 - BWHex.distance(_step(h, d, 4), b.board.camera_focus)
			if score > best_n:
				best_n = score
				best = [h, d]
	print("run from ", best[0], " heading ", best[1], " score ", best_n)
	return best


func _long_dir(b: BWBattle, c: Vector2i) -> int:
	var best := 0
	var best_n := -1
	for d in 6:
		var n := 0
		var cur := c
		var back := c
		for i in 10:
			cur = BWHex.neighbors(cur)[d]
			if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(c):
				break
			n += 1
		for i in 4:
			back = BWHex.neighbors(back)[(d + 3) % 6]
			if not b.board.exists(back) or not b.board.is_passable(back) or b.board.elevation(back) != b.board.elevation(c):
				n -= 3
				break
		if n > best_n:
			best_n = n
			best = d
	print("heading ", best, " open ", best_n)
	return best


func _flat_centre(b: BWBattle) -> Vector2i:
	var best := b.board.camera_focus
	var best_k := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		var k := 0
		for a in BWHex.area(h, 4):
			if b.board.is_passable(a) and b.board.elevation(a) == b.board.elevation(h):
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

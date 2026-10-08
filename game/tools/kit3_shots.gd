extends SceneTree
## D433-D442 review renders on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=cleave,arc,bellow,thread,tapestry,overload,kindle] [CUT=fast] godot --path . --resolution 1600x900 --script res://tools/kit3_shots.gd
## → design/art/kit3_<mode>_*.png (the aim / the result). AUTO=1 [MAP=commons]
## [SEED=n]: one AI-vs-AI fight with axe / sword / dagger kits carrying the new
## skills (no shots); prints KIT3 AUTO and the skills used.
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


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", OS.get_environment("CUT") if OS.get_environment("CUT") != "" else "fast")
	if OS.get_environment("AUTO") != "":
		await _auto()
		return
	var roster := BWData.table("roster")
	var used: Array = []
	var axe := BWUnit.from_roster(_row(roster, "axe", "light", used))
	var sword := BWUnit.from_roster(_row(roster, "sword", "fire", used))
	var dag := BWUnit.from_roster(_row(roster, "daggers", "dark", used))
	var enemies: Array = []
	for wc in ["lance", "bow", "staff", "sword"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "water", used)))
	for u in [axe, sword, dag] + enemies:
		u.stats["con"] = 60
		u.stats["dex"] = 40
	_kit(axe, ["cleave", "reckless_arc", "bellow", "sunder"])
	_kit(sword, ["thread_needle", "tapestry", "lunge"])
	_kit(dag, ["overload", "kindle", "fan_of_knives"])
	s = BWCombatScreen.new()
	s.configure("res://maps/commons.json", [axe, sword, dag], enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	b.expected_rolls = true
	var all: Array = [axe, sword, dag] + enemies
	var c := _flat_centre(b)
	var d := _long_dir(b, c)
	var park := _open(b, c, 300)
	var far_spots: Array = park.slice(park.size() - 9)
	var reset := func():
		s._queue.clear()
		b.tiles.entries.clear()
		for i in all.size():
			_place(all[i], far_spots[i])
			all[i].hp = all[i].max_hp()
			all[i].fx.erase("bellow")
			all[i].statuses.clear()
	reset.call()
	s.rig.pitch = deg_to_rad(55.0)
	var nb := func(h: Vector2i, k: int) -> Vector2i: return BWHex.neighbors(h)[(k + 6) % 6]

	if _want("cleave"):
		_place(axe, c)
		_place(enemies[0], nb.call(c, d))
		_place(enemies[1], nb.call(c, d + 3))
		_place(enemies[2], nb.call(c, d + 2))
		b.tiles.apply([nb.call(c, d + 1)], "light", axe.id, 1)
		await _settle()
		_turn(axe)
		s._skill = { "key": "cleave", "element": "light", "row": BWSkills.get_skill("cleave") }
		s._show_options()
		s._on_hover(nb.call(c, d))
		_look(c, c, 11.0)
		await _wait(1.0)
		await _shot("kit3_cleave_widened")
		s._aim_skill(axe, nb.call(c, d))
		s._on_action("confirm")
		await _busy()
		await _shot("kit3_cleave_after")
		reset.call()
		await _settle()

	if _want("arc"):
		_place(axe, c)
		_place(enemies[0], nb.call(c, d))
		_place(enemies[1], nb.call(c, d - 2))
		_place(enemies[2], nb.call(c, d + 3))
		await _settle()
		_turn(axe)
		s._skill = { "key": "reckless_arc", "element": "light", "row": BWSkills.get_skill("reckless_arc") }
		s._show_options()
		s._on_hover(nb.call(c, d))
		_look(c, c, 11.0)
		await _wait(1.0)
		await _shot("kit3_reckless_arc_preview")
		s._aim_skill(axe, nb.call(c, d))
		s._on_action("confirm")
		await _busy()
		await _shot("kit3_reckless_arc_after")
		reset.call()
		await _settle()

	if _want("bellow"):
		var lr := _longest(b)
		var ls: Vector2i = lr[0]
		var ld: int = lr[1]
		_place(axe, ls)
		_place(enemies[0], _step(ls, ld, 1))
		_place(enemies[1], _step(ls, ld, 6))
		_place(enemies[2], _step(ls, ld, 9))
		await _settle()
		_turn(axe)
		s._on_skill_chosen("bellow", "")
		await _busy()
		_look(ls, ls, 9.0)
		await _wait(0.8)
		await _shot("kit3_bellow_held")
		_turn(axe)
		s._skill = { "key": "sunder", "element": "light", "row": BWSkills.get_skill("sunder") }
		s._show_options()
		s._on_hover(_step(ls, ld, 1))
		_look(ls, _step(ls, ld, 9), 17.0)
		await _wait(1.0)
		await _shot("kit3_bellow_sunder_preview")
		s._aim_skill(axe, _step(ls, ld, 1))
		s._on_action("confirm")
		await _busy()
		_look(ls, _step(ls, ld, 9), 17.0)
		await _wait(0.6)
		await _shot("kit3_bellow_sunder_after")
		reset.call()
		await _settle()

	if _want("thread"):
		_place(sword, c)
		var tgt := _step(c, d, 1)
		_place(enemies[0], tgt)
		_place(enemies[1], _step(c, d + 1, 3))
		var line: Array = [tgt, _step(c, d, 2), _step(c, d, 3), _step(c, d, 4)]
		b.tiles.apply(line, "fire", sword.id, 1)
		await _settle()
		_turn(sword)
		s._skill = { "key": "thread_needle", "element": "fire", "row": BWSkills.get_skill("thread_needle") }
		s._show_options()
		s._on_hover(tgt)
		_look(c, _step(c, d, 4), 12.0)
		await _wait(1.0)
		await _shot("kit3_thread_preview")
		s._aim_skill(sword, tgt)
		s._on_action("confirm")
		await _busy()
		_look(c, _step(c, d, 4), 12.0)
		await _wait(0.5)
		await _shot("kit3_thread_after")
		print("thread: sword at ", sword.pos, " (line end ", line[-1], ")")
		reset.call()
		await _settle()

	if _want("tapestry"):
		_place(sword, c)
		_place(axe, _step(c, d + 2, 2))
		_place(enemies[0], _step(c, d, 2))
		_place(enemies[1], _step(c, d - 1, 3))
		_place(enemies[2], _step(c, d + 3, 3))           # off the element: spared
		var web: Array = [c, _step(c, d, 1), _step(c, d, 2), _step(c, d, 3), _step(c, d - 1, 1), _step(c, d - 1, 2),
			_step(c, d - 1, 3), _step(c, d + 2, 1), _step(c, d + 2, 2)]
		b.tiles.apply(web, "fire", sword.id, 1)
		await _settle()
		_turn(sword)
		_look(c, c, 13.0)
		s._on_skill_chosen("tapestry", "fire")
		await _wait(0.8)
		await _shot("kit3_tapestry_preview")
		BWSettings.put("cutscenes", "fast")
		s._on_action("confirm")
		await _wait(0.35)
		await _shot("kit3_tapestry_pulse")
		await _busy()
		await _wait(0.4)
		await _shot("kit3_tapestry_after")
		reset.call()
		await _settle()

	if _want("overload"):
		_place(dag, c)
		_place(enemies[0], _step(c, d, 1))
		_place(enemies[1], _step(c, d + 2, 2))
		_place(enemies[2], _step(c, d - 2, 3))          # 3 out: spared
		var charged: Array = [c, _step(c, d, 1), _step(c, d, 2), _step(c, d + 2, 2), _step(c, d + 2, 1), _step(c, d - 2, 3), _step(c, d + 3, 1)]
		b.tiles.apply(charged, "dark", dag.id, 1)
		b.tiles.apply([_step(c, d + 1, 1)], "thunder", dag.id, 1)
		await _settle()
		_turn(dag)
		_look(c, c, 12.0)
		s._on_skill_chosen("overload", "")
		await _wait(0.8)
		await _shot("kit3_overload_preview")
		s._on_action("confirm")
		await _wait(0.7)
		await _shot("kit3_overload_blast")
		await _busy()
		await _wait(0.4)
		await _shot("kit3_overload_after")
		reset.call()
		await _settle()

	if _want("kindle"):
		_place(dag, c)
		var tgt := _step(c, d, 3)
		_place(enemies[0], tgt)
		_place(enemies[1], _step(tgt, d + 1, 1))
		await _settle()
		_turn(dag)
		s._skill = { "key": "kindle", "element": "dark", "row": BWSkills.get_skill("kindle") }
		s._show_options()
		s._on_hover(tgt)
		_look(c, tgt, 12.0)
		await _wait(1.0)
		await _shot("kit3_kindle_preview")
		s._aim_skill(dag, tgt)
		s._on_action("confirm")
		await _busy()
		await _wait(0.4)
		await _shot("kit3_kindle_after")
	await _wait(0.3)
	quit(0)


## AUTO=1: one AI-vs-AI fight with the kit-3 skills on both sides.
func _auto() -> void:
	var roster := BWData.table("roster")
	var used: Array = []
	var p: Array = []
	var e: Array = []
	for side in [p, e]:
		var ax := BWUnit.from_roster(_row(roster, "axe", "fire" if side == p else "thunder", used))
		var sw := BWUnit.from_roster(_row(roster, "sword", "water" if side == p else "fire", used))
		var dg := BWUnit.from_roster(_row(roster, "daggers", "thunder" if side == p else "fire", used))
		_kit(ax, ["reckless_arc", "hook", "bellow"] if side == p else ["cleave", "charge", "hook"])
		_kit(sw, ["thread_needle", "lunge", "tapestry"])
		_kit(dg, ["overload", "kindle", "fan_of_knives"])
		side.append_array([ax, sw, dg])
	if OS.get_environment("LANCE") != "":
		var la := BWUnit.from_roster(_row(roster, "lance", "ice", used))
		_kit(la, ["sweep", "lance_charge", "vault"])
		p[1] = la
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
	print("KIT3 AUTO over=%s winner=%s cycles=%d t=%ds used=%s" % [s.battle.over, s.battle.winner, s.battle.cycle, int(t), used_k])
	await _wait(1.0)
	quit(0)


func _busy() -> void:
	await _wait(0.3)
	var t := 0.0
	while s._busy and t < 20.0:
		await _wait(0.2)
		t += 0.2
	await _wait(0.3)


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
		c = BWHex.neighbors(c)[(d + 6) % 6]
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


## The start hex and heading with the longest open, level run (up to 10).
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
			for i in 10:
				cur = BWHex.neighbors(cur)[d]
				if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(h):
					break
				n += 1
			var score := n * 100 - BWHex.distance(_step(h, d, 5), b.board.camera_focus)
			if score > best_n:
				best_n = score
				best = [h, d]
	return best


func _long_dir(b: BWBattle, c: Vector2i) -> int:
	var best := 0
	var best_n := -1
	for d in 6:
		var n := 0
		var cur := c
		for i in 6:
			cur = BWHex.neighbors(cur)[d]
			if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(c):
				break
			n += 1
		if n > best_n:
			best_n = n
			best = d
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

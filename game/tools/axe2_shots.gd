extends SceneTree
## D414-D416 review renders on the real combat screen (needs a window):
##   [SHOTS=<dir>] [ONLY=charge,sunder] [CUT=default|fast] godot --path . --resolution 1600x900 --script res://tools/axe2_shots.gd
## → design/art/axe2_charge_preview.png (Charge 7 aimed through a foe: the run and the push),
##   axe2_charge_strip.png (the run played, frames left to right: the foe pushed ahead),
##   axe2_sunder_preview.png (Sunder aimed: the 5-hex fissure painted, two foes grazed at 60%),
##   axe2_sunder_strip.png (the blow, the inked crack running out, the heave), axe2_sunder_after.png.
## Frames go to <SHOTS>/axe2_frames/<mode>/NN.png first.
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


## Play the confirmed action, saving a frame every `dt` while it runs.
func _frames(mode: String, dt: float, n: int, go: Callable = Callable()) -> void:
	var dir := "%s/axe2_frames/%s" % [out, mode]
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	Engine.time_scale = 0.25                  # slowed so the frames catch the run (saving a frame is slow)
	if go.is_valid():
		go.call()
	else:
		s._on_action("confirm")
	for i in n:
		await _wait(dt)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d.png" % [dir, i])
	Engine.time_scale = 1.0
	var t := 0.0
	while s._busy and t < 20.0:
		await _wait(0.2)
		t += 0.2


## The start hex and heading with the longest open, level run on the map.
func _longest(b: BWBattle) -> Array:
	var best := [b.board.camera_focus, 0]
	var best_n := -1
	var cells := b.board.cells()
	cells.sort()
	for h in cells:
		if not b.board.is_passable(h):
			continue
		var n := 0
		for d in 6:
			n = 0
			var cur: Vector2i = h
			for i in 10:
				cur = BWHex.neighbors(cur)[d]
				if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(h):
					break
				n += 1
			var score := mini(n, 10) * 100 - BWHex.distance(_step(h, d, 4), b.board.camera_focus)
			if score > best_n:
				best_n = score
				best = [h, d]
	print("run from ", best[0], " heading ", best[1], " score ", best_n)
	return best


## The heading from `c` with the longest open, level run (and its length).
func _long_dir(b: BWBattle, c: Vector2i) -> int:
	var best := 0
	var best_n := -1
	for d in 6:
		var n := 0
		var cur := c
		for i in 10:
			cur = BWHex.neighbors(cur)[d]
			if not b.board.exists(cur) or not b.board.is_passable(cur) or b.board.elevation(cur) != b.board.elevation(c):
				break
			n += 1
		if n > best_n:
			best_n = n
			best = d
	print("heading ", best, " open ", best_n)
	return best


func _go() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", OS.get_environment("CUT") if OS.get_environment("CUT") != "" else "fast")
	var roster := BWData.table("roster")
	var used: Array = []
	var axe := BWUnit.from_roster(_row(roster, "axe", "fire", used))
	var mate := BWUnit.from_roster(_row(roster, "staff", "ice", used))
	var mate2 := BWUnit.from_roster(_row(roster, "bow", "ice", used))
	var enemies: Array = []
	for wc in ["sword", "lance", "pistols"]:
		enemies.append(BWUnit.from_roster(_row(roster, wc, "water", used)))
	for u in [axe, mate, mate2] + enemies:
		u.stats["con"] = 60
	for k in ["charge", "sunder"]:
		if not k in axe.known_skills:
			axe.known_skills.append(k)
	axe.skill_loadout[axe.weapon_class] = ["charge", "sunder"]
	s = BWCombatScreen.new()
	s.configure("res://maps/" + OS.get_environment("MAP") + ".json" if OS.get_environment("MAP") != "" else "res://maps/commons.json", [axe, mate, mate2], enemies, [], 4)
	s.autoplay = false
	root.add_child(s)
	await _idle()
	var b := s.battle
	b.expected_rolls = true
	var all: Array = [axe, mate, mate2] + enemies
	var best_run := _longest(b)
	var start: Vector2i = best_run[0]
	var d: int = best_run[1]
	var c := _step(start, d, 4)
	var park := _open(b, c, 300)
	var far_spots: Array = park.slice(park.size() - 8)
	for i in all.size():
		_place(all[i], far_spots[i])
	s.rig.pitch = deg_to_rad(55.0)

	if _want("charge"):
		_place(axe, start)
		_place(enemies[0], _step(start, d, 2))
		await _settle()
		_turn(axe)
		var aim := _step(start, d, 1)
		s._skill = { "key": "charge", "element": "fire", "row": BWSkills.get_skill("charge") }
		s._show_options()
		s._on_hover(aim)                          # Charge has no forecast: a click resolves it, so the hover is its preview
		_look(start, _step(start, d, 8), 15.0)
		await _wait(1.2)
		print("targets ", b.skill_targets(axe, "charge", "fire"), " cur ", b.current().id, " at ", axe.pos)
		var pv := b.skill_preview(axe, "charge", "fire", aim)
		print("charge preview: dest ", pv.dest, " shove ", pv.get("shove", {}).get("to", null), " notes ", pv.notes)
		await _shot("axe2_charge_preview")
		await _frames("charge", 0.05, 16, func(): s._aim_skill(axe, aim))
		print("charge: axe ", axe.pos, " foe ", enemies[0].pos)
		s._queue.clear()
		b.tiles.entries.clear()
		for i in all.size():
			_place(all[i], far_spots[i])
		await _settle()

	if _want("sunder"):
		_place(axe, start)
		var tgt := _step(start, d, 1)
		_place(enemies[0], tgt)
		_place(enemies[1], _step(start, d, 3))
		_place(enemies[2], _step(start, d, 5))
		await _settle()
		_turn(axe)
		s._skill = { "key": "sunder", "element": "fire", "row": BWSkills.get_skill("sunder") }
		s._aim_skill(axe, tgt)
		_look(start, _step(start, d, 5), 14.0)
		await _wait(1.2)
		var pv2 := b.skill_preview(axe, "sunder", "fire", tgt)
		print("sunder preview: hexes ", pv2.hexes, " units ", pv2.units, " notes ", pv2.notes)
		await _shot("axe2_sunder_preview")
		await _frames("sunder", 0.12, 44)
		await _wait(0.8)
		_look(start, _step(start, d, 5), 14.0)
		await _wait(0.8)
		await _shot("axe2_sunder_after")
	await _wait(0.3)
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
	var out_h: Array = []
	for r in 12:
		var ring: Array = [c] if r == 0 else Array(BWHex.ring(c, r))
		for h in ring:
			if out_h.size() >= n:
				return out_h
			if b.board.is_passable(h) and not b.board.blocked(h) and b.unit_at(h) == null:
				out_h.append(h)
	return out_h

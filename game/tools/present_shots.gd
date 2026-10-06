extends SceneTree
## Review renders for the presentation pass (D100-D102), from the real
## combat screen (needs a window, not headless):
##   SHOTS=<dir> MODE=callout|crit|status godot --path . --resolution 1920x1080 --script res://tools/present_shots.gd
## callout  a skill cutscene paused on its callout -> <dir>/present_callout_<w>x<h>.png
## crit     the same cutscene with a crit: every frame from just before the
##          impact to just after the flash -> <dir>/crit_frames/NNN.png
##          (tools/present_strip.py makes the strip and the GIF)
## status   Pinned / Staggered / Blinded floating, a Frost Ward on one unit,
##          its card, a gale 2 hex beside a gale 1 hex, then the ward shattering
##          -> <dir>/present_status.png, <dir>/ward_frames/NNN.png
var out := ""
var s: BWCombatScreen
var _cap_dir := ""
var _cap_n := 0


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout      # real seconds, whatever the time scale


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("shot ", path)


func _go() -> void:
	var wres := OS.get_environment("RES")             # e.g. 1920x1080 (the project starts maximized)
	if wres.contains("x"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3:
			await process_frame
		DisplayServer.window_set_size(Vector2i(int(wres.get_slice("x", 0)), int(wres.get_slice("x", 1))))
		for i in 3:
			await process_frame
	var mode := OS.get_environment("MODE")
	var p: Array = []
	var e: Array = []
	var second := OS.get_environment("UNIT") if OS.get_environment("UNIT") != "" else "rem"
	for id in ["della", second, "will"]:
		var row := BWRosterKits.row(id)
		if row.is_empty():
			row = BWData.table("roster")[p.size()]
		p.append(BWUnit.from_roster(row))
	var roster := BWData.table("roster")
	var taken := p.map(func(u): return u.id)
	for row in roster:
		if e.size() < 3 and not str(row.id) in taken:
			e.append(BWUnit.from_roster(row))
	for u in p:
		u.stats["spd"] = 20
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", p, e, [], 3)
	root.add_child(s)
	await _wait(1.6)
	var a: BWUnit = s.battle._unit(p[0].id)
	var d: BWUnit = s.battle._unit(e[0].id)
	# stand the foe next to the attacker, both facing
	d.pos = BWHex.neighbors(a.pos)[0]
	if not s.battle.board.is_passable(d.pos) or s.battle.unit_at(d.pos) != null and s.battle.unit_at(d.pos) != d:
		for n in BWHex.neighbors(a.pos):
			if s.battle.board.is_passable(n) and s.battle.unit_at(n) == null:
				d.pos = n
				break
	s._views[d.id].position = s.board_view.top_center(d.pos)
	s._face_all()
	await _wait(0.4)
	var res := { "hit": true, "crit": mode == "crit", "glance": false, "resisted": false, "damage": 34 }
	var results := [{ "target": d.id, "result": res, "ko": false, "target_hp": maxi(d.hp - 34, 1), "tags": [] }]
	match mode:
		"crit":
			_cap_dir = out + "/crit_frames"
			DirAccess.make_dir_recursive_absolute(_cap_dir)
			BWCombatUI.flash_slow = float(OS.get_environment("SLOW")) if OS.get_environment("SLOW") != "" else 1.0
			s._cutscene(a.id, results, "", [], "", "")
			await _wait(0.5)
			await _capture_for(2.6 + 0.3 * BWCombatUI.flash_slow)
			await _wait(2.0)
		"status":
			await _status(p, e)
		"clip":
			# a skill clip in the real cutscene: CLIP=spin (Rem's daggers) or pistol_whip (UNIT=<id>)
			var who := OS.get_environment("UNIT")
			var att: BWUnit = s.battle._unit(who) if who != "" and s.battle._unit(who) else s.battle._unit(p[1].id)
			if att.id == d.id:
				d = s.battle._unit(e[1].id)
				results[0].target = d.id
			d.pos = BWHex.neighbors(att.pos)[0]
			for n in BWHex.neighbors(att.pos):
				if s.battle.board.is_passable(n) and s.battle.unit_at(n) == null:
					d.pos = n
					break
			s._views[d.id].position = s.board_view.top_center(d.pos)
			var clip := OS.get_environment("CLIP")
			_cap_dir = out + "/clip_frames"
			DirAccess.make_dir_recursive_absolute(_cap_dir)
			s._cutscene(att.id, results, clip.capitalize(), [], "", clip, { "word": "", "element": "", "name": clip.capitalize(), "text": clip })
			await _wait(0.45 + BWCombatUI.CALLOUT_IN + BWCombatUI.CALLOUT_HOLD)
			var an: BWAnimator = s._views[att.id].character.animator
			var seen := {}
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 2500:
				await process_frame
				seen[an.top_clip()] = true
				if an.has_method("spin_yaw") and an.spin_yaw() > 0.0:
					seen["spin_yaw>0"] = true
			print("CLIPS ", seen.keys())
		_:
			var call := s._callout_for(_skill_key(a), "fire")
			var cn := OS.get_environment("CALLOUT_NAME")      # D173 review: a given name ("Bolt", "Elemental Truth")
			if cn != "":
				call = { "word": "Light", "element": "light", "name": cn, "text": "Light " + cn }
			if call.is_empty():
				call = { "word": "Fire", "element": "fire", "name": "Tempest", "text": "Fire Tempest" }
			s._cutscene(a.id, results, str(call.name), [], str(call.element) if call.element != "" else "fire", "", call)
			await _wait(0.45 + BWCombatUI.CALLOUT_IN + 0.3)
			var tag := ("_" + cn.to_lower().replace(" ", "_")) if cn != "" else ""
			await _shot("%s/present_callout%s_%dx%d.png" % [out, tag, int(root.size.x), int(root.size.y)])
			await _wait(4.0)
	quit()


func _skill_key(u: BWUnit) -> String:
	var rows: Array = s.battle.skills_for(u)
	for r in rows:
		if (r.get("elements", []) as Array).size() > 0 and "fire" in r.get("elements", []):
			return str(r.key)
	return str(rows[0].key) if not rows.is_empty() else ""


## Save every rendered frame for `secs` (real time); present_strip.py
## finds the flash in them.
func _capture_for(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%03d.png" % [_cap_dir, _cap_n])
		_cap_n += 1
	print("captured ", _cap_n, " frames")


func _status(p: Array, e: Array) -> void:
	var w: BWUnit = s.battle._unit(p[1].id)
	p = p.map(func(u): return s.battle._unit(u.id))
	e = e.map(func(u): return s.battle._unit(u.id))
	# the camera close on the warded unit, two gale hexes beside it
	var free: Array = []
	for h in BWHex.neighbors(w.pos) + s.battle.board.area(w.pos, 2):
		if s.battle.board.is_passable(h) and s.battle.unit_at(h) == null and s.battle.tiles.can_hold(h) and not h in free:
			free.append(h)
	if free.size() >= 2:
		s.battle.tiles.author(free[0], 0, 0, "gale")
		s.battle.tiles.author(free[1], 0, 0, "gale")
		s.battle.tiles.entries[free[1]]["gale_level"] = 2
		s.board_view.refresh_tiles()
	# neighbours to wear the statuses
	var near: Array = []
	for u in p + e:
		if u != w:
			near.append(u)
	near.sort_custom(func(x, y): return BWHex.distance(x.pos, w.pos) < BWHex.distance(y.pos, w.pos))
	var keys := ["pinned", "staggered", "blinded"]
	var wearers: Array = [w, near[1], near[2]]       # the nail on the unit in the middle of the shot
	w = near[0]                                      # ... and the ward beside it
	for k in 3:
		var u: BWUnit = wearers[k]
		u.statuses[keys[k]] = { "armed": false, "source": w.id }
		s._queue.append({ "type": "status", "unit": u.id, "status": keys[k], "label": keys[k].capitalize(), "rule": "" })
	w.statuses["frost_ward"] = { "armed": false, "source": w.id }
	s._queue.append({ "type": "ward", "unit": w.id })
	s.rig.following = false
	s.rig.pivot = s._views[wearers[0].id].global_position + Vector3(0, 0.8, 0)
	s.rig.dist = 13.0
	s.rig.pitch = deg_to_rad(34.0)
	await _wait(0.6)
	s._after_events()
	s.rig.following = false
	await _wait(0.45)
	s.ui.set_card(wearers[0], s.battle.tiles, null)
	s.ui.set_acting(w, s.battle.tiles)
	await _wait(0.1)
	await _shot(out + "/present_status.png")
	await _wait(2.0)
	await _shot(out + "/present_ward.png")
	_cap_dir = out + "/ward_frames"
	DirAccess.make_dir_recursive_absolute(_cap_dir)
	w.statuses.erase("frost_ward")
	s._queue.append({ "type": "ward_break", "unit": w.id, "element": "fire" })
	s._after_events()
	await _capture_for(0.9)
	await _wait(0.5)

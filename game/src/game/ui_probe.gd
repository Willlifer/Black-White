class_name BWUIProbe
extends Node
## Drives the real combat screen with synthetic input events (mouse moves,
## clicks, keys at projected screen positions) and checks the battle
## responded. Proves the human input path, which autoplay bypasses.
## `godot --path game -- --ui-probe` (needs a window). Exit 0 = all passed.

var screen: BWCombatScreen
var _fails: PackedStringArray = []
var _passes := 0


func _ready() -> void:
	var roster := BWData.table("roster")
	var players: Array = []
	var enemies: Array = []
	# D154: the roll is the fixed seed's (boot sets it for probes); by seat, the
	# first staff holder (the skill path), the first axe, the first daggers
	# (Fan of Knives); the enemies are the first three seats left over.
	var used := {}
	for wc in ["staff", "axe", "daggers"]:
		for row in roster:
			if str(row.weapon_class) == wc and not used.has(row.id):
				used[row.id] = true
				players.append(BWUnit.from_roster(row))
				break
	for row in roster:
		if enemies.size() < 3 and not used.has(row.id):
			enemies.append(BWUnit.from_roster(row))
	for u in players:
		u.stats["spd"] = 20          # players act first, deterministically
	# D109/D110: Transfer (a second click) for the staff, Fan of Knives (a confirm step) for the daggers
	_learn(players[0], "transfer")
	players[0].stats["spd"] = 40     # the staff first, for the Transfer clicks
	_learn(players[2], "fan_of_knives")
	# D181: the axe holder carries a bow too (the swap probe)
	var kit := BWRun.new()
	players[1].equipment["main_hand"] = kit.make_item(players[1].weapon_model, "E")
	players[1].equipment["second"] = kit.make_item("shortbow", "C")
	players[1].sync_weapon()
	screen = BWCombatScreen.new()
	screen.configure("res://maps/arena.json", players, enemies, [], 3)
	get_parent().add_child.call_deferred(screen)
	_run.call_deferred()


func _run() -> void:
	BWEsc.synthetic = true                       # D171: the real cursor may be outside the window
	await _wait_ready()
	var b := screen.battle
	var u := b.current()
	_check(u != null and u.team == "player", "player has the first turn")
	await _settings_probe()                      # D124 / D123


	# 0. a left-drag orbits the camera and is NOT a click
	var yaw0 := screen.rig.yaw
	var pos0 := u.pos
	var p0 := _to_window(screen.cam.unproject_position(screen.board_view.top_center(u.pos + Vector2i(1, -1))))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p0
	Input.parse_input_event(down)
	await get_tree().process_frame
	for k in 6:
		var mm := InputEventMouseMotion.new()
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.relative = Vector2(25, 0)
		mm.position = p0 + Vector2(25 * (k + 1), 0)
		Input.parse_input_event(mm)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p0 + Vector2(150, 0)
	Input.parse_input_event(up)
	await get_tree().create_timer(0.3).timeout
	_check(absf(screen.rig.yaw - yaw0) > 0.5 and u.pos == pos0, "left-drag orbits (yaw %.2f→%.2f) without moving anyone" % [yaw0, screen.rig.yaw])

	# 1. hover + click a reachable hex → the unit moves there
	var r := b.reachable(u)
	var dest := u.pos
	var best := -1
	for h in r:
		if r[h].stop and h != u.pos and r[h].cost > best and _clickable(h) and not _by_rock(b, h):   # D375: free climbs reach hexes behind pillars
			best = r[h].cost
			dest = h
	var start := u.pos
	await _click_hex(dest)
	await _wait_ready()
	_check(u.pos == dest, "click moves the unit to %s (at %s)" % [dest, u.pos])
	await _key(KEY_ESCAPE)
	await _wait_ready()
	_check(u.pos == start and b.can_move(u), "Esc undoes the move (back at %s)" % start)
	await _click_hex(dest)
	await _wait_ready()
	_check(u.pos == dest, "and it can move again")

	# 2. D109 Transfer from clicks: the source, Esc back, the source again,
	#    the destination, the forecast, Enter
	await _readability_probe(u)                  # D160/D161: tile card, blast preview
	await _transfer_probe(u)
	await _wind_shape_probe(u)                   # D365-D370: a wind Ley Line parted right with the arrow key

	# 3. Space ends the turn (declines any follow-up)
	var who := b.current()
	if who == u:
		await _key(KEY_T)
		await _wait_ready()
	_check(b.current() != u or b.over, "T ends the turn")

	# 4. next player unit: click an enemy in range → forecast → Enter attacks
	var guard := 0
	var atk_done := false
	while not b.over and guard < 24:
		guard += 1
		var p := b.current()
		if p.team != "player":
			await _wait_ready()
			continue
		if not _swap_done and not p.second_weapon().is_empty():
			await _swap_probe(p)                     # D181
		var reach := b.reachable(p)
		var spot := p.pos
		var foe: BWUnit = null
		for h in reach:
			if not reach[h].stop or not _clickable(h):
				continue
			for f in b.foes_of(p):
				if b.in_range(p, f, h):
					spot = h
					foe = f
					break
			if foe:
				break
		if p.weapon_class == "daggers" and not _fan_done:
			await _fan_probe(p)
			continue
		if foe == null or atk_done:
			await _key(KEY_T)
			await _wait_ready()
			continue
		if spot != p.pos:
			await _click_hex(spot)
			await _wait_ready()
		var n := b.history.size()
		await _click_hex(foe.pos)
		await get_tree().create_timer(0.2).timeout
		_check(screen.ui.forecast_open(), "clicking an enemy opens the forecast")
		if not _gloss_done:
			await _gloss_probe()                     # D125
			await _esc_probe()                       # D171
		await _key(KEY_ENTER)
		await _hold_space_through()                  # D123: hold to skip
		_check(b.history.slice(n).any(func(e): return e.type == "attack"), "Enter confirms the attack")
		atk_done = true
		if _fan_done:
			break
		if b.current() == p:
			await _key(KEY_T)
			await _wait_ready()
	_check(_fan_done, "the confirm-step skill was probed")
	_check(_swap_done, "the weapon swap was probed")
	var names: Array = screen.last_tiers.map(func(x): return str(x[1]))
	_check(not names.is_empty() and names.all(func(n): return n in BWCutsceneTier.NAMES), "every blow got a tier (%s)" % ", ".join(names.slice(0, 8)))
	_check(screen.last_tiers.any(func(x): return x[0] == "attack" and (x[1] == "minimal" or x[1] == "full")), "basic attacks play minimal (or full on a crit / KO)")
	await _gear_tooltip_probe()                  # D171: the author's stuck tooltip
	await _autoequip_probe()                     # D315-D318
	_finish()


var _fan_done := false
var _swap_done := false


## D181: click "Swap weapon" (right under Attack): the class, the menu's
## skills and the attack range change; the action and the move are unspent;
## the button stays (D195: unlimited) and swaps back and forth.
func _swap_probe(p: BWUnit) -> void:
	_swap_done = true
	var b := screen.battle
	await _wait_ready()
	var btn: Control = screen.ui.find_child("swap_weapon", true, false)
	_check(btn != null and btn.is_visible_in_tree(), "the menu offers Swap weapon")
	if btn == null:
		return
	var kids: Array = btn.get_parent().get_children()
	var atk := kids.filter(func(c): return c is Button and (c as Button).text == "Attack")
	_check(not atk.is_empty() and kids.find(btn) == kids.find(atk[0]) + 1, "directly under Attack")
	var before: Array = b.skills_for(p).map(func(r): return str(r.key))
	var wc0 := p.weapon_class
	var rng0 := b.weapon_range(p)
	if OS.get_environment("SWAP_SHOTS") != "":
		await _shot_to(OS.get_environment("SWAP_SHOTS") + "/weapons2_menu_before.png")
	await _move(_ctl_center(btn))
	await _press(_ctl_center(btn), true)
	await _press(_ctl_center(btn), false)
	await get_tree().create_timer(0.2).timeout
	await _wait_ready()
	_check(p.weapon_class == "bow" and p.weapon_class != wc0, "the swap draws the bow (%s -> %s)" % [wc0, p.weapon_class])
	_check(b.weapon_range(p) == 6 and rng0 != 6, "the attack range follows (%d -> %d)" % [rng0, b.weapon_range(p)])
	var after: Array = b.skills_for(p).map(func(r): return str(r.key))
	_check(after != before and after.all(func(k): return k in BWSkillRegistry.expand(p.fight_loadout("bow"))), "the action bar shows the bow's skills (%s)" % [after])
	_check(not p.acted and b.can_move(p), "free: the action and the move are unspent")
	if OS.get_environment("SWAP_SHOTS") != "":
		await get_tree().create_timer(0.4).timeout
		await _shot_to(OS.get_environment("SWAP_SHOTS") + "/weapons2_menu_after.png")
	# D195: unlimited: the entry stays and swaps back, then forward again
	for want in [wc0, "bow"]:
		var again: Control = screen.ui.find_child("swap_weapon", true, false)
		_check(again != null and again.is_visible_in_tree(), "Swap weapon is still offered (to %s)" % want)
		if again == null:
			return
		await _move(_ctl_center(again))
		await _press(_ctl_center(again), true)
		await _press(_ctl_center(again), false)
		await get_tree().create_timer(0.2).timeout
		await _wait_ready()
		_check(p.weapon_class == want, "swapped to %s (%s)" % [want, p.weapon_class])
	_check(not p.acted and b.can_move(p), "still free after three swaps")


func _shot_to(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


# ---- D160/D161 readability probe ----

## A hex the mouse can reach: passable, holdable, free, not under the HUD.
func _free_hex(near: Vector2i, d_min: int, d_max: int, skip: Array = []) -> Vector2i:
	var b := screen.battle
	for h in b.board.area(near, d_max):
		var d := BWHex.distance(near, h)
		if d >= d_min and not h in skip and b.board.is_passable(h) and b.tiles.can_hold(h) \
				and b.unit_at(h) == null and _clickable(h):
			return h
	return Vector2i(-1, -1)


func _hover_hex(h: Vector2i) -> void:
	var p := _to_window(screen.cam.unproject_position(screen.board_view.top_center(h)))
	for k in 2:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame


## D161: a real hover shows the tile card. D160: hovering a foe for a basic
## attack that would detonate a glazed water + dark hex previews the blast,
## the chain arc and the ally in the splash, without a roll or an event; the
## confirm box lists the friendly fire; Esc backs out. The scene is put back.
func _readability_probe(u: BWUnit) -> void:
	var b := screen.battle
	var rd := screen.readability
	_check(rd != null, "the readability layer is on the combat screen")
	if rd == null:
		return
	var h := _free_hex(u.pos, 2, 4)
	_check(h.x >= 0, "a free hex to hover")
	if h.x < 0:
		return
	b.tiles.apply([h], "fire", "probe", 2)
	screen.board_view.refresh_tiles()
	await _hover_hex(h)
	await get_tree().create_timer(0.2).timeout
	_check(rd.card_shown() and rd.card_text().contains("Fire 2"), "hovering a hex shows its tile card (%s)" % rd.card_text().get_slice("\n", 0))
	# the detonating aim: Channel attuned to thunder onto a foe on glazed water 3 + dark 3
	var f: BWUnit = b.foes_of(u)[0]
	var g: BWUnit = b.foes_of(u)[1]
	var ally: BWUnit = b.side("player").filter(func(o): return o != u)[0]
	var keep := { f: f.pos, g: g.pos, ally: ally.pos }
	var t := Vector2i(-1, -1)
	var wr := b.weapon_range(u)
	for c in b.board.area(u.pos, wr):
		if c == u.pos or c == h or not b.board.is_passable(c) or not b.tiles.can_hold(c) or not _clickable(c):
			continue
		if b.unit_at(c) != null and b.unit_at(c) != f:
			continue
		var ring: Array = BWHex.neighbors(c).filter(func(n): return n != u.pos and n != h and b.board.is_passable(n) \
			and b.tiles.can_hold(n) and (b.unit_at(n) == null or b.unit_at(n) in [g, ally]))
		if ring.size() < 2:
			continue
		f.pos = c
		if b.in_range(u, f):
			t = c
			g.pos = ring[0]
			ally.pos = ring[1]
			break
		f.pos = keep[f]
	_check(t.x >= 0, "a hex in %s's reach for the detonation" % u.name)
	if t.x < 0:
		return
	for o in [f, g, ally]:
		screen._views[o.id].position = screen.board_view.top_center(o.pos)
	var att0 := u.attuned
	u.attuned = "thunder"
	b.tiles.apply([t], "water", "probe", 3)
	b.tiles.apply([t], "dark", "probe", 3)
	b.tiles.apply([t], "ice", "probe")
	b.tiles.apply([g.pos], "thunder", "probe")
	screen.board_view.refresh_tiles()
	var n0 := b.history.size()
	var rng0 := b.rng.state
	await _hover_hex(t)
	await get_tree().create_timer(0.25).timeout
	var sim: Dictionary = rd.preview.last
	_check(sim.get("detonations", []).size() == 1, "hovering the foe previews the detonation (%s)" % str(sim.get("detonations", [])))
	_check(not sim.get("chains", []).is_empty(), "and the chain arc off the fuse")
	_check(sim.get("units", {}).has(ally.id) and sim.units[ally.id].friendly, "and flags %s in the splash as friendly fire" % ally.name)
	_check(rd.preview._mesh.mesh != null and not rd.preview._tags.is_empty(), "the hatching and the damage tags are drawn")
	_check(not rd.card_shown(), "the tile card steps aside while a preview shows")
	_check(b.history.size() == n0 and b.rng.state == rng0, "the preview fired nothing and drew no roll")
	await _click_hex(t)
	await get_tree().create_timer(0.3).timeout
	_check(screen.ui.forecast_open(), "clicking the foe opens the confirm box")
	var extra: Control = screen.ui._fc_extra
	var ff := extra != null and is_instance_valid(extra) and extra.get_children().any(
		func(c): return c is RichTextLabel and (c as RichTextLabel).get_parsed_text().contains("Friendly fire"))
	_check(ff, "the confirm box lists the friendly fire")
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.1).timeout
	_check(not screen.ui.forecast_open() and b.history.size() == n0, "Esc backs out; nothing happened")
	# put the scene back
	var fuse_at := g.pos
	u.attuned = att0
	for o in keep:
		o.pos = keep[o]
		screen._views[o.id].position = screen.board_view.top_center(o.pos)
	for c in [t, fuse_at, h]:
		b.tiles.entries.erase(c)
	screen.board_view.refresh_tiles()
	await _hover_hex(u.pos)
	screen._show_options()
	await get_tree().process_frame
	_check(not rd.preview.shown(), "the preview clears when nothing is aimed")
# ---- end D160/D161 ----
var _gloss_done := false


## D124: Esc with nothing to back out of opens the pause menu; Settings
## there changes the cutscene mode; F cycles it in battle (D123).
func _settings_probe() -> void:
	_check(str(BWSettings.value("cutscenes")) == "default" and BWSettings.isolated, "the probe starts on default settings (isolated)")
	await _key(KEY_ESCAPE)
	await get_tree().process_frame
	var pm := screen.pause_menu
	_check(pm != null and is_instance_valid(pm) and get_tree().paused, "Esc with nothing to undo opens the pause menu (paused)")
	if pm == null or not is_instance_valid(pm):
		return
	pm._buttons.settings.pressed.emit()
	await get_tree().process_frame
	_check(is_instance_valid(pm.settings), "Settings opens from the pause menu")
	pm.settings.choose("cutscenes", "fast")
	_check(str(BWSettings.value("cutscenes")) == "fast", "the settings panel sets the cutscene mode to Fast")
	pm.settings.choose("show_odds", false)
	_check(BWSettings.value("show_odds") == false, "the odds strip toggles off")
	pm.settings.choose("show_odds", true)
	await _key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not is_instance_valid(pm.settings) and is_instance_valid(pm), "Esc closes the settings, the pause menu stays")
	await _key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not is_instance_valid(pm) and not get_tree().paused, "Esc again resumes")
	await _key(KEY_F)
	_check(str(BWSettings.value("cutscenes")) == "minimal" and screen.ui.toast_text() == "Cutscenes: Minimal", "F cycles to Minimal with a toast")
	await _key(KEY_F)
	_check(str(BWSettings.value("cutscenes")) == "default", "F cycles back to Default")


## D125: hover a glossary term on the acting unit's card (real mouse motion);
## its definition card shows.
func _gloss_probe() -> void:
	_gloss_done = true
	var rt: RichTextLabel = screen.ui._acting.text
	var at := Vector2(-1, -1)
	var tip := ""
	var y := 2.0
	while y < rt.size.y and at.x < 0:
		var x := 2.0
		while x < rt.size.x:
			var t := rt.get_tooltip(Vector2(x, y))
			if t.contains(BWGlossary.HINT_SEP) and not BWGlossary.lookup(t.get_slice(BWGlossary.HINT_SEP, 0)).is_empty():
				at = Vector2(x, y)
				tip = t
				break
			x += 4.0
		y += 4.0
	_check(at.x >= 0, "the unit card links a glossary term (%s)" % tip.get_slice(BWGlossary.HINT_SEP, 0))
	if at.x < 0:
		return
	var p := _to_window(rt.get_global_transform_with_canvas() * at + Vector2(3, 2))
	get_window().grab_focus()
	for k in 3:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame
	var shown := false
	var want := ""
	for i in 30:                                  # the tooltip delay, plus slack
		await get_tree().create_timer(0.1).timeout
		want = str(BWGlossary.lookup(tip.get_slice(BWGlossary.HINT_SEP, 0)).definition)
		shown = _find_label_text(get_tree().root, want)
		if shown:
			break
	_check(shown, "hovering it shows the definition card")
	if not shown:
		var hc := get_viewport().gui_get_hovered_control()
		print("    hovered: ", hc, " at ", p, " tip ", tip.left(40), " windows: ",
			get_tree().root.get_children(true).filter(func(c): return c is Window).map(func(c): return "%s %s" % [c.get_class(), c.visible]))
	var panel := BWGlossary.tooltip_panel(tip)
	_check(panel is Control and panel.get_child_count() >= 2, "the card has the term and its definition")
	panel.free()


## D171: a codex, then a glossary tooltip inside it: Esc closes the tooltip,
## Esc again the codex; the confirm box underneath stays (it is next).
func _esc_probe() -> void:
	BWEsc.close_tooltips()
	await get_tree().process_frame
	var fc_open := screen.ui.forecast_open()
	var codex := BWCodex.summon(screen, "elements")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(BWEsc.top_name() == "codex", "the codex is on top of the Esc stack (%s)" % [BWEsc.names()])
	var at := Vector2(-1, -1)
	var rt: RichTextLabel = null
	for r in codex.find_children("*", "RichTextLabel", true, false):
		var rr: RichTextLabel = r
		if not rr.is_visible_in_tree() or not codex._scroll.get_global_rect().encloses(rr.get_global_rect()):
			continue
		var y := 2.0
		while y < rr.size.y and at.x < 0:
			var x := 2.0
			while x < rr.size.x:
				if rr.get_tooltip(Vector2(x, y)).contains(BWGlossary.HINT_SEP):
					at = Vector2(x, y)
					break
				x += 4.0
			y += 4.0
		if at.x >= 0:
			rt = rr
			break
	_check(rt != null, "the codex shows a glossary term to hover")
	if rt == null:
		codex.close()
		return
	var p := _to_window(rt.get_global_transform_with_canvas() * at + Vector2(3, 2))
	for k in 3:
		var mm := InputEventMouseMotion.new()
		mm.position = p + Vector2(k, 0)
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await get_tree().process_frame
	for i in 30:
		await get_tree().create_timer(0.1).timeout
		if BWEsc.top_name() == "tooltip":
			break
	_check(BWEsc.tooltip_open() and BWEsc.top_name() == "tooltip", "a glossary tooltip over the codex is the newest entry (%s)" % [BWEsc.names()])
	var n0 := BWEsc.log_closed.size()
	await _key(KEY_ESCAPE)
	_check(not BWEsc.tooltip_open() and is_instance_valid(codex) and not codex.is_queued_for_deletion(), "Esc closes the tooltip; the codex stays")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(codex) or codex.is_queued_for_deletion(), "Esc again closes the codex")
	_check(BWEsc.log_closed.slice(n0) == ["tooltip", "codex"], "closed newest first (%s)" % [BWEsc.log_closed.slice(n0)])
	_check(screen.ui.forecast_open() == fc_open and not get_tree().paused, "the confirm box underneath is untouched, no pause menu")


## D171: the author's stuck tooltip was in the pre-battle equipment panel.
## The same panel (BWGearPanel) over the screen: hover an item, drag it a
## little and let go, double-click it on, hover the worn slot, hover a term in
## the card, move away: the tooltip goes on its own; again, and Esc closes it.
func _gear_tooltip_probe() -> void:
	var ids: Array = BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 1)
	var u: BWUnit = run.squad[0]
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = BWStyle.theme()
	layer.add_child(root)
	var gp := BWGearPanel.new(run)
	gp.set_anchors_preset(Control.PRESET_FULL_RECT)
	gp.offset_left = 20
	gp.offset_top = 40
	gp.offset_right = -20
	gp.offset_bottom = -40
	root.add_child(gp)
	gp.set_unit(u)
	for k in 4:
		await get_tree().process_frame
	var tile: BWItemTile = null
	for c in gp._grid.get_children():
		if c is BWItemTile and str(c.item.slot) != "main_hand" and run.can_equip(u, c.item):
			tile = c
			break
	_check(tile != null, "gear panel: a loose piece %s can wear" % u.name)
	if tile == null:
		layer.queue_free()
		return
	var it: Dictionary = tile.item
	var at := _ctl_center(tile)
	await _move(at)
	_check(gp.card.showing(), "gear panel: hovering an item shows its card")
	await _move(_ctl_center(gp._title))           # off the piece, nothing selected
	_check(not gp.card.showing(), "gear panel: moving off the piece hides its card")
	await _move(at)
	_check(gp.card.showing(), "gear panel: hovering it again shows the card")
	# a short drag, let go over the grid
	await _press(at, true)
	for k in 5:
		await _move(at + Vector2(8 * (k + 1), 6 * (k + 1)), MOUSE_BUTTON_MASK_LEFT)
	await _press(at + Vector2(40, 30), false)
	await get_tree().create_timer(0.2).timeout
	tile = null
	for c in gp._grid.get_children():
		if c is BWItemTile and c.item == it and not c.is_queued_for_deletion():
			tile = c
	_check(tile != null, "gear panel: the dragged piece is still loose")
	if tile:
		at = _ctl_center(tile)
		await _move(at)
		await _press(at, true)
		await _press(at, false)
		await _press(at, true, true)               # the double-click
		await _press(at, false)
		await get_tree().create_timer(0.2).timeout
	var slot := str(it.slot)
	_check(u.equipment.get(slot, {}) == it, "gear panel: a double-click equips it")
	await _move(_ctl_center(gp._slots[slot]))
	await get_tree().create_timer(0.15).timeout
	var hint := _hint_point(gp.card)
	_check(hint.x >= 0, "gear panel: the item card links a glossary term")
	if hint.x < 0:
		layer.queue_free()
		return
	for round in 2:
		await _move(_ctl_center(gp._slots[slot]))  # the worn piece's read, then onto the card
		await _move(hint)
		await _move(hint + Vector2(1, 0))
		var up := false
		for i in 30:
			await get_tree().create_timer(0.1).timeout
			if BWEsc.tooltip_open():
				up = true
				break
		_check(up and BWEsc.top_name() == "tooltip", "gear panel: hovering the card's term shows its tooltip (%d)" % (round + 1))
		if round == 0:
			await _move(_ctl_center(gp._title))     # away, onto the panel's title
			await get_tree().create_timer(0.5).timeout
			_check(not BWEsc.tooltip_open(), "gear panel: moving away closes it on its own")
			_check(not gp.card.showing(), "gear panel: and the card's hovered read goes too")
		else:
			await _key(KEY_ESCAPE)
			_check(not BWEsc.tooltip_open() and BWEsc.top_name() != "tooltip", "gear panel: Esc closes it")
	layer.queue_free()
	await get_tree().process_frame


## D315-D318: O opens Optimize all's preview, Esc cancels it, Apply hands the
## gear out, Undo optimize puts it all back.
func _autoequip_probe() -> void:
	var ids: Array = BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 1)
	run.fight = 6
	for i in 10:
		run.inventory.append(run.random_item(["D", "C", "B"][i % 3]))
	run.stats.units[run.squad[3].id] = { "fights": 4, "kos": 0, "damage": 200, "taken": 0, "mvp": 0 }
	var sig := func() -> Array:
		var out: Array = run.inventory.map(func(it): return str(it.uid))
		for u in run.squad:
			for slot in BWRun.GEAR_SLOTS:
				out.append("%s:%s:%s" % [u.id, slot, str(u.equipment.get(slot, {}).get("uid", ""))])
		return out
	var before: Array = sig.call()
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = BWStyle.theme()
	layer.add_child(root)
	var gp := BWGearPanel.new(run)
	gp.set_anchors_preset(Control.PRESET_FULL_RECT)
	gp.offset_left = 20
	gp.offset_top = 40
	gp.offset_right = -20
	gp.offset_bottom = -40
	root.add_child(gp)
	gp.set_unit(run.squad[0])
	for k in 4:
		await get_tree().process_frame
	await _key(KEY_O)
	_check(gp.preview_open(), "auto-equip: O opens Optimize all's preview")
	_check(BWEsc.top_name() == "optimize preview", "auto-equip: the preview is on the Esc stack")
	await _key(KEY_ESCAPE)
	_check(not gp.preview_open() and sig.call() == before, "auto-equip: Esc cancels, nothing changes")
	await _press(_ctl_center(gp._opt_all), true)
	await _press(_ctl_center(gp._opt_all), false)
	await get_tree().process_frame
	_check(gp.preview_open(), "auto-equip: clicking Optimize all opens it too")
	var apply_btn: Button = gp.find_child("preview_apply", true, false)
	await _press(_ctl_center(apply_btn), true)
	await _press(_ctl_center(apply_btn), false)
	await get_tree().create_timer(0.2).timeout
	_check(not gp.preview_open() and sig.call() != before, "auto-equip: Apply hands the gear out")
	_check(gp._undo_btn.is_visible_in_tree(), "auto-equip: Undo optimize shows")
	await _press(_ctl_center(gp._undo_btn), true)
	await _press(_ctl_center(gp._undo_btn), false)
	await get_tree().create_timer(0.2).timeout
	_check(sig.call() == before, "auto-equip: Undo puts everything back")
	_check(not gp._undo_btn.visible, "auto-equip: one step: the Undo button goes")
	layer.queue_free()
	await get_tree().process_frame


func _ctl_center(c: Control) -> Vector2:
	return _to_window(c.get_global_transform_with_canvas() * (c.size * 0.5))


## A window point over a glossary hint in any RichTextLabel under `n` (-1 = none).
func _hint_point(n: Node) -> Vector2:
	for r in n.find_children("*", "RichTextLabel", true, false):
		var rr: RichTextLabel = r
		if not rr.is_visible_in_tree():
			continue
		var y := 2.0
		while y < rr.size.y:
			var x := 2.0
			while x < rr.size.x:
				if rr.get_tooltip(Vector2(x, y)).contains(BWGlossary.HINT_SEP):
					return _to_window(rr.get_global_transform_with_canvas() * Vector2(x + 2, y + 1))
				x += 4.0
			y += 4.0
	return Vector2(-1, -1)


func _move(p: Vector2, mask: int = 0) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	mm.button_mask = mask
	Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame


func _press(p: Vector2, down: bool, double := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.double_click = double
	mb.position = p
	mb.global_position = p
	Input.parse_input_event(mb)
	await get_tree().process_frame


func _find_label_text(n: Node, want: String) -> bool:
	if n is Label and (n as Label).text == want and (n as Label).is_visible_in_tree():
		return true
	for c in n.get_children(true):
		if _find_label_text(c, want):
			return true
	return false


func _learn(u: BWUnit, key: String) -> void:
	if not key in u.known_skills:
		u.known_skills.append(key)
	var kit: Array = u.loadout(u.weapon_class)
	if not key in kit:
		kit = [key] + kit.slice(0, BWUnit.loadout_cap(u.weapon_class) - 1)
	u.skill_loadout[u.weapon_class] = kit


## D109: Transfer takes two clicks; Esc steps back one stage.
func _transfer_probe(u: BWUnit) -> void:
	var b := screen.battle
	_check(b.skills_for(u).any(func(r): return r.key == "transfer"), "%s carries Transfer" % u.name)
	var d: BWSkillDef = BWSkillRegistry.get_def("transfer")
	var src := Vector2i(-1, -1)
	for h in b.board.area(u.pos, 3):
		if h != u.pos and b.unit_at(h) == null and b.tiles.can_hold(h) and b.tiles.at(h).is_empty() and _clickable(h) \
				and (h == u.pos or BWHex.distance(u.pos, h) <= 1 or b.board.has_los(u.pos, h)):
			src = h
			break
	_check(src != Vector2i(-1, -1), "a clickable source hex for Transfer")
	if src == Vector2i(-1, -1):
		return
	b.tiles.apply([src], "fire", "probe", 2)
	screen.board_view.refresh_tiles()
	screen.ui.skill_chosen.emit("transfer", "")
	await get_tree().process_frame
	_check(src in b.skill_targets(u, "transfer", ""), "the charged hex is a Transfer source")
	await _click_hex(src)
	await get_tree().create_timer(0.2).timeout
	_check(screen._skill.get("first", Vector2i(-1, -1)) == src and not screen.ui.forecast_open(), "first click picks the source, no forecast yet")
	await _key(KEY_ESCAPE)
	_check(not screen._skill.is_empty() and not screen._skill.has("first"), "Esc steps back to the source pick")
	await _click_hex(src)
	await get_tree().create_timer(0.2).timeout
	var dest := Vector2i(-1, -1)
	var seconds: Array = d.second_targets(b, u, "", src)
	var auto: Vector2i = d.call("dest_for", b, u, src)
	for h in seconds:
		if h != auto and _clickable(h):
			dest = h
			break
	_check(dest != Vector2i(-1, -1), "a clickable destination other than the automatic one")
	if dest == Vector2i(-1, -1):
		return
	await _click_hex(dest)
	await get_tree().create_timer(0.2).timeout
	_check(screen.ui.forecast_open(), "second click opens the confirm box")
	var before := b.history.size()
	await _key(KEY_ENTER)
	await _wait_ready()
	var ev: Array = b.history.slice(before).filter(func(e): return e.type == "skill" and e.skill == "transfer")
	_check(not ev.is_empty() and dest in ev[0].hexes, "Transfer set the charge down on the picked hex %s" % dest)
	_check(b.tiles.intensity(dest, "fire") == 2, "the fire is on %s" % dest)


## D365-D370: a wind Ley Line: the confirm shows WIND SHAPING; the arrow key
## pointing at the line's right parts it right (live preview); Enter fires and
## the foe on the line ends on its right. (Probe scaffolding: the unit gets
## wind, the skill and its action back.)
func _wind_shape_probe(u: BWUnit) -> void:
	var b := screen.battle
	u.affinity["wind"] = maxi(int(u.affinity.get("wind", 0)), BWUnit.POINTS_PER_RANK)
	_learn(u, "ley_line")
	u.acted = false
	u.follow_up = []
	u.cooldowns.clear()
	var f: BWUnit = b.foes_of(u)[0]
	var dir := -1
	var on := Vector2i(-1, -1)
	for d in 6:
		var a1: Vector2i = BWHex.neighbors(u.pos)[d]
		var a2: Vector2i = BWHex.neighbors(a1)[d]
		var fwd := BWWindShape.forward(u.pos, a1)
		var rh: Vector2i = BWHex.neighbors(a2)[BWWindShape.side_dir(fwd, -1)]
		if not (_clickable(a1) and b.board.is_passable(a1) and b.board.is_passable(a2) and b.board.is_passable(rh)):
			continue
		if b.unit_at(a1) != null or (b.unit_at(a2) != null and b.unit_at(a2) != f) or b.unit_at(rh) != null:
			continue
		if not a1 in b.skill_targets(u, "ley_line", "wind"):
			continue
		f.pos = a2
		screen._views[f.id].position = screen._unit_pos(a2)
		screen.ui.skill_chosen.emit("ley_line", "wind")
		await get_tree().process_frame
		BWWindShape.set_choice(u, "ley_line", "part_left")
		await _click_hex(a1)
		await get_tree().create_timer(0.2).timeout
		if screen.ui.forecast_open() and screen.wind_shape.key_for_side(-1) == KEY_RIGHT:
			dir = d
			on = a2
			break
		await _key(KEY_ESCAPE)
		await _key(KEY_ESCAPE)
	_check(dir >= 0, "a Ley Line heading whose right side is the screen's right")
	if dir < 0:
		return
	_check(screen.ui.find_child("WindShaping", true, false) != null, "the confirm box shows WIND SHAPING")
	await _key(KEY_RIGHT)
	await get_tree().create_timer(0.3).timeout
	_check(str(BWWindShape.choice(u, "ley_line").opt) == "part_right", "→ picks Part right")
	_check(screen.ui.forecast_open(), "the confirm box stays up")
	_check(str(screen.wind_shape.shown.get("opt", "")) == "part_right" and int(screen.wind_shape.shown.get("arrows", 0)) > 0, "the board shows the parting arrows")
	var moves: Array = screen.readability.preview.last.get("moves", [])
	_check(moves.any(func(m): return str(m.unit) == f.id), "the preview shows the foe's push")
	var n0 := b.history.size()
	await _key(KEY_ENTER)
	await _wait_ready()
	var fwd2 := BWWindShape.forward(u.pos, BWHex.neighbors(u.pos)[dir])
	_check(b.history.slice(n0).any(func(e): return e.type == "wind_shape" and e.opt == "part_right"), "Enter fires the Ley Line, parted right")
	_check(not f.alive() or BWWindShape.side_of(u.pos, fwd2, f.pos) == -1, "the foe on the line now stands on its right (%s → %s)" % [on, f.pos])


## D110: Fan of Knives opens its forecast from the menu; Esc backs out,
## Enter fires.
func _fan_probe(p: BWUnit) -> void:
	_fan_done = true
	var b := screen.battle
	var f: BWUnit = b.foes_of(p)[0]
	for n in BWHex.neighbors(p.pos):
		if b.board.is_passable(n) and b.unit_at(n) == null:
			f.pos = n
			screen._views[f.id].position = screen.board_view.top_center(n)
			break
	var rows: Array = b.skills_for(p).filter(func(r): return r.key == "fan_of_knives")
	_check(not rows.is_empty(), "Fan of Knives offered to %s" % p.name)
	if rows.is_empty():
		return
	var el := str(rows[0].elements[0])
	var n0 := b.history.size()
	screen.ui.skill_chosen.emit("fan_of_knives", el)
	await get_tree().create_timer(0.2).timeout
	_check(screen.ui.forecast_open() and b.history.size() == n0, "the menu click opens a confirm box, nothing fired")
	await _key(KEY_ESCAPE)
	_check(not screen.ui.forecast_open() and screen._skill.is_empty(), "Esc backs out to the menu")
	screen.ui.skill_chosen.emit("fan_of_knives", el)
	await get_tree().create_timer(0.2).timeout
	await _key(KEY_ENTER)
	await _wait_ready()
	_check(b.history.slice(n0).any(func(e): return e.type == "skill" and e.skill == "fan_of_knives"), "Enter fires Fan of Knives")
	if b.current() == p:
		await _key(KEY_T)
		await _wait_ready()


## D123: hold Space through the playback: the clock runs fast while held,
## every event still plays, and time is back to 1 after.
func _hold_space_through() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_SPACE
	down.pressed = true
	Input.parse_input_event(down)
	var fast := false
	var t := 0
	while (screen._busy or t < 2) and t < 3600:
		await get_tree().process_frame
		fast = fast or (screen.skipping and Engine.time_scale > 1.5)
		t += 1
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(fast, "holding Space fast-forwards the playback")
	_check(is_equal_approx(Engine.time_scale, 1.0) and not screen.skipping and screen._queue.is_empty(), "released: time back to 1, every event played")


## Not hidden under a HUD panel.
## A hex beside tall rock: its top can hide behind the rock on screen.
func _by_rock(b: BWBattle, h: Vector2i) -> bool:
	for n in BWHex.neighbors(h):
		if b.board.exists(n) and b.board.terrain(n) == BWBoard.JAGGED:
			return true
	return false


func _clickable(h: Vector2i) -> bool:
	var p := screen.cam.unproject_position(screen.board_view.top_center(h))
	for rect in screen.ui.blocking_rects():
		if rect.grow(8).has_point(p):
			return false
	return true


## Waits out the event replay (a whole enemy phase can run 30 s with the
## clip set's runs and strikes; Phase 4 matrix, D62).
func _wait_ready() -> void:
	var t := 0
	while (screen.battle == null or screen._busy) and t < 3600:
		await get_tree().process_frame
		t += 1
	await get_tree().process_frame


## Viewport coordinates → window coordinates: the game stretches its
## 1600×900 design space to whatever window it gets (maximized, 4K...).
func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _click_hex(h: Vector2i) -> void:
	var vp_pos := screen.cam.unproject_position(screen.board_view.top_center(h))
	var p := _to_window(vp_pos)
	var mm := InputEventMouseMotion.new()
	mm.position = p
	Input.parse_input_event(mm)
	await get_tree().process_frame
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = p
		Input.parse_input_event(mb)
		await get_tree().process_frame


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)
	# let the event land and any animation it starts begin, before waiting on it
	await get_tree().process_frame
	await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("  ok   ", what)
	else:
		_fails.append(what)
		print("  FAIL ", what)


func _finish() -> void:
	print("ui-probe: %d passed, %d failed" % [_passes, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

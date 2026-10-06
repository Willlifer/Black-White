class_name BWFlowProbe
extends Node
## Drives the real BWGame through every screen transition: title → roster
## (portrait unpick, codex) → the run-start perk pickers (D90) → the hall's
## prep (equip, give) → pre-battle → combat (autoplayed; picks auto) →
## results → downtime (D127: one of three choices each, the day, one result
## card per unit, its pickers) → the next pre-battle. Uses each screen's own entry points, not internals of the
## rules. `godot --path game -- --flow-probe` (windowed). Exit 0 = passed.

var game: BWGame
var _log: PackedStringArray = []
var _fails := 0


func _ready() -> void:
	BWEsc.synthetic = true                       # D171: the real cursor may be outside the window
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BWGame.SAVE_PATH))
	game = BWGame.new()
	get_parent().add_child.call_deferred(game)
	_run.call_deferred()


func _run() -> void:
	var title: BWTitleScreen = await _wait_screen(BWTitleScreen)
	await get_tree().create_timer(2.6).timeout
	title.done.emit("new")
	var roster: BWRosterScreen = await _wait_screen(BWRosterScreen)
	# D150: Randomize (R) re-rolls with a new seed, clears the picks, re-dresses the seats.
	_check(roster.roster_seed == BWRosterGen.fixed_seed, "the roster opens on the fixed seed (D154)")
	var before: Array = roster.rows.map(func(r): return "%s/%s/%s" % [r.weapon_model, r.element, r.top])
	roster._toggle(0)
	roster._toggle(1)
	_key(KEY_R)
	await roster.rerolled
	var after: Array = roster.rows.map(func(r): return "%s/%s/%s" % [r.weapon_model, r.element, r.top])
	_check(before != after and roster._chosen.is_empty(), "R re-rolls the twenty and clears the picks")
	_check(roster._views.size() == 20 and roster._views.all(func(v): return is_instance_valid(v)), "twenty seats re-dressed")
	_check(str(roster.rows[0].element) == "light" and str(roster.rows[12].element) == "ice", "Aureli light, Rem ice after a re-roll")
	for i in 6:
		roster._toggle(i)
	_check(roster._chosen.size() == 6, "picked six on the roster")
	await get_tree().create_timer(0.7).timeout       # picks finish flying in
	_check(roster._slots.all(func(sl): return sl.is_filled()), "six portrait slots filled")
	# Unpick through a portrait slot, pick again (D75).
	roster._on_slot_clicked(2)
	_check(roster._chosen.size() == 5, "clicking a filled portrait slot unpicks")
	roster._toggle(2)
	roster.open_codex("weapons")
	await get_tree().process_frame
	_check(is_instance_valid(roster._codex) and roster._codex.tab == "weapons", "Info opens the codex")
	_key(KEY_SPACE)                       # the codex swallows keys: no Begin underneath
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not is_instance_valid(roster._codex) and game.screen == roster, "Esc closes the codex, roster still up")
	var rolled_seed := roster.roster_seed
	var rolled_rows: Array = roster.rows
	roster._try_begin()
	# D90: the first perks, one picker per unit, before the hall.
	var picks: BWPicksScreen = await _wait_screen(BWPicksScreen, 12.0)
	await _probe_run_start_picks(picks)
	# Before fight 1: the hall (D84, replaced the loading-screen intro).
	var prep: BWPrepScreen = await _wait_screen(BWPrepScreen)
	await _probe_prep(prep)
	_key(KEY_ENTER)
	var pre: BWPrebattleScreen = await _wait_screen(BWPrebattleScreen, 12.0)
	_check(game.run != null and game.run.squad.size() == 6, "run started with six")
	_check(game.run.roster_seed == rolled_seed and game.run.roster_rows.size() == 20 		and str(game.run.roster_rows[3].weapon_model) == str(rolled_rows[3].weapon_model), "the run keeps the screen's roll (D150)")
	for k in 3:
		pre._on_deploy(true, game.run.squad[k])
	_check(not pre._begin.disabled, "three placed, Begin enabled")
	await _probe_prebattle(pre)
	_check(not pre._begin.disabled, "still three placed after the drags, Begin enabled")
	pre._try_begin()
	var combat: BWCombatScreen = await _wait_screen(BWCombatScreen)
	combat.autoplay = true
	# The probe tests transitions, not balance: tilt this one fight so it is won.
	for e in combat.battle.side("enemy"):
		e.hp = 1
	combat._after_events()
	var next: Node = await _wait_any([BWResultsScreen, BWEndScreen], 240.0)
	# won or lost, a regular fight goes to the after-battle screen (author 10/4)
	_check(next is BWResultsScreen, "fight over → results")
	var res := next as BWResultsScreen
	_check(res.find_children("*", "Button", true, false).is_empty(), "results has no Continue button")
	await get_tree().create_timer(BWResultsScreen.MIN_SHOW).timeout
	_key(KEY_A)
	var down: BWDowntimeScreen = await _wait_screen(BWDowntimeScreen)
	await _probe_downtime(down)
	await get_tree().create_timer(BWDowntimeScreen.MIN_CONTINUE + 0.3).timeout
	_key(KEY_A)                           # the day card: any key goes on
	var pre2: BWPrebattleScreen = await _wait_screen(BWPrebattleScreen, 20.0)
	_check(pre2 != null and game.run.fight == 2 and game.run.day == 2, "day advanced, on to fight 2")
	_check(FileAccess.file_exists(BWGame.SAVE_PATH), "run autosaved")
	_finish()


## D127 downtime: three name-only tiles; keys 1-3 choose; everyone set
## enables Progress day; after the 5 s day one card per unit (any key goes
## on), each followed by that unit's pickers (Branch out always owes a perk
## and a skill pick); nothing banked; then the day card.
func _probe_downtime(down: BWDowntimeScreen) -> void:
	var run := game.run
	_check(down._tile_btns.size() == 3 and down._tile_btns.keys() == BWRun.DOWNTIME_CHOICES, "three choice tiles")
	_check(down._tile_btns.values().all(func(b): return b.tooltip_text == ""), "no tooltip on any tile (names only)")
	_check(down._go.disabled, "Progress day waits for everyone")
	_key(KEY_2)
	await get_tree().process_frame
	_check(down._plans[run.squad[0].id] == "branch_out", "key 2 = Branch out for the selected unit")
	_key(KEY_1)
	await get_tree().process_frame
	_check(down._plans[run.squad[0].id] == "specialize", "key 1 changes it to Specialize")
	var order := ["specialize", "branch_out", "wander"]
	for i in run.squad.size():
		down._plans[run.squad[i].id] = order[i % 3]
	down._refresh_go()
	_check(not down._go.disabled, "one choice each enables Progress day")
	var day_before := run.day
	var n_units := run.squad.size()
	down._progress()
	await get_tree().create_timer(BWDowntimeScreen.RESULT_SECONDS + 0.4).timeout
	var cards := 0
	var picks := 0
	var t := 0.0
	while t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if down.picker != null and down.picker.is_inside_tree():
			var pk := down.picker
			var mine: bool = cards > 0 and pk.unit.id == down.reports[cards - 1].unit
			var recruit: bool = cards == n_units and not down.reports.any(func(x): return x.unit == pk.unit.id)
			_check(mine or recruit, "after %s's card, a %s pick%s" % [pk.unit.name, pk.request.kind, " (a recruit)" if recruit else ""])
			_key(KEY_ENTER)                   # the first free card is preselected
			picks += 1
			await get_tree().process_frame
			await get_tree().process_frame
			continue
		if down.card != null and not down.option_btns.is_empty() and down._card_t >= BWDowntimeScreen.CARD_MIN:
			var r0: Dictionary = down.reports[cards]
			_check(down.option_btns.size() == r0.options.size() and r0.options.size() >= 1, "Branch out offers %d option cards" % r0.options.size())
			var at: int = r0.options.size() - 1
			_key(KEY_2 if at == 1 else KEY_1)  # take the last one by its key
			await get_tree().process_frame
			await get_tree().process_frame
			_check(int(r0.get("picked", -1)) == at and not r0.pending, "  took option %d: %s" % [at + 1, r0.headline])
			continue
		if down.card != null and down._card_t >= BWDowntimeScreen.CARD_MIN:
			var rep: Dictionary = down.reports[cards]
			_check(down.card_unit != null and down.card_unit.id == rep.unit, "card %d: %s, %s" % [cards + 1, rep.name, rep.choice])
			_check(not str(rep.headline).is_empty() and str(rep.headline).begins_with("I "), "  in the first person: %s" % rep.headline)
			cards += 1
			_key(KEY_A)
			await get_tree().process_frame
			continue
		if down._continue_t >= 0.0:
			break
	_check(cards == n_units, "one result card per unit (%d)" % cards)
	_check(picks >= 2, "the earned picks opened between the cards (%d)" % picks)
	_check(run.pending_picks().is_empty(), "nothing banked after the day")
	_check(run.day == day_before + 1, "the day advanced")


## D90 run start: one picker per unit, in squad order; the first by real
## keys (2 then Enter), the rest by clicking a card twice. Each unit ends
## with its element's first perk and nothing owed.
func _probe_run_start_picks(ps: BWPicksScreen) -> void:
	var run := game.run
	_check(run.pending_picks().size() == 6, "six first perks owed at run start")
	for i in 6:
		var t := 0.0
		while (ps.current == null or not ps.current.is_inside_tree()) and t < 3.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		var pk := ps.current
		if pk == null:
			_check(false, "a picker for unit %d" % i)
			return
		var u := pk.unit
		_check(u == run.squad[i], "picker %d is %s's, in squad order" % [i + 1, run.squad[i].name])
		_check(pk.request.kind == "perk" and pk.request.element == u.element, "%s: a %s perk" % [u.name, u.element])
		_check(pk._cards.size() == BWPicks.perks_of(u.element).size(), "a card per %s perk" % u.element)
		if i == 0:
			_key(KEY_2)
			await get_tree().process_frame
			_key(KEY_ENTER)
		else:
			var card: Control = pk._cards[i % pk._cards.size()]
			await get_tree().process_frame
			await _click(card.get_global_rect().get_center(), true)
		await get_tree().create_timer(0.15).timeout
		_check(u.perks.size() == 1 and BWPicks.pending(u).is_empty(), "%s took %s" % [u.name, u.perks])
	_check(run.pending_picks().is_empty(), "every first perk taken")


## The hall before fight 1 (D84): six under their lights, the starting kit
## loose; a click on a unit opens its gear; equip a loose piece on it, then
## hand that piece to another unit with "Give to"; Esc closes; Info opens the
## codex. Then Enter continues.
func _probe_prep(prep: BWPrepScreen) -> void:
	await get_tree().create_timer(0.8).timeout
	var run := game.run
	_check(prep._views.size() == 6 and prep._hall.spot_count() == 6, "the hall: six units, a spotlight each")
	_check(run.inventory.size() >= 5, "the run starts with the kit loose in the inventory")
	var a: BWUnit = run.squad[0]
	var b: BWUnit = run.squad[1]
	# click on unit 0's body
	var v: BWUnitView = prep._views[0]
	var p := prep._cam.unproject_position(v.global_position + Vector3(0, 1.0, 0))
	await _click(p)
	await get_tree().create_timer(0.3).timeout
	_check(prep._open and prep._panel.visible and prep._panel.unit == a, "clicking a unit opens its equipment panel")
	var it: Dictionary = {}
	for x in run.inventory:
		if str(x.slot) != "main_hand" and run.can_equip(a, x):
			it = x
			break
	_check(not it.is_empty(), "a loose armour piece to hand out")
	if not it.is_empty():
		var slot := str(it.slot)
		var n := run.inventory.size()
		prep._panel._equip(it)
		_check(a.equipment.get(slot, {}) == it and run.inventory.size() == n - 1, "equipped %s on %s" % [BWRun.item_name(it), a.name])
		_check(prep._tags[0].pips.unit == a, "the unit's gear squares follow it")
		var before_b: Dictionary = b.equipment.get(slot, {})
		prep._panel._slots[slot].picked.emit(prep._panel._slots[slot])
		await get_tree().process_frame
		_check(prep._panel._give_box.visible, "a picked worn piece offers Give to")
		var ok := prep._panel.give(b, it, slot)
		_check(ok and b.equipment.get(slot, {}) == it and not a.equipment.has(slot), "gave it to %s" % b.name)
		_check(before_b.is_empty() or before_b in run.inventory, "what %s wore there went to the inventory" % b.name)
	_key(KEY_I)
	await get_tree().process_frame
	_check(prep.get_children().any(func(c): return c is BWCodex), "Info opens the codex in the hall")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not prep._open, "Esc closes the panel")


## Pre-battle placement through real (synthetic) mouse events, in window
## coordinates (the window opens maximized; the game draws its 1600×900
## design space stretched into it): drag to an empty hex = move, drop onto
## a unit = swap, a click selects without moving, a squad row dragged onto a
## unit sends it in, a drop off the deploy hexes changes nothing; hovering
## an enemy shows its card; the equipment view equips by double-click.
func _probe_prebattle(pre: BWPrebattleScreen) -> void:
	await get_tree().create_timer(0.6).timeout          # camera fitted
	var a: BWUnit = pre._deployed[0]
	var b: BWUnit = pre._deployed[1]
	var c: BWUnit = pre._deployed[2]
	var on_screen := func(h: Vector2i) -> bool:
		var p := _hex_px(pre, h)
		var r := get_viewport().get_visible_rect().grow(-40)
		return r.has_point(p) and pre._bv.pick(pre._cam, p) == h
	_check(pre._board.deploy.player.all(func(h): return on_screen.call(h)), "every deploy hex is on screen and pickable (bottom row included)")
	var free: Array = pre._board.deploy.player.filter(func(h): return not h in pre._placed.values() and on_screen.call(h))
	var hb: Vector2i = pre._placed[b.id]
	var to: Vector2i = free[free.size() - 1]
	await _drag(_hex_px(pre, pre._placed[a.id]), _hex_px(pre, to))
	_check(pre._placed[a.id] == to and pre._placed[b.id] == hb, "drag to an empty deploy hex is a plain move (no swap)")
	var ha: Vector2i = pre._placed[a.id]
	await _drag(_hex_px(pre, ha), _hex_px(pre, hb))
	_check(pre._placed[a.id] == hb and pre._placed[b.id] == ha, "drop directly onto a unit swaps the two")
	var before: Dictionary = pre._placed.duplicate()
	await _click(_hex_px(pre, pre._placed[c.id]))
	_check(pre._sel == c and pre._placed == before, "a click on a unit selects it, nothing moves")
	var bench: BWUnit = game.run.squad[3]
	var row: Control = null
	for r in pre._list.get_children():
		if r.get("unit") == bench:
			row = r
	var hc: Vector2i = pre._placed[c.id]
	if row:
		await _drag(row.get_global_rect().get_center(), _hex_px(pre, hc))
	_check(bench in pre._deployed and not c in pre._deployed and pre._placed.get(bench.id) == hc, "a squad row dragged onto a unit sends it in, benches the other")
	before = pre._placed.duplicate()
	await _drag(_hex_px(pre, pre._placed[bench.id]), _hex_px(pre, pre._board.spawns.enemy[0]))
	_check(pre._placed == before, "a drop off the deploy hexes changes nothing")
	await _move(_hex_px(pre, pre._board.spawns.enemy[0]) + Vector2(0, -30))
	_check(pre._hover_card.visible and pre._hover_card.unit != null and pre._hover_card.unit.team == "enemy", "hovering an enemy shows its card")
	await _move(Vector2(8, 8))
	# equipment: open, pick a unit who can wear a loose piece, double-click it
	pre._open_overlay(pre._equip)
	await get_tree().create_timer(0.4).timeout
	_check(pre._equip.visible and pre._equip.doll.character != null, "Equipment opens on the live paperdoll")
	game.run.inventory.append(game.run.make_item("vest", "E"))      # fight 1 has no loot yet
	pre._equip.refresh()
	await get_tree().process_frame
	var it: Dictionary = {}
	for x in game.run.inventory:
		if game.run.can_equip(pre._sel, x):
			it = x
			break
	if not it.is_empty():
		var tile: BWItemTile = null
		for t in pre._equip._grid.get_children():
			if t is BWItemTile and t.item == it:
				tile = t
		if tile:
			await _move(tile.get_global_rect().get_center())
			_check(pre._equip.card._body.visible, "hovering a tile shows its card before equipping")
			await _click(tile.get_global_rect().get_center(), true)
		_check(pre._equip.doll.character != null and pre._stats.unit == pre._sel, "the paperdoll and sheet follow the equip")
		_check(pre._sel.equipment.get(it.slot, {}) == it, "double-click equips %s" % BWRun.item_name(it))
	pre._close_overlays()


func _hex_px(pre: BWPrebattleScreen, h: Vector2i) -> Vector2:
	return pre._cam.unproject_position(pre._bv.top_center(h))


func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _move(p: Vector2, mask: int = 0) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _win(p)
	mm.global_position = mm.position
	mm.button_mask = mask
	Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame


func _button(p: Vector2, pressed: bool, dbl: bool = false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = dbl
	mb.position = _win(p)
	mb.global_position = mb.position
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(mb)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(p: Vector2, dbl: bool = false) -> void:
	await _move(p)
	await _button(p, true)
	await _button(p, false)
	if dbl:
		await _button(p, true, true)
		await _button(p, false)


func _drag(from: Vector2, to: Vector2) -> void:
	await _move(from)
	await _button(from, true)
	for i in 10:
		await _move(from.lerp(to, float(i + 1) / 10.0), MOUSE_BUTTON_MASK_LEFT)
	await _button(to, false)
	await get_tree().process_frame


func _wait_screen(type, timeout: float = 8.0) -> Node:
	return await _wait_any([type], timeout)


func _wait_any(types: Array, timeout: float) -> Node:
	var t := 0.0
	while t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		for ty in types:
			if is_instance_valid(game.screen) and is_instance_of(game.screen, ty) and game.screen.is_inside_tree():
				await get_tree().create_timer(0.8).timeout
				_check(true, "reached %s" % game.screen.get_script().get_global_name())
				return game.screen
	_check(false, "timed out waiting for %s (on %s)" % [types, game.screen])
	_finish()
	return null


## A real key press through the input pipeline (press + release).
func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("flow-probe: %s" % ("passed" if _fails == 0 else "%d failed" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

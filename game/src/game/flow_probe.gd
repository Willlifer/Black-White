class_name BWFlowProbe
extends Node
## Drives the real BWGame through every screen transition: title → roster
## (portrait unpick, codex) → (D233: the first perks are drawn, no picker) → the hall's
## prep (equip, give, the discard pile and sorting, D234/D235) → the room select (D190) →
## pre-battle (the free scrolls, D236) → combat (autoplayed; picks auto) →
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
	# D233: no picker: straight from the roster to the hall, every first perk drawn.
	var prep: BWPrepScreen = await _wait_screen(BWPrepScreen, 12.0)
	_probe_first_perks(prep)
	await _probe_prep(prep)
	var trashed: Array = game.run.trash.duplicate()
	_key(KEY_ENTER)
	# D208: fight 1 has no room choice: straight from the hall to the pre-battle
	var pre_n: Node = await _wait_any([BWPrebattleScreen, BWRoomScreen], 12.0)
	_check(pre_n is BWPrebattleScreen, "fight 1: no room screen, straight to the pre-battle")
	var pre := pre_n as BWPrebattleScreen
	_check(pre._board.name == BWBoard.load_file("res://maps/%s.json" % game.run.map_queue[0]).name, "on the queue's front map (%s)" % game.run.map_queue[0])
	_check(pre._enemies.size() == 3, "facing three")
	_check(game.run != null and game.run.squad.size() == 6, "run started with six")
	_check(game.run.roster_seed == rolled_seed and game.run.roster_rows.size() == 20 		and str(game.run.roster_rows[3].weapon_model) == str(rolled_rows[3].weapon_model), "the run keeps the screen's roll (D150)")
	for k in 3:
		pre._on_deploy(true, game.run.squad[k])
	_check(not pre._begin.disabled, "three placed, Begin enabled")
	await _probe_prebattle(pre)
	_check(not pre._begin.disabled, "still three placed after the drags, Begin enabled")
	_check(not trashed.is_empty() and game.run.trash == trashed, "the discard pile carried from the hall to the pre-battle")
	pre._try_begin()
	var combat: BWCombatScreen = await _wait_screen(BWCombatScreen)
	_check(game.run.trash.is_empty() and trashed.all(func(x): return not x in game.run.inventory), "the battle started: the discard pile is gone (D234)")
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
	# D208: fight 2 has no room choice either
	var pre2: Node = await _wait_any([BWPrebattleScreen, BWRoomScreen], 20.0)
	_check(pre2 is BWPrebattleScreen, "fight 2: no room screen, straight to the pre-battle")
	_check(pre2 != null and game.run.fight == 2 and game.run.day == 2, "day advanced, on to fight 2")
	_check(FileAccess.file_exists(BWGame.SAVE_PATH), "run autosaved")
	# The choice starts at fight 3: skip ahead on paper and take the room flow.
	game.run.fight = 3
	game.run.room_offer = {}
	game.go_rooms()
	var rooms3: BWRoomScreen = await _wait_screen(BWRoomScreen, 20.0)
	await _probe_rooms(rooms3, false)
	var pre3: BWPrebattleScreen = await _wait_screen(BWPrebattleScreen, 20.0)
	_check(pre3 != null and game.run.map_for(3) == _room_map, "fight 3 plays the room taken by click")
	_check(pre3._board.name == BWBoard.load_file("res://maps/%s.json" % _room_map).name, "pre-battle is on the chosen room's map (%s)" % _room_map)
	# D353: fight 4 is a boss choice: the Obelisks or the Twins; key 2 takes the Twins
	game.run.fight = 4
	game.run.room_offer = {}
	game.go_rooms()
	var rooms4: BWRoomScreen = await _wait_screen(BWRoomScreen, 20.0)
	_check(rooms4 != null and rooms4.rooms.map(func(c): return str(c.get("boss", ""))) == ["obelisks", "twins"], "fight 4: two boss cards, the Obelisks and the Twins")
	_check(rooms4 != null and rooms4.enemies[1].size() == 2 and rooms4.enemies[1].all(func(u): return BWTwins.is_twin(u)), "the Twins' card shows Noon and Dusk")
	await get_tree().create_timer(0.3).timeout
	_key(KEY_2)
	var pre4: BWPrebattleScreen = await _wait_screen(BWPrebattleScreen, 20.0)
	_check(BWRooms.chosen_index(game.run) == 1 and game.run.is_twins(), "key 2 takes the Twins")
	_check(pre4 != null and game.run.map_for(4) == "court" and pre4._board.name == BWBoard.load_file("res://maps/court.json").name, "the pre-battle is on the court")
	_check(pre4 != null and pre4._need == 3, "three deploy against the Twins")
	_finish()


var _room_map := ""
var _room_enemies: Array = []


## D190 the room select: two cards (Standard, Hard), distinct maps, three
## enemies each, thumbnails land; hovering a card opens its detail and an
## enemy's unit card. Before fight 1 (`from_hall`) Esc goes back to the hall
## and Enter returns to the same two rooms, then key 2 takes Hard; after a
## day Esc stays, and a click on the Standard card takes it.
func _probe_rooms(rs: BWRoomScreen, from_hall: bool) -> void:
	var run := game.run
	_check(rs.cards.size() == 2 and rs.rooms[0].kind == "standard" and rs.rooms[1].kind == "hard", "two room cards: Standard, Hard (or an encounter, D208)")
	_check(rs.rooms[0].map != rs.rooms[1].map, "two different maps (%s / %s)" % [rs.rooms[0].map, rs.rooms[1].map])
	_check(rs.enemies[0].size() == 3 and rs.enemies[1].size() >= 1, "three enemies in the Standard room, a squad in the other")
	var t := 0.0
	while not rs.thumbs_ready() and t < 10.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	_check(rs.thumbs_ready(), "both map thumbnails rendered")
	var offered: Array = rs.rooms.duplicate(true)
	await _move(rs.cards[1].get_global_rect().position + Vector2(30, 30))
	_check(rs.hover == 1 and rs._details[1].all(func(d): return d.visible), "hovering a card opens its detail")
	var cols: Array = rs.cards[1].find_children("*", "VBoxContainer", true, false).filter(func(c): return c.mouse_filter == Control.MOUSE_FILTER_PASS)
	if not cols.is_empty():
		await _move(cols[0].get_global_rect().get_center())
	_check(rs.unit_card.visible and rs.unit_card.unit == rs.enemies[1][0], "hovering an enemy shows its unit card")
	await _move(Vector2(8, 8))
	await get_tree().process_frame
	if from_hall:
		_key(KEY_ESCAPE)
		await get_tree().process_frame
		if game.screen == rs and rs.chosen < 0:
			_key(KEY_ESCAPE)                  # the first Esc closed a leftover hover card
		var back: BWPrepScreen = await _wait_screen(BWPrepScreen)
		_check(back != null, "Esc before fight 1 goes back to the hall")
		_key(KEY_ENTER)
		var again: BWRoomScreen = await _wait_screen(BWRoomScreen, 12.0)
		_check(again.rooms == offered, "the same two rooms again")
		_room_map = str(offered[1].map)
		_room_enemies = offered[1].enemies
		_key(KEY_2)
		await get_tree().create_timer(0.5).timeout
		_check(BWRooms.chosen_index(run) == 1, "key 2 takes the Hard room")
	else:
		_key(KEY_ESCAPE)
		await get_tree().create_timer(0.4).timeout
		_check(game.screen == rs, "after a day Esc doesn't leave the room choice")
		_room_map = str(offered[0].map)
		_room_enemies = offered[0].enemies
		await _click(rs.cards[0].get_global_rect().get_center())
		await get_tree().create_timer(0.5).timeout
		_check(BWRooms.chosen_index(run) == 0, "a click takes the Standard room")


## D127 downtime: name-only tiles, D175 two of the three per unit (keys
## 1..n); D176 Branch out shows its two cards on the tile and a card is the
## choice; everyone set enables Progress day; after the 5 s day one card per
## unit (any key goes on), each followed by that unit's pickers (Branch out
## always owes a perk and a skill pick); nothing banked; then the day card.
func _probe_downtime(down: BWDowntimeScreen) -> void:
	var run := game.run
	var u0: BWUnit = run.squad[0]
	_check(down._tile_btns.size() == 2 and down._tile_btns.keys() == run.day_choices(u0), "two tiles, the day's: %s" % [down._tile_btns.keys()])
	_check(down._tile_btns.values().all(func(b): return b.tooltip_text == ""), "no tooltip on any tile")
	_check(down._go.disabled, "Progress day waits for everyone")
	var bi := -1
	for i in run.squad.size():
		if "branch_out" in run.day_choices(run.squad[i]):
			bi = i
			break
	_check(bi >= 0, "someone is offered Branch out today")
	if bi >= 0:
		var ub: BWUnit = run.squad[bi]
		down._select(bi)
		await get_tree().process_frame
		var bt = down._tile_btns["branch_out"]
		var cards: Array = run.branch_preview(ub)
		_check(bt is BWDowntimeWidgets.BranchTile and bt.cards == cards and cards.size() == 2, "Branch out shows its two cards before committing: %s" % [cards])
		var k2 := -1
		for n in down._keys.size():
			if down._keys[n] == ["branch_out", 1]:
				k2 = n
		_key(KEY_1 + k2)
		await get_tree().process_frame
		_check(down._plans[ub.id] == "branch_out" and int(down._branch.get(ub.id, -1)) == 1, "key %d = Branch out's second card" % (k2 + 1))
		var other: String = run.day_choices(ub).filter(func(c): return c != "branch_out")[0]
		var ko: int = down._keys.find([other, -1])
		_key(KEY_1 + ko)
		await get_tree().process_frame
		_check(down._plans[ub.id] == other and not down._branch.has(ub.id), "key %d changes it to %s (the cards discarded)" % [ko + 1, other])
		down._select(0)
	for i in run.squad.size():
		var u: BWUnit = run.squad[i]
		var offer := run.day_choices(u)
		var c: String = "branch_out" if "branch_out" in offer else str(offer[i % 2])
		down._plans[u.id] = c
		if c == "branch_out":
			down._branch[u.id] = i % 2
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


## D233 run start: no picker; each unit already holds one perk of its own
## element, drawn at random, and the hall names it under the unit.
func _probe_first_perks(prep: BWPrepScreen) -> void:
	var run := game.run
	_check(run.pending_picks().is_empty(), "nothing owed at run start (D233)")
	for i in run.squad.size():
		var u: BWUnit = run.squad[i]
		var pid := BWRun.first_perk(u)
		_check(u.perks.size() == 1 and pid != "" and str(BWPicks.perk(pid).element) == u.element, "%s drew %s" % [u.name, pid])
		var lab: Label = (prep._tags[i].box as Control).find_child("perk", false, false)
		_check(lab != null and lab.text.contains(str(BWPicks.perk(pid).name)), "the hall shows %s's perk (%s)" % [u.name, lab.text if lab else "-"])


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
	await _probe_trash_and_sort(prep._panel)
	_key(KEY_I)
	await get_tree().process_frame
	_check(prep.get_children().any(func(c): return c is BWCodex), "Info opens the codex in the hall")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not prep._open, "Esc closes the panel")


## D234 the discard pile and D235 sorting in the hall's gear panel: drag a
## loose tile onto the pile (real mouse), a double-click on it takes it back,
## the Discard button sends the picked one; Element sorts the grid by the
## element order; the shop won't offer what's on the pile. One stays on the
## pile for the battle to throw away.
func _probe_trash_and_sort(gp: BWGearPanel) -> void:
	var run := game.run
	for b in ["vest", "chaps"]:
		run.inventory.append(run.make_item(b, "E"))
	var fire := run.make_item("tights", "C")
	fire["imbue"] = "fire"
	run.inventory.append(fire)
	gp.refresh()
	await get_tree().process_frame
	var tiles: Array = gp._grid.get_children().filter(func(c): return c is BWItemTile)
	var n := run.inventory.size()
	if tiles.is_empty():
		_check(false, "loose tiles to discard")
		return
	var src: BWItemTile = tiles[0]
	for c in tiles:
		if str(c.item.base) == "vest":
			src = c
	var it: Dictionary = src.item
	var where := "tile %s, pile %s" % [src.get_global_rect(), gp._trash_box.get_global_rect()]
	await _drag(src.get_global_rect().get_center(), gp._trash_box.get_global_rect().get_center())
	await get_tree().process_frame
	_check(it in run.trash and run.inventory.size() == n - 1, "a tile dragged onto the pile is set aside (%s)" % where)
	_check(gp._trash_title.text.contains("1"), "the pile shows its count (%s)" % gp._trash_title.text)
	var tt: Array = gp._trash_row.get_children().filter(func(c): return c is BWItemTile)
	if not tt.is_empty():
		await _click(tt[0].get_global_rect().get_center(), true)
	_check(it in run.inventory and run.trash.is_empty(), "a double-click on the pile keeps it")
	gp._pick_tile(_tile_of(gp, it))
	gp._trash_btn.pressed.emit()
	await get_tree().process_frame
	_check(it in run.trash and gp._sel.is_empty(), "Discard picked sends the picked one")
	gp.set_sort("element")
	await get_tree().process_frame
	var order: Array = gp._grid.get_children().filter(func(c): return c is BWItemTile and not c.is_queued_for_deletion()).map(func(c): return c.item)
	_check(order == BWInvSort.sorted(run.inventory, "element") and order.size() == run.inventory.size(), "Element sorts the grid")
	var first_el := BWRun.item_element(order[0]) if not order.is_empty() else ""
	_check(first_el != "" , "an elemental piece leads (%s)" % first_el)
	_check(gp._sort_btns["element"].button_pressed, "the Element button shows pressed")
	var sh := BWShopPanel.new(run)
	add_child(sh)
	sh.open(run.squad[0])
	var offered: Array = sh._left.get_children().filter(func(c): return c is BWItemTile).map(func(c): return c.item)
	_check(not it in offered, "the shop doesn't offer a discarded item")
	_check(sh._sort_btns["element"].button_pressed, "the shop keeps the session's sort")
	sh.queue_free()
	BWInvSort.set_mode("newest")


func _tile_of(gp: BWGearPanel, it: Dictionary) -> BWItemTile:
	for c in gp._grid.get_children():
		if c is BWItemTile and c.item == it and not c.is_queued_for_deletion():
			return c
	return null


## D236 the shop's scrolls are free: pick one, pick a worn piece, Use scroll.
func _probe_free_scroll(pre: BWPrebattleScreen) -> void:
	var run := game.run
	pre._open_overlay(pre._shop)
	await get_tree().create_timer(0.4).timeout
	var sh := pre._shop
	var s: Dictionary = run.scrolls[0]
	var n := run.inventory.size()
	sh.pick_scroll(s)
	_check(sh.mode == "scroll" and sh._title.text.contains("free"), "a scroll opens its flow, free (%s)" % sh._title.text)
	var target: Dictionary = run.squad[0].equipment.main_hand
	sh._pick_target(target)
	_check(not sh._confirm.disabled and sh._confirm.text == "Use scroll", "a target alone unlocks Use scroll")
	sh._confirm.pressed.emit()
	await get_tree().process_frame
	_check(s.sold and str(target.get("imbue", "")) == str(s.element) and run.inventory.size() == n, "used for free: the weapon took %s, nothing paid" % s.element)
	pre._close_overlays()


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
	await _probe_free_scroll(pre)


func _hex_px(pre: BWPrebattleScreen, h: Vector2i) -> Vector2:
	return pre._cam.unproject_position(pre._bv.top_center(h))


func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


var _last_mouse := Vector2.ZERO


func _move(p: Vector2, mask: int = 0) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _win(p)
	mm.global_position = mm.position
	mm.relative = mm.position - _last_mouse        # the GUI's drag threshold sums `relative` (D234's drag)
	_last_mouse = mm.position
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

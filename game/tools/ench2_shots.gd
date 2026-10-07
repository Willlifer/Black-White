extends SceneTree
## Review renders for Enchantments v2 and the shop redesign (D196-D205), from
## the real screens (needs a window):
##   [SHOTS=<dir>] [MODE=shop|knell] godot --path . --resolution 1920x1080 --script res://tools/ench2_shots.gd
## ench2_shop.png          the shop: the featured scrolls over the stock (1 head, 1 chest, 1 legs, 2 weapons)
## ench2_scroll_card.png   a scroll's hover card (the row it holds, armour vs weapon, the price)
## ench2_scroll_trade.png  the scroll flow (free since D236): the target picked, the item after
## ench2_scroll_weapon.png   the scroll on a weapon: the after card (D206)
## ench2_imbued_card.png    an imbued C weapon: its enchantment, its imbue, the imbue's enchantment
## ench2_cursed_card.png   a cursed item's card: the curse mark on tile, name and kind line
## ench2_cursed_card_cost.png  the same card scrolled to its passive: the cost spelled out
## ench2_knell_<n>.png     combat: a KO with Death Knell (frames; the floater and the burst)
var out := ""
var pre: BWPrebattleScreen


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = root.get_final_transform() * p
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await process_frame
	await process_frame


func _go() -> void:
	var mode := OS.get_environment("MODE")
	if mode == "" or mode == "shop":
		await _shop()
	if mode == "" or mode == "knell":
		await _knell()
	quit(0)


func _shop() -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6                                  # tier C: the v2 families are unlocked
	run.restock_shop()
	var cursed := run.make_item("sword", "B", "bloodpact")
	run.inventory.append(cursed)
	run.inventory.append(run.make_item("feathered_cap", "B", "glass"))
	for i in 3:
		run.inventory.append(run.random_item("C"))
	pre = BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k])
	pre._select(run.squad[0])
	await _wait(0.8)
	pre._open_overlay(pre._shop)
	await _wait(1.2)
	var sh := pre._shop
	await _shot("ench2_shop")
	# a scroll's hover card (the thunder one)
	var tiles := sh._scroll_row.get_children()
	var tt: BWItemTile = tiles[3].get_child(1)          # D380: each scroll tile sits under its FEATURED tag
	await _move(tt.get_global_rect().get_center())
	await _wait(0.5)
	sh._hover_scroll(tt.item)
	await _wait(0.3)
	await _shot("ench2_scroll_card")
	# the scroll flow: fire scroll (free, D236), the unit's chest as the target
	await _move(Vector2(4, 4))
	sh.pick_scroll(run.scrolls[0])
	await _wait(0.2)
	var target: Dictionary = run.squad[0].equipment.get("chest", {})
	if target.is_empty():
		target = run.inventory[0]
	sh.theirs = target
	sh.refresh()
	await _wait(0.8)
	await _shot("ench2_scroll_trade")
	# D206: the same scroll on a weapon (the imbue takes the element and its row)
	sh.theirs = run.squad[0].equipment.main_hand
	sh.refresh()
	await _wait(0.6)
	(sh._card_b.get_parent().get_parent() as ScrollContainer).scroll_vertical = 140   # to the imbue lines
	await _wait(0.2)
	await _shot("ench2_scroll_weapon")
	(sh._card_b.get_parent().get_parent() as ScrollContainer).scroll_vertical = 0
	# D206: an imbued C weapon's card (three lines: enchantment, imbue, imbue enchantment)
	sh.set_mode("trade")
	await _wait(0.3)
	for t in sh._right.get_children():
		if t is BWItemTile and str(t.item.slot) == "main_hand":
			sh._hover(t.item, false)
			break
	await _wait(0.3)
	(sh._card_b.get_parent().get_parent() as ScrollContainer).scroll_vertical = 140
	await _wait(0.2)
	await _shot("ench2_imbued_card")
	(sh._card_b.get_parent().get_parent() as ScrollContainer).scroll_vertical = 0
		# a cursed item's card (trade side, hovered)
	sh.set_mode("trade")
	await _wait(0.3)
	for t in sh._left.get_children():
		if t is BWItemTile and t.item == cursed:
			await _move(t.get_global_rect().get_center())
			await _wait(0.4)
			sh._hover(cursed, true)
			break
	await _wait(0.4)
	await _shot("ench2_cursed_card")
	(sh._card_a.get_parent().get_parent() as ScrollContainer).scroll_vertical = 140   # the cost, scrolled to
	await _wait(0.2)
	await _shot("ench2_cursed_card_cost")
	pre.queue_free()
	await _wait(0.5)


## Death Knell: Stryker KOs Rui; Demeter and Gail stand within 1 of Rui and
## take the burst. Frames every 0.25 s through the playback.
func _knell() -> void:
	BWMusic.ensure(root)
	BWSettings.put("cutscenes", "default")
	var att := BWRosterKits.unit("stryker")
	var mates := [BWRosterKits.unit("kira"), BWRosterKits.unit("bob")]
	var rui := BWRosterKits.unit("rui")
	var dem := BWRosterKits.unit("demeter")
	var gail := BWRosterKits.unit("gail")
	var w: Dictionary = att.equipment.get("main_hand", {})
	if w.is_empty():
		w = { "uid": "knell", "base": att.weapon_model, "slot": "main_hand", "weight": att.weapon_class, "tier": "C", "stats": {}, "worn": {} }
		att.equipment["main_hand"] = w
	w["enchant"] = "death_knell"
	att.stats["dex"] = 60
	var s := BWCombatScreen.new()
	s.configure("res://maps/arena.json", [att] + mates, [rui, dem, gail], [], 3)
	root.add_child(s)
	await _wait(7.0)
	while s._busy:
		await process_frame
	var b := s.battle
	var cells: Array = b.board.cells().filter(func(h): return b.board.is_passable(h) and b.board.elevation(h) == 0)
	var T := Vector2i(-1, -1)
	for h in cells:
		var ring: Array = BWHex.neighbors(h).filter(func(n): return n in cells)
		if ring.size() == 6:
			T = h
			break
	var ring2: Array = BWHex.neighbors(T)
	var place := func(u: BWUnit, h: Vector2i) -> void:
		u.pos = h
		s._views[u.id].position = s.board_view.top_center(h)
	place.call(rui, T)
	place.call(att, ring2[3])
	place.call(dem, ring2[0])
	place.call(gail, ring2[1])
	var far: Array = cells.filter(func(h): return BWHex.distance(h, T) >= 4 and b.unit_at(h) == null)
	place.call(mates[0], far[0])
	place.call(mates[1], far[3])
	rui.hp = 1
	b.tiles.entries.clear()
	s.board_view.refresh_tiles(true)
	att.refresh_effects()
	b.refresh_effects()
	s._face_all()
	b.queue = [att]
	b.turn_index = 0
	b._begin_turn()
	s._queue.clear()
	s.ui.set_acting(att, b.tiles)
	s._show_options()
	s.rig.follow(s.board_view.top_center(T), true)
	s.rig.dist = 13.0
	s.rig.pitch = deg_to_rad(48.0)
	await _wait(0.8)
	b.attack(att, rui)
	print("events: ", b.history.slice(-14).map(func(e): return str(e.type) + (":" + str(e.get("name", "")) if e.type == "enchant" else "")))
	s._after_events()
	for k in 24:
		await _wait(0.25)
		await _shot("ench2_knell_%02d" % k)

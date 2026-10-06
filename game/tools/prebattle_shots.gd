extends SceneTree
## Review renders of the pre-battle screen (placement with an enemy hovered,
## a drag, the paperdoll with an item card, the stat panel, shop, re-imbue)
## on a sample run, written as ui_prebattle_*.png:
##   SHOTS=<dir> [MODE=place|gear|shop] godot --path . --script res://tools/prebattle_shots.gd
## Needs a window (real renders, not headless).
var out := ""
var pre: BWPrebattleScreen
func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	_go.call_deferred()
func _wait(s: float) -> void:
	await create_timer(s).timeout
func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)
func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p
func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _win(p)
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await process_frame
	await process_frame
func _go() -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var e := run.enemies_for(1)
	for x in e:
		x.hp = 0
	run.after_fight(true, run.squad.slice(0, 3), e, e, [])
	for i in 4:
		run.inventory.append(run.random_item("D"))
	run.squad[0].expertise["axe"] = 14
	run.squad[0].affinity["fire"] = 6
	run.equip(run.squad[0], run.make_item("platemail", "D"))
	var it := run.make_item("feathered_full_helm", "D")
	run.inventory.append(it)
	run.equip(run.squad[0], it)
	pre = BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k])
	pre._select(run.squad[0])
	await _wait(1.0)
	var mode := OS.get_environment("MODE")
	if mode == "" or mode == "place":
		var p := pre._cam.unproject_position(pre._bv.top_center(pre._board.spawns.enemy[1])) + Vector2(0, -40)
		await _move(p)
		await _wait(0.6)
		await _shot("ui_prebattle_placement")
		# a drag in progress
		var a := pre._cam.unproject_position(pre._bv.top_center(pre._placed[run.squad[0].id]))
		pre._begin_drag(run.squad[0], "map", a)
		var free: Array = pre._board.deploy.player.filter(func(h): return not h in pre._placed.values())
		var to := pre._cam.unproject_position(pre._bv.top_center(free[free.size() - 1]))
		pre._activate_drag()
		pre._update_drag(to)
		await _wait(0.3)
		await _shot("ui_prebattle_drag")
		pre._cancel_drag()
	if mode == "" or mode == "gear":
		pre._open_overlay(pre._equip)
		await _wait(1.2)
		var tile: BWItemTile = null
		for t in pre._equip._grid.get_children():
			if t is BWItemTile and t.item.slot != "main_hand" and not t.blocked:
				tile = t
				break
		if tile:
			pre._equip._pick_tile(tile)
			await _move(tile.get_global_rect().get_center())
		await _wait(1.5)
		await _shot("ui_prebattle_paperdoll")
		pre._close_overlays()
		await _move(Vector2(5, 5))
		await _wait(0.3)
		await _shot("ui_prebattle_stats")
	if mode == "" or mode == "shop":
		pre._open_overlay(pre._shop)
		await _wait(0.6)
		var g := pre._shop._left.get_children()
		if g.size() > 0 and g[0] is BWItemTile:
			pre._shop._pick_mine(g[0].item)
		var r := pre._shop._right.get_children()
		if r.size() > 1:
			pre._shop._on_shop_item_selected(r[1].item)
		await _wait(0.8)
		await _shot("ui_prebattle_shop")
		pre._shop.set_mode("reimbue")
		await _wait(0.2)
		var s := pre._shop._left.get_children()
		if s.size() > 0 and s[0] is BWItemTile:
			pre._shop._pick_mine(s[0].item)
			await _wait(0.1)
			var t := pre._shop._right.get_children()
			if t.size() > 0 and t[0] is BWItemTile:
				pre._shop.theirs = t[0].item
				pre._shop.refresh()
		await _wait(0.6)
		await _shot("ui_prebattle_reimbue")
	quit(0)

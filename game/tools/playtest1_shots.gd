extends SceneTree
## D233-D236 review renders, from the real screens (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/playtest1_shots.gd
## playtest1_gear_trash.png   the pre-battle gear panel: three pieces on the discard pile, its count
## playtest1_gear_sorted.png  the same grid sorted by Element (fire .. light, plain last)
## playtest1_hall_perks.png   the hall before fight 1: each unit's drawn first perk under its name
## playtest1_shop.png         the shop: the seven free scrolls, sorted grids
## playtest1_shop_scroll.png  a scroll's flow: worn on the left, loose on the right, Use scroll
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _run() -> BWRun:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6                                  # tier C stock, C+ imbues
	run.restock_shop()
	for i in 9:
		run.inventory.append(run.random_item(["E", "D", "C"][i % 3]))
	for spec in [["flamberge", "fire"], ["sword", "ice"], ["m1911", "light"]]:
		var it := run.make_item(spec[0], "C")
		it["imbue"] = spec[1]
		run.inventory.append(it)
	return run


func _go() -> void:
	BWMusic.ensure(root)
	BWItemIcons.ensure(root)
	BWInvSort.set_mode("newest")
	var run := _run()
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k])
	pre._select(run.squad[0])
	await _wait(0.8)
	pre._open_overlay(pre._equip)
	await _wait(1.5)
	var gp: BWGearPanel = pre._equip
	for k in 3:
		gp.discard(run.inventory[k])
	await _wait(1.0)
	print("trash box ", gp._trash_box.get_global_rect(), " panel ", gp.get_global_rect(), " screen ", root.get_visible_rect().size)
	await _shot("playtest1_gear_trash")
	gp.set_sort("element")
	await _wait(1.0)
	await _shot("playtest1_gear_sorted")
	pre._close_overlays()
	await _wait(0.3)
	pre._open_overlay(pre._shop)
	await _wait(1.2)
	await _shot("playtest1_shop")
	var sh := pre._shop
	sh.pick_scroll(run.scrolls[0])
	sh._pick_target(run.squad[0].equipment.main_hand)
	await _wait(0.8)
	await _shot("playtest1_shop_scroll")
	BWInvSort.set_mode("newest")
	pre.queue_free()
	await _wait(0.3)
	# the hall before fight 1: the drawn perks under the names
	var hall := BWPrepScreen.new()
	hall.run = BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 1)
	root.add_child(hall)
	await _wait(3.0)
	await _shot("playtest1_hall_perks")
	quit(0)

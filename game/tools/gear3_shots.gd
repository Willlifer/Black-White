extends SceneTree
## D403-D404 review renders, from the real pre-battle screen (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/gear3_shots.gd
## gear3_preview.png   Optimize all's diff with the primary / secondary reasons
## gear3_header.png    the gear panel header: Optimize all [O] + Unequip all [U],
##                     the per-unit Optimize / Unequip row
## gear3_unequip.png   Unequip all's one-line confirm
## gear3_undo.png      after Apply: main hands only, "Undo unequip"
## gear3_hall.png      the hall's prep with both header buttons
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


func _ench(el: String) -> String:
	for row in BWData.table("enchantments"):
		if str(row.element) == el and not BWEffects.cursed(row) and str(row.id) != BWEffects.WARDED:
			return str(row.id)
	return ""


## A mid-run squad whose top two units have a focus and a learned 2nd
## element, with pieces in both in the inventory.
func _run() -> BWRun:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6
	var used := [[2, 5, 410], [0, 5, 260], [4, 3, 120], [1, 2, 60]]
	for x in used:
		run.stats.units[run.squad[x[0]].id] = { "fights": x[1], "kos": 0, "damage": x[2], "taken": 0, "mvp": 0 }
	for k in [2, 0]:
		var u: BWUnit = run.squad[k]
		var free: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
		var sec: String = free[k % free.size()]
		u.affinity[sec] = 25
		var pri := u.element
		var specs := [["wizard_hat", "D", pri], ["chaps", "E", pri], ["chain_mail", "B", sec], ["platelegs", "B", sec]] if k == 2 \
			else [["vest", "C", pri], ["leather_cap", "B", sec], ["brigandine", "A", sec]]
		for spec in specs:
			if BWData.row("equipment", spec[0]).is_empty():
				continue
			run.inventory.append(run.make_item(spec[0], spec[1], _ench(spec[2])))
	for i in 4:
		run.inventory.append(run.random_item(["D", "C", "B"][i % 3]))
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
	pre._select(run.squad[2])
	await _wait(0.8)
	pre._open_overlay(pre._equip)
	await _wait(1.5)
	var gp: BWGearPanel = pre._equip
	gp.optimize_all()
	await _wait(0.8)
	print(gp._preview_text.get_parsed_text())
	await _shot("gear3_preview")
	gp.apply_preview()
	await _wait(1.5)
	await _shot("gear3_header")
	gp.unequip_all()
	await _wait(0.8)
	print(gp._preview_title.text, " | ", gp._preview_text.get_parsed_text())
	await _shot("gear3_unequip")
	gp.apply_preview()
	await _wait(1.5)
	await _shot("gear3_undo")
	pre.queue_free()
	await _wait(0.3)
	var hall := BWPrepScreen.new()
	hall.run = _run()
	root.add_child(hall)
	await _wait(3.0)
	hall._select(2)
	await _wait(1.5)
	await _shot("gear3_hall")
	quit(0)

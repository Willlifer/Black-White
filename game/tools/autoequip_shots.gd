extends SceneTree
## D315-D318 review renders, from the real pre-battle screen (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/autoequip_shots.gd
## autoequip_preview.png  Optimize all's diff panel over the gear panel (Apply / Cancel)
## autoequip_after.png    the gear panel after Apply: the new loadout, Undo optimize
## autoequip_unit.png     the per-unit Optimize's diff (inventory only)
## autoequip_hall.png     the hall's prep with the same header button
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


## A mid-run squad: fights and damage on the record, a mixed inventory with
## pieces in the squad's own elements.
func _run() -> BWRun:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6
	var used := [[2, 5, 410], [0, 5, 260], [4, 3, 120], [1, 2, 60]]
	for x in used:
		run.stats.units[run.squad[x[0]].id] = { "fights": x[1], "kos": 0, "damage": x[2], "taken": 0, "mvp": 0 }
	for i in 6:
		run.inventory.append(run.random_item(["D", "C", "B"][i % 3]))
	var top: BWUnit = run.squad[2]
	for spec in [["chain_mail", "B"], ["wizard_hat", "C"], ["chaps", "D"]]:
		run.inventory.append(run.make_item(spec[0], spec[1], _ench(top.element)))
	var second: BWUnit = run.squad[0]
	run.inventory.append(run.make_item("platelegs", "C", _ench(second.element)))
	# the top unit's chest is worn by someone used less
	run.squad[5].equipment["chest"] = run.make_item("brigandine", "A", _ench(top.element))
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
	await _shot("autoequip_preview")
	gp.apply_preview()
	await _wait(1.5)
	await _shot("autoequip_after")
	# the per-unit Optimize: a fresh piece in the inventory for this unit
	gp.undo_optimize()
	await _wait(0.5)
	gp.set_unit(run.squad[0])
	await _wait(1.0)
	gp.optimize_unit()
	await _wait(0.8)
	await _shot("autoequip_unit")
	gp.cancel_preview()
	pre.queue_free()
	await _wait(0.3)
	var hall := BWPrepScreen.new()
	hall.run = _run()
	root.add_child(hall)
	await _wait(3.0)
	hall._select(2)
	await _wait(1.5)
	await _shot("autoequip_hall")
	quit(0)

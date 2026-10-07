extends SceneTree
## D277-D284 review renders (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/keystone_shots.gd
## v3_keystone_pick.png       a rank-3 keystone pick: two gold-ruled cards, KEYSTONE over the name
## v3_keystone_unitcard.png   a unit card: the gold sigil after the element, the Keystones line
## v3_keystone_itemcard.png   an item card: the dim "Set: Fire 2/3 · next: Flashpoint" line
## v3_keystone_gear_sets.png  the gear panel: the active sets line under the paper doll
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


func _backdrop() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.theme = BWStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	root.add_child(c)
	return c


func _go() -> void:
	BWMusic.ensure(root)
	BWItemIcons.ensure(root)
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var u: BWUnit = run.squad[0]
	for want in ["fire", "thunder", "ice", "water", "wind", "dark"]:
		var hit := run.squad.filter(func(x): return x.element == want)
		if not hit.is_empty():
			u = hit[0]
			break
	var el := u.element
	# 1. the keystone pick at rank 3
	u.affinity[el] = 30
	BWPicks.auto_resolve(u)                   # the perks owed so far; then undo the keystone it took
	u.keystones.clear()
	var back := _backdrop()
	var req := { "kind": "keystone", "element": el }
	var p := BWPicker.new(u, req, "after fight 3")
	back.add_child(p)
	await _wait(1.0)
	p.select(1)
	await _wait(0.4)
	await _shot("v3_keystone_pick")
	back.queue_free()
	# 2. a unit card with two keystones
	BWPicks.apply(u, req, str(BWPicks.options(u, req)[0].id))
	u.affinity[el] = 60
	BWPicks.auto_resolve(u)
	var hats := { "head": "wizard_hat", "chest": "silken_robe", "legs": "robe_bottoms" }
	var ench := { "fire": "kindled", "water": "brimming", "ice": "glacial", "thunder": "stormcallers",
		"wind": "gusting", "dark": "abyssal", "light": "dawning" }
	u.equipment["head"] = run.make_item(hats.head, "C", ench.get(el, "kindled"))
	u.equipment["chest"] = run.make_item(hats.chest, "C", ench.get(el, "kindled"))
	u.equipment.erase("legs")
	var spare := run.make_item(hats.legs, "C", ench.get(el, "kindled"))
	run.inventory.append(spare)
	u.refresh_effects()
	back = _backdrop()
	var uc := BWUnitCard.new()
	back.add_child(uc)
	uc.position = Vector2(560, 200)
	uc.show_unit(u)
	await _wait(0.8)
	await _shot("v3_keystone_unitcard")
	back.queue_free()
	# 3. the item card: a worn piece (2/3), then a loose one counted as if equipped
	back = _backdrop()
	var ic := BWItemCard.new()
	back.add_child(ic)
	ic.position = Vector2(420, 160)
	ic.show_item(u.equipment.head, u, run, u.equipment.head)
	var ic2 := BWItemCard.new()
	back.add_child(ic2)
	ic2.position = Vector2(1000, 160)
	ic2.show_item(spare, u, run, {})
	await _wait(0.8)
	await _shot("v3_keystone_itemcard")
	back.queue_free()
	# 4. the gear panel with the third piece on: the 3-piece is active
	u.equipment["legs"] = spare
	run.inventory.erase(spare)
	u.refresh_effects()
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k] if run.squad[k] != u else run.squad[k])
	pre._select(u)
	await _wait(0.8)
	pre._open_overlay(pre._equip)
	await _wait(1.5)
	await _shot("v3_keystone_gear_sets")
	quit(0)

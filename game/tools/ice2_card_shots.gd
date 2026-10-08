extends SceneTree
## D399/D400 review renders of the reworked ice picks (needs a window):
##   [SHOTS=<dir>] godot --path . --resolution 1920x1080 --script res://tools/ice2_card_shots.gd
## ice2_keystone_sure_footed.png  an ice unit's rank-3 keystone pick with
##                                Sure-Footed among the two cards, selected
## ice2_perk_ice_legs.png         an ice perk pick with Ice Legs among the cards
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


## Re-seed the unit's draws until `want` is offered; select its card.
func _pick(u: BWUnit, req: Dictionary, want: String, shot: String, after: String) -> void:
	for sd in range(1, 400):
		u.pick_seed = sd
		if want in BWPicks.options(u, req).map(func(o): return str(o.id)):
			break
	var ids: Array = BWPicks.options(u, req).map(func(o): return str(o.id))
	print(shot, ": seed ", u.pick_seed, " options ", ids)
	var back := _backdrop()
	var p := BWPicker.new(u, req, after)
	back.add_child(p)
	await _wait(1.0)
	p.select(maxi(0, ids.find(want)))
	await _wait(0.4)
	await _shot(shot)
	back.queue_free()
	await _wait(0.2)


func _go() -> void:
	BWMusic.ensure(root)
	BWItemIcons.ensure(root)
	var ids := BWData.table("roster").map(func(r): return str(r.id))
	var run := BWRun.start(ids.slice(0, 6), 99)
	var u: BWUnit = null
	for x in run.squad:
		if x.element == "ice":
			u = x
	if u == null:
		u = run.squad[0]
		u.element = "ice"
	u.affinity["ice"] = 30
	BWPicks.auto_resolve(u)
	u.keystones.clear()
	await _pick(u, { "kind": "keystone", "element": "ice" }, "skater", "ice2_keystone_sure_footed", "after fight 3")
	for p in u.perks.duplicate():
		if str(BWPicks.perk(p).element) == "ice":
			u.perks.erase(p)
	await _pick(u, { "kind": "perk", "element": "ice" }, "ice_skate", "ice2_perk_ice_legs", "after fight 1")
	quit()

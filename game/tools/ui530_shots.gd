extends SceneTree
## D532 review renders: the equipment (gear) panel at several window sizes,
## in the pre-battle overlay and the hall's prep, with a full late-run unit:
## a main-hand and a carried weapon of another class, every skill of both
## known (so both skill rows fill), three learned abilities, and a long
## inventory. -> design/art/ui530_<TAG>_<gear|hall>_<w>x<h>.png
##   [TAG=before|after] [RESES=1280x720,1920x1080] [ONLY=gear|hall] [PREFIX=ui540]
## Each gear shot also prints whether the doll column's lower part scrolls
## ("lower_scroll vbar") and the panel's rect against the screen (D540).
##   godot --path . --script res://tools/ui530_shots.gd
## The window is resized in place (canvas_items stretch, base 1600x900), so a
## size larger than the desktop may be clamped: the file name is the size the
## window really got.
const DEFAULT_RESES := "1280x720,1366x768,1600x900,1920x1080,2560x1440,1080x1350"

var out := ""
var tag := "before"
var prefix := "ui530"


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	if OS.get_environment("TAG") != "":
		tag = OS.get_environment("TAG")
	if OS.get_environment("PREFIX") != "":
		prefix = OS.get_environment("PREFIX")
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("shot ", name, " ", img.get_size())


func _run() -> BWRun:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var u: BWUnit = run.squad[0]
	var main := "axe" if u.weapon_class != "axe" else "lance"
	var mains := BWData.table("equipment").filter(func(x): return x.slot == "main_hand" and x.weight == main)
	var it := run.make_item(str(mains[0].id), "B")
	run.inventory.append(it)
	run.equip(u, it, "main_hand")
	var sec := run.make_item("recurve_bow", "C")
	sec.imbue = "fire"
	run.inventory.append(sec)
	run.equip(u, sec, "second")
	u.sync_weapon()
	for wc in [u.weapon_class, "bow"]:
		for k in BWSkillRegistry.pool(wc):
			if not k in u.known_skills:
				u.known_skills.append(k)
	var abil := ["bloodied", "second_wind", "unflinching", "deadeye", "bastion", "flair"]
	for a in abil:
		run.learned[u.id].append(a)
		run.ability_ranks[u.id][a] = 1
		run.equip_ability(u, a)                    # D540: one picked per type, the widest case
	var pieces := BWData.table("equipment")
	for k in 26:
		var row: Dictionary = pieces[(k * 7) % pieces.size()]
		run.inventory.append(run.make_item(str(row.id), ["E", "D", "C", "B"][k % 4]))
	return run


## D540: does anything under the doll scroll, and does the panel fit the screen?
func _report(gp: BWGearPanel, what: String) -> void:
	var ls: ScrollContainer = gp.find_child("lower_scroll", true, false)
	var bar := "n/a"
	if ls != null:
		var vb := ls.get_v_scroll_bar()
		bar = "%s (content %d / view %d)" % [vb.visible, int(vb.max_value), int(ls.size.y)]
	print("[", what, "] lower_scroll vbar ", bar, "  panel ", gp.get_global_rect(), "  screen ", root.get_visible_rect().size)


func _go() -> void:
	var reses := (OS.get_environment("RESES") if OS.get_environment("RESES") != "" else DEFAULT_RESES).split(",")
	var only := OS.get_environment("ONLY")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for r in reses:
		var want := Vector2i(int(r.get_slice("x", 0)), int(r.get_slice("x", 1)))
		DisplayServer.window_set_size(want)
		for i in 6:
			await process_frame
		var got := DisplayServer.window_get_size()
		var tagres := "%dx%d" % [got.x, got.y]
		if got != want:
			print("asked ", want, " got ", got)
		if only == "" or only == "gear":
			var run := _run()
			var pre := BWPrebattleScreen.new()
			pre.run = run
			root.add_child(pre)
			await _wait(1.5)
			for k in 3:
				pre._on_deploy(true, run.squad[k])
			pre._select(run.squad[0])
			await _wait(0.6)
			pre._open_overlay(pre._equip)
			await _wait(1.6)
			_report(pre._equip, "gear " + tagres)
			await _shot("%s_%s_gear_%s" % [prefix, tag, tagres])
			if want == Vector2i(1600, 900):
				var gp: BWGearPanel = pre._equip
				gp._hover_slot(gp._slots["second"])        # the carried weapon's card
				await _wait(1.0)
				await _shot("%s_%s_gearcard_%s" % [prefix, tag, tagres])
				if gp.has_method("discard_tier"):           # D541: Discard ▾ open, a loose item selected
					var tiles: Array = gp._grid.get_children().filter(func(c): return c is BWItemTile)
					if not tiles.is_empty():
						gp._pick_tile(tiles[0])
					gp._discard_btn.show_popup()
					await _wait(0.6)
					await _shot("%s_%s_discardmenu_%s" % [prefix, tag, tagres])
					gp._discard_btn.get_popup().hide()
					gp.discard_tier("D")
					await _wait(0.6)
					await _shot("%s_%s_discarded_%s" % [prefix, tag, tagres])
			pre.queue_free()
			await _wait(0.3)
		if only == "" or only == "hall":
			var hall := BWPrepScreen.new()
			hall.run = _run()
			root.add_child(hall)
			await _wait(3.0)
			hall._select(0)
			await _wait(1.6)
			_report(hall._panel, "hall " + tagres)
			await _shot("%s_%s_hall_%s" % [prefix, tag, tagres])
			hall._panel._hover_slot(hall._panel._slots["second"])   # D573: the full card
			await _wait(1.0)
			await _shot("%s_%s_hallcard_%s" % [prefix, tag, tagres])
			hall.queue_free()
			await _wait(0.3)
	quit(0)

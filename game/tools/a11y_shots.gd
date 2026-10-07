extends SceneTree
## D227-D232 review renders (needs a window):
##   [SHOTS=<dir>] [MODE=all|board|panel|helm|settings|gear] godot --path . --resolution 1920x1080 --script res://tools/a11y_shots.gd
## a11y_board.png        element kanji on, at the game camera: fire/water/light/dark at levels 1-3,
##                       two two-element tiles, the fuse / stasis / gale markers; the acting unit card
## a11y_board_close.png  the same tiles, closer
## a11y_board_off.png    the same frame with the setting off
## a11y_hpbar_off.png    an enemy bar under the combat log, culling disabled (what L-21 saw)
## a11y_hpbar_on.png     the same frame: the bar and its label are hidden behind the panel
## a11y_helm.png         a long-haired unit in a full helm and one in a dragoon helm: no hair pokes out
## a11y_settings.png     Settings with the new Accessibility section
## a11y_gear.png         the gear panel at 1920x1080: every skill row fits (L-22)
var out := ""
var s: BWCombatScreen


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


func _go() -> void:
	BWSettings.put("cutscenes", "default")
	BWMusic.ensure(root)
	var mode := OS.get_environment("MODE")
	if mode in ["", "all", "board", "panel", "helm"]:
		await _fight(mode)
	if mode in ["", "all", "settings"]:
		await _settings()
	if mode in ["", "all", "gear"]:
		await _gear()
	BWKanji.force = null
	quit()


func _fight(mode: String) -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	for u in run.squad:
		BWProgression.level_up(u, 5 - u.level)
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(5))
	run.fight = 5
	var players: Array = run.squad.slice(0, 3)
	players[1].cosmetics["hair_style"] = "long_hair"
	players[1].equipment["head"] = run.make_item("feathered_full_helm", "C")
	players[2].cosmetics["hair_style"] = "long_ponytail"
	players[2].equipment["head"] = run.make_item("dragoon_helm", "C")
	run.prepare_for_battle(players)
	var enemies := BWEncounters.build(run, 5, "blank")
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 5)
	root.add_child(s)
	await _wait(6.0)
	while s._busy:
		await process_frame
	if mode in ["", "all", "board"]:
		await _board()
	if mode in ["", "all", "helm"]:
		await _helm(players[1], players[2])
	if mode in ["", "all", "panel"]:
		await _panel()
	s.queue_free()
	await _wait(0.3)


func _free_hexes(n: int) -> Array:
	var b := s.battle.board
	var c := Vector3.ZERO
	var all := s.battle.side("player") + s.battle.side("enemy")
	for u in all:
		c += s._views[u.id].global_position
	c /= float(all.size())
	var cells := b.cells().filter(func(h): return b.terrain(h) != BWBoard.JAGGED and s.battle.unit_at(h) == null)
	cells.sort_custom(func(a, bb): return BWLook.world(a).distance_to(c) < BWLook.world(bb).distance_to(c))
	return cells.slice(0, n)


func _board() -> void:
	var hs := _free_hexes(16)
	var spec := [[1, 0, ""], [2, 0, ""], [3, 0, ""], [-1, 0, ""], [-2, 0, ""], [-3, 0, ""],
		[0, 1, ""], [0, 2, ""], [0, 3, ""], [0, -1, ""], [0, -2, ""], [0, -3, ""],
		[2, -1, ""], [-3, 1, ""], [0, 0, "fuse"], [0, 0, "stasis"]]
	for i in mini(hs.size(), spec.size()):
		s.battle.tiles.author(hs[i], spec[i][0], spec[i][1], spec[i][2])
	var extra := _free_hexes(17)
	if extra.size() > 16:
		s.battle.tiles.author(extra[16], 0, 0, "gale")
	s.board_view.refresh_tiles(true)
	var c := Vector3.ZERO
	for h in hs:
		c += BWLook.world(h)
	s.rig.follow(c / float(hs.size()), true)
	BWKanji.force = true
	s.ui.set_acting(s.battle.side("player")[0], s.battle.tiles)
	await _wait(1.5)
	await _shot("a11y_board")
	BWKanji.force = false
	s.ui.set_acting(s.battle.side("player")[0], s.battle.tiles)
	await _wait(0.5)
	await _shot("a11y_board_off")
	BWKanji.force = true
	var d := s.rig.dist
	s.rig.dist = 13.0
	await _wait(1.0)
	await _shot("a11y_board_close")
	s.rig.dist = d


func _helm(a: BWUnit, b: BWUnit) -> void:
	var va: Node3D = s._views[a.id]
	var vb: Node3D = s._views[b.id]
	var d := s.rig.dist
	var p := s.rig.pitch
	s.rig.follow((va.global_position + vb.global_position) * 0.5 + Vector3(0, 1.5, 0), true)
	s.rig.dist = maxf(8.0, va.global_position.distance_to(vb.global_position) * 1.4)
	s.rig.pitch = deg_to_rad(20.0)
	await _wait(1.2)
	print("helm: %s hair visible=%s, %s hair visible=%s" % [a.name, s._views[a.id].character.hair.visible, b.name, s._views[b.id].character.hair.visible])
	await _shot("a11y_helm")
	s.rig.dist = d
	s.rig.pitch = p


## Slide the camera until an enemy's bar projects into the combat log.
func _panel() -> void:
	BWKanji.force = false
	BWHPBar3D.hover_unit = null
	s.ui.set_acting(s.battle.side("player")[0], s.battle.tiles)
	var rects: Array = s.ui.cover_rects()
	var feed := Rect2()
	var vis := root.get_visible_rect().size
	for r in rects:
		if (r as Rect2).position.x > vis.x * 0.5 and (r as Rect2).end.y > vis.y * 0.9 and (r as Rect2).end.y > feed.end.y:
			feed = r                             # the bottom-right log plate
	if not feed.has_area():
		print("panel: no log plate in ", rects)
		return
	var cam := root.get_camera_3d()
	var bar: BWHPBar3D = null
	var best := INF
	for u in s.battle.side("player") + s.battle.side("enemy"):      # the bar already nearest the log
		if u == s.battle.side("player")[0]:
			continue
		var bb: BWHPBar3D = s._views[u.id]._hp_bar
		var dd := bb.screen_rect(cam).get_center().distance_to(feed.get_center())
		if dd < best:
			best = dd
			bar = bb
	var keep := BWHPBar3D.covers
	BWHPBar3D.covers = Callable()
	var found := false
	for i in 8:
		var r := bar.screen_rect(cam)
		var goal := feed.get_center() + Vector2(0, -10)
		if r.has_area() and feed.grow(-10).has_point(r.get_center()):
			found = true
			break
		# move the pivot by the ground offset between where the bar is and where it should be
		var y := bar.global_position.y
		var plane := Plane(Vector3.UP, y)
		var at = plane.intersects_ray(cam.project_ray_origin(r.get_center()), cam.project_ray_normal(r.get_center()))
		var want = plane.intersects_ray(cam.project_ray_origin(goal), cam.project_ray_normal(goal))
		if at == null or want == null:
			break
		s.rig.follow(s.rig.pivot + (at - want), true)
		await _wait(0.4)
	print("panel: bar under the log = %s, log %s" % [found, feed])
	await _wait(0.4)
	await _shot("a11y_hpbar_off")
	BWHPBar3D.covers = keep
	await _wait(0.3)
	print("panel: bar covered = %s" % bar.covered)
	await _shot("a11y_hpbar_on")


func _settings() -> void:
	BWKanji.force = null
	BWSettings.put("element_kanji", true)
	var p := BWSettingsPanel.summon(root)
	await _wait(0.8)
	await _shot("a11y_settings")
	p.queue_free()
	BWSettings.put("element_kanji", false)
	await _wait(0.2)


func _gear() -> void:
	BWKanji.force = true
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6
	var u: BWUnit = run.squad[0]
	var fl := run.make_item("flamberge", "C", "cleaving")
	fl.imbue = "wind"
	fl.imbue_enchant = "gusting"
	run.inventory.append(fl)
	run.equip(u, fl, "second")
	for i in 3:
		run.inventory.append(run.random_item("C"))
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k])
	pre._select(u)
	await _wait(0.8)
	pre._open_overlay(pre._equip)
	await _wait(1.5)
	var gp: BWGearPanel = pre._equip
	gp._hover_slot(gp._slots["second"])
	await _wait(1.2)
	var bottom := 0.0
	for c in gp._skills.get_children():
		bottom = maxf(bottom, (c as Control).get_global_rect().end.y)
	print("gear: last skill row bottom %.0f, panel bottom %.0f, screen %s" % [bottom, gp.get_global_rect().end.y, root.get_visible_rect().size])
	await _shot("a11y_gear")
	pre.queue_free()
	await _wait(0.3)

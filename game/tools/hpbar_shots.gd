extends SceneTree
## D215-D218 review renders (needs a window):
##   [SHOTS=<dir>] [MODE=all|combat|cards] [TAG=<suffix>] [RES=1920x1080] godot --path . --resolution 1920x1080 --script res://tools/hpbar_shots.gd
## hpbar_combat.png      a fight: units above and below 50% HP, no numbers
## hpbar_hover.png       the same, one unit hovered: its "hp / max"
## hpbar_colossus.png    the Colossus's bar (same rule, big), clamped under the turn order
## hpbar_colossus_top.png the camera low and close: the bar would sit behind the turn order
## hpbar_cards<TAG>.png  the shop: a cursed card with its cost and an imbued C weapon, unscrolled
## hpbar_gear<TAG>.png   the gear panel: a C weapon with three enchantment lines
var out := ""
var s: BWCombatScreen
var tag := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art").simplify_path()
	tag = OS.get_environment("TAG")
	var res := OS.get_environment("RES")         # e.g. 1920x1080: a real window of that size (the project starts maximized)
	if res != "":
		var wh := res.split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	_go.call_deferred()


func _wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = root.get_final_transform() * p
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await process_frame
	await process_frame


func _go() -> void:
	BWSettings.put("cutscenes", "default")
	var mode := OS.get_environment("MODE")
	if mode in ["", "all", "cards"]:
		await _cards()
	if mode in ["", "all", "combat"]:
		await _combat()
	quit()


func _fight(kind: String, n: int) -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	for u in run.squad:
		BWProgression.level_up(u, n - u.level)
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
	run.fight = n
	var players: Array = run.squad.slice(0, 3)
	run.prepare_for_battle(players)
	var enemies := BWEncounters.build(run, n, kind)
	if s and is_instance_valid(s):
		s.queue_free()
		await process_frame
	s = BWCombatScreen.new()
	s.configure("res://maps/arena.json", players, enemies, [], 5)
	root.add_child(s)
	await _wait(6.0)
	while s._busy:
		await process_frame


func _set_hp(u: BWUnit, f: float) -> void:
	u.hp = maxi(1, int(round(u.max_hp() * f)))
	s._views[u.id].refresh()


func _combat() -> void:
	BWMusic.ensure(root)
	await _fight("blank", 6)
	var ps := s.battle.side("player")
	var es := s.battle.side("enemy")
	_set_hp(ps[0], 0.86)
	_set_hp(ps[1], 0.52)
	_set_hp(ps[2], 0.31)
	_set_hp(es[0], 0.67)
	_set_hp(es[1], 0.44)
	_set_hp(es[2], 0.12)
	await _wait(1.2)
	var c := Vector3.ZERO
	for u in ps + es:
		c += s._views[u.id].global_position
	s.rig.follow(c / 6.0, true)
	s.rig.dist = 15.0
	s.rig.pitch = deg_to_rad(38.0)
	await _move(Vector2(4, 450))
	BWHPBar3D.hover_unit = null
	await _wait(1.0)
	await _shot("hpbar_combat")
	BWHPBar3D.hover_unit = es[1]
	await _wait(0.3)
	await _shot("hpbar_hover")
	BWHPBar3D.hover_unit = null
	# a live hit across 50%: the ghost and the flip pulse, mid-animation
	ps[0].hp = int(ps[0].max_hp() * 0.36)
	s._views[ps[0].id].refresh()
	await _wait(0.12)
	await _shot("hpbar_flip")
	await _fight("colossus", 6)
	var col: BWUnit = s.battle.side("enemy")[0]
	_set_hp(col, 0.58)
	await _wait(0.8)
	BWHPBar3D.hover_unit = col
	s.rig.follow(s._views[col.id].global_position, true)
	s.rig.dist = 30.0
	s.rig.pitch = deg_to_rad(30.0)
	await _wait(1.2)
	await _shot("hpbar_colossus")
	s.rig.dist = 15.0
	s.rig.pitch = deg_to_rad(16.0)
	await _wait(1.2)
	await _shot("hpbar_colossus_top")
	BWHPBar3D.hover_unit = null


func _cards() -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	run.fight = 6
	run.restock_shop()
	var cursed := run.make_item("sword", "B", "bloodpact")
	run.inventory.append(cursed)
	var u: BWUnit = run.squad[0]
	var fl := run.make_item("flamberge", "C", "cleaving")
	fl.imbue = "wind"
	fl.imbue_enchant = "whistling"
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
	pre._open_overlay(pre._shop)
	await _wait(1.2)
	var sh := pre._shop
	sh.set_mode("trade")
	await _wait(0.3)
	sh._hover(cursed, true)
	for t in sh._right.get_children():
		if t is BWItemTile and str(t.item.slot) == "main_hand" and str(t.item.get("imbue_enchant", "")) != "":
			sh._hover(t.item, false)
			break
	await _move(Vector2(4, 4))
	await _wait(0.6)
	var sc := sh._card_a.get_parent().get_parent() as ScrollContainer
	print("cards: card_a h=%d card_b h=%d, room h=%d" % [sh._card_a.size.y, sh._card_b.size.y, sc.size.y])
	await _shot("hpbar_cards" + tag)
	pre._close_overlays()
	pre._open_overlay(pre._equip)
	await _wait(1.5)
	var gp: BWGearPanel = pre._equip
	gp._hover_slot(gp._slots["second"])
	await _wait(1.2)
	var gs := gp.card.get_parent() as ScrollContainer
	print("gear card h=%d, room h=%d" % [gp.card.size.y, gs.size.y])
	await _shot("hpbar_gear" + tag)
	pre.queue_free()
	await _wait(0.3)

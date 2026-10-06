extends SceneTree
## Review renders of the pick system (D90/D91) to design/art/picks_*.png:
##   runstart   the run-start screen, the first unit's perk picker
##   midfight   a player unit crossing affinity rank 2 mid-fight: its tile
##              marked, the picker over the board (its first perk greyed)
##   skill      a weapon-skill pick (improve / learn) after an expertise letter
##   layout5    the card row with five perks (three rows padded in memory for
##              the shot only: the designer's table will have five)
##   [SHOTS=<dir>] godot --path . --script res://tools/picks_shots.gd
## Needs a window (real renders, not headless).

var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/art").simplify_path()
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var p := out.path_join("picks_%s.png" % name)
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _go() -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	# ---- run start
	var run := BWRun.start(ids, 77)
	var ps := BWPicksScreen.new()
	ps.run = run
	root.add_child(ps)
	await _wait(1.0)
	ps.current.select(1)
	await _wait(0.3)
	await _shot("runstart")
	ps.queue_free()
	await _wait(0.3)

	# ---- mid-fight: unit 0 crosses rank 2 in its own element
	var run2 := BWRun.start(ids, 78)
	for u in run2.squad:
		BWPicks.auto_resolve(u)
	var players := run2.squad.slice(0, 3)
	var enemies := run2.enemies_for(1)
	run2.prepare_for_battle(players)
	var cs := BWCombatScreen.new()
	cs.configure("res://maps/arena.json", players, enemies, [], 5)
	cs.picks_live = true
	root.add_child(cs)
	var t := 0.0
	while not cs._player_turn() and t < 30.0:
		await _wait(0.2)
		t += 0.2
	await _wait(0.6)
	var u: BWUnit = cs.battle.current()
	u.affinity[u.element] = 20
	cs._after_events()
	t = 0.0
	while cs.picker == null and t < 5.0:
		await _wait(0.1)
		t += 0.1
	await _wait(1.0)
	await _shot("midfight")
	cs.picker.chosen.emit(str(BWPicks.auto_choice(u, cs.picker.request)))
	await _wait(0.4)
	cs.queue_free()
	await _wait(0.3)

	# ---- a weapon-skill pick (after an expertise letter)
	var v: BWUnit = run.squad[4]
	BWPicks.auto_resolve(v)
	v.expertise[v.weapon_class] = 20
	BWPicks.apply(v, BWPicks.next_request(v), "improve:" + str(v.loadout(v.weapon_class)[0]))
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var pk := BWPicker.new(v, BWPicks.next_request(v), "day 3")
	root.add_child(pk)
	await _wait(0.5)
	await _shot("skill")
	pk.queue_free()

	# ---- five cards (layout check; rows padded in memory, never saved)
	var rows := BWData.table("perks")
	var by_id: Dictionary = BWData._cache[BWData.DATA_DIR + "perks.csv"].by_id
	for i in 3:
		var r := { "id": "fire_layout%d" % i, "element": "fire", "name": "Layout test %d" % (i + 1),
			"effect_text": "Not a real perk: a row added in memory to check five cards fit.",
			"effect_key": "element_damage_pct", "params": "pct=1" }
		rows.append(r)
		by_id[r.id] = r
	var w: BWUnit = run.squad[1]
	w.perks = ["fire_focus"]
	w.affinity["fire"] = 20
	var pk5 := BWPicker.new(w, { "kind": "perk", "element": "fire" })
	root.add_child(pk5)
	await _wait(0.5)
	pk5.select(2)
	await _wait(0.2)
	await _shot("layout5")
	quit(0)

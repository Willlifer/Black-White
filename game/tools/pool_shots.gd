extends SceneTree
## D379-D381 review renders:
##   pool_roster.png       the roster after a Randomize: pool members in the back row
##   pool_roster_hover.png the same, a pool member selected (face + card)
##   featured_shop.png     the shop with its FEATURED scroll and the reason line
##   pool_boot.png     the boot screen, held mid-warm
##   [SHOTS=<dir>] [SEED=n] godot --path . --resolution 1920x1080 --script res://tools/pool_shots.gd
## Needs a window.
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
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", out + "/" + name + ".png")


func _go() -> void:
	BWEsc.synthetic = true
	BWRosterGen.fixed_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	# ---- the roster, then a Randomize
	var r := BWRosterScreen.new()
	root.add_child(r)
	await _wait(2.0)
	await r.randomize_roster()
	await _wait(1.5)
	var pool_seats: Array = []
	for i in r.rows.size():
		if int(r.rows[i].get("pool", 0)) == 1:
			pool_seats.append("%d %s" % [i + 1, r.rows[i].name])
	print("pool seats after Randomize: ", pool_seats)
	await _shot("pool_roster")
	for i in r.rows.size():
		if int(r.rows[i].get("pool", 0)) == 1:
			r._select(i)
			break
	await _wait(1.2)
	await _shot("pool_roster_hover")
	r.queue_free()
	await _wait(0.4)
	# ---- the shop: a squad with a set to complete
	var ids: Array = BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))
	var run := BWRun.start(ids, 71)
	var u: BWUnit = run.squad[3]
	u.affinity["wind"] = 10
	u.equipment["head"] = run.make_item("baseball_cap", "D", "gusting")
	u.refresh_effects()
	for k in 3:
		run.inventory.append(run.random_item("D"))
	print("featured: ", run.featured_scroll().get("reason", ""))
	var pre := BWPrebattleScreen.new()
	pre.run = run
	root.add_child(pre)
	await _wait(1.5)
	for k in 3:
		pre._on_deploy(true, run.squad[k])
	pre._select(run.squad[0])
	await _wait(0.6)
	pre._open_overlay(pre._shop)
	await _wait(1.2)
	await _shot("featured_shop")
	pre.queue_free()
	await _wait(0.4)
	# ---- the boot screen
	var bs := BWBootScreen.new()
	bs.freeze_at = 0.67
	root.add_child(bs)
	await _wait(0.6)
	await _shot("pool_boot")
	quit(0)

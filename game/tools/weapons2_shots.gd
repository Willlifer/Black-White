extends SceneTree
## D180-D182 review renders (design/art/weapons2_*.png):
##   gear     the pre-battle gear panel with both weapon slots filled, the card
##            reading the carried C-tier imbued weapon (+ a crop of the card)
##   carry    characters carrying a second weapon of each stow kind (back:
##            sword, lance, bow; hip: pistol, daggers), from the front and back
##   swap     D195: the swap animation (holster to the carry spot, draw the
##            other) on three units, a frame strip (weapons2_swap_strip.png)
##   SHOTS=<dir> [MODE=gear|carry|swap] godot --path . --script res://tools/weapons2_shots.gd
var out := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://../design/art")
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String, crop: Rect2 = Rect2()) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if crop.size != Vector2.ZERO:
		img = img.get_region(Rect2i(crop))
	img.save_png(out + "/" + name + ".png")
	print("shot ", name)


func _go() -> void:
	var mode := OS.get_environment("MODE")
	if mode == "" or mode == "gear":
		await _gear()
	if mode == "" or mode == "carry":
		await _carry()
	if mode == "" or mode == "swap":
		await _swap()
	quit(0)


func _gear() -> void:
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var u: BWUnit = run.squad[0]
	var fl := run.make_item("flamberge", "C", "cleaving")
	fl.imbue = "fire"
	run.inventory.append(fl)
	run.equip(u, fl, "second")
	for b in ["javelin", "recurve_bow", "pistol"]:
		run.inventory.append(run.make_item(b, "C"))
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
	await _wait(2.0)
	await _shot("weapons2_gear")
	await _shot("weapons2_card", gp.card.get_global_rect().grow(8))
	pre.queue_free()
	await _wait(0.3)


func _carry() -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.84)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	w.add_child(we)
	var pairs := [["axe", "sword"], ["sword", "lance"], ["staff", "shortbow"], ["sword", "pistol"], ["bow", "dagger"], ["lance", "gauntlets"]]
	var imbues := ["fire", "ice", "wind", "thunder", "dark", "light"]
	var chars: Array = []
	for i in pairs.size():
		var row: Dictionary = run.squad[i % run.squad.size()].to_dict()
		var u: BWUnit = run.squad[i % run.squad.size()]
		var m: String = BWData.table("equipment").filter(func(x): return x.slot == "main_hand" and x.weight == pairs[i][0])[0].id
		u.equipment["main_hand"] = run.make_item(m, "E")
		var s := run.make_item(pairs[i][1], "C")
		s.imbue = imbues[i]
		u.equipment["second"] = s
		u.sync_weapon()
		var c := BWCharacter.create(u)
		w.add_child(c)
		chars.append(c)
	var cam := Camera3D.new()
	cam.fov = 30
	w.add_child(cam)
	var n := chars.size()
	var views := { "back": PI * 0.85, "front": PI * 0.15, "side": PI * 0.5 }
	for view in (OS.get_environment("VIEWS") if OS.get_environment("VIEWS") != "" else "back,front").split(","):
		for i in n:
			var c: BWCharacter = chars[i]
			c.position = Vector3((i - (n - 1) / 2.0) * 1.5, 0, 0)
			c.rotation.y = float(views[view])
		cam.transform = Transform3D(Basis(), Vector3(0, 1.5, 11.5)).looking_at(Vector3(0, 1.05, 0), Vector3.UP)
		cam.current = true
		await _wait(1.2)
		await _shot("weapons2_carry_" + view)
	w.queue_free()


## D195: frames of BWCharacter.animate_swap, slowed x4, in a 4 x 2 grid.
func _swap() -> void:
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.84)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	w.add_child(we)
	var pairs := [["sword", "shortbow"], ["lance", "pistol"], ["axe", "dagger"]]
	var chars: Array = []
	var units: Array = []
	for i in pairs.size():
		var u: BWUnit = run.squad[i]
		var m: String = BWData.table("equipment").filter(func(x): return x.slot == "main_hand" and x.weight == pairs[i][0])[0].id
		u.equipment["main_hand"] = run.make_item(m, "E", "")
		u.equipment["second"] = run.make_item(pairs[i][1], "E", "")
		u.sync_weapon()
		var c := BWCharacter.create(u)
		w.add_child(c)
		c.position = Vector3((i - 1) * 1.6, 0, 0)
		c.rotation.y = PI * 0.72
		chars.append(c)
		units.append(u)
	var cam := Camera3D.new()
	cam.fov = 30
	w.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0, 1.6, 8.5)).looking_at(Vector3(0, 1.05, 0), Vector3.UP)
	cam.current = true
	await _wait(1.5)
	await process_frame
	await RenderingServer.frame_post_draw
	var full := root.get_texture().get_image()
	var vs := Vector2(full.get_width(), full.get_height())
	var crop := Rect2i(int(vs.x * 0.22), int(vs.y * 0.03), int(vs.x * 0.62), int(vs.y * 0.74))
	var frames: Array = []
	frames.append(await _grab(crop))
	Engine.time_scale = 0.25
	for i in units.size():
		(units[i] as BWUnit).swap_weapons()
		(chars[i] as BWCharacter).animate_swap()
	for k in 6:
		await create_timer(0.075).timeout   # 0.075 s of game time per frame (0.3 s real)
		frames.append(await _grab(crop))
	Engine.time_scale = 1.0
	await _wait(0.6)
	frames.append(await _grab(crop))
	var fw := crop.size.x / 2
	var fh := crop.size.y / 2
	var sheet := Image.create(fw * 4, fh * 2, false, Image.FORMAT_RGB8)
	for i in frames.size():
		var f: Image = frames[i]
		f.resize(fw, fh, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(f, Rect2i(0, 0, fw, fh), Vector2i((i % 4) * fw, (i / 4) * fh))
	sheet.save_png(out + "/weapons2_swap_strip.png")
	print("shot weapons2_swap_strip")
	w.queue_free()


func _grab(crop: Rect2i) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img.get_region(crop)
